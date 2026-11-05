"use strict";
const $ = id => document.getElementById(id);
const PAGE_SIZE = 120;
const state = {
  units: [], byId: new Map(), selected: null, status: null, csrf: "", page: 0,
  busy: new Set(), pollPromise: null, catalogFetchedAt: 0,
  catalogTotal: -1, catalogVersion: 0, forceCatalog: true, catalogState: "",
  filterKey: "", filtered: [], renderToken: 0, selectionTimer: null,
  submittedSelection: "", selectionJob: null, selectionError: "", selectionSending: false,
  commandChain: Promise.resolve(), keyJob: null, diskSummary: null, trialPolicy: '',unitKeyServer:false,unitKeyRevision:'',unitKeyEvent:'',teamRevision:'',
};
const actions = {spawn:"召唤单位",select_unit:"同步快捷键选择",start:"开始交战",stop:"停止并清理",clear_neutral:"清理未配队单位",refresh_catalog:"扫描游戏目录",configure_keys:"修改快捷键",configure_unit_key:"设置单位快捷键",toggle_spectator:"单独切换无仇恨",toggle_stat_match:"切换数值统一",toggle_camera:"自由观战（无仇恨＋隐身＋无敌锁血）",exit_camera:"退出观战并恢复",cycle_team:"切换队伍",recall_companions:"召回随从",dismiss_companions:"解散随从",toggle_track:"镜头跟踪开关",track_pick:"镜头锁定屏幕中央的单位",track_next:"镜头跟踪下一个单位",set_camera_track:"保存镜头跟踪设置",toggle_time_stop:"时停",set_free_camera:"自由视角设置"};
const labels = {queued:"等待发送",pending:"等待游戏回执",succeeded:"已完成",failed:"失败",uncertain:"结果未确认"};
const yieldUI = () => new Promise(resolve => setTimeout(resolve, 0));
function element(tag, cls, text) { const node=document.createElement(tag); if(cls)node.className=cls; if(text!==undefined)node.textContent=String(text); return node; }
function truth(value) { return value===true||value===1||value==="1"||value==="true"; }
function rawGame() { return state.status?.game?.status||state.status?.game?.values||state.status?.game||{}; }
function gameOnline() { return !!state.status?.game?.online && !!state.csrf; }
function gameReady() { return gameOnline() && state.status?.game?.ready===true; }
function selectedUnit() { return state.byId.get(state.selected)||null; }
function isSpecial(unit) { return SpawnUI.special(unit); }
function displayTitle(unit) {
  const text=unit.display_name||unit.name||unit.id, suffix=`〔${unit.internal_name||""}〕`;
  return text.endsWith(suffix)?text.slice(0,-suffix.length):text;
}
function unitSearchText(unit) {
  return [unit.display_name,unit.internal_name,unit.name,unit.class_path,unit.category,unit.browse_type,unit.species_label,
    unit.chapter_name,unit.chapter_id,unit.map_name,unit.map_id,unit.level_name,...(unit.trait_labels||[])].filter(Boolean).join(" ").toLocaleLowerCase();
}
function permissionLabel(unit) {
  return SpawnUI.label(unit,rawGame());
}
function selectionPayload() {
  const unit=selectedUnit(), count=Number($("count").value), team=$("team").value;
  if(!SpawnUI.canAttempt(unit,rawGame())||!Number.isInteger(count)||count<1||count>SpawnUI.maxCount(unit,rawGame())||!["blue","red","neutral"].includes(team))return null;
  return {unit_id:unit.id,team,count};
}
function signature(payload) { return payload?JSON.stringify([payload.unit_id,payload.team,payload.count]):""; }
function selectionConfirmed(payload) { const raw=rawGame(); return gameOnline()&&!!payload&&raw.current_unit===payload.unit_id&&raw.current_team===payload.team&&Number(raw.current_count)===payload.count; }
function findJob(id) { return state.status?.queue?.find(job=>job.id===id); }
function pending(action) { return state.status?.queue?.some(job=>job.action===action&&["queued","pending"].includes(job.status)); }
function toast(text) { $("toast").textContent=text; $("toast").hidden=false; clearTimeout(toast.timer); toast.timer=setTimeout(()=>{$("toast").hidden=true;},6000); }
async function api(path, body) {
  const controller=new AbortController(), timeout=setTimeout(()=>controller.abort(),12000);
  try {
    const options={signal:controller.signal};
    if(body!==undefined)Object.assign(options,{method:"POST",headers:{"Content-Type":"application/json","X-CSRF-Token":state.csrf},body:JSON.stringify(body)});
    const response=await fetch(path,options); let data;
    try{data=await response.json();}catch{throw new Error("本地服务返回了无法读取的结果");}
    if(!response.ok)throw new Error(data.error||data.message||`请求失败 (${response.status})`);
    return data;
  } catch(error) { if(error.name==="AbortError")throw new Error("本地服务响应超时；先查看操作记录，避免重复提交。"); throw error; }
  finally { clearTimeout(timeout); }
}
// Preserve write order from this tab; a timeout never causes an automatic replay.
function post(path,body) {
  const request=state.commandChain.then(()=>{if(!gameOnline())throw new Error("游戏未连接，未发送操作。");return api(path,body);});
  state.commandChain=request.catch(()=>{}); return request;
}

