local Spectator = dofile("Mods/PhantomGladiator/Scripts/spectator_mode.lua")
local serial = 0
local function object(properties)
    serial = serial + 1
    local id = serial
    local data = properties or {}
    data.alive = true
    data.IsValid = function(self) return self.alive end
    data.GetAddress = function(self) assert(self.alive, "invalid address read"); return id end
    return setmetatable(data, { __index = function(self, key)
        assert(self.alive, "invalid object accessed: " .. key)
        return nil
    end })
end
local function hatred(entries, canBeHatred)
    local list = entries or {}
    list.ForEach = function(self, callback)
        for index, actor in ipairs(self) do
            if callback(index, { get = function() return actor end }) == true then break end
        end
    end
    return object({ CanBeHatredNow = canBeHatred, HatredList = list,
        RemoveActorFromHatredList = function(self, target)
            assert(self.alive and target.alive)
            for i = #self.HatredList, 1, -1 do if self.HatredList[i] == target then table.remove(self.HatredList, i) end end
        end })
end
local function faction(natural, originalOverride)
    return object({ natural = natural, override = originalOverride,
        GetFactionRelation = function(self, target)
            assert(self.alive and target.alive)
            if self.override ~= nil then return self.override end
            return self.natural
        end,
        SetFactionRelationOverride = function(self, target, relation, both)
            assert(self.alive and target.alive and both == false, "must change NPC->player only")
            if self.rejectSet then return end
            self.override = relation
        end,
        ClearFactionRelationOverride = function(self, target)
            assert(self.alive and target.alive)
            if not self.rejectClear then self.override = nil end
        end })
