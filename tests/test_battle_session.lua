-- 纯 Lua 生命周期/恢复测试；不模拟或证明任何 UE 对象、命中或伤害行为。
-- 从仓库根目录运行：texlua tests/test_battle_session.lua
local Session = dofile("Mods/PhantomGladiator/Scripts/battle_session.lua")
local count = 0

local function test(name, body)
    body()
    count = count + 1
    print("PASS " .. name)
end

test("queued work becomes stale when reset cancels before restoring", function()
    local s = Session.new()
    local token = s:begin("one")
    assert(s:currentToken() == token)
    local writes = 0
    local queued = function()
        if not s:isCurrent(token) then return end
        writes = writes + 1
    end
    s:remember("value", function()
        queued() -- 已排入游戏线程的旧任务必须在真正执行时失效。
        assert(s:currentToken() == nil)
        return true, "readback verified"
    end)
    local ok, restored, failed = s:reset("F4")
    queued()
    assert(ok and restored == 1 and failed == 0 and writes == 0)
end)

test("new pair invalidates old token without losing restoration", function()
    local s = Session.new()
    local first = s:begin("first")
    local restored = false
    s:remember("old pair", function() restored = true return true end)
    local second = s:begin("second")
    assert(not s:isCurrent(first) and s:isCurrent(second))
    assert(s:pendingCount() == 1)
    assert(s:restore())
    assert(restored and not s:isCurrent(second))
end)

test("same key keeps its first baseline across sessions", function()
    local s = Session.new()
    local value = 0
    local read = function() return value end
    local write = function(v) value = v end
    s:begin("first")
    assert(s:change("component:channel:19", read, write, 1))
    s:begin("second")
    assert(s:change("component:channel:19", read, write, 2))
    assert(value == 2 and s:pendingCount() == 1)
    assert(s:reset())
    assert(value == 0 and s:pendingCount() == 0)
end)

test("restore runs in reverse order and retains failures for retry", function()
    local s = Session.new()
    local order, ready = {}, false
    s:remember("a", function() order[#order + 1] = "a" return true end)
    s:remember("b", function() order[#order + 1] = "b" return ready, "readback" end)
    s:remember("c", function() order[#order + 1] = "c" return true end)
    local ok, restored, failed = s:restore()
    assert(not ok and restored == 2 and failed == 1)
    assert(table.concat(order) == "cba" and s:pendingCount() == 1)
    assert(not s:remember("b", function() error("must keep original callback") end))
    ready = true
    ok, restored, failed = s:restore()
    assert(ok and restored == 1 and failed == 0 and s:pendingCount() == 0)
    assert(table.concat(order) == "cbab")
end)

test("restore exceptions and missing readback success are not discarded", function()
    local s = Session.new()
    s:remember("throws", function() error("unavailable object") end)
    s:remember("no readback", function() end)
    local ok, restored, failed = s:restore()
    assert(not ok and restored == 0 and failed == 2 and s:pendingCount() == 2)
end)

test("failed initial read never writes or snapshots a guessed baseline", function()
    local s = Session.new()
    local writes = 0
    local ok = s:change("x", function() error("read unavailable") end,
        function() writes = writes + 1 end, true)
    assert(not ok and writes == 0 and s:pendingCount() == 0)
end)

test("unchanged readback reports failure and keeps restoration", function()
    local logs, value = {}, false
    local s = Session.new(function(line) logs[#logs + 1] = line end)
    local ok = s:change("CanBeHatredNow", function() return value end,
        function() end, true)
    assert(not ok and value == false and s:pendingCount() == 1)
    assert(logs[#logs]:find("false", 1, true))
    assert(s:reset()) -- 原值本来就是 false，恢复必须按读回判断。
end)

test("partial write exception preserves the original for recovery", function()
    local s = Session.new()
    local value = 4
    local ok = s:change("x", function() return value end, function(v)
        value = v
        if v == 9 then error("write failed after mutation") end
    end, 9)
    assert(not ok and value == 9 and s:pendingCount() == 1)
    assert(s:reset())
    assert(value == 4)
end)

test("only the addressed property is restored", function()
    local s = Session.new()
    local channels = { [14] = 2, [19] = 0, [31] = 0 }
    assert(s:change("mesh:19", function() return channels[19] end,
        function(v) channels[19] = v end, 2))
    channels[14], channels[31] = 1, 1 -- 其他游戏行为修改未被快照的通道。
    assert(s:reset())
    assert(channels[19] == 0 and channels[14] == 1 and channels[31] == 1)
end)

test("failed restore readback keeps its original baseline until retry succeeds", function()
    local s = Session.new()
    local value, writable = 0, true
    assert(s:change("channel", function() return value end, function(v)
        if writable then value = v end
    end, 2))
    writable = false
    local ok, restored, failed = s:reset()
    assert(not ok and restored == 0 and failed == 1 and value == 2)
    assert(s:pendingCount() == 1)
    writable = true
    ok, restored, failed = s:restore()
    assert(ok and restored == 1 and failed == 0 and value == 0)
end)

print(string.format("%d battle session tests passed; no UE runtime assertions made.", count))
