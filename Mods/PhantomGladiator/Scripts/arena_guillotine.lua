-- 荒行子 C4 的预警取玩家，链刃组件用 AI 目标缓存，原生秒杀演出只接收主角。
local U=require('ue_observe')
local Stats=require('character_stats')
local Retry=require('lookup_retry')
local Guillotine={}

local MBOSS='/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_MBoss.BP_Monster_MBoss_C'
local ROOT='/PBZCombatAsset/ActorData/Mobs/012_MBoss/'
local HIT=ROOT..'Abilities/GA_MBoss_Skill_02_C4.GA_MBoss_Skill_02_C4_C:EventReceived_B050170643A0D6231C0901B07314DB59'
local BLADE=ROOT..'BulletData/BulletData_MBoss_Kill.BulletData_MBoss_Kill'
local KILL='/Game/PBZContent/Blueprint/Ability/GameplayEffects/GE_Kill.GE_Kill_C'
local ABILITY_LIB='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
local TARGET_CHANGED='GameplayEvent.AI.TargetChanged'
local PROTECTED={'CharacterState.Immortal','CharacterState.Stand.Invulnerable','CharacterState.CanNotBeExecuted',
    'CharacterState.Unselectable','CharacterState.Dead','CharacterState.Hitreact.State.Executing',
    'CharacterType.AI.Boss','Driver.Driving'}
local ORDINARY={Mob=true,Standard=true,Elite=true}

local function call(object,method,...)
    if not U.valid(object) then return false,nil end
    local ok,value=pcall(function(target,fn,...)return target[fn](target,...)end,object,method,...)
    return ok,U.unwrap(value)
end

local function fullName(object)
    local ok,name=call(object,'GetFullName')
    return ok and type(name)=='string' and name or nil
end

local function participant(member)
    return (member.team=='blue' or member.team=='red') and not member.stand and not member.reserve and not member.aid
end

