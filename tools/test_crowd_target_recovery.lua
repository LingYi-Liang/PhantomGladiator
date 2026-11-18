-- Real arena and combat-continuity entry points, with an observable native return-to-spawn path.
local source,only=arg[1],arg[2]
local original=arg;arg={source,'fixture'}
local arenaFixture=assert(loadfile('tools/test_arena_controller.lua'))()
arg={nil,'fixture'}
local combatFixture=assert(loadfile('tools/test_combat_continuity.lua'))()
arg=original
local function check(name,fn)
    if not only or only==name then fn();print('PASS '..name) end
end
check('alternate',function()
    local t,attempts,accepted=0,{},{}
    local f=arenaFixture({maxUnits=0,now=function()return t end})
    assert(f.arena:spawn(nil,'blue',12).ok and f.arena:spawn(nil,'red',3).ok)
    local reds={}
    for i=13,15 do reds[f.actors[i]]=true end
    f.options.forceAttack=function(a,b)
        if reds[a] then return true end
        attempts[a]=(attempts[a] or 0)+1
        if b~=f.actors[15] then return false end
        accepted[a]=b;return true
    end
    f.arena:start()
    local pet={name='spawned minion',hp=100,alive=true}
    assert(f.arena:adoptSummon(pet,f.actors[1],'/Game/Pet.Pet_C','summon list').ok)
    for tick=0,80 do t=tick*.25;f.arena:tickReinforcements() end
    local settled=0
    for a,b in pairs(accepted) do assert(b==f.actors[15] and attempts[a]<=3);settled=settled+1 end
    assert(settled==13 and accepted[pet],('only %d/13 ordinary fighters and summons found the accepting opponent'):format(settled))
end)
check('new_summon_home',function()
    local h=combatFixture()
    local parent,boss=h.ally,h.boss
    parent.name,parent.alive,boss.name,boss.alive='parent',true,'boss',true
    local lineup={parent,boss}
    local f=arenaFixture({maxUnits=0,now=function()return h.now end,untargetable=function(a)return a.protected==true end,
        spawnClass=function()return table.remove(lineup,1)end})
    assert(f.arena:spawn(nil,'blue',1).ok and f.arena:spawn(nil,'red',1).ok and f.arena:start().ok)
    f.options.waitForTarget=function(a,b)
        if a==h.actor then return h.c:wait(a,b) end
        return true
    end
    f.options.resumeIntent=function(a)return a~=h.actor or h.c:resume(h.actor) end
    h.actor.name='summoned fighter';h.actor.alive=true
    h.actor.Controller.move=3;boss.protected=true;h:block()
    local requests=0
    f.options.forceAttack=function(a,b)
        if a==h.actor then assert(b==boss and not b.protected and not h.actor.Controller.BrainComponent.paused);requests=requests+1 end
        return true
    end
    assert(f.arena:adoptSummon(h.actor,parent,'/Game/Pet.Pet_C','summon list').ok)
    for i=1,8 do h.now=i*.25;f.arena:tickReinforcements() end
    assert(h.pause==1 and h.stop>0 and h.actor.Controller.move==0 and requests==0,'new ordinary summon kept following its spawn-return path')
    boss.protected=false;h.boss.tags={};h.c:beginTick(h.members,true)
    h.now=2.25;f.arena:tickReinforcements()
    assert(h.resume==1 and requests==1,'summon must leave its own wait and engage on the next tick')
end)
check('pending_summon_at_start',function()
    for _,delay in ipairs({'health','controller'})do
        local f=arenaFixture();assert(f.arena:spawn(nil,'blue',2).ok and f.arena:spawn(nil,'red',2).ok)
        local pet={name='forming minion',alive=true}
        assert(f.arena:adoptSummon(pet,f.actors[1],'/Game/Pet.Pet_C','summon list').ok)
        local ready=false
        local function canRead(a,what)return a~=pet or ready or what~=delay end
        f.options.hp=function(a)if canRead(a,'health') then return 100 end end
        f.options.combatReady=function(a)return canRead(a,'controller') end
        local attacked={}
        f.options.forceAttack=function(a,b)
            assert(ready or (a~=pet and b~=pet))
            attacked[a]=true;return true
        end
        assert(f.arena:start().ok,'one forming summon prevented both sides from starting: '..delay)
        for _,a in ipairs(f.actors)do assert(attacked[a])end
        f.arena:tickReinforcements();assert(not attacked[pet])
        ready=true;f.arena:tickReinforcements();assert(attacked[pet])
    end
end)
check('confirmed_corpse',function()
    local f=arenaFixture({actionBusy=function(a)return a.busy==true end})
    assert(f.arena:spawn(nil,'blue',1).ok and f.arena:spawn(nil,'red',2).ok and f.arena:start().ok)
    local a,old,enemy=table.unpack(f.actors);old.hp=0
    f.arena:tickReinforcements()
    assert(f.arena:canReplaceDefeatedTarget(a,old,enemy))
    a.busy=true;assert(not f.arena:canReplaceDefeatedTarget(a,old,enemy));a.busy=false
    assert(not f.arena:canReplaceDefeatedTarget(a,{alive=true,hp=0},enemy))
    old.hp=100;assert(not f.arena:canReplaceDefeatedTarget(a,old,enemy))
end)
check('one_incomplete_summon',function()
    local t,ready,targets=0,false,{}
    local f=arenaFixture({maxUnits=0,now=function()return t end})
    assert(f.arena:spawn(nil,'blue',1).ok and f.arena:spawn(nil,'red',1).ok and f.arena:start().ok)
    local parent=f.actors[1];local missing={name='late faction',alive=true,hp=100}
    f.options.factionReady=function(actor)return actor~=missing or ready end
    f.options.setRelation=function(a,b)return ready or (a~=missing and b~=missing)end
    f.options.forceAttack=function(a,b)targets[a]=b;return true end
    assert(f.arena:adoptSummon(missing,parent,'/Game/Pet.Pet_C','summon list').ok)
    local peers={}
    for i=1,10 do
        local p={name='reinforcement '..i,alive=true,hp=100};peers[i]=p
        assert(f.arena:adoptSummon(p,parent,'/Game/Pet.Pet_C','summon list').ok)
    end
    for i=1,20 do t=i*.5;f.arena:tickReinforcements() end
    local n=0;for _,p in ipairs(peers)do if targets[p]==f.actors[2] then n=n+1 end end
    assert(n==10 and not targets[missing],('one missing faction component stalled %d/10 healthy summons'):format(10-n))
    ready=true;t=t+.5;f.arena:tickReinforcements();assert(targets[missing]==f.actors[2])
end)
