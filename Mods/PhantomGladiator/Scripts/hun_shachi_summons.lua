-- Correct the native minion's profile before it finishes spawning. The Hun summon blueprints
-- read the globally held weapon's level. All corrections below are confined to a child named
-- by the summon ability of a currently registered NPC, in the very same world.
local U=require('ue_observe')
local M={}
local base='/PBZCombatAsset/ActorData/Players/Hun/Abilities/ShachiAbility/GA_SummonPassive_Hun.GA_SummonPassive_Hun_C'
local function call(o,m,...)
    if not U.valid(o) then return false end
    local args,n={...},select('#',...)
    local ok,v=pcall(function()return o[m](o,table.unpack(args,1,n))end)
    return ok,U.unwrap(v)
end
local function inWorld(child,world)
    local obj=child
    for _=1,8 do
        if not U.valid(obj) then return false end
        if U.key(obj)==world then return true end
        local _,outer=call(obj,'GetOuter');obj=outer
    end
    return false
end
function M.new(o)
    local self={}
    local parents,hooks,alive={},{},true
    local register=o.register or RegisterHook
    local unregister=o.unregister or UnregisterHook
    local function identity(ability,child)
        if not alive or not next(parents) then return end
        ability,child=U.unwrap(ability),U.unwrap(child)
        local _,parent=call(ability,'GetAvatarActorFromActorInfo')
        local r=parents[U.key(parent) or '']
        if not r or not o.current(r) or not U.npcPath(child) or U.key(child)==U.key(parent) or not inWorld(child,r.world) then return end
        local _,class=call(ability,'GetClass')
        local _,name=call(class,'GetFullName')
        local path=type(name)=='string' and name:match('^%S+ (/.+)$') or nil
        local state=r.shadowSummons
        if not state or not path then return end
        local key=U.key(child)
        local named,childName=call(child,'GetFullName')
        if not key or not named or type(childName)~='string' then return end
        local owner=U.key(U.field(child,'Owner'))
        if owner and parents[owner] and parents[owner]~=r then return end
        local prior=state.children[key]
        local rule
        if prior and prior.name==childName then
            if prior.path~=path or (prior.owner and owner and prior.owner~=owner and owner~=U.key(parent)) then return end
            prior.owner=owner or prior.owner
            rule=prior.rule
        else
            rule=state.byClass[path]
            if not rule then return end
            -- Record the birth even if the level or ASC has not initialized yet.
            -- Late upgrade callbacks use the loadout that created this child.
            state.children[key]={actor=child,name=childName,path=path,rule=rule,owner=owner}
        end
        return r,rule,child
    end
    local function onDeferred(ability,child)
        local r,rule,unit=identity(ability,child)
        if not r then return end
        local _,cfg=call(unit,'GetGlobalCombatConfig')
        local got,offset=call(cfg,'GetGlobalMobLevelOffset')
        if not got or type(offset)~='number' or type(U.field(unit,'Level'))~='number' then return end
        local level=rule.choice.level+offset
        o.say(r,'即将写影武召唤物等级 '..level)
        if o.current(r) then pcall(function()unit.Level=level end) end
        o.say(r,'召唤物等级读回 '..tostring((U.field(unit,'Level'))))
    end
    local function onUpgrade(ability,child)
        local r,rule,unit=identity(ability,child)
        if not r then return end
        local childAsc=U.field(unit,'AbilitySystemComponent')
        local parentAsc=U.field(r.actor,'AbilitySystemComponent')
        local _,ascOwner=call(childAsc,'GetOwner')
        if not U.valid(childAsc) or not U.valid(parentAsc) or U.key(ascOwner)~=U.key(unit) then return end
        for _,effect in ipairs(rule.effects) do
            if not o.current(r) or not U.valid(unit) then return end
            local cls=o.asset(effect.path)
            local read,n=call(childAsc,'GetGameplayEffectCount',cls,parentAsc,false)
            if read and type(n)=='number' then
                if rule.choice.level>=effect.level and n==0 then
                    o.say(r,'即将补召唤物武装效果 '..effect.path:match('[^/]+$'))
                    call(parentAsc,'BP_ApplyGameplayEffectToTarget',cls,childAsc,0,{})
                elseif rule.choice.level<effect.level and n>0 then
                    o.say(r,'即将撤回超出本方案的召唤物效果 '..effect.path:match('[^/]+$'))
                    call(childAsc,'RemoveActiveGameplayEffectBySourceEffect',cls,parentAsc,-1)
                else goto continue end
                local _,after=call(childAsc,'GetGameplayEffectCount',cls,parentAsc,false)
                o.say(r,'召唤物效果栈 '..n..'→'..tostring(after))
            end
            ::continue::
        end
    end
    local function hook(path,cb)
        if hooks[path] then return true end
        if type(register)~='function' or not U.valid(o.asset(path)) then return false end
        local ok,pre,post=pcall(register,path,cb)
        if ok and type(pre)=='number' and type(post)=='number' then hooks[path]={pre,post};return true end
        return false
    end
    local function detach()
        if type(unregister)~='function' then return end
        for path,ids in pairs(hooks)do
            local ok,result=pcall(unregister,path,ids[1],ids[2])
            if ok and result~=false then hooks[path]=nil end
        end
    end
    function self:arm(r,choice,rules)
        if not alive then return false end
        if not rules then return true end
        if not o.current(r) then return false end
        local parentKey=U.key(r.actor)
        if not parentKey then return false end
        local ready=hook(base..':OnDeferedSpawn',onDeferred) and hook(base..':OnSpawnFinish',onUpgrade)
            and hook(base..':ApplySummonUpgradeEffect',onUpgrade)
        for cls in pairs(rules) do
            if not ready then break end
            o.asset(cls)
            if U.valid(o.asset(cls..':ApplyEffectOnSummon')) then ready=hook(cls..':ApplyEffectOnSummon',onUpgrade) end
        end
        if not ready or not o.current(r) then if not next(parents) then detach() end;return false end
        local state=r.shadowSummons or {byClass={},children={}}
        r.shadowSummons=state;parents[parentKey]=r
        local previous,installed={},{}
        for cls,effects in pairs(rules) do
            previous[cls]=state.byClass[cls]
            installed[cls]={choice=choice,effects=effects}
            state.byClass[cls]=installed[cls]
        end
        return true,function()
            if parents[parentKey]~=r or r.shadowSummons~=state then return end
            for cls,rule in pairs(installed) do
                if state.byClass[cls]==rule then state.byClass[cls]=previous[cls] end
            end
            if not next(state.byClass) and not next(state.children) then
                parents[parentKey]=nil;r.shadowSummons=nil
                if not next(parents) then detach() end
            end
        end
    end
    function self:cleanup(r)
        local state=r.shadowSummons
        if not state then return end
        local parentKey=U.key(r.actor)
        for key,owner in pairs(parents) do if owner==r then parents[key]=nil end end
        if parentKey and o.current(r) then
            for key,entry in pairs(state.children) do
                local unit=entry.actor
                -- The native ability established parentage at birth; recheck the original identity,
                -- world and a still-live Owner or Instigator so a reused actor cannot be removed.
                local ok,name=call(unit,'GetFullName')
                local owner=U.key(U.field(unit,'Owner'))
                if ok and name==entry.name and U.key(unit)==key and inWorld(unit,r.world) and
                    (owner==parentKey or ((not entry.owner or not owner or entry.owner==owner)
                        and U.key(U.field(unit,'Instigator'))==parentKey)) then
                    local got,gone=call(unit,'IsActorBeingDestroyed')
                    if got and gone==false then
                        o.say(r,'即将清理影武召唤物 '..key)
                        call(unit,'K2_DestroyActor')
                        local _,after=call(unit,'IsActorBeingDestroyed')
                        o.say(r,'影武召唤物销毁中='..tostring(after)..' 有效='..tostring(U.valid(unit)))
                    end
                end
            end
        end
        r.shadowSummons=nil
        if not next(parents) then detach() end
    end
    function self:silence()
        alive=false;parents={};detach()
    end
    return self
end
return M
