"use strict";
// The 粪怪 page: the Hun's profile and its summon controls. The summon buttons, count and hotkeys stay in a
// side panel; the profile is one page of folding sections, each marked with what the game applies today.
window.PGHun = (() => {
  const t = (key, params) => I18N.t(key, params);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]);
  const clone = x => JSON.parse(JSON.stringify(x));
  function categories() { return {main_weapon:t("hun.mainWeapon"), shadow_armament:t("hun.shadow"), accessory:t("hun.accessory"), special:t("hun.special")}; }
  function sections() { return {equipment:t("hun.equipment"), attributes:t("hun.attributes"), strategy:t("hun.strategy"), resources:t("hun.resources"), phases:t("hun.phases")}; }
  // team, button label, function key (function_keybinds.lua), button class
  function teams() { return [['blue',t("hun.blue"),'hun_blue','btn-blue'], ['red',t("hun.red"),'hun_red','btn-red'], ['companion',t("hun.companion"),'hun_companion','btn-companion'], ['neutral',t("hun.neutral"),'hun_neutral','btn-neutral']]; }
  // What the game side does with each part of the profile in this build (hun_body.lua, hun_loadout.lua).
  function wiring() { return {
    on: [t("hun.wired"), t("hun.wiredHint")],
    trial: [t("hun.partial"), t("hun.partialHint")],
    off: [t("hun.unwired"), t("hun.unwiredHint")],
  }; }
  const SECTION_WIRING = {attributes:'on', strategy:'on', resources:'trial', phases:'on'};
  const CATEGORY_WIRING = {main_weapon:'on', shadow_armament:'on', accessory:'on', special:'on'};
  let data, draft, baseline, undo, busy = false, epoch = 0, serial = 0, category = 'main_weapon', query = '', onlyOn = false;
  let notice = '', noticeKind = '', lastJob = null, pendingJob = null, subscribed = false, iconCache = null;
  let renderedKeys = '';
  const open = new Set(['equipment', 'attributes']);
  const failedImages = new Set();
  const root = () => document.querySelector('#hun-page'), rt = () => window.PGRuntime;
  const noticeText = () => typeof notice === 'function' ? notice() : I18N.combatMessage(notice);
  const changed = () => draft && JSON.stringify(draft) !== baseline;
  const inCategory = (row, key = category) => key === 'special' ? row.source === 'resource_only' : row.kind === key && row.source !== 'resource_only';
  const rowsOf = key => data.catalog.items.filter(row => inCategory(row, key));
  const active = rows => rows.filter(row => draft.items[row.id].enabled).length;
  const item = row => I18N.lang === 'en' && row.en ? row.en : row;
  const displayName = row => [item(row).name, item(row).variant].filter(Boolean).join(' · ');
  const profileName = name => name === '满配魂' ? t('hun.defaultProfile') : name;
  const phaseName = name => name === '黑魔伤保命' ? t('hun.defaultPhase') : name;
  const paths = {sword:'M5 19l4-4m-3-3 6 6m-3-3L18 6l2-3-3 2-9 9M4 20l1-1', plus:'M12 5v14M5 12h14', check:'M5 12l4 4L19 6', search:'M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0', down:'M12 3v12m-5-5 5 5 5-5M5 16v5h14v-5', up:'M12 16V4m-5 5 5-5 5 5M5 16v5h14v-5', reset:'M4 10a8 8 0 1 1 1 8M4 4v6h6', close:'m6 6 12 12M6 18 18 6', chevron:'m6 9 6 6 6-6'};
  const icon = name => `<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${paths[name] || paths.sword}"/></svg>`;
  const badge = state => `<span class="hun-wiring is-${state}" title="${esc(wiring()[state][1])}">${wiring()[state][0]}</span>`;

  function imageURL(id) { return rt()?.state?.icons?.[id] || data?.images?.[id] || ''; }
  function art(id, label, portrait = false) {
    const src = imageURL(id);
    return src && !failedImages.has(src)
      ? `<img src="${esc(src)}" alt="${esc(label)}" loading="${portrait ? 'eager' : 'lazy'}" decoding="async" draggable="false" data-hun-image="${id}">`
      : `<span class="hun-art-empty" data-hun-image-slot="${id}" aria-label="${esc(label)}${t("hun.imagePending")}">${portrait ? t("hun.soul") : icon('sword')}</span>`;
  }
  function html() { return `<div id="hun-page" class="hun-page"><div class="hun-loading">${t("hun.loading")}</div></div>`; }
  function receipt(job) {
    if (job.status === 'pending') return t("hun.pending");
    if (job.message && (I18N.lang !== 'en' || !/[\u3400-\u9fff]/u.test(job.message))) return job.message;
    if (job.message && ['failed', 'uncertain'].includes(job.status)) return I18N.combatMessage(job.message);
    if (job.status === 'succeeded' && job.spawned > 0) return t('hun.summonedCount', {n:job.spawned});
    return job.status === 'succeeded' ? t("hun.accepted") : t("hun.uncertain");
  }
  function canSummon() { return !busy && !pendingJob && !!rt()?.ready?.() && (rt()?.state?.hunBodySupported ?? data?.probe_supported); }
  function availability() {
    if (!rt()?.ready?.()) return t("hun.enterGame");
    if (pendingJob) return t("hun.waiting");
    if (!(rt()?.state?.hunBodySupported ?? data?.probe_supported)) return t("hun.updateMod");
    if (rt()?.state?.summonQueue?.on) return t("hun.connectedQueue");
    return t("hun.connected");
  }

  // ---------- side panel ----------
  function summonRows() {
    return teams().map(([team, label, action, cls]) => {
      const key = window.PGHunKeys?.html(action) || {control: '', message: ''};
      return `<div class="hun-summon-row"><button type="button" class="btn ${cls}" data-hun-action="summon" data-hun-team="${team}" ${canSummon() ? '' : 'disabled'}>${label}</button><span class="hun-key-slot">${key.control}</span>${key.message}</div>`;
    }).join('') + (window.PGHunKeys?.html('hun_blue').needsUpdate ? `<p class="hun-hint is-warn">${t("hun.updateKeys")}</p>` : '');
  }
  function side() {
    renderedKeys = summonRows();
    return `<aside class="hun-side card">
      <div class="hun-id"><div class="hun-portrait">${art('HunCharacter', t("hun.soul"), true)}</div><div><p class="hun-eyebrow">${t("hun.subtitle")}</p><h1>${t("hun.soul")}</h1><span class="hun-connection" data-hun-connection>${esc(availability())}</span></div></div>
      <label class="hun-count"><span>${t("hun.count")}</span><input type="number" min="1" max="100" step="1" data-hun-path="count" value="${draft.count}" aria-label="${t("hun.quantity")}"><span>${t("hun.countUnit")}</span></label>
      <div class="hun-summon" data-hun-keys>${renderedKeys}</div>
      <p class="hun-hint">${t("hun.summonHint")}</p>
      <div class="hun-profile">
        <label class="hun-profile-name"><span>${t("hun.profileName")}</span><input maxlength="60" data-hun-path="name" aria-label="${t("hun.profileName")}" value="${esc(profileName(draft.name))}"></label>
        <div class="hun-save-row"><button class="btn btn-primary" data-hun-action="save">${icon('check')}${t("hun.saveProfile")}</button><button class="btn btn-secondary" data-hun-action="undo" ${undo ? '' : 'disabled'}>${t("hun.undo")}</button></div>
        <p class="hun-dirty" data-hun-dirty>${changed() ? t("hun.unsaved") : t("hun.savedState")}</p>
        <p id="hun-message" role="status" class="${noticeKind === 'error' ? 'is-error' : ''}">${esc(noticeText())}</p>
        ${noticeKind === 'error' ? `<button class="btn btn-secondary btn-sm" data-hun-action="reload">${t("hun.reloadProfile")}</button>` : ''}
        <div class="hun-profile-tools"><button class="btn btn-secondary btn-sm" data-hun-action="export">${icon('down')}${t("hun.export")}</button><label class="btn btn-secondary btn-sm hun-import">${icon('up')}${t("hun.import")}<input type="file" data-hun-import accept=".json,application/json" aria-label="${t("hun.importProfile")}"></label><button class="btn btn-secondary btn-sm" data-hun-action="reset">${icon('reset')}${t("hun.reset")}</button></div>
      </div>
      <div class="hun-legend"><p>${t("hun.coverage")}</p>${Object.entries(wiring()).map(([state, [, tip]]) => `<div>${badge(state)}<span>${esc(tip)}</span></div>`).join('')}</div>
    </aside>`;
  }

  // ---------- equipment ----------
  function levelText(row) {
    const value = draft.items[row.id];
    if (!row.level_max) return '';
    return value.level === 'max' ? (row.kind === 'accessory' ? t("hun.maxRefine") : t("hun.maxLevel")) : (row.kind === 'accessory' ? `${t("hun.refinement")} ` : 'Lv ') + value.level;
  }
  function tile(row) {
    const value = draft.items[row.id], meta = [levelText(row), value.soul ? t("hun.tempered") : ''].filter(Boolean).join(' · ');
    return `<div class="hun-tile ${value.enabled ? 'is-enabled' : ''}" data-hun-id="${row.id}">
      <button type="button" class="hun-tile-open" data-hun-action="item-info" title="${esc(displayName(row))}${t("hun.editItem")}${row.kind === 'accessory' ? t("hun.refinement") : t("hun.level")}${t("hun.readDetails")}"><span class="hun-tile-art">${art(row.id, item(row).name)}</span><span class="hun-tile-name">${esc(item(row).name)}</span><small data-hun-tile-meta>${esc(item(row).variant || meta)}</small></button>
      <label class="hun-tile-check" title="${t("hun.toggleItem")}${esc(item(row).name)}"><input type="checkbox" data-hun-item-field="enabled" ${value.enabled ? 'checked' : ''} aria-label="${t("hun.enable")}${esc(displayName(row))}"><span>${icon('check')}</span></label>
    </div>`;
  }
  function tiles() {
    const found = rowsOf(category).filter(row => (!onlyOn || draft.items[row.id].enabled) && (!query || (displayName(row) + ' ' + item(row).description + ' ' + row.name).toLocaleLowerCase().includes(query.toLocaleLowerCase())));
    return found.length ? found.map(tile).join('') : `<div class="hun-empty"><h3>${t("hun.empty")}</h3><button class="btn btn-secondary btn-sm" data-hun-action="clear-search">${t("hun.clearFilters")}</button></div>`;
  }
  function equipmentSummary() { return Object.keys(categories()).map(key => `${categories()[key]} ${active(rowsOf(key))}/${rowsOf(key).length}`).join(' · '); }
  function equipment() {
    const rows = rowsOf(category), state = CATEGORY_WIRING[category];
    const trial = category === 'accessory'
      ? `<label class="hun-setting-toggle hun-trial"><span><strong>${t("hun.accessoryEffects")}</strong><small>${t("hun.effectHint")}</small></span><input type="checkbox" data-hun-path="experimental.accessory_effects" ${draft.experimental.accessory_effects ? 'checked' : ''}></label>` : '';
    return `<div class="hun-categories" role="tablist" aria-label="${t("hun.categories")}">${Object.entries(categories()).map(([key, label]) => `<button role="tab" aria-selected="${key === category}" data-hun-action="category" data-hun-category="${key}" class="${key === category ? 'is-active' : ''}">${label}<span data-hun-count="${key}">${active(rowsOf(key))}/${rowsOf(key).length}</span>${badge(CATEGORY_WIRING[key])}</button>`).join('')}</div>
      <p class="hun-note">${esc(wiring()[state][1])}${category === 'special' ? t("hun.specialHint") : ''}</p>${trial}
      <div class="hun-filter-row"><label class="hun-search">${icon('search')}<input type="search" data-hun-search value="${esc(query)}" placeholder="${t("hun.searchHint")}" aria-label="${t("hun.search")}"></label><label class="hun-only-on"><input type="checkbox" data-hun-only-on ${onlyOn ? 'checked' : ''}>${t("hun.onlyEnabled")}</label><span class="hun-bulk"><button data-hun-action="all-on">${t("hun.enableAll")}</button><button data-hun-action="all-off">${t("hun.disableAll")}</button></span><span class="hun-grid-count"><strong data-hun-category-count>${active(rows)} / ${rows.length}</strong> ${t("hun.enabled")}</span></div>
      <div class="hun-grid" data-hun-grid>${tiles()}</div>`;
  }

  // ---------- the other sections ----------
  function number(label, path, value, opts = {}) { return `<label class="hun-field"><span>${esc(label)}</span><span class="hun-number"><input type="number" data-hun-path="${path}" value="${value ?? ''}" min="${opts.min ?? 0}" max="${opts.max ?? 1000}" step="${opts.step ?? 1}" ${opts.placeholder ? `placeholder="${esc(opts.placeholder)}"` : ''} ${opts.scale ? `data-hun-scale="${opts.scale}"` : ''}>${opts.unit ? `<span>${opts.unit}</span>` : ''}</span>${opts.tip ? `<small>${opts.tip}</small>` : ''}</label>`; }
  const toggle = (label, path, value, tip = '') => `<label class="hun-setting-toggle"><span><strong>${label}</strong>${tip ? `<small>${tip}</small>` : ''}</span><input type="checkbox" data-hun-path="${path}" ${value ? 'checked' : ''}></label>`;
  function statLabel(field) { return window.PGStatLabels?.label(field) || ({Health_Max:t("hun.maxHp"), Shachi_Max:t("hun.maxSha"), Attack:t("hun.attack"), ShachiAttack:t("hun.shaDamage")}[field] || field); }
  function overrideRows(group, fields, labels, placeholder) { return `<div class="hun-parameter-grid">${fields.map(field => number(labels(field), group + '.' + field, draft[group][field], {min: group === 'ai_parameters' && data.ai_parameters[field] !== 'float' ? 0 : -1e9, max: group === 'ai_parameters' && data.ai_parameters[field] === 'bool' ? 1 : 1e9, step: group === 'ai_parameters' && data.ai_parameters[field] !== 'float' ? 1 : 'any', placeholder: field === 'ExecutionExecutorNormalHealthThreshold' ? '0.10' : field === 'ExecutionExecutorBreakHealthThreshold' ? '0.20' : placeholder})).join('')}</div>`; }
  function attributes() {
    const core = ['Health_Max', 'Shachi_Max', 'Attack', 'ShachiAttack'];
    return `<p class="hun-note">${t("hun.attributesHint")}</p><div class="hun-panel"><h3>${t("hun.baseStats")}</h3>${overrideRows('attributes', core, statLabel, t("hun.nativeValue"))}</div>${(window.PGStatLabels?.groups || []).map(g => { const fields = g.fields.filter(f => data.attributes.includes(f) && !core.includes(f)); return fields.length ? `<details class="hun-parameter-group"><summary>${esc(window.PGStatLabels.heading(g))}<span>${fields.filter(f => Object.hasOwn(draft.attributes, f)).length} ${t("hun.overrides")}</span></summary>${g.key === 'execution' ? `<p class="hun-note">${esc(t('hun.executionLimitHint'))}</p>` : ''}${overrideRows('attributes', fields, statLabel, t("hun.nativeValue"))}</details>` : ''; }).join('')}`;
  }
  function strategy() {
    const params = window.PG_AI_PARAMS || [], labels = f => params.find(p => p.name === f)?.label?.[I18N.lang] || f;
    return `<p class="hun-note">${esc(wiring().on[1])}</p><div class="hun-panel"><h3>${t("hun.defense")}</h3><div class="hun-parameter-grid">${[[t("hun.parry"), 'deflect_chance'], [t("hun.dodge"), 'red_dodge_chance'], [t("hun.counter"), 'counter_chance']].map(([label, key]) => number(label, 'ai.' + key, 100 * draft.ai[key], {max: 100, scale: 100, unit: '%'})).join('')}</div></div><div class="hun-panel"><h3>${t("hun.rotation")}</h3>${toggle(t("hun.lateWeapons"), 'ai.late_weapon_bias', draft.ai.late_weapon_bias, t("hun.lateHint"))}<label class="hun-field"><span>${t("hun.repeats")}</span><select data-hun-path="ai.repeat_policy"><option value="soft" ${draft.ai.repeat_policy === 'soft' ? 'selected' : ''}>${t("hun.avoidRepeats")}</option><option value="none" ${draft.ai.repeat_policy === 'none' ? 'selected' : ''}>${t("hun.allowRepeats")}</option></select></label>${number(t("hun.comboLimit"), 'ai.combo_limit', draft.ai.combo_limit, {max: 100, tip: `0 ${t("hun.autoCombo")}`})}</div><details class="hun-parameter-group"><summary>${t("hun.ai")}<span>${Object.keys(draft.ai_parameters).length} ${t("hun.overrides")}</span></summary>${overrideRows('ai_parameters', Object.keys(data.ai_parameters), labels, t("hun.nativeValue"))}</details>`;
  }
  function resources() { return `<p class="hun-note">${t("hun.resourceHint")}</p><div class="hun-panel"><h3>${t("hun.medicineSkills")}</h3><div class="hun-parameter-grid">${number(t("hun.medicine"), 'resources.medicine_count', draft.resources.medicine_count === 'native_max' ? '' : draft.resources.medicine_count, {max: 10000, placeholder: t("hun.nativeMedicine")})}${number(t("hun.cooldown"), 'resources.cooldown_scale', draft.resources.cooldown_scale, {max: 10, step: .1, unit: t("hun.multiplier"), tip: `1 ${t("hun.nativeCooldown")}`})}</div>${toggle(t("hun.consumeMedicine"), 'resources.consume_medicine', draft.resources.consume_medicine)}${toggle(t("hun.consumeSkill"), 'resources.consume_skill_resources', draft.resources.consume_skill_resources)}</div><div class="hun-panel"><h3>${t("hun.survival")}</h3><div class="hun-parameter-grid">${[['grab', t("hun.canGrab")], ['execution', t("hun.canExecute")], ['lethal', t("hun.lethals")]].map(([key, label]) => `<label class="hun-field"><span>${label}</span><select data-hun-path="survival.${key}"><option value="native" ${draft.survival[key] === 'native' ? 'selected' : ''}>${t("hun.native")}</option><option value="immune" ${draft.survival[key] === 'immune' ? 'selected' : ''}>${t("hun.immune")}</option></select></label>`).join('')}</div></div>`; }
  function phaseWeaponOptions(selected) {
    return data.catalog.items.filter(row => row.kind === 'main_weapon').map(row => {
      const disabled = row.has_combat_art === false;
      const label = disabled ? displayName(row) + ' · ' + t('hun.noCombatArt') : displayName(row);
      return `<option value="${row.id}" ${selected === row.id ? 'selected' : ''} ${disabled ? 'disabled' : ''}>${esc(label)}</option>`;
    }).join('');
  }
  function phases() { return `<p class="hun-note">${esc(wiring().on[1])}${t("hun.phaseHint")}</p><div class="hun-phases">${draft.phases.map((p, i) => `<section class="hun-panel hun-phase" data-hun-phase="${i}"><div class="hun-phase-head"><span class="hun-phase-number">${String(i + 1).padStart(2, '0')}</span><input class="hun-phase-name" data-hun-path="phases.${i}.name" value="${esc(phaseName(p.name))}" maxlength="60" aria-label="${t("hun.phaseName")}"><label class="hun-inline-toggle"><input type="checkbox" data-hun-path="phases.${i}.enabled" ${p.enabled ? 'checked' : ''}>${t("hun.enable")}</label><button class="hun-icon-button" data-hun-action="phase-remove" data-hun-index="${i}" aria-label="${t("hun.removePhase")}${esc(phaseName(p.name))}">${icon('close')}</button></div><div class="hun-parameter-grid">${number(t("hun.hpThreshold"), 'phases.' + i + '.health_below', p.health_below * 100, {min: 1, max: 100, scale: 100, unit: '%'})}<label class="hun-field"><span>${t("hun.phaseWeapon")}</span><select data-hun-path="phases.${i}.weapon_id">${phaseWeaponOptions(p.weapon_id)}</select></label>${number(t("hun.priority"), 'phases.' + i + '.priority', p.priority, {max: 1000})}</div><label class="hun-inline-toggle"><input type="checkbox" data-hun-path="phases.${i}.once" ${p.once ? 'checked' : ''}>${t("hun.once")}</label></section>`).join('')}</div><button class="btn btn-secondary btn-sm" data-hun-action="phase-add" ${draft.phases.length >= 16 ? 'disabled' : ''}>${icon('plus')}${t("hun.addPhase")}</button>`; }
  const BODIES = {equipment, attributes, strategy, resources, phases};
  function summary(key) {
    if (key === 'equipment') return equipmentSummary();
    if (key === 'attributes') return Object.keys(draft.attributes).length ? Object.keys(draft.attributes).length + ` ${t("hun.overrides")}` : t("hun.allNative");
    if (key === 'strategy') return `${t("hun.parryShort")} ${Math.round(draft.ai.deflect_chance * 100)}% ${t("hun.dodgeShort")} ${Math.round(draft.ai.red_dodge_chance * 100)}%`;
    if (key === 'resources') return draft.resources.medicine_count === 'native_max' ? t("hun.nativeSupply") : `${t("hun.medicineShort")} ` + draft.resources.medicine_count;
    return draft.phases.filter(p => p.enabled).length + ` ${t("hun.activePhases")}`;
  }
  function section(key) {
    const shown = open.has(key);
    return `<section class="hun-section card ${shown ? 'is-open' : ''}" data-hun-section="${key}"><button type="button" class="hun-section-head" data-hun-action="section" data-hun-section-key="${key}" aria-expanded="${shown}"><span class="hun-chevron">${icon('chevron')}</span><h2>${sections()[key]}</h2><span class="hun-section-summary" data-hun-summary="${key}">${esc(summary(key))}</span>${SECTION_WIRING[key] ? badge(SECTION_WIRING[key]) : ''}</button>${shown ? `<div class="hun-section-body">${BODIES[key]()}</div>` : ''}</section>`;
  }
  function render() {
    const el = root(); if (!el || !draft) return;
    el.innerHTML = `${side()}<div class="hun-main">${Object.keys(sections()).map(section).join('')}</div><dialog class="hun-detail-dialog" aria-label="${t("hun.itemSettings")}"></dialog>`;
    iconCache = rt()?.state?.icons;
    if (busy) for (const field of el.querySelectorAll('input,select,button')) field.disabled = true;
    el.setAttribute('aria-busy', String(busy));
  }
  // The summon keys alone: the app's key capture redraws these without touching the rest of the page.
  function keysChanged() {
    const box = root()?.querySelector('[data-hun-keys]'); if (!box || !draft || busy) return;
    const rows = summonRows();
    if (rows !== renderedKeys) { box.innerHTML = rows; renderedKeys = rows; }
  }
  function stateChanged() {
    const el = root(); if (!el || !draft) return;
    const connection = el.querySelector('[data-hun-connection]'), label = availability();
    if (connection && connection.textContent !== label) connection.textContent = label;
    keysChanged();
    if (iconCache !== rt()?.state?.icons) {
      iconCache = rt()?.state?.icons;
      for (const slot of el.querySelectorAll('[data-hun-image-slot]')) {
        const id = slot.dataset.hunImageSlot;
        if (!imageURL(id)) continue;
        const row = data.catalog.items.find(r => r.id === id);
        slot.outerHTML = art(id, row ? displayName(row) : t("hun.soul"), id === 'HunCharacter');
      }
    }
  }
  function changedView() {
    const el = root(); if (!el) return;
    el.querySelector('[data-hun-dirty]').textContent = changed() ? t("hun.unsaved") : t("hun.savedState");
    for (const label of el.querySelectorAll('[data-hun-summary]')) label.textContent = summary(label.dataset.hunSummary);
    for (const label of el.querySelectorAll('[data-hun-count]')) { const rows = rowsOf(label.dataset.hunCount); label.textContent = active(rows) + '/' + rows.length; }
    const categoryCount = el.querySelector('[data-hun-category-count]'); if (categoryCount) { const rows = rowsOf(category); categoryCount.textContent = active(rows) + ' / ' + rows.length; }
  }
  function refreshTile(id) {
    const row = data.catalog.items.find(r => r.id === id), box = root()?.querySelector(`.hun-tile[data-hun-id="${id}"]`); if (!row || !box) return;
    const value = draft.items[id];
    box.classList.toggle('is-enabled', value.enabled);
    box.querySelector('input[data-hun-item-field="enabled"]').checked = value.enabled;
    if (!item(row).variant) box.querySelector('[data-hun-tile-meta]').textContent = [levelText(row), value.soul ? t("hun.tempered") : ''].filter(Boolean).join(' · ');
  }
  async function mount() {
    if (!subscribed && rt()?.subscribe) { subscribed = true; rt().subscribe(event => {
      if (event.type === 'job') {
        const job = event.job;
        if (job.id !== lastJob || job.status === 'pending') return;
        pendingJob = null; showNotice(() => receipt(job), job.status === 'succeeded' ? 'ok' : 'error');
      } else if (event.type === 'state' && event.parts && !event.parts.has('hun') && !event.parts.has('keys') && iconCache === rt()?.state?.icons) return;
      stateChanged();
    }); }
    if (data) { render(); return; }
    const token = ++epoch; busy = true;
    if (root()) root().innerHTML = `<div class="hun-loading" role="status">${t("hun.reading")}</div>`;
    try { const reply = await rt().hun.load(); if (token !== epoch) return; data = reply; draft = clone(reply.profile); baseline = JSON.stringify(draft); notice = reply.error || ''; noticeKind = reply.error ? 'error' : ''; }
    catch (error) { if (root()) root().innerHTML = `<div class="hun-loading"><h2>${t("hun.loadFailed")}</h2><p>${esc(I18N.combatMessage(error.message) || t("hun.connectionError"))}</p><button class="btn btn-secondary" data-hun-action="reload">${t("hun.reload")}</button></div>`; }
    finally { if (token === epoch) { busy = false; render(); } }
  }
  function showNotice(message, kind = '') { notice = message; noticeKind = kind; const box = root()?.querySelector('#hun-message'); if (box) { box.textContent = noticeText(); box.classList.toggle('is-error', kind === 'error'); } }
  function checkInputs() {
    for (const [field, value] of Object.entries(draft.attributes)) {
      const error = window.PGStatLabels?.valueError?.(field, value);
      if (!error) continue;
      if (!open.has('attributes')) { open.add('attributes'); render(); }
      const input = root()?.querySelector(`[data-hun-path="attributes.${CSS.escape(field)}"]`);
      const group = input?.closest('details');
      if (group) group.open = true;
      input?.focus();
      throw new Error(error);
    }
    const invalid = root()?.querySelector('input:invalid,select:invalid');
    if (invalid) { invalid.reportValidity(); throw new Error(t("hun.invalid")); }
  }
  async function save() { const reply = await rt().hun.save({revision: data.revision, profile: clone(draft)}); data = {...data, ...reply}; draft = clone(reply.profile); baseline = JSON.stringify(draft); }
  // One item's settings: on or off, level or refinement, soul-forged form, pick weight, and what it does.
  function inspect(id) {
    const row = data.catalog.items.find(r => r.id === id); if (!row) return;
    const value = draft.items[id], accessory = row.kind === 'accessory', weighted = row.kind === 'main_weapon' || row.kind === 'shadow_armament';
    const dialog = root().querySelector('dialog');
    dialog.innerHTML = `<button class="hun-icon-button hun-dialog-close" data-hun-action="close-dialog" aria-label="${t("hun.close")}">${icon('close')}</button>
      <div class="hun-dialog-top"><div class="hun-dialog-art">${art(id, item(row).name)}</div><div><h2>${esc(displayName(row))}</h2><p>${esc(item(row).description || (row.source === 'resource_only' ? t("hun.storyItem") : t("hun.noDescription")))}</p></div></div>
      <div class="hun-dialog-controls" data-hun-id="${id}">
        <label class="hun-setting-toggle"><span><strong>${t("hun.enable")}</strong></span><input type="checkbox" data-hun-item-field="enabled" ${value.enabled ? 'checked' : ''}></label>
        <label class="hun-field"><span>${accessory ? t("hun.refinement") : t("hun.level")}</span><span class="hun-number"><input type="number" data-hun-item-field="level" value="${value.level === 'max' ? '' : value.level}" min="${accessory ? 0 : 1}" max="${row.level_max || 1}" placeholder="${row.level_max ? t('hun.maxLabel', {n:row.level_max}) : t("hun.unknown")}" ${row.level_max ? '' : 'disabled'}></span></label>
        ${row.soul_option ? `<label class="hun-setting-toggle"><span><strong>${t("hun.soulForm")}</strong></span><input type="checkbox" data-hun-item-field="soul" ${value.soul ? 'checked' : ''}></label>` : ''}
        ${weighted ? `<label class="hun-field"><span>${t("hun.weight")}</span><span class="hun-number"><input type="number" data-hun-item-field="weight" value="${value.weight}" min="0" max="1000" step="0.1"></span><small>${t("hun.weightHint")}</small></label>` : ''}
      </div>
      <dl><div><dt>${t("hun.source")}</dt><dd>${row.source === 'resource_only' ? t("hun.storySource") : t("hun.gameSource")}</dd></div><div><dt>${t("hun.status")}</dt><dd>${wiring()[CATEGORY_WIRING[row.source === 'resource_only' ? 'special' : row.kind]][0]}</dd></div></dl>`;
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
        notice = () => t("hun.draftHint"); noticeKind = ''; render(); return;
      }
      if (name === 'phase-add') { if (draft.phases.length >= 16) return; let id; do { id = 'phase_' + Date.now().toString(36) + '_' + (++serial); } while (draft.phases.some(p => p.id === id)); draft.phases.push({...clone(data.defaults.phases[0]), id, name: `${t("hun.phase")} ` + (draft.phases.length + 1), health_below: .5}); render(); return; }
      if (name === 'phase-remove') { undo = clone(draft); draft.phases.splice(Number(button.dataset.hunIndex), 1); render(); return; }
      checkInputs();
      if (name === 'export') {
        const blob = new Blob([JSON.stringify({format: 'PhantomGladiatorHunProfile', version: 1, profile: draft}, null, 2)], {type: 'application/json'}), url = URL.createObjectURL(blob), link = document.createElement('a');
        link.href = url; link.download = (draft.name.replace(/[\\/:*?"<>|]/g, '_') || t("hun.defaultFile")) + '.json'; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); showNotice(() => t("hun.exported")); return;
      }
      if (name === 'summon' && !canSummon()) { showNotice(availability, 'error'); return; }
      busy = true; notice = () => name === 'summon' ? t("hun.submitting") : t("hun.saving"); noticeKind = ''; render();
      if (name === 'save') { await save(); notice = () => t("hun.saved"); }
      else if (name === 'summon') {
        if (changed()) await save();
        const job = await rt().command('hun_body_probe', {team: button.dataset.hunTeam, count: draft.count, profile_revision: data.revision}); lastJob = job.id; pendingJob = job.status === 'pending' ? job.id : null;
        notice = () => receipt(job); noticeKind = ['pending', 'succeeded'].includes(job.status) ? '' : 'error';
      }
    } catch (error) { showNotice(error.message || t("hun.retry"), 'error'); }
    finally { if (busy) { busy = false; render(); } }
  }
  function edit(el) {
    if (!root()?.contains(el) || !draft || busy) return;
    if (el.matches('[data-hun-search]')) { query = el.value; root().querySelector('[data-hun-grid]').innerHTML = tiles(); return; }
    if (el.matches('[data-hun-only-on]')) { onlyOn = el.checked; root().querySelector('[data-hun-grid]').innerHTML = tiles(); return; }
    if (el.dataset.hunItemField) {
      const id = el.closest('[data-hun-id]').dataset.hunId, key = el.dataset.hunItemField;
      draft.items[id][key] = el.type === 'checkbox' ? el.checked : el.value === '' && key === 'level' ? 'max' : Number(el.value);
      if (key === 'enabled' && onlyOn) root().querySelector('[data-hun-grid]').innerHTML = tiles(); else refreshTile(id);
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
      const file = el.files[0]; if (file.size > 262144) throw new Error(t("hun.oversize")); busy = true; render();
      const reply = await rt().hun.save({revision: data.revision, import_text: await file.text()}); undo = clone(draft); data = {...data, ...reply}; draft = clone(reply.profile); baseline = JSON.stringify(draft); notice = () => t("hun.imported"); noticeKind = '';
    } catch (error) { notice = error.message || t("hun.importFailed"); noticeKind = 'error'; }
    finally { busy = false; render(); }
  });
  document.addEventListener('error', event => { const img = event.target; if (!img?.matches?.('[data-hun-image]') || !root()?.contains(img)) return; failedImages.add(img.getAttribute('src')); img.outerHTML = '<span class="hun-art-empty">' + icon('sword') + '</span>'; }, true);
  return {html, mount, keysChanged};
})();
