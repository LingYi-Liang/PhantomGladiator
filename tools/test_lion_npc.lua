package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local LionNPC=require('lion_npc')
local bossPath='/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_LionDancer_P2.BP_Monster_LionDancer_P2_C'
local polePath='/Game/RenewalContent/Actors/SpecialMove/Volume/BP_LionDancing_Pole_Base.BP_LionDancing_Pole_Base_C'
local onPole='CharacterState.AbilityState.LionDancer.OnPole'
local protected='CharacterState.Unselectable.Force.Perform'
local address=0
local function object(fields)
    address=address+1
    fields.address=address
    fields.IsValid=function(self)return not self.gone end
    fields.GetOuter=function(self)assert(not self.gone);return self.outer end
    fields.GetAddress=function(self)assert(not self.gone);return self.address end
    return fields
end
local function collider(outer,channel)
    return object({outer=outer,channel=channel,responses={},
        GetCollisionObjectType=function(self)return self.channel end,
        GetCollisionResponseToChannel=function(self,key)return self.responses[key] or 0 end,
        SetCollisionResponseToChannel=function(self,key,value)self.responses[key]=value end,
        SetCollisionEnabled=function(self,value)self.mode=value end,
        GetCollisionEnabled=function(self)return self.mode end,
        SetGenerateOverlapEvents=function(self,value)self.overlapEvents=value end})
