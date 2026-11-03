package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Areas=require('area_levels')
local function fname(s)return {ToString=function()return s end}end
FName=function(s)return fname(s)end
local function object(fields)fields.IsValid=function()return true end;return fields end
local invalid={IsValid=function()return false end}

-- Rows {Parent, LevelOffset}: a chain, a loop and a row whose parent is missing.
local rows={Root={Parent=fname('None'),LevelOffset=1},XiGu={Parent=fname('Root'),LevelOffset=4},
    XiGu_Cave={Parent=fname('XiGu'),LevelOffset=2},Loop_A={Parent=fname('Loop_B'),LevelOffset=1},
    Loop_B={Parent=fname('Loop_A'),LevelOffset=1},Orphan={Parent=fname('Missing'),LevelOffset=3}}
local areaTable=object({GetRowMap=function()return rows end})
local gameLevels={Root=1,XiGu=5,XiGu_Cave=8}
local helper=object({GetAILevel=function(_,_,row)return gameLevels[row:ToString()]end})
local domain=object({['Level Area Name']=fname('XiGu_Cave'),['Level Offset']=0,['Level Area Table']=areaTable,
    ['Offset By Difficulty']={ForEach=function(_,fn)fn(3,2);fn(1,0)end},
    ['Get AI Level']=function()return 7 end,
    GetFullName=function()return 'PBZ_MobDomain_C /Game/Maps/B01/PBZ_Xigu_WP.PBZ_Xigu_WP:PersistentLevel.PBZ_MobDomain_C_1' end})
local byPath,domains={},{domain}
StaticFindObject=function(path)return byPath[path] or invalid end
FindAllOf=function(name)assert(name=='PBZ_MobDomain_C');return #domains>0 and domains or nil end
byPath['/PBZCombatAsset/Config/AIData/DT_AIAreaLevel.DT_AIAreaLevel']=areaTable
byPath['/Script/PBZCombatAsset.Default__AIAreaLevelTableHelper']=helper

local files,logs={},{}
local fs={open=function(path,mode)assert(mode=='w');local parts={}
    return {write=function(_,s)parts[#parts+1]=s;files[path]=table.concat(parts);return true end,close=function()return true end}end}
local function logged(text)return table.concat(logs,'\n'):find(text,1,true)~=nil end
local areas=Areas.new({log=function(m)logs[#logs+1]=m end,path='D:/unit-test/Runtime',io=fs})

local result=areas:export()
local tsv=files['D:/unit-test/Runtime/area-levels.tsv']
assert(result.ok and result.rows==6 and result.domains==1 and result.mismatches==1)
assert(tsv:find('^kind\tname\tparent\toffset\tlevel\tgame_level\tmap\tdifficulty_offsets\n'))
assert(tsv:find('\narea\tRoot\t\t1.00\t1.00\t1.00\t\t\n',1,true),tsv)
assert(tsv:find('\narea\tXiGu\tRoot\t4.00\t5.00\t5.00\t\t\n',1,true),'a level is its parent\'s plus its own offset')
assert(tsv:find('\narea\tXiGu_Cave\tXiGu\t2.00\t7.00\t8.00\t\t\n',1,true),'the game\'s own answer is kept beside it')
assert(tsv:find('\narea\tLoop_A\tLoop_B\t1.00\t\t\t\t\n',1,true) and tsv:find('\narea\tOrphan\tMissing\t3.00\t\t\t\t\n',1,true),'a loop or a missing parent stays unknown')
assert(tsv:find('\ndomain\tXiGu_Cave\t\t0.00\t7.00\t\tPBZ_Xigu_WP\t1=0.00,3=2.00\n',1,true),tsv)
assert(tsv:find('area\tLoop_A',1,true)<tsv:find('area\tRoot',1,true),'rows are sorted by name')
assert(logged('操作=只读 /PBZCombatAsset/Config/AIData/DT_AIAreaLevel.DT_AIAreaLevel 的全部行和当前已加载的 PBZ_MobDomain；不加载资源、不写游戏对象'))
assert(logged('读回 表=按路径找到 行=6 算出等级=3 范围=1.00～7.00 与游戏GetAILevel不一致=1 游戏函数=可用 已加载刷怪区域=1 写入=true'),table.concat(logs,'\n'))
assert(logged('样本 Loop_A= Loop_B= Orphan= Root=1.00 XiGu=5.00 XiGu_Cave=7.00'))

-- The table is not found by path: it is taken from a loaded mob domain.
byPath['/PBZCombatAsset/Config/AIData/DT_AIAreaLevel.DT_AIAreaLevel']=nil;logs={}
assert(areas:export().rows==6 and logged('读回 表=取自已加载的刷怪区域 行=6'))
-- Nothing loaded: an empty file and an honest log.
domains={};logs={}
local empty=areas:export()
assert(empty.rows==0 and empty.domains==0 and files['D:/unit-test/Runtime/area-levels.tsv']=='kind\tname\tparent\toffset\tlevel\tgame_level\tmap\tdifficulty_offsets\n')
assert(logged('读回 表=没有加载 行=0 算出等级=0 范围=～ 与游戏GetAILevel不一致=0 游戏函数=可用 已加载刷怪区域=0 写入=true'),table.concat(logs,'\n'))
print('area_levels: PASS (rows along parents, game cross-check, loops and missing parents, domains with map and difficulty offsets, table from a domain, nothing loaded)')
