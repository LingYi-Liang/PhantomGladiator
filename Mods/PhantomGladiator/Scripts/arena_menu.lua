-- PBZUIPolicy adds WB_OverLayerOut to the local viewport. Its two native menu stacks
-- keep settings and their subpages on the active layer, independently of game time stop.
local U=require('ue_observe')
local Menu={}
local LAYOUT='WB_OverLayerOut_C'
local STACKS={'GameSystem_Stack','GameMenu_Stack'}
local DISCOVERY_INTERVAL=1
local MENU_TRANSITION=0.18

local function call(object,method)
    if not U.valid(object) then return end
    local ok,value=pcall(function()return object[method](object)end)
    if ok then return U.unwrap(value) end
end

local function visible(widget)
    local value=tonumber(call(widget,'GetVisibility'))
    return value==0 or value==3 or value==4
end

local function attached(layout,playerKey)
    return call(layout,'IsInViewport')==true and U.key(call(layout,'GetOwningPlayer'))==playerKey
end

function Menu.new(options)
    local find=options.findAll or FindAllOf
    local clock=options.clock or os.clock
    local worldKey,playerKey,layout,openedAt,nextSearch,hidden=nil,nil,nil,nil,0,false
    local self={}
    local function finish(wanted,source)
        if hidden~=wanted and options.log then
            options.log('[ArenaHUD] 游戏菜单隐藏='..tostring(wanted)..(source and '；原版层='..source or ''))
        end
        hidden=wanted
        return wanted
    end
    local function reset()
        worldKey,playerKey,layout,openedAt,nextSearch=nil,nil,nil,nil,0
    end

    function self:hidden(active)
        if active==false then reset();return finish(false) end
        local world,player=U.key(options.world()),U.key(options.player())
        if not world or not player then reset();return finish(false) end
        if world~=worldKey or player~=playerKey then
            reset();worldKey,playerKey=world,player
        end

        local now=clock()
        if type(now)~='number' or now~=now or math.abs(now)==math.huge then return finish(false) end
        if layout and not attached(layout,player) then layout,openedAt,nextSearch=nil,nil,0 end
        if not layout and type(find)=='function' and now>=nextSearch then
            nextSearch=now+DISCOVERY_INTERVAL
            local ok,found=pcall(find,LAYOUT)
            for _,candidate in ipairs(ok and U.array(found) or {})do
                if U.className(candidate)==LAYOUT and attached(candidate,player) then
                    layout=candidate
                    break
                end
            end
        end
        if not layout or not visible(layout) then openedAt=nil;return finish(false) end
        for _,name in ipairs(STACKS)do
            local stack=U.field(layout,name)
            if visible(stack) then
                local widget=call(stack,'GetActiveWidget')
                if call(widget,'IsActivated')==true and visible(widget) then
                    openedAt=now
                    return finish(true,name)
                end
            end
        end
        -- A CommonUI stack can briefly have no active widget when switching subpages.
        local transitioning=openedAt~=nil and now>=openedAt and now-openedAt<MENU_TRANSITION
        return finish(transitioning)
    end
    return self
end

return Menu
