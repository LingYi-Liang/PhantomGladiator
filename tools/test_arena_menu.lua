package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Menu=require('arena_menu')
local id=0
local function obj(fields)
    id=id+1;local k=id
    fields=fields or {}
    function fields:IsValid()return not self.gone end
    function fields:GetAddress()return k end
    return fields
end
local function widget(visibility,active)
    return obj({visibility=visibility,active=active,
        GetVisibility=function(self)return self.visibility end,
        IsActivated=function(self)return self.active end})
end
local function stack(w)
    local x=widget(4)
    x.current=w
    function x:GetActiveWidget()return self.current end
    return x
end
local function layout(owner,system,menu,className)
    local class=obj({GetFName=function()return {ToString=function()return className or 'WB_OverLayerOut_C' end}end})
    local x=widget(4)
    x.owner=owner;x.inViewport=true
    x.GameSystem_Stack=stack(system);x.GameMenu_Stack=stack(menu)
    function x:GetOwningPlayer()return self.owner end
    function x:IsInViewport()return self.inViewport end
    function x:GetClass()return class end
    return x
end

local world,player,other=obj(),obj(),obj()
local system,submenu,gameMenu=widget(3,false),widget(4,true),widget(0,true)
local cached=layout(player,system,gameMenu)
cached.GameMenu_Stack.visibility=2
local outside=layout(other,widget(0,true),widget(0,true))
local offscreen=layout(player,widget(0,true),widget(0,true));offscreen.inViewport=false
local wrongClass=layout(player,widget(0,true),widget(0,true),'UnrelatedLayout_C')
local candidates={outside,offscreen,wrongClass,cached}
local now,scans=0,0
local detector=Menu.new({world=function()return world end,player=function()return player end,
    clock=function()return now end,findAll=function(class)
        assert(class=='WB_OverLayerOut_C')
        scans=scans+1;return candidates
    end})
assert(not detector:hidden(false) and scans==0,'do not hunt UI when there are no managed bars')
assert(not detector:hidden(true),'detached, hidden and deactivated UI must not hide the HUD')
system.active=true
assert(detector:hidden(true) and scans==1,'the active settings widget hides without another scan')
cached.GameSystem_Stack.current=submenu
assert(detector:hidden(true),'settings sub-pages use the same native layer')
cached.GameSystem_Stack.current=nil
now=0.04
assert(detector:hidden(true),'a brief transition between sub-pages does not flash the HUD')
now=0.3
assert(not detector:hidden(true),'closing the system layer restores HUD')
cached.GameMenu_Stack.visibility=0
assert(detector:hidden(true),'the native Game Menu layer can itself cover combat')
cached.inViewport=false
assert(not detector:hidden(true),'a detached cached layout cannot continue hiding the HUD')
assert(not detector:hidden(true))
assert(scans==2,'discovery is throttled when no usable layout exists')
player=obj()
world=obj()
assert(not detector:hidden(true) and scans==3,'the next world/controller starts fresh')
cached=layout(player,widget(0,true));candidates={cached}
now=1.5
assert(detector:hidden(true) and scans==4,'the new controller can activate its own game settings')
assert(not detector:hidden(false) and scans==4,'turning the overlay off releases the session')
print('arena_menu: PASS (active layers, visibility, transition, ownership, viewport, discovery and travel)')
