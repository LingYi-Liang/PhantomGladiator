local Exporter = dofile("Mods/PhantomGladiator/Scripts/codex_catalog_export.lua")
local realOpen = io.open
local files, logs, worlds, subsystems, entries, calls, gameThread, kismet, fileCloseResult
local path = "D:/unit-test/Runtime/codex.tsv"
local locationsPath='D:/unit-test/Runtime/codex-locations.tsv'
local function object(id, data)
    data = data or {}
    data.alive = true
    data.IsValid = function(self) return self.alive end
    data.GetAddress = function(self) assert(self.alive); return id end
    data.type = function() return "UObject" end
    return data
end
local function text(s, name)
    return { type = function() return name or "FString" end, ToString = function() return s end }
end
local function soft(p, sub)
    return { type = function() return "TSoftObjectPtrUserdata" end,
        GetObjectID = function() return {
            type = function() return "FSoftObjectPathUserdata" end,
            GetAssetPathName = function() return text(p or "None", "FName") end,
            GetSubPathString = function() return text(sub or "") end,
        } end }
end
local function param(value)
    return { type = function() return "LocalUnrealParam" end, get = function() return value end }
end
local function row(p, name, boss, enemyType, aliases)
    return { EnemyClass = soft(p), Enemy_CH_Hans_Name = text(name), bIsBoss = boss, EnemyType = enemyType,
        ReplacedByEnemyClass = soft(nil), AliasEnemyClasses = aliases or {}, bUseReplacementTargetEntry = false }
end
local function reset()
    files, logs, calls, entries, subsystems = {}, {}, 0, {}, {}
    worlds = { object(1), object(2) }
    gameThread, fileCloseResult = true, true
    kismet = nil
    IsInGameThread = function() return gameThread end
    FindAllOf = function(name) assert(name == "PBZCodexSubsystem"); return subsystems end
    StaticFindObject = function(name) assert(name == "/Script/Engine.Default__KismetSystemLibrary"); return kismet end
    LoadAsset = function() error("codex must not load assets") end
    io.open = function(name, mode)
        assert((name == path or name==locationsPath) and mode == "w")
        files[name] = ""
        return { write = function(self, contents) files[name] = files[name] .. contents; return self end,
            flush = function() return true end, close = function() return fileCloseResult end }
    end
end
local function subsystem(id, world)
    return object(id, { GetOuter = function(self) assert(self.alive); return world end,
        GetAllEnemyCodexEntries = function(self) assert(self.alive); calls = calls + 1; return entries end,
        RevealAllConfiguredEnemies = function() error("must not reveal") end,
        ClearAllDiscovered = function() error("must not mutate saves") end })