function Guillotine.new(options)
    local self={}
    local stats=options.attributes or Stats.new()
    local clock=options.clock or os.clock
    local find=options.staticFind or StaticFindObject
    local load=options.loadAsset or LoadAsset
    local register=options.registerHook or RegisterHook
    local fname=options.fname or FName
    local inGameThread=options.inGameThread or IsInGameThread
    local alive,hooked=true,false
    local session,roster,pending,aims=nil,{},{},{}
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

    local function hit(context,remotePayload)
        if not alive or not session or (type(inGameThread)=='function' and not inGameThread()) then return end
        local bullet=U.struct(remotePayload,'OptionalObject')
        local data=fullName(U.field(bullet,'BulletData'))
        if not data or data:match('^%S+ (/.+)$')~=BLADE then return end
        local source=U.field(bullet,'BulletOwnerAvatar')
        local got,avatar=call(U.unwrap(context),'GetAvatarActorFromActorInfo')
        local target=U.struct(remotePayload,'Target')
        local sourceKey,targetKey=U.key(source),U.key(target)
        if not sourceKey or not got or U.key(avatar)~=sourceKey then return end
        local attacker,victim=roster[sourceKey],roster[targetKey]
        if not attacker or attacker.class_path~=MBOSS or not victim or attacker.team==victim.team then return end
        if not pending[targetKey] then
            local sourceName,targetName=fullName(source),fullName(target)
            if not sourceName or not targetName then return end
            pending[targetKey]={source=sourceKey,sourceName=sourceName,targetName=targetName,
                sourceTeam=attacker.team,targetTeam=victim.team}
            say('铡刀原生命中已读回 '..sourceName..' -> '..targetName)
        end
    end

    local function install()
        if hooked or not retry:ready(HIT) then return end
        local found,fn=pcall(find,HIT)
        if not found or not U.valid(fn) then retry:result(HIT,false);return end
        local ok,pre,post=pcall(register,HIT,hit)
        hooked=ok and type(pre)=='number' and type(post)=='number'
        retry:result(HIT,hooked,hooked and ('挂钩ID '..pre..'/'..post) or '挂钩未确认')
    end

    local function syncAim(member,key)
        local actor=member.actor
        local target=options.opponentOf(key)
        local targetKey=U.key(target)
        local opponent=roster[targetKey]
        if not opponent or opponent.team==member.team or opponent.untargetable or not options.live(target) then return end
        local component=U.field(actor,'BP_Guillotine')
        local meshKey=U.key(U.field(target,'Mesh'))
        if not U.valid(component) or not meshKey then return end
        if U.key(U.field(component,'TargetActor'))==targetKey and U.key(U.field(component,'TargetMesh'))==meshKey then return end
        local at=clock()
        local last=aims[key]
        if last and last.target==targetKey and at-last.at<1 then return end
        aims[key]={target=targetKey,at=at}
        local lib=retry:find(ABILITY_LIB,find)
        if not U.valid(lib) then return end
        local tag={TagName=fname(TARGET_CHANGED)}
        local sent=call(lib,'SendGameplayEventToActor',actor,tag,{EventTag=tag,Instigator=actor,Target=target})
        local after=U.key(U.field(component,'TargetActor'))
        local afterMesh=U.key(U.field(component,'TargetMesh'))
        say('同步链刃目标 '..(fullName(target) or targetKey)..' 调用='..tostring(sent)..' TargetActor='..tostring(after)
            ..' TargetMesh='..tostring(afterMesh)..' 一致='..tostring(after==targetKey and afterMesh==meshKey))
    end

    local function finish(member)
        local actor=member.actor
        if options.isImmortal(member.team) or member.untargetable then return '队伍或单位受保护' end
        if not options.live(actor) or not U.npcPath(actor) then return '目标非有效 NPC' end
        local tag=U.struct(U.field(U.field(actor,'Actor Config'),'Difficulty Tag'),'TagName')
        local ok,rank=pcall(function()return tag:ToString()end)
        if not ok or type(rank)~='string' or not ORDINARY[rank:gsub('^CharacterType%.Difficulty%.','')] then
            return '目标不是普通等级 NPC'
        end
        local hp,floor=read(actor,'Health'),stats:read(actor,'Health_Min')
        if not hp or hp<=0 or not floor or floor.current>0 or floor.base>0 then return '死亡状态或锁血保护' end
        local asc=U.field(actor,'AbilitySystemComponent')
        for _,name in ipairs(PROTECTED)do
            local readTag,count=call(asc,'GetGameplayTagCount',{TagName=fname(name)})
            if not readTag or count~=0 then return '状态保护或未读回 '..name end
        end
        local effect=retry:find(KILL,function(path)
            local found=find(path)
            if U.valid(found) then return found end
            local loaded=load(path)
            return U.valid(loaded) and loaded or find(path)
        end)
        if not U.valid(effect) then return 'GE_Kill 未加载' end
        if not options.live(actor) then return '结算前目标已失效' end
        local applied=call(asc,'BP_ApplyGameplayEffectToSelf',effect,0.0,{})
        return 'GE_Kill 调用='..tostring(applied)..' HP='..tostring(hp)..' -> '..tostring(read(actor,'Health'))
    end

    function self:stop()
        session,roster,pending,aims=nil,{},{},{}
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
        local hits=pending
        pending={}
        for targetKey,record in pairs(hits)do
            local attacker,victim=roster[record.source],roster[targetKey]
            if attacker and attacker.class_path==MBOSS and victim
                and attacker.team==record.sourceTeam and victim.team==record.targetTeam
                and fullName(attacker.actor)==record.sourceName and fullName(victim.actor)==record.targetName then
                say('铡刀命中结算 '..record.targetName..' '..finish(victim))
            end
        end
        for key,member in pairs(roster)do
            if member.class_path==MBOSS and options.live(member.actor) and (read(member.actor,'Health') or 0)>0 then
                syncAim(member,key)
            end
        end
        for key in pairs(aims)do if not roster[key] then aims[key]=nil end end
    end

    -- UE4SS removes the script hook with the mod. Any retained callback becomes inert first.
    function self:silence()
        alive=false
        self:stop()
    end
    return self
end

return Guillotine
