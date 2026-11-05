-- Pure Lua controller tests; no UE4SS globals or game objects are used.
local Arena = dofile("Mods/PhantomGladiator/Scripts/arena_controller.lua")
local function fixture(overrides)
    local trace, actors, transforms, synced = {}, {}, {}, {}
    local player, world, cls = { name = "player", alive = true }, { alive = true }, { alive = true }
    local catalog = { selectedPath = "/Catalog/BP_Test.BP_Test_C" }
    function catalog:registerPath(path) trace[#trace + 1] = "register"; return { path = path } end
    function catalog:select(path) self.selectedPath = path; trace[#trace + 1] = "select"; return { path = path } end
    function catalog:refresh(npcs) assert(next(npcs) == nil); trace[#trace + 1] = "refresh"; return {} end
    function catalog:resolveSelected() trace[#trace + 1] = "resolve"; return cls end
    function catalog:selected() return { path = self.selectedPath } end
    local options = {
        catalog = catalog, log = function() end,
        canSpawn = function() return true end, -- Explicit fixture permission, not a production fallback.
        valid = function(object) return object ~= nil and object.alive == true end,
        name = function(actor) assert(actor.alive); return actor.name end,
        hp = function(actor) assert(actor.alive); return actor.hp or 400 end,
        combatReady = function(actor) assert(actor.alive); return true end,
        getPlayer = function() return player end,
        getWorld = function(p) assert(p == player and p.alive); return world end,
        getLocation = function(p) assert(p == player and p.alive); return { X = 0, Y = 0, Z = 100 } end,
        getForward = function(p) assert(p == player and p.alive); return { X = 2, Y = 0, Z = 0 } end,
        spawnClass = function(c, transform, w)
            assert(c == cls and w == world and cls.alive and world.alive)
            trace[#trace + 1] = "spawn"
            transforms[#transforms + 1] = transform
            local actor = { alive = true, name = "unit" .. (#actors + 1) }
            actors[#actors + 1] = actor
            return actor
        end,
        onUnitsChanged = function(units)
            trace[#trace + 1] = "sync"
            synced = units
        end,
        activate = function(actor)
            assert(actor.alive)
            local found = false
            for _, unit in ipairs(synced) do if unit.actor == actor then found = true end end
            assert(found, "ownership must be synchronized before activation")
            trace[#trace + 1] = "activate"
            return true
        end,
        setRelation = function(a, b, relation)
            assert(a.alive and b.alive)
            trace[#trace + 1] = { "relation", a, b, relation }
            return true
        end,
        forceAttack = function(a, b)
            assert(a.alive and b.alive and a ~= b)
            trace[#trace + 1] = { "attack", a, b }
            return true
        end,
        restore = function() trace[#trace + 1] = "restore"; return true end,
        destroy = function(actor) trace[#trace + 1] = "destroy"; actor.alive = false end,
        onBattleStarted = function(a, b) trace[#trace + 1] = { "observe", a, b } end,
    }
    for key, value in pairs(overrides or {}) do options[key] = value end
    return { arena = Arena.new(options), options = options, catalog = catalog, player = player, world = world,
        cls = cls, trace = trace, actors = actors, transforms = transforms, synced = function() return synced end }
end

local function stageCount(fixtureValue, stage)
    local count = 0
    for _, event in ipairs(fixtureValue.trace) do
        if event == stage or (type(event) == "table" and event[1] == stage) then count = count + 1 end
    end
    return count
end

local f = fixture()
local warningSpawn=fixture({activate=function()return true,'activated','数值未统一，已回滚到原生值' end})
assert(warningSpawn.arena:spawn(nil,'blue',1).ok)
local warningResult=warningSpawn.arena:spawn(nil,'red',1)
assert(warningResult.ok and warningResult.message:find('数值未统一',1,true))
assert(warningSpawn.arena:status().state~='cleanup_pending' and warningSpawn.arena:start().ok,
    'a safely rolled-back optional stat change must not remove HUDs or block normal combat')
local prepared=fixture()
assert(prepared.arena:spawn(nil,'blue',1).ok and prepared.arena:spawn(nil,'red',1).ok)
prepared.options.prepareBattle=function(members)
    assert(#members==2 and stageCount(prepared,'attack')==0 and stageCount(prepared,'relation')==0)
    return false
end
assert(not prepared.arena:start().ok and stageCount(prepared,'attack')==0,'unconfirmed preparation cannot request combat')
prepared.options.prepareBattle=function()return true end
assert(prepared.arena:start().ok and stageCount(prepared,'attack')==2)
-- Reproduce the multi-second spawn hitch: a selected path must never run discovery.
local directSpawn=fixture()
function directSpawn.catalog:refresh()error('full class discovery on the spawn path')end
assert(directSpawn.arena:spawn('/Catalog/BP_Chosen.BP_Chosen_C','blue',1).ok,
    'spawning an exact selected class must not perform a global catalog refresh')
assert(stageCount(directSpawn,'resolve')==1 and stageCount(directSpawn,'spawn')==1)
-- Switching the next spawn team cannot move existing participants or spawn one.
local teamCycle=fixture()
assert(teamCycle.arena:spawn('/Catalog/BP_Test.BP_Test_C','blue',1).ok)
assert(teamCycle.arena:select('/Catalog/BP_Test.BP_Test_C','blue',3).ok)
local beforeTeamCycle=#teamCycle.trace
for revision,wanted in ipairs({'red','neutral','companion','blue'})do
    local changed=teamCycle.arena:cycleTeam()
    local status=teamCycle.arena:status()
    assert(changed.ok and changed.spawned_count==0 and status.current_team==wanted and status.team_revision==revision)
    assert(status.current_count==3 and status.current_unit=='/Catalog/BP_Test.BP_Test_C')
    assert(status.blue_count==1 and status.red_count==0 and status.neutral_count==0)
end
assert(#teamCycle.trace==beforeTeamCycle,'cycling must not call spawn, relation or attack callbacks')
assert(teamCycle.arena:cycleTeam().ok)
assert(teamCycle.arena:spawn().ok and teamCycle.arena:status().red_count==3,'next shortcut spawn must use the cycled team')
local summons=fixture()
assert(summons.arena:spawn('/Catalog/BP_Owner.BP_Owner_C','blue',1).ok)
assert(summons.arena:spawn('/Catalog/BP_Enemy.BP_Enemy_C','red',1).ok)
assert(summons.arena:start().ok)
local pet={alive=true,name='summon',hp=100}
assert(not summons.arena:adoptSummon(pet,{alive=true},'/Catalog/BP_Pet.BP_Pet_C','fixture').ok,'unowned summoner must never claim a map actor')
assert(summons.arena:adoptSummon(pet,summons.actors[1],'/Catalog/BP_Pet.BP_Pet_C','fixture').ok)
assert(summons.arena:status().blue_count==2 and summons.arena:status().summon_count==1)
local attacks=stageCount(summons,'attack')
summons.arena:tickReinforcements()
assert(stageCount(summons,'attack')==attacks+1,'new summon should be directed at the opposing team')
summons.arena:tickReinforcements()
assert(stageCount(summons,'attack')==attacks+1,'stable targets must not be forced again every tick')
assert(summons.arena:stop().ok and not pet.alive,'owned summons must be included in cleanup')
-- 冷荼: seven dolls she keeps hidden for later, and herself out of reach until she comes down to fight.
local staged=fixture({dormant=function(actor)return actor.hidden==true end,untargetable=function(actor)return actor.outOfReach==true end})
assert(staged.arena:spawn('/Catalog/BP_LengTu.BP_LengTu_C','blue',1).ok)
assert(staged.arena:spawn('/Catalog/BP_Enemy.BP_Enemy_C','red',1).ok)
local lengtu,enemy=staged.actors[1],staged.actors[2]
lengtu.outOfReach=true
local doll={alive=true,name='doll',hp=100,hidden=true}
assert(staged.arena:adoptSummon(doll,lengtu,'/Catalog/BP_Doll.BP_Doll_C','fixture').ok)
local s=staged.arena:status()
assert(s.blue_count==1 and s.reserve_count==1 and s.summon_count==1,'a hidden doll is owned but not counted alive')
assert(staged.arena:start().ok)
for _,event in ipairs(staged.trace)do
    if type(event)=='table' and event[1]=='attack' then
        assert(event[2]~=doll and event[3]~=doll,'a reserve doll is neither sent nor sent at')
        assert(event[3]~=lengtu,'nobody is sent at her while she is out of reach')
    end
end
assert(stageCount(staged,'attack')==1,'she is still sent at the enemy')
staged.arena:tickReinforcements()
assert(stageCount(staged,'attack')==1,'the enemy waits: no reachable opponent')
for _,member in ipairs(staged.arena:members())do
    if member.actor==doll then assert(member.reserve==true) end
    if member.actor==lengtu then assert(member.untargetable==true) end
end
local scav={alive=true,name='scavenger',hp=100}
assert(staged.arena:adoptSummon(scav,lengtu,'/Catalog/BP_Scav.BP_Scav_C','fixture').ok)
staged.arena:tickReinforcements()
local sentAtScav=false
for _,event in ipairs(staged.trace)do
    if type(event)=='table' and event[1]=='attack' and event[2]==enemy and event[3]==scav then sentAtScav=true end
end
assert(sentAtScav,'the enemy fights her summon')
scav.hp=0
doll.hidden=false
staged.arena:tickReinforcements()
local s2=staged.arena:status()
assert(s2.reserve_count==0 and s2.blue_count==2,'a doll she brings out counts again')
local sentAtDoll=false
for _,event in ipairs(staged.trace)do
    if type(event)=='table' and event[1]=='attack' and event[2]==enemy and event[3]==doll then sentAtDoll=true end
end
assert(sentAtDoll,'the doll she brings out is fought')
doll.hp=0
staged.arena:tickReinforcements()
lengtu.outOfReach=false
local before=stageCount(staged,'attack')
staged.arena:tickReinforcements()
assert(stageCount(staged,'attack')>before,'once she comes down she can be fought')
-- The AI's targeting fallback (Last Sensed Actor) is kept on each fighter's opponent, every tick and after a
-- perception event; with no opponent alive it is passed nil (only taken off the player).
local holds={}
local fallback=fixture({holdTarget=function(actor,target,why)holds[#holds+1]={actor=actor,target=target,why=why};return true end})
assert(fallback.arena:spawn(nil,'blue',1).ok and fallback.arena:spawn(nil,'red',1).ok and fallback.arena:start().ok)
local fa,fb=fallback.actors[1],fallback.actors[2]
fallback.arena:tickReinforcements()
local function heldFor(actor)
    for i=#holds,1,-1 do if holds[i].actor==actor then return holds[i] end end
end
assert(heldFor(fa).target==fb and heldFor(fb).target==fa and heldFor(fa).why=='定时检查','each fighter is held on its opponent')
local before=#holds
assert(fallback.arena:holdSensed(tostring(fa)) and #holds==before+1 and holds[#holds].why=='感知更新后' and holds[#holds].target==fb)
assert(not fallback.arena:holdSensed('nobody'),'an unknown unit is ignored')
fb.hp=0
fallback.arena:tickReinforcements()
assert(heldFor(fa).target==nil,'no opponent alive: nil, so it is only taken off the player')
-- The opponent a unit's skill gets instead of the player (player_aim.lua): its assigned target while alive, else
-- a living shown unit of the other side; nil for nobody of ours or with nobody left.
local foes=fixture()
assert(foes.arena:spawn(nil,'blue',1).ok and foes.arena:spawn(nil,'red',2).ok and foes.arena:start().ok)
local fb1,fr1,fr2=foes.actors[1],foes.actors[2],foes.actors[3]
assert(foes.arena:actorOf(tostring(fb1))==fb1 and foes.arena:actorOf('nobody')==nil)
assert(foes.arena:opponentOf(tostring(fb1))==fr1,'the assigned target')
fr1.hp=0
local other=foes.arena:opponentOf(tostring(fb1))
assert(other==fr2,'the assigned one dead: another living enemy')
fr2.hp=0
assert(foes.arena:opponentOf(tostring(fb1))==nil and foes.arena:opponentOf('nobody')==nil)
-- Out of reach only after she was assigned: the attacker is taken off her and waits.
local held=fixture({untargetable=function(actor)return actor.outOfReach==true end})
assert(held.arena:spawn('/Catalog/BP_LengTu.BP_LengTu_C','blue',1).ok and held.arena:spawn(nil,'red',1).ok)
assert(held.arena:start().ok and stageCount(held,'attack')==2)
held.actors[1].outOfReach=true
held.arena:tickReinforcements()
held.arena:tickReinforcements()
assert(stageCount(held,'attack')==2,'no new order while nobody is in reach, and none repeated')
held.actors[1].outOfReach=false
held.arena:tickReinforcements()
assert(stageCount(held,'attack')==3,'sent at her again when she is back in reach')
local unlimited=fixture({maxUnits=0})
for _=1,4 do assert(unlimited.arena:spawn(nil,'blue',8).ok) end
assert(unlimited.arena:status().total==32 and unlimited.arena:status().max_units==0)
assert(unlimited.arena:spawn(nil,'neutral',2).ok)
local restoresBefore=stageCount(unlimited,'restore')
assert(unlimited.arena:clearNeutral().ok)
assert(unlimited.arena:status().blue_count==32 and unlimited.arena:status().neutral_count==0)
assert(stageCount(unlimited,'restore')==restoresBefore,'neutral cleanup must not reset blue/red battles')
local death=fixture()
assert(death.arena:spawn(nil,'blue',1).ok)
death.actors[1].hp=0
local deadState=death.arena:status()
assert(deadState.blue_count==0 and deadState.dead_count==1 and deadState.owned_records==1,'HP zero must leave live counts immediately without dropping cleanup ownership')
death.actors[1].hp=400
assert(death.arena:status().blue_count==1,'a revived phase must be counted again')
death.actors[1].hp=0
assert(death.arena:stop().ok and death.arena:status().owned_records==0,'dead actors must remain cleanable')
local limited=fixture({maxUnits=2})
assert(limited.arena:spawn('/Catalog/BP_A.BP_A_C','blue',1).ok)
assert(limited.arena:spawn('/Catalog/BP_B.BP_B_C','red',1).ok)
local beforeLimit=stageCount(limited,'resolve')
assert(not limited.arena:spawn('/Catalog/BP_C.BP_C_C','blue',1).ok)
assert(stageCount(limited,'resolve')==beforeLimit and #limited.actors==2,'total trial limit applies across different classes before loading')
assert(f.arena:status().current_team == "blue" and f.arena:status().current_count == 1)
local blue = f.arena:spawn("/Catalog/BP_A.BP_A_C", "blue", 2)
assert(blue.ok and blue.spawned_count == 2 and blue.activated_count == 2)
assert(stageCount(f,'refresh')==0 and f.trace[3]=='resolve','resolve the selected path directly without discovery')
assert(not f.arena:start().ok, "one team cannot start a battle")
local red = f.arena:spawn("/Catalog/BP_B.BP_B_C", "red", 2)
assert(red.ok and f.arena:status().total == 4)
local positions = {}
for _, transform in ipairs(f.transforms) do
    local p = transform.Translation
    local key = p.X .. "," .. p.Y .. "," .. p.Z
    assert(not positions[key], "spawn slots must be distinct")
    positions[key] = true
    assert(p.X >= 600 and p.Z == 150, "horizontal forward vector must be normalized")
end
assert(f.arena:start().ok)
local relationCount, attackCount, observeCount = 0, 0, 0
local owned, teams = {}, {}
for _, unit in ipairs(f.synced()) do owned[unit.actor], teams[unit.actor] = true, unit.team end
for _, event in ipairs(f.trace) do
    if type(event) == "table" then
        if event[1] == "relation" then
            relationCount = relationCount + 1
            assert(event[3] ~= f.player, 'starting a battle must not silently grant no-aggro while F8 is off')
            assert(owned[event[2]] and (event[3] == f.player or owned[event[3]]))
            if event[4] == 2 then assert(teams[event[2]] ~= teams[event[3]]) end
        elseif event[1] == "attack" then
            attackCount = attackCount + 1
            assert(owned[event[2]] and owned[event[3]] and teams[event[2]] ~= teams[event[3]])
        elseif event[1] == "observe" then observeCount = observeCount + 1 end
    end
end
assert(relationCount == 4 and attackCount == 4 and observeCount == 1)
local cleanup = f.arena:stop()
assert(cleanup.ok and cleanup.remaining_count == 0 and f.arena:status().total == 0)
local restoreIndex, destroyIndex
for i, event in ipairs(f.trace) do
    if event == "restore" then restoreIndex = i end
    if event == "destroy" and not destroyIndex then destroyIndex = i end
end
assert(restoreIndex < destroyIndex)

f = fixture()
assert(not f.arena:select("/Catalog/X.X_C", "red", 101).ok and f.arena:select("/Catalog/X.X_C", "red", 50).ok)
assert(not f.arena:spawn(nil, "invalid", 1).ok and #f.actors == 0)
assert(not f.arena:spawn(nil, "blue", 1.5).ok)
for _ = 1, 3 do assert(f.arena:spawn(nil, "blue", 8).ok) end
assert(f.arena:status().total == 24)
assert(not f.arena:spawn(nil, "red", 1).ok and #f.actors == 24)

f = fixture()
local originalSpawn, originalActivate, spawnCalls = f.options.spawnClass, f.options.activate, 0
f.options.spawnClass = function(...)
    spawnCalls = spawnCalls + 1
    if spawnCalls == 2 then return nil, "failed before native spawn", "not_started" end
    return originalSpawn(...)
end
f.options.activate = function(actor)
    originalActivate(actor)
    if spawnCalls == 3 then return false, "activation rejected" end
    return true
end
local partial = f.arena:spawn(nil, "blue", 3)
assert(not partial.ok and partial.spawned_count == 2 and partial.activated_count == 1)
assert(f.arena:status().total == 2)
assert(f.arena:stop().ok)

-- A valid returned actor with a warning still belongs to us, but is not full success.
f = fixture()
local spawnWithWarning = f.options.spawnClass
f.options.spawnClass = function(...)
    local actor = spawnWithWarning(...)
    return actor, "finish-spawn readback not fully confirmed"
end
local warningResult = f.arena:spawn(nil, "blue", 1)
assert(not warningResult.ok and warningResult.spawned_count == 1 and warningResult.failure_count == 1
    and warningResult.activated_count == 1)
assert(f.arena:status().owned_records == 1 and #f.synced() == 1)
assert(f.arena:stop().ok and f.arena:status().total == 0, "warning actors must remain available for owned cleanup")

-- Policy rejection must happen before any catalog loading or game generation.
for _, mode in ipairs({ "denied", "missing", "throws", "non_boolean" }) do
    f = fixture()
    if mode == "denied" then f.options.canSpawn = function() return false, "not verified" end
    elseif mode == "missing" then f.options.canSpawn = nil
    elseif mode == "throws" then f.options.canSpawn = function() error("policy unavailable") end
    else f.options.canSpawn = function() return "true" end end
    local selection = f.arena:select("/Catalog/BP_Unverified.BP_Unverified_C", "blue", 1)
    local refused = f.arena:spawn("/Catalog/BP_Unverified.BP_Unverified_C", "blue", 1)
    assert(not selection.ok and not refused.ok and refused.spawned_count == 0, mode)
    assert(stageCount(f, "refresh") == 0 and stageCount(f, "resolve") == 0 and stageCount(f, "spawn") == 0,
        mode .. ": denied choices must not reach refresh, class resolve, or generation")
    assert(#f.actors == 0 and f.arena:status().owned_records == 0)
end

-- Always check the actual selected path even if the catalog has changed independently.
local allowedPath, blockedPath = "/Catalog/BP_Allowed.BP_Allowed_C", "/Catalog/BP_Unverified.BP_Unverified_C"
local checkedPaths = {}
f = fixture({ canSpawn = function(path)
    checkedPaths[#checkedPaths + 1] = path
    return path == allowedPath, "not verified"
end })
assert(f.arena:select(allowedPath, "blue", 1).ok)
f.catalog.selectedPath=blockedPath
local changedSelection = f.arena:spawn()
assert(not changedSelection.ok and changedSelection.spawned_count == 0)
assert(checkedPaths[#checkedPaths] == blockedPath, "policy must inspect the actual catalog selection")
assert(stageCount(f, "refresh") == 0 and stageCount(f, "resolve") == 0 and stageCount(f, "spawn") == 0)
assert(#f.actors == 0)

-- Missing player/world during startup must stop before asset refresh/resolve.
for _, invalidObject in ipairs({ "player", "world" }) do
    f = fixture()
    f[invalidObject].alive = false
    local unavailable = f.arena:spawn("/Catalog/BP_A.BP_A_C", "blue", 1)
    assert(not unavailable.ok and unavailable.spawned_count == 0)
    assert(stageCount(f, "refresh") == 0 and stageCount(f, "resolve") == 0 and stageCount(f, "spawn") == 0,
        invalidObject .. ": no catalog or generation side effects are allowed while loading")
    assert(#f.actors == 0)
end

f = fixture()
function f.catalog:resolveSelected()
    f.trace[#f.trace + 1] = "resolve"
    f.world.alive = false -- The world can disappear during a class-load operation.
    return f.cls
end
assert(not f.arena:spawn().ok and stageCount(f, "resolve") == 1 and stageCount(f, "spawn") == 0)

f = fixture()
f.player.alive = false
assert(not f.arena:spawn().ok and #f.actors == 0)
f.player.alive, f.world.alive = true, false
assert(not f.arena:spawn().ok and #f.actors == 0)
f.world.alive, f.cls.alive = true, false
assert(not f.arena:spawn().ok and #f.actors == 0)

f = fixture()
assert(f.arena:spawn().ok)
f.options.destroy = function() return true end -- engine accepted request, actor is still live
local pending = f.arena:stop()
assert(not pending.ok and pending.remaining_count == 1 and f.arena:status().state == "cleanup_pending")
f.options.destroy = function(actor) actor.alive = false end
assert(f.arena:stop().ok and f.arena:status().total == 0)

-- A failed cleanup must block the next spawn/start, including an eight-unit batch.
f = fixture()
assert(f.arena:spawn(nil, "blue", 4).ok and f.arena:spawn(nil, "red", 4).ok)
f.options.destroy = function() return true end
assert(not f.arena:stop().ok and f.arena:status().state == "cleanup_pending")
local beforeBlockedRefresh, beforeBlockedResolve, beforeBlockedSpawn =
    stageCount(f, "refresh"), stageCount(f, "resolve"), stageCount(f, "spawn")
local blockedSpawn = f.arena:spawn("/Catalog/BP_New.BP_New_C", "blue", 1)
assert(not blockedSpawn.ok and blockedSpawn.spawned_count == 0)
assert(not f.arena:start().ok)
assert(stageCount(f, "refresh") == beforeBlockedRefresh and stageCount(f, "resolve") == beforeBlockedResolve
    and stageCount(f, "spawn") == beforeBlockedSpawn, "pending cleanup must stop before refresh, resolve or generation")
assert(stageCount(f, "relation") == 0 and stageCount(f, "attack") == 0 and stageCount(f, "observe") == 0)
assert(#f.actors == 8 and f.arena:status().owned_records == 8 and f.arena:status().state == "cleanup_pending")
f.options.destroy = function(actor) actor.alive = false end
assert(f.arena:stop().ok)
assert(f.arena:spawn(nil, "blue", 1).ok, "confirmed cleanup should permit the next spawn")

-- Restoration is a separate gate even after every owned actor has been destroyed.
f = fixture()
assert(f.arena:spawn(nil, "blue", 1).ok and f.arena:spawn(nil, "red", 1).ok)
f.options.restore = function() return false end
assert(not f.arena:stop().ok and f.arena:status().state == "restore_pending" and f.arena:status().total == 0)
local restoreBlockedRefresh, restoreBlockedResolve, restoreBlockedSpawn =
    stageCount(f, "refresh"), stageCount(f, "resolve"), stageCount(f, "spawn")
assert(not f.arena:spawn("/Catalog/BP_New.BP_New_C", "red", 1).ok and not f.arena:start().ok)
assert(stageCount(f, "refresh") == restoreBlockedRefresh and stageCount(f, "resolve") == restoreBlockedResolve
    and stageCount(f, "spawn") == restoreBlockedSpawn)
assert(stageCount(f, "relation") == 0 and stageCount(f, "attack") == 0 and stageCount(f, "observe") == 0)
assert(f.arena:status().state == "restore_pending")
f.options.restore = function() return true end
assert(f.arena:stop().ok and f.arena:status().state == "idle")

-- Check all combatants before issuing even the first relationship/attack write.
for _, failure in ipairs({ "hp_zero", "hp_negative", "hp_nil", "hp_nan", "hp_infinite",
    "hp_string", "hp_error", "ai_false", "ai_missing", "ai_string", "ai_error" }) do
    f = fixture()
    assert(f.arena:spawn(nil, "blue", 2).ok and f.arena:spawn(nil, "red", 1).ok)
    local lastCombatant = f.actors[3]
    local inspectedHP = {}
    f.options.hp = function(actor)
        inspectedHP[#inspectedHP + 1] = actor
        if actor ~= lastCombatant then return 400 end
        if failure == "hp_zero" then return 0 end
        if failure == "hp_negative" then return -1 end
        if failure == "hp_nil" then return nil end
        if failure == "hp_nan" then return 0 / 0 end
        if failure == "hp_infinite" then return math.huge end
        if failure == "hp_string" then return "400" end
        if failure == "hp_error" then error("HP read unavailable") end
        return 400
    end
    if failure == "ai_missing" then f.options.combatReady = nil
    else
        f.options.combatReady = function(actor)
            if actor ~= lastCombatant then return true end
            if failure == "ai_false" then return false end
            if failure == "ai_string" then return "true" end
            if failure == "ai_error" then error("combat AI read unavailable") end
            return true
        end
    end
    local refusedBattle = f.arena:start()
    assert(not refusedBattle.ok, failure .. ": unverified combatant must block battle")
    assert(stageCount(f, "relation") == 0 and stageCount(f, "attack") == 0 and stageCount(f, "observe") == 0,
        failure .. ": a healthy earlier combatant must not receive partial battle writes")
    assert(f.arena:status().owned_records == 3, "failed combat preflight must preserve owned cleanup records")
    if failure ~= "ai_missing" then
        assert(inspectedHP[#inspectedHP] == lastCombatant, "the failing last combatant must have been checked")
    end
end

-- UE can keep the UObject valid after the Actor has entered destruction.
f = fixture({
    isDestroying = function(actor) return actor.destroying == true end,
    destroy = function(actor) actor.destroying = true; return true end,
})
assert(f.arena:spawn().ok)
local destroyingActor = f.actors[1]
local destroyingCleanup = f.arena:stop()
assert(destroyingActor.alive == true, "the regression must not rely on IsValid turning false")
assert(destroyingCleanup.ok and destroyingCleanup.destroyed_count == 1 and destroyingCleanup.remaining_count == 0)
local destroyingStatus = f.arena:status()
assert(destroyingStatus.state == "idle" and destroyingStatus.total == 0 and destroyingStatus.owned_records == 0)
assert(#f.synced() == 0, "confirmed destruction must remove the actor from synchronized ownership")

-- A later status poll must finish pending cleanup without issuing Destroy again.
local delayedDestroyCalls = 0
f = fixture({
    isDestroying = function(actor) return actor.destroying == true end,
    destroy = function() delayedDestroyCalls = delayedDestroyCalls + 1; return true end,
})
assert(f.arena:spawn(nil, "red", 1).ok)
local delayedCleanup = f.arena:stop()
assert(not delayedCleanup.ok and delayedCleanup.remaining_count == 1)
local delayedBefore = f.arena:status()
assert(delayedBefore.state == "cleanup_pending" and delayedBefore.total == 1 and delayedBefore.owned_records == 1)
f.actors[1].destroying = true
local delayedAfter = f.arena:status()
assert(f.actors[1].alive == true and delayedDestroyCalls == 1)
assert(delayedAfter.state == "idle" and delayedAfter.total == 0 and delayedAfter.red_count == 0
    and delayedAfter.owned_records == 0 and #f.synced() == 0,
    "status must prune an actor whose destruction becomes observable after stop")

-- A failed/non-boolean destruction query cannot prove that an owned actor is gone.
f = fixture({
    isDestroying = function() error("destruction query unavailable") end,
    destroy = function(actor) actor.destroyRequested = true; return true end,
})
assert(not f.arena:spawn().ok and stageCount(f,'activate')==0,
    'unknown destruction state must prevent activation while retaining ownership')
local unknownDestruction = f.arena:stop()
assert(not unknownDestruction.ok and unknownDestruction.remaining_count == 1 and unknownDestruction.destroyed_count == 0)
local unknownDestructionStatus = f.arena:status()
assert(unknownDestructionStatus.state == "cleanup_pending" and unknownDestructionStatus.total == 0 and unknownDestructionStatus.unreadable_count==1
    and unknownDestructionStatus.owned_records == 1 and #f.synced() == 1,
    "a query exception must retain ownership rather than report cleanup success")
f.options.isDestroying = function() return "true" end
assert(f.arena:status().owned_records == 1, "a non-boolean query result is still unknown")
f.options.isDestroying = function() return true end
assert(f.arena:status().state == "idle" and f.arena:status().total == 0)

f = fixture()
assert(f.arena:spawn().ok)
f.options.restore = function() return false end
assert(not f.arena:stop().ok and f.arena:status().state == "restore_pending")
f.options.restore = function() return true end
assert(f.arena:stop().ok)

f = fixture()
assert(f.arena:spawn().ok)
local originalValid = f.options.valid
f.options.valid = function(object)
    if object == f.actors[1] then error("cannot read validity") end
    return originalValid(object)
end
assert(f.arena:status().unreadable_count == 1)
assert(not f.arena:stop().ok and f.arena:status().owned_records == 1, "unknown validity must retain ownership")
f.options.valid = originalValid
assert(f.arena:stop().ok)

f = fixture()
assert(f.arena:spawn().ok)
f.options.spawnClass = function() return f.actors[1] end
assert(not f.arena:spawn().ok and f.arena:status().total == 1, "duplicate actor must not gain second team/ownership")

f = fixture()
assert(f.arena:spawn(nil, "neutral", 1).ok)
assert(f.arena:status().neutral_count == 1 and not f.arena:start().ok)
assert(f.arena:spawn(nil, "blue", 1).ok and f.arena:spawn(nil, "red", 1).ok)
assert(f.arena:start().ok)
local neutralActor = f.actors[1]
for _, event in ipairs(f.trace) do
    if type(event) == "table" and event[1] == "attack" then assert(event[2] ~= neutralActor and event[3] ~= neutralActor) end
end
-- Companions follow the player: activation is told their team, they are counted apart,
-- a stop keeps them, and only their own clear removes them.
local c=fixture()
local activatedTeams={}
c.options.activate=function(actor,path,team) activatedTeams[#activatedTeams+1]=team;return true end
assert(c.arena:spawn('/Catalog/BP_Test.BP_Test_C','companion',2).ok)
assert(c.arena:spawn('/Catalog/BP_Test.BP_Test_C','blue',1).ok)
assert(activatedTeams[1]=='companion' and activatedTeams[2]=='companion' and activatedTeams[3]=='blue')
local cs=c.arena:status()
assert(cs.companion_count==2 and cs.companion_owned==2 and cs.blue_count==1 and cs.neutral_count==0 and cs.total==1)
local near=c.transforms[1].Translation
assert(math.abs(near.X)<=200 and math.abs(near.Y)==300,'companions appear beside the player')
local stopped=c.arena:stop()
assert(stopped.ok and stopped.remaining_count==0 and c.arena:status().state=='idle','stop finishes without waiting for companions')
assert(c.actors[1].alive and c.actors[2].alive and not c.actors[3].alive and c.arena:status().companion_count==2)
local dismissed=c.arena:clearCompanions()
assert(dismissed.ok and dismissed.destroyed_count==2 and not c.actors[1].alive and c.arena:status().companion_owned==0)

-- A batch of 50: allowed, every slot distinct, laid out in rows of five within about 33 m ahead and
-- 16 m to the side; a single no-team unit still appears straight ahead.
local big=fixture({maxUnits=0})
local bigResult=big.arena:spawn(nil,'blue',50)
assert(bigResult.ok and bigResult.spawned_count==50 and big.arena:status().blue_count==50,bigResult.message)
local seenSlots={}
for _,transform in ipairs(big.transforms)do
    local p=transform.Translation
    local key=p.X..','..p.Y
    assert(not seenSlots[key],'50 slots must be distinct');seenSlots[key]=true
    assert(p.X>=600 and p.X<=600+9*300 and p.Y<=-360 and p.Y>=-(360+4*300),'blue rows of five on the left: '..key)
end
assert(not big.arena:spawn(nil,'red',101).ok,'more than 100 in one summon is refused')
local solo=fixture()
assert(solo.arena:spawn(nil,'neutral',1).ok and solo.transforms[1].Translation.Y==0,'one no-team unit straight ahead')

-- Facing: the player looks along +X (fixture forward), blue stands on -Y and red on +Y. Blue faces +Y (yaw 90),
-- red faces -Y (yaw -90), a no-team unit faces the player (yaw 180), a companion looks where the player does.
local function yawOf(transform)
    local r=transform.Rotation
    assert(r.X==0 and r.Y==0 and math.abs(r.Z*r.Z+r.W*r.W-1)<1e-9,'a pure yaw rotation')
    return math.deg(2*math.atan(r.Z,r.W))
end
local facing=fixture()
assert(facing.arena:spawn(nil,'blue',1).ok and facing.arena:spawn(nil,'red',1).ok)
assert(facing.arena:spawn(nil,'neutral',1).ok and facing.arena:spawn(nil,'companion',1).ok)
assert(facing.transforms[1].Translation.Y<0 and facing.transforms[2].Translation.Y>0)
assert(math.abs(yawOf(facing.transforms[1])-90)<1e-6,'blue faces red')
assert(math.abs(yawOf(facing.transforms[2])+90)<1e-6,'red faces blue')
assert(math.abs(math.abs(yawOf(facing.transforms[3]))-180)<1e-6,'a no-team unit faces the player')
assert(math.abs(yawOf(facing.transforms[4]))<1e-6,'a companion looks where the player does')

-- Safety net behind combat_lock.lua: every second a unit found out of combat (it walks home after a round)
-- is sent at its target again; units in combat are never forced. A unit whose target died goes for the
-- least attacked enemy.
do
    local t,combat,engaged=200,{},{}
    local r=fixture({now=function()return t end,
        inCombat=function(actor)local c=combat[actor]~=false;return c,c and 'AI.State.Combat' or 'AI.State.Idle' end,
        engage=function(actor,target)engaged[#engaged+1]={actor,target};return true,'AI.State.Combat' end})
    assert(r.arena:spawn(nil,'blue',3).ok and r.arena:spawn(nil,'red',2).ok and r.arena:start().ok)
    local b1,b2,b3,r1,r2=r.actors[1],r.actors[2],r.actors[3],r.actors[4],r.actors[5]
    r.arena:tickReinforcements()
    assert(#engaged==0,'units in combat are left alone')
    combat[b2]=false
    t=200.5;r.arena:tickReinforcements()
    assert(#engaged==0,'the safety net looks once a second')
    t=201;r.arena:tickReinforcements()
    assert(#engaged==1 and engaged[1][1]==b2 and engaged[1][2]==r2,'b2 is sent back at its own target (round robin gave it r2)')
    t=201.5;r.arena:tickReinforcements()
    assert(#engaged==1)
    t=202;r.arena:tickReinforcements()
    assert(#engaged==2 and engaged[2][1]==b2)
    combat[b2]=nil;t=206;r.arena:tickReinforcements()
    assert(#engaged==2,'back in combat: not forced again')
    -- r1 dies: b1 and b3 (both sent at r1) take the least attacked enemy, which is r2.
    r1.hp=0;t=207
    local attacks=stageCount(r,'attack')
    r.arena:tickReinforcements()
    assert(stageCount(r,'attack')==attacks+2,'both attackers of the fallen enemy get a new target')
    local last=r.trace[#r.trace]
    assert(last[1]=='attack' and last[3]==r2)
    -- Instant send-back by key: the unit goes at its live target; unknown keys, dead targets, the
    -- stopped arena are refused.
    local before=#engaged
    assert(r.arena:reengage(tostring(b2)) and #engaged==before+1 and engaged[#engaged][1]==b2 and engaged[#engaged][2]==r2)
    assert(not r.arena:reengage('nobody') and not r.arena:reengage(nil))
    r2.hp=0;assert(not r.arena:reengage(tostring(b2)),'its target is down')
    assert(r.arena:stop().ok and not r.arena:reengage(tostring(b1)),'no fight, no send-back')
end

-- A unit the game's fall safety froze in the air is looked at once a second, in or out of combat, with its target.
do
    local t,looked=300,{}
    local r=fixture({now=function()return t end,inCombat=function()return true,'AI.State.Combat' end,engage=function()return true,'AI.State.Combat' end,
        unstick=function(actor,target)looked[#looked+1]={actor,target};return false end})
    assert(r.arena:spawn(nil,'blue',1).ok and r.arena:spawn(nil,'red',1).ok and r.arena:start().ok)
    r.arena:tickReinforcements()
    assert(#looked==2 and looked[1][1]==r.actors[1] and looked[1][2]==r.actors[2] and looked[2][1]==r.actors[2] and looked[2][2]==r.actors[1],'each with its opponent')
    t=300.5;r.arena:tickReinforcements();assert(#looked==2,'once a second')
    t=301;r.arena:tickReinforcements();assert(#looked==4)
    assert(r.arena:stop().ok)
end

-- Battle clock in game seconds: runs once both sides stand after the start, stops when one side has
-- nobody alive or unreadable, starts over when the beaten side gets new units, and stop clears it.
local now=100
local k=fixture({now=function()return now end})
assert(k.arena:status().battle_clock=='' and k.arena:status().battle_seconds==0,'no clock before a fight')
assert(k.arena:spawn(nil,'blue',1).ok and k.arena:spawn(nil,'red',2).ok)
now=103;assert(k.arena:status().battle_clock=='','summoning alone does not start the clock')
assert(k.arena:start().ok)
now=105;local ks=k.arena:status()
assert(ks.battle_clock=='running' and ks.battle_seconds==0,'the clock starts at the first status after the start')
now=110.5;assert(k.arena:status().battle_seconds==5.5)
k.actors[2].hp=0;now=112;assert(k.arena:status().battle_clock=='running','one red still stands')
k.options.valid=function(object)
    if object==k.actors[3] then error('unreadable') end
    return object~=nil and object.alive==true
end
k.actors[3].hp=0;now=114
assert(k.arena:status().battle_clock=='running','an unreadable unit does not end the fight')
k.options.valid=function(object)return object~=nil and object.alive==true end
now=117;ks=k.arena:status()
assert(ks.battle_clock=='ended' and ks.battle_seconds==12,'red wiped out at 117, 12 s after 105')
now=130;assert(k.arena:status().battle_seconds==12,'an ended fight keeps its time')
assert(k.arena:spawn(nil,'red',1).ok)
now=131;ks=k.arena:status()
assert(ks.battle_clock=='running' and ks.battle_seconds==0,'new units on the beaten side start a new fight')
assert(k.arena:stop().ok and k.arena:status().battle_clock=='','stop clears the clock')
local noClock=fixture()
assert(noClock.arena:spawn(nil,'blue',1).ok and noClock.arena:spawn(nil,'red',1).ok and noClock.arena:start().ok)
assert(noClock.arena:status().battle_clock=='','without a game clock nothing is timed')
-- Escorts (escorts.lua): a 驯犬客 comes with two 狂犬 on his team, after him, each with him as its leader.
local TAMER,DOG='/Catalog/BP_Tamer.BP_Tamer_C','/Catalog/BP_Dog.BP_Dog_C'
local function escortFixture(overrides)
    local dogCls,dogEntry={alive=true},{path=DOG,isNPC=true}
    local e
    local options={
        escortsFor=function(path)if path==TAMER then return {{path=DOG,count=2}} end end,
        resolveEscort=function(path)assert(path==DOG);e.trace[#e.trace+1]='resolve_escort';return dogCls,nil,dogEntry end,
        spawnClass=function(c,transform,w,given)
            assert(w==e.world and (c==e.cls and given==nil or c==dogCls and given==dogEntry),'an escort is spawned with its own entry')
            e.trace[#e.trace+1]=c==dogCls and 'spawn_escort' or 'spawn'
            e.transforms[#e.transforms+1]=transform
            local actor={alive=true,name=(c==dogCls and 'dog' or 'unit')..(#e.actors+1)}
            e.actors[#e.actors+1]=actor
            return actor
        end,
        finishSpawn=function(actor,transform,w,leader)e.leaders[actor]=leader or false;return true end,
        activate=function(actor,path,team,escort)e.activated[#e.activated+1]={actor=actor,path=path,team=team,escort=escort};return true end,
    }
    for key,value in pairs(overrides or {})do options[key]=value end
    e=fixture(options);e.leaders,e.activated,e.dogCls={}, {},dogCls
    return e
end
local pack=escortFixture()
local packResult=pack.arena:spawn(TAMER,'red',1)
assert(packResult.ok and packResult.spawned_count==1 and packResult.escort_count==2 and packResult.failure_count==0,packResult.message)
assert(packResult.message:find('随行单位 2/2',1,true))
assert(stageCount(pack,'spawn')==1 and stageCount(pack,'spawn_escort')==2 and stageCount(pack,'resolve_escort')==1)
local tamer=pack.actors[1]
assert(pack.leaders[tamer]==false and pack.leaders[pack.actors[2]]==tamer and pack.leaders[pack.actors[3]]==tamer,'escorts finish with the tamer as leader')
assert(not pack.activated[1].escort and pack.activated[2].escort and pack.activated[3].escort and pack.activated[2].path==DOG)
local packStatus=pack.arena:status()
assert(packStatus.red_count==3 and packStatus.summon_count==0 and packStatus.current_unit==TAMER,'dogs are red members, not native summons; the selection stays')
local slots={}
for _,unit in ipairs(pack.synced())do assert(unit.team=='red');slots[#slots+1]=unit.class_path end
assert(slots[1]==TAMER and slots[2]==DOG and slots[3]==DOG)
assert(pack.transforms[2].Translation.Y~=pack.transforms[1].Translation.Y,'each dog takes the next free slot')
-- Two tamers: each is followed by his own dogs.
local packs=escortFixture()
local packsResult=packs.arena:spawn(TAMER,'blue',2)
assert(packsResult.ok and packsResult.spawned_count==2 and packsResult.escort_count==4)
assert(packs.leaders[packs.actors[2]]==packs.actors[1] and packs.leaders[packs.actors[5]]==packs.actors[4])
-- Other units bring nobody.
local plain=escortFixture()
local plainResult=plain.arena:spawn('/Catalog/BP_Test.BP_Test_C','blue',1)
assert(plainResult.ok and plainResult.escort_count==0 and stageCount(plain,'resolve_escort')==0 and not plainResult.message:find('随行',1,true))
-- A dog class that does not resolve: the tamer stays, the failure is reported, nothing is guessed.
local lone=escortFixture({resolveEscort=function()return nil,'not found' end})
local loneResult=lone.arena:spawn(TAMER,'red',1)
assert(not loneResult.ok and loneResult.spawned_count==1 and loneResult.escort_count==0 and loneResult.failure_count==1)
assert(loneResult.message:find('随行单位 0/2',1,true) and lone.arena:status().red_count==1)
-- A dog that fails to activate is kept for cleanup and stops the batch, like any unit.
local bitten=escortFixture({activate=function(actor,path,team,escort)return not escort end})
local bittenResult=bitten.arena:spawn(TAMER,'red',2)
assert(not bittenResult.ok and bittenResult.spawned_count==1 and bittenResult.escort_count==1)
assert(bitten.arena:status().state=='cleanup_pending' and bitten.arena:status().red_count==2)
-- A stand is a skill participant even when shown; it keeps damage relations and cleanup ownership.
do
    local logs,engaged,held={},0,0
    local f=fixture({isStand=function(actor)return actor.stand==true,'fixture tag' end,
        dormant=function(actor)return actor.hidden==true end,now=function()return 10 end,
        inCombat=function()return false,'None' end,
        engage=function(actor)assert(not actor.stand);engaged=engaged+1;return true end,
        holdTarget=function(actor,target)assert(not actor.stand and not (target and target.stand));held=held+1 end,
        log=function(s)logs[#logs+1]=s end})
    assert(f.arena:spawn(nil,'blue',1).ok and f.arena:spawn(nil,'red',1).ok)
    local owner,enemy=f.actors[1],f.actors[2]
    local stand={alive=true,name='stand',hp=100,stand=true,hidden=true}
    assert(f.arena:adoptSummon(stand,owner,'/Catalog/BP_Stand.BP_Stand_C','fixture').ok)
    assert(f.arena:status().blue_count==1,'a stand is not a separate survivor')
    assert(f.arena:start().ok)
    stand.hidden=false
    f.arena:tickReinforcements()
    local s=f.arena:status()
    assert(s.blue_count==1 and s.stand_count==1 and s.reserve_count==0,'shown stands remain skill participants')
    local relation=false
    for _,event in ipairs(f.trace)do
        if type(event)=='table' and event[1]=='attack' then assert(event[2]~=stand and event[3]~=stand) end
        if type(event)=='table' and event[1]=='relation' and (event[2]==stand or event[3]==stand) then relation=true end
    end
    assert(relation and engaged==2 and held==2,'damage relations survive without autonomous stand control')
    assert(not f.arena:reengage(tostring(stand)) and not f.arena:holdSensed(tostring(stand)))
    assert(f.arena:opponentOf(tostring(stand))==enemy,'stand skills use their summoner opponent')
    local members=f.arena:members()
    assert(members[3].stand==true and members[3].summoner==owner)
    owner.hp=0
    assert(f.arena:opponentOf(tostring(enemy))==nil,'neither assigned nor nearest fallback can pick a stand')
    assert(f.arena:opponentOf(tostring(stand))==nil,'a dead summoner has no opponent')
    assert(f.arena:status().battle_clock=='ended','an invulnerable stand cannot keep its side alive')
    assert(table.concat(logs,'\n'):find('替身身份读回',1,true),'role change and evidence are logged')
    assert(f.arena:stop().ok and not stand.alive,'stands remain owned for cleanup')
end

-- A skill asking for "the player" is never left with the real one because its only opponent is out of reach for now,
-- nor because the caster itself has just gone down; only a stand's answer depends on its summoner being alive. A stand is
-- reserve to the modules that pick who takes part (executions, combos), and a unit that never was a summon is not asked.
do
    local asked=0
    local f=fixture({isStand=function(actor)asked=asked+1;return actor.stand==true end,
        untargetable=function(actor)return actor.offstage==true end})
    assert(f.arena:spawn(nil,'blue',1).ok and f.arena:spawn(nil,'red',1).ok and f.arena:start().ok)
    local blue,red=f.actors[1],f.actors[2]
    f.arena:tickReinforcements()
    f.arena:status()
    f.arena:opponentOf(tostring(blue))
    assert(asked==0,'not a summon: not asked')
    red.offstage=true
    assert(f.arena:opponentOf(tostring(blue))==red,'out of reach is still who it fights')
    f.arena:tickReinforcements()
    assert(f.arena:opponentOf(tostring(blue))==red,'also once it is no longer sent at her')
    red.offstage=false
    local stand={alive=true,name='stand',hp=100,stand=true}
    assert(f.arena:adoptSummon(stand,blue,'/Catalog/BP_Stand.BP_Stand_C','fixture').ok)
    local members=f.arena:members()
    assert(members[3].stand==true and members[3].reserve==true,'stands stay out of what picks fighters')
    blue.hp=0
    assert(f.arena:opponentOf(tostring(blue))==red,'its bullets still in flight keep their target')
    assert(f.arena:opponentOf(tostring(stand))==nil)
end

-- A summon that is an ordinary fighter is asked now and then, not on each answer to a hook.
do
    local asked=0
    local f=fixture({isStand=function(actor)asked=asked+1;return actor.stand==true end})
    assert(f.arena:spawn(nil,'blue',1).ok and f.arena:spawn(nil,'red',1).ok and f.arena:start().ok)
    local helper={alive=true,name='helper',hp=100}
    assert(f.arena:adoptSummon(helper,f.actors[2],'/Catalog/BP_Helper.BP_Helper_C','fixture').ok)
    f.arena:status()
    asked=0
    for _=1,50 do f.arena:opponentOf(tostring(helper)) end
    assert(asked<=1,'asked '..asked..' times')
end

-- An assigned opponent that died is not "out of reach by design".
do
    local logs={}
    local f=fixture({isStand=function()return false end,log=function(s)logs[#logs+1]=s end})
    assert(f.arena:spawn(nil,'blue',1).ok and f.arena:spawn(nil,'red',1).ok and f.arena:start().ok)
    f.arena:tickReinforcements()
    f.actors[2].hp=0
    f.arena:tickReinforcements()
    assert(not table.concat(logs,'\n'):find('暂不迎敌',1,true),table.concat(logs,'\n'))
end

do
    local f=fixture({isStand=function(actor)return actor.stand==true end})
    assert(f.arena:spawn(nil,'blue',1).ok and f.arena:spawn(nil,'red',1).ok and f.arena:start().ok)
    local stand={alive=true,name='late stand',hp=100,stand=true}
    assert(f.arena:adoptSummon(stand,f.actors[1],'/Catalog/BP_Stand.BP_Stand_C','fixture').ok)
    local before=stageCount(f,'attack')
    f.arena:tickReinforcements()
    assert(stageCount(f,'attack')==before,'a stand discovered mid-fight is not sent into autonomous combat')
    assert(f.arena:spawn(nil,'red',1).ok)
    local newcomer=f.actors[3]
    f.arena:tickReinforcements()
    local related=false
    for _,event in ipairs(f.trace)do
        if type(event)=='table' and event[1]=='relation' and event[2]==newcomer and event[3]==stand and event[4]==2 then related=true end
        if type(event)=='table' and event[1]=='attack' then assert(event[2]~=stand and event[3]~=stand) end
    end
    assert(related,'new enemy reinforcements still receive stand damage relations')
end
-- In the free camera a batch works from the origin it is given (spawn_spot.lua); with none it stays on the player.
do
    local asked={}
    local f = fixture({spawnOrigin=function(at,look,team,w)
        asked[#asked+1]={at=at,look=look,team=team,world=w}
        return {X=5000,Y=6000,Z=700},{X=0,Y=1,Z=0}
    end})
    assert(f.arena:spawn("/Catalog/BP_Test.BP_Test_C", "blue", 1).ok)
    assert(#asked==1 and asked[1].at.X==0 and asked[1].at.Z==100 and asked[1].look.X==2 and asked[1].team=="blue" and asked[1].world==f.world)
    local spot=f.transforms[1].Translation
    assert(spot.X==5000+360 and spot.Y==6000+600 and spot.Z==750,'origin + first row, facing the origin\'s way: '..spot.X..','..spot.Y..','..spot.Z)
    local kept = fixture({spawnOrigin=function()return nil end})
    assert(kept.arena:spawn("/Catalog/BP_Test.BP_Test_C", "blue", 1).ok)
    assert(kept.transforms[1].Translation.X==600,'no origin back: the player')
    local bad = fixture({spawnOrigin=function()error('boom')end})
    assert(bad.arena:spawn("/Catalog/BP_Test.BP_Test_C", "blue", 1).ok)
    assert(bad.transforms[1].Translation.X==600,'a failure is no reason not to summon')
end
print("arena_controller: PASS (spawn policy, loading gate, pending-cleanup gate, combat preflight, warning ownership, spacing, teams, caps, partial failures, cleanup retries, deferred destruction, unknown readbacks, escorts, stands)")
