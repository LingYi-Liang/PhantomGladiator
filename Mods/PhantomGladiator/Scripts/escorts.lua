-- Units the game places together with another one, summoned along with it on the same team.
-- 驯犬客: at his home (血色森林 C, level 6) two of the three stand in a group with two 狂犬; on 登顶山道 a spawner
-- script (AIScript_SummonMonster, Dog group) raises four or five when he starts. His own summon passive
-- (GA_SummonPassive_DogTrainer: SummonInfos = one BP_Monster_Dog with MaxCount 1) keeps at most one whistled dog
-- alive, so without these a summoned 驯犬客 has one dog at most. Found offline (audit-tools), see REVERSE_ENGINEERING.
local Escorts={}
local LIST={
    ['/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_DogTamer.BP_Monster_DogTamer_C']={
        {path='/PBZCombatAsset/ActorData/Mobs/005_ModDog/BP_Monster_Dog.BP_Monster_Dog_C',count=2}},
}
function Escorts.of(path)return LIST[path]end
return Escorts
