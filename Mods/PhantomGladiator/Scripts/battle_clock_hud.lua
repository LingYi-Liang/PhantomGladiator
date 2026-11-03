-- Battle clock on the game screen. When switched on, the fight time (arena_controller.lua, game
-- seconds) is shown at the top centre of the screen while a fight runs, and the final time stays until
-- the field is cleared. The text sits in a private copy of the game's boss bar widget whose tree is
-- replaced by a single text block: the construction the private boss bars already use
-- (arena_hud_widget.lua), without its bar. The switch is saved in Runtime/clock-hud.tsv.
local U=require('ue_observe')
local Clock={}
local CLASS='/Game/PBZContent/UI/Hud/WB_BossHPBar.WB_BossHPBar_C'
local HEADER='ClockHudV1'
local ROOT='PG_ClockRoot'
local WIDTH,HEIGHT,TOP,FONT=360,64,14,30

local function same(a,b)local key=U.key(a);return key~=nil and key==U.key(b)end
local function call(obj,name,...)
    assert(U.valid(obj),'invalid widget object: '..name)
    return obj[name](obj,...)
end
local function text(value)
    if type(value)=='string' then return value end
    local ok,s=pcall(function()return value:ToString()end);return ok and s or nil
end
local function fname(obj)
    local ok,n=pcall(function()return obj:GetFName():ToString()end)
    return ok and type(n)=='string' and n or ''
