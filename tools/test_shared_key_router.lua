package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Router=require('key_router');local Functions=require('function_keybinds');local Units=require('unit_keybinds')
local root=assert(arg[1],'isolated directory required')
local slots,queue,unitCalls,functionCalls={},{},{},{};local inGame=false
local function slot(vk,mods)local mask=0;for _,mod in ipairs(mods or {})do mask=mask+mod end;return vk..':'..mask end
local keyTable={F6=117,F7=118,Q=81};local modifiers={CONTROL=1,ALT=2,SHIFT=4}
local router=Router.new({keys=keyTable,modifiers=modifiers,
    occupied=function(vk,mods)return slots[slot(vk,mods)]~=nil end,
    register=function(vk,mods,fn)if type(mods)=='function'then fn=mods;mods={}end;slots[slot(vk,mods)]=fn end})
local functions
local units=Units.new({path=root,keys=keyTable,modifiers=modifiers,router=router,
    reserved=function(vk)if functions then local _,name=functions:owner(vk);return name end end,
    queue=function(fn)queue[#queue+1]=fn end,ready=function()assert(inGame);return true end,
    spawn=function(unit)assert(inGame);unitCalls[#unitCalls+1]=unit;return {ok=true,message='fixture'}end})
functions=Functions.new({path=root,router=router,unitOwner=function(vk)return units:owner(vk)end,
    queue=function(fn)queue[#queue+1]=fn end,dispatch=function(action)assert(inGame);functionCalls[#functionCalls+1]=action end})
router.dispatch=function(vk,mask)if not functions:press(vk,mask)then units:dispatch(vk,mask)end end
functions:start();units:start();assert(next(slots)==nil)
local function drain()inGame=true;while #queue>0 do table.remove(queue,1)()end;inGame=false end
local function proposal()
    local out={};for _,name in ipairs(Functions.actions)do out[name]='UNBOUND'end;return out
end
local a='/Game/BP_A.BP_A_C';local b='/Game/BP_B.BP_B_C'
assert(units:configure(a,117,0).ok);slots['117:0']();drain();assert(unitCalls[1]==a)
local p=proposal();p.toggle_camera='F6'
assert(not functions:configure(p).ok,'an occupied unit key must block function assignment')
assert(units:configure(a,0,0).ok and functions:configure(p).ok)
slots['117:0']();drain();assert(#unitCalls==1 and functionCalls[1]=='toggle_camera')
assert(not units:configure(b,117,4).ok,'an occupied function primary key must block unit assignment')
assert(functions:configure(proposal()).ok and units:configure(b,117,4).ok)
slots['117:0']();assert(#queue==0,'the old unmodified chord is inert')
slots['117:4']();drain();assert(unitCalls[2]==b and #functionCalls==1)
print('shared_key_router: PASS (unit/function ownership transfer, cross-modifier conflicts, inert old chords, no duplicate actions)')
