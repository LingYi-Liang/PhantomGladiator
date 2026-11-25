package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Selfie=require('selfie')
local assets=require('selfie_poses')
local function fixture()
    local h={objects={},serial=0,shots=0,now=1,reads=0}
    local function object(path,fields)
        h.serial=h.serial+1
        local o=fields or {}
        o.id,o.path,o.alive=h.serial,path,true
        function o:IsValid()return self.alive end
        function o:GetAddress()assert(self.alive);return self.id end
        function o:GetFullName()assert(self.alive);return 'Object '..self.path end
        h.objects[path]=o
        return o
    end
    local function point(x,y,z)return {X=x,Y=y,Z=z} end
    local function rot(yaw)return {Yaw=yaw,Pitch=0,Roll=0} end
    local world=object('/Test.World')
    h.world=world
    local rigPath='/HuaShira/Characters/EliteBoss/MuXiaoKui/MuXiaoKui_Skeleton'
    local rig=object(rigPath..'.MuXiaoKui_Skeleton')
    local otherRig=object('/Test.Unmatched')
    local package=assert(assets[rigPath][1])
    local asset=object(package..'.'..package:match('([^/]+)$'),{Skeleton=rig,bEnableRootMotion=false})
    function asset:GetPlayLength()return 3 end
    local function actor(name,y,yaw,skeleton)
        local pose=object('/Test.'..name..'.Anim')
        local mesh=object('/Test.'..name..'.Mesh')
        local model=object('/Test.'..name..'.Model')
        function mesh:DoesSocketExist(socket)return socket=='head' end
        function mesh:GetSocketLocation()return point(10,y,178) end
        function mesh:GetSkeletalMeshAsset()return model end
        function mesh:GetAnimInstance()return not h.animMissing and pose or nil end
        function model:GetSkeleton()return skeleton end
        function pose:GetCurrentActiveMontage()return self.active end
        function pose:PlaySlotAnimationAsDynamicMontage(anim,slot,blendIn,blendOut,rate,loops,trigger,start)
            assert(anim==asset and slot=='DefaultSlot' and blendIn==0 and rate==1 and loops==1)
            if h.rejectPose then return end
            self.active=object('/Transient.Montage'..h.serial,{at=start,paused=false})
            return self.active
        end
        function pose:Montage_Pause(m)assert(m==self.active);m.paused=not h.rejectPausePose end
        function pose:Montage_GetPosition(m)return m.at end
        function pose:Montage_IsActive(m)return self.active==m end
        function pose:Montage_IsPlaying(m)return self.active==m and not m.paused end
        function pose:Montage_Stop(_,m)assert(self.active==m);self.active=nil end
        local a=object('/Test.World:'..name,{Mesh=mesh,pose=pose,at=point(10,y,20),rotation=rot(yaw),hp=100,bHidden=false})
        function a:GetOuter()assert(self.alive);return world end
        function a:K2_GetActorRotation()assert(self.alive);return self.rotation end
        function a:K2_SetActorRotation(r,teleport)assert(self.alive and teleport==false);self.rotation=r end
        return a
    end
    h.player=actor('Player',0,22,rig)
    h.near=actor('Nearby',160,65,rig)
    h.far=actor('Other',240,100,otherRig)
    h.members={{actor=h.far,team='companion',class_path='/Test.Nearless_C'},
        {actor=h.near,team='companion',class_path='/Test.Near_C'}}
    local c={}
    h.camera=c
    local view=object('/Test.Camera',{at=point(0,0,0),rotation=rot(0)})
    function view:K2_GetActorRotation()return self.rotation end
    function view:K2_GetActorLocation()return self.at end
    function view:K2_SetActorLocationAndRotation(at,facing,sweep,out,teleport)
        assert(sweep==false and type(out)=='table' and teleport)
        self.at,self.rotation=at,facing
    end
    function c:isActive()return self.active==true end
    function c:isFrozen()return self.frozen==true end
    function c:enter(mode)assert(mode=='photo');self.active=true;return true end
    function c:fieldOfView()return 80 end
    function c:borrow(owner)self.owner=owner;return view end
    h.view=view
    function c:photoInput(owner)assert(self.owner==owner);return h.input end
    function c:viewConfirmed(owner)return self.owner==owner and not h.viewDelayed end
    function c:freeze(value)
        if h.rejectFreeze and value then return {ok=false} end
        self.frozen=value
        return {ok=true}
    end
    function c:stop(reason)
        local owner=self.owner
        self.active,self.frozen,self.owner=false,false,nil
        if owner then owner:cameraLost(reason) end
        return true
    end
    local shared={}
    function shared:GetSharedVariable(k)return self[k] end
    function shared:SetSharedVariable(k,v)self[k]=v end
    local opts={shared=shared,camera=c,world=function()return h.world end,player=function()return h.player end,
        hp=function(a)return a.hp end,location=function(a)return a.at end,blocked=function(a)return a.busy end,
        members=function()h.reads=h.reads+1;return h.members end,blockedView=function(_,from)return h.allBlocked or h.oneSideBlocked and from.X>0 end,
        clock=function()return h.now end,fname=function(name)return name end,find=function(path)return h.objects[path] end,
        load=function(path)return h.objects[path] end,capture=function(w)
             assert(w==h.world);h.shots=h.shots+1
             if h.onShoot then h.onShoot() end
             return true
         end}
    function h:new(studio)opts.studio=studio;return Selfie.new(opts)end
    function h:lookRig(actor,isPlayer)
        local mesh=actor.Mesh
        local node={BoneToModify={BoneName='head'},LookAt_Axis={Axis=point(1,0,0),bInLocalSpace=true},InterpolationTime=.5}
        local anim=object(mesh.path..'.LookPose',{AnimGraphNode_LookAt=node,bUseMultiThreadedAnimationUpdate=true})
        mesh.PrimaryComponentTick={bTickEvenWhenPaused=false}
        function mesh:GetOwner()return actor end
        function mesh:SetTickableWhenPaused(on)self.PrimaryComponentTick.bTickEvenWhenPaused=on end
        if isPlayer then
            actor.bInteractiveLookAt=false
            function mesh:GetPostProcessInstance()return anim end
            anim.LookAtLocation,anim.LookAtAlpha,anim.bLookAt=point(1,2,3),0,false
        end
        return anim
    end
    function h:frames() for _=1,2 do if c.owner then self.now=self.now+1/60;c.owner:frame(1/60,self.now) end end end
    return h
