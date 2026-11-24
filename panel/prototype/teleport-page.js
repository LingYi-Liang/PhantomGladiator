"use strict";
// The 传送 page (experimental): places the player can be sent to through the game's own teleport. The app sends a
// place code only; the mod looks the coordinates up in its own table (teleport_places.lua). One click teleports.
// Every place, and the return, can have a key of its own (teleport_keys.lua); in the game one press teleports.
// Chinese and English. A place carries both names (teleport-places.json: name, en); what the mod answers is Chinese
// and is put into English here (modText), the place name inside it included.
I18N.add("en", {
  "nav.teleport": "Teleport",
  "action.teleport": "Teleport",
  "action.teleport_back": "Return to where I was",
  "action.configure_teleport_key": "Set teleport hotkey",
  "tp.title": "Teleport (experimental)",
  "tp.subtitle": "Uses the game's own teleport, with a loading screen. It can take you to places the story no longer lets you return to.",
  "tp.warn.title": "Back up your save first",
  "tp.warn.body": "Clicking a place or pressing its hotkey teleports at once, with no confirmation. The game's teleport very likely saves at the new position right away, and this build has not been checked in the game. You land on a developer point or a boss's spawn point; if you fall within 15 seconds of arriving you are put back there. An area whose story is over may have no enemies and no exit. If you cannot get out, use a bell or \"Return to where I was\". You cannot teleport while spectating.",
  "tp.offline": "Game not connected. Enter the game and load a save to teleport.",
  "tp.old": "The mod in the game does not support teleport. Install or update the in-game mod first.",
  "tp.ready": "Ready to teleport.",
  "tp.pending": "Teleporting. Waiting for the game to load…",
  "tp.back": "Return to where I was",
  "tp.search": "Search places or bosses",
  "tp.none": "No matching places.",
  "tp.loading": "Loading the place list…",
  "tp.loadFailed": "Could not load the place list.",
  "tp.retry": "Retry",
  "tp.kind.dev": "Dev point",
  "tp.kind.boss": "BOSS",
  "tp.level": "Lv. {n}",
  "tp.sent": "Sent: {name}",
  "tp.failed": "Not teleported: {why}",
  "tp.count": { one: "{n} place", other: "{n} places" },
  "tp.key.none": "+ Key",
  "tp.key.title": "Give this place a hotkey. In the game, one press teleports.",
  "tp.key.capture": "Press a key (Esc cancels, Delete unbinds)",
  "tp.key.saved": "Hotkey saved: {name} → {key}",
  "tp.key.removed": "Hotkey removed: {name}",
  "tp.key.failed": "Hotkey not saved: {why}",
  "tp.key.invalid": "That key cannot be used as a hotkey.",
  "tp.key.inactive": "This key is not active in the game: {why}",
  "tp.key.bound": "Only places with a hotkey",
});
I18N.add("zh", {
  "nav.teleport": "传送",
  "action.teleport": "传送",
  "action.teleport_back": "返回传送前的位置",
  "action.configure_teleport_key": "设置传送快捷键",
  "tp.title": "传送（试验）",
  "tp.subtitle": "走游戏自己的传送，带加载，可以去流程过后回不去的场景。",
  "tp.warn.title": "先备份存档",
  "tp.warn.body": "点一下地点或按一下快捷键就会立刻传送，没有确认。原生传送很可能会让游戏立刻按新位置存一次档，这一版还没有实机验证过。落点是开发用的点或 BOSS 的出生点，到位后 15 秒内如果掉下去会被拉回落点；剧情已过的场景里可能没有怪，也可能没有出口；出不去就用钟，或点「返回传送前的位置」。自由观战中不能传送。",
  "tp.offline": "游戏未连接。进入游戏并读档后再传送。",
  "tp.old": "游戏里的模组版本不支持传送，请先安装或更新游戏内的模组。",
  "tp.ready": "可以传送。",
  "tp.pending": "正在传送，等待游戏加载……",
  "tp.back": "返回传送前的位置",
  "tp.search": "搜索地点或 BOSS 名",
  "tp.none": "没有匹配的地点。",
  "tp.loading": "正在读取地点清单……",
  "tp.loadFailed": "地点清单读取失败。",
  "tp.retry": "重试",
  "tp.kind.dev": "开发点",
  "tp.kind.boss": "BOSS",
  "tp.level": "{n} 级",
  "tp.sent": "已发出：{name}",
  "tp.failed": "没有传送：{why}",
  "tp.count": "{n} 个地点",
  "tp.key.none": "＋键",
  "tp.key.title": "给这个地点设一个快捷键；在游戏里按一次就传送",
  "tp.key.capture": "按下要用的键（Esc 取消，Delete 解除）",
  "tp.key.saved": "快捷键已保存：{name} → {key}",
  "tp.key.removed": "已解除快捷键：{name}",
  "tp.key.failed": "快捷键没有保存：{why}",
  "tp.key.invalid": "这个键不能用作快捷键。",
  "tp.key.inactive": "这个键在游戏里没有生效：{why}",
  "tp.key.bound": "只看已设快捷键的",
});
window.PGTeleport = (() => {
  const t = (key, params) => I18N.t(key, params);
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const rt = () => window.PGRuntime, root = () => document.querySelector("#teleport-page");
  const BACK = "BACK";
  let data = null, failed = "", loading = false, query = "", onlyBound = false, capture = "", notice = "", noticeKind = "", busy = false, subscribed = false, bound = null, shown = "", keysBound = false;

  // The same chords the mod's key router accepts (key_router.lua Router.valid / Router.label).
  const NAMES = { 8: "Backspace", 9: "Tab", 13: "Enter", 19: "Pause", 20: "CapsLock", 32: "Space", 33: "PageUp", 34: "PageDown", 35: "End", 36: "Home",
    37: "Left", 38: "Up", 39: "Right", 40: "Down", 45: "Insert", 46: "Delete", 106: "Num*", 107: "Num+", 109: "Num-", 110: "Num.", 111: "Num/",
    144: "NumLock", 145: "ScrollLock", 186: ";", 187: "=", 188: ",", 189: "-", 190: ".", 191: "/", 192: "`", 219: "[", 220: "\\", 221: "]", 222: "'" };
  const validKey = vk => Number.isInteger(vk) && (NAMES[vk] !== undefined || (vk >= 48 && vk <= 57) || (vk >= 65 && vk <= 90) || (vk >= 96 && vk <= 135));
  function keyLabel(vk, mask) {
    const pad = window.PGXbox?.label(vk, mask);
    if (pad) return pad;
    const base = NAMES[vk] || ((vk >= 65 && vk <= 90) || (vk >= 48 && vk <= 57) ? String.fromCharCode(vk) : vk >= 96 && vk <= 105 ? "Num" + (vk - 96) : vk >= 112 && vk <= 135 ? "F" + (vk - 111) : "VK" + vk);
    return ["Ctrl", "Alt", "Shift"].filter((_, i) => (mask >> i) & 1).concat(base).join("+");
  }

  // The name shown: English outside Chinese, when the list carries one.
  const label = item => (I18N.lang !== "zh" && item.en) || item.name;
  // What the mod answers, in Chinese, for an English reader. A status is "<place>：<message>"; place names may hold
  // the same colon, the messages below do not, so the last colon is where the place ends.
  const MOD_EN = {
    "地点无效": "Invalid place.", "地图名无效": "Invalid map name.", "坐标无效": "Invalid coordinates.", "朝向无效": "Invalid facing.",
    "玩家不可读": "The player could not be read.", "当前地图名不可读": "The current map could not be read.", "玩家位置不可读": "The player's position could not be read.",
    "模组正在卸载": "The mod is unloading.",
    "上一次传送还在进行，请等它结束": "The previous teleport is still in progress. Wait for it to finish.",
    "找不到游戏的存档传送系统，没有传送": "The game's teleport system was not found. Nothing was done.",
    "传送调用失败，位置没有变": "The teleport call failed. Your position did not change.",
    "已发起传送，等待游戏加载": "Teleport started. Waiting for the game to load.",
    "这次加载还没有传送过，没有可返回的位置": "You have not teleported since this load, so there is nowhere to return to.",
    "已到达": "Arrived.",
    "自由观战中不能传送，请先退出观战": "You cannot teleport while spectating. Exit Spectate first.",
    "传送模块未加载": "The teleport module is not loaded.",
    "这个地点不在本版模组的地点表里，请先更新游戏内的模组": "The mod in the game does not know this place. Update the in-game mod first.",
    "这个地点不在本版模组的地点表里": "The mod in the game does not know this place.",
    "按键格式无效": "Invalid key.", "按键没有注册上": "The key could not be registered.",
    "快捷键保存未读回，旧绑定保留": "The hotkey could not be saved. The previous binding is kept.",
    "当前UE4SS未提供这个按键": "This key is not available in this UE4SS.", "按键路由不可用": "Key handling is not available.",
    "传送返回未确认": "The teleport was not confirmed.",
    "地点清单读取失败": "The place list could not be read.",
  };
  function placeEn(name) {
    if (name === "传送前的位置") return t("tp.back");
    for (const group of data?.groups || []) for (const place of group.places) if (place.name === name) return label(place);
    return name;
  }
  function modText(text) {
    if (typeof text !== "string" || !text || I18N.lang === "zh" || !/[㐀-鿿]/u.test(text)) return text;
    if (Object.hasOwn(MOD_EN, text)) return MOD_EN[text];
    let m;
    if ((m = /^已到达（落下去过，拉回(\d+)次）$/.exec(text))) return `Arrived. You fell and were put back ${m[1]} time(s).`;
    if ((m = /^没有读到到位，当前在 (.+)$/.exec(text))) return `Arrival was not confirmed. You are now at ${m[1] === "不可读" ? "an unknown position" : m[1]}.`;
    if ((m = /^这个组合键已被「传送：(.+)」占用，请先解除那一个$/.exec(text))) return `That key combination is already used by "Teleport: ${placeEn(m[1])}". Unbind that one first.`;
    if ((m = /^该键已被(?:功能|单位|怪物池)?「(.+)」占用$/.exec(text)) || (m = /^该键已被(.+)占用$/.exec(text))) return `That key is already in use (${m[1]}).`;
    const cut = text.lastIndexOf("：");
    if (cut > 0) {
      const rest = modText(text.slice(cut + 1));
      if (rest !== text.slice(cut + 1)) return placeEn(text.slice(0, cut)) + ": " + rest;
    }
    return I18N.combatMessage ? I18N.combatMessage(text) : text;
  }

  function html() { return `<div id="teleport-page" class="tp-page"><div class="tp-loading" role="status">${esc(t("tp.loading"))}</div></div>`; }
  function state() {
    const s = rt()?.state || {}, tp = s.teleport || {};
    const online = rt()?.online ? rt().online() : false;
    return { online, supported: online && tp.supported === true, pending: tp.pending === true, canReturn: tp.canReturn === true, message: tp.message || "", keys: tp.keysRevision || 0 };
  }
  function keyHTML(target, usable) {
    const key = data.keys?.[target], capturing = capture === target;
    const label = capturing ? t("tp.key.capture") : key ? keyLabel(key.key_code, key.modifiers) : t("tp.key.none");
    const title = key && !key.active ? t("tp.key.inactive", { why: modText(key.message || "") }) : t("tp.key.title");
    return `<button class="tp-key${key ? " is-set" : ""}${key && !key.active ? " is-off" : ""}${capturing ? " is-capturing" : ""}" type="button" data-tp-action="key" data-target="${esc(target)}" title="${esc(title)}" ${usable ? "" : "disabled"}>${esc(label)}</button>`;
  }
  function statusHTML() {
    const s = state();
    const text = !s.online ? t("tp.offline") : !s.supported ? t("tp.old") : s.pending ? t("tp.pending") : modText(s.message) || t("tp.ready");
    const tone = !s.online || !s.supported ? "is-warn" : s.pending ? "is-busy" : "";
    const last = notice ? `<span class="tp-notice${noticeKind ? " is-" + noticeKind : ""}">${esc(notice)}</span>` : "";
    return `<div class="tp-status ${tone}" role="status"><span class="tp-state">${esc(text)}</span>${last}
      <span class="tp-back"><button class="btn btn-secondary btn-sm" type="button" data-tp-action="back" ${s.supported && s.canReturn && !s.pending && !busy ? "" : "disabled"}>${esc(t("tp.back"))}</button>${keyHTML(BACK, s.supported && !busy)}</span></div>`;
  }
  function placeHTML(place, s) {
    const tag = place.kind === "boss" ? t("tp.kind.boss") + (place.level ? " · " + t("tp.level", { n: place.level }) : "") : t("tp.kind.dev");
    return `<div class="tp-item"><button class="tp-place" type="button" data-tp-action="go" data-code="${esc(place.code)}" ${s.supported && !s.pending && !busy ? "" : "disabled"}>
      <span class="tp-name">${esc(label(place))}</span><span class="tp-tag tp-tag-${esc(place.kind)}">${esc(tag)}</span></button>${keyHTML(place.code, s.supported && !busy)}</div>`;
  }
  function groupsHTML() {
    const s = state(), q = query.trim().toLowerCase();
    const parts = [];
    for (const group of data.groups) {
      const hit = item => item.name.toLowerCase().includes(q) || (item.en || "").toLowerCase().includes(q);   // either language
      let places = q ? (hit(group) ? group.places : group.places.filter(hit)) : group.places;
      if (onlyBound) places = places.filter(p => data.keys?.[p.code]);
      if (!places.length) continue;
      parts.push(`<section class="card tp-group"><h2 class="tp-group-title">${esc(label(group))}<span class="tp-group-count">${esc(t("tp.count", { n: places.length }))}</span></h2>
        <div class="tp-places">${places.map(p => placeHTML(p, s)).join("")}</div></section>`);
    }
    return parts.length ? parts.join("") : `<p class="tp-empty">${esc(t("tp.none"))}</p>`;
  }
  function render() {
    const el = root();
    if (!el) return;
    if (!data) {
      el.innerHTML = failed
        ? `<div class="tp-loading"><h2>${esc(t("tp.loadFailed"))}</h2><p>${esc(modText(failed))}</p><button class="btn btn-secondary" type="button" data-tp-action="reload">${esc(t("tp.retry"))}</button></div>`
        : `<div class="tp-loading" role="status">${esc(t("tp.loading"))}</div>`;
      return;
    }
    el.innerHTML = `<div class="page-head"><div><h1 class="page-title">${esc(t("tp.title"))}</h1><p class="page-sub">${esc(t("tp.subtitle"))}</p></div></div>
      <div class="callout callout-amber"><div class="callout-body"><strong>${esc(t("tp.warn.title"))}</strong><span>${esc(t("tp.warn.body"))}</span></div></div>
      <div id="tp-status">${statusHTML()}</div>
      <div class="tp-tools"><label class="search tp-search"><input type="search" id="tp-query" value="${esc(query)}" placeholder="${esc(t("tp.search"))}" autocomplete="off"></label>
        <label class="tp-only"><input type="checkbox" id="tp-only" ${onlyBound ? "checked" : ""}> ${esc(t("tp.key.bound"))}</label></div>
      <div id="tp-groups">${groupsHTML()}</div>`;
  }
  // Status and buttons only: the search box keeps its focus and caret.
  function refresh() {
    const el = root();
    if (!el || !data) return render();
    const status = el.querySelector("#tp-status"), groups = el.querySelector("#tp-groups");
    if (status) status.innerHTML = statusHTML();
    if (groups) groups.innerHTML = groupsHTML();
  }
  function nameOf(target) {
    if (target === BACK) return t("tp.back");
    for (const group of data?.groups || []) for (const place of group.places) if (place.code === target) return label(place);
    return "";
  }
  const why = job => modText(job.message) || job.code || job.status;
  async function send(action, payload, name) {
    if (busy) return;
    busy = true; capture = ""; notice = ""; refresh();
    try {
      const job = await rt().command(action, payload);
      if (job.status === "succeeded") { notice = t("tp.sent", { name }); noticeKind = "ok"; }
      else { notice = t("tp.failed", { why: why(job) }); noticeKind = "error"; }
    } catch (error) {
      notice = t("tp.failed", { why: error.detail || error.message || String(error) }); noticeKind = "error";
    }
    busy = false; refresh();
  }
  async function reloadKeys() {
    try { const reply = await rt().teleport.load(); if (data) data.keys = reply.keys || {}; } catch (error) { /* the old keys stay shown */ }
  }
  async function saveKey(target, vk, mask) {
    if (busy) return;
    busy = true; capture = ""; notice = ""; refresh();
    try {
      const job = await rt().command("configure_teleport_key", { place: target, key_code: vk, modifiers: mask });
      if (job.status === "succeeded") {
        await reloadKeys();
        notice = vk ? t("tp.key.saved", { name: nameOf(target), key: keyLabel(vk, mask) }) : t("tp.key.removed", { name: nameOf(target) });
        noticeKind = "ok";
      } else { notice = t("tp.key.failed", { why: why(job) }); noticeKind = "error"; }
    } catch (error) {
      notice = t("tp.key.failed", { why: error.detail || error.message || String(error) }); noticeKind = "error";
    }
    busy = false; refresh();
  }
  function onClick(event) {
    const button = event.target.closest?.("[data-tp-action]");
    if (!button || button.disabled) return;
    const action = button.dataset.tpAction;
    if (action === "reload") { failed = ""; mount(); return; }
    if (action === "key") {
      const target = button.dataset.target;
      capture = capture === target ? "" : target; refresh();
      if (capture && rt().state.xboxKeysSupported) window.PGXbox.capture(
        () => capture === target && !!root() && rt().state.xboxKeysSupported,
        binding => saveKey(target, binding.code, binding.mods),
        () => { capture = ""; refresh(); });
      return;
    }
    capture = "";
    if (action === "back") { send("teleport_back", {}, t("tp.back")); return; }
    const name = nameOf(button.dataset.code);
    if (name) send("teleport", { place: button.dataset.code }, name);
  }
  function onInput(event) {
    if (event.target.id === "tp-only") onlyBound = event.target.checked;
    else if (event.target.id === "tp-query") query = event.target.value;
    else return;
    capture = "";
    const groups = root()?.querySelector("#tp-groups");
    if (groups) groups.innerHTML = groupsHTML();
  }
  // While a key button waits: the next key (with Ctrl / Alt / Shift) becomes that target's key.
  function onKeyDown(event) {
    if (!capture || !root()) return;
    if (event.target?.classList?.contains("xbox-picker") && event.key !== "Escape") return;
    const vk = event.keyCode;
    if (vk === 16 || vk === 17 || vk === 18) return;   // a modifier alone: keep waiting
    event.preventDefault(); event.stopPropagation();
    const target = capture;
    if (vk === 27) { capture = ""; refresh(); return; }
    if (vk === 46 && !event.ctrlKey && !event.altKey && !event.shiftKey) { saveKey(target, 0, 0); return; }
    if (!validKey(vk)) { capture = ""; notice = t("tp.key.invalid"); noticeKind = "error"; refresh(); return; }
    saveKey(target, vk, (event.ctrlKey ? 1 : 0) | (event.altKey ? 2 : 0) | (event.shiftKey ? 4 : 0));
  }
  async function mount() {
    const el = root();
    if (el && bound !== el) { bound = el; el.addEventListener("click", onClick); el.addEventListener("input", onInput); }
    if (!keysBound) { keysBound = true; document.addEventListener("keydown", onKeyDown, true); }
    // The status polls about once a second; the page is redrawn only when the teleport state itself changed.
    if (!subscribed && rt()?.subscribe) { subscribed = true; rt().subscribe(async event => {
      if (event.type !== "state" && event.type !== "demo") return;
      const before = shown ? JSON.parse(shown).keys : 0, s = state();
      const now = JSON.stringify(s);
      if (now === shown || !root()) return;
      shown = now;
      if (data && s.keys !== before && !busy) await reloadKeys();   // keys changed in the game (another window, a restart)
      if (!capture) refresh();
    }); }
    shown = JSON.stringify(state());
    capture = "";
    if (data || loading) { render(); return; }
    loading = true; render();
    try { data = await rt().teleport.load(); data.keys = data.keys || {}; failed = ""; }
    catch (error) { failed = error.detail || error.message || String(error); }
    loading = false; render();
  }
  return { html, mount };
})();
