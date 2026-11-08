-- 镜头跟踪: the free camera follows a chosen unit and keeps its opponent in the picture. It runs inside
-- the free camera's frame (free_camera.lua) and only says where the camera goes; the camera moves it and reads it back.
-- Framing: side keeps the view across the line between the two, without flipping over when they swap places; shoulder looks
-- from behind the unit at its opponent; orbit follows position and distance and leaves the angle to the mouse.
-- The hand comes first, one channel at a time: the mouse takes the angle, the wheel the distance, WASD/QE the position. A
-- channel left alone for the resume time eases back to automatic (0: it stays where the hand left it).
local U=require('ue_observe')
local Track={}
Track.DEFAULTS={framing='side',resume=3}
Track.FRAMINGS={side=true,shoulder=true,orbit=true}
Track.RESUME_MAX=10
local HEADER='CameraTrackV1'
local MAIN_SHARE=0.65          -- how much of the look point is the followed unit
local LOOK_HIGH=30             -- cm over the capsule's middle
local MIN_DIST,MAX_DIST=300,2500
local SOLO_DIST=500            -- with no opponent
local MARGIN=150               -- cm around the two, plus one and a half capsule radii
local DIST_BAND=0.05           -- a change of the wanted distance under this share is ignored, so the view does not breathe
local ASPECT=9/16              -- for the height a unit needs in the picture
local HEIGHT_ROOM=1.3
local TAU_LOOK,TAU_RETARGET,TAU_DIST,TAU_ZOOM,TAU_YAW=0.2,0.5,0.6,0.15,0.25
local RETARGET_SECONDS=1.5
local SIDE_ZONE,SIDE_RATE=25,40          -- degrees off square before it turns, degrees a second
local SHOULDER_ZONE,SHOULDER_RATE=5,120
local SHOULDER_SIDE,SHOULDER_DIST=40,300 -- cm beside the unit, past its radius; cm behind it, plus three radii
local DEFAULT_PITCH,TAU_PITCH=-12,0.8
local PITCH_MIN,PITCH_MAX=-70,40
local MOVE_TAU,TURN_TAU=0.30,0.15        -- as the free camera, at smoothing 100
local RETURN_TAU=0.33                    -- back to automatic in about a second
local WHEEL_STEP,ZOOM_MIN,ZOOM_MAX=0.12,0.3,4
local OPPONENT_REACH=4000                -- cm; a farther opponent pulls the view no more than one this far away
local PAN_MAX=3000                       -- cm WASD/QE can take the view from the look point
local VIEW_MAX=10000                     -- cm from the followed unit, whatever the wheel and the keys add up to
local FLOOR_GAP=50                       -- cm kept above the ground the keys run into
local HOLD_SECONDS=1.5                   -- on a fallen unit before moving on
local CHECK_EVERY=0.25                   -- health and opponent
local TRACE_EVERY=0.1                    -- the line from the look point to the camera
local WALL_GAP,WALL_MIN=30,100           -- cm kept from a wall; closest the camera comes for one
local UNIT_ROOM=20                       -- cm around a capsule within which a hit is that unit, not a wall
local TAU_WALL_IN,TAU_WALL_OUT=0.06,0.8
-- The wall check pulled the view in for every branch and rock the line swept past and let it out a moment later, so
-- the distance jumped between 1 m and 20 m. It now asks the camera channel (ETraceTypeQuery 1, ECC_Camera: what a game
-- camera tests against; foliage and small props usually let it through, where the visibility channel stops), wants
-- the line blocked twice in a row before pulling in, and the line clear for WALL_HOLD before backing out.
local CAMERA_CHANNEL=1
local WALL_CONFIRM=2                     -- traces in a row
local WALL_HOLD=0.6                      -- s
local LOG_EVERY,LOG_LINES,EVENT_LINES=2,30,60
local TARGETS_MAX=24

local function wrap(a)return (a+180)%360-180 end
local function ease(dt,tau)return tau>0 and 1-math.exp(-dt/tau) or 1 end
local function clamp(v,low,high)return math.max(low,math.min(high,v)) end
local function vec(v)
    local ok,x,y,z=pcall(function()return v.X,v.Y,v.Z end)
    if ok and type(x)=='number' and type(y)=='number' and type(z)=='number' then return {X=x,Y=y,Z=z} end
