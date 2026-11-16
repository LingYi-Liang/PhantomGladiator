"use strict";
window.PGHun = (() => {
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]);
  const clone = x => JSON.parse(JSON.stringify(x));
  const categories = {main_weapon:'主武器', shadow_armament:'影之武装', accessory:'饰品', special:'特殊装备'};
  const tabs = {equipment:'装备库', attributes:'角色属性', strategy:'战斗策略', resources:'资源与生存', phases:'阶段套路'};
  const teams = {blue:'召唤到蓝方', red:'召唤到红方', companion:'召为随从', neutral:'与我对战'};
  let data, draft, baseline, undo, busy=false, epoch=0, serial=0, tab='equipment', category='main_weapon', query='', onlyOn=false;
  let notice='', noticeKind='', lastJob=null, pendingJob=null, subscribed=false, iconCache=null;
  const failedImages=new Set();
  const root=()=>document.querySelector('#hun-page'), rt=()=>window.PGRuntime;
  const changed=()=>draft && JSON.stringify(draft)!==baseline;
  const inCategory=r=>category==='special'?r.source==='resource_only':r.kind===category;
  const count=kind=>data.catalog.items.filter(r=>kind==='special'?r.source==='resource_only':r.kind===kind);
  const active=rows=>rows.filter(r=>draft.items[r.id].enabled).length;
  const displayName=r=>r.name+(r.variant?' · '+r.variant:'');
  const paths={sword:'M5 19l4-4m-3-3 6 6m-3-3L18 6l2-3-3 2-9 9M4 20l1-1',plus:'M12 5v14M5 12h14',check:'M5 12l4 4L19 6',search:'M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0',down:'M12 3v12m-5-5 5 5 5-5M5 16v5h14v-5',up:'M12 16V4m-5 5 5-5 5 5M5 16v5h14v-5',reset:'M4 10a8 8 0 1 1 1 8M4 4v6h6',close:'m6 6 12 12M6 18 18 6',shield:'M12 3 4 6v6c0 5 8 9 8 9s8-4 8-9V6Z'};
  const icon=name=>`<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${paths[name]||paths.sword}"/></svg>`;
  function imageURL(id){return rt()?.state?.icons?.[id]||data?.images?.[id]||'';}
  function art(id,label,portrait=false){const src=imageURL(id);return src&&!failedImages.has(src)?`<img src="${esc(src)}" alt="${esc(label)}" loading="${portrait?'eager':'lazy'}" decoding="async" draggable="false" data-hun-image="${id}">`:`<span class="hun-art-empty" data-hun-image-slot="${id}" aria-label="${esc(label)}图片待载入">${portrait?'魂':icon('sword')}<small>图片待载入</small></span>`;}
  function html(){return '<div id="hun-page" class="hun-page"><div class="hun-loading">正在载入魂的角色方案…</div></div>';}
  function canSummon(){return !busy&&!pendingJob&&!!rt()?.ready?.()&&(rt()?.state?.hunBodySupported??data?.probe_supported)&&!rt()?.state?.summonQueue?.on;}
  function availability(){
    if(!rt()?.ready?.())return '进入游戏地图后即可召唤';
    if(pendingJob)return '正在召唤，等待游戏确认';
    if(rt()?.state?.summonQueue?.on)return '请先关闭排队召唤或接力模式';
    if(!(rt()?.state?.hunBodySupported??data?.probe_supported))return '游戏中的模组需要更新并重载';
    return data.full_ready?'已连接 · 可以召唤':'当前可召唤原生本体';
  }
  function hero(){return `<section class="hun-hero card"><div class="hun-portrait">${art('HunCharacter','魂',true)}<span>魂</span><small>独立角色</small></div><div class="hun-hero-main"><div class="hun-title-row"><div><p class="hun-eyebrow">粪怪 · 自定义角色</p><h1>魂</h1></div><span class="hun-connection" data-hun-connection>${esc(availability())}</span></div><p class="hun-intro">装备、属性与战斗策略独立配置。默认全选顶配，按你的想法逐项调整。</p><div class="hun-summary">${['main_weapon','shadow_armament','accessory'].map(k=>`<span><strong data-hun-summary="${k}">${active(count(k))}</strong><span>${categories[k]}已启用</span></span>`).join('')}</div><div class="hun-summon-row"><label class="hun-count">每次召唤<input type="number" min="1" max="100" step="1" data-hun-path="count" value="${draft.count}" aria-label="召唤数量"><span>个</span></label><span class="hun-save-hint">调整后直接召唤，会先保存当前方案</span></div><div class="hun-summon-actions">${Object.entries(teams).map(([team,label])=>`<button type="button" class="hun-summon hun-team-${team}" data-hun-action="summon" data-hun-team="${team}" ${canSummon()?'':'disabled'}>${icon(team==='companion'?'shield':'plus')}${label}</button>`).join('')}</div>${data.full_ready?'':'<p class="hun-capability-note">能力适配中：当前召唤的是原生本体，下面的满配装备与战斗策略尚未应用。</p>'}</div></section>`;}
  function toolbar(){return `<div class="hun-profile-bar"><label class="hun-profile-name"><span>当前方案</span><input maxlength="60" data-hun-path="name" aria-label="方案名称" value="${esc(draft.name)}"></label><div class="hun-profile-actions"><button class="btn btn-secondary btn-sm" data-hun-action="export">${icon('down')}导出方案</button><label class="btn btn-secondary btn-sm hun-import">${icon('up')}导入方案<input type="file" data-hun-import accept=".json,application/json" aria-label="导入魂方案"></label><button class="btn btn-secondary btn-sm" data-hun-action="reset">${icon('reset')}恢复顶配</button></div></div>`;}
  function itemCard(row){
    const value=draft.items[row.id],special=row.source==='resource_only',accessory=row.kind==='accessory',max=row.level_max;
    return `<article class="hun-equipment-card ${value.enabled?'is-enabled':''}" data-hun-id="${row.id}"><div class="hun-item-art">${art(row.id,row.name)}${row.variant?`<span class="hun-variant">${esc(row.variant)}</span>`:''}<label class="hun-enable" title="启用或关闭${esc(row.name)}"><input type="checkbox" data-hun-item-field="enabled" ${value.enabled?'checked':''} aria-label="启用${esc(displayName(row))}"><span>${icon('check')}</span></label>${row.image_note?`<small class="hun-image-note">${esc(row.image_note)}</small>`:''}</div><div class="hun-item-body"><div class="hun-item-heading"><h3>${esc(row.name)}</h3><button class="hun-info" data-hun-action="item-info" aria-label="查看${esc(displayName(row))}说明">说明</button></div><p class="hun-item-desc">${esc(row.description||(special?'独立保留的剧情或交互配置。':'可单独调整等级与启用状态。'))}</p><div class="hun-item-controls"><label>${accessory?'精炼':'等级'}<input type="number" data-hun-item-field="level" value="${value.level==='max'?'':value.level}" min="1" max="${max||1}" placeholder="${max?'最高 '+max:'待确认'}" ${max?'':'disabled'} aria-label="${esc(displayName(row))}${accessory?'精炼':'等级'}"></label>${row.soul_option?`<label class="hun-soul"><input type="checkbox" data-hun-item-field="soul" ${value.soul?'checked':''}>铸魂</label>`:accessory?'<span class="hun-item-rule">效果叠加</span>':'<span class="hun-item-rule">原版形态</span>'}</div>${!accessory?`<label class="hun-weight">使用倾向<input type="number" min="0" max="1000" step="0.1" data-hun-item-field="weight" value="${value.weight}" aria-label="${esc(displayName(row))}使用倾向"><span title="同等条件下，数值越高越倾向使用；0表示不主动选择。">权重</span></label>`:''}</div></article>`;
  }
  function equipment(){
    const all=data.catalog.items.filter(inCategory),found=all.filter(r=>(!onlyOn||draft.items[r.id].enabled)&&(!query||(displayName(r)+' '+r.description).includes(query)));
    return `<div class="hun-equipment-top"><div class="hun-categories" role="tablist" aria-label="装备种类">${Object.entries(categories).map(([key,label])=>`<button role="tab" aria-selected="${key===category}" data-hun-action="category" data-hun-category="${key}" class="${key===category?'is-active':''}">${label}<span>${count(key).length}</span></button>`).join('')}</div><div class="hun-filter-row"><label class="hun-search">${icon('search')}<input type="search" data-hun-search value="${esc(query)}" placeholder="搜索装备名称或效果" aria-label="搜索装备"></label><label class="hun-only-on"><input type="checkbox" data-hun-only-on ${onlyOn?'checked':''}>只看已启用</label><div class="hun-bulk"><button data-hun-action="all-on">本类全选</button><button data-hun-action="all-off">全部关闭</button></div></div></div><div class="hun-list-heading"><span>${categories[category]} <strong data-hun-category-count>${active(all)} / ${all.length}</strong> 已启用</span><small>${category==='accessory'?'启用的饰品效果同时生效':category==='special'?'剧情、交互与临时装备，保留各自来源':'等级留空时使用该装备的最高有效等级'}</small></div><div class="hun-item-grid">${found.length?found.map(itemCard).join(''):'<div class="hun-empty">没有匹配的装备<button class="btn btn-secondary" data-hun-action="clear-search">清除筛选</button></div>'}</div>`;
  }
  function number(label,path,value,opts={}){return `<label class="hun-field"><span>${esc(label)}</span><span class="hun-number"><input type="number" data-hun-path="${path}" value="${value??''}" min="${opts.min??0}" max="${opts.max??1000}" step="${opts.step??1}" ${opts.placeholder?`placeholder="${esc(opts.placeholder)}"`:''} ${opts.scale?`data-hun-scale="${opts.scale}"`:''}>${opts.unit?`<span>${opts.unit}</span>`:''}</span>${opts.tip?`<small>${opts.tip}</small>`:''}</label>`;}
  const toggle=(label,path,value,tip='')=>`<label class="hun-setting-toggle"><span><strong>${label}</strong>${tip?`<small>${tip}</small>`:''}</span><input type="checkbox" data-hun-path="${path}" ${value?'checked':''}></label>`;
  function statLabel(field){return window.PGStatLabels?.label(field)||({Health_Max:'血量上限',Shachi_Max:'杀气上限',Attack:'攻击力',ShachiAttack:'杀气攻击'}[field]||'角色属性');}
  function overrideRows(group,fields,labels){return `<div class="hun-parameter-grid">${fields.map(field=>number(labels(field),group+'.'+field,draft[group][field],{min:group==='ai_parameters'&&data.ai_parameters[field]!=='float'?0:-1e9,max:group==='ai_parameters'&&data.ai_parameters[field]==='bool'?1:1e9,step:group==='ai_parameters'&&data.ai_parameters[field]!=='float'?1:'any',placeholder:'使用顶配预设'})).join('')}</div>`;}
  function attributes(){
    const core=['Health_Max','Shachi_Max','Attack','ShachiAttack'];
    return `<div class="hun-section-head"><h2>角色属性</h2><p>留空使用预设，填写后覆盖对应数值。只影响之后召唤的魂。</p></div><div class="hun-panel"><h3>基础战力</h3>${overrideRows('attributes',core,statLabel)}</div>${(window.PGStatLabels?.groups||[]).map(g=>{const fields=g.fields.filter(f=>data.attributes.includes(f)&&!core.includes(f));return fields.length?`<details class="hun-parameter-group"><summary>${esc(window.PGStatLabels.heading(g))}<span>${fields.filter(f=>Object.hasOwn(draft.attributes,f)).length} 项已调整</span></summary>${overrideRows('attributes',fields,statLabel)}</details>`:'';}).join('')}`;
  }
  function strategy(){
    const params=window.PG_AI_PARAMS||[],labels=f=>params.find(p=>p.name===f)?.label?.zh||f;
    return `<div class="hun-section-head"><h2>战斗策略</h2><p>防御与反击概率按百分比设置，仍遵守原版可响应的动作窗口。</p></div><div class="hun-panel"><h3>防御与反击</h3><div class="hun-parameter-grid">${[['精防尝试概率','deflect_chance'],['红光闪避概率','red_dodge_chance'],['闪避后反击倾向','counter_chance']].map(([label,key])=>number(label,'ai.'+key,100*draft.ai[key],{max:100,scale:100,unit:'%'})).join('')}</div></div><div class="hun-panel"><h3>出招与武器切换</h3>${toggle('优先考虑后期武器','ai.late_weapon_bias',draft.ai.late_weapon_bias,'在目标、资源与动作条件合适时，提高后期武器的选择权重。')}<label class="hun-field"><span>重复出招</span><select data-hun-path="ai.repeat_policy"><option value="soft" ${draft.ai.repeat_policy==='soft'?'selected':''}>尽量避免重复，紧急情况允许</option><option value="none" ${draft.ai.repeat_policy==='none'?'selected':''}>不限制重复</option></select></label>${number('连招长度上限','ai.combo_limit',draft.ai.combo_limit,{max:100,tip:'0 表示由战斗策略决定。'})}</div><details class="hun-parameter-group"><summary>精细调整战斗参数<span>${Object.keys(draft.ai_parameters).length} 项已调整</span></summary><p class="hun-help">留空恢复角色预设。权重用于同类行为之间的比较，不是成功率。</p>${overrideRows('ai_parameters',Object.keys(data.ai_parameters),labels)}</details>`;
  }
  function resources(){return `<div class="hun-section-head"><h2>资源与生存</h2><p>默认按原版消耗、恢复与重生规则运行。独立设置不会修改玩家的装备或资源。</p></div><div class="hun-panel"><h3>血药与技能</h3><div class="hun-parameter-grid">${number('血药携带量','resources.medicine_count',draft.resources.medicine_count==='native_max'?'':draft.resources.medicine_count,{max:10000,placeholder:'原版最高携带量'})}${number('技能冷却倍率','resources.cooldown_scale',draft.resources.cooldown_scale,{max:10,step:.1,unit:'倍',tip:'1 倍为原版冷却。'})}</div>${toggle('血药正常消耗','resources.consume_medicine',draft.resources.consume_medicine)}${toggle('技能资源正常消耗','resources.consume_skill_resources',draft.resources.consume_skill_resources)}</div><div class="hun-panel"><h3>受击与致死规则</h3><div class="hun-parameter-grid">${[['grab','能否被抓取'],['execution','能否被处决'],['lethal','原版致死招式']].map(([key,label])=>`<label class="hun-field"><span>${label}</span><select data-hun-path="survival.${key}"><option value="native" ${draft.survival[key]==='native'?'selected':''}>遵循原版规则</option><option value="immune" ${draft.survival[key]==='immune'?'selected':''}>免疫</option></select></label>`).join('')}</div><p class="hun-help">黑魔伤等装备的重生条件、次数和冷却仍按原版处理，不会因换装刷新。</p></div>`;}
  function phases(){return `<div class="hun-section-head"><div><h2>阶段套路</h2><p>在指定血线优先切换武器并尝试原生技能；条件不满足时跳过。</p></div><button class="btn btn-secondary" data-hun-action="phase-add" ${draft.phases.length>=16?'disabled':''}>${icon('plus')}添加阶段</button></div><div class="hun-phases">${draft.phases.map((p,i)=>`<section class="hun-panel hun-phase" data-hun-phase="${i}"><div class="hun-phase-head"><span class="hun-phase-number">${String(i+1).padStart(2,'0')}</span><input class="hun-phase-name" data-hun-path="phases.${i}.name" value="${esc(p.name)}" maxlength="60" aria-label="阶段名称"><label class="hun-inline-toggle"><input type="checkbox" data-hun-path="phases.${i}.enabled" ${p.enabled?'checked':''}>启用</label><button class="hun-icon-button" data-hun-action="phase-remove" data-hun-index="${i}" aria-label="删除${esc(p.name)}">${icon('close')}</button></div><div class="hun-parameter-grid">${number('剩余血量不高于','phases.'+i+'.health_below',p.health_below*100,{min:1,max:100,scale:100,unit:'%'})}<label class="hun-field"><span>优先使用的武器</span><select data-hun-path="phases.${i}.weapon_id">${count('main_weapon').map(r=>`<option value="${r.id}" ${p.weapon_id===r.id?'selected':''}>${esc(displayName(r))}</option>`).join('')}</select></label>${number('优先级','phases.'+i+'.priority',p.priority,{max:1000,tip:'多阶段同时满足时，数值大的优先。'})}</div>${toggle('每场只触发一次','phases.'+i+'.once',p.once)}</section>`).join('')||'<p class="hun-empty">还没有阶段套路，可以添加一条血线策略。</p>'}</div>`;}
  function content(){return ({equipment,attributes,strategy,resources,phases})[tab]();}
  function render(){
    const el=root();if(!el||!draft)return;
    el.innerHTML=`${hero()}${toolbar()}<div class="hun-tabs" role="tablist" aria-label="魂配置分组">${Object.entries(tabs).map(([key,label])=>`<button role="tab" aria-selected="${tab===key}" class="${tab===key?'is-active':''}" data-hun-action="tab" data-hun-tab="${key}">${label}</button>`).join('')}</div><div class="hun-tab-content">${content()}</div><div class="hun-save-bar"><div><span data-hun-dirty>${changed()?'有未保存的调整':'当前方案已保存'}</span><p id="hun-message" role="status" class="${noticeKind==='error'?'is-error':''}">${esc(notice)}</p></div><div>${noticeKind==='error'?'<button class="btn btn-secondary" data-hun-action="reload">重新载入方案</button>':''}<button class="btn btn-secondary" data-hun-action="undo" ${undo?'':'disabled'}>撤销批量调整</button><button class="btn btn-primary" data-hun-action="save">${icon('check')}保存方案</button></div></div><dialog class="hun-detail-dialog" aria-label="装备说明"></dialog>`;
    if(busy)for(const field of el.querySelectorAll('input,select,button'))field.disabled=true;
    el.setAttribute('aria-busy',String(busy));
  }
  function stateChanged(){
    const el=root();if(!el||!draft)return;
    const connection=el.querySelector('[data-hun-connection]');if(connection)connection.textContent=availability();
    for(const button of el.querySelectorAll('[data-hun-action="summon"]'))button.disabled=!canSummon();
    if(iconCache!==rt()?.state?.icons){
      iconCache=rt()?.state?.icons;
      for(const slot of el.querySelectorAll('[data-hun-image-slot]')){
        const id=slot.dataset.hunImageSlot;if(imageURL(id))slot.outerHTML=art(id,id==='HunCharacter'?'魂':data.catalog.items.find(r=>r.id===id)?.name||'装备',id==='HunCharacter');
      }
    }
  }
  function changedView(){
    const el=root();if(!el)return;el.querySelector('[data-hun-dirty]').textContent=changed()?'有未保存的调整':'当前方案已保存';
    for(const label of el.querySelectorAll('[data-hun-summary]'))label.textContent=active(count(label.dataset.hunSummary));
    const categoryCount=el.querySelector('[data-hun-category-count]');if(categoryCount){const rows=data.catalog.items.filter(inCategory);categoryCount.textContent=active(rows)+' / '+rows.length;}
  }
  async function mount(){
    if(!subscribed&&rt()?.subscribe){subscribed=true;rt().subscribe(event=>{
      if(event.type==='job'&&event.job.id===lastJob&&root()){
        const job=event.job;if(job.status!=='pending'){pendingJob=null;showNotice(job.status==='succeeded'?'召唤已完成。'+(data.full_ready?'':'当前为原生本体。'):(job.message||'召唤未确认，请查看操作记录。'),job.status==='succeeded'?'ok':'error');stateChanged();}
      }else if(root())stateChanged();
    });}
    if(data){render();return;}
    const token=++epoch;busy=true;
    if(root())root().innerHTML='<div class="hun-loading" role="status">正在读取角色方案…</div>';
    try{const reply=await rt().hun.load();if(token!==epoch)return;data=reply;draft=clone(reply.profile);baseline=JSON.stringify(draft);notice=reply.error||'';noticeKind=reply.error?'error':'';}
    catch(error){if(root())root().innerHTML=`<div class="hun-loading"><h2>方案未能载入</h2><p>${esc(error.message||'请检查助手连接。')}</p><button class="btn btn-secondary" data-hun-action="reload">重新载入</button></div>`;}
    finally{if(token===epoch){busy=false;render();}}
  }
  function showNotice(message,kind=''){notice=message;noticeKind=kind;const box=root()?.querySelector('#hun-message');if(box){box.textContent=message;box.classList.toggle('is-error',kind==='error');}}
  function checkInputs(){const invalid=root()?.querySelector('input:invalid,select:invalid');if(invalid){invalid.reportValidity();throw new Error('请检查标出的输入值。');}}
  async function save(){const reply=await rt().hun.save({revision:data.revision,profile:clone(draft)});data={...data,...reply};draft=clone(reply.profile);baseline=JSON.stringify(draft);}
  function inspect(id){
    const row=data.catalog.items.find(r=>r.id===id);if(!row)return;
    const dialog=root().querySelector('dialog');dialog.innerHTML=`<button class="hun-icon-button hun-dialog-close" data-hun-action="close-dialog" aria-label="关闭说明">${icon('close')}</button><div class="hun-dialog-art">${art(id,row.name)}</div><h2>${esc(displayName(row))}</h2><p>${esc(row.description||'当前条目没有正式装备说明。')}</p><dl><div><dt>来源</dt><dd>${row.source==='resource_only'?'剧情或交互配置':'游戏装备资料'}</dd></div><div><dt>最高${row.kind==='accessory'?'精炼':'等级'}</dt><dd>${row.level_max||'未确认'}</dd></div><div><dt>铸魂</dt><dd>${row.soul_option?'可选择':'此形态不适用'}</dd></div></dl>`;dialog.showModal();
  }
  async function action(name,button){
    if(name==='reload'){if(!busy){if(draft)undo=clone(draft);data=null;draft=null;await mount();}return;}
    if(name==='close-dialog'){root()?.querySelector('dialog')?.close();return;}
    if(busy||!draft)return;
    try{
      if(name==='item-info'){inspect(button.closest('[data-hun-id]').dataset.hunId);return;}
      if(name==='tab'){tab=button.dataset.hunTab;render();return;}
      if(name==='category'){category=button.dataset.hunCategory;query='';render();return;}
      if(name==='clear-search'){query='';onlyOn=false;render();return;}
      if(['reset','all-on','all-off','undo'].includes(name)){
        if(name==='undo'){if(undo){const previous=draft;draft=undo;undo=previous;}}
        else{undo=clone(draft);if(name==='reset')draft=clone(data.defaults);else for(const item of data.catalog.items.filter(inCategory))draft.items[item.id].enabled=name==='all-on';}
        notice='调整尚未保存，可继续编辑或撤销。';noticeKind='';render();return;
      }
      if(name==='phase-add'){if(draft.phases.length>=16)return;let id;do{id='phase_'+Date.now().toString(36)+'_'+(++serial);}while(draft.phases.some(p=>p.id===id));draft.phases.push({...clone(data.defaults.phases[0]),id,name:'阶段 '+(draft.phases.length+1),health_below:.5});render();return;}
      if(name==='phase-remove'){undo=clone(draft);draft.phases.splice(Number(button.dataset.hunIndex),1);render();return;}
      checkInputs();
      if(name==='export'){
        const blob=new Blob([JSON.stringify({format:'PhantomGladiatorHunProfile',version:1,profile:draft},null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),link=document.createElement('a');
        link.href=url;link.download=(draft.name.replace(/[\\/:*?"<>|]/g,'_')||'魂角色方案')+'.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);showNotice('方案已导出。');return;
      }
      if(name==='summon'&&!canSummon()){showNotice(availability(),'error');return;}
      busy=true;notice=name==='summon'?'正在保存并提交召唤…':'正在保存方案…';noticeKind='';render();
      if(name==='save'){await save();notice='方案已保存。';}
      else if(name==='summon'){
        if(changed())await save();
        const job=await rt().command('hun_body_probe',{team:button.dataset.hunTeam,count:draft.count,profile_revision:data.revision});lastJob=job.id;pendingJob=job.status==='pending'?job.id:null;
        notice=job.status==='pending'?'召唤已提交，等待游戏确认。':job.status==='succeeded'?'召唤已完成。':job.message||'召唤未确认，请查看操作记录。';noticeKind=['pending','succeeded'].includes(job.status)?'':'error';
      }
    }catch(error){showNotice(error.message||'操作未完成，请重试。','error');}
    finally{if(busy){busy=false;render();}}
  }
  function edit(el){
    if(!root()?.contains(el)||!draft||busy)return;
    if(el.matches('[data-hun-search]')){query=el.value;const start=el.selectionStart;root().querySelector('.hun-tab-content').innerHTML=equipment();const input=root().querySelector('[data-hun-search]');input.focus();input.setSelectionRange(start,start);return;}
    if(el.matches('[data-hun-only-on]')){onlyOn=el.checked;render();return;}
    if(el.dataset.hunItemField){const id=el.closest('[data-hun-id]').dataset.hunId,key=el.dataset.hunItemField;draft.items[id][key]=el.type==='checkbox'?el.checked:el.value===''&&key==='level'?'max':Number(el.value);el.closest('[data-hun-id]').classList.toggle('is-enabled',draft.items[id].enabled);if(key==='enabled'&&onlyOn){root().querySelector('.hun-tab-content').innerHTML=equipment();}}
    else if(el.dataset.hunPath){
      const parts=el.dataset.hunPath.split('.'),key=parts.pop();let obj=draft;for(const part of parts)obj=obj[part];
      if(el.type==='checkbox')obj[key]=el.checked;
      else if(el.type==='number'){
        if(el.value===''&&(parts[0]==='attributes'||parts[0]==='ai_parameters'))delete obj[key];
        else if(el.value===''&&key==='medicine_count')obj[key]='native_max';
        else obj[key]=Number(el.value)/(Number(el.dataset.hunScale)||1);
      }else obj[key]=el.value;
    }else return;
    changedView();
  }
  document.addEventListener('click',event=>{const button=event.target.closest('[data-hun-action]');if(button&&root()?.contains(button)){event.preventDefault();action(button.dataset.hunAction,button);}});
  document.addEventListener('input',event=>edit(event.target));
  document.addEventListener('change',async event=>{
    const el=event.target;if(!root()?.contains(el)||busy)return;
    if(el.tagName==='SELECT'){edit(el);return;}
    if(!el.matches('[data-hun-import]')||!el.files[0])return;
    try{
      const file=el.files[0];if(file.size>262144)throw new Error('方案文件过大，请使用导出的角色方案。');busy=true;render();
      const reply=await rt().hun.save({revision:data.revision,import_text:await file.text()});undo=clone(draft);data={...data,...reply};draft=clone(reply.profile);baseline=JSON.stringify(draft);notice='方案已导入并保存，场上角色保持原状。';noticeKind='';
    }catch(error){notice=error.message||'导入失败，原方案已保留。';noticeKind='error';}
    finally{busy=false;render();}
  });
  document.addEventListener('error',event=>{const img=event.target;if(!img?.matches?.('[data-hun-image]')||!root()?.contains(img))return;failedImages.add(img.getAttribute('src'));img.outerHTML='<span class="hun-art-empty">'+icon('sword')+'<small>图片未载入</small></span>';},true);
  return {html,mount};
})();