end

do
    local h=fixture()
    local selfie=h:new()
    for _=1,300 do selfie:tick() end
    assert(h.reads==0,'idle selfie must never scan the roster')
    h.camera.active=true
    assert(not selfie:toggle().ok and h.camera.active,'regular observation remains owned')
    h.camera.active=false
    assert(selfie:toggle().ok and selfie:status().target=='/Test.Near_C')
    assert(not selfie:shot().ok and h.shots==0)
    h.viewDelayed=true;h:frames()
    assert(not selfie:status().ready and not h.camera:isFrozen())
    h.viewDelayed=false;h:frames()
    assert(selfie:status().ready and h.camera:isFrozen() and selfie:status().posed==2)
    assert(h.player.rotation.Yaw~=22 and h.near.rotation.Yaw~=65)
    assert(h.player.pose.active.paused and h.near.pose.active.paused and selfie:shot().ok and h.shots==1)
    local origin=h.view.at
    local yaw=h.player.rotation.Yaw
    local hold=h.near.pose.active.at
    h.input={mx=30,wheel=1,turn=100}
    h:frames()
    local moved=h.view.at
    assert(moved.Y~=origin.Y and moved.X~=origin.X and h.camera:isFrozen(),'manual orbit and zoom move the paused camera')
    assert(h.player.rotation.Yaw==yaw and h.near.pose.active.at==hold,'lens movement cannot rotate or move the posed bodies')
    h.allBlocked=true;h:frames()
    assert(h.view.at==moved,'camera cannot pass through a blocking surface')
    h.allBlocked=false
    h.input={}
    assert(selfie:pose().ok);h:frames()
    assert(h.view.at==moved,'changing pose preserves a manually positioned camera')
    assert(selfie:status().style==2 and h.player.pose.active.at>1.5)
    assert(selfie:next().ok and h.near.rotation.Yaw==65 and not h.near.pose.active)
    h:frames()
    assert(selfie:status().posed==1 and selfie:status().target=='/Test.Nearless_C')
    assert(selfie:pose().ok);h:frames()
    assert(selfie:status().style==0 and selfie:status().posed==0 and not h.player.pose.active)
    assert(selfie:toggle().ok and not h.camera:isFrozen() and not h.camera:isActive())
    assert(h.player.rotation.Yaw==22 and h.far.rotation.Yaw==100 and h.player.hp==100)
end
do
    local h=fixture();local photo=h:new()
    h.player.busy=true
    assert(not photo:toggle().ok and not h.camera:isActive())
    h.player.busy=false;h.allBlocked=true
    assert(not photo:toggle().ok and not h.camera:isActive() and not h.player.pose.active)
    h.allBlocked=false;h.oneSideBlocked=true
    assert(photo:toggle().ok);h:frames()
    assert(math.abs(h.player.rotation.Yaw)>90,'blocked front view should use the opposite side')
    h.camera:stop('other camera command')
    assert(not photo:status().on and h.player.rotation.Yaw==22 and not h.player.pose.active)
