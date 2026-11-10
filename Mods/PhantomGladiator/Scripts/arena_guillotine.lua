-- NPC 受抓由精确 C4 命中启动，只有本次收回、正常结束和被抓动画收尾都读回才结算。
local U=require('ue_observe')
local Stats=require('character_stats')
local Retry=require('lookup_retry')
local Guillotine={}

local MBOSS='/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_MBoss.BP_Monster_MBoss_C'
local ROOT='/PBZCombatAsset/ActorData/Mobs/012_MBoss/'
local C4=ROOT..'Abilities/GA_MBoss_Skill_02_C4.GA_MBoss_Skill_02_C4_C:'
local HIT=C4..'EventReceived_B050170643A0D6231C0901B07314DB59'
local ENDED=C4..'K2_OnEndAbility'
local MONTAGE=ROOT..'Montages/Skill/MBoss_Skill_02_D1_Montage.MBoss_Skill_02_D1_Montage'
local KILL='/Game/PBZContent/Blueprint/Ability/GameplayEffects/GE_Kill.GE_Kill_C'
-- C4 Main: the exact sweep begins at 3.139814 and lasts 0.323442 s. The IK unlocks at
-- 4.733333; the following PutDown action at 4.933327 is the visible catch and put-down.
local HIT_MIN,HIT_MAX,PUT_DOWN=2.95,3.70,4.933327
local MAX_STEP,MAX_HOLD=0.5,12
local BLADE=ROOT..'BulletData/BulletData_MBoss_Kill.BulletData_MBoss_Kill'
local ABILITY_LIB='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
local TARGET_CHANGED='GameplayEvent.AI.TargetChanged'
local PROTECTED={'CharacterState.Immortal','CharacterState.Stand.Invulnerable',
    'CharacterState.Unselectable','CharacterState.Dead','CharacterState.Hitreact.State.Executing',
    'Driver.Driving'}

local function call(object,method,...)
    if not U.valid(object) then return false,nil end
    local ok,value=pcall(function(target,fn,...)return target[fn](target,...)end,object,method,...)
    return ok,U.unwrap(value)
end

local function fullName(object)
    local ok,name=call(object,'GetFullName')
    return ok and type(name)=='string' and name or nil
end

local function finite(value)
    return type(value)=='number' and value==value and value>-math.huge and value<math.huge
end

local function boolParam(value)
    local kind=U.kind(value)
    if kind=='RemoteUnrealParam' or kind=='LocalUnrealParam' then
        local ok,read=pcall(function()return value:get()end)
        if ok and type(read)=='boolean' then return read end
    elseif type(value)=='boolean' then
        return value
    end
end

local function participant(member)
    return (member.team=='blue' or member.team=='red') and not member.stand and not member.reserve and not member.aid
end

