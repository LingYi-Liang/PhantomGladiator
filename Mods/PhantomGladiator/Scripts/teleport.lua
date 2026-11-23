-- Experimental: move the real player to a place through the game's own teleport.
-- The game's teleporter device (BP_Teleport, DoTeleport) calls
--   PBZSaveLoadSubsystem:TeleportTo(NewLevelName, MakeTransform(Location, Rotation, 1), None)
-- for a place in the same level (NewLevelName = GetCurrentLevelName) and for one in another level alike; the same
-- call, with the same empty bell id, is made here. It brings the game's own loading with it, which a plain location
-- write does not (the destination is not streamed in yet and the player falls through it).
-- No save call, no bell and no flow state are written here. What the game itself saves after its teleport is the
-- game's own behaviour and has not been read back (another teleport mod's notes say the native teleport forces a
-- save at the destination); the app tells the user to back the save up first.
-- Before the native call a "即将" line goes to the log; afterwards the player's level and position are read back
-- for up to READBACK_SECONDS. After the arrival the only other write is the fall watch: a player who drops below
-- the target is stopped and put back at it (StopMovementImmediately + K2_TeleportTo), each time announced and read back.
local U=require('ue_observe')
local Teleport={}
Teleport.SUBSYSTEM='PBZSaveLoadSubsystem'
Teleport.MAX_COORD=2e7        -- cm; the last arena stands at z = 4.5e6
Teleport.READBACK_SECONDS=40
Teleport.ARRIVED_CM=5000      -- within this of the target horizontally, in the target level, counts as arrived
-- After the arrival the floor may not be streamed in yet (another teleport mod added "fall protection during
-- loading" to this same native route). For HOLD_SECONDS the player's height is watched every tick: FALL_CM below the
-- target, the movement is stopped and the player is put back at the target, at most MAX_PULLS times.
Teleport.HOLD_SECONDS=15
Teleport.FALL_CM=600
Teleport.MAX_PULLS=60       -- 12 seconds of ticks: most of the watch
Teleport.TICK_MS=200
local WORLD='^[%a_][%w_]*$'

local function finite(v)return type(v)=='number'and v==v and v>-Teleport.MAX_COORD and v<Teleport.MAX_COORD end
-- A place is {world=<level name>, x=, y=, z= (cm), yaw= (degrees, optional), name= (optional)}.
function Teleport.check(place)
    if type(place)~='table'then return false,'地点无效'end
    if type(place.world)~='string'or #place.world>64 or not place.world:match(WORLD)then return false,'地图名无效'end
    if not(finite(place.x)and finite(place.y)and finite(place.z))then return false,'坐标无效'end
    if place.yaw~=nil and not(type(place.yaw)=='number'and place.yaw==place.yaw and place.yaw>=-360 and place.yaw<=360)then return false,'朝向无效'end
    return true
end
function Teleport.quat(yaw)
    local half=math.rad(yaw or 0)/2
    return {X=0,Y=0,Z=math.sin(half),W=math.cos(half)}
end
local function call(o,m,...)
    if not U.valid(o)then return false end
    local a,n={...},select('#',...);local ok,value=pcall(function()return o[m](o,table.unpack(a,1,n))end)
    return ok,U.unwrap(value)
end
local function num(v)return type(v)=='number'and string.format('%.0f',v)or'?'end
local function text(p)return p and(tostring(p.world)..' ('..num(p.x)..','..num(p.y)..','..num(p.z)..')')or'不可读'end

function Teleport.new(o)
    local self={alive=true,last=nil}
    local pending
    local find=o.find or FindFirstOf
    local fname=o.fname or FName
    local clock=o.clock or os.clock
    local function say(s)(o.log or function()end)('[Teleport] '..s)end
    -- Where the real player is now: level name and position (read only).
    function self:here()
        local player=o.player()
        if not U.valid(player)then return nil,'玩家不可读'end
        local world=o.worldName()
        if type(world)~='string'or not world:match(WORLD)then return nil,'当前地图名不可读'end
        local got,location=call(player,'K2_GetActorLocation')
        local x,y,z=U.struct(location,'X'),U.struct(location,'Y'),U.struct(location,'Z')
        if not got or not(finite(x)and finite(y)and finite(z))then return nil,'玩家位置不可读'end
        local _,rotation=call(player,'K2_GetActorRotation')
        local yaw=U.struct(rotation,'Yaw')
        return {world=world,x=x,y=y,z=z,yaw=type(yaw)=='number'and yaw==yaw and yaw or 0}
    end
    function self:busy()return pending~=nil end
    -- A fast timer of its own while a teleport is being read back or held; the support loop's tick is the fallback.
    local timer,lastTick
    local function stopTimer()
        local old=timer;timer=nil;lastTick=nil
        if old and old.handle and o.cancel then pcall(o.cancel,old.handle) end
    end
    local function startTimer()
        if timer~=nil or type(o.loop)~='function'then return end
        local ticket={}
        timer=ticket
        local ok,handle=pcall(o.loop,Teleport.TICK_MS,function()
            if timer~=ticket or not ticket.handle or not self.alive or not pending then return end
            local t=clock()
            if lastTick and t>=lastTick and t-lastTick<Teleport.TICK_MS*.00075 then return end
            local request=pending
            local ticked,why=pcall(self.tick,self)
            if not ticked and request==pending then say('读回中断：'..tostring(why));pending=nil;stopTimer()end
        end)
        if timer~=ticket then
            if ok and handle and o.cancel and (not timer or timer.handle~=handle) then pcall(o.cancel,handle) end
        elseif ok and handle then ticket.handle=handle
        else timer=nil end
    end
    function self:needsSupportTick()
        if not pending then return false end
        if not timer or not timer.handle then return true end
        local elapsed=clock()-(lastTick or pending.started)
        return elapsed<0 or elapsed>=.5
    end
    -- Stops the fall and puts the player back at the target; returns whether the position read back near it.
    local function pull(p,now)
        local player=o.player()
        p.hold.pulls=p.hold.pulls+1
        say('即将 防坠拉回 第'..p.hold.pulls..'次 '..p.label..' 当前高度='..num(now.z)..' 目标高度='..num(p.place.z)
            ..' StopMovementImmediately + K2_TeleportTo(目标)')
        local _,movement=call(player,'GetMovementComponent')
        call(movement,'StopMovementImmediately')
        local moved=call(player,'K2_TeleportTo',{X=p.place.x,Y=p.place.y,Z=p.place.z},{Pitch=0,Yaw=p.place.yaw or 0,Roll=0})
        local after=self:here()
        local back=after~=nil and math.abs(after.z-p.place.z)<Teleport.FALL_CM
        say('防坠拉回 读回 调用='..tostring(moved==true)..' 当前='..text(after)..' 回到目标高度='..tostring(back))
        return back
    end
    -- Starts the game's teleport. Returns {ok=, message=}; the arrival is read back by tick().
    function self:go(place)
        if not self.alive then return {ok=false,message='模组正在卸载'}end
        local valid,why=Teleport.check(place)
        if not valid then return {ok=false,message=why}end
        -- A new teleport may start during the fall watch of the one before; it replaces that watch once it is called.
        if pending and not pending.hold then return {ok=false,message='上一次传送还在进行，请等它结束'}end
        local blocked=o.blocked and o.blocked()
        if blocked then return {ok=false,message=blocked}end
        local before,unreadable=self:here()
        if not before then return {ok=false,message=unreadable}end
        local found,subsystem=pcall(find,Teleport.SUBSYSTEM)
        if not found or not U.valid(subsystem)then return {ok=false,message='找不到游戏的存档传送系统，没有传送'}end
        local label=tostring(place.name or'')
        say('即将 传送 '..label..' 目标='..text(place)..' 朝向='..num(place.yaw or 0)..' 当前='..text(before)
            ..' 调用 PBZSaveLoadSubsystem:TeleportTo(地图名, 位置, None)（与原版传送机关同一调用）')
        local transform={Rotation=Teleport.quat(place.yaw),Translation={X=place.x,Y=place.y,Z=place.z},Scale3D={X=1,Y=1,Z=1}}
        local called=call(subsystem,'TeleportTo',fname(place.world),transform,fname('None'))
        if not called then
            say('传送 调用失败 '..label..'；没有等待读回')
            self.last={ok=false,message='传送调用失败，位置没有变',place=label}
            return {ok=false,message=self.last.message}
        end
        pending={place=place,label=label,before=before,started=clock(),lines=0}
        lastTick=nil
        startTimer()
        self.back=before
        self.last={ok=true,pending=true,message='已发起传送，等待游戏加载',place=label}
        return {ok=true,message='已发起传送：'..(label~=''and label or text(place))..'；到位结果见状态'}
    end
    -- Back to where the player stood before the last teleport this load.
    function self:goBack()
        if not self.back then return {ok=false,message='这次加载还没有传送过，没有可返回的位置'}end
        local place=self.back
        return self:go({world=place.world,x=place.x,y=place.y,z=place.z,yaw=place.yaw,name='传送前的位置'})
    end
    -- Reads the arrival back once a call: the player in the target level, near the target horizontally (the height
    -- is the fall watch's business), or READBACK_SECONDS gone. Then watches the height for HOLD_SECONDS.
    function self:tick()
        if not pending then return end
        local p=pending
        lastTick=clock()
        local now=self:here()
        if pending~=p then return end
        if p.hold then
            local done=clock()>=p.hold.untilTime
            if not done and now and now.world==p.place.world and now.z<p.place.z-Teleport.FALL_CM then
                if p.hold.pulls<Teleport.MAX_PULLS then pull(p,now)else done=true end
            end
            if done and pending==p then
                pending=nil;stopTimer()
                say('防坠观察结束 '..p.label..' 拉回'..p.hold.pulls..'次 当前='..text(now))
                self.last={ok=true,message=p.hold.pulls>0 and('已到达（落下去过，拉回'..p.hold.pulls..'次）')or'已到达',place=p.label}
            end
            return
        end
        local waited=clock()-p.started
        local arrived=false
        if now and now.world==p.place.world then
            local dx,dy=now.x-p.place.x,now.y-p.place.y
            arrived=math.sqrt(dx*dx+dy*dy)<=Teleport.ARRIVED_CM
        end
        if arrived then
            p.hold={untilTime=clock()+Teleport.HOLD_SECONDS,pulls=0}
            say('传送读回 到位 '..p.label..' 当前='..text(now)..' 用时='..string.format('%.1f',waited)..'秒；接下来'
                ..Teleport.HOLD_SECONDS..'秒观察高度，掉下去就拉回')
            self.last={ok=true,message='已到达',place=p.label}
        elseif waited>=Teleport.READBACK_SECONDS then
            pending=nil;stopTimer()
            say('传送读回 超时 '..p.label..' 目标='..text(p.place)..' 当前='..text(now)..'（'..Teleport.READBACK_SECONDS..'秒内没有读到到位）')
            self.last={ok=false,message='没有读到到位，当前在 '..text(now),place=p.label}
        end
    end
    function self:status()
        return {pending=pending~=nil and pending.hold==nil,can_return=self.back~=nil,last=self.last}
    end
    function self:silence()self.alive=false;pending=nil;stopTimer()end
    return self
end
return Teleport
