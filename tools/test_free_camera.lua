package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Camera=require('free_camera')
local function harness()
    local h={objects={},files={},timers={},time=1,input={},logs={},spawned=0,engineCalls=0,actions=0,inputActors={},clockCalls=0,sequenceCount=0}
    local serial=0
    local function object(path,fields)
        serial=serial+1
        local o=fields or {};o.key=serial;o.alive=true;o.path=path
        function o:IsValid()return self.alive end
        function o:GetAddress()assert(self.alive,'accessed invalid object');return self.key end
        function o:GetFullName()assert(self.alive);return 'Object '..self.path end
        h.objects[path]=o;return o
    end
    h.world=object('/Test.World')
    -- The world's time dilation (时停), behind PersistentLevel.WorldSettings as in the game.
    h.worldSettings=object('/Test.World:PersistentLevel.WorldSettings',{TimeDilation=1.0})
    h.world.PersistentLevel=object('/Test.World:PersistentLevel',{WorldSettings=h.worldSettings})
    -- The older cases follow the keys at once (smoothing 0); the eased ones set their own.
    h.files['memory/free-camera-settings.tsv']='FreeCameraSettingsV1\nspeed\t900\nturn\t100\nsmooth\t0\n'
    h.player=object('/Test.LocalPlayer')
    h.pawn=object('/Test.World:PersistentLevel.Player')
    function h.pawn:GetOuter()assert(self.alive);return h.world end
    h.pawn.AbilitySystemComponent=object('/Test.World:PersistentLevel.Player.ASC')
    function h.pawn.AbilitySystemComponent:GetGameplayTagCount(tag)
        assert(self.alive and tag.TagName=='CharacterState.InLevelSequence')
        return h.sequenceCount
    end
    h.pc=object('/Test.World:PersistentLevel.PC',{Pawn=h.pawn,Player=h.player,moveDepth=0,lookDepth=0,target=h.pawn,
        bShouldPerformFullTickWhenPaused=false})
    h.player.PlayerController=h.pc
    -- APBZPlayerController.SetCameraMoveableWhenPaused; with pbzFullTick it also sets the engine's full-tick flag.
    function h.pc:SetCameraMoveableWhenPaused(on)
        assert(self.alive and type(on)=='boolean');self.moveable=on
        if h.pbzFullTick then self.bShouldPerformFullTickWhenPaused=on end
    end
    function h.pc:GetViewTarget()assert(self.alive);return self.target end
    function h.pc:SetViewTargetWithBlend(target,seconds,mode,exp,lock)
        assert(self.alive and target:IsValid() and seconds==0 and mode==0 and lock==false)
        if not h.rejectView then self.target=target end
    end
    function h.pc:IsMoveInputIgnored()assert(self.alive);return self.moveDepth>0 end
    function h.pc:IsLookInputIgnored()assert(self.alive);return self.lookDepth>0 end
    function h.pc:SetIgnoreMoveInput(on)assert(self.alive);self.moveDepth=math.max(0,self.moveDepth+(on and 1 or -1))end
    function h.pc:SetIgnoreLookInput(on)assert(self.alive);self.lookDepth=math.max(0,self.lookDepth+(on and 1 or -1))end
    function h.pc:GetInputAnalogKeyState(k)
        assert(self.alive and type(k)=='table' and type(k.KeyName)=='string')
        if h.badInput then return nil end
        return h.input[k.KeyName] or 0
    end
    h.manager=object('/Test.World:PersistentLevel.Manager')
    -- With povFollows the camera manager shows the observer camera (it updates while paused).
    function h.manager:GetCameraLocation()if h.povFollows and h.camera then return h.camera.position end;return {X=100,Y=200,Z=300}end
    function h.manager:GetCameraRotation()return {Pitch=0,Yaw=0,Roll=0}end
    function h.manager:GetFOVAngle()return 80 end
    h.pc.PlayerCameraManager=h.manager
    h.lib=object('/Script/Engine.Default__GameplayStatics')
    object('/Script/Engine.CameraActor')
    function h.lib:GetRealTimeSeconds(world)
        h.clockCalls=h.clockCalls+1
        assert(world==h.world and world:IsValid())
        return h.time
    end
    function h.lib:SetGlobalTimeDilation(world,value)
        assert(world==h.world and world:IsValid())
        h.worldSettings.TimeDilation=math.max(0.0001,math.min(20,value))
    end
    -- The game's pause (时停): GameplayStatics.SetGamePaused and IsGamePaused.
    h.paused=false
    function h.lib:IsGamePaused(world)assert(world==h.world and world:IsValid());return h.paused end
    function h.lib:SetGamePaused(world,on)
        assert(world==h.world and world:IsValid() and type(on)=='boolean')
        if not (h.rejectPause and on) then h.paused=on end
        return h.paused==on
    end
    function h.lib:BeginDeferredActorSpawnFromClass(...)
        local world,cls,t,collision,owner,scale=...
        assert(select('#',...)==6 and world==h.world and cls==h.objects['/Script/Engine.CameraActor'])
        assert(collision==1 and owner==nil and scale==1 and t.Rotation.W==1)
        h.spawned=h.spawned+1
        if h.unknownSpawn then return nil end
        local camera=object('/Test.World:PersistentLevel.Observer'..h.spawned,{position=t.Translation,rotation={Pitch=0,Yaw=0,Roll=0}})
        function camera:K2_GetActorLocation()assert(self.alive);return self.position end
        function camera:K2_SetActorLocationAndRotation(p,r,sweep,hit,teleport)
            assert(self.alive and sweep==false and type(hit)=='table' and teleport==true)
            if h.rejectMove then return false end
            self.position,self.rotation=p,r;return true
        end
        function camera:K2_DestroyActor()assert(self.alive);self.alive=false;self.inputActive=false end
        function camera:IsActorBeingDestroyed()assert(self.alive);return false end
        function camera:EnableInput(pc)
            assert(self.alive and pc==h.pc)
            self.inputActive=true;h.inputActors[#h.inputActors+1]=self
            if h.rejectInputLayer then return end
            self.InputComponent=object(self.path..'.InputComponent')
            function self.InputComponent:GetOwner()assert(self.alive);return camera end
        end
        function camera:DisableInput(pc)assert(self.alive and pc==h.pc);self.inputActive=false end
        local component=object(camera.path..'.CameraComponent')
        function component:GetOwner()assert(self.alive);return camera end
        function component:SetFieldOfView(fov)assert(self.alive);self.FieldOfView=fov end
        camera.CameraComponent=component
        h.camera=camera;return camera
    end
    function h.lib:FinishSpawningActor(camera,t,scale)
        assert(camera==h.camera and scale==1)
        if h.rejectFinish then error('fixture finish failure')end
        return camera
    end
    local fs={open=function(path,mode)
        if mode=='r' and not h.files[path] then return nil end
        local text=h.files[path] or ''
        return {write=function(_,value)text=value;return true end,
            read=function()return text end,
            close=function()if mode=='w' then h.files[path]=text end;return true end}
    end}
    StaticFindObject=function(path)h.engineCalls=h.engineCalls+1;return h.objects[path]end
    FName=function(name)return name end
    LoopInGameThreadWithDelay=function(ms,callback)
        assert(ms==16)
        local handle=#h.timers+1;h.timers[handle]={callback=callback}
        if h.rejectTimer then return nil end
        return handle
    end
    CancelDelayedAction=function(handle)assert(h.timers[handle]);h.timers[handle].cancelled=true end
    h.options={path='memory',io=fs,log=function(s)h.logs[#h.logs+1]=s end,
        getController=function()return h.pc end,getWorld=function()return h.world end}
    function h:new()return Camera.new(self.options)end
    function h:tick()
        self.time=self.time+0.02
        for _,t in ipairs(self.timers)do if not t.cancelled then t.callback()end end
    end
    function h:pressAction()
        for _,actor in ipairs(self.inputActors)do
            if actor.alive and actor.inputActive and actor.bBlockInput and actor.InputPriority>0 then return end
        end
        self.actions=self.actions+1
    end
    h.cameraController=h:new()
    return h
end
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end

test('observer blocks player actions while raw movement remains available and restores on exit',function()
    local h=harness();h:pressAction();assert(h.actions==1)
    assert(h.cameraController:enter());h:pressAction()
    assert(h.actions==1,'Space/attack actions must not reach the player during observation')
    h.input.W=1;h:tick();assert(h.camera.position.X>100)
    assert(h.cameraController:stop('F6'));h:pressAction();assert(h.actions==2)
end)

test('E or Space raises the camera, Q or Ctrl lowers it',function()
    local h=harness();assert(h.cameraController:enter())
    local function height(keys)
        h.input={};for k,v in pairs(keys)do h.input[k]=v end
        local before=h.camera.position.Z;h.time=h.time+0.05;h:tick();return h.camera.position.Z-before
    end
    assert(height({SpaceBar=1})>0 and height({E=1})>0,'Space and E go up')
    assert(height({LeftControl=1})<0 and height({RightControl=1})<0 and height({Q=1})<0,'either Ctrl and Q go down')
    assert(height({SpaceBar=1,E=1})==height({SpaceBar=1}),'Space and E together are not faster')
    assert(height({SpaceBar=1,LeftControl=1})==0,'up and down cancel')
end)

test('view target changes without replacing PlayerController, Player or Pawn; exit restores',function()
    local h=harness();local c=h.cameraController
    assert(c:enter() and c:isActive())
    assert(h.pc.target==h.camera and h.pc.Player==h.player and h.pc.Pawn==h.pawn and h.player.PlayerController==h.pc)
    assert(h.pc.moveDepth==1 and h.pc.lookDepth==1)
    assert(h.camera.CameraComponent.FieldOfView==80)
    h.options.getController=function()error('no controller enumeration per frame')end
    h.options.getWorld=function()error('no world enumeration per frame')end
    h.input.W=1;h.input.MouseX=2;h:tick()
    assert(c:isActive() and h.camera.position.X>100 and h.camera.rotation.Yaw==2)
    assert(c:stop('F7') and not h.camera.alive and h.pc.target==h.pawn)
    assert(h.pc.moveDepth==0 and h.pc.lookDepth==0 and not c:hasPending())
    h.timers[1].callback();assert(not h.camera.alive,'retained callback is inert after exit')
end)
test('the view is told only while the player has the camera',function()
    local h=harness();local c=h.cameraController
    assert(c:view()==nil,'not running')
    assert(c:enter())
    h.input.W=1;h.input.MouseX=30;h:tick()
    local position,rotation=c:view()
    assert(position.X==h.camera.position.X and rotation.Yaw==h.camera.rotation.Yaw)
    assert(c:borrow());assert(c:view()==nil,'lent to the execution camera')
    assert(c:release());assert(c:view()~=nil)
    assert(c:stop('F7'));assert(c:view()==nil,'stopped')
end)
test('while following, the track says where the camera goes; a failure or an end falls back to the free camera',function()
    local h=harness();local c=h.cameraController
    local track={on=true,stops={}}
    function track:running()return self.on end
    function track:stop(why)self.stops[#self.stops+1]=why;self.on=false end
    function track:frame(dt,now,input)
        self.input=input
        if self.fail then error('boom') end
        return self.position,{Pitch=-12,Yaw=725,Roll=0}
    end
    h.options.track=function()return track end
    assert(c:enter())
    track.position={X=1234,Y=567,Z=89}
    h.input.W=1;h.input.MouseX=2;h.input.MouseWheelAxis=3;h.input.E=1;h.input.LeftShift=1;h:tick()
    assert(h.camera.position.X==1234 and h.camera.position.Y==567 and h.camera.rotation.Pitch==-12,'moved where it said')
    assert(track.input.mx==2 and track.input.forward==1 and track.input.up==1 and track.input.wheel==3 and track.input.fast==true)
    assert(track.input.speed==c:settings().speed and track.input.turn==c:settings().turn and track.input.smooth==c:settings().smooth)
    -- The free camera carries on from there, not from where it last aimed.
    track.on=false;h.input={}
    h:tick()
    assert(h.camera.position.X==1234,'still, no keys')
    local yaw=h.camera.rotation.Yaw
    assert(math.abs(((yaw-5+180)%360)-180)<0.01,yaw)
    -- A wheel that does not read is no wheel.
    track.on=true;track.position={X=1,Y=2,Z=3};h:tick()
    assert(track.input.wheel==0)
    -- An error ends the following, not the camera.
    track.fail=true;h.input.W=1;h:tick()
    assert(c:isActive() and track.stops[1]=='出错' and h.camera.position.X>1,'carries on as the free camera')
    track.fail=false;track.on=true
    -- nil from the track: this frame is the free camera's.
    track.position=nil;local x=h.camera.position.X;h:tick()
    assert(h.camera.position.X>x)
    -- Leaving the camera ends the following, and borrowing pauses it.
    track.position={X=5,Y=5,Z=5};track.input=nil
    assert(c:borrow());h:tick();assert(track.input==nil,'lent to the execution camera')
    assert(c:release())
    assert(c:stop('F7'));assert(track.stops[#track.stops]=='退出自由观战')
end)
test('the field of view is told while the camera runs',function()
    local h=harness();local c=h.cameraController
    assert(c:fieldOfView()==nil)
    assert(c:enter());assert(c:fieldOfView()==80)
    assert(c:stop('F7'));assert(c:fieldOfView()==nil)
end)
test('preexisting guards and another systems increment are preserved',function()
    local h=harness();h.pc.moveDepth=2;h.pc.lookDepth=1
    assert(h.cameraController:enter());assert(h.cameraController:stop('F7'))
    assert(h.pc.moveDepth==2 and h.pc.lookDepth==1)
    h=harness();assert(h.cameraController:enter());h.pc.moveDepth=h.pc.moveDepth+1
    assert(h.cameraController:stop('F7'));assert(h.pc.moveDepth==1)
    assert(h.cameraController:stop('F7'));assert(h.pc.moveDepth==1,'never release someone elses counter twice')
end)
test('failed view target, finish or timer registration rolls back only owned changes',function()
    for _,failure in ipairs({'rejectView','rejectFinish','rejectTimer','rejectInputLayer'})do
        local h=harness();h[failure]=true
        assert(not h.cameraController:enter(),failure)
        assert(not h.cameraController:isActive() and not h.cameraController:hasPending())
        assert(not h.camera.alive and h.pc.target==h.pawn and h.pc.moveDepth==0 and h.pc.lookDepth==0,failure)
        h:pressAction();assert(h.actions==1,'failed entry must not leave an input blocker')
        for _,timer in ipairs(h.timers)do timer.callback()end
    end
end)
test('input signature is checked before creating an actor or restricting input',function()
    local h=harness();h.badInput=true
    assert(not h.cameraController:enter() and h.spawned==0 and h.pc.moveDepth==0)
end)
test('movement failure restores view and controls instead of leaving the player stuck',function()
    local h=harness();assert(h.cameraController:enter());h.rejectMove=true;h.input.W=1;h:tick()
    assert(not h.cameraController:isActive() and not h.cameraController:hasPending())
    assert(h.pc.target==h.pawn and h.pc.moveDepth==0 and h.pc.lookDepth==0)
end)
test('hot reload cancels work without touching UObjects and the new module restores the journal',function()
    local h=harness();local first=h.cameraController;assert(first:enter())
    local calls=h.engineCalls;first:silence();assert(h.engineCalls==calls,'unload must not inspect engine objects')
    assert(h.pc.target==h.camera and h.pc.moveDepth==1)
    h.timers[1].callback();assert(h.engineCalls==calls)
    local reloaded=h:new();assert(reloaded:hasPending());reloaded:recover()
    assert(not reloaded:hasPending() and h.pc.target==h.pawn and not h.camera.alive)
    assert(h.pc.moveDepth==0 and h.pc.lookDepth==0)
    h:pressAction();assert(h.actions==1,'reload must remove the owned action blocker')
end)
test('game-selected view target is not overwritten on stop',function()
    local h=harness();assert(h.cameraController:enter())
    h.pc.target=h.manager
    assert(h.cameraController:stop('F7') and h.pc.target==h.manager)
end)
test('a story sequence ends following and releases only the observer input',function()
    for _,takesView in ipairs({false,true})do
        local h=harness();local c=h.cameraController
        local track={on=true,frames=0}
        function track:running()return self.on end
        function track:frame()self.frames=self.frames+1 end
        function track:stop()self.on=false end
        h.options.track=function()return track end
        assert(c:enter());h:tick();assert(track.frames==1)
        h.sequenceCount=1
        h.pc.moveDepth=h.pc.moveDepth+1;h.pc.lookDepth=h.pc.lookDepth+1
        if takesView then h.pc.target=h.manager end
        h.time=h.time+0.25;h:tick()
        assert(not c:isActive() and not c:hasPending() and not h.camera.alive,'story leaves no observer camera')
        assert(not track.on and track.frames==1,'the story check runs before another follow update')
        assert(h.pc.target==(takesView and h.manager or h.pawn),'restore the player view only while we own it')
        assert(h.pc.moveDepth==1 and h.pc.lookDepth==1,'leave the story input lock in place')
    end
end)
test('observation cannot start while a story sequence owns the player',function()
    local h=harness();local c=h.cameraController
    h.sequenceCount=1
    assert(not c:enter() and h.spawned==0 and h.pc.target==h.pawn and not c:hasPending())
    h.sequenceCount=0
    assert(c:enter() and h.spawned==1,'observation is available again after the story')
    assert(c:stop('F7'))
end)
test('a destroyed world is rejected before passing it to the native clock',function()
    local h=harness();local c=h.cameraController
    assert(c:enter());h:tick()
    local before=h.clockCalls
    h.world.alive=false;h:tick()
    assert(h.clockCalls==before,'the dead world must never reach GetRealTimeSeconds')
    assert(not c:isActive() and not c:hasPending())
end)
test('invalid original controller does not modify the replacement controller',function()
    local h=harness();assert(h.cameraController:enter())
    h.pc.alive=false
    h.cameraController:tick()
    assert(not h.cameraController:isActive() and not h.camera.alive)
    assert(h.pc.moveDepth==1,'invalid object must not be called')
end)
test('unconfirmed native creation cannot be retried into duplicate unknown objects',function()
    local h=harness();h.unknownSpawn=true
    assert(not h.cameraController:enter() and h.cameraController:hasPending())
    assert(not h.cameraController:enter() and h.spawned==1)
    assert(h.pc.target==h.pawn and h.pc.moveDepth==0 and h.pc.lookDepth==0)
    h.options.getWorld=function()return nil end
    assert(not h.cameraController:stop('loading') and h.cameraController:hasPending(),'unknown world must not discard an uncertain creation')
end)
test('observer lifecycle is journaled, ticked while stationary and restored before camera destruction',function()
    local h=harness();local ticks,restores=0,0
    h.options.guard={fields={'guard_fixture'},enter=function(_,c)
        assert(c.pc==h.pc and c.pawn==h.pawn and c.camera==h.camera)
        c.record.guard_fixture='owned';c.save()
    end,tick=function()ticks=ticks+1 end,stop=function(_,c)
        if c.record.guard_fixture then assert(c.camera.alive);restores=restores+1 end
        return true
    end}
    local camera=h:new();assert(camera:enter());h:tick();assert(ticks==1,'idle camera must still maintain protection')
    camera:silence();local nextCamera=h:new();nextCamera:recover()
    assert(restores==1 and not nextCamera:hasPending() and not h.camera.alive)
end)
test('observer entry failure rolls back the camera and original input association',function()
    local h=harness();local restored=false
    h.options.guard={fields={},enter=function()error('fixture protection failure')end,tick=function()end,
        stop=function()restored=true;return true end}
    local camera=h:new();assert(not camera:enter())
    assert(restored and not camera:hasPending() and h.pc.target==h.pawn and h.pc.moveDepth==0)
end)
test('the view updates once a frame when the host offers it, else every 16 ms',function()
    local h=harness();local frames={}
    LoopInGameThreadAfterFrames=function(n,callback)assert(n==1);frames[#frames+1]=callback;return 'frame-handle'end
    local cancelled
    local old=CancelDelayedAction;CancelDelayedAction=function(handle)cancelled=handle end
    local c=h:new();assert(c:enter())
    assert(#frames==1 and #h.timers==0,'one frame loop, no 16 ms timer')
    assert(table.concat(h.logs,'\n'):find('更新=frame',1,true))
    h.input.W=1;h.time=h.time+0.016;frames[1]()
    assert(h.camera.position.X>100)
    assert(c:stop('F7') and cancelled=='frame-handle')
    LoopInGameThreadAfterFrames=nil;CancelDelayedAction=old
    local fallback=harness();assert(fallback.cameraController:enter() and #fallback.timers==1)
    assert(table.concat(fallback.logs,'\n'):find('更新=16ms',1,true))
end)
test('smoothing eases starts, stops and turns; the camera glides to rest and then sends nothing',function()
    local h=harness();h.files['memory/free-camera-settings.tsv']='FreeCameraSettingsV1\nspeed\t1000\nturn\t100\nsmooth\t100\n'
    local c=h:new();assert(c:enter())
    local function step(seconds)h.time=h.time+seconds;h.timers[#h.timers].callback()end
    h.input.W=1
    local x0=h.camera.position.X;step(0.016);local first=h.camera.position.X-x0
    for _=1,150 do step(0.016) end
    local x1=h.camera.position.X;step(0.016);local cruising=h.camera.position.X-x1
    assert(first>0 and first<cruising*0.2,'eases in: the first frame moves far less than at speed')
    assert(math.abs(cruising-1000*0.016)<0.5,'reaches the set speed')
    h.input.W=nil
    local x2=h.camera.position.X;step(0.016)
    assert(h.camera.position.X>x2,'glides on after the key is let go')
    for _=1,200 do step(0.016) end
    local rest=h.camera.position.X;step(0.016)
    assert(h.camera.position.X==rest,'comes to rest')
    local moves=0;local set=h.camera.K2_SetActorLocationAndRotation
    h.camera.K2_SetActorLocationAndRotation=function(...)moves=moves+1;return set(...)end
    step(0.016);step(0.016);assert(moves==0,'nothing is sent while settled')
    h.input.MouseX=30;step(0.016);h.input.MouseX=nil
    local yaw=h.camera.rotation.Yaw;assert(yaw>0 and yaw<30,'the view eases toward the aim')
    for _=1,120 do step(0.016) end
    assert(math.abs(h.camera.rotation.Yaw-30)<0.05,'and arrives')
end)
test('speed, turn and smoothing are checked, saved, read back and kept after a reload',function()
    local h=harness();local c=h.cameraController
    local saved=c:configure(1500,150,25)
    assert(saved.ok and h.files['memory/free-camera-settings.tsv']=='FreeCameraSettingsV1\nspeed\t1500\nturn\t150\nsmooth\t25\n')
    assert(saved.message=='自由视角：移动速度 1500，转向 150%，平滑 25%',saved.message)
    for _,bad in ipairs({{50,100,40},{900,10,40},{900,100,101},{900.5,100,40},{nil,100,40}})do
        local r=c:configure(bad[1],bad[2],bad[3])
        assert(not r.ok and r.message:find('超出范围',1,true))
    end
    assert(c:settings().speed==1500,'a refused change leaves the saved one')
    local again=h:new();local s=again:settings();assert(s.speed==1500 and s.turn==150 and s.smooth==25)
    h.files['memory/free-camera-settings.tsv']='FreeCameraSettingsV1\nspeed\t99999\nturn\t100\nsmooth\t40\n'
    local fallback=h:new();assert(fallback:settings().speed==900,'an invalid file falls back to the defaults')
    assert(c:configure(1500,150,0).ok and c:enter());h.input.W=1;local x=h.camera.position.X;h:tick()
    assert(math.abs(h.camera.position.X-x-1500*0.02)<0.01,'the new speed is used at once')
end)
test('time stop pauses the game, the camera keeps moving, and the game resumes on release, on exit and after a reload',function()
    local h=harness();local c=h.cameraController
    assert(not c:freeze(true).ok,'only while observing')
    assert(c:enter())
    local r=c:freeze(true)
    assert(r.ok and h.paused and c:isFrozen(),r.message)
    assert(h.pc.moveable==true and h.pc.bShouldPerformFullTickWhenPaused==true,'the view follows the camera while paused')
    local journal=h.files['memory/free-camera.tsv']
    assert(journal:find('paused\t1\n',1,true) and journal:find('moveable\t1\n',1,true) and journal:find('full_tick\t1\n',1,true))
    -- Real time moves the camera; once it has left the spot, the view is read back.
    h.povFollows=true;h.input.W=1;local x=h.camera.position.X
    for _=1,15 do h:tick() end
    h.time=h.time+0.3;h:tick()
    assert(h.camera.position.X>x+200,'the camera still moves while paused')
    assert(table.concat(h.logs,'\n'):find('画面跟随=true',1,true))
    -- Something resumes the game (a menu of its own closing): paused again at the next check.
    h.paused=false;h.time=h.time+0.3;h:tick()
    assert(h.paused and table.concat(h.logs,'\n'):find('重新暂停 第1次',1,true))
    local off=c:freeze(false)
    assert(off.ok and not h.paused and not c:isFrozen() and h.pc.moveable==false and h.pc.bShouldPerformFullTickWhenPaused==false)
    journal=h.files['memory/free-camera.tsv']
    assert(journal:find('paused\t\n',1,true) and journal:find('moveable\t\n',1,true) and journal:find('full_tick\t\n',1,true))
    -- Leaving the camera while frozen resumes the game.
    assert(c:freeze(true).ok and c:stop('F7') and not h.paused and h.pc.bShouldPerformFullTickWhenPaused==false and not c:hasPending())
    -- A reload while frozen: the journal resumes the game and puts the controller's flags back.
    local h2=harness();assert(h2.cameraController:enter() and h2.cameraController:freeze(true).ok)
    h2.cameraController:silence();assert(h2.paused)
    local reloaded=h2:new();reloaded:recover()
    assert(not h2.paused and h2.pc.moveable==false and h2.pc.bShouldPerformFullTickWhenPaused==false and not reloaded:hasPending())
    -- A controller whose own setter turns on the full tick: that flag is not this camera's to put back.
    local h3=harness();h3.pbzFullTick=true;assert(h3.cameraController:enter() and h3.cameraController:freeze(true).ok)
    assert(h3.files['memory/free-camera.tsv']:find('full_tick\t\n',1,true))
    assert(h3.cameraController:freeze(false).ok and h3.pc.bShouldPerformFullTickWhenPaused==false)
    -- Already paused by the game (a menu): refused, nothing touched.
    local h4=harness();assert(h4.cameraController:enter());h4.paused=true
    local busy=h4.cameraController:freeze(true)
    assert(not busy.ok and h4.paused and h4.pc.moveable==nil and not h4.cameraController:isFrozen())
    -- A game that will not pause: refused, the controller's flags put back.
    local h5=harness();assert(h5.cameraController:enter());h5.rejectPause=true
    local refused=h5.cameraController:freeze(true)
    assert(not refused.ok and not h5.paused and h5.pc.moveable==false and h5.pc.bShouldPerformFullTickWhenPaused==false)
    assert(not h5.cameraController:isFrozen() and h5.cameraController:stop('F7') and not h5.cameraController:hasPending())
    -- A journal of the first 0.38.2 build, frozen by the time dilation, still puts the time back.
    local h6=harness();assert(h6.cameraController:enter());h6.cameraController:silence()
    h6.worldSettings.TimeDilation=0.0001
    h6.files['memory/free-camera.tsv']=h6.files['memory/free-camera.tsv']:gsub('time_before\t\n','time_before\t1\n')
    local old=h6:new();old:recover()
    assert(h6.worldSettings.TimeDilation==1 and not old:hasPending())
end)
print('free_camera: PASS ('..passed..' control, recovery and ownership regressions; no game accessed)')