function Guillotine.new(options)
    local self={}
    local stats=options.attributes or Stats.new()
    local clock=options.clock or os.clock
    local now=options.now or clock
    local find=options.staticFind or StaticFindObject
    local load=options.loadAsset or LoadAsset
    local register=options.registerHook or RegisterHook
    local defer=options.defer or function(callback)return ExecuteInGameThreadWithDelay(1,callback)end
    local loop=options.loop or LoopInGameThreadWithDelay
    local cancel=options.cancel or CancelDelayedAction
    local fname=options.fname or FName
    local inGameThread=options.inGameThread or IsInGameThread
    local alive=true
    local hooked={}
    local session,roster,aims=nil,{},{}
    local capture,syncAim,restorePending
    local lines=0
    local function say(message)
        if lines>=80 then return end
        lines=lines+1
        options.log('[Guillotine] '..message)
    end
    local retry=Retry.new({clock=clock,log=say})
    local function read(actor,field)
        local value=stats:read(actor,field)
        return value and value.current
    end

    local function eventLog(message)
        options.log('[Guillotine] '..message)
    end

    local function readPosition(ability,actor)
        if U.field(ability,'bIsActive')~=true then return nil end
        local ok,avatar=call(ability,'GetAvatarActorFromActorInfo')
        if not ok or U.key(avatar)~=U.key(actor) then return nil end
        local montage=retry:find(MONTAGE,find)
        if not U.valid(montage) then return nil end
        local _,anim=call(U.field(actor,'Mesh'),'GetAnimInstance')
        local _,playing=call(anim,'Montage_IsPlaying',montage)
        if playing~=true then return nil end
        local _,position=call(anim,'Montage_GetPosition',montage)
        return finite(position) and position or nil
    end

    local function pair(record)
        local attacker,victim=roster[record.source],roster[record.target]
        if not attacker or attacker.class_path~=MBOSS or not victim or attacker.team==victim.team
            or attacker.team~=record.sourceTeam or victim.team~=record.targetTeam then return nil end
        local source,target=attacker.actor,victim.actor
        if not options.live(source) or not options.live(target)
            or U.key(source)~=record.source or U.key(target)~=record.target
            or fullName(source)~=record.sourceName or fullName(target)~=record.targetName then return nil end
        local sourceHP,targetHP=read(source,'Health'),read(target,'Health')
        if not finite(sourceHP) or sourceHP<=0 or not finite(targetHP) or targetHP<=0 then return nil end
        if options.isImmortal(victim.team) or victim.untargetable then return nil end
        return source,target
    end

    local function targetASC(actor)
        if not options.live(actor) or not U.npcPath(actor) then return nil end
        local asc=U.field(actor,'AbilitySystemComponent')
        for _,name in ipairs(PROTECTED)do
            local got,count=call(asc,'GetGameplayTagCount',{TagName=fname(name)})
            if not got or count~=0 then return nil end
        end
        return asc
    end

    local function disarm(record)
        capture=nil
        if record.timer and type(cancel)=='function' then pcall(cancel,record.timer) end
        record.timer=nil
    end

    local function release(record,reason)
        disarm(record)
        if not record.holding then return true end
        local called,restored,detail=pcall(options.stopGrab,reason)
        eventLog('抓取释放 '..record.targetName..' 原因='..reason..' 恢复='..tostring(called and restored)
            ..' '..tostring(called and detail or restored or ''))
        restorePending=not (called and restored==true)
        return not restorePending
    end

    local function sameWorld(record)
        local status=options.session()
        return status.game_ready==true and status.game_session==record.session and session==record.session
    end

    local function finish(record)
        local restored=release(record,'收回、技能正常结束、受抓动作均读回')
        if not restored then eventLog('铡刀收尾跳过结算：控制恢复未确认');return end
        local effect=retry:find(KILL,function(path)
            local value=find(path)
            if U.valid(value) then return value end
            if type(load)=='function' then
                value=load(path)
                if U.valid(value) then return value end
            end
            return find(path)
        end)
        local _,target=pair(record)
        local asc=target and targetASC(target)
        if not sameWorld(record) or not U.valid(effect) or not asc then
            eventLog('铡刀收尾跳过结算：会话、效果或目标未读回');return
        end
        local before=read(target,'Health')
        local floor=read(target,'Health_Min')
        local called=call(asc,'BP_ApplyGameplayEffectToSelf',effect,0.0,{})
        local after=options.live(target) and read(target,'Health') or nil
        local _,dead=call(asc,'GetGameplayTagCount',{TagName=fname('CharacterState.Dead')})
        eventLog('铡刀完整收尾 '..record.targetName..' GE_Kill调用='..tostring(called)
            ..' HP='..tostring(before)..' -> '..tostring(after)..' 底线='..tostring(floor)
            ..' 死亡标签='..tostring(dead)..' 判死读回='..tostring((finite(after) and after<=0) or (finite(dead) and dead>0)))
    end

    local function sample(record)
        if capture~=record then return end
        if record.abort then release(record,record.abort);return end
        if not sameWorld(record) then release(record,'对战会话变化');return end
        local source,target=pair(record)
        if not source then release(record,'参战双方状态变化');return end
        local elapsed=now()
        if not finite(elapsed) or elapsed<record.started or elapsed-record.started>=MAX_HOLD then
            release(record,'收尾读回等待超时');return
        end
        local held,visualFinished=options.grabHeld(target)
        if held~=true then release(record,'目标控制已失效');return end
        if not record.normalEnd then
            local position=readPosition(record.ability,source)
            if position then
                if position<record.position-0.02 or position-record.position>MAX_STEP then
                    release(record,'出招动画跳转');return
                end
                if not record.returned and record.position<PUT_DOWN and position>=PUT_DOWN then
                    record.returned=true
                    eventLog(string.format('同一次铡刀收回读回 %.3f -> %.3f %s',record.position,position,record.sourceName))
                end
                record.position=math.max(record.position,position)
            elseif not record.returned then
                release(record,'收回前原生动画停止');return
            end
        end
        if record.returned and record.normalEnd and visualFinished==true then finish(record) end
    end

    local function startHold(record)
        if capture~=record or record.holding then return end
        if record.abort or not sameWorld(record) then release(record,record.abort or '对战会话变化');return end
        local source,target=pair(record)
        local position=source and readPosition(record.ability,source)
        if not position or position<record.position-0.02 or position>=PUT_DOWN or not targetASC(target) then
            release(record,'命中后的目标或原生动作未确认');return
        end
        local started=now()
        if not finite(started) or type(loop)~='function' or type(cancel)~='function' then
            release(record,'控制时钟或更新任务未就绪');return
        end
        if not syncAim(roster[record.source],record.source,target) then
            release(record,'链刃实际命中目标未确认');return
        end
        record.started,record.position=started,position
        -- Set ownership before invoking the controller so a thrown partial takeover is also restored.
        record.holding=true
        local ok,held,detail=pcall(options.playGrab,target,function()
            return alive and capture==record and not record.abort and session==record.session
        end)
        if capture~=record then return end
        eventLog('铡刀控制 '..record.targetName..' HP='..tostring(read(target,'Health'))..' 读回='
            ..tostring(ok and held)..' '..tostring(ok and detail or held or ''))
        if not ok or held~=true then release(record,'控制或受抓动画未确认');return end
        local registered,handle=pcall(loop,25,function()
            if not alive or capture~=record then return end
            local sampled,why=pcall(sample,record)
            if not sampled and capture==record then release(record,'控制读回异常 '..tostring(why)) end
        end)
        if not registered or not handle then release(record,'控制更新任务未登记');return end
        if capture==record then record.timer=handle else pcall(cancel,handle) end
    end

    local function hit(context,remotePayload)
        if not alive or not session or capture or restorePending or not hooked[ENDED]
            or (type(inGameThread)=='function' and not inGameThread()) then return end
        local bullet=U.struct(remotePayload,'OptionalObject')
        local data=fullName(U.field(bullet,'BulletData'))
        if not data or data:match('^%S+ (/.+)$')~=BLADE then return end
        local source=U.field(bullet,'BulletOwnerAvatar')
        local ability=U.unwrap(context)
        local target=U.struct(remotePayload,'Target')
        local sourceKey,targetKey,cast=U.key(source),U.key(target),U.key(ability)
        if not sourceKey or not targetKey or not cast then return end
        local attacker,victim=roster[sourceKey],roster[targetKey]
        if not attacker or attacker.class_path~=MBOSS or not victim or attacker.team==victim.team
            or not options.live(source) or not options.live(target) then return end
        local position=readPosition(ability,source)
        local sourceName,targetName=fullName(source),fullName(target)
        if not position or position<HIT_MIN or position>HIT_MAX or not sourceName or not targetName then
            say('铡刀命中，但当前出招位置未确认 '..tostring(position));return
        end
        local record={ability=ability,cast=cast,source=sourceKey,sourceName=sourceName,sourceTeam=attacker.team,
            target=targetKey,targetName=targetName,targetTeam=victim.team,position=position,session=session}
        capture=record
        eventLog(string.format('铡刀原生命中读回 t=%.3f %s -> %s',position,sourceName,targetName))
        pcall(defer,function()
            if not alive or capture~=record then return end
            local ok,why=pcall(startHold,record)
            if not ok and capture==record then release(record,'控制初始化异常 '..tostring(why)) end
        end)
    end

    local function onEnd(context,cancelled)
        if not alive or not capture or (type(inGameThread)=='function' and not inGameThread()) then return end
        local record=capture
        if U.key(U.unwrap(context))~=record.cast then return end
        local value=boolParam(cancelled)
        if value==false and record.returned and record.holding then
            record.normalEnd=true
            eventLog('铡刀正常结束读回 '..record.sourceName)
        else
            record.abort=value==true and '荒行子技能取消' or '结束前未确认收回或取消状态'
        end
    end

    local function installHook(path,callback)
        if hooked[path] or not retry:ready(path) then return end
        local found,fn=pcall(find,path)
        if not found or not U.valid(fn) then retry:result(path,false);return end
        local ok,pre,post=pcall(register,path,callback)
        hooked[path]=ok and type(pre)=='number' and type(post)=='number'
        retry:result(path,hooked[path],hooked[path] and ('挂钩ID '..pre..'/'..post) or '挂钩未确认')
    end

    local function install()
        installHook(ENDED,onEnd)
        installHook(HIT,hit)
    end

    syncAim=function(member,key,hitTarget)
        local actor=member.actor
        local target=hitTarget or options.opponentOf(key)
        local targetKey=U.key(target)
        local opponent=roster[targetKey]
        if not opponent or opponent.team==member.team or opponent.untargetable or not options.live(target) then return end
        local component=U.field(actor,'BP_Guillotine')
        local meshKey=U.key(U.field(target,'Mesh'))
        if not U.valid(component) or not meshKey then return end
        if U.key(U.field(component,'TargetActor'))==targetKey and U.key(U.field(component,'TargetMesh'))==meshKey then return true end
        local at=clock()
        local last=aims[key]
        if not hitTarget and last and last.target==targetKey and at-last.at<1 then return end
        aims[key]={target=targetKey,at=at}
        local lib=retry:find(ABILITY_LIB,find)
        if not U.valid(lib) then return end
        local tag={TagName=fname(TARGET_CHANGED)}
        local sent=call(lib,'SendGameplayEventToActor',actor,tag,{EventTag=tag,Instigator=actor,Target=target})
        local after=U.key(U.field(component,'TargetActor'))
        local afterMesh=U.key(U.field(component,'TargetMesh'))
        say('同步链刃目标 '..(fullName(target) or targetKey)..' 调用='..tostring(sent)..' TargetActor='..tostring(after)
            ..' TargetMesh='..tostring(afterMesh)..' 一致='..tostring(after==targetKey and afterMesh==meshKey))
        return after==targetKey and afterMesh==meshKey
    end

    function self:stop()
        local restored=true
        if capture then
            restored=release(capture,'交战结束或召唤会话变化')
        elseif restorePending then
            local called,verified=pcall(options.stopGrab,'重试恢复血滴子控制')
            restored=called and verified==true
            restorePending=not restored
        end
        session,roster,aims=nil,{},{}
        return restored
    end

    function self:prepare(members)
        self:stop()
        for _,member in ipairs(members)do
            if participant(member) and member.class_path==MBOSS then install();return end
        end
    end

    function self:tick(members,status)
        if not alive then return end
        if not status.battle_active or status.blue_count<=0 or status.red_count<=0 then
            if session then self:stop() end
            return
        end
        local hasCaster=false
        for _,member in ipairs(members)do
            if participant(member) and member.class_path==MBOSS then hasCaster=true;break end
        end
        if not hasCaster then
            if session then self:stop() end
            return
        end
        local current=options.session()
        if not current.game_ready or not current.game_session then self:stop();return end
        if session~=current.game_session then self:stop();session=current.game_session end
        roster={}
        for _,member in ipairs(members)do
            if participant(member) then
                local key=U.key(member.actor)
                if key then roster[key]=member end
            end
        end
        install()
        if capture and not capture.holding then
            local record=capture
            local ok,why=pcall(startHold,record)
            if not ok and capture==record then release(record,'控制初始化异常 '..tostring(why)) end
        end
        for key,member in pairs(roster)do
            if member.class_path==MBOSS and options.live(member.actor) and (read(member.actor,'Health') or 0)>0 then
                if not capture or capture.source~=key then syncAim(member,key) end
            end
        end
        for key in pairs(aims)do if not roster[key] then aims[key]=nil end end
    end

    -- UE4SS removes the script hook with the mod. Any retained callback becomes inert first.
    function self:silence()
        alive=false
        if type(inGameThread)=='function' and inGameThread() then
            self:stop()
        elseif capture then
            disarm(capture)
        end
    end
    return self
end

return Guillotine
