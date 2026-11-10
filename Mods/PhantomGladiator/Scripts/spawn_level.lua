-- Spawn level: a map NPC comes out of its area's AI spawner, which sets the character's own `Level`
-- property (BP_RenewalNPC.hpp, a double next to MobGroup and Spawner) before the character starts.
-- A summoned unit skips the spawner and keeps Level 0; the player found summoned bosses taking damage
-- like mobs while the map's own NPCs were normal. v0.36.5 raised the Level *attribute* after
-- activation and nothing changed (docs/REVERSE_ENGINEERING.md), so now the property is written
-- before FinishSpawn, the way the spawner would. The nearby rule follows the highest Level among the
-- map's own NPCs unless a cycle is selected. After activation the unit and its reference are logged side by side
-- (property, GetCombatLevel, the Level attribute, health and defence attributes) to show what the
-- level changes. v0.36.7 confirmed it: a summoned 阿花 written to 18 came out with 104652 HP instead
-- of 9000, and the player found it normal. Where no map NPC is loaded (an empty field, right after a load) the
-- level comes from the game's own spawners where the player is (home_levels.lua nearest(), v0.37.6); the last
-- level found is remembered with its world and only reused in that world (v0.37.6 test: 22 from 正道大营 was
-- carried into 悲泣溪谷, a 1–4 map).
local U=require('ue_observe')
local Stats=require('character_stats')
local Mounts=require('mounts')
local Level={}
local RADIUS=20000       -- cm around the player whose map NPCs count; all loaded ones when none are that close
local CACHE=5            -- seconds the scan is reused, so a batch of summons scans the map once
local EPS=0.01
local HEADER='SpawnLevelV1\t'
local NEAR_METRES=RADIUS/100
-- Read side by side after activation.
local COMPARE={'Level','Health_Max','Attack','Shachi_Max','ShachiAttack','Resistance_Physical',
    'TakenReductionMultiplier_Physical','TakenVulnerabilityMultiplier_Physical','TakenAdditiveMultiplier_Physical',
    'Resistance_Poise','Resistance_DefenceShachi','TakenReductionMultiplier_DefenceShachi'}

local function num(v)return type(v)=='number' and v==v and v or nil end
local function short(actor)
    local ok,cls=pcall(function()return actor:GetClass():GetFName():ToString()end)
    return ok and type(cls)=='string' and cls:gsub('_C$','') or '?'
end
local function fmt(v)return v and string.format('%.2f',v) or 'nil' end
-- The game's own enemies come out of an AI spawner, which leaves itself and the unit's group on the character
-- (BP_RenewalNPC Spawner and MobGroup; "Init Level" reads both). Summons have neither, also those left from before a
-- Restart All Mods, when the mod no longer knows they are its own (v0.37.6 test: three earlier 三面 at 15, 22 and
-- 60 were taken for map enemies and HERE gave 60).
-- A summoned rider sits on a spawner of the mod's (mounts.lua, tagged SpawnerID): that does not make it a map enemy.
local function fromSpawner(pawn)
    local spawner=U.field(pawn,'Spawner')
    return (U.valid(spawner) and not Mounts.isOurs(spawner)) or U.valid((U.field(pawn,'MobGroup')))
end
-- Where a HOME or CUSTOM level came from (home_levels.lua), for the log.
local CHOICES={custom='自定义等级',picked='玩家选的老家等级',native='老家等级',area='老家地图的区域等级',
    extra='老家地图另一片区域的等级',prologue='序章等级'}