const selectionHint=element("p","hint"); selectionHint.id="selection-sync";
selectionHint.setAttribute("aria-live","polite"); $("selected-reason").insertAdjacentElement("afterend",selectionHint);
function renderSelectionState() {
  const payload=selectionPayload();
  if(!selectedUnit())selectionHint.textContent="选择单位后，可同步给游戏内召唤快捷键。";
  else if(SpawnUI.needsReload(selectedUnit(),rawGame()))selectionHint.textContent="新召唤许可已部署；请在 UE4SS 点一次 Restart All Mods，等游戏确认后即可试召唤。";
  else if(selectedUnit().validation_status==="unverified")selectionHint.textContent="未验证，暂不可直接召唤；可继续浏览目录。";
  else if(!payload)selectionHint.textContent="当前单位尚不可尝试召唤，或数量不是 1 到 8。";
  else if(!gameOnline())selectionHint.textContent="游戏未连接；此选择尚未同步到游戏快捷键。";
  else if(selectionConfirmed(payload))selectionHint.textContent=`游戏已确认：快捷键召唤当前单位 ×${payload.count}，${{blue:"蓝队",red:"红队",neutral:"暂不配队"}[payload.team]}。`;
  else if(state.selectionError)selectionHint.textContent=`选择同步未确认：${state.selectionError} 再点一次单位可重试。`;
  else selectionHint.textContent="正在同步选择；游戏回报确认前，快捷键可能仍使用之前的单位。";
}
function updateControls() {
  const online=gameOnline();
  const cap=Number(rawGame().arena_max_units??2),atLimit=cap>0&&Number(rawGame().arena_owned_records??rawGame().total)>=cap;
  $("spawn").disabled=!gameReady()||!selectionPayload()||state.busy.has("spawn")||atLimit;
  const selected=selectedUnit();
  $("spawn").textContent=!selected?"请先选择单位":!truth(selected.spawnable)?"目录参考：暂不可召唤":SpawnUI.needsReload(selected,rawGame())?"等待重载 Mod 启用":atLimit?"等待重载取消旧数量限制":SpawnUI.hasSpawnObservation(selected)?"召唤所选单位":"尝试召唤所选单位";
  if(selected)$("count").max=String(SpawnUI.maxCount(selected,rawGame()));
  $("clear-neutral").disabled=!online||rawGame().spawn_mode!=='all_catalog'||state.busy.has('clear_neutral')||pending('clear_neutral');
  $("start").disabled=!gameReady()||state.busy.has("start"); $("stop").disabled=!online||state.busy.has("stop");
  const spectator=rawGame().spectator_enabled;
  const spectatorKnown=online&&(spectator===true||spectator===false||spectator==="true"||spectator==="false");
  const spectatorEnabled=spectator===true||spectator==="true";
  const spectatorPending=state.busy.has("toggle_spectator")||pending("toggle_spectator");
  const flag=rawGame().spectator_flag_readback;
  const canBeTargeted=flag===true||flag==="true", cannotBeTargeted=flag===false||flag==="false";
  const restoring=!spectatorEnabled&&(Number(rawGame().spectator_pending_relations)>0||Number(rawGame().spectator_pending_flags)>0);
  const confirmed=spectatorKnown&&!restoring&&(spectatorEnabled?cannotBeTargeted:canBeTargeted);
  const observerActive=online&&truth(rawGame().arena_free_camera);
  const cameraSupported=Number(rawGame().function_keys_schema)===2;
  $("toggle-camera").disabled=!cameraSupported||(!gameReady()&&!observerActive)||state.busy.has('toggle_camera')||pending('toggle_camera');
  $("exit-camera").disabled=!online||!cameraSupported||state.busy.has('exit_camera')||pending('exit_camera');
  $("toggle-camera").textContent=observerActive?'退出自由观战（恢复原状态）':'进入自由观战（无仇恨＋隐身＋无敌锁血）';
  $("toggle-spectator").disabled=!gameReady()||spectatorPending||restoring||observerActive;
  $("toggle-spectator").textContent=spectatorPending?"无仇恨观战（等待回执）":!spectatorKnown?"切换无仇恨观战（状态未知）":restoring?"无仇恨观战（正在恢复）":spectatorEnabled?(confirmed?"关闭无仇恨观战（已开启）":"关闭无仇恨观战（生效待确认）"):(confirmed?"开启无仇恨观战（已关闭）":"开启无仇恨观战（关闭状态待确认）");
  $("toggle-spectator").setAttribute("aria-pressed",confirmed?String(spectatorEnabled):"mixed");
  if(observerActive)$("toggle-spectator").textContent='无仇恨观战（自由镜头保持中）';
  let observerState=$("observer-state");
  if(!observerState){observerState=document.createElement('p');observerState.id='observer-state';observerState.className='hint';$("toggle-spectator").after(observerState);}
  observerState.hidden=!observerActive;
  observerState.textContent=truth(rawGame().observer_health_verified)?'观战保护：生命下限已确认，退出镜头后恢复。':rawGame().observer_message||'观战保护状态待确认。';
  const matchReady=online&&state.status?.stat_match_supported===true&&truth(rawGame().stat_match_supported);
  const matchEnabled=truth(rawGame().stat_match_enabled),matchPending=state.busy.has('toggle_stat_match')||pending('toggle_stat_match');
  $("toggle-stat-match").disabled=!matchReady||matchPending;
  $("toggle-stat-match").textContent=!online?'数值统一（等待连接）':state.status?.stat_match_supported!==true?'数值统一（等待面板后台更新）':!truth(rawGame().stat_match_supported)?'数值统一（等待重载 Mod）':matchPending?'数值统一（等待回执）':matchEnabled?'关闭数值统一（已开启）':'开启数值统一（已关闭）';
  $("toggle-stat-match").setAttribute('aria-pressed',matchReady?String(matchEnabled):'mixed');
  const base=rawGame().stat_match_baseline_unit,baseUnit=state.byId.get(base);
  $("stat-match-baseline").textContent=base?`基准：${baseUnit?displayTitle(baseUnit):base.split('.').pop().replace(/_C$/,'')}`:matchEnabled?'等待第一只有效战斗单位作为基准。':'开启后，第一只有效战斗单位作为基准。';
  const statNumber=value=>Number.isFinite(Number(value))?Number(value).toLocaleString('zh-CN',{maximumFractionDigits:2}):'—';
  $("stat-match-values").textContent=base?`生命 ${statNumber(rawGame().stat_match_health)} · 杀气 ${statNumber(rawGame().stat_match_shachi)} · 攻击 ${statNumber(rawGame().stat_match_attack)} · 削杀气 ${statNumber(rawGame().stat_match_shachi_attack)}`:'';
  $("stat-match-state").textContent=matchReady?(Number(rawGame().stat_match_failures)>0?'存在未统一成功的单位，仍保留原生数值；具体结果见操作记录。':base?`后续已对齐 ${rawGame().stat_match_count||0} 只；战斗中照常消耗生命和杀气。`:rawGame().stat_match_message||''):'';
  $("refresh").disabled=!online||state.busy.has("refresh_catalog")||pending("refresh_catalog")||rawGame().catalog_state==="scanning";
  FunctionShortcuts.paint();
  renderSelectionState();
}
function requestSelectionSync(retry=false) {
  clearTimeout(state.selectionTimer);
  if(retry){state.selectionError="";state.submittedSelection="";}
  renderSelectionState(); if(!gameOnline())return;
  state.selectionTimer=setTimeout(syncSelection,200);
}
async function syncSelection() {
  const payload=selectionPayload(), wanted=signature(payload);
  if(!gameOnline()||!payload||selectionConfirmed(payload)||wanted===state.submittedSelection){renderSelectionState();return;}
  if(state.selectionSending){requestSelectionSync();return;}
  state.selectionSending=true; state.submittedSelection=wanted; state.selectionError="";
  try {
    const result=await post("/api/command",{action:"select_unit",...payload}); state.selectionJob=result.id; await poll();
  } catch(error) { state.selectionError=error.message; }
  finally { state.selectionSending=false;renderSelectionState();if(signature(selectionPayload())!==wanted)requestSelectionSync(); }
}
function selectUnit(unit,fromUser=true) {
  state.selected=unit.id; try{localStorage.setItem("pg-selected-unit",unit.id);}catch{}
  $("selected-name").textContent=displayTitle(unit); $("selected-category").textContent=[CatalogBrowser.typeLabel(unit.browse_type||unit.category||"未分类"),unit.species_label].filter(Boolean).join(" · ");
  $("selected-location").textContent=CatalogBrowser.affiliation(unit)+(unit.map_id?"（图鉴归属）":"");
  $("selected-configured").textContent=unit.configured_spawner_count>0?`刷怪配置证据：${(unit.configured_map_names||unit.configured_maps||[]).join("、")||"地图未读回"}；${unit.configured_spawner_count} 条配置样本（仅已读取场景）`:"暂无地图刷怪配置证据；不等于不会出现。";
  $("selected-basis").textContent=[unit.browse_type_basis,SpawnUI.description(unit,rawGame())].filter(Boolean).join("；");
  $("selected-internal").textContent=`内部名：${unit.internal_name||unit.name||unit.id}`;
  $("selected-path").textContent=[unit.class_path||unit.id,unit.disk_file?`磁盘资源：${unit.disk_file.file_path}`:""].filter(Boolean).join("\n"); $("selected-reason").textContent=[...(unit.trait_labels||[]),unit.validation_status==="controlled_test"?SpawnUI.description(unit,rawGame()):unit.reason].filter(Boolean).join("；"); $("unit-icon").textContent="◈";
  $("count").max=String(SpawnUI.maxCount(unit,rawGame()));if(Number($("count").value)>SpawnUI.maxCount(unit,rawGame()))$("count").value="1";
  updateControls(); for(const tile of document.querySelectorAll(".unit"))tile.classList.toggle("selected",tile.dataset.id===unit.id);
  if(fromUser)requestSelectionSync(true);
}

