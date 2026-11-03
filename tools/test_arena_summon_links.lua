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
root.alive=false;enemy.alive=false
assert(#scanner:scan({{actor=root},{actor=enemy}})==0,'invalid owners must not be dereferenced or used to claim map actors')
print('arena_summon_links: PASS (native list, false pending flag, exact owner, conflicts, world boundary, duplicate and invalid exclusions)')
