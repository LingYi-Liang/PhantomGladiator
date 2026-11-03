-- Companions' health bars above their heads. Map NPCs carry the game's own bar (BP_RenewalNPC.hpbar, a
-- PBZLazyWidgetComponent that creates WB_EnemyHPBar on demand), and the game shows it for enemies only. For a
-- companion it is set up through the NPC's own EnsureInitHpBar and kept visible while the companion lives,
-- showing the companion's health. Only the companion's own component and widget are written.
-- The first pass on each companion logs the bar's state before and after; later passes log only when the game
-- had hidden the bar again, so the log shows whether the game keeps hiding a friendly unit's bar.
local U=require('ue_observe')
local Bars={}
local SHOWN={[0]=true,[3]=true,[4]=true} -- ESlateVisibility: Visible, HitTestInvisible, SelfHitTestInvisible
local VISIBLE,COLLAPSED=3,1 -- HitTestInvisible as the private boss bars use (arena_hud_widget.lua); Collapsed
local LINES,RESHOW_LINES=40,10

local function fname(object)
    local ok,name=pcall(function()return object:GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end
local function className(object)
    if not U.valid(object) then return 'invalid' end
    local ok,class=pcall(function()return object:GetClass()end)
    return ok and U.valid(class) and fname(class) or '?'
end
local function call(object,name,...)
    if not U.valid(object) then return false,nil end
    local args=table.pack(...)
    local ok,result=pcall(function()return object[name](object,table.unpack(args,1,args.n))end)
    if not ok then return false,result end
    return true,U.unwrap(result)
end

function Bars.new(options)
    local log=options.log or function()end
    local self={records={},count=0,shown=0,reshown=0,failures=0,lines=0,reshowLines=0}
    local function say(m)
        if self.lines>=LINES then return end
        self.lines=self.lines+1;log('[CompanionBar] '..m)
    end
    local function widgetOf(component)
        local ok,widget=call(component,'GetUserWidgetObject')
        return ok and U.valid(widget) and widget or nil
    end
    local function bound(widget,actor)return U.key((U.field(widget,'SelfActor')))==U.key(actor)end
    local function describe(component,widget,actor)
        local _,visible=call(component,'IsVisible')
        local text='组件可见='..tostring(visible)..' 组件隐藏='..tostring((U.field(component,'bHiddenInGame')))
        if not widget then return text..' 控件=未创建' end
        local _,visibility=call(widget,'GetVisibility')
        local out={}
        local okCan=pcall(function()widget:CanDisplayHpBar(out)end)
        return text..' 控件='..className(widget)..' 可见性='..tostring(visibility)
            ..' WantToShow='..tostring((U.field(widget,'WantToShow')))..' 绑定本单位='..tostring(bound(widget,actor))
            ..' 游戏判断可显示='..(okCan and tostring(U.unwrap(out.CanDisplay)) or '读不到')
            ..' 血条比例='..tostring((U.field(U.field(widget,'hpbar'),'CurPercent')))
    end

    local function show(record,actor,ratio)
        local component=U.field(actor,'hpbar')
        if not U.valid(component) then
            if not record.noComponent then record.noComponent=true;say('没有头顶血条组件 unit='..record.path..' 类='..className(actor))end
            return
        end
        local widget=widgetOf(component)
        local first=not record.seen
        if first then record.seen=true;say('开始显示 unit='..record.path..' 之前：'..describe(component,widget,actor))end
        if not widget then
            local okInit=call(actor,'EnsureInitHpBar')
            widget=widgetOf(component)
            if not widget then call(component,'EnsureWidgetCreated');widget=widgetOf(component)end
            say('创建血条 unit='..record.path..' EnsureInitHpBar调用='..tostring(okInit)..' 读回控件='..className(widget))
            if not widget then self.failures=self.failures+1;return end
        end
        if not bound(widget,actor) then
            local okInit=call(widget,'Init',actor)
            say('控件没绑定本单位，调用Init='..tostring(okInit)..' 读回绑定='..tostring(bound(widget,actor))..' unit='..record.path)
        end
        local _,componentVisible=call(component,'IsVisible')
        local _,visibility=call(widget,'GetVisibility')
        if componentVisible~=true or SHOWN[visibility]~=true then
            if not first then
                self.reshown=self.reshown+1
                if self.reshowLines<RESHOW_LINES then
                    self.reshowLines=self.reshowLines+1
                    say('血条被游戏收起，重新显示 第'..self.reshown..'次 unit='..record.path..' 当时：'..describe(component,widget,actor))
                end
            end
            if U.field(component,'bHiddenInGame')==true then call(component,'SetHiddenInGame',false,false)end
            if componentVisible~=true then call(component,'SetVisibility',true,false)end
            call(widget,'ForSeq_ShowEnemyHPBar',actor)
            local _,now=call(widget,'GetVisibility')
            if SHOWN[now]~=true then call(widget,'SetVisibility',VISIBLE)end
        end
        if ratio and (record.ratio==nil or math.abs(record.ratio-ratio)>0.001) then
            call(widget,'ForSeq_UpdateHealth',ratio);record.ratio=ratio
        end
        if first then say('显示后 unit='..record.path..'：'..describe(component,widget,actor))end
        record.widget,record.shown=widget,true
    end
    local function hide(record)
        if record.shown and U.valid(record.widget) then
            call(record.widget,'SetVisibility',COLLAPSED)
            say('随从倒下，收起血条 unit='..record.path)
        end
        record.shown=false
    end

    -- members: the arena's units this support tick; only companions themselves get a bar (not their summons).
    function self:sync(members)
        local seen,count,shown={},0,0
        for _,unit in ipairs(members or {})do
            local key=unit.team=='companion' and not unit.summoner and U.key(unit.actor)
            if key and not seen[key] then
                seen[key]=true;count=count+1
                local record=self.records[key]
                if not record then
                    record={path=tostring((unit.class_path or ''):match('([^/%.]+)_C$') or unit.class_path or key)}
                    self.records[key]=record
                end
                local okHP,hp=pcall(options.hp,unit.actor)
                local okMax,maximum=pcall(options.maxHP,unit.actor)
                hp,maximum=okHP and tonumber(hp) or nil,okMax and tonumber(maximum) or nil
                if hp and hp<=0 then hide(record)
                else
                    local ratio=hp and maximum and maximum>0 and math.max(0,math.min(1,hp/maximum)) or nil
                    local ok,err=pcall(show,record,unit.actor,ratio)
                    if not ok then self.failures=self.failures+1;say('显示出错 unit='..record.path..' error='..tostring(err))end
                    if record.shown then shown=shown+1 end
                end
            end
        end
        for key in pairs(self.records)do if not seen[key] then self.records[key]=nil end end
        self.count,self.shown=count,shown
    end
    function self:status()return {companions=self.count,shown=self.shown,reshown=self.reshown,failures=self.failures}end
    return self
end
return Bars
