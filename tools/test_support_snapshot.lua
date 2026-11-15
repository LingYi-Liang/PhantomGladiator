package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local U=require('ue_observe')
local f=assert(io.open(arg[1] or 'Mods/PhantomGladiator/Scripts/main.lua','r'));local text=f:read('*a');f:close()
local function section(a,b)local first=assert(text:find(a,1,true));return text:sub(first,assert(text:find(b,first,true))-1)end
local function obj(id)return {IsValid=function()return true end,GetAddress=function()return id end}end
local pawns,attributes,reads={},{},{attributes=0,camera=0}
for i=1,100 do
    local actor=obj(i);actor.AbilitySystemComponent=obj(1000+i);pawns[i]=actor
    local attribute=obj(2000+i);attribute.Health={CurrentValue=100+i};attribute.GetOuter=function()return actor end;attributes[i]=attribute
end
local camera=obj(3001);camera.Player=obj(3002)
local env=setmetatable({arenaSupport={frameContext={}},UEObserve=U,safeValid=U.valid,
    FindAllOf=function(name)
        if name=='BasicAttributeSet' then reads.attributes=reads.attributes+1;return attributes end
        assert(name=='DebugCameraController');reads.camera=reads.camera+1;return {camera}
    end},{__index=_G})
local chunk=section('local function GetHP(','local function StartDuelWatch')..section('local function FindActiveDebugCam()','local observerGuard=')
local getHP,getCamera=assert(load(chunk..'\nreturn GetHP,FindActiveDebugCam','production support getters','t',env))()
for i=1,100 do assert(getHP(pawns[i])==100+i)end
print('100 fallback health reads: global attribute scans='..reads.attributes)
assert(reads.attributes==1,'one support tick shares the attribute set list, not health values')
attributes[1].Health.CurrentValue=55;assert(getHP(pawns[1])==55,'health itself remains live')
for _=1,100 do assert((env.arenaSupport.debugCameraForSupport and env.arenaSupport:debugCameraForSupport() or getCamera())==camera)end
assert(reads.camera==1,'the camera snapshot is scoped to a support tick')
env.arenaSupport.frameContext={};assert(getHP(pawns[1])==55);assert(env.arenaSupport:debugCameraForSupport()==camera)
assert(reads.attributes==2 and reads.camera==2,'a new support tick must refresh native objects')
env.arenaSupport.frameContext=nil;assert(getHP(pawns[1])==55);assert(getHP(pawns[1])==55);assert(reads.attributes==4)
env.arena={members=function()error('fixture failure')end,status=function()return {}end}
env.supportSteps=function()error('unexpected steps')end
assert(load(section('function arenaSupport:tick()','function arenaSupport:status()'),'production support cleanup','t',env))()
assert(not pcall(env.arenaSupport.tick,env.arenaSupport));assert(env.arenaSupport.frameContext==nil,'an exception before supportSteps must release the frame snapshot')
print('support_snapshot: PASS (100 health/camera scans -> 1 each; live HP, next-tick refresh and failure cleanup)')
