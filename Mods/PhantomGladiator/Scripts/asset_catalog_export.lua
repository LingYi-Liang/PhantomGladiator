-- 按当前 cooked AssetRegistry 的缓存路径导出候选单位，不加载任何资产。
-- start/tick 必须由游戏线程调用；tick 每次只查询有限个非递归路径。
-- 头文件：AssetRegistry.hpp / CoreUObject.hpp。完整性只覆盖本次 registry 视图。
-- UE4SS dff435dd LuaUObject.cpp:212-296、862-872：out TArray 是 Lua 表，
-- 元素为参数代理；item:get() 的 UScriptStruct 可保留 FAssetData 非反射标签数据。
local Exporter = {}

local function clamp(n, default, low, high)
    n = tonumber(n) or default
    if n ~= n then n = default end
    return math.floor(math.max(low, math.min(high, n)))
end

local function valid(object)
    if object == nil then return false end
    local ok, value = pcall(function() return object:IsValid() end)
    return ok and value == true
end

local function unwrap(value)
    if value == nil then return nil end
    if type(value) ~= "userdata" and type(value) ~= "table" then return value end
    local ok, result = pcall(function() return value:get() end)
    if ok then return result end
    return value
end

local function field(value, key)
    if value == nil then return nil end
    local ok, result = pcall(function() return value[key] end)
    if ok then return result end
end

local function string_value(value)
    value = unwrap(value)
    if type(value) == "string" then return value end
    if value == nil then return nil end
    local ok, result = pcall(function() return value:ToString() end)
    if ok and type(result) == "string" then return result end
end

local function clean(value)
    return (tostring(value or ""):gsub("[\t\r\n]", " "))
end

local function object_path(value)
    if type(value) ~= "string" then return nil end
    local quoted = value:match("^[^']*'([^']+)'$")
    value = quoted or value
    if value:find("[%s\t\r\n]") or value:find(":", 1, true) then return nil end
    if not value:match("^/[^.]+%.[^./]+$") then return nil end
    return value
end

local function class_path(value)
    local path = object_path(value)
    if path and path:match("_C$") then return path end
end

local function path_from_fields(value)
    local package = string_value(field(value, "PackageName"))
    local name = string_value(field(value, "AssetName"))
    if package and name then return object_path(package .. "." .. name) end
end

local function current_game_thread()
    if type(IsInGameThread) ~= "function" then return false end
    local ok, result = pcall(IsInGameThread)
    return ok and result == true
end

