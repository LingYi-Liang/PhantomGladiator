-- These pawns attach to a mod-owned spawner that supplies coordinates or group data.
-- BP_NPC_Base waits for that spawner's completion. Its pawn callback just registers the target.
local U=require('ue_observe')
local Registration={}
local COMBAT='Targeting.Target.Combat'
local BATCH_SIZE,ATTEMPTS,RETRY_SECONDS=12,6,0.75

local function nameOf(object)
    if not U.valid(object) then return nil end
    local ok,name=pcall(function()return object:GetFullName()end)
    if ok and type(name)=='string' and name~='' then return name end
end

local function registered(subsystem)
    if not U.valid(subsystem) then return nil end
    local out={}
    local ok=pcall(function()subsystem:GetTargetsByTag({TagName=FName(COMBAT)},true,out)end)
    local actors=ok and U.array(out.OutTargets or (out[1] and out))
    if not actors then return nil end
    local keys={}
    for _,actor in ipairs(actors)do
        local key=U.key(actor)
        if key then keys[key]=true end
    end
    return keys
end

function Registration.new(options)
    local self,pending={},{}
    local clock=options.clock or os.clock
    local function sameBinding(row,world)
        return U.key(row.actor)==row.key and nameOf(row.actor)==row.name and U.inWorld(row.actor,world)
            and U.key(row.spawner)==row.spawnerKey and nameOf(row.spawner)==row.spawnerName
            and U.inWorld(row.spawner,world) and U.field(row.spawner,'InitialSpawn')==false
            and U.key(U.field(row.actor,'Spawner'))==row.spawnerKey
            and not options.isDestroying(row.actor) and not options.isDestroying(row.spawner)
    end
    local function finish(row,readback)
        pending[row.key]=nil
        options.log(string.format('[SummonTarget] %s 回调调用=%s 战斗目标登记读回=%s',
            row.name,tostring(row.called==true),readback==nil and '?' or tostring(readback)))
    end

    -- Called once after FinishSpawn, with the placeholder resolved from a mod-owned record.
    function self:enqueue(actor,spawner,world)
        if options.inGameThread()~=true then return end
        local key,spawnerKey,worldKey=U.key(actor),U.key(spawner),U.key(world)
        if not key or not spawnerKey or not worldKey then return end
        local name,spawnerName=nameOf(actor),nameOf(spawner)
        if not name or not spawnerName then return end
        local previous=pending[key]
        if previous and previous.worldKey==worldKey and previous.name==name
            and previous.spawnerKey==spawnerKey and previous.spawnerName==spawnerName then return end
        local row={actor=actor,spawner=spawner,key=key,spawnerKey=spawnerKey,worldKey=worldKey,
            name=name,spawnerName=spawnerName,due=clock(),tries=0}
        if sameBinding(row,world) then pending[key]=row end
    end

    function self:cancel(actor)
        if not next(pending) then return end
        local key=U.key(actor)
        local row=pending[key]
        if row and row.name==nameOf(actor) then pending[key]=nil end
    end

    function self:tick()
        if not next(pending) or options.inGameThread()~=true then return end
        local world=options.world()
        local worldKey=U.key(world)
        if not worldKey then return end
        local now=clock()
        local batch,verify={},{}
        for key,row in pairs(pending)do
            if row.worldKey~=worldKey then pending[key]=nil
            elseif row.awaiting or (#batch<BATCH_SIZE and now>=row.due) then
                if sameBinding(row,world) then
                    local hp=options.hp(row.actor)
                    if type(hp)=='number' and hp<=0 then pending[key]=nil
                    elseif row.awaiting then verify[#verify+1]=row
                    else
                        row.ready=type(hp)=='number' and hp>0
                        row.due,row.tries=now+RETRY_SECONDS,row.tries+1
                        batch[#batch+1]=row
                    end
                else pending[key]=nil end
            end
        end
        if #batch==0 and #verify==0 then return end

        local subsystem=options.subsystem()
        local available=U.inWorld(subsystem,world)
        -- Share one snapshot for the previous batch's readback and the new batch's duplicate check.
        local targets=available and registered(subsystem) or nil
        for _,row in ipairs(verify)do
            row.awaiting=nil
            local seen
            if targets then seen=targets[row.key]==true end
            if seen or row.tries>=ATTEMPTS then finish(row,seen) end
        end
        for _,row in ipairs(batch)do
            local seen
            if targets then seen=targets[row.key]==true end
            if seen then finish(row,true)
            else
                if row.ready and available and (targets or not row.called)
                    and sameBinding(row,world) and U.valid(subsystem) then
                    local ok=pcall(function()row.actor:CompleteSpawnAI_Event(row.actor)end)
                    if ok then row.called,row.awaiting=true,true end
                end
                if not row.awaiting and row.tries>=ATTEMPTS then finish(row,seen) end
            end
        end
    end

    return self
end

return Registration
