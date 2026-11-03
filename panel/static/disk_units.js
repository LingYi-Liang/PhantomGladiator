"use strict";
const DiskUnits=(()=>{
  function build(index,catalog,{query="",kind="unit",type="",offset=0,limit=100}={}){
    if(!index||index.schema_version!==1||index.verified!==true)return {available:false};
    const byPackage=new Map(catalog.map(unit=>[unit.class_path.slice(0,unit.class_path.lastIndexOf('.')).toLocaleLowerCase(),unit]));
    const summary={verified:0,candidates:0,by_kind:{}},types=new Map(),selected=[],seen=new Set();
    const term=query.toLocaleLowerCase();
    for(const file of index.files){
      const key=file.virtual_package.toLocaleLowerCase(),unit=byPackage.get(key);
      if(!unit||seen.has(key))continue;seen.add(key);
      const verified=unit.inheritance_verified===true||["primary","alias"].includes(unit.codex_entry_kind);
      summary[verified?"verified":"candidates"]++;
      if(verified){const root=unit.resolved_unit_kind||"codex";summary.by_kind[root]=(summary.by_kind[root]||0)+1;}
      if(verified!==(kind==="unit"))continue;
      const category=unit.browse_type||"待分类";types.set(category,(types.get(category)||0)+1);
      if(type&&category!==type)continue;
      const search=[file.file_path,file.virtual_package,unit.display_name,unit.internal_name,unit.chapter_name,unit.map_name].filter(Boolean).join(" ").toLocaleLowerCase();
      if(term&&!search.includes(term))continue;
      selected.push({...file,kind:"package",unit:{display_name:unit.display_name,internal_name:unit.internal_name,
        name_source_label:unit.name_source_label,browse_type:category,chapter_name:unit.chapter_name,map_name:unit.map_name,
        codex_entry_kind:unit.codex_entry_kind,class_path:unit.class_path,verified}});
    }
    selected.sort((a,b)=>(a.unit.codex_entry_kind==="primary"?0:1)-(b.unit.codex_entry_kind==="primary"?0:1)
      ||a.unit.browse_type.localeCompare(b.unit.browse_type,"zh-CN")||String(a.unit.display_name).localeCompare(String(b.unit.display_name),"zh-CN")
      ||a.file_path.localeCompare(b.file_path));
    return {available:true,verified:true,total:index.total_files,matched:selected.length,offset,unit_summary:summary,
      unit_types:[...types].sort(([a],[b])=>a.localeCompare(b,"zh-CN")).map(([name,count])=>({name,count})),files:selected.slice(offset,offset+limit)};
  }
  return {build};
})();
if(typeof module!=="undefined")module.exports=DiskUnits;
