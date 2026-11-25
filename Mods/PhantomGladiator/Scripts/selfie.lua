-- A borrowed camera and two owned pose overrides. Restore only values this session successfully read back.
local U=require('ue_observe')
local poses=require('selfie_poses')
local Lens=require('selfie_lens')
local Gaze=require('selfie_gaze')
local Selfie={}
local JOURNAL='PhantomGladiator.selfie.v1'
local function number(n)return type(n)=='number' and n==n and math.abs(n)<1e8 end
local function call(object,method,...)
    if not U.valid(object) then return false end
    local ok,v=pcall(function(...)return object[method](object,...)end,...)
    return ok,U.unwrap(v)
end
local function fullName(object)
    local ok,name=call(object,'GetFullName')
    return ok and type(name)=='string' and not name:find('%c') and name or nil
end
local function path(name)return name and name:match('^%S+ (/.+)$') end
local function assetPath(package)return package..'.'..package:match('([^/]+)$') end
local function vector(value)
    local x,y,z=U.struct(value,'X'),U.struct(value,'Y'),U.struct(value,'Z')
    if number(x) and number(y) and number(z) then return {X=x,Y=y,Z=z} end
end
local function rotation(actor)
    local _,v=call(actor,'K2_GetActorRotation')
    local pitch,yaw,roll=U.struct(v,'Pitch'),U.struct(v,'Yaw'),U.struct(v,'Roll')
    if number(pitch) and number(yaw) and number(roll) then return {Pitch=pitch,Yaw=yaw,Roll=roll} end