end
local function fixture(config)
    local player = object({ BP_PBZHatredManagerComponent = hatred({}, true) })
    local otherNPC = object()
    local fc, hm = faction(2), hatred({ player, otherNPC }, true)
    local npc = object({ ["Faction Component"] = fc, BP_PBZHatredManagerComponent = hm })
    local npcs, logs, desired = { npc }, {}, {}
    local opts = { config = config or {}, log = function(s) logs[#logs + 1] = s end,
        getPlayer = function() return player end, getNPCs = function() return npcs end,
        getDesiredPlayerRelation = function(n, p) assert(p == player); return desired[n] end }
    return { mode = Spectator.new(opts), opts = opts, player = player, npc = npc, fc = fc, hm = hm,
        npcs = npcs, logs = logs, desired = desired, other = otherNPC }
end

local f = fixture()
local initial=f.mode:tick()
assert(initial.enabled_requested==false and initial.player_can_be_hatred_readback==true)
assert(f.fc.override==nil and #f.hm.HatredList==2,'initial off observation must not write neutrality or remove hatred')
f.player.BP_PBZHatredManagerComponent.CanBeHatredNow=false
local externallyDisabled=f.mode:tick()
assert(externallyDisabled.enabled_requested==false and externallyDisabled.player_can_be_hatred_readback==false,
    'requested off must not falsely report an externally disabled flag as enabled')
assert(externallyDisabled.pending_flags==0 and f.player.BP_PBZHatredManagerComponent.CanBeHatredNow==false)
f.player.BP_PBZHatredManagerComponent.CanBeHatredNow=true
local on = f.mode:setEnabled(true)
assert(on.enabled_requested and on.overrides_verified == 1 and on.removed_player_entries == 1)
assert(f.player.BP_PBZHatredManagerComponent.CanBeHatredNow == false)
assert(f.fc.override == 1 and #f.hm.HatredList == 1 and f.hm.HatredList[1] == f.other,
    "NPC-vs-NPC hatred must remain intact")
local newFC, newHM = faction(2), hatred({ f.player }, true)
f.npcs[#f.npcs + 1] = object({ ["Faction Component"] = newFC, BP_PBZHatredManagerComponent = newHM })
f.mode:tick()
assert(newFC.override == 1 and #newHM.HatredList == 0, "newly appearing NPC must be handled")
local off = f.mode:setEnabled(false)
assert(off.ok and not off.enabled_requested and off.pending_relations == 0 and off.pending_flags == 0)
assert(f.fc.override == nil and newFC.override == nil)
assert(f.player.BP_PBZHatredManagerComponent.CanBeHatredNow == true)
assert(off.player_can_be_hatred_readback == true, "off status must reflect restored player eligibility")
assert(off.override_structure_unknown == 2, "do not claim restoration of unknowable override structure")

f = fixture()
f.fc.override = 0 -- initial Friendly override, while natural relationship is Hostile
f.mode:on(); local restored = f.mode:off()
assert(restored.ok and f.fc.override == 0 and f.fc:GetFactionRelation(f.player) == 0)
assert(restored.effective_restored == 1 and restored.override_structure_unknown == 1)
assert(table.concat(f.logs, "\n"):find("原覆盖结构未知", 1, true))

f = fixture()
f.player.BP_PBZHatredManagerComponent.CanBeHatredNow = false
f.mode:on(); f.mode:off()
assert(f.player.BP_PBZHatredManagerComponent.CanBeHatredNow == false, "restore original bool, not an assumed true")

f = fixture()
f.mode:on()
f.desired[f.npc] = 1 -- arena takes over neutrality while spectator is enabled
local arenaOff = f.mode:off()
assert(arenaOff.ok and arenaOff.arena_preserved == 1 and f.fc.override == 1)

f = fixture()
f.fc.override = 1 -- existing Neutral relation was never written by spectator
f.mode:on(); local existing = f.mode:off()
assert(existing.pending_relations == 0 and f.fc.override == 1)

f = fixture()
f.mode:on(); f.fc.rejectClear, f.fc.rejectSet = true, true
local pending = f.mode:off()
assert(not pending.ok and pending.pending_relations == 1 and pending.readFailures > 0)
f.fc.rejectSet = false
local retried = f.mode:tick()
assert(retried.pending_relations == 0 and f.fc.override == 2, "off retry must not leave a formerly hostile NPC permanently neutral")

f = fixture({ BatchSize = 1 })
local fc2, fc3 = faction(2), faction(2)
f.npcs[2] = object({ ["Faction Component"] = fc2, BP_PBZHatredManagerComponent = hatred({}, true) })
f.npcs[3] = object({ ["Faction Component"] = fc3, BP_PBZHatredManagerComponent = hatred({}, true) })
f.mode:on(); f.mode:tick(); f.mode:tick()
f.fc.rejectClear, f.fc.rejectSet = true, true
f.mode:off()
for _ = 1, 8 do f.mode:tick() end
assert(fc2.override == nil and fc3.override == nil, "one failing restore must not starve other records")
assert(f.mode:status().pending_relations == 1)

f = fixture()
f.mode:on(); f.npc.alive, f.fc.alive, f.hm.alive = false, false, false
local invalidOff = f.mode:off()
assert(invalidOff.pending_relations == 0 and invalidOff.invalid_records_discarded == 1)

f = fixture()
f.player.BP_PBZHatredManagerComponent.CanBeHatredNow = nil
f.mode:on()
assert(f.mode:status().readFailures > 0 and f.mode:status().pending_flags == 0)

f = fixture()
f.mode:on()
f.opts.getDesiredPlayerRelation = function() error("policy unavailable") end
local badPolicy = f.mode:off()
assert(not badPolicy.ok and badPolicy.pending_relations == 1 and f.fc.override == 1,
    "uncertain arena policy must not clear its potential override")

f = fixture()
f.mode:on()
f.opts.valid = function() error("no UObject access during unload") end
f.mode:silence("OnUnload")
local quiet = f.mode:tick()
assert(quiet.silenced and not quiet.enabled_requested and quiet.pending_relations == 1)
assert(f.fc.override == 1, "silence must not pretend it restored game state")

local function destruction_callback(f)
    f.opts.isActorDestroying = function(actor)
        assert(actor == f.player or actor == f.npc, "destroy check must never receive component/UClass")
        return actor.destroying == true
    end
end
local function forbid_components(actor, components)
    local accesses = 0
    local oldActorMeta = getmetatable(actor)
    rawset(actor, "Faction Component", nil)
    rawset(actor, "BP_PBZHatredManagerComponent", nil)
    setmetatable(actor, { __index = function(self, property)
        if property == "Faction Component" or property == "BP_PBZHatredManagerComponent" then
            accesses = accesses + 1; error("component lookup forbidden on pending-destroy actor")
        end
        return oldActorMeta.__index(self, property)
    end })
    for _, comp in ipairs(components) do
        comp.IsValid = function() accesses = accesses + 1; error("even component validity must not be read") end
        comp.GetAddress = function() accesses = accesses + 1; error("component identity read forbidden") end
        comp.GetFactionRelation = function() accesses = accesses + 1; error("component relation read forbidden") end
        comp.SetFactionRelationOverride = function() accesses = accesses + 1; error("component write forbidden") end
        comp.ClearFactionRelationOverride = function() accesses = accesses + 1; error("component clear forbidden") end
        rawset(comp, "CanBeHatredNow", nil)
        local oldMeta = getmetatable(comp)
        setmetatable(comp, { __index = function(self, property)
            if property == "CanBeHatredNow" then accesses = accesses + 1; error("flag read forbidden") end
            return oldMeta.__index(self, property)
        end, __newindex = function(self, property, value)
            if property == "CanBeHatredNow" then accesses = accesses + 1; error("flag write forbidden") end
            rawset(self, property, value)
        end })
    end
    return function() return accesses end
end

f = fixture(); destruction_callback(f)
f.npc.destroying = true
local accessed = forbid_components(f.npc, { f.fc, f.hm })
local destroyedBeforeOn = f.mode:on()
assert(f.npc:IsValid() == true and accessed() == 0)
assert(destroyedBeforeOn.overrides_verified == 0 and destroyedBeforeOn.destroying_actors_skipped == 1)

f = fixture(); destruction_callback(f); f.mode:on()
f.npc.destroying = true
accessed = forbid_components(f.npc, { f.fc, f.hm })
local destroyedOff = f.mode:off()
assert(accessed() == 0 and destroyedOff.pending_relations == 0)
assert(destroyedOff.destroying_records_discarded == 1)
assert(table.concat(f.logs, "\n"):find("Actor销毁读回=true", 1, true))

f = fixture(); destruction_callback(f); f.mode:on()
f.npc.destroying = true
accessed = forbid_components(f.npc, { f.fc, f.hm })
local destroyedTick = f.mode:tick()
assert(accessed() == 0 and destroyedTick.pending_relations == 0 and destroyedTick.destroying_records_discarded == 1)

f = fixture(); destruction_callback(f); f.mode:on()
local playerHM = f.player.BP_PBZHatredManagerComponent
f.player.destroying = true
local playerAccess = forbid_components(f.player, { playerHM })
local npcAccess = forbid_components(f.npc, { f.fc, f.hm })
local destroyedPlayerOff = f.mode:off()
assert(playerAccess() == 0 and npcAccess() == 0)
assert(destroyedPlayerOff.pending_relations == 0 and destroyedPlayerOff.pending_flags == 0)
assert(destroyedPlayerOff.destroying_records_discarded == 2)

f = fixture(); destruction_callback(f); f.mode:on()
playerHM = f.player.BP_PBZHatredManagerComponent
f.player.destroying = true
playerAccess = forbid_components(f.player, { playerHM })
npcAccess = forbid_components(f.npc, { f.fc, f.hm })
local destroyedPlayerTick = f.mode:tick()
assert(playerAccess() == 0 and npcAccess() == 0)
assert(destroyedPlayerTick.pending_relations == 0 and destroyedPlayerTick.pending_flags == 0)

f = fixture(); destruction_callback(f); f.mode:on()
accessed = forbid_components(f.npc, { f.fc, f.hm })
f.opts.isActorDestroying = function(actor) if actor == f.npc then return "unknown" end; return false end
local unknownDestroy = f.mode:off()
assert(accessed() == 0 and unknownDestroy.pending_relations == 1)
assert(unknownDestroy.destroying_records_discarded == 0 and unknownDestroy.readFailures > 0)

f = fixture(); destruction_callback(f); f.mode:on()
playerHM = f.player.BP_PBZHatredManagerComponent
playerAccess = forbid_components(f.player, { playerHM })
npcAccess = forbid_components(f.npc, { f.fc, f.hm })
f.opts.isActorDestroying = function() error("cannot read destruction state") end
local errorDestroy = f.mode:off()
assert(playerAccess() == 0 and npcAccess() == 0)
assert(errorDestroy.pending_relations == 1 and errorDestroy.pending_flags == 1 and errorDestroy.destroying_records_discarded == 0)
f=fixture()
local fallbackFC,fallbackHM=f.fc,f.hm
f.npc['Faction Component']=nil;f.npc.BP_PBZHatredManagerComponent=nil
local fcClass,hmClass=object(),object()
StaticFindObject=function(path)
    if path=='/Script/SGameCombatSystem.FactionComponent' then return fcClass end
    if path:find('BP_PBZHatredManagerComponent',1,true) then return hmClass end
end
function f.npc:GetComponentByClass(cls)return cls==fcClass and fallbackFC or fallbackHM end
function fallbackFC:GetOwner()return f.npc end
function fallbackHM:GetOwner()return f.npc end
local fallbackResult=f.mode:on()
assert(fallbackResult.overrides_verified==1 and fallbackResult.removed_player_entries==1,'component-class lookup must cover NPCs with different property names')
assert(f.mode:off().ok)
f=fixture()
local immediateFC,immediateHM=faction(2),hatred({f.player},true)
local immediate=object({['Faction Component']=immediateFC,BP_PBZHatredManagerComponent=immediateHM})
f.mode:on();f.mode:applyTo(immediate)
assert(immediateFC.override==1 and #immediateHM.HatredList==0,'new spawn must not wait for the next NPC scan')
local cameraActive=true;f.opts.isObserverActive=function()return cameraActive end
assert(not f.mode:off().ok and f.mode:status().enabled_requested,'F8 must not disable an active camera guard')
cameraActive=false;assert(f.mode:off().ok)

f=fixture()
local files,objects={},{}
local function named(o,name)
    function o:GetFullName()assert(self.alive);return 'Object '..name end
    objects[name]=o
end
named(f.player,'/Test.Player');named(f.player.BP_PBZHatredManagerComponent,'/Test.Player.Hatred')
named(f.npc,'/Test.NPC');named(f.fc,'/Test.NPC.Faction')
local rejectWrite=false
f.opts.path='memory'
f.opts.io={open=function(path,mode)
    if (mode=='w' and rejectWrite) or (mode=='r' and not files[path]) then return nil end
    local text=files[path] or ''
    return {write=function(_,value)text=value;return true end,read=function()return text end,
        close=function()if mode=='w' then files[path]=text end;return true end}
end}
StaticFindObject=function(path)return objects[path]end
f.mode=Spectator.new(f.opts);f.mode:on()
assert(files['memory/spectator-state.tsv']:find('R\t',1,true) and f.fc.override==1)
f.mode:silence('fixture reload')
local reloaded=Spectator.new(f.opts);local recovered=reloaded:tick()
assert(recovered.pending_relations==0 and recovered.pending_flags==0 and f.fc.override==nil)
assert(f.player.BP_PBZHatredManagerComponent.CanBeHatredNow==true and files['memory/spectator-state.tsv']=='SpectatorV1\n')
rejectWrite=true;f.mode=Spectator.new(f.opts);f.mode:on();f.mode:tick()
assert(f.fc.override==nil and f.player.BP_PBZHatredManagerComponent.CanBeHatredNow,
    'a failed journal write must gate mutations on retries as well as first attempts')
-- v0.37.4: the player's side. A companion recorded while it was still the enemy (what v0.37.3 did when one was
-- summoned with no-aggro on) is left alone once it has joined, and on exit is set friendly, not back to hostile.
f=fixture()
local side={}
f.opts.isPlayerSide=function(n)return side[n]==true end
f.mode=Spectator.new(f.opts);f.mode:on()
local compFC,compHM=faction(2),hatred({},true)
local companion=object({['Faction Component']=compFC,BP_PBZHatredManagerComponent=compHM})
f.mode:applyTo(companion)
assert(compFC.override==1,'recorded and made neutral while still the enemy')
compFC.natural,compFC.override,side[companion]=0,0,true -- joins the player's side: the player's faction, friendly
f.npcs[#f.npcs+1]=companion
for _=1,3 do f.mode:tick() end
assert(compFC.override==0,'the player\'s side is not made neutral again')
local sideOff=f.mode:off()
assert(sideOff.ok and sideOff.pending_relations==0 and compFC.override==0,'set friendly on exit, never back to hostile')
assert(sideOff.player_side_released==1 and sideOff.player_side_skipped>=1 and f.fc.override==nil,'map NPCs are restored as before')
local skippedLine,releasedLine
for _,s in ipairs(f.logs)do
    if s:find('是玩家一方（随从、其召唤物或玩家阵营）；不改关系',1,true) then skippedLine=true end
    if s:find('已是玩家一方，设为友好，不恢复旧关系=2；读回=0',1,true) then releasedLine=true end
end
assert(skippedLine and releasedLine)
-- Already on the player's side when no-aggro comes on: left alone entirely, hatred included.
f=fixture();f.opts.isPlayerSide=function(n)return n==f.npc end;f.mode=Spectator.new(f.opts)
local leftAlone=f.mode:on()
assert(f.fc.override==nil and #f.hm.HatredList==2 and leftAlone.overrides_verified==0 and leftAlone.player_side_skipped>=1)
assert(f.mode:off().ok and f.fc.override==nil)
-- A check that errors counts as not the player's side: the NPC is handled as before.
f=fixture();f.opts.isPlayerSide=function()error('unreadable')end;f.mode=Spectator.new(f.opts)
assert(f.mode:on().overrides_verified==1 and f.fc.override==1)
assert(f.mode:off().ok and f.fc.override==nil)
print("spectator_mode: PASS (pending destruction, unknown state retention, reversible relations, immediate spawn, camera hold, persisted reload recovery, player's side left alone and never restored hostile)")
