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
local FIELDS={'schema','table_path','row_name','asset_path','related_class','character_id','display_name','is_monster','enabled',
    'max_health_base','map_id','map_name','chapter_id','chapter_name','chapter_order','map_order','level_name'}
local function newBatch()
    return {tables={},nextTable=1,lines={table.concat(FIELDS,'\t')..'\n'},stats={tables=0,rows=0,errors=0,truncated=false}}
end

function Tables.new(options)
    local instance={}
    local active
    local function log(s)if options.log then pcall(options.log,'[TableCatalog] '..s)end end
    local function onThread()
        local thread,yes=pcall(IsInGameThread)
        return thread and yes==true
    end

    local function rowsFrom(batch,dt,item,structure)
        local stats=batch.stats
        local gotRows,map=call(dt,'GetRowMap')
        if not gotRows or type(map)~='table' then
            stats.errors=stats.errors+1;log('UNKNOWN: GetRowMap '..item.name)
            return
        end
        stats.tables=stats.tables+1
        log('读取已加载表 '..item.name..' schema='..item.schema..'；只读精确字段')
        local n=0
        for key,row in pairs(map)do
            n=n+1
            if n>4096 then stats.truncated=true;break end
            if not valid(dt) or not valid(structure) then stats.errors=stats.errors+1;break end
            local schema=item.schema
            local r={schema=schema,table_path=item.name,row_name=key}
            if schema=='map' then
                local mid=field(row,'MapID');r.map_id=text(mid)
                local mapped=options.maps:resolve(mid)
                for _,k in ipairs({'map_name','chapter_id','chapter_name','chapter_order','map_order','level_name'})do r[k]=mapped[k] end
            elseif schema=='chapter' then
                r.chapter_id=text(field(row,'ChapterID'));r.chapter_name=options.maps:localize(field(row,'ChapterName'));r.chapter_order=field(row,'ChapterOrder')
            elseif schema=='attributes' then
                r.asset_path=path(field(row,'AssetPath'));r.max_health_base=field(row,'MaxHealth_Base')
            elseif schema=='sequence' then
                r.character_id=text(field(row,'CharacterId'));r.asset_path=path(field(row,'GameplayCharacterClass'))
                r.related_class=path(field(row,'HighQHeadSourceClass'));r.enabled=field(row,'bEnabled')
            elseif schema=='npc_codex' then
                r.character_id=text(field(row,'CodexID'));r.display_name=text(field(row,'NPCName'));r.is_monster=field(row,'BIsMonster')
            end
            local cells={}
            for _,k in ipairs(FIELDS)do cells[#cells+1]=clean(r[k])end
            batch.lines[#batch.lines+1]=table.concat(cells,'\t')..'\n'
            stats.rows=stats.rows+1
        end
    end

    local function discover(batch,readImmediately)
        local ok,list=pcall(FindAllOf,'DataTable')
        if not ok or type(list)~='table' then return false end
        for i,dt in ipairs(list)do
            if i>4096 then batch.stats.truncated=true;break end
            local got,structure=call(dt,'GetRowStruct')
            local schema=got and SCHEMAS[name(structure)]
            if schema then
                local label=name(dt)
                local objectPath=label:match('^%S+ (/.+)$')
                if objectPath then
                    local item={name=label,path=objectPath,schema=schema}
                    if readImmediately then rowsFrom(batch,dt,item,structure)
                    else batch.tables[#batch.tables+1]=item end
                end
            end
        end
        return true
    end

    local function publish(batch)
        local stats=batch.stats
        local f=io.open(options.path..'/native-table-catalog.tsv','w')
        if not f then return {ok=false} end
        local wrote=f:write(table.concat(batch.lines));local flushed=f:flush();local closed=f:close()
        stats.ok=wrote~=nil and flushed==true and closed==true
        log('读回 tables='..stats.tables..' rows='..stats.rows..' errors='..stats.errors..' truncated='..tostring(stats.truncated)..' written='..tostring(stats.ok)
            ..'；属性表不证明小兵/精英，也不保证生成兼容')
        return stats
    end

    function instance:export()
        if not onThread() then return {ok=false} end
        local batch=newBatch()
        return discover(batch,true) and publish(batch) or {ok=false}
    end

    -- No DataTable, row pointers, or reflected structs survive the callback that reads them.
    function instance:step(session,generation)
        if not onThread() then return {ok=false} end
        if not active or active.session~=session or active.generation~=generation then
            local batch=newBatch()
            batch.session,batch.generation=session,generation
            active=nil
            if not discover(batch,false) then return {ok=false} end
            active=batch
            return {pending=true}
        end
        local batch=active
        local item=batch.tables[batch.nextTable]
        if not item then active=nil;return publish(batch) end
        batch.nextTable=batch.nextTable+1
        local found,dt=pcall(StaticFindObject,item.path)
        local got,structure=call(found and dt or nil,'GetRowStruct')
        if not got or name(dt)~=item.name or SCHEMAS[name(structure)]~=item.schema then
            -- A stale native table should not replace the last completed export.
            active=nil
            return {ok=false,message='原生数据表已卸载或更换'}
        end
        rowsFrom(batch,dt,item,structure)
        return {pending=true}
    end
    return instance
end
return Tables
