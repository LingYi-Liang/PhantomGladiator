package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local U=require('ue_observe')
local f=assert(io.open(arg[1] or 'Mods/PhantomGladiator/Scripts/main.lua','r'));local source=f:read('*a');f:close()
local first=assert(source:find('local senseHold=',1,true));local last=assert(source:find('local function ForceAttack',first,true))
local serial=0
local function object()
    serial=serial+1;local id=1000+serial
    return {valid=true,IsValid=function(s)return s.valid end,GetAddress=function()return id end}
end
local function actor(id)
    return {valid=true,IsValid=function(s)return s.valid end,GetAddress=function()return id end}
end
local function fixture()
    local h={player=actor(1),target=actor(2),other=actor(3),values={},writes=0,logs={}}
    h.bb=object()
    function h.bb:GetValueAsObject(key)if h.failRead==key or h.failAfter and h.writes>0 then error('read failed')end;return h.values[key]end
    function h.bb:SetValueAsObject(key,value)h.writes=h.writes+1;if not h.deny then h.values[key]=value end end
    function h.bb:ClearValue(key)h.writes=h.writes+1;h.values[key]=nil end
    h.handler=object();h.handler.Blackboard=h.bb;h.handler.LastSensedActorKey='fallback';h.handler['Target Key']='main'
    local targeting=object();targeting.DefaultTargetHandler=h.handler
    h.actor=actor(4);h.actor['Targeting Component']=targeting
    local env=setmetatable({UEObserve=U,safeValid=U.valid,GetPlayerPawn=function()return h.player end,
        objectName=function(v)return tostring(U.key(v))end,log=function(line)h.logs[#h.logs+1]=line end},{__index=_G})
    h.hold=assert(load(source:sub(first,last-1)..'\nreturn HoldSensedTarget','production target fallback','t',env))()
    return h
end
local h=fixture();assert(h.hold(h.actor,h.target,'fixture'));assert(h.values.fallback==h.target,'missing fallback and primary must recover the opponent')
assert(h.writes==1 and h.logs[1]:find('读回=true',1,true))
h=fixture();h.values.main=h.other;assert(h.hold(h.actor,h.target));assert(h.writes==0,'a valid primary must be retained')
h=fixture();h.values.fallback=h.other;assert(h.hold(h.actor,h.target));assert(h.writes==0,'a valid native fallback must be retained')
h=fixture();h.values.fallback=h.player;assert(h.hold(h.actor,h.target));assert(h.values.fallback==h.target)
h=fixture();h.values.fallback=h.player;assert(h.hold(h.actor,nil));assert(h.values.fallback==nil)
h=fixture();h.failRead='main';assert(not h.hold(h.actor,h.target));assert(h.writes==0,'unknown primary cannot be treated as empty')
h=fixture();h.failRead='fallback';assert(not h.hold(h.actor,h.target));assert(h.writes==0)
h=fixture();h.failAfter=true;assert(not h.hold(h.actor,h.target),'failed verification cannot count as a successful clear/write')
h=fixture();h.deny=true;assert(not h.hold(h.actor,h.target))
h=fixture();h.bb.valid=false;assert(not h.hold(h.actor,h.target));assert(h.writes==0)
local body=assert(source:match('inCombat=function%(actor%)(.-)end,%s*%-%- Sends a unit'))
for _,tag in ipairs({'AI.State.Combat','AI.State.Combat.Attack','AI.State.OffCombat','AI.State.NonCombat','AI.State.Search','AI.State.CombatPreparing'})do
    local env={GetAIComp=function()return {CurrentStateTag={TagName=tag}}end,FNameToString=function(v)return v end,pcall=pcall,type=type}
    local fn=assert(load('return function(actor)'..body..'end','production state check','t',env))()
    local expected=tag=='AI.State.Combat' or tag=='AI.State.Combat.Attack'
    assert(fn({})==expected,'incorrect combat classification: '..tag)
end
print('main_target_recovery: PASS (production fallback, readback failures, native targets and exact combat states)')
