-- Private native boss widgets: never borrow the game's reusable extension widgets.
local U=require('ue_observe')
local Renderer={}
local CLASS='/Game/PBZContent/UI/Hud/WB_BossHPBar.WB_BossHPBar_C'
local function same(a,b)local key=U.key(a);return key~=nil and key==U.key(b)end
local function call(obj,name,...)
    assert(U.valid(obj),'invalid widget object: '..name)
    return obj[name](obj,...)
end
local function text(value)
    if type(value)=='string' then return value end
    local ok,s=pcall(function()return value:ToString()end);return ok and s or nil
end
local function readText(block)
    if not U.valid(block) then return nil end
    local ok,value=pcall(function()return block:GetText()end);return ok and text(value) or nil
end
function Renderer.new(options)
    local self={serial=0,hidden={}};local log=options.log or function()end
    local function library(path)local value=StaticFindObject(path);assert(U.valid(value),'missing '..path);return value end
    local function makeText(value)
        return call(library('/Script/Engine.Default__KismetTextLibrary'),'Conv_StringToText',value)
    end
    function self:create(unit)
        local record={};local ok,why=pcall(function()
            local pc,world=options.getController(),options.getWorld()
            assert(U.valid(pc) and U.valid(world) and U.inWorld(unit.actor,world),'HUD world/player mismatch')
            local cls=StaticFindObject(CLASS)
            if not U.valid(cls) then cls=LoadAsset(CLASS) end
            assert(U.valid(cls) and call(cls,'IsAnyClass')==true,'boss widget class unavailable')
            assert(call(cls,'GetFullName'):match('^%S+ (/.+)$')==CLASS,'boss widget class mismatch')
            local widget=call(library('/Script/UMG.Default__WidgetBlueprintLibrary'),'Create',world,cls,pc)
            assert(U.valid(widget),'private widget creation failed');record.widget=widget
            assert(same(call(widget,'GetOwningPlayer'),pc),'private widget belongs to another player')
            local tree=U.field(widget,'WidgetTree');local original=U.field(tree,'RootWidget')
            assert(U.valid(tree) and U.valid(original),'private widget tree unavailable')
            self.serial=self.serial+1
            local overlay=StaticConstructObject(library('/Script/UMG.Overlay'),tree,FName('PG_BossRoot_'..self.serial))
            local numeric=StaticConstructObject(library('/Script/UMG.TextBlock'),tree,FName('PG_BossHP_'..self.serial))
            assert(U.valid(overlay) and U.valid(numeric),'private HP text construction failed')
            assert(same(call(overlay,'GetOuter'),tree) and same(call(numeric,'GetOuter'),tree),'private widget ownership mismatch')
            local originalSlot=call(overlay,'AddChildToOverlay',original)
            call(originalSlot,'SetPadding',{Left=0,Top=28,Right=0,Bottom=0})
            call(originalSlot,'SetHorizontalAlignment',0);call(originalSlot,'SetVerticalAlignment',0)
            local numberSlot=call(overlay,'AddChildToOverlay',numeric)
            call(numberSlot,'SetHorizontalAlignment',2);call(numberSlot,'SetVerticalAlignment',1)
            call(numeric,'SetJustification',1)
            call(numeric,'SetShadowOffset',{X=1,Y=1})
            call(numeric,'SetShadowColorAndOpacity',{R=0,G=0,B=0,A=1})
            local font=U.field(numeric,'Font');assert(U.struct(font,'Size')~=nil,'number font unavailable')
            font.Size=20;call(numeric,'SetFont',font)
            assert(U.valid(tree) and U.valid(overlay));tree.RootWidget=overlay
            assert(same(U.field(tree,'RootWidget'),overlay),'private root readback mismatch')
            record.numeric=numeric;record.overlay=overlay;record.world=world;record.pc=pc
            assert(U.valid(unit.actor) and U.valid(widget));widget.Character=unit.actor
            call(widget,'SetVisibility',3) -- ESlateVisibility.HitTestInvisible in this build.
            call(widget,'AddToViewport',-1) -- Keep menus and the normal HUD above this layer.
            call(widget,'Init',unit.actor)
            assert(same(U.field(widget,'Character'),unit.actor),'private actor binding failed')
            log('[ArenaHUD] 独立血条创建 actor='..tostring(U.key(unit.actor))..' widget='..tostring(U.key(widget))..' number='..tostring(U.key(numeric)))
        end)
        if not ok then
            if U.valid(record.widget) then pcall(function()record.widget:RemoveFromParent()end)end
            return nil,tostring(why)
        end
        return record
    end
    local function displayNumber(value)
        local rounded=math.floor(math.max(0,value)*10+0.5)/10
        if value>0 and rounded==0 then rounded=0.1 end
        return rounded%1==0 and string.format('%.0f',rounded) or string.format('%.1f',rounded)
    end
    function self:update(record,unit,hp,maximum,title,row)
        local widget,numeric=record.widget,record.numeric
        if not U.valid(widget) or not U.valid(numeric) or not same(U.field(widget,'Character'),unit.actor) then return false,'private binding lost' end
        local ok,result=pcall(function()
            local layout=library('/Script/UMG.Default__WidgetLayoutLibrary')
            local size=call(layout,'GetViewportSize',record.world);local scale=call(layout,'GetViewportScale',record.world)
            local width=U.struct(size,'X');assert(type(width)=='number' and type(scale)=='number' and scale>0,'viewport size unavailable')
            local screenWidth=width/scale;local barWidth=math.min(700,math.max(240,(screenWidth-72)/2))
            local x=unit.team=='blue' and 24 or screenWidth-24-barWidth
            local placement=unit.team..':'..row..':'..screenWidth
            if record.placement~=placement then
                call(widget,'SetAlignmentInViewport',{X=0,Y=0})
                call(widget,'SetDesiredSizeInViewport',{X=barWidth,Y=128})
                call(widget,'SetPositionInViewport',{X=x,Y=18+(row-1)*132},false)
                record.placement=placement
            end
            -- The native widget may hide itself after combat/cinematic tag events.
            -- This instance belongs only to this Mod and must stay visible while alive.
            if call(widget,'GetVisibility')~=3 then call(widget,'SetVisibility',3)end
            call(record.overlay,'SetVisibility',3)
            call(numeric,'SetVisibility',3)
            local name=U.field(widget,'BossName')
            if readText(name)~=title then call(widget,'ForSeq_SetNameText',makeText(title))end
            local box=U.field(widget,'BossNameHorBox');if U.valid(box) then call(box,'SetVisibility',3)end
            local ratio=math.max(0,math.min(1,hp/maximum));local bar=U.field(widget,'hpbar')
            call(bar,'SetVisibility',3)
            local actual=U.field(bar,'CurPercent')
            if not record.healthInitialized or type(actual)~='number' or math.abs(actual-ratio)>0.0001 then
                call(widget,'ForSeq_UpdateHealth',ratio);record.healthInitialized=true
            end
            local value=displayNumber(hp)..' / '..displayNumber(maximum)
            if readText(numeric)~=value then call(numeric,'SetText',makeText(value))end
            actual=U.field(bar,'CurPercent')
            local state={visible=call(widget,'IsVisible')==true,names=readText(name)==title,
                health=type(actual)=='number' and math.abs(actual-ratio)<0.002,numbers=readText(numeric)==value}
            local signature=title..':'..math.floor(ratio*10)..':'..tostring(state.visible)..':'..tostring(state.names)..':'..tostring(state.health)..':'..tostring(state.numbers)
            if record.signature~=signature then
                record.signature=signature
                log('[ArenaHUD] 显示读回 name='..title..' HP='..value..' visible='..tostring(state.visible)
                    ..' name_ok='..tostring(state.names)..' hp_ok='..tostring(state.health)..' number_ok='..tostring(state.numbers))
            end
            return state
        end)
        return ok and result or nil,not ok and tostring(result) or nil
    end
    function self:remove(record)
        if not U.valid(record.widget) then return true end
        local ok,removed=pcall(function()
            call(record.widget,'RemoveFromParent')
            return call(record.widget,'IsInViewport')==false
        end)
        log('[ArenaHUD] 清理独立血条 widget='..tostring(U.key(record.widget))..' removed='..tostring(ok and removed))
        return ok and removed
    end
    local function findHUD()
        if options.getHUD then return options.getHUD() end
        local pc=options.getController();if not U.valid(pc) then return nil end
        if U.valid(self.hud) and same(call(self.hud,'GetOwningPlayer'),pc) then return self.hud end
        local ok,list=pcall(FindAllOf,'PBZHUDLayout')
        if ok then for _,hud in ipairs(U.array(list or {}) or {})do
            if U.valid(hud) and same(call(hud,'GetOwningPlayer'),pc) then self.hud=hud;return hud end
        end end
    end
    function self:syncNative(desired,privateKeys,removeUnbound)
        local wanted={};local hud=findHUD();local entries={};local point=U.field(hud,'BossPoint')
        if U.valid(hud) then
            local ok,list=pcall(function()return hud:GetBossHPBarInstances()end)
            for _,w in ipairs(ok and U.array(list) or {})do entries[#entries+1]=w end
        end
        if U.valid(point) then
            local ok,list=pcall(function()return point:GetAllEntries()end)
            for _,w in ipairs(ok and U.array(list) or {})do entries[#entries+1]=w end
        end
        for _,widget in ipairs(entries)do
            local key=U.key(widget);local actor,read=U.field(widget,'Character');local actorKey=U.key(actor)
            if key and not privateKeys[key] and desired[actorKey] then
                wanted[key]=true
                local ok,visibility=pcall(function()return widget:GetVisibility()end)
                if ok and type(visibility)=='number' then
                    if visibility~=1 and not self.hidden[key] then self.hidden[key]={widget=widget,original=visibility}end
                    if visibility~=1 then pcall(function()if U.valid(widget) then widget:SetVisibility(1)end end)end
                end
            elseif removeUnbound and key and not privateKeys[key] and read and not U.valid(actor) and U.valid(point) then
                pcall(function()point:UnregsiterHandleByWidget(widget)end)
            end
        end
        for key,record in pairs(self.hidden)do if not wanted[key] then
            if U.valid(record.widget) then
                pcall(function()
                    if record.widget:GetVisibility()==1 then record.widget:SetVisibility(record.original)end
                end)
            end
            self.hidden[key]=nil
        end end
    end
    return self
end
return Renderer
