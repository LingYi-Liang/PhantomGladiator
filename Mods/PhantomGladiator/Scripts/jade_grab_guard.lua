-- Keep Yu Ding's normal grab when an arena opponent is protected by its native phase floor.
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
local function hasHandle(info,key)
    local value=U.struct(U.struct(info,key),'Handle')
    return type(value)=='number' and value>0
end
function Guard.new(o)
    local self={}
    local actors,hooks={},{}
    local find,load=o.staticFind or StaticFindObject,o.loadAsset or LoadAsset
    local register,unregister=o.registerHook or RegisterHook,o.unregisterHook or UnregisterHook
    local thread=o.inGameThread or IsInGameThread
    local clock=o.clock or os.clock
    local stats=o.attributes
    local world,retry,lines=nil,0,0
    local alive=true
    local function say(msg)if lines<20 and o.log then lines=lines+1;o.log('[JadeGrab] '..msg)end end
    local function onThread()
        if type(thread)~='function' then return false end
        local ok,v=pcall(thread);return ok and v==true
    end
    local function protected(source,target)
        local attacker,victim=actors[U.key(source)],actors[U.key(target)]
        if not attacker or not victim or attacker.team==victim.team or attacker.class_path~=JADE or not VICTIMS[victim.class_path] then return false end
        local current=o.world();local player=o.player()
        if not same(current,world) or not U.valid(player) or same(player,source) or same(player,target)
            or not U.inWorld(source,current) or not U.inWorld(target,current)
            or classPath(source)~=JADE or classPath(target)~=victim.class_path
            or call(source,'IsPlayerControlled')==true or call(target,'IsPlayerControlled')==true then return false end
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
    local function slow(action)
        if classPath(action)~=SLOW then return end
        local multiplier=U.field(action,'Multiplier')
        if type(multiplier)~='number' or math.abs(multiplier-0.01)>0.00001 then return end
        local id=U.field(action,'Slomo ID')
        if type(id)~='string' then local ok,s=pcall(function()return id:ToString()end);id=ok and s end
        if id~='Ability' then return end
        local ability=call(action,'GetAbility')
        if classPath(ability)~=RECEIVER or U.field(ability,'bIsActive')~=true then return end
        local target=call(ability,'GetAvatarActorFromActorInfo')
        local info=U.field(ability,'Execution Info')
        local source=actorRef(U.struct(info,'Executor'))
        if not same(actorRef(U.struct(info,'Target')),target) or not protected(source,target) then return end
        -- Received_ActionBegin has just cleared the map and added the receiver's handles.
        -- Reject a shared or unreadable map rather than resetting any actor's time dilation.
        local count,exclusive=0,true
        local handles=U.field(action,'Handles')
        local ok=pcall(function()handles:ForEach(function(k)
            count=count+1;if not same(actorRef(U.unwrap(k)),target) then exclusive=false end
        end)end)
        if not ok or count~=1 or not exclusive then return end
        local stopped=pcall(function()action['Stop Slomo Handles'](action)end)
        local after=U.field(target,'CustomTimeDilation')
        say('回收本次致死投的受招慢动作；对象='..U.key(target)..' 调用='..tostring(stopped)..' 个人速度='..tostring(after))
    end
    function self:clear()
        world=nil;actors={};retry=0
        if next(hooks) and onThread()then
            for path,h in pairs(hooks)do
                local ok,result=pcall(unregister,path,h[1],h[2])
                if ok and result~=false then h.enabled=false;hooks[path]=nil end
            end
        end
    end
    function self:silence()alive=false;self:clear()end
    function self:sync(list,active)
        if not alive then return false end
        local jade,targets={},{}
        if active then for _,m in ipairs(list)do
            if not m.reserve and not m.stand and not m.aid and (m.team=='red' or m.team=='blue') then
                if m.class_path==JADE then jade[m.team]=true elseif VICTIMS[m.class_path] then targets[m.team]=true end
            end
        end end
        if not (jade.red and targets.blue or jade.blue and targets.red) then
            if world or next(hooks) then self:clear()end
            return true
        end
        world=o.world and o.world();actors={}
        if not U.valid(world) or not o.player or not onThread() then return false end
        for _,m in ipairs(list)do
            if not m.reserve and not m.stand and not m.aid and (m.team=='blue' or m.team=='red') and (m.class_path==JADE or VICTIMS[m.class_path]) then
                local key=U.key(m.actor);if key then actors[key]=m end
            end
        end
        local complete=true
        for i,path in ipairs(Guard.paths)do
            if not hooks[path] then
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
                if not hooks[path] then complete=false end
            end
        end
        if not complete and clock()>=retry then retry=clock()+3;say('阶段保护接口未就绪，本次保留玉鼎原版对 NPC 命中行为')end
        return complete
    end
    return self
end
return Guard
