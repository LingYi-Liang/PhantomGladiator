-- Offline lifecycle tests; no game process or UE4SS is needed.
-- Run from repository root: texlua tools/test_combat_probe.lua
local Probe = dofile("Mods/PhantomGladiator/Scripts/combat_probe.lua")
local now, timers, gameQueue, registrations, removed, messages = 100, {}, {}, {}, {}, {}
local cancelled, executingTimer = {}, nil
local realTime = os.time
os.time = function() return now end

local function object(name, data, alive)
    data = data or {}
    data.IsValid = function() return alive ~= false end
    return setmetatable(data, { __index = function(_, key)
        assert(alive ~= false, "invalid object accessed: " .. key)
        if key == "GetAddress" then return function() return name end end
        if key == "GetFullName" then return function() return name end end
        return nil
    end })
end

local function param(value) return { get = function() return value end } end
local function attack(hookFn, self, component)
    return hookFn(param(self), param(component), param("bone"), param({}), param({}), param({}), param({}))
end
local function reset()
    timers, gameQueue, registrations, removed, messages = {}, {}, {}, {}, {}
    cancelled, executingTimer = {}, nil
    StaticFindObject = function(path) return object(path) end
    RegisterHook = function(path, pre, post)
        local id = #registrations * 2 + 1
        registrations[#registrations + 1] = { path = path, pre = pre, post = post, id = id }
        return id, id + 1
    end
    UnregisterHook = function(path, preId, postId)
        removed[#removed + 1] = { path = path, preId = preId, postId = postId }
    end
    ExecuteWithDelay = function() error("legacy async timer must not be used") end
    ExecuteInGameThread = function() error("cross-thread queue must not be used") end
    ExecuteInGameThreadWithDelay = function(ms, callback)
        local handle = #timers + 1
        timers[#timers + 1] = { ms = ms, fn = callback, handle = handle, state = "Active" }
        return handle
    end
    CancelDelayedAction = function(handle)
        for _, timer in ipairs(timers) do
            if timer.handle == handle and timer.state ~= "PendingRemoval" and timer.state ~= "Finished" then
                cancelled[#cancelled + 1] = { handle = handle, wasExecuting = timer.state == "Executing" }
                timer.state = "PendingRemoval"
                return true
            end
        end
        return false
    end
end

local function create(config)
    config = config or {}
    config.IncludeAttitude = true -- legacy lifecycle cases explicitly opt into noisy attitude probes
    return Probe.new({ config = config, log = function(s) messages[#messages + 1] = s end })
end
local function contains(needle)
    for _, message in ipairs(messages) do if message:find(needle, 1, true) then return true end end
    return false
end
local function hook(name)
    for _, registration in ipairs(registrations) do
        if registration.path:sub(-#name) == name then return registration end
    end
    error("missing " .. name)
end
local function fire(timer)
    if timer.state ~= "Active" then return end
    timer.state, executingTimer = "Executing", timer
    assert(timer.fn() == nil, "timer callbacks must not return a value")
    if timer.state == "Executing" then timer.state = "Finished" end
    executingTimer = nil
end
local function drainStop()
    for _, timer in ipairs(timers) do if timer.ms == 1 then fire(timer) end end
end

reset()
local p = create()
assert(p:start("positive"))
assert(#registrations == 9)
assert(registrations[8].post == nil and registrations[9].post == nil, "script hook must use second callback")
local attributes = object("attributes", { Health = { CurrentValue = 400 } })
local attacker = object("attacker")
local victim = object("victim", { AttributeSetBase = attributes })
local component = object("capsule", { GetOwner = function() return victim end })
local module = object("module", { LastOwnerAvatar = attacker })
local tryAttack = hook("TryAttack")
assert(attack(tryAttack.pre, module, component) == nil)
assert(attack(tryAttack.post, module, component) == nil)
assert(p:status().events == 2)
assert(contains("source=attacker@attacker") and contains("target=victim@victim"))
assert(contains("target_hp=400"))
assert(hook("IsValidTarget").post(param(module), param(false), param(victim)) == nil)
assert(contains("return_offset=1 | original_return=false | source=attacker@attacker | target=victim@victim"),
    "native post original return must not shift target identity")
local poisonedParam = { get = function() error("signature mismatch must not read parameters") end }
hook("IsValidTarget").post(poisonedParam, poisonedParam, poisonedParam, poisonedParam)
assert(p:status().signatureMismatches == 1 and p:status().snapshotErrors == 0)
assert(contains("unknown(signature_mismatch)"))
hook("BlueprintGetTeamAttitudeTowards").pre(param(attacker), param(victim))
assert(p:status().counts.PBZAttitude.post == 1 and p:status().counts.PBZAttitude.pre == 0)
local tagMap = setmetatable({ ForEach = function(_, fn)
    fn(param({ TagName = { ToString = function() return "Damage.Physical" end } }), param(25))
end }, { __len = function() return 1 end })
local attributeComponent = object("attribute_component", { GetOwner = function() return victim end })
local damageHook = hook("TakeDamage")
damageHook.post(param(attributeComponent), param(attacker), param({ TagName = "Damage.Attack" }),
    param({}), param({}), param({}), param(tagMap), param(nil), param({}), param({}), param(tagMap))
assert(contains("final_damage={Damage.Physical=25} count=1"), "native out parameter must be read back")
damageHook.post(param(attributeComponent), param(true), param(attacker), param({ TagName = "Damage.Attack" }),
    param({}), param({}), param({}), param(tagMap), param(nil), param({}), param({}), param(tagMap))
assert(messages[#messages]:find("return_offset=1 | original_return=true", 1, true))
assert(messages[#messages]:find("final_damage={Damage.Physical=25} count=1", 1, true),
    "native return insertion must also preserve output parameter index")
local savedOldCallback, savedOldTimer = tryAttack.pre, timers[1].fn
assert(p:stop("manual"))
assert(#removed == 9 and p:status().hooks == 0)
assert(#cancelled == 1 and p:status().timerHandles == 0)
assert(p:start("negative"))
attack(savedOldCallback, module, component)
savedOldTimer()
assert(p:status().events == 0 and p:status().active, "old callbacks/timers must not affect new session")
p:stop()

reset()
p = create()
assert(p:start("unload"))
local unloadingHook, unloadingTimer = hook("TryAttack").pre, timers[1].fn
local timerCount, queueCount = #timers, #gameQueue
local silenced = p:silence("OnUnload")
assert(not silenced.active and not silenced.stopPending and silenced.reason == "OnUnload")
assert(silenced.hooks == 9 and #removed == 0, "silence must not unregister hooks")
assert(#cancelled == 1 and silenced.timerHandles == 0, "silence must cancel host queue handles")
assert(#timers == timerCount and #gameQueue == queueCount, "silence must not schedule work")
unloadingHook(poisonedParam, poisonedParam, poisonedParam, poisonedParam, poisonedParam, poisonedParam, poisonedParam)
unloadingTimer()
assert(p:status().events == 0 and p:status().snapshotErrors == 0)
assert(#timers == timerCount and #gameQueue == queueCount, "old callbacks must remain silent after unload")
p:stop("test_cleanup")

reset()
p = create({ MaxEvents = 3, MaxLogs = 2 })
assert(p:start("budget"))
tryAttack = hook("TryAttack")
for _ = 1, 10 do attack(tryAttack.pre, module, component) end
assert(p:status().events == 3 and p:status().detailLines == 2)
assert(not p:status().active and p:status().stopPending)
assert(#removed == 0 and #timers == 2, "hook must defer its own unregister to a single game-thread timer")
drainStop()
assert(#removed == 9 and p:status().reason == "event_limit")
assert(#cancelled == 2 and p:status().timerHandles == 0)
local cancelledWhileExecuting = false
for _, call in ipairs(cancelled) do if call.wasExecuting then cancelledWhileExecuting = true end end
assert(cancelledWhileExecuting, "deferred stop must safely cancel its currently executing one-shot")

reset()
p = create({ MaxEvents = 1 })
assert(p:start("pending_stop_restart"))
attack(hook("TryAttack").pre, module, component)
local staleDeferred = timers[2].fn
assert(p:stop("manual") and #cancelled == 2)
assert(p:start("fresh_after_pending_stop"))
local removedBeforeStale = #removed
assert(staleDeferred() == nil)
assert(p:status().active and #removed == removedBeforeStale, "cancelled deferred callback must not stop a later session")
p:stop()

reset()
p = create()
assert(p:start("invalid"))
local invalid = object("dead", {}, false)
attack(hook("TryAttack").pre, invalid, invalid)
assert(p:status().snapshotErrors == 0, "invalid objects must not be dereferenced")
assert(contains("unknown(invalid_or_unavailable)"))
p:stop()

reset()
p = create()
assert(p:start("timeout"))
fire(timers[1])
assert(not p:status().active and p:status().reason == "time_limit" and #removed == 9)
assert(#timers == 1 and #cancelled == 1 and cancelled[1].wasExecuting,
    "automatic timeout stops directly and cancels its executing handle without another timer")

reset()
p = create({ DurationMs = 1000 })
assert(p:start("deadline"))
now = now + 2
attack(hook("TryAttack").pre, module, component)
assert(p:status().events == 0 and not p:status().active, "expired callback must not read objects")
drainStop()

reset()
ExecuteInGameThreadWithDelay = function() error("timer unavailable") end
p = create()
assert(not p:start("failed_timer"))
assert(not p:status().active and #removed == 9)

reset()
ExecuteInGameThreadWithDelay = nil
p = create()
assert(not p:start("no_game_thread_timer") and #registrations == 0)
assert(contains("ExecuteInGameThreadWithDelay"), "missing new API must fail explicitly, not use async fallback")

reset()
CancelDelayedAction = nil
p = create()
assert(not p:start("no_cancel_api") and #registrations == 0)
assert(contains("CancelDelayedAction"))

reset()
ExecuteInGameThreadWithDelay = function() return nil end
p = create()
assert(not p:start("unknown_timer_handle"))
assert(p:status().timerRegistrationUncertain and not p:start("cannot_stack_unknown_timers"))

reset()
p = create()
assert(p:start("cancel_failure"))
local originalCancel = CancelDelayedAction
CancelDelayedAction = function() error("host queue unavailable") end
assert(not p:stop("manual"))
assert(p:status().timerHandles == 1 and not p:status().active)
assert(not p:start("cancel_must_retry") and #registrations == 9)
CancelDelayedAction = originalCancel
assert(p:stop("retry") and p:status().timerHandles == 0)

reset()
p = create()
assert(p:start("already_finished_timer"))
timers[1].state = "Finished"
assert(p:stop("manual") and p:status().timerHandles == 0)

reset()
StaticFindObject = function() return object("absent", {}, false) end
p = create()
assert(not p:start("no_functions"))
assert(#registrations == 0 and p:status().unavailable == 9)

reset()
p = create()
assert(p:start("cleanup_failure"))
UnregisterHook = function() error("busy") end
assert(not p:stop("manual"))
assert(not p:start("must_not_stack"))
assert(#registrations == 9 and p:status().hooks == 9)
UnregisterHook = function() end
assert(p:stop("retry"))

reset()
RegisterHook = function() return nil, nil end
p = create()
assert(not p:start("unknown_ids"))
assert(p:status().registrationUncertain and not p:start("must_reload"))

reset()
p = create({ DurationMs = 999999, MaxLogs = 9999, MaxEvents = 999999 })
assert(p:start("clamped"))
assert(p:status().durationMs == 60000 and timers[1].ms == 60000)
p:stop()
-- v0.14 defaults: only seven native candidates; attitude requires explicit opt-in.
reset()
local stopCalls = 0
p = Probe.new({ log = function(s) messages[#messages + 1] = s end,
    onStop = function(status)
        assert(not status.active)
        stopCalls = stopCalls + 1
    end })
assert(p:start("default"))
assert(#registrations == 7)
for _, h in ipairs(registrations) do assert(not h.path:find("Attitude", 1, true)) end
assert(hook("OnDamage").pre)
hook("OnDamage").post(param(victim), param(15), param({ GameplayTags = {
    ForEach = function() end } }), param({}))
assert(contains("damage_amount=15") and contains("hp_readback=400"))
p:stop()
p:stop()
assert(stopCalls == 1, "onStop must run only once per session")
assert(p:start("silent_unload"))
p:silence("OnUnload")
assert(stopCalls == 1, "silence must not invoke onStop")
p:stop("test_cleanup")
assert(stopCalls == 1)

local function fn(path, flags)
    return object(path, { GetFullName = function() return "Function " .. path end,
        GetFunctionFlags = function() return flags or 0x08000800 end })
end
local function class(name, functions, parent)
    return object(name, { ForEachFunction = function(_, callback)
        for _, f in ipairs(functions) do if callback(f) == true then break end end
    end, GetSuperStruct = function() return parent end })
end
reset()
local hunPath = "/ActualLoaded/NotGuessed/Hun.Hun_C:Health Post Func"
local mixinPath = "/ActualLoaded/NotGuessed/Hun.Hun_C:Health Post Func__puerts_mixin__"
local parentPath = "/ActualLoaded/Base.Base_C:Health Post Func"
local changedPath = "/ActualLoaded/Base.Base_C:Changed_65C423C64D9460919B5AC49EEE1A1401"
local eventPath = "/ActualLoaded/Base.Base_C:EventReceived_B1FF86534050CD4041F4E69109D6C58E"
local delegatePath = "/ActualLoaded/Bad.Bad_C:On Dead"
local badFunction = object("invalidFunction", {}, false)
local baseClass = class("base", { fn(parentPath), fn(changedPath), fn(eventPath), badFunction })
local hunClass = class("hun", { fn(hunPath), fn(mixinPath), fn(delegatePath, 0x00100000),
    fn("/ActualLoaded/Hun.Hun_C:UnverifiedFunction"), fn("/ActualLoaded/Hun.Hun_C:On Dead__DelegateSignature") }, baseClass)
local livePlayer = object("livePlayer", { GetClass = function() return hunClass end, AttributeSetBase = attributes })
p = Probe.new({ config = { IncludeNativeCombat = false }, log = function(s) messages[#messages + 1] = s end })
assert(p:start("discovered", { livePlayer, livePlayer, object("invalidSubject", {}, false) }))
assert(#registrations == 6, "one native OnDamage and five deduplicated discovered functions expected")
assert(p:status().discovery.selected == 5 and p:status().discovery.classes == 2)
local actual = {}
for _, h in ipairs(registrations) do
    actual[h.path] = true
    if h.path:sub(1, 8) ~= "/Script/" then assert(h.post == nil, "discovered scripts use second callback") end
end
assert(actual[hunPath] and actual[mixinPath] and actual[parentPath] and actual[changedPath] and actual[eventPath])
assert(not actual[delegatePath])
hook("Health Post Func__puerts_mixin__").pre(param(livePlayer), param(375), param(400))
assert(contains("new_value=375 | old_value=400 | hp_readback=400"))
hook("Changed_65C423C64D9460919B5AC49EEE1A1401").pre(param(livePlayer),
    param({ AttributeName = "Health" }), param(350), param(375))
assert(contains("attribute=Health | new_value=350 | old_value=375"))
hook("EventReceived_B1FF86534050CD4041F4E69109D6C58E").pre(param(livePlayer), param({
    EventTag = { TagName = "Event.Damage" }, Instigator = attacker, Target = victim, EventMagnitude = 25 }))
assert(contains("event_tag=Event.Damage | instigator=attacker@attacker | target=victim@victim | magnitude=25"))
p:stop()

reset()
local invalidParent = object("invalidParent", {}, false)
local emptyClass = class("empty", {}, invalidParent)
local unknownPlayer = object("unknownPlayer", { GetClass = function() return emptyClass end })
p = Probe.new({ log = function(s) messages[#messages + 1] = s end })
assert(p:start("no_guessed_paths", { unknownPlayer }))
assert(#registrations == 7 and p:status().discovery.selected == 0)
p:stop()

reset()
local cyclicClass
cyclicClass = object("cycle", { ForEachFunction = function() end, GetSuperStruct = function() return cyclicClass end })
p = Probe.new({ log = function() end })
assert(p:start("cycle_guard", { object("cycleSubject", { GetClass = function() return cyclicClass end }) }))
assert(p:status().discovery.classes == 1)
p:stop()

reset()
local chain
for i = 15, 1, -1 do chain = class("class" .. i, {}, chain) end
p = Probe.new({ log = function() end })
assert(p:start("depth_guard", { object("deepSubject", { GetClass = function() return chain end }) }))
assert(p:status().discovery.classes == 12 and p:status().discovery.limited)
p:stop()
os.time = realTime
reset()
local production=dofile('Mods/PhantomGladiator/Scripts/config.lua')
assert(production.Probe.Enabled==false)
StaticFindObject=function() error('disabled probe must never touch a UObject') end
RegisterHook=function() error('disabled probe must never register') end
p=Probe.new({config=production.Probe,log=function() end})
assert(not p:start('arena_duel',{}))
assert(#registrations==0 and #timers==0)
print("combat_probe: PASS (native ABI, game-thread one-shots, executing cancellation, stale timers, budgets, discovery, cleanup)")
