-- Free observation without replacing UPlayer.PlayerController or possessing a pawn.
-- All engine access runs on the game thread. A small recovery journal survives reload.
local U=require('ue_observe')
local Camera={}
-- The app's 自由视角设置 (Runtime/free-camera-settings.tsv, v0.38.2): speed in cm/s, turn in percent of the raw
-- mouse, smoothing in percent of the easing below.
Camera.DEFAULTS={speed=900,turn=100,smooth=40}
Camera.LIMITS={speed={100,5000},turn={20,300},smooth={0,100}}
-- At smoothing 100 movement eases in and out over about MOVE_TAU s and the view over TURN_TAU s; 0 follows the keys.
local MOVE_TAU,TURN_TAU=0.30,0.15
-- 时停 pauses the game the way its own photo mode does: GameplayStatics.SetGamePaused, with the controller's
-- SetCameraMoveableWhenPaused (APBZPlayerController) so the view keeps following this camera, which runs on real time.
-- The first 0.38.2 build set the world's time dilation instead: the game's slow-motion subsystem put it back to 1
-- within a frame and the fight went on.
-- The player, controller and view target are checked this often, not every frame.
local CHECK_EVERY=0.25
local function number(v)return type(v)=='number' and v==v and math.abs(v)<1e12 end
local function vec(v)
    local ok,x,y,z=pcall(function()return v.X,v.Y,v.Z end)
    if ok and number(x) and number(y) and number(z) then return {X=x,Y=y,Z=z} end
end
local function distance(a,b)local dx,dy,dz=a.X-b.X,a.Y-b.Y,a.Z-b.Z;return math.sqrt(dx*dx+dy*dy+dz*dz)end
local function rot(v)
    local ok,p,y,r=pcall(function()return v.Pitch,v.Yaw,v.Roll end)
    if ok and number(p) and number(y) and number(r) then return {Pitch=p,Yaw=y,Roll=r} end
end
local function call(obj,name,...)
    if not U.valid(obj) then return false,'invalid '..name end
    local args=table.pack(...)
    return pcall(function()return obj[name](obj,table.unpack(args,1,args.n))end)
end
local function identity(obj)
    local ok,name=call(obj,'GetFullName')
    local path=ok and type(name)=='string' and name:match('^%S+ (/.+)$')
    local key=U.key(obj)
    if path and key then return path,key end
