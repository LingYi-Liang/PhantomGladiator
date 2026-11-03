package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Levels=require('home_levels')

local function fs(files)
    return {open=function(path,mode)
        if mode=='r' then
            local text=files[path];if not text then return nil end
            return {read=function()return text end,close=function()return true end}
        end
        local parts={}
        return {write=function(_,s)parts[#parts+1]=s;files[path]=table.concat(parts);return true end,close=function()return true end}
    end}
end
local R='D:/unit-test/Runtime'
local files={
    [R..'/area-levels.tsv']=table.concat({'kind\tname\tparent\toffset\tlevel\tgame_level\tmap\tdifficulty_offsets',
        'area\tXiguA\t\t1.00\t1.00\t1.00\t\t','area\tXiguB\t\t2.00\t2.00\t2.00\t\t','area\tXiguC\t\t3.00\t3.00\t3.00\t\t','area\tXiguD\t\t4.00\t4.00\t4.00\t\t',
        'area\tFujizhilinA\t\t4.00\t4.00\t4.00\t\t','area\tFujizhilinB\t\t5.00\t5.00\t5.00\t\t','area\tFujizhilinC\t\t6.00\t6.00\t6.00\t\t',
        'area\tXueSeSenLin\t\t24.00\t24.00\t24.00\t\t','domain\tXiguA\t\t0.00\t1.00\t\tPBZ_Xigu_WP\t'},'\n')..'\n',
    [R..'/codex.tsv']=table.concat({'class_path\tzh_name\tis_boss\tenemy_type\tsource\tname\tname_lang',
        '/Game/M/BP_Monster_YuCong_FirstTime.BP_Monster_YuCong_FirstTime_C\t三面\t1\tPuppet\tx\t三面\tzh-Hans',
        '/Game/M/BP_Monster_Thug.BP_Monster_Thug_C\t暴徒\t0\tHuman\tx\t暴徒\tzh-Hans',
        '/Game/M/BP_Monster_Boss.BP_Monster_Boss_C\t头目\t1\tHuman\tx\t头目\tzh-Hans',
        '/Game/M/BP_Monster_Intro.BP_Monster_Intro_C\t少年\t1\tHuman\tx\t少年\tzh-Hans',
        '/Game/M/BP_Monster_Wanderer.BP_Monster_Wanderer_C\t游侠\t0\tHuman\tx\t游侠\tzh-Hans'},'\r\n')..'\r\n',
    [R..'/codex-locations.tsv']=table.concat({'class_path\town_map_id\tmap_name\tchapter_id',
        '/Game/M/BP_Monster_YuCong_FirstTime.BP_Monster_YuCong_FirstTime_C\tXiGu\t悲泣溪谷\tC1',
        '/Game/M/BP_Monster_Thug.BP_Monster_Thug_C\tFuJiZhiLin\t血色森林\tC2',
        '/Game/M/BP_Monster_Boss.BP_Monster_Boss_C\tFuJiZhiLin\t血色森林\tC2',
        '/Game/M/BP_Monster_Intro.BP_Monster_Intro_C\tZhuLinGuWu\t序章\t',
        '/Game/M/BP_Monster_Wanderer.BP_Monster_Wanderer_C\tXiGu\t悲泣溪谷\tC1'},'\n')..'\n',
}
-- Native levels as native_levels.lua writes them: {level before difficulty/cycle, area, map, spawners}.
local native={
    BP_Monster_YuCong_FirstTime={{15,'XiguA','XiGu',1}},
    BP_Monster_Wanderer={{2,'XiguB','XiGu',3},{3,'XiguC','XiGu',3},{19,'MeiguhuB','MeiGuHu',24},{0,'','ZhuLinGuWu',1}},
    BP_Monster_Roamer={{20,'ZhengdaodayingB','ZhengDaoDaYing',2},{18,'Meiguhu','MeiGuHu',5}},
}
local logs={}
local ctx={difficulty='Normal',cycle=0}
local function make()return Levels.new({log=function(m)logs[#logs+1]=m end,path=R,io=fs(files),
    native=native,context=function()return ctx end})end
local function logged(text)return table.concat(logs,'\n'):find(text,1,true)~=nil end
local levels=make()
assert(levels:refresh() and logged('读回 区域=8 有图鉴归属的单位=5 原生等级单位=3 难度=Normal 周目=0 写入=true 模式=HOME 自定义=nil 自选=0'),table.concat(logs,'\n'))

-- Native levels: every place the game puts the unit; by default where most of its spawners are on its codex map,
-- the higher level on a tie; a unit with none on its codex map takes its most common place anywhere.
local list,default=levels:choices('BP_Monster_Wanderer')
assert(#list==4 and list[1].level==1 and list[1].map_id=='ZhuLinGuWu' and list[1].map=='序章' and list[2].level==2 and list[2].part=='B' and list[4].level==19,'sorted by level; a level 0 place spawns at 1')
assert(default.level==3 and default.map=='悲泣溪谷' and default.part=='C' and default.count==3 and default.source=='native','home map, tie -> higher')
list,default=levels:choices('BP_Monster_Roamer')
assert(default.level==18 and default.map_id=='MeiGuHu' and default.count==5,'no codex home: the most common place')
list,default=levels:choices('BP_Monster_YuCong_FirstTime')
assert(#list==1 and default.level==15 and default.part=='A','a boss fight arena keeps its own level')
-- What the game adds on spawn: -1 on the lowest difficulty (never below 1), 25 per game cycle.
assert(levels:target('BP_Monster_YuCong_FirstTime').level==15)
ctx={difficulty='Handicapped',cycle=0}
assert(levels:target('BP_Monster_YuCong_FirstTime').level==14 and select(1,levels:choices('BP_Monster_Wanderer'))[1].level==1)
ctx={difficulty='Hard',cycle=2}
assert(levels:target('BP_Monster_YuCong_FirstTime').level==65-5 and levels:target('BP_Monster_Wanderer').level==53,'cycles add 25 each (capped at 60)')
assert(Levels.spawned(0,{difficulty='handicapped'})==1 and Levels.spawned(3,{difficulty='Nightmare'})==3)
ctx={difficulty='Normal',cycle=0}

-- Units no spawner places: the areas of their codex home map, deepest by default; an area that only shares the map's name too.
list,default=levels:choices('BP_Monster_Thug')
assert(#list==4 and list[1].level==4 and list[1].part=='A' and list[3].level==6 and list[4].source=='extra' and list[4].level==24)
assert(default.level==6 and default.source=='area' and default.map=='血色森林' and default.part=='C')
-- A boss without native levels is no different: its codex map's deepest area.
assert(select(2,levels:choices('BP_Monster_Boss')).level==6)
assert(levels.record==nil and files[R..'/unit-levels.tsv']==nil,'levels seen on map enemies are not kept any more')
-- The prologue has no area table: level 1. A unit without a home map or native level falls back to the nearby rule.
assert(levels:target('BP_Monster_Intro').level==1 and levels:target('BP_Monster_Intro').source=='prologue')
assert(levels:target('BP_Monster_Unknown')==nil)

-- Modes and picks, saved and read back by a new instance.
assert(levels:target('BP_Monster_Thug').level==6)
assert(levels:configure('BP_Monster_Thug','UNIT','4').ok and levels:target('BP_Monster_Thug').level==4 and levels:target('BP_Monster_Thug').source=='picked')
assert(levels:configure('','HERE','').ok and levels:target('BP_Monster_Thug')==nil,'HERE leaves it to the nearby rule')
assert(levels:configure('','CUSTOM','12').ok and levels:target('BP_Monster_YuCong_FirstTime').level==12)
assert(not levels:configure('','CUSTOM','61').ok and not levels:configure('','CUSTOM','').ok and levels:status().custom==12)
assert(not levels:configure('bad name','UNIT','3').ok and not levels:configure('','LOUD','3').ok)
assert(levels:configure('','HOME','').ok)
assert(files[R..'/spawn-level-settings.tsv']=='SpawnLevelSettingsV1\tHOME\t12\nunit\tBP_Monster_Thug\t4\n',files[R..'/spawn-level-settings.tsv'])
local again=make();again:refresh()
assert(again:status().mode=='HOME' and again:status().custom==12 and again:target('BP_Monster_Thug').level==4)
assert(again:configure('BP_Monster_Thug','UNIT','').ok and again:target('BP_Monster_Thug').level==6,'clearing a pick goes back to the default')

-- The app's file: every choice of every unit (codex or native), with the default, the pick and the spawner count.
again:configure('BP_Monster_Intro','UNIT','30')
again:configure('BP_Monster_Wanderer','UNIT','19')
local out=files[R..'/home-levels.tsv']
assert(out:find('^unit\tlevel\tsource\tmap\tpart\tdefault\tpicked\tcount\n'))
assert(out:find('\nBP_Monster_Thug\t6\tarea\t血色森林\tC\t1\t0\t0\n',1,true) and out:find('\nBP_Monster_Thug\t24\textra\t血色森林\t\t0\t0\t0\n',1,true),out)
assert(out:find('\nBP_Monster_YuCong_FirstTime\t15\tnative\t悲泣溪谷\tA\t1\t0\t1\n',1,true),out)
assert(out:find('\nBP_Monster_Wanderer\t3\tnative\t悲泣溪谷\tC\t1\t0\t3\nBP_Monster_Wanderer\t19\tnative\tMeiGuHu\tB\t0\t1\t24\n',1,true),out)
assert(out:find('\nBP_Monster_Roamer\t18\tnative\tMeiGuHu\t\t1\t0\t5\n',1,true),'a native unit without a codex entry is listed too')
assert(out:find('\nBP_Monster_Intro\t1\tprologue\t序章\t\t1\t0\t0\nBP_Monster_Intro\t30\tpicked\t\t\t0\t1\t0\n',1,true),out)
-- Where the player is, from the game's own spawners (native_places.lua, metres): the highest within the radius,
-- else the nearest; with the difficulty and cycle of the unit asked for.
local placed=Levels.new({log=function()end,path=R,io=fs(files),native={},context=function(actor)return actor or {difficulty='Normal',cycle=0}end,
    places={PBZ_Test_WP={{0,0,0,2},{150,0,0,4},{0,500,0,9}}}})
local near=placed:nearest('PBZ_Test_WP',{X=1000,Y=0,Z=0},200)
assert(near.level==4 and near.near and math.abs(near.distance-140)<0.01,'highest within 200 m')
near=placed:nearest('PBZ_Test_WP',{X=0,Y=80000,Z=0},200)
assert(near.level==9 and not near.near and math.abs(near.distance-300)<0.01,'none within: the nearest')
assert(placed:nearest('PBZ_Test_WP',{X=0,Y=0,Z=0},200,{difficulty='Handicapped',cycle=1}).level==28,'the unit\'s difficulty and cycle')
assert(placed:nearest('PBZ_Other_WP',{X=0,Y=0,Z=0},200)==nil and placed:nearest('PBZ_Test_WP',nil,200)==nil)
print('home_levels: PASS (native levels with difficulty and cycle, home-map default, area fallback, prologue, modes, picks, app file, places)')
