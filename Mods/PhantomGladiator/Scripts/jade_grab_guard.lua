-- Keep phase-protected grabs nonlethal and release Yu Ding's terminal slow on surviving arena targets.
local U=require('ue_observe')
local Guard={}
local ROOT='/PBZCombatAsset/ActorData/Mobs/'
local JADE_ROOT=ROOT..'YuDing_00/'
local function asset(dir,name)return dir..name..'.'..name..'_C' end
local JADE=asset(JADE_ROOT,'BP_Monster_FemaleVessel_YuDing')
local VICTIMS={
    [asset(ROOT..'054_ZuoShang/','BP_Monster_ZuoShang')]=true,
    [asset(ROOT..'078_MengHua/','BP_Monster_MengHua')]=true,
}
local GRAB=JADE_ROOT..'Ability/Abilities/Grab/'
local BASE,LETHAL,RECEIVER=asset(GRAB,'GA_YuDing_GEx_01'),asset(GRAB,'GA_YuDing_GEx_01_Execution'),asset(GRAB,'GA_YuDing_GEd_01')
local SLOW=asset('/MagCombatAbilities/Actions/','GAAction_Slomo')
local HANDLE_LIST='Handles_3_877B29EB47E2D6E588FC0C9DF344F29B'
local CLOCK_LIBRARY='/Script/Engine.Default__KismetSystemLibrary'
local SLOW_END_GRACE=0.25
Guard.family=JADE_ROOT
Guard.paths={BASE..':IsKill',LETHAL..':IsKill',SLOW..':Received_ActionBegin'}
local function call(obj,method,...)
    if not U.valid(obj)then return nil end
    local args=table.pack(...)
    local ok,value=pcall(function()return obj[method](obj,table.unpack(args,1,args.n))end)
    if ok then return U.unwrap(value)end
end
local function classPath(obj)
    local full=call(call(obj,'GetClass'),'GetFullName')
    return type(full)=='string' and full:match('^%S+ (/.+)$') or nil
end
local function actorRef(obj)
    obj=U.unwrap(obj)
    local kind=U.kind(obj)
    if kind=='WeakObjectPtr' or kind=='FWeakObjectPtr' or kind=='TWeakObjectPtr' then
        local ok,value=pcall(function()return obj:Get()end)
        return ok and U.valid(value) and value or nil
    end
    return U.valid(obj) and obj or nil
end
local function same(a,b)local k=U.key(a);return k~=nil and k==U.key(b)end
local function finite(v)
    return type(v)=='number' and v==v and v>-math.huge and v<math.huge
end
local function singleTargetHandles(action,target)
    local count,owned=0,nil
    local handles=U.field(action,'Handles')
    local ok=pcall(function()handles:ForEach(function(k,list)
        count=count+1
        if same(actorRef(k),target) then owned=U.unwrap(list) end
    end)end)
    if ok and count==1 then return owned end
end
local function hasHandle(info,key)
    local value=U.struct(U.struct(info,key),'Handle')
    return type(value)=='number' and value>0