end
local function direction(yaw,pitch)
    local y,p=math.rad(yaw),math.rad(pitch)
    return {X=math.cos(p)*math.cos(y),Y=math.cos(p)*math.sin(y),Z=math.sin(p)}
end
local function className(actor)
    if not U.valid(actor) then return '无' end
    local ok,name=pcall(function()return actor:GetClass():GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end
local function capsule(actor)
    local comp=U.field(actor,'CapsuleComponent')
    if not U.valid(comp) then return 50,100 end
    local okR,radius=pcall(function()return comp:GetScaledCapsuleRadius()end)
    local okH,half=pcall(function()return comp:GetScaledCapsuleHalfHeight()end)
    return okR and type(radius)=='number' and radius or 50,okH and type(half)=='number' and half or 100
end

function Track.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local file=options.path..'/camera-track.tsv'
    local self={framing=Track.DEFAULTS.framing,resume=Track.DEFAULTS.resume}
    local run
    local events,periodic=0,0
    local boss={}
    local function say(text)
        if events<EVENT_LINES then events=events+1;log('[CameraTrack] '..text) end
    end
    do
        local f=fs.open(file,'r')
        if f then
            local text=f:read('*a');f:close()
            if type(text)=='string' and text:sub(1,#HEADER+1)==HEADER..'\t' then
                local framing=text:match('\tframing=(%a+)')
                local resume=tonumber(text:match('\tresume=(%d+)'))
                if Track.FRAMINGS[framing] then self.framing=framing end
                if resume and resume>=0 and resume<=Track.RESUME_MAX and resume%1==0 then self.resume=resume end
            end
        end
    end
    local function alive(actor)
        if not U.valid(actor) then return false end
        if not options.hp then return true end
        local ok,hp=pcall(options.hp,actor)
        return not (ok and type(hp)=='number' and hp<=0)
    end
    local function isBoss(actor,key)
        if boss[key]==nil then
            local ok,yes=false,false
            if options.isBoss then ok,yes=pcall(options.isBoss,actor) end
            boss[key]=ok and yes==true
        end
        return boss[key]
    end
    -- Who can be followed: on the field, not a stand or a reserve, with health left. Bosses first.
    local function candidates()
        local list={}
        for _,member in ipairs(options.members() or {})do
            local key=U.key(member.actor)
            if key and not member.stand and not member.reserve and alive(member.actor) then
                list[#list+1]={actor=member.actor,key=key,team=member.team,boss=isBoss(member.actor,key),order=#list}
            end
        end
        table.sort(list,function(a,b)
            if a.boss~=b.boss then return a.boss end
            return a.order<b.order
        end)
        return list
    end
    local function located(actor)
        if not U.valid(actor) then return nil end
        local ok,at=pcall(options.location,actor)
        return ok and vec(at) or nil
    end
    -- The one nearest the middle of the view.
    local function inView(list,position,rotation)
        local forward=direction(rotation.Yaw,rotation.Pitch)
        local best,bestCos
        for _,entry in ipairs(list)do
            local at=located(entry.actor)
            if at then
                local dx,dy,dz=at.X-position.X,at.Y-position.Y,at.Z-position.Z
                local length=math.sqrt(dx*dx+dy*dy+dz*dz)
                local cos=length>1 and (dx*forward.X+dy*forward.Y+dz*forward.Z)/length or 1
                if not best or cos>bestCos then best,bestCos=entry,cos end
            end
        end
        return best
    end
    local function setOther(r,who)
        local key=U.key(who)
        if key==r.otherKey then return end
        r.other,r.otherKey=who,key
        if key then r.otherRadius,r.otherHalf=capsule(who) else r.otherRadius,r.otherHalf=nil,nil end
        say('对手='..className(who)..' 主目标='..className(r.target))
    end
    local function setTarget(r,actor,why)
        r.target,r.targetKey=actor,U.key(actor)
        r.targetRadius,r.targetHalf=capsule(actor)
        r.lostAt=nil
        r.lastAt=nil
        setOther(r,nil)
        if alive(actor) and options.opponentOf then
            local ok,who=pcall(options.opponentOf,actor)
            if ok and alive(who) then setOther(r,who) end
        end
        say(string.format('主目标=%s（%s） 对手=%s 构图=%s 回归=%d秒',className(actor),why,className(r.other),self.framing,self.resume))
    end
    function self:running()return run~=nil end
    function self:stop(why)
        if not run then return end
        local r=run
        run=nil
        boss={}
        say('结束（'..tostring(why)..'） 主目标='..className(r.target))
    end
    local function begin(actor,position,rotation,why)
        local at=located(actor) or position
        local gap=math.sqrt((at.X-position.X)^2+(at.Y-position.Y)^2+(at.Z-position.Z)^2)
        local distance=clamp(gap,MIN_DIST,MAX_DIST)
        local forward=direction(rotation.Yaw,rotation.Pitch)
        -- Starts exactly where the camera is, so the view moves over, not jumps.
        local fov=options.fov and options.fov() or nil
        run={fov=type(fov)=='number' and fov>5 and fov<175 and fov or 90,
            look={X=position.X+forward.X*distance,Y=position.Y+forward.Y*distance,Z=position.Z+forward.Z*distance},
            distance=distance,shown=distance,baseDist=distance,zoom=1,
            yaw=rotation.Yaw,pitch=rotation.Pitch,baseYaw=rotation.Yaw,basePitch=rotation.Pitch,offYaw=0,offPitch=0,
            pan={X=0,Y=0,Z=0},panVel={X=0,Y=0,Z=0},slowUntil=math.huge,logAt=-math.huge}
        periodic,events=0,0
        setTarget(run,actor,why)
    end
    local function answer(ok,message)return {ok=ok,message=message,spawned_count=0} end
    -- Start, on the unit the view is on or the one asked for. The free camera has to be running.
    function self:start(targetKey)
        local position,rotation
        if options.view then position,rotation=options.view() end
        if not position or not rotation then return answer(false,'不在自由观战中，镜头跟踪没有开始') end
        local list=candidates()
        local chosen
        for _,entry in ipairs(list)do if entry.key==targetKey then chosen=entry end end
        chosen=chosen or inView(list,position,rotation)
        if not chosen then return answer(false,'场上没有可跟踪的单位，先召唤') end
        if run then
            run.slowUntil=math.huge
            setTarget(run,chosen.actor,'切换')
            return answer(true,'镜头跟踪：换目标')
        end
        begin(chosen.actor,position,rotation,'开始')
        return answer(true,'镜头跟踪已开启')
    end
    function self:finish()
        self:stop('关闭')
        return answer(true,'镜头跟踪已关闭')
    end
    local function retarget(actor,why)
        if not run then return false end
        run.slowUntil=math.huge
        setTarget(run,actor,why)
        return true
    end
    -- Lock onto the unit in the middle of the view.
    function self:pick()
        local position,rotation
        if options.view then position,rotation=options.view() end
        if not position or not rotation then return answer(false,'不在自由观战中') end
        local chosen=inView(candidates(),position,rotation)
        if not chosen then return answer(false,'场上没有可跟踪的单位') end
        if not retarget(chosen.actor,'锁定屏幕中央') then begin(chosen.actor,position,rotation,'锁定屏幕中央') end
        return answer(true,'镜头跟踪：锁定屏幕中央的单位')
    end
    -- The next unit in the list.
    function self:next()
        local position,rotation
        if options.view then position,rotation=options.view() end
        if not position or not rotation then return answer(false,'不在自由观战中') end
        local list=candidates()
        if #list==0 then return answer(false,'场上没有可跟踪的单位') end
        local index=0
        for i,entry in ipairs(list)do if run and entry.key==run.targetKey then index=i end end
        local chosen=list[index%#list+1]
        if not retarget(chosen.actor,'下一个') then begin(chosen.actor,position,rotation,'下一个') end
        return answer(true,'镜头跟踪：下一个单位')
    end
    -- From the app: framing, resume seconds, and optionally the unit to follow.
    function self:set(framing,resume,targetKey)
        resume=tonumber(resume)
        if not Track.FRAMINGS[framing] then return answer(false,'镜头跟踪：构图不对') end
        if not resume or resume%1~=0 or resume<0 or resume>Track.RESUME_MAX then return answer(false,'镜头跟踪：回归时间应为 0–'..Track.RESUME_MAX..' 秒') end
        if framing~=self.framing or resume~=self.resume then
            local text=string.format('%s\tframing=%s\tresume=%d\n',HEADER,framing,resume)
            local saved=pcall(function()
                local f=assert(fs.open(file,'w'));assert(f:write(text));assert(f:close())
                local check=assert(fs.open(file,'r'));local actual=check:read('*a');check:close()
                assert(actual==text,'readback differs')
            end)
            log(string.format('[CameraTrack] 设置 构图=%s 回归=%d秒 保存读回=%s',framing,resume,tostring(saved)))
            if not saved then return answer(false,'镜头跟踪设置保存未确认，仍用原来的设置') end
            self.framing,self.resume=framing,resume
        end
        if targetKey and targetKey~='' then
            if not run then return self:start(targetKey) end
            for _,entry in ipairs(candidates())do
                if entry.key==targetKey then
                    retarget(entry.actor,'助手选择')
                    return answer(true,'镜头跟踪：换目标')
                end
            end
            return answer(false,'这个单位已经不在了')
        end
        return answer(true,'镜头跟踪设置已保存')
    end
    function self:status()
        local r=run
        return {on=r~=nil,framing=self.framing,resume=self.resume,target=r and r.targetKey or '',
            target_class=r and className(r.target) or '',other_class=r and r.other and className(r.other) or ''}
    end
    -- For the app's list: key:class:team;...
    function self:targets()
        local parts={}
        for i,entry in ipairs(candidates())do
            if i>TARGETS_MAX then break end
            parts[#parts+1]=entry.key..':'..className(entry.actor)..':'..tostring(entry.team)
        end
        return table.concat(parts,';')
    end
    -- Someone standing in the line is not a wall: the view is not pulled in for every unit that walks past. A skeleton
    -- answers with its bone; a capsule by where the hit is.
    local function isUnit(hit)
        if hit.bone then return true end
        local list={}
        for _,member in ipairs(options.members() or {})do list[#list+1]=member.actor end
        if options.player then list[#list+1]=options.player() end
        for _,actor in ipairs(list)do
            local at=located(actor)
            if at then
                local radius,half=capsule(actor)
                local dx,dy=hit.at.X-at.X,hit.at.Y-at.Y
                if dx*dx+dy*dy<(radius+UNIT_ROOM)^2 and math.abs(hit.at.Z-at.Z)<half+UNIT_ROOM then return true end
            end
        end
        return false
    end
    -- One frame: where the camera goes. nil once there is nothing to follow.
    -- input: mx, my, wheel, forward, right, up, fast, turn, speed, smooth, world.
    function self:frame(dt,now,input)
        local r=run
        if not r then return nil end
        if not r.checkedAt or now-r.checkedAt>=CHECK_EVERY then
            r.checkedAt=now
            if r.slowUntil==math.huge then r.slowUntil=now+RETARGET_SECONDS end
            if alive(r.target) then
                r.lostAt=nil
                if options.opponentOf then
                    local ok,who=pcall(options.opponentOf,r.target)
                    setOther(r,ok and alive(who) and who or nil)
                end
            elseif not r.lostAt then
                r.lostAt=now
                say('主目标倒下 '..className(r.target)..'，停 '..HOLD_SECONDS..' 秒')
            elseif now-r.lostAt>=HOLD_SECONDS then
                local successor=alive(r.other) and r.other or nil
                if not successor then
                    local list=candidates()
                    successor=list[1] and list[1].actor or nil
                end
                if not successor then
                    self:stop('场上没有可跟踪的单位了')
                    return nil
                end
                r.slowUntil=now+RETARGET_SECONDS
                setTarget(r,successor,'原目标倒下')
            end
        end
        local a=located(r.target)
        if a then r.lastAt=a else a=r.lastAt end
        if not a then
            self:stop('读不到主目标的位置')
            return nil
        end
        local b=r.otherKey and alive(r.other) and located(r.other) or nil
        local framing,resume=self.framing,self.resume
        local smooth=input.smooth or 40
        local tanH=math.tan(math.rad(r.fov/2))
        local half=math.max(r.targetHalf or 100,r.otherHalf or 0)
        local sep=b and math.sqrt((b.X-a.X)^2+(b.Y-a.Y)^2) or 0
        -- Where it looks and how far back it wants to be.
        local wantLook,auto
        if framing=='shoulder' then
            local y=math.rad(r.yaw)
            local side=r.targetRadius+SHOULDER_SIDE
            wantLook={X=a.X-math.sin(y)*side,Y=a.Y+math.cos(y)*side,Z=a.Z+LOOK_HIGH}
            auto=SHOULDER_DIST+r.targetRadius*3
        elseif b then
            local gap=math.sqrt((b.X-a.X)^2+(b.Y-a.Y)^2+(b.Z-a.Z)^2)
            local pull=(1-MAIN_SHARE)*(gap>OPPONENT_REACH and OPPONENT_REACH/gap or 1)
            wantLook={X=a.X+(b.X-a.X)*pull,Y=a.Y+(b.Y-a.Y)*pull,Z=a.Z+(b.Z-a.Z)*pull+LOOK_HIGH}
            auto=(MAIN_SHARE*math.min(sep,OPPONENT_REACH)+math.max(r.targetRadius,r.otherRadius or 0)*1.5+MARGIN)/tanH
        else
            wantLook={X=a.X,Y=a.Y,Z=a.Z+LOOK_HIGH}
            auto=SOLO_DIST
        end
        auto=clamp(auto,math.max(MIN_DIST,half*HEIGHT_ROOM/(tanH*ASPECT)),MAX_DIST)
        -- The mouse: in orbit it turns the view for good, otherwise it holds the angle until it has been left alone.
        local turn=(input.turn or 100)/100
        local mx,my=input.mx or 0,input.my or 0
        if mx~=0 or my~=0 then
            if framing=='orbit' then
                r.baseYaw=r.baseYaw+mx*turn
                r.basePitch=clamp(r.basePitch+my*turn,PITCH_MIN,PITCH_MAX)
            else
                r.offYaw=r.offYaw+mx*turn
                r.offPitch=clamp(r.offPitch+my*turn,PITCH_MIN-r.basePitch,PITCH_MAX-r.basePitch)
                r.mouseAt,r.mouseBack=now,nil
            end
        elseif r.mouseAt and resume>0 and now-r.mouseAt>=resume then
            if not r.mouseBack then r.mouseBack=true;r.offYaw=wrap(r.offYaw) end
            local e=ease(dt,RETURN_TAU)
            r.offYaw,r.offPitch=r.offYaw*(1-e),r.offPitch*(1-e)
            if math.abs(r.offYaw)<0.2 and math.abs(r.offPitch)<0.2 then r.offYaw,r.offPitch,r.mouseAt,r.mouseBack=0,0,nil,nil end
        end
        -- The automatic angle, while the hand is off it.
        if framing~='orbit' and not r.mouseAt then
            if b and sep>50 then
                local axis=math.deg(math.atan(b.Y-a.Y,b.X-a.X))
                local goal,zone,rate
                if framing=='side' then
                    local first,second=axis+90,axis-90
                    goal=math.abs(wrap(first-r.baseYaw))<=math.abs(wrap(second-r.baseYaw)) and first or second
                    zone,rate=SIDE_ZONE,SIDE_RATE
                else goal,zone,rate=axis,SHOULDER_ZONE,SHOULDER_RATE end
                local gap=wrap(goal-r.baseYaw)
                if math.abs(gap)>zone then
                    local step=math.min(math.abs(gap)-zone,rate*dt)
                    r.baseYaw=r.baseYaw+(gap>0 and step or -step)
                end
            end
            r.basePitch=r.basePitch+(DEFAULT_PITCH-r.basePitch)*ease(dt,TAU_PITCH)
        end
        -- The wheel holds the distance the same way.
        local wheel=input.wheel or 0
        if wheel~=0 then
            if not r.wheelSeen then r.wheelSeen=true;say('滚轮读回='..tostring(wheel)) end
            r.zoom=clamp(r.zoom*math.exp(-wheel*WHEEL_STEP),ZOOM_MIN,ZOOM_MAX)
            r.wheelAt=now
        elseif r.wheelAt and resume>0 and now-r.wheelAt>=resume then
            r.zoom=r.zoom+(1-r.zoom)*ease(dt,RETURN_TAU)
            if math.abs(r.zoom-1)<0.01 then r.zoom,r.wheelAt=1,nil end
        end
        if not r.wheelAt and math.abs(auto-r.baseDist)>r.baseDist*DIST_BAND then r.baseDist=auto end
        r.distance=r.distance+(r.baseDist*r.zoom-r.distance)*ease(dt,r.wheelAt and TAU_ZOOM or TAU_DIST)
        -- The view eases toward its angle.
        local handOn=framing=='orbit' or (r.mouseAt and not r.mouseBack)
        local e=handOn and (smooth>0 and ease(dt,TURN_TAU*smooth/100) or 1) or ease(dt,TAU_YAW)
        r.yaw=r.yaw+wrap(r.baseYaw+r.offYaw-r.yaw)*e
        r.pitch=r.pitch+(clamp(r.basePitch+r.offPitch,PITCH_MIN,PITCH_MAX)-r.pitch)*e
        -- WASD/QE: an offset from the look point, in the view's directions.
        local forward,right,up=input.forward or 0,input.right or 0,input.up or 0
        local y,p=math.rad(r.yaw),math.rad(r.pitch)
        local speed=(input.speed or 900)*(input.fast and 3 or 1)/math.max(1,math.sqrt(forward*forward+right*right+up*up))
        local want={X=(forward*math.cos(p)*math.cos(y)-right*math.sin(y))*speed,
            Y=(forward*math.cos(p)*math.sin(y)+right*math.cos(y))*speed,
            Z=(forward*math.sin(p)+up)*speed}
        local moveEase=smooth>0 and ease(dt,MOVE_TAU*smooth/100) or 1
        local v,pan=r.panVel,r.pan
        v.X,v.Y,v.Z=v.X+(want.X-v.X)*moveEase,v.Y+(want.Y-v.Y)*moveEase,v.Z+(want.Z-v.Z)*moveEase
        pan.X,pan.Y,pan.Z=pan.X+v.X*dt,pan.Y+v.Y*dt,pan.Z+v.Z*dt
        -- As far as the hand can take it: at the limit, what still pushes outward is dropped, so turning back answers at once.
        local panned=math.sqrt(pan.X*pan.X+pan.Y*pan.Y+pan.Z*pan.Z)
        if panned>PAN_MAX then
            local nx,ny,nz=pan.X/panned,pan.Y/panned,pan.Z/panned
            pan.X,pan.Y,pan.Z=nx*PAN_MAX,ny*PAN_MAX,nz*PAN_MAX
            local outward=v.X*nx+v.Y*ny+v.Z*nz
            if outward>0 then v.X,v.Y,v.Z=v.X-outward*nx,v.Y-outward*ny,v.Z-outward*nz end
            if not r.panLimitSeen then r.panLimitSeen=true;say(string.format('平移到上限 %.0fm 读回=%.0fm',PAN_MAX/100,math.sqrt(pan.X*pan.X+pan.Y*pan.Y+pan.Z*pan.Z)/100)) end
        end
        if forward~=0 or right~=0 or up~=0 then r.panAt=now
        elseif r.panAt and resume>0 and now-r.panAt>=resume then
            local back=1-ease(dt,RETURN_TAU)
            pan.X,pan.Y,pan.Z=pan.X*back,pan.Y*back,pan.Z*back
            if math.abs(pan.X)+math.abs(pan.Y)+math.abs(pan.Z)<1 then pan.X,pan.Y,pan.Z,r.panAt=0,0,0,nil end
        end
        -- The look point follows; a new target more slowly, so the view travels there.
        local follow=ease(dt,now<r.slowUntil and TAU_RETARGET or TAU_LOOK)
        local look=r.look
        look.X,look.Y,look.Z=look.X+(wantLook.X-look.X)*follow,look.Y+(wantLook.Y-look.Y)*follow,look.Z+(wantLook.Z-look.Z)*follow
        local origin={X=look.X+pan.X,Y=look.Y+pan.Y,Z=look.Z+pan.Z}
        -- The keys do not take the view through the ground: from under it, the wall check below finds nothing to stop the camera.
        if options.trace and pan.Z<0 and (not r.floorAt or now-r.floorAt>=TRACE_EVERY) then
            r.floorAt=now
            local hit=options.trace(input.world,look,origin)
            if hit and hit.at and not hit.inside and (not hit.normal or hit.normal.Z>0.5) and not isUnit(hit) then
                local room=hit.at.Z+FLOOR_GAP-origin.Z
                if room>0 then
                    pan.Z=pan.Z+room
                    if v.Z<0 then v.Z=0 end
                    origin.Z=look.Z+pan.Z
                    if not r.floorSeen then r.floorSeen=true;say(string.format('平移碰到地面 地面Z=%.0f 抬高=%.0fcm 读回Z=%.0f',hit.at.Z,room,origin.Z)) end
                end
            end
        end
        local dir=direction(r.yaw,r.pitch)
        -- A wall between the look point and the camera: closer once it is there twice in a row, back out slowly once it
        -- has been gone for WALL_HOLD. A unit in the line changes nothing; a look point inside something counts as clear.
        if options.trace and (not r.traceAt or now-r.traceAt>=TRACE_EVERY) then
            r.traceAt=now
            local hit=options.trace(input.world,origin,{X=origin.X-dir.X*r.distance,Y=origin.Y-dir.Y*r.distance,Z=origin.Z-dir.Z*r.distance},CAMERA_CHANNEL)
            if hit and hit.at and not hit.inside then
                if not isUnit(hit) then
                    local reach=math.sqrt((hit.at.X-origin.X)^2+(hit.at.Y-origin.Y)^2+(hit.at.Z-origin.Z)^2)
                    local limit=math.max(reach-WALL_GAP,WALL_MIN)
                    r.blocked,r.clearAt=(r.blocked or 0)+1,nil
                    if r.limit or r.blocked>=WALL_CONFIRM then
                        if not r.limit then r.pulls=(r.pulls or 0)+1 end
                        r.limit=limit
                        if not r.wallSeen then r.wallSeen=true;say(string.format('视线被墙挡住 离注视点=%.0fcm 拉近到=%.0fcm 通道=相机',reach,r.limit)) end
                    end
                elseif not r.unitSeen then
                    r.unitSeen=true
                    say('视线被单位挡住，不算墙，距离不变 骨骼='..tostring(hit.bone))
                end
            else
                r.blocked=0
                if r.limit then
                    r.clearAt=r.clearAt or now
                    if now-r.clearAt>=WALL_HOLD then r.limit,r.clearAt=nil,nil end
                end
            end
        end
        local allowed=r.limit and math.min(r.distance,r.limit) or r.distance
        r.shown=r.shown+(allowed-r.shown)*ease(dt,allowed<r.shown and TAU_WALL_IN or TAU_WALL_OUT)
        if periodic<LOG_LINES and now-r.logAt>=LOG_EVERY then
            r.logAt=now;periodic=periodic+1
            log(string.format('[CameraTrack] 读回 主目标=%s 对手=%s 两人距离=%.1fm 想要距离=%.1fm 实际距离=%.1fm 朝向=%.0f 手动=%s%s%s%s 墙拉近=%d次',className(r.target),className(r.other),
                sep/100,r.baseDist*r.zoom/100,r.shown/100,r.yaw%360,r.mouseAt and '鼠标 ' or '',r.wheelAt and '滚轮 ' or '',r.panAt and '平移 ' or '',r.limit and '有墙' or '',r.pulls or 0))
            r.pulls=0
        end
        local camera={X=origin.X-dir.X*r.shown,Y=origin.Y-dir.Y*r.shown,Z=origin.Z-dir.Z*r.shown}
        local fromUnit=math.sqrt((camera.X-a.X)^2+(camera.Y-a.Y)^2+(camera.Z-a.Z)^2)
        if fromUnit>VIEW_MAX then
            local share=VIEW_MAX/fromUnit
            camera={X=a.X+(camera.X-a.X)*share,Y=a.Y+(camera.Y-a.Y)*share,Z=a.Z+(camera.Z-a.Z)*share}
            if not r.viewLimitSeen then r.viewLimitSeen=true;say(string.format('镜头到距离上限 %.0fm 原本=%.0fm',VIEW_MAX/100,fromUnit/100)) end
        end
        return camera,{Pitch=r.pitch,Yaw=r.yaw%360,Roll=0}
    end
    return self
end
return Track
