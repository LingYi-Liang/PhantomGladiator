package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Renderer=arg[1] and assert(loadfile(arg[1]))() or require('arena_hud_widget')
local serial=0;local registry={}
local function obj(path,properties)
    serial=serial+1;local id=serial;local o=properties or {};o.alive=true;o.visibility=0
    function o:IsValid()return self.alive end
    function o:GetAddress()assert(self.alive);return id end
    function o:GetFullName()assert(self.alive);return 'Class '..path end
    function o:SetVisibility(value)assert(self.alive);self.visibility=value end
    function o:GetVisibility()assert(self.alive);return self.visibility end
    registry[path]=o;return o
end
local world,pc,actor,other=obj('/Test.World'),obj('/Test.PC'),obj('/Test.Actor'),obj('/Test.Other')
function actor:GetOuter()return world end
local cls=obj('/Game/PBZContent/UI/Hud/WB_BossHPBar.WB_BossHPBar_C')
function cls:IsAnyClass()return true end
local overlayClass,textClass=obj('/Script/UMG.Overlay'),obj('/Script/UMG.TextBlock')
local library=obj('/Script/UMG.Default__WidgetBlueprintLibrary')
local texts=obj('/Script/Engine.Default__KismetTextLibrary')
function texts:Conv_StringToText(value)return value end
local layout=obj('/Script/UMG.Default__WidgetLayoutLibrary')
local viewportWidth,viewportHeight,viewportScale,sizeReads,scaleReads=3840,2160,2,0,0
function layout:GetViewportSize(context)sizeReads=sizeReads+1;assert(context==world and context.alive);return {X=viewportWidth,Y=viewportHeight}end
function layout:GetViewportScale(context)scaleReads=scaleReads+1;assert(context==world and context.alive);return viewportScale end
local widget,tree,original
function library:Create(context,class,player)
    assert(context==world and class==cls and player==pc)
    tree=obj('/Test.Tree');original=obj('/Test.Original');tree.RootWidget=original
    widget=obj('/Test.Private',{WidgetTree=tree,BossName=obj('/Test.Name'),BossNameHorBox=obj('/Test.NameBox'),hpbar=obj('/Test.HP',{CurPercent=0})})
    function widget:GetOwningPlayer()return pc end
    function widget:Init(value)assert(self.inViewport and self.Character==value);self.initialized=true end
    function widget:AddToViewport(z)assert(z==-1);self.inViewport=true end
    function widget:RemoveFromParent()self.inViewport=false end
    function widget:IsInViewport()return self.inViewport==true end
    function widget:IsVisible()return self.inViewport and self.visibility==3 end
    function widget:SetAlignmentInViewport(value)self.alignment=value end
    function widget:SetDesiredSizeInViewport(value)self.size=value end
    function widget:SetPositionInViewport(value,removeDPI)assert(removeDPI==false);self.position=value end
    function widget:ForSeq_SetNameText(value)self.BossName.value=value end
    function widget.BossName:GetText()return self.value end
    function widget:ForSeq_UpdateHealth(value)self.hpbar.CurPercent=value end
    return widget