end
local function gap(a,b)
    if not a or not b then return math.huge end
    return ((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)^.5
end
local function yawNear(a,b)return number(a) and number(b) and math.abs((a-b+180)%360-180)<1 end
local function toward(a,b)
    local x,y,z=b.X-a.X,b.Y-a.Y,b.Z-a.Z
    return {Pitch=math.deg(math.atan(z,(x*x+y*y)^.5)),Yaw=math.deg(math.atan(y,x)),Roll=0}
end
local function reply(ok,message)return {ok=ok,message=message,spawned_count=0} end

-- Frame both faces along the line between the subjects. Prefer their existing front side.
local function framing(a,b,startYaw,fov,isBlocked)
    local dx,dy=b.X-a.X,b.Y-a.Y
    local width=(dx*dx+dy*dy)^.5
    local fx,fy=math.cos(math.rad(startYaw)),math.sin(math.rad(startYaw))
    local nx,ny=fx,fy
    if width>2 then
        nx,ny=-dy/width,dx/width
        if nx*fx+ny*fy<0 then nx,ny=-nx,-ny end
    end
    local focus={X=(a.X+b.X)/2,Y=(a.Y+b.Y)/2,Z=(a.Z+b.Z)/2-18}
    local lens=math.tan(math.rad(math.min(105,math.max(45,fov))*.38))
    local distance=math.max(225,((width/2)+100)/lens,((math.abs(a.Z-b.Z)/2)+85)/(lens*.55))
    if distance>1600 then return end
    for _,side in ipairs({1,-1})do
        local camera={X=focus.X+nx*distance*side,Y=focus.Y+ny*distance*side,Z=focus.Z+38}
        if not isBlocked(camera,a) and not isBlocked(camera,b) then return camera,toward(camera,focus),focus end
    end
end
Selfie.framing=framing

function Selfie.new(o)
    local self={}
    local camera=o.camera
    local gaze=Gaze.new(o)
    local studio=o.studio or o.getController and require('photo_studio').new(o)
    local shared=o.shared or ModRef
    local log=o.log or function()end
    local wall=o.clock or os.clock
    local find=o.find or StaticFindObject
    local load=o.load or LoadAsset
    local fname=o.fname or FName
    local run,undo,cleanupAt,lastError=nil,{},0,''
    local function say(text)log('[Selfie] '..text)end
    local function key(actor)return U.key(actor)end
    local function current(actor,world,photoHidden)
        if not key(actor) or not U.inWorld(actor,world) or (o.live and not o.live(actor))
            or (not photoHidden and U.field(actor,'bHidden')~=false) then return false end
        local hp=o.hp(actor)
        return number(hp) and hp>0
    end
    local function subject(actor)
        local p=vector(o.location(actor))
        if not p then return end
        local mesh=U.field(actor,'Mesh')
        for _,name in ipairs({'head','Head'})do
            local ok,has=call(mesh,'DoesSocketExist',fname(name))
            if ok and has==true then
                local read,at=call(mesh,'GetSocketLocation',fname(name))
                at=read and vector(at)
                if at and gap(p,at)<400 then return at end
            end
        end
        local _,half=call(U.field(actor,'CapsuleComponent'),'GetScaledCapsuleHalfHeight')
        local h=number(half) and math.max(30,math.min(180,half*.78)) or 72
        return {X=p.X,Y=p.Y,Z=p.Z+h}
    end
    local function candidates(world,player)
        local found={}
        local start=vector(o.location(player))
        if not start then return found end
        for _,entry in ipairs(o.members() or {})do
            local actor=entry.actor
            if entry.team=='companion' and not entry.stand and not entry.reserve and not entry.aid
                and not entry.summoner and current(actor,world) and not o.blocked(actor) then
                local dist=gap(start,vector(o.location(actor)))
                if dist<math.huge then found[#found+1]={actor=actor,dist=dist,path=entry.class_path or '',key=key(actor)} end
            end
        end
        table.sort(found,function(a,b)return a.dist==b.dist and a.key<b.key or a.dist<b.dist end)
        return found
    end
    local function animFor(actor)
        local mesh=U.field(actor,'Mesh')
        local _,anim=call(mesh,'GetAnimInstance')
        return mesh,anim
    end

    -- Persist only identities and yaw. Keep transient wrappers inside this world and Lua load.
    local function save()
        if not shared then return true end
        local rows={}
        for _,entry in ipairs(undo)do
            rows[#rows+1]=table.concat({entry.world,entry.key,entry.name,entry.before,entry.wanted,
                entry.animKey or '-',entry.montageKey or '-',entry.montageName or '-'},'\t')
        end
        local text=table.concat(rows,'\n')
        local ok,yes=pcall(function()shared:SetSharedVariable(JOURNAL,text);return shared:GetSharedVariable(JOURNAL)==text end)
        return ok and yes==true
    end
    if shared then
        local ok,saved=pcall(function()return shared:GetSharedVariable(JOURNAL)end)
        if ok and type(saved)=='string' and #saved<=16384 then
            for line in saved:gmatch('[^\n]+')do
                local world,id,name,before,wanted,anim,montage,montageName=line:match(
                    '^(%d+)\t(%d+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([%d%-]+)\t([%d%-]+)\t([^\t]+)$')
                before,wanted=tonumber(before),tonumber(wanted)
                if world and path(name) and not name:find('%c') and number(before) and number(wanted) and #undo<2 then
                    undo[#undo+1]={world=world,key=id,name=name,before=before,wanted=wanted,
                        animKey=anim~='-' and anim or nil,montageKey=montage~='-' and montage or nil,
                        montageName=path(montageName) and not montageName:find('%c') and montageName or nil}
                end
            end
        end
    end
    local function resolve(name)
        local id=path(name)
        if not id or type(find)~='function' then return nil end
        local ok,object=pcall(find,id)
        return ok and U.valid(object) and object or nil
    end
    local function restore(entry,world,worldID)
        if entry.world~=worldID then return true end
        local actor=entry.actor or resolve(entry.name)
        if key(actor)~=entry.key or fullName(actor)~=entry.name or not U.inWorld(actor,world) then return true end
        local done=true
        if entry.montageKey then
            local _,anim=animFor(actor)
            local animKey=key(anim)
            if not animKey then done=false end
            if animKey==entry.animKey then
                local montage=entry.montage
                if not U.valid(montage) then
                    local _,active=call(anim,'GetCurrentActiveMontage')
                    montage=key(active)==entry.montageKey and active or resolve(entry.montageName)
                end
                if key(montage)==entry.montageKey then
                    call(anim,'Montage_Stop',0,montage)
                    local read,active=call(anim,'Montage_IsActive',montage)
                    done=read and active==false
                end
            end
            if done then entry.montageKey=nil end
        end
        local now=rotation(actor)
        if not now then return false end
        if yawNear(now.Yaw,entry.wanted) and not yawNear(now.Yaw,entry.before) then
            now.Yaw=entry.before
            call(actor,'K2_SetActorRotation',now,false)
            now=rotation(actor)
            done=now~=nil and yawNear(now.Yaw,entry.before) and done
        end
        say('恢复角色 '..entry.name..' 读回='..tostring(done))
        return done
    end
    local function restoreActors()
        if #undo==0 then return true end
        local world=o.world();local worldID=key(world)
        if not worldID then return false end
        local left={}
        for _,entry in ipairs(undo)do if not restore(entry,world,worldID) then left[#left+1]=entry end end
        undo=left
        local saved=save()
        return #undo==0 and saved
    end
    local function poseFor(entry,index)
        if index==0 then return false end -- existing stance
        local mesh,anim=animFor(entry.actor)
        local _,skeletal=call(mesh,'GetSkeletalMeshAsset')
        local _,skeleton=call(skeletal,'GetSkeleton')
        local skeletonPath=path(fullName(skeleton))
        local skeletonPackage=skeletonPath and (skeletonPath:match('^(.-)%.[^./]+$') or skeletonPath)
        local options=poses[skeletonPackage]
        if not options or not U.valid(anim) or type(load)~='function' then return false end
        local read,active=call(anim,'GetCurrentActiveMontage')
        if not read or U.valid(active) then return false end
        local assetName=assetPath(options[1+(index-1)%#options])
        local ok,asset=pcall(load,assetName)
        if not ok or not U.valid(asset) or key(U.field(asset,'Skeleton'))~=key(skeleton)
            or U.field(asset,'bEnableRootMotion')~=false then return false end
        local lengthRead,length=call(asset,'GetPlayLength')
        if not lengthRead or not number(length) or length<=0 then return false end
        local at=length*(index==1 and .38 or .67)
        local launched,montage=call(anim,'PlaySlotAnimationAsDynamicMontage',asset,fname('DefaultSlot'),0,.1,1,1,-1,at)
        if not launched then return false end
        if not U.valid(montage) then
            local got,from=call(anim,'DynamicMontage_IsPlayingFrom',asset)
            if not got or from~=true then return false end
            local _,found=call(anim,'GetCurrentActiveMontage')
            montage=found
        end
        local montageKey=key(montage)
        if not montageKey then return false end
        entry.animKey=key(anim);entry.montageKey=montageKey;entry.montageName=fullName(montage);entry.montage=montage
        if not save() then return false,'selfie.retryRestore' end
        call(anim,'Montage_Pause',montage)
        local sampled,position=call(anim,'Montage_GetPosition',montage)
        local readActive,held=call(anim,'Montage_IsActive',montage)
        local readPlaying,playing=call(anim,'Montage_IsPlaying',montage)
        local applied=sampled and number(position) and math.abs(position-at)<.08
            and readActive and held==true and readPlaying and playing==false
        say('定格动作 '..assetName..' 读回='..tostring(applied))
        if not applied then return false,'selfie.poseFailed' end
        return true
    end
    local function face(entry,yaw)
        local now=rotation(entry.actor)
        if not now then return false end
        now.Yaw=yaw
        call(entry.actor,'K2_SetActorRotation',now,false)
        now=rotation(entry.actor)
        return now~=nil and yawNear(now.Yaw,yaw)
    end

    local function hasPair(r)
        local world=o.world()
        if key(world)~=r.worldID or key(o.player())~=r.playerKey or not current(r.player,world,r.hidden and r.hidden[1]) then return false end
        if r.mode=='free' then return true end
        if not r.other or not current(r.other.actor,world,r.hidden and r.hidden[2]) or o.blocked(r.player) or o.blocked(r.other.actor) then return false end
        for _,entry in ipairs(o.members() or {})do
            if entry.team=='companion' and not entry.stand and not entry.reserve and not entry.aid
                and not entry.summoner and key(entry.actor)==r.other.key then return true end
        end
        return false
    end
    local function close(reason,lostCamera)
        local r=run
        run=nil
        local restored=not studio or studio:close()
        restored=gaze:stop() and restored
        restored=restoreActors() and restored
        if r and not lostCamera then
            -- stop() owns restoration of the view target, input and any pause this camera set.
            restored=camera:stop(reason) and restored
        end
        if r then say('结束 '..tostring(reason)..' 恢复读回='..tostring(restored)) end
        return reply(restored,restored and 'selfie.closed' or 'selfie.retryRestore')
    end
    local function moveCamera(r,loc,view,verify)
        local ok,result=call(r.camera,'K2_SetActorLocationAndRotation',loc,view,false,{},true)
        if not ok or result==false then return false end
        if verify then
            local _,actual=call(r.camera,'K2_GetActorLocation')
            local rot=rotation(r.camera)
            if gap(vector(actual),loc)>1 or not rot or not yawNear(rot.Yaw,view.Yaw)
                or not yawNear(rot.Pitch,view.Pitch) or not yawNear(rot.Roll,view.Roll) then return false end
        end
        r.position,r.rotation=loc,view
        return true
    end
    local function reframe(r,other,poses)
        if studio and not studio:releaseSubjects(r) then return reply(false,'selfie.retryRestore') end
        local a,b=subject(r.player),subject(other.actor)
        local baseYaw=rotation(r.player)
        local fov=camera:fieldOfView()
        if not a or not b or not baseYaw or not number(fov) then return reply(false,'selfie.frameUnavailable') end
        local world=o.world()
        local keep=r.other and r.other.key==other.key
        local loc,view,focus
        local facing={}
        if keep then
            loc,view=r.position,r.rotation
            for _,entry in ipairs(undo)do facing[key(entry.actor)]=entry.wanted end
        else
            loc,view,focus=framing(a,b,r.startYaw or baseYaw.Yaw,fov,function(from,to)
                return o.blockedView(world,from,to,r.player,other.actor)
            end)
        end
        if not loc then return reply(false,'selfie.blockedView') end
        if studio and not studio:releaseFaces() then return reply(false,'selfie.retryRestore') end
        if not gaze:stop() or not restoreActors() then return reply(false,'selfie.retryRestore') end
        if not current(r.player,world) or not current(other.actor,world) or o.blocked(r.player) or o.blocked(other.actor) then
            return reply(false,'selfie.finishAction')
        end
        local entries={}
        for _,actor in ipairs({r.player,other.actor})do
            local where=vector(o.location(actor))
            local prev=rotation(actor)
            local name=fullName(actor)
            if not where or not prev or not path(name) then return reply(false,'selfie.frameUnavailable') end
            local want=toward(where,loc)
            local id=key(actor)
            entries[#entries+1]={actor=actor,world=r.worldID,key=id,name=name,before=prev.Yaw,wanted=facing[id] or want.Yaw,at=where}
        end
        if r.settings then view.Roll=r.settings.roll end
        if not moveCamera(r,loc,view,true) then return reply(false,'selfie.frameUnavailable') end
        undo=entries
        if not save() then return reply(false,'selfie.retryRestore') end
        local posed,read=0,{}
        for role,entry in ipairs(entries)do
            if not face(entry,entry.wanted) then return reply(false,'selfie.frameUnavailable') end
            local ok,why=poseFor(entry,poses[role])
            if why then return reply(false,why) end
            read[role]=ok
            if ok then posed=posed+1 end
        end
        r.other,r.poses,r.posed,r.poseRead,r.frames,r.prepareUntil=other,poses,posed,read,2,wall()+2
        r.gazeDelay=nil
        if studio then
            r.lookBound={}
            if not keep then r.expressions[2]=1 end
        end
        if focus then r.lens=Lens.new(focus,loc) end
        if camera:isFrozen() then
            local resumed=camera:freeze(false)
            if not resumed or not resumed.ok then return reply(false,'selfie.retryRestore') end
        end
        return reply(true,'selfie.preparing')
    end

    local function apply(r,other,poses)
        local ok,result=pcall(reframe,r,other,poses)
        if not ok then
            say('构图异常 '..tostring(result))
            result=reply(false,'selfie.frameUnavailable')
        end
        if not result.ok then close(result.message,false) end
        return result
    end
    local function control(r,input,dt,now)
        local loc,view,yaw,pitch,distance
        if r.mode=='duo' then
            loc,view,yaw,pitch,distance=Lens.step(r.lens,input,dt)
        else
            loc,view=Lens.free(r.position,r.rotation,input,dt)
        end
        if loc and U.valid(r.player) and (not r.other or U.valid(r.other.actor))
            and not o.blockedView(o.world(),r.position,loc,r.player,r.other and r.other.actor) then
            if r.settings then view.Roll=r.settings.roll end
            local first=not r.lensLogged
            if moveCamera(r,loc,view,first) then
                if r.mode=='duo' then r.lens.yaw,r.lens.pitch,r.lens.distance=yaw,pitch,distance end
                if first then r.lensLogged=true;say('手动构图 镜头位置读回=true') end
            end
        end
        gaze:update(r.position,now,r.settings)
        if studio then studio:moved(r,now) end
    end
    function self:tick()
        if not run and #undo==0 and not gaze:pending() and (not studio or not studio:pending()) then return end
        local now=wall()
        if now<cleanupAt then return end
        cleanupAt=now+1
        if run then
            if run.frames==0 then
                if not camera:isFrozen() or not hasPair(run) then
                    lastError='selfie.subjectChanged';close('摄影对象或时停已变化',false)
                end
            elseif now>=run.prepareUntil then
                lastError='selfie.cameraFailed';close('摄影定格超时',false)
            end
        else
            if studio then studio:close() end
            gaze:stop()
            restoreActors()
        end
    end
    function self:status()
        local r=run
        return {on=r~=nil,ready=r~=nil and r.frames==0,mode=r and r.mode or '',target=r and r.other and r.other.path or '',
            posed=r and r.posed or 0,style=r and r.poses[1] or 0,next=r and r.canCycle or false,message=lastError}
    end

    local function chooseMode(r,mode)
        if r.frames~=0 or r.shotQueued then return reply(false,'selfie.notReady') end
        if r.mode==mode then return reply(true,'photo.mode') end
        if mode=='duo' then
            local list=candidates(o.world(),r.player)
            if not list[1] then return reply(false,'selfie.summonFirst') end
            r.mode,r.canCycle=mode,#list>1
            return apply(r,list[1],r.poses)
        end
        if studio and (not studio:releaseFaces() or not studio:releaseSubjects(r)) then return reply(false,'selfie.retryRestore') end
        if not gaze:stop() or not restoreActors() then return reply(false,'selfie.retryRestore') end
        r.mode,r.other,r.lens,r.gazeDelay,r.canCycle,r.posed='free',nil,nil,nil,false,0
        if studio then
            r.menu.tab,r.menu.selected=1,1;r.expressions={1,1}
            r.lookBound={}
            if r.look[1] or (r.settings.eyes1 or 1)>1 then r.gazeDelay=2 end
            studio:subjects(r)
        end
        return reply(true,'photo.mode')
    end
    local function take(r)
        if not camera:viewConfirmed(r,r.position,r.rotation) then return false end
        local ok=o.capture(o.world(),r.settings)
        say('拍照请求 Shot 调用='..tostring(ok==true))
        return ok==true
    end
    function self:shot()
        local r=run
        if not r or r.frames~=0 or r.shotQueued or not camera:isFrozen() or not hasPair(r) then
            return reply(false,'selfie.notReady')
        end
        if studio then
            if not studio:capture(r,r.now or 0) then return reply(false,'selfie.shotFailed') end
            -- Keep the menu hidden across the frame used for the screenshot request.
            r.shotQueued={frames=5}
            return reply(true,'photo.shotQueued')
        end
        local ok=take(r)
        return reply(ok,ok and 'selfie.shotSent' or 'selfie.shotFailed')
    end
    local function choosePose(r,role,delta)
        if r.mode~='duo' or not r.other or r.frames~=0 or r.shotQueued then return reply(false,'selfie.notReady') end
        local indices={}
        for i,v in ipairs(r.poses)do indices[i]=(not role or i==role) and (v+delta)%3 or v end
        return apply(r,r.other,indices)
    end
    function self:pose()
        local r=run
        return r and choosePose(r,nil,1) or reply(false,'selfie.notReady')
    end
    function self:next()
        local r=run
        if not r or r.frames~=0 or r.shotQueued or r.mode~='duo' then return reply(false,'selfie.notReady') end
        if studio and not studio:releaseSubjects(r) then return reply(false,'selfie.retryRestore') end
        local list=candidates(o.world(),r.player)
        r.canCycle=#list>1
        if not r.canCycle then
            if studio then studio:subjects(r) end
            return reply(false,'selfie.noOther')
        end
        local nextIndex=1
        for i,v in ipairs(list)do if v.key==r.other.key then nextIndex=i%#list+1;break end end
        return apply(r,list[nextIndex],r.poses)
    end
    local studioErrors={
        ['selfie.notReady']='等待定格后再调整', ['selfie.summonFirst']='先召一名随从，等两人停稳',
        ['selfie.noOther']='只有一名可用的随从', ['selfie.blockedView']='构图受阻，请到开阔处',
        ['selfie.shotFailed']='截图请求未确认', ['selfie.retryRestore']='上次操作还在恢复',
        ['selfie.finishAction']='等待角色动作结束', ['selfie.poseFailed']='姿势未读回',
    }
    local function action(r,id,step,now)
        if id=='leave' then close('退出游戏内摄影',false);return end
        if r.frames~=0 or r.shotQueued then return end
        local result
        if id=='shot' then result=self:shot()
        elseif id=='mode' then result=chooseMode(r,r.mode=='duo' and 'free' or 'duo')
        elseif id=='next' then result=self:next()
        else
            local role=tonumber(id:sub(-1))
            if role and id:sub(1,4)=='pose' then result=choosePose(r,role,step)
            elseif role and id:sub(1,4)=='face' then
                local ok,message=studio:face(r,role,step)
                if not ok then studio:notice(r,message,now) end
            elseif role and id:sub(1,4)=='look' then
                if gaze:stop() then
                    r.look[role]=not r.look[role]
                    r.lookBound={}
                    r.gazeDelay=1
                else studio:notice(r,'视线正在恢复',now) end
            else
                local ok,message=studio:adjust(r,id,step,now,function(roll)
                    return moveCamera(r,r.position,{Yaw=r.rotation.Yaw,Pitch=r.rotation.Pitch,Roll=roll},true)
                end)
                if not ok then studio:notice(r,message,now)
                elseif id=='eyes1' or id=='eyes2' or id=='load' or id=='reset' then
                    if gaze:stop() then r.gazeDelay=1;r.lookBound={} end
                end
            end
        end
        if result and not result.ok and run==r then
            studio:notice(r,studioErrors[result.message] or '操作未完成',now)
        end
    end
    local function frame(r,dt,now)
        if run~=r then return end
        r.now=now
        if r.frames==0 then
            if not camera:isFrozen() then return end
            local input=camera:photoInput(r,studio~=nil)
            if studio then
                if r.prepareOrdinary then r.prepareOrdinary=nil;studio:prepare(r,now) end
                local id,step=studio:input(r,input,now)
                if id then action(r,id,step,now) end
                if run~=r then return end
            end
            if r.frames==0 then
                if r.gazeDelay then
                    r.gazeDelay=r.gazeDelay-1
                    if r.gazeDelay==0 then
                        r.gazeDelay=nil
                        local companion=r.mode=='duo' and r.other and r.other.actor or nil
                        local wanted={r.look[1],companion~=nil and r.look[2]}
                        local s=r.settings or {}
                        local eyes={s.eyes1 or 1,companion and (s.eyes2 or 1) or 1}
                        if hasPair(r) and (wanted[1] or wanted[2] or eyes[1]>1 or eyes[2]>1) then
                            r.lookBound=gaze:start(r.player,companion,r.camera,wanted,eyes)
                        end
                    end
                end
                if r.shotQueued then
                    local ticket=r.shotQueued
                    ticket.frames=ticket.frames-1
                    if ticket.frames==2 then
                        ticket.ok=hasPair(r) and studio:capture(r,now) and take(r)
                    end
                    if ticket.frames==0 then
                        r.shotQueued=nil
                        studio:notice(r,ticket.ok and '拍照请求已提交' or '截图请求未确认',now)
                    end
                else control(r,input,dt,now) end
            end
            if studio then studio:render(r,now) end
            return
        end
        if not hasPair(r) then lastError='selfie.subjectChanged';close('角色已改变或开始动作',false);return end
        for _,entry in ipairs(undo)do
            if gap(vector(o.location(entry.actor)),entry.at)>35 then
                lastError='selfie.subjectChanged';close('角色已离开取景点',false);return
            end
        end
        if r.frames>1 then r.frames=r.frames-1;return end
        if not camera:viewConfirmed(r,r.position,r.rotation) then return end
        local frozen=camera:freeze(true)
        if not frozen or not frozen.ok then lastError='selfie.cameraFailed';close('自拍时停未确认',false);return end
        for _,entry in ipairs(undo)do
            if not face(entry,entry.wanted) then lastError='selfie.frameUnavailable';close('角色朝向没有保持',false);return end
        end
        -- Let the last playing-world mesh evaluation finish before changing animation inputs.
        r.frames,r.gazeDelay=0,2
        if studio then studio:prepare(r,now) end
        say('双人自拍定格 姿势读回='..r.posed..'/2 随从='..r.other.path)
    end
    local function open(mode)
        lastError=''
        if run then
            if run.mode==mode then return close('主动退出',false) end
            return chooseMode(run,mode)
        end
        if studio and not studio:close() then return reply(false,'selfie.retryRestore') end
        if not gaze:stop() or not restoreActors() then return reply(false,'selfie.retryRestore') end
        if camera:isActive() then return reply(false,'selfie.exitObserver') end
        local world=o.world();local player=o.player()
        if not current(player,world) or mode=='duo' and o.blocked(player) then return reply(false,'selfie.finishAction') end
        local list=mode=='duo' and candidates(world,player) or {}
        if mode=='duo' and not list[1] then return reply(false,'selfie.summonFirst') end
        if not camera:enter('photo') then return reply(false,'selfie.cameraFailed') end
        local r={mode=mode,player=player,playerKey=key(player),worldID=key(world),canCycle=#list>1,poses={1,1},posed=0,look={false,false}}
        local _,prev=call(player,'K2_GetActorRotation')
        r.startYaw=U.struct(prev,'Yaw')
        function r:cameraLost(reason)
            if run==self then close(reason,true) end
        end
        function r:frame(dt,now)
            if run==self then frame(self,dt,now) end
        end
        r.camera,r.position,r.rotation=camera:borrow(r)
        if not U.valid(r.camera) then
            camera:stop('没有取得摄影镜头')
            return reply(false,'selfie.cameraFailed')
        end
        if not r.position then local _,v=call(r.camera,'K2_GetActorLocation');r.position=vector(v) end
        r.rotation=r.rotation or rotation(r.camera)
        run=r
        if studio and not studio:open(r,camera:fieldOfView() or 60) then
            close('摄影面板没有打开',false)
            return reply(false,'photo.panelFailed')
        end
        if mode=='duo' then return apply(r,list[1],r.poses) end
        local frozen=camera:freeze(true)
        if not r.position or not r.rotation or not frozen or not frozen.ok then
            close('普通摄影定格失败',false)
            return reply(false,'selfie.cameraFailed')
        end
        r.frames=0
        r.prepareOrdinary=studio~=nil
        say('普通摄影时停读回=true')
        return reply(true,'photo.mode')
    end
    function self:toggle()return open('duo')end
    function self:standard()
        if not studio then return reply(false,'selfie.unavailable') end
        return open('free')
    end
    function self:panel()
        local r=run
        if not studio or not r then return reply(false,'selfie.notReady') end
        r.menu.visible=not r.menu.visible
        return reply(true,'photo.mode')
    end
    self.studioSupported=studio~=nil
    function self:silence(restore)
        if restore then close('Mod卸载',false) end
    end
    return self
end
return Selfie
