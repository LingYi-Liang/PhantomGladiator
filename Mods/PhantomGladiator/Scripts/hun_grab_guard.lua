-- With immunity enabled, decline the targeted NPC's grab receiver grant and its grab-only target check.
-- Only inspect immutable data paths. The class argument belongs to this call on this ASC.
local U=require('ue_observe')
local Catalog=require('hun_grab_catalog')
local Guard={}
local GIVE='/Script/GameplayAbilities.AbilitySystemComponent:K2_GiveAbility'
local TARGET='/Script/SGameCombatSystem.BulletAttackModule:IsValidTarget'
local EVENT='/SGameExecution/Bullet/Events/BP_BulletEvent_Grab.BP_BulletEvent_Grab_C'

local function call(obj,method,...)
    if not U.valid(obj) then return nil end
    local args=table.pack(...)
    local ok,result=pcall(function()return obj[method](obj,table.unpack(args,1,args.n))end)
    if ok then return U.unwrap(result) end
end
local function path(obj)
    local full=call(obj,'GetFullName')
    return type(full)=='string' and full:match('^%S+ (/.+)$') or nil
end

function Guard.new(o)
    local self={grants=0,targets=0}
    local byActor,byASC,hooks={},{},{}
    local find,register,unregister=o.find or StaticFindObject,o.register or RegisterHook,o.unregister or UnregisterHook
    local thread=o.inGameThread or IsInGameThread
    local empty
    local alive=true
    local function say(text) if o.log then o.log('[HunGrabGuard] '..text) end end
    local function gameThread()
        if type(thread)~='function' then return false end
        local ok,inGame=pcall(thread)
        return ok and inGame==true
    end
    local function authorized(r)
        return r and o.current(r) and r.loadout and r.loadout.survival and r.loadout.survival.grab=='immune'
    end
    local function emptyClass()
        if U.kind(empty)=='UClass' and not U.valid(empty) then return empty end
        local ok,event=pcall(find,EVENT)
        if not ok or not U.valid(event) then return end
        local value,read=U.field(call(event,'GetCDO'),'NonPlayerGE')
        if read and U.kind(value)=='UClass' and not U.valid(value) then empty=value;return value end
    end
    local function grant(context,ability,level,input)
        if not alive or not gameThread() then return end
        local asc=U.unwrap(context)
        local r=byASC[U.key(asc) or '']
        if not r or U.unwrap(level)~=0 or U.unwrap(input)~=-1 then return end
        local old=U.unwrap(ability)
        local name=path(old)
        if not Catalog.receivers[name] or not authorized(r) or U.key(U.field(r.actor,'AbilitySystemComponent'))~=U.key(asc) then return end
        local null=emptyClass()
        if not null then say('原生空类未读回，跳过本次受抓能力拦截');return end
        say('即将 拦截 '..tostring(r.name)..' 本次受抓能力 '..name)
        local ok=pcall(function()ability:set(null)end)
        local read=U.unwrap(ability)
        if ok and U.kind(read)=='UClass' and not U.valid(read) then
            self.grants=self.grants+1;say('受抓能力参数读回为空，累计='..self.grants)
        else say('本次受抓能力参数未确认') end
    end
    local function target(context,actor)
        if not alive or not gameThread() then return end
        local r=byActor[U.key(U.unwrap(actor)) or '']
        if not r then return end
        local module=U.unwrap(context)
        local name=path(U.field(module,'BulletData'))
        if Catalog.bullets[name] and authorized(r) then
            self.targets=self.targets+1
            if self.targets<=8 then say('投技不选免抓实例 '..tostring(r.name)..' '..name) end
            return false
        end
    end
    local function install(key,pre,post)
        if hooks[key] then return end
        local found,fn=pcall(find,key)
        if not found or not U.valid(fn) or type(register)~='function' then return end
        local function guarded(cb)
            return function(...)
                local ok,value=pcall(cb,...)
                if ok then return value end
                say('挂钩回调中断 '..tostring(value))
            end
        end
        local ok,a,b=pcall(register,key,guarded(pre),guarded(post))
        if ok and type(a)=='number' and a>=0 and type(b)=='number' and b>=0 then
            hooks[key]={a,b};say('挂钩已登记 '..key..' '..a..'/'..b)
        end
    end
    local function noop()end
    local function detach()
        for key,ids in pairs(hooks) do
            if type(unregister)=='function' then
                local ok,ret=pcall(unregister,key,ids[1],ids[2])
                if ok and ret~=false then hooks[key]=nil else say('注销未确认 '..key) end
            end
        end
    end
    function self:start(r)
        if not alive or not authorized(r) then return end
        local actor,asc=U.key(r.actor),U.key(U.field(r.actor,'AbilitySystemComponent'))
        if not actor or not asc then return end
        byActor[actor],byASC[asc]=r,r
        -- The game grants a fresh level-0 receiver only inside the grab Trigger blueprint.
        -- The native target hook provides earlier rejection on collision paths that pass through reflection.
        install(GIVE,grant,noop)
        install(TARGET,noop,target)
    end
    function self:stop(r)
        local actor=U.key(r.actor)
        if actor and byActor[actor]==r then byActor[actor]=nil end
        -- An expired or reused component may no longer be readable.
        for key,record in pairs(byASC) do if record==r then byASC[key]=nil end end
        if not actor then for key,record in pairs(byActor)do if record==r then byActor[key]=nil end end end
        if not next(byActor) then detach() end
    end
    function self:silence()
        alive=false;byASC={};byActor={};detach()
    end
    return self
end
return Guard
