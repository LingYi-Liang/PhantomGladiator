-- 战斗会话与可读回的恢复账本。这里不调用 UE API；对象有效性由传入回调检查。
-- 必须在游戏线程中调用 begin/cancel/change/restore/reset；异步任务排进游戏线程
-- 后再次检查 isCurrent(token)，不要只在排队前检查。
local Session = {}
Session.__index = Session

local function same(a, b) return a == b end

function Session.new(log)
    return setmetatable({
        generation = 0,
        active = false,
        label = nil,
        records = {},
        byKey = {},
        log = log or function() end,
    }, Session)
end

function Session:begin(label)
    self.generation = self.generation + 1
    self.active = true
    self.label = label or "battle"
    -- 开始新配对不能丢弃旧配对尚未恢复的快照。
    self.log(string.format("会话开始 #%d: %s（待恢复 %d 项）",
        self.generation, self.label, #self.records))
    return self.generation
end

function Session:currentToken()
    return self.active and self.generation or nil
end

function Session:isCurrent(token)
    return self.active and token == self.generation
end

function Session:cancel(reason)
    self.generation = self.generation + 1
    self.active = false
    self.label = nil
    self.log(string.format("会话取消: %s；代次=%d（待恢复 %d 项）",
        tostring(reason or "cancel"), self.generation, #self.records))
end

-- restoreFn 必须返回 true, detail，且 true 只能表示已经读回验证成功。
-- 失败或抛出 Lua 错误的记录会保留。相同 key 始终保留首次修改前的快照。
function Session:remember(key, restoreFn)
    assert(type(key) == "string" and key ~= "", "snapshot key must be a nonempty string")
    assert(type(restoreFn) == "function", "restoreFn must be a function")
    if self.byKey[key] then return false end
    local record = { key = key, restore = restoreFn }
    self.byKey[key] = record
    self.records[#self.records + 1] = record
    return true
end

function Session:pendingCount()
    return #self.records
end

-- 简单属性/单个碰撞通道的读写助手。readFn 返回值；writeFn(value) 完成写入。
-- 回调要自行逐级 IsValid，不能把 pcall 当作 UObject 原生崩溃保护。
-- equalsFn 可选，默认适用于 bool/number/string。即使写入失败，也保留恢复账本。
function Session:change(key, readFn, writeFn, desired, equalsFn)
    local equals = equalsFn or same
    local okBefore, before = pcall(readFn)
    if not okBefore then
        local detail = "修改前读取失败: " .. tostring(before)
        self.log(key .. " " .. detail .. "；未写入")
        return false, detail
    end
    self:remember(key, function()
        local okWrite, writeError = pcall(writeFn, before)
        local okRead, actual = pcall(readFn)
        local okCompare, matches = false, false
        if okRead then okCompare, matches = pcall(equals, actual, before) end
        local detail = string.format("恢复目标=%s；读回=%s；写入=%s",
            tostring(before), okRead and tostring(actual) or ("读取失败: " .. tostring(actual)),
            okWrite and "已调用" or ("失败: " .. tostring(writeError)))
        return okWrite and okRead and okCompare and matches == true, detail
    end)
    local okWrite, writeError = pcall(writeFn, desired)
    local okRead, actual = pcall(readFn)
    local okCompare, matches = false, false
    if okRead then okCompare, matches = pcall(equals, actual, desired) end
    local detail = string.format("修改前=%s；写入目标=%s；读回=%s；写入=%s",
        tostring(before), tostring(desired),
        okRead and tostring(actual) or ("读取失败: " .. tostring(actual)),
        okWrite and "已调用" or ("失败: " .. tostring(writeError)))
    local verified = okWrite and okRead and okCompare and matches == true
    self.log(key .. " " .. detail .. "；验证=" .. tostring(verified))
    return verified, detail
end

-- 逆序恢复；任何旧异步任务都应先失效。失败条目原样保留，下次可重试。
-- 返回 allVerified, restoredCount, failedCount。
function Session:restore()
    if self.active then self:cancel("restore") end
    local restored, failed = 0, 0
    local sampled, omitted={},0
    local bulk=#self.records>48
    local gone={}
    for i = #self.records, 1, -1 do
        local record = self.records[i]
        local called, verified, detail = pcall(record.restore,gone)
        if not called then detail = verified end
        local ok=called and verified==true
        local kind=record.key:match('^(%w+):')
        local emit=true
        if bulk and (kind=='relation' or kind=='hatred' or kind=='blackboard') then
            local group=kind..tostring(ok)
            sampled[group]=(sampled[group] or 0)+1
            if sampled[group]>3 then emit=false;omitted=omitted+1 end
        end
        if ok then
            if emit then self.log("恢复 " .. record.key .. "：读回验证成功；" .. tostring(detail or "")) end
            self.byKey[record.key] = nil
            self.records[i]=false
            restored = restored + 1
        else
            if emit then self.log("恢复 " .. record.key .. "：未验证成功，保留待重试；"
                .. tostring(detail or "恢复回调未返回 true")) end
            failed = failed + 1
        end
    end
    local kept=0
    for i=1,#self.records do
        if self.records[i] then kept=kept+1;self.records[kept]=self.records[i] end
    end
    for i=#self.records,kept+1,-1 do self.records[i]=nil end
    if omitted>0 then self.log(string.format("批量恢复读回：成功 %d 项，待重试 %d 项，同类明细合并 %d 行",restored,failed,omitted)) end
    return failed == 0, restored, failed
end

function Session:reset(reason)
    self:cancel(reason or "reset")
    return self:restore()
end

return Session
