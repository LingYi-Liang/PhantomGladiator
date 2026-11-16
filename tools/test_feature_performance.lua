package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local saved=arg;arg={saved[1],'fixture'}
local make=assert(loadfile('tools/test_combat_continuity.lua'))();arg=saved
local h=make();h.options.deferTargetHold=true;h.actor.ai.CurrentStateTag={TagName='AI.State.Combat'}
local reads=0
for _,o in ipairs({h.actor,h.boss,h.actor.Controller,h.actor.Controller.BrainComponent})do
    local native=o.GetFullName;o.GetFullName=function(self)reads=reads+1;return native(self)end
end
for _=1,200 do h.c:beginTick(h.members,true);h.c:maintain(h.actor,h.boss)end
print('MEASURE 200 stable Combat ticks identity reads='..reads..'; forced combat='..h.engage..'; new hatred='..h.add)
assert(reads<=3200 and h.engage==0 and h.add==0,'read-only stable combat must avoid duplicate transaction validation')
local Policy=require('execution_policy');local scans=0
local p=Policy.new({configured=function()return false end,rule=function()error('default must not look up a rule')end})
local actor={IsValid=function()scans=scans+1;return true end}
for _=1,2000 do p:sync({{actor=actor,team='blue'}},true);assert(p:allow(actor,actor,true))end
assert(scans==0 and p.draws==0,'default execution policy must be zero-native-query')
print('feature performance: PASS stable intent read budget, zero default policy queries; no game accessed')