end
function Guard.new(o)
    local self={}
    local actors,allies,hooks,pendingSlows={},{},{},{}
    local find,load=o.staticFind or StaticFindObject,o.loadAsset or LoadAsset
    local register,unregister=o.registerHook or RegisterHook,o.unregisterHook or UnregisterHook
    local thread=o.inGameThread or IsInGameThread
    local clock=o.clock or os.clock
    local stats=o.attributes
    local fname=o.fname or FName
    local clockLibrary
    local world,retry,lines=nil,0,0
    local alive=true
    local function say(msg)if lines<20 and o.log then lines=lines+1;o.log('[JadeGrab] '..msg)end end
    local function onThread()
        if type(thread)~='function' then return false end
        local ok,v=pcall(thread);return ok and v==true
    end
    local function protected(source,target)
        local targetKey=U.key(target)
        local attacker=actors[U.key(source)]
        if not attacker or attacker.class_path~=JADE or not targetKey then return false end
        local current=o.world();local player=o.player()
        if not same(current,world) or not U.valid(player) or same(player,source) or same(player,target)
            or not U.inWorld(source,current) or not U.inWorld(target,current)
            or classPath(source)~=JADE
            or call(source,'IsPlayerControlled')==true or call(target,'IsPlayerControlled')==true then return false end
        local targetClass=classPath(target)
        if not VICTIMS[targetClass] then return false end
        if attacker.team=='companion' then
            if allies[targetKey] or tonumber((call(U.field(source,'Faction Component'),'GetFactionRelation',target)))~=2 then return false end
        else
            local victim=actors[targetKey]
            if not victim or victim.team==attacker.team or victim.class_path~=targetClass then return false end
        end
        local hp=o.hp(target)
        if type(hp)~='number' or not (hp>0) then return false end
        stats=stats or require('character_stats').new()
        local floor,max=stats:read(target,'Health_Min'),stats:read(target,'Health_Max')
        return floor and max and type(floor.current)=='number' and type(max.current)=='number' and max.current>0
            and floor.current>max.current*0.01+1 and floor.current<=max.current+1
    end
    local function choose(ability,output)
        if U.unwrap(output)~=true then return end
        local class=classPath(ability)
        if (class~=BASE and class~=LETHAL) or U.field(ability,'bIsActive')~=true then return end
        local source=call(ability,'GetAvatarActorFromActorInfo')
        local info=U.field(ability,'Execution Info')
        local ex,ed=actorRef(U.struct(info,'Executor')),actorRef(U.struct(info,'Target'))
        local target
        -- The hit binds both handles before GrabSuccess. The lock socket can have moved by CheckGrabKill.
        local paired=ed and same(ex,source) and U.struct(info,'IsTarget')==false
            and hasHandle(info,'ExecutionHandle') and hasHandle(info,'ExecutedHandle')
        if paired then target=ed
        else target=call(actorRef(U.struct(U.field(ability,'Lock Target'),'Component')),'GetOwner') end
        if (ex and not same(ex,source)) or (ed and not same(ed,target)) or not protected(source,target) then return end
        local ok=pcall(function()output:set(false)end)
        say('阶段保护目标非致死结算；对象='..U.key(target)..' 来源='..(paired and '已命中配对' or '锁定插槽')
            ..' ForceKill=false 读回='..tostring(ok and U.unwrap(output)==false))
    end
    local function gameTime(current)
        if not U.valid(clockLibrary) then
            local ok,object=pcall(find,CLOCK_LIBRARY)
            clockLibrary=ok and object or nil
        end
        local time=call(clockLibrary,'GetGameTimeInSeconds',current)
        return finite(time) and time or nil
    end
    local function rememberSlow(source,target,list,elapsed,duration)
        local key=U.key(target)
        local attacker,victim=actors[U.key(source)],actors[key]
        if not attacker or attacker.class_path~=JADE or (attacker.team~='red' and attacker.team~='blue')
            or not victim or victim.team==attacker.team then return end
        local current=o.world()
        local player=o.player()
        if not same(current,world) or not U.valid(player) or same(player,source) or same(player,target)
            or call(source,'IsPlayerControlled')==true or call(target,'IsPlayerControlled')==true
            or not U.inWorld(source,current) or not U.inWorld(target,current)
            or classPath(source)~=JADE or classPath(target)~=victim.class_path then return end
        local ids=U.array(U.struct(list,HANDLE_LIST))
        local id=ids and #ids==1 and ids[1]
        -- The native StopSlomo treats zero as a wildcard.
        if not finite(id) or id<=0 or id%1~=0 then return end
        elapsed,duration=U.unwrap(elapsed),U.unwrap(duration)
        if not finite(elapsed) or not finite(duration) or duration<0 then return end
        local time=gameTime(current)
        local targetName,worldName=call(target,'GetFullName'),call(current,'GetFullName')
        if not time or type(targetName)~='string' or type(worldName)~='string' then return end
        local old=pendingSlows[key]
        if old and old.id==id and old.targetName==targetName and old.worldKey==U.key(current)
            and old.worldName==worldName then return end
        -- GrabKill measures this action on the slowed receiver. Its authored duration is the
        -- deadline on the world clock for a survivor, including a disciple that later revives.
        local remaining=math.max(0,duration-elapsed)
        pendingSlows[key]={actor=target,targetName=targetName,worldKey=U.key(current),worldName=worldName,
            id=id,untilTime=time+remaining+SLOW_END_GRACE,attempts=0,retryAt=0}
        say('记录玉鼎致死投的 0.01 慢动作；对象='..key..' 句柄='..id..' 原动作剩余秒数='..remaining)
    end
    local function recoverSlows(force)
        if not next(pendingSlows) or not onThread() then return end
        local current=o.world()
        local worldKey,worldName=U.key(current),call(current,'GetFullName')
        if not worldKey or type(worldName)~='string' then return end
        local player=o.player()
        local time=not force and gameTime(current)
        local at=clock()
        for key,record in pairs(pendingSlows)do
            local target=record.actor
            if record.worldKey~=worldKey or record.worldName~=worldName or U.key(target)~=key
                or call(target,'GetFullName')~=record.targetName or not U.inWorld(target,current)
                or same(player,target) or call(target,'IsPlayerControlled')==true then
                pendingSlows[key]=nil
            elseif U.valid(player) and at>=record.retryAt
                and (force or time and time>=record.untilTime and (o.hp(target) or 0)>0) then
                local before=U.field(target,'CustomTimeDilation')
                pendingSlows[key]=nil
                local ok=pcall(function()target:StopSlomo(fname('Ability'),record.id)end)
                local after=U.field(target,'CustomTimeDilation')
                say('回收受招者慢动作；对象='..key..' 句柄='..record.id..' 调用='..tostring(ok)
                    ..' 个人速度='..tostring(before)..'→'..tostring(after))
                if not ok and record.attempts<2 and not pendingSlows[key] then
                    record.attempts=record.attempts+1;record.retryAt=at+0.5;pendingSlows[key]=record
                end
            end
        end
    end
    local function slow(action,elapsed,duration)
        if classPath(action)~=SLOW then return end
        local multiplier=U.field(action,'Multiplier')
        if not finite(multiplier) or math.abs(multiplier-0.01)>0.00001 then return end
        local id=U.field(action,'Slomo ID')
        if type(id)~='string' then local ok,s=pcall(function()return id:ToString()end);id=ok and s end
        if id~='Ability' then return end
        local ability=call(action,'GetAbility')
        if classPath(ability)~=RECEIVER or U.field(ability,'bIsActive')~=true then return end
        local target=call(ability,'GetAvatarActorFromActorInfo')
        local info=U.field(ability,'Execution Info')
        local source=actorRef(U.struct(info,'Executor'))
        if not same(actorRef(U.struct(info,'Target')),target) or not U.valid(source) then return end
        -- The native begin action just populated this map. A shared map cannot establish ownership.
        local handles=singleTargetHandles(action,target)
        if not handles then return end
        if not protected(source,target) then
            rememberSlow(source,target,handles,elapsed,duration)
            return
        end
        local stopped=pcall(function()action['Stop Slomo Handles'](action)end)
        local after=U.field(target,'CustomTimeDilation')
        say('回收本次致死投的受招慢动作；对象='..U.key(target)..' 调用='..tostring(stopped)..' 个人速度='..tostring(after))
    end
    local function detachHooks()
        world=nil;actors,allies={},{};retry=0
        if next(hooks) and onThread()then
            for path,h in pairs(hooks)do
                local ok,result=pcall(unregister,path,h[1],h[2])
                if ok and result~=false then h.enabled=false;hooks[path]=nil end
            end
        end
    end
    function self:clear()
        recoverSlows(true)
        detachHooks()
    end
    function self:silence()alive=false;self:clear()end
    function self:sync(list,active)
        if not alive then return false end
        recoverSlows(false)
        local jade,targets={},{}
        for _,m in ipairs(list)do
            if not m.reserve and not m.stand and not m.aid then
                local team=m.team
                if team=='companion' and m.class_path==JADE then
                    jade.companion=true
                elseif active and (team=='red' or team=='blue') then
                    if m.class_path==JADE then jade[team]=true elseif VICTIMS[m.class_path] then targets[team]=true end
                end
            end
        end
        local arenaJade=jade.red or jade.blue
        local phaseProtection=jade.companion or jade.red and targets.blue or jade.blue and targets.red
        if not arenaJade and not jade.companion then
            if world or next(hooks) then detachHooks()end
            return true
        end
        world=o.world and o.world();actors,allies={},{}
        if not U.valid(world) or not o.player or not onThread() then return false end
        for _,m in ipairs(list)do
            local team=m.team
            local key=U.key(m.actor)
            if key then
                if team=='companion' then allies[key]=true end
                if not m.reserve and not m.stand and not m.aid then
                    if (team=='companion' and m.class_path==JADE)
                        or (arenaJade and (team=='blue' or team=='red')) then
                        actors[key]=m
                    end
                end
            end
        end
        local complete=true
        for i,path in ipairs(Guard.paths)do
            local needed=phaseProtection or i==3
            if needed and not hooks[path] then
                if clock()>=retry and type(register)=='function' and type(unregister)=='function' then
                    local ok,fn=pcall(find,path)
                    if not ok or not U.valid(fn) then pcall(load,path:match('^(.*):'));ok,fn=pcall(find,path)end
                    if ok and U.valid(fn)then
                        local handler=i==3 and slow or choose
                        local registration={enabled=false}
                        local reg,pre,post=pcall(register,path,function(ctx,...)
                            if alive and registration.enabled and world and onThread()then
                                local done,err=pcall(handler,U.unwrap(ctx),...);if not done then say('回调未完成 '..tostring(err))end
                            end
                        end)
                        if reg and type(pre)=='number' and type(post)=='number' then
                            registration[1],registration[2],registration.enabled=pre,post,true
                            hooks[path]=registration
                        end
                    end
                end
                if needed and not hooks[path] then complete=false end
            end
        end
        if not complete and clock()>=retry then retry=clock()+3;say('玉鼎抓取守护接口未就绪，稍后重试')end
        return not phaseProtection or complete
    end
    return self
end
return Guard
