-- 只验证采样器边界/缓存/参数连接，不模拟或证明 UE 攻击实现。
local Profile = dofile("Mods/PhantomGladiator/Scripts/attack_profile.lua")
local tests, nextId = 0, 100

local function object(name, fields)
    nextId = nextId + 1
    local value = fields or {}
    value.alive, value.name, value.address = true, name, nextId
    function value:GetFullName() assert(self.alive) return self.name end
    function value:GetAddress() assert(self.alive) return self.address end
    function value:GetClass() assert(self.alive) return self.class end
    return value
end

local function valid(value) return type(value) == "table" and value.alive == true end
local function tag(name)
    return { TagName = { ToString = function() return name end } }
end
local function test(name, body)
    body()
    tests = tests + 1
    print("PASS " .. name)
end

local function fixture()
    local a, b, player = object("A"), object("B"), object("Player")
    local calculatorClass = object("FactionCalculator_Map")
    local calculator = object("Calculator", { class = calculatorClass })
    local module = object("AttackModule", {
        TargetRequiredTags = { GameplayTags = { tag("Target.Player") } },
        TargetIgnoredTags = { GameplayTags = {} },
        FactionCalculator = calculator, LastOwnerAvatar = a,
    })
    local calls = 0
    function module:IsValidTarget(target) calls = calls + 1 return target == player end
    local sweep = object("Sweep", { TraceChannel = 7, IgnoreOwner = true, IgnoredActors = { a } })
    local data = object("SharedData", { FactionTarget = 0, FactionCanTargetSelf = false })
    local bullet = object("Bullet", { BulletOwnerAvatar = a, BulletStatus = 2, Destroyed = false,
        AttackModule = module, SweepTraceModule = sweep, MyData = data })
    local logs, list = {}, { bullet }
    local profile = Profile.new({ valid = valid,
        log = function(line) logs[#logs + 1] = line end,
        findAll = function(name) assert(name == "PBZ_SweepTraceBullet") return list end })
    return { a = a, b = b, player = player, module = module, sweep = sweep, data = data,
        bullet = bullet, list = list, profile = profile, logs = logs,
        calls = function() return calls end }
end

test("only running owned instances and boolean target readbacks", function()
    local f = fixture()
    f.list[2] = object("Idle", { BulletOwnerAvatar = f.a, BulletStatus = 1, Destroyed = false })
    f.list[3] = object("Destroyed", { BulletOwnerAvatar = f.a, BulletStatus = 2, Destroyed = true })
    f.list[4] = object("Other", { BulletOwnerAvatar = f.player, BulletStatus = 2, Destroyed = false })
    local result = f.profile:sample({ f.a, f.b }, "start", f.player)
    assert(result.totalFound == 4 and result.scanned == 4 and result.matched == 1)
    assert(#result.entries == 1 and result.queryCalls == 2)
    local e = result.entries[1]
    assert(e.side == "A" and e.requiredTags.values[1] == "Target.Player")
    assert(e.opponentQuery.value == false and e.opponentQuery.returnType == "boolean")
    assert(e.playerQuery.value == true and e.traceType == "ETraceTypeQuery" and e.traceChannel == 7)
    assert(e.ignoredActors.hasA == true and e.ignoredActors.hasB == false)
    assert(f.data.FactionTarget == 0 and f.module.TargetRequiredTags.GameplayTags[1].TagName:ToString() == "Target.Player")
end)

test("unchanged content is quiet and queries are not repeated", function()
    local f = fixture()
    f.profile:sample({ f.a, f.b }, "tick1", f.player)
    local before = #f.logs
    local result = f.profile:sample({ f.a, f.b }, "tick2", f.player)
    assert(#f.logs == before and result.queryCalls == 0 and f.calls() == 2)
    assert(result.entries[1].queryObservedPhase == "tick1")
end)

test("same object address with changed structure is observed again", function()
    local f = fixture()
    f.profile:sample({ f.a, f.b }, "tick1", f.player)
    local before = #f.logs
    f.module.TargetIgnoredTags.GameplayTags[1] = tag("Target.NPC")
    local result = f.profile:sample({ f.a, f.b }, "tick2", f.player)
    assert(#f.logs == before + 1 and result.queryCalls == 2 and f.calls() == 4)
    assert(result.entries[1].ignoredTags.values[1] == "Target.NPC")
end)

test("scan cap rotates past idle pooled objects", function()
    local f = fixture()
    for i = 1, 512 do
        f.list[i] = object("Idle" .. i, { BulletOwnerAvatar = f.a, BulletStatus = 1, Destroyed = false })
    end
    f.list[513] = f.bullet
    local first = f.profile:sample({ f.a, f.b }, "first", f.player)
    assert(first.totalFound == 513 and first.scanned == 512 and first.truncated and #first.entries == 0)
    local second = f.profile:sample({ f.a, f.b }, "second", f.player)
    assert(second.scanned == 512 and second.scanStart == 513 and #second.entries == 1)
end)

test("eight instance and eight target query budgets", function()
    local f = fixture()
    for i = 1, 10 do
        local module = object("Module" .. i, { TargetRequiredTags = { GameplayTags = {} },
            TargetIgnoredTags = { GameplayTags = {} } })
        function module:IsValidTarget() return true end
        f.list[i] = object("Bullet" .. i, { BulletOwnerAvatar = f.a, BulletStatus = 2,
            Destroyed = false, AttackModule = module })
    end
    local result = f.profile:sample({ f.a, f.b }, "budget", f.player)
    assert(result.matched == 10 and #result.entries == 8 and result.entryLimitReached)
    assert(result.queryCalls == 8)
    assert(result.entries[5].opponentQuery.value == "UNKNOWN")
    local nextResult = f.profile:sample({ f.a, f.b }, "next", f.player)
    assert(nextResult.queryCalls == 8 and nextResult.entries[8].opponentQuery.value == true)
end)

test("invalid inner objects are never dereferenced", function()
    local f = fixture()
    local dead = setmetatable({ alive = false }, { __index = function() error("invalid dereference") end })
    f.module.FactionCalculator, f.module.LastOwnerAvatar = dead, dead
    f.bullet.SweepTraceModule, f.bullet.MyData = dead, dead
    f.list[2] = dead
    local result = f.profile:sample({ f.a, f.b }, "invalid", f.player)
    assert(#result.entries == 1 and result.entries[1].calculator == "UNKNOWN")
    assert(result.entries[1].myData == "UNKNOWN" and result.entries[1].traceChannel == "UNKNOWN")
end)

test("non boolean and failed queries stay UNKNOWN without endless retries", function()
    local f = fixture()
    local calls = 0
    function f.module:IsValidTarget(target)
        calls = calls + 1
        if target == f.player then error("query unavailable") end
        return 1
    end
    local result = f.profile:sample({ f.a, f.b }, "first", f.player)
    assert(result.entries[1].opponentQuery.returnType == "number")
    assert(result.entries[1].opponentQuery.value == "UNKNOWN")
    assert(result.entries[1].playerQuery.returnType == "error")
    f.profile:sample({ f.a, f.b }, "second", f.player)
    assert(calls == 2)
end)

test("truncated ignored list cannot prove the opponent is absent", function()
    local f = fixture()
    for i = 1, 64 do f.sweep.IgnoredActors[i] = object("Ignored" .. i) end
    f.sweep.IgnoredActors[65] = f.b
    local result = f.profile:sample({ f.a, f.b }, "truncated", f.player)
    assert(result.entries[1].ignoredActors.truncated)
    assert(result.entries[1].ignoredActors.hasB == "UNKNOWN")
end)

test("per battle log caps do not stop scans or queries", function()
    local f = fixture()
    local result
    for i = 1, 70 do
        f.module.TargetRequiredTags.GameplayTags[1] = tag("Target.Variant" .. i)
        f.list[i + 1] = object("Idle" .. i, { BulletOwnerAvatar = f.a, BulletStatus = 1, Destroyed = false })
        result = f.profile:sample({ f.a, f.b }, "tick" .. i, f.player)
        assert(result.queryCalls == 2 and result.scanned == i + 1)
    end
    assert(result.loggedDetail == 64 and result.loggedStats == 24 and #f.logs == 88)
    assert(result.suppressedDetail == 6 and result.suppressedStats == 46 and result.suppressed == 52)
    assert(f.calls() == 140 and result.entries[1].requiredTags.values[1] == "Target.Variant70")
    local notices = 0
    for _, line in ipairs(f.logs) do
        if line:find("达到上限", 1, true) then notices = notices + 1 end
    end
    assert(notices == 2)
    local repeated = f.profile:sample({ f.a, f.b }, "unchanged", f.player)
    assert(repeated.suppressed == 52 and repeated.queryCalls == 0)
end)

print(string.format("%d attack profile tests passed; no UE runtime assertions made.", tests))
