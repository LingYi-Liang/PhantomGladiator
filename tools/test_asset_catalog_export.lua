-- Pure Lua tests. No game calls, actual files, asset loading or unpacking.
local Exporter = dofile("Mods/PhantomGladiator/Scripts/asset_catalog_export.lua")
local originalOpen, originalTime = io.open, os.time
local files, logs, queried, fakeTime, onGameThread = {}, {}, {}, 100, true
local buffers, flushCalls, closeCalls = {}, {}, {}
local registry, helpers
local function value(s) return { ToString = function() return s end } end
local function param(v) return { get = function() return v end } end
local function object(t)
    t = t or {}; t.IsValid = function() return true end; return t
end
local function asset(package, name, kind, tags)
    return { PackageName = value(package), PackagePath = value(package:match("^(.*)/[^/]+$")),
        AssetName = value(name), AssetClassPath = { PackageName = value("/Script/Engine"), AssetName = value(kind) },
        __native_tags = tags or {}, __original_asset_data = true }
end
local data, cachedPaths, loaded = {}, {}, {}
local function reset()
    files, logs, queried, data, cachedPaths, loaded = {}, {}, {}, {}, {}, {}
    buffers, flushCalls, closeCalls = {}, {}, {}
    onGameThread = true
    IsInGameThread = function() return onGameThread end
    -- UE4SS constructors may be callable class tables rather than Lua functions.
    FName = setmetatable({}, { __call = function(_, s) return s end })
    LoadAsset = function() error("must not load any assets") end
    registry = object({
        IsLoadingAssets = function() return false end,
        GetAllCachedPaths = function(_, out)
            for i, path in ipairs(cachedPaths) do out[i] = param(value(path)) end
        end,
        GetAssetsByPath = function(_, path, out, recursive, onDisk)
            assert(recursive == false and onDisk == true)
            queried[#queried + 1] = path
            for i, row in ipairs(data[path] or {}) do out[i] = param(row) end
            return true
        end,
    })
    helpers = object({
        GetAssetRegistry = function() return registry end,
        GetTagValue = function(_, row, tag, out)
            assert(row.__original_asset_data, "must pass original FAssetData proxy; copying reflected fields loses opaque tags")
            local result = row.__native_tags[tag]
            if result then out.OutTagValue = value(result); return true end
            return false
        end,
    })
    StaticFindObject = function(path)
        if path == "/Script/AssetRegistry.Default__AssetRegistryHelpers" then return helpers end
        return loaded[path]
    end
    io.open = function(path, mode)
        assert(mode == "w")
        files[path], buffers[path] = "", ""
        return { write = function(self, s) buffers[path] = buffers[path] .. s; return self end,
            flush = function()
                flushCalls[path] = (flushCalls[path] or 0) + 1
                files[path] = buffers[path]
                return true
            end,
            close = function()
                closeCalls[path] = (closeCalls[path] or 0) + 1
                files[path] = buffers[path]
                return true
            end }
    end
    os.time = function() return fakeTime end
end
local function exporter(config)
    return Exporter.new({ path = "D:/unit-test/Runtime/catalog.tsv", config = config or {},
        log = function(message) logs[#logs + 1] = message end })
end
local function done(e)
    for _ = 1, 25 do if not e:status().active then return end; e:tick() end
    error("export did not finish")
end

reset()
cachedPaths = { "/Game/B", "/Game/A", "/Game/A" }
local exact = "/UnloadedPlugin/Mobs/Silent.Silent_C"
data["/Game/A"] = {
    asset("/Game/A/BP_Silent", "BP_Silent", "Blueprint", {
        GeneratedClass = "BlueprintGeneratedClass'" .. exact .. "'",
        NativeParentClass = "/Script/CoreUObject.Class'/Script/ProjectPBZ.PBZCharacter_NPC'" }),
    asset("/Game/A/BP_Crate", "BP_Crate", "Blueprint", { NativeParentClass = "/Script/Engine.Actor" }),
}
data["/Game/B"] = {
    asset("/Game/B/BP_Boss_Unknown", "BP_Boss_Unknown", "Blueprint"),
    asset("/Game/B/BP_Monster_Direct", "BP_Monster_Direct_C", "BlueprintGeneratedClass"),
}
local loadedGenerated = "/Game/B/BP_Monster_Direct.BP_Monster_Direct_C"
loaded[loadedGenerated] = object({ IsAnyClass = function() return true end,
    IsClass = function() error("must use IsAnyClass for generated classes") end })
local e = exporter()
local began, startState = e:start()
if not began then print("start failed: " .. tostring(startState.reason) .. "; FName type=" .. type(FName)) end
assert(began, "callable-table FName must be accepted")
assert(#queried == 0, "start must only get registry paths")
e:tick()
assert(#queried == 1 and e:status().paths_done == 1)
assert(flushCalls["D:/unit-test/Runtime/catalog.tsv.partial"] == 1)
assert(files["D:/unit-test/Runtime/catalog.tsv.partial"]:find(exact, 1, true), "completed partial rows must be visible after this tick")
assert(files["D:/unit-test/Runtime/catalog.tsv"] == nil, "do not publish a half-written catalog")
done(e)
local s, output = e:status(), files["D:/unit-test/Runtime/catalog.tsv"]
assert(s.published and s.complete and not s.truncated and s.coverage == "UNKNOWN")
assert(s.candidates == 3 and s.unresolved == 1 and s.unclassified_blueprints == 1)
assert(output:match("^id\tname\tcategory\tclass_path\tloaded\tspawnable\treason\n"))
assert(output:find(exact .. "\tBP_Silent", 1, true), "unloaded class is found through registry metadata")
assert(output:find(exact .. "\t0\t1\t", 1, true), "valid discovered class path is attemptable without loading")
assert(output:find("/Game/B/BP_Boss_Unknown.BP_Boss_Unknown\tBP_Boss_Unknown\tBOSS\t\t0\t0\t", 1, true))
assert(not output:find("BP_Boss_Unknown_C", 1, true), "must not guess GeneratedClass by appending _C")
assert(output:find(loadedGenerated .. "\t1\t1\t", 1, true), "BlueprintGeneratedClass must be marked loaded via IsAnyClass")

reset()
cachedPaths = { "/Other/Z", "/Game/Character/Hero", "/PBZCombatAsset/ActorData/Mobs/A",
    "/Other/A", "/Game/NPC", "/PBZCombatAsset/ActorData", "/Game/Summon" }
local sourcePaths = {}
for _, path in ipairs(cachedPaths) do sourcePaths[path] = true end
e = exporter({ PathsPerTick = 4 }); assert(e:start()); done(e)
assert(queried[1] == "/PBZCombatAsset/ActorData" and queried[2] == "/PBZCombatAsset/ActorData/Mobs/A")
assert(queried[3] == "/Game/Character/Hero" and queried[4] == "/Game/NPC" and queried[5] == "/Game/Summon")
assert(queried[6] == "/Other/A" and queried[7] == "/Other/Z")
assert(#queried == #cachedPaths)
for _, path in ipairs(queried) do assert(sourcePaths[path], "priority sorting must not create guessed paths") end

reset()
cachedPaths = { "/Game/A" }
local workingOpen = io.open
io.open = function(path, mode)
    local file = workingOpen(path, mode)
    if path:match("%.tsv$") then file.flush = function() return nil, "disk full" end end
    return file
end
e = exporter(); assert(e:start()); done(e)
assert(not e:status().published and not e:status().complete)
assert(e:status().reason == "publish_write_failed" and e:status().last_error == "disk full")
assert(closeCalls["D:/unit-test/Runtime/catalog.tsv"] == 1, "close must still run after flush failure")

reset()
cachedPaths = { "/Game/A" }
workingOpen = io.open
io.open = function(path, mode)
    local file = workingOpen(path, mode)
    if path:match("%.tsv$") then file.close = function() return nil, "close failed" end end
    return file
end
e = exporter(); assert(e:start()); done(e)
assert(not e:status().published and e:status().last_error == "close failed")

reset()
cachedPaths = { "/Game/A" }
workingOpen = io.open
io.open = function(path, mode)
    local file = workingOpen(path, mode)
    if path:match("%.partial$") then file.flush = function() return nil, "partial flush failed" end end
    return file
end
e = exporter(); assert(e:start()); e:tick()
assert(not e:status().active and not e:status().published and e:status().reason == "partial_flush_failed")
assert(closeCalls["D:/unit-test/Runtime/catalog.tsv.partial"] == 1)

reset()
cachedPaths = { "/Game/A" }
data["/Game/A"] = {
    asset("/Game/A/BP_Monster_A", "BP_Monster_A_C", "BlueprintGeneratedClass"),
    asset("/Game/A/BP_Monster_B", "BP_Monster_B_C", "BlueprintGeneratedClass"),
}
e = exporter({ MaxAssetsPerPath = 1 })
assert(e:start()); done(e)
assert(e:status().truncated and not e:status().complete and e:status().assets_reported == 2)

reset()
cachedPaths = { "/Game/A" }
registry.GetAssetsByPath = function() return false end
e = exporter(); assert(e:start()); done(e)
assert(e:status().query_errors == 1 and not e:status().complete)

reset()
cachedPaths = { "/Game/A" }
registry.GetAssetsByPath = function() return nil end
e = exporter(); assert(e:start()); done(e)
assert(e:status().query_errors == 1, "nil query return must not count as verified success")

reset()
cachedPaths = { "/Game/A" }
registry.IsLoadingAssets = function() return true end
e = exporter(); assert(e:start()); done(e)
assert(e:status().truncated and not e:status().complete, "registry loading invalidates completeness")

reset()
cachedPaths = { "/Game/A" }
e = exporter(); assert(e:start()); e:cancel("manual")
assert(not e:status().active and not e:status().published and #queried == 0)

reset()
onGameThread = false
e = exporter(); assert(not e:start())
assert(e:status().reason == "requires_game_thread")

reset()
FName = nil
e = exporter(); assert(not e:start())
assert(e:status().reason == "missing_ue4ss_api")
assert(e:status().last_error:find("FName=nil", 1, true))
assert(logs[1]:find("StaticFindObject=function; FName=nil; IsInGameThread=function", 1, true))

reset()
cachedPaths = { "/Game/A" }
FName = {} -- exists but is not callable: report the real call failure, never claim successful traversal
e = exporter(); assert(e:start()); done(e)
assert(e:status().query_errors == 1 and not e:status().complete)

reset()
helpers.GetAssetRegistry = function() return { IsValid = function() return false end } end
e = exporter(); assert(not e:start())
assert(e:status().reason == "registry_interface_unavailable")

reset()
registry.GetAllCachedPaths = function() error("interface function not callable") end
e = exporter(); assert(not e:start())
assert(e:status().reason == "cached_paths_api_failed")

reset()
cachedPaths = { "/Game/A" }
e = exporter({ MaxSeconds = 5 }); assert(e:start())
fakeTime = fakeTime + 6
e:tick()
assert(e:status().reason == "time_limit" and e:status().truncated)

io.open, os.time = originalOpen, originalTime
print("asset_catalog_export: PASS (registry metadata, loaded generated classes, path priority, partial flush, publication IO errors, bounds)")