end
local function fixture(combat)
    local h={now=0,world=object({}),poles={},resume={},log={},members={},battle={battle_active=true}}
    local npcBase=object({GetFullName=function()return 'Class /Script/ProjectPBZ.PBZCharacter_NPC' end})
    function h:unit(path,team,mode,radius,x)
        local actor=object({outer=self.world,hp=100,tags={},at={X=x or 250,Y=0,Z=radius*2+3},moves={}})
        local cls=object({GetFullName=function()return 'BlueprintGeneratedClass '..path end,GetSuperStruct=function()return npcBase end})
        actor.GetClass=function()return cls end
        actor.K2_GetActorRotation=function()return {Pitch=0,Yaw=180,Roll=0} end
        actor.K2_TeleportTo=function(a,dest,rotation)
            assert(not a.gone and rotation.Yaw==180)
            a.at=dest
            a.moves[#a.moves+1]=dest
            a.CharacterMovement.base=nil
            if dest.Z>200 and not self.noBase and a.CharacterMovement.MovementMode==1 then
                for _,pole in ipairs(self.poles)do
                    if pole.Owner==a and not pole.gone then a.CharacterMovement.base=pole.SM_WoodPost_001;break end
                end
            end
            return not (dest.Z>200 and self.teleportFails)
        end
        actor.CapsuleComponent=collider(actor,19)
        actor.CapsuleComponent.GetScaledCapsuleRadius=function()return radius end
        actor.CapsuleComponent.GetScaledCapsuleHalfHeight=function()return radius*2 end
        actor.CharacterMovement=object({outer=actor,MovementMode=mode,bCanWalkOffLedges=true,bCanWalkOffLedgesWhenCrouching=true,
            GetMovementBase=function(self)return self.base end,
            GetGravityZ=function()return -980 end,
            SetMovementMode=function(self,value)self.MovementMode=value end})
        actor.AbilitySystemComponent=object({outer=actor,GetGameplayTagCount=function(_,value)
            if actor.noTags then return nil end
            return actor.tags[value.TagName] or 0
        end})
        if team then self.members[#self.members+1]={actor=actor,class_path=path,team=team} end
        return actor
    end
    h.boss=h:unit(bossPath,'red',5,50,0)
    h.boss.at.Z=603
    h.boss.tags[onPole]=1
    h.area=object({outer=h.world,ActivatedPoles={},DeactivatedPoles={}})
    h.anchor=object({outer=h.world,Area=h.area,Activated=true,Occupied=true,
        StandPoint=object({K2_GetComponentLocation=function()return {X=0,Y=0,Z=500} end})})
    h.area.ActivatedPoles[1]=h.anchor
    h.area.ReceiveActorBeginOverlap=function(area,pole)
        assert(pole.Owner and pole.Occupied and not pole.PlayerCanJump and not pole.CanCreateLink)
        pole.Area=area
        area.ActivatedPoles[#area.ActivatedPoles+1]=pole
    end
    h.area.UnregisterPole=function(area,pole)
        assert(pole~=h.anchor,'original map pole must not be touched')
        for i,other in ipairs(area.ActivatedPoles)do
            if other==pole then table.remove(area.ActivatedPoles,i);break end
        end
    end
    local poleClass=object({GetFullName=function()return 'BlueprintGeneratedClass '..polePath end})
    local statics=object({
        BeginDeferredActorSpawnFromClass=function(_,world,cls,transform,collision,owner,scale)
            assert(world==h.world and cls==poleClass and collision==1 and scale==1)
            local at=transform.Translation
            local pole=object({outer=world,Owner=owner,Activated=true,scale=transform.Scale3D,
                StandPoint=object({K2_GetComponentLocation=function()return {X=at.X,Y=at.Y,Z=at.Z+500.126801} end})})
            pole.SM_WoodPost_001=collider(pole,1)
            pole.SetActorEnableCollision=function(self,on)self.collision=on end
            pole.IsOverlappingActor=function(self,area)
                return self.collision and self.SM_WoodPost_001.overlapEvents and area==h.area and not h.noOverlap
            end
            pole.K2_DestroyActor=function(self)
                for _,other in ipairs(h.area.ActivatedPoles)do assert(other~=self) end
                self.gone=true
            end
            h.poles[#h.poles+1]=pole
            return pole
        end,
        FinishSpawningActor=function(_,pole)
            assert(pole.Occupied and not pole.PlayerCanJump and not pole.CanCreateLink)
            return pole
        end})
    local library=object({ResumeLionDancerPoleClusterActions=function(_,area,actor)
        assert(area==h.area and actor.at.Z>200 and #h.poles>0)
        h.resume[#h.resume+1]=actor
        return h.resumeCount or 1
    end})
    h.adapter=LionNPC.new({log=function(message)h.log[#h.log+1]=message end,
        now=function()return h.now end,world=function()return h.world end,area=function()return h.area end,
        location=function(a)assert(not a.gone);return a.at end,hp=function(a)assert(not a.gone);return a.hp end,
        ground=function()return 0 end,isDestroying=function(a)return a.gone end,
        statics=function()return statics end,find=function(path)assert(path==polePath);return poleClass end,
        library=function()return library end,range=function(a)return a.range end,
        opponent=function(a)return a.target end,carrier=function(a)if not a.mountPending then return a.mount or a end end,
        fname=function(s)return s end,combat=combat})
    function h:tick(seconds)
        self.now=self.now+(seconds or 0.5)
        self.adapter:tick(self.members,self.battle)
    end
    return h
end
local function enemy(h,mode,radius,path)
    local npc=h:unit(path or '/Test/CustomNPC.CustomNPC_C','blue',mode or 1,radius or 35)
    npc.target=h.boss
    return npc
end
local function test(name,fn)fn();print('ok - '..name)end

test('native phase protection and unknown tags keep opponents on the ground',function()
    local h=fixture()
    local npc=enemy(h)
    h.boss.tags[protected]=1
    h:tick()
    h.boss.noTags=true
    h:tick()
    assert(#h.poles==0 and #npc.moves==0)
end)

test('an arbitrary native walker boards an owned pole and restores the movement snapshot',function()
    local h=fixture()
    local npc=enemy(h,2)
    h:tick()
    assert(#h.poles==1 and #npc.moves==0 and #h.resume==0)
    h:tick()
    assert(h.adapter:holds(npc) and #npc.moves==1 and npc.at.Z==573)
    assert(npc.CharacterMovement.MovementMode==1 and not npc.CharacterMovement.bCanWalkOffLedges)
    assert(npc.CapsuleComponent.responses[1]==2 and h.poles[1].Area==h.area)
    assert(#h.resume==0,'position alone does not confirm a walking unit has a floor')
    h:tick()
    assert(#h.resume==1 and h.resume[1]==npc and npc.hp==100)
    h.boss.tags[onPole]=0
    h:tick()
    assert(npc.at.Z==73 and npc.CharacterMovement.MovementMode==2 and npc.CharacterMovement.bCanWalkOffLedges)
    assert(npc.CapsuleComponent.responses[1]==0 and h.poles[1].gone and h.adapter:count()==0)
    assert(#h.area.ActivatedPoles==1 and h.area.ActivatedPoles[1]==h.anchor)
end)

test('a rider waits for its own mount and only the carrier is moved',function()
    local h=fixture()
    local rider=enemy(h,0)
    rider.mountPending=true
    h:tick()
    assert(#h.poles==0)
    rider.mount=h:unit('/Test/Mount.Mount_C',nil,1,95)
    rider.mountPending=false
    h:tick();h:tick();h:tick()
    assert(#rider.moves==0 and #rider.mount.moves==1 and h.resume[1]==rider.mount)
    assert(h.poles[1].Owner==rider.mount and h.poles[1].scale.X>=3)
    assert(h.adapter:stop() and h.poles[1].gone and rider.mount.at.Z==193)
end)

test('flying units retain their movement mode and continue after leaving the pole',function()
    local h=fixture()
    local npc=enemy(h,5)
    h:tick();h:tick();h:tick()
    assert(#h.resume==1 and npc.CharacterMovement.MovementMode==5 and npc.CharacterMovement.bCanWalkOffLedges)
    npc.at={X=750,Y=0,Z=600}
    h:tick(3);h:tick()
    assert(#npc.moves==1 and npc.at.X==750 and npc.CharacterMovement.MovementMode==5 and h.poles[1].gone)
end)

test('unsupported and busy movement waits rather than interrupting an action',function()
    local h=fixture()
    local npc=enemy(h,3)
    h:tick()
    assert(#h.poles==0)
    npc.CharacterMovement.MovementMode=1
    npc.tags['Ability.Action']=1
    h:tick(6)
    assert(#h.poles==0)
    npc.tags['Ability.Action']=0
    h:tick(6);h:tick();h:tick()
    assert(#h.resume==1)
end)

test('failed pole registration leaves the actor and its collisions untouched',function()
    local h=fixture()
    local npc=enemy(h)
    h.noOverlap=true
    h:tick();h:tick();h:tick()
    assert(h.poles[1].gone and #npc.moves==0 and #h.resume==0)
    assert(npc.CapsuleComponent.responses[1]==nil and npc.CharacterMovement.bCanWalkOffLedges)
end)

test('the original scatter resumes only after a real physical floor readback',function()
    local h=fixture()
    local npc=enemy(h)
    h.noBase=true
    h:tick();h:tick();h:tick(3);h:tick()
    assert(#h.resume==0 and npc.at.Z==73 and #npc.moves==2 and h.poles[1].gone)
end)

test('partial relocation and actor invalidation both clean up owned poles',function()
    local h=fixture()
    local npc=enemy(h)
    h.teleportFails=true
    h:tick();h:tick();h:tick()
    assert(npc.at.Z==73 and h.poles[1].gone and #h.resume==0)
    h.teleportFails=false
    h:tick(6)
    assert(#h.poles==1,'one failure per native phase avoids repeated actor creation')
    h.boss.tags[onPole]=0;h:tick()
    h.boss.tags[onPole]=1;h:tick();h:tick();h:tick()
    npc.gone=true
    h:tick()
    assert(h.poles[2].gone and h.adapter:count()==0 and #h.area.ActivatedPoles==1)
end)

test('inactive fights and map changes do not take over other actors',function()
    local h=fixture()
    local npc=enemy(h)
    h.battle.battle_active=false
    h:tick()
    assert(#h.poles==0)
    h.battle.battle_active=true
    h:tick();h:tick();h:tick()
    h.world=object({})
    h.members={}
    h:tick()
    assert(#npc.moves==1 and not h.poles[1].gone and h.adapter:count()==0)
end)

test('opponents on other targets and non-fighting actors stay put',function()
    local h=fixture()
    local npc=enemy(h)
    h.members[2].stand=true
    local other=enemy(h)
    other.target=h:unit('/Test/Other.Other_C','red',1,30)
    h:tick()
    assert(#h.poles==0 and #npc.moves==0 and #other.moves==0)
end)

test('a second verified pole is reserved through the native jump and the old one is removed only after landing',function()
    local combat={ticks=0}
    function combat:arm(seat)seat.combat={};return true end
    function combat:held(seat)return seat.combat~=nil end
    function combat:tick(seat)
        self.ticks=self.ticks+1
        return true,self.ticks==1
    end
    function combat:beginHop()self.started=true;return true end
    function combat:endHop()self.landed=true;return true end
    function combat:release(seat)seat.combat=nil;return true end
    local h=fixture(combat)
    local npc=enemy(h)
    npc.LaunchCharacter=function(self,velocity,xy,z)
        assert(xy and z and velocity.Z>0 and combat.started and h.poles[2].Area==h.area)
        self.CharacterMovement.base=nil
        self.CharacterMovement.MovementMode=3
    end
    h:tick();h:tick();h:tick()
    assert(#h.poles==2 and not combat.started and combat.ticks==1)
    h:tick();h:tick()
    assert(combat.started and not combat.landed and not h.poles[1].gone and combat.ticks==1)
    npc.CharacterMovement.base=h.poles[2].SM_WoodPost_001
    npc.CharacterMovement.MovementMode=1
    h:tick()
    assert(combat.landed and h.poles[1].gone and not h.poles[2].gone and h.adapter:holds(npc))
    assert(h.adapter:stop() and h.poles[2].gone and #h.area.ActivatedPoles==1)
end)
