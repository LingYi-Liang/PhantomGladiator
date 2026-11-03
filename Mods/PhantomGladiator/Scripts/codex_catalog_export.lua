-- 只读原生敌人图鉴中文/BOSS元数据；不加载资产、不揭示图鉴、不改存档。
-- ProjectPBZ.hpp:374-400 FCodexEnemyRow；8677-8703 PBZCodexSubsystem。
-- GetAllEnemyCodexEntries的返回类型在dump中缺失：运行时仅接纳有已核实字段的数组行。
-- UE4SS dff435dd LuaTSoftObjectPtr.cpp/GetObjectID 与 LuaFSoftObjectPath.cpp/GetAssetPathName。
-- name 列是游戏当前语言的名称（EnemyName，FFlowLocText，按地图名同样的方式解析），name_lang 是游戏语言
-- （KismetInternationalizationLibrary.GetCurrentLanguage）；助手按它显示单位名。zh_name 仍是 Enemy_CH_Hans_Name。
local Exporter = {}
local ENEMY_TYPES = { [0] = "None", [1] = "Animal", [2] = "GuaiMian", [3] = "DragonModified", [4] = "HumanMaster", [5] = "Puppet" }
local MAX_ENTRIES, MAX_ALIASES = 4096, 64

local function valid(value)
    if value == nil then return false end
    local ok, result = pcall(function() return value:IsValid() end)
    return ok and result == true
end

local function kind(value)
    if type(value) ~= "userdata" and type(value) ~= "table" then return type(value) end
    local ok, result = pcall(function() return value:type() end)
    return ok and type(result) == "string" and result or type(value)
end

local function unwrap(value)
    local name = kind(value)
    if name == "RemoteUnrealParam" or name == "LocalUnrealParam" then
        local ok, result = pcall(function() return value:get() end)
        if ok then return result end
        return nil
    end
    return value
end

local function field(value, name)
    local valueKind = kind(value)
    if valueKind ~= "table" and valueKind ~= "UScriptStruct" then return nil end
    local ok, result = pcall(function() return value[name] end)
    if ok then return result end
end

local function text_value(value)
    value = unwrap(value)
    if type(value) == "string" then return value end
    if value == nil then return nil end
    local valueKind = kind(value)
    if valueKind ~= "FString" and valueKind ~= "FName" and valueKind ~= "table" then return nil end
    local ok, result = pcall(function() return value:ToString() end)
    if ok and type(result) == "string" then return result end
end

local function clean(value) return (tostring(value or ""):gsub("[\t\r\n]", " ")) end

-- FText/FString/Lua string -> string, nil if unreadable.
local function loc_text(value)
    value = unwrap(value)
    if type(value) == "string" then return value end
    if value == nil then return nil end
    local ok, result = pcall(function() return value:ToString() end)
    if ok and type(result) == "string" then return result end
end

local function exact_class_path(value)
    if type(value) ~= "string" or #value > 1024 or value:find("[%s:]") then return nil end
    if not value:match("^/[^.]+%.[^./]+$") then return nil end
    if value:sub(1, 8) == "/Script/" or value:match("_C$") then return value end
end

local function object_key(object)
    if not valid(object) then return nil end
    local ok, result = pcall(function() return object:GetAddress() end)
    if ok and (type(result) == "number" or type(result) == "string") then return tostring(result) end
end

