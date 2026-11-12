-- 处决镜头: while an arena execution runs (arena_executions.lua) the view plays the camera the player gets in that
-- execution: the executor ability's LGAAction_CameraAnim keyframes (execution_data.lua, generated offline), placed the
-- way the game places them. Each frame's LookAt is turned by a base yaw and set on the executor's location; the camera
-- sits ViewDistance back along ViewRotation, whose yaw is added to the same base yaw. In the game that yaw comes from
-- the executor toward its target (CameraAnimRotationProvider_Execution) after the executor has been warped to face it;
-- the arena turns the executor to face its target first and the borrowed body plays along the executor's facing, so
-- the base yaw here is the executor's own facing (following the target instead put the camera askew).
-- The executor's visible body is the borrowed player skeleton, which keeps the clip's root motion in its pose, so the
-- executor's location is that skeleton's root bone plus the player's capsule half height, and the time is that
-- skeleton's clip position. In the free camera its own camera is moved: it blends from where the player left it into
-- the execution and back again, then is given back. Otherwise a camera actor is spawned for the run and the view
-- blends to it and back. Off by default; the app switch (set_execution_camera) is saved in Runtime/execution-camera.tsv.
local U=require('ue_observe')
local Cam={}
local HEADER='ExecutionCameraV1'
local STATICS='/Script/Engine.Default__GameplayStatics'
local CAMERA_CLASS='/Script/Engine.CameraActor'
local BLEND_IN,BLEND_OUT=0.35,0.5   -- seconds of real time
local FRAME_MS=16
local HALF_HEIGHT=90                -- cm, when the player's capsule cannot be read
local LOG_CAP=60

local function number(v)return type(v)=='number' and v==v and math.abs(v)<1e12 end
local function vec(v)
    local ok,x,y,z=pcall(function()return v.X,v.Y,v.Z end)
    if ok and number(x) and number(y) and number(z) then return {X=x,Y=y,Z=z} end
end
local function rot(v)
    local ok,p,y,r=pcall(function()return v.Pitch,v.Yaw,v.Roll end)
    if ok and number(p) and number(y) and number(r) then return {Pitch=p,Yaw=y,Roll=r} end
end
local function lerpAngle(a,b,t)return a+((b-a+180)%360-180)*t end
local function fmt(v)return v and string.format('%.0f,%.0f,%.0f',v.X,v.Y,v.Z) or '?' end
local function short(object)
    if not U.valid(object) then return '?' end
    local ok,n=pcall(function()return object:GetFName():ToString()end)
    return ok and type(n)=='string' and n or '?'
end
local function smooth(t)t=math.max(0,math.min(1,t));return t*t*(3-2*t)end
-- From one camera pose to another, eased.
function Cam.blend(fromLocation,fromRotation,toLocation,toRotation,t)
    local a=smooth(t)
    return {X=fromLocation.X+(toLocation.X-fromLocation.X)*a,Y=fromLocation.Y+(toLocation.Y-fromLocation.Y)*a,
            Z=fromLocation.Z+(toLocation.Z-fromLocation.Z)*a},
        {Pitch=lerpAngle(fromRotation.Pitch,toRotation.Pitch,a),Yaw=lerpAngle(fromRotation.Yaw,toRotation.Yaw,a),
            Roll=lerpAngle(fromRotation.Roll,toRotation.Roll,a)}
end

