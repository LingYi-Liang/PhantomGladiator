package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Timer=require('hun_combat_timer')
local now,calls,cancels,ticks=0,{},{},0
local fail,reenter=true,false
local timer
local function tick()ticks=ticks+1 end
local function register(ms,fn)
    assert(ms==100);calls[#calls+1]=fn
    local id=#calls
    fn() -- UE can enter Lua before it returns the handle.
    if reenter then reenter=false;timer:stop();assert(timer:ensure(tick)) end
    if fail then return false end
    return id
end
timer=Timer.new(100,register,function(id)cancels[id]=true;calls[id]();return false end,function()return now end,function()end)
assert(not timer:ensure(tick));for i=1,100 do assert(not timer:ensure(tick)) end
assert(#calls==1 and ticks==0)
fail=false;now=1;assert(timer:ensure(tick));calls[1]();assert(ticks==0)
calls[2]();assert(ticks==1);timer:stop();assert(cancels[2] and ticks==1)
assert(timer:ensure(tick));calls[2]();calls[3]();assert(ticks==2)
timer:stop();reenter=true
assert(not timer:ensure(tick));assert(cancels[4] and not cancels[5])
calls[4]();assert(ticks==2);calls[5]();assert(ticks==3)
timer:stop();calls[5]();assert(ticks==3)
print('PASS registration acknowledgement, bounded retries, reentrant cancellation and generation ownership')
