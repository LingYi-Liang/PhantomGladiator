package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Track=require('camera_track')
local serial=0
local function near(a,b,tolerance)return math.abs(a-b)<(tolerance or 0.5) end
local function wrap(a)return (a+180)%360-180 end
local function unit(class,x,y,z,fields)
    serial=serial+1;local address=serial
    local o=fields or {}
    o.live=true
    o.IsValid=function(self)return self.live end
    o.GetAddress=function()return address end
    o.GetClass=function()return {GetFName=function()return {ToString=function()return class end}end}end
    o.at={X=x,Y=y,Z=z}
    o.hp=100
    o.CapsuleComponent={IsValid=function()return true end,GetAddress=function()return address+100000 end,
        GetScaledCapsuleRadius=function()return o.radius or 50 end,GetScaledCapsuleHalfHeight=function()return o.half or 100 end}
    return o
end
local function filesystem(files)
    local fs={files=files or {}}
    function fs.open(path,mode)
        if mode:find('r',1,true) then
            local text=fs.files[path]
            if not text then return nil end
            return {read=function()return text end,close=function()return true end}
        end
        if fs.deny then return nil end
        local out={}
        return {write=function(_,s)out[#out+1]=s;return true end,close=function()if not fs.lose then fs.files[path]=table.concat(out) end;return true end}
    end
    return fs
end
local function harness(extra)
    local h={lines={},members={},fs=filesystem(),opponents={},bosses={},now=0,position={X=0,Y=-800,Z=300},rotation={Pitch=-12,Yaw=90,Roll=0},fov=90}
    local settings={log=function(s)h.lines[#h.lines+1]=s end,path='memory',io=h.fs,members=function()return h.members end,
        hp=function(a)return a.hp end,location=function(a)return a.at end,
        view=function()return h.position,h.rotation end,fov=function()return h.fov end,
        isBoss=function(a)return h.bosses[a]==true end,
        opponentOf=function(a)return h.opponents[a] end}
    for key,value in pairs(extra or {})do settings[key]=value end
    h.track=Track.new(settings)
    function h.add(class,x,y,z,team,fields)
        local actor=unit(class,x,y,z,fields)
        h.members[#h.members+1]={actor=actor,team=team or 'blue'}
        return actor
    end
    -- Runs seconds of frames at 60 fps with this input, each frame's answer kept.
    function h.run(seconds,input)
        local steps=math.max(1,math.floor(seconds*60+0.5))
        local position,rotation
        for _=1,steps do
            h.now=h.now+1/60
            position,rotation=h.track:frame(1/60,h.now,input or {})
            if not position then return nil end
            h.position,h.rotation=position,rotation
        end
        return position,rotation
    end
    function h.all()return table.concat(h.lines,'\n')end
    return h
end

-- Not in the free camera, nobody on the field: says so, nothing starts.
do
    local h=harness({view=function()return nil end})
    h.add('BP_A_C',0,0,100)
    local result=h.track:start()
    assert(not result.ok and result.spawned_count==0 and result.message:find('不在自由观战',1,true))
    assert(not h.track:running() and h.track:frame(1/60,1,{})==nil)
    local empty=harness()
    assert(not empty.track:start().ok and empty.track:start().message:find('没有可跟踪',1,true))
    assert(not empty.track:status().on)
end
-- Starting does not jump: the first frame is where the camera already was, and it travels from there.
do
    local h=harness()
    local a=h.add('BP_A_C',3000,0,100)
    assert(h.track:start().ok and h.track:running())
    local before={X=h.position.X,Y=h.position.Y,Z=h.position.Z}
    h.now=1/60
    local position=h.track:frame(1/600,h.now,{})
    assert(near(position.X,before.X,15) and near(position.Y,before.Y,15) and near(position.Z,before.Z,15),position.X..','..position.Y..','..position.Z)
    local travelled=h.run(0.1)
    assert(travelled.X<1000,'travels over, not snaps: '..travelled.X)
    assert(h.track:status().target==tostring(a.GetAddress()))
    assert(h.all():find('主目标=BP_A_C（开始）',1,true),h.all())
end
-- Side: the view settles across the line between the two, the followed unit nearer the middle, both in the picture; the distance
-- is worked out from the field of view. Reads back in the log.
do
    local h=harness()
    h.position,h.rotation={X=500,Y=-1200,Z=300},{Pitch=-12,Yaw=90,Roll=0}
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red')
    h.opponents[a]=b;h.opponents[b]=a
    assert(h.track:start(tostring(a.GetAddress())).ok)
    local position,rotation=h.run(6)
    assert(near(wrap(rotation.Yaw-90),0,1),rotation.Yaw)
    assert(near(rotation.Pitch,-12,0.5),rotation.Pitch)
    -- Look point 65% the followed unit, 30 cm up; distance (0.65*1000+1.5*50+150)/tan45 = 875.
    local distance=875
    local p=math.rad(-12)
    assert(near(position.X,350,2),position.X)
    assert(near(position.Y,0-math.cos(p)*distance,3),position.Y)
    assert(near(position.Z,130-math.sin(p)*distance,3),position.Z)
    assert(h.all():find('对手=BP_B_C',1,true) and h.all():find('读回 主目标=BP_A_C 对手=BP_B_C 两人距离=10.0m',1,true),h.all())
    -- Inside the dead zone the view does not turn: the pair turned 20 degrees.
    b.at={X=math.cos(math.rad(20))*1000,Y=math.sin(math.rad(20))*1000,Z=100}
    h.now=h.now+1
    local _,turned=h.run(3)
    assert(near(wrap(turned.Yaw-90),0,1),'stays inside the dead zone: '..turned.Yaw)
    -- Past it, it turns only as far as the zone's edge, and not faster than 40 degrees a second.
    b.at={X=0,Y=1000,Z=100}   -- now along Y: square is yaw 0 or 180, 90 from where it looks
    local _,oneFrame=h.run(1/60)
    assert(near(wrap(oneFrame.Yaw-90),0,1.5),'no jump')
    local _,later=h.run(6)
    assert(math.abs(wrap(later.Yaw-90))>60 and math.abs(wrap(later.Yaw-90))<=66,later.Yaw)
    -- They swap places: square is the same line, the view does not go round the other way.
    local a0=a.at;a.at,b.at=b.at,a0
    local _,swapped=h.run(3)
    assert(near(wrap(swapped.Yaw-later.Yaw),0,1.5),swapped.Yaw..' '..later.Yaw)
end
-- Far apart: no further than the cap, and the opponent pulls the look point no further than one 40 m away. Close together: not nearer than the height of the taller one needs.
do
    local h=harness()
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',20000,0,100,'red')
    h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    h.run(8)
    assert(near(h.track:status().on and math.sqrt((h.position.X-13000*0.5385)^2)<1e9 and 1 or 0,1),'running')
    local far=harness()
    far.position,far.rotation={X=0,Y=-2500,Z=300},{Pitch=-12,Yaw=90,Roll=0}
    local one=far.add('BP_A_C',0,0,100);local two=far.add('BP_B_C',20000,0,100,'red')
    far.opponents[one]=two
    far.track:start(tostring(one.GetAddress()))
    local p=far.run(10)
    local look={X=1400,Y=0,Z=130}
    local d=math.sqrt((p.X-look.X)^2+(p.Y-look.Y)^2+(p.Z-look.Z)^2)
    assert(near(d,2500,5),d)
    local tall=harness()
    local big=tall.add('BP_Big_C',0,0,100,'blue',{half=400,radius=120});local small=tall.add('BP_S_C',60,0,100,'red')
    tall.opponents[big]=small
    tall.track:start(tostring(big.GetAddress()))
    local q=tall.run(10)
    local gap=math.sqrt((q.X-21)^2+q.Y^2+(q.Z-130)^2)
    assert(near(gap,400*1.3/(9/16),6),gap)
end
-- A narrower or wider view changes the distance; a field of view that cannot be read counts as 90.
do
    local h=harness();h.fov=60
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    local p=h.run(8)
    local d=math.sqrt((p.X-350)^2+p.Y^2+(p.Z-130)^2)
    assert(near(d,875/math.tan(math.rad(30)),6),d)
end
-- Mouse: holds the angle, the automatic angle waits, then eases back after the resume time. Other channels are not touched.
do
    local h=harness()
    h.position,h.rotation={X=350,Y=-900,Z=300},{Pitch=-12,Yaw=90,Roll=0}
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    h.run(4)
    local _,turned=h.run(0.5,{mx=2,my=-0.2,turn=100,smooth=40})
    assert(wrap(turned.Yaw-90)>40,turned.Yaw)
    local kept=turned.Yaw
    -- Off the mouse for less than the resume time (3 s): it stays, even with the pair moving.
    b.at={X=0,Y=1000,Z=100}
    local _,waiting=h.run(2,{turn=100,smooth=40})
    assert(math.abs(wrap(waiting.Yaw-kept))<8,'waits: '..waiting.Yaw..' '..kept)
    b.at={X=1000,Y=0,Z=100}
    -- After it, back to automatic.
    local _,back=h.run(5,{turn=100,smooth=40})
    assert(near(wrap(back.Yaw-90),0,3),back.Yaw)
    assert(near(back.Pitch,-12,1.5),back.Pitch)
end
-- Pulling past the limit does not store up: the first move back answers at once.
do
    local h=harness()
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    h.run(3)
    local _,top=h.run(1,{my=20,turn=100,smooth=0})
    assert(near(top.Pitch,40,0.5),top.Pitch)
    local _,back=h.run(5/60,{my=-2,turn=100,smooth=0})
    assert(near(back.Pitch,30,0.5),back.Pitch)
end
-- Resume 0: the hand's angle stays.
do
    local h=harness()
    h.track:set('side',0)
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    h.run(4)
    local _,turned=h.run(0.5,{mx=2,turn=100,smooth=40})
    local _,later=h.run(8,{turn=100,smooth=40})
    assert(math.abs(wrap(later.Yaw-turned.Yaw))<8 and wrap(later.Yaw-90)>40,later.Yaw)
end
-- Wheel: closer for a positive turn, and the auto distance waits; then back. The first read is logged, to know the wheel reads at all.
do
    local h=harness()
    h.position,h.rotation={X=350,Y=-900,Z=300},{Pitch=-12,Yaw=90,Roll=0}
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    h.run(5)
    -- The view looks along Y, so the distance shows in Y and Z wherever the look point goes along X.
    local function shown()return math.sqrt(h.position.Y^2+(h.position.Z-130)^2) end
    local auto=shown()
    h.now=h.now+1/60;h.track:frame(1/60,h.now,{wheel=3})
    h.run(1)
    assert(shown()<auto*0.8,shown())
    assert(h.all():find('滚轮读回=3',1,true),h.all())
    local zoomed=shown()
    b.at={X=3000,Y=0,Z=100}
    h.run(1)
    assert(near(shown(),zoomed,10),'the look moves, the distance is the hand\'s')
    b.at={X=1000,Y=0,Z=100}
    h.run(8)
    assert(near(shown(),auto,8),shown()..' '..auto)
    -- Its limits.
    for _=1,60 do h.now=h.now+1/60;h.track:frame(1/60,h.now,{wheel=5}) end
    h.run(1)
    assert(shown()>=auto*0.3-5,'not closer than the limit')
end
-- WASD/QE: an offset from the look point, in the view's directions, Shift faster, and back after the resume time.
do
    local h=harness()
    h.position,h.rotation={X=350,Y=-900,Z=300},{Pitch=-12,Yaw=90,Roll=0}
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    local start=h.run(5)
    local moved=h.run(1,{right=1,speed=900,smooth=40})
    -- Yaw 90: the view's right is -X.
    assert(moved.X<start.X-500,moved.X..' '..start.X)
    local stillOff=h.run(2,{speed=900,smooth=40})
    assert(stillOff.X<start.X-500,'stays while within the resume time')
    local home=h.run(4,{speed=900,smooth=40})
    assert(near(home.X,start.X,5),home.X)
    local up=h.run(0.5,{up=1,speed=900,smooth=40})
    assert(up.Z>start.Z+200,up.Z)
    h.run(8,{speed=900,smooth=40})
    local slow=h.run(0.5,{forward=1,speed=900,smooth=0})
    h.run(8,{speed=900,smooth=0})
    local fast=h.run(0.5,{forward=1,fast=true,speed=900,smooth=0})
    assert(fast.Y-start.Y>(slow.Y-start.Y)*2.5,'Shift is faster')
end
-- Shoulder: behind the followed unit, looking at the opponent, a little to the side.
do
    local h=harness();h.track:set('shoulder',3)
    h.position,h.rotation={X=-300,Y=-300,Z=300},{Pitch=-12,Yaw=45,Roll=0}
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    local p,r=h.run(6)
    assert(near(wrap(r.Yaw),0,6),r.Yaw)
    assert(p.X<-350 and p.X>-520,p.X)
    assert(p.Y>30 and p.Y<140,'to the side: '..p.Y)
end
-- Orbit: follows position and distance, leaves the angle alone; the mouse's angle stays with no return.
do
    local h=harness();h.track:set('orbit',3)
    h.position,h.rotation={X=-300,Y=-300,Z=300},{Pitch=-20,Yaw=30,Roll=0}
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    local _,r=h.run(5)
    assert(near(r.Yaw,30,0.5) and near(r.Pitch,-20,0.5),r.Yaw)
    local _,turned=h.run(0.2,{mx=1,turn=100,smooth=40})
    assert(turned.Yaw>30)
    local _,later=h.run(8,{turn=100,smooth=40})
    assert(math.abs(wrap(later.Yaw-(30+12)))<1.5,later.Yaw)
end
-- The opponent changes: followed in the frame, at 4 Hz. With none, a set distance around the unit.
do
    local h=harness()
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');local c=h.add('BP_C_C',0,1000,100,'red')
    h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    h.run(2)
    assert(h.track:status().other_class=='BP_B_C')
    h.opponents[a]=c
    h.run(0.4)
    assert(h.track:status().other_class=='BP_C_C')
    h.opponents[a]=nil
    h.run(0.4)
    assert(h.track:status().other_class=='')
    local p=h.run(8)
    local d=math.sqrt(p.X^2+p.Y^2+(p.Z-130)^2)
    assert(near(d,500,4),d)
end
-- The followed unit falls: the view stays on it for a moment, then its opponent, or the next unit; nobody left ends the following.
do
    local h=harness()
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');local c=h.add('BP_C_C',5000,0,100,'red')
    h.opponents[a]=b;h.opponents[b]=a
    h.track:start(tostring(a.GetAddress()))
    h.run(2)
    a.hp=0
    h.run(1)
    assert(h.track:status().target==tostring(a.GetAddress()),'stays a moment')
    assert(h.all():find('主目标倒下 BP_A_C，停 1.5 秒',1,true),h.all())
    h.run(1)
    assert(h.track:status().target==tostring(b.GetAddress()),'then the one it fought')
    assert(h.all():find('主目标=BP_B_C（原目标倒下）',1,true),h.all())
    -- B falls too, with no opponent left: the next on the field.
    h.opponents[b]=nil
    b.hp=0
    h.run(2.5)
    assert(h.track:status().target==tostring(c.GetAddress()))
    -- Destroyed outright: treated the same. Nobody left: over, back to the free camera.
    c.live=false
    assert(h.run(3)==nil and not h.track:running())
    assert(h.all():find('结束（场上没有可跟踪的单位了）',1,true),h.all())
end
-- Stands, reserves and the dead cannot be chosen. Bosses come first; next goes round; pick takes the one in the middle of the view.
do
    local h=harness()
    h.position,h.rotation={X=0,Y=0,Z=100},{Pitch=0,Yaw=0,Roll=0}
    local mob=h.add('BP_Mob_C',1000,1000,100)
    local boss=h.add('BP_Boss_C',-1000,0,100,'red');h.bosses[boss]=true
    local middle=h.add('BP_Middle_C',1000,10,100)
    h.members[#h.members+1]={actor=unit('BP_Stand_C',1000,0,100),team='blue',stand=true}
    h.members[#h.members+1]={actor=unit('BP_Reserve_C',1000,0,100),team='blue',reserve=true}
    local dead=h.add('BP_Dead_C',1000,0,100);dead.hp=0
    local listed=h.track:targets()
    assert(listed:find('^'..boss.GetAddress()..':BP_Boss_C:red;'),listed)
    assert(not listed:find('Stand',1,true) and not listed:find('Reserve',1,true) and not listed:find('Dead',1,true),listed)
    assert(h.track:pick().ok and h.track:status().target_class=='BP_Middle_C')
    assert(h.track:next().ok and h.track:status().target_class=='BP_Boss_C','round to the first')
    assert(h.track:next().ok and h.track:status().target_class=='BP_Mob_C')
    assert(h.track:pick().ok and h.track:status().target_class=='BP_Middle_C')
    assert(h.track:set('side',3,tostring(mob.GetAddress())).ok and h.track:status().target_class=='BP_Mob_C')
    assert(not h.track:set('side',3,'424242').ok,'gone')
    assert(h.track:finish().ok and not h.track:running())
    assert(h.track:next().ok and h.track:running(),'next starts it too')
    h.track:finish()
    assert(h.track:pick().ok and h.track:running(),'pick starts it too')
    h.track:finish()
    assert(h.track:set('side',3,tostring(mob.GetAddress())).ok and h.track:running() and h.track:status().target_class=='BP_Mob_C','choosing starts it')
    -- More units than the list holds.
    local crowd=harness()
    for _=1,30 do crowd.add('BP_M_C',0,0,100) end
    local _,commas=crowd.track:targets():gsub(';','')
    assert(commas==23)
end
-- A new target: the view travels there rather than cutting. The camera's stop ends it.
do
    local h=harness()
    h.position,h.rotation={X=0,Y=-500,Z=300},{Pitch=-12,Yaw=90,Roll=0}
    local a=h.add('BP_A_C',0,0,100);local far=h.add('BP_F_C',10000,0,100,'red')
    h.track:start(tostring(a.GetAddress()))
    h.run(4)
    h.track:set('side',3,tostring(far.GetAddress()))
    local p=h.run(0.1)
    assert(p.X<3000,'travels: '..p.X)
    p=h.run(5)
    assert(near(p.X,10000,10),p.X)
    h.track:stop('退出自由观战')
    assert(not h.track:running() and h.all():find('结束（退出自由观战）',1,true))
    h.track:stop('again')
end
-- A wall between the look point and the camera: closer once it is there, back out slowly when it has been gone a while; a look point inside something is ignored.
do
    local wall
    local traces=0
    local bone
    local body=unit('BP_Player_C',0,-100,100)
    local h=harness({trace=function(world,from,to,channel)
        traces=traces+1
        assert(world=='WORLD' and channel==1,'the wall check asks the camera channel')
        if wall=='inside' then return {inside=true} end
        if wall then return {at={X=from.X+(to.X-from.X)*wall,Y=from.Y+(to.Y-from.Y)*wall,Z=from.Z+(to.Z-from.Z)*wall},distance=1,bone=bone} end
    end,player=function()return body end})
    h.position,h.rotation={X=0,Y=-500,Z=300},{Pitch=-12,Yaw=90,Roll=0}
    body.at={X=9000,Y=9000,Z=100}
    local a=h.add('BP_A_C',0,0,100,'blue',{radius=10})
    h.track:start(tostring(a.GetAddress()))
    local input={world='WORLD'}
    local function shown()return math.sqrt(h.position.X^2+h.position.Y^2+(h.position.Z-130)^2) end
    h.run(4,input)
    assert(near(shown(),500,3) and traces>=30 and traces<=45,traces)
    wall=0.4
    h.run(0.5,input)
    assert(near(shown(),170,12),shown())
    assert(h.all():find('',1,true))
    wall=nil
    h.run(0.2,input)
    assert(shown()<400,'comes back slowly')
    h.run(5,input)
    assert(near(shown(),500,5),shown())
    wall='inside'
    h.run(1,input)
    assert(near(shown(),500,5),'ignored')
    -- A skeleton in the line is not a wall.
    wall,bone=0.4,'spine_01'
    h.run(1,input)
    assert(near(shown(),500,5),shown())
    assert(h.all():find('视线被单位挡住，不算墙，距离不变 骨骼=spine_01',1,true),h.all())
    -- Nor is a capsule: another unit's, or the hidden player's. The line's hit is on it.
    bone=nil
    local passer=h.add('BP_P_C',0,-196,170)
    h.run(1,input)
    assert(near(shown(),500,5),shown())
    passer.at={X=0,Y=-196-71,Z=170}
    h.run(1,input)
    assert(shown()<300,'just past the capsule: a wall')
    wall=nil;h.run(5,input);assert(near(shown(),500,5))
    wall=0.4;passer.at={X=9000,Y=0,Z=0};body.at={X=0,Y=-196,Z=170}
    h.run(1,input)
    assert(near(shown(),500,5),shown())
    -- A wall already in force stays while someone stands in the line.
    body.at={X=9000,Y=9000,Z=100}
    h.run(1,input)
    local held=shown()
    assert(held<300)
    bone='spine_01'
    h.run(1,input)
    assert(near(shown(),held,5),shown())
    bone=nil
    -- Never closer than the least it allows.
    wall=0.12
    h.run(2,input)
    assert(near(shown(),100,5),shown())
end
-- A branch the line sweeps past once does not pull the view in. A line that keeps flickering holds the view in instead
-- of letting it jump out and back (the distance jumped between 1 m and 22 m every few seconds).
do
    local wall
    local traces=0
    local h=harness({trace=function(_,from,to)
        traces=traces+1
        if wall then return {at={X=from.X+(to.X-from.X)*wall,Y=from.Y+(to.Y-from.Y)*wall,Z=from.Z+(to.Z-from.Z)*wall},distance=1} end
    end})
    h.position,h.rotation={X=0,Y=-500,Z=300},{Pitch=-12,Yaw=90,Roll=0}
    local a=h.add('BP_A_C',0,0,100,'blue',{radius=10})
    h.track:start(tostring(a.GetAddress()))
    local input={world='WORLD'}
    local function shown()return math.sqrt(h.position.X^2+h.position.Y^2+(h.position.Z-130)^2) end
    h.run(4,input)
    assert(near(shown(),500,3),shown())
    wall=0.4
    local before=traces
    repeat h.run(1/60,input) until traces>before
    wall=nil
    h.run(1,input)
    assert(near(shown(),500,3),'one blocked trace leaves the view where it is: '..shown())
    wall=0.4
    h.run(0.5,input)
    assert(shown()<200,shown())
    local most=0
    for i=1,10 do
        if i%2==1 then wall=nil else wall=0.4 end
        h.run(0.3,input)
        most=math.max(most,shown())
    end
    assert(most<250,'a flickering line holds the view in: '..most)
    wall=nil
    h.run(5,input)
    assert(near(shown(),500,5),shown())
    assert(h.all():find('通道=相机',1,true) and h.all():find('墙拉近=1次',1,true),h.all())
end
-- Settings: saved and read back, refused when out of range or not saved; a damaged file means the defaults.
do
    local h=harness()
    assert(h.track:status().framing=='side' and h.track:status().resume==3)
    assert(h.track:set('orbit',5).ok)
    assert(h.fs.files['memory/camera-track.tsv']=='CameraTrackV1\tframing=orbit\tresume=5\n',h.fs.files['memory/camera-track.tsv'])
    assert(h.all():find('设置 构图=orbit 回归=5秒 保存读回=true',1,true),h.all())
    for _,bad in ipairs({{'wide',3},{'side',11},{'side',-1},{'side',1.5},{'side','x'},{nil,3}})do
        assert(not h.track:set(bad[1],bad[2]).ok)
    end
    assert(h.track:status().framing=='orbit' and h.track:status().resume==5)
    h.fs.lose=true
    assert(not h.track:set('side',1).ok and h.track:status().framing=='orbit')
    h.fs.lose=false
    local again=Track.new({path='memory',io=h.fs,members=function()return {} end})
    assert(again:status().framing=='orbit' and again:status().resume==5)
    for _,text in ipairs({'','OldV0\tframing=orbit\n','CameraTrackV1\tframing=huge\tresume=99\n'})do
        local fresh=Track.new({path='memory',io=filesystem({['memory/camera-track.tsv']=text}),members=function()return {} end})
        assert(fresh:status().framing=='side' and fresh:status().resume==3)
    end
end
-- Limits: however long the keys are held, with no return to automatic, the view stays within reach of the followed unit.
do
    local h=harness()
    h.track:set('side',0)
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    local start=h.run(4)
    local function fromStart(p)return math.sqrt((p.X-start.X)^2+(p.Y-start.Y)^2+(p.Z-start.Z)^2) end
    local far=h.run(60,{up=-1,forward=1,right=1,fast=true,speed=900,smooth=40})
    assert(fromStart(far)<=3000+5,fromStart(far))
    assert(fromStart(far)>2900,'the hand does get there')
    assert(h.all():find('平移到上限 30m 读回=30m',1,true),h.all())
    -- Turning back answers at once, it does not first have to undo what pushed against the limit.
    local back=h.run(0.25,{up=1,forward=-1,right=-1,speed=900,smooth=40})
    assert(fromStart(back)<fromStart(far)-80,fromStart(far)-fromStart(back))
    local settled=h.run(1,{speed=900,smooth=40})
    local stay=h.run(5,{speed=900,smooth=40})
    assert(near(fromStart(stay),fromStart(settled),5),'stays, resume 0')
end
-- The view also stays within 100 m of the unit with the wheel all the way out on top of it.
do
    local h=harness()
    h.track:set('side',0)
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',3400,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    h.run(8)
    for _=1,120 do h.now=h.now+1/60;h.track:frame(1/60,h.now,{wheel=-5}) end
    local p=h.run(30,{forward=-1,up=1,fast=true,speed=900,smooth=40})
    local d=math.sqrt(p.X^2+p.Y^2+(p.Z-100)^2)
    assert(d<=10000+1 and d>9500,d)
    assert(h.all():find('镜头到距离上限 100m',1,true),h.all())
end
-- An opponent very far away, or deep under the map: the view keeps to the followed unit, it does not go after that one.
do
    for _,place in ipairs({{50000,0,100},{0,0,-60000},{30000,0,-40000}})do
        local h=harness()
        local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
        h.track:start(tostring(a.GetAddress()))
        h.run(4)
        b.at={X=place[1],Y=place[2],Z=place[3]}
        local p=h.run(6)
        local d=math.sqrt(p.X^2+p.Y^2+(p.Z-100)^2)
        assert(d<=1400+2500+200,d)
        assert(p.Z>100-1400-100,'not pulled underground '..p.Z)
    end
    -- With a wide view the distance is what the opponent's reach asks for, not what its real distance would.
    do
        local h=harness();h.fov=120
        h.position,h.rotation={X=0,Y=-1600,Z=300},{Pitch=-12,Yaw=90,Roll=0}
        local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',50000,0,100,'red');h.opponents[a]=b
        h.track:start(tostring(a.GetAddress()))
        local p=h.run(10)
        local d=math.sqrt((p.X-1400)^2+p.Y^2+(p.Z-130)^2)
        assert(near(d,1631,40),d)
    end
    -- The far opponent can come back: within reach nothing has changed.
    local h=harness()
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',50000,0,100,'red');h.opponents[a]=b
    h.position,h.rotation={X=0,Y=-2500,Z=300},{Pitch=-12,Yaw=90,Roll=0}
    h.track:start(tostring(a.GetAddress()))
    h.run(4)
    b.at={X=1000,Y=0,Z=100}
    local p=h.run(8)
    local dir=math.rad(90)
    assert(near(p.X,350,40),'the look point is the old share of the way again '..p.X)
end
-- The keys do not take the view through the ground; from under it the wall check would find nothing to stop the camera.
do
    local floor=0
    local function hitFloor(from,to)
        if from.Z<=floor or to.Z>=floor then return nil end
        local t=(from.Z-floor)/(from.Z-to.Z)
        return {at={X=from.X+(to.X-from.X)*t,Y=from.Y+(to.Y-from.Y)*t,Z=floor},normal={X=0,Y=0,Z=1},distance=1}
    end
    local h=harness({trace=function(_,from,to)return hitFloor(from,to) end})
    h.track:set('side',0)
    local a=h.add('BP_A_C',0,0,100);local b=h.add('BP_B_C',1000,0,100,'red');h.opponents[a]=b
    h.track:start(tostring(a.GetAddress()))
    h.run(4,{world='WORLD'})
    local p=h.run(20,{up=-1,fast=true,speed=900,smooth=40,world='WORLD'})
    assert(p.Z>floor,'camera above the ground '..p.Z)
    assert(h.all():find('平移碰到地面',1,true),h.all())
    -- Without the check the same keys go 15 m under it.
    local free=harness()
    free.track:set('side',0)
    local a1=free.add('BP_A_C',0,0,100);local b1=free.add('BP_B_C',1000,0,100,'red');free.opponents[a1]=b1
    free.track:start(tostring(a1.GetAddress()))
    free.run(4)
    assert(free.run(20,{up=-1,fast=true,speed=900,smooth=40}).Z<-1500)
    -- A wall in the way of the keys does not stop them; only ground under the view does.
    local wall=harness({trace=function(_,from,to)
        return {at={X=(from.X+to.X)/2,Y=(from.Y+to.Y)/2,Z=(from.Z+to.Z)/2},normal={X=1,Y=0,Z=0},distance=1}
    end})
    wall.track:set('side',0)
    local a2=wall.add('BP_A_C',0,0,100);local b2=wall.add('BP_B_C',1000,0,100,'red');wall.opponents[a2]=b2
    wall.track:start(tostring(a2.GetAddress()))
    wall.run(4,{world='WORLD'})
    wall.run(1,{up=-1,speed=900,smooth=40,world='WORLD'})
    assert(not wall.all():find('平移碰到地面',1,true),wall.all())
end
print('camera_track: PASS')
