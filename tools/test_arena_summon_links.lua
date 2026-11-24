package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Links=require('arena_summon_links')
local function object(id,fields)
    local v=fields or {};v.alive=true
    function v:IsValid() return self.alive end
    function v:GetAddress() assert(self.alive);return id end
    function v:GetOuter() assert(self.alive);return self.outer end
    function v:GetClass() assert(self.alive);return self.class end
    function v:GetFullName() assert(self.alive);return self.full end
    function v:GetSuperStruct() assert(self.alive);return self.parent end
    return v
end
local world=object(1);local level=object(2,{outer=world})
local base=object(3,{full='Class /Script/ProjectPBZ.PBZCharacter_NPC'})
local cls=object(4,{full='BlueprintGeneratedClass /Game/BP_Child.BP_Child_C',parent=base})
local root=object(5,{outer=level,class=cls})
local enemy=object(6,{outer=level,class=cls})
local child=object(7,{outer=level,class=cls,Owner=enemy})
local own=object(8,{outer=level,class=cls,Owner=root})
local mapNpc=object(9,{outer=level,class=cls})
local pending=object(10,{outer=level,class=cls})
local foreign=object(11,{outer=object(12),class=cls,Owner=root})
local ability=object(13,{SpawnedSummonInstances={{Pawn=child,bPawnPending=false},{Pawn=pending,bPawnPending=true}}})
function ability:GetAvatarActorFromActorInfo() assert(self.alive);return root end
local scanner=Links.new({getWorld=function()return world end,findAll=function()return {ability} end,getNPCs=function()return {child,own,mapNpc,pending,foreign} end})
local found=scanner:scan({{actor=root,team='blue'},{actor=enemy,team='red'}})
assert(#found==2,'only verified same-world descendants are candidates')
for _,entry in ipairs(found) do
    assert(entry.parent==root,'explicit ability provenance wins over a weaker Owner link')
    assert(entry.actor==child or entry.actor==own)
end
assert(#scanner:scan({{actor=root},{actor=enemy},{actor=child},{actor=own}})==0,'already owned summons must not be adopted again')
local passives={}
scanner:scan({{actor=root,team='companion'}},function(a)passives[#passives+1]=a end)
assert(#passives==1 and passives[1]==ability,'the passive of a unit in the list is handed on')
passives={}
scanner:scan({{actor=enemy,team='red'}},function(a)passives[#passives+1]=a end)
assert(#passives==0,'not the passive of a unit outside the list')
local errors=''
local logged=Links.new({getWorld=function()return world end,findAll=function()return {ability} end,getNPCs=function()return {} end,log=function(s)errors=s end})
logged:scan({{actor=root,team='blue'}},function()error('boom')end)
assert(errors:find('errors=1',1,true),'an error there stays in the count and the scan goes on: '..errors)
-- A third duplicate cannot resolve two conflicting native parent records.
do
    local rival=object(906,{outer=level,class=cls})
    local child=object(907,{outer=level,class=cls})
    local function listedBy(owner)
        local p=object(908,{SpawnedSummonInstances={{Pawn=child,bPawnPending=false}}})
        function p:GetAvatarActorFromActorInfo()return owner end
        return p
    end
    for _,order in ipairs({{root,rival,root},{rival,root,rival},{root,root,rival}}) do
        local s=Links.new({getWorld=function()return world end,getNPCs=function()return {} end,
            findAll=function()return {listedBy(order[1]),listedBy(order[2]),listedBy(order[3])}end})
        assert(#s:scan({{actor=root,team='blue'},{actor=rival,team='red'}})==0,'conflicting summoners cannot be decided by list order')
    end
end
-- Whom the passive's summons fight (SummonCombatTargetMode, a name): EncounterSummons and Summoner fight the
-- summoner's side; InheritedHatred, no value, None and a non-name do not.
do
    local function fname(s)return {ToString=function()return s end} end
    local boss=object(20,{outer=level,class=cls})
    local rival=object(21,{outer=level,class=cls})
    local function run(mode,rows,npcs)
        local passive=object(22,{SpawnedSummonInstances=rows,SummonCombatTargetMode=mode})
        function passive:GetAvatarActorFromActorInfo() assert(self.alive);return boss end
        local s=Links.new({getWorld=function()return world end,findAll=function()return {passive} end,getNPCs=function()return npcs or {} end})
        local out={}
        for _,entry in ipairs(s:scan({{actor=boss,team='red'},{actor=rival,team='blue'}}))do out[entry.actor]=entry end
        return out
    end
    for _,case in ipairs({{fname('EncounterSummons'),true},{fname('Summoner'),true},{'EncounterSummons',true},
        {fname('InheritedHatred'),false},{nil,false},{fname('None'),false},{2,false}})do
        local helper=object(23,{outer=level,class=cls})
        local got=run(case[1],{{Pawn=helper,bPawnPending=false}})[helper]
        assert(got and got.parent==boss and got.opposing==case[2],'mode '..tostring(case[1] and (type(case[1])=='table' and case[1].ToString() or case[1])))
        if case[2] then assert(got.evidence:find('SummonCombatTargetMode=',1,true) and got.mode) else assert(not got.evidence:find('SummonCombatTargetMode=',1,true) or got.mode=='InheritedHatred') end
    end
    -- Still pending in the list but found by its Owner first: the link takes the mode of its own summoner's passive.
    local early=object(24,{outer=level,class=cls,Owner=boss})
    local got=run(fname('EncounterSummons'),{{Pawn=early,bPawnPending=true}},{early})[early]
    assert(got and got.parent==boss and got.opposing==true and got.evidence:find('Actor.Owner',1,true),'pending, found by Owner: still a helper')
    local stray=object(25,{outer=level,class=cls,Owner=rival})
    got=run(fname('EncounterSummons'),{{Pawn=stray,bPawnPending=true}},{stray})[stray]
    assert(got and got.parent==rival and got.opposing==false,'owned by someone else than the passive\'s summoner: no mode')
    local plain=object(26,{outer=level,class=cls,Owner=boss})
    got=run(fname('EncounterSummons'),{},{plain})[plain]
    assert(got and got.opposing==false,'not in the passive\'s list: no mode')
end
do
    local tick,fullScans,passives,idle=0,0,{},true
    local parent=object(60,{outer=level,class=cls,full='NPC Follower',Children={}})
    local stray=object(61,{outer=level,class=cls,Instigator=parent})
    local child2=object(62,{outer=level,class=cls,Owner=parent})
    local npcs={}
    for i=1,240 do npcs[i]=object(100+i,{outer=level,class=cls})end
    local roster={{actor=parent,team='companion'}}
    local scan=Links.new({getWorld=function()return world end,clock=function()return tick*.5 end,
        localNPC=function()return true end,idleOwner=function()return idle end,findAll=function()return passives end,
        getNPCs=function()fullScans=fullScans+1;return npcs end})
    local function has(items,actor)for _,e in ipairs(items)do if e.actor==actor then return true end end;return false end
    for i=0,119 do tick=i;assert(#scan:scan(roster,nil,true)==0)end
    print("MEASURE 120 companion ticks, 240 map NPCs: world enumerations="..fullScans)
    assert(fullScans<=30,"the map was enumerated again on every stable companion tick")
    tick=120;scan:scan(roster,nil,true)
    tick=121;parent.Children={child2};npcs[#npcs+1]=child2;npcs[#npcs+1]=stray
    assert(has(scan:scan(roster,nil,true),child2),"actor-owned child appears on the first tick")
    local discovered=false
    for i=122,124 do tick=i;discovered=has(scan:scan(roster,nil,true),stray) or discovered end
    assert(discovered,"periodic full sweep finds instigator-only summons")
    local lastMoment=object(63,{outer=level,class=cls,Instigator=parent})
    tick=125;npcs[#npcs+1]=lastMoment
    assert(has(scan:scan(roster),lastMoment),"cleanup must see new instigator-only summons immediately")
    local last=fullScans;roster[1].team='red';tick=126;scan:scan(roster,nil,true);tick=127;scan:scan(roster,nil,true)
    assert(fullScans==last+2,"the arena always checks full ownership")
    roster[1].team='companion';parent.Children=nil;tick=128;scan:scan(roster,nil,true);tick=129;scan:scan(roster,nil,true)
    assert(fullScans==last+4,"unreadable actor children require the complete discovery path")
    parent.Children={};idle=false
    for i=130,132 do tick=i;scan:scan(roster,nil,true)end
    assert(fullScans==last+7,"a companion in combat or playing a move keeps the full scan cadence")
end
do
    local parent=object(378,{outer=level,class=cls});local other=object(379,{outer=level,class=cls})
    local child2=object(380,{outer=level,class=cls,Owner=parent})
    local function passive(id,owner,mode,pending)
        return object(id,{GetAvatarActorFromActorInfo=function()return owner end,SummonCombatTargetMode=mode,
            SpawnedSummonInstances={{Pawn=child2,bPawnPending=pending}}})
    end
    local function match(a,b)
        local scan=Links.new({getWorld=function()return world end,findAll=function()return {a,b}end,getNPCs=function()return {child2}end})
        return scan:scan({{actor=parent},{actor=other}})
    end
    local fight=passive(381,parent,'Summoner',true);local stranger=passive(382,other,'InheritedHatred',true)
    for _,pair in ipairs({{fight,stranger},{stranger,fight}})do
        local out=match(pair[1],pair[2]);assert(#out==1 and out[1].opposing,"a second passive cannot erase the owner's pending summon rule")
    end
    fight.SpawnedSummonInstances[1].bPawnPending=false
    local friendly=passive(383,parent,'InheritedHatred',false)
    assert(#match(fight,friendly)==0 and #match(friendly,fight)==0,"contradictory full proofs must never pick a side by scan order")
    local sameSide=passive(384,parent,'EncounterSummons',false)
    local x,y=match(fight,sameSide)[1],match(sameSide,fight)[1]
    assert(x and y and x.opposing and y.opposing and x.evidence==y.evidence,"different native modes that agree on the side remain usable")
end
do
    local partial=Links.new({getWorld=function()return world end,findAll=function()return {} end,
        getNPCs=function()return {own},false end})
    local matches,stats=partial:scan({{actor=root}})
    assert(#matches==1 and stats.errors>0,'a partial native sweep can prove a child exists but cannot prove the roster is complete')
end
root.alive=false;enemy.alive=false
assert(#scanner:scan({{actor=root},{actor=enemy}})==0,'invalid owners must not be dereferenced or used to claim map actors')
print('arena_summon_links: PASS (native list, false pending flag, exact owner, conflicts, world boundary, duplicate and invalid exclusions, summon combat side)')