function Level.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local stats=options.attributes or Stats.new()
    local fs=options.io or io
    local self={raised=0,kept=0,failures=0,message=''}
    local cached
    -- The last map level found: {level=, name=}, read from and written to Runtime/spawn-level.tsv.
    -- The last map level found: {level=, name=, world=}, read from and written to Runtime/spawn-level.tsv (a file
    -- from before v0.37.6 has no world and is never reused).
    local saved=options.path and options.path..'/spawn-level.tsv'
    local last
    local function worldName()return options.getWorldName and options.getWorldName() or nil end
    if saved then
        local file=fs.open(saved,'r')
        if file then
            local text=file:read('*a');file:close()
            text=type(text)=='string' and text or ''
            local level,name,world=text:match('^SpawnLevelV1\t([%d%.]+)\t([^\t\n]*)\t([^\t\n]*)\n$')
            if not level then level,name=text:match('^SpawnLevelV1\t([%d%.]+)\t([^\t\n]*)\n$') end
            level=tonumber(level)
            if level and level>0 then last={level=level,name=name,world=world~='' and world or nil} end
        end
    end
    local function remember(entry)
        local world=worldName()
        if last and math.abs(last.level-entry.level)<=EPS and last.name==entry.name and last.world==world then return end
        last={level=entry.level,name=entry.name,world=world}
        local file=saved and fs.open(saved,'w')
        if not file then return end
        file:write(HEADER..string.format('%.2f',entry.level)..'\t'..entry.name..'\t'..(world or '')..'\n');file:close()
    end
    -- What the last summon got, for the app ("上次召唤").
    local summoned
    local references={}    -- summoned unit key -> the map NPC its level came from, for the after-activation log
    local function say(m)log('[SpawnLevel] '..m)end
    local function property(actor)return num(U.field(actor,'Level'))end
    local function combatLevel(actor)
        if not U.valid(actor) then return nil end
        local ok,value=pcall(function()return actor:GetCombatLevel()end)
        return ok and num(U.unwrap(value)) or nil
    end
    -- The map's own NPCs with a Level property, preferring those near the player; the highest one wins.
    local function mapLevel()
        if cached and clock()-cached.at<CACHE then return cached end
        local ours=options.ours and options.ours() or {}
        local player=options.getPlayer and options.getPlayer()
        local origin=U.valid(player) and options.getLocation and options.getLocation(player) or nil
        local near,all={}, {}
        local loose=0
        for _,pawn in ipairs(options.collect and options.collect() or {})do
            local key=U.key(pawn)
            local level=key and not ours[key] and property(pawn)
            if level and not fromSpawner(pawn) then level=nil;loose=loose+1 end
            if level then
                local entry={actor=pawn,name=short(pawn),level=level}
                all[#all+1]=entry
                local at=origin and options.getLocation(pawn)
                if at then
                    local dx,dy,dz=at.X-origin.X,at.Y-origin.Y,at.Z-origin.Z
                    if dx*dx+dy*dy+dz*dz<=RADIUS*RADIUS then near[#near+1]=entry end
                end
            end
        end
        local pool=#near>0 and near or all
        local best
        for _,entry in ipairs(pool)do if not best or entry.level>best.level then best=entry end end
        if best then remember(best) end
        local sample={}
        for i=1,math.min(10,#pool)do sample[#sample+1]=pool[i].name..'='..string.format('%.0f',pool[i].level) end
        cached={at=clock(),best=best,count=#pool,scope=#near>0 and '玩家附近' or '已加载地图',sample=table.concat(sample,','),origin=origin,
            loose=loose}
        return cached
    end
    -- Before FinishSpawn.
    function self:prepare(actor,unitPath,leader)
        local own=property(actor)
        if own==nil then
            self.kept=self.kept+1;self.message='该单位没有等级字段'
            say('跳过 unit='..tostring(unitPath)..'：没有 Level 字段')
            return {applied=false}
        end
        -- An escort (escorts.lua) takes the level of the unit it comes with, as every unit of a map group gets its
        -- domain's level. The leader's level already holds the mode, difficulty and cycle; the status keeps the leader's.
        if leader~=nil then
            local level=U.valid(leader) and property(leader) or nil
            if level then
                local ok,err=true,nil
                if math.abs(level-own)>EPS then ok,err=pcall(function()actor.Level=level end) end
                local after=property(actor)
                local good=ok and after and math.abs(after-level)<=EPS
                if not good then self.failures=self.failures+1 end
                say(string.format('随行 unit=%s 跟随 %s 的等级 %s→%s 调用=%s 读回=%s %s',tostring(unitPath),short(leader),fmt(own),fmt(level),
                    tostring(ok),fmt(after),err and ('错误='..tostring(err)) or ''))
                return {applied=good}
            end
            say('随行 unit='..tostring(unitPath)..'：带队单位的等级读不到，按召唤等级设置处理')
        end
        local area=mapLevel()
        local key=U.key(actor)
        if key and area.best then references[key]=area.best.actor end
        say(string.format('出生前 unit=%s 自身等级=%s %s地图怪=%d只 最高=%s(%s) 样本=[%s] 不是刷怪点刷出的=%d只',tostring(unitPath),fmt(own),
            area.scope,area.count,area.best and fmt(area.best.level) or 'nil',area.best and area.best.name or '-',area.sample,area.loose))
        -- HOME and CUSTOM (home_levels.lua) give the level outright, lower than the map's too; HERE goes on below.
        local levels=options.homeLevels
        local chosen=levels and levels:target(short(actor),actor)
        if chosen then
            local why=CHOICES[chosen.source] or chosen.source
            if chosen.source=='area' or chosen.source=='native' then
                why=why..'（'..tostring(chosen.map)..(chosen.part and chosen.part~='' and ' '..chosen.part or '')
                    ..(chosen.count and ' 刷怪点'..chosen.count..'个' or '')..' 难度='..tostring(chosen.difficulty)..' 周目='..tostring(chosen.cycle)
                    ..(chosen.exempt and ' 免周目加成' or '')..'）'
            end
            if math.abs(chosen.level-own)<=EPS then
                self.kept=self.kept+1;self.message='已是'..why;summoned={level=own,unit=short(actor)}
                say('不调整：已是'..why..' '..fmt(chosen.level))
                return {applied=false}
            end
            local ok,err=pcall(function()actor.Level=chosen.level end)
            local after=property(actor)
            local good=ok and after and math.abs(after-chosen.level)<=EPS
            if good then self.raised=self.raised+1;self.message='已按'..why..'生成';summoned={level=after,unit=short(actor)}
            else self.failures=self.failures+1;self.message='等级写入未读回' end
            say(string.format('按%s写入等级 %s→%s 调用=%s 读回=%s %s',why,fmt(own),fmt(chosen.level),tostring(ok),fmt(after),err and ('错误='..tostring(err)) or ''))
            return {applied=good}
        end
        local cycle=levels and levels.cycle or 0
        local target=area.best and area.best.level
        if target and cycle>0 then
            local why
            target,why=levels:mapTarget(target,area.best.actor,actor)
            say('指定周目='..cycle..' 参照等级='..fmt(area.best.level)..' 换算='..fmt(target)..(why and '；'..why or ''))
        end
        local world=worldName()
        if not target and levels and levels.nearest then
            local place=levels:nearest(world,area.origin,NEAR_METRES,actor)
            if place then
                target=place.level
                say(string.format('附近没有地图怪，按%s的游戏刷怪点 %s 级（%.0f 米外，%s）',place.near and '玩家附近' or '离玩家最近',
                    fmt(place.level),place.distance,tostring(world)))
            end
        end
        if not target and cycle>0 then
            target=levels:withoutPlace(actor)
            say('没有可换算的地点等级，按基础 1 级计算指定周目='..cycle..' 目标='..fmt(target))
        elseif not target and last and last.world and last.world==world then
            target=last.level
            say(string.format('附近没有地图怪，沿用这张图上次记录的等级 %s（来自 %s）',fmt(last.level),tostring(last.name)))
        end
        if not target then self.kept=self.kept+1;self.message='附近没有地图怪可参照';return {applied=false} end
        if math.abs(target-own)<=EPS or (cycle==0 and target<own) then
            self.kept=self.kept+1
            self.message=cycle>0 and '已是指定周目算出的等级' or '召唤单位等级不低于地图怪，未调整'
            summoned={level=own,unit=short(actor)}
            say('不调整：自身等级已不低于地图怪')
            return {applied=false}
        end
        local ok,err=pcall(function()actor.Level=target end)
        local after=property(actor)
        local good=ok and after and math.abs(after-target)<=EPS
        if good then self.raised=self.raised+1;self.message='已按地图怪等级生成';summoned={level=after,unit=short(actor)}
        else self.failures=self.failures+1;self.message='等级写入未读回' end
        say(string.format('写入等级 %s→%s 调用=%s 读回=%s %s',fmt(own),fmt(target),tostring(ok),fmt(after),err and ('错误='..tostring(err)) or ''))
        return {applied=good}
    end
    local function describe(actor)
        local parts={'等级字段='..fmt(property(actor)),'战斗等级='..fmt(combatLevel(actor))}
        for _,field in ipairs(COMPARE)do
            local entry=stats:read(actor,field)
            parts[#parts+1]=field..'='..(entry and fmt(entry.current) or 'nil')
        end
        return table.concat(parts,' ')
    end
    -- After activation: the unit next to the map NPC it took its level from (or the best one found now).
    function self:verify(actor)
        if not U.valid(actor) then return end
        local key=U.key(actor)
        local reference=key and references[key]
        if key then references[key]=nil end
        say('出生后 召唤 '..short(actor)..' '..describe(actor))
        reference=U.valid(reference) and reference or (mapLevel().best or {}).actor
        if U.valid(reference) then say('出生后 对照地图怪 '..short(reference)..' '..describe(reference)) end
        return U.valid(reference) and reference or nil
    end
    -- So the app can show the level a summon would get before anything is summoned (panel_runtime.lua: every 10 s
    -- after a world is ready until map enemies have loaded, then every 60 s). Logged the first time and whenever
    -- the level changes. Returns whether any map enemy was found.
    local shown
    function self:refresh()
        local area=mapLevel()
        local level=last and last.level
        if shown==nil or level~=shown then
            shown=level or false
            say(string.format('读召唤等级 %s地图怪=%d只 最高=%s(%s)；记录的等级=%s',area.scope,area.count,
                area.best and fmt(area.best.level) or 'nil',area.best and area.best.name or '-',last and fmt(last.level) or 'nil'))
        end
        return area.count>0
    end
    function self:status()
        return {raised=self.raised,kept=self.kept,failures=self.failures,message=self.message,
            last_level=summoned and summoned.level or nil,last_unit=summoned and summoned.unit or nil}
    end
    return self
end
return Level
