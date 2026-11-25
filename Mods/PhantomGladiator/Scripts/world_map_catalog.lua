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
    local maps,chapters,managers,retries,attempted={},{},{},{},{}
    local worldKey,lookups=nil,0
    local clock=options.clock or os.clock
    local instance={}
    local function log(s) if options.log then pcall(options.log,'[WorldMapCatalog] '..s) end end
    local function refreshWorld()
        local ok,current=pcall(options.getWorld or function() end)
        local key=ok and address(current)
        if not key then return false end
        if key~=worldKey then
            worldKey,lookups=key,0
            maps,chapters,managers,retries,attempted={},{},{},{},{}
        end
        return true
    end
    local function cooling(at,now)
        return at~=nil and now>=at and now-at<1
    end
    local function subsystem(class)
        local now=clock()
        local remembered=managers[class]
        if remembered then
            local ok,outer=call(remembered.actor,'GetOuter')
            if ok and address(outer)==worldKey then return remembered.actor end
            if cooling(remembered.missing,now) then return nil end
        end
        local ok,list=pcall(options.findAll or FindAllOf,class)
        if not ok or type(list)~='table' or #list>64 then list={} end
        local found,seen,count=nil,{},0
        for _,o in ipairs(list) do
            local outerOk,outer=call(o,'GetOuter')
            local key=address(o)
            if outerOk and key and not seen[key] and address(outer)==worldKey then
                seen[key]=true;found=o;count=count+1
            end
        end
        if count==1 then
            managers[class]={actor=found}
            return found
        end
        managers[class]={missing=now}
        log('UNKNOWN: 当前World '..class..' 不唯一或不可读，稍后复核')
    end
    local function localized(value)
        local cached=text(field(value,'ValueCache'))
        if cached and cached~='' then return cached,true end
        if value==nil then return '',true end
        local pipeline=subsystem('EventPipelineManager')
        local ok,result=call(pipeline,'Conv_LocTextToString',value)
        local label=ok and text(result)
        return label or '',type(label)=='string'
    end
    function instance:localize(value)
        if not refreshWorld() then return '' end
        local label=localized(value)
        return label
    end
    function instance:resolve(mapID)
        local mapKey=id(mapID)
        if not mapKey then return {} end
        if not refreshWorld() then return {} end
        if maps[mapKey] then return maps[mapKey] end
        local now=clock()
        local pending=retries[mapKey]
        if pending and cooling(pending.at,now) then return pending.result end
        if not attempted[mapKey] and lookups>=128 then return {} end
        local bell=subsystem('BellManager')
        if not bell then return pending and pending.result or {} end
        if not attempted[mapKey] then attempted[mapKey]=true;lookups=lookups+1 end
        local result={}
        retries[mapKey]={at=now,result=result}
        log('读取图鉴归属地图 '..mapKey..'：GetMapData/GetChapterData；不调用存档、传送或生成')
        local mapOk,map=call(bell,'GetMapData',mapID)
        if not mapOk or id(field(map,'MapID'))~=mapKey then
            log('UNKNOWN: GetMapData返回结构/MapID不匹配 '..mapKey);return result
        end
        result.map_order=order(field(map,'MapOrder'))
        result.level_name=id(field(map,'LevelName')) or ''
        local nameOK,name=call(bell,'GetMapNameTextFromMapID',mapID)
        result.map_name=nameOK and text(name) or nil
        local nameReady=type(result.map_name)=='string' and result.map_name~=''
        if not nameReady then result.map_name,nameReady=localized(field(map,'MapName')) end
        local chapterReady=true
        local chapterID=field(map,'OwnChapterID')
        local chapterKey=id(chapterID)
        result.chapter_id=chapterKey or ''
        if chapterKey then
            local decoded=chapters[chapterKey]
            if not decoded then
                local chapterOK,chapter=call(bell,'GetChapterData',chapterID)
                decoded={}
                if chapterOK and id(field(chapter,'ChapterID'))==chapterKey then
                    decoded.name,chapterReady=localized(field(chapter,'ChapterName'))
                    decoded.order=order(field(chapter,'ChapterOrder'))
                    if chapterReady then chapters[chapterKey]=decoded end
                else
                    chapterReady=false
                    log('UNKNOWN: GetChapterData返回结构/ChapterID不匹配 '..chapterKey)
                end
            end
            result.chapter_name=decoded.name or ''
            result.chapter_order=decoded.order
        end
        if nameReady and chapterReady then maps[mapKey]=result;retries[mapKey]=nil end
        log('读回 map='..mapKey..' name='..tostring(result.map_name)..' chapter='..result.chapter_id
            ..' chapter_name='..tostring(result.chapter_name or '')..' level='..result.level_name)
        return result
    end
    return instance
end
return Maps
