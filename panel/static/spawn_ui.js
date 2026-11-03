"use strict";
const SpawnUI=(()=>{
  const baseline='/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue.BP_Monster_MaleThug_Sword_Blue_C';
  const spear='/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Spear_Blue.BP_Monster_MaleThug_Spear_Blue_C';
  const isBaseline=unit=>unit?.class_path===baseline;
  const hasSpawnObservation=unit=>isBaseline(unit)||unit?.class_path===spear;
  const special=unit=>unit?.is_special===true||unit?.browse_type==='特殊机制'||unit?.category==='特殊实体';
  const trial=unit=>unit?.validation_status==='controlled_test'&&!isBaseline(unit);
  const needsReload=(unit,game)=>unit?.validation_status==='experimental_spawn'?game?.spawn_mode!=='all_catalog':trial(unit)&&(game?.spawn_trial_policy!=='codex_primary_npc_v1'||Number(game?.spawn_trial_count)<1);
  const maxCount=(unit,game)=>Math.min(unit?.max_count||8,game?.spawn_mode==='all_catalog'?8:1);
  const allowed=unit=>[true,1,'1','true'].includes(unit?.spawnable);
  const canAttempt=(unit,game)=>!!unit&&allowed(unit)&&(!special(unit)||game?.spawn_mode==='all_catalog')&&!needsReload(unit,game);
  function label(unit,game){
    if(!allowed(unit))return '目录参考 · 暂不可召唤';
    if(needsReload(unit,game))return '重载 Mod 后可试召唤';
    if(isBaseline(unit))return '已实测互斗 · 可召唤';
    if(hasSpawnObservation(unit))return '已实测生成 · 可召唤';
    if(unit.validation_status==='experimental_spawn')return special(unit)?'特殊／模板 · 可尝试召唤':'可尝试召唤 · 未验证';
    if(trial(unit))return '单只试召唤 · 未实测';
    return '可召唤 · 战斗未验收';
  }
  function description(unit,game){
    if(isBaseline(unit))return '该持刀暴徒已有生成、受击、NPC互伤和死亡实测；每次最多8只，总量不设上限，长期稳定性仍待验证。';
    if(hasSpawnObservation(unit))return '该长枪暴徒已有生成、AI和血量读回，已确认会行动；每次最多8只，总量不设上限，互斗尚未验收。';
    if(unit?.validation_status==='experimental_spawn')return (needsReload(unit,game)?'等待游戏重载新模式。':'')+'已开放尝试召唤；未知实体可能生成失败或导致崩溃。非战斗实体不保证有AI或血量，失败会显示具体原因。';
    if(trial(unit))return (needsReload(unit,game)?'新许可等待游戏重载读回。':'')+'原生图鉴已确认敌人身份；可单只试召唤，生成兼容性尚未实测，仍可能崩溃。场上最多2只，失败时先清理。';
    return unit?.validation_scope||'单位兼容性尚未验证。';
  }
  return {isBaseline,hasSpawnObservation,special,trial,needsReload,canAttempt,label,description,maxCount};
})();
if(typeof module!=='undefined')module.exports=SpawnUI;
