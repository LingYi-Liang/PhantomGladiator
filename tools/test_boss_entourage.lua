package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local M=require('boss_entourage')
local id=0
local function obj(name,outer)
    id=id+1;local n=id
    return {hp=100,IsValid=function()return true end,GetAddress=function()return n end,
        GetFullName=function()return name end,GetOuter=function()return outer end}
end
local world=obj('world')
local hooks={};local adopts=0;local now=10
local ai=obj('SGameAIFunctionLibrary')
function ai:GetPendingSummonCount(a)return a.pending end
local m=M.new({world=function()return world end,hp=function(a)return a.hp end,now=function()return now end,
    find=function(path)return path=='/Script/SGameAI.Default__SGameAIFunctionLibrary' and ai or world end,
    log=function()end,register=function(path,pre,post)hooks[path]={pre,post};return 1,2 end,
    unregister=function(path)hooks[path]=nil end,adopt=function()adopts=adopts+1 end})
local function rec(id,group,on)
    local path='/Game/'..id..'.'..id..'_C'
    return {actor=obj(id,world),team='blue',class_path=path,formation=on,formationGroup=group}
end
local g,h={},{}
local l=rec('BP_Monster_HuaShan_Blue',g,true);local s=rec('Soldier',g)
local other=rec('BP_Monster_HuaShan_Blue',h,true);local otherSoldier=rec('Soldier',h)
local dead=rec('Soldier',g);dead.actor.hp=0
local x=rec(M.xiao,{},true);local b=rec('BP_Monster_CanQu_BiHai',{},true)
m:roster({l,s,other,otherSoldier,dead,x,b})
local function callback(endName)
    for k,v in pairs(hooks)do if k:sub(-#endName)==endName then return v[1] end end
end
local task=obj('private task',world);task.TreeAsset=obj('BehaviorTree /PBZCombatAsset/ActorData/Mobs/035_HuaShan/BehaviorTree/Troop/Test.Test')
task.ControlledPawn=l.actor;callback('ExecuteInternal')(task)
assert(#task.ActorsToAssign==1 and task.ActorsToAssign[1]==s.actor)
g.nativeFormation=true
local nativeList={s.actor,dead.actor};task.ActorsToAssign=nativeList
callback('ExecuteInternal')(task)
assert(task.ActorsToAssign==nativeList and nativeList[2]==dead.actor,'the native revival task keeps its downed candidate')
g.nativeFormation=nil
local function passive(parent,name,n)
    local a=obj('inst',world);a.class=obj(name)
    function a:GetClass()return self.class end
    function a.class:GetFName()return {ToString=function()return name end} end
    function a:GetAvatarActorFromActorInfo()return parent.actor end
    a.MaxSummonCount=n;a.SpawnedSummonInstances={};a.calls=0
    function a:OnReceivedSpawnSummonsEvent(payload)assert(payload.EventMagnitude==4);self.calls=self.calls+1 end
    return a
end
local a=passive(x,'GA_SummonPassive_XiaoXue_C',4)
m:passive(a);m:passive(a);assert(a.calls==1)
local child=obj('minion',world)
local native=obj('Class /Script/ProjectPBZ.PBZCharacter_NPC')
local cls=obj('BlueprintGeneratedClass /Game/Minion.Minion_C')
function cls:GetSuperStruct()return native end
function child:GetClass()return cls end
local finish
for path,pair in pairs(hooks)do if path:match(':OnSpawnFinish$')then finish=pair[2] end end
assert(finish);finish(a,child);assert(adopts==1)
local phase=passive(b,'GA_CanQu_BiHai_SummonPassive_01_C',3)
phase.DestroySummonsOnDead=true;phase.DestroySummonsOnEndAbility=true;phase.bDestroySummonsOnDeadLatched=true
m:passive(phase);assert(phase.calls==0 and not phase.bDestroySummonsOnDeadLatched and not phase.DestroySummonsOnEndAbility)
local solo=rec(M.xiao,nil,false);m:roster({solo,b});local off=passive(solo,'GA_SummonPassive_XiaoXue_C',4)
callback('OnReceivedSpawnSummonsEvent')(off);assert(off.MaxSummonCount==0 and off.calls==0)
local foreign=passive(l,'GA_SummonPassive_XiaoXue_C',4);m:passive(foreign);assert(foreign.MaxSummonCount==4 and foreign.calls==0)
local retry=rec(M.xiao,{},true);m:roster({retry,solo,b});local delayed=passive(retry,'GA_SummonPassive_XiaoXue_C',4)
delayed.bIsActive=true
function delayed:OnReceivedSpawnSummonsEvent(payload)
    assert(payload.EventMagnitude==4)
    self.calls=self.calls+1
    if self.calls==1 then error('native dispatch unavailable') end
end
m:passive(delayed);assert(delayed.calls==1)
now=12;delayed.pending=1;m:passive(delayed);assert(delayed.calls==1,'never resend over an active native reservation')
now=14;delayed.pending=nil;m:passive(delayed);assert(delayed.calls==1,'unknown reservations are not an empty slot')
now=16;delayed.pending=0;m:passive(delayed);assert(delayed.calls==2,'retry failed native dispatch with confirmed empty reservations')
now=30;m:passive(delayed);assert(delayed.calls==2,'no repeated requests when the summon continues to fail')
local wait=rec(M.xiao,{},true);m:roster({wait,solo,b});local queued=passive(wait,'GA_SummonPassive_XiaoXue_C',4)
queued.bIsActive=true;queued.pending=1;queued.SpawnedSummonInstances={{bPawnPending=true}}
m:passive(queued);assert(queued.calls==0)
now=32;queued.pending=0;queued.SpawnedSummonInstances={}
m:passive(queued);assert(queued.calls==1,'a pending row that vanished without completion is not a permanent spawn receipt')
finish(queued,child)
now=34;m:passive(queued);assert(queued.calls==1,'a confirmed birth prevents replenishing the original group')
m:silence(true);assert(not next(hooks) and off.MaxSummonCount==4 and phase.DestroySummonsOnDead and phase.bDestroySummonsOnDeadLatched)
print('PASS scoped formations, native and formation cards, native caps, phase timing, no repeated summons, owner isolation and cleanup')
