package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Spot=require('spawn_spot')
local function near(a,b)return math.abs(a-b)<0.01 end
local function harness()
    local h={lines={},world={},traces={}}
    h.spot=Spot.new({log=function(s)h.lines[#h.lines+1]=s end,
        view=function()return h.position,h.rotation end,
        trace=function(world,from,to)
            assert(world==h.world)
            h.traces[#h.traces+1]={from=from,to=to}
            return h.hit and h.hit(from,to) or nil
        end,
        ground=function(world,x,y,z,up)
            assert(world==h.world)
            if h.ground then return h.ground(x,y,z,up) end
            return nil
        end})
    function h.all()return table.concat(h.lines,'\n')end
    return h
end
local BODY,LOOK={X=1000,Y=2000,Z=300},{X=0,Y=1,Z=0}

-- Outside the free camera: the player's body and facing, as before, and the batch's middle is the body.
do
    local h=harness()
    local at,look=h.spot:origin(BODY,LOOK,'blue',h.world)
    assert(at==BODY and look==LOOK and h.spot:anchor()==BODY and #h.traces==0)
    assert(h.all():find('来源=玩家 ',1,true) and h.all():find('玩家身体=1000,2000,300',1,true) and h.all():find('距上次召唤时身体=首次',1,true) and h.all():find('镜头=不在自由观战',1,true),h.all())
    -- The body's move between two summons is on record.
    h.spot:origin({X=1300,Y=2400,Z=300},LOOK,'blue',h.world)
    assert(h.all():find('距上次召唤时身体=500cm',1,true),h.all())
end
-- In the free camera the first row comes out where the view points, on the ground there, turned the view's way.
do
    local h=harness()
    h.position,h.rotation={X=0,Y=0,Z=1000},{Pitch=-45,Yaw=90,Roll=0}
    h.hit=function()return {at={X=0,Y=1000,Z=0},distance=1414} end
    h.ground=function(x,y,z,up)return 10 end
    local at,look=h.spot:origin(BODY,LOOK,'red',h.world)
    assert(#h.traces==1)
    local to=h.traces[1].to
    assert(to.Y>5000 and to.Z<0,'the line follows the view')
    assert(near(look.X,0) and near(look.Y,1) and look.Z==0,'flat, the way the view looks')
    local middle=h.spot:anchor()
    -- 100 cm back from what it hit, toward the camera, along the view.
    assert(near(middle.X,0) and near(middle.Y,1000-100*math.cos(math.rad(45))) and near(middle.Z,110),middle.Y)
    assert(near(at.X,0) and near(at.Y,middle.Y-600) and near(at.Z,110),'the origin is one row behind it')
    assert(h.all():find('来源=镜头看向的地方',1,true) and h.all():find('镜头=0,0,1000',1,true),h.all())
end
-- Looking at nothing: some way ahead. Companions stay by the body they follow.
do
    local h=harness()
    h.position,h.rotation={X=0,Y=0,Z=100},{Pitch=0,Yaw=0,Roll=0}
    h.ground=function()return 0 end
    h.spot:origin(BODY,LOOK,'neutral',h.world)
    assert(near(h.spot:anchor().X,1500) and h.all():find('来源=镜头前方',1,true),h.all())
    local at,look=h.spot:origin(BODY,LOOK,'companion',h.world)
    assert(at==BODY and look==LOOK and h.spot:anchor()==BODY)
end
-- No ground where the view points: back to the body, and the log says why. A camera inside something aims straight ahead.
do
    local h=harness()
    h.position,h.rotation={X=0,Y=0,Z=100},{Pitch=0,Yaw=0,Roll=0}
    local at=h.spot:origin(BODY,LOOK,'blue',h.world)
    assert(at==BODY and h.all():find('镜头前方下方没有地面，改用玩家',1,true),h.all())
    h.hit=function()return {inside=true} end
    h.ground=function()return 0 end
    h.spot:origin(BODY,LOOK,'blue',h.world)
    assert(near(h.spot:anchor().X,1500))
end
-- A roof over a room: the floor is looked for from just over the spot first, and the higher look only when that finds nothing.
do
    local h=harness()
    h.position,h.rotation={X=0,Y=0,Z=100},{Pitch=-10,Yaw=0,Roll=0}
    h.hit=function()return {at={X=500,Y=0,Z=0}} end
    local asked={}
    h.ground=function(x,y,z,up)asked[#asked+1]={z=z,up=up};if #asked==1 then return nil end;return -5 end
    h.spot:origin(BODY,LOOK,'blue',h.world)
    assert(asked[1].z==100 and asked[1].up==0 and asked[2].z==0 and asked[2].up==nil)
    assert(near(h.spot:anchor().Z,95))
end
-- A wall between the middle and a spot: the spot comes back to this side of it, at chest height along the line.
do
    local h=harness()
    h.spot:origin({X=0,Y=0,Z=100},{X=1,Y=0,Z=0},'blue',h.world)
    h.hit=function(from,to)
        assert(from.Z==150 and to.Z==150,'level, over the middle')
        assert(near(from.X,60) and near(from.Y,0),'starting past the body standing there')
        return {at={X=400,Y=0,Z=150},normal={X=-1,Y=0,Z=0}}
    end
    local t={Translation={X=600,Y=0,Z=150}}
    assert(h.spot:clear(h.world,t)==true)
    assert(near(t.Translation.X,280) and near(t.Translation.Y,0) and t.Translation.Z==150)
    assert(h.all():find('出生点被墙挡住 原=600,0,150 墙在中心外 400cm 改到=280,0,150',1,true),h.all())
end
-- Not walls: a hillside, nothing, a hit beyond the spot, a start inside something (said), a spot at the middle.
do
    local h=harness()
    h.spot:origin({X=0,Y=0,Z=100},{X=1,Y=0,Z=0},'blue',h.world)
    local function unchanged(hit,spot)
        h.hit=function()return hit end
        local t={Translation=spot or {X=600,Y=0,Z=150}}
        local x=t.Translation.X
        assert(h.spot:clear(h.world,t)==false and t.Translation.X==x)
    end
    unchanged({at={X=400,Y=0,Z=150},normal={X=-0.5,Y=0,Z=0.8}})
    unchanged(nil)
    unchanged({at={X=700,Y=0,Z=150},normal={X=-1,Y=0,Z=0}})
    unchanged({at={X=400,Y=0,Z=150},normal={X=-1,Y=0,Z=0},bone='spine_01'})
    unchanged({inside=true})
    assert(h.all():find('查墙的起点在实体里，这个出生点不改 位置=600,0,150',1,true),h.all())
    unchanged({at={X=50,Y=0,Z=150},normal={X=-1,Y=0,Z=0}},{X=80,Y=0,Z=150})
    assert(not h.spot:clear(h.world,nil) and not h.spot:clear(h.world,{}))
end
-- A wall right in front of the middle: not closer than half the way, and never through it.
do
    local h=harness()
    h.spot:origin({X=0,Y=0,Z=100},{X=1,Y=0,Z=0},'blue',h.world)
    h.hit=function()return {at={X=150,Y=0,Z=150},normal={X=-1,Y=0,Z=0}} end
    local t={Translation={X=600,Y=0,Z=150}}
    assert(h.spot:clear(h.world,t))
    assert(near(t.Translation.X,75),t.Translation.X)
end
print('spawn_spot: PASS')
