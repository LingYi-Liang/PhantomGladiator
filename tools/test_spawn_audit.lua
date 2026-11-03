-- 生成阶段持久化防护测试；只使用内存IO，不写真实游戏Runtime，不复现原生崩溃。
local Audit = dofile("Mods/PhantomGladiator/Scripts/spawn_audit.lua")
assert(type(Audit) == "table", "spawn_audit must return its module table")
local originalOpen, originalTime = io.open, os.time
os.time = function() return 1000 end
local bytes, events, logs, failStage, failValue = "", {}, {}, nil, nil
local path = "D:/in-memory-only/Runtime/spawn-audit.tsv"
io.open = function(actualPath, mode)
    assert(actualPath == path and mode == "a", "audit must append to only the provided path")
    events[#events + 1] = "open"
    if failStage == "open" then return failValue, "open failed" end
    return {
        write = function(self, line)
            events[#events + 1] = "write"
            if failStage == "write" then return failValue, "write failed" end
            bytes = bytes .. line; return self
        end,
        flush = function()
            events[#events + 1] = "flush"
            if failStage == "flush" then return failValue, "flush failed" end
            return true
        end,
        close = function()
            events[#events + 1] = "close"
            if failStage == "close" then return failValue, "close failed" end
            return true
        end,
    }
end
local audit = Audit.new(path, function(s) logs[#logs + 1] = s end)
assert(audit:record("before_load", "/Package/Class.Class_C", "attempt=1") == true)
assert(audit:record("after\tload\n", "/Package/Class.Class_C", "readback\r\nok") == true)
assert(table.concat(events, ",") == "open,write,flush,close,open,write,flush,close")
local lineCount, failures = 0, {}
for line in bytes:gmatch("[^\n]+") do
    lineCount = lineCount + 1
    local fields = 1
    for _ in line:gmatch("\t") do fields = fields + 1 end
    if fields ~= 5 then failures[#failures + 1] = "record " .. lineCount .. " has " .. fields .. " TSV fields; expected 5" end
    assert(line:match("^1000\t" .. lineCount .. "\t"), "serial must increase across appended records")
end
assert(lineCount == 2)
local formatFailures = #failures
for _, stage in ipairs({ "open", "write", "flush", "close" }) do
    for _, value in ipairs({ "nil", "false" }) do
        failStage = stage
        -- 显式保留false故障返回。
        if value == "false" then failValue = false else failValue = nil end
        events = {}
        local ok, result = pcall(audit.record, audit, "before_spawn", "/Package/Class.Class_C", "failure case")
        if ok and result == true then failures[#failures + 1] = stage .. " returned " .. value .. " but record returned true" end
        if stage ~= "open" then
            assert(events[#events] == "close", "file must be closed after a non-throwing IO failure")
        end
    end
end
io.open, os.time = originalOpen, originalTime
if #failures == formatFailures then print("spawn_audit IO gate: PASS (nil/false from open/write/flush/close never passes)") end
for _, failure in ipairs(failures) do print("FAIL: " .. failure) end
assert(#failures == 0, "audit record format or persistence gate failed")
print("spawn_audit: PASS (append stages, exact path, write/flush/close success gate, failure rejection; no native crash reproduced)")
