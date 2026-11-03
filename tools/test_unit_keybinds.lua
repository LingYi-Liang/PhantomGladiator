package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Keys=dofile('Mods/PhantomGladiator/Scripts/unit_keybinds.lua')
local root=assert(arg[1],'isolated test directory required')
os.remove(root..'/unit-keybinds.tsv');os.remove(root..'/unit-keybinds-state.tsv')
local slots,queue,spawned,teams={},{},{},{}
local inGame=false
local function slot(vk,mods)
    local mask=0;for _,mod in ipairs(mods or {})do mask=mask+({[1]=1,[2]=2,[4]=4})[mod] end
    return vk..':'..mask
end
slots['116:0']=function()end -- Shared unused panel key.
local options={path=root,keys={Q=81,E=69,F5=116,F6=117,R=82},modifiers={CONTROL=1,ALT=2,SHIFT=4},
    occupied=function(vk,mods)return slots[slot(vk,mods)]~=nil end,
    register=function(vk,mods,callback)if type(mods)=='function'then callback=mods;mods={}end;slots[slot(vk,mods)]=callback end,
    shared=function(vk)return vk==116 end,
    queue=function(fn)queue[#queue+1]=fn end,
    ready=function()assert(inGame);return true end,
    spawn=function(unit,team,count)assert(inGame);spawned[#spawned+1]=unit;teams[#spawned]={team,count};return {ok=true,message='fixture spawned'}end}
local keys=Keys.new(options);keys:start()
assert(keys:status().revision==0 and not keys:isBound(81),'defaults must not assign any unit key')
local a='/Game/BP_A.BP_A_C';local b='/Game/BP_B.BP_B_C'
assert(keys:configure(a,81,1).ok)
slots['81:1']();assert(#queue==1 and #spawned==0)
assert(keys:configure(a,69,0).ok)
inGame=true;table.remove(queue,1)();inGame=false
assert(#spawned==0,'a remapped key must cancel an already queued old binding')
slots['69:0']();inGame=true;table.remove(queue,1)();inGame=false
assert(spawned[1]==a)
assert(not keys:configure(b,69,4).ok,'same primary key must not double-spawn two different units')
assert(keys:configure(b,117,0).ok,'an unassigned former camera key must be available')
assert(keys:configure(b,116,0).ok)
keys:dispatch(116,0);inGame=true;table.remove(queue,1)();inGame=false
assert(spawned[2]==b,'unassigned shared panel keys must reach unit bindings')
assert(keys:configure(a,0,0).ok);slots['69:0']();assert(#queue==0,'cleared callbacks remain inert')
local restored=Keys.new(options);restored:start();assert(restored:isBound(116) and not restored:isBound(69),'confirmed bindings survive reload')
keys:silence();keys:dispatch(116,0);assert(#queue==0,'unloaded callbacks must be inert')
slots['81:2']=function()end
assert(not restored:configure(a,81,0).ok,'a different modifier chord from another mod still conflicts on the same primary key')
-- Each unit key keeps its own team and count; switching it later re-saves the same key.
assert(restored:configure(b,116,0,'red',2).ok)
restored:dispatch(116,0);inGame=true;table.remove(queue,1)();inGame=false
assert(spawned[#spawned]==b and teams[#spawned][1]=='red' and teams[#spawned][2]==2,'a unit key spawns to its own team and count')
assert(restored:configure(b,116,0,'neutral',1).ok,'switching the team keeps the same key')
restored:dispatch(116,0);inGame=true;table.remove(queue,1)();inGame=false
assert(teams[#spawned][1]=='neutral' and teams[#spawned][2]==1)
assert(not restored:configure(b,116,0,'green',1).ok and not restored:configure(b,116,0,'red',101).ok,'unknown team or count is refused')
local reloaded=Keys.new(options);reloaded:start()
reloaded:dispatch(116,0);inGame=true;table.remove(queue,1)();inGame=false
assert(teams[#spawned][1]=='neutral' and teams[#spawned][2]==1,'team and count survive reload (UnitKeysV2)')
local f=assert(io.open(root..'/unit-keybinds.tsv','wb'));f:write('UnitKeysV1\t9\n'..a..'\t82\t0\n');f:close()
local legacy=Keys.new(options);legacy:start();assert(legacy:isBound(82),'V1 files still load')
legacy:dispatch(82,0);inGame=true;table.remove(queue,1)();inGame=false
assert(spawned[#spawned]==a and teams[#spawned][1]==nil and teams[#spawned][2]==nil,'a V1 key follows the current selection')
reloaded:silence();legacy:silence();restored:silence()
print('unit_keybinds: PASS (unbound defaults, native registration readback, remap cancellation, persistence, conflicts, shared slots, unload, per-unit team/count, V1 compatibility)')