function taxonomyOptions(id,placeholder,entries){
  const select=$(id),old=select.value,fragment=document.createDocumentFragment();
  const all=element("option","",placeholder);all.value="";fragment.append(all);
  for(const entry of entries){const option=element("option","",entry.label);option.value=entry.value;fragment.append(option);}
  select.replaceChildren(fragment);select.value=entries.some(entry=>entry.value===old)?old:"";
}
function updateTaxonomyFilters(){
  const view=$("catalog-view").value,files=view==="files";DiskBrowser.show(files);if(files)return;
  const primary=view==="primary",disk=view==="disk";
  $("special-option").hidden=primary;
  const scope=state.units.filter(unit=>(!primary||unit.codex_entry_kind==="primary")&&(!disk||unit.disk_verified_unit===true));
  $("taxonomy-note").textContent=disk?"按原生图鉴归属分章节和地图。小怪对应原生普通敌人，尚未细分精英；无官方归属的角色显示待查。这里的单位已在现有目录中。":"默认只显示游戏图鉴直接列出的角色。地图是图鉴归属，不代表全部出现地点；小怪对应原生普通敌人，尚未细分精英。";
  const chapters=new Map();
  let noChapter=0;
  for(const unit of scope){
    if(unit.chapter_id){
      const old=chapters.get(unit.chapter_id)||{value:unit.chapter_id,name:unit.chapter_name||unit.chapter_id,order:unit.chapter_order??1000000,count:0};
      old.count++;chapters.set(unit.chapter_id,old);
    }else noChapter++;
  }
  const chapterOptions=[...chapters.values()].sort((a,b)=>a.order-b.order||a.value.localeCompare(b.value)).map(v=>({value:v.value,label:`${v.name}（${v.count}）`}));
  if(noChapter)chapterOptions.push({value:CatalogBrowser.unknown,label:`未标注章节（${noChapter}）`});
  taxonomyOptions("chapter","全部章节",chapterOptions);
  const chapter=$("chapter").value,maps=new Map();let noMap=0;
  for(const unit of scope){
    if(chapter&&(chapter===CatalogBrowser.unknown?!!unit.chapter_id:unit.chapter_id!==chapter))continue;
    if(unit.map_id){
      const item=maps.get(unit.map_id)||{value:unit.map_id,name:unit.map_name||unit.map_id,chapterOrder:unit.chapter_order??unit.map_order??1000000,order:unit.map_order??1000000,count:0};
      item.count++;maps.set(unit.map_id,item);
    }else noMap++;
  }
  const mapNames=new Map();for(const item of maps.values())mapNames.set(item.name,(mapNames.get(item.name)||0)+1);
  const mapOptions=[...maps.values()].sort((a,b)=>a.chapterOrder-b.chapterOrder||a.order-b.order||a.value.localeCompare(b.value)).map(v=>({value:v.value,label:`${v.name}${mapNames.get(v.name)>1?` · ${v.value}`:""}（${v.count}）`}));
  if(noMap)mapOptions.push({value:CatalogBrowser.unknown,label:`地图待查（${noMap}）`});
  taxonomyOptions("map","全部地图",mapOptions);
  const selectedMap=$("map").value,types=new Map();
  for(const unit of scope){
    if(chapter&&(chapter===CatalogBrowser.unknown?!!unit.chapter_id:unit.chapter_id!==chapter))continue;
    if(selectedMap&&(selectedMap===CatalogBrowser.unknown?!!unit.map_id:unit.map_id!==selectedMap))continue;
    const type=unit.browse_type||"待分类";types.set(type,(types.get(type)||0)+1);
  }
  taxonomyOptions("category","全部类型",[...types].map(([value,count])=>({value,label:`${CatalogBrowser.typeLabel(value)}（${count}）`})));
}

