package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Probe=require('execution_pose_probe')
local clock,lines=0,{}
local function obj(label,fields)
    fields=fields or {}
    fields.IsValid=function()return true end
    fields.GetFName=function()return {ToString=function()return label end}end
    return fields
end
local function v(x,y,z)return {X=x,Y=y,Z=z}end
local anim=obj('Anim',{RootMotionMode=0,GetCurrentActiveMontage=function()return nil end})
local clip=obj('Clip',{bEnableRootMotion=true,bForceRootLock=false})
local rig=obj('Borrowed',{AnimationMode=1,AnimationData={AnimToPlay=clip},
    GetBoneIndex=function(_,n)return n=='root' and 0 or 1 end,
    K2_GetComponentLocation=function()return v(10,20,30)end,
    K2_GetComponentScale=function()return v(1,1,1)end,
    GetSocketLocation=function(_,n)return n=='root' and v(110,20,30) or v(110,20,130)end,
    GetSocketRotation=function()return {Yaw=40}end,
    GetAnimInstance=function()return anim end,
    GetPosition=function()return 0.35 end})
local actor=obj('Executor',{Mesh=rig,K2_GetActorLocation=function()return v(10,20,126)end,
    K2_GetActorRotation=function()return {Yaw=90}end,GetVelocity=function()return v(0,0,0)end})
local badCalls=0
-- type() is UE4SS wrapper metadata, not a native UObject/property access.
local invalid=setmetatable({IsValid=function()return false end,type=function()return 'UObject'end},
    {__index=function()badCalls=badCalls+1;error('invalid access')end})
local options={log=function(s)lines[#lines+1]=s end,now=function()return clock end,
    fname=function(s)return s end,staticFind=function()return nil end}
local p=Probe.new(options)
p:begin(actor,invalid,rig)
local s=lines[#lines]
assert(s:find('event=begin',1,true) and s:find('root-mesh=100.0,0.0,0.0',1,true),s)
assert(s:find('target[actor=invalid]',1,true) and s:find('clip=Clip@0.350',1,true),s)
assert(s:find('rootMotion=0',1,true) and s:find('forceLock=false',1,true),s)
-- Every UObject level is checked, including a valid actor with an expired mesh or animation instance.
actor.Mesh=invalid
p:sample('expired-mesh')
assert(lines[#lines]:find('mesh=invalid',1,true),lines[#lines])
actor.Mesh=rig
rig.GetAnimInstance=function()return invalid end
p:sample('expired-anim')
assert(badCalls==0,'must not dereference any level of an expired UObject')
assert(anim.RootMotionMode==0 and clip.bEnableRootMotion and not clip.bForceRootLock,'sampling must not change animation settings')
p:stop('done')
local n=#lines
p:sample('outside-run')
assert(#lines==n,'no actor reads outside an execution')
-- Bounded per run and across this Lua lifetime, with no timer or hook to leak on stop/reload.
p:begin(actor,invalid,rig)
for i=1,100 do clock=i/2;p:sample('tick')end
local count=0
for _,line in ipairs(lines)do if line:find('run=2 sample=',1,true)then count=count+1 end end
assert(count==80,'sample budget must stop at 80')
p:stop('limit');p:begin(actor,invalid,rig);p:stop('third')
n=#lines;p:begin(actor,invalid,rig);p:sample('fourth')
assert(#lines==n,'no more than three executions per load')
assert(badCalls==0)
print('execution_pose_probe ok: values, nested validity, read-only settings, stop, sample/run bounds')
