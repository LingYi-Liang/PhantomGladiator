-- 怪物类目录；不依赖场上仍有活 NPC。所有 UObject 操作及 resolveSelected 必须在游戏线程。
-- 官方 API：https://docs.ue4ss.com/lua-api/classes/uobject.html (IsAnyClass/GetFullName)
-- https://docs.ue4ss.com/lua-api/classes/ustruct.html (GetSuperStruct，返回值可能失效)
-- https://docs.ue4ss.com/lua-api/global-functions/findobjects.html
-- https://docs.ue4ss.com/lua-api/global-functions/loadasset.html (只能在游戏线程)
-- 本地头文件 BP_NPC_Base.hpp / ProjectPBZ.hpp 确认原生 NPC 基类。
local Catalog = {}
Catalog.__index = Catalog
local NPC_BASE = "/Script/ProjectPBZ.PBZCharacter_NPC"
local PREFERRED_NAME = "BP_Monster_Vessel_Child_C"
local HEADER = "PhantomGladiatorCatalogV1"
local MAX_CLASSES, MAX_ENTRIES, MAX_LIVE, MAX_FILE = 4096, 512, 512, 262144

local function short(value)
    local s = tostring(value):gsub("[\r\n\t]", " ")
    return #s > 220 and s:sub(1, 220) .. "..." or s
end

-- 只接受已知完整 generated-class 路径；不拼猜包目录，不接收命令或可执行 Lua。
local function pathName(path,allowBases)
    if type(path) ~= "string" or #path > 1024 or not path:match("^/[%w_/%-%.]+$") then return nil end
    if path:find("..", 1, true) or path:find("/./", 1, true) or path:find("//", 1, true) then return nil end
    local package, name = path:match("^(.+)%.([%w_%-]+_C)$")
    if not package or not name or (not allowBases and name:lower():match("_base_c$")) then return nil end
    local asset = package:match("([^/]+)$")
    if not asset or asset .. "_C" ~= name then return nil end
    return name
end

-- 仅减少广泛枚举时的无关类检查；前端已登记路径仍以实际NPC继承为准。
local function discoveryName(name)
    local lower = name and name:lower() or ""
    return lower:find("monster", 1, true) or lower:find("npc", 1, true)
        or lower:find("boss", 1, true) or lower:find("enemy", 1, true)
end

local function pathFromFullName(full)
    if type(full) ~= "string" then return nil end
    return full:match("^%S+ (/.+)$")
end