end
-- m:ss, or h:mm:ss from an hour on.
function Clock.format(seconds)
    local s=math.max(0,math.floor(tonumber(seconds) or 0))
    if s>=3600 then return string.format('%d:%02d:%02d',s//3600,s%3600//60,s%60) end
    return string.format('%d:%02d',s//60,s%60)
end

function Clock.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local settings=options.path..'/clock-hud.tsv'
    local self={alive=true,on=false,state='off',message='',failures=0}
    local record       -- the widget on screen: {widget, text, world, shown}
    local leftoversChecked=false
    local function say(m)log('[ClockHUD] '..m)end
    local function readFile(path)
        local f=fs.open(path,'r');if not f then return nil end
        local value=f:read('*a');f:close();return value
    end
    local function writeFile(path,value)
        local f=fs.open(path,'w');if not f then return false end
        local wrote=f:write(value);local closed=f:close()
        return wrote~=nil and wrote~=false and closed~=false and readFile(path)==value
    end
    do
        local saved=readFile(settings)
        if type(saved)=='string' and saved:sub(1,#HEADER+1)==HEADER..'\t' then self.on=saved:find('\tshow=1',1,true)~=nil end
    end
    local function library(path)local value=StaticFindObject(path);assert(U.valid(value),'missing '..path);return value end
    local function makeText(value)return call(library('/Script/Engine.Default__KismetTextLibrary'),'Conv_StringToText',value)end

    local function remove(reason)
        if record and U.valid(record.widget) then
            local ok,gone=pcall(function()call(record.widget,'RemoveFromParent');return call(record.widget,'IsInViewport')==false end)
            say('移除计时（'..reason..'） 读回已移除='..tostring(ok and gone))
        end
        record=nil
    end
    -- A mod reload leaves the last instance's widget on screen; its tree root carries our name.
    local function removeLeftovers()
        local ok,list=pcall(FindAllOf,'WB_BossHPBar_C')
        local removed=0
        for _,widget in ipairs(ok and U.array(list or {}) or {})do
            local root=U.field(U.field(widget,'WidgetTree'),'RootWidget')
            if U.valid(root) and fname(root):sub(1,#ROOT)==ROOT then
                if pcall(function()call(widget,'RemoveFromParent')end) then removed=removed+1 end
            end
        end
        if removed>0 then say('移除上次留下的计时 '..removed..' 个') end
    end
    local function create(world,pc)
        local made={}
        local ok,why=pcall(function()
            local cls=StaticFindObject(CLASS)
            if not U.valid(cls) then cls=LoadAsset(CLASS) end
            assert(U.valid(cls) and call(cls,'IsAnyClass')==true,'widget class unavailable')
            local widget=call(library('/Script/UMG.Default__WidgetBlueprintLibrary'),'Create',world,cls,pc)
            assert(U.valid(widget),'widget creation failed');made.widget=widget
            assert(same(call(widget,'GetOwningPlayer'),pc),'widget belongs to another player')
            local tree=U.field(widget,'WidgetTree')
            assert(U.valid(tree),'widget tree unavailable')
            local overlay=StaticConstructObject(library('/Script/UMG.Overlay'),tree,FName(ROOT))
            local block=StaticConstructObject(library('/Script/UMG.TextBlock'),tree,FName('PG_ClockText'))
            assert(U.valid(overlay) and U.valid(block),'text construction failed')
            local slot=call(overlay,'AddChildToOverlay',block)
            call(slot,'SetHorizontalAlignment',2);call(slot,'SetVerticalAlignment',1)   -- centre, top
            call(block,'SetJustification',1)
            call(block,'SetShadowOffset',{X=2,Y=2})
            call(block,'SetShadowColorAndOpacity',{R=0,G=0,B=0,A=0.85})
            local font=U.field(block,'Font');assert(U.struct(font,'Size')~=nil,'font unavailable')
            font.Size=FONT;call(block,'SetFont',font)
            tree.RootWidget=overlay
            assert(same(U.field(tree,'RootWidget'),overlay),'root readback mismatch')
            -- The boss bar's own graph expects a character; the player keeps it harmless (its bar is not shown).
            local player=options.getPlayer and options.getPlayer()
            if U.valid(player) then widget.Character=player end
            call(widget,'SetVisibility',3)          -- HitTestInvisible: never takes the mouse
            call(widget,'AddToViewport',-1)         -- below menus and the game's own HUD
            made.text=block;made.world=world
        end)
        if not ok then
            if U.valid(made.widget) then pcall(function()made.widget:RemoveFromParent()end) end
            return nil,tostring(why)
        end
        say('创建计时 widget='..tostring(U.key(made.widget))..' 文本='..tostring(U.key(made.text)))
        return made
    end
    local function place(world)
        local layout=library('/Script/UMG.Default__WidgetLayoutLibrary')
        local size=call(layout,'GetViewportSize',world);local scale=call(layout,'GetViewportScale',world)
        local width=U.struct(size,'X');assert(type(width)=='number' and type(scale)=='number' and scale>0,'viewport size unavailable')
        local centre=width/scale/2
        if record.centre~=centre then
            call(record.widget,'SetAlignmentInViewport',{X=0.5,Y=0})
            call(record.widget,'SetDesiredSizeInViewport',{X=WIDTH,Y=HEIGHT})
            call(record.widget,'SetPositionInViewport',{X=centre,Y=TOP},false)
            record.centre=centre
        end
    end

    function self:set(value)
        if value~='ON' and value~='OFF' then return {ok=false,message='计时显示开关只接受 ON 或 OFF',spawned_count=0} end
        local before=self.on
        self.on=value=='ON'
        local saved=writeFile(settings,HEADER..'\tshow='..(self.on and '1' or '0')..'\n')
        if not saved then self.on=before end
        if saved then self.state=self.on and 'waiting' or 'off' end
        say('设置 显示='..value..' 保存读回='..tostring(saved))
        return {ok=saved,spawned_count=0,message=saved and (self.on and '画面计时已开启' or '画面计时已关闭') or '计时显示设置没能保存'}
    end
    -- Support tick (0.5 s): show the clock while a fight runs or has ended, otherwise take it away.
    function self:tick()
        if not self.alive or (options.ready and not options.ready()) then return end
        if not leftoversChecked then leftoversChecked=true;removeLeftovers() end
        if not self.on then
            if record then remove('已关闭') end
            self.state='off';return
        end
        local clock,seconds=options.clock()
        if clock~='running' and clock~='ended' then
            if record then remove('没有在计时的战斗') end
            -- A failed widget is tried again with the next fight.
            self.state='waiting';return
        end
        local pc,world=options.getController(),options.getWorld()
        if not U.valid(pc) or not U.valid(world) then return end
        if record and (not U.valid(record.widget) or not U.valid(record.text) or not same(record.world,world)) then
            say('计时控件已失效（换地图或读档），重新创建');record=nil
        end
        if not record then
            if self.state=='failed' then return end
            local made,why=create(world,pc)
            if not made then
                self.failures=self.failures+1;self.state='failed';self.message='计时没能显示：'..why
                say(self.message);return
            end
            record=made
        end
        local ok,why=pcall(function()
            place(world)
            local value=Clock.format(seconds)
            if text(call(record.text,'GetText'))~=value then call(record.text,'SetText',makeText(value)) end
            if call(record.widget,'GetVisibility')~=3 then call(record.widget,'SetVisibility',3) end
            local shown=call(record.widget,'IsInViewport')==true and text(call(record.text,'GetText'))==value
            if shown~=record.shown then
                record.shown=shown
                say('显示读回 文本='..value..' 在屏幕上='..tostring(shown)..' 状态='..tostring(clock))
            end
        end)
        if not ok then
            self.failures=self.failures+1;self.state='failed';self.message='计时更新失败：'..tostring(why)
            say(self.message);remove('更新失败');return
        end
        self.state=record.shown and 'shown' or 'failed';self.message=''
    end
    function self:status()return {on=self.on,state=self.state,failures=self.failures,message=self.message}end
    -- Unloading writes nothing to the game; the next instance removes the widget left behind.
    function self:silence()self.alive=false end
    return self
end
return Clock
