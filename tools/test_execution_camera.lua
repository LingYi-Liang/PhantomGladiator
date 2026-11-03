package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Cam=require('execution_camera')
local function near(a,b,eps)return math.abs(a-b)<=(eps or 0.01)end

-- The pose: LookAt turned by the base yaw and set on the base; the camera ViewDistance back along ViewRotation.
do
    local anim={start=0,duration=5,frames={{0,0,0,100,0,0,0,300,0,0,0}}}
    local location,rotation,pivot=Cam.pose(anim,1,{X=10,Y=20,Z=30},0)
    assert(near(pivot.X,10) and near(pivot.Y,20) and near(pivot.Z,130))
    assert(near(location.X,-290) and near(location.Y,20) and near(location.Z,130) and near(rotation.Yaw,0))
    anim.frames={{0,100,0,0,-30,0,0,200,0,0,0}}
    location,rotation,pivot=Cam.pose(anim,0,{X=0,Y=0,Z=0},90)
    assert(near(pivot.X,0) and near(pivot.Y,100),'LookAt x turns with the base yaw')
    assert(near(rotation.Yaw,90) and near(rotation.Pitch,-30))
    -- 200 back along a view looking 30 degrees down, facing +Y: behind in Y and above.
    assert(near(location.X,0) and near(location.Y,100-200*math.cos(math.rad(30))) and near(location.Z,200*math.sin(math.rad(30))))
end
do
    local anim={frames={{0,0,0,0,0,0,90,0,0,10,20}}}
    local location=Cam.pose(anim,0,{X=0,Y=0,Z=0},0)
    assert(near(location.X,0) and near(location.Y,20) and near(location.Z,-10),'SocketOffset uses the full UE rotation, including roll')
end
-- Between frames: linear, angles the short way round; before the first frame and after the last, held.
do
    local anim={start=0,duration=5,frames={{1,0,0,0,0,170,0,100,0,0,0},{2,100,0,0,0,-170,0,300,0,0,0}}}
    local _,rotation,pivot=Cam.pose(anim,1.5,{X=0,Y=0,Z=0},0)
    assert(near(pivot.X,50) and (near(rotation.Yaw,180) or near(rotation.Yaw,-180)),'170 to -170 passes 180, not 0')
    _,_,pivot=Cam.pose(anim,0.2,{X=0,Y=0,Z=0},0);assert(near(pivot.X,0))
    _,_,pivot=Cam.pose(anim,9,{X=0,Y=0,Z=0},0);assert(near(pivot.X,100))
end
-- Blend: eased, ends exactly on the target pose, angles the short way.
do
    local l,r=Cam.blend({X=0,Y=0,Z=0},{Pitch=0,Yaw=170,Roll=0},{X=100,Y=0,Z=0},{Pitch=-20,Yaw=-170,Roll=0},0.5)
    assert(near(l.X,50) and (near(r.Yaw,180) or near(r.Yaw,-180)) and near(r.Pitch,-10))
    l=Cam.blend({X=0,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0},{X=100,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0},1.4);assert(near(l.X,100))
    l=Cam.blend({X=0,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0},{X=100,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0},0.1);assert(l.X<10,'eased in')
end

local address=0
local function object(name,fields)
    address=address+1;local a=address
    local o=fields or {}
    o.IsValid=function()return o.alive~=false end
    o.GetAddress=function()return a end
    o.GetFName=function()return {ToString=function()return name end}end
    return o