local function array_items(value, maximum)
    local valueKind = kind(value)
    local result, total = {}, 0
    if valueKind == "table" then
        total = #value
        if total == 0 and next(value) ~= nil then return nil, nil, false end
        for index = 1, math.min(total, maximum) do result[#result + 1] = unwrap(value[index]) end
    elseif valueKind == "TArray" then
        local ok = pcall(function()
            total = #value
            value:ForEach(function(_, item)
                if #result >= maximum then return true end
                result[#result + 1] = unwrap(item)
                if #result >= maximum then return true end
            end)
        end)
        if not ok then return nil, nil, false end
    else return nil, nil, false end
    return result, total, total > maximum
end

function Exporter.new(options)
    options = options or {}
    local path = options.path
    local instance = {}
    local function log(message)
        if options.log then pcall(options.log, "[CodexCatalog] " .. message) end
    end
    local function failure(message, stats)
        log("UNKNOWN: " .. message)
        return { ok = false, count = 0, message = "UNKNOWN: " .. message, stats = stats or {} }
    end
    -- The codex row's EnemyName in the game's current language, resolved like the map names
    -- (WorldMapCatalog:localize: its cached text, else the game's Conv_LocTextToString); "" if unreadable.
    local function localized_name(row)
        local value = field(row, "EnemyName")
        if value == nil then return "" end
        if options.maps and options.maps.localize then
            local ok, name = pcall(options.maps.localize, options.maps, value)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        return loc_text(field(value, "ValueCache")) or ""
    end
    local function game_language()
        if options.language then
            local ok, value = pcall(options.language)
            return ok and type(value) == "string" and value or ""
        end
        local ok, lib = pcall(StaticFindObject, "/Script/Engine.Default__KismetInternationalizationLibrary")
        if not ok or not valid(lib) then return "" end
        local okLanguage, value = pcall(function() return lib:GetCurrentLanguage() end)
        return okLanguage and loc_text(value) or ""
    end

    function instance:export()
        if type(IsInGameThread) ~= "function" then return failure("缺少游戏线程检查API") end
        local okThread, inGame = pcall(IsInGameThread)
        if not okThread or inGame ~= true then return failure("必须在游戏线程调用") end
        if type(path) ~= "string" or not (path:match("^[A-Za-z]:[/\\]") or path:sub(1, 1) == "/")
            or path:find("[\t\r\n]") then return failure("输出必须是明确绝对路径") end
        if type(FindAllOf) ~= "function" or type(options.getWorld) ~= "function" then return failure("缺少FindAllOf/getWorld") end
        local okWorld, world = pcall(options.getWorld)
        local worldKey = okWorld and object_key(world)
        if not worldKey then return failure("当前World无效或身份未读回") end
        local okFind, candidates = pcall(FindAllOf, "PBZCodexSubsystem")
        if not okFind or type(candidates) ~= "table" then return failure("未找到图鉴子系统") end
        if #candidates > 64 then return failure("图鉴子系统对象数量异常，未任选一个") end
        local found, seen, matches = nil, {}, 0
        for _, subsystem in ipairs(candidates) do
            if valid(subsystem) then
                local okOuter, outer = pcall(function() return subsystem:GetOuter() end)
                if okOuter and valid(outer) and object_key(outer) == worldKey then
                    local id = object_key(subsystem)
                    if id and not seen[id] then found, matches, seen[id] = subsystem, matches + 1, true end
                end
            end
        end
        if matches ~= 1 then return failure("当前World的图鉴子系统匹配数量=" .. matches) end
        if not valid(found) or not valid(world) then return failure("读取前World/子系统已失效") end
        log("操作=当前World子系统:GetAllEnemyCodexEntries()一次；不LoadAsset、不Reveal、不改存档")
        local okEntries, entries = pcall(function() return found:GetAllEnemyCodexEntries() end)
        if not okEntries then return failure("GetAllEnemyCodexEntries调用失败: " .. clean(entries)) end
        local list, rawCount, truncated = array_items(entries, MAX_ENTRIES)
        log("读回 return_type=" .. kind(entries) .. " count=" .. tostring(rawCount or "UNKNOWN") .. " truncated=" .. tostring(truncated))
        if not list then return failure("返回schema未识别；未猜FCodexEntry/RowClass") end
        local stats = { raw_count = rawCount, decoded_rows = 0, unknown_rows = 0, unknown_soft_paths = 0,
            unknown_names = 0, aliases = 0, conflicts = 0, truncated = truncated, coverage = "UNKNOWN", localized_names = 0 }
        local language = game_language():gsub("[^%w%-]", ""):sub(1, 16)
        local rows, conflicts = {}, {}
        local kismet, triedKismet = nil, false

        local function soft_path(reference)
            reference = unwrap(reference)
            if reference == nil then return nil end
            -- 这些是值包装器API；GetWeakPtr/Get不会调用，避免解析或加载UObject。
            local refKind = kind(reference)
            if refKind == "TSoftObjectPtrUserdata" then
                local okID, objectID = pcall(function() return reference:GetObjectID() end)
                if okID and kind(objectID) == "FSoftObjectPathUserdata" then
                    local okName, assetName = pcall(function() return objectID:GetAssetPathName() end)
                    local okSub, subPath = pcall(function() return objectID:GetSubPathString() end)
                    local subText = okSub and text_value(subPath)
                    local value = okName and text_value(assetName)
                    if subText and subText ~= "" then
                        stats.unknown_soft_paths = stats.unknown_soft_paths + 1
                        return nil -- 软类必须是顶层类路径，不能把子对象地址裁成假的类路径。
                    end
                    if subText == "" and value then
                        if value == "" or value == "None" then return nil end
                        local parsed = exact_class_path(value)
                        if parsed then return parsed end
                    end
                end
            end
            -- 已核实的反射转换入口。参数包装若当前构建不支持，记录UNKNOWN，不拼_C。
            if not triedKismet then
                triedKismet = true
                if type(StaticFindObject) == "function" then
                    local ok, value = pcall(StaticFindObject, "/Script/Engine.Default__KismetSystemLibrary")
                    if ok and valid(value) then kismet = value end
                end
            end
            if refKind == "TSoftObjectPtrUserdata" and valid(kismet) then
                local ok, value = pcall(function() return kismet:Conv_SoftClassReferenceToString(reference) end)
                local parsed = ok and exact_class_path(text_value(value))
                if parsed then return parsed end
            end
            stats.unknown_soft_paths = stats.unknown_soft_paths + 1
            if stats.unknown_soft_paths <= 8 then log("软类路径未解析 type=" .. refKind .. "；未生成替代路径") end
            return nil
        end

        local function add(classPath, name, boss, enemyType, source, priority, location, display)
            if not classPath or conflicts[classPath] then return end
            local row = { class_path = classPath, zh_name = name, is_boss = boss, enemy_type = enemyType,
                source = source, priority = priority, location=location, name = display }
            local old = rows[classPath]
            if old and old.priority > priority then return end
            if old and old.priority == priority and (old.zh_name ~= name or old.is_boss ~= boss or old.enemy_type ~= enemyType) then
                rows[classPath], conflicts[classPath] = nil, true
                stats.conflicts = stats.conflicts + 1
                log("同一路径图鉴数据冲突，未任选名称: " .. classPath)
                return
            end
            rows[classPath] = row
        end

        for _, row in ipairs(list) do
            local enemy = field(row, "EnemyClass")
            local bossValue = field(row, "bIsBoss")
            local rawName = field(row, "Enemy_CH_Hans_Name")
            if enemy == nil or (type(bossValue) ~= "boolean" and rawName == nil) then
                stats.unknown_rows = stats.unknown_rows + 1
            else
                stats.decoded_rows = stats.decoded_rows + 1
                local name = text_value(rawName) or ""
                if name == "" then stats.unknown_names = stats.unknown_names + 1 end
                local display = localized_name(row)
                if display ~= "" then stats.localized_names = stats.localized_names + 1 else display = name end
                local boss = type(bossValue) == "boolean" and (bossValue and "1" or "0") or "UNKNOWN"
                local enemyType = ENEMY_TYPES[field(row, "EnemyType")] or "UNKNOWN"
                local mainPath = soft_path(enemy)
                local rawMap=field(row,'OwnMapID')
                local mapID=text_value(rawMap)
                local mapStatus=mapID and ((mapID=='' or mapID=='None') and 'unassigned' or 'assigned') or 'unknown'
                local location={own_map_id=mapStatus=='assigned' and mapID or '',map_status=mapStatus,
                    display_order=field(row,'DisplayOrder'),canonical_class_path=mainPath or ''}
                if options.locationsPath and mapStatus=='assigned' and options.maps then
                    local okMap,resolved=pcall(options.maps.resolve,options.maps,rawMap)
                    if okMap and type(resolved)=='table' then
                        for _,key in ipairs({'map_name','chapter_id','chapter_name','chapter_order','map_order','level_name'}) do
                            location[key]=resolved[key]
                        end
                    end
                end
                local replaced = soft_path(field(row, "ReplacedByEnemyClass"))
                local source = "native_codex:FCodexEnemyRow"
                if replaced then source = source .. ";replacement=" .. replaced end
                local useReplacement = field(row, "bUseReplacementTargetEntry")
                if type(useReplacement) == "boolean" then source = source .. ";use_replacement_entry=" .. tostring(useReplacement) end
                add(mainPath, name, boss, enemyType, source .. ";EnemyClass", 2, location, display)
                local aliases, _, aliasTruncated = array_items(field(row, "AliasEnemyClasses"), MAX_ALIASES)
                if aliasTruncated then stats.truncated = true end
                if aliases then
                    for _, alias in ipairs(aliases) do
                        local aliasPath = soft_path(alias)
                        if aliasPath then
                            stats.aliases = stats.aliases + 1
                            add(aliasPath, name, boss, enemyType, source .. ";AliasEnemyClasses;canonical=" .. (mainPath or "UNKNOWN"), 1, location, display)
                        end
                    end
                end
            end
        end
        local sorted = {}
        for _, row in pairs(rows) do sorted[#sorted + 1] = row end
        table.sort(sorted, function(a, b) return a.class_path < b.class_path end)
        if #sorted == 0 then return failure("没有解析出任何精确class_path；未覆盖已有codex.tsv", stats) end
        local lines = { "class_path\tzh_name\tis_boss\tenemy_type\tsource\tname\tname_lang\n" }
        for _, row in ipairs(sorted) do
            lines[#lines + 1] = table.concat({ clean(row.class_path), clean(row.zh_name), clean(row.is_boss),
                clean(row.enemy_type), clean(row.source), clean(row.name), clean(language) }, "\t") .. "\n"
        end
        local content = table.concat(lines)
        local okOpen, file = pcall(io.open, path, "w")
        if not okOpen or not file then return failure("无法打开codex.tsv", stats) end
        local okWrite, written = pcall(function() return file:write(content) end)
        local okFlush, flushed = pcall(function() return file:flush() end)
        local okClose, closed = pcall(function() return file:close() end)
        if not okWrite or not written or not okFlush or flushed ~= true or not okClose or closed ~= true then
            return failure("codex.tsv写入/flush/close未确认", stats)
        end
        if options.locationsPath then
            local fields={'class_path','own_map_id','map_name','chapter_id','chapter_name','chapter_order',
                'map_order','level_name','display_order','canonical_class_path','map_status','source'}
            local locationLines={table.concat(fields,'\t')..'\n'}
            local mapped=0
            for _,row in ipairs(sorted) do
                local values=row.location or {}
                values.class_path=row.class_path;values.source='native_codex_own_map_v1'
                if values.map_status=='assigned' then mapped=mapped+1 end
                local columns={}
                for _,key in ipairs(fields) do columns[#columns+1]=clean(values[key]) end
                locationLines[#locationLines+1]=table.concat(columns,'\t')..'\n'
            end
            local output=table.concat(locationLines)
            local opened,destination=pcall(io.open,options.locationsPath,'w')
            local published=false
            if opened and destination then
                local wrote,w=pcall(function() return destination:write(output) end)
                local flushed,f=pcall(function() return destination:flush() end)
                local closed,c=pcall(function() return destination:close() end)
                published=wrote and w~=nil and flushed and f==true and closed and c==true
            end
            stats.locations_published=published
            log('图鉴归属导出='..tostring(published)..'；有OwnMapID='..mapped..'/'..#sorted..'；不等于全部出现地图')
        end
        local message = string.format("原生图鉴导出%d条精确类路径；未知行=%d，软引用未解=%d，冲突=%d，truncated=%s；游戏语言=%s，本地化名称=%d/%d；全量覆盖UNKNOWN",
            #sorted, stats.unknown_rows, stats.unknown_soft_paths, stats.conflicts, tostring(stats.truncated),
            language ~= "" and language or "UNKNOWN", stats.localized_names, stats.decoded_rows)
        log(message)
        -- Readers that cache the file (the boss bars) read it again, so names follow a new export the same session.
        if options.onWritten then pcall(options.onWritten) end
        return { ok = true, count = #sorted, message = message, stats = stats }
    end

    return instance
end

return Exporter
