local Tables=dofile('Mods/PhantomGladiator/Scripts/table_catalog_export.lua')
local realOpen=io.open;local output=''
io.open=function()return {write=function(self,s)output=output..s;return self end,flush=function()return true end,close=function()return true end}end
local function object(name,extra)
    local o=extra or {};o.IsValid=function()return true end;o.GetFullName=function()return name end;return o
end
local function path(s)return {GetAssetPathName=function()return s end,GetSubPathString=function()return ''end}end
local function dt(schema,data)
    local structure=object('ScriptStruct /Script/'..schema)
    return object('DataTable /Game/Test.Test',{GetRowStruct=function()return structure end,GetRowMap=function()return data end})
end
local list={
 dt('ProjectPBZ.MapData',{row={MapID='Map_A'}}),
 dt('ProjectPBZ.ChapterData',{row={ChapterID='Chapter_A',ChapterName='Actual chapter',ChapterOrder=2}}),
 dt('PBZCombatAsset.PBZCharacterAttributeTableData',{row={AssetPath={AssetPath={PackageName='/Game/Config',AssetName='Config'},SubPathString=''},MaxHealth_Base=400}}),
 dt('ProjectPBZ.SeqHeadSwapRow',{row={CharacterId='Actor_A',GameplayCharacterClass=path('/Game/A.A_C'),HighQHeadSourceClass=path('/Game/Seq.Seq_C'),bEnabled=false}}),
 dt('ProjectPBZ.CodexDataStruct',{row={CodexID='Npc_A',NPCName='Official name',BIsMonster=false}}),
 dt('Unknown.Schema',{}),
}
list[6].GetRowMap=function()error('unknown schema must not be touched')end
IsInGameThread=function()return true end;FindAllOf=function(k)assert(k=='DataTable');return list end
LoadAsset=function()error('must not load')end
local result=Tables.new({path='D:/test-tables',maps={resolve=function(_,id)assert(id=='Map_A');return {map_name='Actual map',chapter_id='Chapter_A'}end,
    localize=function(_,v)return v end}}):export()
assert(result.ok and result.tables==5 and result.rows==5 and result.errors==0)
assert(output:find('/Game/Config.Config',1,true) and output:find('/Game/Seq.Seq_C',1,true) and output:find('Official name',1,true))
assert(output:find('\tfalse\t',1,true),'false metadata must remain explicit')
for line in output:gmatch('([^\n]+)\n')do local _,tabs=line:gsub('\t','');assert(tabs==16)end
io.open=realOpen
print('table_catalog_export: PASS (exact schemas only, native references/labels, explicit false values, no loading or mutation)')
