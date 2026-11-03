local Survey=dofile('Mods/PhantomGladiator/Scripts/spawn_catalog_export.lua')
local realOpen=io.open;local files={}
io.open=function(path)files[path]='';return {write=function(self,s)files[path]=files[path]..s;return self end,flush=function()return true end,close=function()return true end}end
local serial=0
local function object(name,fields)
    serial=serial+1;local id=serial;local o=fields or {};o.alive=true
    o.IsValid=function()return o.alive end;o.GetAddress=function()assert(o.alive);return id end
    o.GetFullName=function()assert(o.alive);return name end
    return o
end
local function soft(path)
    return {GetObjectID=function()return {GetAssetPathName=function()return path end,GetSubPathString=function()return ''end}end,
        Get=function()error('never resolve/load soft reference')end,LoadSynchronous=function()error('never load')end}
end
local w1=object('World /Game/Test.Test');local w2=object('World /Game/Other.Other')
local level=object('Level /Game/Test.Test:PersistentLevel',{GetOuter=function()return w1 end})
local clsPath='/Game/Units/BP_Test.BP_Test_C'
local cls=object('BlueprintGeneratedClass '..clsPath,{IsAnyClass=function()return true end})
local function actor(n)
    return object(n,{GetOuter=function()return level end,IsActorBeingDestroyed=function()return false end,
        K2_GetActorLocation=function()return {X=1,Y=2,Z=3}end,GetClass=function()return cls end})
end
local npc=actor('BP_Test_C /Game/Test.Test:PersistentLevel.OriginalNPC')
local spawner=actor('BP_AISpawner_C /Game/Test.Test:PersistentLevel.Spawner')
spawner.Class=soft(clsPath);spawner.RandomSpawnClasses={soft('/Game/Units/BP_Random.BP_Random_C')}
spawner.Spawn=function()error('must not spawn')end
local foreign=actor('BP_AISpawner_C /Game/Other.Other:PersistentLevel.OtherSpawner');foreign.GetOuter=function()return w2 end
local dead=actor('BP_AISpawner_C /Game/Test.Test:PersistentLevel.Destroying');dead.IsActorBeingDestroyed=function()return true end
dead.K2_GetActorLocation=function()error('destroying actor must never be read')end
local map=object('MapSubsystem',{GetOuter=function()return w1 end,GetMapIDByLocation=function(_,p)assert(p.X==1);return 'Map_A'end})
IsInGameThread=function()return true end
LoadAsset=function()error('must not load')end
FindAllOf=function(kind)
    if kind=='PBZCharacter_NPC' then return {npc} end
    if kind=='AISpawner' then return {spawner,foreign,dead} end
    if kind=='MapSubsystem' then return {map} end
    return {}
end
local result=Survey.new({path='D:/test-spawns',getWorld=function()return w1 end}):export()
assert(result.ok and result.actors==1 and result.spawners==1 and result.configured==2)
local csv=files['D:/test-spawns/spawn-config.tsv']
assert(csv:find('configured_spawn',1,true) and csv:find('loaded_actor_observation',1,true))
assert(csv:find(clsPath,1,true) and csv:find('Map_A',1,true) and not csv:find('OtherSpawner',1,true))
for line in csv:gmatch('([^\n]+)\n') do local _,tabs=line:gsub('\t','');assert(tabs==10) end
io.open=realOpen
print('spawn_catalog_export: PASS (current World only, destroying guard, exact soft classes, random alternatives, occurrence vs config, no load/spawn)')
