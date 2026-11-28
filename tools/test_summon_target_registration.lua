package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Registration=require('summon_target_registration')
FName=function(value)return value end

local function fixture()
    local h={time=0,onThread=true,available=true,reads=0,lines={},targets={},readable=true}
    local serial=0
    local function object(name,outer)
        serial=serial+1
        local id=serial
        local t={alive=true,name=name,outer=outer}
        function t:IsValid()return self.alive end
        function t:GetAddress()assert(self.alive);return id end
        function t:GetFullName()assert(self.alive);return self.name end
        function t:GetOuter()assert(self.alive);return self.outer end
        return t
    end
    h.world=object('World')
    h.other=object('OtherWorld')
    h.at=h.world
    h.sub=object('TargetingWorldSubsystem',h.world)
    function h.sub:GetTargetsByTag(tag,exact,out)
        assert(self.alive and tag.TagName=='Targeting.Target.Combat' and exact)
        h.reads=h.reads+1
        if h.readable then
            out.OutTargets={}
            for actor in pairs(h.targets)do out.OutTargets[#out.OutTargets+1]=actor end
        end
    end
    h.registration=Registration.new({world=function()return h.at end,clock=function()return h.time end,
        inGameThread=function()return h.onThread end,hp=function(a)return a.hp end,
        isDestroying=function(a)assert(a.alive);return a.destroying==true end,
        subsystem=function()return h.available and h.sub or nil end,
        log=function(line)h.lines[#h.lines+1]=line end})
    function h:actor(name,quiet)
        local pawn=object(name,h.world)
        pawn.hp,pawn.calls=100,0
        if quiet then
            pawn.Spawner=object('BP_AISpawner for '..name,h.world)
            pawn.Spawner.InitialSpawn=false
            pawn.Spawner.location={X=100,Y=200,Z=300}
        end
        function pawn:CompleteSpawnAI_Event(p)
            assert(self.alive and self==p and self.begun and h.onThread)
            assert(self.Spawner and self.Spawner.InitialSpawn==false)
            self.calls=self.calls+1
            if self.throws then error('callback unavailable') end
            if not self.wait then h.targets[self]=true end
        end
        return pawn
    end
    function h:finishSpawn(actor)
        actor.begun=true
        -- BP_NPC_Base binds CompleteSpawnAI when it sees a spawner. Its direct branch handles other pawns.
        if not actor.Spawner then h.targets[actor]=true
        else self.registration:enqueue(actor,actor.Spawner,self.world) end
    end
    function h:tick()
        self.time=self.time+1
        self.registration:tick()
    end
    return h
end

local function test(label,fn)
    fn(fixture())
    print('ok - '..label)
end

test('Lei Dang, the rider and the team each receive their own completion',function(h)
    local lei=h:actor('LeiDang_P2',true)
    local rider=h:actor('JingYe',true)
    local horse=h:actor('JingYe_Horse',false)
    local ordinary=h:actor('YuDing',false)
    local disciple=h:actor('HuaShan_White',true)
    local group={members={disciple}}
    disciple.Spawner.SpawnedAI=disciple;disciple.MobGroup=group
    local anchor=lei.Spawner
    local at=anchor.location
    rider.DrivingVehicle=horse;horse.Unselectable=true
    for _,a in ipairs({lei,rider,ordinary,disciple})do h:finishSpawn(a) end
    assert(h.targets[ordinary] and not h.targets[lei] and not h.targets[rider] and not h.targets[disciple])
    h:tick()
    assert(h.targets[lei] and h.targets[rider] and h.targets[disciple],'quiet spawner skips native registration')
    assert(lei.calls==1 and rider.calls==1 and disciple.calls==1 and horse.calls==0 and ordinary.calls==0)
    assert(lei.Spawner==anchor and anchor.location==at and at.Z==300 and anchor.SpawnedAI==nil)
    assert(rider.DrivingVehicle==horse and horse.Unselectable and not h.targets[horse])
    assert(disciple.Spawner.SpawnedAI==disciple and disciple.MobGroup==group)
    assert(h.reads==1 and #h.lines==0,'the first batch only reads once')
    h:tick()
    assert(h.reads==2 and #h.lines==3 and h.lines[1]:find('战斗目标登记读回=true',1,true))
    h.targets[rider]=nil
    h:tick()
    assert(h.reads==2 and rider.calls==1,'a later native unregister is respected')
end)

test('an already registered target skips its completion callback',function(h)
    local a=h:actor('NativeAlreadyAdded',true)
    h:finishSpawn(a);h.targets[a]=true;h:tick()
    assert(a.calls==0 and h.reads==1 and h.lines[1]:find('回调调用=false 战斗目标登记读回=true',1,true))
end)

test('an unready subsystem, thread and pawn yield until spawn is ready',function(h)
    local a=h:actor('LateRegistry',true)
    h:finishSpawn(a);h.available=false;h:tick()
    assert(a.calls==0)
    h.available=true;h.onThread=false;h:tick();assert(a.calls==0)
    h.onThread=true;a.hp=nil;h:tick();assert(a.calls==0)
    a.hp=100;h:tick()
    assert(a.calls==1 and h.targets[a])
end)

test('an absent registration allows a rejected callback to retry',function(h)
    local a=h:actor('Retry',true)
    h:finishSpawn(a);a.throws=true;h:tick()
    assert(a.calls==1 and not h.targets[a])
    a.throws=false;h:tick();assert(a.calls==2 and h.targets[a])
    h:tick();assert(a.calls==2)
end)

test('unavailable target-list output only invokes a successful callback once',function(h)
    local a=h:actor('Unreadable',true)
    h:finishSpawn(a);h.readable=false;h:tick();h:tick()
    assert(a.calls==1 and h.targets[a])
    h.readable=true;h:tick()
    assert(a.calls==1 and #h.lines==1 and h.lines[1]:find('战斗目标登记读回=true',1,true))
end)

test('a callback with no matching entry is bounded',function(h)
    local a=h:actor('MissingReadback',true)
    h:finishSpawn(a);a.wait=true
    for _=1,12 do h:tick() end
    assert(a.calls==6 and not h.targets[a] and #h.lines==1)
    assert(h.lines[1]:find('战斗目标登记读回=false',1,true))
end)

test('a cleanup request cancels just that pawn even when destruction is delayed',function(h)
    local rider=h:actor('JingYeWaitingForCleanup',true)
    local other=h:actor('AnotherRider',true)
    h:finishSpawn(rider);h:finishSpawn(other)
    h.registration:cancel(rider)
    assert(rider.alive and not rider.destroying,'the engine has not yet destroyed the rider')
    h:tick()
    assert(rider.calls==0 and not h.targets[rider])
    assert(other.calls==1 and h.targets[other])
end)

test('cleanup and travel cancel a pending registration',function(h)
    local dead=h:actor('Dead',true)
    local destroyed=h:actor('Destroyed',true)
    local replaced=h:actor('ReplacedBinding',true)
    local moved=h:actor('Moved',true)
    local renamed=h:actor('DifferentInstance',true)
    for _,a in ipairs({dead,destroyed,replaced,moved,renamed})do h:finishSpawn(a) end
    dead.hp=0;destroyed.destroying=true;replaced.Spawner=nil;moved.outer=h.other;renamed.name='ReusedAddress'
    h:tick()
    assert(h.reads==0 and dead.calls==0 and destroyed.calls==0 and replaced.calls==0 and moved.calls==0 and renamed.calls==0)
    local travel=h:actor('OldWorld',true)
    h:finishSpawn(travel);h.at=h.other;h:tick();h.at=h.world;h:tick()
    assert(travel.calls==0 and h.reads==0)
end)

test('destruction before the shared readback never re-registers the pawn',function(h)
    local a=h:actor('JingYeLeavingWhileAwaiting',true)
    h:finishSpawn(a);h:tick()
    assert(a.calls==1 and h.targets[a] and h.reads==1)
    h.targets[a]=nil;a.destroying=true
    h:tick();h:tick()
    assert(a.calls==1 and h.reads==1 and not h.targets[a])
end)

test('reuse of a pending actor address replaces the old attempt',function(h)
    local a=h:actor('PreviousPawn',true)
    h:finishSpawn(a)
    a.name='NextPawn'
    h:finishSpawn(a)
    h:tick();h:tick()
    assert(a.calls==1 and h.targets[a] and h.lines[1]:find('NextPawn',1,true))
end)

test('large batches share a registry snapshot with the previous batch',function(h)
    local actors={}
    for i=1,17 do actors[i]=h:actor('Formation pawn '..i,true);h:finishSpawn(actors[i]) end
    h:tick()
    local count=0;for _ in pairs(h.targets)do count=count+1 end
    assert(count==12 and h.reads==1)
    h:tick()
    for _,a in ipairs(actors)do assert(h.targets[a] and a.calls==1) end
    assert(h.reads==2 and #h.lines==12,'new writes and previous confirmations use the same scan')
    h:tick();h:tick()
    assert(h.reads==3 and #h.lines==17)
end)
print('summon_target_registration: all tests passed')