end
do
    local h=fixture();local photo=h:new()
    h.rejectPausePose=true
    assert(not photo:toggle().ok and not h.camera:isActive() and not h.player.pose.active and h.player.rotation.Yaw==22)
    h.rejectPausePose=false;h.rejectFreeze=true
    assert(photo:toggle().ok);h:frames()
    assert(not photo:status().on and not h.camera:isActive() and not h.near.pose.active and h.near.rotation.Yaw==65)
    h.rejectFreeze=false;h.viewDelayed=true
    assert(photo:toggle().ok);h:frames()
    h.now=h.now+3;photo:tick()
    assert(not photo:status().on and not h.player.pose.active)
end
do
    local h=fixture();local photo=h:new()
    assert(photo:toggle().ok);h:frames()
    h.animMissing=true
    assert(not photo:toggle().ok and not h.camera:isActive() and h.player.rotation.Yaw==22 and h.player.pose.active)
    h.animMissing=false
    local reloaded=h:new()
    reloaded:tick()
    assert(not h.player.pose.active and not h.near.pose.active,'reload retries exact owned montage cleanup')
    assert(reloaded:toggle().ok);h:frames()
    h.near.alive=false
    h.now=h.now+2;reloaded:tick()
    assert(not reloaded:status().on and h.player.rotation.Yaw==22 and not h.player.pose.active)
end
do
    local h=fixture()
    local camera=h.camera
    local pc={IsValid=function()return true end}
    local fx,overlay={},{shown=false}
    function fx:pending()return false end
    function fx:release()return true end
    function fx:own()return true end
    function fx:subject()return true end
    function fx:optics(_,s)self.fov=s.fov;return true end
    function fx:bars(hide)self.hidden=hide;return true end
    function fx:light()return true end
    function overlay:open(_,p)assert(p==pc);self.shown=true;return true end
    function overlay:render(model)self.shown=model.visible;self.model=model;return true end
    function overlay:hide()
        if self.rejectHide then return false end
        self.shown=false
        return true
    end
    function overlay:detach()self.shown=false end
    local studio=require('photo_studio').new({world=function()return h.world end,getController=function()return pc end,
        find=function()end,visuals=fx,overlay=overlay})
    local photo=h:new(studio)
    h:lookRig(h.player,true)
    h.player.busy=true
    assert(photo:standard().ok,'ordinary photo must be available during combat')
    h.input={nav={}};h:frames()
    assert(photo:status().mode=='free' and camera:isFrozen() and fx.hidden and overlay.model.title=='普通拍照')
    local first=h.view.at
    h.input={forward=1,turn=100,speed=900,nav={}}
    h:frames()
    assert(h.view.at.X>first.X,'ordinary mode camera is free to travel')
    h.input={nav={up=false,down=true}};h:frames()
    h.input={nav={more=true}};h:frames()
    assert(fx.fov==82,'in-game camera menu sets field of view')
    h.onShoot=function()assert(not overlay.shown and fx.hidden and camera:isFrozen())end
    overlay.rejectHide=true
    assert(not photo:shot().ok and h.shots==0,'capture refuses a panel that did not hide')
    overlay.rejectHide=false
    assert(photo:shot().ok and h.shots==0)
    overlay.shown,overlay.rejectHide=true,true
    h.input={nav={}};h:frames();h:frames();h:frames()
    assert(h.shots==0,'capture checks again immediately before submitting the queued screenshot')
    overlay.rejectHide=false
    assert(photo:shot().ok and h.shots==0)
    h.input={nav={}};h:frames();h:frames();h:frames()
    assert(h.shots==1 and overlay.shown,'screenshot waits for the overlay to be hidden and then brings it back')
    local function press(k)
        h.input={nav={[k]=true}};h:frames()
        h.input={nav={}};h:frames()
    end
    press('prevTab')
    assert(overlay.model.tabs:find('〔人物〕',1,true) and overlay.model.rows[1].value=='关')
    assert(h.player.LookAtTarget==nil)
    press('more')
    assert(h.player.bInteractiveLookAt and h.player.LookAtTarget==h.view and h.player.rotation.Yaw==22)
    press('more')
    assert(not h.player.bInteractiveLookAt and h.player.LookAtTarget==nil and not h.player.Mesh.PrimaryComponentTick.bTickEvenWhenPaused)
    h.player.busy=false
    assert(photo:toggle().ok)
    h:frames();h:frames()
    assert(photo:status().mode=='duo' and photo:status().posed==2 and h.player.LookAtTarget==nil)
    assert(overlay.model.tabs:find('〔人物〕',1,true))
    assert(h.near.pose.active and h.near.pose.active.paused)
    local companionAt=h.near.pose.active.at
    h.input={nav={more=true}};h:frames()
    h.input={nav={}};h:frames();h:frames()
    assert(h.player.pose.active.at>1.5 and h.near.pose.active.at==companionAt,'posing the player must preserve the companion selection')
    assert(photo:standard().ok and not h.near.pose.active and h.near.rotation.Yaw==65 and camera:isFrozen())
    assert(photo:standard().ok and not camera:isFrozen() and not overlay.shown)
end
print('selfie: PASS free and duo sessions, independent posing, studio input, clean capture and recovery')
