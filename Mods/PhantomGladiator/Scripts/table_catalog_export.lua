-- Only already-loaded tables with exact, header-verified native row schemas.
-- GetRowMap is UE4SS dff435dd's readonly reference API; no LoadAsset/AddRow/Save.
local Tables={}
local function valid(o)if o==nil then return false end local ok,v=pcall(function()return o:IsValid()end);return ok and v==true end
local function call(o,k,...)
    if not valid(o)then return false,nil end
    local args=table.pack(...);return pcall(function()return o[k](o,table.unpack(args,1,args.n))end)
end
local function field(v,k)local ok,r=pcall(function()return v[k]end);if ok then return r end end
local function text(v)if type(v)=='string'then return v end local ok,r=pcall(function()return v:ToString()end);if ok and type(r)=='string'then return r end end
local function name(o)local ok,v=call(o,'GetFullName');return ok and v or '' end
local function clean(v)if v==nil then return ''end;return(tostring(v):gsub('[\t\r\n]',' '))end
local function path(v)
    if v==nil then return ''end
    local ok,id=pcall(function()return v:GetObjectID()end);if ok and id~=nil then v=id end
    local got,a,s=pcall(function()return v:GetAssetPathName(),v:GetSubPathString()end)
    local p,sub=got and text(a),got and text(s)
    if not got then
        local asset=field(v,'AssetPath')
        local package,assetName=text(field(asset,'PackageName')),text(field(asset,'AssetName'))
        if package and assetName then p=package..'.'..assetName;sub=text(field(v,'SubPathString')) end
    end
    if not p or p=='' or p=='None' or sub==nil then return ''end
    return p..(sub~='' and ':'..sub or '')
end
local SCHEMAS={
    ['ScriptStruct /Script/ProjectPBZ.MapData']='map',
    ['ScriptStruct /Script/ProjectPBZ.ChapterData']='chapter',
    ['ScriptStruct /Script/PBZCombatAsset.PBZCharacterAttributeTableData']='attributes',
    ['ScriptStruct /Script/ProjectPBZ.SeqHeadSwapRow']='sequence',
    ['ScriptStruct /Script/ProjectPBZ.CodexDataStruct']='npc_codex',
}
function Tables.new(options)
    local instance={}
    local function log(s)if options.log then pcall(options.log,'[TableCatalog] '..s)end end
    function instance:export()
        local thread,yes=pcall(IsInGameThread);if not thread or yes~=true then return {ok=false}end
        local ok,list=pcall(FindAllOf,'DataTable');if not ok or type(list)~='table'then return {ok=false}end
        local rows,stats={}, {tables=0,rows=0,errors=0,truncated=false}
        for i,dt in ipairs(list)do
            if i>4096 then stats.truncated=true;break end
            if valid(dt)then
                local got,structure=call(dt,'GetRowStruct')
                local schema=got and SCHEMAS[name(structure)]
                if schema then
                    local gotRows,map=call(dt,'GetRowMap')
                    if gotRows and type(map)=='table'then
                        stats.tables=stats.tables+1;local n=0
                        log('读取已加载表 '..name(dt)..' schema='..schema..'；只读精确字段')
                        for key,row in pairs(map)do
                            n=n+1;if n>4096 then stats.truncated=true;break end
                            if not valid(dt) or not valid(structure)then stats.errors=stats.errors+1;break end
                            local r={schema=schema,table_path=name(dt),row_name=key}
                            if schema=='map'then
                                local mid=field(row,'MapID');r.map_id=text(mid)
                                local mapped=options.maps:resolve(mid)
                                for _,k in ipairs({'map_name','chapter_id','chapter_name','chapter_order','map_order','level_name'})do r[k]=mapped[k]end
                            elseif schema=='chapter'then
                                r.chapter_id=text(field(row,'ChapterID'));r.chapter_name=options.maps:localize(field(row,'ChapterName'));r.chapter_order=field(row,'ChapterOrder')
                            elseif schema=='attributes'then
                                r.asset_path=path(field(row,'AssetPath'));r.max_health_base=field(row,'MaxHealth_Base')
                            elseif schema=='sequence'then
                                r.character_id=text(field(row,'CharacterId'));r.asset_path=path(field(row,'GameplayCharacterClass'))
                                r.related_class=path(field(row,'HighQHeadSourceClass'));r.enabled=field(row,'bEnabled')
                            elseif schema=='npc_codex'then
                                r.character_id=text(field(row,'CodexID'));r.display_name=text(field(row,'NPCName'));r.is_monster=field(row,'BIsMonster')
                            end
                            rows[#rows+1]=r;stats.rows=stats.rows+1
                        end
                    else stats.errors=stats.errors+1;log('UNKNOWN: GetRowMap '..name(dt))end
                end
            end
        end
        local fields={'schema','table_path','row_name','asset_path','related_class','character_id','display_name','is_monster','enabled',
            'max_health_base','map_id','map_name','chapter_id','chapter_name','chapter_order','map_order','level_name'}
        local lines={table.concat(fields,'\t')..'\n'}
        for _,r in ipairs(rows)do local cells={};for _,k in ipairs(fields)do cells[#cells+1]=clean(r[k])end;lines[#lines+1]=table.concat(cells,'\t')..'\n'end
        local f=io.open(options.path..'/native-table-catalog.tsv','w');if not f then return {ok=false}end
        local wrote=f:write(table.concat(lines));local flushed=f:flush();local closed=f:close()
        stats.ok=wrote~=nil and flushed==true and closed==true
        log('读回 tables='..stats.tables..' rows='..stats.rows..' errors='..stats.errors..' truncated='..tostring(stats.truncated)..' written='..tostring(stats.ok)
            ..'；属性表不证明小兵/精英，也不保证生成兼容')
        return stats
    end
    return instance
end
return Tables
