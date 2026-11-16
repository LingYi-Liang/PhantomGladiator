local input,only=arg[1],arg[2]
local saved=arg;arg={input,'fixture'}
local fixture,stageCount=assert(loadfile('tools/test_arena_controller.lua'))();arg=saved
local passed=0
local function test(id,fn)if only and only~=id then return end;fn();passed=passed+1;print('PASS '..id)end
local function setup()
    local h={now=0,waits={},resumes={},maintenance=0,engages=0,native={}}
    h.f=fixture({maxUnits=0,now=function()return h.now end,
        untargetable=function(a)return a.protected==true end,phaseBusy=function(a)return a.phase==true end,
        actionBusy=function(a)return a.casting==true end,
        inCombat=function()return true,'AI.State.Combat'end,
        waitForTarget=function(a,b)assert(a~=b);h.waits[a]=b;return true end,
        resumeIntent=function(a)h.resumes[a]=(h.resumes[a]or 0)+1;h.waits[a]=nil;return true end,
        maintainTarget=function(a,b)assert(not b.protected);h.maintenance=h.maintenance+1;h.native[a]=b;return true end,
        engage=function()h.engages=h.engages+1;return true end})
    assert(h.f.arena:spawn(nil,'blue',50).ok and h.f.arena:spawn(nil,'red',1).ok and h.f.arena:start().ok)
    h.boss=h.f.actors[51]
    function h:units()
        for i=1,80 do local n,v=debug.getupvalue(self.f.arena.tickReinforcements,i);if n=='units'then return v end end
        error('diagnostic fixture cannot inspect assignment identity')
    end
    return h
end
test('hold_50',function()
    local h=setup();h.boss.protected=true;h.boss.phase=true
    for i=1,40 do h.now=i*0.05;h.f.arena:tickReinforcements()end
    local retained=0
    for _,u in ipairs(h:units())do if u.team=='blue'then
        assert(u.assignedTarget==h.boss,'temporary protection must not clear battle intent')
        assert(h.waits[u.actor]==h.boss,'each waiting attacker needs a scoped wait request');retained=retained+1
    end end
    assert(retained==50 and stageCount(h.f,'attack')==51 and h.engages==0)
    print('READ protected 50v1 intents='..retained..' forced attacks during window=0')
end)
test('resume_50',function()
    local h=setup();h.boss.protected=true;h.boss.phase=true;h.f.arena:tickReinforcements()
    h.boss.protected=false;h.boss.phase=false;h.now=0.05;h.f.arena:tickReinforcements()
    for i=1,50 do assert(h.native[h.f.actors[i]]==h.boss,'intent must repair on the first tick after protection, without the 8-second assignment backoff')end
    assert(h.engages==0,'actors already in Combat cannot be forced merely because protection ended')
end)
test('combat_target_lost',function()
    local h=setup();h.f.arena:tickReinforcements();h.now=1.1;h.native={};h.f.arena:tickReinforcements()
    for i=1,50 do assert(h.native[h.f.actors[i]]==h.boss,'Combat state alone is not proof that native hatred/target is intact')end
    assert(h.engages==0)
end)
test('drop_during_protection',function()
    local h=setup();h.boss.protected=true;h.now=0.1;h.f.arena:tickReinforcements()
    local a=h.f.actors[1];h.waits[a]=nil
    assert(h.f.arena:reengage(tostring(a))and h.waits[a]==h.boss,'a drop callback should hold the attacker rather than forget or force the protected target')
    assert(h.engages==0)
end)
test('no_interrupt',function()
    local h=setup();local a=h.f.actors[1];a.casting=true;h.boss.protected=true;h.boss.phase=true
    h.f.arena:tickReinforcements()
    assert(not h.waits[a]and not h.waits[h.boss],'active attacks and boss phases must not be paused by intent maintenance')
    a.casting=false;h.now=1;h.f.arena:tickReinforcements();assert(h.waits[a]==h.boss)
end)
test('stop',function()
    local h=setup();h.boss.protected=true;h.f.arena:tickReinforcements();assert(h.f.arena:stop().ok)
    local m=h.maintenance;h.now=10;h.f.arena:tickReinforcements()
    assert(h.maintenance==m and not h.f.arena:reengage(tostring(h.f.actors[1])))
end)
test('cycles',function()
    local h=setup()
    for round=1,20 do
        h.boss.protected=true;h.boss.phase=true
        for i=1,5 do h.now=h.now+0.05;h.f.arena:tickReinforcements()end
        for _,u in ipairs(h:units())do if u.team=='blue'then assert(u.assignedTarget==h.boss)end end
        h.boss.protected=false;h.boss.phase=false;h.now=h.now+0.05;h.f.arena:tickReinforcements()
        for i=1,50 do assert(h.native[h.f.actors[i]]==h.boss and not h.waits[h.f.actors[i]])end
    end
    assert(h.engages==0)
    print('READ 20 protected windows x 50 minions: retained=1000, active-action ForceIntoCombat=0')
end)
print('battle intent: PASS '..passed..' controller continuity checks; no game accessed')
