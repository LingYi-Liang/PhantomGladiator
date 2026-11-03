-- Stable ownership/lifecycle for the Mod's live boss bars.
local U=require('ue_observe')
local Renderer=require('arena_hud_widget')
local HUD={}
local function number(value)return type(value)=='number' and value==value and math.abs(value)<1e12 end
-- Team labels in the game's language, as the app names the teams; Chinese keeps 蓝队/红队, others fall back to English.
local TEAMS={zh={blue='蓝队',red='红队'},en={blue='Blue',red='Red'},ja={blue='青チーム',red='赤チーム'},
    fr={blue='Bleus',red='Rouges'},de={blue='Blau',red='Rot'},es={blue='Azul',red='Rojo'}}
function HUD.new(options)
    local self={records={},attempts={},ticks=0,names={},bosses=nil,readback={},teams=TEAMS.zh}
    local log=options.log or function()end
    local renderer=options.renderer or Renderer.new(options)
    -- codex.tsv up to v0.37.4 ends at source; v0.37.5 adds name (in the game's language) and name_lang.
    local function loadCodex()
        if self.bosses or not options.codexPath then return end
        local file=io.open(options.codexPath,'rb');if not file then return end
        local data=file:read(8388609);file:close()
        if not data or #data>8388608 or not data:match('^class_path\tzh_name\tis_boss\tenemy_type\tsource[\t\r\n]')then return end
        self.bosses={}
        for line in data:gmatch('[^\r\n]+')do
            local cols={}
            for col in (line..'\t'):gmatch('([^\t]*)\t')do cols[#cols+1]=col end
            if cols[3]=='1' then
                self.bosses[cols[1]]=true;self.names[cols[1]]=(cols[6] or '')~='' and cols[6] or cols[2]
                local lang=(cols[7] or ''):match('^(%a%a)')
                if lang then self.teams=TEAMS[lang:lower()] or TEAMS.en end
            end
        end
    end
    local function wanted(unit)
        if unit.summoner or (unit.team~='blue' and unit.team~='red') or not U.valid(unit.actor)then return false end
        if options.isBoss then return options.isBoss(unit)==true end
        return self.bosses and self.bosses[unit.class_path]==true
    end
    function self:sync(members)
        self.ticks=self.ticks+1;loadCodex()
        local desired,ordered={},{}
        local world=options.getWorld and options.getWorld()
        for _,unit in ipairs(members)do if wanted(unit) and (not world or U.inWorld(unit.actor,world))then
            local ok,hp=pcall(options.hp,unit.actor);local maxOK,maximum=pcall(options.maxHP,unit.actor)
            if ok and maxOK and number(hp) and number(maximum) and hp>0 and maximum>0 then
                local key=U.key(unit.actor)
                if key and not desired[key]then
                    desired[key]={unit=unit,hp=hp,maximum=maximum};ordered[#ordered+1]=key
                end
            end
        end end
        local result={registered=0,visible=0,pending=0,health_verified=0,names_verified=0,numbers_verified=0}
        for key,record in pairs(self.records)do if not desired[key]then
            if renderer:remove(record)then self.records[key]=nil;self.attempts[key]=nil else result.pending=result.pending+1 end
        end end
        for key in pairs(self.attempts)do if not desired[key] and not self.records[key]then self.attempts[key]=nil end end
        local rows={blue=0,red=0};local privateKeys,displayed={},{}
        for _,key in ipairs(ordered)do
            local data=desired[key];local unit=data.unit;rows[unit.team]=rows[unit.team]+1
            local record=self.records[key]
            if not record and (self.attempts[key] or 0)<3 then
                self.attempts[key]=(self.attempts[key] or 0)+1
                local why;record,why=renderer:create(unit)
                if record then self.records[key]=record else log('[ArenaHUD] 创建未确认 actor='..key..' error='..tostring(why))end
            end
            if record then
                local name=(options.getName and options.getName(unit)) or self.names[unit.class_path] or (unit.class_path or ''):match('%.([^%.]+)$') or 'BOSS'
                local title=self.teams[unit.team]..' · '..name
                local state,why=renderer:update(record,unit,data.hp,data.maximum,title,rows[unit.team])
                if state then
                    result.registered=result.registered+1
                    if state.visible then result.visible=result.visible+1 end
                    if state.health then result.health_verified=result.health_verified+1 end
                    if state.names then result.names_verified=result.names_verified+1 end
                    if state.numbers then result.numbers_verified=result.numbers_verified+1 end
                    self.attempts[key]=0;displayed[key]=true
                else
                    log('[ArenaHUD] 独立控件失效，释放后重建 actor='..key..' error='..tostring(why))
                    if renderer:remove(record)then self.records[key]=nil end
                    result.pending=result.pending+1
                end
                local widgetKey=U.key(record.widget);if widgetKey then privateKeys[widgetKey]=true end
            else result.pending=result.pending+1 end
        end
        renderer:syncNative(displayed,privateKeys,false)
        self.readback=result
    end
    -- After codex.tsv is written again (first export over the shipped copy, or the game's language changed).
    function self:reloadCodex()self.bosses=nil;self.names={};self.teams=TEAMS.zh end
    function self:clear(removeUnbound)
        self:sync({});renderer:syncNative({},{},removeUnbound==true)
    end
    function self:status()return self.readback end
    return self
end
return HUD
