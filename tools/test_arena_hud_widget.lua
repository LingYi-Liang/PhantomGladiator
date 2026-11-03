package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Renderer=require('arena_hud_widget')
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
function layout:GetViewportSize(context)assert(context==world);return {X=3840,Y=2160}end
function layout:GetViewportScale(context)assert(context==world);return 2 end
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
        o.children={};o.slots={}
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
print('arena_hud_widget: PASS (private tree, numeric placement/text readback, persistent visibility, duplicate isolation, foreign binding gate, cleanup)')
