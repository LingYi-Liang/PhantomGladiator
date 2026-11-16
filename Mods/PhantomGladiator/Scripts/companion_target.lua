-- Read a companion's own current enemy; never select the player or mutate AI state.
local U=require('ue_observe')
local Targets={}
local function nameOf(object)
    if not U.valid(object) then return nil end
    local ok,name=pcall(function()return object:GetFullName()end)
    return ok and type(name)=='string' and name or nil
end
local function alive(options,actor)
    if not U.valid(actor) then return false end
    local ok,hp=pcall(options.hp,actor)
    return ok and type(hp)=='number' and hp==hp and hp>0 and hp<math.huge
end
function Targets.new(options)
    local owned,seen={},{}
    local log=options.log or function()end
    local self={}
    function self:sync(members)
        local current={}
        for _,member in ipairs(members or {})do
            if member.team=='companion' and not member.stand and not member.reserve then
                local key,name=U.key(member.actor),nameOf(member.actor)
                if key and name then current[key]={actor=member.actor,name=name}end
            end
        end
        owned=current
        for key in pairs(seen)do if not owned[key]then seen[key]=nil end end
    end
    function self:current(actor)
        local key=U.key(actor);local record=key and owned[key]
        if not record or record.name~=nameOf(actor) or not alive(options,actor) then return nil end
        if options.stillOwned and options.stillOwned(actor)~=true then return nil end
        local world=options.world();local player=options.player()
        local playerKey=U.key(player)
        if not U.valid(world) or not playerKey or key==playerKey or not U.inWorld(actor,world) then return nil end
        local targeting=U.field(actor,'Targeting Component')
        if not U.valid(targeting) then return nil end
        local called,owner=pcall(function()return targeting:GetOwner()end)
        if not called or U.key(U.unwrap(owner))~=key then return nil end
        local handler=U.field(targeting,'DefaultTargetHandler')
        local bb=U.field(handler,'Blackboard')
        local expected=options.boardOf(actor)
        if not U.valid(bb) or not U.valid(expected) or U.key(bb)~=U.key(expected) then return nil end
        local faction=U.field(actor,'Faction Component')
        if not U.valid(faction) then return nil end
        for _,field in ipairs({'Target Key','LastSensedActorKey'})do
            local targetKey,known=U.field(handler,field)
            if not known or targetKey==nil then return nil end
            local ok,target=pcall(function()return U.unwrap(bb:GetValueAsObject(targetKey))end)
            if not ok then return nil end
            local targetId=U.key(target)
            if targetId and targetId~=key and targetId~=playerKey and not owned[targetId]
                and U.inWorld(target,world) and alive(options,target) and U.npcPath(target) then
                local related,relation=pcall(function()return faction:GetFactionRelation(target)end)
                if related and tonumber(U.unwrap(relation))==2 then
                    local enemyName=nameOf(target)
                    if enemyName and seen[key]~=enemyName then
                        seen[key]=enemyName
                        log('[CompanionTarget] 当前敌人读回 '..record.name..' -> '..enemyName..'；来源='..field..'；敌对=2')
                    end
                    return target
                end
            end
        end
        return nil
    end
    return self
end
return Targets
