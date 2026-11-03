-- Read-only metadata: FCodexEnemyRow.OwnMapID -> FMapData -> FChapterData.
-- ProjectPBZ.hpp:325,1053,5517,5562-5570. These are World subsystem instances,
-- never CDOs. The result describes codex affiliation, not all spawn locations.
local Maps={}
local function valid(o)
    if o==nil then return false end
    local ok,v=pcall(function() return o:IsValid() end);return ok and v==true
end
local function call(o,key,...)
    if not valid(o) then return false,nil end
    local args=table.pack(...)
    return pcall(function() return o[key](o,table.unpack(args,1,args.n)) end)
end
local function field(s,key)
    if s==nil then return nil end
    local ok,v=pcall(function() return s[key] end);if ok then return v end
end
local function text(v)
    if type(v)=='string' then return v end
    local ok,s=pcall(function() return v:ToString() end)
    if ok and type(s)=='string' then return s end
end
local function id(v)
    local s=text(v)
    if s and s~='' and s~='None' and #s<=256 and not s:find('%c') then return s end
end
local function address(o)
    local ok,a=call(o,'GetAddress')
    if ok and (type(a)=='number' or type(a)=='string') then return tostring(a) end
end
local function order(v)
    if type(v)=='number' and v==v and v>=0 and v<1000000 and v%1==0 then return v end
end
function Maps.new(options)
    options=options or {}
    local maps,chapters,worldKey,world,lookups={}, {},nil,nil,0
    local instance={}
    local function log(s) if options.log then pcall(options.log,'[WorldMapCatalog] '..s) end end
    local function subsystem(class)
        local ok,list=pcall(options.findAll or FindAllOf,class)
        if not ok or type(list)~='table' or #list>64 then return nil end
        local found,seen,count=nil,{},0
        for _,o in ipairs(list) do
            local outerOk,outer=call(o,'GetOuter')
            local key=address(o)
            if outerOk and key and not seen[key] and address(outer)==worldKey then
                seen[key]=true;found=o;count=count+1
            end
        end
        if count==1 then return found end
    end
    local function localized(value)
        local cached=text(field(value,'ValueCache'))
        if cached and cached~='' then return cached end
        if value==nil then return '' end
        local pipeline=subsystem('EventPipelineManager')
        local ok,result=call(pipeline,'Conv_LocTextToString',value)
        return ok and text(result) or ''
    end
    function instance:localize(value)
        local ok,current=pcall(options.getWorld or function() end)
        local currentKey=ok and address(current)
        if not currentKey then return '' end
        if currentKey~=worldKey then maps,chapters,lookups={}, {},0;worldKey,world=currentKey,current end
        return localized(value) or ''
    end
    function instance:resolve(mapID)
        local mapKey=id(mapID)
        if not mapKey then return {} end
        local ok,current=pcall(options.getWorld or function() end)
        local currentKey=ok and address(current)
        if not currentKey then log('UNKNOWN: 当前World不可读');return {} end
        if currentKey~=worldKey then maps,chapters,lookups={}, {},0;worldKey,world=currentKey,current end
        if maps[mapKey] then return maps[mapKey] end
        if lookups>=128 then log('地图查询达到128条上限');return {} end
        lookups=lookups+1
        local result={}
        maps[mapKey]=result
        local bell=subsystem('BellManager')
        if not bell then log('UNKNOWN: 当前World BellManager不唯一或不存在，地图='..mapKey);return result end
        log('读取图鉴归属地图 '..mapKey..'：GetMapData/GetChapterData；不调用存档、传送或生成')
        local mapOk,map=call(bell,'GetMapData',mapID)
        if not mapOk or id(field(map,'MapID'))~=mapKey then
            log('UNKNOWN: GetMapData返回结构/MapID不匹配 '..mapKey);return result
        end
        result.map_order=order(field(map,'MapOrder'))
        result.level_name=id(field(map,'LevelName')) or ''
        local nameOK,name=call(bell,'GetMapNameTextFromMapID',mapID)
        result.map_name=nameOK and text(name) or nil
        if not result.map_name or result.map_name=='' then result.map_name=localized(field(map,'MapName')) or '' end
        local chapterID=field(map,'OwnChapterID')
        local chapterKey=id(chapterID)
        result.chapter_id=chapterKey or ''
        if chapterKey then
            if not chapters[chapterKey] then
                local chapterOK,chapter=call(bell,'GetChapterData',chapterID)
                local decoded={}
                if chapterOK and id(field(chapter,'ChapterID'))==chapterKey then
                    decoded.name=localized(field(chapter,'ChapterName')) or ''
                    decoded.order=order(field(chapter,'ChapterOrder'))
                else log('UNKNOWN: GetChapterData返回结构/ChapterID不匹配 '..chapterKey) end
                chapters[chapterKey]=decoded
            end
            result.chapter_name=chapters[chapterKey].name or ''
            result.chapter_order=chapters[chapterKey].order
        end
        log('读回 map='..mapKey..' name='..tostring(result.map_name)..' chapter='..result.chapter_id
            ..' chapter_name='..tostring(result.chapter_name or '')..' level='..result.level_name)
        return result
    end
    return instance
end
return Maps
