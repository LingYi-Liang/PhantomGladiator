"use strict";
const CatalogBrowser=(()=>{
  const unknown="__unknown__";
  function matches(unit,filters){
    if(filters.view==="primary"&&unit.codex_entry_kind!=="primary")return false;
    if(filters.view==="disk"&&unit.disk_verified_unit!==true)return false;
    if(filters.view!=="primary"&&!filters.showSpecial&&unit.is_special)return false;
    if(filters.type&&unit.browse_type!==filters.type)return false;
    if(filters.chapter&&(filters.chapter===unknown?!!unit.chapter_id:unit.chapter_id!==filters.chapter))return false;
    if(filters.map&&(filters.map===unknown?!!unit.map_id:unit.map_id!==filters.map))return false;
    if(filters.only&&!unit.spawnable)return false;
    if(filters.configured&&!(unit.configured_spawner_count>0))return false;
    return !filters.query||unit.searchText.includes(filters.query);
  }
  function compare(a,b){
    const order=x=>Number.isFinite(x)?x:1000000;
    return order(a.chapter_order??a.map_order)-order(b.chapter_order??b.map_order)
      ||order(a.map_order)-order(b.map_order)||order(a.codex_order)-order(b.codex_order)
      ||String(a.display_name||a.name).localeCompare(String(b.display_name||b.name),"zh-CN")
      ||a.id.localeCompare(b.id);
  }
  function affiliation(unit){
    if(!unit.map_id)return unit.map_status==="unassigned"?"图鉴未指定地图":"地图归属待查";
    return [unit.chapter_name||unit.chapter_id,unit.map_name||unit.map_id].filter(Boolean).join(" · ");
  }
  function groupKey(unit){return JSON.stringify([unit.chapter_id||"",unit.map_id||""]);}
  function typeLabel(type){return type==="普通敌人"?"小怪":type;}
  return {unknown,matches,compare,affiliation,groupKey,typeLabel};
})();
if(typeof module!=="undefined")module.exports=CatalogBrowser;
