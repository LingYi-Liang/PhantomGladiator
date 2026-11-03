local Maps=dofile('Mods/PhantomGladiator/Scripts/world_map_catalog.lua')
local function object(id,extra)
    local o=extra or {};o.alive=true
    function o:IsValid() return self.alive end
    function o:GetAddress() assert(self.alive);return id end
    return o
end
local function value(s) return {ToString=function() return s end} end
local w1,w2=object(1),object(2)
local mc,cc=0,0
local map={MapID=value('map_A'),MapName={ValueCache=value('地图原文')},MapOrder=4,
    LevelName=value('Actual_Level_Name'),OwnChapterID=value('chapter_Z')}
local chapter={ChapterID=value('chapter_Z'),ChapterName={ValueCache=value('章节原文')},ChapterOrder=7}
local bell=object(3,{GetOuter=function() return w1 end,
    GetMapData=function(_,id) assert(id:ToString()=='map_A');mc=mc+1;return map end,
    GetChapterData=function(_,id) assert(id:ToString()=='chapter_Z');cc=cc+1;return chapter end,
    GetMapNameTextFromMapID=function() return value('地图显示名') end})
local other=object(4,{GetOuter=function() return w2 end,GetMapData=function() error('wrong world') end})
local current=w1
local options={getWorld=function() return current end,findAll=function(class)
    if class=='BellManager' then return {other,bell} end
    assert(class=='EventPipelineManager');return {}
end}
LoadAsset=function() error('classification must not load units') end
local lookup=Maps.new(options)
local got=lookup:resolve(value('map_A'))
assert(got.map_name=='地图显示名' and got.chapter_id=='chapter_Z' and got.chapter_name=='章节原文')
assert(got.chapter_order==7 and got.map_order==4 and got.level_name=='Actual_Level_Name')
lookup:resolve(value('map_A'));assert(mc==1 and cc==1,'cache each map, not each enemy')
assert(next(lookup:resolve(value('None')))==nil)
map.MapID=value('wrong_map');lookup=Maps.new(options)
assert(next(lookup:resolve(value('map_A')))==nil and cc==1,'wrong ID must not acquire chapter evidence')
map.MapID=value('map_A');chapter.ChapterID=value('wrong_chapter');lookup=Maps.new(options)
got=lookup:resolve(value('map_A'))
assert(got.chapter_id=='chapter_Z' and got.chapter_name=='' and got.chapter_order==nil)
chapter.ChapterID=value('chapter_Z');bell.alive=false;lookup=Maps.new(options)
assert(next(lookup:resolve(value('map_A')))==nil)
bell.alive=true
options.findAll=function() return {bell,object(5,{GetOuter=function() return w1 end})} end
lookup=Maps.new(options);assert(next(lookup:resolve(value('map_A')))==nil,'ambiguous subsystem must not be chosen')
print('world_map_catalog: PASS (exact World/row IDs, real names/order, cache, unknown/missing/invalid guards; no game changes)')
