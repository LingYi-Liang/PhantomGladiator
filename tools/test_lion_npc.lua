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
    local h={now=0,world=object({}),poles={},resume={},log={},members={},timers={},timerId=0,battle={battle_active=true}}
    local npcBase=object({GetFullName=function()return 'Class /Script/ProjectPBZ.PBZCharacter_NPC' end})
    function h:unit(path,team,mode,radius,x)
        local actor=object({outer=self.world,hp=100,tags={},at={X=x or 250,Y=0,Z=radius*2+3},moves={},teleports={}})
        local cls=object({GetFullName=function()return 'BlueprintGeneratedClass '..path end,GetSuperStruct=function()return npcBase end})
        actor.GetClass=function()return cls end
        actor.K2_GetActorRotation=function()return {Pitch=0,Yaw=180,Roll=0} end
        actor.K2_TeleportTo=function(a,dest)
            assert(not a.gone)
            a.at=dest
            a.teleports[#a.teleports+1]=dest
            a.CharacterMovement.base=nil
            return true
        end
        actor.K2_SetActorLocationAndRotation=function(a,dest,_,sweep,_,teleport)
            assert(not a.gone and sweep and not teleport)
            if self.block and self.block(a,dest) then return false end
            a.at=dest
            a.moves[#a.moves+1]=dest
            a.CharacterMovement.base=nil
            return true
        end
        actor.CapsuleComponent=collider(actor,19)
        actor.CapsuleComponent.GetScaledCapsuleRadius=function()return radius end
        actor.CapsuleComponent.GetScaledCapsuleHalfHeight=function()return radius*2 end
        actor.CharacterMovement=object({outer=actor,MovementMode=mode,bCanWalkOffLedges=true,bCanWalkOffLedgesWhenCrouching=true,
            GetMovementBase=function(self)return self.base end,
            StopMovementImmediately=function()end,
            SetMovementMode=function(move,value)
                move.MovementMode=value
                move.base=nil
                if value~=1 or self.noBase then return end
                for _,pole in ipairs(self.area.ActivatedPoles)do
                    local top=pole.StandPoint:K2_GetComponentLocation()
                    if pole.SM_WoodPost_001 and not pole.gone and math.abs(actor.at.Z-top.Z-radius*2-3)<1
                        and (actor.at.X-top.X)^2+(actor.at.Y-top.Y)^2<1 then
                        move.base=pole.SM_WoodPost_001
                        break
                    end
                end
            end})
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
        assert(area==h.area and actor.at.Z>200 and #h.area.ActivatedPoles>1)
        h.resume[#h.resume+1]=actor
        return h.resumeCount or 1
    end})
    h.adapter=LionNPC.new({log=function(message)h.log[#h.log+1]=message end,
        now=function()return h.now end,world=function()return h.world end,area=function()return h.area end,
        location=function(a)assert(not a.gone);return a.at end,hp=function(a)assert(not a.gone);return a.hp end,
        ground=function()return 0 end,isDestroying=function(a)return a.gone end,
        statics=function()return statics end,find=function(path)
            if path=='/Script/MotionWarping.MotionWarpingComponent' then return h.warpClass end
            assert(path==polePath);return poleClass
        end,
        library=function()return library end,range=function(a)return a.range end,
        opponent=function(a)return a.target end,carrier=function(a)if not a.mountPending then return a.mount or a end end,
        fname=function(s)return s end,combat=combat,busy=function(actor)return actor.executing==true end,
        loop=function(ms,fn)
            assert(ms==16)
            h.timerId=h.timerId+1
            h.timers[h.timerId]=fn
            return h.timerId
        end,
        cancel=function(id)h.timers[id]=nil end})
    function h:frames(seconds)
        local untilTime=self.now+seconds
        while self.now<untilTime do
            self.now=math.min(self.now+0.016,untilTime)
            for _,callback in pairs(self.timers)do callback() end
        end
    end
    function h:tick(seconds)
        self:frames(seconds or 0.5)
        self.adapter:tick(self.members,self.battle)
    end
    function h:board()
        self:tick();self:tick();self:tick(1.4);self:tick()
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

test('native lion dance movement is not treated as a stuck actor',function()
    local h=fixture()
    assert(h.adapter:keepsMovement(h.boss,bossPath))
    h.boss.tags[onPole]=0
    assert(not h.adapter:keepsMovement(h.boss,bossPath))
    assert(not h.adapter:keepsMovement(enemy(h),'/Test/CustomNPC.CustomNPC_C'))
end)

test('an arbitrary native walker boards an owned pole and restores the movement snapshot',function()
    local h=fixture()
    local npc=enemy(h,2)
    h:tick()
    assert(#h.poles==1 and #npc.moves==0 and #h.resume==0)
    h:tick()
    h:frames(0.8)
    assert(h.adapter:holds(npc) and #npc.moves>1 and npc.at.Z>73 and npc.at.Z<700 and #npc.teleports==0)
    assert(npc.CharacterMovement.MovementMode==5 and #h.resume==0)
    h:tick(0.6)
    assert(math.abs(npc.at.Z-573)<0.01)
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
    h:board()
    assert(#rider.moves==0 and #rider.mount.moves>1 and h.resume[1]==rider.mount)
    assert(h.poles[1].Owner==rider.mount and h.poles[1].scale.X>=3)
    assert(h.adapter:stop() and h.poles[1].gone and rider.mount.at.Z==193)
end)

test('the last lion execution can finish over a prepared pole without missing the next idle tick',function()
    local h=fixture()
    local npc=enemy(h,5)
    npc.executing=true
    h:tick()
    assert(#h.poles==1 and #npc.moves==0,'prepare the pole during the execution tail')
    for _=1,8 do h:tick() end
    assert(#npc.moves==0 and not h.poles[1].gone,'keep waiting through the rest of the execution')
    npc.executing=false
    npc.CharacterMovement.MovementMode=1
    h:tick()
    assert(npc.CharacterMovement.MovementMode==5 and next(h.timers),'start the jump when the execution releases the actor')
    h:tick(1.4)
    h:tick()
    assert(#h.resume==1 and h.adapter:holds(npc))
end)

test('an elevated boss can be located by its actual feet and the registered pole top',function()
    local h=fixture()
    local npc=enemy(h)
    h.anchor.Occupied=false
    h:board()
    assert(#h.resume==1 and #npc.moves>1,'the temporary Occupied flag can be cleared by native transitions')
end)

test('flying units retain their movement mode and continue after leaving the pole',function()
    local h=fixture()
    local npc=enemy(h,5)
    h:board()
    assert(#h.resume==1 and npc.CharacterMovement.MovementMode==5 and npc.CharacterMovement.bCanWalkOffLedges)
    npc.at={X=750,Y=0,Z=600}
    h:tick();h:tick(1.2);h:tick()
    assert(#npc.teleports==0 and npc.at.X==750 and npc.CharacterMovement.MovementMode==5 and h.poles[1].gone)
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
    h:tick(6);h:tick();h:tick(1.4);h:tick()
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
    h:board();h:tick(2);h:tick()
    assert(#h.resume==0 and npc.at.Z==73 and #npc.teleports==1 and h.poles[1].gone)
end)

test('partial relocation and actor invalidation both clean up owned poles',function()
    local h=fixture()
    local npc=enemy(h)
    h.block=function(_,dest)return dest.Z>200 end
    h:tick();h:tick();h:tick(1.4);h:tick()
    assert(npc.at.Z==73 and h.poles[1].gone and #h.resume==0)
    h.block=nil
    h:tick(6)
    assert(#h.poles==1,'one failure per native phase avoids repeated actor creation')
    h.boss.tags[onPole]=0;h:tick()
    h.boss.tags[onPole]=1;h:board()
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
    h:tick();h:tick();h:frames(0.8)
    local moved=#npc.moves
    h.world=object({})
    h.members={}
    h:tick()
    assert(#npc.moves==moved and not next(h.timers) and not h.poles[1].gone and h.adapter:count()==0)
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

local function combatFixture()
    local combat={hops=0,landings=0,turn=false,restored=0}
    function combat:arm(seat)seat.combat={};return true end
    function combat:held(seat)return seat.combat~=nil end
    function combat:tick()
        local requested=self.turn
        self.turn=false
        return true,requested
    end
    function combat:beginHop()self.hops=self.hops+1;return true end
    function combat:endHop()self.landings=self.landings+1;return true end
    function combat:release(seat)seat.combat=nil;return true end
    function combat:captureWeapon()return {} end
    function combat:restoreWeapon()self.restored=self.restored+1;return true end
    return combat
end

test('a staged pickup selects the newly registered pole at the native warp target',function()
    local combat=combatFixture()
    local h=fixture(combat)
    local npc=enemy(h)
    local victim=h:unit('/Test/HouHouHou.HouHouHou_C','red',1,25)
    h.members[#h.members].summoner=h.boss
    npc.executing=true
    assert(h.adapter:beginPickup(npc,victim,h.members,h.battle))
    h:tick()
    assert(#h.poles==0,'wait for the actual pole plan before choosing the first landing')
    local top={X=440,Y=0,Z=500}
    local pole=object({outer=h.world,Area=h.area,Activated=true,Occupied=false,
        StandPoint=object({K2_GetComponentLocation=function()return top end})})
    pole.SM_WoodPost_001=collider(pole,1)
    pole.SM_WoodPost_001.mode=3
    pole.SM_WoodPost_001.responses[19]=2
    h.area.ActivatedPoles[#h.area.ActivatedPoles+1]=pole
    h.warpClass=object({})
    local warp=object({WarpTargets={{Name={ToString=function()return 'Pole' end},Location=top}}})
    function npc:GetComponentByClass(cls)assert(cls==h.warpClass);return warp end
    npc.tags['CharacterState.HasTempWeapon.HouHouHouHead']=1
    assert(h.adapter:pickupReady(npc))
    assert(#h.poles==0 and pole.Occupied)
    h.adapter:pickupEnded(npc)
    npc.executing=false
    h:tick();h:tick(1.4);h:tick()
    assert(combat.hops==1 and combat.landings==1 and npc.CharacterMovement.base==pole.SM_WoodPost_001)
    assert(#npc.teleports==0 and #h.resume==1)
    assert(h.adapter:stop() and combat.restored==1 and not pole.Occupied and not pole.gone)
end)

test('confirmed poles can be reused for a second and third landing without a ground reset',function()
    local combat=combatFixture()
    local h=fixture(combat)
    local npc=enemy(h)
    h:board()
    assert(combat.hops==1 and combat.landings==1)
    combat.turn=true
    h:tick();h:tick();h:tick(1.4)
    assert(#h.poles==2 and combat.landings==2 and not h.poles[1].gone
        and npc.CharacterMovement.base==h.poles[2].SM_WoodPost_001)
    combat.turn=true
    h:tick();h:tick();h:tick(1.4)
    assert(#h.poles==2 and combat.landings==3 and #npc.teleports==0
        and npc.CharacterMovement.base==h.poles[1].SM_WoodPost_001)
    assert(h.adapter:stop() and h.poles[1].gone and h.poles[2].gone and #h.area.ActivatedPoles==1)
end)

test('an obstructed hop returns to the last supported pole and keeps the weapon mode',function()
    local combat=combatFixture()
    local h=fixture(combat)
    local npc=enemy(h)
    h:board()
    local first={X=npc.at.X,Y=npc.at.Y,Z=npc.at.Z}
    combat.turn=true
    h:tick()
    h.block=function(_,dest)return (dest.X-first.X)^2+(dest.Y-first.Y)^2>30^2 end
    h:tick();h:tick(1.4);h:tick(0.8)
    assert(h.poles[2].gone and not h.poles[1].gone and h.adapter:holds(npc))
    assert(npc.CharacterMovement.base==h.poles[1].SM_WoodPost_001 and #npc.teleports==0)
    assert(combat.landings==2 and h.adapter:stop())
end)
