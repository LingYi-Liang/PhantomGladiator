local Tables=dofile('Mods/PhantomGladiator/Scripts/table_catalog_export.lua')
local realOpen=io.open;local output=''
io.open=function()return {write=function(self,s)output=output..s;return self end,flush=function()return true end,close=function()return true end}end
local function object(name,extra)
    local o=extra or {};o.IsValid=function()return true end;o.GetFullName=function()return name end;return o
end
local function path(s)return {GetAssetPathName=function()return s end,GetSubPathString=function()return ''end}end
local tableNames=0
local function dt(schema,data)
    local structure=object('ScriptStruct /Script/'..schema)
    local tableObject=object('DataTable /Game/Test.Test',{GetRowStruct=function()return structure end,GetRowMap=function()return data end})
    function tableObject:GetFullName()tableNames=tableNames+1;return 'DataTable /Game/Test.Test'end
    return tableObject
end
local list={
 dt('ProjectPBZ.MapData',{row={MapID='Map_A'}}),
 dt('ProjectPBZ.ChapterData',{row={ChapterID='Chapter_A',ChapterName='Actual chapter',ChapterOrder=2}}),
 dt('PBZCombatAsset.PBZCharacterAttributeTableData',{row={AssetPath={AssetPath={PackageName='/Game/Config',AssetName='Config'},SubPathString=''},MaxHealth_Base=400}}),
 dt('ProjectPBZ.SeqHeadSwapRow',{row={CharacterId='Actor_A',GameplayCharacterClass=path('/Game/A.A_C'),HighQHeadSourceClass=path('/Game/Seq.Seq_C'),bEnabled=false}}),
 dt('ProjectPBZ.CodexDataStruct',{row={CodexID='Npc_A',NPCName='Official name',BIsMonster=false},other={CodexID='Npc_B',NPCName='Second name'}}),
 dt('Unknown.Schema',{}),
}
list[6].GetRowMap=function()error('unknown schema must not be touched')end
IsInGameThread=function()return true end;FindAllOf=function(k)assert(k=='DataTable');return list end
LoadAsset=function()error('must not load')end
local result=Tables.new({path='D:/test-tables',maps={resolve=function(_,id)assert(id=='Map_A');return {map_name='Actual map',chapter_id='Chapter_A'}end,
    localize=function(_,v)return v end}}):export()
assert(result.ok and result.tables==5 and result.rows==6 and result.errors==0)
assert(tableNames==5,'table name readback must not repeat for every row')
assert(output:find('/Game/Config.Config',1,true) and output:find('/Game/Seq.Seq_C',1,true) and output:find('Official name',1,true))
assert(output:find('\tfalse\t',1,true),'false metadata must remain explicit')
for line in output:gmatch('([^\n]+)\n')do local _,tabs=line:gsub('\t','');assert(tabs==16)end
local syncOutput=output
local descriptors,loads={},0
for i,item in ipairs(list)do
    local tablePath='/Game/Test'..i..'.Test'..i
    local original=item.GetRowMap
    function item:GetFullName()return 'DataTable '..tablePath end
    function item:GetRowMap()loads=loads+1;return original(self)end
    descriptors[tablePath]=item
end
StaticFindObject=function(name)return descriptors[name]end
local batched=Tables.new({path='D:/test-tables',maps={
    resolve=function()return {map_name='Actual map',chapter_id='Chapter_A'}end,
    localize=function(_,v)return v end}})
assert(type(batched.step)=='function','runtime export needs a per-heartbeat native table step')
output=''
local initial=batched:step('map-1',0)
assert(initial.pending and loads==0 and output=='','discovery does not borrow row pointers across callbacks')
batched:step('map-1',0)
assert(loads==1 and output=='','one table per callback, with the previous final file left in place')
local before=loads
assert(batched:step('map-2',0).pending and loads==before,'travel discards incomplete data without row reads')
local complete
for _=1,8 do
    local prior=loads;local state=batched:step('map-2',0)
    assert(loads-prior<=1,'a single heartbeat read too many native row maps')
    if state.ok then complete=state;break end
    assert(state.pending and output=='','no partially published export')
end
assert(complete and complete.tables==5 and complete.rows==6)
assert(output:find('Official name',1,true) and output:find('Actual map',1,true) and output:find('Second name',1,true))
local _,newLines=output:gsub('\n','')
local _,oldLines=syncOutput:gsub('\n','')
assert(newLines==oldLines,'the incremental export has the same schema and row coverage')
io.open=realOpen
print('table_catalog_export: PASS (exact schemas only, native references/labels, explicit false values, no loading or mutation)')
