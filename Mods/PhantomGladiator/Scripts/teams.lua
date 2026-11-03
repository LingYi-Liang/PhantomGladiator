-- 阵营写入模块：对一个 Pawn 依次尝试多种策略，返回成功的策略名或 nil
local Config = require("config")

local Teams = {}

-- FGenericTeamId 是个只有一个 uint8 字段 (Id) 的结构体；
-- 有的游戏直接暴露整数属性。两种写法都试。
local function tryWriteProperty(obj, propName, teamId)
    if not obj or not obj:IsValid() then return false end
    -- 结构体写法: obj.GenericTeamId.Id = n
    local ok = pcall(function()
        local prop = obj[propName]
        if prop ~= nil and prop.Id ~= nil then
            prop.Id = teamId
        else
            error("not a struct")
        end
    end)
    if ok then return true end
    -- 整数写法: obj.TeamId = n
    ok = pcall(function() obj[propName] = teamId end)
    return ok
end

local function tryCallFunction(obj, fnName, teamId)
    if not obj or not obj:IsValid() then return false end
    return pcall(function()
        local fn = obj[fnName]
        if fn == nil then error("no such function") end
        obj[fnName](obj, teamId)
    end)
end

local function getController(pawn)
    local ok, controller = pcall(function() return pawn.Controller end)
    if ok and controller and controller:IsValid() then return controller end
    return nil
end

--- 读出 pawn 当前的阵营 ID（用于快照/恢复），读不到返回 nil
function Teams.ReadTeam(pawn)
    local targets = { pawn }
    local controller = getController(pawn)
    if controller then table.insert(targets, controller) end
    for _, obj in ipairs(targets) do
        for _, propName in ipairs(Config.TeamPropertyCandidates) do
            local ok, value = pcall(function()
                local prop = obj[propName]
                if prop == nil then error("no prop") end
                if type(prop) == "number" then return prop end
                local id = prop.Id
                if type(id) == "number" then return id end
                -- UE4SS 对 uint8 字段可能返回代理对象，尝试取值
                if id ~= nil then
                    local okG, n = pcall(function() return id:get() end)
                    if okG and type(n) == "number" then return n end
                end
                error("not readable")
            end)
            if ok and type(value) == "number" then return value end
        end
    end
    return nil
end

--- 把 pawn 及其 AIController 都写入指定阵营（AI 感知判断敌我看的是
--- Controller 的阵营接口，只改 Pawn 等于白改）。
--- @return string|nil 成功时返回写入摘要（命中了哪些对象/途径）
function Teams.ApplyTeam(pawn, teamId)
    local targets = { { obj = pawn, tag = "pawn" } }
    local controller = getController(pawn)
    if controller then
        table.insert(targets, { obj = controller, tag = "ctrl" })
    end

    local hits = {}
    for _, t in ipairs(targets) do
        -- 先走函数（游戏自己的 setter 会同步内部状态），再退属性直写
        local written = false
        for _, fnName in ipairs(Config.TeamFunctionCandidates) do
            if tryCallFunction(t.obj, fnName, teamId) then
                table.insert(hits, fnName .. "()@" .. t.tag)
                written = true
                break
            end
        end
        if not written then
            for _, propName in ipairs(Config.TeamPropertyCandidates) do
                if tryWriteProperty(t.obj, propName, teamId) then
                    table.insert(hits, propName .. "@" .. t.tag)
                    break
                end
            end
        end
    end
    if #hits > 0 then return table.concat(hits, "+") end
    return nil
end

return Teams