end
function Camera.new(options)
    local self={alive=true,active=false,record=nil,session=nil,handle=nil,keys={},objects={}}
    local log=options.log or function()end
    -- 卡顿测量: what each frame of the camera costs (with the observer guard and 镜头跟踪 in it) and the time from one frame
    -- to the next, summed up once a minute (perf_meter.lua).
    local meter=require('perf_meter').new({label='自由视角每帧',log=log,slow=8,hitch=50})
    local fs=options.io or io
    local filePath=options.path..'/free-camera.tsv'
    -- paused, moveable, full_tick: what 时停 changed (the game paused, the controller's paused-camera flags), undone on
    -- exit and after a reload. time_before: the time dilation the first 0.38.2 build replaced, only read from its journal.
    local fields={'world','world_key','controller','controller_key','pawn','pawn_key',
        'target','target_key','camera','camera_key','move_owned','look_owned','input_owned','spawn_uncertain','time_before',
        'paused','moveable','full_tick'}
    for _,name in ipairs(options.guard and options.guard.fields or {})do fields[#fields+1]=name end
    local function save(record)
        local lines={'FreeCameraV1'}
        for _,name in ipairs(fields)do
            local value=tostring(record[name] or '')
            assert(not value:find('[\t\r\n]'),'invalid recovery value')
            lines[#lines+1]=name..'\t'..value
        end
        local text=table.concat(lines,'\n')..'\n'
        local file=assert(fs.open(filePath,'w'));assert(file:write(text));assert(file:close())
        file=assert(fs.open(filePath,'r'));local actual=file:read('*a');file:close()
        assert(actual==text,'camera recovery journal readback failed')
    end
    local function clearJournal()
        local file=assert(fs.open(filePath,'w'));assert(file:write('FreeCameraV1\n'));assert(file:close())
        local check=assert(fs.open(filePath,'r'));local actual=check:read('*a');check:close()
        assert(actual=='FreeCameraV1\n','camera journal clear not verified')
    end
    do
        local file=fs.open(filePath,'r')
        if file then
            local text=file:read('*a');file:close()
            if type(text)=='string' and text:match('^FreeCameraV1\n') then
                local record={};for k,v in text:gmatch('\n([^\t\r\n]+)\t([^\r\n]*)')do record[k]=v end
                if record.controller and record.controller~='' then self.record=record end
            elseif type(text)~='string' then log('[FreeCamera] 读取恢复记录失败 读回=无文本，保留默认状态')
            end
        end
    end
    -- Speed, turn and smoothing: Config's numbers until the app saves its own.
    local settingsPath=options.path..'/free-camera-settings.tsv'
    local function setting(name,value)
        local limit=Camera.LIMITS[name];value=tonumber(value)
        if not limit or not value or value%1~=0 or value<limit[1] or value>limit[2] then return nil end
        return value
    end
    self.tuning={speed=setting('speed',options.moveSpeed) or Camera.DEFAULTS.speed,
        turn=setting('turn',options.mouseSensitivity and math.floor(options.mouseSensitivity*100+0.5)) or Camera.DEFAULTS.turn,
        smooth=Camera.DEFAULTS.smooth}
    do
        local file=fs.open(settingsPath,'r')
        if file then
            local text=file:read('*a');file:close()
            if type(text)=='string' and text:match('^FreeCameraSettingsV1\n') then
                local invalid,ignored={},0
                for line in text:gmatch('[^\r\n]+')do
                    local name,raw=line:match('^([%w_]+)\t(.*)$')
                    if Camera.LIMITS[name] then
                        local value=setting(name,raw)
                        self.tuning[name]=value or Camera.DEFAULTS[name]
                        if not value then invalid[name]=true end
                    elseif name then ignored=ignored+1 end
                end
                for _,name in ipairs({'speed','turn','smooth'})do
                    if invalid[name] then log('[FreeCamera] 设置字段无效 '..name..' 回退默认值='..Camera.DEFAULTS[name]..' 最终读回='..self.tuning[name]) end
                end
                log(string.format('[FreeCamera] 读取设置 读回 speed=%d turn=%d smooth=%d 忽略未知字段=%d',self.tuning.speed,self.tuning.turn,self.tuning.smooth,ignored))
            end
        end
    end
    function self:settings()return {speed=self.tuning.speed,turn=self.tuning.turn,smooth=self.tuning.smooth}end
    function self:configure(speed,turn,smooth)
        local values={speed=setting('speed',speed),turn=setting('turn',turn),smooth=setting('smooth',smooth)}
        for _,name in ipairs({'speed','turn','smooth'})do
            if not values[name] then
                local limit=Camera.LIMITS[name]
                return {ok=false,message='自由视角设置超出范围：'..name..' 应为 '..limit[1]..'–'..limit[2],spawned_count=0}
            end
        end
        local text=string.format('FreeCameraSettingsV1\nspeed\t%d\nturn\t%d\nsmooth\t%d\n',values.speed,values.turn,values.smooth)
        local ok=pcall(function()
            local file=assert(fs.open(settingsPath,'w'));assert(file:write(text));assert(file:close())
            local check=assert(fs.open(settingsPath,'r'));local actual=check:read('*a');check:close()
            assert(actual==text,'readback differs')
        end)
        if not ok then return {ok=false,message='自由视角设置保存未确认，仍用原来的设置',spawned_count=0} end
        self.tuning=values
        local message=string.format('自由视角：移动速度 %d，转向 %d%%，平滑 %d%%',values.speed,values.turn,values.smooth)
        log('[FreeCamera] 设置已保存并读回 '..message)
        return {ok=true,message=message,spawned_count=0}
    end
    local function resolve(record,field)
        local path,key=record[field],record[field..'_key']
        if not path or path=='' or not key then return nil end
        local cached=self.objects[field]
        if U.valid(cached) and U.key(cached)==key and identity(cached)==path then return cached end
        local ok,obj=pcall(StaticFindObject,path)
        if not ok or not U.valid(obj) or U.key(obj)~=key then return nil end
        local actual=identity(obj)
        return actual==path and obj or nil
    end
    local function same(a,b)return U.key(a)~=nil and U.key(a)==U.key(b)end
    local function remember(record,field,obj)
        local path,key=identity(obj);assert(path,'missing identity: '..field)
        record[field],record[field..'_key']=path,key
        self.objects[field]=obj
    end
    local function guardContext(record)
        return {record=record,pc=resolve(record,'controller'),pawn=resolve(record,'pawn'),
            camera=resolve(record,'camera'),world=resolve(record,'world'),
            remember=function(name,obj)remember(record,name,obj)end,
            resolve=function(name)return resolve(record,name)end,save=function()save(record)end}
    end
    local function key(name)
        if not self.keys[name] then self.keys[name]={KeyName=FName(name)} end
        return self.keys[name]
    end
    local function axis(pc,name)
        local ok,value=call(pc,'GetInputAnalogKeyState',key(name))
        assert(ok and number(value),'input readback unavailable: '..name)
        return value
    end
    -- The first 0.38.2 build's 时停 set the time dilation; only a journal it left still needs it put back.
    local function worldSettings(world)
        local direct=U.field(U.field(world,'PersistentLevel'),'WorldSettings')
        if U.valid(direct) then return direct end
        local ok,found=call(world,'K2_GetWorldSettings')
        return ok and U.valid(found) and found or nil
    end
    local function dilationOf(world)return tonumber((U.field(worldSettings(world),'TimeDilation')))end
    local function setDilation(world,value)
        local lib=StaticFindObject('/Script/Engine.Default__GameplayStatics')
        local called=call(lib,'SetGlobalTimeDilation',world,value)
        local after=dilationOf(world)
        return called and after~=nil and math.abs(after-value)<=math.max(1e-6,value*0.01),after
    end
    local function pausedOf(lib,world)
        local ok,paused=call(lib,'IsGamePaused',world);paused=ok and U.unwrap(paused)
        if type(paused)=='boolean' then return paused end
    end
    local function fullTickOf(pc)
        local value=U.field(pc,'bShouldPerformFullTickWhenPaused')
        if type(value)=='boolean' then return value end
    end
    -- Undo 时停 in order: the game runs again, then the controller's paused-camera flags. Each step leaves the journal
    -- once read back; a world or controller that is gone took its state along.
    local function resume(record,pc,world,why)
        local done=true
        if record.paused=='1' then
            if not U.valid(world) then
                record.paused='';save(record);log('[FreeCamera] 时停的世界已不在，不用恢复运行')
            else
                local lib=StaticFindObject('/Script/Engine.Default__GameplayStatics')
                local called=call(lib,'SetGamePaused',world,false)
                local paused=pausedOf(lib,world)
                log('[FreeCamera] '..why..'恢复游戏运行 调用='..tostring(called)..' 读回暂停='..tostring(paused))
                if paused==false then record.paused='';save(record) else done=false end
            end
        end
        if record.moveable=='1' or record.full_tick=='1' then
            if not U.valid(pc) then
                record.moveable,record.full_tick='','';save(record)
            else
                if record.moveable=='1' then
                    if call(pc,'SetCameraMoveableWhenPaused',false) then record.moveable='';save(record) else done=false end
                end
                if record.full_tick=='1' then
                    local wrote=pcall(function()assert(U.valid(pc));pc.bShouldPerformFullTickWhenPaused=false end)
                    if wrote and fullTickOf(pc)==false then record.full_tick='';save(record) else done=false end
                end
            end
        end
        return done
    end
    function self:isActive()return self.active end
    function self:hasPending()return self.record~=nil end
    function self:isFrozen()return self.active and self.session~=nil and self.session.frozen~=nil end
    local function trackOf()return options.track and options.track() or nil end
    function self:stop(reason)
        self.active=false;self.session=nil
        meter:pause()
        local track=trackOf()
        if track then pcall(track.stop,track,'退出自由观战') end
        if self.handle then
            local ok=pcall(CancelDelayedAction,self.handle)
            if ok then self.handle=nil end
        end
        local record=self.record
        if not record then return true end
        local pc=resolve(record,'controller')
        local camera=resolve(record,'camera')
        local pending=false
        -- 时停 first: the game runs again before anything else is put back.
        if (record.paused=='1' or record.moveable=='1' or record.full_tick=='1')
            and not resume(record,pc,resolve(record,'world'),'退出时解除时停，') then pending=true end
        -- A journal of the first 0.38.2 build, frozen by the time dilation. A world that is gone (another map) took
        -- its time dilation with it.
        if record.time_before and record.time_before~='' then
            local before,world=tonumber(record.time_before),resolve(record,'world')
            if not world then
                record.time_before='';save(record);log('[FreeCamera] 时停的世界已不在，不用恢复时间流速')
            elseif before then
                local restored,after=setDilation(world,before)
                log('[FreeCamera] 退出时解除时停 时间流速 -> '..tostring(before)..' 读回='..tostring(after)..' reason='..tostring(reason))
                if restored then record.time_before='';save(record) else pending=true end
            else pending=true end
        end
        if options.guard then
            local ok,restored=pcall(function()return options.guard:stop(guardContext(record))end)
            if not ok or restored~=true then pending=true;log('[FreeCamera] 观战保护恢复待确认：'..tostring(restored)) end
        end
        if record.spawn_uncertain=='1' then
            local currentWorld=U.key(options.getWorld())
            pending=not currentWorld or currentWorld==record.world_key
        end
        if pc then
            local ok,target=call(pc,'GetViewTarget')
            if not ok or not U.valid(target) then pending=true
            elseif same(target,camera) then
                local previous=resolve(record,'target') or U.field(pc,'Pawn')
                if U.valid(previous) then
                    local changed=call(pc,'SetViewTargetWithBlend',previous,0,0,0,false)
                    local read,actual=call(pc,'GetViewTarget')
                    local verified=changed and read and same(actual,previous)
                    log('[FreeCamera] 恢复视点 reason='..tostring(reason)..' verified='..tostring(verified))
                    if not verified then pending=true end
                else pending=true end
            end
            if record.input_owned=='1' then
                local released=not camera or call(camera,'DisableInput',pc)
                if released then
                    record.input_owned='0';save(record)
                    log('[FreeCamera] 已请求撤销自建相机输入层；随后以相机销毁读回确认清理')
                else pending=true end
            end
            for _,guard in ipairs({{'move_owned','IsMoveInputIgnored','SetIgnoreMoveInput'},
                    {'look_owned','IsLookInputIgnored','SetIgnoreLookInput'}})do
                if record[guard[1]]=='1' then
                    local read,before=call(pc,guard[2])
                    if read and type(before)=='boolean' then
                        local changed=not before or call(pc,guard[3],false)
                        if changed then
                            -- Release our stack increment once; never repeatedly reset another system's guard.
                            record[guard[1]]='0';save(record)
                            local got,after=call(pc,guard[2])
                            log('[FreeCamera] 释放本次输入限制 '..guard[1]..' readback='..tostring(got and after))
                        else pending=true end
                    else pending=true end
                end
            end
        else
            -- The exact old controller no longer exists; never modify the replacement player's flags.
            record.move_owned,record.look_owned='0','0'
        end
        if camera and not pending then
            local destroyed=call(camera,'K2_DestroyActor')
            local removed=not U.valid(camera)
            if not removed then
                local read,dying=call(camera,'IsActorBeingDestroyed');removed=read and dying==true
            end
            log('[FreeCamera] 清理自建相机 call='..tostring(destroyed)..' removed='..tostring(removed))
            if not removed then pending=true end
        end
        if pending then save(record);log('[FreeCamera] 恢复待确认；可点击退出观战或使用自定义退出键重试');return false end
        clearJournal();self.record=nil;self.objects={}
        log('[FreeCamera] 已退出；原玩家控制器未切换')
        return true
    end
    function self:recover(force)
        if self.alive and not self.active and self.record and (force or not self.recoveryTried) then
            self.recoveryTried=true
            local ok,err=pcall(function()return self:stop('恢复上次相机记录')end)
            if not ok then log('[FreeCamera] 恢复失败 '..tostring(err)) end
        end
    end
    local function transform(position,rotation)
        local p,y,r=math.rad(rotation.Pitch)*0.5,math.rad(rotation.Yaw)*0.5,math.rad(rotation.Roll)*0.5
        local sp,cp,sy,cy,sr,cr=math.sin(p),math.cos(p),math.sin(y),math.cos(y),math.sin(r),math.cos(r)
        return {Translation=position,Scale3D={X=1,Y=1,Z=1},
            Rotation={X=cr*sp*sy-sr*cp*cy,Y=-cr*sp*cy-sr*cp*sy,Z=cr*cp*sy-sr*sp*cy,W=cr*cp*cy+sr*sp*sy}}
    end
    -- Once a frame (see enter()): input, the eased view and velocity, one move. Real time drives it, so it runs on
    -- during 时停 and at any frame rate.
    function self:tick()
        local s=self.session
        if not self.alive or not self.active or not s then return end
        local started,parts=os.clock(),{}
        local ok,err=pcall(function()
            local timed,now=call(s.lib,'GetRealTimeSeconds',s.world)
            assert(timed and number(now),'clock unavailable')
            local dt=math.min(0.1,math.max(0,now-s.lastTime));s.lastTime=now
            -- No FindAllOf / player-controller enumeration here; these checks four times a second.
            if not s.checkedAt or now-s.checkedAt>=CHECK_EVERY then
                s.checkedAt=now
                assert(same(U.field(s.pc,'Player'),s.player) and same(U.field(s.player,'PlayerController'),s.pc)
                    and same(U.field(s.pc,'Pawn'),s.pawn),'player/controller changed')
                assert(U.inWorld(s.pawn,s.world),'world changed')
                local read,target=call(s.pc,'GetViewTarget')
                assert(read and same(target,s.camera),'camera target replaced')
                if s.frozen then
                    -- Something may resume the game while frozen (a menu of its own ends its pause): paused again.
                    if pausedOf(s.lib,s.world)==false then
                        local again=call(s.lib,'SetGamePaused',s.world,true)
                        local after=pausedOf(s.lib,s.world)
                        s.frozen.repaused=s.frozen.repaused+1
                        if s.frozen.repaused<=3 or s.frozen.repaused%20==0 then
                            log('[FreeCamera] 时停中游戏恢复了运行，重新暂停 第'..s.frozen.repaused..'次 调用='..tostring(again)..' 读回暂停='..tostring(after))
                        end
                    end
                    -- Once the camera has left the spot where time stopped: did the view go with it? (The camera manager
                    -- only updates while paused when the controller ticks fully.)
                    if not s.frozen.viewLogged and distance(s.position,s.frozen.at)>200 then
                        s.frozen.viewLogged=true
                        local moved=distance(s.position,s.frozen.at)
                        local read,pov=call(U.field(s.pc,'PlayerCameraManager'),'GetCameraLocation');pov=read and vec(pov)
                        local shown=pov and distance(pov,s.frozen.at)
                        log(string.format('[FreeCamera] 时停中视图读回：相机离开时停点 %.0f cm，画面离开 %s cm，画面跟随=%s',moved,
                            shown and string.format('%.0f',shown) or '读不到',tostring(shown~=nil and shown>moved*0.5)))
                    end
                end
            end
            if options.guard then
                local t=os.clock();options.guard:tick(guardContext(self.record));parts.guard=(os.clock()-t)*1000
            end
            -- Lent to the execution camera: it moves the camera, input waits.
            if s.borrowed then return end
            local mx,my=axis(s.pc,'MouseX'),axis(s.pc,'MouseY')
            local forward=axis(s.pc,'W')-axis(s.pc,'S')
            local right=axis(s.pc,'D')-axis(s.pc,'A')
            -- Up: E or Space; down: Q or either Ctrl. Player actions are blocked while observing, so
            -- Space does not make the character jump.
            local up=math.max(axis(s.pc,'E'),axis(s.pc,'SpaceBar'))-math.max(axis(s.pc,'Q'),axis(s.pc,'LeftControl'),axis(s.pc,'RightControl'))
            local fast=math.max(axis(s.pc,'LeftShift'),axis(s.pc,'RightShift'))>0
            local tuning=self.tuning
            local position,rotation
            -- 镜头跟踪 (camera_track.lua) says where the camera goes while it runs; a failure there only ends the following.
            local track=trackOf()
            if track and track:running() then
                local readWheel,wheel=call(s.pc,'GetInputAnalogKeyState',key('MouseWheelAxis'))
                local t=os.clock()
                local framed,at,facing=pcall(track.frame,track,dt,now,{mx=mx,my=my,forward=forward,right=right,up=up,fast=fast,
                    wheel=readWheel and number(wheel) and wheel or 0,turn=tuning.turn,speed=tuning.speed,smooth=tuning.smooth,world=s.world})
                parts.track=(os.clock()-t)*1000
                if framed then position,rotation=at,facing
                else
                    log('[FreeCamera] 镜头跟踪出错，退回自由视角：'..tostring(at))
                    pcall(track.stop,track,'出错')
                end
                if position then
                    s.aimYaw,s.aimPitch=rotation.Yaw%360,math.max(-89,math.min(89,rotation.Pitch))
                    s.velocity={X=0,Y=0,Z=0}
                end
            end
            if not position then
                -- The mouse moves where the view aims; the view eases toward it (smoothing 0: at once).
                s.aimYaw=(s.aimYaw+mx*tuning.turn/100)%360
                s.aimPitch=math.max(-89,math.min(89,s.aimPitch+my*tuning.turn/100))
                local turnEase=tuning.smooth>0 and 1-math.exp(-dt/(TURN_TAU*tuning.smooth/100)) or 1
                local yawGap=(s.aimYaw-s.rotation.Yaw+180)%360-180
                local pitchGap=s.aimPitch-s.rotation.Pitch
                rotation={Pitch=s.rotation.Pitch+pitchGap*turnEase,Yaw=(s.rotation.Yaw+yawGap*turnEase)%360,Roll=0}
                -- The keys set a velocity to reach; the velocity eases toward it, so starts and stops are soft.
                local yaw,pitch=math.rad(rotation.Yaw),math.rad(rotation.Pitch)
                local speed=tuning.speed*(fast and 3 or 1)/math.max(1,math.sqrt(forward*forward+right*right+up*up))
                local want={X=(forward*math.cos(pitch)*math.cos(yaw)-right*math.sin(yaw))*speed,
                    Y=(forward*math.cos(pitch)*math.sin(yaw)+right*math.cos(yaw))*speed,
                    Z=(forward*math.sin(pitch)+up)*speed}
                local moveEase=tuning.smooth>0 and 1-math.exp(-dt/(MOVE_TAU*tuning.smooth/100)) or 1
                local v=s.velocity
                v.X,v.Y,v.Z=v.X+(want.X-v.X)*moveEase,v.Y+(want.Y-v.Y)*moveEase,v.Z+(want.Z-v.Z)*moveEase
                -- Settled: no keys, eased to a stop, the view on its aim. Nothing to send.
                if math.abs(v.X)+math.abs(v.Y)+math.abs(v.Z)<1 and want.X==0 and want.Y==0 and want.Z==0
                    and math.abs(yawGap)<0.01 and math.abs(pitchGap)<0.01 then
                    v.X,v.Y,v.Z=0,0,0
                    return
                end
                position={X=s.position.X+v.X*dt,Y=s.position.Y+v.Y*dt,Z=s.position.Z+v.Z*dt}
            end
            local moved,result=call(s.camera,'K2_SetActorLocationAndRotation',position,rotation,false,{},true)
            assert(moved and result~=false,'camera movement failed')
            s.position,s.rotation=position,rotation
            -- Read back the first move, then once a second.
            if not s.verifiedAt or now-s.verifiedAt>=1 then
                s.verifiedAt=now
                local got,actual=call(s.camera,'K2_GetActorLocation')
                actual=got and vec(actual)
                assert(actual,'camera position readback unavailable')
                assert(math.abs(actual.X-position.X)<0.5 and math.abs(actual.Y-position.Y)<0.5 and math.abs(actual.Z-position.Z)<0.5,'camera location did not follow input')
                s.position=actual
                if not s.movementVerified then
                    s.movementVerified=true
                    log(string.format('[FreeCamera] 输入/相机位置读回：WASDQE/Mouse；position=%.1f,%.1f,%.1f 每帧更新=%s 速度=%d 转向=%d%% 平滑=%d%%',
                        actual.X,actual.Y,actual.Z,tostring(self.loop=='frame'),tuning.speed,tuning.turn,tuning.smooth))
                end
            end
        end)
        if not ok then
            log('[FreeCamera] 观察相机中止：'..tostring(err))
            local restored,why=pcall(function()return self:stop('更新异常')end)
            if not restored then log('[FreeCamera] 异常恢复失败：'..tostring(why)) end
        end
        if self.active then meter:add((os.clock()-started)*1000,started,parts) end
    end
    function self:enter()
        if not self.alive then return false end
        if self.active then return true end
        if self.record then self:recover(true);if self.record then return false end end
        local ok,err=pcall(function()
            local pc=options.getController();assert(U.valid(pc),'player controller unavailable')
            local pawn=U.field(pc,'Pawn');local player=U.field(pc,'Player');local world=options.getWorld()
            assert(U.valid(pawn) and U.valid(player) and U.valid(world),'player/world unavailable')
            assert(same(U.field(player,'PlayerController'),pc),'local player association unavailable')
            assert(U.inWorld(pawn,world),'player world mismatch')
            local manager=U.field(pc,'PlayerCameraManager');assert(U.valid(manager),'camera manager unavailable')
            local readLocation,location=call(manager,'GetCameraLocation');location=readLocation and vec(location)
            local readRotation,rotation=call(manager,'GetCameraRotation');rotation=readRotation and rot(rotation)
            local readTarget,target=call(pc,'GetViewTarget')
            assert(location and rotation and readTarget and U.valid(target),'current viewpoint unavailable')
            local moveRead,moveIgnored=call(pc,'IsMoveInputIgnored')
            local lookRead,lookIgnored=call(pc,'IsLookInputIgnored')
            assert(moveRead and lookRead and type(moveIgnored)=='boolean' and type(lookIgnored)=='boolean','input guard readback unavailable')
            axis(pc,'W');axis(pc,'MouseX') -- Validate FKey reflection before any state changes.
            assert(type(LoopInGameThreadWithDelay)=='function' and type(CancelDelayedAction)=='function','camera timer unavailable')
            local lib=StaticFindObject('/Script/Engine.Default__GameplayStatics')
            local cls=StaticFindObject('/Script/Engine.CameraActor')
            assert(U.valid(lib) and U.valid(cls),'native camera class/library unavailable')
            local timed,now=call(lib,'GetRealTimeSeconds',world);assert(timed and number(now),'clock unavailable')
            local record={move_owned='0',look_owned='0',input_owned='0'}
            remember(record,'world',world);remember(record,'controller',pc);remember(record,'pawn',pawn);remember(record,'target',target)
            save(record);self.record=record;self.recoveryTried=false
            local t=transform(location,rotation)
            record.spawn_uncertain='1';save(record)
            local spawned,camera=call(lib,'BeginDeferredActorSpawnFromClass',world,cls,t,1,nil,1)
            assert(spawned and U.valid(camera),'camera spawn not confirmed')
            remember(record,'camera',camera);record.spawn_uncertain='0';save(record)
            local finished=call(lib,'FinishSpawningActor',camera,t,1);assert(finished and U.valid(camera),'camera finish not confirmed')
            local component=U.field(camera,'CameraComponent');assert(U.valid(component),'camera component unavailable')
            local owned,owner=call(component,'GetOwner');assert(owned and same(owner,camera),'camera component ownership mismatch')
            local gotFOV,fov=call(manager,'GetFOVAngle')
            if gotFOV and number(fov) and fov>5 and fov<175 then
                assert(call(component,'SetFieldOfView',fov),'camera FOV not applied')
                local actual=U.field(component,'FieldOfView')
                assert(number(actual) and math.abs(actual-fov)<0.01,'camera FOV not verified')
            end
            -- An owned input component blocks underlying gameplay actions, including
            -- Jump and Dodge. Raw key state still drives this camera; the player's
            -- input components and mappings are never removed or disabled.
            assert(U.valid(camera),'camera invalid before input registration')
            camera.bBlockInput=true
            camera.InputPriority=10000
            assert(U.field(camera,'bBlockInput')==true and U.field(camera,'InputPriority')==10000,'input layer configuration not verified')
            record.input_owned='1';save(record)
            assert(call(camera,'EnableInput',pc),'observer input layer registration failed')
            local input=U.field(camera,'InputComponent')
            local readInputOwner,inputOwner=call(input,'GetOwner')
            assert(readInputOwner and same(inputOwner,camera),'observer input component ownership not verified')
            local rawW,rawMouse=axis(pc,'W'),axis(pc,'MouseX')
            log('[FreeCamera] 动作输入层登记读回：block=true priority=10000 component_owner=observer raw_W='..rawW..' raw_MouseX='..rawMouse..'；跳跃/攻击屏蔽效果待实测')
            for _,guard in ipairs({{'move_owned',moveIgnored,'SetIgnoreMoveInput','IsMoveInputIgnored'},
                    {'look_owned',lookIgnored,'SetIgnoreLookInput','IsLookInputIgnored'}})do
                if not guard[2] then
                    record[guard[1]]='1';save(record)
                    assert(call(pc,guard[3],true),'input guard failed')
                    local read,actual=call(pc,guard[4]);assert(read and actual==true,'input guard not verified')
                end
            end
            assert(call(pc,'SetViewTargetWithBlend',camera,0,0,0,false),'view target request failed')
            local read,actual=call(pc,'GetViewTarget')
            assert(read and same(actual,camera),'view target not verified')
            assert(same(U.field(pc,'Player'),player) and same(U.field(pc,'Pawn'),pawn),'original player/controller association changed')
            if options.guard then options.guard:enter(guardContext(record)) end
            self.session={pc=pc,player=player,pawn=pawn,world=world,lib=lib,camera=camera,position=location,rotation=rotation,lastTime=now,
                aimYaw=rotation.Yaw%360,aimPitch=math.max(-89,math.min(89,rotation.Pitch)),velocity={X=0,Y=0,Z=0}}
            self.active=true
            -- Once a frame. Up to v0.38.1 a 16 ms timer ran out of step with the frames: some frames moved the view twice,
            -- the next not at all, and the mouse of a frame could be read twice (the view juddered).
            if type(LoopInGameThreadAfterFrames)=='function' then
                self.handle,self.loop=LoopInGameThreadAfterFrames(1,function()self:tick()end),'frame'
            else
                self.handle,self.loop=LoopInGameThreadWithDelay(16,function()self:tick()end),'16ms'
            end
            assert(self.handle~=nil and self.handle~=false,'camera timer registration not confirmed')
            log('[FreeCamera] 已进入；原控制器/Player/Pawn关联读回=true；view_target='..record.camera..'；更新='..self.loop
                ..'；面板或自定义键退出，WASD移动、E或空格上升、Q或Ctrl下降、Shift加速、鼠标转向')
        end)
        if not ok then
            log('[FreeCamera] 进入未完成：'..tostring(err))
            local restored,why=pcall(function()return self:stop('进入失败')end)
            if not restored then log('[FreeCamera] 失败回滚待确认：'..tostring(why)) end
        end
        return ok
    end
    -- 时停 on or off, only while observing (the camera keeps moving on real time); stop() resumes the game.
    function self:freeze(on)
        local s=self.session
        local record=self.record
        if not self.active or not s or not record then return {ok=false,message='不在自由观战中，时停未切换',spawned_count=0} end
        if on==(s.frozen~=nil) then return {ok=true,message=on and '已经是时停' or '游戏已在正常运行',spawned_count=0} end
        if on then
            local before=pausedOf(s.lib,s.world)
            if before==nil then return {ok=false,message='读不到游戏是否暂停，没有时停',spawned_count=0} end
            -- Paused by the game itself (a menu): resuming that pause is the game's, not this camera's.
            if before then return {ok=false,message='游戏本身正在暂停（可能开着菜单），回到游戏后再时停',spawned_count=0} end
            -- Each change is journaled before it is made and dropped from the journal if it did not happen.
            record.moveable='1';save(record)
            local moveable=call(s.pc,'SetCameraMoveableWhenPaused',true)
            if not moveable then record.moveable='';save(record) end
            local full=fullTickOf(s.pc)
            if full~=true then
                record.full_tick='1';save(record)
                local wrote=pcall(function()assert(U.valid(s.pc));s.pc.bShouldPerformFullTickWhenPaused=true end)
                full=fullTickOf(s.pc)
                if not wrote or full~=true then record.full_tick='';save(record) end
            end
            record.paused='1';save(record)
            local called=call(s.lib,'SetGamePaused',s.world,true)
            local paused=pausedOf(s.lib,s.world)
            log('[FreeCamera] 时停 暂停游戏 调用='..tostring(called)..' 读回暂停='..tostring(paused)..' 暂停时镜头可动='..tostring(moveable)
                ..' 暂停时完整更新='..tostring(full)..(record.full_tick=='1' and '（本Mod设置）' or ''))
            if paused~=true then
                local undone=resume(record,s.pc,s.world,'时停失败，')
                return {ok=false,message='游戏没有暂停（读回 '..tostring(paused)..'），时停未开启'..(undone and '' or '；恢复待确认，退出自由观战会再试'),spawned_count=0}
            end
            s.frozen={at={X=s.position.X,Y=s.position.Y,Z=s.position.Z},repaused=0}
            return {ok=true,message='时停：游戏已暂停，镜头照常移动',spawned_count=0}
        end
        if not resume(record,s.pc,s.world,'解除时停，') then
            return {ok=false,message='解除时停未确认，可以再试一次或退出自由观战',spawned_count=0}
        end
        s.frozen=nil
        return {ok=true,message='已解除时停',spawned_count=0}
    end
    function self:toggle()if self.active then return self:stop('切换自由观战') else return self:enter()end end
    -- Where the view is while the player has this camera (summons go where it points, spawn_spot.lua).
    function self:view()
        local s=self.session
        if not self.active or not s or s.borrowed then return nil end
        return s.position,s.rotation
    end
    -- The view's width, for 镜头跟踪's framing.
    function self:fieldOfView()
        local s=self.session
        local fov=s and U.field(U.field(s.camera,'CameraComponent'),'FieldOfView')
        return number(fov) and fov or nil
    end
    -- 处决镜头 (execution_camera.lua) moves this camera for one execution; the view target stays, input movement
    -- waits, and release puts the camera back where the player left it.
    function self:borrow()
        local s=self.session
        if not self.active or not s or s.borrowed or not U.valid(s.camera) then return nil end
        s.borrowed={position=s.position,rotation=s.rotation}
        return s.camera,s.position,s.rotation
    end
    function self:release()
        local s=self.session
        if not s or not s.borrowed then return false end
        local back=s.borrowed;s.borrowed=nil
        s.aimYaw,s.aimPitch,s.velocity=back.rotation.Yaw%360,back.rotation.Pitch,{X=0,Y=0,Z=0}
        local moved=call(s.camera,'K2_SetActorLocationAndRotation',back.position,back.rotation,false,{},true)
        local got,actual=call(s.camera,'K2_GetActorLocation');actual=got and vec(actual)
        return moved and actual~=nil and math.abs(actual.X-back.position.X)<0.5 and math.abs(actual.Y-back.position.Y)<0.5
            and math.abs(actual.Z-back.position.Z)<0.5
    end
    function self:silence()
        local track=trackOf()
        if track then pcall(track.stop,track,'Mod卸载') end
        self.alive=false;self.active=false;self.session=nil
        if self.handle then pcall(CancelDelayedAction,self.handle);self.handle=nil end
        if self.record then log('[FreeCamera] 卸载保留恢复记录；下一次游戏线程恢复，不在卸载线程访问对象') end
    end
    return self
end
return Camera