end
StaticFindObject=function(path)return registry[path]end
FName=function(value)return value end
StaticConstructObject=function(class,outer,name)
    assert(outer==tree)
    local o=obj('/Test.Tree.'..name)
    function o:GetOuter()return outer end
    if class==overlayClass then
        o.children={};o.slots={};o.RenderTransform={Scale={X=1,Y=1}}
        function o:SetRenderTransformPivot(value)self.RenderTransformPivot=value end
        function o:SetRenderScale(value)
            self.RenderTransform.Scale=value
            self.scaleWrites=(self.scaleWrites or 0)+1
        end
        function o:AddChildToOverlay(child)
            self.children[#self.children+1]=child
            local slot=obj('/Test.Slot'..#self.children)
            function slot:SetPadding(value)self.padding=value end
            function slot:SetHorizontalAlignment(value)self.horizontal=value end
            function slot:SetVerticalAlignment(value)self.vertical=value end
            self.slots[#self.slots+1]=slot;return slot
        end
    else
        assert(class==textClass);o.Font={Size=24}
        function o:SetJustification(value)self.justification=value end
        function o:SetShadowOffset()end
        function o:SetShadowColorAndOpacity()end
        function o:SetFont(value)self.Font=value end
        function o:SetText(value)self.value=value end
        function o:GetText()return self.value end
    end
    return o
end
local native=obj('/Test.Native',{Character=actor});local foreign=obj('/Test.NativeForeign',{Character=other})
local hud=obj('/Test.HUD',{BossPoint=obj('/Test.BossPoint')})
function hud:GetBossHPBarInstances()return {native,foreign,widget}end
function hud.BossPoint:GetAllEntries()return {}end
local renderer=Renderer.new({getController=function()return pc end,getWorld=function()return world end,getHUD=function()return hud end})
local unit={actor=actor,team='blue'}
local record,why=renderer:create(unit);assert(record,why)
assert(widget.initialized and widget.inViewport and tree.RootWidget==record.overlay)
assert(record.overlay.children[1]==original and record.overlay.slots[1].padding.Top==28,'numeric line must reserve space above the original bar')
local state=renderer:update(record,unit,73.2,100,'蓝队 · 测试',1)
assert(state.visible and state.health and state.names and state.numbers and record.numeric.value=='73.2 / 100')
assert(widget.position.X==24 and widget.position.Y==18 and record.numeric.Font.Size==20)
widget.visibility=1;widget.hpbar.visibility=1;widget.BossName.value='native overwrite';record.numeric.value='stale'
state=renderer:update(record,unit,72.5,100,'蓝队 · 测试',1)
assert(state.visible and state.health and state.names and state.numbers and widget.hpbar.visibility==3)
renderer:syncNative({[tostring(actor:GetAddress())]=true},{[tostring(widget:GetAddress())]=true},false)
assert(native.visibility==1 and foreign.visibility==0 and widget.visibility==3,'only matching native duplicates may be hidden')
renderer:syncNative({},{},false);assert(native.visibility==0 and foreign.visibility==0)
widget.Character=other;assert(renderer:update(record,unit,72.5,100,'蓝队 · 测试',1)==false)
assert(widget.Character==other and renderer:remove(record) and not widget.inViewport)
-- Whole-bar compaction preserves the original HP/name proportions and packs the viewport rows.
do
    local normal=assert(renderer:create(unit))
    local red={actor=actor,team='red'}
    local crowded=assert(renderer:create(red))
    assert(renderer:update(normal,unit,50,100,'normal',3,{},nil,3))
    assert(renderer:update(crowded,red,73.2,100,'crowded',4,{},nil,4))
    local function factor(r)return r.overlay.RenderTransform.Scale.X end
    local screenWidth=viewportWidth/2
    local dense=factor(crowded)
    assert(factor(normal)==1 and normal.widget.position.Y==282)
    assert(dense<1 and dense>0.5 and crowded.overlay.RenderTransform.Scale.Y==dense)
    assert(crowded.widget.position.Y<414 and crowded.widget.position.Y>18)
    assert(math.abs(crowded.widget.position.X+crowded.widget.size.X*dense-(screenWidth-24))<.001)
    assert(crowded.overlay.RenderTransformPivot.X==0 and crowded.overlay.RenderTransformPivot.Y==0)
    local writes=crowded.overlay.scaleWrites
    assert(renderer:update(crowded,red,72.5,100,'crowded',4,{},nil,4))
    assert(crowded.overlay.scaleWrites==writes,'an unchanged scale must not be reapplied')
    assert(renderer:update(crowded,red,72.5,100,'crowded',4,{},nil,8))
    local roomy=factor(crowded)
    assert(roomy<dense and roomy>0.5)
    viewportHeight=900
    assert(renderer:update(crowded,red,72.5,100,'crowded',4,{},nil,8))
    assert(factor(crowded)>=.5 and factor(crowded)<roomy)
    viewportHeight=2160
    assert(renderer:update(crowded,red,72.5,100,'crowded',3,{},nil,3))
    assert(factor(crowded)==1 and crowded.widget.position.Y==282 and crowded.widget.position.X==1196)

    crowded.widget.opacity=0
    local hidden=assert(renderer:update(crowded,red,60,100,'crowded',3,{},nil,3,true))
    assert(not hidden.visible and hidden.health and hidden.numbers and crowded.widget.IsInViewport(crowded.widget))
    assert(crowded.widget.visibility==2 and crowded.overlay.visibility==2
        and crowded.widget.opacity==0 and crowded.numeric.value=='60 / 100')
    local shown=assert(renderer:update(crowded,red,59,100,'crowded',3,{},nil,3,false))
    assert(shown.visible and shown.health and crowded.widget.visibility==3
        and crowded.overlay.visibility==3 and crowded.widget.opacity==0)
    assert(renderer:remove(normal) and renderer:remove(crowded))
end
-- Viewport changes inside the settings menu may detach existing widgets or report no valid size.
do
    local HUD=require('arena_hud')
    local newcomer=obj('/Test.Newcomer')
    function newcomer:GetOuter()return world end
    local list={{actor=actor,team='blue'}}
    local bars=HUD.new({renderer=renderer,isBoss=function()return true end,hp=function()return 50 end,
        maxHP=function()return 100 end,getWorld=function()return world end})
    local actorKey=tostring(actor:GetAddress())
    local newcomerKey=tostring(newcomer:GetAddress())
    bars:sync(list)
    local old=bars.records[actorKey]
    assert(old and bars:status().visible==1 and old.widget:IsInViewport())
    old.widget:RemoveFromParent()
    bars:sync(list)
    assert(not bars.records[actorKey] and native.visibility==0,
        'a detached bar must release the record and stop masking the native bar')
    bars:sync(list)
    local recovered=bars.records[actorKey]
    assert(recovered and recovered~=old and bars:status().visible==1 and native.visibility==1)
    local position=recovered.widget.position

    viewportScale=0;viewportWidth=0
    list[2]={actor=newcomer,team='red'}
    local beforeSize=sizeReads
    bars:sync(list)
    assert(sizeReads==beforeSize+1,'unavailable geometry is still sampled only once per sync')
    local pending=bars.records[newcomerKey]
    assert(pending and bars.records[actorKey]==recovered and recovered.widget.position==position,
        'a geometry outage must preserve existing widgets and their last known position')
    assert(bars:status().visible==1 and pending.widget.visibility==2 and pending.widget.position==nil,
        'a new bar must wait to show until its placement is known')
    for _=1,6 do bars:sync(list) end
    viewportScale=2;viewportWidth=3840
    bars:sync(list)
    assert(bars.records[actorKey]==recovered and bars.records[newcomerKey]==pending
        and bars:status().visible==2 and pending.widget.position.X==1196,
        'the same bars should resume after geometry returns without exhausting creation attempts')
    bars:clear()
end
-- Empty arenas must not search the global widget registry merely to discover no boss HUD yet exists.
do
    local scans=0;local previous=FindAllOf
    FindAllOf=function(class)assert(class=='PBZHUDLayout');scans=scans+1;return {}end
    local idle=Renderer.new({getController=function()return pc end,getWorld=function()return world end})
    for _=1,10 do idle:syncNative({},{},false) end
    assert(scans==0,'idle native HUD scanned the object registry '..scans..' times')
    idle:syncNative({},{},true)
    assert(scans==1,'explicit unbound cleanup still searches the HUD')
    FindAllOf=previous
end
-- Each sync owns its viewport snapshot; it never holds a native object across updates.
do
    local records={};local count=100
    for i=1,count do records[i]=assert(renderer:create(unit))end
    sizeReads,scaleReads=0,0
    local frame={}
    for i,r in ipairs(records)do assert(renderer:update(r,unit,50,100,'batch',i,frame))end
    print('viewport batch='..count..' size_reads='..sizeReads..' scale_reads='..scaleReads)
    assert(sizeReads==1 and scaleReads==1,'a HUD sync must read a common viewport once')
    viewportWidth=2000
    local resized={}
    assert(renderer:update(records[1],{actor=actor,team='red'},50,100,'resized',1,resized))
    assert(sizeReads==2 and scaleReads==2 and records[1].widget.position.X==512,'the next sync reads the changed width')
    world.alive=false
    local before=sizeReads
    assert(not renderer:update(records[1],unit,50,100,'invalid world',1,{}))
    assert(sizeReads==before,'invalid world cannot reach a native viewport call')
    world.alive=true
end
do
    local HUD=require('arena_hud')
    local list={}
    for i=1,50 do
        local a=obj('/Test.FrameActor'..i);function a:GetOuter()return world end
        list[#list+1]={actor=a,team=i%2==0 and 'red' or 'blue'}
    end
    local hudBars=HUD.new({renderer=renderer,isBoss=function()return true end,hp=function()return 50 end,
        maxHP=function()return 100 end,getWorld=function()return world end,getName=function()return 'batch' end})
    sizeReads,scaleReads=0,0
    hudBars:sync(list)
    assert(hudBars:status().visible==50 and sizeReads==1 and scaleReads==1,'real HUD sync shares the local viewport snapshot')
    viewportWidth=2400;hudBars:sync(list)
    assert(sizeReads==2 and scaleReads==2,'a later HUD sync must not reuse the previous viewport')
    local resizedRed=hudBars.records[tostring(list[2].actor:GetAddress())]
    local width=resizedRed.widget.size.X*resizedRed.overlay.RenderTransform.Scale.X
    assert(math.abs(resizedRed.widget.position.X+width-(viewportWidth/2-24))<.001)
    print('real HUD bars=50 syncs=2 size_reads='..sizeReads..' scale_reads='..scaleReads)
    hudBars:clear()
end
print('arena_hud_widget: PASS (private tree, numeric placement/text readback, persistent visibility, duplicate isolation, foreign binding gate, cleanup)')
