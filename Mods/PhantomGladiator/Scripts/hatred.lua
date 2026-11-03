-- V2 仇恨矩阵（实验性骨架，默认由 config.EnableHatred 关闭）
--
-- 思路：hook 伤害事件，给 (受害者, 攻击者) 这一对累积仇恨值；
-- 仇恨随时间衰减；超过阈值的一对视为"结仇"，由 main.lua 决定
-- 是否据此改写阵营。真正接入要等解包确认本作的伤害事件名。
local Config = require("config")

local Hatred = {}

-- matrix[victimAddr][attackerAddr] = { hate = number, lastHit = os.clock() }
local matrix = {}

local function key(actor)
    local ok, addr = pcall(function() return actor:GetAddress() end)
    return ok and addr or nil
end

function Hatred.AddHate(victim, attacker, amount)
    local v, a = key(victim), key(attacker)
    if not v or not a or v == a then return end
    matrix[v] = matrix[v] or {}
    local entry = matrix[v][a] or { hate = 0, lastHit = os.clock() }
    -- 先按时间衰减再累加
    local now = os.clock()
    entry.hate = math.max(0, entry.hate - (now - entry.lastHit) * Config.HatredDecayPerSecond)
    entry.hate = entry.hate + amount
    entry.lastHit = now
    matrix[v][a] = entry
end

--- 返回 victim 当前最恨的攻击者地址（超过阈值才算），否则 nil
function Hatred.TopGrudge(victim)
    local v = key(victim)
    if not v or not matrix[v] then return nil end
    local best, bestHate = nil, Config.HatredThreshold
    local now = os.clock()
    for attacker, entry in pairs(matrix[v]) do
        local hate = math.max(0, entry.hate - (now - entry.lastHit) * Config.HatredDecayPerSecond)
        if hate >= bestHate then
            best, bestHate = attacker, hate
        end
    end
    return best, best and bestHate or nil
end

function Hatred.Reset()
    matrix = {}
end

--- 尝试注册伤害 hook。失败（本作不走该事件）则返回 false，不影响其余功能。
function Hatred.TryInstallHook(log)
    local ok, err = pcall(function()
        RegisterHook(Config.DamageHookFunction, function(selfActor, damage, _, _, instigatedBy)
            local victim = selfActor:get()
            local amount = damage and damage:get() or 1
            local attackerController = instigatedBy and instigatedBy:get()
            local attacker = nil
            if attackerController and attackerController:IsValid() then
                pcall(function() attacker = attackerController.Pawn end)
            end
            if victim and attacker then
                Hatred.AddHate(victim, attacker, amount)
            end
        end)
    end)
    if ok then
        log(string.format("仇恨矩阵已挂载到 %s", Config.DamageHookFunction))
    else
        log(string.format("仇恨矩阵 hook 失败（预期内，待解包后换成本作事件名）: %s", tostring(err)))
    end
    return ok
end

return Hatred