function Catalog.new(options)
    options = options or {}
    local self = setmetatable({
        log = options.log or function() end,
        valid = options.valid or function(obj) return obj ~= nil and obj:IsValid() end,
        findAll = options.findAll or function(name) return FindAllOf(name) end,
        findObjects = options.findObjects or function(...) return FindObjects(...) end,
        staticFind = options.staticFind or function(path) return StaticFindObject(path) end,
        loadAsset = options.loadAsset or function(path) return LoadAsset(path) end,
        getPlayer = options.getPlayer,
        canSpawn = options.canSpawn,
        allowActors=options.allowActors==true,maxEntries=options.allowActors and 4096 or MAX_ENTRIES,
        audit = options.audit,
        path = options.path, records = {}, selectedPath = nil, preferredPath = nil,
        lastSaved = nil, scanOffset = 0, stats = {}, knownOrder = {},
    }, Catalog)
    self:_loadFile()
    for _, path in ipairs(options.knownPaths or {}) do
        if not self:_remember(path, "configured-known") then
            self.log("图鉴配置路径被拒绝: " .. short(path))
        else
            self.knownOrder[#self.knownOrder + 1] = path
        end
    end
    -- F9 needs an explicit default without enumerating all loaded Blueprint classes.
    -- This selects metadata only; resolveSelected still validates the actual UClass.
    self.selectedPath=self.preferredPath or self.knownOrder[1]
    return self
end

function Catalog:_valid(obj)
    local ok, valid = pcall(self.valid, obj)
    return ok and valid == true
end

function Catalog:_name(obj)
    if not self:_valid(obj) then return "INVALID" end
    local ok, name = pcall(function() return obj:GetFullName() end)
    return ok and type(name) == "string" and name or "UNKNOWN"
end

function Catalog:_validate(cls, expected)
    if not self:_valid(cls) then return nil, "类对象未加载或已失效" end
    local okClass, isClass = pcall(function() return cls:IsAnyClass() end)
    if not okClass or isClass ~= true then return nil, "返回对象不是有效UClass" end
    local full = self:_name(cls)
    local path = pathFromFullName(full)
    local name = pathName(path,self.allowActors)
    if not name then return nil, "不是允许的具体蓝图生成类路径" end
    if expected and path ~= expected then return nil, "类路径读回不匹配" end
    local parent = cls
    for _ = 1, 32 do
        if not self:_valid(parent) then break end
        if pathFromFullName(self:_name(parent)) == NPC_BASE then
            return { name = name, path = path, class = cls, fullName = full, loaded = true,isNPC=true }
        elseif self.allowActors and pathFromFullName(self:_name(parent))=='/Script/Engine.Actor' then
            return {name=name,path=path,class=cls,fullName=full,loaded=true,isNPC=false}
        end
        local ok, nextParent = pcall(function() return parent:GetSuperStruct() end)
        if not ok then return nil, "无法读取NPC继承链" end
        parent = nextParent
    end
    return nil, self.allowActors and '未证实继承Actor，无法作为场景实体生成' or "未证实继承PBZCharacter_NPC（拒绝生成）"
end

function Catalog:_remember(path, source)
    local name = pathName(path,self.allowActors)
    if not name then return nil end
    if self.records[path] then return self.records[path] end
    local count = 0
    for _ in pairs(self.records) do count = count + 1 end
    if count >= self.maxEntries then return nil end
    local entry = { name = name, path = path, source = source, loaded = false }
    self.records[path] = entry
    return entry
end

function Catalog:_register(cls, source)
    local validated, reason = self:_validate(cls)
    if not validated then return nil, reason end
    local entry = self:_remember(validated.path, source)
    if not entry then return nil, "目录达到512项上限" end
    entry.class, entry.loaded, entry.fullName = cls, true, validated.fullName
    entry.isNPC=validated.isNPC
    entry.unavailableReason = nil
    return entry
end

function Catalog:_lookup(entry)
    local ok, cls = pcall(self.staticFind, entry.path)
    local validated, reason
    if ok then validated, reason = self:_validate(cls, entry.path) end
    if validated then
        entry.class, entry.loaded, entry.fullName = cls, true, validated.fullName
        entry.isNPC=validated.isNPC
        entry.unavailableReason = nil
        return cls
    end
    entry.class, entry.loaded = nil, false
    entry.unavailableReason = ok and reason or ("StaticFindObject失败: " .. short(cls))
    return nil, entry.unavailableReason
end

function Catalog:_ordered()
    local entries = {}
    for _, entry in pairs(self.records) do entries[#entries + 1] = entry end
    table.sort(entries, function(a, b)
        if a.name == b.name then return a.path < b.path end
        return a.name < b.name
    end)
    return entries
end

function Catalog:_loadFile()
    if not self.path then return end
    local file = io.open(self.path, "r")
    if not file then return end -- 首次使用尚无目录文件。
    local content = file:read(MAX_FILE + 1)
    file:close()
    if not content or #content > MAX_FILE or not content:match("^" .. HEADER .. "\r?\n") then
        self.log("图鉴持久文件读取失败：格式错误或超过256KiB；未执行文件内容")
        return
    end
    local rejected = 0
    for line in content:gmatch("[^\r\n]+") do
        if line ~= HEADER then
            local kind, path = line:match("^(%a+)\t([^\t]+)$")
            if kind == "class" then
                if not self:_remember(path, "persisted") then rejected = rejected + 1 end
            elseif kind == "selected" and pathName(path,self.allowActors) then
                self.preferredPath = path
            else
                rejected = rejected + 1
            end
        end
    end
    if self.preferredPath and not self.records[self.preferredPath] then self.preferredPath = nil end
    self.lastSaved = content
    self.log(string.format("图鉴持久目录已读取：%d项；拒绝行=%d；尚需核验当前加载状态", #self:_ordered(), rejected))
end

function Catalog:_save()
    if not self.path then return false, "未配置持久路径" end
    local lines = { HEADER }
    if self.preferredPath and self.records[self.preferredPath] then
        lines[#lines + 1] = "selected\t" .. self.preferredPath
    end
    for _, entry in ipairs(self:_ordered()) do lines[#lines + 1] = "class\t" .. entry.path end
    local content = table.concat(lines, "\n") .. "\n"
    if content == self.lastSaved then return true end
    local file, errorText = io.open(self.path, "w")
    if not file then
        self.log("图鉴保存失败: " .. short(errorText))
        return false, errorText
    end
    local written, writeError = file:write(content)
    file:close()
    local check = io.open(self.path, "r")
    local readback = check and check:read(MAX_FILE + 1) or nil
    if check then check:close() end
    if written and readback == content then
        self.lastSaved = content
        self.log(string.format("图鉴保存：%d项；读回一致；%s", #self:_ordered(), self.path))
        return true
    end
    self.log("图鉴保存未验证：" .. short(writeError or "读回内容不一致"))
    return false, writeError or "读回内容不一致"
end

function Catalog:_location(actor)
    if not self:_valid(actor) then return nil end
    local ok, value = pcall(function() return actor:K2_GetActorLocation() end)
    if not ok or value == nil then return nil end
    local okXYZ, x, y, z = pcall(function() return value.X, value.Y, value.Z end)
    if okXYZ and type(x) == "number" and type(y) == "number" and type(z) == "number" then
        return { x, y, z }
    end
    return nil
end

function Catalog:refresh(npcs)
    local stats = { classTotal = 0, classScanned = 0, classTruncated = false,
        liveScanned = 0, rejected = 0, preferredMatches = 0, discoveryErrors = {} }
    for _, entry in ipairs(self:_ordered()) do self:_lookup(entry) end
    -- 不猜 Vessel_Child 的包路径：按已知短名找，路径只取实际UClass.GetFullName。
    local okPreferred, preferred = pcall(self.findObjects, 32, nil, PREFERRED_NAME, 0, 0, true)
    if okPreferred and type(preferred) == "table" then
        for i = 1, math.min(#preferred, 32) do
            if self:_register(preferred[i], "loaded-short-name") then stats.preferredMatches = stats.preferredMatches + 1 end
        end
    elseif not okPreferred then stats.discoveryErrors[#stats.discoveryErrors + 1] = "FindObjects短名: " .. short(preferred) end
    local okClasses, classes = pcall(self.findAll, "BlueprintGeneratedClass")
    if not okClasses or type(classes) ~= "table" or #classes == 0 then
        local fallbackOk, fallback = pcall(self.findObjects, MAX_CLASSES, "BlueprintGeneratedClass", nil, 0, 0, false)
        if fallbackOk and type(fallback) == "table" then
            classes, okClasses, stats.discovery = fallback, true, "FindObjects"
        else
            stats.discoveryErrors[#stats.discoveryErrors + 1] = "类枚举无结果: " .. short(fallback)
        end
    else stats.discovery = "FindAllOf" end
    if okClasses and type(classes) == "table" then
        stats.classTotal, stats.classTruncated = #classes, #classes >= MAX_CLASSES
        local offset = #classes > 0 and self.scanOffset % #classes or 0
        for step = 1, math.min(#classes, MAX_CLASSES) do
            local cls = classes[(offset + step - 1) % #classes + 1]
            stats.classScanned = stats.classScanned + 1
            local path = pathFromFullName(self:_name(cls))
            if discoveryName(pathName(path)) then
                local entry = self:_register(cls, "loaded-class")
                if not entry then stats.rejected = stats.rejected + 1 end
            end
        end
        self.scanOffset = #classes > 0 and (offset + stats.classScanned) % #classes or 0
    end
    local player
    if self.getPlayer then
        local ok, result = pcall(self.getPlayer)
        if ok then player = result end
    end
    local playerLocation = self:_location(player)
    local nearestPath, nearestDistance = nil, math.huge
    for i = 1, math.min(#(npcs or {}), MAX_LIVE) do
        local npc = npcs[i]
        stats.liveScanned = stats.liveScanned + 1
        if self:_valid(npc) then
            local ok, cls = pcall(function() return npc:GetClass() end)
            local entry = ok and self:_register(cls, "live-npc") or nil
            if entry then
                local distance = i
                local location = self:_location(npc)
                if playerLocation and location then
                    distance = 0
                    for axis = 1, 3 do distance = distance + (location[axis] - playerLocation[axis]) ^ 2 end
                elseif playerLocation then distance = math.huge end
                if not nearestPath or distance < nearestDistance then nearestPath, nearestDistance = entry.path, distance end
            else stats.rejected = stats.rejected + 1 end
        end
    end
    local entries = self:_ordered()
    local chosen = self.preferredPath and self.records[self.preferredPath] or nil
    -- 用户保存的选择仍保留，即使暂未加载；F9可按需解析它。
    if not chosen then
        for _, entry in ipairs(entries) do
            if entry.loaded and entry.name == PREFERRED_NAME then chosen = entry break end
        end
        if not chosen and nearestPath then chosen = self.records[nearestPath] end
        if not chosen then
            for _, path in ipairs(self.knownOrder) do
                if self.records[path] then chosen = self.records[path] break end
            end
        end
        if not chosen then
            for _, entry in ipairs(entries) do if entry.loaded then chosen = entry break end end
        end
        chosen = chosen or entries[1]
    end
    self.selectedPath = chosen and chosen.path or nil
    if not self.preferredPath then self.preferredPath = self.selectedPath end
    self.stats = stats
    self:_save()
    local status = self:status()
    self.log(string.format("图鉴刷新：已知=%d 已加载=%d 未加载=%d；类扫描=%d/%d 截断=%s；活NPC=%d；选择=%s%s",
        status.known, status.loaded, status.unavailable, stats.classScanned, stats.classTotal,
        tostring(stats.classTruncated), stats.liveScanned, chosen and chosen.name or "无",
        chosen and (chosen.loaded and "（已加载）" or "（F9将按需加载已知路径）") or "（没有合法类，无法召唤）"))
    for _, err in ipairs(stats.discoveryErrors) do self.log("图鉴发现提示: " .. err) end
    return status
end

function Catalog:selected()
    local entry = self.selectedPath and self.records[self.selectedPath] or nil
    if not entry then return nil, "目录没有合法怪物类" end
    if entry.class and not self:_valid(entry.class) then entry.class, entry.loaded = nil, false end
    return entry
end

-- 供后续 AssetRegistry 目录接入；路径注册不等于类已加载或可生成。
function Catalog:registerPath(path)
    local entry = self:_remember(path, "registered-known")
    if not entry then return nil, "路径格式不允许、基类被排除或目录已满" end
    return entry
end

function Catalog:select(path)
    local entry = self.records[path]
    if not entry then return nil, "路径尚未登记" end
    self.selectedPath, self.preferredPath = path, path
    self:_save()
    self.log("图鉴选择: " .. entry.name .. (entry.loaded and "（已加载）" or "（未加载，F9按需解析）"))
    return entry
end

function Catalog:next()
    local entries = self:_ordered()
    if #entries == 0 then
        self.log("切换失败：目录没有合法怪物类")
        return nil, "目录没有合法怪物类"
    end
    local index = 0
    for i, entry in ipairs(entries) do if entry.path == self.selectedPath then index = i break end end
    local entry = entries[index % #entries + 1]
    self.selectedPath, self.preferredPath = entry.path, entry.path
    self:_save()
    self.log("图鉴选择: " .. entry.name .. (entry.loaded and "（已加载）" or "（未加载，F9按需解析）"))
    return entry
end

-- 只解析当前选中一类；不加载其他目录条目，不把Blueprint资产对象当UClass。
function Catalog:resolveSelected()
    local entry, errorText = self:selected()
    if not entry then self.log("召唤类解析失败: " .. errorText) return nil, errorText end
    return self:_resolve(entry)
end

-- A unit summoned along with the selected one (escorts.lua), resolved the same way; the selection stays.
function Catalog:resolvePath(path)
    local entry = self.records[path] or self:_remember(path, "escort")
    if not entry then return nil, "路径格式不允许、基类被排除或目录已满" end
    local cls, reason = self:_resolve(entry)
    return cls, reason, entry
end

function Catalog:_resolve(entry)
    if type(self.canSpawn)~="function" then return nil,"未配置生成验证策略；未加载任何资产" end
    local okPolicy,allowed,policyReason=pcall(self.canSpawn,entry.path)
    if not okPolicy or allowed~=true then
        local reason=tostring(policyReason or "该单位没有生成验证记录")
        self.log("生成门禁拒绝: "..entry.path.."；"..reason)
        return nil,reason
    end
    local cls = self:_lookup(entry)
    if cls then
        self.log("召唤类解析：StaticFindObject命中；UClass/实体继承/路径读回通过；NPC="..tostring(entry.isNPC).."；" .. entry.path)
        return cls
    end
    local attempts = { entry.path, entry.path:sub(1, -3) }
    for index, request in ipairs(attempts) do
        if self.audit and self.audit("load_begin",entry.path,request)~=true then
            return nil,"无法确认阶段日志已保存；没有加载资产"
        end
        local ok, loadedObject, found, loaded = pcall(self.loadAsset, request)
        if self.audit then self.audit("load_return",entry.path,"call="..tostring(ok).." found="..tostring(found).." loaded="..tostring(loaded)) end
        self.log(string.format("召唤类加载[%d]：LoadAsset(%s)；对象=%s；found=%s；loaded=%s；调用=%s",
            index, request, ok and short(self:_name(loadedObject)) or "UNKNOWN",
            tostring(found), tostring(loaded), ok and "完成" or short(loadedObject)))
        cls = self:_lookup(entry)
        if not cls and ok then
            local verified = self:_validate(loadedObject, entry.path)
            if verified then
                cls = loadedObject
                entry.class, entry.loaded, entry.fullName = cls, true, verified.fullName
                entry.isNPC=verified.isNPC
                entry.unavailableReason = nil
            end
        end
        if cls then
            self.log("召唤类加载读回：UClass/实体继承/原始路径通过；NPC="..tostring(entry.isNPC).."；" .. entry.path)
            return cls
        end
        -- 只有资产注册表明确没找到_C对象时，才尝试对应Blueprint资产对象路径。
        if index == 1 and (not ok or found ~= false) then break end
    end
    local reason = "已知路径未解析为合法NPC类: " .. entry.path .. "；" .. tostring(entry.unavailableReason)
    self.log("召唤类解析失败：" .. reason .. "；没有生成，也没有猜测其他包路径")
    return nil, reason
end

function Catalog:status()
    local known, loaded = 0, 0
    for _, entry in pairs(self.records) do
        known = known + 1
        if entry.loaded and self:_valid(entry.class) then loaded = loaded + 1 end
    end
    return { known = known, loaded = loaded, unavailable = known - loaded,
        selectedPath = self.selectedPath, persistencePath = self.path, scan = self.stats }
end

return Catalog