-- The camera at tau seconds into a camera animation, for the executor at base facing yaw (degrees).
-- A frame is {time, LookAt x,y,z, ViewRotation pitch,yaw,roll, ViewDistance, SocketOffset x,y,z}.
function Cam.pose(anim,tau,base,yaw)
    local frames=anim.frames
    local a,b,alpha=frames[1],frames[1],0
    if tau>=frames[#frames][1] then a,b=frames[#frames],frames[#frames]
    elseif tau>frames[1][1] then
        for i=1,#frames-1 do
            if tau<frames[i+1][1] then a,b=frames[i],frames[i+1];alpha=(tau-a[1])/(b[1]-a[1]);break end
        end
    end
    local function lerp(i)return a[i]+(b[i]-a[i])*alpha end
    local c,s=math.cos(math.rad(yaw)),math.sin(math.rad(yaw))
    local lx,ly,lz=lerp(2),lerp(3),lerp(4)
    local pivot={X=base.X+lx*c-ly*s,Y=base.Y+lx*s+ly*c,Z=base.Z+lz}
    local pitch,viewYaw,roll=lerpAngle(a[5],b[5],alpha),yaw+lerpAngle(a[6],b[6],alpha),lerpAngle(a[7],b[7],alpha)
    local cp,sp=math.cos(math.rad(pitch)),math.sin(math.rad(pitch))
    local cy,sy=math.cos(math.rad(viewYaw)),math.sin(math.rad(viewYaw))
    local forward,right0,up0={X=cp*cy,Y=cp*sy,Z=sp},{X=-sy,Y=cy,Z=0},{X=-sp*cy,Y=-sp*sy,Z=cp}
    local cr,sr=math.cos(math.rad(roll)),math.sin(math.rad(roll))
    local right,up={},{}
    for _,axis in ipairs({'X','Y','Z'})do right[axis]=right0[axis]*cr-up0[axis]*sr;up[axis]=right0[axis]*sr+up0[axis]*cr end
    local back=lerp(8)-lerp(9)
    local sideways,lift=lerp(10),lerp(11)
    local location={X=pivot.X-forward.X*back+right.X*sideways+up.X*lift,Y=pivot.Y-forward.Y*back+right.Y*sideways+up.Y*lift,
        Z=pivot.Z-forward.Z*back+right.Z*sideways+up.Z*lift}
    return location,{Pitch=pitch,Yaw=viewYaw,Roll=roll},pivot
end

local function transform(position,rotation)
    local p,y,r=math.rad(rotation.Pitch)*0.5,math.rad(rotation.Yaw)*0.5,math.rad(rotation.Roll)*0.5
    local sp,cp,sy,cy,sr,cr=math.sin(p),math.cos(p),math.sin(y),math.cos(y),math.sin(r),math.cos(r)
    return {Translation=position,Scale3D={X=1,Y=1,Z=1},
        Rotation={X=cr*sp*sy-sr*cp*cy,Y=-cr*sp*cy-sr*cp*sy,Z=cr*cp*sy-sr*sp*cy,W=cr*cp*cy+sr*sp*sy}}
end

function Cam.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local settings=options.path..'/execution-camera.tsv'
    local data=options.cameras or require('execution_data')
    local find=options.staticFind or function(path)return StaticFindObject(path)end
    local loop=options.loop or function(ms,fn)return LoopInGameThreadWithDelay(ms,fn)end
    local cancel=options.cancel or function(handle)return CancelDelayedAction(handle)end
    local name=options.fname or FName
    local self={on=false,state='off',message='',failures=0,shots=0}
    local run=nil
    local spent={}      -- spawned cameras waiting for the blend back to finish: {camera, frames}
    local lines=0
    local function say(m)if lines<LOG_CAP then lines=lines+1;log('[ExecutionCamera] '..m)end end
    local function call(object,method,...)
        if not U.valid(object) then return false,'对象无效' end
        local n,args=select('#',...),{...}
        return pcall(function()return object[method](object,table.unpack(args,1,n))end)
    end
    local function same(a,b)local ka,kb=U.key(a),U.key(b);return ka~=nil and ka==kb end
    local function readFile(path)
        local f=fs.open(path,'r');if not f then return nil end
        local value=f:read('*a');f:close();return value
    end
    local function writeFile(path,value)
        local f=fs.open(path,'w');if not f then return false end
        local wrote=f:write(value);local closed=f:close()
        return wrote~=nil and wrote~=false and closed==true and readFile(path)==value
    end
    do
        local saved=readFile(settings)
        if type(saved)=='string' and saved:sub(1,#HEADER+1)==HEADER..'\t' then self.on=saved:find('\ton=1',1,true)~=nil end
        self.state=self.on and 'waiting' or 'off'
    end
    local function gameTime(r)
        local ok,t=call(r.lib,'GetTimeSeconds',r.world)
        return ok and number(U.unwrap(t)) and U.unwrap(t) or nil
    end
    local function realTime(r)
        local ok,t=call(r.lib,'GetRealTimeSeconds',r.world)
        return ok and number(U.unwrap(t)) and U.unwrap(t) or nil
    end
    local function place(r,location,rotation)
        assert(call(r.camera,'K2_SetActorLocationAndRotation',location,rotation,false,{},true),'移动镜头失败')
        r.last={location=location,rotation=rotation}
    end
    local function stopLoop(r)if r.handle then pcall(cancel,r.handle);r.handle=nil end end

    function self:set(value)
        if value~='ON' and value~='OFF' then return {ok=false,message='处决镜头开关只接受 ON 或 OFF',spawned_count=0} end
        local before=self.on
        self.on=value=='ON'
        local saved=writeFile(settings,HEADER..'\ton='..(self.on and '1' or '0')..'\n')
        if not saved then self.on=before end
        if saved then self.state=self.on and 'waiting' or 'off' end
        say('设置 开关='..value..' 保存读回='..tostring(saved))
        if saved and not self.on and run then self:finish('关掉了处决镜头') end
        return {ok=saved,spawned_count=0,message=saved and (self.on and '处决镜头已开启' or '处决镜头已关闭') or '处决镜头设置没能保存'}
    end
    function self:status()
        return {on=self.on,state=self.state,failures=self.failures,shots=self.shots,message=self.message}
    end

    -- The borrowed free camera eases back to where the player left it, then is given back.
    local function returning(r)
        local t=realTime(r)
        local progress=t and (t-r.outAt)/BLEND_OUT or 1
        if progress<1 and r.last and r.home then
            local location,rotation=Cam.blend(r.outFrom.location,r.outFrom.rotation,r.home.location,r.home.rotation,progress)
            place(r,location,rotation)
            return
        end
        stopLoop(r)
        if run==r then run=nil end
        say(string.format('还给自由观战 位置读回=%s（过渡 %d 帧）',tostring(options.freeCamera:release()),r.outFrames or 0))
    end

    local function update()
        local r=run
        if not r then return end
        local ok,err=pcall(function()
            if r.phase=='out' then r.outFrames=(r.outFrames or 0)+1;returning(r);return end
            local info=r.info
            assert(U.valid(r.camera),'镜头失效')
            assert(U.valid(info.executor),'执行方失效')
            local clip
            if info.body then
                local got,position=call(info.body,'GetPosition')
                position=got and U.unwrap(position)
                if number(position) then clip=(position-(info.clip_from or 0))/(info.rate or 1)+(info.timeline_start or 0) end
            end
            if not clip then
                local t=gameTime(r);assert(t,'读不到游戏时间')
                clip=t-r.started
            end
            if clip>r.anim.start+r.anim.duration then self:finish('镜头播完');return end
            local base
            if info.body then
                local got,root=call(info.body,'GetSocketLocation',name('root'))
                base=got and vec(U.unwrap(root))
                if base then base.Z=base.Z+r.halfHeight end
            end
            if not base then
                local got,location=call(info.executor,'K2_GetActorLocation')
                base=got and vec(U.unwrap(location))
            end
            assert(base,'读不到执行方的位置')
            local okYaw,facing=call(info.executor,'K2_GetActorRotation')
            facing=okYaw and rot(U.unwrap(facing))
            local yaw=facing and facing.Yaw or info.yaw or 0
            local location,rotation=Cam.pose(r.anim,clip-r.anim.start,base,yaw)
            if r.from then
                local t=realTime(r)
                local progress=t and (t-r.realStart)/BLEND_IN or 1
                if progress<1 then location,rotation=Cam.blend(r.from.location,r.from.rotation,location,rotation,progress) end
            end
            place(r,location,rotation)
            r.frames=r.frames+1
            if r.frames==1 or (r.frames%120==0 and r.frames<=600) then
                local got,actual=call(r.camera,'K2_GetActorLocation');actual=got and vec(U.unwrap(actual))
                say(string.format('第%d帧 动画位置=%.2fs 镜头=%s 读回=%s 执行方=%s 朝向=%.0f',r.frames,clip,fmt(location),fmt(actual),fmt(base),yaw))
            end
        end)
        if not ok then
            self.failures=self.failures+1
            if r.phase=='out' then
                stopLoop(r);if run==r then run=nil end
                say('还镜头时出错：'..tostring(err)..'；还给自由观战 位置读回='..tostring(options.freeCamera:release()))
            else self:finish('更新出错：'..tostring(err)) end
        end
    end

    -- An execution started: info = {executor, target, ability (executor ability class name), body (borrowed skeleton),
    -- yaw (the executor's facing after it turned)}.
    function self:begin(info)
        if not self.on then return end
        local entry=data[info.ability]
        local anim=info.camera or (entry and entry.camera)
        if info.continuing and run and anim and U.valid(run.camera) then
            local r=run
            r.info=info;r.anim=anim;r.phase='play';r.started=gameTime(r);r.frames=0
            r.outAt=nil;r.outFrom=nil;r.outFrames=0
            r.from=r.last;r.realStart=realTime(r)
            self.state='running';self.shots=self.shots+1
            say('衔接原生处决，保留相机及最初返回位置：'..tostring(info.ability))
            return
        end
        if run and run.phase=='out' then
            stopLoop(run);run=nil
            say('上一段还在过渡回去，直接还给自由观战 位置读回='..tostring(options.freeCamera:release()))
        elseif run then self:finish('下一次处决开始') end
        if not anim then say('这对处决没有镜头数据，保持原视角：'..tostring(info.ability));return end
        local ok,err=pcall(function()
            local pc=options.getController();assert(U.valid(pc),'读不到玩家控制器')
            local world=options.getWorld();assert(U.valid(world),'读不到 World')
            local lib=find(STATICS);assert(U.valid(lib),'找不到 GameplayStatics')
            local okTarget,previous=call(pc,'GetViewTarget');previous=okTarget and U.unwrap(previous) or nil
            assert(U.valid(previous),'读不到当前视角')
            local halfHeight=HALF_HEIGHT
            local player=options.getPlayer and options.getPlayer()
            local okHalf,half=call(U.field(player,'CapsuleComponent'),'GetScaledCapsuleHalfHeight')
            half=okHalf and U.unwrap(half)
            if number(half) and half>20 and half<300 then halfHeight=half end
            local r={info=info,anim=anim,pc=pc,world=world,lib=lib,previous=previous,halfHeight=halfHeight,frames=0,phase='play'}
            r.started=gameTime(r);assert(r.started,'读不到游戏时间')
            if options.freeCamera and options.freeCamera:isActive() then
                local camera,position,rotation=options.freeCamera:borrow()
                assert(camera~=nil,'自由观战的镜头借不出来')
                r.camera,r.borrowed=camera,true
                r.home={location=vec(position),rotation=rot(rotation)}
                if r.home.location and r.home.rotation then
                    r.from=r.home;r.realStart=realTime(r)
                    if not r.realStart then r.from=nil end
                else r.home=nil end
            else
                local manager=U.field(pc,'PlayerCameraManager');assert(U.valid(manager),'读不到镜头管理器')
                local okL,location=call(manager,'GetCameraLocation');location=okL and vec(U.unwrap(location))
                local okR,rotation=call(manager,'GetCameraRotation');rotation=okR and rot(U.unwrap(rotation))
                assert(location and rotation,'读不到当前镜头位置')
                local cls=find(CAMERA_CLASS);assert(U.valid(cls),'找不到 CameraActor')
                local t=transform(location,rotation)
                local spawned,camera=call(lib,'BeginDeferredActorSpawnFromClass',world,cls,t,1,nil,1)
                camera=spawned and U.unwrap(camera) or nil
                assert(U.valid(camera),'镜头生成未确认')
                r.camera=camera
                assert(call(lib,'FinishSpawningActor',camera,t,1),'镜头生成未完成')
                local gotFOV,fov=call(manager,'GetFOVAngle');fov=gotFOV and U.unwrap(fov)
                if number(fov) and fov>5 and fov<175 then call(U.field(camera,'CameraComponent'),'SetFieldOfView',fov) end
                assert(call(pc,'SetViewTargetWithBlend',camera,BLEND_IN,0,0,false),'切换视角失败')
            end
            run=r
            r.handle=loop(FRAME_MS,function()update()end)
            assert(r.handle~=nil and r.handle~=false,'逐帧更新没登记上')
            self.state='running';self.shots=self.shots+1
            self.message='处决镜头：'..tostring(info.ability)
            say(string.format('开始 动作=%s 镜头从第%.2fs起 共%.2fs %d帧 方式=%s 原视角=%s 玩家半身高=%.0f 执行方朝向=%s',info.ability,anim.start,anim.duration,
                #anim.frames,r.borrowed and ('借用自由观战的镜头'..(r.from and '，0.35 秒过渡进入' or '，直接切入')) or '生成镜头并切过去',
                short(previous),halfHeight,info.yaw and string.format('%.0f',info.yaw) or '?'))
        end)
        if not ok then
            self.failures=self.failures+1
            say('没能开始，保持原视角：'..tostring(err))
            if run then self:finish('开始失败') end
        end
    end

    -- A QTE execution moved to another stage: its clip starts over on the borrowed skeleton, and so does that stage's
    -- camera track, from the camera's current place.
    function self:stage(anim,label)
        local r=run
        if not r or r.phase~='play' or not anim or not anim.frames or #anim.frames==0 then return false end
        r.anim=anim;r.stages=(r.stages or 0)+1
        if r.last then r.from=r.last;r.realStart=realTime(r);if not r.realStart then r.from=nil end end
        if r.stages<=3 or label=='End' then
            say(string.format('换段 第%d段 %s 镜头从第%.2fs起 共%.2fs %d帧 %s',r.stages,tostring(label or '?'),anim.start,anim.duration,#anim.frames,
                r.from and '0.35 秒过渡' or '直接切'))
        end
        return true
    end

    -- The execution ended (or the camera ran out): stop following it and give the view back.
    function self:finish(why)
        local r=run
        if not r or r.phase=='out' then return end
        local back
        if r.borrowed then
            if r.home and r.last then
                r.phase='out';r.outFrom=r.last;r.outAt=realTime(r)
                if r.outAt then
                    self.state=self.on and 'waiting' or 'off'
                    say(string.format('结束（%s）帧数=%d；0.5 秒过渡回自由观战的位置',tostring(why),r.frames))
                    return
                end
            end
            stopLoop(r);run=nil
            back='还给自由观战 位置读回='..tostring(options.freeCamera:release())
        else
            stopLoop(r);run=nil
            local okTarget,current=call(r.pc,'GetViewTarget')
            current=okTarget and U.unwrap(current) or nil
            if same(current,r.camera) and U.valid(r.previous) then
                back='切回原视角='..tostring((call(r.pc,'SetViewTargetWithBlend',r.previous,BLEND_OUT,0,0,false)))
            else
                back='视角已经不在处决镜头上，不切回'
            end
            spent[#spent+1]={camera=r.camera,frames=0}
        end
        self.state=self.on and 'waiting' or 'off'
        say(string.format('结束（%s）帧数=%d；%s',tostring(why),r.frames,back))
    end
    -- Support tick (0.5 s): a spawned camera goes once the view has blended back.
    function self:sweep()
        local kept={}
        for _,item in ipairs(spent) do
            item.frames=item.frames+1
            if item.frames>=3 then
                if U.valid(item.camera) then call(item.camera,'K2_DestroyActor') end
            else kept[#kept+1]=item end
        end
        spent=kept
    end
    function self:active()return run~=nil end
    return self
end
return Cam
