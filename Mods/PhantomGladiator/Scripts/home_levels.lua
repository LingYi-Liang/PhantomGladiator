-- Summon level: where a summoned unit's level comes from (docs/STATS_GUIDE.md). Three modes, set from the app
-- (set_spawn_level) and saved in Runtime/spawn-level-settings.tsv:
--   HOME    (default) the unit's own level in the game: the place the player picked for this unit, else where its
--           spawners put it most often on its codex home map (native_levels.lua, read offline from every level;
--           a boss's fight arena carries its own level, 三面 is 15 in a 1–4 map);
--   HERE    the level of the map enemies near the player (spawn_level.lua's rule), or with none loaded, of the
--           game's own spawners where the player is (native_places.lua, nearest());
--   CUSTOM  one level for every summon.
-- A native level gets what the game adds on spawn (BP_RenewalNPC "Init Level"): the difficulty's global mob level
-- offset (-1 on the lowest), at least 1, then 25 per effective game cycle unless exempt. Units no spawner places (summoned by bosses,
-- spawned by sequences) fall back to the areas of their codex home map (area-levels.tsv).
-- Inputs are files the mod writes itself (area-levels.tsv, codex-locations.tsv) and the generated
-- native_levels.lua and native_places.lua. Writes home-levels.tsv for the app. Nothing in the game is written.
local Levels={}
local MODES={HOME=true,HERE=true,CUSTOM=true}
local MAX_LEVEL=60
local CYCLE_LEVELS=25
local MAX_CYCLE=6
local MAX_PICK=MAX_LEVEL+MAX_CYCLE*CYCLE_LEVELS
-- Global Mob Level Offset of each difficulty (GlobalConfig_Combat_*): only the lowest sets one.
local GLOBAL={handicapped=-1}
-- Codex home map -> its areas in DT_AIAreaLevel, for units without native levels; `extra` areas carry the map's
-- name but are not where its own units live (血色森林's XueSeSenLin is 24, its FujizhilinA–C are 4–6).
local MAP_AREAS={
    XiGu={'XiguA','XiguB','XiguC','XiguD'},
    FuJiZhiLin={'FujizhilinA','FujizhilinB','FujizhilinC',extra={'XueSeSenLin'}},
    LuJiaCun={'LujiacunA','LujiacunB','LujiacunC'},
    PangZhen={'PangzhenA','PangzhenB','PangzhenC'},
    HouJie={'HoujieA','HoujieB','HoujieC'},
    ZhengDaoDaYing={'ZhengdaodayingA','ZhengdaodayingB'},
    DengDingShanDao={'JialongshanA','JialongshanB'},
    MeiGuHu={'MeiGuHu','MeiguhuB','MeiguhuC'},
    MeiGu_YiJi={'Huanshushiyiji'},
    XiMeng={'XimengshanzhuangA','XimengshanzhuangB','XimengshanzhuangC'},
    DuanHunYa={'DuanhunshanA','DuanhunshanB','DuanhunshanC'},
    DuanHunShan={'DuanhunshanA','DuanhunshanB','DuanhunshanC'},
}
local PROLOGUE='ZhuLinGuWu'
local SETTINGS,OUT='spawn-level-settings.tsv','home-levels.tsv'

local function short(path)return (tostring(path or ''):match('([^/%.]+)_C$') or tostring(path or ''):match('([^/%.]+)$') or '')end
local function clean(v)return v==nil and '' or (tostring(v):gsub('[\t\r\n]',' '))end
local function int(v,max)v=tonumber(v);if v and v==v and v>=0 and v<=(max or MAX_LEVEL) then return math.floor(v+0.5) end end
local function cycleChoice(v)
    v=tonumber(v)
    if v and v>=0 and v<=MAX_CYCLE+1 and v%1==0 then return v end
end
local function savedCycle(header)
    if not header or header[1]~='SpawnLevelSettingsV1' then return nil end
    if header[4]==nil or header[4]=='' then return 0 end
    return cycleChoice(header[4])
end
local function cycleBonus(cycle,exempt)
    if exempt then return 0 end
    return CYCLE_LEVELS*math.max(0,math.min(MAX_CYCLE,math.floor(tonumber(cycle) or 0)))
end
local function part(area)return tostring(area or ''):match('%l([A-D])$') or '' end
local function rows(text)
    local out={}
    for line in (text or ''):gmatch('[^\r\n]+')do
        local cols={}
        for col in (line..'\t'):gmatch('([^\t]*)\t')do cols[#cols+1]=col end
        out[#out+1]=cols
    end
    return out
end
-- What the game adds to a native level on spawn, for the difficulty and game cycle in `context`.
local function spawned(level,context)
    context=context or {}
    local lv=level+(GLOBAL[string.lower(tostring(context.difficulty or ''))] or 0)
    if lv<1 then lv=1 end
    return lv+cycleBonus(context.cycle,context.exempt)
end

function Levels.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local dir=options.path
    local native=options.native
    if native==nil then
        local ok,data=pcall(require,'native_levels')
        native=ok and type(data)=='table' and data or {}
    end
    local places=options.places
    if places==nil then
        local ok,data=pcall(require,'native_places')
        places=ok and type(data)=='table' and data or {}
    end
    local self={mode='HOME',custom=nil,cycle=0,picks={},areas={},homes={},maps={},written=0}
    local function say(m)log('[HomeLevels] '..m)end
    local function context(actor)return options.context and options.context(actor) or {}end
    local function exemption(actor)
        if actor and options.cycleExempt then return options.cycleExempt(actor) end
    end
    local function summonContext(actor)
        local ctx=context(actor)
        local cycle=self.cycle>0 and self.cycle-1 or ctx.cycle
        return {difficulty=ctx.difficulty,cycle=cycle,exempt=cycle and cycle>0 and exemption(actor)}
    end
    local function read(name)
        local file=dir and fs.open(dir..'/'..name,'r');if not file then return nil end
        local text=file:read('*a');file:close();return text
    end
    local function write(name,text)
        local file=dir and fs.open(dir..'/'..name,'w');if not file then return false end
        local ok=file:write(text);local closed=file:close();return not not (ok and closed)
    end

    local function saveSettings()
        local lines={'SpawnLevelSettingsV1\t'..self.mode..'\t'..(self.custom and tostring(self.custom) or '')}
        if self.cycle>0 then lines[1]=lines[1]..'\t'..self.cycle end
        local units={}
        for unit in pairs(self.picks)do units[#units+1]=unit end
        table.sort(units)
        for _,unit in ipairs(units)do lines[#lines+1]='unit\t'..unit..'\t'..self.picks[unit] end
        return write(SETTINGS,table.concat(lines,'\n')..'\n')
    end
    local function loadSettings()
        local list=rows(read(SETTINGS))
        local head=list[1]
        if not head or head[1]~='SpawnLevelSettingsV1' then return end
        if MODES[head[2]] then self.mode=head[2] end
        self.custom=int(head[3])
        self.cycle=savedCycle(head) or 0
        for i=2,#list do
            local row=list[i]
            if row[1]=='unit' and row[2] and row[2]:match('^[%w_]+$') and int(row[3],MAX_PICK) then self.picks[row[2]]=int(row[3],MAX_PICK) end
        end
    end
    local function mapName(id)return self.maps[id] or id end

    -- Where the game itself puts this unit: one entry per level and place, with how many spawners put it there.
    local function nativeChoices(unit,ctx)
        local list,byKey={}, {}
        for _,row in ipairs(native[unit] or {})do
            local level,area,map,count=spawned(tonumber(row[1]) or 0,ctx),row[2] or '',row[3] or '',tonumber(row[4]) or 1
            local key=level..'\t'..map..'\t'..part(area)
            local entry=byKey[key]
            if entry then entry.count=entry.count+count
            else
                entry={level=level,source='native',map=mapName(map),map_id=map,part=part(area),area=area,count=count}
                byKey[key]=entry;list[#list+1]=entry
            end
        end
        if #list==0 then return nil end
        table.sort(list,function(a,b)
            if a.level~=b.level then return a.level<b.level end
            if a.map_id~=b.map_id then return a.map_id<b.map_id end
            return a.part<b.part
        end)
        -- The default is where it lives: most spawners on its codex home map (anywhere if none there), higher level on a tie.
        local home=self.homes[unit] and self.homes[unit].map
        local best
        for pass=1,2 do
            for _,entry in ipairs(list)do
                if (pass==2 or entry.map_id==home) and (not best or entry.count>best.count or (entry.count==best.count and entry.level>best.level)) then best=entry end
            end
            if best then break end
        end
        return list,best
    end

    -- The choices for one unit, in display order; `default` is the one HOME uses unless the player picked another.
    function self:choices(unit,ctx)
        ctx=ctx or summonContext(nil)
        local list,default=nativeChoices(unit,ctx)
        if list then return list,default end
        list={}
        local home=self.homes[unit]
        local areas=home and MAP_AREAS[home.map]
        local deepest
        if areas then
            for _,name in ipairs(areas)do
                local level=self.areas[name]
                if level then
                    local entry={level=spawned(level,ctx),source='area',map=home.name,part=part(name)}
                    list[#list+1]=entry
                    if not deepest or entry.level>deepest.level then deepest=entry end
                end
            end
            for _,name in ipairs(areas.extra or {})do
                if self.areas[name] then list[#list+1]={level=spawned(self.areas[name],ctx),source='extra',map=home.name,part=''} end
            end
        elseif home and home.map==PROLOGUE then
            deepest={level=spawned(1,ctx),source='prologue',map=home.name,part=''}
            list[#list+1]=deepest
        end
        return list,deepest
    end

    -- The level a summon of this unit gets, or nil to use the nearby rule (HERE, or HOME with nothing known).
    function self:target(unit,actor)
        if self.mode=='CUSTOM' and self.custom then return {level=self.custom,source='custom'} end
        if self.mode~='HOME' then return nil end
        if self.picks[unit] then return {level=self.picks[unit],source='picked'} end
        local ctx=summonContext(actor)
        local _,default=self:choices(unit,ctx)
        return default and {level=default.level,source=default.source,map=default.map,part=default.part,area=default.area,
            count=default.count,difficulty=ctx.difficulty,cycle=ctx.cycle,exempt=ctx.exempt} or nil
    end

    -- The level of where a point of this world is, from the game's own spawners (native_places.lua): the highest
    -- within `radius` metres, else the nearest one, with what the game adds on spawn for this unit. For the HERE rule
    -- when no map enemy is loaded around the player.
    function self:nearest(world,location,radius,actor)
        local list=world and places[world]
        if not list or not location then return nil end
        local x,y,z=location.X/100,location.Y/100,location.Z/100
        local r2=(radius or 200)^2
        local within,closest,closestD
        for _,p in ipairs(list)do
            local dx,dy,dz=p[1]-x,p[2]-y,p[3]-z
            local d=dx*dx+dy*dy+dz*dz
            if d<=r2 and (not within or p[4]>within[4]) then within=p end
            if not closestD or d<closestD then closest,closestD=p,d end
        end
        local p=within or closest
        if not p then return nil end
        local dx,dy,dz=p[1]-x,p[2]-y,p[3]-z
        return {level=spawned(p[4],summonContext(actor)),distance=math.sqrt(dx*dx+dy*dy+dz*dz),near=within~=nil}
    end

    -- A live map reference already includes the save's cycle. Rebase only when that contribution is known.
    function self:mapTarget(level,reference,actor)
        local current=context(nil).cycle
        if current==nil then return nil,'存档周目未读回' end
        local exempt
        if current>0 then
            exempt=exemption(reference)
            if exempt==nil then return nil,'参照怪的免周目标签未读回' end
        end
        local base=level-cycleBonus(current,exempt)
        if base<1 then return nil,'参照怪的基础等级无法换算' end
        return base+cycleBonus(self.cycle-1,exemption(actor))
    end

    function self:withoutPlace(actor)
        return spawned(1,summonContext(actor))
    end

    function self:export()
        local units={}
        for unit in pairs(self.homes)do units[#units+1]=unit end
        for unit in pairs(native)do if not self.homes[unit] then units[#units+1]=unit end end
        table.sort(units)
        local ctx=summonContext(nil)
        local lines={'unit\tlevel\tsource\tmap\tpart\tdefault\tpicked\tcount'}
        for _,unit in ipairs(units)do
            local list,default=self:choices(unit,ctx)
            local pick,listed=self.picks[unit],false
            for _,entry in ipairs(list)do
                local mine=pick==entry.level and not listed
                listed=listed or mine
                lines[#lines+1]=table.concat({unit,entry.level,entry.source,clean(entry.map),entry.part or '',
                    entry==default and 1 or 0,mine and 1 or 0,entry.count or 0},'\t')
            end
            -- A level picked that is none of the choices (the app offers any level) still shows as the one in use.
            if pick and not listed then lines[#lines+1]=table.concat({unit,pick,'picked','','',0,1,0},'\t') end
        end
        local ok=write(OUT,table.concat(lines,'\n')..'\n')
        self.written=self.written+1
        return ok
    end

    -- Reads the area levels and the codex homes again (after their exports) and rewrites home-levels.tsv.
    function self:refresh()
        self.areas={}
        for _,row in ipairs(rows(read('area-levels.tsv')))do
            if row[1]=='area' and row[2] and int(row[5]) then self.areas[row[2]]=int(row[5]) end
        end
        self.homes,self.maps={}, {}
        local codex=rows(read('codex-locations.tsv'))
        local head=codex[1] or {}
        local idMap,idName
        for i,name in ipairs(head)do if name=='own_map_id' then idMap=i elseif name=='map_name' then idName=i end end
        for i=2,#codex do
            local row=codex[i]
            local unit=short(row[1])
            if unit~='' and idMap and row[idMap] and row[idMap]~='' then
                local name=idName and row[idName] or ''
                self.homes[unit]={map=row[idMap],name=name~='' and name or row[idMap]}
                if name~='' then self.maps[row[idMap]]=name end
            end
        end
        local count=0;for _ in pairs(self.homes)do count=count+1 end
        local areas=0;for _ in pairs(self.areas)do areas=areas+1 end
        local units=0;for _ in pairs(native)do units=units+1 end
        local ok=self:export()
        local ctx=context(nil)
        say(string.format('读回 区域=%d 有图鉴归属的单位=%d 原生等级单位=%d 难度=%s 周目=%s 写入=%s 模式=%s 自定义=%s 自选=%d',
            areas,count,units,tostring(ctx.difficulty),tostring(ctx.cycle),tostring(ok),self.mode,tostring(self.custom),
            (function()local n=0;for _ in pairs(self.picks)do n=n+1 end;return n end)()))
        return ok
    end

    -- CYCLE selects 0 (follow the save) or 1–7. Fixed levels remain absolute.
    function self:configure(unit,token,level)
        if token=='CYCLE' then
            local cycle=cycleChoice(level)
            if not cycle then return {ok=false,message='召唤周目必须是跟随存档或一到七周目',spawned_count=0} end
            local previous=self.cycle
            self.cycle=cycle
            local saved=saveSettings()
            local actual=savedCycle(rows(read(SETTINGS))[1])
            local confirmed=saved and actual==cycle
            if not confirmed then self.cycle=previous end
            say('设置召唤周目='..cycle..' 写入='..tostring(saved)..' 读回='..tostring(actual))
            if confirmed then self:export() end
            return {ok=confirmed,message=confirmed and '召唤周目已设置' or '召唤周目保存未确认',spawned_count=0}
        elseif token=='UNIT' then
            if not (unit and unit:match('^[%w_]+$')) then return {ok=false,message='单位名不对',spawned_count=0} end
            if level=='' or level==nil then self.picks[unit]=nil
            elseif int(level,MAX_PICK) then self.picks[unit]=int(level,MAX_PICK)
            else return {ok=false,message='等级要在 0～'..MAX_PICK..' 之间',spawned_count=0} end
        elseif MODES[token] then
            if token=='CUSTOM' then
                if not int(level) then return {ok=false,message='等级要在 0～'..MAX_LEVEL..' 之间',spawned_count=0} end
                self.custom=int(level)
            end
            self.mode=token
        else return {ok=false,message='未知的召唤等级模式',spawned_count=0} end
        local saved=saveSettings()
        self:export()
        say(string.format('设置 模式=%s 自定义=%s 单位=%s 等级=%s 保存读回=%s',self.mode,tostring(self.custom),tostring(unit),tostring(level),tostring(saved)))
        return {ok=saved,message=saved and '召唤等级已设置' or '召唤等级没能保存',spawned_count=0}
    end

    function self:status()return {mode=self.mode,custom=self.custom,cycle=self.cycle}end

    loadSettings()
    return self
end
Levels.short=short
Levels.spawned=spawned
return Levels
