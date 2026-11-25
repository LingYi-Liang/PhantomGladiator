package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Teleport=require('teleport')
local index=0
local function object(fields)
    index=index+1;local id=index;local a=fields or {}
    a.valid=true
    function a:IsValid()return self.valid end
    function a:GetAddress()return id end
    return a
end
local function fixture()
    local h={logs={},calls={},pulls={},timers={},cancelled=0,now=0,world='PBZ_Xigu_WP',at={X=100,Y=200,Z=300},yaw=90,identity='1|2|3'}
    h.player=object()
    function h.player:K2_GetActorLocation()h.positionReads=(h.positionReads or 0)+1;return h.at end
    function h.player:K2_GetActorRotation()return {Pitch=0,Yaw=h.yaw,Roll=0}end
    h.movement=object();h.stops=0
    function h.movement:StopMovementImmediately()h.stops=h.stops+1 end
    function h.player:GetMovementComponent()return h.movement end
    function h.player:K2_TeleportTo(location,rotation)
        h.pulls[#h.pulls+1]={location=location,rotation=rotation,logs=#h.logs}
        if not h.pullIgnored then h.at={X=location.X,Y=location.Y,Z=location.Z}end
        return true
    end
    h.subsystem=object()
    function h.subsystem:TeleportTo(level,transform,bell)
        h.calls[#h.calls+1]={level=level,transform=transform,bell=bell,logs=#h.logs}
        if h.throws then error('native fixture failure')end
    end
    h.mod=Teleport.new({log=function(s)h.logs[#h.logs+1]=s end,fname=function(s)return 'N:'..s end,clock=function()return h.now end,
        player=function()return h.player end,worldName=function()
             if h.readThrows then error('transient world read') end
             return h.world
         end,
        find=function(name)assert(name=='PBZSaveLoadSubsystem');return h.subsystem end,
        blocked=function()return h.blocked end,
        worldKey=function()
            if h.identityFails then error('reading') end
            return h.identity and h.identity:match('^[^|]+')
        end,
        loop=function(ms,fn)h.timers[#h.timers+1]={ms=ms,fn=fn};return #h.timers end,
        cancel=function(handle)assert(handle==#h.timers);h.cancelled=h.cancelled+1 end})
    function h:logged(text)local n=0;for _,line in ipairs(self.logs)do if line:find(text,1,true)then n=n+1 end end;return n end
    return h
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end
local PLACE={world='PBZ_Duanhun_WP',x=-193040,y=-117950,z=4500030,yaw=180,name='左殇'}

test('a place is checked before anything is called',function()
    assert(Teleport.check(PLACE))
    for _,bad in ipairs({false,{},{world='a b',x=0,y=0,z=0},{world='/Game/X',x=0,y=0,z=0},{world=('x'):rep(65),x=0,y=0,z=0},
        {world='W',x=0/0,y=0,z=0},{world='W',x=0,y=3e7,z=0},{world='W',x=0,y=0,z='1'},{world='W',x=0,y=0,z=0,yaw=1000}})do
        assert(not Teleport.check(bad))
        local h=fixture();assert(not h.mod:go(bad).ok and #h.calls==0 and #h.logs==0)
    end
end)
test('a late timer cannot drive a new teleport and a stopped native clock has a support fallback',function()
    local h=fixture();assert(h.mod:go(PLACE).ok);local old=h.timers[1].fn
    h.now=41;old();assert(not h.mod:busy());assert(h.mod:go(PLACE).ok)
    h.world=PLACE.world;h.at={X=PLACE.x,Y=PLACE.y,Z=PLACE.z};h.now=41.2
    local before=h.positionReads;old()
    assert(h.positionReads==before and h.mod:status().pending,'previous timer sampled a new teleport')
    assert(not h.mod:needsSupportTick(),'normal fast timer was duplicated by support')
    h.now=42;assert(h.mod:needsSupportTick(),'an acknowledged timer that stopped firing needs a fallback')
    h.mod:tick();assert(not h.mod:status().pending);before=h.positionReads
    h.timers[2].fn();assert(h.positionReads==before,'native callback repeated the same support read')
end)
test('expired fall protection never pulls the player back after the window',function()
    local h=fixture();assert(h.mod:go(PLACE).ok)
    h.world=PLACE.world;h.at={X=PLACE.x,Y=PLACE.y,Z=PLACE.z};h.mod:tick()
    h.now=Teleport.HOLD_SECONDS+1;h.at.Z=PLACE.z-800;h.mod:tick()
    assert(not h.mod:busy() and #h.pulls==0,'expired fall protection moved the player')
end)
test('the game teleport is called as the teleporter device calls it, announced first',function()
    local h=fixture();local result=h.mod:go(PLACE)
    assert(result.ok and #h.calls==1)
    local c=h.calls[1]
    assert(c.level=='N:PBZ_Duanhun_WP' and c.bell=='N:None','level name and an empty bell id')
    assert(c.transform.Translation.X==-193040 and c.transform.Translation.Z==4500030 and c.transform.Scale3D.X==1)
    assert(math.abs(c.transform.Rotation.Z-1)<1e-9 and math.abs(c.transform.Rotation.W)<1e-9,'yaw 180 as a quaternion')
    assert(c.logs==1 and h.logs[1]:find('即将 传送 左殇 目标=PBZ_Duanhun_WP (-193040,-117950,4500030)',1,true) and h.logs[1]:find('当前=PBZ_Xigu_WP (100,200,300)',1,true))
    assert(h.mod:busy() and h.mod:status().pending and not h.mod:status().can_return)
    assert(not h.mod:go(PLACE).ok and #h.calls==1,'one teleport at a time')
end)
test('the arrival is read back: level and position, or a timeout',function()
    local h=fixture();h.mod:go(PLACE)
    assert(#h.timers==1 and h.timers[1].ms==200,'its own fast timer while a teleport is read back')
    h.now=2;h.mod:tick();assert(h.mod:status().pending,'still in the old level')
    h.world='PBZ_Duanhun_WP';h.at={X=0,Y=0,Z=4500030};h.now=5;h.mod:tick();assert(h.mod:status().pending,'right level, 2 km away')
    h.at={X=-193000,Y=-117900,Z=4500100};h.now=9;h.timers[1].fn()
    assert(h.mod.last.ok and h.mod.last.message=='已到达' and h:logged('传送读回 到位 左殇')==1 and h:logged('用时=9.0秒')==1)
    assert(h.mod:busy() and not h.mod:status().pending,'arrived for the app, the fall watch still runs')
    h.now=20;h.mod:tick();assert(h.mod:busy() and #h.pulls==0,'standing: nothing is written')
    h.now=24.5;h.timers[1].fn()
    assert(not h.mod:busy() and h.cancelled==1 and #h.pulls==0 and h:logged('防坠观察结束 左殇 尝试=0 已确认拉回=0')==1 and h.mod.last.message=='已到达')
    h=fixture();h.mod:go(PLACE);h.now=39;h.mod:tick();assert(h.mod:busy())
    h.now=41;h.mod:tick()
    assert(not h.mod:busy() and h.mod.last.ok==false and h:logged('传送读回 超时 左殇')==1)
    h.now=50;h.mod:tick();assert(#h.logs==2 and h.cancelled==1,'nothing after the wait ended')
end)
-- 11 m from the target in the same level, as in the player's log.
local NEAR={world='PBZ_Xigu_WP',x=1200,y=200,z=340,yaw=0,name='近处'}
test('a target close by in the same level is not an arrival until the map has loaded again',function()
    local h=fixture();h.mod:go(NEAR)
    for i=1,10 do h.now=i*.2;h.mod:tick()end
    assert(h.mod:status().pending and h:logged('到位')==0,'0.2 s after the call the old world is still there')
    local at=h.at;h.at={X=0/0,Y=0,Z=0};h.now=3;h.mod:tick();assert(h.mod:status().pending,'unreadable while it loads');h.at=at
    h.identity='9|8|7';h.at={X=1150,Y=230,Z=340};h.now=3.8;h.mod:tick()
    assert(not h.mod:status().pending and h.mod.last.message=='已到达' and h:logged('地图已重新载入 近处 用时=3.8秒')==1)
    assert(h:logged('到位 近处 目标=PBZ_Xigu_WP (1200,200,340) 当前=PBZ_Xigu_WP (1150,230,340) 重新载入=true 用时=3.8秒')==1)
    h.now=18.7;h.mod:tick();assert(h.mod:busy(),'the fall watch runs its full time from the arrival')
    h.now=18.9;h.mod:tick();assert(not h.mod:busy() and h:logged('防坠观察结束 近处')==1)
end)
test('a fall right after the reload is pulled back, which the early report used to miss',function()
    local h=fixture();h.mod:go(NEAR);h.now=.2;h.mod:tick()
    h.identity='9|8|7';h.at={X=1200,Y=200,Z=340};h.now=14;h.mod:tick()
    h.at={X=1200,Y=200,Z=-2000};h.now=20;h.mod:tick();assert(#h.pulls==1,'6 s after arriving, 20 s after the call')
end)
test('the new map far from the target keeps waiting, then times out',function()
    local h=fixture();h.mod:go(NEAR);h.identity='9|8|7';h.at={X=90000,Y=0,Z=0};h.now=4;h.mod:tick()
    assert(h.mod:status().pending and h:logged('地图已重新载入')==1);h.now=41;h.mod:tick()
    assert(h.mod.last.ok==false and h:logged('传送读回 超时 近处')==1)
end)
test('ordinary movement or a replaced controller is not proof of a same-map arrival',function()
    local h=fixture()
    local high={world=NEAR.world,x=NEAR.x,y=NEAR.y,z=2300,name='楼上'}
    assert(h.mod:go(high).ok)
    h.identity='1|99|3';h.now=1.7;h.mod:tick()
    assert(h.mod:status().pending,'only the controller changed')
    h.identity='1|99|99';h.at.X=h.at.X+110
    h.now=10.1;h.mod:tick();h.now=10.3;h.mod:tick()
    assert(h.mod:status().pending and #h.pulls==0,'walking nearby must not start the fall watch')
    h.at={X=NEAR.x,Y=NEAR.y,Z=2300};h.now=41;h.mod:tick()
    assert(h.mod.last.ok==false and #h.pulls==0,'coordinates alone cannot acknowledge a reload')
end)
test('an identity that cannot be read is neither a reload nor an error',function()
    for _,start in ipairs({true,false})do
        local h=fixture();h.identityFails=start;h.mod:go(NEAR);h.identityFails=not start
        h.now=2;h.mod:tick();assert(h.mod:status().pending and h:logged('地图已重新载入')==0)
        h.identityFails=false;h.identity=nil;h.now=3;h.mod:tick();assert(h.mod:status().pending)
        h.at={X=1200,Y=200,Z=340};h.now=10.5;h.mod:tick();assert(h.mod:status().pending and #h.pulls==0)
    end
end)
test('a player who falls through the floor after arriving is stopped and put back, announced and read back',function()
    local h=fixture();h.mod:go(PLACE)
    h.world='PBZ_Duanhun_WP';h.at={X=PLACE.x,Y=PLACE.y,Z=PLACE.z-3000};h.now=4;h.mod:tick()
    assert(h.mod.last.message=='已到达' and #h.pulls==0,'the arrival is horizontal; the height is the fall watch')
    h.now=4.2;h.mod:tick()
    assert(#h.pulls==1 and h.stops==1 and h.pulls[1].location.Z==PLACE.z and h.pulls[1].rotation.Yaw==180)
    assert(h.logs[h.pulls[1].logs]:find('即将 防坠拉回 第1次 左殇',1,true) and h:logged('回到目标高度=true')==1)
    h.now=4.4;h.mod:tick();assert(#h.pulls==1,'back on the target: not pulled again')
    h.at={X=PLACE.x,Y=PLACE.y,Z=PLACE.z-500};h.now=5;h.mod:tick();assert(#h.pulls==1,'a short drop is not a fall')
    h.at={X=PLACE.x,Y=PLACE.y,Z=PLACE.z-700};h.now=6;h.mod:tick();assert(#h.pulls==2)
    h.now=30;h.mod:tick()
    assert(not h.mod:busy() and h.mod.last.message=='已到达（落下去过，拉回2次）' and h:logged('防坠观察结束 左殇 尝试=2 已确认拉回=2')==1)
    h=fixture();h.pullIgnored=true;h.mod:go(PLACE);h.world='PBZ_Duanhun_WP';h.at={X=PLACE.x,Y=PLACE.y,Z=0};h.now=1;h.mod:tick()
    for i=1,70 do h.now=1+i*0.2;h.mod:tick()end
    assert(#h.pulls==Teleport.MAX_PULLS and h:logged('回到目标高度=false')==Teleport.MAX_PULLS and not h.mod:busy(),'a pull that never holds stops after its limit')
    assert(h.mod.last.ok==false and h.mod:status().can_return,'failed attempts never report successful recovery')
    h=fixture();h.mod:go(PLACE);h.world='PBZ_Duanhun_WP';h.at={X=PLACE.x,Y=PLACE.y,Z=PLACE.z};h.now=2;h.mod:tick()
    assert(h.mod:go({world='PBZ_Xigu_WP',x=1,y=2,z=3,name='别处'}).ok and #h.calls==2,'a new teleport may start during the fall watch')
    h.world='PBZ_Duanhun_WP';h.at={X=PLACE.x,Y=PLACE.y,Z=0};h.now=3;h.mod:tick();assert(#h.pulls==0,'and the old watch is gone')
end)
test('a new player body or a move away ends the old fall watch',function()
    local h=fixture();h.mod:go(NEAR);h.identity='9|8|7';h.at={X=1200,Y=200,Z=340}
    h.now=3;h.mod:tick();assert(h.mod.last.message=='已到达')
    h.player=object(h.player);h.at.Z=-2000;h.now=3.2;h.mod:tick()
    assert(#h.pulls==0 and not h.mod:busy(),'do not pull a respawned body')
    h=fixture();h.mod:go(NEAR);h.identity='9|8|7';h.at={X=1200,Y=200,Z=340};h.now=3;h.mod:tick()
    h.at={X=7000,Y=200,Z=-2000};h.now=5;h.mod:tick()
    assert(#h.pulls==0 and not h.mod:busy(),'walking away also ends the watch')
end)
test('nothing is called when the player, the level name, the subsystem or the moment is wrong',function()
    local h=fixture();h.player.valid=false;assert(h.mod:go(PLACE).message=='玩家不可读' and #h.calls==0)
    h=fixture();h.world='World 1';assert(h.mod:go(PLACE).message=='当前地图名不可读' and #h.calls==0)
    h=fixture();h.at={X=0/0,Y=0,Z=0};assert(not h.mod:go(PLACE).ok and #h.calls==0)
    h=fixture();h.subsystem.valid=false;assert(h.mod:go(PLACE).message:find('找不到',1,true) and #h.calls==0)
    h=fixture();h.blocked='自由观战中不能传送';assert(h.mod:go(PLACE).message=='自由观战中不能传送' and #h.calls==0)
    h=fixture();h.throws=true;local result=h.mod:go(PLACE)
    assert(not result.ok and not h.mod:busy() and h:logged('传送 调用失败')==1 and h.mod.last.ok==false)
    h=fixture();h.mod:silence();assert(not h.mod:go(PLACE).ok and #h.calls==0)
end)
test('return goes to where the player stood before the last teleport',function()
    local h=fixture();assert(not h.mod:goBack().ok and #h.calls==0)
    h.mod:go(PLACE);h.world='PBZ_Duanhun_WP';h.at={X=PLACE.x,Y=PLACE.y,Z=PLACE.z};h.now=3;h.mod:tick()
    assert(h.mod:goBack().ok and #h.calls==2,'also during the fall watch')
    local c=h.calls[2]
    assert(c.level=='N:PBZ_Xigu_WP' and c.transform.Translation.X==100 and c.transform.Translation.Z==300)
    assert(math.abs(c.transform.Rotation.Z-math.sin(math.rad(45)))<1e-9,'the yaw the player had')
    assert(h:logged('即将 传送 传送前的位置')==1)
end)
test('a timeout on a no-op preserves the previous return point',function()
    local h=fixture();assert(h.mod:go(PLACE).ok)
    h.world=PLACE.world;h.identity='9|8|7';h.at={X=PLACE.x,Y=PLACE.y,Z=PLACE.z};h.now=3;h.mod:tick()
    assert(h.mod:status().can_return)
    assert(h.mod:go(NEAR).ok)
    h.now=44;h.mod:tick()
    assert(h.mod.last.ok==false and h.mod:goBack().ok)
    assert(h.calls[3].level=='N:PBZ_Xigu_WP' and h.calls[3].transform.Translation.X==100)
end)
test('an arrival off target can still return to the departure point',function()
    local h=fixture();assert(h.mod:go(PLACE).ok)
    h.world=PLACE.world;h.identity='9|8|7';h.at={X=PLACE.x+6000,Y=PLACE.y,Z=PLACE.z}
    h.now=41;h.mod:tick()
    assert(h.mod.last.ok==false and h.mod:goBack().ok)
    assert(h.calls[2].level=='N:PBZ_Xigu_WP' and h.calls[2].transform.Translation.X==100)
end)
test('a transient world read error during loading does not abandon the request',function()
    local h=fixture();assert(h.mod:go(PLACE).ok)
    h.readThrows=true;h.now=.2;h.timers[1].fn()
    assert(h.mod:status().pending and h.cancelled==0 and not h.mod:status().can_return)
    h.readThrows=false;h.world=PLACE.world;h.identity='9|8|7';h.at={X=PLACE.x,Y=PLACE.y,Z=PLACE.z}
    h.now=3;h.timers[1].fn()
    assert(h.mod.last.message=='已到达' and h.mod:status().can_return)
end)
print('teleport: PASS '..n..' check/call/readback/fall-watch/refusal/return checks; the native teleport remains unverified in game')
