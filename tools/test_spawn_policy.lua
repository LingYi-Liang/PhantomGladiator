-- 防护策略单元测试；不是原生崩溃复现，也不证明允许单位的战斗兼容性。
local Policy = dofile("Mods/PhantomGladiator/Scripts/spawn_policy.lua")
assert(type(Policy) == "table", "spawn_policy must return its module table")
local vessel = "/PBZCombatAsset/ActorData/Mobs/023_Vessel_Child/BP_Monster_Vessel_Child.BP_Monster_Vessel_Child_C"
local flame = "/PBZCombatAsset/ActorData/Mobs/005_ModDog/BP_Monster_FlameDog.BP_Monster_FlameDog_C"
local ok, message, status = Policy.check(vessel)
assert(ok == true and status == "verified_spawn_observation")
assert(message:find("战斗兼容性未验收", 1, true), "allowlist is not a combat compatibility claim")
ok, message, status = Policy.check(flame)
assert(ok == false and status == "quarantined_incident")
assert(message:find("尚未单独定因", 1, true), "quarantine must not claim a proven native crash cause")
local rejected = {
    "/AnotherPlugin/BP_Monster_Vessel_Child.BP_Monster_Vessel_Child_C",
    "/PBZCombatAsset/ActorData/Mobs/023_Vessel_Child/Other.BP_Monster_Vessel_Child_C",
    vessel .. " ", vessel .. ":SubObject", vessel .. "\n",
    "BlueprintGeneratedClass " .. vessel, vessel:lower(), "", false, 1,
    "/AnotherPlugin/BP_Monster_FlameDog.BP_Monster_FlameDog_C",
    "/PBZCombatAsset/ActorData/Mobs/000_Hun/BP_Monster_Hun.BP_Monster_Hun_C",
}
for _, path in ipairs(rejected) do
    local allowed, _, classification = Policy.check(path)
    assert(allowed == false and classification == "unverified", "exact path policy must reject alternate location/name/type")
end
assert(Policy.check(nil) == false)
local paths = Policy.knownPaths()
local sword='/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue.BP_Monster_MaleThug_Sword_Blue_C'
assert(#paths == 2 and paths[1] == sword and paths[2]==vessel)
local tested,_,testStatus=Policy.check(sword)
assert(tested and testStatus=='verified_spawn_observation')
assert(Policy.limits(sword).max_count==8 and Policy.limits(sword).max_live==24)
assert(Policy.canBattle(vessel)==false and Policy.canBattle(sword)==true)
paths[1], paths[2] = flame, vessel
assert(Policy.knownPaths()[1] == sword and #Policy.knownPaths() == 2, "caller cannot mutate policy through returned paths")
print("spawn_policy: PASS (bounded ordinary NPC test, Vessel excluded from battle, FlameDog quarantine, exact paths)")
local trial='/Game/Mobs/BP_TestEnemy.BP_TestEnemy_C'
local tmp=os.tmpname()
local file=assert(io.open(tmp,'wb'));file:write('PhantomGladiatorSpawnTrialsV1\n'..trial..'\tmob\n');file:close()
assert(Policy.loadTrials(tmp,function() end))
assert(Policy.check(trial)==true and Policy.limits(trial).max_count==1)
assert(Policy.status().count==1 and Policy.status().version=='codex_primary_npc_v1')
assert(Policy.check(flame)==false and Policy.check(trial..':SubObject')==false)
file=assert(io.open(tmp,'wb'));file:write('PhantomGladiatorSpawnTrialsV1\n'..trial..'\tmob\n'..flame..'\tmob\n');file:close()
assert(Policy.loadTrials(tmp,function() end)==false)
assert(Policy.check(trial)==false and Policy.status().count==0,'invalid manifest must not keep a partial allowlist')
os.remove(tmp)
print('spawn_policy trials: PASS (exact manifest, single spawn, quarantine, fail closed)')
Policy.enableAllCatalog()
assert(Policy.check(flame)==true and Policy.check('/Game/BP_Test_Base.BP_Test_Base_C')==true)
assert(Policy.limits(sword)==nil and Policy.limits(trial)==nil)
assert(Policy.check('/Game/../Bad.Bad_C')==false and Policy.status().mode=='all_catalog')
