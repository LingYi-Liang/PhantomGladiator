package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local U=require('ue_observe')
local f=assert(io.open(arg[1] or 'Mods/PhantomGladiator/Scripts/main.lua','r'));local text=f:read('*a');f:close()
local first=assert(text:find('local senseHold=',1,true));local last=assert(text:find('-- 不再调用通用ApplyDamage',first,true))
local function object(id)return {IsValid=function()return true end,GetAddress=function()return id end}end
local actor,target,bb,handler,ai,component=object(1),object(2),object(3),object(4),object(5),object(6)
handler.Blackboard=bb;handler['Target Key']='target';component.DefaultTargetHandler=handler;actor['Targeting Component']=component
ai.BlackboardComponent=bb;ai.CurrentStateTag={TagName='AI.State.Combat'}
ai.ForceIntoCombat=function()end
local current,deny,scans=nil,false,0
bb.GetValueAsObject=function()return current end;bb.SetValueAsObject=function(_,key,value)if not deny then current=value end end;bb.ClearValue=function()current=nil end
local env=setmetatable({arenaSupport={},UEObserve=U,safeValid=U.valid,engineValid=U.valid,checked=function(v)assert(U.valid(v))end,
    SetFactionRelation=function()return true end,AddHatred=function()return true,'verified'end,GetAIComp=function()return ai end,
    FindAllOf=function(name)assert(name=='PBZ_TargetingHandler_AI_C');scans=scans+1;return {handler}end,
    FNameToString=tostring,objectName=function(v)return tostring(U.key(v))end,log=function()end,HOSTILE=2,
    battle={remember=function()end}},{__index=_G})
local send=assert(load(text:sub(first,last-1)..'\nreturn ForceAttack','production target assignment','t',env))()
for _=1,100 do assert(send(actor,target))end
print('100 production target assignments: global scans='..scans)
assert(scans==0,'a bound private target handler should not require a global scan')
deny=true;current=nil;assert(not send(actor,target),'a denied target write cannot be reported as confirmed');assert(scans==0)
deny=false;component.DefaultTargetHandler=nil;assert(send(actor,target) and scans==1,'missing private handler keeps validated fallback')
ai.BlackboardComponent=nil;ai.CurrentStateTag={TagName='AI.State.Idle'}
assert(not send(actor,target),'an idle unit with no target binding cannot confirm an assignment')
ai.CurrentStateTag={TagName='AI.State.Combat'}
assert(send(actor,target),'a unit without a target handler can still acknowledge through native combat')
print('target_binding: PASS (global scans 100 -> 0; failed write readback and fallback)')
