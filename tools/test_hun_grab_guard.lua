package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Guard=require('hun_grab_guard')
local C=require('hun_grab_catalog')
local a,b=0,0
for _ in pairs(C.bullets)do a=a+1 end
for _ in pairs(C.receivers)do b=b+1 end
assert(a==68 and b==62)
local seq=0
local function obj(name)
    seq=seq+1;local id=seq
    return {IsValid=function(self)return self.valid~=false end,GetAddress=function()return id end,
        GetFullName=function()return name end}
end
local function param(value)
    return {type=function()return 'RemoteUnrealParam' end,get=function()return value end,
        set=function(_,new)value=new end}
end
local function record(rule)
    local actor=obj('NPC Soul')
    actor.AbilitySystemComponent=obj('ASC Soul')
    return {name='NPC',actor=actor,loadout={survival={grab=rule}}}
end
local n,guarded,other=record('native'),record('immune'),record('immune')
local null={type=function()return 'UClass' end,IsValid=function()return false end}
local event=obj('Class BP_BulletEvent_Grab');local cdo=obj('CDO')
cdo.NonPlayerGE=null;event.GetCDO=function()return cdo end
local hooks,live,removed={},{[n]=true,[guarded]=true,[other]=true},0
local inside=true
local g=Guard.new{current=function(r)return live[r]==true end,inGameThread=function()return inside end,
    find=function(path)if path:find('BP_BulletEvent_Grab',1,true)then return event end;return obj('Function '..path) end,
    register=function(key,pre,post)hooks[key]={pre,post};return 12,13 end,
    unregister=function(key,i,j)assert(i==12 and j==13);hooks[key]=nil;removed=removed+1 end}
g:start(n);assert(not next(hooks))
g:start(guarded);g:start(other)
local gi=hooks['/Script/GameplayAbilities.AbilitySystemComponent:K2_GiveAbility'][1]
local vt=hooks['/Script/SGameCombatSystem.BulletAttackModule:IsValidTarget'][2]
local receiver=next(C.receivers)
local ability=obj('BlueprintGeneratedClass '..receiver);local value=param(ability)
gi(param(n.actor.AbilitySystemComponent),value,param(0),param(-1));assert(value:get()==ability)
inside=false;gi(param(guarded.actor.AbilitySystemComponent),value,param(0),param(-1));assert(value:get()==ability)
inside=true;gi(param(guarded.actor.AbilitySystemComponent),value,param(1),param(-1));assert(value:get()==ability)
live[guarded]=false;gi(param(guarded.actor.AbilitySystemComponent),value,param(0),param(-1));assert(value:get()==ability)
live[guarded]=true;gi(param(guarded.actor.AbilitySystemComponent),value,param(0),param(-1));assert(value:get()==null and g.grants==1)
local normal=obj('Class /Game/Test.MyNormalCombatExecution_C');local untouched=param(normal)
gi(param(guarded.actor.AbilitySystemComponent),untouched,param(0),param(-1));assert(untouched:get()==normal)
local hit=obj('Module')
hit.BulletData=obj('BulletData '..next(C.bullets))
assert(vt(param(hit),param(n.actor))==nil)
assert(vt(param(hit),param(guarded.actor))==false and g.targets==1)
hit.BulletData=obj('BulletData /Game/Generic.Damage');assert(vt(param(hit),param(guarded.actor))==nil)
g:stop(guarded);assert(next(hooks))
value=param(ability);gi(param(guarded.actor.AbilitySystemComponent),value,param(0),param(-1));assert(value:get()==ability)
g:stop(other);assert(not next(hooks) and removed==2)
g:silence();assert(cdo.NonPlayerGE==null and ability.valid~=false)
print('PASS hun_grab_guard 68 bullet packages and 62 receivers, target and ASC isolation, hook lifecycle')
