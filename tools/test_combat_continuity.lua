package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local C=arg[1]and assert(loadfile(arg[1]))()or require('combat_continuity')
local id=0
local function obj(label,outer)
    id=id+1;local key=id
    local o={live=true,label=label,outer=outer}
    function o:IsValid()return self.live end
    function o:GetAddress()assert(self.live);return key end
    function o:GetFullName()assert(self.live);return self.label end
    function o:GetOuter()assert(self.live);return self.outer end
    return o
end
local function fixture()
    FName=function(v)return v end
    local h={now=0,pause=0,resume=0,stop=0,engage=0,add=0,hates=true,journal={},logs={}}
    h.world=obj('World')
    local function actor(label,boss)
        local a=obj(label,h.world);a.hp=100;a.boss=boss;a.tags={};a.casting=false
        local asc=obj('ASC',a);function asc:GetGameplayTagCount(t)if h.unreadTags then error('unreadable')end;return a.tags[t.TagName]or 0 end
        a.AbilitySystemComponent=asc
        local mesh=obj('Mesh',a);local anim=obj('Anim',a)
        function mesh:GetAnimInstance()return anim end;function anim:IsAnyMontagePlaying()return a.casting end;a.Mesh=mesh
        local pc=obj('Controller',h.world);local brain=obj('Brain',pc);brain.paused=false;pc.Pawn=a;brain.AIOwner=pc
        function brain:IsPaused()return self.paused end
        function brain:IsRunning()return self.running~=false end
        function pc:StopMovement()h.stop=h.stop+1;self.move=0 end
        function pc:GetMoveStatus()return self.move or 0 end
        pc.BrainComponent=brain;a.Controller=pc
        a.ai=obj('AI',pc);a.ai.CurrentStateTag={TagName='AI.State.Idle'}
        a.hm=obj('Hatred',a)
        return a
    end
    h.actor=actor('Minion',false);h.boss=actor('Boss',true);h.ally=actor('Ally',false)
    h.members={{actor=h.actor,team='blue'},{actor=h.boss,team='red'},{actor=h.ally,team='blue'}}
    h.lib=obj('Library')
    function h.lib:PauseLogic(brain)h.pause=h.pause+1;if not h.rejectPause then brain.paused=true end end
    function h.lib:ResumeLogic(brain)h.resume=h.resume+1;if not h.rejectResume then brain.paused=false end end
    h.options={clock=function()return h.now end,world=function()return h.world end,hp=function(a)assert(a.live);return a.hp end,
        aiOf=function(a)return a.ai end,hatredOf=function(a)return a.hm end,hates=function()return h.hates end,
        addHatred=function()h.add=h.add+1;h.hates=true;return true end,
        ordinary=function(a)return not a.boss end,
        find=function()return h.lib end,
        engage=function(a)h.engage=h.engage+1;a.ai.CurrentStateTag={TagName='AI.State.Combat'};return true end,
        holdTarget=function(a,b)h.held=b;return true end,
        track=function(key,restore)h.journal[key]=h.journal[key]or restore;return true end,
        log=function(s)h.logs[#h.logs+1]=s end}
    h.c=C.new(h.options);h.c:beginTick(h.members,true)
    function h:block()self.boss.tags['CharacterState.Unselectable']=1;self.c:beginTick(self.members,true)end
    return h
end
if arg[2]=='fixture'then return fixture,obj end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end
test('idle minion waits without changing boss AI or cancelling an ability',function()
    local h=fixture();h:block();assert(h.c:wait(h.actor,h.boss))
    assert(h.pause==1 and h.stop==1 and h.actor.Controller.BrainComponent.paused)
    assert(not h.boss.Controller.BrainComponent.paused and h.engage==0)
    for _=1,20 do h.c:wait(h.actor,h.boss)end;assert(h.pause==1 and h.stop==1,'wait is paced')
end)
test('active montages, executing actors and bosses never enter idle wait',function()
    local h=fixture();h:block();h.actor.casting=true;assert(not h.c:wait(h.actor,h.boss))
    h.actor.casting=false;h.actor.tags['CharacterState.Hitreact.State.Executing']=1;assert(not h.c:wait(h.actor,h.boss))
    h.actor.tags={};h.actor.boss=true;assert(not h.c:wait(h.actor,h.boss)and h.pause==0)
end)
test('combat-state minions keep their current action and repair only missing hatred',function()
    local h=fixture();h.actor.ai.CurrentStateTag={TagName='AI.State.Combat'};h.hates=false;h.actor.casting=true
    assert(h.c:maintain(h.actor,h.boss)and h.add==1 and h.engage==0)
    for _=1,50 do assert(h.c:maintain(h.actor,h.boss))end;assert(h.add==1 and h.engage==0)
end)
test('protection ending restores only owned pause and engages idle actor once',function()
    local h=fixture();h:block();assert(h.c:wait(h.actor,h.boss));h.boss.tags={};h.c:beginTick(h.members,true);h.hates=false
    assert(h.c:maintain(h.actor,h.boss)and h.resume==1 and h.engage==1 and h.add==1)
    assert(h.c:maintain(h.actor,h.boss)and h.engage==1)
end)
test('a pause owned by the game or another mod is never resumed or forced',function()
    local h=fixture();h.actor.Controller.BrainComponent.paused=true;h:block()
    assert(not h.c:wait(h.actor,h.boss));assert(h.c:resume(h.actor))
    h.boss.tags={};h.c:beginTick(h.members,true);h.c:maintain(h.actor,h.boss)
    assert(h.resume==0 and h.engage==0 and h.actor.Controller.BrainComponent.paused)
end)
test('failed restoration stays pending and retries with a deadline',function()
    local h=fixture();h:block();h.c:wait(h.actor,h.boss);h.rejectResume=true
    assert(not h.c:resume(h.actor));for _=1,20 do assert(not h.c:resume(h.actor))end
    assert(h.resume==1 and h.c:status().pending==1)
    h.rejectResume=false;h.now=1.1;assert(h.c:resume(h.actor)and h.c:status().pending==0)
end)
test('death and stopping restore waiting brains through normal sync and the journal',function()
    local h=fixture();h:block();h.c:wait(h.actor,h.boss);h.boss.hp=0;h.c:beginTick(h.members,true)
    assert(not h.actor.Controller.BrainComponent.paused)
    h.boss.hp=100;h.c:beginTick(h.members,true);h.c:wait(h.actor,h.boss)
    for _,restore in pairs(h.journal)do assert(restore())end
    assert(not h.actor.Controller.BrainComponent.paused)
end)
test('unknown tags, wrong teams and foreign worlds do not acquire a pause',function()
    local h=fixture();h.unreadTags=true;assert(not h.c:wait(h.actor,h.boss))
    h.unreadTags=false;h.ally.tags['CharacterState.Unselectable']=1;assert(not h.c:wait(h.actor,h.ally))
    h:block();h.boss.outer=obj('ForeignWorld');assert(not h.c:wait(h.actor,h.boss)and h.pause==0)
end)
test('world and controller replacement do not resume a different brain',function()
    local h=fixture();h:block();h.c:wait(h.actor,h.boss);local old=h.actor.Controller.BrainComponent
    local replacement=obj('NewBrain',h.actor.Controller);replacement.AIOwner=h.actor.Controller;replacement.paused=true
    function replacement:IsPaused()return self.paused end
    h.actor.Controller.BrainComponent=replacement;assert(h.c:resume(h.actor));assert(h.resume==0 and replacement.paused)
    h.world=obj('NextWorld');h.c:beginTick({},false);assert(h.resume==0 and old.paused)
end)
test('temporarily unreadable world or actor identity retains restoration ownership',function()
    local h=fixture();h:block();h.c:wait(h.actor,h.boss)
    local w=h.world;h.world=nil;assert(not h.c:resume(h.actor)and h.c:status().pending==1)
    h.world=w;local get=h.actor.GetFullName;h.actor.GetFullName=function()error('temporary identity read')end
    assert(not h.c:resume(h.actor)and h.c:status().pending==1)
    h.actor.GetFullName=get;assert(h.c:resume(h.actor)and not h.actor.Controller.BrainComponent.paused)
end)
test('a protected source retains its original phase targets and hatred handling',function()
    local h=fixture();h.boss.tags['CharacterState.Unselectable']=1;h.c:beginTick(h.members,true);h.hates=false
    assert(not h.c:maintain(h.boss,h.actor)and h.add==0 and h.engage==0)
end)
test('rapid protection cycles reuse one restore lease without carrying a prior deadline',function()
    local h=fixture()
    for i=1,30 do
        h.now=i*0.05;h:block();assert(h.c:wait(h.actor,h.boss),'each new window acquires its own wait immediately')
        h.boss.tags={};h.c:beginTick(h.members,true);assert(h.c:resume(h.actor),'ending the window restores immediately')
    end
    local count=0;for _ in pairs(h.journal)do count=count+1 end
    assert(count==1 and h.pause==30 and h.resume==30 and h.c:status().pending==0)
end)
test('an already stopped native brain is not claimed or restarted',function()
    local h=fixture();h.actor.Controller.BrainComponent.running=false;h:block()
    assert(not h.c:wait(h.actor,h.boss)and h.pause==0)
    h.boss.tags={};h.c:beginTick(h.members,true);h.c:maintain(h.actor,h.boss)
    assert(h.engage==0 and h.resume==0)
end)
test('fall-recovery blocking does not suppress the existing unstick opportunity',function()
    local h=fixture();h.actor.tags['AI.DisableCombatAI']=1
    assert(not h.c:actionBusy(h.actor),'fall blocking is not an active montage or execution')
    h.c:maintain(h.actor,h.boss);assert(h.engage==0,'the fall safety is repaired before combat re-entry')
end)
test('the native hatred gate alone preserves a protected opponent',function()
    local h=fixture();h.boss.hm.CanBeHatredNow=false;h.c:beginTick(h.members,true)
    assert(h.c:protected(h.boss)==true and h.c:wait(h.actor,h.boss))
    h.boss.hm.CanBeHatredNow=true;h.c:beginTick(h.members,true)
    assert(h.c:protected(h.boss)==false and h.c:maintain(h.actor,h.boss))
end)
test('leaving and rejoining the roster cannot reuse a completed restore callback',function()
    local h=fixture();h:block();h.c:wait(h.actor,h.boss)
    h.c:beginTick({},false);assert(not h.actor.Controller.BrainComponent.paused)
    h.c:beginTick(h.members,true);h.c:wait(h.actor,h.boss)
    assert(h.actor.Controller.BrainComponent.paused)
    for _,restore in pairs(h.journal)do assert(restore())end
    assert(not h.actor.Controller.BrainComponent.paused,'a new lease needs its own journal entry')
end)
print('combat continuity: PASS '..n..' native-boundary ownership/phase/restore checks; no game accessed')
