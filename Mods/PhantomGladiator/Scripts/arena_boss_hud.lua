-- Legacy extension-pool route, retained for the earlier regression evidence.
-- Production now uses arena_hud.lua and arena_hud_widget.lua.
-- Native boss widgets need an actor binding, not just an extension registration.
local U=require('ue_observe')
local HUD={}
local function number(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function text(v)
    if type(v)=='string' then return v end
    local ok,s=pcall(function() return v:ToString() end);return ok and s or nil
end
function HUD.new(options)
    options=options or {}
    local self={records={},ticks=0,readback={registered=0,visible=0,pending=0},bosses=nil,names={},pendingActor=nil}
    local log=options.log or function() end
    local function label(actor)
        if not U.valid(actor) then return 'INVALID' end
        local ok,s=pcall(function()return actor:GetFullName()end);return ok and tostring(s) or 'UNKNOWN'
    end
    local function loadCodex()
        if self.bosses then return end
        local f=options.codexPath and io.open(options.codexPath,'rb');if not f then return end
        local data=f:read(8388609);f:close()
        if not data or #data>8388608 or not data:match('^class_path\tzh_name\tis_boss\tenemy_type\tsource\r?\n') then return end
        self.bosses={}
        for line in data:gmatch('[^\r\n]+') do
            local path,name,boss=line:match('^([^\t]+)\t([^\t]*)\t([^\t]+)\t')
            if boss=='1' then self.bosses[path]=true;self.names[path]=name end
        end
    end
    local function wanted(unit)
        if unit.summoner or (unit.team~='blue' and unit.team~='red') or not U.valid(unit.actor) then return false end
        if options.isBoss then return options.isBoss(unit)==true end
        loadCodex();return self.bosses and self.bosses[unit.class_path]==true
    end
    local function findHUD()
        if options.getHUD then return options.getHUD() end
        local key=U.key(options.getController());if not key then return nil end
        local ok,objects=pcall(options.findAll or FindAllOf,'PBZHUDLayout');if not ok then return nil end
        local matches,active={},{}
        for _,hud in ipairs(U.array(objects or {}) or {}) do
            if U.valid(hud) then
                local passed,owner=pcall(function()return hud:GetOwningPlayer()end)
                if passed and U.key(owner)==key and U.valid(U.field(hud,'BossPoint')) then
                    matches[#matches+1]=hud
                    local read,on=pcall(function()return hud:IsActivated()end)
                    if read and on==true then active[#active+1]=hud end
                end
            end
        end
        if #active==1 then return active[1] end
        if #matches==1 then return matches[1] end
    end
    local function widgets(hud)
        if not U.valid(hud) then return nil end
        local ok,value=pcall(function()return hud:GetBossHPBarInstances()end)
        local list=ok and U.array(value) or nil
        local point=U.field(hud,'BossPoint')
        local read,entries=false,nil
        if U.valid(point) then read,entries=pcall(function()return point:GetAllEntries()end) end
        entries=read and U.array(entries) or nil
        if not list and not entries then return nil end
        local result,seen={},{}
        for _,source in ipairs({list or {},entries or {}}) do
            for _,widget in ipairs(source) do
                local key=U.key(widget)
                if key and not seen[key] then seen[key]=true;result[#result+1]=widget end
            end
        end
        return result
    end
    local function bindings(list)
        local actors,keys={},{}
        for _,widget in ipairs(list or {}) do
            local key=U.key(widget)
            if key then
                keys[key]=widget
                local actor=U.field(widget,'Character');local ak=U.key(actor)
                if ak then actors[ak]=widget end
            end
        end
        return actors,keys
    end
    local function bind(record,actor)
        local widget=record.widget
        if not U.valid(widget) or not U.valid(actor) then return false end
        local prior,read=U.field(widget,'Character')
        if not read then
            if not record.bindError then log('[BossHUD] 控件没有可读Character字段：'..label(widget));record.bindError=true end
            return false
        end
        if U.valid(prior) and U.key(prior)~=U.key(actor) then
            log('[BossHUD] 拒绝覆盖绑定到其它角色的控件');return false
        end
        if U.key(prior)~=U.key(actor) and not record.initAttempted then
            record.initAttempted=true
            local called,err=pcall(function()
                if not U.valid(widget) or not U.valid(actor) then error('绑定前对象失效') end
                widget.Character=actor
                widget:Init(actor)
            end)
            log('[BossHUD] 绑定角色并Init；actor='..label(actor)..' call='..tostring(called)..(called and '' or (' error='..tostring(err))))
        end
        local actual=U.field(widget,'Character')
        return U.key(actual)==U.key(actor)
    end
    local function makeText(s)
        if options.makeText then return options.makeText(s) end
        if not U.valid(self.textLibrary) then self.textLibrary=StaticFindObject('/Script/Engine.Default__KismetTextLibrary') end
        if not U.valid(self.textLibrary) then return nil end
        return self.textLibrary:Conv_StringToText(s)
    end
    local function update(record,unit,hp)
        local widget=record.widget
        if not bind(record,unit.actor) then return false,false end
        local maxOK,maximum=pcall(options.maxHP or function()return nil end,unit.actor)
        if maxOK and number(maximum) and maximum>0 then
            local ratio=math.max(0,math.min(1,hp/maximum))
            if record.lastHP~=hp or record.lastMax~=maximum then record.hpAttempts=0 end
            if record.lastHP~=hp or record.lastMax~=maximum or (not record.healthVerified and (record.hpAttempts or 0)<3) then
                record.hpAttempts=(record.hpAttempts or 0)+1
                local wrote=pcall(function()if U.valid(widget) then widget:ForSeq_UpdateHealth(ratio) end end)
                local bar=U.field(widget,'hpbar');local actual=U.valid(bar) and U.field(bar,'CurPercent') or nil
                local verified=wrote and number(actual) and math.abs(actual-ratio)<0.002
                record.healthVerified=verified
                local bucket=math.floor(ratio*10)
                if record.bucket~=bucket or not verified then log('[BossHUD] 真实血量显示读回 HP='..hp..'/'..maximum..' expected='..ratio..' actual='..tostring(actual)..' verified='..tostring(verified)) end
                record.lastHP,record.lastMax,record.bucket=hp,maximum,bucket
            end
        end
        local name=(options.getName and options.getName(unit)) or self.names[unit.class_path] or (unit.class_path or ''):match('%.([^%.]+)$') or 'BOSS'
        local title=(unit.team=='blue' and '蓝队 · ' or '红队 · ')..name
        local function readTitle()
            local block=U.field(widget,'BossName')
            if U.valid(block) then
                local read,value=pcall(function()return block:GetText()end)
                if read then return text(value) end
            end
        end
        local actual=readTitle()
        if record.expectedTitle~=title then record.expectedTitle=title;record.nameAttempts=0 end
        if actual==title then record.nameAttempts=0 end
        if actual~=title and (record.nameAttempts or 0)<3 then
            record.nameAttempts=(record.nameAttempts or 0)+1
            local before=actual
            local ok,err=pcall(function()
                local value=makeText(title)
                if value~=nil and U.valid(widget) then widget:ForSeq_SetNameText(value) end
                local box=U.field(widget,'BossNameHorBox');if U.valid(box) then box:SetVisibility(0) end
            end)
            actual=readTitle()
            log('[BossHUD] 名称绑定读回 actor='..label(unit.actor)..' expected='..title..' before='..tostring(before)..' actual='..tostring(actual)..' call='..tostring(ok)..(ok and '' or (' error='..tostring(err))))
            if actual==title then record.nameAttempts=0 end
        end
        record.title=actual
        local ok,visible=pcall(function()return widget:IsVisible()end)
        return true,ok and visible==true,record.healthVerified==true,record.title==title
    end
    function self:sync(members)
        self.ticks=self.ticks+1;loadCodex()
        local desired={}
        for _,unit in ipairs(members) do
            if wanted(unit) then
                local ok,hp=pcall(options.hp,unit.actor);local world=options.getWorld and options.getWorld()
                if ok and number(hp) and hp>0 and (not world or U.inWorld(unit.actor,world)) then desired[U.key(unit.actor)]={unit=unit,hp=hp} end
            end
        end
        local hud=next(desired) and findHUD() or nil
        local list=widgets(hud);local byActor,keys=bindings(list)
        local registered,visible,pending,healthVerified,namesVerified=0,0,0,0,0
        for key,data in pairs(desired) do
            local unit=data.unit;local record=self.records[key]
            if not record then record={actor=unit.actor,hud=hud,attempts=0,owned=not byActor[key],widget=byActor[key]};self.records[key]=record end
            if not U.valid(record.hud) and U.valid(hud) then record.hud=hud end
            if not U.valid(record.widget) and self.pendingActor==key and list then
                local fresh={}
                for wk,w in pairs(keys) do
                    local claimed=false
                    for otherKey,other in pairs(self.records) do if otherKey~=key and U.key(other.widget)==wk then claimed=true;break end end
                    if not record.beforeKeys[wk] and not claimed then fresh[#fresh+1]=w end
                end
                if #fresh==1 then record.widget=fresh[1];self.pendingActor=nil end
            end
            if U.valid(record.widget) then
                record.widgetKey=U.key(record.widget)
                local bound,on,hpOK,nameOK=update(record,unit,data.hp)
                if bound then registered=registered+1;if on then visible=visible+1 end else pending=pending+1 end
                if hpOK then healthVerified=healthVerified+1 end
                if nameOK then namesVerified=namesVerified+1 end
            elseif U.valid(hud) and not self.pendingActor and record.attempts==0 then
                record.beforeKeys=keys;record.attempts=1;self.pendingActor=key
                local ok,handle=pcall(function()return hud:RegisterBossHPBar(unit.actor)end)
                local kind=U.kind(handle);local got,widget=false,nil
                if ok and (kind=='UScriptStruct' or kind=='table') then got,widget=pcall(function()return hud:GetBossHPBarInstanceByHandle(handle)end) end
                if ok and not U.valid(widget) and U.valid(handle) then
                    local _,hasCharacter=U.field(handle,'Character')
                    if hasCharacter then got,widget=true,handle end
                end
                if got and U.valid(widget) then record.widget=widget;self.pendingActor=nil;bind(record,unit.actor) end
                log('[BossHUD] 注册返回读回 kind='..kind..' handle_widget='..tostring(got and U.valid(widget))..' actor='..label(unit.actor)..(ok and '' or (' error='..tostring(handle))))
                pending=pending+1
            else pending=pending+1 end
        end
        for key,record in pairs(self.records) do
            if not desired[key] then
                local gone=not record.owned or not U.valid(record.hud)
                if record.owned and U.valid(record.hud) then
                    local wk=U.key(record.widget) or record.widgetKey
                    local called=pcall(function()
                        if U.valid(record.actor) then record.hud:UnRegisterBossHPBar(record.actor) end
                        local point=U.field(record.hud,'BossPoint')
                        if U.valid(point) and U.valid(record.widget) then point:UnregsiterHandleByWidget(record.widget) end
                    end)
                    local after=widgets(record.hud);local _,remaining=bindings(after)
                    gone=after~=nil and wk~=nil and not remaining[wk]
                    if not record.widget and after and #after==0 then gone=true end
                    log('[BossHUD] 清理具体血条控件；call='..tostring(called)..' widget_absent='..tostring(gone))
                end
                if gone then self.records[key]=nil;if self.pendingActor==key then self.pendingActor=nil end
                else pending=pending+1 end
            end
        end
        self.readback={registered=registered,visible=visible,pending=pending,health_verified=healthVerified,names_verified=namesVerified}
    end
    function self:clear(removeUnbound)
        self:sync({})
        if not removeUnbound then return end
        -- v0.23 could create empty native widgets with no Character binding.
        -- Manual F4 may remove only those unbound entries in the current HUD;
        -- valid bars belonging to a real actor are never swept here.
        local hud=findHUD();local point=U.valid(hud) and U.field(hud,'BossPoint') or nil
        if not U.valid(point) then return end
        for _,widget in ipairs(widgets(hud) or {}) do
            local character,read=U.field(widget,'Character')
            if read and not U.valid(character) and U.valid(widget) then
                local key=U.key(widget)
                local called=pcall(function()point:UnregsiterHandleByWidget(widget)end)
                local after=widgets(hud);local _,keys=bindings(after)
                log('[BossHUD] 清理未绑定角色的旧空血条；call='..tostring(called)..' widget_absent='..tostring(after~=nil and not keys[key]))
            end
        end
    end
    function self:status()return self.readback end
    return self
end
return HUD
