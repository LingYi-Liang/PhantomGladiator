-- Paused selfie orbit. Angles are relative to the initial composition.
local Lens={}
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<1e8 end
local function clamp(v,lo,hi)return math.min(hi,math.max(lo,v))end
local function value(v)return finite(v) and v or 0 end
function Lens.new(focus,location)
    local x,y,z=location.X-focus.X,location.Y-focus.Y,location.Z-focus.Z
    local distance=math.sqrt(x*x+y*y+z*z)
    return {focus=focus,originYaw=math.atan(y,x),yaw=0,pitch=math.atan(z,math.sqrt(x*x+y*y)),distance=distance,
        min=math.max(125,distance*.52),max=math.min(2200,math.max(850,distance*1.9))}
end
function Lens.step(lens,input,dt)
    if type(input)~='table' or not finite(dt) then return end
    dt=clamp(dt,0,.1)
    local mouseX=clamp(value(input.mx),-50,50)
    local mouseY=clamp(value(input.my),-50,50)
    local turn=clamp(value(input.turn),20,300)*.008
    local yaw=clamp(lens.yaw+math.rad(mouseX*turn+value(input.right)*52*dt),math.rad(-64),math.rad(64))
    local pitch=clamp(lens.pitch+math.rad(mouseY*turn+(value(input.up)+value(input.lookUp))*42*dt),math.rad(-22),math.rad(35))
    local change=clamp(value(input.wheel),-3,3)*.10+value(input.forward)*dt
    local distance=clamp(lens.distance*math.exp(-change),lens.min,lens.max)
    if yaw==lens.yaw and pitch==lens.pitch and distance==lens.distance then return end
    local xy=math.cos(pitch)*distance
    local a=lens.originYaw+yaw
    local location={X=lens.focus.X+math.cos(a)*xy,Y=lens.focus.Y+math.sin(a)*xy,Z=lens.focus.Z+math.sin(pitch)*distance}
    return location,{Yaw=math.deg(a+math.pi)%360,Pitch=math.deg(-pitch),Roll=0},yaw,pitch,distance
end
function Lens.free(position,rotation,input,dt)
    if type(input)~='table' or not finite(dt) then return end
    dt=clamp(dt,0,.1)
    local turn=clamp(value(input.turn),20,300)*.009
    local swing=clamp(value(input.mx),-50,50)*turn+value(input.lookRight)*65*dt
    local rise=clamp(value(input.my),-50,50)*turn+value(input.lookUp)*65*dt
    local f,pn,h=value(input.forward),value(input.pan),value(input.up)
    if swing==0 and rise==0 and f==0 and pn==0 and h==0 then return end
    local yaw=(rotation.Yaw+swing)%360
    local pitch=clamp(rotation.Pitch+rise,-85,85)
    local y,p=math.rad(yaw),math.rad(pitch)
    local scale=clamp(value(input.speed)*.6,100,1350)*dt/math.max(1,math.sqrt(f*f+pn*pn+h*h))
    local out={
        X=position.X+(f*math.cos(p)*math.cos(y)-pn*math.sin(y))*scale,
        Y=position.Y+(f*math.cos(p)*math.sin(y)+pn*math.cos(y))*scale,
        Z=position.Z+(f*math.sin(p)+h)*scale,
    }
    return out,{Yaw=yaw,Pitch=pitch,Roll=rotation.Roll}
end
return Lens
