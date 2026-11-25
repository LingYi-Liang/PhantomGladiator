-- A runtime-only Unreal CommonUI widget. All visuals are constructed into its own tree.
local U=require('ue_observe')
local N=require('photo_native')
local Overlay={}
local WIDTH,HEIGHT,ROWS=442,509,8
local COLORS={
    base={R=.016,G=.030,B=.043,A=.96}, edge={R=.075,G=.115,B=.133,A=1},
    focus={R=.18,G=.105,B=.052,A=1}, gold={R=.94,G=.69,B=.42,A=1},
    ink={R=.90,G=.95,B=.96,A=1}, soft={R=.58,G=.68,B=.72,A=1},
}
local function rgba(value)return {SpecifiedColor=value,ColorUseRule=0}end

function Overlay.new(o)
    local self={}
    local find=o.find or StaticFindObject
    local construct=o.construct or StaticConstructObject
    local fname=o.fname or FName
    local log=o.log or function()end
    local rec
    local function native(path)
        local value=type(find)=='function' and find(path)
        assert(U.valid(value),'studio class unavailable '..path)
        return value
    end
    local function setText(block,value)
        if block.value==value then return end
        local text=N.need(rec.textLib,'Conv_StringToText',value)
        assert(text~=nil,'studio text conversion failed')
        N.need(block.widget,'SetText',text)
        block.value=value
    end
    local function visible(widget,show,verify)
        if not U.valid(widget) then return false end
        local wanted=show and 3 or 1
        if verify and tonumber((N.call(widget,'GetVisibility')))==wanted then return true end
        local _,wrote=N.call(widget,'SetVisibility',wanted)
        return wrote and (not verify or tonumber((N.call(widget,'GetVisibility')))==wanted)
    end
    local function makeLabel(row,x,y,w,h,size,c,right,wrap)
        local label=construct(rec.textClass,rec.tree,fname('PG_StudioText_'..row))
        assert(U.valid(label) and N.same(N.call(label,'GetOuter'),rec.tree),'studio text ownership mismatch')
        local slot=N.need(rec.canvas,'AddChildToCanvas',label)
        N.need(slot,'SetPosition',{X=x,Y=y});N.need(slot,'SetSize',{X=w,Y=h})
        local font=U.field(label,'Font')
        assert(U.struct(font,'Size')~=nil,'studio font unavailable')
        font.Size=size
        N.need(label,'SetFont',font)
        N.need(label,'SetColorAndOpacity',rgba(c))
        if right then N.need(label,'SetJustification',2) end
        if wrap then N.need(label,'SetAutoWrapText',true) end
        return {widget=label}
    end
    local function makeBox(id,x,y,w,h,color,z)
        local box=construct(rec.borderClass,rec.tree,fname('PG_Studio_'..id))
        assert(U.valid(box) and N.same(N.call(box,'GetOuter'),rec.tree),'studio panel ownership mismatch')
        N.need(box,'SetBrushColor',color)
        local slot=N.need(rec.canvas,'AddChildToCanvas',box)
        N.need(slot,'SetPosition',{X=x,Y=y});N.need(slot,'SetSize',{X=w,Y=h})
        if z then N.need(slot,'SetZOrder',z) end
        return box
    end
    function self:hide(verify)
        if not rec then return false end
        if rec.hidden and not verify then return true end
        local hidden=visible(rec.widget,false,true)
        rec.hidden=hidden and true or nil
        return hidden
    end
    function self:detach()
        if rec then
            if rec.decor then N.call(rec.decor.widget,'RemoveFromParent') end
            N.call(rec.widget,'RemoveFromParent');rec=nil
        end
    end
    function self:open(world,pc,own)
        if rec then return false,'摄影面板已打开' end
        local made
        local ok,reason=pcall(function()
            local cls=native('/Script/CommonUI.CommonUserWidget')
            local lib=native('/Script/UMG.Default__WidgetBlueprintLibrary')
            local widget=N.need(lib,'Create',world,cls,pc)
            assert(U.valid(widget) and N.same(N.call(widget,'GetOwningPlayer'),pc),'studio widget player mismatch')
            made=widget
            local tree=U.field(widget,'WidgetTree')
            if not U.valid(tree) then
                tree=construct(native('/Script/UMG.WidgetTree'),widget,fname('PG_StudioTree'))
                assert(U.valid(tree) and N.same(N.call(tree,'GetOuter'),widget),'studio widget tree unavailable')
                widget.WidgetTree=tree
                assert(N.same(U.field(widget,'WidgetTree'),tree),'studio widget tree readback mismatch')
            end
            local canvas=construct(native('/Script/UMG.CanvasPanel'),tree,fname('PG_StudioRoot'))
            assert(U.valid(canvas) and N.same(N.call(canvas,'GetOuter'),tree),'studio root ownership mismatch')
            tree.RootWidget=canvas
            assert(N.same(U.field(tree,'RootWidget'),canvas),'studio root readback mismatch')
            rec={widget=widget,tree=tree,canvas=canvas,world=world,pc=pc,own=own,rows={},textClass=native('/Script/UMG.TextBlock'),
                borderClass=native('/Script/UMG.Border'),textLib=native('/Script/Engine.Default__KismetTextLibrary'),
                layout=native('/Script/UMG.Default__WidgetLayoutLibrary')}
            makeBox('Panel',0,0,WIDTH,HEIGHT,COLORS.base,-3)
            makeBox('Edge',0,0,3,HEIGHT,COLORS.gold,-2)
            makeBox('Separator',22,83,WIDTH-44,1,COLORS.edge,-1)
            rec.title=makeLabel('Title',22,18,WIDTH-44,30,24,COLORS.ink)
            rec.tabs=makeLabel('Tabs',22,58,WIDTH-44,22,16,COLORS.gold)
            for i=1,ROWS do
                local top=93+(i-1)*38
                rec.rows[i]={back=makeBox('Row'..i,15,top,WIDTH-30,35,COLORS.focus,-1),
                    label=makeLabel('Label'..i,25,top+6,193,24,17,COLORS.ink),
                    value=makeLabel('Value'..i,213,top+6,204,24,17,COLORS.ink,true)}
            end
            rec.hint=makeLabel('Hint',22,409,WIDTH-44,83,14,COLORS.soft,false,true)
            assert(own(widget),'studio widget recovery record unavailable')
            N.need(widget,'SetDesiredSizeInViewport',{X=WIDTH,Y=HEIGHT})
            N.need(widget,'SetAlignmentInViewport',{X=1,Y=.5})
            N.need(widget,'SetRenderTransformPivot',{X=1,Y=.5})
            N.need(widget,'SetVisibility',3)
            N.need(widget,'AddToViewport',42)
            assert(N.call(widget,'IsInViewport')==true,'studio widget not in viewport')
            rec.hidden=false
        end)
        if not ok then
            if U.valid(made) then N.call(made,'RemoveFromParent') end
            rec=nil
            log('[Photo] 面板创建未确认 '..tostring(reason))
            return false,'游戏内摄影面板未打开'
        end
        log('[Photo] 独立面板创建读回=true')
        return true
    end
    local function newDecor()
        local instance
        local ok,why=pcall(function()
            local cls=native('/Script/CommonUI.CommonUserWidget')
            local lib=native('/Script/UMG.Default__WidgetBlueprintLibrary')
            instance=N.need(lib,'Create',rec.world,cls,rec.pc)
            assert(U.valid(instance) and N.same(N.call(instance,'GetOwningPlayer'),rec.pc),'composition widget owner unavailable')
            local tree=U.field(instance,'WidgetTree')
            if not U.valid(tree) then
                tree=construct(native('/Script/UMG.WidgetTree'),instance,fname('PG_PhotoCompositionTree'))
                assert(U.valid(tree))
                instance.WidgetTree=tree
            end
            local canvas=construct(native('/Script/UMG.CanvasPanel'),tree,fname('PG_PhotoCompositionRoot'))
            assert(U.valid(canvas) and N.same(N.call(canvas,'GetOuter'),tree))
            tree.RootWidget=canvas
            assert(N.same(U.field(tree,'RootWidget'),canvas))
            local d={widget=instance,borders={},grid={},cross={}}
            local function box(id,color)
                local obj=construct(rec.borderClass,tree,fname('PG_PhotoComposition'..id))
                assert(U.valid(obj) and N.same(N.call(obj,'GetOuter'),tree))
                local slot=N.need(canvas,'AddChildToCanvas',obj)
                N.need(obj,'SetBrushColor',color)
                return {widget=obj,slot=slot}
            end
            for i=1,4 do d.borders[i]=box('Edge'..i,COLORS.base) end
            local line={R=.96,G=.96,B=.96,A=.24}
            for i=1,4 do d.grid[i]=box('Guide'..i,line) end
            d.cross[1]=box('Focus1',COLORS.gold);d.cross[2]=box('Focus2',COLORS.gold)
            local label=construct(rec.textClass,tree,fname('PG_PhotoCompositionMark'))
            assert(U.valid(label))
            local font=U.field(label,'Font')
            assert(U.struct(font,'Size')~=nil)
            font.Size=22
            N.need(label,'SetFont',font)
            N.need(label,'SetJustification',2)
            N.need(label,'SetShadowColorAndOpacity',{R=0,G=0,B=0,A=.82})
            N.need(label,'SetShadowOffset',{X=1,Y=1})
            d.mark={widget=label,slot=N.need(canvas,'AddChildToCanvas',label)}
            assert(rec.own(instance),'composition recovery record unavailable')
            N.need(instance,'SetVisibility',3)
            N.need(instance,'AddToViewport',41)
            assert(N.call(instance,'IsInViewport')==true)
            rec.decor=d
            log('[Photo] 独立构图层创建读回=true')
        end)
        if not ok then
            if U.valid(instance) then N.call(instance,'RemoveFromParent') end
            log('[Photo] 构图层未创建 '..tostring(why))
        end
        return ok
    end
    local function rect(item,x,y,w,h)
        N.need(item.slot,'SetPosition',{X=x,Y=y})
        N.need(item.slot,'SetSize',{X=w,Y=h})
        visible(item.widget,w>0 and h>0)
    end
    function self:composition(s,shooting,now)
        if not rec then return false end
        local guides=s.grid and not shooting
        local cross=s.focusMark and not shooting
        local output=not shooting or not s.captureHDR
        local border=output and s.border or 1
        local mark=output and s.mark or 1
        if not guides and not cross and border==1 and mark==1 then
            if rec.decor and (rec.decor.shown or shooting) then
                if not visible(rec.decor.widget,false,true) then return false end
                rec.decor.shown=false
            end
            return true
        end
        if not rec.decor then
            if rec.decorFailed then return false end
            if not newDecor() then rec.decorFailed=true;return false end
        end
        local d=rec.decor
        if not d.x or now>=(d.resizeAt or 0) then
            d.resizeAt=now+.35
            local size=N.call(rec.layout,'GetViewportSize',rec.world)
            local scale=N.call(rec.layout,'GetViewportScale',rec.world)
            local x,y=U.struct(size,'X'),U.struct(size,'Y')
            if N.number(x) and N.number(y) and N.number(scale) and scale>0 and x>0 and y>0 then
                d.x,d.y=x/scale,y/scale
            end
        end
        if not d.x then return false end
        local w,h=d.x,d.y
        local key=table.concat({w,h,border,mark,tostring(guides),tostring(cross)},':')
        if not d.shown then
            if not visible(d.widget,true,true) then return false end
            d.shown=true
        end
        if d.key==key then return true end
        N.need(d.widget,'SetAlignmentInViewport',{X=0,Y=0})
        N.need(d.widget,'SetPositionInViewport',{X=0,Y=0},false)
        N.need(d.widget,'SetDesiredSizeInViewport',{X=w,Y=h})
        local tall=border==2 and h*.10 or border>2 and 12 or 0
        local wide=border>2 and 12 or 0
        local color=border==3 and COLORS.ink or {R=0,G=0,B=0,A=1}
        for _,item in ipairs(d.borders)do N.need(item.widget,'SetBrushColor',color)end
        rect(d.borders[1],0,0,w,tall);rect(d.borders[2],0,h-tall,w,tall)
        rect(d.borders[3],0,tall,wide,h-tall*2);rect(d.borders[4],w-wide,tall,wide,h-tall*2)
        for i=1,2 do
            if guides then
                rect(d.grid[i],w*i/3,tall,1,h-tall*2)
                rect(d.grid[i+2],wide,h*i/3,w-wide*2,1)
            else
                visible(d.grid[i].widget,false);visible(d.grid[i+2].widget,false)
            end
        end
        if cross then
            rect(d.cross[1],w/2-9,h/2,18,1);rect(d.cross[2],w/2,h/2-9,1,18)
        else
            visible(d.cross[1].widget,false);visible(d.cross[2].widget,false)
        end
        local markText=({'','斗蛐蛐 · 摄影','留影','影之刃零'})[mark]
        if mark>1 then
            setText(d.mark,markText)
            rect(d.mark,w-260-wide,h-46-tall,238,30)
        else visible(d.mark.widget,false) end
        d.key=key
        return true
    end
    function self:render(model,now)
        if not rec then return false end
        if not U.valid(rec.widget) then return false end
        if not model.visible then return self:hide() end
        if rec.hidden~=false then
            if not visible(rec.widget,true,true) then return false end
            rec.hidden=false
        end
        if now>=(rec.resizeAt or 0) then
            rec.resizeAt=now+.5
            local size=N.call(rec.layout,'GetViewportSize',rec.world)
            local scale=N.call(rec.layout,'GetViewportScale',rec.world)
            local x,y=U.struct(size,'X'),U.struct(size,'Y')
            if N.number(x) and N.number(y) and N.number(scale) and scale>0 and x>0 and y>0 then
                x,y=x/scale,y/scale
                if rec.x~=x or rec.y~=y then
                    local factor=math.min(1,(y-36)/HEIGHT,(x-36)/WIDTH)
                    factor=math.max(.45,factor)
                    N.need(rec.widget,'SetRenderScale',{X=factor,Y=factor})
                    N.need(rec.widget,'SetPositionInViewport',{X=x-20,Y=y*.5},false)
                    rec.x,rec.y=x,y
                end
            end
        end
        if rec.signature==model.signature then return true end
        setText(rec.title,model.title);setText(rec.tabs,model.tabs)
        for i,row in ipairs(rec.rows)do
            local v=model.rows[i]
            visible(row.back,v and i==model.selected)
            visible(row.label.widget,v~=nil);visible(row.value.widget,v~=nil)
            if v then setText(row.label,v.label);setText(row.value,v.value)end
        end
        setText(rec.hint,model.hint)
        rec.signature=model.signature
        return true
    end
    return self
end
return Overlay
