-- The game's area levels, read-only, for the stats guide (docs/STATS_GUIDE.md). Map enemies take the level of the
-- mob domain they spawn in (PBZ_MobDomain: Level Area Name, Level Offset, Offset By Difficulty, Level Area Table);
-- the area table DT_AIAreaLevel has rows {Parent, LevelOffset}, an area's level being its parent's plus its own
-- offset (docs/REVERSE_ENGINEERING.md v0.36.5). Read once per world: every table row, its level worked out along
-- the parents and asked of the game's own AIAreaLevelTableHelper.GetAILevel, and every mob domain loaded now.
-- Written to Runtime/area-levels.tsv. Nothing is loaded, created or changed.
local U=require('ue_observe')
local Areas={}
local TABLE='/PBZCombatAsset/Config/AIData/DT_AIAreaLevel.DT_AIAreaLevel'
local HELPER='/Script/PBZCombatAsset.Default__AIAreaLevelTableHelper'
local MAX_ROWS,MAX_DOMAINS,MAX_DEPTH=4096,512,32
local FIELDS={'kind','name','parent','offset','level','game_level','map','difficulty_offsets'}

local function text(v)
    v=U.unwrap(v)
    if type(v)=='string' then return v end
    if v==nil then return nil end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string' and s or nil
end
local function num(v)v=U.unwrap(v);return type(v)=='number' and v==v and v or nil end
-- A row from GetRowMap is a struct value, not an object, so its fields are read directly.
local function get(row,key)local ok,v=pcall(function()return row[key]end);return ok and U.unwrap(v) or nil end
local function clean(v)return v==nil and '' or (tostring(v):gsub('[\t\r\n]',' '))end
local function fmt(v)return v and string.format('%.2f',v) or '' end
local function call(object,name,...)
    if not U.valid(object) then return false,nil end
    local args=table.pack(...)
    local ok,result=pcall(function()return object[name](object,table.unpack(args,1,args.n))end)
    if not ok then return false,result end
    return true,U.unwrap(result)
end
-- The first number a call gives back, as a return value or in an out-parameter table.
local function numberFrom(object,name,...)
    local ok,value=call(object,name,...)
    if ok and num(value) then return num(value) end
    local out={}
    local args=table.pack(...);args[args.n+1]=out;args.n=args.n+1
    ok=call(object,name,table.unpack(args,1,args.n))
    if ok then for _,v in pairs(out)do if num(v) then return num(v) end end end
    return nil
end
-- "/Game/Maps/B04_05/PBZ_Zhengdaodaying_WP.PBZ_Zhengdaodaying_WP:PersistentLevel.X" -> "PBZ_Zhengdaodaying_WP"
local function mapOf(object)
    local ok,full=call(object,'GetFullName')
    return ok and type(full)=='string' and full:match('/Game/Maps/[^%.]*/([^/%.:]+)%.') or ''
end

function Areas.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local self={rows=0,domains=0,mismatches=0,written=false}
    local function say(m)log('[AreaLevels] '..m)end

    function self:export()
        say('操作=只读 '..TABLE..' 的全部行和当前已加载的 PBZ_MobDomain；不加载资源、不写游戏对象')
        local okList,list=pcall(FindAllOf,'PBZ_MobDomain_C')
        local domains={}
        if okList and type(list)=='table' then
            for i,domain in ipairs(list)do
                if i>MAX_DOMAINS then break end
                if U.valid(domain) then domains[#domains+1]=domain end
            end
        end
        local tableObject=StaticFindObject(TABLE)
        local source='按路径找到'
        if not U.valid(tableObject) then
            tableObject,source=nil,'没有加载'
            for _,domain in ipairs(domains)do
                local own=U.field(domain,'Level Area Table')
                if U.valid(own) then tableObject,source=own,'取自已加载的刷怪区域';break end
            end
        end
        local rows,names={},{}
        if U.valid(tableObject) then
            local okMap,map=call(tableObject,'GetRowMap')
            if okMap and type(map)=='table' then
                for key,row in pairs(map)do
                    if #names>=MAX_ROWS then break end
                    local name=text(key) or tostring(key)
                    local parent=text(get(row,'Parent'))
                    rows[name]={parent=(parent and parent~='None' and parent~='') and parent or nil,offset=num(get(row,'LevelOffset'))}
                    names[#names+1]=name
                end
            else say('读不到表的行 GetRowMap='..tostring(okMap)) end
        end
        table.sort(names)
        -- An area's level along its parents; a loop or a missing parent leaves it unknown.
        local memo,visiting={},{}
        local function level(name,depth)
            if memo[name]~=nil then return memo[name] or nil end
            local row=rows[name]
            if not row or not row.offset or visiting[name] or depth>MAX_DEPTH then return nil end
            visiting[name]=true
            local value=row.offset
            if row.parent then
                local up=level(row.parent,depth+1)
                value=up and value+up or nil
            end
            visiting[name]=nil
            memo[name]=value or false
            return value
        end
        local helper=StaticFindObject(HELPER)
        local lines={table.concat(FIELDS,'\t')..'\n'}
        local mismatches,known,low,high=0,0,nil,nil
        for _,name in ipairs(names)do
            local row,value=rows[name],level(name,0)
            local game=U.valid(helper) and numberFrom(helper,'GetAILevel',tableObject,FName(name)) or nil
            if value then
                known=known+1;low=math.min(low or value,value);high=math.max(high or value,value)
                if game and math.abs(game-value)>0.01 then mismatches=mismatches+1 end
            end
            lines[#lines+1]=table.concat({'area',clean(name),clean(row.parent),fmt(row.offset),fmt(value),fmt(game),'',''},'\t')..'\n'
        end
        for _,domain in ipairs(domains)do
            local area=text(U.field(domain,'Level Area Name'))
            local offset=num((U.field(domain,'Level Offset')))
            local byDifficulty={}
            local map=U.field(domain,'Offset By Difficulty')
            pcall(function()map:ForEach(function(k,v)byDifficulty[#byDifficulty+1]=tostring(U.unwrap(k))..'='..fmt(num(v))end)end)
            table.sort(byDifficulty)
            local value=numberFrom(domain,'Get AI Level')
            lines[#lines+1]=table.concat({'domain',clean(area),'',fmt(offset),fmt(value),'',clean(mapOf(domain)),table.concat(byDifficulty,',')},'\t')..'\n'
        end
        local file=options.path and fs.open(options.path..'/area-levels.tsv','w')
        local wrote=file and file:write(table.concat(lines))
        local closed=file and file:close()
        self.rows,self.domains,self.mismatches,self.written=#names,#domains,mismatches,(wrote~=nil and closed==true)
        say(string.format('读回 表=%s 行=%d 算出等级=%d 范围=%s～%s 与游戏GetAILevel不一致=%d 游戏函数=%s 已加载刷怪区域=%d 写入=%s',
            source,#names,known,fmt(low),fmt(high),mismatches,U.valid(helper) and '可用' or '不可用',#domains,tostring(self.written)))
        local sample={}
        for i=1,math.min(12,#names)do sample[#sample+1]=names[i]..'='..fmt(level(names[i],0))end
        if #sample>0 then say('样本 '..table.concat(sample,' '))end
        return {ok=self.written,rows=#names,domains=#domains,mismatches=mismatches}
    end
    return self
end
return Areas
