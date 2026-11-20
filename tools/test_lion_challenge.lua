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
