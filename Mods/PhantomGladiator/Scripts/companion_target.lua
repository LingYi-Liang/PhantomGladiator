-- Read a companion's own current enemy; never select the player or mutate AI state.
local U=require('ue_observe')
local Targets={}
-- How long the enemy a companion was last read fighting may stand in for an AI target key that is empty for a moment.
Targets.MEMORY_SECONDS=20
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
    local owned,seen,last={},{},{}
    local clock=options.clock or os.clock
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
        for key in pairs(last)do if not owned[key]then last[key]=nil end end
    end
    local function query(actor,castTarget,castName)
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
        local bb=options.boardOf(actor);local boardKey=U.key(bb)
        if not boardKey then return nil end
        local handler=U.field(targeting,'DefaultTargetHandler')
        if U.key(U.field(handler,'Blackboard'))~=boardKey or U.field(handler,'Target Key')==nil then
            handler=options.boundHandler and options.boundHandler(actor,bb)
            if U.key(U.field(handler,'Blackboard'))~=boardKey then return nil end
        end
        local faction=U.field(actor,'Faction Component')
        if not U.valid(faction) then return nil end
        local function hostile(target,field,remember)
            local id=U.key(target)
            if not id or id==key or id==playerKey or owned[id] then return nil,true end
            if not U.inWorld(target,world) then return nil,false end
            local ok,hp=pcall(options.hp,target)
            if not ok or type(hp)~='number' or hp~=hp or math.abs(hp)==math.huge then return nil,false end
            if hp<=0 then return nil,true end
            if not U.npcPath(target) then return nil,false end
            local related,value=pcall(function()return faction:GetFactionRelation(target)end)
            local relation=related and tonumber(U.unwrap(value))
            if relation~=2 then return nil,relation==0 or relation==1 end
            local enemyName=nameOf(target)
            if enemyName and seen[key]~=enemyName then
                seen[key]=enemyName
                log('[CompanionTarget] 当前敌人读回 '..record.name..' -> '..enemyName..'；来源='..field..'；敌对=2')
            end
            if remember then last[key]={target=target,name=enemyName,at=clock()}end
            return target,true
        end
        local empty=true
        for _,field in ipairs({'Target Key','LastSensedActorKey'})do
            local targetKey,known=U.field(handler,field)
            if not known or targetKey==nil then return nil end
            local ok,target=pcall(function()return U.unwrap(bb:GetValueAsObject(targetKey))end)
            if not ok then return nil end
            local enemy,known=hostile(target,field,true)
            if enemy then return enemy,true end
            if not known then empty=false end
        end
        -- An already launched volley may outlast the AI's target key. Revalidate its own enemy.
        if castName and castName==nameOf(castTarget) then return hostile(castTarget,'本次施法或刚才的敌人'),false end
        return nil,empty
    end
    function self:inspect(actor)return query(actor)end
    function self:current(actor,castTarget,castName)
        local target=query(actor,castTarget,castName)
        return target
    end
    -- For a skill that takes its own lock while the AI's target key is empty for a moment (左殇's 万剑归宗 keeps the
    -- first target it selects, and the game's own choice then can be the player): the current enemy, else the enemy
    -- this companion was read fighting within MEMORY_SECONDS, checked again now as any target is (alive, hostile,
    -- in this world, never the player or a companion). The memory is only what current() read from the AI itself.
    function self:lastEnemy(actor)
        local enemy=self:current(actor)
        if enemy then return enemy end
        local key=U.key(actor);local memory=key and last[key]
        if not memory or clock()-memory.at>Targets.MEMORY_SECONDS then return nil end
        return self:current(actor,memory.target,memory.name)
    end
    return self
end
return Targets
