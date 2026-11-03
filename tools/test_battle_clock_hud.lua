package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Clock=require('battle_clock_hud')
local address=0
local function object(fields,name)
    address=address+1;local a=address
    fields.IsValid=fields.IsValid or function()return true end
    fields.GetAddress=function()return a end
    fields.GetFName=function()return {ToString=function()return name or 'obj' end}end
    return fields
end
local function harness()
    local h={files={},lines={},created={},viewport={},clock='',seconds=0,ready=true}
    h.io={open=function(path,mode)
        if mode=='w' and h.failSave then return nil end
        if mode=='r' and h.files[path]==nil then return nil end
        local text=h.files[path] or ''
        return {read=function()return text end,write=function(_,s)text=s;return true end,
            close=function()if mode=='w' then h.files[path]=text end;return true end}
    end}
    h.pc=object({},'PC');h.world=object({},'World');h.player=object({},'Player')
    local function textBlock(name)
        local block=object({text=''},name)
        block.SetText=function(self,value)self.text=value.value end
        block.GetText=function(self)return {ToString=function()return self.text end}end
        block.SetJustification=function()end;block.SetShadowOffset=function()end;block.SetShadowColorAndOpacity=function()end
        block.Font={Size=12};block.SetFont=function(self,font)self.fontSize=font.Size end
        return block
    end
    local function widgetClass()
        return object({IsAnyClass=function()return true end},'WB_BossHPBar_C')
    end
    h.class=widgetClass()
    local function newWidget()
        local tree=object({},'WidgetTree')
        local widget=object({WidgetTree=tree,visibility=0,inViewport=false},'WB_BossHPBar_C')
        widget.GetOwningPlayer=function()return h.pc end
        widget.SetVisibility=function(self,v)self.visibility=v end
        widget.GetVisibility=function(self)return self.visibility end
        widget.AddToViewport=function(self)self.inViewport=true;h.viewport[#h.viewport+1]=self end
        widget.RemoveFromParent=function(self)self.inViewport=false end
        widget.IsInViewport=function(self)return self.inViewport end
        widget.SetAlignmentInViewport=function(self,v)self.alignment=v end
        widget.SetDesiredSizeInViewport=function(self,v)self.size=v end
        widget.SetPositionInViewport=function(self,v)self.position=v end
        h.created[#h.created+1]=widget
        return widget
    end
    local paths={
        ['/Game/PBZContent/UI/Hud/WB_BossHPBar.WB_BossHPBar_C']=h.class,
        ['/Script/UMG.Default__WidgetBlueprintLibrary']=object({Create=function(_,world,cls,pc)
            assert(world==h.world and cls==h.class and pc==h.pc)
            if h.failCreate then return nil end
            return newWidget()
        end}),
        ['/Script/UMG.Overlay']=object({},'OverlayClass'),
        ['/Script/UMG.TextBlock']=object({},'TextBlockClass'),
        ['/Script/Engine.Default__KismetTextLibrary']=object({Conv_StringToText=function(_,s)return {value=s} end}),
        ['/Script/UMG.Default__WidgetLayoutLibrary']=object({GetViewportSize=function()return {X=1920,Y=1080} end,
            GetViewportScale=function()return 1 end}),
    }
    StaticFindObject=function(path)return paths[path] end
    LoadAsset=function()end
    FName=function(s)return s end
    StaticConstructObject=function(cls,outer,name)
        if cls==paths['/Script/UMG.Overlay'] then
            local overlay=object({children={}},name)
            overlay.GetOuter=function()return outer end
            overlay.AddChildToOverlay=function(self,child)
                self.children[#self.children+1]=child
                return object({SetHorizontalAlignment=function(_,v)child.halign=v end,SetVerticalAlignment=function(_,v)child.valign=v end},'OverlaySlot')
            end
            return overlay
        end
        local block=textBlock(name);block.GetOuter=function()return outer end;return block
    end
    FindAllOf=function(name)assert(name=='WB_BossHPBar_C');return h.leftovers end
    function h.new()
        return Clock.new({path='R',io=h.io,log=function(s)h.lines[#h.lines+1]=s end,
            getController=function()return h.pc end,getWorld=function()return h.world end,getPlayer=function()return h.player end,
            ready=function()return h.ready end,clock=function()return h.clock,h.seconds end})
    end
    function h.all()return table.concat(h.lines,'\n')end
    return h
end

assert(Clock.format(0)=='0:00' and Clock.format(42.9)=='0:42' and Clock.format(62.01)=='1:02' and Clock.format(3725)=='1:02:05')

-- Settings: off by default, saved with readback, a failed save keeps the old value.
do
    local h=harness()
    local c=h.new()
    assert(not c:status().on and c:status().state=='off')
    assert(c:set('ON').ok and c:status().on and h.files['R/clock-hud.tsv']=='ClockHudV1\tshow=1\n')
    assert(not c:set('YES').ok)
    h.failSave=true;assert(not c:set('OFF').ok and c:status().on,'a failed save keeps the switch on');h.failSave=false
    assert(h.new():status().on,'a new Lua instance reads the saved switch')
end

-- Off, or on without a timed fight: nothing on screen. A running fight: the time at the top centre,
-- updated as it runs; the final time stays when it ends; the widget goes once the clock clears.
do
    local h=harness()
    local c=h.new()
    h.clock,h.seconds='running',5;c:tick()
    assert(#h.created==0,'switched off: nothing created')
    c:set('ON');h.clock='';c:tick()
    assert(#h.created==0 and c:status().state=='waiting')
    h.clock,h.seconds='running',42.4;c:tick()
    local w=h.created[1]
    assert(w and w.inViewport and w.visibility==3,h.all())
    local root=w.WidgetTree.RootWidget
    local text=root.children[1]
    assert(root:GetFName():ToString()=='PG_ClockRoot' and #root.children==1,'the tree holds only the clock text')
    assert(text.text=='0:42' and text.halign==2 and text.valign==1 and text.fontSize==30)
    assert(w.alignment.X==0.5 and w.position.X==960 and w.position.Y==14,'top centre of a 1920 wide screen')
    assert(w.Character==h.player)
    assert(c:status().state=='shown' and h.all():find('显示读回 文本=0:42 在屏幕上=true',1,true),h.all())
    h.seconds=61;c:tick()
    assert(text.text=='1:01' and #h.created==1,'the same widget is updated')
    h.clock,h.seconds='ended',75.2;c:tick()
    assert(text.text=='1:15' and w.inViewport,'the final time stays')
    h.clock,h.seconds='',0;c:tick()
    assert(not w.inViewport and c:status().state=='waiting','gone once the field is cleared')
    h.clock,h.seconds='running',3;c:tick()
    assert(#h.created==2 and h.created[2].inViewport,'a new fight gets a new widget')
    c:set('OFF');c:tick()
    assert(not h.created[2].inViewport and c:status().state=='off')
end

-- A world change (map, load) gets a new widget; a failed creation is tried again with the next fight.
do
    local h=harness()
    local c=h.new();c:set('ON')
    h.clock,h.seconds='running',1;c:tick()
    h.world=object({},'World2');c:tick()
    assert(#h.created==2 and h.all():find('重新创建',1,true),h.all())
    h.failCreate=true;h.world=object({},'World3');c:tick()
    assert(c:status().state=='failed' and c:status().failures==1)
    c:tick();assert(c:status().failures==1,'not retried every tick')
    h.failCreate=false;h.clock='';c:tick();h.clock='running';c:tick()
    assert(c:status().state=='shown','tried again with the next fight')
end

-- After a reload the last instance's clock is taken off the screen once.
do
    local h=harness()
    local tree=object({},'WidgetTree')
    local old=object({WidgetTree=tree,inViewport=true},'WB_BossHPBar_C')
    old.RemoveFromParent=function(self)self.inViewport=false end
    tree.RootWidget=object({},'PG_ClockRoot')
    local boss=object({WidgetTree=object({RootWidget=object({},'PG_BossRoot_1')},'Tree'),inViewport=true},'WB_BossHPBar_C')
    boss.RemoveFromParent=function(self)self.inViewport=false end
    h.leftovers={old,boss}
    local c=h.new();c:tick()
    assert(not old.inViewport and boss.inViewport,'only our clock is removed, never a boss bar')
    assert(h.all():find('移除上次留下的计时 1 个',1,true))
end
print('battle_clock_hud: PASS (format, settings, show/update/keep/remove, world change, retry, reload leftovers)')