const previousPage=element("button","text-button","上一页");previousPage.type="button";previousPage.hidden=true;
$("more").insertAdjacentElement("beforebegin",previousPage);$("more").textContent="下一页";
async function renderCatalogue() {
  if($("catalog-view").value==="files"){await DiskBrowser.render(api);return;}
  const token=++state.renderToken;
  const filters={query:$("search").value.trim().toLocaleLowerCase(),type:$("category").value,only:$("available-only").checked,
    showSpecial:$("show-special").checked,view:$("catalog-view").value,chapter:$("chapter").value,map:$("map").value,configured:$("configured-only").checked};
  const key=JSON.stringify([state.catalogVersion,filters]);
  if(state.filterKey!==key){
    const filtered=[];
    for(let index=0;index<state.units.length;index++){
      const unit=state.units[index];
      if(CatalogBrowser.matches(unit,filters))filtered.push(unit);
      if(index>0&&index%1000===0){await yieldUI();if(token!==state.renderToken)return;}
    }
    filtered.sort(CatalogBrowser.compare);state.filtered=filtered;state.filterKey=key;
  }
  if(token!==state.renderToken)return;
  const filtered=state.filtered;
  state.page=Math.min(state.page,Math.max(0,Math.ceil(filtered.length/PAGE_SIZE)-1));
  const begin=state.page*PAGE_SIZE,fragment=document.createDocumentFragment();
  if(!filtered.length){
    const empty=element("div","empty");
    empty.append(element("span","empty-mark","◇"),element("h3","",state.units.length?"没有符合条件的单位":"还没有读取到单位"),element("p","",state.units.length?"试试更短的名称，或切换分类。":"点击右上角“扫描游戏目录”，读取游戏中的单位。"));fragment.append(empty);
  }else {
   let previousGroup=null;
   for(const unit of filtered.slice(begin,begin+PAGE_SIZE)){
    const group=CatalogBrowser.groupKey(unit);
    if(group!==previousGroup){
      const heading=element("div","catalog-group");heading.append(element("h3","",CatalogBrowser.affiliation(unit)));
      const size=filtered.filter(item=>CatalogBrowser.groupKey(item)===group).length;
      heading.append(element("span","",`${size} 个条目`));fragment.append(heading);previousGroup=group;
    }
    const button=element("button",`unit${unit.id===state.selected?" selected":""}`);button.type="button";button.dataset.id=unit.id;
    const type=unit.browse_type||unit.category;
    const top=element("div","unit-top");top.append(element("span",`unit-type${type==="BOSS"?" boss":type==="普通敌人"?" mob":""}`,CatalogBrowser.typeLabel(type)),element("span","",unit.codex_entry_kind==="primary"?"主图鉴":unit.codex_entry_kind==="alias"?"图鉴别名":"候选资产"));
    const bottom=element("div","unit-footer");bottom.append(element("span",`tag${SpawnUI.canAttempt(unit,rawGame())?"":" warn"}`,permissionLabel(unit)));
    button.append(top,element("div","unit-name",displayTitle(unit)));
    if(filters.view!=="primary"||unit.same_name_count>1)button.append(element("small","muted",unit.internal_name||unit.name));
    button.append(element("small","muted",unit.species_label||unit.name_source_label||"分类待核"),bottom);button.addEventListener("click",()=>selectUnit(unit));
    const card=element('div','unit-card');card.append(button,UnitShortcuts.render(unit));fragment.append(card);
   }
  }
  $("catalog").replaceChildren(fragment);
  UnitShortcuts.paint();
  const end=Math.min(begin+PAGE_SIZE,filtered.length);
  $("shown-count").textContent=`${filters.view==="primary"?"主图鉴":filters.view==="disk"?"磁盘单位":"全部候选"} ${filtered.length} 个条目 · 显示 ${filtered.length?begin+1:0}–${end}`;
  previousPage.hidden=state.page===0;$("more").hidden=end>=filtered.length;
}
async function loadCatalogue() {
  const data=await api("/api/catalog"),source=Array.isArray(data.units)?data.units:[];
  state.unitKeyServer=data.unit_shortcuts_supported===true;
  const fields=["id","name","category","class_path","loaded","spawnable","reason","display_name","internal_name","name_source","name_source_label","validation_status","max_count","is_special","species_label","trait_labels",
    "codex_entry_kind","browse_type","browse_type_basis","canonical_class_path","map_id","map_name","chapter_id","chapter_name","chapter_order","map_order","codex_order","level_name","map_status","same_name_count","resolved_unit_kind","inheritance_verified","configured_maps","configured_map_names","configured_spawner_count","unit_shortcut"];
  let same=source.length===state.units.length;
  for(let index=0;same&&index<source.length;index++){
    same=fields.every(field=>(source[index][field]!==null&&typeof source[index][field]==='object')?JSON.stringify(source[index][field])===JSON.stringify(state.units[index][field]):(field==="category"?source[index][field]||"未分类":source[index][field])===state.units[index][field]);
    if(index>0&&index%1000===0)await yieldUI();
  }
  state.catalogFetchedAt=Date.now();state.catalogTotal=data.total??source.length;state.forceCatalog=false;if(same)return;
  const units=[],byId=new Map();
  const disk=DiskUnits.build(typeof DiskUnitFiles==="undefined"?null:DiskUnitFiles,source,{limit:source.length});
  const diskByClass=new Map((disk.files||[]).map(file=>[file.unit.class_path,file]));state.diskSummary=disk.unit_summary||null;
  for(let index=0;index<source.length;index++){
    // Also normalize responses from a panel service started before the terminology correction.
    const sourceUnit=source[index],raw={...sourceUnit,species_label:sourceUnit.species_label==='GuaiMian类（术语待核）'?'怪面类':sourceUnit.species_label};
    const diskFile=diskByClass.get(raw.class_path),unit={...raw,category:raw.category||"未分类",searchText:unitSearchText(raw),disk_file:diskFile,disk_verified_unit:!!diskFile};
    units.push(unit);byId.set(unit.id,unit);if(index>0&&index%1000===0)await yieldUI();
  }
  state.units=units;state.byId=byId;state.catalogVersion++;
  updateTaxonomyFilters();
  let saved=state.selected;if(!saved){try{saved=localStorage.getItem("pg-selected-unit");}catch{}}
  const selected=byId.get(saved);
  if(selected){selectUnit(selected,false);requestSelectionSync();}
  else if(state.selected){state.selected=null;$("selected-name").textContent="所选单位已不在目录";$("selected-internal").textContent="";$("selected-path").textContent="";$("selected-reason").textContent="请重新选择。";}
  await renderCatalogue();updateControls();
}
function renderQueue(queue) {
  const list=$("jobs");list.replaceChildren();if(!queue?.length){list.append(element("li","empty-job","暂无操作"));return;}
  for(const job of [...queue].sort((a,b)=>b.id-a.id).slice(0,20)){
    const li=element("li");li.append(element("span",`job-state ${job.status}`,labels[job.status]||job.status),element("span","",actions[job.action]||job.action),element("span","job-message",job.message||"等待游戏处理"));list.append(li);
  }
}
function renderStatus(data) {
  const wasOnline=gameOnline();state.status=data;state.csrf=data.csrf_token||state.csrf;
  const game=data.game||{},raw=rawGame(),scanning=raw.catalog_state==="scanning";
  const teamRevision=String(raw.game_session||'')+':'+String(raw.arena_team_revision??0);
  if(game.online&&teamRevision!==state.teamRevision&&['blue','red','neutral'].includes(raw.current_team)){
    state.teamRevision=teamRevision;$("team").value=raw.current_team;
    state.selectionError='';state.submittedSelection='';
    if(Number(raw.arena_team_revision)>0)toast('召唤队伍：'+({blue:'蓝队',red:'红队',neutral:'暂不配队'})[raw.current_team]);
  }
  const teamKey=UnitShortcuts.parseBinding(raw.key_cycle_team);
  $("team-key-hint").textContent=game.online&&teamKey.key_code?`${UnitShortcuts.label(teamKey.key_code,teamKey.modifiers)} 切队：蓝队 → 红队 → 暂不配队。只影响之后的召唤。`:'切队快捷键未绑定；可在上方选择队伍。';
  const keyRevision=String(raw.unit_keys_epoch||'')+':'+String(raw.unit_keys_revision||0);
  if(keyRevision!==state.unitKeyRevision){state.unitKeyRevision=keyRevision;state.forceCatalog=true;}
  const keyEvent=String(raw.unit_keys_epoch||'')+':'+String(raw.unit_keys_event||0);
  if(keyEvent!==state.unitKeyEvent){state.unitKeyEvent=keyEvent;const unit=state.byId.get(raw.unit_keys_last_unit);if(unit&&raw.current_unit===unit.id)selectUnit(unit,false);if(Number(raw.unit_keys_event)>0&&raw.unit_keys_message)toast(raw.unit_keys_message);}
  UnitShortcuts.observe(data.queue);
  $("unit-key-help").textContent=state.unitKeyServer&&raw.unit_keys_epoch?'卡片键框：点击后按键，Esc 取消，× 清除。召唤沿用当前队伍与数量；现有功能键不会被覆盖。':'单位快捷键等待新版后台与游戏模块连接；默认均未绑定。';
  const policy=String(raw.spawn_mode||raw.spawn_trial_policy||''),policyChanged=policy!==state.trialPolicy;state.trialPolicy=policy;
  const available=state.units.filter(unit=>SpawnUI.canAttempt(unit,raw)).length;
  const waiting=state.units.filter(unit=>truth(unit.spawnable)&&SpawnUI.needsReload(unit,raw)).length;
  $("spawn-help-text").textContent=waiting?`${waiting} 个目录条目等待游戏重载新模式。`:`${available} 个目录条目开放尝试召唤 · 每次1–8只 · 总量不设上限。`;
  $("connection").classList.toggle("online",!!game.online);$("connection-text").textContent=game.online?"游戏已连接":"等待游戏连接";
  $("game-notice").classList.toggle("connected",!!game.online);
  $("game-notice").textContent=data.transport_error||(game.online?(scanning?`正在读取游戏单位目录… ${raw.catalog_message||""}`:((game.message||raw.message)==="bridge ready"?(data.catalog?.total?"游戏已连接，可按章节和地图浏览单位。":"连接已就绪，请点击右上角“扫描游戏目录”。"):(game.message||raw.message||"游戏端已连接，可以选择单位并召唤。"))):"游戏端尚未连接。请启动游戏并加载新版 Mod；若游戏已开，点 UE4SS 的 Restart All Mods。");
  const codexErrors=data.catalog?.codex_errors?.length||0;
  $("catalog-summary").textContent=`主图鉴 ${data.catalog?.primary_count??0} 个角色 · 全部候选 ${data.catalog?.total??state.units.length} 条${scanning?" · 目录扫描中":""}${codexErrors?` · ${codexErrors}条图鉴证据异常`:""}`;
  const inventory=data.catalog?.inventory_audit;
  $("inventory-summary").textContent=$("catalog-view").value==="disk"?(state.diskSummary?`磁盘已核对 ${state.diskSummary.verified} 个单位／角色类，其中 ${state.diskSummary.by_kind.npc||0} 个 NPC 类。另有 ${state.diskSummary.candidates} 个身份待核对候选留在“全部资产候选”。`:"磁盘单位索引尚未就绪。"):
    inventory?.inventory_verified?`已核对 ${Number(inventory.asset_count).toLocaleString()} 条已挂载资产 · ${data.catalog?.configured_count||0} 个类有刷怪配置证据。未加载地图的刷怪配置尚未全覆盖。`:"完整资产核对尚无已确认结果。";
  $("blue-count").textContent=raw.blue_count??"—";$("red-count").textContent=raw.red_count??"—";
  $("neutral-count").textContent=raw.neutral_count??"—";
  $("arena-count-note").textContent=`死亡待清理 ${raw.arena_dead_count??0} · 存活状态未确认 ${raw.arena_unreadable_count??0}`;
  $("neutral-note").textContent=`登记 ${raw.neutral_owned_records??raw.neutral_count??0} 个（含待清理实体）；只清理本 Mod 生成的未配队单位。`;
  if(state.catalogState==="scanning"&&!scanning)state.forceCatalog=true;state.catalogState=raw.catalog_state||"";
  const selectionJob=findJob(state.selectionJob);if(selectionJob&&["failed","uncertain"].includes(selectionJob.status))state.selectionError=selectionJob.message||labels[selectionJob.status];
  FunctionShortcuts.observe(data.function_keys,data.queue);
  renderQueue(data.queue);updateControls();if(!wasOnline&&gameOnline())requestSelectionSync();
  if(policyChanged){if(selectedUnit()){selectUnit(selectedUnit(),false);requestSelectionSync(true);}renderCatalogue();}
}
async function send(action,payload={}) {
  if(!gameOnline()){toast("游戏未连接，未发送操作。");return;}if(state.busy.has(action))return;
  if(["spawn","start","toggle_spectator"].includes(action)&&!gameReady()){toast("等待游戏进入地图并确认就绪，未发送操作。");return;}
  state.busy.add(action);updateControls();
  try{const data=await post("/api/command",{action,...payload});toast(data.message||"已加入队列，等待游戏回执");await poll();}
  catch(error){toast(error.message);}finally{state.busy.delete(action);updateControls();}
}
function poll() {
  if(state.pollPromise)return state.pollPromise;
  state.pollPromise=(async()=>{
    try{
      const data=await api("/api/status");renderStatus(data);
      // No full 20k-row download/stringify on each heartbeat.
      if(state.forceCatalog||state.catalogTotal!==data.catalog?.total||Date.now()-state.catalogFetchedAt>10000){
        try{await loadCatalogue();}catch(error){$("catalog-summary").textContent=`目录暂不可读：${error.message}`;}
      }
    }catch(error){$("connection").classList.remove("online");$("connection-text").textContent="本地服务未连接";$("game-notice").textContent=error.message;state.status=null;updateControls();}
  })().finally(()=>{state.pollPromise=null;});return state.pollPromise;
}

