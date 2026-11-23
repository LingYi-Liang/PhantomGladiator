package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Supply=require('hun_supply')
local seq=0
local function obj(props)
    seq=seq+1
    local id=seq
    local v=props or {}
    function v:IsValid() return self.valid~=false end
    function v:GetAddress() return id end
    return v
end
local function fixture()
    local t={time=0,hp=20,max=100,events={},drinks=0,reborns=0,allows=true,inBattle=true,position=0}
    local r={name='魂',actor=obj(),intent={},loadout={resources={medicine_count='native_max',consume_medicine=true}}}
    t.r=r
    local tags={};local asc=obj{tags=tags,ActivatableAbilities={Items={}}}
    t.asc=asc
    r.actor.AbilitySystemComponent=asc
    function asc:GetGameplayTagCount(tag) return tags[tag.TagName] or 0 end
    function asc:BP_ApplyGameplayEffectToSelf(ge,level)
        if ge.path:find('GE_Medicine_Medicine_01',1,true) then
            assert(level==6); t.drinks=t.drinks+1;t.hp=t.hp+40
        elseif ge.path:find('GE_MedicineInHit_Cooldown',1,true) then
            tags['CharacterState.AbilityState.Medicine.InHitCooldown']=1
        elseif ge.path:find('GE_HeiMoShang_RebornCooldown',1,true) then
            tags['CharacterState.AbilityState.HeiMoShang.RebornCooldown']=1
        else error('unexpected '..ge.path) end
    end
    local settings=obj{}
    function settings:SpawnObject(c,actor) assert(actor==r.actor and c.path:find('Payload',1,true));return obj{} end
    local eventlib=obj{}
    function eventlib:SendGameplayEventToActor(actor,tag,p)
        assert(actor==r.actor and p.Target==actor and p.Instigator==actor)
        t.events[#t.events+1]=tag.TagName
        if tag.TagName=='GameplayEvent.Medicine.PreActivate' then
            assert(p.OptionalObject['Use Count']==1)
            if t.interruptOnSip then t.module:interrupt(r) end
            if t.free then p.OptionalObject['Use Count']=0 end
        end
    end
    local anim=obj{
        Montage_IsPlaying=function(_,m) return t.playing==m end,
        Montage_GetPosition=function() return t.position end,
        Montage_Stop=function(_,_,m) assert(m==t.playing);t.stops=(t.stops or 0)+1;t.playing=nil end,
    }
    r.actor.Mesh=obj{GetAnimInstance=function() return anim end}
    function r.actor:PlayAnimMontage(montage)
        assert(montage.path:find('AM_Hun_Medicine_',1,true))
        if t.noPlay then return 0 end
        t.playing=montage;t.position=0;return 1.96
    end
    local aic=obj{AbilitySystem=asc}
    r.actor['Ability Input Component']=aic
    function aic:TryActivateExternalActionAbilityByTag(tag,ia,priority)
        assert(tag.TagName=='Ability.Action.Hun.HeiMoShang.Reborn' and ia==nil and priority==-5)
        t.reborns=t.reborns+1;self.at=t.time
        if t.accept then tags[tag.TagName]=1;return true end
        return false
    end
    function t:addPassive()
        local state=obj{
            InPendingState=function(_,tag)return self.pending and tag.TagName=='CharacterState.Dead' end,
            CanActivateNewState=function(_,tag)return self.canVanish and tag.TagName=='CharacterState.Vanish' end}
        local inst=obj{GetAvatarActorFromActorInfo=function()return r.actor end,ActorStateComponent=state}
        local class=obj{GetFName=function()return {ToString=function()return 'GA_HeiMoShang_RebornPassive' end}end}
        self.asc.ActivatableAbilities.Items={{ActiveCount=1,Ability=obj{GetClass=function()return class end},NonReplicatedInstances={inst}}}
        return inst
    end
    t.module=Supply.new{
        fname=function(x)return x end,now=function()return t.time end,
        current=function(x)return x==r and t.allows end, fighting=function()t.fightReads=(t.fightReads or 0)+1;return t.inBattle end,
        stat=function(actor,key)
            assert(actor==r.actor)
            if key=='Health' then t.healthReads=(t.healthReads or 0)+1 end
            return ({Health=t.hp,Health_Max=t.max,Shachi=22})[key]
        end,
        find=function(path)
            assert(not path:find('BackPack',1,true))
            if path=='/Script/Engine.Default__GameplayStatics' then return settings end
            if path=='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary' then return eventlib end
            return obj{path=path}
        end,
    }
    function t:tick(ctx) return self.module:tick(r,ctx or {distance=600}) end
    function t:hold()return self.module:holdsDeath(r)end
    return t
end
do
    local h=fixture();h.r.loadout.resources.medicine_count=0
    for i=1,100 do h.time=i/10;assert(not h:tick()) end
    print('MEASURE empty flask, 100 decisions: health='..(h.healthReads or 0)..', fighting='..(h.fightReads or 0))
    assert(not h.healthReads and not h.fightReads,'an empty flask still polls health and combat')
end
do
    local h=fixture();h.hp=0;h:addPassive().AbilityInput=obj()
    assert(h:hold());h.time=2;assert(not h:hold())
    h.asc.tags['CharacterState.Dead']=1;h.hp=1;h:hold();h:tick()
    h.hp=0;assert(not h:hold(),'health flicker with Dead still set reopened rebirth')
    h.hp=40;h.asc.tags['CharacterState.Dead']=0;h:hold()
    h.hp=0;assert(h:hold(),'an actual new life should get its own native rebirth window')
end
do
    for _,interruptAt in ipairs({'before','after'}) do
        local h=fixture();local play=h.r.actor.PlayAnimMontage
        function h.r.actor:PlayAnimMontage(...)
            if interruptAt=='before' then h.module:interrupt(h.r) end
            local duration=play(self,...)
            if interruptAt=='after' then h.module:interrupt(h.r) end
            return duration
        end
        assert(not h:tick() and h.module:remaining(h.r)==4 and h.drinks==0 and not h.playing
            and not h.asc.tags['CharacterState.AbilityState.Medicine.InHitCooldown'],'interruption during playback start committed a drink')
    end
end
local f=fixture();assert(f.module:remaining(f.r)==4)
assert(not f:tick{distance=200});assert(f:tick{distance=200,opening=true});assert(f.module:remaining(f.r)==3)
f.position=0.20;f.time=0.2;assert(f:tick() and f.drinks==0)
f.position=0.25;f.time=0.25;assert(f:tick() and f.drinks==1 and f.hp==60 and #f.events==2)
assert(f.events[1]=='GameplayEvent.Medicine.PreActivate' and f.events[2]=='GameplayEvent.Medicine.PostActive')
f.position=0.35;f.time=0.35;f:tick();assert(f.drinks==1)
f.position=1.36;f.time=1.36;assert(not f:tick())
local g=fixture();g.r.loadout.resources.medicine_count=1
assert(g:tick());g.asc.tags['CharacterState.Hitreact.Phase.Act']=1
g.position=0.29;g.time=0.29;assert(not g:tick() and g.drinks==0 and g.module:remaining(g.r)==0)
local free=fixture();free.free=true;assert(free:tick());free.position=.3;free.time=.3;free:tick()
assert(free.drinks==1 and free.module:remaining(free.r)==4)
local bonus=fixture()
local capClass=obj{GetFName=function()return {ToString=function()return 'GA_AddMedicineUseTime_C' end}end}
bonus.asc.ActivatableAbilities.Items={{Ability=obj{GetClass=function()return capClass end},ActiveCount=1}}
assert(bonus.module:remaining(bonus.r)==5)
local unlimited=fixture();unlimited.r.loadout.resources.consume_medicine=false
assert(unlimited:tick() and unlimited.module:remaining(unlimited.r)==4)
local stopped=fixture();stopped.noPlay=true;assert(not stopped:tick() and stopped.module:remaining(stopped.r)==4)
local windup=fixture()
local input=windup.r.actor['Ability Input Component'];input.InActionPhase=true
input.ActionPhase={TagName='CharacterState.Action.Phase.Act'}
assert(not windup:tick() and windup.module:remaining(windup.r)==4,'a low-health fighter must finish the current attack before drinking')
input.InActionPhase=false;windup.time=.1;assert(windup:tick())
windup.playing=nil;windup.time=.2
assert(not windup:tick() and (windup.r.intent.busyUntil or 0)<=windup.time,'losing the drink animation releases its own decision lock')
stopped.allows=false;assert(not stopped:tick() and not stopped:hold())
local cancel=fixture();assert(cancel:tick());cancel.module:stop(cancel.r);assert(cancel.stops==1 and cancel.drinks==0)
do
    local h=fixture();assert(h:tick())
    local anim=h.r.actor.Mesh:GetAnimInstance()
    function anim:Montage_IsPlaying(m)return m==h.playing and not h.paused end
    function anim:Montage_IsActive(m)return m==h.playing end
    h.paused=true;h.position=.18;h.time=.2
    assert(h:tick() and h.drinks==0,'a paused, still active flask animation keeps the pending sip')
    h.paused=false;h.position=.3;h.time=.45;assert(h:tick() and h.drinks==1)
    h:tick();assert(h.drinks==1 and h.module:remaining(h.r)==3)
    h.paused=true;h.module:stop(h.r);assert(h.stops==1,'cleanup also recognizes a paused owned montage')
end
do
    local h=fixture();assert(h:tick());h.inBattle=false;h.position=.3;h.time=.3
    assert(h:tick() and h.drinks==1,'an already committed flask can finish after the target leaves')
    local other=fixture();assert(other:tick())
    other.r.actor.Mesh.GetAnimInstance=function()return obj()end;other.position=.4;other.time=.4
    assert(not other:tick() and other.drinks==0,'a detached animation instance cannot commit a heal')
end
local lost=fixture();assert(lost:tick());lost.allows=false;lost.module:stop(lost.r);assert(not lost.stops)
local d=fixture();d.hp=0;assert(not d:hold());d:addPassive()
do
    local h=fixture();assert(h:tick());h.interruptOnSip=true;h.time=.4;h.position=.4
    assert(not h:tick() and h.drinks==0 and #h.events==1,'a synchronous interruption must not heal after the drink is retired')
end
do
    local h=fixture();h.hp=0;h:addPassive().AbilityInput=obj()
    assert(h:hold());h.time=2;assert(not h:hold())
    h.hp=100;h.time=3;h:tick()
    h.hp=0;h.time=30
    assert(h:hold(),'positive life observed in ordinary combat must reset the previous native death attempt')
end
d.asc.tags['CharacterState.Forbid.Resurrect']=1;assert(not d:hold())
d.asc.tags['CharacterState.Forbid.Resurrect']=0
assert(d:hold());d.time=.2;d.pending=false;d.canVanish=true;d:hold();assert(d.reborns==0)
d.time=.3;d.pending=true;d.canVanish=false;d:hold();assert(d.reborns==0)
d.time=.4;d.canVanish=true;d.accept=true;assert(d:hold() and d.reborns==1)
assert(d.asc.tags['CharacterState.AbilityState.HeiMoShang.RebornCooldown']==1 and d.hp==0)
d.time=1.7;assert(d:hold() and d.reborns==1)
d.hp=50;assert(not d:hold())
d.hp=0;d.asc.tags['Ability.Action.Hun.HeiMoShang.Reborn']=0;assert(not d:hold())
local x=fixture();x.hp=0;x:addPassive();assert(x:hold())
x.time=1.6;assert(not x:hold());x.time=2;assert(not x:hold() and x.reborns==0)
do
    local h=fixture();h.hp=0;h:addPassive();assert(h:hold())
    h.hp=nil;h.time=.35;assert(h:hold() and h.reborns==0,'preserve an existing rebirth window across an unreadable health sample')
    h.time=2;assert(not h:hold() and h.reborns==0,'incomplete readbacks must not extend that window')
    h.hp=0;assert(not h:hold(),'a transient read failure must not start a second death attempt')
end
local native=fixture();native.hp=0;native:addPassive().AbilityInput=obj()
native.pending=true;native.canVanish=true;assert(native:hold());native.time=.5
native:hold();assert(native.reborns==0)
native.time=2;native.asc.tags['Ability.Action.Hun.HeiMoShang.Reborn']=1;assert(native:hold())
native.time=7;assert(not native:hold())
print('PASS hun_supply montage commit, interruption, inventory isolation, accessory refund and bounded native rebirth')
