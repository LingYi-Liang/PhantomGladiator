package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Pillar=require('moyuan_pillar')
local seq=0
local function obj(v)
    seq=seq+1;local id=seq
    v.IsValid=function()return true end;v.GetAddress=function()return id end
    return v
end
local function make()
    local mesh=obj({})
    local asset=obj({GetFullName=function()return 'NiagaraSystem /PBZVFXPack/VFX/BattleFX/MoYuan/NS_MoYuan_Pillar_001_Main.NS_MoYuan_Pillar_001_Main'end})
    local comp=obj({Asset=asset,running=true,GetAttachParent=function()return mesh end,IsActive=function(self)return self.running end})
    local cls=obj({GetFName=function()return {ToString=function()return 'GA_MoTian_Skill_06_C'end}end})
    local row={Ability=obj({GetClass=function()return cls end}),ActiveCount=1}
    local asc=obj({ActivatableAbilities={Items={row}}})
    local actor=obj({Mesh=mesh,Pillar=comp,AbilitySystemComponent=asc,DespawnPillar=function(self)self.Pillar.running=false end})
    return {actor=actor,class_path='/PBZCombatAsset/ActorData/Mobs/067_MoTian/BP_Monster_MoTian.BP_Monster_MoTian_C'},row,comp
end
local a,row,comp=make();local b,_,other=make()
local adapter=Pillar.new(function()end)
adapter:tick({a,b});row.ActiveCount=0;adapter:tick({a,b})
assert(comp.running,'allow a transient inactive frame')
row.ActiveCount=1;adapter:tick({a,b});assert(comp.running)
row.ActiveCount=0;adapter:tick({a,b});adapter:tick({a,b})
assert(not comp.running and other.running,'only the interrupted instance is cleaned')
comp.running=true;comp.GetAttachParent=function()return b.actor.Mesh end
adapter:tick({a});adapter:tick({a});assert(comp.running,'do not touch a detached or reparented effect')
print('PASS scoped interrupted pillar cleanup')
