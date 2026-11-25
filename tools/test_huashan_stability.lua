local function fixture()
    local env=setmetatable({arg={'fixture'}},{__index=_G})
    return assert(loadfile('tools/test_huashan_formation.lua','t',env))()
end
local function newGroup(h)
    local token,rows=h.party(false,'blue',100)
    assert(h.manage:prepare(token,rows,h.world,'blue'))
    assert(h.manage:ready(token))
    return token,rows
end
local function allGone(h)
    for _,helper in ipairs(h.created)do assert(not helper.live,'owned helper survived cleanup')end
end

-- BeginDeferred has already created the actor when one of the ensuing reads is unavailable.
for _,method in ipairs({'GetClass','GetOuter','GetFullName'})do
    for _,failAt in ipairs({1,5})do
        local h=fixture()
        local token,rows=h.party(false,'blue',100)
        local statics=h.options.statics()
        local begin=statics.BeginDeferredActorSpawnFromClass
        function statics:BeginDeferredActorSpawnFromClass(...)
            local actor=begin(self,...)
            if #h.created==failAt then
                local original=actor[method]
                actor[method]=function(self)self[method]=original;return nil end
            end
            return actor
        end
        assert(not h.manage:prepare(token,rows,h.world,'blue'))
        assert(h.manage:abort(token));allGone(h)
        for _,row in ipairs(rows)do assert(row.actor.live and not row.actor.Spawner and not row.actor.MobGroup)end
    end
end

do
    local h=fixture();local token,rows=newGroup(h)
    local manager,leader=h.manage,rows[1].actor
    local domain=leader.MobGroup.MobDomain
    local roster={}
    for i,row in ipairs(rows)do roster[i]={actor=row.actor,team='blue',formationGroup=token}end
    local foe=h.actor('/Test/Foe.Foe_C',{X=0,Y=0,Z=0})
    roster[8]={actor=foe,team='red'};manager:roster(roster)
    local list,attempts,refuse=domain.ActorsInMobDomain,0,true
    domain.ActorsInMobDomain=nil
    setmetatable(domain,{__index=function(_,k)if k=='ActorsInMobDomain' then return list end end,
        __newindex=function(self,k,v)
            if k=='ActorsInMobDomain' then attempts=attempts+1;if not refuse then list=v end
            else rawset(self,k,v)end
        end})
    for i=1,30 do assert(not manager:beforeAttack(leader,foe));manager:tick()end
    assert(attempts==1)
    refuse=false;h.setTime(.5);assert(manager:beforeAttack(leader,foe))
    assert(attempts==2 and domain:IsActorInMobDomain(foe))
    manager:roster(roster);manager:tick();assert(attempts==2,'identical native membership should not be rewritten')

    local reads=0;local address=foe.GetAddress
    function foe:GetAddress()reads=reads+1;return address(self)end
    for i=1,100 do assert(not manager:supportingActor(foe))end
    assert(reads==0)
    local caster=rows[2].actor
    local healing={IsValid=function()return true end,bIsActive=true,GetAvatarActorFromActorInfo=function()return caster end}
    manager:started(healing,'GA_HuaShan_Troop_Healing_C')
    assert(manager:supportingActor(caster) and not manager:supportingActor(foe))
    healing.bIsActive=false;manager:tick();local before=reads
    assert(not manager:supportingActor(foe) and reads==before)

    local destroy=domain.K2_DestroyActor;local tries=0
    function domain:K2_DestroyActor()tries=tries+1 end
    assert(not manager:abort(token))
    for i=1,30 do manager:roster({});manager:tick()end
    assert(tries==1 and domain.live)
    h.setWorld(nil);h.setTime(3);manager:tick();assert(domain.live)
    domain.K2_DestroyActor=destroy;h.setWorld(h.world);manager:tick();allGone(h)
end

do
    local h=fixture();local token,rows=newGroup(h)
    local a=rows[1].actor;local outer=a.GetOuter
    function a:GetOuter()return nil end
    assert(not h.manage:abort(token))
    assert(a.Spawner and a.Spawner.live,'an unreadable owner may still be bound')
    a.GetOuter=outer;h.setTime(2);h.manage:tick();allGone(h)
    assert(not a.Spawner and not a.MobGroup)
end
for _,unknownLeader in ipairs({false,true})do
    local h=fixture();local token,rows=newGroup(h)
    local leader,fallen=rows[1].actor,rows[2].actor
    local calls=0
    local script={Pawn=leader,IsValid=function()return true end,
        GetClass=function()return h.tree('/Game/Fixture.AIScript_HuaShan_Troop_Blue_Dead_C')end}
    function script:OnGroupMemberDead(spawner)
        assert(spawner==fallen.Spawner)
        calls=calls+1
        if calls==1 then error('native death notice temporarily unavailable') end
        self.completed=true
    end
    leader.ai.SpawnedAIScripts={script}
    fallen.hp=0;fallen.tags['CharacterState.Dead']=1;h.manage:lifeChanged(token,fallen,false)
    if unknownLeader then
        leader.hp=nil;h.setTime(1);h.manage:tick();assert(calls==0)
        leader.hp=100
    end
    h.setTime(2);h.manage:tick();assert(calls==1,'a temporary HP read cannot discard this death')
    h.setTime(3);h.manage:tick();assert(calls==2 and script.completed,'a rejected death notice remains pending')
    h.setTime(4);h.manage:tick();assert(calls==2,'the confirmed native notification is sent only once')
end
do
    local h=fixture();local _,blue=newGroup(h);local _,red=h.party(true,'red',3000)
    local a,target=blue[1].actor,red[1].actor
    h.foes[a]=target;assert(h.manage:beforeAttack(a,target));h.manage:assigned(a,target)
    local gas=h.options.find('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
    local send=gas.SendGameplayEventToActor
    local attempts=0
    function gas:SendGameplayEventToActor(...)
        attempts=attempts+1
        if attempts==1 then error('native opening dispatch unavailable') end
        return send(self,...)
    end
    h.setTime(1);h.manage:tick();assert(attempts==1 and #h.events==0)
    h.setTime(2);h.manage:tick();assert(attempts==2 and #h.events==1,'retry an opener rejected before native dispatch')
    h.setTime(3);h.manage:tick();assert(attempts==2 and #h.events==1)
end
print('PASS sword formation rollback, bounded retries, cast expiry, map transitions and native membership')
