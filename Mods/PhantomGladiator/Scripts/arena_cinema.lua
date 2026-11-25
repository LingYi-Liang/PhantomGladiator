-- Slow, context-sensitive framing for observation. All input is already sampled by the tracker.
local Cinema={}
Cinema.MIN_SHOT=6.5
Cinema.WIDE_INTERVAL=38
local SAMPLE=0.25
local RECHECK=1.25

local function clamp(v,lo,hi)return math.max(lo,math.min(hi,v))end
local function movement(a,b)
    local x,y=a.X-b.X,a.Y-b.Y
    return math.sqrt(x*x+y*y)
end

function Cinema.new()
    return {time=0,shot=nil,started=0,recheck=0,wideAt=-math.huge,nextSample=0}
end

local function sample(d,frame)
    if d.time<d.nextSample then return end
    local interval=math.max(SAMPLE,d.time-(d.sampleAt or d.time))
    local moving=0
    if d.a and frame.target==d.target then moving=movement(frame.a,d.a)/interval end
    if d.b and frame.b and frame.other==d.other then moving=math.max(moving,movement(frame.b,d.b)/interval) end
    d.speed=moving
    d.a,d.b,d.target,d.other=frame.a,frame.b,frame.target,frame.other
    d.sampleAt,d.nextSample=d.time,d.time+SAMPLE
    d.activity=frame.activity
end

local function choose(d,b,gap)
    if d.activity=='phase' or d.activity=='execution' then return 'action' end
    if not b then return 'side' end
    if gap>=1150 and gap<=3000
        and (not d.shot or (d.speed>=120 and d.time-d.wideAt>=Cinema.WIDE_INTERVAL)) then return 'aerial' end
    if gap<=620 and (d.speed>=190 or d.activity=='attack') then
        return d.shot=='low' and 'side' or 'low'
    end
    if gap>=400 and gap<=1300 and d.speed>=95 and d.shot~='shoulder' then return 'shoulder' end
    return 'side'
end

-- Positive pitch places the camera low. Look and distance remain relative to character size.
function Cinema.frame(d,dt,f)
    d.time=d.time+dt
    sample(d,f)
    local gap=f.gap
    if not d.shot or (not f.manual and d.time>=d.recheck and d.time-d.started>=Cinema.MIN_SHOT) then
        local chosen=choose(d,f.b,gap)
        d.recheck=d.time+RECHECK
        if chosen~=d.shot then
            d.shot,d.started=chosen,d.time
            if chosen=='aerial' then d.wideAt=d.time end
        end
    end
    local age=d.time-d.started
    local radius=math.max(f.radius,f.otherRadius or 0)
    local half=math.max(f.half,f.otherHalf or 0)
    local side='side'
    local lens,pull,raise,dist,pitch
    local sway=0
    if d.shot=='shoulder' then
        side='shoulder';lens,pull,raise,dist,pitch=74,.24,f.half*.38,math.max(420,gap*.40+250),-9
    elseif d.shot=='low' then
        lens,pull,raise,dist,pitch=82,.40,-half*.14,math.max(500,gap*.68+250),5
    elseif d.shot=='aerial' and f.b then
        local push=clamp(age/4,0,1)
        push=push*push*(3-2*push)
        lens,pull,raise,dist,pitch=60-10*push,.49,half*.15,math.max(1750,gap*.80+520)-280*push,-32+5*push
        sway=math.sin(age*.85)*.85
    elseif d.shot=='action' then
        lens,pull,raise,dist,pitch=70,.35,half*.30,math.max(590,gap*.66+280),-10
    else
        lens,pull,raise,dist,pitch=78,.44,half*.24,math.max(590,gap*.62+270),-13
    end
    local fit=half*1.38/(math.tan(math.rad(lens/2))*.5625)
    dist=clamp(math.max(dist,fit+radius*.8),360,d.shot=='aerial' and 3600 or 2500)
    return {name=d.shot,side=side,fov=lens,pull=pull,raise=raise,distance=dist,pitch=pitch,yawDrift=sway,
        focus=d.shot=='aerial' and f.b and clamp((age-.35)/1.45,0,1) or nil}
end
return Cinema