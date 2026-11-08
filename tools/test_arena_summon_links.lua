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
root.alive=false;enemy.alive=false
assert(#scanner:scan({{actor=root},{actor=enemy}})==0,'invalid owners must not be dereferenced or used to claim map actors')
print('arena_summon_links: PASS (native list, false pending flag, exact owner, conflicts, world boundary, duplicate and invalid exclusions, summon combat side)')
