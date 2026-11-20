package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local C=require('arena_counter_windows')
local U=require('ue_observe')
local seq=0
local function obj(v)
    v=v or {};seq=seq+1;local id=seq
    v.IsValid=function(self)return not self.gone end;v.GetAddress=function()return id end
    return v
end
local world=obj();local function actor()
    local a=obj({hp=100,tags={},at={X=0,Y=0,Z=0},GetOuter=function()return world end})
    a.AbilitySystemComponent=obj({GetGameplayTagCount=function(_,t)return a.tags[t.TagName] or 0 end})
    a['Actor State Component']=obj({GetOwner=function()return a end,CanActivateNewState=function()return a.canAct==true end})
    return a
end
local blade,jade,foe,ally,player=actor(),actor(),actor(),actor(),actor()
local now=10;local m={{actor=blade,class_path=C.BLADE,team='red'},{actor=jade,class_path=C.JADE,team='red'},
    {actor=foe,team='blue'},{actor=ally,team='red'}}
local task=obj({CurrentTime=2.33});local grab=obj({bIsActive=true,GetPlayTimelineTask=function()return task end,
    GetAvatarActorFromActorInfo=function()return blade end,['Execution Info']={Executor=blade,Target=foe}})
local function cls(path)return obj({GetFullName=function()return 'LegoAbilityBlueprintGeneratedClass '..path end})end
local bc=cls(C.BLADE_GRAB);grab.GetClass=function()return bc end
local calls=0;local yd=0
local options={now=function()return now end,world=function()return world end,player=function()return player end,
    eligible=function()return true end,hp=function(a)return a.hp end,location=function(a)return a.at end,
    assigned=function(a)return a==foe and blade or foe end,fname=function(n)return n end,
    bladeCounter=function(a,b,t)assert(a==foe and b==blade and t==task.CurrentTime);calls=calls+1;return true end,
    log=function()end}
local c=C.new(options);c:sync(m,true)
blade.tags[C.JUDGE]=1
c:bladeTick(grab);assert(calls==0,'a grabbed actor unable to act cannot counter')
foe.canAct=true;foe.at.X=601;c:bladeTick(grab);assert(calls==0)
foe.at.X=600;blade.tags[C.JUDGE]=0;c:bladeTick(grab);assert(calls==0,'HP alone cannot open a window')
blade.tags[C.JUDGE]=1;grab['Execution Info'].Target=player;c:bladeTick(grab);assert(calls==0)
grab['Execution Info'].Target=nil;c:bladeTick(grab);assert(calls==0,'assigned target alone does not prove who is being grabbed')
grab['Execution Info'].Target=foe;c:bladeTick(grab);c:bladeTick(grab);assert(calls==1,'one native finisher per live window')
-- When the grabbed unit cannot act, only an in-range hostile combatant engaging this boss can help.
local rescue=actor();rescue.canAct=true;foe.canAct=false
local assigned=options.assigned;options.assigned=function(a)return a==rescue and jade or assigned(a)end
m[#m+1]={actor=rescue,team='blue'};c:sync(m,true)
blade.tags[C.JUDGE]=0;c:bladeTick(grab);blade.tags[C.JUDGE]=1
options.bladeCounter=function(a,b)assert(a==rescue and b==blade);calls=calls+1;return true end
c:bladeTick(grab);assert(calls==1)
options.assigned=function(a)return a==rescue and blade or assigned(a)end
c:bladeTick(grab);assert(calls==2)
local yc=cls(C.JADE_COUNTER)
local ja=obj({GetClass=function()return cls(C.JADE_GRAB)end})
local action=obj({GetAbility=function()return ja end,GetAvatarActor=function()return jade end,CounterAbility=yc,DeflectBulletType=3})
local data={SourceAction=action,SourceAvatar=jade,DefenderAvatar=foe,DeflectResult={TagName='Deflect.Result.Perfect'},HitGameTime=now,CounterAbility=yc}
local dc=obj({GetOwner=function()return foe end,PerfectDodgeResultData=data})
foe['Deflect Component']=dc;foe.tags[C.READY]=1
local asc=foe.AbilitySystemComponent;foe['Ability Input Component']=obj({AbilitySystem=asc})
asc.ActivatableAbilities={Items={{Ability=obj({GetClass=function()return yc end}),Handle={Handle=17},ActiveCount=0}}}
asc.TryActivateAbility=function(_,handle)assert(handle.Handle==17);yd=yd+1;return true end
data.HitGameTime=now-1;c:jadeResult(foe,jade);assert(yd==0)
data.HitGameTime=now;data.DeflectResult.TagName='Deflect.Result.Normal';c:jadeResult(foe,jade);assert(yd==0)
data.DeflectResult.TagName='Deflect.Result.Perfect';data.DefenderAvatar=player;c:jadeResult(foe,jade);assert(yd==0)
data.DefenderAvatar=foe;foe.tags[C.READY]=0;c:jadeResult(foe,jade);assert(yd==0)
foe.tags[C.READY]=1;c:jadeResult(foe,jade);c:jadeResult(foe,jade);assert(yd==1)
-- A previous cast's result cannot activate the new grab, even at the same game time.
local cb,stopped;options.loop=function(_,fn)cb=fn;return 7 end;options.cancel=function(id)assert(id==7);stopped=true end
local nextCast=obj({bIsActive=true,GetClass=function()return cls(C.JADE_GRAB)end,GetAvatarActorFromActorInfo=function()return jade end})
asc.ActivatableAbilities.Items={};asc.K2_GiveAbilityAndActivateOnce=function(_,cl,lvl,input)
    assert(cl==yc and lvl==1 and input==-1);yd=yd+1;return {Handle=18}
end
now=10.2;c:jadeCast(nextCast);assert(cb);cb();assert(yd==1,'do not consume previous dodge')
action.GetAbility=function()return nextCast end;cb();assert(yd==1,'old frame precedes the cast')
data.HitGameTime=now;cb();cb();assert(yd==2,'ungranted native ability is granted only once for this result')
local victim=obj({bIsActive=true,GetClass=function()return cls(C.JADE_EXECUTED)end,GetAvatarActorFromActorInfo=function()return jade end,
    ['Execution Info']={Executor=foe,Target=jade}})
local counter=obj({bIsActive=true,GetClass=function()return yc end,GetAvatarActorFromActorInfo=function()return foe end,
    ['Execution Info']={Executor=foe,Target=jade},['Current Frame']=data,TargetExecutedAbilitySpec=victim})
local adopted=assert(c:jadePair(counter));assert(adopted.executor==foe and adopted.target==jade)
victim['Execution Info'].Executor=player;assert(not c:jadePair(counter),'both actual native sides must agree')
data.HitGameTime=now+0.01;cb();assert(yd==2)
nextCast.bIsActive=false;assert(cb() and stopped)
c:sync({},false);now=11;data.HitGameTime=now;c:jadeResult(foe,jade);assert(yd==2)
print('PASS native Bi Feng judgment, action/range and real Yu Ding perfect-dodge receipt')