function Exporter.new(options)
    options = options or {}
    local cfg = options.config or {}
    local perTick = clamp(cfg.PathsPerTick, 1, 1, 4)
    local pathLimit = clamp(cfg.MaxPaths, 20000, 1, 100000)
    local assetLimit = clamp(cfg.MaxAssetsPerPath, 2048, 1, 10000)
    local candidateLimit = clamp(cfg.MaxCandidates, 20000, 1, 100000)
    local duration = clamp(cfg.MaxSeconds, 180, 5, 1800)
    local path = options.path
    local partialPath = type(path) == "string" and path .. ".partial" or nil
    local header = "id\tname\tcategory\tclass_path\tloaded\tspawnable\treason\n"
    local registry, helpers, output
    local paths, rows, seen = {}, {}, {}
    local state = {}
    local instance = {}

    local function log(message)
        if options.log then pcall(options.log, "[AssetCatalog] " .. message) end
    end

    local function reset()
        state = { active = false, complete = false, published = false, truncated = false,
            registry_loading = "unknown", coverage = "UNKNOWN", source_scope = "cooked_registry_cached_paths",
            paths_total = 0, paths_reported = 0, path_decode_errors = 0, paths_done = 0,
            assets_reported = 0, assets_seen = 0, candidates = 0, unresolved = 0,
            unclassified_blueprints = 0, query_errors = 0, tag_errors = 0, row_errors = 0,
            started_at = 0, reason = "not_started", path = path, partial_path = partialPath }
    end
    reset()

    local function file_action(handle, method)
        local ok, result, detail = pcall(function() return handle[method](handle) end)
        if ok and result == true then return true end
        return false, clean(ok and (detail or (method .. " returned " .. tostring(result))) or result)
    end

    local function close()
        if not output then return true end
        local handle = output
        output = nil
        local flushed, flushError = file_action(handle, "flush")
        -- flush 失败也要尝试 close，避免遗留文件句柄。
        local closed, closeError = file_action(handle, "close")
        return flushed and closed, flushError or closeError
    end

    local function write(handle, text)
        local ok, result = pcall(function() return handle:write(text) end)
        return ok and result ~= nil and result ~= false
    end

    local function finish(reason, publish)
        state.active = false
        state.reason = reason
        local closed, closeError = close()
        if not closed then
            state.complete, publish = false, false
            state.last_error = closeError
            if reason ~= "partial_flush_failed" then state.reason = "partial_close_failed" end
        end
        if publish then
            local ok, final = pcall(io.open, path, "w")
            if not ok or not final then
                state.complete = false
                state.reason = "publish_open_failed"
                log("发布失败；保留partial文件，最终目录未确认: " .. tostring(path))
                return
            end
            local good = write(final, header)
            for _, row in ipairs(rows) do
                if good then good = write(final, row) end
            end
            local flushed, flushError = file_action(final, "flush")
            local finalClosed, finalCloseError = file_action(final, "close")
            state.published = good and flushed and finalClosed
            if not state.published then
                state.complete = false
                state.reason = "publish_write_failed"
                state.last_error = flushError or finalCloseError or "write_failed"
            end
        end
        log(string.format("结束 reason=%s paths=%d/%d assets=%d candidates=%d unresolved=%d truncated=%s loading=%s published=%s coverage=UNKNOWN",
            state.reason, state.paths_done, state.paths_total, state.assets_seen, state.candidates, state.unresolved,
            tostring(state.truncated), tostring(state.registry_loading), tostring(state.published)))
        registry, helpers = nil, nil
    end

    local function get_tag(data, name)
        if not valid(helpers) then state.tag_errors = state.tag_errors + 1; return nil end
        local out = {}
        local ok, found = pcall(function() return helpers:GetTagValue(data, FName(name), out) end)
        if not ok then state.tag_errors = state.tag_errors + 1; return nil end
        if found ~= true then return nil end
        local text = string_value(out.OutTagValue)
        if text and text ~= "" and text ~= "None" then return text end
    end

    local function read_row(data)
        local asset = path_from_fields(data)
        local name = string_value(field(data, "AssetName"))
        local package = string_value(field(data, "PackageName"))
        local packagePath = string_value(field(data, "PackagePath"))
        local assetType = path_from_fields(field(data, "AssetClassPath"))
        if not asset or not name or not package then state.row_errors = state.row_errors + 1; return end
        local typeName = (assetType or string_value(field(data, "AssetClass")) or ""):lower()
        local looksBlueprint = typeName:find("blueprint", 1, true) ~= nil
            or typeName == "/script/coreuobject.class"
        if not looksBlueprint then return end
        -- 保持 data 为完整 UScriptStruct 代理，不能先复制成只含反射字段的表再查标签。
        local generatedRaw = get_tag(data, "GeneratedClass")
        local parent = get_tag(data, "ParentClass")
        local nativeParent = get_tag(data, "NativeParentClass")
        local generated = class_path(generatedRaw)
        local evidence = generated and "registry_generated_class_tag" or nil
        if not generated and assetType == "/Script/Engine.BlueprintGeneratedClass" then
            generated = class_path(asset)
            if generated then evidence = "registry_class_asset" end
        end
        local lowerName = name:lower()
        local family = ((parent or "") .. " " .. (nativeParent or "")):lower()
        local unitParent = family:find("pbzcharacter_npc", 1, true) or family:find("bp_renewalnpc", 1, true)
            or family:find("bp_npc_base", 1, true) or family:find("bp_monster", 1, true)
            or family:find("/script/engine.pawn", 1, true) or family:find("/script/engine.character", 1, true)
        local unitName = lowerName:match("^bp_") and (lowerName:find("monster", 1, true)
            or lowerName:find("boss", 1, true) or lowerName:find("npc", 1, true)
            or lowerName:find("enemy", 1, true) or lowerName:find("creature", 1, true)
            or lowerName:find("summon", 1, true))
        if not unitParent and not unitName then
            state.unclassified_blueprints = state.unclassified_blueprints + 1
            return
        end
        local id = generated or asset
        if seen[id] then return end
        if state.candidates >= candidateLimit then state.truncated = true; return end
        seen[id] = true
        local loaded = false
        if generated then
            local ok, cls = pcall(StaticFindObject, generated)
            if ok and valid(cls) then
                local okClass, isClass = pcall(function() return cls:IsAnyClass() end)
                loaded = okClass and isClass == true
            end
        end
        local category = lowerName:find("boss", 1, true) and "BOSS"
            or lowerName:find("monster", 1, true) and "怪物"
            or lowerName:find("npc", 1, true) and "NPC" or "未验证单位"
        local reason = table.concat({ evidence or "class_unresolved", "npc_inheritance_unverified",
            unitParent and "parent_tag_candidate" or "name_candidate", "asset=" .. asset,
            "asset_type=" .. (assetType or "unknown"), "package=" .. package,
            "package_path=" .. (packagePath or "unknown"), "parent=" .. (parent or "unknown"),
            "native_parent=" .. (nativeParent or "unknown"), "registry_coverage_unknown" }, ";")
        local cells = { id, name, category, generated or "", loaded and "1" or "0", generated and "1" or "0", reason }
        for index, value in ipairs(cells) do cells[index] = clean(value) end
        local line = table.concat(cells, "\t") .. "\n"
        if not write(output, line) then error("partial_write_failed") end
        rows[#rows + 1] = line
        state.candidates = state.candidates + 1
        if not generated then state.unresolved = state.unresolved + 1 end
    end

    function instance:status()
        local copy = {}
        for key, value in pairs(state) do copy[key] = value end
        return copy
    end

    function instance:cancel(reason)
        if state.active then finish(reason or "cancelled", false) end
        return self:status()
    end

    function instance:silence(reason)
        -- 无 UE 调用、无排队；仅停止当前Lua工作并关闭自己的文件。
        state.active, state.reason = false, reason or "unload"
        close()
        registry, helpers = nil, nil
    end

    function instance:start()
        if state.active then return false, self:status() end
        reset(); paths, rows, seen = {}, {}, {}
        if not current_game_thread() then state.reason = "requires_game_thread"; return false, self:status() end
        if type(path) ~= "string" or not (path:match("^[A-Za-z]:[/\\]") or path:sub(1, 1) == "/")
            or path:find("[\t\r\n]") then
            state.reason = "requires_absolute_output_path"; return false, self:status()
        end
        -- FName 是 UE4SS 构造器，可由可调用 class table/userdata 提供；不能限定为 Lua function。
        -- 真正的 FName(...) 调用仍位于查询/读标签的 pcall 内，调用失败不会记为成功。
        if type(StaticFindObject) ~= "function" or FName == nil then
            state.reason = "missing_ue4ss_api"
            state.last_error = "StaticFindObject=" .. type(StaticFindObject) .. "; FName=" .. type(FName)
                .. "; IsInGameThread=" .. type(IsInGameThread)
            log("未开始：缺少UE4SS API；读回类型 " .. state.last_error)
            return false, self:status()
        end
        local okHelper, foundHelper = pcall(StaticFindObject, "/Script/AssetRegistry.Default__AssetRegistryHelpers")
        if not okHelper or not valid(foundHelper) then state.reason = "helpers_unavailable"; return false, self:status() end
        helpers = foundHelper
        if not valid(helpers) then state.reason = "helpers_invalidated"; return false, self:status() end
        local okRegistry, foundRegistry = pcall(function() return helpers:GetAssetRegistry() end)
        if not okRegistry or not valid(foundRegistry) then
            state.reason = "registry_interface_unavailable"
            if not okRegistry then state.last_error = clean(foundRegistry) end
            log("未开始：GetAssetRegistry返回未通过IsValid，未猜接口指针。 " .. (state.last_error or ""))
            return false, self:status()
        end
        registry = foundRegistry
        if not valid(registry) then state.reason = "registry_invalidated"; return false, self:status() end
        local okLoading, loading = pcall(function() return registry:IsLoadingAssets() end)
        if okLoading and type(loading) == "boolean" then state.registry_loading = loading end
        if state.registry_loading == true then state.truncated = true end
        local outPaths = {}
        if not valid(registry) then state.reason = "registry_invalidated"; return false, self:status() end
        local okPaths, errorPaths = pcall(function() registry:GetAllCachedPaths(outPaths) end)
        if not okPaths then
            state.reason = "cached_paths_api_failed"
            log("未开始：GetAllCachedPaths失败 " .. clean(errorPaths))
            return false, self:status()
        end
        local uniquePaths = {}
        state.paths_reported = #outPaths
        for _, item in ipairs(outPaths) do
            local value = string_value(item)
            if value and value:sub(1, 1) == "/" and not value:find("[\t\r\n]") and not uniquePaths[value] then
                if #paths >= pathLimit then state.truncated = true; break end
                uniquePaths[value] = true
                paths[#paths + 1] = value
            elseif not value or value:sub(1, 1) ~= "/" or value:find("[\t\r\n]") then
                state.path_decode_errors = state.path_decode_errors + 1
            end
        end
        -- 只重排 registry 实际返回的路径，不生成/猜测任何新路径。
        local function priority(value)
            local lower = value:lower()
            local actorData = "/pbzcombatasset/actordata"
            if lower == actorData or lower:sub(1, #actorData + 1) == actorData .. "/" then return 0 end
            for _, keyword in ipairs({ "mobs", "npc", "monster", "boss", "character", "summon" }) do
                if lower:find(keyword, 1, true) then return 1 end
            end
            return 2
        end
        local priorities = {}
        for _, value in ipairs(paths) do priorities[value] = priority(value) end
        table.sort(paths, function(a, b)
            local rankA, rankB = priorities[a], priorities[b]
            return rankA == rankB and a < b or rankA < rankB
        end)
        state.paths_total = #paths
        if #paths == 0 then
            state.reason = "no_cached_paths"
            log("未开始：缓存路径读回为空；不把空注册表视为游戏没有单位。")
            return false, self:status()
        end
        local okFile, file = pcall(io.open, partialPath, "w")
        if not okFile or not file then state.reason = "output_open_failed"; return false, self:status() end
        output = file
        if not write(output, header) then close(); state.reason = "output_header_failed"; return false, self:status() end
        state.active, state.started_at, state.reason = true, os.time(), "running"
        log(string.format("开始 操作=按缓存路径只读枚举 onDisk=true recursive=false；读回paths=%d loading=%s；每tick路径<=%d，每路径处理<=%d；不LoadAsset，完整性UNKNOWN。",
            #paths, tostring(state.registry_loading), perTick, assetLimit))
        return true, self:status()
    end

    function instance:tick()
        if not state.active then return self:status() end
        if not current_game_thread() then finish("tick_requires_game_thread", false); return self:status() end
        if os.time() - state.started_at >= duration then
            state.truncated = true; finish("time_limit", true); return self:status()
        end
        for _ = 1, perTick do
            if not state.active then break end
            if not valid(registry) or not valid(helpers) then finish("registry_or_helpers_invalidated", false); break end
            local currentPath = paths[state.paths_done + 1]
            if not currentPath then
                state.complete = not state.truncated and state.query_errors == 0 and state.row_errors == 0
                    and state.tag_errors == 0 and state.path_decode_errors == 0 and state.registry_loading == false
                finish(state.complete and "traversal_finished" or "traversal_partial", true)
                break
            end
            state.current_path = currentPath
            local outAssets = {}
            local ok, success = pcall(function() return registry:GetAssetsByPath(FName(currentPath), outAssets, false, true) end)
            if not ok or success ~= true then
                state.query_errors = state.query_errors + 1
                state.last_error = ok and "GetAssetsByPath_return_not_true" or clean(success)
                log("路径查询失败/未返回成功: " .. currentPath)
            else
                state.assets_reported = state.assets_reported + #outAssets
                if #outAssets > assetLimit then state.truncated = true end
                for index = 1, math.min(#outAssets, assetLimit) do
                    state.assets_seen = state.assets_seen + 1
                    -- 当前查询的结构体代理只在本tick中使用；不跨帧保存。
                    local okRow, rowError = pcall(read_row, unwrap(outAssets[index]))
                    if not okRow then
                        state.row_errors = state.row_errors + 1
                        state.last_error = clean(rowError)
                        if tostring(rowError):find("partial_write_failed", 1, true) then finish("partial_write_failed", false); break end
                    end
                    if state.candidates >= candidateLimit then
                        state.truncated = true; finish("candidate_limit", true); break
                    end
                end
            end
            state.paths_done = state.paths_done + 1
            if output then
                local flushed, flushError = file_action(output, "flush")
                if not flushed then
                    state.last_error = flushError
                    finish("partial_flush_failed", false)
                end
            end
        end
        return self:status()
    end

    return instance
end

return Exporter
