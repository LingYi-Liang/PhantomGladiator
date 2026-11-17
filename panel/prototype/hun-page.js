"use strict";
// The 粪怪 page: the Hun's profile and its summon controls. The summon buttons, count and hotkeys stay in a
// side panel; the profile is one page of folding sections, each marked with what the game applies today.
window.PGHun = (() => {
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]);
  const clone = x => JSON.parse(JSON.stringify(x));
  const CATEGORIES = {main_weapon:'主武器', shadow_armament:'影之武装', accessory:'饰品', special:'特殊装备'};
  const SECTIONS = {equipment:'装备', attributes:'角色属性', strategy:'战斗策略', resources:'资源与生存', phases:'阶段套路'};
  // team, button label, function key (function_keybinds.lua), button class
  const TEAMS = [['blue','召唤到蓝方','hun_blue','btn-blue'], ['red','召唤到红方','hun_red','btn-red'], ['companion','召为随从','hun_companion','btn-companion'], ['neutral','与我对战','hun_neutral','btn-neutral']];
  // What the game side does with each part of the profile in this build (hun_body.lua, hun_loadout.lua).
  const WIRING = {
    on: ['已接入', '会作用到之后召唤的魂。还没在游戏里验证过。'],
    trial: ['试验', '默认关闭。打开这一类里的试验开关后才会作用到魂身上。'],
    off: ['还没接上', '可以先配好并保存，现在不会影响召出来的魂。'],
  };
  const SECTION_WIRING = {attributes:'on', strategy:'off', resources:'off', phases:'off'};
  const CATEGORY_WIRING = {main_weapon:'off', shadow_armament:'off', accessory:'trial', special:'off'};
  let data, draft, baseline, undo, busy = false, epoch = 0, serial = 0, category = 'main_weapon', query = '', onlyOn = false;
  let notice = '', noticeKind = '', lastJob = null, pendingJob = null, subscribed = false, iconCache = null;
  const open = new Set(['equipment', 'attributes']);
  const failedImages = new Set();
  const root = () => document.querySelector('#hun-page'), rt = () => window.PGRuntime;
  const changed = () => draft && JSON.stringify(draft) !== baseline;
  const inCategory = (row, key = category) => key === 'special' ? row.source === 'resource_only' : row.kind === key && row.source !== 'resource_only';
  const rowsOf = key => data.catalog.items.filter(row => inCategory(row, key));
  const active = rows => rows.filter(row => draft.items[row.id].enabled).length;
  const displayName = row => row.name + (row.variant ? ' · ' + row.variant : '');
  const paths = {sword:'M5 19l4-4m-3-3 6 6m-3-3L18 6l2-3-3 2-9 9M4 20l1-1', plus:'M12 5v14M5 12h14', check:'M5 12l4 4L19 6', search:'M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0', down:'M12 3v12m-5-5 5 5 5-5M5 16v5h14v-5', up:'M12 16V4m-5 5 5-5 5 5M5 16v5h14v-5', reset:'M4 10a8 8 0 1 1 1 8M4 4v6h6', close:'m6 6 12 12M6 18 18 6', chevron:'m6 9 6 6 6-6'};
  const icon = name => `<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${paths[name] || paths.sword}"/></svg>`;
  const badge = state => `<span class="hun-wiring is-${state}" title="${esc(WIRING[state][1])}">${WIRING[state][0]}</span>`;

  function imageURL(id) { return rt()?.state?.icons?.[id] || data?.images?.[id] || ''; }
  function art(id, label, portrait = false) {
    const src = imageURL(id);
    return src && !failedImages.has(src)
      ? `<img src="${esc(src)}" alt="${esc(label)}" loading="${portrait ? 'eager' : 'lazy'}" decoding="async" draggable="false" data-hun-image="${id}">`
      : `<span class="hun-art-empty" data-hun-image-slot="${id}" aria-label="${esc(label)}图片待载入">${portrait ? '魂' : icon('sword')}</span>`;
  }
  function html() { return '<div id="hun-page" class="hun-page"><div class="hun-loading">正在载入魂的角色方案…</div></div>'; }
  function canSummon() { return !busy && !pendingJob && !!rt()?.ready?.() && (rt()?.state?.hunBodySupported ?? data?.probe_supported) && !rt()?.state?.summonQueue?.on; }
  function availability() {
    if (!rt()?.ready?.()) return '进入游戏地图后即可召唤';
    if (pendingJob) return '正在召唤，等待游戏确认';
    if (rt()?.state?.summonQueue?.on) return '请先关闭排队召唤或接力模式';
    if (!(rt()?.state?.hunBodySupported ?? data?.probe_supported)) return '游戏中的模组需要更新并重载';
    return '已连接 · 可以召唤';
  }

  // ---------- side panel ----------
  function summonRows() {
    return TEAMS.map(([team, label, action, cls]) => {
      const key = window.PGHunKeys?.html(action) || {control: '', message: ''};
      return `<div class="hun-summon-row"><button type="button" class="btn ${cls}" data-hun-action="summon" data-hun-team="${team}" ${canSummon() ? '' : 'disabled'}>${label}</button><span class="hun-key-slot">${key.control}</span>${key.message}</div>`;
    }).join('') + (window.PGHunKeys?.html('hun_blue').needsUpdate ? '<p class="hun-hint is-warn">更新并重载游戏内模组后才能设置快捷键。</p>' : '');
  }
  function side() {
    return `<aside class="hun-side card">
      <div class="hun-id"><div class="hun-portrait">${art('HunCharacter', '魂', true)}</div><div><p class="hun-eyebrow">粪怪 · 自定义角色</p><h1>魂</h1><span class="hun-connection" data-hun-connection>${esc(availability())}</span></div></div>
      <label class="hun-count"><span>每次召唤</span><input type="number" min="1" max="100" step="1" data-hun-path="count" value="${draft.count}" aria-label="召唤数量"><span>个</span></label>
      <div class="hun-summon" data-hun-keys>${summonRows()}</div>
      <p class="hun-hint">点按钮会先保存当前方案再召唤。快捷键按最近一次保存的方案和数量召唤。</p>
      <div class="hun-profile">
        <label class="hun-profile-name"><span>方案名称</span><input maxlength="60" data-hun-path="name" aria-label="方案名称" value="${esc(draft.name)}"></label>
        <div class="hun-save-row"><button class="btn btn-primary" data-hun-action="save">${icon('check')}保存方案</button><button class="btn btn-secondary" data-hun-action="undo" ${undo ? '' : 'disabled'}>撤销</button></div>
        <p class="hun-dirty" data-hun-dirty>${changed() ? '有未保存的调整' : '当前方案已保存'}</p>
        <p id="hun-message" role="status" class="${noticeKind === 'error' ? 'is-error' : ''}">${esc(notice)}</p>
        ${noticeKind === 'error' ? '<button class="btn btn-secondary btn-sm" data-hun-action="reload">重新载入方案</button>' : ''}
        <div class="hun-profile-tools"><button class="btn btn-secondary btn-sm" data-hun-action="export">${icon('down')}导出</button><label class="btn btn-secondary btn-sm hun-import">${icon('up')}导入<input type="file" data-hun-import accept=".json,application/json" aria-label="导入魂方案"></label><button class="btn btn-secondary btn-sm" data-hun-action="reset">${icon('reset')}恢复顶配</button></div>
      </div>
      <div class="hun-legend"><p>各部分现在的状态</p>${Object.entries(WIRING).map(([state, [, tip]]) => `<div>${badge(state)}<span>${esc(tip)}</span></div>`).join('')}</div>
    </aside>`;
  }

  // ---------- equipment ----------
  function levelText(row) {
    const value = draft.items[row.id];
    if (!row.level_max) return '';
    return value.level === 'max' ? (row.kind === 'accessory' ? '满精炼' : '满级') : (row.kind === 'accessory' ? '精炼 ' : 'Lv ') + value.level;
  }
  function tile(row) {
    const value = draft.items[row.id], meta = [levelText(row), value.soul ? '铸魂' : ''].filter(Boolean).join(' · ');
    return `<div class="hun-tile ${value.enabled ? 'is-enabled' : ''}" data-hun-id="${row.id}">
      <button type="button" class="hun-tile-open" data-hun-action="item-info" title="${esc(displayName(row))}：点开设置${row.kind === 'accessory' ? '精炼' : '等级'}和查看说明"><span class="hun-tile-art">${art(row.id, row.name)}</span><span class="hun-tile-name">${esc(row.name)}</span><small data-hun-tile-meta>${esc(row.variant || meta)}</small></button>
      <label class="hun-tile-check" title="启用或关闭${esc(row.name)}"><input type="checkbox" data-hun-item-field="enabled" ${value.enabled ? 'checked' : ''} aria-label="启用${esc(displayName(row))}"><span>${icon('check')}</span></label>
    </div>`;
  }
  function tiles() {
    const found = rowsOf(category).filter(row => (!onlyOn || draft.items[row.id].enabled) && (!query || (displayName(row) + ' ' + row.description).includes(query)));
    return found.length ? found.map(tile).join('') : '<div class="hun-empty"><h3>没有符合条件的装备</h3><button class="btn btn-secondary btn-sm" data-hun-action="clear-search">清除筛选</button></div>';
  }
  function equipmentSummary() { return Object.keys(CATEGORIES).map(key => `${CATEGORIES[key]} ${active(rowsOf(key))}/${rowsOf(key).length}`).join(' · '); }
  function equipment() {
    const rows = rowsOf(category), state = CATEGORY_WIRING[category];
    const trial = category === 'accessory'
      ? `<label class="hun-setting-toggle hun-trial"><span><strong>试验：把启用的饰品效果加到魂身上</strong><small>魂出生后逐条施加并读回，结果写在游戏日志里。这是第一次在 NPC 身上用饰品效果，可能没有作用，也可能让游戏不稳定，先确认魂能正常出战再打开。</small></span><input type="checkbox" data-hun-path="experimental.accessory_effects" ${draft.experimental.accessory_effects ? 'checked' : ''}></label>` : '';
    return `<div class="hun-categories" role="tablist" aria-label="装备种类">${Object.entries(CATEGORIES).map(([key, label]) => `<button role="tab" aria-selected="${key === category}" data-hun-action="category" data-hun-category="${key}" class="${key === category ? 'is-active' : ''}">${label}<span data-hun-count="${key}">${active(rowsOf(key))}/${rowsOf(key).length}</span>${badge(CATEGORY_WIRING[key])}</button>`).join('')}</div>
      <p class="hun-note">${esc(WIRING[state][1])}${category === 'special' ? '这一类是剧情、交互与表外配置。' : ''}</p>${trial}
      <div class="hun-filter-row"><label class="hun-search">${icon('search')}<input type="search" data-hun-search value="${esc(query)}" placeholder="搜索名称或效果" aria-label="搜索装备"></label><label class="hun-only-on"><input type="checkbox" data-hun-only-on ${onlyOn ? 'checked' : ''}>只看已启用</label><span class="hun-bulk"><button data-hun-action="all-on">本类全开</button><button data-hun-action="all-off">本类全关</button></span><span class="hun-grid-count"><strong data-hun-category-count>${active(rows)} / ${rows.length}</strong> 已启用</span></div>
      <div class="hun-grid" data-hun-grid>${tiles()}</div>`;
  }

  // ---------- the other sections ----------
  function number(label, path, value, opts = {}) { return `<label class="hun-field"><span>${esc(label)}</span><span class="hun-number"><input type="number" data-hun-path="${path}" value="${value ?? ''}" min="${opts.min ?? 0}" max="${opts.max ?? 1000}" step="${opts.step ?? 1}" ${opts.placeholder ? `placeholder="${esc(opts.placeholder)}"` : ''} ${opts.scale ? `data-hun-scale="${opts.scale}"` : ''}>${opts.unit ? `<span>${opts.unit}</span>` : ''}</span>${opts.tip ? `<small>${opts.tip}</small>` : ''}</label>`; }
  const toggle = (label, path, value, tip = '') => `<label class="hun-setting-toggle"><span><strong>${label}</strong>${tip ? `<small>${tip}</small>` : ''}</span><input type="checkbox" data-hun-path="${path}" ${value ? 'checked' : ''}></label>`;
  function statLabel(field) { return window.PGStatLabels?.label(field) || ({Health_Max:'血量上限', Shachi_Max:'杀气上限', Attack:'攻击力', ShachiAttack:'杀气攻击'}[field] || field); }
  function overrideRows(group, fields, labels, placeholder) { return `<div class="hun-parameter-grid">${fields.map(field => number(labels(field), group + '.' + field, draft[group][field], {min: group === 'ai_parameters' && data.ai_parameters[field] !== 'float' ? 0 : -1e9, max: group === 'ai_parameters' && data.ai_parameters[field] === 'bool' ? 1 : 1e9, step: group === 'ai_parameters' && data.ai_parameters[field] !== 'float' ? 1 : 'any', placeholder})).join('')}</div>`; }
  function attributes() {
    const core = ['Health_Max', 'Shachi_Max', 'Attack', 'ShachiAttack'];
    return `<p class="hun-note">填了的数值会在魂出生后写入并读回，留空保持游戏给这只魂的原值。只影响之后召唤的魂。</p><div class="hun-panel"><h3>基础战力</h3>${overrideRows('attributes', core, statLabel, '游戏原值')}</div>${(window.PGStatLabels?.groups || []).map(g => { const fields = g.fields.filter(f => data.attributes.includes(f) && !core.includes(f)); return fields.length ? `<details class="hun-parameter-group"><summary>${esc(window.PGStatLabels.heading(g))}<span>${fields.filter(f => Object.hasOwn(draft.attributes, f)).length} 项已填</span></summary>${overrideRows('attributes', fields, statLabel, '游戏原值')}</details>` : ''; }).join('')}`;
  }
  function strategy() {
    const params = window.PG_AI_PARAMS || [], labels = f => params.find(p => p.name === f)?.label?.zh || f;
    return `<p class="hun-note">${esc(WIRING.off[1])}</p><div class="hun-panel"><h3>防御与反击</h3><div class="hun-parameter-grid">${[['精防尝试概率', 'deflect_chance'], ['红光闪避概率', 'red_dodge_chance'], ['闪避后反击倾向', 'counter_chance']].map(([label, key]) => number(label, 'ai.' + key, 100 * draft.ai[key], {max: 100, scale: 100, unit: '%'})).join('')}</div></div><div class="hun-panel"><h3>出招与武器切换</h3>${toggle('优先考虑后期武器', 'ai.late_weapon_bias', draft.ai.late_weapon_bias, '在目标、资源与动作条件合适时，提高后期武器的选择权重。')}<label class="hun-field"><span>重复出招</span><select data-hun-path="ai.repeat_policy"><option value="soft" ${draft.ai.repeat_policy === 'soft' ? 'selected' : ''}>尽量避免重复，紧急情况允许</option><option value="none" ${draft.ai.repeat_policy === 'none' ? 'selected' : ''}>不限制重复</option></select></label>${number('连招长度上限', 'ai.combo_limit', draft.ai.combo_limit, {max: 100, tip: '0 表示交给角色自行判断。'})}</div><details class="hun-parameter-group"><summary>行为参数<span>${Object.keys(draft.ai_parameters).length} 项已填</span></summary>${overrideRows('ai_parameters', Object.keys(data.ai_parameters), labels, '游戏原值')}</details>`;
  }
  function resources() { return `<p class="hun-note">${esc(WIRING.off[1])}</p><div class="hun-panel"><h3>血药与技能</h3><div class="hun-parameter-grid">${number('血药携带量', 'resources.medicine_count', draft.resources.medicine_count === 'native_max' ? '' : draft.resources.medicine_count, {max: 10000, placeholder: '原版最高携带量'})}${number('技能冷却倍率', 'resources.cooldown_scale', draft.resources.cooldown_scale, {max: 10, step: .1, unit: '倍', tip: '1 倍为原版冷却。'})}</div>${toggle('血药正常消耗', 'resources.consume_medicine', draft.resources.consume_medicine)}${toggle('技能资源正常消耗', 'resources.consume_skill_resources', draft.resources.consume_skill_resources)}</div><div class="hun-panel"><h3>受击与致死规则</h3><div class="hun-parameter-grid">${[['grab', '能否被抓取'], ['execution', '能否被处决'], ['lethal', '原版致死招式']].map(([key, label]) => `<label class="hun-field"><span>${label}</span><select data-hun-path="survival.${key}"><option value="native" ${draft.survival[key] === 'native' ? 'selected' : ''}>遵循原版</option><option value="immune" ${draft.survival[key] === 'immune' ? 'selected' : ''}>免疫</option></select></label>`).join('')}</div></div>`; }
  function phases() { return `<p class="hun-note">${esc(WIRING.off[1])}在指定血线优先切换武器并尝试原生技能；条件不满足时跳过。</p><div class="hun-phases">${draft.phases.map((p, i) => `<section class="hun-panel hun-phase" data-hun-phase="${i}"><div class="hun-phase-head"><span class="hun-phase-number">${String(i + 1).padStart(2, '0')}</span><input class="hun-phase-name" data-hun-path="phases.${i}.name" value="${esc(p.name)}" maxlength="60" aria-label="阶段名称"><label class="hun-inline-toggle"><input type="checkbox" data-hun-path="phases.${i}.enabled" ${p.enabled ? 'checked' : ''}>启用</label><button class="hun-icon-button" data-hun-action="phase-remove" data-hun-index="${i}" aria-label="删除${esc(p.name)}">${icon('close')}</button></div><div class="hun-parameter-grid">${number('剩余血量不高于', 'phases.' + i + '.health_below', p.health_below * 100, {min: 1, max: 100, scale: 100, unit: '%'})}<label class="hun-field"><span>优先武器</span><select data-hun-path="phases.${i}.weapon_id">${data.catalog.items.filter(r => r.kind === 'main_weapon').map(r => `<option value="${r.id}" ${p.weapon_id === r.id ? 'selected' : ''}>${esc(displayName(r))}</option>`).join('')}</select></label>${number('优先级', 'phases.' + i + '.priority', p.priority, {max: 1000})}</div><label class="hun-inline-toggle"><input type="checkbox" data-hun-path="phases.${i}.once" ${p.once ? 'checked' : ''}>每只魂只触发一次</label></section>`).join('')}</div><button class="btn btn-secondary btn-sm" data-hun-action="phase-add" ${draft.phases.length >= 16 ? 'disabled' : ''}>${icon('plus')}添加阶段</button>`; }
  const BODIES = {equipment, attributes, strategy, resources, phases};
  function summary(key) {
    if (key === 'equipment') return equipmentSummary();
    if (key === 'attributes') return Object.keys(draft.attributes).length ? Object.keys(draft.attributes).length + ' 项已填' : '全部用游戏原值';
    if (key === 'strategy') return `精防 ${Math.round(draft.ai.deflect_chance * 100)}% · 闪避 ${Math.round(draft.ai.red_dodge_chance * 100)}%`;
    if (key === 'resources') return draft.resources.medicine_count === 'native_max' ? '血药按原版' : '血药 ' + draft.resources.medicine_count;
    return draft.phases.filter(p => p.enabled).length + ' 个阶段启用';
  }
  function section(key) {
    const shown = open.has(key);
    return `<section class="hun-section card ${shown ? 'is-open' : ''}" data-hun-section="${key}"><button type="button" class="hun-section-head" data-hun-action="section" data-hun-section-key="${key}" aria-expanded="${shown}"><span class="hun-chevron">${icon('chevron')}</span><h2>${SECTIONS[key]}</h2><span class="hun-section-summary" data-hun-summary="${key}">${esc(summary(key))}</span>${SECTION_WIRING[key] ? badge(SECTION_WIRING[key]) : ''}</button>${shown ? `<div class="hun-section-body">${BODIES[key]()}</div>` : ''}</section>`;
  }
  function render() {
    const el = root(); if (!el || !draft) return;
    el.innerHTML = `${side()}<div class="hun-main">${Object.keys(SECTIONS).map(section).join('')}</div><dialog class="hun-detail-dialog" aria-label="装备设置"></dialog>`;
    if (busy) for (const field of el.querySelectorAll('input,select,button')) field.disabled = true;
    el.setAttribute('aria-busy', String(busy));
  }
  // The summon keys alone: the app's key capture redraws these without touching the rest of the page.
  function keysChanged() { const box = root()?.querySelector('[data-hun-keys]'); if (box && draft) box.innerHTML = summonRows(); }
  function stateChanged() {
    const el = root(); if (!el || !draft) return;
    const connection = el.querySelector('[data-hun-connection]'); if (connection) connection.textContent = availability();
    keysChanged();
    if (iconCache !== rt()?.state?.icons) {
      iconCache = rt()?.state?.icons;
      for (const slot of el.querySelectorAll('[data-hun-image-slot]')) {
        const id = slot.dataset.hunImageSlot; if (imageURL(id)) slot.outerHTML = art(id, id === 'HunCharacter' ? '魂' : data.catalog.items.find(r => r.id === id)?.name || '装备', id === 'HunCharacter');
      }
    }
  }
  function changedView() {
    const el = root(); if (!el) return;
    el.querySelector('[data-hun-dirty]').textContent = changed() ? '有未保存的调整' : '当前方案已保存';
    for (const label of el.querySelectorAll('[data-hun-summary]')) label.textContent = summary(label.dataset.hunSummary);
    for (const label of el.querySelectorAll('[data-hun-count]')) { const rows = rowsOf(label.dataset.hunCount); label.textContent = active(rows) + '/' + rows.length; }
    const categoryCount = el.querySelector('[data-hun-category-count]'); if (categoryCount) { const rows = rowsOf(category); categoryCount.textContent = active(rows) + ' / ' + rows.length; }
  }
  function refreshTile(id) {
    const row = data.catalog.items.find(r => r.id === id), box = root()?.querySelector(`.hun-tile[data-hun-id="${id}"]`); if (!row || !box) return;
    const value = draft.items[id];
    box.classList.toggle('is-enabled', value.enabled);
    box.querySelector('input[data-hun-item-field="enabled"]').checked = value.enabled;
    if (!row.variant) box.querySelector('[data-hun-tile-meta]').textContent = [levelText(row), value.soul ? '铸魂' : ''].filter(Boolean).join(' · ');
  }
  async function mount() {
    if (!subscribed && rt()?.subscribe) { subscribed = true; rt().subscribe(event => {
      if (event.type === 'job' && event.job.id === lastJob && root()) {
        const job = event.job; if (job.status !== 'pending') { pendingJob = null; showNotice(job.status === 'succeeded' ? '召唤已完成。' : (job.message || '召唤未确认，请查看操作记录。'), job.status === 'succeeded' ? 'ok' : 'error'); stateChanged(); }
      } else if (root()) stateChanged();
    }); }
    if (data) { render(); return; }
    const token = ++epoch; busy = true;
    if (root()) root().innerHTML = '<div class="hun-loading" role="status">正在读取角色方案…</div>';
    try { const reply = await rt().hun.load(); if (token !== epoch) return; data = reply; draft = clone(reply.profile); baseline = JSON.stringify(draft); notice = reply.error || ''; noticeKind = reply.error ? 'error' : ''; }
    catch (error) { if (root()) root().innerHTML = `<div class="hun-loading"><h2>方案未能载入</h2><p>${esc(error.message || '请检查助手连接。')}</p><button class="btn btn-secondary" data-hun-action="reload">重新载入</button></div>`; }
    finally { if (token === epoch) { busy = false; render(); } }
  }
  function showNotice(message, kind = '') { notice = message; noticeKind = kind; const box = root()?.querySelector('#hun-message'); if (box) { box.textContent = message; box.classList.toggle('is-error', kind === 'error'); } }
  function checkInputs() { const invalid = root()?.querySelector('input:invalid,select:invalid'); if (invalid) { invalid.reportValidity(); throw new Error('请检查标出的输入值。'); } }
  async function save() { const reply = await rt().hun.save({revision: data.revision, profile: clone(draft)}); data = {...data, ...reply}; draft = clone(reply.profile); baseline = JSON.stringify(draft); }
  // One item's settings: on or off, level or refinement, soul-forged form, pick weight, and what it does.
  function inspect(id) {
    const row = data.catalog.items.find(r => r.id === id); if (!row) return;
    const value = draft.items[id], accessory = row.kind === 'accessory', weighted = row.kind === 'main_weapon' || row.kind === 'shadow_armament';
    const dialog = root().querySelector('dialog');
    dialog.innerHTML = `<button class="hun-icon-button hun-dialog-close" data-hun-action="close-dialog" aria-label="关闭">${icon('close')}</button>
      <div class="hun-dialog-top"><div class="hun-dialog-art">${art(id, row.name)}</div><div><h2>${esc(displayName(row))}</h2><p>${esc(row.description || (row.source === 'resource_only' ? '独立保留的剧情或交互配置。' : '当前条目没有正式装备说明。'))}</p></div></div>
      <div class="hun-dialog-controls" data-hun-id="${id}">
        <label class="hun-setting-toggle"><span><strong>启用</strong></span><input type="checkbox" data-hun-item-field="enabled" ${value.enabled ? 'checked' : ''}></label>
        <label class="hun-field"><span>${accessory ? '精炼' : '等级'}</span><span class="hun-number"><input type="number" data-hun-item-field="level" value="${value.level === 'max' ? '' : value.level}" min="1" max="${row.level_max || 1}" placeholder="${row.level_max ? '最高（' + row.level_max + '）' : '未确认'}" ${row.level_max ? '' : 'disabled'}></span></label>
        ${row.soul_option ? `<label class="hun-setting-toggle"><span><strong>铸魂形态</strong></span><input type="checkbox" data-hun-item-field="soul" ${value.soul ? 'checked' : ''}></label>` : ''}
        ${weighted ? `<label class="hun-field"><span>出场权重</span><span class="hun-number"><input type="number" data-hun-item-field="weight" value="${value.weight}" min="0" max="1000" step="0.1"></span><small>越大越常被选用；0 表示不主动选用。</small></label>` : ''}
      </div>
      <dl><div><dt>来源</dt><dd>${row.source === 'resource_only' ? '剧情或交互配置' : '游戏装备资料'}</dd></div><div><dt>现在的状态</dt><dd>${WIRING[CATEGORY_WIRING[row.source === 'resource_only' ? 'special' : row.kind]][0]}</dd></div></dl>`;
    dialog.showModal();
  }
  async function action(name, button) {
    if (name === 'reload') { if (!busy) { if (draft) undo = clone(draft); data = null; draft = null; await mount(); } return; }
    if (name === 'close-dialog') { root()?.querySelector('dialog')?.close(); return; }
    if (busy || !draft) return;
    try {
      if (name === 'item-info') { inspect(button.closest('[data-hun-id]').dataset.hunId); return; }
      if (name === 'section') { const key = button.dataset.hunSectionKey; if (open.has(key)) open.delete(key); else open.add(key); render(); return; }
      if (name === 'category') { category = button.dataset.hunCategory; query = ''; render(); return; }
      if (name === 'clear-search') { query = ''; onlyOn = false; render(); return; }
      if (['reset', 'all-on', 'all-off', 'undo'].includes(name)) {
        if (name === 'undo') { if (undo) { const previous = draft; draft = undo; undo = previous; } }
        else { undo = clone(draft); if (name === 'reset') draft = clone(data.defaults); else for (const item of rowsOf(category)) draft.items[item.id].enabled = name === 'all-on'; }
        notice = '调整尚未保存，可继续编辑或撤销。'; noticeKind = ''; render(); return;
      }
      if (name === 'phase-add') { if (draft.phases.length >= 16) return; let id; do { id = 'phase_' + Date.now().toString(36) + '_' + (++serial); } while (draft.phases.some(p => p.id === id)); draft.phases.push({...clone(data.defaults.phases[0]), id, name: '阶段 ' + (draft.phases.length + 1), health_below: .5}); render(); return; }
      if (name === 'phase-remove') { undo = clone(draft); draft.phases.splice(Number(button.dataset.hunIndex), 1); render(); return; }
      checkInputs();
      if (name === 'export') {
        const blob = new Blob([JSON.stringify({format: 'PhantomGladiatorHunProfile', version: 1, profile: draft}, null, 2)], {type: 'application/json'}), url = URL.createObjectURL(blob), link = document.createElement('a');
        link.href = url; link.download = (draft.name.replace(/[\\/:*?"<>|]/g, '_') || '魂角色方案') + '.json'; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); showNotice('方案已导出。'); return;
      }
      if (name === 'summon' && !canSummon()) { showNotice(availability(), 'error'); return; }
      busy = true; notice = name === 'summon' ? '正在保存并提交召唤…' : '正在保存方案…'; noticeKind = ''; render();
      if (name === 'save') { await save(); notice = '方案已保存。'; }
      else if (name === 'summon') {
        if (changed()) await save();
        const job = await rt().command('hun_body_probe', {team: button.dataset.hunTeam, count: draft.count, profile_revision: data.revision}); lastJob = job.id; pendingJob = job.status === 'pending' ? job.id : null;
        notice = job.status === 'pending' ? '召唤已提交，等待游戏确认。' : job.status === 'succeeded' ? '召唤已完成。' : job.message || '召唤未确认，请查看操作记录。'; noticeKind = ['pending', 'succeeded'].includes(job.status) ? '' : 'error';
      }
    } catch (error) { showNotice(error.message || '操作未完成，请重试。', 'error'); }
    finally { if (busy) { busy = false; render(); } }
  }
  function edit(el) {
    if (!root()?.contains(el) || !draft || busy) return;
    if (el.matches('[data-hun-search]')) { query = el.value; root().querySelector('[data-hun-grid]').innerHTML = tiles(); return; }
    if (el.matches('[data-hun-only-on]')) { onlyOn = el.checked; root().querySelector('[data-hun-grid]').innerHTML = tiles(); return; }
    if (el.dataset.hunItemField) {
      const id = el.closest('[data-hun-id]').dataset.hunId, key = el.dataset.hunItemField;
      draft.items[id][key] = el.type === 'checkbox' ? el.checked : el.value === '' && key === 'level' ? 'max' : Number(el.value);
      if (key === 'enabled' && onlyOn && !el.closest('dialog')) root().querySelector('[data-hun-grid]').innerHTML = tiles(); else refreshTile(id);
    } else if (el.dataset.hunPath) {
      const parts = el.dataset.hunPath.split('.'), key = parts.pop(); let obj = draft; for (const part of parts) obj = obj[part];
      if (el.type === 'checkbox') obj[key] = el.checked;
      else if (el.type === 'number') {
        if (el.value === '' && (parts[0] === 'attributes' || parts[0] === 'ai_parameters')) delete obj[key];
        else if (el.value === '' && key === 'medicine_count') obj[key] = 'native_max';
        else obj[key] = Number(el.value) / (Number(el.dataset.hunScale) || 1);
      } else obj[key] = el.value;
    } else return;
    changedView();
  }
  document.addEventListener('click', event => { const button = event.target.closest('[data-hun-action]'); if (button && root()?.contains(button)) { event.preventDefault(); action(button.dataset.hunAction, button); } });
  document.addEventListener('input', event => edit(event.target));
  document.addEventListener('change', async event => {
    const el = event.target; if (!root()?.contains(el) || busy) return;
    if (el.tagName === 'SELECT') { edit(el); return; }
    if (!el.matches('[data-hun-import]') || !el.files[0]) return;
    try {
      const file = el.files[0]; if (file.size > 262144) throw new Error('方案文件过大，请使用导出的角色方案。'); busy = true; render();
      const reply = await rt().hun.save({revision: data.revision, import_text: await file.text()}); undo = clone(draft); data = {...data, ...reply}; draft = clone(reply.profile); baseline = JSON.stringify(draft); notice = '方案已导入并保存，场上角色保持原状。'; noticeKind = '';
    } catch (error) { notice = error.message || '导入失败，原方案已保留。'; noticeKind = 'error'; }
    finally { busy = false; render(); }
  });
  document.addEventListener('error', event => { const img = event.target; if (!img?.matches?.('[data-hun-image]') || !root()?.contains(img)) return; failedImages.add(img.getAttribute('src')); img.outerHTML = '<span class="hun-art-empty">' + icon('sword') + '</span>'; }, true);
  return {html, mount, keysChanged};
})();