let searchTimer;
UnitShortcuts.init({unit:id=>state.byId.get(id),available:()=>state.unitKeyServer&&gameOnline()&&!!rawGame().unit_keys_epoch,
  units:()=>state.units,status:rawGame,functions:()=>state.status?.function_keys?.bindings||{},cancelOther:()=>FunctionShortcuts.cancel(),refreshBindings:async()=>{state.forceCatalog=true;await poll();},
  request:(unit_id,key_code,modifiers)=>post('/api/command',{action:'configure_unit_key',unit_id,key_code,modifiers}),
  refresh:()=>poll(),changed:()=>{state.forceCatalog=true;},notify:toast});
FunctionShortcuts.init({units:()=>state.units,available:()=>gameOnline(),
  request:bindings=>post('/api/keybinds',bindings),refresh:()=>poll(),changed:()=>{state.forceCatalog=true;},notify:toast});
DiskBrowser.bind();
$("search").addEventListener("input",()=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>{state.page=0;renderCatalogue();},120);});
$("category").addEventListener("change",()=>{if(state.units.some(u=>u.browse_type===$("category").value&&u.is_special))$("show-special").checked=true;state.page=0;renderCatalogue();});$("available-only").addEventListener("change",()=>{state.page=0;renderCatalogue();});
$("configured-only").addEventListener("change",()=>{state.page=0;renderCatalogue();});
$("show-special").addEventListener("change",()=>{state.page=0;renderCatalogue();});
$("catalog-view").addEventListener("change",()=>{state.page=0;updateTaxonomyFilters();renderCatalogue();});
$("show-spawnable").addEventListener("click",()=>{$("search").value="";$("chapter").value="";$("map").value="";$("category").value="";$("configured-only").checked=false;$("available-only").checked=true;$("catalog-view").value="primary";state.page=0;updateTaxonomyFilters();renderCatalogue();});
$("chapter").addEventListener("change",()=>{state.page=0;$("map").value="";updateTaxonomyFilters();renderCatalogue();});
$("map").addEventListener("change",()=>{state.page=0;updateTaxonomyFilters();renderCatalogue();});
$("more").addEventListener("click",()=>{state.page++;renderCatalogue();});previousPage.addEventListener("click",()=>{state.page=Math.max(0,state.page-1);renderCatalogue();});
$("team").addEventListener("change",()=>{updateControls();requestSelectionSync(true);});$("count").addEventListener("input",()=>{updateControls();requestSelectionSync(true);});
$("refresh").addEventListener("click",()=>send("refresh_catalog"));
$("spawn").addEventListener("click",()=>{const payload=selectionPayload();if(!payload){toast("选择可尝试召唤的单位，数量填写 1 到 8。");return;}send("spawn",payload);});
$("start").addEventListener("click",()=>send("start"));$("stop").addEventListener("click",()=>send("stop"));
$("clear-neutral").addEventListener("click",()=>send("clear_neutral"));
$("toggle-spectator").addEventListener("click",()=>send("toggle_spectator"));
$("toggle-camera").addEventListener("click",()=>send("toggle_camera"));
$("exit-camera").addEventListener("click",()=>send("exit_camera"));
$("toggle-stat-match").addEventListener("click",()=>send("toggle_stat_match"));
$("toggle-keys").addEventListener("click",()=>{const expanded=$("toggle-keys").getAttribute("aria-expanded")==="true";$("keys-panel").hidden=expanded;$("toggle-keys").setAttribute("aria-expanded",String(!expanded));$("toggle-keys").querySelector("span").textContent=expanded?"＋":"−";});
updateControls();
async function pollingLoop(){await poll();setTimeout(pollingLoop,500);}
pollingLoop();
