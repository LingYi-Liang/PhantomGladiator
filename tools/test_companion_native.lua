package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local P=require('companion_profile')
local counter=0
local function object(name,outer)
    counter=counter+1;local a={key=counter,name=name,parent=outer}
    function a:IsValid()return not self.invalid end
    function a:GetAddress()return self.key end
    function a:GetFullName()return self.name end
    function a:GetOuter()return self.parent end
    function a:GetClass()return self.cls end
    return a
end
local world=object('map');local npc=object('Class /Script/ProjectPBZ.PBZCharacter_NPC')
local function actor(name,phase,hp,max)
    local a=object(name,world);a.cls=object('BlueprintGeneratedClass '..(phase==1 and P.first or P.second))
    function a.cls:GetSuperStruct()return npc end
    a.stats={Health_Max=max,Health=hp,Shachi_Max=max/2,Shachi=max/8}
    a.pos={X=10,Y=20,Z=40};a.face={X=0,Y=0,Z=.6,W=.8}
    function a:GetTransform()return {Rotation=self.face}end
    a.ai=object('ai',a);a.ai.bAIStarted=true;a.ai.CurrentStateTag={TagName='AI.State.Idle'}
    local hm=object('hatred',a);hm.HatredList={};hm.BeHatredList={};hm.CanBeHatredNow=true
    function hm:GetOwner()return a end
    a.BP_PBZHatredManagerComponent=hm
    a['Faction Component']=object('faction',a);a['Faction Component'].GetFactionRelation=function()return 2 end
    a.ai.ForceIntoCombat=function(_,target)a.aim=target;table.insert(hm.HatredList,target)end
    a.Controller=object('ctrl',a);a.Controller.Pawn=a;a.Controller.BrainComponent=object('brain',a.Controller)
    local brain=a.Controller.BrainComponent;brain.AIOwner=a.Controller
    function brain:IsPaused()return self.paused==true end
    function brain:IsRunning()return true end
    return a
end
local library=object('library')
function library:PauseLogic(brain)brain.paused=true end
function library:ResumeLogic(brain)brain.paused=false end
function StaticFindObject()return library end
local attrs={};function attrs:read(a,f)return {current=a.stats[f],base=a.stats[f]}end
function attrs:writeBase(a,f,v)a.stats[f]=v;return true end
function attrs:nativeValue(a,f)return a.stats[f]end
package.loaded.character_stats={new=function()return attrs end,close=function(a,b)return math.abs(a-b)<.0001 end}
local player,old,new,enemy=actor('player',1,100,100),actor('first',1,30,100),actor('second',2,300,300),actor('enemy',1,100,100)
local known=true;local now=0;local shut=false
local n=require('companion_native').new({path='runtime',read=function()end,write=function()return true end,world=function()return world end,player=function()return player end,
    now=function()return now end,session=function()return 'testmap',true end,location=function(a)return a.pos end,
    ai=function(a)return a.ai end,hp=function(a)return a.stats.Health end,maxHP=function(a)return a.stats.Health_Max end,
    tagName=function(s)return s end,destroying=function()return false end,blocked=function()return shut end,actionBusy=function()return false end,
    aimedAt=function(a,b)return a.aim==b end,target=function(a)return a.target,known end,canHeal=function()return true end})
local members={{team='companion',actor=old,class_path=P.first,dual=true}}
n.manager:tick(members);local r=n.manager:lookup(old)
local t=assert(n.transfer(r,world,'manual',{combat=false}));assert(n.restore(r,new,t,'manual',world));assert(new.stats.Health==90 and new.stats.Shachi==37.5)
old.target=enemy;assert(not n.restore(r,new,t,'quiet',world))
t=assert(n.transfer(r,world,'combat',{combat=true}));assert(n.restore(r,new,t,'combat',world));assert(new.BP_PBZHatredManagerComponent.HatredList[1]==enemy)
new.face={X=0,Y=0,Z=0,W=1};assert(not n.restore(r,new,t,'combat',world));new.face=old.face
assert(n.commitReady(r,new,t,world));old.stats.Health=29;assert(not n.commitReady(r,new,t,world));assert(not n.restore(r,new,t,'combat',world))
shut=true;assert(not n.transfer(r,world,'manual',{combat=true}));shut=false
known=false;assert(not n.transfer(r,world,'manual',{combat=true}));known=true
old.target=nil;old.stats.Health=100
local function save(mode,targetable)
    local p=P.copy(r.p);p.policy='manual';p.behavior=mode;p.targetable=targetable
    assert(n.manager:command(r.id..'|'..r.rev..'|save|'..P.encode(p)).ok);now=now+1;n.manager:tick(members)
end
save('peace',0);assert(old.Controller.BrainComponent.paused and not old.BP_PBZHatredManagerComponent.CanBeHatredNow)
assert(player.BP_PBZHatredManagerComponent.CanBeHatredNow and not player.Controller.BrainComponent:IsPaused())
save('assist',1);assert(old.Controller.BrainComponent.paused and old.BP_PBZHatredManagerComponent.CanBeHatredNow)
player.BP_PBZHatredManagerComponent.BeHatredList={enemy};now=now+1;n.manager:tick(members);assert(not old.Controller.BrainComponent:IsPaused())
player.BP_PBZHatredManagerComponent.BeHatredList={}
local mapEnemy=actor('map enemy',1,100,100);mapEnemy.aim=player
local blue=actor('blue',1,100,100);blue.aim=player
members[#members+1]={team='blue',actor=blue,class_path=P.second}
members[#members+1]={team='neutral',actor=enemy,class_path=P.first};enemy.aim=player
save('active',2);assert(enemy.aim==old and blue.aim==player and mapEnemy.aim==player)
-- Count iteration of a reflected hatred array when only its size is used.
local visits=0
local dense={type=function()return 'TArray'end,GetArrayNum=function()return 240 end,
    ForEach=function(_,fn)for i=1,240 do visits=visits+1;fn(i,enemy) end end}
old.BP_PBZHatredManagerComponent.HatredList=dense
save('active',1)
print('MEASURE 240 hatred entries: array element callbacks='..visits)
local countPass=visits==0
old.BP_PBZHatredManagerComponent.HatredList={}
save('active',1)
assert(n.manager:command(r.id..'|'..r.rev..'|wait|').ok and old.Controller.BrainComponent:IsPaused())
known=false;local follow=n.manager:command(r.id..'|'..r.rev..'|follow|')
print('MEASURE resume from hold with unreadable target='..tostring(follow.ok))
local followPass=follow.ok and not r.waiting and not old.Controller.BrainComponent:IsPaused()
known=true;save('peace',0)
known=false;save('active',1)
local released=not old.Controller.BrainComponent:IsPaused() and old.BP_PBZHatredManagerComponent.CanBeHatredNow
print('MEASURE active with unreadable target after peace: own pause and aggro flag released='..tostring(released))
known=true;save('peace',0)
local replacement=actor('replacement owner',1,100,100).Controller
replacement.Pawn=old;old.Controller=replacement;now=now+1;n.manager:tick(members)
local reclaimed=replacement.BrainComponent:IsPaused() and r.lease==replacement.BrainComponent
print('MEASURE peaceful companion reacquired replaced controller='..tostring(reclaimed))
n.manager:silence(true)
assert(countPass and released and reclaimed and followPass)
assert(not old.Controller.BrainComponent:IsPaused() and old.BP_PBZHatredManagerComponent.CanBeHatredNow)
print('PASS native adapter with controlled objects: resources, rotation, target, re-entry, death guards and AI leases')