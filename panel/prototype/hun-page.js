"use strict";
window.PGHun=(()=>{
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]);
  const clone=x=>JSON.parse(JSON.stringify(x));
  let data=null,draft=null,dirty=false,loading=false,epoch=0,phaseSerial=0,kind='main_weapon',query='',message='';
  const expanded=new Set();
  const kinds={main_weapon:'主武器',shadow_armament:'影之武装',accessory:'饰品',resource_weapon:'表外武器配置',resource_armament:'表外武装配置'};
  const root=()=>document.querySelector('#hun-page');
  function html(){return '<div id="hun-page"><h1>粪怪 · 魂</h1><p class="muted">正在读取独立角色方案…</p></div>';}
  function progress(){return `<div class="hun-notice"><strong>开发中：配置与本体验证</strong><p>可编辑、保存、导入和导出方案。当前游戏入口仅验证魂的独立本体、可见性、阵营和清理；全套装备、饰品、成长与自动防御尚未应用，请勿将本体当作满配完成版。</p></div>`;}
  function attributeLabel(field){const key='stats.field.'+field,value=window.PG_I18N?.t(key);return value&&value!==key?value+' · '+field:field;}
  function overrides(group,label){
    const fields=group==='attributes'?data.attributes:Object.keys(data.ai_parameters),name=field=>group==='attributes'?attributeLabel(field):field;
    return `<details data-hun-details="${group}" ${expanded.has(group)?'open':''}><summary>${label} · ${Object.keys(draft[group]).length} 项覆盖</summary><p class="muted">未添加的项目使用角色预设。添加一项即可单独调整，删除后恢复预设。</p><div class="hun-toolbar"><select class="select" data-hun-add-name="${group}">${fields.map(field=>`<option value="${esc(field)}">${esc(name(field))}</option>`).join('')}</select><input class="input" type="number" step="any" data-hun-add-value="${group}" placeholder="数值"><button class="btn btn-secondary" data-hun-action="override-add" data-hun-group="${group}">添加或覆盖</button></div>${Object.entries(draft[group]).map(([field,value])=>`<div class="row"><div class="row-main">${esc(name(field))}：${value}</div><button class="btn btn-secondary btn-sm" data-hun-action="override-remove" data-hun-group="${group}" data-hun-key="${esc(field)}">恢复预设</button></div>`).join('')}</details>`;
  }
  function phases(){return `<details data-hun-details="phases" ${expanded.has('phases')?'open':''}><summary>阶段套路 · ${draft.phases.length}</summary><p class="muted">默认25%血线优先考虑黑魔伤，原生条件与次数仍适用。这里只保存阶段配置，全装备联动识别仍在开发。</p>${draft.phases.map((p,i)=>`<div class="hun-phase" data-hun-phase="${i}"><div class="hun-options"><label><input type="checkbox" data-hun-phase-field="enabled" ${p.enabled?'checked':''}>启用</label><label>阶段名称<input class="input" data-hun-phase-field="name" value="${esc(p.name)}" maxlength="60"></label><label>剩余血量 ≤ %<input class="input" type="number" min="1" max="100" data-hun-phase-field="health_below" value="${p.health_below*100}"></label><label>优先武器<select class="select" data-hun-phase-field="weapon_id">${data.catalog.items.filter(r=>r.kind==='main_weapon').map(r=>`<option value="${r.id}" ${r.id===p.weapon_id?'selected':''}>${esc(r.name)}</option>`).join('')}</select></label><label>优先级<input class="input" type="number" min="0" max="1000" data-hun-phase-field="priority" value="${p.priority}"></label><label><input type="checkbox" data-hun-phase-field="once" ${p.once?'checked':''}>每场只触发一次</label><button class="btn btn-secondary btn-sm" data-hun-action="phase-remove" data-hun-index="${i}">删除阶段</button></div></div>`).join('')}<button class="btn btn-secondary" data-hun-action="phase-add" ${draft.phases.length>=16?'disabled':''}>添加阶段</button></details>`;}
  function equipment(){
    const items=data.catalog.items.filter(r=>r.kind===kind && (!query || (r.name+' '+r.native_id).toLowerCase().includes(query.toLowerCase())));
    return `<div class="hun-equipment-head"><select class="select" data-hun-category>${Object.entries(kinds).map(([id,label])=>`<option value="${id}" ${id===kind?'selected':''}>${label} · ${data.catalog.items.filter(r=>r.kind===id).length}</option>`).join('')}</select><input class="input" data-hun-search placeholder="搜索名称或编号" value="${esc(query)}"><button class="btn btn-secondary" data-hun-action="all-on">本类全开</button><button class="btn btn-secondary" data-hun-action="all-off">本类全关</button></div>
      <p class="muted">保留同名和剧情变体。表内武器等级范围按原生上限与升级表核对；表外配置仅代表发现资源，等级、获取方式与 NPC 兼容性仍待核查。</p>
      <div class="hun-item-list">${items.map(r=>{const value=draft.items[r.id];return `<div class="hun-item" data-hun-id="${r.id}"><label class="hun-item-name"><input type="checkbox" data-hun-field="enabled" ${value.enabled?'checked':''}>${esc(r.name)}<small>${r.source==='resource_only'?'仅资源配置 · 获取待核':'游戏数据表记录'} · NPC 适配待验证</small></label><label>等级<input class="input" type="number" min="1" max="${r.level_max || 1}" data-hun-field="level" placeholder="${r.level_max?'留空最高 '+r.level_max:'最高等级待核'}" value="${value.level==='max'?'':value.level}" ${r.level_max?'':'disabled'}></label><label><input type="checkbox" data-hun-field="soul" ${value.soul?'checked':''} ${r.soul_option?'':'disabled'}>${r.soul_option?'铸魂':'铸魂不适用'}</label><label>权重<input class="input" type="number" min="0" max="1000" step="0.1" data-hun-field="weight" value="${value.weight}"></label></div>`;}).join('')}</div>`;
  }
  function render(){
    const el=root();if(!el || !data || !draft)return;
    for(const section of el.querySelectorAll('[data-hun-details]')){if(section.open)expanded.add(section.dataset.hunDetails);else expanded.delete(section.dataset.hunDetails);}
    el.innerHTML=`<h1>粪怪 · 魂</h1><p class="muted">独立 NPC 方案，只作用于之后召唤的实例。默认全部顶配、全饰品效果开启，玩家可逐项削弱。</p>${progress()}
      <section class="card"><div class="card-body hun-toolbar"><label>方案名称<input class="input" data-hun-name maxlength="60" value="${esc(draft.name)}"></label><button class="btn btn-primary" data-hun-action="save" ${loading?'disabled':''}>保存方案</button><button class="btn btn-secondary" data-hun-action="export">导出方案</button><label class="btn btn-secondary">导入方案<input type="file" data-hun-import accept=".json,application/json" hidden></label><button class="btn btn-secondary" data-hun-action="reset">恢复全部顶配</button><button class="btn btn-secondary" data-hun-action="reload">重新载入</button><span id="hun-dirty">${dirty?'有未保存修改':'已保存版本 '+data.revision}</span></div></section>
      <section class="card"><div class="card-head"><h2 class="card-title">装备库</h2></div><div class="card-body" id="hun-equipment">${equipment()}</div></section>
      <section class="card"><div class="card-head"><h2 class="card-title">策略、资源与生存</h2></div><div class="card-body">
        <div class="hun-options">${[['deflect_chance','精防尝试概率'],['red_dodge_chance','红光闪避尝试概率'],['counter_chance','反击倾向']].map(([field,label])=>`<label>${label}<input class="input" data-hun-ai="${field}" type="number" min="0" max="1" step="0.05" value="${draft.ai[field]}"></label>`).join('')}
        <label>重复招式<select class="select" data-hun-policy><option value="soft" ${draft.ai.repeat_policy==='soft'?'selected':''}>软限制，紧急情况允许重复</option><option value="none" ${draft.ai.repeat_policy==='none'?'selected':''}>不限制</option></select></label>
        <label><input type="checkbox" data-hun-late ${draft.ai.late_weapon_bias?'checked':''}>后期武器优先（获得阶段仍待核查）</label>
        <label>血药数量<input class="input" data-hun-medicine value="${draft.resources.medicine_count==='native_max'?'':draft.resources.medicine_count}" placeholder="原版最高携带量" type="number" min="0" max="10000"></label>
        <label><input type="checkbox" data-hun-resource="consume_medicine" ${draft.resources.consume_medicine?'checked':''}>血药正常消耗</label><label><input type="checkbox" data-hun-resource="consume_skill_resources" ${draft.resources.consume_skill_resources?'checked':''}>技能资源正常消耗</label>
        <label>冷却倍率<input class="input" data-hun-cooldown type="number" min="0" max="10" step="0.1" value="${draft.resources.cooldown_scale}"></label>
        ${[['grab','抓取'],['execution','处决'],['lethal','原版致死']].map(([field,label])=>`<label>${label}<select class="select" data-hun-survival="${field}"><option value="native" ${draft.survival[field]==='native'?'selected':''}>遵循原版</option><option value="immune" ${draft.survival[field]==='immune'?'selected':''}>免疫</option></select></label>`).join('')}</div>
        <p class="muted">默认先拉满原版永久成长再叠饰品，允许超过正常配装上限；精防和闪避仍受原生动作条件约束。当前这些设置仅保存，未应用到本体验证。</p>
        ${overrides('attributes','自定义角色属性')}${overrides('ai_parameters','原生 AI 参数')}${phases()}
      </div></section>
      <section class="card"><div class="card-head"><h2 class="card-title">独立本体验证</h2></div><div class="card-body"><p>此按钮仅测试魂的分身模板是否可见、可被攻击、能行动并正常清理。满配属性和配装尚未接入。配置改动不会影响已经召出的本体。</p><div class="hun-toolbar"><select class="select" data-hun-mode>${[['blue','蓝方'],['red','红方'],['neutral','挑战玩家'],['companion','随从']].map(([id,name])=>`<option value="${id}" ${draft.mode===id?'selected':''}>${name}</option>`).join('')}</select><label>数量<input class="input" data-hun-count min="1" max="100" type="number" value="${draft.count}"></label><button class="btn btn-secondary" data-hun-action="probe" ${loading?'disabled':''}>召唤本体验证</button></div></div></section>
      <p id="hun-message" role="status">${esc(message || data.error || '')}</p>`;
    if(loading)for(const field of el.querySelectorAll('input,select,textarea,button'))field.disabled=true;
  }
  async function mount(force=false){
    if(data && !force){render();return;}
    const rt=window.PGRuntime,token=++epoch;if(!rt.hun){if(root())root().innerHTML='<h1>粪怪 · 魂</h1>'+progress()+'<p>请使用桌面开发版读取方案和目录。</p>';return;}
    loading=true;
    try{const reply=await rt.hun.load();if(token!==epoch)return;data=reply;draft=clone(reply.profile);dirty=false;message=reply.error || '';}
    catch(e){message=e.message ||'方案读取失败';if(root())root().innerHTML='<h1>粪怪 · 魂</h1><p>'+esc(message)+'</p>';}
    finally{if(token===epoch){loading=false;render();}}
  }
  function mark(){dirty=true;const el=document.querySelector('#hun-dirty');if(el)el.textContent='有未保存修改';}
  function collect(){
    if(!root()||!draft)return;
    const get=s=>root().querySelector(s),next=clone(draft);
    next.name=get('[data-hun-name]').value;
    for(const el of root().querySelectorAll('[data-hun-ai]'))next.ai[el.dataset.hunAi]=Number(el.value);
    next.ai.repeat_policy=get('[data-hun-policy]').value;next.ai.late_weapon_bias=get('[data-hun-late]').checked;
    next.resources.medicine_count=get('[data-hun-medicine]').value===''?'native_max':Number(get('[data-hun-medicine]').value);
    for(const el of root().querySelectorAll('[data-hun-resource]'))next.resources[el.dataset.hunResource]=el.checked;
    next.resources.cooldown_scale=Number(get('[data-hun-cooldown]').value);
    for(const el of root().querySelectorAll('[data-hun-survival]'))next.survival[el.dataset.hunSurvival]=el.value;
    next.mode=get('[data-hun-mode]').value;next.count=Number(get('[data-hun-count]').value);
    for(const row of root().querySelectorAll('[data-hun-phase]')){
      const phase=next.phases[Number(row.dataset.hunPhase)];
      for(const el of row.querySelectorAll('[data-hun-phase-field]')){
        const field=el.dataset.hunPhaseField;
        phase[field]=el.type==='checkbox'?el.checked:field==='health_below'?Number(el.value)/100:field==='priority'?Number(el.value):el.value;
      }
    }
    draft=next;
  }
  async function action(name,button){
    if(loading || !data)return;
    try{
      collect();
      if(name==='reload'){await mount(true);return;}
      if(name==='reset'){draft=clone(data.defaults);mark();render();return;}
      if(name==='override-add'||name==='override-remove'){
        const group=button.dataset.hunGroup;if(!['attributes','ai_parameters'].includes(group))throw new Error('未知属性分组');
        if(name==='override-remove')delete draft[group][button.dataset.hunKey];
        else{
          const field=root().querySelector(`[data-hun-add-name="${group}"]`).value,input=root().querySelector(`[data-hun-add-value="${group}"]`).value,value=Number(input);
          if(input.trim()===''||!Number.isFinite(value))throw new Error('请输入有限数值');
          draft[group][field]=value;
        }
        mark();render();return;
      }
      if(name==='phase-add'){
        if(draft.phases.length>=16)throw new Error('最多16个阶段');
        let id;do{id='phase_'+Date.now().toString(36)+'_'+(++phaseSerial);}while(draft.phases.some(p=>p.id===id));
        draft.phases.push({...clone(data.defaults.phases[0]),id,name:'阶段 '+(draft.phases.length+1),health_below:.5});mark();render();return;
      }
      if(name==='phase-remove'){draft.phases.splice(Number(button.dataset.hunIndex),1);mark();render();return;}
      if(name==='all-on'||name==='all-off'){for(const r of data.catalog.items)if(r.kind===kind)draft.items[r.id].enabled=name==='all-on';mark();render();return;}
      if(name==='export'){
        const blob=new Blob([JSON.stringify({format:'PhantomGladiatorHunProfile',version:1,profile:draft},null,2)],{type:'application/json'});
        const url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download='魂角色方案.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);return;
      }
      loading=true;render();
      if(name==='save'){
        const saved=await window.PGRuntime.hun.save({revision:data.revision,profile:draft});data={...data,...saved};draft=clone(saved.profile);dirty=false;message='方案保存已读回；只影响后续正式召唤，当前入口仍为本体验证。';
      } else if(name==='probe'){
        if(dirty)throw new Error('请先保存方案，或重新载入已保存版本。');
        const job=await window.PGRuntime.command('hun_body_probe',{team:draft.mode,count:draft.count,profile_revision:data.revision});
        message=job.message ||'本体验证指令已提交，结果以游戏回执为准。';
      }
    }catch(e){message=e.message ||'操作失败';}
    finally{loading=false;render();}
  }
  document.addEventListener('click',e=>{const button=e.target.closest('[data-hun-action]');if(button&&root()?.contains(button)){e.preventDefault();action(button.dataset.hunAction,button);}});
  document.addEventListener('change',async e=>{
    if(!root()?.contains(e.target)||!data||loading)return;
    const el=e.target;
    try{
      if(el.matches('[data-hun-import]')){
        const file=el.files[0];if(!file)return;if(file.size>262144)throw new Error('方案文件超过256 KiB');
        const revision=data.revision;loading=true;render();
        const text=await file.text();
        // Validate by saving on the backend, including revision, IDs, finite numbers and all fields.
        const saved=await window.PGRuntime.hun.save({revision,import_text:text});data={...data,...saved};draft=clone(saved.profile);dirty=false;message='方案已导入并保存；不修改场上已有实例。';loading=false;render();return;
      }
      if(el.matches('[data-hun-category]')){collect();kind=el.value;render();return;}
      if(el.dataset.hunField){
        const id=el.closest('[data-hun-id]').dataset.hunId,field=el.dataset.hunField;
        draft.items[id][field]=el.type==='checkbox'?el.checked:field==='level'&&el.value===''?'max':Number(el.value);
      }
      mark();
    }catch(err){loading=false;message=err.message;render();}
  });
  document.addEventListener('input',e=>{
    if(e.target.matches('[data-hun-search]')&&root()?.contains(e.target)){
      query=e.target.value;const box=root().querySelector('#hun-equipment'),focus=e.target.selectionStart;box.innerHTML=equipment();const input=box.querySelector('[data-hun-search]');input.focus();input.setSelectionRange(focus,focus);
    }
  });
  return {html,mount};
})();