end
local function make()
    return Exporter.new({ path = path, getWorld = function() return worlds[1] end,
        log = function(message) logs[#logs + 1] = message end })
end

reset()
subsystems = { subsystem(10, worlds[2]), subsystem(11, worlds[1]) }
local main = "/PBZCombatAsset/ActorData/Mobs/Test/BP_Monster_A.BP_Monster_A_C"
local alias = "/PBZCombatAsset/ActorData/Mobs/Test/BP_Monster_Alias.BP_Monster_Alias_C"
local replacement = "/PBZCombatAsset/ActorData/Mobs/Test/BP_Monster_Replacement.BP_Monster_Replacement_C"
local first = row(main, "原生敌人名称", true, 4, { param(soft(alias)) })
first.ReplacedByEnemyClass, first.bUseReplacementTargetEntry = soft(replacement), true
entries = { param(first) }
local result = make():export()
assert(result.ok and result.count == 2 and calls == 1)
assert(files[path]:match("^class_path\tzh_name\tis_boss\tenemy_type\tsource\tname\tname_lang\n"))
assert(files[path]:find(main .. "\t原生敌人名称\t1\tHumanMaster\t", 1, true))
assert(files[path]:find(alias .. "\t原生敌人名称\t1\tHumanMaster\t", 1, true))
assert(files[path]:find("\t原生敌人名称\t\n", 1, true), "without a localized name the Chinese one is used, language unknown")
assert(not files[path]:find("\n" .. replacement .. "\t", 1, true), "replacement must not inherit another row's identity")
assert(files[path]:find("replacement=" .. replacement, 1, true))
for line in files[path]:gmatch("([^\n]+)\n") do
    local _,tabs=line:gsub("\t","")
    assert(tabs==6,"codex.tsv must have exactly seven columns; helper multi-return must not add a count")
end

reset()
subsystems = { subsystem(10, worlds[1]) }
entries = { { RowClass = soft(main), Name = "unsupported guessed schema" } }
result = make():export()
assert(not result.ok and result.stats.unknown_rows == 1 and not files[path] and calls == 1)

reset()
subsystems = { subsystem(10, worlds[1]) }
entries = { unexpected = "map schema" }
result = make():export()
assert(not result.ok and not files[path] and calls == 1)
assert(table.concat(logs, "\n"):find("count=UNKNOWN", 1, true))

reset()
subsystems = { subsystem(10, worlds[2]) }
result = make():export()
assert(not result.ok and calls == 0, "do not query another world's subsystem")

reset()
subsystems = { subsystem(10, worlds[1]), subsystem(11, worlds[1]) }
result = make():export()
assert(not result.ok and calls == 0, "ambiguous world match must not choose arbitrarily")

reset()
local dead = subsystem(10, worlds[1]); dead.alive = false
subsystems = { dead, subsystem(11, worlds[1]) }
entries = { param(row(main, "可读名", false, 1)) }
result = make():export()
assert(result.ok and result.count == 1 and calls == 1)

reset()
subsystems = { subsystem(10, worlds[1]) }
entries = { param(row(main, "别名冲突一", false, 1)), param(row(main, "别名冲突二", false, 1)) }
result = make():export()
assert(not result.ok and result.stats.conflicts == 1 and not files[path])

reset()
subsystems = { subsystem(10, worlds[1]) }
local converted = { type = function() return "TSoftObjectPtrUserdata" end, GetObjectID = function() error("not exposed") end }
local fallbackRow = row(main, "转换名称", false, 2); fallbackRow.EnemyClass = converted
entries = { param(fallbackRow) }
kismet = object(20, { Conv_SoftClassReferenceToString = function(_, value) assert(value == converted); return text(main) end })
result = make():export()
assert(result.ok and result.count == 1)

reset()
subsystems = { subsystem(10, worlds[1]) }
local noPathRow = row(main, "不能猜路径", false, 1); noPathRow.EnemyClass = { type = function() return "UnknownSoftWrapper" end }
entries = { param(noPathRow) }
result = make():export()
assert(not result.ok and result.stats.unknown_soft_paths == 1 and not files[path])

reset()
subsystems = { subsystem(10, worlds[1]) }
local subObjectRow = row(main, "不是顶层类", false, 1); subObjectRow.EnemyClass = soft(main, "SubObject")
entries = { param(subObjectRow) }
result = make():export()
assert(not result.ok and not files[path])

reset()
subsystems = { subsystem(10, worlds[1]) }
entries = { type = function() return "TArray" end,
    ForEach = function(_, callback) callback(1, param(row(main, "数组包装", false, 5))) end }
setmetatable(entries, { __len = function() return 1 end })
result = make():export()
assert(result.ok and result.count == 1)

reset()
subsystems = { subsystem(10, worlds[1]) }
entries = { param(row(main, "未写成功", false, 1)) }
fileCloseResult = nil
result = make():export()
assert(not result.ok, "failed close must not be reported as export success")

reset()
subsystems={subsystem(10,worlds[1])}
local placed=row(main,'归属测试',false,4,{param(soft(alias))})
placed.OwnMapID=text('Map_A','FName');placed.DisplayOrder=8
entries={param(placed)}
local mappingCalls=0
result=Exporter.new({path=path,locationsPath=locationsPath,getWorld=function() return worlds[1] end,
    maps={resolve=function(_,mapID)
        mappingCalls=mappingCalls+1;assert(mapID:ToString()=='Map_A')
        return {map_name='实际地图',chapter_id='Chapter_X',chapter_name='实际章节',chapter_order=3,map_order=4,level_name='ActualLevel'}
    end}}):export()
assert(result.ok and mappingCalls==1 and result.stats.locations_published==true)
for line in files[locationsPath]:gmatch('([^\n]+)\n') do
    local _,tabs=line:gsub('\t','');assert(tabs==11,'locations contract has exactly 12 columns')
end
assert(files[locationsPath]:find(main..'\tMap_A\t实际地图\tChapter_X\t实际章节\t3\t4\tActualLevel\t8\t'..main..'\tassigned\tnative_codex_own_map_v1',1,true))
assert(files[locationsPath]:find(alias..'\tMap_A\t实际地图',1,true),'official aliases inherit the row affiliation')

-- The name in the game's language: EnemyName resolved by the map catalog, else its cached text; the language tags every row.
reset()
subsystems = { subsystem(10, worlds[1]) }
local named = row(main, "原生敌人名称", true, 4, { param(soft(alias)) })
named.EnemyName = { type = function() return "UScriptStruct" end, ValueCache = text("Cached Enemy", "FText") }
entries = { param(named) }
local localizeCalls, rereads = 0, 0
result = Exporter.new({ path = path, getWorld = function() return worlds[1] end, language = function() return "en" end,
    onWritten = function() assert(files[path]:find("\tNative Enemy\ten\n", 1, true)); rereads = rereads + 1 end,
    maps = { localize = function(_, value) localizeCalls = localizeCalls + 1; assert(value == named.EnemyName); return "Native Enemy" end } }):export()
assert(result.ok and result.stats.localized_names == 1 and localizeCalls == 1)
assert(rereads == 1, "readers that cache codex.tsv are told once the new file is written")
assert(files[path]:find(main .. "\t原生敌人名称\t1\tHumanMaster\t", 1, true))
assert(files[path]:find("\tNative Enemy\ten\n", 1, true) and select(2, files[path]:gsub("\tNative Enemy\ten\n", "")) == 2, "aliases share the name")
reset()
subsystems = { subsystem(10, worlds[1]) }
entries = { param(named) }
result = Exporter.new({ path = path, getWorld = function() return worlds[1] end, language = function() return "zh-Hans; bad" end,
    maps = { localize = function() return "" end } }):export()
assert(result.ok and files[path]:find("\tCached Enemy\tzh-Hansbad\n", 1, true), "cached text when the game cannot resolve it; language sanitized")

reset(); gameThread = false
assert(not Exporter.new({ path = path, getWorld = function() return worlds[1] end,
    onWritten = function() rereads = rereads + 1 end }):export().ok and calls == 0)
assert(rereads == 1, "no reread without a new file")
io.open = realOpen
print("codex_catalog_export: PASS (world ownership, native row schema, exact soft paths, aliases, unknown schema, no load/reveal, IO failure, names in the game's language)")
