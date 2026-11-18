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
    local parents,hooks={},{}
    local register=o.register or RegisterHook
    local unregister=o.unregister or UnregisterHook
    local function identity(ability,child)
        ability,child=U.unwrap(ability),U.unwrap(child)
        local _,parent=call(ability,'GetAvatarActorFromActorInfo')
        local r=parents[U.key(parent) or '']
        if not r or not o.current(r) or not U.npcPath(child) or U.key(child)==U.key(parent) or not inWorld(child,r.world) then return end
        local _,class=call(ability,'GetClass')
        local _,name=call(class,'GetFullName')
        local path=type(name)=='string' and name:match('^%S+ (/.+)$') or nil
        local rule=path and r.shadowSummons.byClass[path]
        if rule then return r,rule,child end
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
        r.shadowSummons.children[U.key(unit)]={actor=unit,rule=rule}
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
        r.shadowSummons.children[U.key(unit)]={actor=unit,rule=rule}
    end
    local function hook(path,cb)
        if hooks[path] then return true end
        if type(register)~='function' or not U.valid(o.asset(path)) then return false end
        local ok,pre,post=pcall(register,path,cb)
        if ok and type(pre)=='number' and type(post)=='number' then hooks[path]={pre,post};return true end
        return false
    end
    function self:arm(r,choice,rules)
        if not rules then return true end
        if not o.current(r) then return false end
        r.shadowSummons=r.shadowSummons or {byClass={},children={}}
        parents[U.key(r.actor)]=r
        if not hook(base..':OnDeferedSpawn',onDeferred) or not hook(base..':OnSpawnFinish',onUpgrade)
            or not hook(base..':ApplySummonUpgradeEffect',onUpgrade) then return false end
        for cls,effects in pairs(rules) do
            o.asset(cls)
            if U.valid(o.asset(cls..':ApplyEffectOnSummon')) and not hook(cls..':ApplyEffectOnSummon',onUpgrade) then return false end
            r.shadowSummons.byClass[cls]={choice=choice,effects=effects}
        end
        return true
    end
    function self:cleanup(r)
        local state=r.shadowSummons
        if not state then return end
        local parentKey=U.key(r.actor)
        if parentKey then parents[parentKey]=nil end
        for key,owner in pairs(parents) do if owner==r then parents[key]=nil end end
        if o.current(r) then
            for key,entry in pairs(state.children) do
                local unit=entry.actor
                -- The native ability established parentage at birth; recheck the original identity,
                -- world and a still-live Owner or Instigator so a reused actor cannot be removed.
                if U.key(unit)==key and inWorld(unit,r.world) and
                    (U.key(U.field(unit,'Owner'))==parentKey or U.key(U.field(unit,'Instigator'))==parentKey) then
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
        if not next(parents) and type(unregister)=='function' then
            for path,ids in pairs(hooks) do
                local ok=pcall(unregister,path,ids[1],ids[2])
                if ok then hooks[path]=nil end
            end
        end
    end
    return self
end
return M