end
local function harness(files)
    local h={files=files or {},lines={},calls={},time=100,real=50,loops={},cancelled={},spawned={}}
    h.io={open=function(path,mode)
        if mode=='w' and h.failSave then return nil end
        if mode=='r' and h.files[path]==nil then return nil end
        local text=h.files[path] or ''
        return {read=function()return text end,write=function(_,s)text=s;return true end,
            close=function()if mode=='w' then h.files[path]=text end;return true end}
    end}
    h.pawn=object('BP_Player_Hero_Hun',{CapsuleComponent=object('Capsule',{GetScaledCapsuleHalfHeight=function()return 92 end})})
    h.manager=object('CameraManager',{GetCameraLocation=function()return {X=1,Y=2,Z=3} end,GetCameraRotation=function()return {Pitch=0,Yaw=45,Roll=0} end,
        GetFOVAngle=function()return 80 end})
    h.view=h.pawn
    h.pc=object('PlayerController',{PlayerCameraManager=h.manager,GetViewTarget=function()return h.view end})
    function h.pc:SetViewTargetWithBlend(target,blend)h.calls[#h.calls+1]='view '..target:GetFName():ToString()..' '..blend;h.view=target end
    h.world=object('World')
    h.lib=object('Default__GameplayStatics',{GetTimeSeconds=function()return h.time end,GetRealTimeSeconds=function()return h.real end})
    function h.lib:BeginDeferredActorSpawnFromClass(world,cls,transform)
        local camera=object('CameraActor_'..(#h.spawned+1),{at=transform.Translation})
        camera.CameraComponent=object('CameraComponent',{SetFieldOfView=function(_,fov)camera.fov=fov end})
        function camera:K2_SetActorLocationAndRotation(location,rotation)self.at,self.rot=location,rotation;return true end
        function camera:K2_GetActorLocation()return self.at end
        function camera:K2_DestroyActor()self.alive=false;h.calls[#h.calls+1]='destroy '..self:GetFName():ToString() end
        h.spawned[#h.spawned+1]=camera
        return camera
    end
    function h.lib:FinishSpawningActor()return true end
    h.found={['/Script/Engine.Default__GameplayStatics']=h.lib,['/Script/Engine.CameraActor']=object('CameraActor')}
    h.cameras={GA_Exec_C={clip='/x.y',executor=5,camera={start=1,duration=4,stop_yaw=3,frames={{0,0,0,100,0,0,0,300,0,0,0},{2,0,0,100,0,0,0,500,0,0,0}}}},
        GA_NoCamera_C={clip='/x.z',executor=3}}
    function h.new(extra)
        local options={log=function(s)h.lines[#h.lines+1]=s end,path='R',io=h.io,cameras=h.cameras,
            getController=function()return h.pc end,getWorld=function()return h.world end,getPlayer=function()return h.pawn end,
            staticFind=function(path)return h.found[path] end,fname=function(s)return s end,
            loop=function(ms,fn)h.loops[#h.loops+1]={ms=ms,fn=fn};return #h.loops end,
            cancel=function(handle)h.cancelled[handle]=true end}
        for k,v in pairs(extra or {})do options[k]=v end
        return Cam.new(options)
    end
    function h.frame()local l=h.loops[#h.loops];if l and not h.cancelled[#h.loops] then l.fn() end end
    function h.all()return table.concat(h.lines,'\n')end
    function h.has(text)for _,c in ipairs(h.calls)do if c==text then return true end end;return false end
    return h
end
-- An executor facing `yaw` whose borrowed skeleton is at clip position `clip`, its root at `root`.
local function scene(clip,root,yaw)
    local s={clip=clip,root=root,yaw=yaw or 0}
    s.body=object('SkeletalMeshComponent_0',{GetPosition=function()return s.clip end,GetSocketLocation=function(_,bone)assert(bone=='root');return s.root end})
    s.executor=object('BP_Monster_MoTian_0',{K2_GetActorLocation=function()return {X=-999,Y=0,Z=0} end,
        K2_GetActorRotation=function()return {Pitch=0,Yaw=s.yaw,Roll=0} end})
    s.target=object('BP_Monster_PengMeng_Axe_0')
    s.info={executor=s.executor,target=s.target,ability='GA_Exec_C',body=s.body,yaw=s.yaw}
    return s
end

-- The switch: off by default, saved with readback, a failed save keeps the old value, bad values refused.
do
    local h=harness()
    local cam=h.new()
    assert(cam:status().on==false and cam:status().state=='off')
    assert(cam:set('ON').ok and h.files['R/execution-camera.tsv']=='ExecutionCameraV1\ton=1\n' and cam:status().state=='waiting')
    assert(h.new():status().on==true,'the next Lua state reads it back')
    h.failSave=true
    assert(not cam:set('OFF').ok and cam:status().on==true)
    h.failSave=false
    assert(not cam:set('maybe').ok)
    assert(cam:set('OFF').ok and cam:status().on==false)
    cam:begin(scene(0,{X=0,Y=0,Z=0}).info)
    assert(#h.spawned==0 and #h.loops==0,'off: nothing happens')
end

-- On, player camera: a camera is spawned where the view is, the view blends to it, every frame follows the
-- borrowed skeleton (root + the player's half height), the clip time and the executor's facing. The end blends
-- back to the player and the camera goes three support ticks later.
do
    local h=harness({['R/execution-camera.tsv']='ExecutionCameraV1\ton=1\n'})
    local cam=h.new()
    local s=scene(0.5,{X=0,Y=0,Z=0},0)
    cam:begin(s.info)
    local camera=h.spawned[1]
    assert(camera and camera.fov==80 and h.has('view CameraActor_1 0.35') and cam:status().state=='running',h.all())
    assert(h.all():find('开始 动作=GA_Exec_C 镜头从第1.00s起 共4.00s 2帧 方式=生成镜头并切过去 原视角=BP_Player_Hero_Hun 玩家半身高=92 执行方朝向=0',1,true),h.all())
    h.frame()
    -- clip 0.5 is before the camera starts at 1: held at the first frame; facing +X.
    assert(near(camera.at.X,-300) and near(camera.at.Y,0) and near(camera.at.Z,192),h.all())
    s.clip=2;h.frame()
    -- one second into the camera: half way from 300 to 500.
    assert(near(camera.at.X,-400) and near(camera.at.Z,192))
    s.yaw=90;s.clip=2.5;h.frame()
    assert(near(camera.rot.Yaw,90) and near(camera.at.X,0) and camera.at.Y<0,'the camera turns with the executor, not with the target')
    s.clip=5.2;h.frame()
    assert(cam:status().state=='waiting' and h.cancelled[1] and h.has('view BP_Player_Hero_Hun 0.5'),h.all())
    assert(h.all():find('结束（镜头播完）帧数=3；切回原视角=true',1,true),h.all())
    cam:sweep();cam:sweep()
    assert(camera.alive~=false,'kept while the view blends back')
    cam:sweep()
    assert(camera.alive==false and h.has('destroy CameraActor_1'))
end

-- The view moved elsewhere meanwhile (the player entered the free camera): it is not pulled back.
-- The camera dying mid-run ends it as a failure. No camera for the pair: the view stays.
do
    local h=harness({['R/execution-camera.tsv']='ExecutionCameraV1\ton=1\n'})
    local cam=h.new()
    local s=scene(1.5,{X=0,Y=0,Z=0},0)
    cam:begin(s.info)
    h.view=object('FreeCameraActor')
    cam:finish('处决结束')
    assert(not h.has('view BP_Player_Hero_Hun 0.5') and h.all():find('视角已经不在处决镜头上，不切回',1,true),h.all())
    cam:begin(s.info)
    h.spawned[2].alive=false
    h.frame()
    assert(cam:status().failures==1 and h.all():find('结束（更新出错：',1,true),h.all())
    local before=#h.spawned
    s.info.ability='GA_NoCamera_C'
    cam:begin(s.info)
    assert(#h.spawned==before and h.all():find('这对处决没有镜头数据，保持原视角：GA_NoCamera_C',1,true))
end

-- In the free camera its own camera is borrowed: it eases from where the player left it into the execution (0.35 s),
-- and at the end eases back there (0.5 s) before it is given back; the view target never changes.
do
    local h=harness({['R/execution-camera.tsv']='ExecutionCameraV1\ton=1\n'})
    local free=object('FreeCamera')
    local own=object('FreeCameraActor',{at={X=1000,Y=0,Z=500},rot={Pitch=0,Yaw=0,Roll=0}})
    function own:K2_SetActorLocationAndRotation(location,rotation)self.at,self.rot=location,rotation;return true end
    function own:K2_GetActorLocation()return self.at end
    free.isActive=function()return true end
    free.borrow=function()h.calls[#h.calls+1]='borrow';return own,{X=1000,Y=0,Z=500},{Pitch=0,Yaw=0,Roll=0} end
    free.release=function()h.calls[#h.calls+1]='release';own.at={X=1000,Y=0,Z=500};return true end
    local cam=h.new({freeCamera=free})
    local s=scene(1.5,{X=0,Y=0,Z=0},0)
    cam:begin(s.info)
    h.frame()
    assert(h.has('borrow') and #h.spawned==0 and near(own.at.X,1000) and not h.has('view FreeCameraActor 0.35'),'starts where the player left it')
    assert(h.all():find('方式=借用自由观战的镜头，0.35 秒过渡进入',1,true),h.all())
    h.real=50.2;h.frame()
    assert(own.at.X<1000 and own.at.X>-350,'on the way in')
    h.real=50.4;h.frame()
    assert(near(own.at.X,-350),'in the execution camera once the blend is over')
    cam:finish('处决结束')
    assert(not h.has('release') and cam:status().state=='waiting','eases back first')
    h.real=50.65;h.frame()
    assert(own.at.X>-350 and own.at.X<1000 and not h.has('release'))
    h.real=51;h.frame()
    assert(h.has('release') and h.cancelled[1],h.all())
    assert(h.all():find('0.5 秒过渡回自由观战的位置',1,true) and h.all():find('还给自由观战 位置读回=true',1,true),h.all())
    -- Turning the switch off mid-run eases back the same way; a new execution meanwhile gives it back at once.
    -- Ended before its first frame, there is nothing to ease from: given back at once.
    cam:begin(s.info)
    h.frame()
    assert(cam:set('OFF').ok and cam:status().state=='off')
    assert(h.all():find('结束（关掉了处决镜头）帧数=1；0.5 秒过渡回自由观战的位置',1,true),h.all())
    assert(cam:set('ON').ok)
    cam:begin(s.info)
    assert(h.all():find('上一段还在过渡回去，直接还给自由观战',1,true),h.all())
    cam:finish('处决结束')
    assert(h.all():find('结束（处决结束）帧数=0；还给自由观战 位置读回=true',1,true),h.all())
end

-- A QTE execution's next stage: its own track from its clip's start, eased in from where the camera is; an empty
-- track or no run is refused.
do
    local h=harness({['R/execution-camera.tsv']='ExecutionCameraV1\ton=1\n'})
    local cam=h.new()
    local s=scene(1.5,{X=0,Y=0,Z=0},0)
    assert(cam:stage({start=0,duration=1,frames={{0,0,0,100,0,0,0,800,0,0,0}}})==false,'no run')
    cam:begin(s.info)
    h.frame()
    local camera=h.spawned[1]
    local before=camera.at.X
    assert(cam:stage({start=0,duration=1,frames={}})==false)
    assert(cam:stage({start=0,duration=1,frames={{0,0,0,100,0,0,0,800,0,0,0}}},'SingleA')==true)
    assert(h.all():find('换段 第1段 SingleA 镜头从第0.00s起 共1.00s 1帧 0.35 秒过渡',1,true),h.all())
    s.clip=0.1;h.real=h.real+0.1;h.frame()
    assert(camera.at.X<before and camera.at.X>-800 and cam:status().state=='running','eased toward the new track, not finished')
    h.real=h.real+1;h.frame()
    assert(near(camera.at.X,-800),h.all())
end

-- Without a borrowed skeleton: the executor's own location and the game clock.
do
    local h=harness({['R/execution-camera.tsv']='ExecutionCameraV1\ton=1\n'})
    local cam=h.new()
    local s=scene(0,{X=0,Y=0,Z=0},30)
    s.info.body=nil
    cam:begin(s.info)
    h.time=102;h.frame()
    local camera=h.spawned[1]
    assert(near(camera.rot.Yaw,30) and near(camera.at.Z,100),h.all())
end
do
    local h=harness({['R/execution-camera.tsv']='ExecutionCameraV1\ton=1\n'})
    local cam=h.new();local s=scene(6.86,{X=0,Y=0,Z=0},0)
    s.info.clip_from=5.36;s.info.rate=1
    cam:begin(s.info);h.real=50.4;h.frame()
    assert(cam:status().state=='running' and near(h.spawned[1].at.X,-350),'a trimmed animation uses montage-relative camera time')
end
do
    local h=harness({['R/execution-camera.tsv']='ExecutionCameraV1\ton=1\n'})
    local borrowed,released=0,0
    local own=object('ChainCamera',{at={X=1000,Y=0,Z=500}})
    function own:K2_SetActorLocationAndRotation(location,rotation)self.at=location;return true end
    function own:K2_GetActorLocation()return self.at end
    local free={isActive=function()return true end,borrow=function()borrowed=borrowed+1;return own,{X=1000,Y=0,Z=500},{Pitch=0,Yaw=0,Roll=0}end,
        release=function()released=released+1;own.at={X=1000,Y=0,Z=500};return true end}
    local cam=h.new({freeCamera=free});local s=scene(1,{X=0,Y=0,Z=0})
    cam:begin(s.info);h.real=50.4;h.frame()
    s.info.continuing=true;s.info.camera={start=0,duration=4,frames={{0,0,0,100,0,0,0,900,0,0,0}}}
    cam:begin(s.info);h.real=50.8;h.frame()
    assert(borrowed==1 and released==0 and near(own.at.X,-900),'native continuation reuses the camera without returning home mid-chain')
    cam:finish('done');h.real=51.4;h.frame()
    assert(released==1 and near(own.at.X,1000),'the whole chain returns to the original observation point')
end
print('execution_camera ok')
