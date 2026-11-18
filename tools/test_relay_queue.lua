local Queue=dofile('Mods/PhantomGladiator/Scripts/summon_queue.lua')
local function fixture()
    local h={now=0,files={},calls={},began=0,world='A',ready=true,state={blue_count=0,red_count=0,blue_unreadable=0,red_unreadable=0,battle_active=false},hp=137}
    local fs={open=function(path,mode)
        if mode=='w' and h.failSave then return nil end
        if mode=='r' and not h.files[path] then return nil end
        local value=h.files[path]
        return {read=function()return value end,write=function(_,s)value=s;return true end,close=function()if mode=='w' then h.files[path]=value end;return true end}
    end}
    h.options={path='fixture',io=fs,now=function()return h.now end,
        session=function()return {game_session=h.world,game_ready=h.ready}end,state=function()return h.state end,
        begin=function()h.began=h.began+1;h.state.battle_active=true;return {ok=true}end,
        pending=function(enabled,blue,red)h.pending={enabled,blue,red}end,
        spawn=function(path,team,n,profile)
            h.calls[#h.calls+1]={path=path,team=team,count=n,time=h.now,profile=profile}
            h.state[team..'_count']=(h.state[team..'_count'] or 0)+n
            return {ok=not h.failSpawn,uncertain=h.failSpawn,spawned_count=n,message='spawn verified'}
        end}
    h.q=Queue.new(h.options);h.q.enabled=true;h.q:sync(h.options.session())
    function h.tick(n)for _=1,n or 1 do h.now=h.now+0.25;h.q:tick()end end
    function h.mode(mode,blue,red)h.q.enabled=false;assert(h.q:configure(mode,250,blue or 1,red or 1).ok);h.q.enabled=true end
    return h
end
do
    local h=fixture();assert(h.q:configure('TIMED',1250,3,3).ok)
    assert(h.q:enqueue('A','blue',1).ok and h.q:enqueue('B','red',1).ok)
    h.q:tick();h.now=1.249;h.q:tick();assert(#h.calls==1);h.now=1.25;h.q:tick();assert(#h.calls==2)
    h.failSave=true;assert(not h.q:configure('TIMED',50,3,3).ok and h.q.intervalMs==1250)
    h.failSave=false;local loaded=Queue.new(h.options);assert(loaded.intervalMs==1250 and not loaded.enabled)
    for _,bad in ipairs({0,49,600001,0/0,math.huge})do assert(not h.q:configure('TIMED',bad,3,3).ok)end
    h.q:cancel('stop');assert(h.q.nextAt==h.now)
end
do
    local h=fixture();h.mode('SINGLE')
    for _,v in ipairs({{'blueA','blue'},{'redA','red'},{'blueB','blue'},{'redB','red'}})do assert(h.q:enqueue(v[1],v[2],1).ok)end
    h.tick(3);assert(#h.calls==0,'relay reserves stay unspawned before start')
    assert(h.q:startRelay().ok);h.tick(4)
    assert(#h.calls==2 and h.began==1 and h.q.relayStarted)
    h.tick(20);assert(#h.calls==2,'living starters prevent reserve entry')
    h.state.red_count=0;h.state.red_unreadable=1;h.tick(8);assert(#h.calls==2,'unreadable does not mean dead')
    h.state.red_unreadable=0;h.tick(4)
    assert(#h.calls==3 and h.calls[3].path=='redB','blocked blue FIFO must not stall a ready red reserve')
    assert(h.began==1 and h.hp==137,'continuing a relay must not restart battle preparation or refill the survivor')
    h.state.red_count=0;h.tick(3);assert(not h.q.relayStarted and #h.calls==3 and #h.q.jobs==1,'an exhausted side ends the match; winner reserves stay waiting')
end
do
    local h=fixture();h.mode('WAVE',2,2)
    for _,v in ipairs({{'blueA','blue',1},{'blueB','blue',1},{'blueC','blue',2},{'redA','red',1},{'redB','red',1},{'redC','red',3}})do assert(h.q:enqueue(table.unpack(v)).ok)end
    assert(h.q:startRelay().ok);h.tick(8)
    assert(h.state.blue_count==2 and h.state.red_count==2 and h.began==1)
    h.state.red_count=1;h.tick(10);assert(#h.calls==4,'one remaining member keeps the current wave active')
    h.state.red_count=0;h.tick(5)
    assert(h.state.red_count==2 and #h.calls==6 and h.calls[5].path=='redC' and h.calls[6].path=='redC')
    assert(h.q:reserves().red==1 and h.q:reserves().blue==2 and h.began==1)
    h.q:cancel('stop');h.tick(8);assert(#h.calls==6 and not h.q.relayStarted and h.pending[2]==0 and h.pending[3]==0)
end
do
    local h=fixture();h.mode('WAVE',3,3)
    h.q:enqueue('B','blue',1);h.q:enqueue('R','red',1);assert(h.q:startRelay().ok);h.tick(4)
    h.q:enqueue('late','red',2);h.tick(8);assert(#h.calls==2,'a partial wave is fixed when it begins; late entries wait for the next wave')
    h.world='B';h.q:sync(h.options.session());h.tick(3);assert(#h.q.jobs==0 and not h.q.relayStarted and #h.calls==2)
end
do
    local h=fixture();h.mode('SINGLE');h.state.blue_count=2;h.state.red_count=1;h.state.battle_active=true
    h.q:enqueue('next','red',1);assert(h.q:startRelay().ok);h.tick(4)
    assert(#h.calls==0 and h.began==0,'existing combatants are the first wave and are not re-prepared')
    h.state.red_count=0;h.failSpawn=true;h.tick(5)
    assert(#h.calls==1 and #h.q.jobs==0 and not h.q.relayStarted,'uncertain generation cancels the remainder, never retries')
end
do
    local h=fixture();h.mode('SINGLE')
    local first={revision=12,resources={medicine_count=2}}
    assert(h.q:enqueue('Hun','blue',2,h.q:epoch(),first).ok)
    first.revision=13;first.resources.medicine_count=9
    assert(h.q:enqueue('Hun','red',1,h.q:epoch(),first).ok)
    assert(h.q:startRelay().ok);h.tick(6)
    assert(h.calls[1].profile.revision==12 and h.calls[2].profile.revision==13)
    h.state.blue_count=0;h.tick(6)
    assert(#h.calls==3 and h.calls[3].profile.resources.medicine_count==2 and h.calls[3].count==1)
    h.q:cancel('stop');h.tick(2);assert(#h.calls==3)
end
print('relay_queue: PASS (saved interval, single and mixed team waves, unreadable health, survivor preservation, late reserves, scene cancellation and failure)')

-- State observation and battle start do not wait for the next generation deadline.
do
    local h=fixture();h.mode('SINGLE');assert(h.q:configure('SINGLE',10000,1,1).ok)
    h.q:enqueue('B','blue',1);h.q:enqueue('R','red',1)
    assert(h.q:startRelay().ok);h.q:tick();h.now=10;h.q:tick()
    assert(#h.calls==2 and h.began==0)
    h.now=10.025;h.q:tick()
    assert(h.began==1,'ready starters must not idle through another ten-second generation interval')
end
do
    local h=fixture();h.mode('SINGLE');assert(h.q:configure('SINGLE',10000,1,1).ok)
    h.state.blue_count=1;h.state.battle_active=true
    h.q:enqueue('R1','red',1);h.q:enqueue('R2','red',1);assert(h.q:startRelay().ok)
    h.q:tick();h.state.red_count=0;h.now=0.25;h.q:tick()
    h.now=10.25;h.q:tick()
    assert(#h.calls==2,'death during cooldown must not add a second full interval before replacement')
end
do
    local h=fixture();h.mode('SINGLE');assert(h.q:configure('SINGLE',600000,1,1).ok)
    local observations=0
    h.options.state=function()observations=observations+1;return h.state end
    h.q:enqueue('B','blue',1);h.q:enqueue('R','red',1);assert(h.q:startRelay().ok);h.q:tick()
    observations=0
    for i=1,1000 do h.now=i*0.025;h.q:tick()end
    assert(#h.calls==1 and observations<=101,'cooldown observation must not become a 40-Hz native state scan')
    print('relay cooldown fixture: ticks=1000 state_reads='..observations..' spawned='..#h.calls)
    h.world='B';h.now=25.25;h.q:tick()
    assert(#h.q.jobs==0 and not h.q.relayStarted,'a scene change cancels reserves even during a long cooldown')
end
-- A retired spawn cannot apply its old cooldown to the newly cancelled/reconfigured generation.
do
    local h=fixture();h.mode('WAVE',100,100);assert(h.q:configure('WAVE',50,100,100).ok)
    local observations=0;h.options.state=function()observations=observations+1;return h.state end
    h.q:enqueue('B','blue',100);h.q:enqueue('R','red',100);assert(h.q:startRelay().ok);h.q:tick()
    observations=0
    for i=1,100 do h.now=i*0.025;h.q:tick()end
    assert(observations<=#h.calls+1,'a filling wave must not repeat the full native scan between short-interval spawns')
    print('relay short-gap fixture: ticks=100 state_reads='..observations..' spawned='..#h.calls)
end
do
    local h=fixture();h.mode('TIMED');assert(h.q:configure('TIMED',600000,1,1).ok)
    h.q:enqueue('old','blue',1)
    h.options.spawn=function()
        h.q:cancel('reentrant cancellation')
        assert(h.q:configure('TIMED',50,1,1).ok)
        return {ok=true,spawned_count=1}
    end
    h.q:tick()
    assert(h.q.nextAt==h.now and h.q.lastDone==nil,'retired generation must not rewrite the current deadline')
end
print('relay_queue: PASS (control polling during cooldown and retired-spawn isolation)')
do
    local h=fixture();h.mode('SINGLE')
    h.q:enqueue('B','blue',1);h.q:enqueue('R','red',1)
    h.options.begin=function()h.q:cancel('cancelled during begin');return {ok=true}end
    assert(h.q:startRelay().ok)
    h.tick(4)
    assert(not h.q.relayStarted and #h.q.jobs==0 and h.q.initial==nil,
        'cancelled battle start cannot access retired waves or restore relay state')
end
print('relay_queue: PASS (retired battle-start isolation)')
do
    local h=fixture();h.mode('SINGLE');h.q:cancel('relay enabled')
    h.q:enqueue('neutral','neutral',1);h.q:tick()
    assert(#h.calls==1 and not h.q.relayStarted,'unassigned jobs still run while blue/red wait for relay start')
end
print('relay_queue: PASS (unassigned jobs before relay start)')
