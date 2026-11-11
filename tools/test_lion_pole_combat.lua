package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Combat=require('lion_pole_combat')
local address=0
local function object(values)
    address=address+1
    values.address=address
    values.IsValid=function(self)return not self.gone end
    values.GetAddress=function(self)assert(not self.gone);return self.address end
    values.GetOuter=function(self)assert(not self.gone);return self.outer end
    return values
end
local function fixture()
    local h={time=0,world=object({}),bullets={},poses={},logs={}}
    local class=object({GetFullName=function()
        return 'BlueprintGeneratedClass /PBZCombatAsset/ActorData/Mobs/LionDancer/BP_Bullet_LionDancer_FlameBall_Small.BP_Bullet_LionDancer_FlameBall_Small_C'
    end})
    local data=object({GetBulletClass=function()return class end})
    local asset,meshClass=object({}),object({})
    local ai=object({PauseLogic=function(_,brain)brain.paused=true end,ResumeLogic=function(_,brain)brain.paused=false end})
    function h:makeActor(x)
        local actor=object({outer=self.world,at={X=x,Y=0,Z=700},hp=100})
        actor.CapsuleComponent=object({outer=actor})
        actor.RootComponent=actor.CapsuleComponent
        actor.Mesh=object({outer=actor,DoesSocketExist=function(_,name)return name=='weapon_r_Socket' end})
        actor.brain=object({outer=actor,paused=false,IsPaused=function(self)return self.paused end})
        actor.Controller=object({outer=self.world,BrainComponent=actor.brain})
        actor.K2_SetActorRotation=function(self,rotation)self.rotation=rotation;return true end
        actor.AddComponentByClass=function(self,cls,manual,t,deferred)
            assert(cls==meshClass and manual and not deferred)
            local head=object({outer=self,SetCollisionEnabled=function(_,mode)assert(mode==0)end,
                SetSkeletalMeshAsset=function(self,value)self.asset=value end,GetSkeletalMeshAsset=function(self)return self.asset end,
                K2_AttachToComponent=function(self,parent,socket)
                    assert(parent==actor.Mesh and socket=='weapon_r_Socket')
                    self.AttachParent=parent
                    return true
                end,
                K2_DestroyComponent=function(self,other)assert(self==other);self.gone=true end})
            h.head=head
            return head
        end
        return actor
    end
    h.actor,h.boss=h:makeActor(0),h:makeActor(500)
    h.seat={key='test',world=h.world,actor=h.actor,carrier=h.actor,body={radius=35,half=90},source={actor=h.boss}}
    data.CreateBullet=function(self,t,context)
        assert(context==h.actor and t.Translation.X>35 and t.Rotation.W>0)
        if h.failCreate then return nil end
        local bullet=object({outer=h.world,BulletStatus=0,GetClass=function()return class end})
        bullet.Initialize=function(b,parent,owner,ability,resource,debug)
            assert(parent==nil and owner==h.actor and ability==nil and resource==data and not debug)
            b.BulletOwnerAvatar=owner;b.BulletData=resource;b.BulletStatus=1
        end
        bullet.K2_DetachFromActor=function()end
        bullet.InitializePreSelectedTarget=function(b,target)
            assert(target.Component==h.boss.CapsuleComponent and target.SocketName=='None')
            b.CurrentTarget=target
        end
        bullet.SetBulletTransform=function(b,tf)assert(tf==t);b.placed=true end
        bullet.Start=function(b)
            assert(b.placed and b.CurrentTarget.Component==h.boss.CapsuleComponent and h.actor.brain.paused)
            if h.wrongTarget then b.CurrentTarget={Component=h.actor.CapsuleComponent} end
            b.BulletStatus=2
        end
        bullet.Deactivate=function(b,time)assert(time==0.0);b.BulletStatus=3 end
        h.bullets[#h.bullets+1]=bullet
        return bullet
    end
    h.combat=Combat.new({
        log=function(s)h.logs[#h.logs+1]=s end,location=function(actor)return actor.at end,hp=function(actor)return actor.hp end,
        isDestroying=function(actor)return actor.gone==true end,fname=function(s)return s end,
        find=function(path)
            if path:find('FireBall',1,true) then return data end
            if path:find('HouHouHou_Head',1,true) then return asset end
            if path:find('SkeletalMeshComponent',1,true) then return meshClass end
            if path:find('SGameAIFunctionLibrary',1,true) then return ai end
        end,
        pose=function(_,clip,looping)
            if h.noPose then return nil end
            local pose={clip=clip,started=h.time,looping=looping}
            function pose:position()if not h.lostPose then return h.time-self.started end end
            function pose:stop()self.stopped=true;return true end
            function pose:play(nextClip,loop)
                self.clip,self.started,self.looping=nextClip,h.time,loop
                return true
            end
            h.poses[#h.poses+1]=pose
            return pose
        end})
    function h:tick(time,ready)
        self.time=time
        return self.combat:tick(self.seat,time,ready~=false)
    end
    return h
end
local function test(name,fn)fn();print('ok - '..name)end

test('two confirmed projectiles trigger a hop, with the same pose driver used for idle, aiming and jumping',function()
    local h=fixture()
    assert(h.combat:arm(h.seat,0) and h.actor.brain.paused and h.head.AttachParent==h.actor.Mesh)
    assert(h:tick(0) and #h.poses==1 and h.poses[1].clip:find('Attack_R',1,true))
    assert(h:tick(0.98) and #h.bullets==0)
    assert(h:tick(1.0) and #h.bullets==1 and h.bullets[1].BulletStatus==2)
    assert(h.bullets[1].BulletOwnerAvatar==h.actor and h.bullets[1].CurrentTarget.Component==h.boss.CapsuleComponent)
    assert(h:tick(2.0) and #h.bullets==1 and h.boss.hp==100)
    local ok,hop=h:tick(2.9)
    assert(ok and not hop and h.poses[1].looping and h.poses[1].clip:find('Battle_Idle_R',1,true))
    h.bullets[1].BulletStatus=3
    assert(h:tick(3) and h:tick(4) and #h.bullets==2)
    ok,hop=h:tick(6)
    assert(ok and hop and #h.poses==1)
    assert(h.combat:beginHop(h.seat) and h.poses[1].clip:find('Battle_Walk_Fwd_R',1,true))
    assert(h.combat:endHop(h.seat,7.3) and h.poses[1].looping and not h.poses[1].stopped)
    assert(h.combat:release(h.seat) and not h.actor.brain.paused and h.head.gone and h.bullets[2].BulletStatus==3)
end)

test('a hit interrupts the windup and stop never completes an unfinished shot',function()
    local h=fixture()
    assert(h.combat:arm(h.seat,0) and h:tick(0))
    h.actor.hp=99
    assert(h:tick(1.1) and #h.bullets==0 and h.poses[1].stopped)
    assert(h:tick(1.7) and #h.poses==2)
    assert(h.combat:release(h.seat) and #h.bullets==0 and not h.actor.brain.paused)
end)

test('loss of pose readback and native target replacement fail closed',function()
    local h=fixture()
    assert(h.combat:arm(h.seat,0) and h:tick(0))
    h.lostPose=true
    assert(not h:tick(1.1) and #h.bullets==0 and h.combat:release(h.seat))
    h.lostPose=false;h.wrongTarget=true
    assert(h.combat:arm(h.seat,2) and h:tick(2))
    assert(not h:tick(3.1) and h.bullets[1].BulletStatus==3 and h.combat:release(h.seat))
end)

test('mounted NPC uses the same projectile without replacing either skeleton',function()
    local h=fixture()
    local mount=h:makeActor(0)
    h.seat.carrier=mount
    assert(h.combat:arm(h.seat,0) and h.actor.brain.paused and mount.brain.paused)
    assert(h:tick(0) and h:tick(1.1) and #h.bullets==1 and #h.poses==0)
    assert(h.combat:release(h.seat) and not h.actor.brain.paused and not mount.brain.paused)
end)

test('a deflected or recycled projectile is left to its new owner',function()
    local h=fixture()
    assert(h.combat:arm(h.seat,0) and h:tick(0) and h:tick(1.1))
    h.bullets[1].BulletOwnerAvatar=h.boss
    assert(h.combat:release(h.seat) and h.bullets[1].BulletStatus==2)
end)

test('existing AI pause and native spawn failure preserve a recoverable actor',function()
    local h=fixture()
    h.actor.brain.paused=true
    assert(not h.combat:arm(h.seat,0) and h.combat:release(h.seat) and h.actor.brain.paused)
    h.actor.brain.paused=false;h.failCreate=true
    assert(h.combat:arm(h.seat,0) and h:tick(0) and not h:tick(1.1))
    assert(h.combat:release(h.seat) and not h.actor.brain.paused and #h.bullets==0)
end)

test('native pickup uses its equipped lion head and restores the original main weapon on exit',function()
    local h=fixture()
    local actor=h.actor
    local original=object({})
    local weapons=object({current=0})
    actor['Character Weapons Component']=weapons
    actor.AbilitySystemComponent=object({GetGameplayTagCount=function(_,tag)
        assert(tag.TagName=='CharacterState.HasTempWeapon.HouHouHouHead')
        return weapons.current==1 and 1 or 0
    end})
    function weapons:GetCurrentWeaponIndex(slot,pending)
        assert(slot.TagName=='Weapon.Slot.Main' and pending==false)
        return self.current
    end
    function weapons:GetSlotWeapon(_,index,out)
        if index==0 then out.WeaponConfig=original end
    end
    function weapons:SetCurrentWeapon(_,index)
        assert(index==0)
        self.current=index
    end
    local record=assert(h.combat:captureWeapon(actor,h.world))
    weapons.current=1
    assert(h.combat:arm(h.seat,0) and not h.head and h.combat:held(h.seat))
    assert(h.combat:release(h.seat) and h.combat:restoreWeapon(record))
    assert(weapons.current==0 and not actor.brain.paused and not h.head)
end)
