local Arena=dofile(arg[1] or 'Mods/PhantomGladiator/Scripts/arena_controller.lua')
local function harness()
    local h={actors={},clock=0,unsafe=0,attacks=0}
    local selected='/Game/BP_Test.BP_Test_C'
    local catalog={registerPath=function()return {}end,select=function()return {}end,resolveSelected=function()return {live=true}end,selected=function()return {path=selected}end}
    h.options={catalog=catalog,maxUnits=0,canSpawn=function()return true end,valid=function(a)return a and a.live==true end,
        name=function(a)return a.name end,actorKey=function(a)return a.id end,hp=function(a)return a.hp end,
        now=function()return h.clock end,combatReady=function()return true end,inCombat=function()return true end,
        phaseBusy=function()return false end,untargetable=function(a)return a.blocked==true end,
        getPlayer=function()return {live=true}end,getWorld=function()return {live=true}end,
        getLocation=function()return {X=0,Y=0,Z=100}end,getForward=function()return {X=1,Y=0,Z=0}end,
        spawnClass=function()local a={live=true,hp=100,id=tostring(#h.actors+1),name='Actor'..(#h.actors+1)};h.actors[#h.actors+1]=a;return a end,
        activate=function()return true end,setRelation=function()return true end,
        forceAttack=function(a,b)h.attacks=h.attacks+1;if not a.live or a.hp<=0 or not b.live or b.hp<=0 or b.blocked then h.unsafe=h.unsafe+1 end;return true end,
        restore=function()return true end,destroy=function(a)a.live=false end}
    h.arena=Arena.new(h.options)
    function h:spawn(team,n)local result=self.arena:spawn(selected,team,n);assert(result.ok,result.message)end
    return h
end
local only=arg[2]
if not only or only=='late-attacker' then
    local h=harness();h:spawn('blue',1);h:spawn('red',1);assert(h.arena:start().ok)
    h:spawn('blue',1);h:spawn('red',1)
    local first,late=h.actors[3],h.actors[4];local original=h.options.forceAttack
    h.options.forceAttack=function(a,b)local result=original(a,b);if a==first then late.hp=0 end;return result end
    h.arena:tickReinforcements()
    print('late dead attacker native commands='..h.unsafe)
    assert(h.unsafe==0,'an actor killed by an earlier native callback cannot receive an attack command')
end
if not only or only=='late-target' then
    for _,changed in ipairs({'dead','blocked'})do
        local h=harness();h:spawn('blue',1);h:spawn('red',1);assert(h.arena:start().ok);h:spawn('blue',2)
        local first,enemy=h.actors[3],h.actors[2];local original=h.options.forceAttack
        h.options.forceAttack=function(a,b)local result=original(a,b);if a==first then if changed=='dead' then enemy.hp=0 else enemy.blocked=true end end;return result end
        h.arena:tickReinforcements();print('late '..changed..' target native commands='..h.unsafe)
        assert(h.unsafe==0,'target availability is live, not the early-tick candidate snapshot')
    end
end
if not only or only=='cleared' then
    local h=harness();h:spawn('blue',1);h:spawn('red',1);assert(h.arena:start().ok);h:spawn('blue',2)
    local trigger=h.actors[3];local original=h.options.forceAttack
    h.options.forceAttack=function(a,b)if a==trigger then assert(h.arena:stop().ok);return false end;return original(a,b)end
    h.arena:tickReinforcements();print('commands after reentrant cleanup='..h.unsafe)
    assert(h.unsafe==0 and h.arena:status().owned_records==0,'a retired roster cannot keep sending native commands')
end
if not only or only=='self-retired' then
    for _,retire in ipairs({'forceAttack','holdTarget'})do
        local h=harness();h:spawn('blue',1);h:spawn('red',1);assert(h.arena:start().ok);h:spawn('blue',1)
        local watched=h.actors[3]
        h.options.releaseLock=function(a)if a.hp<=0 then h.unsafe=h.unsafe+1 end;return true end
        h.options[retire]=function(a)if a==watched then a.hp=0 end;return true end
        h.arena:tickReinforcements();assert(h.unsafe==0,'an earlier action may retire its own actor: '..retire)
    end
end
if not only or only=='index' then
    local h=harness();for _=1,5 do h:spawn('blue',100)end
    local last=h.actors[#h.actors];assert(h.arena:actorOf(last.id)==last)
    local ticks=0;debug.sethook(function()ticks=ticks+1 end,'',100)
    for _=1,2000 do assert(h.arena:actorOf(last.id)==last)end
    debug.sethook();print('500 actors, 2000 hot lookups: 100-instruction samples='..ticks)
    assert(ticks<10000,'hot actor lookup must not traverse every owned record')
    assert(h.arena:stop().ok and h.arena:actorOf(last.id)==nil,'cleanup invalidates the index')
    h:spawn('red',1);local fresh=h.actors[#h.actors];assert(h.arena:actorOf(fresh.id)==fresh)
    local unknown=true
    h.options.actorKey=function(a)if a==fresh and unknown then return nil end;return a.id end
    -- A roster notification retires the old index; an unreadable new identity can recover without another mutation.
    h:spawn('red',1);local pending=h.actors[#h.actors]
    h.options.actorKey=function(a)if a==pending and unknown then return nil end;return a.id end
    assert(h.arena:actorOf(pending.id)==nil)
    unknown=false;assert(h.arena:actorOf(pending.id)==pending)
    fresh.live=false;h.arena:members();assert(h.arena:actorOf(fresh.id)==nil,'pruning invalidates retired index entries')
end
print('controller_roster: PASS (live availability, reentrant cleanup, bounded hot lookup)')
