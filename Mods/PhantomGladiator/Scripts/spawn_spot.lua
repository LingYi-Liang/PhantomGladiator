-- Where a batch of summons goes.
-- Outside the free camera: ahead of the player's body, as it always was. In the free camera the body stands hidden where it
-- was left and summons came out around it, whatever the camera looked at, into whatever stood next to the body. Now the batch
-- comes out where the view points: its first row on the spot the view hits (or some way ahead when it hits nothing), on the
-- ground there, turned the way the view looks. Companions still start by the body, which they follow.
-- Either way a spot with a wall between it and the middle of the batch is pulled back to this side of the wall.
local Spot={}
local AIM_RANGE=8000    -- cm the view looks for something to stand on
local AIM_EMPTY=1500    -- cm ahead of the camera when it hits nothing
local AIM_BACK=100      -- cm from what the view hit, back toward the camera
local FIRST_ROW=600     -- cm: arena_controller's first row of blue, red and no-team units, ahead of the origin
local BODY=100          -- cm from the feet to the height a batch is worked out at, about a capsule's middle
local WALL_Z=50         -- cm over that height a wall is looked for
local WALL_GAP=120      -- cm kept from a wall
local MIN_REACH=100     -- cm: a spot this close to the middle is not checked, nor pulled closer than this
local CLEAR_START=60    -- cm from the middle the line starts, past the capsule of a body standing there
local SLOPE=0.5         -- a surface whose normal has this much Z can be walked on: a hillside, not a wall
local LINES=40

local function text(v)return v and string.format('%.0f,%.0f,%.0f',v.X,v.Y,v.Z) or '?' end

function Spot.new(options)
    local log=options.log or function()end
    local self={}
    local center,lastBody
    local lines=0
    local function say(line)
        if lines<LINES then lines=lines+1;log('[SpawnSpot] '..line) end
    end
    -- The spot the view points at, or nil with no ground under it.
    local function aim(world,position,rotation)
        local yaw,pitch=math.rad(rotation.Yaw),math.rad(rotation.Pitch)
        local dir={X=math.cos(pitch)*math.cos(yaw),Y=math.cos(pitch)*math.sin(yaw),Z=math.sin(pitch)}
        local hit=options.trace(world,position,{X=position.X+dir.X*AIM_RANGE,Y=position.Y+dir.Y*AIM_RANGE,Z=position.Z+dir.Z*AIM_RANGE})
        local spot,how
        if hit and hit.at and not hit.inside then
            spot,how={X=hit.at.X-dir.X*AIM_BACK,Y=hit.at.Y-dir.Y*AIM_BACK,Z=hit.at.Z},'镜头看向的地方'
        else
            spot,how={X=position.X+dir.X*AIM_EMPTY,Y=position.Y+dir.Y*AIM_EMPTY,Z=position.Z+dir.Z*AIM_EMPTY},'镜头前方'
        end
        local ground=options.ground(world,spot.X,spot.Y,spot.Z+BODY,0) or options.ground(world,spot.X,spot.Y,spot.Z)
        if type(ground)~='number' then return nil,how end
        local flat={X=math.cos(yaw),Y=math.sin(yaw),Z=0}
        local middle={X=spot.X,Y=spot.Y,Z=ground+BODY}
        return {middle=middle,forward=flat,origin={X=middle.X-flat.X*FIRST_ROW,Y=middle.Y-flat.Y*FIRST_ROW,Z=middle.Z},how=how}
    end
    -- body and look: the player's. Returns where spawn_transform works from and which way it looks.
    function self:origin(body,look,team,world)
        center=body
        local moved=lastBody and math.sqrt((body.X-lastBody.X)^2+(body.Y-lastBody.Y)^2+(body.Z-lastBody.Z)^2) or nil
        lastBody=body
        local position,rotation
        if team~='companion' and options.view then position,rotation=options.view() end
        local aimed,how
        if position and rotation then aimed,how=aim(world,position,rotation) end
        if aimed then center=aimed.middle end
        say(string.format('召唤点 队伍=%s 来源=%s 中心=%s 玩家身体=%s 距上次召唤时身体=%s 镜头=%s',tostring(team),
            aimed and aimed.how or (position and tostring(how)..'下方没有地面，改用玩家' or '玩家'),text(center),text(body),
            moved and string.format('%.0fcm',moved) or '首次',position and text(position) or '不在自由观战'))
        if aimed then return aimed.origin,aimed.forward end
        return body,look
    end
    -- A spot behind a wall comes back to this side of it. Changes transform.Translation; true when it did.
    function self:clear(world,transform)
        local spot=transform and transform.Translation
        if type(spot)~='table' or not center or not options.trace then return false end
        local dx,dy=spot.X-center.X,spot.Y-center.Y
        local length=math.sqrt(dx*dx+dy*dy)
        if length<=MIN_REACH then return false end
        local z=center.Z+WALL_Z
        local hit=options.trace(world,{X=center.X+dx/length*CLEAR_START,Y=center.Y+dy/length*CLEAR_START,Z=z},{X=spot.X,Y=spot.Y,Z=z})
        if hit and hit.inside then say('查墙的起点在实体里，这个出生点不改 位置='..text(spot)) end
        if not hit or hit.inside or not hit.at or hit.bone then return false end
        if hit.normal and type(hit.normal.Z)=='number' and hit.normal.Z>=SLOPE then return false end
        local reach=math.sqrt((hit.at.X-center.X)^2+(hit.at.Y-center.Y)^2)
        if reach>=length then return false end
        local keep=math.max(reach-WALL_GAP,math.min(MIN_REACH,reach*0.5))
        local before=text(spot)
        spot.X,spot.Y=center.X+dx/length*keep,center.Y+dy/length*keep
        say(string.format('出生点被墙挡住 原=%s 墙在中心外 %.0fcm 改到=%s（离中心 %.0fcm）',before,reach,text(spot),keep))
        return true
    end
    -- The middle of the batch being summoned: what a spot over a drop moves toward (on_ground.lua).
    function self:anchor()return center end
    return self
end
return Spot
