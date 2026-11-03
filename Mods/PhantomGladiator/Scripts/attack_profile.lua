-- 只读记录当前配对的原生扫掠攻击实例，不依赖 native hook 是否触发。
-- 依据：PBZCombatAsset.hpp:3731 / SGameCombatSystem.hpp:992,1412,1580。
-- sample 必须在游戏线程执行；所有 UObject 逐级验证。不会改共享 DataAsset。
local Profile = {}
Profile.__index = Profile
local UNKNOWN = "UNKNOWN"

local function short(value)
    local s = tostring(value):gsub("[\r\n]", " ")
    return #s > 180 and s:sub(1, 180) .. "..." or s
end

local function signature(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = signature(key) .. "=" .. signature(value[key])
    end
    return "{" .. table.concat(parts, ";") .. "}"
end

function Profile.new(options)
    options = options or {}
    return setmetatable({
        log = options.log or function() end,
        valid = options.valid or function(obj) return obj ~= nil and obj:IsValid() end,
        findAll = options.findAll or function(name) return FindAllOf(name) end,
        seen = {}, seenOrder = {}, queries = {}, queryOrder = {}, lastStats = nil, scanOffset = 0,
        logCounts = { detail = 0, stats = 0 }, suppressedCounts = { detail = 0, stats = 0 },
    }, Profile)
end

function Profile:_emit(kind, message)
    local limit = kind == "detail" and 64 or 24
    if self.logCounts[kind] >= limit then
        self.suppressedCounts[kind] = self.suppressedCounts[kind] + 1
        return
    end
    self.logCounts[kind] = self.logCounts[kind] + 1
    if self.logCounts[kind] == limit then
        message = message .. string.format("；本场%s日志达到上限%d，后续只计数，扫描与查询继续", kind, limit)
    end
    self.log(message)
end

function Profile:_valid(obj)
    local ok, valid = pcall(self.valid, obj)
    return ok and valid == true
end

function Profile:_read(obj, field)
    if not self:_valid(obj) then return nil end
    local ok, value = pcall(function() return obj[field] end)
    if ok then return value end
    return nil
end

function Profile:_name(obj)
    if not self:_valid(obj) then return UNKNOWN end
    local ok, name = pcall(function() return obj:GetFullName() end)
    return ok and type(name) == "string" and short(name) or UNKNOWN
end

function Profile:_address(obj)
    if not self:_valid(obj) then return nil end
    local ok, address = pcall(function() return obj:GetAddress() end)
    if ok and (type(address) == "number" or type(address) == "string") then
        return tostring(address)
    end
    return nil
end

function Profile:_class(obj)
    if not self:_valid(obj) then return UNKNOWN end
    local ok, cls = pcall(function() return obj:GetClass() end)
    return ok and self:_name(cls) or UNKNOWN
end

local function scalar(value)
    local kind = type(value)
    if kind == "number" or kind == "boolean" or kind == "string" then return value end
    return UNKNOWN
end

local function arrayCount(array)
    if array == nil then return nil end
    local ok, count = pcall(function() return #array end)
    if ok and type(count) == "number" and count >= 0 then return count end
    return nil
end

local function arrayItem(array, index)
    local ok, value = pcall(function() return array[index] end)
    return ok and value or nil
end

-- FGameplayTagContainer/FGameplayTag 是结构体，不是 UObject。
local function tags(container)
    local ok, array = pcall(function() return container.GameplayTags end)
    local count = ok and arrayCount(array) or nil
    if count == nil then return { value = UNKNOWN } end
    local out = { count = count, values = {}, truncated = count > 32 }
    for i = 1, math.min(count, 32) do
        local item = arrayItem(array, i)
        local okTag, value = pcall(function() return item.TagName:ToString() end)
        out.values[#out.values + 1] = okTag and type(value) == "string" and short(value) or UNKNOWN
    end
    return out
end

function Profile:_ignored(array, a, b)
    local count = arrayCount(array)
    if count == nil then return { value = UNKNOWN, hasA = UNKNOWN, hasB = UNKNOWN } end
    local out = { count = count, names = {}, truncated = count > 64, hasA = false, hasB = false }
    local complete = count <= 64
    for i = 1, math.min(count, 64) do
        local actor = arrayItem(array, i)
        local address = self:_address(actor)
        if not address then complete = false end
        if a and address == a then out.hasA = true end
        if b and address == b then out.hasB = true end
        if i <= 16 then out.names[#out.names + 1] = self:_name(actor) end
    end
    if not out.hasA and (not complete or not a) then out.hasA = UNKNOWN end
    if not out.hasB and (not complete or not b) then out.hasB = UNKNOWN end
    return out
end

function Profile:_cache(cache, order, key, value)
    if cache[key] == nil then order[#order + 1] = key end
    cache[key] = value
    if #order > 256 then cache[table.remove(order, 1)] = nil end
end

function Profile:_targetQuery(module, target)
    if not self:_valid(module) or not self:_valid(target) then
        return { action = "未调用IsValidTarget", value = UNKNOWN, returnType = "invalid object" }
    end
    local ok, result = pcall(function() return module:IsValidTarget(target) end)
    local value = UNKNOWN
    if ok and type(result) == "boolean" then value = result end
    return {
        action = "调用IsValidTarget",
        returnType = ok and type(result) or "error",
        value = value,
        boolean = ok and type(result) == "boolean",
        raw = short(result),
    }
end

-- 返回纯 Lua 快照 {entries, scanned, matched, truncated, queryCalls, ...}。
-- 每轮最多检查 512 个 bullet、处理/输出 8 个实例、执行 8 次目标查询。
function Profile:sample(subjects, phase, player)
    subjects = subjects or {}
    local a, b = self:_address(subjects[1]), self:_address(subjects[2])
    local result = { entries = {}, totalFound = 0, scanned = 0, matched = 0, truncated = false,
        queryCalls = 0, unknownState = 0, phase = short(phase or "battle") }
    if not a or not b then
        result.error = "A/B对象无效"
    else
        local ok, bullets = pcall(self.findAll, "PBZ_SweepTraceBullet")
        if not ok or type(bullets) ~= "table" then
            result.error = "FindAllOf结果不可用: " .. (ok and type(bullets) or short(bullets))
        else
            result.totalFound = #bullets
            result.truncated = #bullets > 512
            local offset = #bullets > 0 and self.scanOffset % #bullets or 0
            result.scanStart = offset + 1
            for step = 1, math.min(#bullets, 512) do
                local i = (offset + step - 1) % #bullets + 1
                result.scanned = result.scanned + 1
                local bullet = bullets[i]
                local owner = self:_read(bullet, "BulletOwnerAvatar")
                local ownerAddress = self:_address(owner)
                if ownerAddress == a or ownerAddress == b then
                    local status = self:_read(bullet, "BulletStatus")
                    local destroyed = self:_read(bullet, "Destroyed")
                    if type(status) ~= "number" or type(destroyed) ~= "boolean" then
                        result.unknownState = result.unknownState + 1
                    elseif status == 2 and destroyed == false then
                        result.matched = result.matched + 1
                        if #result.entries < 8 then
                            local module = self:_read(bullet, "AttackModule")
                            local sweep = self:_read(bullet, "SweepTraceModule")
                            local data = self:_read(bullet, "MyData")
                            local calculator = self:_read(module, "FactionCalculator")
                            local lastOwner = self:_read(module, "LastOwnerAvatar")
                            local entry = {
                                side = ownerAddress == a and "A" or "B",
                                bullet = self:_name(bullet), bulletAddress = self:_address(bullet) or UNKNOWN,
                                owner = self:_name(owner), ownerAddress = ownerAddress,
                                status = status, destroyed = destroyed,
                                attackModule = self:_name(module), moduleAddress = self:_address(module) or UNKNOWN,
                                requiredTags = tags(self:_read(module, "TargetRequiredTags")),
                                ignoredTags = tags(self:_read(module, "TargetIgnoredTags")),
                                calculator = self:_name(calculator), calculatorClass = self:_class(calculator),
                                lastOwner = self:_name(lastOwner), lastOwnerAddress = self:_address(lastOwner) or UNKNOWN,
                                myData = self:_name(data), factionTarget = scalar(self:_read(data, "FactionTarget")),
                                factionCanTargetSelf = scalar(self:_read(data, "FactionCanTargetSelf")),
                                sweepModule = self:_name(sweep), traceType = "ETraceTypeQuery",
                                traceChannel = scalar(self:_read(sweep, "TraceChannel")),
                                ignoreOwner = scalar(self:_read(sweep, "IgnoreOwner")),
                                ignoredActors = self:_ignored(self:_read(sweep, "IgnoredActors"), a, b),
                                opponentAddress = ownerAddress == a and b or a,
                                playerAddress = self:_address(player) or UNKNOWN,
                            }
                            local base = signature(entry)
                            local cached = self.queries[entry.moduleAddress]
                            if cached and cached.signature == base then
                                entry.opponentQuery, entry.playerQuery = cached.opponent, cached.player
                                entry.queryObservedPhase = cached.phase
                            else
                                local target = ownerAddress == a and subjects[2] or subjects[1]
                                local needed = self:_valid(player) and 2 or 1
                                if result.queryCalls + needed <= 8 and self:_valid(module) then
                                    entry.opponentQuery = self:_targetQuery(module, target)
                                    result.queryCalls = result.queryCalls + 1
                                    if self:_valid(player) then
                                        entry.playerQuery = self:_targetQuery(module, player)
                                        result.queryCalls = result.queryCalls + 1
                                    else
                                        entry.playerQuery = { value = UNKNOWN, action = "未提供有效player" }
                                    end
                                    entry.queryObservedPhase = result.phase
                                    self:_cache(self.queries, self.queryOrder, entry.moduleAddress,
                                        { signature = base, opponent = entry.opponentQuery,
                                            player = entry.playerQuery, phase = result.phase })
                                else
                                    entry.opponentQuery = { value = UNKNOWN, action = "未调用:预算不足或模块无效" }
                                    entry.playerQuery = { value = UNKNOWN, action = "未调用" }
                                end
                            end
                            result.entries[#result.entries + 1] = entry
                            local fingerprint = signature(entry)
                            if self.seen[entry.bulletAddress] ~= fingerprint then
                                self:_emit("detail", "攻击配置[" .. result.phase .. "] " .. fingerprint)
                                self:_cache(self.seen, self.seenOrder, entry.bulletAddress, fingerprint)
                            end
                        end
                    end
                end
            end
            -- 轮换有界扫描窗口，不让池中前 512 个闲置实例永久遮住后面的活跃实例。
            self.scanOffset = #bullets > 0 and (offset + result.scanned) % #bullets or 0
        end
    end
    result.entryLimitReached = result.matched > #result.entries
    local stats = signature({ totalFound = result.totalFound, scanned = result.scanned, matched = result.matched,
        truncated = result.truncated, unknownState = result.unknownState, error = result.error })
    if stats ~= self.lastStats then
        self:_emit("stats", "攻击配置扫描[" .. result.phase .. "] " .. stats .. "; 输出实例上限=8; TraceChannel是ETraceTypeQuery，不能直接当CollisionChannel")
        self.lastStats = stats
    end
    result.loggedDetail, result.loggedStats = self.logCounts.detail, self.logCounts.stats
    result.suppressedDetail, result.suppressedStats = self.suppressedCounts.detail, self.suppressedCounts.stats
    result.suppressed = result.suppressedDetail + result.suppressedStats
    return result
end

return Profile
