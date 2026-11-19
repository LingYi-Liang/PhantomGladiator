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
    local h={logs={},calls={},pulls={},timers={},cancelled=0,now=0,world='PBZ_Xigu_WP',at={X=100,Y=200,Z=300},yaw=90}
    h.player=object()
    function h.player:K2_GetActorLocation()return h.at end
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
        player=function()return h.player end,worldName=function()return h.world end,
        find=function(name)assert(name=='PBZSaveLoadSubsystem');return h.subsystem end,
        blocked=function()return h.blocked end,
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
test('the game teleport is called as the teleporter device calls it, announced first',function()
    local h=fixture();local result=h.mod:go(PLACE)
    assert(result.ok and #h.calls==1)
    local c=h.calls[1]
    assert(c.level=='N:PBZ_Duanhun_WP' and c.bell=='N:None','level name and an empty bell id')
    assert(c.transform.Translation.X==-193040 and c.transform.Translation.Z==4500030 and c.transform.Scale3D.X==1)
    assert(math.abs(c.transform.Rotation.Z-1)<1e-9 and math.abs(c.transform.Rotation.W)<1e-9,'yaw 180 as a quaternion')
    assert(c.logs==1 and h.logs[1]:find('即将 传送 左殇 目标=PBZ_Duanhun_WP (-193040,-117950,4500030)',1,true) and h.logs[1]:find('当前=PBZ_Xigu_WP (100,200,300)',1,true))
    assert(h.mod:busy() and h.mod:status().pending and h.mod:status().can_return)
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
    assert(not h.mod:busy() and h.cancelled==1 and #h.pulls==0 and h:logged('防坠观察结束 左殇 拉回0次')==1 and h.mod.last.message=='已到达')
    h=fixture();h.mod:go(PLACE);h.now=39;h.mod:tick();assert(h.mod:busy())
    h.now=41;h.mod:tick()
    assert(not h.mod:busy() and h.mod.last.ok==false and h:logged('传送读回 超时 左殇')==1)
    h.now=50;h.mod:tick();assert(#h.logs==2 and h.cancelled==1,'nothing after the wait ended')
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
    assert(not h.mod:busy() and h.mod.last.message=='已到达（落下去过，拉回2次）' and h:logged('防坠观察结束 左殇 拉回2次')==1)
    h=fixture();h.pullIgnored=true;h.mod:go(PLACE);h.world='PBZ_Duanhun_WP';h.at={X=PLACE.x,Y=PLACE.y,Z=0};h.now=1;h.mod:tick()
    for i=1,70 do h.now=1+i*0.2;h.mod:tick()end
    assert(#h.pulls==Teleport.MAX_PULLS and h:logged('回到目标高度=false')==Teleport.MAX_PULLS and not h.mod:busy(),'a pull that never holds stops after its limit')
    h=fixture();h.mod:go(PLACE);h.world='PBZ_Duanhun_WP';h.at={X=PLACE.x,Y=PLACE.y,Z=PLACE.z};h.now=2;h.mod:tick()
    assert(h.mod:go({world='PBZ_Xigu_WP',x=1,y=2,z=3,name='别处'}).ok and #h.calls==2,'a new teleport may start during the fall watch')
    h.world='PBZ_Duanhun_WP';h.at={X=PLACE.x,Y=PLACE.y,Z=0};h.now=3;h.mod:tick();assert(#h.pulls==0,'and the old watch is gone')
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
print('teleport: PASS '..n..' check/call/readback/fall-watch/refusal/return checks; the native teleport remains unverified in game')
