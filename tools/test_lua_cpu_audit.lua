-- Controller work budgets measured at real call boundaries, with no game access.
local source,only=arg[1],arg[2]
local continuitySource=arg[3]
local saved=arg;arg={source,'fixture'}
local fixture=assert(loadfile('tools/test_arena_controller.lua'))();arg=saved
local function upvalue(fn,wanted)
    for i=1,100 do local key,value=debug.getupvalue(fn,i);if not key then break end;if key==wanted then return value end end
    error('missing fixture seam '..wanted)
end
local function setup()
    local h={now=0,calls=0,waits=0}
    h.f=fixture({maxUnits=0,now=function()return h.now end,
        untargetable=function(a)return a.protected==true end,
        actionBusy=function(a)return a.casting==true end,
        waitForTarget=function()h.waits=h.waits+1;return true end,
        resumeIntent=function()return true end,
        forceAttack=function()h.calls=h.calls+1;return h.allow==true end})
    assert(h.f.arena:spawn(nil,'blue',50).ok and h.f.arena:spawn(nil,'red',50).ok)
    h.f.arena:start();assert(h.f.arena:status().battle_active)
    h.units=upvalue(h.f.arena.tickReinforcements,'units')
    return h
end
local n=0
local function test(id,fn)if only and only~=id then return end;fn();n=n+1;print('PASS '..id)end
test('retry_budget',function()
    local h=setup();local choose=upvalue(h.f.arena.tickReinforcements,'leastAttacked')
    local searches,instructions=0,0
    local calls=h.calls
    debug.sethook(function(event)
        if event=='count'then instructions=instructions+1000
        elseif debug.getinfo(2,'f').func==choose then searches=searches+1 end
    end,'c',1000)
    for _=1,20 do h.f.arena:tickReinforcements()end
    debug.sethook()
    print('MEASURE 100 failed assignments x 20 cooldown ticks: target searches='..searches..'; Lua instructions~'..instructions..'; new commands='..(h.calls-calls))
    assert(h.calls==calls,'cooldown must still suppress commands')
    assert(searches==0,'cooldown without a held protected opponent must not rescan the full target roster')
    h.allow=true;h.now=1;h.f.arena:tickReinforcements()
    assert(h.calls==calls+100,'each request must retry when its original deadline expires')
    for _,unit in ipairs(h.units)do assert(unit.assignedTarget and not unit.attackPending)end
end)
test('protected_wait_during_backoff',function()
    local h=setup();h.allow=true;h.now=1;h.f.arena:tickReinforcements()
    for _,u in ipairs(h.units)do
        if u.team=='red'then u.actor.protected=true end
        if u.team=='blue'then u.attackPending=true;u.attackRetryAt=99 end
    end
    h.now=1.1;local calls=h.calls;h.f.arena:tickReinforcements()
    assert(h.waits==50 and h.calls==calls,'protected targets still enter waiting even with an assignment retry deadline')
    for _,u in ipairs(h.units)do if u.team=='blue'then assert(u.assignedTarget and u.intentWaiting)end end
end)
test('death_and_stop_during_backoff',function()
    local h=setup();h.f.actors[51].hp=0;h.allow=true;h.now=1;h.f.arena:tickReinforcements()
    for _,u in ipairs(h.units)do assert(u.assignedTarget~=h.f.actors[51],'dead target cannot be selected when retry becomes due')end
    assert(h.f.arena:stop().ok);local calls=h.calls;h.now=99;h.f.arena:tickReinforcements();assert(h.calls==calls)
end)
test('inactive_intent_cost',function()
    package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
    local save=arg;arg={continuitySource,'fixture'}
    local make=assert(loadfile('tools/test_combat_continuity.lua'))();arg=save
    local h=make();local reads=0;local members={}
    for i=1,1000 do
        local actor={IsValid=function()return true end,GetAddress=function()return i end,
            GetFullName=function()reads=reads+1;return 'inactive actor '..i end}
        members[i]={actor=actor,team=i%2==0 and'blue'or'red'}
    end
    for _=1,200 do h.c:beginTick(members,false)end
    print('MEASURE 1000 prebattle members x 200 inactive ticks: identity reads='..reads)
    assert(reads==0,'inactive intent ownership must not build a discarded native identity index')
    h.c:beginTick(h.members,true);h:block();assert(h.c:wait(h.actor,h.boss))
    h.c:beginTick(h.members,false)
    assert(h.resume==1 and not h.actor.Controller.BrainComponent.paused,'inactive early path must still restore owned pauses')
end)
print('Lua CPU audit: PASS '..n..' retry-budget and continuity checks; no game accessed')
