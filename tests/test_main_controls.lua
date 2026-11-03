-- Runs the real main.lua key callbacks in an isolated Lua environment.
-- These tests cover control flow only, not UE4SS ABI, native hooks or combat.
-- From the repository root: texlua tests/test_main_controls.lua
local MAIN = "Mods/PhantomGladiator/Scripts/main.lua"
local CONFIG = "Mods/PhantomGladiator/Scripts/config.lua"
local Session = dofile("Mods/PhantomGladiator/Scripts/battle_session.lua")
assert(loadfile(MAIN), "main.lua must pass the real Lua parser")

local passed = 0
local function test(name, body)
    body()
    passed = passed + 1
    print("PASS " .. name)
end

local function harness(overrides)
    local h = {
        keys = {}, queue = {}, loops = {}, timers = {}, logs = {}, objects = {}, objectData = {},
        engineReads = 0, objectReads = 0, engineWrites = 0, inGameThread = false,
        starts = 0, stops = 0, silences = 0, hatredResets = 0,
        stopNotifications = 0, offThreadReads = 0, searches = {}, healthReads = 0,
    }
    local config = dofile(CONFIG)
    for k, v in pairs(overrides or {}) do config[k] = v end
    h.config = config

    local function keyId(key, modifiers)
        return tostring(key) .. (modifiers and ":SHIFT" or "")
    end
    function h:contains(text)
        for _, message in ipairs(self.logs) do
            if message:find(text, 1, true) then return true end
        end
        return false
    end
    function h:press(key)
        local fn = assert(self.keys[key], "key not registered: " .. key)
        fn()
    end
    function h:takeTimer(ms)
        for index, timer in ipairs(self.timers) do
            if timer.ms == ms then return table.remove(self.timers, index).fn end
        end
        error("missing timer for " .. tostring(ms) .. " ms")
    end
    function h:run(fn)
        assert(not self.inGameThread, "nested test game-thread dispatch")
        self.inGameThread = true
        local ok, err = pcall(fn)
        self.inGameThread = false
        assert(ok, err)
    end
    function h:drain()
        local safety = 0
        while #self.queue > 0 do
            safety = safety + 1
            assert(safety < 100, "unbounded game-thread queue")
            self:run(table.remove(self.queue, 1))
        end
    end
    function h:object(name, fields, access)
        local data = fields or {}
        local methods = {
            IsValid = function() return true end,
            GetAddress = function() return name end,
            GetFullName = function() return name end,
        }
        local object = setmetatable({}, {
            __index = function(_, key)
                h.objectReads = h.objectReads + 1
                if not h.inGameThread then h.offThreadReads = h.offThreadReads + 1 end
                if access and access.read then
                    local handled, value = access.read(key)
                    if handled then return value end
                end
                if data[key] ~= nil then return data[key] end
                return methods[key]
            end,
            __newindex = function(_, key, value)
                assert(h.inGameThread, "engine write outside game thread")
                h.engineWrites = h.engineWrites + 1
                if access and access.write then access.write(key, value) else data[key] = value end
            end,
        })
        self.objectData[object] = data
        return object
    end
    function h:addDuelScene(withHealth)
        local health = {}
        local function attributes(name, initial)
            if not withHealth then return nil end
            local state = { value = initial }
            health[name] = state
            local value = setmetatable({}, {
                __index = function(_, key)
                    assert(key == "CurrentValue", "unexpected Health field")
                    h.healthReads = h.healthReads + 1
                    assert(h.inGameThread, "HP read outside game thread")
                    return state.value
                end,
                __newindex = function()
                    h.engineWrites = h.engineWrites + 1
                    error("HP watch must never write Health")
                end,
            })
            return self:object(name .. "AttributeSet", { Health = value })
        end
        local player = self:object("PlayerPawn", {
            K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
            GetActorForwardVector = function() return { X = 1, Y = 0, Z = 0 } end,
            AttributeSetBase = attributes("player", 200),
        })
        local playerClass = self:object("PlayerControllerClass")
        local pc = self:object("PlayerController", {
            Player = self:object("UPlayer"), Pawn = player,
            GetClass = function() return playerClass end,
        })
        local monsterClass = self:object("BlueprintGeneratedClass BP_Monster_Test_C")
        local first = self:object("BP_Monster_First_C", {
            GetClass = function() return monsterClass end,
            K2_GetActorLocation = function() return { X = 100, Y = 0, Z = 0 } end,
            AttributeSetBase = attributes("first", 400),
        })
        local second = self:object("BP_Monster_Second_C", {
            GetClass = function() return monsterClass end,
            K2_GetActorLocation = function() return { X = 200, Y = 0, Z = 0 } end,
            AttributeSetBase = attributes("second", 300),
        })
        self.objects.PlayerController = { pc }
        for _, className in ipairs(self.config.EnemyClasses) do
            self.objects[className] = { player, first, second }
        end
        self.scene = { player = player, originals = { first, second }, monsterClass = monsterClass }
        return health
    end
    function h:addWorld(original, mode)
        local state = { value = original, writes = 0, mode = mode }
        local ws = self:object("WorldSettings", {}, {
            read = function(key)
                if key ~= "TimeDilation" then return false end
                if state.mode == "baseline_error" or (state.mode == "readback_error" and state.writes > 0) then
                    error("simulated TimeDilation read failure")
                end
                return true, state.value
            end,
            write = function(key, value)
                assert(key == "TimeDilation", "unexpected world property write")
                state.writes = state.writes + 1
                if state.mode ~= "ignored_write" then state.value = value end
            end,
        })
        self.objects.WorldSettings = { ws }
        return state
    end

    local probeState = { active = false, stopPending = false }
    local probe = {
        status = function() return probeState end,
        start = function(_, label, subjects)
            assert(h.inGameThread, "probe start outside game thread")
            h.starts = h.starts + 1
            h.probeLabel = label
            h.probeSubjects = subjects
            probeState.active = true
            return true, probeState
        end,
        stop = function(_, reason)
            assert(h.inGameThread, "probe stop outside game thread")
            h.stops = h.stops + 1
            local hadSession = probeState.active or probeState.stopPending
            probeState.active, probeState.stopPending = false, false
            probeState.reason = reason
            if hadSession and h.probeOptions.onStop then
                h.stopNotifications = h.stopNotifications + 1
                h.probeOptions.onStop(probeState)
            end
            return true, probeState
        end,
        silence = function()
            h.silences = h.silences + 1
            probeState.active = false
        end,
    }
    h.probe = probe
    local function unexpectedWrite(name)
        return function()
            h.engineWrites = h.engineWrites + 1
            error("unexpected engine mutation: " .. name)
        end
    end
    h.helpers = { GetPlayerController = function() return nil end }
    local modules = {
        config = config,
        teams = { ApplyTeam = unexpectedWrite("ApplyTeam"), ReadTeam = function() return nil end },
        hatred = { Reset = function() h.hatredResets = h.hatredResets + 1 end },
        UEHelpers = h.helpers,
        attack_profile = { new = function()
            return { sample = function()
                assert(h.inGameThread, "attack profile sample outside game thread")
                h.profileSamples = (h.profileSamples or 0) + 1
            end }
        end },
        battle_session = { new = function(log)
            h.session = Session.new(log)
            return h.session
        end },
        combat_probe = { new = function(options)
            h.probeOptions = options
            return probe
        end },
    }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.require = function(name) return assert(modules[name], "unmocked require: " .. name) end
    env.Key = setmetatable({}, { __index = function(_, key) return key end })
    env.ModifierKey = { SHIFT = "SHIFT" }
    env.ModRef = {}
    env.print = function(...) h.logs[#h.logs + 1] = table.concat({ ... }, " ") end
    env.RegisterKeyBind = function(key, modifiers, fn)
        if type(modifiers) == "function" then fn, modifiers = modifiers, nil end
        h.keys[keyId(key, modifiers)] = fn
    end
    env.ExecuteInGameThread = function(fn) h.queue[#h.queue + 1] = fn end
    env.ExecuteWithDelay = function(ms, fn) h.timers[#h.timers + 1] = { ms = ms, fn = fn } end
    env.LoopAsync = function(ms, fn) h.loops[#h.loops + 1] = { ms = ms, fn = fn } end
    env.FindAllOf = function(name)
        assert(h.inGameThread, "FindAllOf outside game thread")
        h.engineReads = h.engineReads + 1
        h.searches[name] = (h.searches[name] or 0) + 1
        return h.objects[name] or {}
    end
    env.StaticFindObject = function()
        h.engineReads = h.engineReads + 1
        return nil
    end
    env.FindObject = env.StaticFindObject
    env.StaticConstructObject = unexpectedWrite("StaticConstructObject")
    env.RegisterHook = unexpectedWrite("RegisterHook outside probe stub")
    env.FName = function(value) return { ToString = function() return value end } end
    h.env = env
    local chunk, err = loadfile(MAIN, "t", env)
    assert(chunk, err)
    chunk()
    return h
end

-- Models only the reflected calls used by the real F9/F3/F4 control path.
local function arenaHarness(failSpawn)
    local h = harness()
    h:addDuelScene(true)
    h.spawnCalls, h.finishCalls, h.activateCalls = 0, 0, 0
    h.spawned, h.destroyed, h.forces, h.targetWrites, h.relations = {}, {}, {}, {}, {}
    local world = h:object("TestWorld")
    h.helpers.GetWorld = function() return world end
    local function mutate()
        assert(h.inGameThread, "arena mutation outside game thread")
        h.engineWrites = h.engineWrites + 1
    end
    for _, original in ipairs(h.scene.originals) do
        h.objectData[original].K2_DestroyActor = function()
            mutate(); h.destroyed[#h.destroyed + 1] = original
        end
    end
    local function faction(label, owner)
        return h:object(label .. "Faction", {
            GetFactionRelation = function(_, other)
                return (h.relations[owner()] or {})[other] or 0
            end,
            GetCurrnetFaction = function() return { TagName = h.env.FName("Faction.Enemy") } end,
            SetFactionRelationOverride = function(_, other, relation, both)
                mutate()
                local self = owner()
                h.relations[self] = h.relations[self] or {}
                h.relations[self][other] = relation
                if both then
                    h.relations[other] = h.relations[other] or {}
                    h.relations[other][self] = relation
                end
            end,
            ClearFactionRelationOverride = function(_, other)
                mutate()
                if h.relations[owner()] then h.relations[owner()][other] = nil end
            end,
        })
    end
    h.objectData[h.scene.player]["Faction Component"] = faction("Player", function() return h.scene.player end)
    local library = h:object("AIFunctionLibrary", {
        SpawnAIDefered = function(_, cls, transform, optional, suppliedWorld)
            mutate()
            assert(cls == h.scene.monsterClass and optional == nil and suppliedWorld == world)
            h.spawnCalls = h.spawnCalls + 1
            if h.spawnCalls == failSpawn then return nil end
            local item = { alive = true, transform = transform, bbValue = h.scene.player, hatred = {} }
            local actor
            local bb = h:object("ArenaBlackboard" .. h.spawnCalls, {
                GetValueAsObject = function() return item.bbValue end,
                SetValueAsObject = function(_, _, target)
                    mutate(); item.bbValue = target
                    h.targetWrites[#h.targetWrites + 1] = { actor, target }
                end,
                ClearValue = function() mutate(); item.bbValue = nil end,
            })
            local ai = h:object("ArenaAI" .. h.spawnCalls, {
                BlackboardComponent = bb,
                CurrentStateTag = { TagName = h.env.FName("AI.State.Combat") },
                ForceIntoCombat = function(_, target)
                    mutate(); h.forces[#h.forces + 1] = { actor, target }
                end,
            })
            local hatred = h:object("ArenaHatred" .. h.spawnCalls, {
                HatredList = item.hatred,
                AddActorToHatredList = function() mutate(); return false end,
                RemoveActorFromHatredList = function(_, target)
                    mutate()
                    for index = #item.hatred, 1, -1 do
                        if item.hatred[index] == target then table.remove(item.hatred, index) end
                    end
                end,
            })
            actor = h:object("ArenaSpawn" .. h.spawnCalls, {
                IsValid = function() return item.alive end,
                K2_GetActorLocation = function() return transform.Translation end,
                AttributeSetBase = h:object("ArenaAttributes" .. h.spawnCalls, { Health = { CurrentValue = 400 } }),
                Controller = h:object("ArenaController" .. h.spawnCalls, { SGameAIComponent = ai }),
                BP_PBZHatredManagerComponent = hatred,
                ["Faction Component"] = faction("Arena" .. h.spawnCalls, function() return actor end),
                K2_DestroyActor = function()
                    mutate(); item.alive = false; h.destroyed[#h.destroyed + 1] = actor
                end,
            })
            item.actor = actor
            h.spawned[#h.spawned + 1] = item
            h.objects.PBZ_TargetingHandler_AI_C = h.objects.PBZ_TargetingHandler_AI_C or {}
            table.insert(h.objects.PBZ_TargetingHandler_AI_C, h:object("ArenaTargetHandler" .. h.spawnCalls, {
                Blackboard = bb, ["Target Key"] = h.env.FName("Target"),
            }))
            return actor
        end,
        FinishSpawnAIDefered = function(_, actor, transform, suppliedWorld)
            mutate()
            local item = h.spawned[#h.spawned]
            assert(item.actor == actor and item.transform == transform and suppliedWorld == world)
            h.finishCalls = h.finishCalls + 1
        end,
        ActivateAI = function(_, actor, suppliedWorld)
            mutate()
            assert(h.spawned[#h.spawned].actor == actor and suppliedWorld == world)
            h.activateCalls = h.activateCalls + 1
        end,
    })
    local originalFind = h.env.StaticFindObject
    h.env.StaticFindObject = function(path)
        if path:find("Default__BP_SGameAIFunctionLibrary_C", 1, true) then return library end
        return originalFind(path)
    end
    return h
end

test("default broad battle keys remain gated before engine access", function()
    local h = harness()
    assert(h.config.EnableBattleExperiments == false)
    for _, key in ipairs({ "F2", "F8" }) do h:press(key) end
    assert(#h.queue == 0 and h.engineReads == 0 and h.engineWrites == 0)
    assert(h:contains("诊断版未启用"))
    assert(type(h.keys.F6) == "function" and type(h.keys.F7) == "function", "camera controls remain registered")
end)

test("F11 starts and stops the probe only after game-thread dispatch", function()
    local h = harness()
    h:press("F11")
    assert(h.starts == 0 and #h.queue == 1)
    h:drain()
    assert(h.starts == 1 and h.probeLabel == "native_baseline")
    assert(h:contains("只读阳性对照"))
    h:press("F11")
    assert(h.stops == 0)
    h:drain()
    assert(h.stops == 1 and h.engineWrites == 0)
end)

test("F4 cancels before restoring and invalidates an already queued real duel watcher", function()
    local h = harness({ EnableBattleExperiments = true })
    h:addDuelScene()
    h:press("F3")
    h:drain()
    assert(h.session.active and #h.loops == 1, "real F3 must install the duel watcher: " .. table.concat(h.logs, " | "))
    local token = h.session:currentToken()
    assert(h.loops[1].fn() == false and #h.queue == 1)
    local oldWatch = table.remove(h.queue, 1)
    local restored = false
    h.session:remember("assert-cancel-order", function()
        assert(not h.session:isCurrent(token) and not h.session.active, "cancel must precede restoration")
        restored = true
        return true, "verified by control test"
    end)
    h:press("F4")
    assert(not restored, "F4 restoration must be queued")
    h:drain()
    assert(restored and h.stops >= 1)
    local engineReads, objectReads, writes = h.engineReads, h.objectReads, h.engineWrites
    h:run(oldWatch)
    assert(h.engineReads == engineReads and h.objectReads == objectReads and h.engineWrites == writes,
        "stale watcher must not even read or validate an engine object")
    assert(h.loops[1].fn() == true and #h.queue == 0)
    assert(h:contains("F4 恢复读回完成"))
end)

test("F5 writes verified time dilation and F4 restores the original non-default value", function()
    local h = harness()
    local world = h:addWorld(0.8)
    h:press("F5")
    assert(world.writes == 0)
    h:drain()
    assert(world.value == 0.5 and h:contains("时间流速: 0.50x"))
    h:press("F5")
    h:drain()
    assert(world.value == 0.2 and h.session:pendingCount() == 1)
    h:press("F4")
    h:drain()
    assert(world.value == 0.8 and h.session:pendingCount() == 0)
end)

test("F5 readback exception cannot report success and keeps recovery available", function()
    local h = harness()
    local world = h:addWorld(0.8, "readback_error")
    h:press("F5")
    h:drain()
    assert(world.writes == 1 and world.value == 0.5)
    assert(h:contains("设置 TimeDilation 失败") and not h:contains("时间流速:"))
    assert(h.session:pendingCount() == 1)
    world.mode = nil
    h:press("F4")
    h:drain()
    assert(world.value == 0.8 and h.session:pendingCount() == 0)
end)

test("F5 ignored write is not accepted as successful readback", function()
    local h = harness()
    local world = h:addWorld(0.8, "ignored_write")
    h:press("F5")
    h:drain()
    assert(world.value == 0.8 and world.writes == 1)
    assert(h:contains("设置 TimeDilation 失败") and not h:contains("时间流速:"))
end)

test("F5 baseline read error makes no write or fabricated snapshot", function()
    local h = harness()
    local world = h:addWorld(0.8, "baseline_error")
    h:press("F5")
    h:drain()
    assert(world.writes == 0 and h.session:pendingCount() == 0)
    assert(h:contains("设置 TimeDilation 失败") and not h:contains("时间流速:"))
end)

test("OnUnload only silences and cancels, leaving UObject restoration to explicit F4", function()
    local h = harness()
    h:press("F11")
    h:drain()
    local restoreCalled = false
    h.session:begin("unload-control-test")
    h.session:remember("must-not-run-on-unload", function()
        restoreCalled = true
        return true
    end)
    local engineReads, objectReads, writes = h.engineReads, h.objectReads, h.engineWrites
    assert(type(h.env.ModRef.OnUnload) == "function")
    h.env.ModRef.OnUnload()
    assert(h.silences == 1 and h.stops == 0 and not restoreCalled)
    assert(not h.session.active and h.session:pendingCount() == 1 and #h.queue == 0)
    -- The old F11 scene timer may still have reached a queue before teardown.
    for _, timer in ipairs(h.timers) do timer.fn() end
    h:drain()
    assert(h.engineReads == engineReads and h.objectReads == objectReads and h.engineWrites == writes)
    assert(h:contains("重载前须F4"))
end)

test("HP watch logs consecutive values read-only and manual onStop captures the final value", function()
    local h = harness()
    local health = h:addDuelScene(true)
    h:press(h.config.Keybinds.Probe)
    h:drain()
    assert(#h.probeSubjects == 3, "the real main must pass player and nearby NPC subjects")
    local reads = h.objectReads
    health.player.value = 150 -- Simulated external gameplay change, not a mod write.
    h:takeTimer(1000)()
    assert(h.objectReads == reads and #h.queue == 1, "timer may only queue the sample")
    h:drain()
    assert(h:contains("PlayerPawn HP=200→150"))
    assert(h:contains("只读，不据此判断伤害来源"))
    health.player.value = 140
    health.first.value = 375
    h:takeTimer(1000)()
    h:drain()
    assert(h:contains("PlayerPawn HP=150→140"))
    assert(h:contains("BP_Monster_First_C HP=400→375"))
    assert((h.searches.BasicAttributeSet or 0) == 0, "valid direct AttributeSetBase must avoid fallback scans")

    health.player.value = 133 -- No timer tick before stop: final read must still see this.
    h:press(h.config.Keybinds.Probe)
    assert(h.stopNotifications == 0)
    h:drain()
    assert(h.stopNotifications == 1)
    assert(h:contains("[HPWatch] 结束 PlayerPawn start=200 final=133"))
    assert(h.engineWrites == 0 and h.offThreadReads == 0)
end)

test("F4 final read precedes disposal of a stale already queued HP sample", function()
    local h = harness()
    local health = h:addDuelScene(true)
    h:press(h.config.Keybinds.Probe)
    h:drain()
    h:takeTimer(1000)()
    local oldSample = assert(table.remove(h.queue, 1))
    health.first.value = 390
    h:press("F4")
    h:drain()
    assert(h.stopNotifications == 1)
    assert(h:contains("BP_Monster_First_C start=400 final=390 reason=F4"))
    local objectReads, engineReads, hpReads = h.objectReads, h.engineReads, h.healthReads
    h:run(oldSample)
    assert(h.objectReads == objectReads and h.engineReads == engineReads and h.healthReads == hpReads)
    assert(h.engineWrites == 0 and h.offThreadReads == 0)
end)

test("unload silences without final HP reads and invalidates a queued HP sample", function()
    local h = harness()
    h:addDuelScene(true)
    h:press(h.config.Keybinds.Probe)
    h:drain()
    h:takeTimer(1000)()
    local oldSample = assert(table.remove(h.queue, 1))
    local objectReads, engineReads, hpReads = h.objectReads, h.engineReads, h.healthReads
    h.env.ModRef.OnUnload()
    assert(h.stopNotifications == 0 and h.stops == 0 and h.silences == 1)
    h:run(oldSample)
    assert(h.objectReads == objectReads and h.engineReads == engineReads and h.healthReads == hpReads)
    assert(not h:contains("[HPWatch] 结束"))
    assert(h.engineWrites == 0 and h.offThreadReads == 0)
end)

test("automatic game-thread onStop reads final HP once and invalidates old timers", function()
    local h = harness()
    local health = h:addDuelScene(true)
    h:press(h.config.Keybinds.Probe)
    h:drain()
    health.second.value = 250
    h:run(function() h.probe:stop("time_limit") end)
    assert(h.stopNotifications == 1)
    assert(h:contains("BP_Monster_Second_C start=300 final=250 reason=time_limit"))
    local objectReads, engineReads, hpReads = h.objectReads, h.engineReads, h.healthReads
    for _, timer in ipairs(h.timers) do timer.fn() end
    h:drain()
    h:run(function() h.probe:stop("again") end)
    assert(h.stopNotifications == 1, "a closed session must not send a duplicate final read")
    assert(h.objectReads == objectReads and h.engineReads == engineReads and h.healthReads == hpReads)
    assert(h.engineWrites == 0 and h.offThreadReads == 0)
end)

test("HP watch stops scheduling at sixty samples and caps detail lines", function()
    local h = harness()
    local health = h:addDuelScene(true)
    h:press(h.config.Keybinds.Probe)
    h:drain()
    for index = 1, 60 do
        health.first.value = 400 - index
        h:takeTimer(1000)()
        h:drain()
    end
    for _, timer in ipairs(h.timers) do assert(timer.ms ~= 1000, "HP watch exceeded sixty samples") end
    local changes = 0
    for _, message in ipairs(h.logs) do
        if message:find("[HPWatch]", 1, true) and message:find("只读，不据此判断伤害来源", 1, true) then
            changes = changes + 1
        end
    end
    assert(changes == 40, "HP detail budget must be forty lines")
    assert(h.engineWrites == 0 and h.offThreadReads == 0)
end)

test("F9 owns exactly two spawns, F3 targets only them, and F4 cleans only them", function()
    local h = arenaHarness()
    h:press("F9")
    assert(h.spawnCalls == 0, "F9 must defer all engine work")
    h:drain()
    assert(h.spawnCalls == 2 and h.finishCalls == 2 and h.activateCalls == 2,
        "F9 must use the complete official spawn lifecycle exactly twice: " .. table.concat(h.logs, " | "))
    local a, b = h.spawned[1].actor, h.spawned[2].actor
    assert(h.spawned[1].transform.Translation.Y ~= h.spawned[2].transform.Translation.Y)
    assert(h.relations[a][h.scene.player] == 1 and h.relations[b][h.scene.player] == 1)
    assert(h.relations[a][b] == 2 and h.relations[b][a] == 2)
    assert(#h.forces == 2 and h.forces[1][1] == a and h.forces[1][2] == b)
    assert(h.forces[2][1] == b and h.forces[2][2] == a)
    assert(h.spawned[1].hatred[1] == b and h.spawned[2].hatred[1] == a)
    assert(h.spawned[1].bbValue == b and h.spawned[2].bbValue == a)
    assert(h.probeLabel == "arena_duel" and h.probeSubjects[1] == a and h.probeSubjects[2] == b)

    h:press("F9")
    h:drain()
    assert(h.spawnCalls == 2, "repeated F9 must not duplicate owned actors")
    h:press("F3")
    h:drain()
    assert(#h.forces == 4 and h.spawnCalls == 2)
    for _, request in ipairs(h.forces) do
        assert((request[1] == a and request[2] == b) or (request[1] == b and request[2] == a),
            "F3 must not choose closer map NPCs")
    end
    local watch = h.loops[#h.loops]
    assert(watch.ms == 250 and watch.fn() == false)
    local oldWork = assert(table.remove(h.queue, 1))
    h:press("F4")
    h:drain()
    assert(#h.destroyed == 2 and h.destroyed[1] == a and h.destroyed[2] == b)
    assert(not h.spawned[1].alive and not h.spawned[2].alive)
    assert(h.spawned[1].bbValue == h.scene.player and h.spawned[2].bbValue == h.scene.player,
        "F4 must restore original blackboard targets before cleanup")
    assert(#h.spawned[1].hatred == 0 and #h.spawned[2].hatred == 0)
    local objectReads, engineReads, writes = h.objectReads, h.engineReads, h.engineWrites
    h:run(oldWork)
    assert(h.objectReads == objectReads and h.engineReads == engineReads and h.engineWrites == writes)
    assert(watch.fn() == true and h.offThreadReads == 0)
end)

test("partial official spawn failure remains owned and F4 can clean it", function()
    local h = arenaHarness(2)
    h:press("F9")
    h:drain()
    assert(h.spawnCalls == 2 and #h.spawned == 1 and h.finishCalls == 1 and h.activateCalls == 1)
    assert(#h.forces == 0 and h.starts == 0, "partial pair must not enter combat")
    h:press("F9")
    h:drain()
    assert(h.spawnCalls == 2, "partial pair must remain tracked until explicit cleanup")
    h:press("F4")
    h:drain()
    assert(#h.destroyed == 1 and h.destroyed[1] == h.spawned[1].actor and not h.spawned[1].alive)
    h:press("F9")
    h:drain()
    assert(h.spawnCalls == 4 and #h.spawned == 3, "F4 must release the pair slot")
end)

test("default F3 without owned pair leaves map NPCs untouched", function()
    local h = arenaHarness()
    h:press("F3")
    h:drain()
    assert(h.spawnCalls == 0 and #h.forces == 0 and h.engineWrites == 0 and #h.loops == 0)
    assert(h:contains("请先按F9召出一对参赛怪"))
end)

test("failed destroy remains owned for F4 retry and blocks F3 and duplicate F9", function()
    local h = arenaHarness()
    h:press("F9"); h:drain()
    local first = h.spawned[1]
    local destroy = h.objectData[first.actor].K2_DestroyActor
    local attempts = 0
    h.objectData[first.actor].K2_DestroyActor = function()
        assert(h.inGameThread)
        attempts = attempts + 1
        error("simulated destroy failure")
    end
    h:press("F4"); h:drain()
    assert(attempts == 1 and first.alive and not h.spawned[2].alive)
    assert(h:contains("调用=false；对象有效性读回=true"))
    assert(h:contains("保留记录供F4重试"))
    local forces = #h.forces
    h:press("F3"); h:press("F9"); h:drain()
    assert(#h.forces == forces and h.spawnCalls == 2)
    h.objectData[first.actor].K2_DestroyActor = destroy
    h:press("F4"); h:drain()
    assert(not first.alive and #h.destroyed == 2)
    h:press("F9"); h:drain()
    assert(h.spawnCalls == 4 and #h.forces == forces + 2)
end)

test("delayed destruction stays tracked until F9 observes invalid owned actors", function()
    local h = arenaHarness()
    h:press("F9"); h:drain()
    local pending = { h.spawned[1], h.spawned[2] }
    local requests = 0
    for _, item in ipairs(pending) do
        h.objectData[item.actor].K2_DestroyActor = function()
            assert(h.inGameThread)
            requests = requests + 1 -- Native request accepted; engine invalidates later.
        end
    end
    h:press("F4"); h:drain()
    assert(requests == 2 and pending[1].alive and pending[2].alive)
    assert(h:contains("调用=true；对象有效性读回=true"))
    local forces = #h.forces
    h:press("F3"); h:press("F9"); h:drain()
    assert(#h.forces == forces and h.spawnCalls == 2 and requests == 2)
    pending[1].alive, pending[2].alive = false, false
    h:press("F9"); h:drain()
    assert(h.spawnCalls == 4 and #h.forces == forces + 2 and requests == 2,
        "F9 must prune invalid old actors and release the cleanup gate")
end)

print(string.format("main_controls: PASS (%d real-main control regressions; no game process accessed)", passed))
