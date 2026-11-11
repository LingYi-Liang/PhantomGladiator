-- The original C4 commits Health=0 after a 0.9 s catch, then plays the victim's finishing animation.
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
local BLADE=ROOT..'BulletData/BulletData_MBoss_Kill.BulletData_MBoss_Kill'
local ABILITY_LIB='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
local TARGET_CHANGED='GameplayEvent.AI.TargetChanged'
local CATCH_TIME,FINISH_TIME,MAX_HOLD=0.9,3.788884,12
local PROTECTED={'CharacterState.Immortal','CharacterState.Stand.Invulnerable',
    'CharacterState.Unselectable','CharacterState.Dead','CharacterState.Hitreact.State.Executing','Driver.Driving'}

local function call(object,method,...)
    if not U.valid(object) then return false end
    local ok,value=pcall(function(target,key,...)return target[key](target,...)end,object,method,...)
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
        local ok,result=pcall(function()return value:get()end)
        if ok and type(result)=='boolean' then return result end
    elseif type(value)=='boolean' then return value end
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
    local register=options.registerHook or RegisterHook
    local defer=options.defer or function(fn)return ExecuteInGameThreadWithDelay(1,fn)end
    local loop=options.loop or LoopInGameThreadWithDelay
    local cancel=options.cancel or CancelDelayedAction
    local fname=options.fname or FName
    local inGameThread=options.inGameThread or IsInGameThread
    local alive=true
    local hooked,captures,targets,pending={},{},{},{}
    local session,roster,aims=nil,{},{}
    local syncAim
    local function say(text)options.log('[Guillotine] '..text)end
    local retry=Retry.new({clock=clock,log=say})
    local function read(actor,field)
        local value=stats:read(actor,field)
        return value and value.current
    end
    local function sameWorld(record)
        local status=options.session()
        return status.game_ready==true and status.game_session==record.session and session==record.session
    end
    local function victim(record)
        local actor=record.targetActor
        if not options.live(actor) or U.key(actor)~=record.target or fullName(actor)~=record.targetName then return nil end
        return actor
    end
    local function source(record)
        local member=roster[record.source]
        if not member or member.team~=record.sourceTeam or not options.live(member.actor)
            or fullName(member.actor)~=record.sourceName or (read(member.actor,'Health') or 0)<=0 then return nil end
        return member.actor
    end
    local function sourceActive(ability,actor)
        if U.field(ability,'bIsActive')~=true then return false end
        local got,avatar=call(ability,'GetAvatarActorFromActorInfo')
        return got and U.key(avatar)==U.key(actor)
    end
    local function readPosition(ability,actor)
        if not sourceActive(ability,actor) then return nil end
        local montage=retry:find(MONTAGE,find)
        if not U.valid(montage) then return nil end
        local _,anim=call(U.field(actor,'Mesh'),'GetAnimInstance')
        local _,playing=call(anim,'Montage_IsPlaying',montage)
        if playing~=true then return nil end
        local _,position=call(anim,'Montage_GetPosition',montage)
        return finite(position) and position or nil
    end
    local function canCatch(actor,member)
        if not options.live(actor) or not U.npcPath(actor) or member.untargetable or options.isImmortal(member.team) then return false end
        local asc=U.field(actor,'AbilitySystemComponent')
        for _,text in ipairs(PROTECTED)do
            local got,count=call(asc,'GetGameplayTagCount',{TagName=fname(text)})
            if not got or count~=0 then return false end
        end
        return (read(actor,'Health') or 0)>0
    end
    local function restoreDelay(record)
        if record.delay==nil or not options.live(record.targetActor) then return true end
        local actor=record.targetActor
        local actual=U.field(actor,'Death Delay')
        if actual~=record.wantedDelay then return actual~=nil end
        local ok=pcall(function()actor['Death Delay']=record.delay end)
        return ok and U.field(actor,'Death Delay')==record.delay
    end
    local function release(record,reason)
        if captures[record.source]==record then captures[record.source]=nil end
        if targets[record.target]==record then targets[record.target]=nil end
        if record.timer then pcall(cancel,record.timer);record.timer=nil end
        local restored,detail=restoreDelay(record),'未接管动画'
        if record.holding then
            local called,value,why=pcall(options.stopGrab,reason,record.targetActor)
            restored=called and value==true and restored
            detail=called and why or value
        end
        pending[record.target]=not restored and record or nil
        say('抓取释放 '..record.targetName..' 原因='..reason..' 恢复读回='..tostring(restored)..' '..tostring(detail or ''))
        return restored
    end
    local function preserveFinish(record,target)
        if record.delay~=nil then return end
        local original=U.field(target,'Death Delay')
        if not finite(original) then return end
        record.delay=original
        local dilation=U.field(target,'CustomTimeDilation')
        if not finite(dilation) or dilation<=0 then dilation=1 end
        record.wantedDelay=math.max(original,math.min(MAX_HOLD,FINISH_TIME/dilation+0.35))
        local wrote=pcall(function()target['Death Delay']=record.wantedDelay end)
        say('受抓死亡表现延迟 '..record.targetName..' 原值='..original..' 写入='..tostring(wrote)
            ..' 读回='..tostring(U.field(target,'Death Delay')))
    end
    local function beginFinish(record,target)
        if not record.holding or not options.finishGrab or record.visualStarted then return end
        local ok,started,detail=pcall(options.finishGrab,target)
        local confirmed=ok and started==true
        if record.visualStarted~=confirmed then
            say('受抓后半段 '..record.targetName..' 启动读回='..tostring(confirmed)..' '..tostring(detail or started or ''))
        end
        record.visualStarted=confirmed
    end
    local function execute(record,target)
        preserveFinish(record,target)
        local before=read(target,'Health')
        local floor=read(target,'Health_Min')
        record.writeAttempts=(record.writeAttempts or 0)+1
        -- Use the same AttributeUtils operation as the player's GuillotineSeckill branch.
        local ok,wrote,why=pcall(stats.writeBase,stats,target,'Health',0)
        local after=options.live(target) and read(target,'Health')
        local called=ok and wrote==true
        say('原版铡刀致死点 '..record.targetName..' Health Override=0 调用='..tostring(called)
            ..' HP='..tostring(before)..' -> '..tostring(after)..' 底线='..tostring(floor)
            ..' '..tostring(ok and why or wrote or ''))
        if not called and not (finite(after) and after<=0) then
            if record.writeAttempts>=2 then release(record,'生命归零调用未确认') end
            return
        end
        record.executed=true
        record.executedAt=now()
        beginFinish(record,target)
    end
    local function sample(record)
        if captures[record.source]~=record then return end
        if not sameWorld(record) then release(record,'对战会话变化');return end
        local target=victim(record)
        local time=now()
        if not target or not finite(time) or time<record.started or time-record.started>=MAX_HOLD then
            release(record,'目标离场或抓取超时');return
        end
        local held,finished=false,false
        if record.holding then held,finished=options.grabHeld(target) end
        if not record.executed then
            local attacker=source(record)
            local member=roster[record.target]
            if record.abort or not attacker or not member or member.team~=record.targetTeam
                or options.isImmortal(member.team) or not sourceActive(record.ability,attacker) then
                release(record,record.abort or '致死点前施技者或目标状态变化');return
            end
            local hp=read(target,'Health')
            if not finite(hp) or hp<=0 then release(record,'致死点前目标已倒下');return end
            local position=readPosition(record.ability,attacker)
            if position and record.position and position<record.position-0.02 then release(record,'出招动画回退');return end
            record.position=position or record.position
            if record.holding and held~=true then
                -- Presentation failure does not discard an already confirmed native catch.
                say('受抓控制丢失，保留本次原生命中 '..record.targetName)
                local restored=options.stopGrab('受抓控制变化',target)
                record.holding=restored~=true
            end
            local elapsed=time-record.started
            local _,dash=call(U.field(target,'AbilitySystemComponent'),'GetGameplayTagCount',{TagName=fname('Ability.Action.Hun.Dash')})
            if elapsed>=0.1 and finite(dash) and dash>0 and not record.dashCommit then record.dashCommit=time+0.05 end
            if elapsed>=CATCH_TIME or (record.dashCommit and time>=record.dashCommit) then execute(record,target) end
            return
        end
        -- The native victim finish lasts past the caster montage. Death and its final animation are independent.
        if time-record.executedAt<=0.35 then beginFinish(record,target) end
        if finished==true or not record.holding then
            release(record,'原版致死后受抓收尾完成')
        end
    end
    local function startHold(record)
        if captures[record.source]~=record or record.started then return end
        if record.abort or not sameWorld(record) then release(record,record.abort or '对战会话变化');return end
        local attacker,target=source(record),victim(record)
        if not attacker or not target or not sourceActive(record.ability,attacker) then release(record,'原生命中身份未读回');return end
        local time=now()
        if not finite(time) or type(loop)~='function' or type(cancel)~='function' then release(record,'游戏线程计时未就绪');return end
        record.started=time
        syncAim(roster[record.source],record.source,target)
        record.holding=true
        local ok,held,detail=pcall(options.playGrab,target,function()
            return alive and captures[record.source]==record and sameWorld(record)
        end)
        if captures[record.source]~=record then return end
        if not ok or held~=true then
            local restored,result=pcall(options.stopGrab,'受抓接管未完成',target)
            record.holding=not (restored and result==true)
        end
        say('铡刀控制 '..record.targetName..' 读回='..tostring(ok and held==true)..' '..tostring(detail or held or ''))
        local registered,handle=pcall(loop,25,function()
            if not alive or captures[record.source]~=record then return end
            local sampled,why=pcall(sample,record)
            if not sampled and captures[record.source]==record then release(record,'抓取读回异常 '..tostring(why)) end
        end)
        if not registered or handle==nil or handle==false then release(record,'控制更新任务未登记');return end
        if captures[record.source]==record then record.timer=handle else pcall(cancel,handle) end
    end
    local function hit(context,payload)
        if not alive or not session or not hooked[ENDED] or (type(inGameThread)=='function' and not inGameThread()) then return end
        local bullet=U.struct(payload,'OptionalObject')
        local data=fullName(U.field(bullet,'BulletData'))
        if not data or data:match('^%S+ (/.+)$')~=BLADE then return end
        local attacker,target=U.field(bullet,'BulletOwnerAvatar'),U.struct(payload,'Target')
        local ability=U.unwrap(context)
        local sourceKey,targetKey=U.key(attacker),U.key(target)
        local a,b=roster[sourceKey],roster[targetKey]
        if not a or a.class_path~=MBOSS or not b or a.team==b.team or captures[sourceKey] or targets[targetKey]
            or pending[targetKey] or not sourceActive(ability,attacker) or not canCatch(target,b) then return end
        local sourceName,targetName=fullName(attacker),fullName(target)
        if not sourceName or not targetName then return end
        local record={ability=ability,cast=U.key(ability),source=sourceKey,sourceName=sourceName,sourceTeam=a.team,
            target=targetKey,targetActor=target,targetName=targetName,targetTeam=b.team,session=session,
            position=readPosition(ability,attacker)}
        captures[sourceKey]=record
        targets[targetKey]=record
        say('铡刀原生命中读回 t='..tostring(record.position)..' '..sourceName..' -> '..targetName)
        local queued=pcall(defer,function()
            if alive and captures[sourceKey]==record then
                local ok,why=pcall(startHold,record)
                if not ok then release(record,'控制初始化异常 '..tostring(why)) end
            end
        end)
        if not queued then release(record,'命中后游戏线程任务未登记') end
    end
    local function onEnd(context,cancelled)
        if not alive or (type(inGameThread)=='function' and not inGameThread()) then return end
        local ability=U.unwrap(context)
        local _,actor=call(ability,'GetAvatarActorFromActorInfo')
        local record=captures[U.key(actor)]
        if not record or U.key(ability)~=record.cast then return end
        if not record.executed then
            record.abort=boolParam(cancelled)==true and '致死点前技能取消' or '致死点前技能结束'
        else
            say('施技者结束，继续受抓后半段 '..record.targetName)
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
        local time=clock()
        local last=aims[key]
        if not hitTarget and last and last.target==targetKey and time-last.at<1 then return end
        aims[key]={target=targetKey,at=time}
        local lib=retry:find(ABILITY_LIB,find)
        if not U.valid(lib) then return end
        local tag={TagName=fname(TARGET_CHANGED)}
        local sent=call(lib,'SendGameplayEventToActor',actor,tag,{EventTag=tag,Instigator=actor,Target=target})
        local after=U.key(U.field(component,'TargetActor'))
        local afterMesh=U.key(U.field(component,'TargetMesh'))
        say('同步链刃目标 '..(fullName(target) or targetKey)..' 调用='..tostring(sent)
            ..' TargetActor='..tostring(after)..' TargetMesh='..tostring(afterMesh)
            ..' 一致='..tostring(after==targetKey and afterMesh==meshKey))
        return after==targetKey and afterMesh==meshKey
    end
    function self:stop()
        local restored=true
        for _,record in pairs(captures)do if not release(record,'停止或换图') then restored=false end end
        for key,record in pairs(pending)do if release(record,'重试抓取恢复') then pending[key]=nil else restored=false end end
        session,roster,aims=nil,{},{}
        return restored
    end
    function self:prepare(members)
        self:stop()
        for _,member in ipairs(members)do if participant(member) and member.class_path==MBOSS then install();return end end
    end
    function self:tick(members,status)
        if not alive then return end
        local fighting=status.battle_active and status.blue_count>0 and status.red_count>0
        local hasCaster=false
        for _,member in ipairs(members)do
            if participant(member) and member.class_path==MBOSS then hasCaster=true;break end
        end
        if not next(captures) and not next(pending) and (not fighting or not hasCaster) then
            session,roster,aims=nil,{},{}
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
        for _,record in pairs(captures)do
            if not fighting and not record.executed then release(record,'致死点前交战结束')
            elseif not record.started then startHold(record) end
        end
        for _,record in pairs(pending)do release(record,'重试抓取恢复') end
        if not fighting or not hasCaster then return end
        install()
        for key,member in pairs(roster)do
            if member.class_path==MBOSS and options.live(member.actor) and (read(member.actor,'Health') or 0)>0 and not captures[key] then
                syncAim(member,key)
            end
        end
        for key in pairs(aims)do if not roster[key] then aims[key]=nil end end
    end
    function self:silence()
        alive=false
        if type(inGameThread)=='function' and inGameThread() then self:stop()
        else
            for _,record in pairs(captures)do if record.timer then pcall(cancel,record.timer);record.timer=nil end end
        end
    end
    return self
end
return Guillotine
