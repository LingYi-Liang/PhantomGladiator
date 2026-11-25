package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Wave=require('lion_challenge')
local U=require('ue_observe')
local seq=0
local function actor(world)
    seq=seq+1;local id=seq
    return {GetAddress=function()return id end,IsValid=function()return true end,GetOuter=function()return world end,
        GetFullName=function()return 'NPC '..id end,hp=100,tags={}}
end
local w=actor();local boss,other,enemy,ally,cub,second=actor(w),actor(w),actor(w),actor(w),actor(w),actor(w)
boss.tags[Wave.ON_POLE]=1;other.tags[Wave.ON_POLE]=1
local members={{actor=boss,class_path=Wave.BOSS,team='red'},{actor=other,class_path=Wave.BOSS,team='red'},
    {actor=enemy,team='blue'},{actor=ally,team='red'},{actor=cub,summoner=boss,class_path=Wave.CUB,team='red'},
    {actor=second,summoner=other,class_path=Wave.CUB,team='red'}}
local c=Wave.new({world=function()return w end,hp=function(a)return a.hp end,tag=function(a,t)return a.tags[t] or 0 end})
c:sync(members,true);assert(c:preferred(enemy,'blue',U.key(boss))[U.key(cub)])
assert(not c:preferred(enemy,'blue',U.key(boss))[U.key(second)])
assert(not c:ticket(enemy,cub),'a regular cub cannot award a lion head')
assert(not c:holdsHead(enemy,boss),'taking an unrelated kill or unlocking the boss cannot award a head')
cub.tags[Wave.LAST]=1;assert(not c:ticket(ally,cub))
local proof=assert(c:ticket(enemy,cub));assert(not c:award(proof,enemy,boss),'a living cub cannot award the head');cub.hp=0;c:sync(members,true)
assert(c:award(proof,enemy,boss) and c:holdsHead(enemy,boss) and not c:holdsHead(enemy,other))
assert(not c:award(proof,enemy,boss),'a completed pickup is consumed once')
assert(c:preferred(enemy,'blue',U.key(second))[U.key(boss)],'return to the owner of this head')
boss.tags[Wave.ON_POLE]=0;c:sync(members,true);assert(not c:holdsHead(enemy,boss))
boss.tags[Wave.ON_POLE]=1;c:sync(members,true);assert(not c:award(proof,enemy,boss),'old wave receipt cannot be reused')
print('PASS owned cub priority, last-only pickup and scoped phase handoff')

local npcBase=actor()
npcBase.GetFullName=function()return 'Class /Script/ProjectPBZ.PBZCharacter_NPC' end
local function typed(a,path)
    local cls=actor()
    cls.GetFullName=function()return 'BlueprintGeneratedClass '..path end
    cls.GetSuperStruct=function()return npcBase end
    a.GetClass=function()return cls end
    return a
end
local source=typed(actor(w),Wave.BOSS)
local weakCub=typed(actor(w),Wave.CUB)
local unrelated=typed(actor(w),Wave.CUB)
local friend,otherFriend=actor(w),actor(w)
friend['Faction Component']=actor(w)
otherFriend['Faction Component']=friend['Faction Component']
friend['Faction Component'].GetFactionRelation=function(_,value)
    return (value==source or value==weakCub or value==unrelated) and 2 or 0
end
local path='/PBZCombatAsset/ActorData/Mobs/LionDancer_P2/Ability/GA_SummonPassive_LionDancer_P2.GA_SummonPassive_LionDancer_P2_C'
local passive=typed(actor(w),path)
passive.GetAvatarActorFromActorInfo=function()return source end
passive.bIsActive=true
passive.SpawnedSummonInstances={{Pawn=weakCub,bPawnPending=false}}
source.tags[Wave.ON_POLE]=1;weakCub.tags[Wave.LAST]=1;unrelated.tags[Wave.LAST]=1
local roster={{actor=friend,team='companion'},{actor=otherFriend,team='companion'}}
local target={[friend]=source,[otherFriend]=unrelated}
local time=2
local paused=false
local field=Wave.new({world=function()return w end,hp=function(a)return a.hp end,tag=function(a,t)return a.tags[t] or 0 end,
    clock=function()return time end,fieldEnabled=function()return not paused end,paused=function()return paused end,
    companionOpponent=function(a)return target[a]end,findAll=function()return {passive}end})
field:sync(roster,false)
assert(field:canFieldTarget(friend,weakCub) and not field:canFieldTarget(otherFriend,weakCub))
assert(not field:ticket(friend,unrelated),'a same-class unordered cub cannot be accepted')
local last=field:fieldLastCubs()
assert(#last==1 and last[1].actor==weakCub)
target[friend]=weakCub
field:sync(roster,false)
local fieldProof=assert(field:ticket(friend,weakCub))
assert(not field:award(fieldProof,friend,source),'the head cannot be awarded while its cub lives')
paused=true;time=time+0.5
field:sync(roster,false)
assert(field:fieldSource(friend)==source and #field:fieldLastCubs()==0,'freeze preserves the same encounter without scheduling a new pickup')
paused=false
weakCub.hp=0;target[friend]=nil;time=time+0.5
field:sync(roster,false)
assert(field:award(fieldProof,friend,source))
assert(field:holdsHead(friend,source) and field:fieldSource(friend)==source and not field:holdsHead(otherFriend,source))
paused=true;field:sync(roster,false)
assert(field:holdsHead(friend,source),'the same head proof stays readable while frozen')
paused=false
field:stopArena()
assert(field:holdsHead(friend,source),'stopping the arena preserves an ongoing map duel')
source.tags[Wave.ON_POLE]=0;time=time+0.5
field:sync(roster,false)
assert(not field:holdsHead(friend,source) and not field:fieldSource(friend))
print('PASS field phase from an exact native summon row, expiring head receipts and isolated companion scope')
