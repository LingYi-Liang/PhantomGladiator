"use strict";
// The player-facing app. Game data comes from window.PGRuntime: MockRuntime in the clickable
// prototype, RealRuntime (backend.py + native window) in the packaged app. Both share one interface.
(() => {
  const RT = window.PGRuntime, S = RT.state;
  const t = (key, params) => I18N.t(key, params);
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const icon = (name, cls = "") => `<svg class="icon ${cls}" aria-hidden="true"><use href="#i-${name}"/></svg>`;
  const kbd = (label, cls = "") => `<kbd class="kbd ${cls}">${esc(label)}</kbd>`;
  // Escapes a translated template and fills {slots} with trusted HTML (keycaps, links).
  const tHtml = (key, slots) => esc(t(key)).replace(/\{(\w+)\}/g, (m, k) => slots[k] ?? m);
  const store = {
    get(key, fallback) { try { const raw = localStorage.getItem("pg-proto." + key); return raw === null ? fallback : JSON.parse(raw); } catch { return fallback; } },
    set(key, value) { try { localStorage.setItem("pg-proto." + key, JSON.stringify(value)); } catch { /* storage may be unavailable */ } },
    clear() { try { Object.keys(localStorage).filter(k => k.startsWith("pg-proto.")).forEach(k => localStorage.removeItem(k)); } catch { /* ignore */ } },
  };

  const REPO = "https://github.com/LingYi-Liang/PhantomGladiator";
  const BILI = "https://space.bilibili.com/10010098";
  // The eight function keys backend.py accepts (BINDING_NAMES); all of them start unbound.
  const KEY_ICONS = { spawn: "user-plus", start: "play", stop: "trash", cycle_team: "swap", toggle_camera: "video", exit_camera: "x", toggle_spectator: "shield", refresh_catalog: "scan", recall_companions: "zap", toggle_time_stop: "stop" };
  const KEY_GROUPS = [["fight", ["spawn", "start", "stop", "cycle_team"]], ["watch", ["toggle_camera", "exit_camera", "toggle_time_stop", "toggle_spectator"]], ["companion", ["recall_companions"]]];
  const NO_KEYS = Object.fromEntries(Object.keys(KEY_ICONS).map(action => [action, null]));
  const VK_CODES = { Space: 32, Pause: 19, CapsLock: 20, NumLock: 144, ScrollLock: 145, Backquote: 192, NumpadEnter: 13, Tab: 9, Enter: 13, Backspace: 8, Delete: 46, Insert: 45, Home: 36, End: 35, PageUp: 33, PageDown: 34, ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40, Minus: 189, Equal: 187, BracketLeft: 219, BracketRight: 221, Backslash: 220, Semicolon: 186, Quote: 222, Comma: 188, Period: 190, Slash: 191, NumpadAdd: 107, NumpadSubtract: 109, NumpadMultiply: 106, NumpadDivide: 111, NumpadDecimal: 110 };
  const VK_NAMES = { 8: "Backspace", 9: "Tab", 13: "Enter", 32: "Space", 33: "PageUp", 34: "PageDown", 35: "End", 36: "Home", 37: "←", 38: "↑", 39: "→", 40: "↓", 45: "Insert", 46: "Delete", 106: "Num*", 107: "Num+", 109: "Num-", 110: "Num.", 111: "Num/", 186: ";", 187: "=", 188: ",", 189: "-", 190: ".", 191: "/", 219: "[", 220: "\\", 221: "]", 222: "'" };
  const BEGINNER_ID = "BP_Monster_MaleThug_Sword_Blue";
  const TEAMS = ["blue", "red", "neutral", "companion"];

  // ---------- Units ----------
  function initialOf(name) {
    const parts = name.split(/[：:.．]/).filter(Boolean);
    let tail = parts[parts.length - 1] || name;
    if (parts.length > 1 && tail.replace(/[“”"「」]/g, "").length <= 1) tail = parts[0];
    const clean = tail.replace(/[“”"「」『』（）()\s—\-，,]/g, "");
    return (clean || name).charAt(0);
  }
  const UNITS = PG_UNITS.map(u => ({ ...u, zhName: u.name, zhMap: u.map, zhChName: u.chName, initial: initialOf(u.name), search: u.name.toLowerCase() }));
  const byId = new Map(UNITS.map(u => [u.id, u]));
  const buildChapters = () => [...new Map(UNITS.map(u => [u.ch, { ch: u.ch, name: u.chName, map: u.map }])).values()].sort((a, b) => a.ch - b.ch);
  let CHAPTERS = buildChapters();
  // Names from the player's own game, in its language (codex_catalog_export.lua via /api/unit-names), over the
  // Chinese ones units.js ships; the Chinese name stays searchable. The game gives a few different units one name
  // (Zuo Shang in the prologue and at the end), so those also show their map, as team lists show only the name.
  let namesKey = "";
  function applyNames(data) {
    const key = data ? JSON.stringify(data) : "";
    if (key === namesKey) return;
    namesKey = key;
    const uses = new Map();
    for (const u of UNITS) {
      const n = data?.units?.[u.id];
      u.name = n?.name || u.zhName;
      u.map = n?.map || u.zhMap;
      u.chName = n?.chapter || u.zhChName;
      u.initial = initialOf(u.name);
      uses.set(u.name, (uses.get(u.name) || 0) + 1);
    }
    for (const u of UNITS) {
      const place = u.map || u.chName;
      if (uses.get(u.name) > 1 && place) u.name = /[　-鿿＀-￯]/.test(u.name) ? `${u.name}（${place}）` : `${u.name} (${place})`;
      u.search = (u.name === u.zhName ? u.name : `${u.name} ${u.zhName}`).toLowerCase();
    }
    CHAPTERS = buildChapters();
  }

  // ---------- State ----------
  const detected = I18N.detect();
  const ui = {
    page: "arena",
    langMode: store.get("langMode", "auto"),
    lang: "zh",
    theme: store.get("theme", "light"),
    query: "",
    type: "all",
    chapter: "all",
    selectedId: store.get("selected", null),
    team: "blue",
    count: 1,
    roster: { blue: {}, red: {}, neutral: {}, companion: {} },
    lastSolo: null,           // { id, count } of the latest no-team summon, for "summon again"
    busy: new Set(),
    capture: null,            // { kind: "global", action } | { kind: "unit", id }
    keyNote: null,            // { action, type: "err"|"conflict"|"ok", text, key, other }
    unitKeyError: "",
    seenFailures: 0,
    lastCounts: { blue: 0, red: 0 },
    settings: { autoUpdate: store.get("autoUpdate", true), allUnits: store.get("allUnits", false), tech: store.get("tech", false) },
    gamePath: store.get("gamePath", "C:\\Program Files (x86)\\Steam\\steamapps\\common\\PBZ"),
    detecting: false,
    installing: null,
    update: { phase: "idle", info: null, line: "auto", progress: null, error: null, lastChecked: store.get("lastChecked", 0) },
    onboarding: !store.get("onboarded", false),
    onb: { step: 0, detect: "idle", game: null, comps: null },
    demoOpen: false,
    historyOpen: false,
    syncTimer: null,
  };
  ui.lang = ui.langMode === "auto" ? detected.lang : store.get("lang", detected.lang);
  I18N.set(ui.lang);
  if (!byId.has(ui.selectedId)) ui.selectedId = null;
  if (RT.demo) {
    if (ui.onboarding) S.game = "offline";
    S.installed = !ui.onboarding;
  }
  const gamePath = () => S.gamePath || ui.gamePath;

  // ---------- Formatting ----------
  const locale = () => I18N.locale();
  const fmtNum = n => new Intl.NumberFormat(locale()).format(n);
  const fmtBytes = n => `${new Intl.NumberFormat(locale(), { maximumFractionDigits: 1, minimumFractionDigits: 1 }).format(n / 1048576)} MB`;
  const fmtDate = iso => new Intl.DateTimeFormat(locale(), { dateStyle: "medium" }).format(new Date(iso));
  const fmtSeconds = s => new Intl.NumberFormat(locale(), { style: "unit", unit: "second", unitDisplay: "long", maximumFractionDigits: 0 }).format(Math.max(1, Math.round(s)));
  function fmtAgo(ts) {
    const diff = Math.round((ts - Date.now()) / 1000), rtf = new Intl.RelativeTimeFormat(locale(), { numeric: "auto" });
    if (Math.abs(diff) < 60) return rtf.format(Math.min(0, diff), "second");
    if (Math.abs(diff) < 3600) return rtf.format(Math.round(diff / 60), "minute");
    if (Math.abs(diff) < 86400) return rtf.format(Math.round(diff / 3600), "hour");
    return rtf.format(Math.round(diff / 86400), "day");
  }
  const teamName = team => t("team." + team);
  const speciesName = sp => t("species." + sp);
  const chapterName = ch => (ch === 0 ? t("chapter.prologue") : t("chapter.n", { n: ch }));
  const unitMeta = u => [speciesName(u.species), u.ch === 0 ? chapterName(0) : u.map].join(" · ");
  const langName = id => I18N.LANGS.find(l => l.id === id)?.name || id;

  // ---------- Keys ----------
  function vkFromEvent(e) {
    if (/^Key[A-Z]$/.test(e.code)) return e.code.charCodeAt(3);
    if (/^Digit\d$/.test(e.code)) return Number(e.code.slice(5)) + 48;
    if (/^Numpad\d$/.test(e.code)) return Number(e.code.slice(6)) + 96;
    if (/^F\d{1,2}$/.test(e.code)) { const n = Number(e.code.slice(1)); if (n >= 1 && n <= 24) return 111 + n; }
    return VK_CODES[e.code] || null;
  }
  function vkLabel(code, mods = 0) {
    const base = (code >= 65 && code <= 90) || (code >= 48 && code <= 57) ? String.fromCharCode(code)
      : code >= 96 && code <= 105 ? "Num" + (code - 96)
      : code >= 112 && code <= 135 ? "F" + (code - 111)
      : VK_NAMES[code] || "VK" + code;
    return [(mods & 1) && "Ctrl", (mods & 2) && "Alt", (mods & 4) && "Shift", base].filter(Boolean).join("+");
  }
  const keyLabel = b => (b ? vkLabel(b.code, b.mods) : "");
  // What a unit key summons: its own team and count, or (keys saved before that) the current selection.
  const unitKeyUses = k => (!k.team ? t("keys.unit.follow") : k.team === "neutral" ? t("keys.unit.usesNeutral", { n: k.count || 1 })
    : k.team === "companion" ? t("keys.unit.usesCompanion", { n: k.count || 1 }) : t("keys.unit.uses", { team: teamName(k.team), n: k.count || 1 }));
  const keyCap = (b, cls = "") => (b ? kbd(keyLabel(b), cls) : "");
  // Combos the game or Windows already own: the same list as binding_system_owner() in backend.py.
  function systemOwner(code, mods) {
    if (code === 121 || code === 192) return "console";
    if (code === 91 || code === 92) return "win";
    if (code === 82 && mods & 1) return "reload";
    if (code === 115 && mods & 2) return "altF4";
    if (code === 9 && mods & 2) return "altTab";
    if (code === 46 && (mods & 3) === 3) return "cad";
    return "";
  }
  // A main key belongs to one function or one unit at a time, whatever the modifiers (backend.py rule).
  function keyOwner(code, { action, unitId } = {}) {
    const fn = Object.keys(S.keys).find(a => a !== action && S.keys[a]?.code === code);
    if (fn) return { kind: "action", action: fn };
    const unit = Object.entries(S.unitKeys).find(([id, k]) => id !== unitId && k.code === code);
    return unit ? { kind: "unit", id: unit[0] } : null;
  }
  function readCapture(e) {
    if (e.metaKey) return { error: t("keys.err.win") };
    const code = vkFromEvent(e);
    if (!code) return { error: t("keys.err.unknown") };
    const mods = (e.ctrlKey ? 1 : 0) | (e.altKey ? 2 : 0) | (e.shiftKey ? 4 : 0);
    const owner = systemOwner(code, mods);
    return owner ? { error: t("keys.err.system", { key: vkLabel(code, mods), owner: t("keys.sys." + owner) }) } : { code, mods };
  }
  // "Shift+F9 vs F9" reads as a bug unless the message says the two share one main key.
  function clashText(key, theirs, owner) {
    const same = keyLabel(key) === keyLabel(theirs);
    return t(same ? "keys.clash.same" : "keys.clash.main", { key: keyLabel(key), theirs: keyLabel(theirs), owner });
  }

  // ---------- Filters ----------
  function filteredUnits(ignoreType = false) {
    const q = ui.query.trim().toLowerCase();
    return UNITS.filter(u =>
      (ignoreType || ui.type === "all" || (ui.type === "boss") === u.boss) &&
      (ui.chapter === "all" || String(u.ch) === ui.chapter) &&
      (!q || u.search.includes(q)));
  }
  function highlight(text, q) {
    const i = q ? text.toLowerCase().indexOf(q) : -1;
    if (i < 0) return esc(text);
    return esc(text.slice(0, i)) + "<mark>" + esc(text.slice(i, i + q.length)) + "</mark>" + esc(text.slice(i + q.length));
  }

  // ---------- Status helpers ----------
  const selected = () => byId.get(ui.selectedId) || null;
  function connState() {
    switch (S.game) {
      case "offline": return { cls: "is-off", text: t("conn.offline") };
      case "connecting": return { cls: "is-busy", text: t("conn.connecting") };
      case "notInMap": return { cls: "is-warn", text: t("conn.notInMap") };
      case "mismatch": return { cls: "is-error", text: t("conn.mismatch") };
      default: return { cls: "is-ready", text: t("conn.ready") };
    }
  }
  // kind picks the wording: "sel" (summon) or "field" (start a fight).
  function gameBlocker(kind) {
    if (S.game === "offline" || S.game === "connecting") return t(kind + ".blocked.offline");
    if (S.game === "notInMap") return t(kind + ".blocked.notInMap");
    return "";
  }
  // The mod refuses new units until an unfinished cleanup is done (or, after an unknown spawn, a restart).
  const cleanupBlocker = () => (S.cleanup === "spawn_uncertain" ? t("sel.blocked.uncertain") : S.cleanup ? t("sel.blocked.unfinished") : "");
  function summonBlocker() {
    return selected() ? gameBlocker("sel") || cleanupBlocker() : t("sel.blocked.noUnit");
  }
  const synced = () => !!S.synced && S.synced.unit_id === ui.selectedId && S.synced.team === ui.team && S.synced.count === ui.count;
  const fieldTotal = () => RT.owned();

  // ---------- Overlays ----------
  const overlays = $("#overlays");
  let pop = null, dlg = null;
  function openPopover(anchor, html, { cls = "", align = "start", role = "menu" } = {}) {
    closePopover();
    const el = document.createElement("div");
    el.className = "popover " + cls;
    el.setAttribute("role", role);
    el.innerHTML = html;
    overlays.appendChild(el);
    const r = anchor.getBoundingClientRect(), w = el.offsetWidth, h = el.offsetHeight;
    let left = align === "end" ? r.right - w : align === "center" ? r.left + r.width / 2 - w / 2 : r.left;
    left = Math.max(8, Math.min(left, innerWidth - w - 8));
    const top = r.bottom + h + 8 > innerHeight ? Math.max(8, r.top - h - 6) : r.bottom + 6;
    Object.assign(el.style, { left: left + "px", top: top + "px" });
    anchor.setAttribute("aria-expanded", "true");
    pop = { el, anchor };
    (el.querySelector(".menu-item[aria-checked='true'], .menu-item, button") || el).focus?.();
  }
  function closePopover(restore = false) {
    if (!pop) return;
    pop.el.remove();
    pop.anchor.setAttribute("aria-expanded", "false");
    if (restore) pop.anchor.focus();
    pop = null;
  }
  function openDialog(kind, html, cls = "") {
    closePopover();
    closeDialog(false);
    const wrap = document.createElement("div");
    wrap.innerHTML = `<div class="backdrop" data-action="dialog-dismiss"></div><div class="dialog-wrap"><div class="dialog ${cls}" id="dialog" role="dialog" aria-modal="true" aria-labelledby="dlg-title" tabindex="-1">${html}</div></div>`;
    overlays.appendChild(wrap);
    dlg = { kind, wrap, prev: document.activeElement };
    document.body.classList.add("has-dialog");
    const target = wrap.querySelector("[data-autofocus]") || wrap.querySelector(".dialog-foot .btn-primary:not(:disabled), .dialog-foot .btn:not(:disabled)") || $("#dialog");
    target.focus();
  }
  function setDialog(html) {
    if (!dlg) return;
    const box = $("#dialog");
    box.innerHTML = html;
    // Content swaps (checking → available → done) keep keyboard users on the next sensible control.
    if (!box.contains(document.activeElement) || document.activeElement === box) (box.querySelector("[data-autofocus]") || box).focus();
  }
  // Download ticks touch only the bar and numbers, so focus and screen readers are not disturbed 5× a second.
  function patchDownload() {
    const u = ui.update, p = u.progress, bar = $("#dialog .progress > i"), meta = $$("#dialog .progress-meta span");
    if (u.phase !== "downloading" || !bar || meta.length < 2) return false;
    bar.style.width = (p.done / p.total * 100).toFixed(1) + "%";
    meta[0].textContent = `${fmtBytes(p.done)} / ${fmtBytes(p.total)} · ${fmtBytes(p.speed)}/s`;
    meta[1].textContent = t("update.eta", { time: fmtSeconds((p.total - p.done) / Math.max(p.speed, 1)) });
    return true;
  }
  function closeDialog(restore = true) {
    if (!dlg) return;
    const { wrap, prev, kind } = dlg;
    dlg = null;
    wrap.remove();
    document.body.classList.remove("has-dialog");
    if (kind === "update" && ui.update.dl) { ui.update.dl.cancel(); ui.update.dl = null; ui.update.phase = "available"; }
    if (restore && prev && document.contains(prev)) prev.focus();
  }

  // ---------- Toasts ----------
  let toastSeq = 0;
  const TOAST_ICONS = { success: "check", error: "x", warning: "alert", info: "info" };
  function toast({ id, kind = "info", title, body = "", actions = [], timeout }) {
    const tid = id || ++toastSeq;
    let el = $(`[data-toast="${tid}"]`);
    if (!el) {
      el = document.createElement("div");
      el.dataset.toast = tid;
      $("#toasts").appendChild(el);
      const all = $$("#toasts .toast:not(.is-leaving)");
      if (all.length > 4) dismissToast(all[0].dataset.toast);
    }
    el.className = `toast toast-${kind}`;
    el.setAttribute("role", kind === "error" ? "alert" : "status");
    el.innerHTML = `<div class="toast-icon">${kind === "pending" ? '<span class="spinner"></span>' : icon(TOAST_ICONS[kind])}</div>
      <div class="toast-main"><div class="toast-title">${esc(title)}</div>${body ? `<div class="toast-body">${esc(body)}</div>` : ""}
      ${actions.length ? `<div class="toast-actions">${actions.map(a => `<button class="btn-link" type="button" data-action="${a.action}" data-toast-id="${tid}">${esc(a.label)}</button>`).join("")}</div>` : ""}</div>
      <button class="icon-btn icon-btn-sm" type="button" data-action="toast-close" data-toast-id="${tid}" aria-label="${esc(t("common.close"))}">${icon("x", "icon-sm")}</button>`;
    clearTimeout(el._timer);
    const ms = timeout ?? (kind === "pending" ? 0 : kind === "error" ? 9000 : kind === "warning" ? 7000 : 4200);
    if (ms) el._timer = setTimeout(() => dismissToast(tid), ms);
    return tid;
  }
  function dismissToast(id) {
    const el = $(`[data-toast="${id}"]`);
    if (!el || el.classList.contains("is-leaving")) return;
    el.classList.add("is-leaving");
    setTimeout(() => el.remove(), 200);
  }

  // ---------- Shell ----------
  function applyStatic() {
    const lang = I18N.LANGS.find(l => l.id === ui.lang);
    document.documentElement.lang = lang.html;
    document.documentElement.dataset.theme = ui.theme;
    document.title = `${t("app.title")} · ${t("app.subtitle")}`;
    $$("[data-i18n]").forEach(el => { el.textContent = t(el.dataset.i18n); });
    $$("[data-i18n-attr]").forEach(el => {
      el.dataset.i18nAttr.split(";").forEach(pair => { const [attr, key] = pair.split(":"); el.setAttribute(attr, t(key)); });
    });
  }
  function renderTopbar() {
    const c = connState();
    $("#conn-pill").className = "conn-pill " + c.cls;
    $("#conn-text").textContent = c.text;
    $("#lang-label").textContent = langName(ui.lang);
    const toDark = ui.theme !== "dark";
    $("#btn-theme").innerHTML = icon(toDark ? "moon" : "sun");
    $("#btn-theme").setAttribute("aria-label", t(toDark ? "header.themeDark" : "header.themeLight"));
    $("#btn-theme").title = t(toDark ? "header.themeDark" : "header.themeLight");
    $("#update-dot").hidden = !(ui.update.info && !ui.update.info.latest && !ui.update.info.rollback && ui.update.phase !== "done");
    const failures = RT.jobs.filter(j => j.status === "failed" || j.status === "uncertain").length - ui.seenFailures;
    $("#history-badge").hidden = failures <= 0 || ui.historyOpen;
    $("#history-badge").textContent = failures;
  }
  function renderRail() {
    $$(".nav-item").forEach(b => { if (b.dataset.page === ui.page) b.setAttribute("aria-current", "page"); else b.removeAttribute("aria-current"); });
  }
  function renderAll() {
    applyStatic();
    renderTopbar();
    renderRail();
    renderPage();
    if (ui.onboarding) renderOnboarding();
    if (ui.demoOpen) renderDemo();
    if (dlg?.kind === "update") setDialog(updateHTML());
    if (dlg?.kind === "history") setDialog(historyHTML());
  }
  function go(page) {
    if (ui.capture) cancelCapture();
    ui.page = page;
    renderRail();
    renderPage();
    // Only a real navigation fades in; re-renders of the same page stay still.
    $("#content .page")?.classList.add("is-entering");
    $("#grid")?.classList.add("is-entering");
  }
  function renderPage() {
    const content = $("#content");
    document.body.classList.toggle("has-dock", ui.page === "arena");
    if (ui.page === "arena") {
      content.innerHTML = arenaHTML();
      renderToolbar();
      renderGrid();
      renderDock();
      return;
    }
    const html = { hotkeys: hotkeysHTML, fun: funHTML, settings: settingsHTML, about: aboutHTML }[ui.page]();
    content.innerHTML = `<div class="page page-scroll scroll">${html}</div>`;
  }

  // ---------- Arena: catalog ----------
  function arenaHTML() {
    return `<div class="page arena">
      <section class="catalog-col scroll" id="catalog-col" aria-labelledby="arena-title">
        <div class="catalog-head">
          <div><h1 class="page-title" id="arena-title">${esc(t("arena.title"))}</h1><p class="page-sub">${esc(t("arena.subtitle"))}</p></div>
          <label class="search">${icon("search")}
            <input id="search" type="search" autocomplete="off" spellcheck="false" placeholder="${esc(t("search.placeholder"))}" aria-label="${esc(t("search.placeholder"))}" value="${esc(ui.query)}">
            <span class="search-end" id="search-end"></span>
          </label>
        </div>
        <div class="toolbar" id="toolbar"></div>
        <div id="grid" role="list"></div>
      </section>
      <aside class="dock" id="dock" aria-label="${esc(t("dock.label"))}">
        <div class="dock-scroll scroll">
          <div id="dock-banner"></div>
          <section class="dock-section" id="dock-sel"></section>
          <section class="dock-section" id="dock-solo" aria-labelledby="solo-title"></section>
          <section class="dock-section" id="dock-companion" aria-labelledby="companion-title"></section>
          <section class="dock-section" id="dock-diff" aria-labelledby="diff-title"></section>
          <section class="dock-section" id="dock-match" aria-labelledby="match-title"></section>
          <section class="dock-section" id="dock-view"></section>
        </div>
        <section class="dock-footer" id="dock-battle" aria-label="${esc(t("field.title"))}"></section>
      </aside>
    </div>`;
  }
  function renderSearchEnd() {
    const end = $("#search-end");
    if (!end) return;
    end.innerHTML = ui.query
      ? `<button class="icon-btn icon-btn-sm" type="button" data-action="clear-search" aria-label="${esc(t("search.clear"))}">${icon("x", "icon-sm")}</button>`
      : kbd("/");
  }
  function renderToolbar() {
    const bar = $("#toolbar");
    if (!bar) return;
    renderSearchEnd();
    const base = filteredUnits(true), shown = filteredUnits().length;
    const counts = { all: base.length, minion: base.filter(u => !u.boss).length, boss: base.filter(u => u.boss).length };
    const chapterOptions = CHAPTERS.map(c => {
      const n = UNITS.filter(u => u.ch === c.ch).length;
      const label = c.ch === 0 ? chapterName(0) : `${chapterName(c.ch)} · ${c.name}`;
      return `<option value="${c.ch}" ${ui.chapter === String(c.ch) ? "selected" : ""}>${esc(label)}（${n}）</option>`;
    }).join("");
    bar.innerHTML = `
      <div class="seg" role="radiogroup" aria-label="${esc(t("filter.type"))}">
        ${["all", "minion", "boss"].map(k => `<button class="seg-btn" type="button" role="radio" aria-checked="${ui.type === k}" data-action="type" data-type="${k}">${k === "boss" ? icon("crown", "icon-sm") : ""}${esc(t("filter." + k))}<span class="count">${counts[k]}</span></button>`).join("")}
      </div>
      <select class="select" id="chapter" aria-label="${esc(t("filter.chapter"))}">
        <option value="all">${esc(t("filter.allChapters"))}</option>${chapterOptions}
      </select>
      ${ui.settings.allUnits ? `<span class="chip chip-amber">${icon("flask")}${esc(t("filter.allUnitsOn"))}</span>` : ""}
      <span class="toolbar-end" aria-live="polite">${esc(t("grid.count", { n: shown }))}</span>`;
  }
  function cardHTML(u, q, focusable) {
    const sel = u.id === ui.selectedId, key = S.unitKeys[u.id];
    const chips = [
      u.status === "verified" || u.status === "spawn" ? `<span class="chip chip-green">${icon("check-circle")}${esc(t("badge.verified"))}</span>` : "",
      u.status === "special" ? `<span class="chip chip-red">${icon("alert")}${esc(t("badge.special"))}</span>` : "",
      u.variant ? `<span class="chip">${esc(t("badge.variant", { i: u.variant, n: u.variants }))}</span>` : "",
    ].join("");
    return `<div class="unit-card${sel ? " is-selected" : ""}" role="listitem" data-id="${u.id}">
      <button class="card-main" type="button" data-action="select" data-id="${u.id}" tabindex="${focusable ? 0 : -1}" aria-pressed="${sel}" aria-keyshortcuts="B R N" aria-label="${esc(u.name)}${u.boss ? " · BOSS" : ""}">
        <span class="avatar sp-${u.species}${u.boss ? " is-boss" : ""}${artClass(u)}">
          ${avatarArt(u)}<span class="avatar-initial" aria-hidden="true">${esc(u.initial)}</span>
          ${u.boss ? `<span class="avatar-tag">${icon("crown")}BOSS</span>` : ""}
          ${key ? `<span class="avatar-key${key.team ? " key-" + key.team : ""}">${kbd(vkLabel(key.code, key.mods))}</span>` : ""}
          ${sel ? `<span class="avatar-check">${icon("check")}</span>` : ""}
        </span>
        <span class="unit-body">
          <span class="card-name">${highlight(u.name, q)}</span>
          <span class="card-meta">${esc(unitMeta(u))}</span>
          ${chips ? `<span class="card-chips">${chips}</span>` : ""}
        </span>
      </button>
      <div class="card-quick">
        <button class="quick-btn quick-blue" type="button" tabindex="-1" data-action="quick" data-team="blue" data-id="${u.id}" title="${esc(t("card.quickTitle", { n: ui.count, team: teamName("blue") }))}">${icon("plus")}${esc(teamName("blue"))}</button>
        <button class="quick-btn quick-red" type="button" tabindex="-1" data-action="quick" data-team="red" data-id="${u.id}" title="${esc(t("card.quickTitle", { n: ui.count, team: teamName("red") }))}">${icon("plus")}${esc(teamName("red"))}</button>
      </div>
    </div>`;
  }
  // The codex bust the mod saved on this PC (codex_icons.lua), over the species colour; the name's first
  // character until it exists, or if it fails to load (see the error listener below).
  const artClass = u => (S.icons?.[u.id] ? " has-art" : "");
  const avatarArt = u => (S.icons?.[u.id] ? `<img class="avatar-art" src="${esc(S.icons[u.id])}" alt="" loading="lazy" decoding="async" draggable="false">` : "");
  function renderGrid({ animate = false } = {}) {
    const grid = $("#grid");
    if (!grid) return;
    grid.classList.toggle("is-entering", animate);
    const list = filteredUnits(), q = ui.query.trim().toLowerCase();
    if (!list.length) {
      grid.innerHTML = `<div class="empty"><span class="empty-icon">${icon("search")}</span><h3>${esc(t("grid.empty.title"))}</h3><p>${esc(t("grid.empty.body"))}</p><button class="btn btn-secondary btn-sm" type="button" data-action="clear-filters">${esc(t("filter.clear"))}</button></div>`;
      return;
    }
    const focusId = list.some(u => u.id === ui.selectedId) ? ui.selectedId : list[0].id;
    const groups = new Map();
    for (const u of list) { if (!groups.has(u.ch)) groups.set(u.ch, []); groups.get(u.ch).push(u); }
    grid.innerHTML = [...groups].map(([ch, units]) => {
      const c = CHAPTERS.find(x => x.ch === ch);
      return `<section class="group" aria-label="${esc(chapterName(ch))}">
        <div class="group-head"><h3>${esc(ch === 0 ? chapterName(0) : `${chapterName(ch)} · ${c.name}`)}</h3>${ch === 0 ? "" : `<span class="group-map">${esc(c.map)}</span>`}<span class="group-count">${fmtNum(units.length)}</span></div>
        <div class="unit-grid">${units.map(u => cardHTML(u, q, u.id === focusId)).join("")}</div>
      </section>`;
    }).join("");
  }
  function markSelection() {
    $$(".unit-card").forEach(card => {
      const on = card.dataset.id === ui.selectedId, main = card.querySelector(".card-main");
      card.classList.toggle("is-selected", on);
      main.setAttribute("aria-pressed", on);
      main.tabIndex = on ? 0 : -1;
      const avatar = card.querySelector(".avatar"), check = avatar.querySelector(".avatar-check");
      if (on && !check) avatar.insertAdjacentHTML("beforeend", `<span class="avatar-check">${icon("check")}</span>`);
      if (!on && check) check.remove();
    });
  }
  function selectUnit(id, { scroll = false } = {}) {
    ui.selectedId = id;
    ui.unitKeyError = "";
    const own = S.unitKeys[id];
    if (own?.team) { ui.team = own.team; ui.count = own.count || ui.count; }
    store.set("selected", id);
    markSelection();
    renderSelection();
    scheduleSync();
    if (scroll) $(`.unit-card[data-id="${id}"]`)?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }
  function moveGridFocus(from, dir) {
    const cards = $$(".card-main", $("#grid")), i = cards.indexOf(from);
    if (i < 0) return;
    let target = null;
    if (dir === "ArrowLeft") target = cards[i - 1];
    else if (dir === "ArrowRight") target = cards[i + 1];
    else {
      const r = from.getBoundingClientRect(), cx = r.left + r.width / 2, down = dir === "ArrowDown";
      let best = Infinity;
      for (const c of cards) {
        const cr = c.getBoundingClientRect();
        if (down ? cr.top <= r.top + 4 : cr.top >= r.top - 4) continue;
        const score = Math.abs(cr.top - r.top) * 4 + Math.abs(cr.left + cr.width / 2 - cx);
        if (score < best) { best = score; target = c; }
      }
    }
    if (!target) return;
    cards.forEach(c => { c.tabIndex = c === target ? 0 : -1; });
    target.focus();
    target.scrollIntoView({ block: "nearest" });
  }

  // ---------- Arena: dock ----------
  function renderDock() {
    renderBanner();
    renderSelection();
    renderSolo();
    renderCompanion();
    renderDifficulty();
    renderMatch();
    renderBattle();
    renderView();
  }
  function renderBanner() {
    const el = $("#dock-banner");
    if (!el) return;
    const map = {
      offline: ["amber", "gamepad", "banner.offline.title", "banner.offline.body", `<button class="btn btn-secondary btn-sm" type="button" data-action="launch-game">${icon("gamepad", "icon-sm")}${esc(t("conn.launch"))}</button>`],
      connecting: ["blue", "", "banner.connecting.title", "banner.connecting.body", ""],
      notInMap: ["amber", "monitor", "banner.notInMap.title", "banner.notInMap.body", ""],
      mismatch: ["red", "alert", "banner.mismatch.title", "", `<button class="btn btn-secondary btn-sm" type="button" data-action="nav" data-page="settings">${icon("download", "icon-sm")}${esc(t("conn.updateMod"))}</button>`],
      modUpdate: ["amber", "download", "conn.mismatch", "banner.modUpdate.body", `<button class="btn btn-secondary btn-sm" type="button" data-action="nav" data-page="settings">${icon("download", "icon-sm")}${esc(t("conn.updateMod"))}</button>`],
    }[modOutdated() && S.game === "offline" ? "modUpdate" : S.game];
    let html = "";
    if (map) {
      const [tone, ic, title, body, action] = map;
      const text = S.game === "mismatch" ? t("conn.hint.mismatch", { mod: S.modVersion, app: S.expectedBuild || S.appVersion }) : t(body);
      html = `<div class="callout callout-${tone} dock-banner">${ic ? icon(ic) : '<span class="spinner"></span>'}<div class="callout-body"><strong>${esc(t(title))}</strong><span>${esc(text)}</span>${action ? `<div class="callout-actions">${action}</div>` : ""}</div></div>`;
    }
    el.innerHTML = html + queueBannerHTML();
  }
  // Commands the game has not taken for a while (backend.py), with what holds them and the way to clear them.
  function queueBannerHTML() {
    const q = S.queue;
    if (!q?.stuck || !RT.online()) return "";
    const key = "queue.reason." + q.code, reason = q.code ? t(key) : "";
    const text = t("queue.wait", { n: q.count, s: Math.max(1, Math.round((Date.now() - q.since) / 1000)) }) + (reason && reason !== key ? " " + reason : "");
    const busy = ui.busy.has("clearQueue");
    return `<div class="callout callout-amber dock-banner">${icon("alert")}<div class="callout-body"><strong>${esc(t("queue.title"))}</strong><span>${esc(text)}</span>
      <div class="callout-actions"><button class="btn btn-primary btn-sm" type="button" data-action="clear-queue" ${busy ? "disabled" : ""}>${busy ? '<span class="spinner" style="width:12px;height:12px"></span>' : icon("trash", "icon-sm")}${esc(t("queue.clear"))}</button>
      <button class="btn btn-secondary btn-sm" type="button" data-action="open-history">${esc(t("history.open"))}</button></div></div></div>`;
  }
  function statusNote(u) {
    const map = { verified: ["verified", "check-circle"], spawn: ["spawn", "info"], experimental: ["experimental", "flask"], special: ["special", "alert"] };
    const [cls, ic] = map[u.status];
    return `<div class="status-note status-${cls}">${icon(ic)}<span>${esc(t("status." + u.status))}</span></div>`;
  }
  function renderSelection() {
    const el = $("#dock-sel");
    if (!el) return;
    const u = selected();
    if (!u) {
      const b = byId.get(BEGINNER_ID);
      el.innerHTML = `<div class="dock-title">${esc(t("sel.title"))}</div>
        <div class="empty" style="padding:8px 0 4px"><span class="empty-icon">${icon("target")}</span><h3>${esc(t("sel.empty.title"))}</h3><p>${esc(t("sel.empty.body"))}</p></div>
        ${b ? `<div class="callout callout-green" style="margin-top:12px">${icon("sparkles")}<div class="callout-body"><strong>${esc(t("sel.tip.title"))}</strong><span>${esc(t("sel.tip.body", { name: b.name }))}</span><div class="callout-actions"><button class="btn btn-secondary btn-sm" type="button" data-action="select" data-id="${b.id}" data-scroll="1">${esc(t("sel.tip.action", { name: b.name }))}</button></div></div></div>` : ""}`;
      return;
    }
    const blocker = summonBlocker(), busy = ui.busy.has("spawn");
    const label = busy ? t("sel.summoning") : ui.team === "neutral" ? t("sel.summonNeutral", { n: ui.count })
      : ui.team === "companion" ? t("sel.summonCompanion", { n: ui.count }) : t("sel.summonTo", { n: ui.count, team: teamName(ui.team) });
    const btnTone = { blue: "btn-blue", red: "btn-red", neutral: "btn-neutral", companion: "btn-companion" }[ui.team];
    let hint;
    if (blocker) hint = `${icon("info")}<span>${esc(blocker)}</span>`;
    else if (synced() && S.keys.spawn) hint = `<span class="sync-ok">${icon("check-circle")}</span><span>${tHtml("sel.synced", { key: keyCap(S.keys.spawn) })}</span>`;
    else if (synced()) hint = `<span class="sync-ok">${icon("check-circle")}</span><span>${esc(t("sel.synced.nokey"))}</span><button class="btn-link" type="button" data-action="nav" data-page="hotkeys">${esc(t("sel.synced.setKey"))}</button>`;
    else hint = `<span class="spinner" style="width:12px;height:12px"></span><span>${esc(t("sel.syncing"))}</span>`;
    // Says what equal stats will do to this summon before the player clicks.
    const m = S.statMatch, base = m.baseline && byId.get(m.baseline.id);
    const matchLine = m.mode === "match" && RT.online() && !blocker
      ? `<button class="match-line" type="button" data-action="match-focus">${icon("scale")}<span>${esc(base ? t("match.next.match", { name: base.name }) : t("match.next.baseline"))}</span></button>`
      : m.mode === "custom" && RT.online() && !blocker && ui.team !== "companion"
      ? `<button class="match-line" type="button" data-action="match-focus">${icon("sliders")}<span>${esc(t("stats.next.custom", { n: m.customCount }))}</span></button>`
      : "";
    // A no-team unit keeps the game's hostility, but spectator mode (or the F6 camera) stops it attacking the player.
    const soloLine = ui.team === "neutral" && S.spectator && RT.online() && !blocker
      ? `<div class="solo-line">${icon("shield", "icon-sm")}<span>${esc(t("sel.soloSpectator"))}</span></div>`
      : "";
    const key = S.unitKeys[u.id], capturing = ui.capture?.kind === "unit" && ui.capture.id === u.id;
    el.innerHTML = `<div class="dock-title">${esc(t("sel.title"))}${u.boss ? `<span class="chip chip-gold">${icon("crown")}BOSS</span>` : ""}</div>
      <div class="sel-head">
        <span class="avatar sp-${u.species}${u.boss ? " is-boss" : ""}${artClass(u)}">${avatarArt(u)}<span class="avatar-initial" aria-hidden="true">${esc(u.initial)}</span></span>
        <div style="min-width:0"><div class="sel-name">${esc(u.name)}</div>
          <div class="sel-meta"><span>${esc(speciesName(u.species))}</span><span>·</span><span>${esc(u.ch === 0 ? chapterName(0) : `${chapterName(u.ch)} ${u.map}`)}</span>${u.variant ? `<span class="chip">${esc(t("badge.variant", { i: u.variant, n: u.variants }))}</span>` : ""}</div>
        </div>
      </div>
      ${statusNote(u)}
      ${ui.settings.tech ? `<div class="tech">${esc(t("sel.internal"))}: ${esc(u.id)}</div>` : ""}
      <div class="field">
        <div class="field-label">${esc(t("sel.team"))}<small>${esc(t("sel.teamHelp." + ui.team))}</small></div>
        <div class="team-seg" role="radiogroup" aria-label="${esc(t("sel.team"))}">
          ${TEAMS.map(team => `<button class="team-btn team-${team}" type="button" role="radio" aria-checked="${ui.team === team}" data-action="team" data-team="${team}"><span class="team-dot"></span>${esc(teamName(team))}</button>`).join("")}
        </div>
      </div>
      <div class="field">
        <div class="field-label">${esc(t("sel.count"))}<small>${esc(t("sel.countHelp"))}</small></div>
        <div class="count-row">
          <div class="stepper">
            <button type="button" data-action="count-dec" aria-label="${esc(t("sel.countDec"))}" ${ui.count <= 1 ? "disabled" : ""}>${icon("minus")}</button>
            <input id="count-input" type="text" inputmode="numeric" value="${ui.count}" aria-label="${esc(t("sel.count"))}">
            <button type="button" data-action="count-inc" aria-label="${esc(t("sel.countInc"))}" ${ui.count >= MAX_COUNT ? "disabled" : ""}>${icon("plus")}</button>
          </div>
          <div class="count-presets">${[1, 5, 10, 50].map(n => `<button class="preset" type="button" data-action="count-preset" data-n="${n}" aria-pressed="${ui.count === n}">${n}</button>`).join("")}</div>
        </div>
      </div>
      ${levelField(u)}
      <div class="summon-wrap">
        <button class="btn btn-lg btn-block ${btnTone}" type="button" data-action="summon" ${blocker || busy ? "disabled" : ""} aria-keyshortcuts="Control+Enter">
          ${busy ? '<span class="spinner"></span>' : icon("user-plus")}<span>${esc(label)}</span>${busy ? "" : keyCap(S.keys.spawn)}
        </button>
        <div class="hint-line" aria-live="polite">${hint}</div>
        ${matchLine}${soloLine}
      </div>
      <div class="unitkey-line">
        <span class="unitkey-label">${esc(t("sel.unitKey"))}${key && !capturing ? `<small>${esc(unitKeyUses(key))}</small>` : ""}</span>
        <span style="display:flex;gap:4px;align-items:center">
          <button class="unitkey-btn${capturing ? " is-capturing" : ""}" type="button" data-action="unitkey-capture" data-id="${u.id}" ${RT.online() ? "" : "disabled"} title="${esc(t("sel.unitKeyHelp"))}">
            ${capturing ? esc(t("sel.unitKeyCapture")) : key ? `${icon("keyboard", "icon-sm")}${esc(vkLabel(key.code, key.mods))}` : `${icon("plus", "icon-sm")}${esc(t("sel.unitKeyBind"))}`}
          </button>
          ${key && !capturing ? `<button class="icon-btn icon-btn-sm" type="button" data-action="unitkey-remove" data-id="${u.id}" aria-label="${esc(t("keys.unit.remove"))}" title="${esc(t("keys.unit.remove"))}">${icon("x", "icon-sm")}</button>` : ""}
        </span>
      </div>
      ${ui.unitKeyError ? `<div class="inline-error">${icon("alert")}<span>${esc(ui.unitKeyError)}</span></div>` : ""}`;
  }
  // No-team units (team "neutral" in backend.py) keep the game's own hostility, so this is how a
  // player fights a boss themselves. Counted and cleaned up apart from Blue and Red, like the old panel.
  const soloAgainLabel = () => {
    const u = byId.get(ui.lastSolo?.id);
    return u ? t("solo.again", { name: u.name }) + (ui.lastSolo.count > 1 ? ` ×${ui.lastSolo.count}` : "") : "";
  };
  function renderSolo() {
    const el = $("#dock-solo");
    if (!el) return;
    const alive = S.neutral, down = S.down.neutral, held = alive + down, online = RT.online();
    const busy = ui.busy.has("clear_neutral") || ui.busy.has("solo-again");
    const chips = Object.entries(ui.roster.neutral)
      .map(([id, n]) => `<span class="roster-item" title="${esc(byId.get(id)?.name)} ×${n}"><span>${esc(byId.get(id)?.name)}</span><b>×${n}</b></span>`).join("");
    // Boss practice: once everything here is down, one click clears the bodies and summons the same unit again.
    const again = ui.lastSolo && alive === 0 && down > 0
      ? `<button class="btn btn-secondary btn-sm" type="button" data-action="solo-again" title="${esc(t("solo.againHint"))}" ${RT.ready() && !busy && !ui.busy.has("spawn") ? "" : "disabled"}>${icon("refresh", "icon-sm")}<span>${esc(soloAgainLabel())}</span></button>`
      : "";
    const use = !held && ui.team !== "neutral"
      ? `<button class="btn btn-secondary btn-sm" type="button" data-action="team" data-team="neutral">${esc(t("solo.use"))}</button>`
      : "";
    const warn = online && S.spectator && alive > 0
      ? `<div class="solo-warn">${icon("shield", "icon-sm")}<span>${esc(t("solo.spectatorWarn"))}</span>${S.freeCam ? "" : `<button class="btn-link" type="button" data-action="spectator" ${ui.busy.has("toggle_spectator") || S.spectatorPhase ? "disabled" : ""}>${esc(t("solo.spectatorOff"))}</button>`}</div>`
      : "";
    el.innerHTML = `<div class="dock-title"><span id="solo-title">${esc(teamName("neutral"))}</span></div>
      ${held
        ? `<div class="side-chips solo-roster">${chips}</div>
           <div class="solo-stats">${esc(t("solo.stats", { alive: fmtNum(alive), down: fmtNum(down) }))}</div>`
        : `<p class="solo-desc">${esc(t("solo.desc"))}</p>`}
      ${warn}
      <div class="solo-actions">${again}${use}
        <button class="btn btn-ghost btn-sm solo-clear" type="button" data-action="clear-neutral" ${online && held && !busy ? "" : "disabled"}>${ui.busy.has("clear_neutral") ? '<span class="spinner" style="width:12px;height:12px"></span>' : icon("trash", "icon-sm")}<span>${esc(t("solo.clear"))}</span></button>
      </div>
      ${held ? `<p class="solo-note">${esc(t("solo.clearNote"))}</p>` : ""}`;
  }
  // Companions (team "companion", companion.lua): they follow the player with the game's own helper-NPC follow
  // state and fight on the player's side. "Stop and clear" leaves them; only dismissing removes them.
  function renderCompanion() {
    const el = $("#dock-companion");
    if (!el) return;
    const alive = S.companion, down = S.down.companion, held = alive + down, online = RT.online();
    const busy = ui.busy.has("dismiss_companions"), recalling = ui.busy.has("recall_companions");
    const chips = Object.entries(ui.roster.companion)
      .map(([id, n]) => `<span class="roster-item" title="${esc(byId.get(id)?.name)} ×${n}"><span>${esc(byId.get(id)?.name)}</span><b>×${n}</b></span>`).join("");
    const use = !held && ui.team !== "companion"
      ? `<button class="btn btn-secondary btn-sm" type="button" data-action="team" data-team="companion">${esc(t("companion.use"))}</button>`
      : "";
    const warn = online && held && S.companionFailures
      ? `<div class="solo-warn">${icon("alert", "icon-sm")}<span>${esc(t("companion.followWarn"))}</span></div>`
      : "";
    el.innerHTML = `<div class="dock-title"><span id="companion-title">${esc(teamName("companion"))}</span></div>
      ${held
        ? `<div class="side-chips companion-roster">${chips}</div>
           <div class="solo-stats">${esc(t("companion.stats", { alive: fmtNum(alive), down: fmtNum(down) }))}</div>`
        : `<p class="solo-desc">${esc(t("companion.desc"))}</p>`}
      ${warn}
      <div class="solo-actions">${use}${guardHTML("companion")}
        ${held ? `<button class="btn btn-secondary btn-sm" type="button" data-action="recall-companions" ${online && alive && !recalling ? "" : "disabled"}>${recalling ? '<span class="spinner" style="width:12px;height:12px"></span>' : icon("zap", "icon-sm")}<span>${esc(t("companion.recall"))}</span>${keyCap(S.keys.recall_companions)}</button>` : ""}
        <button class="btn btn-ghost btn-sm solo-clear" type="button" data-action="dismiss-companions" ${online && held && !busy ? "" : "disabled"}>${busy ? '<span class="spinner" style="width:12px;height:12px"></span>' : icon("trash", "icon-sm")}<span>${esc(t("companion.dismiss"))}</span></button>
      </div>
      ${held ? `<p class="solo-note">${esc(t("companion.recallNote"))} ${esc(t("companion.note"))}</p>` : ""}`;
  }
  async function soloAgain() {
    const last = ui.lastSolo;
    if (!last || ui.busy.has("solo-again")) return;
    ui.busy.add("solo-again");
    try {
      const job = await run("clear_neutral");
      if (job?.status !== "succeeded") return;
      ui.roster.neutral = {};
      await summon(last.id, "neutral", last.count);
    } finally {
      ui.busy.delete("solo-again");
      renderSolo();
    }
  }
  // Summon difficulty (set_spawn_difficulty, spawn_difficulty.lua): units summoned from now on use the
  // chosen level's numbers through their own per-difficulty configs; FOLLOW keeps the game's level.
  const DIFFICULTIES = ["FOLLOW", "EASY", "NORMAL", "HARD", "NIGHTMARE"];
  const GAME_LEVELS = { Handicapped: "HANDICAPPED", Easy: "EASY", Normal: "NORMAL", Hard: "HARD", Nightmare: "NIGHTMARE" };
  const diffName = level => t("diff." + level);
  function renderDifficulty() {
    const el = $("#dock-diff");
    if (!el) return;
    const d = S.difficulty, online = RT.online(), busy = ui.busy.has("set_spawn_difficulty");
    const level = busy ? ui.diffWanted : d.level, game = GAME_LEVELS[d.game];
    const usable = online && d.supported && !busy;
    const desc = busy ? t("match.switching") : !online ? t("diff.desc.offline") : !d.supported ? t("diff.desc.old")
      : level === "FOLLOW" ? t("diff.desc.follow") : t("diff.desc.set", { name: diffName(level) });
    const label = v => (v === "FOLLOW" && game ? t("diff.followNow", { name: diffName(game) }) : diffName(v));
    const notes = [];
    if (usable && level !== "FOLLOW") notes.push(`<div class="match-note">${icon("info", "icon-sm")}<span>${esc(t("diff.note"))}</span></div>`);
    if (d.failures) notes.push(`<div class="match-warn">${icon("alert", "icon-sm")}<span>${esc(t("diff.failures", { n: d.failures }))}</span><button class="btn-link" type="button" data-action="open-history">${esc(t("history.open"))}</button></div>`);
    if (d.aiFailed) notes.push(`<div class="match-warn">${icon("alert", "icon-sm")}<span>${esc(t("diff.aiFailed"))}</span></div>`);
    else if (usable && level !== "FOLLOW" && d.skipped) notes.push(`<div class="match-note">${icon("info", "icon-sm")}<span>${esc(t("diff.skipped", { n: d.skipped }))}</span></div>`);
    el.innerHTML = `<div class="dock-title"><span id="diff-title">${esc(t("diff.title"))}</span></div>
      <select class="select diff-select" id="diff-select" aria-labelledby="diff-title" aria-describedby="diff-desc" ${usable ? "" : "disabled"}>${DIFFICULTIES.map(v => `<option value="${v}"${v === level ? " selected" : ""}>${esc(label(v))}</option>`).join("")}</select>
      <p class="diff-desc" id="diff-desc">${esc(desc)}</p>
      ${notes.join("")}
      ${levelBlock()}`;
  }
  // Summon level (set_spawn_level, home_levels.lua): each unit's own level in the game (HOME, the default), the level
  // of the map enemies near the player (HERE), or one level for every summon (CUSTOM).
  const LEVEL_MODES = ["HOME", "HERE", "CUSTOM"];
  function levelBlock() {
    const L = S.level, online = RT.online(), busy = ui.busy.has("set_spawn_level");
    const mode = ui.levelDraft || L.mode, usable = online && L.supported && !busy;
    const desc = !online ? t("diff.desc.offline") : !L.supported ? t("level.desc.old")
      : mode === "CUSTOM" && L.mode !== "CUSTOM" ? t("level.desc.customDraft") : t("level.desc." + mode, { n: L.custom });
    const last = online && S.difficulty.summonLevel != null ? `<p class="diff-desc diff-level">${esc(t("diff.level", { n: S.difficulty.summonLevel }))}</p>` : "";
    const custom = mode === "CUSTOM" ? `<div class="level-custom">
        <input class="stat-input" id="level-custom" type="text" inputmode="numeric" value="${esc(ui.levelCustom ?? L.custom ?? "")}" placeholder="1–${LEVEL_MAX}" aria-label="${esc(t("level.custom"))}" ${usable ? "" : "disabled"}>
        <button class="btn btn-secondary btn-sm" type="button" data-action="level-apply" ${usable ? "" : "disabled"}>${esc(t("level.apply"))}</button>
      </div>` : "";
    return `<div class="dock-title level-title"><span id="level-title">${esc(t("level.title"))}</span></div>
      <select class="select diff-select" id="level-mode" aria-labelledby="level-title" aria-describedby="level-desc" ${usable ? "" : "disabled"}>${LEVEL_MODES.map(v => `<option value="${v}"${v === mode ? " selected" : ""}>${esc(t("level.mode." + v))}</option>`).join("")}</select>
      ${custom}
      <p class="diff-desc" id="level-desc">${esc(desc)}</p>
      ${last}
      ${ui.levelError ? `<div class="inline-error">${icon("alert")}<span>${esc(ui.levelError)}</span></div>` : ""}`;
  }
  const LEVEL_MAX = 60;
  function setLevelMode(mode) {
    if (!LEVEL_MODES.includes(mode)) return;
    ui.levelError = "";
    // A custom level needs a number first; the choice waits in the box until the player applies one.
    if (mode === "CUSTOM" && S.level.custom == null) { ui.levelDraft = "CUSTOM"; renderDifficulty(); $("#level-custom")?.focus(); return; }
    ui.levelDraft = null;
    if (mode === S.level.mode) { renderDifficulty(); return; }
    sendLevel(mode, mode === "CUSTOM" ? S.level.custom : null);
  }
  function applyCustomLevel(text) {
    const n = Number(String(text ?? "").trim());
    if (!Number.isInteger(n) || n < 1 || n > LEVEL_MAX) { ui.levelError = t("level.bad", { max: LEVEL_MAX }); renderDifficulty(); return; }
    ui.levelError = "";
    ui.levelCustom = null;
    sendLevel("CUSTOM", n);
  }
  async function sendLevel(mode, level) {
    const job = await run("set_spawn_level", { payload: { mode, level },
      ok: () => ({ title: t("toast.level.set", { name: mode === "CUSTOM" ? t("level.customN", { n: level }) : t("level.mode." + mode) }), body: t("toast.level.body") }) });
    if (job?.status === "succeeded") ui.levelDraft = null;
    renderDifficulty();
    renderSelection();
  }
  // One place's label: the map and its part, the level, and how many of the game's spawners put the unit there.
  const levelPlace = o => [o.map, o.part].filter(Boolean).join(" ") || t("level.somewhere");
  const levelLabel = o => t("level.option", { place: levelPlace(o), n: o.level }) + (o.count > 1 ? " · " + t("level.spawners", { n: o.count }) : "");
  // The selected unit's level in HOME mode: the default place, or one the player picks from where the game puts it.
  function levelField(u) {
    const L = S.level;
    if (!RT.online() || !L.supported) return "";
    if (L.mode !== "HOME") return `<div class="level-line">${icon("info", "icon-sm")}<span>${esc(L.mode === "CUSTOM" ? t("level.now.CUSTOM", { n: L.custom }) : t("level.now.HERE"))}</span></div>`;
    const h = L.homes[u.id];
    if (!h || !h.options.length) return `<div class="level-line">${icon("info", "icon-sm")}<span>${esc(t("level.none"))}</span></div>`;
    const def = h.default != null ? h.options[h.default] : null, picked = h.picked ?? -1, busy = ui.busy.has("set_spawn_level");
    const options = [`<option value=""${picked < 0 ? " selected" : ""}>${esc(def ? t("level.default", { label: levelLabel(def) }) : t("level.defaultNone"))}</option>`,
      ...h.options.map((o, i) => `<option value="${o.level}"${i === picked ? " selected" : ""}>${esc(o.source === "picked" ? t("level.pickedOnly", { n: o.level }) : levelLabel(o))}</option>`)];
    return `<div class="field">
        <div class="field-label"><span id="home-level-label">${esc(t("level.home"))}</span><small>${esc(t("level.homeHelp"))}</small></div>
        <select class="select" id="home-level" data-id="${esc(u.id)}" aria-labelledby="home-level-label" ${busy ? "disabled" : ""}>${options.join("")}</select>
      </div>`;
  }
  async function setHomeLevel(id, value) {
    const u = byId.get(id), level = value === "" ? null : Number(value);
    const h = S.level.homes[id], picked = h && h.picked != null ? h.options[h.picked].level : null;
    if (!u || level === picked) return;
    await run("set_spawn_level", { payload: { mode: "UNIT", unit: id, level },
      ok: () => ({ title: t("toast.level.unit", { name: u.name, label: level == null ? t("level.backToDefault") : t("level.levelN", { n: level }) }), body: t("toast.level.body") }) });
    renderSelection();
  }
  function setDifficulty(level) {
    if (!DIFFICULTIES.includes(level) || level === S.difficulty.level) return;
    ui.diffWanted = level;
    run("set_spawn_difficulty", { payload: { difficulty: level }, ok: () => ({ title: level === "FOLLOW" ? t("toast.diff.follow") : t("toast.diff.set", { name: diffName(level) }), body: t("toast.diff.body") }) });
  }
  // The equal-stats card mirrors the stat_match_* status: baseline unit, its spawn stats, matched/failed counts.
  const fmtStat = n => new Intl.NumberFormat(locale(), { maximumFractionDigits: 1 }).format(n);
  // Spawn stats (set_stat_mode, stat_match.lua): the game's numbers, the first unit's (equal stats), or the
  // player's own values for the fields they fill in; empty fields keep the unit's own value.
  const STAT_CORE = [["Health_Max", "hp"], ["Shachi_Max", "shachi"], ["Attack", "atk"], ["ShachiAttack", "satk"]];
  // Every attribute of the game's attribute set (backend.py STAT_FIELDS, character_stats.lua Stats.allFields),
  // grouped for the dialog. A family group's rows are its seven multipliers.
  const STAT_PREFIXES = ["Amplification", "DealtVulnerabilityMultiplier", "DealtReductionMultiplier", "Resistance", "TakenAdditiveMultiplier", "TakenVulnerabilityMultiplier", "TakenReductionMultiplier"];
  const STAT_DAMAGE = ["Physical", "PhysicalSharp", "PhysicalBlunt", "Elemental", "Fire", "Toxin", "Ice", "Aqua", "Lightning", "Blood", "Chaos", "ImpactShachi", "ReflectShachi"];
  // Status buildup: Amplification_<family>, the other six <prefix>_<family>Accumulation.
  const STAT_BUILDUP = ["ElementalAccumulation", "Ignite", "Poison", "Frost", "Electrified", "Bleed", "BloodBurst", "Water"];
  const buildupField = (prefix, family) => prefix + "_" + (prefix === "Amplification" || family === "ElementalAccumulation" ? family : family + "Accumulation");
  const STAT_GROUPS = [
    { key: "core", fields: STAT_CORE.map(([f]) => f) },
    // Damage is worked out from these (stat_match.lua); the core four move them by the same ratio.
    { key: "lv1", fields: ["Health_Max_Lv1", "Shachi_Max_Lv1", "Attack_Lv1", "ShachiAttack_Lv1", "Infliction_Max_Lv1"] },
    { key: "health", fields: ["Health", "Health_Min", "Shield", "Shield_Max"] },
    { key: "shachi", fields: ["Shachi", "Shachi_Min", "ShachiRegen", "ShachiRegenCooldown", "HeavyAttack_ShachiCostReduction", "BreakDurationAdditionalMultiplier"] },
    { key: "defense", fields: [...STAT_PREFIXES.slice(3).map(p => p + "_Poise"), "Resistance_BreakDamageAdditionalMultiplier", ...STAT_PREFIXES.slice(4).map(p => p + "_BreakDamage"), ...STAT_PREFIXES.map(p => p + "_DefenceShachi")] },
    { key: "weapon", fields: ["Health", "Shachi", "Strength", "Ranged", "Magic", "Martial", "Summon"].map(w => "Resistance_ShachiWeapon" + w) },
    ...STAT_DAMAGE.map(family => ({ key: family, family, fields: STAT_PREFIXES.map(p => p + "_" + family) })),
    { key: "status", fields: ["Infliction_Max", "StatusInflictionDecrementRate", ...["Ignite", "Poison", "Frost", "Thunder", "Electrified", "Bleed", "BloodBurst", "Water"].map(x => x + "_Accumulation")] },
    ...STAT_BUILDUP.map(family => ({ key: family, family, fields: STAT_PREFIXES.map(p => buildupField(p, family)) })),
    { key: "ultimate", fields: ["UltimateCharge", "UltimateCharge_Max", "UltimateChargeCount", "UltimateChargeCount_Max", "UltimateChargeAdditiveRate", "UltimateChargeGainRateMultiplier", "SpiritShadow", "SpiritShadow_Max", "Awakening", "Awakening_Max"] },
    { key: "execution", fields: ["ExecutionExecutorNormalHealthThreshold", "ExecutionExecutorBreakHealthThreshold", "ExecutionTargetNormalHealthThreshold", "ExecutionTargetBreakHealthThreshold"] },
    { key: "movement", fields: ["WalkSpeed", "JogSpeed", "SprintSpeed", "CrouchSpeed", "FinalWalkSpeed"] },
    { key: "other", fields: ["Level", "MindDustAdditiveMultiplier", "PowerScore", "XP", "Coin", "Corrosion"] },
  ];
  const groupHeading = g => g.family ? "stats.family." + g.family : "stats.group." + g.key;
  // field -> [heading key or null, own key]: "family · multiplier", or a name of its own.
  const STAT_META = new Map();
  for (const g of STAT_GROUPS) for (const field of g.fields) {
    const core = STAT_CORE.find(([f]) => f === field);
    const multiplier = field.match(/^([A-Za-z]+)_(Poise|BreakDamage|DefenceShachi)$/);
    const weapon = field.match(/^Resistance_ShachiWeapon(\w+)$/);
    const buildup = field.match(/^(\w+)_Accumulation$/);
    STAT_META.set(field, core ? [null, "stats.core." + core[1]]
      : g.family ? [groupHeading(g), "stats.prefix." + field.split("_")[0]]
      : field === "Resistance_BreakDamageAdditionalMultiplier" ? ["stats.family.BreakDamage", "stats.prefix.Resistance"]
      : multiplier ? ["stats.family." + multiplier[2], "stats.prefix." + multiplier[1]]
      : weapon ? ["stats.group.weapon", "stats.weapon." + weapon[1]]
      : buildup ? ["stats.family." + buildup[1], "stats.current"]
      : [null, "stats.field." + field]);
  }
  function statLabel(field) {
    const [head, own] = STAT_META.get(field) || [null, null];
    if (!own) return field;
    return head ? t(head) + " · " + t(own) : t(own);
  }
  // In its own family's group a row needs only the multiplier's name.
  const rowLabel = (field, g) => { const [head, own] = STAT_META.get(field); return head && head === groupHeading(g) ? t(own) : statLabel(field); };
  // The draft the player edits: every saved value, as text; empty means "keep the unit's own".
  function statDraft() {
    if (!ui.statDraft) ui.statDraft = Object.fromEntries(Object.entries(S.statMatch.values || {}).map(([k, v]) => [k, String(v)]));
    return ui.statDraft;
  }
  async function loadStatValues() {
    ui.statLoaded = true;
    try { const saved = await RT.statSettings(); S.statMatch.values = saved.values || {}; ui.statDraft = null; } catch { /* keep what we have */ }
  }
  // Numbers from the draft; null with a reason when a field cannot be sent.
  function statValues() {
    const values = {};
    for (const [field, text] of Object.entries(statDraft())) {
      const raw = String(text).trim();
      if (!raw) continue;
      const n = Number(raw);
      if (!Number.isFinite(n) || Math.abs(n) > 1e9) return [null, t("stats.invalid", { name: statLabel(field) })];
      if (["Health", "Health_Max", "Shachi_Max", "Attack"].includes(field) && n <= 0) return [null, t("stats.positive", { name: statLabel(field) })];
      if (["Shachi", "ShachiAttack"].includes(field) && n < 0) return [null, t("stats.nonneg", { name: statLabel(field) })];
      values[field] = n;
    }
    return Object.keys(values).length ? [values] : [null, t("stats.empty")];
  }
  async function setStatMode(mode) {
    if (mode === "custom") {
      // Saved values switch at once; with none yet the form opens and Apply switches.
      if (!S.statMatch.customCount) { ui.statTab = "custom"; await loadStatValues(); renderMatch(); return; }
      await loadStatValues();
      const [values] = statValues();
      if (!values) { ui.statTab = "custom"; renderMatch(); return; }
      return applyStats(values);
    }
    ui.statTab = null;
    run("set_stat_mode", { payload: { mode }, ok: () => ({ title: t("toast.stats." + mode), body: t("toast.stats.body") }) });
  }
  async function applyStats(values) {
    if (!values) {
      const [checked, why] = statValues();
      if (!checked) { toast({ kind: "error", title: why }); return; }
      values = checked;
    }
    const job = await run("set_stat_mode", { payload: { mode: "custom", values }, ok: () => ({ title: t("toast.stats.custom", { n: Object.keys(values).length }), body: t("toast.stats.body") }) });
    if (job?.status === "succeeded") { ui.statTab = null; S.statMatch.values = values; ui.statDraft = null; renderMatch(); renderSelection(); }
  }
  function statsDialog() {
    const draft = statDraft();
    const filled = f => String(draft[f] ?? "").trim() !== "";
    const groups = STAT_GROUPS.map(g => `<details class="stat-group" data-group="${g.key}" ${g.key === "core" || g.fields.some(filled) ? "open" : ""}>
      <summary><span class="stat-group-name">${esc(t(groupHeading(g)))}</span><span class="stat-group-count">${g.fields.filter(filled).length}/${g.fields.length}</span>${icon("chevron-down", "chev")}</summary>
      ${g.fields.map(field => `<label class="stat-row" data-search="${esc((statLabel(field) + " " + field).toLowerCase())}"><span class="stat-row-name">${esc(rowLabel(field, g))}<small class="mono">${esc(field)}</small></span>
        <input class="stat-input" type="text" inputmode="decimal" data-field="${field}" value="${esc(draft[field] ?? "")}" placeholder="${esc(t("stats.placeholder"))}" aria-label="${esc(statLabel(field))}"></label>`).join("")}</details>`).join("");
    openDialog("stats", `<div class="dialog-head"><span class="row-icon">${icon("sliders")}</span><h2 id="dlg-title">${esc(t("stats.dialog.title"))}</h2><button class="icon-btn icon-btn-sm" type="button" data-action="dialog-close" aria-label="${esc(t("common.close"))}">${icon("x")}</button></div>
      <div class="dialog-body"><p class="stat-dialog-desc">${esc(t("stats.dialog.desc"))}</p>
        <input class="stat-filter" type="search" placeholder="${esc(t("stats.filter"))}" aria-label="${esc(t("stats.filter"))}">
        ${groups}<p class="stat-filter-none" hidden>${esc(t("stats.filter.none"))}</p></div>
      <div class="dialog-foot"><button class="btn btn-ghost" type="button" data-action="stats-clear">${esc(t("stats.dialog.clear"))}</button><button class="btn btn-ghost" type="button" data-action="dialog-close">${esc(t("common.cancel"))}</button><button class="btn btn-primary" type="button" data-action="stats-save" data-autofocus>${esc(t("stats.dialog.save"))}</button></div>`);
  }
  function renderMatch() {
    const el = $("#dock-match");
    if (!el) return;
    const m = S.statMatch, online = RT.online(), busy = ui.busy.has("set_stat_mode") || ui.busy.has("toggle_stat_match");
    if (ui.statTab && ui.statTab === m.mode) ui.statTab = null;
    const tab = ui.statTab || m.mode;
    const usable = online && !busy && m.modeSupported;
    const desc = busy ? t("match.switching") : !online ? t("match.desc.offline") : !m.modeSupported ? t("fun.old")
      : tab === "match" ? t("match.desc.on") : tab === "custom" ? t("stats.desc.custom") : t("stats.desc.game");
    const seg = `<div class="seg stat-seg" role="radiogroup" aria-labelledby="match-title">${["game", "match", "custom"].map(mode =>
      `<button class="seg-btn" type="button" role="radio" aria-checked="${tab === mode}" data-action="stats-mode" data-mode="${mode}" ${usable ? "" : "disabled"}>${esc(t("stats.mode." + mode))}</button>`).join("")}</div>`;
    if (tab === "custom" && online && m.modeSupported && !ui.statLoaded) loadStatValues().then(renderMatch);
    // Status updates re-render the card; keep the field being typed in.
    const typing = el.contains(document.activeElement) && document.activeElement.classList.contains("stat-input")
      ? { field: document.activeElement.dataset.field, start: document.activeElement.selectionStart, end: document.activeElement.selectionEnd } : null;
    let card = "";
    if (tab === "custom" && online && m.modeSupported) {
      const draft = statDraft();
      const others = Object.keys(draft).filter(f => !STAT_CORE.some(([c]) => c === f) && String(draft[f]).trim()).length;
      card = `<div class="match-card stat-card">
          <div class="stat-grid">${STAT_CORE.map(([field, key]) => `<label class="stat-field"><span>${esc(t("stats.core." + key))}</span>
            <input class="stat-input" type="text" inputmode="decimal" data-field="${field}" value="${esc(draft[field] ?? "")}" placeholder="${esc(t("stats.placeholder"))}" ${busy ? "disabled" : ""}></label>`).join("")}</div>
          <div class="stat-actions"><button class="btn-link" type="button" data-action="stats-all">${icon("sliders", "icon-sm")}${esc(others ? t("stats.all.more", { n: others }) : t("stats.all"))}</button>
            <button class="btn btn-primary btn-sm" type="button" data-action="stats-apply" ${usable ? "" : "disabled"}>${esc(t("stats.apply"))}</button></div>
          ${m.mode === "custom" ? `<div class="match-foot">${icon("check-circle", "icon-sm")}<span>${esc(m.customized ? t("stats.applied", { n: m.customized }) : t("stats.applied.none"))}</span></div>` : ""}
          ${m.rejected.length && m.mode === "custom" ? `<div class="match-warn">${icon("alert", "icon-sm")}<span>${esc(t("stats.rejected", { n: m.rejectedCount || m.rejected.length, names: m.rejected.slice(0, 4).map(statLabel).join("、") + (m.rejected.length > 4 ? "…" : "") }))}</span></div>` : ""}
          ${m.failures && m.mode === "custom" ? `<div class="match-warn">${icon("alert", "icon-sm")}<span>${esc(t("match.failures", { n: m.failures }))}</span><button class="btn-link" type="button" data-action="open-history">${esc(t("history.open"))}</button></div>` : ""}
          <p class="stat-note">${esc(t("stats.note"))}</p>
        </div>`;
    } else if (m.mode === "match" && tab === "match" && online && !busy) {
      const base = m.baseline && byId.get(m.baseline.id);
      const failures = m.failures
        ? `<div class="match-warn">${icon("alert", "icon-sm")}<span>${esc(t("match.failures", { n: m.failures }))}</span><button class="btn-link" type="button" data-action="open-history">${esc(t("history.open"))}</button></div>`
        : "";
      const stats = base ? [["hp", m.baseline.hp], ["shachi", m.baseline.shachi], ["atk", m.baseline.atk], ["satk", m.baseline.satk]] : [];
      card = base
        ? `<div class="match-card">
            <div class="match-base">
              <span class="avatar sp-${base.species}${base.boss ? " is-boss" : ""}${artClass(base)}">${avatarArt(base)}<span class="avatar-initial" aria-hidden="true">${esc(base.initial)}</span></span>
              <div class="match-base-main"><div class="match-base-name">${esc(base.name)}</div><div class="match-base-sub">${esc(t("match.baseline.sub"))}</div></div>
              <span class="chip chip-green">${icon("scale")}${esc(t("match.baseline"))}</span>
            </div>
            <dl class="match-stats">${stats.map(([k, v]) => `<div><dt>${esc(t("match.stat." + k))}</dt><dd>${esc(fmtStat(v))}</dd></div>`).join("")}</dl>
            <div class="match-foot">${icon("check-circle", "icon-sm")}<span>${esc(m.matched ? t("match.matched", { n: m.matched }) : t("match.matched.none"))}</span></div>
            ${failures}
          </div>`
        : `<div class="match-card is-waiting">
            <div class="match-base">
              <span class="match-slot">${icon("scale")}</span>
              <div class="match-base-main"><div class="match-base-name">${esc(t("match.waiting.title"))}</div><div class="match-base-sub">${esc(t("match.waiting.body"))}</div></div>
            </div>
            ${m.reset ? `<div class="match-note">${icon("refresh", "icon-sm")}<span>${esc(t("match.waiting.reset"))}</span></div>` : ""}
            ${failures}
          </div>`;
    }
    el.innerHTML = `<div class="dock-title"><span id="match-title">${esc(t("stats.title"))}</span><button class="title-link" type="button" data-action="match-rules">${icon("help", "icon-sm")}${esc(t("match.rules"))}</button></div>
      ${seg}
      <p class="diff-desc">${esc(desc)}</p>
      ${card}`;
    const again = typing && el.querySelector(`.stat-input[data-field="${typing.field}"]`);
    if (again) { again.focus(); again.setSelectionRange(typing.start, typing.end); }
  }
  function matchRulesDialog() {
    const rules = (prefix, n) => `<ol class="rule-list">${Array.from({ length: n }, (_, i) => `<li>${esc(t(prefix + (i + 1)))}</li>`).join("")}</ol>`;
    openDialog("match", `<div class="dialog-head"><span class="row-icon">${icon("scale")}</span><h2 id="dlg-title">${esc(t("stats.rules.title"))}</h2><button class="icon-btn icon-btn-sm" type="button" data-action="dialog-close" aria-label="${esc(t("common.close"))}">${icon("x")}</button></div>
      <div class="dialog-body">
        <h3 class="rule-head">${esc(t("stats.mode.game"))}</h3><p class="rule-text">${esc(t("stats.rules.game"))}</p>
        <h3 class="rule-head">${esc(t("stats.mode.match"))}</h3>${rules("match.rules.", 8)}
        <h3 class="rule-head">${esc(t("stats.mode.custom"))}</h3>${rules("stats.rules.custom.", 7)}
      </div>
      <div class="dialog-foot"><button class="btn btn-primary" type="button" data-action="dialog-close" data-autofocus>${esc(t("common.gotIt"))}</button></div>`, "dialog-sm");
  }
  // What equal stats did to a batch, read from the status change the same way the real panel will.
  function matchNote(before, n) {
    const m = S.statMatch, base = m.baseline && byId.get(m.baseline.id);
    if (m.mode !== "match" || !base) return "";
    if (!before.baseline) return n > 1 ? t("toast.summon.baselineMore", { n: n - 1 }) : t("toast.summon.baseline");
    return m.matched > before.matched ? t("toast.summon.matched", { name: base.name }) : "";
  }
  function rosterHTML(team) {
    const entries = Object.entries(ui.roster[team]);
    if (!entries.length) return `<div class="side-chips"><span class="roster-empty">${esc(t("field.emptySide"))}</span></div>`;
    const shown = entries.slice(0, 2).map(([id, n]) => `<span class="roster-item" title="${esc(byId.get(id)?.name)} ×${n}"><span>${esc(byId.get(id)?.name)}</span><b>×${n}</b></span>`).join("");
    const rest = entries.slice(2);
    const more = rest.length ? `<span class="roster-item" title="${esc(rest.map(([id, n]) => `${byId.get(id)?.name} ×${n}`).join("\n"))}">+${rest.length}</span>` : "";
    return `<div class="side-chips">${shown}${more}</div>`;
  }
  // 不倒下 (set_team_immortal, immortal_teams.lua): the units of a side switched on keep their HP.
  function guardHTML(team) {
    const on = S.immortal[team], busy = ui.busy.has("immortal_" + team);
    return `<button class="side-guard${on ? " is-on" : ""}" type="button" role="switch" aria-checked="${on}" aria-busy="${busy}" data-action="immortal-toggle" data-team="${team}" title="${esc(t("immortal.hint"))}" ${RT.online() && S.immortal.supported && !busy ? "" : "disabled"}>${icon("shield", "icon-sm")}<span>${esc(t("immortal.name"))}</span></button>`;
  }
  async function toggleImmortal(team) {
    if (!["blue", "red", "companion"].includes(team)) return;
    const enabled = !S.immortal[team], name = teamName(team);
    // With both sides held up nobody can win; say so, but an endless show fight is allowed.
    const both = enabled && team !== "companion" && S.immortal[team === "blue" ? "red" : "blue"];
    await run("set_team_immortal", { busyKey: "immortal_" + team, payload: { team, enabled },
      ok: () => ({ title: t(enabled ? "toast.immortal.on" : "toast.immortal.off", { team: name }), ...(both ? { body: t("toast.immortal.both", { stop: t("field.stop") }) } : {}) }) });
  }
  // Game seconds from arena_controller.lua, shown as m:ss.
  const fmtClock = seconds => { const s = Math.max(0, Math.floor(seconds)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`; };
  function renderClock() {
    const el = $("#battle-clock");
    if (el) el.lastChild.textContent = fmtClock(S.clock.seconds);
  }
  function renderBattle() {
    const el = $("#dock-battle");
    if (!el) return;
    const summoned = team => Object.values(ui.roster[team]).reduce((a, b) => a + b, 0);
    const fighting = S.fight === "fighting";
    // Once someone summons into the beaten side again, the result gives way to a new start.
    const showResult = S.fight === "ended" && !(S.blue > 0 && S.red > 0);
    const side = team => `<div class="side side-${team}${showResult && S.winner === team ? " is-winner" : ""}${showResult && S.winner && S.winner !== team ? " is-loser" : ""}">
        <div class="side-name"><span class="team-dot" style="background:var(--${team})"></span>${esc(teamName(team))}</div>
        <div class="side-count" id="count-${team}">${S[team]}</div>
        <div class="side-sub">${esc(t("field.aliveOf", { n: summoned(team) }))}</div>
        ${rosterHTML(team)}
        ${guardHTML(team)}
      </div>`;
    // Fallen units stay in the world until cleanup; unreadable ones are neither alive nor fallen.
    const fallen = S.down.blue + S.down.red;
    const unlocked = S.immortal.failures;
    const note = fallen || S.unreadable || unlocked
      ? `<div class="field-note">${fallen ? `<span>${esc(t("field.down", { n: fmtNum(fallen) }))}</span>` : ""}${S.unreadable ? `<span class="field-note-warn" title="${esc(t("field.unreadableHelp"))}">${icon("alert", "icon-sm")}${esc(t("field.unreadable", { n: fmtNum(S.unreadable) }))}</span>` : ""}${unlocked ? `<span class="field-note-warn">${icon("alert", "icon-sm")}${esc(t("immortal.failed", { n: fmtNum(unlocked) }))}</span>` : ""}</div>`
      : "";
    const time = S.clock.state === "ended" ? ` · ${t("field.time", { time: fmtClock(S.clock.seconds) })}` : "";
    const startBlocked = gameBlocker("field") || (fighting ? "" : !(S.blue > 0 && S.red > 0) ? t("field.needBoth") : "");
    const startBusy = ui.busy.has("start");
    const rematchable = Object.keys(ui.roster.blue).length && Object.keys(ui.roster.red).length;
    const stopDisabled = !RT.online() || (fieldTotal() === 0 && S.fight === "idle" && !S.cleanup) || ui.busy.has("stop");
    const unfinished = S.cleanup && RT.online()
      ? S.cleanup === "spawn_uncertain"
        ? `<div class="callout callout-red field-callout">${icon("alert")}<div class="callout-body"><strong>${esc(t("field.uncertain.title"))}</strong><span>${esc(t("field.uncertain.body"))}</span></div></div>`
        : `<div class="callout callout-amber field-callout">${icon("alert")}<div class="callout-body"><strong>${esc(t("field.unfinished.title"))}</strong><span>${esc(t("field.unfinished.body"))}</span><div class="callout-actions"><button class="btn btn-primary btn-sm" type="button" data-action="stop-again" ${ui.busy.has("stop") ? "disabled" : ""}>${ui.busy.has("stop") ? '<span class="spinner" style="width:12px;height:12px"></span>' : icon("trash", "icon-sm")}${esc(t("field.unfinished.again"))}</button></div></div></div>`
      : "";
    const actions = showResult
      ? `<div class="result-banner"><span class="trophy">${icon("trophy")}</span><div><strong>${esc(t("field.winner." + S.winner))}</strong><p>${esc((S.winner === "draw" ? t("field.result.draw") : t("field.result.left", { n: S[S.winner] })) + time)}</p></div></div>
        <div class="result-actions">${rematchable ? `<button class="btn btn-primary btn-sm" type="button" data-action="rematch" ${ui.busy.has("rematch") ? "disabled" : ""}>${icon("refresh", "icon-sm")}${esc(t("field.rematch"))}</button>` : ""}<button class="btn btn-secondary btn-sm" type="button" data-action="stop">${icon("trash", "icon-sm")}${esc(t("field.cleanup"))}</button></div>`
      : `<div class="battle-actions">
          <button class="btn btn-lg btn-block btn-primary" type="button" data-action="start" ${startBlocked || fighting || startBusy ? "disabled" : ""}>
            ${startBusy ? '<span class="spinner"></span>' : fighting ? '<span class="dot" style="background:var(--red);animation:pulse 1s infinite"></span>' : icon("play")}<span>${esc(fighting ? t("field.fighting") : t("field.start"))}</span>${fighting || startBusy ? "" : keyCap(S.keys.start)}
          </button>
          ${startBlocked ? `<p class="reason">${esc(startBlocked)}</p>` : fighting ? `<p class="reason">${esc(t("field.fightingHint"))}</p>` : ""}
        </div>`;
    const clock = fighting && S.clock.state === "running"
      ? `<span class="battle-clock" id="battle-clock" title="${esc(t("field.clockHint"))}">${icon("clock", "icon-sm")}<span>${esc(fmtClock(S.clock.seconds))}</span></span>` : "";
    el.innerHTML = `<div class="dock-title"><span style="display:flex;align-items:center;gap:8px">${esc(t("field.title"))}<span class="phase phase-${S.fight}">${esc(t("field.phase." + S.fight))}</span>${clock}</span>
        <button class="btn btn-ghost stop-btn" type="button" data-action="stop" ${stopDisabled ? "disabled" : ""} title="${esc(t("field.stopHint"))}">${ui.busy.has("stop") ? '<span class="spinner" style="width:12px;height:12px"></span>' : icon("trash", "icon-sm")}${esc(t("field.stop"))}${keyCap(S.keys.stop)}</button></div>
      <div class="scoreboard">${side("blue")}<div class="vs">VS</div>${side("red")}</div>
      ${note}${unfinished}
      ${actions}`;
    for (const team of ["blue", "red"]) {
      if (ui.lastCounts[team] !== S[team]) $(`#count-${team}`)?.classList.add("count-bump");
      ui.lastCounts[team] = S[team];
    }
  }
  function renderView() {
    const el = $("#dock-view");
    if (!el) return;
    const phase = S.spectatorPhase, on = S.spectator, cam = S.freeCam;
    // While the F6 camera runs it owns spectator mode, so the switch waits until the camera exits.
    const desc = cam ? t("view.spectator.byCam") : phase === "switching" ? t("view.spectator.switching") : phase === "restoring" ? t("view.spectator.restoring") : t(on ? "view.spectator.on" : "view.spectator.desc");
    // Entering needs the player in a map; leaving only needs the game connected (backend.py rules).
    const camBusy = ui.busy.has("toggle_camera") || ui.busy.has("exit_camera");
    const camBtn = cam
      ? `<button class="btn btn-secondary btn-sm" type="button" data-action="camera-exit" ${RT.online() && !camBusy ? "" : "disabled"}>${ui.busy.has("exit_camera") ? '<span class="spinner" style="width:12px;height:12px"></span>' : icon("x", "icon-sm")}${esc(t("view.freecam.exit"))}</button>`
      : `<button class="btn btn-secondary btn-sm" type="button" data-action="camera-enter" ${RT.ready() && !camBusy ? "" : "disabled"}>${ui.busy.has("toggle_camera") ? '<span class="spinner" style="width:12px;height:12px"></span>' : icon("video", "icon-sm")}${esc(t("view.freecam.enter"))}</button>`;
    el.innerHTML = `<div class="dock-title">${esc(t("view.title"))}</div>
      <div class="control-list">
        <div class="control-row${cam ? " is-on" : ""}">
          <span class="control-icon">${icon("video")}</span>
          <div class="control-main"><div class="control-title">${esc(t("view.freecam"))}${cam ? `<span class="chip chip-green">${esc(t("view.freecam.active"))}</span>` : keyCap(S.keys.toggle_camera)}</div><div class="control-desc">${esc(t(cam ? "view.freecam.on" : "view.freecam.desc"))}</div>${keyLineHTML("toggle_camera")}</div>
          ${camBtn}
        </div>
        ${timeStopRow()}
        ${camSettingsHTML()}
        <div class="control-row${on && !phase ? " is-on" : ""}">
          <span class="control-icon">${icon("shield")}</span>
          <div class="control-main"><div class="control-title">${esc(t("view.spectator"))}${keyCap(S.keys.toggle_spectator)}</div><div class="control-desc">${esc(desc)}</div>${keyLineHTML("toggle_spectator")}</div>
          <button class="switch" type="button" role="switch" aria-checked="${on}" aria-busy="${!!phase}" data-action="spectator" aria-label="${esc(t("view.spectator"))}" ${RT.ready() && !phase && !cam ? "" : "disabled"}></button>
        </div>
        ${clockHudRow()}
        ${executionCameraRow()}
      </div>`;
  }
  // 时停 (toggle_time_stop, free_camera.lua): the game stands still and the free camera keeps moving; outside the
  // camera it opens first. Leaving the camera ends it.
  // A function key set in the row that uses it: the hotkeys page's capture, drawn here, a clash too, with its swap.
  function keyLineHTML(action) {
    const capturing = ui.capture?.kind === "global" && ui.capture.action === action && ui.capture.host === "view";
    const note = ui.keyNote?.action === action && ui.keyNote.host === "view" ? ui.keyNote : null;
    const body = capturing
      ? `<span class="capture-box">${icon("keyboard", "icon-sm")}${esc(t("keys.capture"))}</span><button class="btn-link" type="button" data-action="key-cancel">${esc(t("common.cancel"))}</button>`
      : note?.type === "saving"
        ? `<span class="spinner" style="width:12px;height:12px"></span><span class="muted">${esc(t("keys.saving"))}</span>`
        : `<button class="btn-link" type="button" data-action="key-capture" data-key-action="${action}" data-key-host="view" ${RT.online() && !ui.keysSaving ? "" : "disabled"}>${icon("keyboard", "icon-sm")}${esc(t(S.keys[action] ? "view.key.change" : "view.key.set"))}</button>`;
    const noteHTML = note?.type === "conflict"
      ? `<div class="key-note err">${esc(note.text)} <button class="btn-link" type="button" data-action="key-swap">${icon("swap", "icon-sm")} ${esc(t(S.keys[action] ? "keys.swap" : "keys.take"))}</button></div>`
      : note?.type === "err" ? `<div class="key-note err">${esc(note.text)}</div>` : "";
    return `<div class="control-key">${body}</div>${noteHTML}`;
  }
  function timeStopRow() {
    const on = S.frozen, busy = ui.busy.has("toggle_time_stop"), supported = S.camSettings.supported;
    const usable = (S.freeCam ? RT.online() : RT.ready()) && supported && !busy;
    const desc = !supported && RT.online() ? t("fun.old") : t(on ? "view.timeStop.on" : "view.timeStop.desc");
    return `<div class="control-row${on ? " is-on" : ""}">
          <span class="control-icon">${icon("stop")}</span>
          <div class="control-main"><div class="control-title">${esc(t("view.timeStop"))}${on ? `<span class="chip chip-green">${esc(t("view.timeStop.active"))}</span>` : keyCap(S.keys.toggle_time_stop)}</div><div class="control-desc">${esc(desc)}</div>${keyLineHTML("toggle_time_stop")}</div>
          <button class="switch" type="button" role="switch" aria-checked="${on}" aria-busy="${busy}" data-action="time-stop" aria-label="${esc(t("view.timeStop"))}" ${usable ? "" : "disabled"}></button>
        </div>`;
  }
  // The free camera's speed, turn and smoothing (set_free_camera); a slider saves when it is let go.
  const CAM_DEFAULTS = { speed: 900, turn: 100, smooth: 40 };
  const CAM_RANGES = { speed: [100, 5000, 100], turn: [20, 300, 10], smooth: [0, 100, 5] };
  function camValue(key, value) {
    if (key === "speed") return t("view.cam.speedValue", { n: (value / 100).toFixed(1) });
    if (key === "smooth" && !value) return t("view.cam.off");
    return value + "%";
  }
  function camSettingsHTML() {
    const c = S.camSettings, usable = RT.online() && c.supported;
    const range = key => {
      const [min, max, step] = CAM_RANGES[key];
      return `<label class="cam-setting"><span>${esc(t("view.cam." + key))}</span><output id="cam-${key}-value">${esc(camValue(key, c[key]))}</output>
        <input class="cam-range" type="range" data-cam="${key}" min="${min}" max="${max}" step="${step}" value="${c[key]}" ${usable ? "" : "disabled"} aria-label="${esc(t("view.cam." + key))}"></label>`;
    };
    return `<details class="cam-settings"${ui.camSettingsOpen ? " open" : ""}><summary>${icon("sliders", "icon-sm")}<span>${esc(t("view.cam.title"))}</span>${icon("chevron-down", "icon-sm cam-chevron")}</summary>
        <div class="cam-settings-body">${range("speed")}${range("turn")}${range("smooth")}
          <div class="cam-settings-foot"><span>${esc(t("view.cam.hint"))}</span><button class="btn-link" type="button" data-action="cam-reset" ${usable ? "" : "disabled"}>${esc(t("view.cam.reset"))}</button></div></div></details>`;
  }
  function saveCamSettings(values) {
    clearTimeout(ui.camTimer);
    ui.camTimer = setTimeout(() => run("set_free_camera", { payload: values }), 250);
  }
  function camSliderValues() {
    const out = { ...CAM_DEFAULTS, ...S.camSettings };
    for (const input of document.querySelectorAll(".cam-range")) out[input.dataset.cam] = Number(input.value);
    return { speed: out.speed, turn: out.turn, smooth: out.smooth };
  }
  // The fight time at the top centre of the game screen (set_clock_hud, battle_clock_hud.lua).
  function clockHudRow() {
    const h = S.clockHud, busy = ui.busy.has("set_clock_hud"), shown = h.on && h.supported;
    const desc = !h.supported && RT.online() ? t("fun.old") : h.on && h.state === "failed" ? t("view.clockHud.failed")
      : h.on && h.state === "shown" ? t("view.clockHud.shown") : t(h.on ? "view.clockHud.on" : "view.clockHud.desc");
    return `<div class="control-row${shown ? " is-on" : ""}">
          <span class="control-icon">${icon("clock")}</span>
          <div class="control-main"><div class="control-title">${esc(t("view.clockHud"))}</div><div class="control-desc">${esc(desc)}</div></div>
          <button class="switch" type="button" role="switch" aria-checked="${h.on}" aria-busy="${busy}" data-action="clock-hud" aria-label="${esc(t("view.clockHud"))}" ${RT.online() && h.supported && !busy ? "" : "disabled"}></button>
        </div>`;
  }
  function toggleClockHud() {
    const enabled = !S.clockHud.on;
    run("set_clock_hud", { payload: { enabled }, ok: () => t(enabled ? "toast.clockHud.on" : "toast.clockHud.off") });
  }
  // When a monster executes a locked boss, the view plays that execution's own camera (set_execution_camera,
  // execution_camera.lua); off, the view stays as it is.
  function executionCameraRow() {
    const h = S.executionCamera, busy = ui.busy.has("set_execution_camera"), shown = h.on && h.supported;
    const desc = !h.supported && RT.online() ? t("fun.old") : h.on && h.state === "running" ? t("view.execCam.running")
      : t(h.on ? "view.execCam.on" : "view.execCam.desc");
    return `<div class="control-row${shown ? " is-on" : ""}">
          <span class="control-icon">${icon("swords")}</span>
          <div class="control-main"><div class="control-title">${esc(t("view.execCam"))}</div><div class="control-desc">${esc(desc)}</div></div>
          <button class="switch" type="button" role="switch" aria-checked="${h.on}" aria-busy="${busy}" data-action="execution-camera" aria-label="${esc(t("view.execCam"))}" ${RT.online() && h.supported && !busy ? "" : "disabled"}></button>
        </div>`;
  }
  function toggleExecutionCamera() {
    const enabled = !S.executionCamera.on;
    run("set_execution_camera", { payload: { enabled }, ok: () => t(enabled ? "toast.execCam.on" : "toast.execCam.off") });
  }

  // ---------- Commands ----------
  function scheduleSync() {
    clearTimeout(ui.syncTimer);
    if (!selected() || !RT.online()) return;
    ui.syncTimer = setTimeout(() => {
      RT.command("select_unit", { unit_id: ui.selectedId, team: ui.team, count: ui.count }).then(renderSelection, () => {});
    }, 200);
  }
  // Translated text for known codes; otherwise the game's or backend's own answer, which is Chinese.
  function reasonText(code, detail = "") {
    if (detail && (!code || code === "rejected" || code === "host")) return detail;
    return t("reason." + (code || "unknown"));
  }
  async function summon(id = ui.selectedId, team = ui.team, count = ui.count) {
    const u = byId.get(id);
    if (!u) return;
    if (!RT.ready()) { toast({ kind: "warning", title: gameBlocker("sel") || t("sel.blocked.notInMap") }); return; }
    if (cleanupBlocker()) { toast({ kind: "warning", title: cleanupBlocker() }); return; }
    ui.busy.add("spawn");
    renderSelection();
    const tid = toast({ kind: "pending", title: t("toast.summon.pending", { name: u.name, n: count, team: teamName(team) }) });
    const before = { baseline: S.statMatch.baseline?.id, matched: S.statMatch.matched };
    try {
      const job = await RT.command("spawn", { unit_id: id, team, count });
      // A failed batch can still leave units behind (equal stats stops mid-batch); they count until cleaned up.
      if (job.spawned) ui.roster[team][id] = (ui.roster[team][id] || 0) + job.spawned;
      if (job.spawned && team === "neutral") ui.lastSolo = { id, count };
      if (job.status === "succeeded" && job.warning === "matchFailed") {
        toast({ id: tid, kind: "warning", title: t("toast.summon.matchWarn", { name: u.name, n: job.spawned }), body: t("toast.summon.matchWarn.body", { n: job.spawned }), actions: [{ label: t("history.open"), action: "open-history" }] });
      } else if (job.status === "succeeded") {
        const title = team === "neutral" ? t("toast.summon.okNeutral", { name: u.name, n: job.spawned })
          : team === "companion" ? t("toast.summon.okCompanion", { name: u.name, n: job.spawned }) : t("toast.summon.ok", { name: u.name, n: job.spawned, team: teamName(team) });
        toast({ id: tid, kind: "success", title, body: matchNote(before, job.spawned) });
      } else if (job.status === "uncertain") {
        toast({ id: tid, kind: "warning", title: t("toast.summon.uncertainTitle"), body: t("toast.summon.uncertain"), actions: [{ label: t("history.open"), action: "open-history" }] });
      } else {
        toast({ id: tid, kind: "error", title: t("toast.summon.fail", { name: u.name }), body: reasonText(job.code, job.message), actions: [{ label: t("history.open"), action: "open-history" }] });
      }
    } catch (error) {
      toast({ id: tid, kind: "error", title: t("toast.notSent"), body: reasonText(error.code, error.detail) });
    } finally {
      ui.busy.delete("spawn");
      renderDock();
    }
  }
  async function run(action, { busyKey = action, pendingTitle, ok, failed, payload } = {}) {
    if (ui.busy.has(busyKey)) return null;
    ui.busy.add(busyKey);
    renderDock();
    const tid = pendingTitle ? toast({ kind: "pending", title: pendingTitle }) : undefined;
    try {
      const job = await RT.command(action, payload);
      if (job.status === "succeeded") {
        const done = ok?.(job);
        if (done) toast({ id: tid, kind: "success", ...(typeof done === "string" ? { title: done } : done) });
        else if (tid) dismissToast(tid);
      }
      else toast({ id: tid, kind: job.status === "uncertain" ? "warning" : "error", title: t("toast.failed"), body: reasonText(job.code, job.message), ...failed?.(job) });
      return job;
    } catch (error) {
      toast({ id: tid, kind: "error", title: t("toast.notSent"), body: reasonText(error.code, error.detail) });
      return null;
    } finally {
      ui.busy.delete(busyKey);
      renderDock();
    }
  }
  function confirmStop() {
    // Nothing left to remove: only the unfinished part of the last cleanup, no need to confirm.
    if (fieldTotal() === 0) { stopAll(); return; }
    openDialog("confirm", `<div class="dialog-head"><h2 id="dlg-title">${esc(t("stop.confirmTitle"))}</h2></div>
      <div class="dialog-body"><p>${esc(t("stop.confirmBody", { n: fieldTotal() }))}</p>${S.statMatch.baseline ? `<p class="dialog-note">${icon("scale", "icon-sm")}<span>${esc(t("stop.matchReset"))}</span></p>` : ""}</div>
      <div class="dialog-foot"><button class="btn btn-ghost" type="button" data-action="dialog-close">${esc(t("common.cancel"))}</button><button class="btn btn-danger-solid" type="button" data-action="stop-confirm" data-autofocus>${icon("trash", "icon-sm")}${esc(t("field.stop"))}</button></div>`, "dialog-sm");
  }
  async function stopAll() {
    closeDialog();
    if (ui.busy.has("stop")) return;
    ui.busy.add("stop");
    renderDock();
    const tid = toast({ kind: "pending", title: t("toast.stop.pending") });
    try {
      let job = await RT.command("stop");
      const cleared = job.cleared || 0;
      // arena_controller.lua restores before it destroys, so a unit still alive at that moment leaves
      // one record that only the next pass can drop. That pass destroys nothing; do it in this click.
      if (job.code === "restorePending") job = await RT.command("stop");
      if (job.status === "succeeded") toast({ id: tid, kind: "success", title: t("toast.stop.ok", { n: cleared }) });
      else if (S.cleanup && S.cleanup !== "spawn_uncertain") toast({ id: tid, kind: "warning", title: t("toast.stop.partial"), body: t("toast.stop.partial.body"), actions: [{ label: t("field.unfinished.again"), action: "stop-again" }] });
      else toast({ id: tid, kind: job.status === "uncertain" ? "warning" : "error", title: t("toast.failed"), body: reasonText(job.code, job.message) });
      if (job.status === "succeeded" || RT.owned() === 0) ui.roster = { blue: {}, red: {}, neutral: {}, companion: ui.roster.companion };
    } catch (error) {
      toast({ id: tid, kind: "error", title: t("toast.notSent"), body: reasonText(error.code, error.detail) });
    } finally {
      ui.busy.delete("stop");
      renderDock();
    }
  }
  async function rematch() {
    // The stop below makes equal stats pick a new baseline, so the old baseline is summoned first
    // and the rematch keeps the same numbers.
    const baseId = S.statMatch.mode === "match" ? S.statMatch.baseline?.id : null;
    const lineup = ["blue", "red"].flatMap(team => Object.entries(ui.roster[team]).map(([id, n]) => ({ id, team, n })))
      .sort((a, b) => (b.id === baseId) - (a.id === baseId));
    if (!lineup.length || ui.busy.has("rematch")) return;
    ui.busy.add("rematch");
    const tid = toast({ kind: "pending", title: t("toast.rematch.pending") });
    try {
      let job = await RT.command("stop");
      if (job.code === "restorePending") job = await RT.command("stop");
      if (job.status !== "succeeded") throw job;
      ui.roster = { blue: {}, red: {}, neutral: {}, companion: ui.roster.companion };
      renderDock();
      for (const [i, item] of lineup.entries()) {
        for (let left = item.n; left > 0; left -= 8) {
          const n = Math.min(8, left);
          toast({ id: tid, kind: "pending", title: t("toast.rematch.progress", { i: i + 1, total: lineup.length }) });
          job = await RT.command("spawn", { unit_id: item.id, team: item.team, count: n });
          if (job.status !== "succeeded") throw job;
          ui.roster[item.team][item.id] = (ui.roster[item.team][item.id] || 0) + n;
          renderBattle();
        }
      }
      job = await RT.command("start");
      if (job.status !== "succeeded") throw job;
      toast({ id: tid, kind: "success", title: t("toast.rematch.ok") });
    } catch (error) {
      toast({ id: tid, kind: "error", title: t("toast.rematch.fail"), body: S.cleanup ? cleanupBlocker() : reasonText(error.code, error.detail || error.message), actions: S.cleanup && S.cleanup !== "spawn_uncertain" ? [{ label: t("field.unfinished.again"), action: "stop-again" }] : [] });
    } finally {
      ui.busy.delete("rematch");
      renderDock();
    }
  }

  // ---------- Hotkey capture ----------
  function startCapture(target) {
    ui.capture = target;
    ui.keyNote = null;
    ui.unitKeyError = "";
    rerenderCaptureHost();
  }
  function cancelCapture() {
    const host = ui.capture;
    ui.capture = null;
    if (host) rerenderCaptureHost(host);
  }
  // A function key captured in the 观战 card (host "view") redraws only that card, not the whole arena page.
  function rerenderCaptureHost(host = ui.capture) {
    if (!host) return;
    if (host.kind === "unit") renderSelection();
    else if (host.host === "view") renderView();
    else if (ui.page === "hotkeys") renderPage();
  }
  // configure_keys always carries all the bindings; action names the row that shows the result
  // (none for "clear all", which reports in a toast), host the card it is in.
  async function saveGlobalKeys(bindings, note, action = ui.capture?.action, host = ui.capture?.host || "") {
    ui.capture = null;
    ui.keyNote = action ? { action, host, type: "saving" } : null;
    ui.keysSaving = true;
    if (host === "view") renderView(); else renderPage();
    let ok = false, text;
    try {
      const job = await RT.command("configure_keys", { bindings });
      ok = job.status === "succeeded";
      text = ok ? note : reasonText(job.code, job.message);
    } catch (error) {
      text = reasonText(error.code, error.detail);
    }
    ui.keysSaving = false;
    // Set in the 观战 card: a toast says it worked; the row keeps only a problem.
    if (action && host === "view") {
      ui.keyNote = ok ? null : { action, host, type: "err", text };
      if (ok) toast({ kind: "success", title: note });
    } else if (action) ui.keyNote = { action, host, type: ok ? "ok" : "err", text };
    else toast({ kind: ok ? "success" : "error", title: ok ? note : t("toast.failed"), body: ok ? "" : text });
    if (host === "view") renderView();
    else if (ui.page === "hotkeys") renderPage();
  }
  function handleGlobalCapture(e) {
    const { action, host = "" } = ui.capture, got = readCapture(e);
    const redraw = () => (host === "view" ? renderView() : renderPage());
    // An unusable key keeps the box listening, so the player can just press another one.
    const refuse = text => { ui.keyNote = { action, host, type: "err", text }; redraw(); };
    if (got.error) { refuse(got.error); return; }
    const label = vkLabel(got.code, got.mods), mine = S.keys[action];
    if (mine && mine.code === got.code && mine.mods === got.mods) { cancelCapture(); return; }
    const owner = keyOwner(got.code, { action });
    if (owner?.kind === "unit") { refuse(clashText(got, S.unitKeys[owner.id], t("keys.owner.unit", { name: byId.get(owner.id)?.name || owner.id })) + t("keys.clash.unitFix")); return; }
    if (owner) {
      ui.keyNote = { action, host, type: "conflict", key: got, other: owner.action, text: clashText(got, S.keys[owner.action], t("keys.owner.action", { action: t("keys.action." + owner.action) })) };
      ui.capture = null;
      redraw();
      return;
    }
    saveGlobalKeys({ ...S.keys, [action]: got }, t("toast.key.saved", { action: t("keys.action." + action), key: label }));
  }
  async function handleUnitCapture(e) {
    const id = ui.capture.id, u = byId.get(id), got = readCapture(e);
    if (got.error) { ui.unitKeyError = got.error; renderSelection(); return; }
    const { code, mods } = got;
    const owner = keyOwner(code, { unitId: id });
    const reason = owner?.kind === "unit" ? clashText(got, S.unitKeys[owner.id], t("keys.owner.unit", { name: byId.get(owner.id)?.name || owner.id })) + t("keys.clash.unitFix")
      : owner ? clashText(got, S.keys[owner.action], t("keys.owner.action", { action: t("keys.action." + owner.action) })) + t("keys.clash.actionFix") : "";
    ui.capture = null;
    if (reason) { ui.unitKeyError = reason; renderSelection(); return; }
    ui.unitKeyError = "";
    renderSelection();
    try {
      const job = await RT.command("configure_unit_key", { unit_id: id, code, mods, team: ui.team, count: ui.count });
      if (job.status === "succeeded") toast({ kind: "success", title: t("toast.unitKey.saved", { name: u.name, key: vkLabel(code, mods) }) });
    } catch (error) {
      toast({ kind: "error", title: t("toast.notSent"), body: reasonText(error.code, error.detail) });
    }
    renderSelection();
    if ($("#grid")) renderGrid();
  }

  // ---------- Hotkeys page ----------
  function keyRowHTML(action) {
    const capturing = ui.capture?.kind === "global" && ui.capture.action === action;
    const note = ui.keyNote?.action === action ? ui.keyNote : null;
    let noteHTML = "";
    if (capturing && note?.type === "err") noteHTML = `<div class="key-note err">${esc(note.text)}</div>`;
    else if (note?.type === "conflict") noteHTML = `<div class="key-note err">${esc(note.text)} <button class="btn-link" type="button" data-action="key-swap">${icon("swap", "icon-sm")} ${esc(t(S.keys[action] ? "keys.swap" : "keys.take"))}</button></div>`;
    else if (note?.type === "ok") noteHTML = `<div class="key-note ok">${icon("check", "icon-sm")} ${esc(note.text)}</div>`;
    else if (note?.type === "err") noteHTML = `<div class="key-note err">${esc(note.text)}</div>`;
    const side = capturing
      ? `<span class="capture-box">${icon("keyboard", "icon-sm")}${esc(t("keys.capture"))}</span><button class="btn btn-ghost btn-sm" type="button" data-action="key-cancel">${esc(t("common.cancel"))}</button>`
      : note?.type === "saving"
        ? `<span class="spinner"></span><span class="muted">${esc(t("keys.saving"))}</span>`
        : `${S.keys[action] ? keyCap(S.keys[action], "kbd-lg") : `<span class="key-unbound">${esc(t("keys.unbound"))}</span>`}
          <button class="btn btn-secondary btn-sm" type="button" data-action="key-capture" data-key-action="${action}" ${RT.online() && !ui.keysSaving ? "" : "disabled"}>${esc(t(S.keys[action] ? "keys.change" : "keys.set"))}</button>
          ${S.keys[action] ? `<button class="icon-btn icon-btn-sm" type="button" data-action="key-clear" data-key-action="${action}" ${RT.online() && !ui.keysSaving ? "" : "disabled"} aria-label="${esc(t("keys.clear"))}" title="${esc(t("keys.clear"))}">${icon("x", "icon-sm")}</button>` : ""}`;
    return `<div class="row key-row${capturing ? " is-capturing" : ""}${note?.type === "conflict" || (capturing && note?.type === "err") ? " has-error" : ""}">
      <span class="row-icon">${icon(KEY_ICONS[action])}</span>
      <div class="row-main"><div class="row-title">${esc(t("keys.action." + action))}</div><div class="row-desc">${esc(t("keys.desc." + action))}</div>${noteHTML}</div>
      <div class="row-side">${side}</div>
    </div>`;
  }
  function hotkeysHTML() {
    const unitKeys = Object.entries(S.unitKeys), bound = Object.values(S.keys).filter(Boolean).length;
    return `<div class="stack">
      <div class="page-head"><div><h1 class="page-title">${esc(t("keys.title"))}</h1><p class="page-sub">${esc(t("keys.subtitle"))}</p></div>
        <button class="btn btn-ghost btn-sm" type="button" data-action="keys-clear-all" ${RT.online() && bound && !ui.keysSaving ? "" : "disabled"}>${icon("trash", "icon-sm")}${esc(t("keys.clearAll"))}</button></div>
      ${RT.online() ? "" : `<div class="callout callout-amber">${icon("gamepad")}<div class="callout-body"><strong>${esc(t("keys.offline.title"))}</strong><span>${esc(t("keys.offline.body"))}</span></div></div>`}
      <section class="card"><div class="card-head"><h2 class="card-title">${esc(t("keys.global"))}</h2><span class="chip">${esc(t("keys.boundCount", { n: bound, total: Object.keys(S.keys).length }))}</span></div><p class="card-desc">${esc(t("keys.global.desc"))}</p>
        ${KEY_GROUPS.map(([group, actions]) => `<div class="section-label key-group">${esc(t("keys.group." + group))}</div><div class="rows">${actions.map(keyRowHTML).join("")}</div>`).join("")}</section>
      <section class="card"><div class="card-head"><h2 class="card-title">${esc(t("keys.unit"))}</h2><span class="chip">${fmtNum(unitKeys.length)}</span></div><p class="card-desc">${esc(t("keys.unit.desc"))}</p>
        <div class="rows" style="margin-top:10px">${unitKeys.length ? unitKeys.map(([id, k]) => {
          const u = byId.get(id);
          return `<div class="row unitkey-item"><span class="avatar sp-${u?.species || "GuaiMian"}${u ? artClass(u) : ""}">${u ? avatarArt(u) : ""}<span class="avatar-initial">${esc(u?.initial || "?")}</span></span><div class="row-main"><div class="row-title">${esc(u?.name || id)}</div><div class="row-desc">${k.team ? `<span class="team-dot" style="background:var(--${k.team})"></span>` : ""}${esc(unitKeyUses(k))}</div></div><div class="row-side">${kbd(vkLabel(k.code, k.mods), "kbd-lg")}<button class="icon-btn icon-btn-sm" type="button" data-action="unitkey-remove" data-id="${id}" aria-label="${esc(t("keys.unit.remove"))}" title="${esc(t("keys.unit.remove"))}">${icon("x", "icon-sm")}</button></div></div>`;
        }).join("") : `<div class="row"><div class="row-main"><div class="row-desc">${esc(t("keys.unit.empty"))}</div></div><div class="row-side"><button class="btn btn-secondary btn-sm" type="button" data-action="nav" data-page="arena">${icon("swords", "icon-sm")}${esc(t("keys.unit.go"))}</button></div></div>`}</div></section>
      <details class="advanced"><summary><span class="row-icon">${icon("scan")}</span><div class="row-main"><div class="row-title">${esc(t("keys.advanced"))}</div><div class="row-desc">${esc(t("keys.advanced.desc"))}</div></div>${icon("chevron-down", "chev")}</summary>
        <div class="rows">${keyRowHTML("refresh_catalog")}</div></details>
    </div>`;
  }

  // ---------- Settings page ----------
  function compState(ok) { return ok ? `<span class="state-icon state-ok">${icon("check")}</span>` : `<span class="state-icon state-missing">${icon("alert")}</span>`; }
  // The mod is installed but is not the build this app ships (after an app update).
  const modOutdated = () => !!S.components?.some(c => c.id === "mod" && !c.ok && c.detail);
  function componentsHTML() {
    const comps = (S.components || [{ id: "game", ok: true, detail: "build 26266538" }, { id: "loader", ok: S.installed, detail: "UE4SS 3.0.1" }, { id: "mod", ok: S.installed, detail: "v" + S.modVersion }]).map(c => [c.id, c.ok, c.detail, c.warn]);
    const missing = comps.some(c => !c[1]);
    return `<div class="comp-list">${comps.map(([id, ok, detail, warn]) => `<div class="comp">${compState(ok)}<span class="comp-name">${esc(t("comp." + id))}<small>${esc(detail)}</small></span>${warn ? `<span class="chip chip-amber">${esc(t("comp.untested"))}</span>` : ""}<span class="${ok ? "muted" : ""}" style="font-size:12.5px">${esc(t(ok ? "comp.ok" : id === "mod" && detail ? "comp.outdated" : "comp.missing"))}</span></div>`).join("")}</div>
      ${ui.installing ? `<div style="margin-top:10px"><div class="progress"><i style="width:${Math.round(ui.installing.ratio * 100)}%"></i></div><div class="progress-meta"><span>${esc(t("comp.installing", { step: t("comp." + ui.installing.step) }))}</span><span>${Math.round(ui.installing.ratio * 100)}%</span></div></div>`
        : missing ? `<div class="callout-actions"><button class="btn btn-primary btn-sm" type="button" data-action="install-components">${icon("download", "icon-sm")}${esc(t("comp.install"))}</button></div>` : ""}`;
  }
  // ---------- Fun features (fun_features.lua) ----------
  // Player-only switches; the mod saves them, so they show the game's answer and wait for it to connect.
  const FUN = [["SHACHI", "shachi", "zap"], ["DEFLECT", "deflect", "shield"], ["DODGE", "dodge", "swap"]];
  function funState(feature) {
    const f = S.fun;
    if (feature === "SHACHI") return f.shachiState === "locked" ? ["green", t("fun.state.locked")]
      : f.shachiState === "failed" ? ["amber", t("fun.state.failed")] : ["", t("fun.state.waitMap")];
    if (f.guardState === "failed") return ["amber", t("fun.state.failed")];
    if (f.guardState === "off") return ["", t("fun.state.waitMap")];
    const n = feature === "DEFLECT" ? f.deflects : f.dodges;
    return n ? ["green", t(feature === "DEFLECT" ? "fun.state.deflects" : "fun.state.dodges", { n })] : ["", t("fun.state.waiting")];
  }
  function funHTML() {
    const f = S.fun, online = RT.online(), usable = online && f.supported;
    const callout = !online ? ["info", "fun.offline"] : !f.supported ? ["alert", "fun.old"] : null;
    const rows = FUN.map(([feature, key, ic]) => {
      const on = f[key], busy = ui.busy.has("fun_" + feature);
      const [tone, text] = on && usable ? funState(feature) : ["", ""];
      return `<div class="row"><span class="row-icon">${icon(ic)}</span>
        <div class="row-main"><div class="row-title">${esc(t("fun." + feature + ".name"))}</div><div class="row-desc">${esc(t("fun." + feature + ".desc"))}</div>
          ${text ? `<div class="fun-state${tone ? " is-" + tone : ""}">${tone === "green" ? icon("check-circle", "icon-sm") : tone === "amber" ? icon("alert", "icon-sm") : icon("clock", "icon-sm")}<span>${esc(text)}</span></div>` : ""}</div>
        <button class="switch" type="button" role="switch" aria-checked="${on}" aria-busy="${busy}" data-action="fun-toggle" data-feature="${feature}" aria-label="${esc(t("fun." + feature + ".name"))}" ${usable && !busy ? "" : "disabled"}></button></div>`;
    }).join("");
    return `<div class="stack">
      <div class="page-head"><div><h1 class="page-title">${esc(t("fun.title"))}</h1><p class="page-sub">${esc(t("fun.subtitle"))}</p></div></div>
      ${callout ? `<div class="callout${callout[0] === "alert" ? " callout-amber" : ""}">${icon(callout[0])}<div class="callout-body"><span>${esc(t(callout[1]))}</span></div></div>` : ""}
      <section class="card"><div class="rows">${rows}</div></section>
      <p class="muted" style="font-size:12.5px">${esc(t("fun.note"))}</p>
    </div>`;
  }
  async function toggleFun(feature) {
    const key = FUN.find(([f]) => f === feature)?.[1];
    if (!key) return;
    const enabled = !S.fun[key], name = t("fun." + feature + ".name");
    const busyKey = "fun_" + feature;
    const pending = run("set_fun_feature", { busyKey, payload: { feature, enabled }, ok: () => t(enabled ? "toast.fun.on" : "toast.fun.off", { name }) });
    if (ui.page === "fun") renderPage();
    await pending;
    if (ui.page === "fun") renderPage();
  }
  function settingsHTML() {
    const opt = (action, value, checked, main, sub = "", extra = "") => `<button class="option ${extra}" type="button" role="radio" aria-checked="${checked}" data-action="${action}" data-value="${value}"><span class="radio"></span><span class="option-main"><span>${main}</span>${sub ? `<small>${sub}</small>` : ""}</span></button>`;
    const sw = (key, title, desc) => `<div class="row"><div class="row-main"><div class="row-title">${esc(title)}</div><div class="row-desc">${esc(desc)}</div></div><button class="switch" type="button" role="switch" aria-checked="${ui.settings[key]}" data-action="toggle-setting" data-setting="${key}" aria-label="${esc(title)}"></button></div>`;
    const scan = S.scan;
    return `<div class="stack">
      <div class="page-head"><div><h1 class="page-title">${esc(t("settings.title"))}</h1><p class="page-sub">${esc(t("settings.subtitle"))}</p></div></div>
      <section class="card"><div class="card-head"><h2 class="card-title">${esc(t("settings.language"))}</h2></div>
        <div class="card-body"><div class="option-list" role="radiogroup" aria-label="${esc(t("settings.language"))}">
          ${opt("set-lang", "auto", ui.langMode === "auto", esc(t("settings.language.auto")), esc(t("settings.language.detected", { tz: detected.tz || "—", lang: langName(detected.lang) })), "option-wide")}
          ${I18N.LANGS.map(l => opt("set-lang", l.id, ui.langMode === "manual" && ui.lang === l.id, `<span lang="${l.html}">${esc(l.name)}</span>`)).join("")}
        </div><p class="muted" style="font-size:12.5px;margin-top:10px">${esc(t("settings.language.unitNote"))}</p></div></section>
      <section class="card"><div class="card-head"><h2 class="card-title">${esc(t("settings.appearance"))}</h2></div>
        <div class="card-body"><div class="theme-tiles" role="radiogroup" aria-label="${esc(t("settings.appearance"))}">
          ${["light", "dark"].map(th => `<button class="theme-tile" type="button" role="radio" aria-checked="${ui.theme === th}" data-action="set-theme" data-value="${th}"><span class="theme-preview ${th}"><i></i><i></i></span><span class="theme-label"><span class="radio"></span>${esc(t("settings.theme." + th))}</span></button>`).join("")}
        </div></div></section>
      <section class="card"><div class="card-head"><h2 class="card-title">${esc(t("settings.game"))}</h2>${S.installed ? `<span class="chip chip-green">${icon("check")}${esc(t("settings.game.ok"))}</span>` : ""}</div>
        <div class="card-body">
          <div class="field-label" style="margin-top:4px">${esc(t("settings.game.path"))}</div>
          <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><div class="path-field" style="flex:1">${icon("folder", "icon-sm")}<span title="${esc(gamePath())}">${esc(gamePath() || t("path.none"))}</span></div>
            <button class="btn btn-secondary btn-sm" type="button" data-action="detect-game" ${ui.detecting ? "disabled" : ""}>${ui.detecting ? '<span class="spinner"></span>' : icon("search", "icon-sm")}${esc(t("settings.game.detect"))}</button>
            <button class="btn btn-ghost btn-sm" type="button" data-action="change-path">${esc(t("settings.game.change"))}</button></div>
          <div class="field-label" style="margin-top:16px">${esc(t("settings.game.components"))}</div>
          ${componentsHTML()}
        </div></section>
      <section class="card"><div class="card-head"><h2 class="card-title">${esc(t("settings.updates"))}</h2><button class="btn btn-secondary btn-sm" type="button" data-action="open-update">${icon("refresh", "icon-sm")}${esc(t("about.check"))}</button></div>
        <div class="rows" style="margin-top:6px">${sw("autoUpdate", t("settings.updates.auto"), t("settings.updates.autoDesc"))}</div></section>
      <details class="advanced"><summary><span class="row-icon">${icon("sliders")}</span><div class="row-main"><div class="row-title">${esc(t("settings.advanced"))}</div><div class="row-desc">${esc(t("settings.advanced.desc"))}</div></div>${icon("chevron-down", "chev")}</summary>
        <div class="rows">
          <div class="row"><div class="row-main"><div class="row-title">${esc(t("settings.scan"))}</div><div class="row-desc">${esc(t("settings.scan.desc"))}</div>
            ${scan ? `<div style="margin-top:10px"><div class="progress"><i style="width:${(scan.done / scan.total * 100).toFixed(1)}%"></i></div><div class="progress-meta"><span>${esc(t("settings.scan.progress", { done: fmtNum(scan.done), total: fmtNum(scan.total) }))}</span><span>${Math.round(scan.done / scan.total * 100)}%</span></div></div>` : ""}</div>
            <button class="btn btn-secondary btn-sm" type="button" data-action="scan" ${scan || !RT.online() ? "disabled" : ""}>${icon("scan", "icon-sm")}${esc(t(scan ? "settings.scan.running" : "settings.scan.btn"))}</button></div>
          ${RT.demo ? sw("allUnits", t("settings.allUnits"), t("settings.allUnits.desc")) : ""}
          ${sw("tech", t("settings.tech"), t("settings.tech.desc"))}
          <div class="row"><div class="row-main"><div class="row-title">${esc(t("settings.folder"))}</div><div class="row-desc mono">…\\ue4ss\\Mods\\PhantomGladiator\\Runtime</div></div><button class="btn btn-secondary btn-sm" type="button" data-action="open-folder">${icon("folder", "icon-sm")}${esc(t("settings.folder.btn"))}</button></div>
          <div class="row"><div class="row-main"><div class="row-title">${esc(t("settings.report"))}</div><div class="row-desc">${esc(t("settings.report.desc"))}</div></div><button class="btn btn-secondary btn-sm" type="button" data-action="export-report">${icon("file", "icon-sm")}${esc(t("settings.report.btn"))}</button></div>
        </div></details>
      <div><button class="btn btn-ghost btn-sm" type="button" data-action="reset-settings">${icon("refresh", "icon-sm")}${esc(t("settings.reset"))}</button></div>
    </div>`;
  }

  // ---------- About page ----------
  function aboutHTML() {
    const u = ui.update;
    const status = u.phase === "checking" ? `<span class="spinner"></span>${esc(t("update.checking"))}`
      : u.info && !u.info.latest && u.phase !== "done" ? `<span class="chip chip-blue">${icon("sparkles")}${esc(t("about.newVersion", { v: u.info.version }))}</span>`
      : u.lastChecked ? esc(t("about.lastChecked", { time: fmtAgo(u.lastChecked) })) : "";
    return `<div class="stack">
      <section class="card about-hero">
        <span class="seal seal-lg" aria-hidden="true">斗</span>
        <div style="min-width:0"><h2>Phantom Gladiator</h2><p>${esc(t("app.tagline"))}</p>
          <div class="about-version"><span class="chip chip-outline">${esc(t("about.version", { v: S.appVersion }))}</span><span class="chip chip-amber">${esc(t("about.channel"))}</span></div></div>
        <div class="about-hero-side"><button class="btn btn-primary" type="button" data-action="open-update">${icon("refresh", "icon-sm")}${esc(t("about.check"))}</button><small class="muted" style="display:flex;align-items:center;gap:6px;font-size:12px">${status}</small></div>
      </section>
      <section class="card">
        <div class="author"><span class="author-avatar" aria-hidden="true">泠</span>
          <div style="min-width:0"><div class="muted" style="font-size:12px">${esc(t("about.author"))}</div><div class="author-name">泠依_01</div>
            <div class="author-meta">${icon("tv", "icon-sm")}<span>${esc(t("about.bili"))}</span><b class="mono" style="font-size:13px">10010098</b>
              <button class="icon-btn icon-btn-sm" type="button" data-action="copy-uid" aria-label="${esc(t("about.copyUid"))}" title="${esc(t("about.copyUid"))}">${icon("copy", "icon-sm")}</button></div></div></div>
        <div class="link-buttons">
          <a class="btn btn-secondary" href="${BILI}" target="_blank" rel="noopener noreferrer">${icon("tv", "icon-sm")}${esc(t("about.visitBili"))}${icon("external", "icon-sm")}</a>
          <a class="btn btn-secondary" href="${REPO}" target="_blank" rel="noopener noreferrer">${icon("code", "icon-sm")}GitHub${icon("external", "icon-sm")}</a>
          <a class="btn btn-ghost" href="${REPO}/issues" target="_blank" rel="noopener noreferrer">${icon("message", "icon-sm")}${esc(t("about.feedback"))}</a>
        </div>
      </section>
      <section class="card"><div class="card-head"><h2 class="card-title">${esc(t("about.legalTitle"))}</h2></div>
        <div class="card-body"><p class="legal">${esc(t("about.disclaimer"))}</p><p class="legal" style="margin-top:8px">${esc(t("about.license"))}</p></div></section>
    </div>`;
  }

  // ---------- Update flow ----------
  const LINE_IDS = ["auto", "cn1", "cn2", "github"];
  const versionParts = v => String(v || "").split(".").map(n => parseInt(n, 10) || 0);
  const compareVersions = (a, b) => {
    const x = versionParts(a), y = versionParts(b);
    for (let i = 0; i < Math.max(x.length, y.length); i++) if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) - (y[i] || 0);
    return 0;
  };
  // The oldest version a player can go back to: from here on the app installs an update in place and the new exe waits
  // for the old one (desktop/AppUpdate.cs), so the old copy starts properly and can update forward again later.
  const ROLLBACK_FROM = "0.37.6";
  const releaseNotes = r => r?.notes?.[I18N.lang] || r?.notes?.en || r?.notes?.zh || [];
  // Every released version this copy of the app has received (changelog.js), newest first, in the app's language.
  function releaseHistoryHTML() {
    const list = (window.PG_CHANGELOG || []).filter(r => compareVersions(r.version, S.appVersion) <= 0);
    if (!list.length) return "";
    const items = list.map(r => {
      const notes = releaseNotes(r);
      const current = compareVersions(r.version, S.appVersion) === 0 ? `<span class="chip chip-green">${esc(t("update.history.current"))}</span>` : "";
      const back = compareVersions(r.version, S.appVersion) < 0 && compareVersions(r.version, ROLLBACK_FROM) >= 0
        ? `<button class="btn btn-secondary btn-sm release-rollback" type="button" data-action="update-rollback" data-value="${esc(r.version)}">${esc(t("update.rollback"))}</button>` : "";
      return `<div class="release-item"><div class="release-head"><strong>v${esc(r.version)}</strong><span class="muted">${esc(fmtDate(r.date))}</span>${current}${back}</div><ul class="notes">${notes.map(n => `<li>${esc(n)}</li>`).join("")}</ul></div>`;
    }).join("");
    return `<details class="release-history"><summary>${icon("history", "icon-sm")}<span>${esc(t("update.history"))}</span><span class="muted">${esc(t("update.history.count", { n: list.length }))}</span>${icon("chevron-down", "icon-sm release-chevron")}</summary><div class="release-list">${items}</div></details>`;
  }
  // When no line answers the speed test the first one is still tried: the short test can time out where a download works.
  function lineFor(info, id) { return id === "auto" ? [...info.lines].filter(l => l.ms !== null).sort((a, b) => a.ms - b.ms)[0] || info.lines[0] : info.lines.find(l => l.id === id); }
  function updateHTML() {
    const u = ui.update, info = u.info;
    const head = title => `<div class="dialog-head"><h2 id="dlg-title">${esc(title)}</h2><button class="icon-btn icon-btn-sm" type="button" data-action="dialog-close" aria-label="${esc(t("common.close"))}">${icon("x")}</button></div>`;
    const state = (badge, title, body, extra = "") => `<div class="update-state">${badge}<h3>${esc(title)}</h3><p>${esc(body)}</p>${extra}</div>`;
    switch (u.phase) {
      case "checking":
        return head(t("update.title")) + `<div class="dialog-body">${state('<span class="state-badge"><span class="spinner spinner-lg"></span></span>', t("update.checking"), t("update.checking.sub"))}</div>`;
      case "latest":
        return head(t("update.title")) + `<div class="dialog-body">${state(`<span class="state-badge ok">${icon("check")}</span>`, t("update.latest.title"), t("update.latest.body", { v: S.appVersion }))}${releaseHistoryHTML()}</div><div class="dialog-foot"><button class="btn btn-primary" type="button" data-action="dialog-close">${esc(t("common.done"))}</button></div>`;
      case "error":
        return head(t("update.title")) + `<div class="dialog-body">${state(`<span class="state-badge err">${icon("cloud-off")}</span>`, t("update.error.title"), t("update.error.body"), `<p class="muted" style="font-size:12px">${esc(t("update.error.tried", { list: u.error.tried.map(s => t("update.source." + s)).join(" · ") }))}</p>`)}${releaseHistoryHTML()}</div>
          <div class="dialog-foot"><a class="btn btn-ghost" href="${REPO}/releases" target="_blank" rel="noopener noreferrer">${icon("external", "icon-sm")}${esc(t("update.manual"))}</a><button class="btn btn-primary" type="button" data-action="update-check">${icon("refresh", "icon-sm")}${esc(t("common.retry"))}</button></div>`;
      case "available": {
        const best = lineFor(info, "auto");
        const lines = LINE_IDS.map(id => {
          const l = id === "auto" ? best : info.lines.find(x => x.id === id);
          const lat = !l || l.ms === null ? `<span class="latency bad">${esc(t("update.line.timeout"))}</span>` : `<span class="latency${l.ms > 100 ? " slow" : ""}">${icon("signal", "icon-sm")}${l.ms} ms</span>`;
          const sub = id === "auto" ? t("update.line.autoDesc", { line: t("update.line." + best.id) }) : t("update.line." + id + ".desc");
          return `<button class="line" type="button" role="radio" aria-checked="${u.line === id}" data-action="update-line" data-value="${id}" ${l && l.ms === null ? "disabled" : ""}><span class="radio"></span><span class="line-main"><strong>${esc(t("update.line." + id))}</strong><small>${esc(sub)}</small></span>${lat}</button>`;
        }).join("");
        if (info.rollback) {
          const notes = releaseNotes((window.PG_CHANGELOG || []).find(r => r.version === info.version));
          return head(t("update.title")) + `<div class="dialog-body">
            <div class="update-head"><span class="state-badge">${icon("history")}</span><div><h3>${esc(t("update.rollback.title", { v: info.version }))}</h3><div class="muted" style="font-size:12.5px">${esc(t("update.available.meta", { date: fmtDate(info.date), size: fmtBytes(info.size), current: S.appVersion }))}</div></div></div>
            <div class="callout callout-amber">${icon("alert")}<div class="callout-body"><span>${esc(t("update.rollback.body"))}</span></div></div>
            ${notes.length ? `<div class="section-label">${esc(t("update.notes"))}</div><ul class="notes">${notes.map(n => `<li>${esc(n)}</li>`).join("")}</ul>` : ""}
            <div class="section-label">${esc(t("update.line"))}</div>
            <div class="line-list" role="radiogroup" aria-label="${esc(t("update.line"))}">${lines}</div>
          </div>
          <div class="dialog-foot"><span class="muted grow" style="font-size:12px;display:flex;gap:6px;align-items:center">${icon("shield", "icon-sm")}${esc(t("update.safe"))}</span><button class="btn btn-ghost" type="button" data-action="update-check">${esc(t("common.cancel"))}</button><button class="btn btn-primary" type="button" data-action="update-download" data-autofocus>${icon("download", "icon-sm")}${esc(t("update.rollback.confirm"))}</button></div>`;
        }
        return head(t("update.title")) + `<div class="dialog-body">
            <div class="update-head"><span class="state-badge new">${icon("sparkles")}</span><div><h3>${esc(t("update.available.title", { v: info.version }))}</h3><div class="muted" style="font-size:12.5px">${esc(t("update.available.meta", { date: fmtDate(info.date), size: fmtBytes(info.size), current: S.appVersion }))}</div></div></div>
            <div class="section-label">${esc(t("update.notes"))}</div>
            <ul class="notes">${(info.notes?.length ? info.notes : [1, 2, 3].map(i => t("update.note" + i))).map(n => `<li>${esc(n)}</li>`).join("")}</ul>
            <div class="section-label">${esc(t("update.line"))}</div>
            <div class="line-list" role="radiogroup" aria-label="${esc(t("update.line"))}">${lines}</div>
            ${releaseHistoryHTML()}
          </div>
          <div class="dialog-foot"><span class="muted grow" style="font-size:12px;display:flex;gap:6px;align-items:center">${icon("shield", "icon-sm")}${esc(t("update.safe"))}</span><button class="btn btn-ghost" type="button" data-action="dialog-close">${esc(t("update.later"))}</button><button class="btn btn-primary" type="button" data-action="update-download" data-autofocus>${icon("download", "icon-sm")}${esc(t("update.download"))}</button></div>`;
      }
      case "downloading":
      case "verifying": {
        const p = u.progress || { done: 0, total: info.size, speed: 0 }, ratio = p.done / p.total, verifying = u.phase === "verifying";
        const line = t("update.line." + lineFor(info, u.line).id);
        return head(t("update.title")) + `<div class="dialog-body"><div class="dl-panel">
            <div class="dl-title">${verifying ? '<span class="spinner"></span>' : icon("download")}${esc(verifying ? t("update.verifying") : t("update.downloading", { v: info.version, line }))}</div>
            <div class="progress${verifying ? " is-green" : ""}"><i style="width:${(ratio * 100).toFixed(1)}%"></i></div>
            <div class="progress-meta"><span>${esc(verifying ? t("update.verifying.sub") : `${fmtBytes(p.done)} / ${fmtBytes(p.total)} · ${fmtBytes(p.speed)}/s`)}</span><span>${verifying ? "" : esc(t("update.eta", { time: fmtSeconds((p.total - p.done) / Math.max(p.speed, 1)) }))}</span></div>
          </div></div>
          <div class="dialog-foot">${verifying ? "" : `<button class="btn btn-ghost" type="button" data-action="update-cancel">${esc(t("update.cancel"))}</button>`}</div>`;
      }
      case "ready":
        return head(t("update.title")) + `<div class="dialog-body">
            <div class="callout callout-green">${icon("shield")}<div class="callout-body"><strong>${esc(t("update.verified"))}</strong><span>${esc(t("update.verified.body", { v: info.version }))}</span></div></div>
            ${S.gameRunning ? `<div class="callout callout-amber" style="margin-top:10px">${icon("alert")}<div class="callout-body"><strong>${esc(t("update.gameRunning.title"))}</strong><span>${esc(t("update.gameRunning.body"))}</span><div class="callout-actions"><button class="btn btn-secondary btn-sm" type="button" data-action="update-game-closed">${esc(t("update.gameClosed"))}</button></div></div></div>` : ""}
            <p style="margin-top:12px">${esc(t("update.keep"))}</p>
          </div>
          <div class="dialog-foot"><button class="btn btn-ghost" type="button" data-action="dialog-close">${esc(t("update.later"))}</button><button class="btn btn-primary" type="button" data-action="update-install" ${S.gameRunning ? "disabled" : ""}>${icon("package", "icon-sm")}${esc(t("update.install"))}</button></div>`;
      case "installing":
        return head(t("update.title")) + `<div class="dialog-body">${state('<span class="state-badge"><span class="spinner spinner-lg"></span></span>', t("update.installing"), t("update.installing.sub"))}</div>`;
      case "done":
        return head(t("update.title")) + `<div class="dialog-body">${state(`<span class="state-badge ok">${icon("check")}</span>`, t("update.done.title"), t("update.done.body", { v: S.appVersion }))}</div><div class="dialog-foot"><button class="btn btn-primary" type="button" data-action="update-restart" data-autofocus>${icon("refresh", "icon-sm")}${esc(t("update.restart"))}</button></div>`;
      default:
        return "";
    }
  }
  async function checkUpdate({ silent = false } = {}) {
    const u = ui.update;
    if (u.phase === "checking" || u.phase === "downloading" || u.phase === "verifying" || u.phase === "installing") return;
    if (silent && (u.info?.rollback || dlg?.kind === "update")) return;
    u.phase = "checking";
    if (dlg?.kind === "update") setDialog(updateHTML());
    if (ui.page === "about") renderPage();
    try {
      const info = await RT.update.check();
      u.info = info;
      u.phase = info.latest ? "latest" : "available";
      u.line = "auto";
      if (!info.latest && silent && dlg?.kind !== "update") toast({ kind: "info", title: t("toast.update.available", { v: info.version }), body: t("toast.update.body"), actions: [{ label: t("toast.update.view"), action: "open-update" }], timeout: 10000 });
    } catch (error) {
      u.phase = "error";
      u.error = { tried: error.tried || [] };
      if (silent) u.phase = "idle";
    }
    u.lastChecked = Date.now();
    store.set("lastChecked", u.lastChecked);
    if (dlg?.kind === "update") setDialog(updateHTML());
    if (ui.page === "about") renderPage();
    renderTopbar();
  }
  // Asks for the older version's download lines; the dialog then confirms it and goes on like an update.
  async function rollbackTo(version) {
    const u = ui.update;
    if (u.phase === "checking" || u.phase === "downloading" || u.phase === "verifying" || u.phase === "installing") return;
    u.phase = "checking";
    setDialog(updateHTML());
    try {
      const info = await RT.update.selectVersion(version);
      u.info = { ...info, rollback: true };
      u.phase = "available";
      u.line = "auto";
    } catch (error) {
      u.info = null;
      u.phase = "error";
      u.error = { tried: error.tried || [] };
    }
    if (dlg?.kind === "update") setDialog(updateHTML());
    renderTopbar();
  }
  function openUpdate() {
    const u = ui.update;
    if (["idle", "latest", "error", "done"].includes(u.phase) || !u.info || (u.phase === "available" && u.info.rollback)) {
      openDialog("update", "");
      checkUpdate();
    } else openDialog("update", updateHTML());
    setDialog(updateHTML());
  }
  async function downloadUpdate() {
    const u = ui.update, line = lineFor(u.info, u.line);
    u.phase = "downloading";
    u.progress = { done: 0, total: u.info.size, speed: 0 };
    setDialog(updateHTML());
    u.dl = RT.update.download(line.id, u.info.size, p => { u.progress = p; if (dlg?.kind === "update" && !patchDownload()) setDialog(updateHTML()); });
    try {
      await u.dl.promise;
      u.dl = null;
      u.phase = "verifying";
      setDialog(updateHTML());
      await RT.update.verify();
      u.phase = "ready";
    } catch (error) {
      u.dl = null;
      u.phase = "available";
      if (error.code !== "cancelled") toast({ kind: "error", title: t("update.error.title") });
    }
    if (dlg?.kind === "update") setDialog(updateHTML());
  }
  async function installUpdate() {
    const u = ui.update;
    u.phase = "installing";
    setDialog(updateHTML());
    await RT.update.install();
    u.phase = "done";
    if (dlg?.kind === "update") setDialog(updateHTML());
    renderTopbar();
  }

  // ---------- History drawer ----------
  function jobTitle(job) {
    const p = job.payload || {}, u = byId.get(p.unit_id);
    switch (job.action) {
      case "spawn": return p.team === "neutral" ? t("action.spawnNeutral", { name: u?.name, n: p.count })
        : p.team === "companion" ? t("action.spawnCompanion", { name: u?.name, n: p.count }) : t("action.spawn", { name: u?.name, n: p.count, team: teamName(p.team) });
      case "configure_unit_key": return t("action.configure_unit_key", { name: u?.name });
      case "set_spawn_difficulty": return t("action.set_spawn_difficulty", { name: diffName(p.difficulty) });
      case "set_spawn_level": {
        // The app's own payload says mode/unit; a job read back from backend.py says level_mode/unit_id.
        const mode = p.mode || p.level_mode, unit = byId.get(p.unit || p.unit_id);
        return mode === "UNIT" ? t("action.set_spawn_level.unit", { name: unit?.name || p.unit || p.unit_id, label: p.level == null ? t("level.backToDefault") : t("level.levelN", { n: p.level }) })
          : t("action.set_spawn_level", { name: mode === "CUSTOM" ? t("level.customN", { n: p.level }) : t("level.mode." + mode) });
      }
      case "set_fun_feature": return t("action.set_fun_feature", { name: t("fun." + p.feature + ".name"), state: t(p.enabled ? "fun.on" : "fun.off") });
      case "set_team_immortal": return t("action.set_team_immortal", { team: teamName(p.team), state: t(p.enabled ? "fun.on" : "fun.off") });
      case "set_clock_hud": return t("action.set_clock_hud", { state: t(p.enabled ? "fun.on" : "fun.off") });
      case "set_execution_camera": return t("action.set_execution_camera", { state: t(p.enabled ? "fun.on" : "fun.off") });
      case "set_stat_mode": return t("action.set_stat_mode", { mode: t("stats.mode." + p.mode) });
      default: return t("action." + job.action);
    }
  }
  function historyHTML() {
    const list = RT.jobs.filter(j => j.action !== "select_unit");
    const stateIcon = { pending: '<span class="spinner" style="width:14px;height:14px"></span>', succeeded: icon("check"), failed: icon("x"), uncertain: icon("alert") };
    const body = list.length ? list.map(job => `<div class="job job-${job.status}">
        <span class="job-icon">${stateIcon[job.status] || icon("clock")}</span>
        <div class="job-main"><div class="job-title">${esc(jobTitle(job))}</div>
          <div class="job-meta"><span>${esc(t("history.state." + job.status))}</span><span>·</span><span>${esc(fmtAgo(job.created))}</span><span class="mono">#${job.id}</span></div>
          ${job.status === "failed" ? `<div class="job-msg">${esc(reasonText(job.code, job.message))}</div>` : job.status === "uncertain" ? `<div class="job-msg">${esc(t("history.uncertainHelp"))}</div>` : job.warning === "matchFailed" ? `<div class="job-msg job-msg-warn">${esc(t("history.matchWarn"))}</div>` : ""}</div>
      </div>`).join("")
      : `<div class="empty"><span class="empty-icon">${icon("history")}</span><h3>${esc(t("history.empty"))}</h3><p>${esc(t("history.empty.body"))}</p></div>`;
    // Always here, so a player whose commands stopped reaching the game finds the way out.
    const waiting = S.queue?.count || 0, busy = ui.busy.has("clearQueue");
    const tools = `<div class="queue-tools${waiting ? " queue-tools-waiting" : ""}"><span>${esc(waiting ? t("queue.clear.pending", { n: waiting }) : t("queue.clear.hint"))}</span>
      <button class="btn btn-secondary btn-sm" type="button" data-action="clear-queue" ${busy ? "disabled" : ""}>${busy ? '<span class="spinner" style="width:12px;height:12px"></span>' : icon("trash", "icon-sm")}${esc(t("queue.clear"))}</button></div>`;
    return `<div class="drawer-head"><h2 id="dlg-title">${esc(t("history.title"))}</h2><button class="icon-btn icon-btn-sm" type="button" data-action="dialog-close" aria-label="${esc(t("common.close"))}">${icon("x")}</button></div><div class="drawer-body">${tools}${body}</div>`;
  }
  async function clearQueue() {
    if (ui.busy.has("clearQueue")) return;
    ui.busy.add("clearQueue");
    const refresh = () => { if (ui.page === "arena") renderBanner(); if (dlg?.kind === "history") setDialog(historyHTML()); };
    refresh();
    try {
      const r = await RT.clearQueue();
      const n = (r.cleared || 0) + (r.interrupted || 0);
      if (r.files_left?.length) toast({ kind: "warning", title: n ? t("toast.queue.cleared", { n }) : t("toast.queue.empty"), body: t("toast.queue.filesLeft") });
      else if (n) toast({ kind: "success", title: t("toast.queue.cleared", { n }), body: t("toast.queue.cleared.body") });
      else toast({ kind: "info", title: t("toast.queue.empty") });
    } catch (error) {
      toast({ kind: "error", title: t("toast.queue.failed"), body: reasonText(error.code, error.detail) });
    } finally {
      ui.busy.delete("clearQueue");
      refresh();
    }
  }
  function openHistory() {
    closePopover();
    closeDialog(false);
    const wrap = document.createElement("div");
    wrap.innerHTML = `<div class="backdrop" data-action="dialog-dismiss"></div><aside class="drawer" id="dialog" role="dialog" aria-modal="true" aria-labelledby="dlg-title" tabindex="-1">${historyHTML()}</aside>`;
    overlays.appendChild(wrap);
    dlg = { kind: "history", wrap, prev: document.activeElement };
    ui.historyOpen = true;
    ui.seenFailures = RT.jobs.filter(j => j.status === "failed" || j.status === "uncertain").length;
    renderTopbar();
    $("#dialog").focus();
  }

  // ---------- Menus & small dialogs ----------
  function connPopoverHTML() {
    const online = RT.online(), ready = RT.ready();
    const item = (ok, label) => `<div class="check-item${ok ? "" : " todo"}">${ok ? `<span class="state-icon state-ok">${icon("check")}</span>` : `<span class="state-icon" style="border:1.5px dashed var(--border-strong)"></span>`}<span>${esc(label)}</span></div>`;
    const hint = { offline: "conn.hint.offline", connecting: "conn.hint.connecting", notInMap: "conn.hint.notInMap", ready: "conn.hint.ready" }[S.game];
    return `<div class="popover-pad" style="width:320px">
      <div class="row-title">${esc(t("conn.title"))}</div>
      <div class="checklist">${item(true, t("conn.check.app"))}${item(online, t("conn.check.game"))}${item(ready, t("conn.check.map"))}</div>
      <p class="muted" style="font-size:12.5px">${esc(S.game === "mismatch" ? t("conn.hint.mismatch", { mod: S.modVersion, app: S.expectedBuild || S.appVersion }) : t(hint))}</p>
      <div class="callout-actions">
        ${S.game === "offline" ? `<button class="btn btn-primary btn-sm" type="button" data-action="launch-game">${icon("gamepad", "icon-sm")}${esc(t("conn.launch"))}</button>` : ""}
        ${S.game === "mismatch" ? `<button class="btn btn-primary btn-sm" type="button" data-action="nav" data-page="settings">${icon("download", "icon-sm")}${esc(t("conn.updateMod"))}</button>` : ""}
        <a class="btn btn-ghost btn-sm" href="${REPO}#readme" target="_blank" rel="noopener noreferrer">${esc(t("conn.help"))}${icon("external", "icon-sm")}</a>
      </div></div>`;
  }
  function langMenuHTML() {
    const check = on => (on ? icon("check", "check") : "");
    return `<div class="menu-label">${esc(t("settings.language"))}</div>
      <button class="menu-item" type="button" role="menuitemradio" aria-checked="${ui.langMode === "auto"}" data-action="set-lang" data-value="auto">${icon("globe")}<span>${esc(t("settings.language.auto"))}</span><small>${esc(langName(detected.lang))}</small>${check(ui.langMode === "auto")}</button>
      <div class="menu-sep"></div>
      ${I18N.LANGS.map(l => `<button class="menu-item" type="button" role="menuitemradio" aria-checked="${ui.langMode === "manual" && ui.lang === l.id}" data-action="set-lang" data-value="${l.id}" lang="${l.html}"><span style="width:18px"></span><span>${esc(l.name)}</span>${check(ui.langMode === "manual" && ui.lang === l.id)}</button>`).join("")}`;
  }
  function helpMenuHTML() {
    return `<button class="menu-item" type="button" role="menuitem" data-action="onboarding">${icon("book")}<span>${esc(t("help.guide"))}</span></button>
      <button class="menu-item" type="button" role="menuitem" data-action="shortcuts">${icon("keyboard")}<span>${esc(t("help.shortcuts"))}</span></button>
      <div class="menu-sep"></div>
      <a class="menu-item" role="menuitem" href="${REPO}#readme" target="_blank" rel="noopener noreferrer">${icon("help")}<span>${esc(t("help.faq"))}</span>${icon("external", "check")}</a>
      <a class="menu-item" role="menuitem" href="${REPO}/issues" target="_blank" rel="noopener noreferrer">${icon("message")}<span>${esc(t("help.feedback"))}</span>${icon("external", "check")}</a>
      <div class="menu-sep"></div>
      <button class="menu-item" type="button" role="menuitem" data-action="nav" data-page="about">${icon("info")}<span>${esc(t("nav.about"))}</span><small>v${esc(S.appVersion)}</small></button>`;
  }
  function shortcutsDialog() {
    const row = (keys, label) => `<div class="row" style="padding:10px 0"><div class="row-main">${esc(label)}</div><div class="row-side">${keys.map(k => kbd(k)).join(" ")}</div></div>`;
    openDialog("shortcuts", `<div class="dialog-head"><h2 id="dlg-title">${esc(t("help.shortcuts"))}</h2><button class="icon-btn icon-btn-sm" type="button" data-action="dialog-close" aria-label="${esc(t("common.close"))}">${icon("x")}</button></div>
      <div class="dialog-body"><div class="section-label">${esc(t("shortcuts.app"))}</div><div class="rows">
        ${row(["/"], t("shortcuts.search"))}${row(["←", "→", "↑", "↓"], t("shortcuts.move"))}${row(["Enter"], t("shortcuts.select"))}${row(["B"], t("shortcuts.blue"))}${row(["R"], t("shortcuts.red"))}${row(["N"], t("shortcuts.neutral"))}${row(["Ctrl", "Enter"], t("shortcuts.summon"))}${row(["Esc"], t("shortcuts.close"))}
      </div><div class="section-label" style="margin-top:14px">${esc(t("shortcuts.game"))}</div><div class="rows">
        ${KEY_GROUPS.flatMap(([, actions]) => actions).map(a => `<div class="row" style="padding:10px 0"><div class="row-main">${esc(t("keys.action." + a))}</div><div class="row-side">${S.keys[a] ? keyCap(S.keys[a]) : `<span class="key-unbound">${esc(t("keys.unbound"))}</span>`}</div></div>`).join("")}
      </div><p class="muted" style="font-size:12.5px;margin-top:10px">${esc(t("shortcuts.gameNote"))} <button class="btn-link" type="button" data-action="nav" data-page="hotkeys">${esc(t("shortcuts.gameSet"))}</button></p></div>`);
  }
  function pathDialog(error = "", value = gamePath()) {
    const html = `<div class="dialog-head"><h2 id="dlg-title">${esc(t("path.title"))}</h2><button class="icon-btn icon-btn-sm" type="button" data-action="dialog-close" aria-label="${esc(t("common.close"))}">${icon("x")}</button></div>
      <div class="dialog-body"><p>${esc(t("path.body"))}</p>
        <div style="display:flex;gap:8px;margin-top:12px"><label class="search" style="flex:1;min-width:0">${icon("folder")}<input id="path-input" type="text" value="${esc(value)}" spellcheck="false" style="padding-right:12px;font-family:var(--font-mono);font-size:12.5px" data-autofocus></label>
          ${RT.hasHost ? `<button class="btn btn-secondary" type="button" data-action="path-browse">${esc(t("path.browse"))}</button>` : ""}</div>
        ${error ? `<div class="inline-error">${icon("alert")}<span>${esc(error)}</span></div>` : ""}
        <p class="muted" style="font-size:12px;margin-top:10px">${esc(t("path.example"))}</p></div>
      <div class="dialog-foot"><button class="btn btn-ghost" type="button" data-action="dialog-close">${esc(t("common.cancel"))}</button><button class="btn btn-primary" type="button" data-action="path-save">${esc(t("common.save"))}</button></div>`;
    if (dlg?.kind === "path") setDialog(html); else openDialog("path", html, "dialog-sm");
  }
  function confirmScan() {
    openDialog("confirm", `<div class="dialog-head"><h2 id="dlg-title">${esc(t("scan.confirmTitle"))}</h2></div>
      <div class="dialog-body"><p>${esc(t("scan.confirmBody"))}</p></div>
      <div class="dialog-foot"><button class="btn btn-ghost" type="button" data-action="dialog-close">${esc(t("common.cancel"))}</button><button class="btn btn-primary" type="button" data-action="scan-confirm" data-autofocus>${icon("scan", "icon-sm")}${esc(t("settings.scan.btn"))}</button></div>`, "dialog-sm");
  }
  async function copyText(text) {
    try { await navigator.clipboard.writeText(text); }
    catch {
      const area = Object.assign(document.createElement("textarea"), { value: text });
      document.body.appendChild(area);
      area.select();
      document.execCommand("copy");
      area.remove();
    }
    toast({ kind: "success", title: t("common.copied"), body: text, timeout: 2500 });
  }

  // ---------- Onboarding ----------
  function onbHTML(entering) {
    const step = ui.onb.step, labels = ["onb.step.welcome", "onb.step.game", "onb.step.ready"];
    const steps = labels.map((k, i) => `${i ? '<span class="onb-step-line"></span>' : ""}<span class="onb-step${i === step ? " is-current" : i < step ? " is-done" : ""}"><i>${i < step ? icon("check", "icon-sm") : i + 1}</i>${esc(t(k))}</span>`).join("");
    let body = "", foot = "";
    if (step === 0) {
      const options = [`<option value="auto" ${ui.langMode === "auto" ? "selected" : ""}>${esc(t("settings.language.auto"))} · ${esc(langName(detected.lang))}</option>`, ...I18N.LANGS.map(l => `<option value="${l.id}" ${ui.langMode === "manual" && ui.lang === l.id ? "selected" : ""}>${esc(l.name)}</option>`)].join("");
      body = `<div class="onb-hero"><span class="seal seal-xl" aria-hidden="true">斗</span><h1 id="onb-title">${esc(t("onb.welcome.title"))}</h1><p>${esc(t("onb.welcome.body"))}</p></div>
        <div class="onb-features">${[["grid", 1], ["user-plus", 2], ["swords", 3]].map(([ic, n]) => `<div class="feature"><span class="feature-icon">${icon(ic)}</span><div class="feature-num">${esc(t("onb.stepN", { n }))}</div><h3>${esc(t("onb.f" + n))}</h3><p>${esc(t("onb.f" + n + ".desc"))}</p></div>`).join("")}</div>
        <div class="onb-lang">${icon("globe", "icon-sm")}<span>${esc(t("onb.language"))}</span><select class="select" id="onb-lang" style="height:32px" aria-label="${esc(t("settings.language"))}">${options}</select></div>`;
      foot = `<span class="grow muted" style="font-size:12.5px">${esc(t("onb.credit"))}</span><button class="btn btn-primary" type="button" data-action="onb-next" data-autofocus>${esc(t("onb.start"))}${icon("arrow-right", "icon-sm")}</button>`;
    } else if (step === 1) {
      const o = ui.onb, comps = o.comps;
      const found = o.game ? `<div class="found-card"><span class="found-icon">${icon("check")}</span><div class="found-main"><strong>${esc(t("onb.game.found"))}</strong><span class="mono" title="${esc(gamePath())}">${esc(gamePath())}</span><span class="muted" style="font-size:12px">${esc(o.game.store)} · build ${esc(o.game.build)}</span></div><button class="btn btn-ghost btn-sm" type="button" data-action="change-path">${esc(t("settings.game.change"))}</button></div>`
        : o.detect === "failed" ? `<div class="callout callout-amber">${icon("search")}<div class="callout-body"><strong>${esc(t("onb.game.notFound"))}</strong><span>${esc(t("onb.game.notFound.body"))}</span><div class="callout-actions"><button class="btn btn-primary btn-sm" type="button" data-action="change-path">${icon("folder", "icon-sm")}${esc(t("onb.game.pick"))}</button></div></div></div>`
        : `<div class="searching"><span class="spinner"></span><span>${esc(t("onb.game.searching"))}</span></div>`;
      const compList = comps ? `<div class="field-label" style="margin-top:22px">${esc(t("settings.game.components"))}</div>${componentsHTML()}` : o.game ? `<div class="searching">${'<span class="spinner"></span>'}<span>${esc(t("onb.game.checking"))}</span></div>` : "";
      const allOk = comps && S.installed;
      body = `<h1 class="onb-section-title" id="onb-title">${esc(t("onb.game.title"))}</h1><p class="onb-section-sub">${esc(t("onb.game.sub"))}</p>${found}${compList}
        ${allOk ? `<div class="callout callout-green" style="margin-top:14px">${icon("check-circle")}<div class="callout-body"><strong>${esc(t("onb.game.allOk"))}</strong><span>${esc(t("onb.game.allOk.body"))}</span></div></div>` : ""}`;
      foot = `<button class="btn btn-ghost" type="button" data-action="onb-back">${icon("chevron-left", "icon-sm")}${esc(t("onb.back"))}</button><span class="grow"></span><button class="btn btn-primary" type="button" data-action="onb-next" ${allOk ? "" : "disabled"}>${esc(t("onb.next"))}${icon("arrow-right", "icon-sm")}</button>`;
    } else {
      body = `<h1 class="onb-section-title" id="onb-title">${esc(t("onb.ready.title"))}</h1><p class="onb-section-sub">${esc(t("onb.ready.sub"))}</p>
        <div class="ready-list">${[1, 2, 3].map(n => `<div class="ready-item"><span class="ready-num">${n}</span><div><strong>${esc(t("onb.ready.s" + n))}</strong><span>${esc(t("onb.ready.s" + n + ".desc"))}</span></div></div>`).join("")}</div>`;
      foot = `<button class="btn btn-ghost" type="button" data-action="onb-back">${icon("chevron-left", "icon-sm")}${esc(t("onb.back"))}</button><span class="grow"></span><button class="btn btn-secondary" type="button" data-action="onb-launch">${icon("gamepad", "icon-sm")}${esc(t("conn.launch"))}</button><button class="btn btn-primary" type="button" data-action="onb-finish" data-autofocus>${esc(t("onb.enter"))}${icon("arrow-right", "icon-sm")}</button>`;
    }
    return `<div class="onb-card" role="dialog" aria-modal="true" aria-labelledby="onb-title">
      <div class="onb-top"><span class="seal" aria-hidden="true">斗</span><div class="onb-steps">${steps}</div>${step < 2 ? `<button class="btn btn-ghost btn-sm" type="button" data-action="onb-finish">${esc(t("onb.skip"))}</button>` : ""}</div>
      <div class="onb-body${entering ? " is-entering" : ""}" ${step === 0 ? "" : 'style="min-height:380px"'}>${body}</div>
      <div class="onb-foot">${foot}</div></div>`;
  }
  function renderOnboarding() {
    let el = $("#onb");
    if (!ui.onboarding) { el?.remove(); return; }
    if (!el) { el = document.createElement("div"); el.id = "onb"; el.className = "onb"; overlays.appendChild(el); }
    // Progress updates re-render the same step; only a step change animates and moves focus.
    const entering = ui.onb.shownStep !== ui.onb.step;
    ui.onb.shownStep = ui.onb.step;
    el.innerHTML = onbHTML(entering);
    if (entering) (el.querySelector("[data-autofocus]") || el.querySelector(".onb-card"))?.focus?.();
  }
  async function onbDetect() {
    const o = ui.onb;
    if (o.detect !== "idle") return;
    o.detect = "running";
    renderOnboarding();
    try {
      o.game = await RT.setup.detectGame();
      ui.gamePath = o.game.path;
      if (!RT.demo) await RT.setup.setGamePath(o.game.path);
    } catch {
      o.detect = "failed";
      renderOnboarding();
      return;
    }
    renderOnboarding();
    o.comps = await RT.setup.components();
    o.detect = "done";
    renderOnboarding();
  }
  // A folder the player chose by hand: the native window checks it holds the game.
  async function useGamePath(value) {
    if (RT.demo) {
      if (!/PBZ|Phantom/i.test(value)) return t("path.invalid");
      ui.gamePath = value;
      store.set("gamePath", value);
      return "";
    }
    try {
      const info = await RT.setup.setGamePath(value);
      ui.gamePath = info.path;
      ui.onb.game = { path: info.path, store: info.store, build: info.build };
      ui.onb.comps = await RT.setup.components();
      ui.onb.detect = "done";
      return "";
    } catch (error) {
      return error.code === "notGame" ? t("path.invalid") : reasonText(error.code, error.detail);
    }
  }
  async function installComponents() {
    if (ui.installing) return;
    ui.installing = { step: "loader", ratio: 0 };
    const refresh = () => { if (ui.onboarding) renderOnboarding(); if (ui.page === "settings") renderPage(); };
    refresh();
    try {
      await RT.setup.install(p => { ui.installing = p; refresh(); });
      ui.installing = null;
      if (ui.onboarding) ui.onb.comps = await RT.setup.components();
      toast({ kind: "success", title: t("toast.installed") });
    } catch (error) {
      ui.installing = null;
      toast({ kind: "error", title: t("toast.installFailed"), body: reasonText(error.code, error.detail) });
    }
    refresh();
  }
  function finishOnboarding() {
    ui.onboarding = false;
    store.set("onboarded", true);
    renderOnboarding();
    go("arena");
    scheduleAutoUpdate();
  }
  // A background check never interrupts the first-run guide; it runs once the guide is closed.
  function scheduleAutoUpdate() {
    if (!ui.settings.autoUpdate || ui.onboarding || ui.autoChecked) return;
    ui.autoChecked = true;
    setTimeout(() => checkUpdate({ silent: true }), 2600);
  }

  // ---------- Prototype demo panel ----------
  function renderDemo() {
    let panel = $("#demo-panel");
    $("#demo-fab").setAttribute("aria-expanded", String(ui.demoOpen));
    if (!ui.demoOpen) { panel?.remove(); return; }
    if (!panel) { panel = document.createElement("div"); panel.id = "demo-panel"; panel.className = "demo-panel"; document.body.appendChild(panel); }
    const group = (label, key, options) => `<div class="demo-group"><span>${label}</span><div class="demo-opts">${options.map(([value, text]) => `<button class="demo-opt" type="button" data-action="demo-set" data-key="${key}" data-value="${value}" aria-pressed="${String(S[key]) === value}">${text}</button>`).join("")}</div></div>`;
    panel.innerHTML = `<h4>${icon("sliders", "icon-sm")}原型演示控制</h4><p>只在原型里出现，用来切换各种情况。正式版没有这个面板，以下数据都是模拟的。</p>
      ${group("游戏状态", "game", [["offline", "未启动"], ["connecting", "连接中"], ["notInMap", "未进地图"], ["ready", "可以召唤"], ["mismatch", "版本不一致"]])}
      ${group("下一次清理", "stopOutcome", [["ok", "一次清完"], ["partial", "游戏留一条恢复记录"], ["stuck", "两遍都清不完"]])}
      ${group("下一次召唤的结果", "nextOutcome", [["ok", "成功"], ["error", "失败"], ["uncertain", "游戏无回执"], ["matchWarn", "数值没统一（已还原）"], ["matchAbort", "数值还原失败"]])}
      <p>后两项要先打开「数值统一」才会出现。</p>
      ${group("读不到状态的单位", "unreadable", [["0", "没有"], ["1", "1 个"]])}
      ${group("指令队列（之后的指令）", "queueScenario", [["ok", "正常"], ["stuck", "卡住（旧指令文件挡着）"]])}
      ${group("检查更新的结果", "updateScenario", [["available", "有新版本"], ["latest", "已是最新"], ["offline", "网络不通"]])}
      ${group("安装更新时游戏", "gameRunning", [["true", "仍在运行"], ["false", "已退出"]])}
      <div class="demo-group"><span>其他</span><div class="demo-opts">
        <button class="demo-opt" type="button" data-action="demo-f2">模拟游戏内按切队键</button>
        <button class="demo-opt" type="button" data-action="demo-f6" aria-pressed="${S.freeCam}">模拟游戏内按自由观战键</button>
        <button class="demo-opt" type="button" data-action="demo-defeat" ${S.neutral ? "" : "disabled"}>你打倒 1 个暂不配队的</button>
        <button class="demo-opt" type="button" data-action="onboarding">重看新手引导</button>
        <button class="demo-opt" type="button" data-action="demo-reset">清空原型数据</button>
      </div></div>`;
  }

  // ---------- Language & theme ----------
  function setLanguage(value) {
    if (value === "auto") { ui.langMode = "auto"; ui.lang = detected.lang; }
    else { ui.langMode = "manual"; ui.lang = value; }
    store.set("langMode", ui.langMode);
    store.set("lang", ui.lang);
    I18N.set(ui.lang);
    closePopover();
    renderAll();
  }
  function setTheme(theme) {
    ui.theme = theme;
    store.set("theme", theme);
    document.documentElement.dataset.theme = theme;
    renderTopbar();
    if (ui.page === "settings") renderPage();
  }

  // ---------- Events ----------
  const actions = {
    nav: el => { closePopover(); closeDialog(false); go(el.dataset.page); },
    "conn-popover": el => (pop?.anchor === el ? closePopover() : openPopover(el, connPopoverHTML(), { align: "center", role: "dialog" })),
    "lang-menu": el => (pop?.anchor === el ? closePopover() : openPopover(el, langMenuHTML(), { align: "end" })),
    "help-menu": el => (pop?.anchor === el ? closePopover() : openPopover(el, helpMenuHTML(), { align: "end" })),
    "toggle-theme": () => setTheme(ui.theme === "dark" ? "light" : "dark"),
    "set-theme": el => setTheme(el.dataset.value),
    "set-lang": el => setLanguage(el.dataset.value),
    "open-update": () => { closePopover(); openUpdate(); },
    "open-history": el => { if (el.dataset.toastId) dismissToast(el.dataset.toastId); openHistory(); },
    "clear-queue": () => clearQueue(),
    "time-stop": () => run("toggle_time_stop", { ok: j => t(/解除/.test(j.message || "") ? "toast.timeStop.off" : "toast.timeStop.on") }),
    "cam-reset": () => {
      Object.assign(S.camSettings, CAM_DEFAULTS);
      renderView();
      saveCamSettings({ ...CAM_DEFAULTS });
    },
    "dialog-close": () => closeDialog(),
    "dialog-dismiss": () => { if (ui.update.phase !== "installing") closeDialog(); },
    "toast-close": el => dismissToast(el.dataset.toastId),
    select: el => { selectUnit(el.dataset.id, { scroll: !!el.dataset.scroll }); },
    quick: el => { if (ui.selectedId !== el.dataset.id) selectUnit(el.dataset.id); if (!ui.busy.has("spawn")) summon(el.dataset.id, el.dataset.team, ui.count); },
    type: el => { ui.type = el.dataset.type; renderToolbar(); renderGrid({ animate: true }); },
    "clear-search": () => { ui.query = ""; const input = $("#search"); input.value = ""; input.focus(); renderToolbar(); renderGrid(); },
    "clear-filters": () => { Object.assign(ui, { query: "", type: "all", chapter: "all" }); $("#search").value = ""; renderToolbar(); renderGrid({ animate: true }); },
    team: el => { ui.team = el.dataset.team; renderSelection(); renderSolo(); renderCompanion(); scheduleSync(); followUnitKey(); },
    "count-dec": () => setCount(ui.count - 1),
    "count-inc": () => setCount(ui.count + 1),
    "count-preset": el => setCount(Number(el.dataset.n)),
    "level-apply": () => applyCustomLevel($("#level-custom")?.value),
    summon: () => summon(),
    start: () => run("start", { ok: () => t("toast.fight.start") }),
    stop: () => confirmStop(),
    "stop-confirm": () => stopAll(),
    "stop-again": el => { if (el.dataset.toastId) dismissToast(el.dataset.toastId); stopAll(); },
    rematch: () => rematch(),
    "recall-companions": () => run("recall_companions", { ok: j => {
      const m = /^已召回 (\d+)\/(\d+)/.exec(j.message || "");
      return m ? t("toast.companion.recalled", { n: Number(m[1]) }) : t("toast.companion.recallNone");
    } }),
    "dismiss-companions": async () => { const job = await run("dismiss_companions", { ok: j => t("toast.companion.dismissed", { n: j.cleared }) }); if (job?.status === "succeeded") { ui.roster.companion = {}; renderCompanion(); } },
    "clear-neutral": async () => { const job = await run("clear_neutral", { ok: j => t("toast.neutral.cleared", { n: j.cleared }) }); if (job?.status === "succeeded") { ui.roster.neutral = {}; renderSolo(); } },
    "solo-again": el => { if (el.dataset.toastId) dismissToast(el.dataset.toastId); soloAgain(); },
    spectator: () => run("toggle_spectator", { busyKey: "toggle_spectator", ok: () => t(S.spectator ? "toast.spectator.on" : "toast.spectator.restoring") }),
    "match-toggle": () => run("toggle_stat_match", { ok: () => (S.statMatch.enabled ? { title: t("toast.match.on"), body: t("toast.match.on.body") } : { title: t("toast.match.off"), body: t("toast.match.off.body") }) }),
    "match-rules": () => matchRulesDialog(),
    "fun-toggle": el => toggleFun(el.dataset.feature),
    "immortal-toggle": el => toggleImmortal(el.dataset.team),
    "stats-mode": el => setStatMode(el.dataset.mode),
    "stats-apply": () => applyStats(),
    "stats-all": async () => { if (!ui.statDraft) await loadStatValues(); statsDialog(); },
    "stats-save": () => { closeDialog(); applyStats(); },
    "stats-clear": () => { ui.statDraft = {}; for (const input of document.querySelectorAll(".dialog .stat-input")) input.value = ""; },
    "clock-hud": () => toggleClockHud(),
    "execution-camera": () => toggleExecutionCamera(),
    "match-focus": () => { const el = $("#dock-match"); el?.scrollIntoView({ block: "nearest", behavior: "smooth" }); el?.querySelector(".switch")?.focus({ preventScroll: true }); },
    "launch-game": () => { closePopover(); RT.launchGame(); toast({ kind: "info", title: t("toast.launching"), body: t("toast.launching.body") }); },
    "unitkey-capture": el => { if (ui.capture?.kind === "unit") cancelCapture(); else startCapture({ kind: "unit", id: el.dataset.id }); },
    "unitkey-remove": async el => {
      const u = byId.get(el.dataset.id);
      try { await RT.command("configure_unit_key", { unit_id: el.dataset.id, code: 0, mods: 0 }); toast({ kind: "success", title: t("toast.unitKey.removed", { name: u?.name }) }); }
      catch (error) { toast({ kind: "error", title: t("toast.notSent"), body: reasonText(error.code, error.detail) }); }
      if (ui.page === "hotkeys") renderPage(); else { renderSelection(); renderGrid(); }
    },
    "key-capture": el => { startCapture({ kind: "global", action: el.dataset.keyAction, host: el.dataset.keyHost || "" }); },
    "key-cancel": () => { ui.keyNote = null; cancelCapture(); },
    "key-swap": () => {
      const n = ui.keyNote, mine = S.keys[n.action], names = { a: t("keys.action." + n.action), b: t("keys.action." + n.other) };
      saveGlobalKeys({ ...S.keys, [n.action]: n.key, [n.other]: mine }, t(mine ? "toast.key.swapped" : "toast.key.moved", names), n.action, n.host);
    },
    "key-clear": el => { const a = el.dataset.keyAction; saveGlobalKeys({ ...S.keys, [a]: null }, t("toast.key.removed", { action: t("keys.action." + a) }), a); },
    "keys-clear-all": () => openDialog("confirm", `<div class="dialog-head"><h2 id="dlg-title">${esc(t("keys.clearAll.title"))}</h2></div>
      <div class="dialog-body"><p>${esc(t("keys.clearAll.body"))}</p></div>
      <div class="dialog-foot"><button class="btn btn-ghost" type="button" data-action="dialog-close">${esc(t("common.cancel"))}</button><button class="btn btn-danger-solid" type="button" data-action="keys-clear-confirm" data-autofocus>${icon("trash", "icon-sm")}${esc(t("keys.clearAll"))}</button></div>`, "dialog-sm"),
    "keys-clear-confirm": () => { closeDialog(); saveGlobalKeys({ ...NO_KEYS }, t("toast.key.cleared"), null); },
    "camera-enter": () => run("toggle_camera", { ok: () => ({ title: t("toast.camera.on"), body: t("toast.camera.on.body") }) }),
    "camera-exit": () => run("exit_camera", { ok: () => t("toast.camera.off") }),
    "toggle-setting": el => {
      const key = el.dataset.setting;
      ui.settings[key] = !ui.settings[key];
      store.set(key, ui.settings[key]);
      el.setAttribute("aria-checked", ui.settings[key]);
    },
    "detect-game": async () => {
      ui.detecting = true; renderPage();
      try {
        const game = await RT.setup.detectGame();
        const error = await useGamePath(game.path);
        if (error) throw Object.assign(new Error(error), { detail: error });
        toast({ kind: "success", title: t("toast.gameFound"), body: game.path });
      } catch (error) {
        toast({ kind: "warning", title: t("onb.game.notFound"), body: t("onb.game.notFound.body") });
      }
      ui.detecting = false;
      renderPage();
    },
    "change-path": () => pathDialog(),
    "path-browse": async () => {
      try { const path = await RT.setup.pickFolder(); if (path) $("#path-input").value = path; } catch { /* dialog closed */ }
    },
    "path-save": async () => {
      const value = $("#path-input").value.trim();
      const error = await useGamePath(value);
      if (error) { pathDialog(error, value); return; }
      closeDialog();
      if (ui.onboarding) renderOnboarding(); else renderPage();
      toast({ kind: "success", title: t("toast.pathSaved") });
    },
    "install-components": () => installComponents(),
    scan: () => confirmScan(),
    "scan-confirm": async () => { closeDialog(); await run("refresh_catalog", { busyKey: "scan" }); if (ui.page === "settings") renderPage(); },
    "open-folder": async () => {
      if (RT.demo) { toast({ kind: "info", title: t("toast.folder"), body: t("demo.only") }); return; }
      try { await RT.openFolder(); } catch (error) { toast({ kind: "error", title: t("toast.failed"), body: reasonText(error.code, error.detail) }); }
    },
    "export-report": async () => {
      if (RT.demo) { toast({ kind: "success", title: t("toast.report"), body: t("demo.only") }); return; }
      try { toast({ kind: "success", title: t("toast.report"), body: await RT.exportReport() }); }
      catch (error) { toast({ kind: "error", title: t("toast.failed"), body: reasonText(error.code, error.detail) }); }
    },
    "reset-settings": () => {
      Object.assign(ui.settings, { autoUpdate: true, allUnits: false, tech: false });
      ["autoUpdate", "allUnits", "tech"].forEach(k => store.set(k, ui.settings[k]));
      setTheme("light");
      setLanguage("auto");
      toast({ kind: "success", title: t("toast.settingsReset") });
    },
    "copy-uid": () => copyText("10010098"),
    "update-check": () => checkUpdate(),
    "update-rollback": el => rollbackTo(el.dataset.value),
    "update-line": el => { ui.update.line = el.dataset.value; setDialog(updateHTML()); $(`.line[data-value="${el.dataset.value}"]`)?.focus(); },
    "update-download": () => downloadUpdate(),
    "update-cancel": () => { ui.update.dl?.cancel(); },
    "update-game-closed": () => { if (RT.demo) { S.gameRunning = false; RT.setGame("offline"); } setDialog(updateHTML()); },
    "update-install": () => installUpdate(),
    "update-restart": () => { if (!RT.demo) { RT.update.restart(); return; } closeDialog(); ui.update = { phase: "idle", info: null, line: "auto", progress: null, error: null, lastChecked: Date.now() }; renderAll(); toast({ kind: "success", title: t("toast.updated", { v: S.appVersion }), body: t("demo.only") }); },
    onboarding: () => { closePopover(); closeDialog(false); ui.onboarding = true; ui.onb = { step: 0, detect: "idle", game: null, comps: null }; renderOnboarding(); },
    shortcuts: () => shortcutsDialog(),
    "onb-next": () => { ui.onb.step = Math.min(2, ui.onb.step + 1); renderOnboarding(); if (ui.onb.step === 1) onbDetect(); },
    "onb-back": () => { ui.onb.step = Math.max(0, ui.onb.step - 1); renderOnboarding(); },
    "onb-launch": () => { RT.launchGame(); finishOnboarding(); toast({ kind: "info", title: t("toast.launching"), body: t("toast.launching.body") }); },
    "onb-finish": () => finishOnboarding(),
    "demo-toggle": () => { ui.demoOpen = !ui.demoOpen; renderDemo(); },
    "demo-set": el => {
      const { key, value } = el.dataset;
      if (key === "game") RT.setGame(value);
      else RT.set({ [key]: value === "true" ? true : value === "false" ? false : /^\d+$/.test(value) ? Number(value) : value });
      if (key === "updateScenario") { ui.update.phase = "idle"; ui.update.info = null; renderTopbar(); }
      renderDemo();
    },
    "demo-f2": () => RT.cycleTeam(),
    "demo-defeat": () => RT.defeatSolo(),
    "demo-f6": () => RT.toggleFreeCam(),
    "demo-reset": () => { store.clear(); location.reload(); },
  };
  // Units per summon; backend.py MAX_SPAWN_COUNT (a guard against a mistyped number, not a game limit).
  const MAX_COUNT = 100;
  function setCount(n) {
    ui.count = Math.max(1, Math.min(MAX_COUNT, Math.round(n) || 1));
    renderSelection();
    scheduleSync();
    followUnitKey();
  }
  // The selected unit's own key follows the team and count chosen above, so each unit can sit on its
  // own side and the player switches it back and forth here.
  function followUnitKey() {
    const id = ui.selectedId, key = S.unitKeys[id];
    clearTimeout(ui.unitKeyTimer);
    if (!key || !RT.online() || (key.team === ui.team && key.count === ui.count)) return;
    ui.unitKeyTimer = setTimeout(async () => {
      if (ui.selectedId !== id) return;
      try {
        const job = await RT.command("configure_unit_key", { unit_id: id, code: key.code, mods: key.mods, team: ui.team, count: ui.count });
        ui.unitKeyError = job.status === "succeeded" ? "" : reasonText(job.code, job.message);
      } catch (error) {
        ui.unitKeyError = reasonText(error.code, error.detail);
      }
      renderSelection();
      if ($("#grid")) renderGrid();
    }, 400);
  }

  document.addEventListener("click", e => {
    const el = e.target.closest("[data-action]");
    if (pop && !pop.el.contains(e.target) && !pop.anchor.contains(e.target)) closePopover();
    if (ui.capture && !(el && ["unitkey-capture", "key-capture", "key-cancel"].includes(el.dataset.action))) {
      if (!e.target.closest(".capture-box")) cancelCapture();
    }
    if (!el) return;
    const fn = actions[el.dataset.action];
    if (!fn || el.disabled) return;
    if (el.tagName === "A") return;
    e.preventDefault();
    fn(el, e);
  });
  document.addEventListener("input", e => {
    if (e.target.classList?.contains("stat-input")) {
      statDraft()[e.target.dataset.field] = e.target.value;
      const group = e.target.closest(".stat-group");
      if (group) {
        const inputs = [...group.querySelectorAll(".stat-input")];
        group.querySelector(".stat-group-count").textContent = `${inputs.filter(i => i.value.trim()).length}/${inputs.length}`;
      }
      return;
    }
    if (e.target.classList?.contains("stat-filter")) {
      const q = e.target.value.trim().toLowerCase();
      let any = false;
      for (const group of document.querySelectorAll(".dialog .stat-group")) {
        let hits = 0;
        for (const row of group.querySelectorAll(".stat-row")) { const hit = !q || row.dataset.search.includes(q); row.hidden = !hit; hits += hit; }
        group.hidden = !hits;
        if (q && hits) group.open = true;
        any ||= hits > 0;
      }
      document.querySelector(".dialog .stat-filter-none").hidden = any;
      return;
    }
    if (e.target.classList?.contains("cam-range")) {
      const out = document.getElementById("cam-" + e.target.dataset.cam + "-value");
      if (out) out.textContent = camValue(e.target.dataset.cam, Number(e.target.value));
      return;
    }
    if (e.target.id === "search") {
      ui.query = e.target.value;
      clearTimeout(ui.searchTimer);
      ui.searchTimer = setTimeout(() => { renderToolbar(); renderGrid(); }, 90);
    }
  });
  document.addEventListener("change", e => {
    if (e.target.id === "chapter") { ui.chapter = e.target.value; renderToolbar(); renderGrid({ animate: true }); $("#catalog-col").scrollTop = 0; }
    if (e.target.id === "count-input") setCount(Number(e.target.value));
    if (e.target.id === "diff-select") setDifficulty(e.target.value);
    if (e.target.id === "level-mode") setLevelMode(e.target.value);
    if (e.target.id === "level-custom") ui.levelCustom = e.target.value;
    if (e.target.id === "home-level") setHomeLevel(e.target.dataset.id, e.target.value);
    if (e.target.id === "onb-lang") { setLanguage(e.target.value); }
    if (e.target.classList?.contains("cam-range")) saveCamSettings(camSliderValues());
  });
  // A details element does not bubble its toggle; keep the free camera settings open across re-renders.
  document.addEventListener("toggle", e => { if (e.target.classList?.contains("cam-settings")) ui.camSettingsOpen = e.target.open; }, true);
  const isTyping = el => el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.tagName === "SELECT" || el.isContentEditable);
  document.addEventListener("keydown", e => {
    if (ui.capture) {
      if (["Control", "Shift", "Alt", "Meta"].includes(e.key)) return;
      e.preventDefault();
      e.stopPropagation();
      if (e.key === "Escape") { ui.keyNote = null; cancelCapture(); return; }
      if (e.repeat) return;
      if (ui.capture.kind === "global") handleGlobalCapture(e); else handleUnitCapture(e);
      return;
    }
    if (e.key === "Escape") {
      if (pop) { closePopover(true); return; }
      if (dlg) { if (ui.update.phase !== "installing") closeDialog(); return; }
      if (ui.demoOpen) { ui.demoOpen = false; renderDemo(); return; }
      if (e.target.id === "search" && ui.query) { actions["clear-search"](); return; }
    }
    if (dlg && e.key === "Tab") {
      const focusables = $$("button:not(:disabled), a[href], input, select, [tabindex='0']", $("#dialog"));
      if (focusables.length) {
        const first = focusables[0], last = focusables[focusables.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    }
    if (pop && ["ArrowDown", "ArrowUp"].includes(e.key)) {
      const items = $$(".menu-item", pop.el), i = items.indexOf(document.activeElement);
      if (items.length) { e.preventDefault(); items[(i + (e.key === "ArrowDown" ? 1 : -1) + items.length) % items.length].focus(); }
      return;
    }
    if (e.target.id === "path-input" && e.key === "Enter") { actions["path-save"](); return; }
    if (ui.page !== "arena" || dlg || ui.onboarding) return;
    if (e.key === "/" && !isTyping(e.target)) { e.preventDefault(); $("#search")?.focus(); return; }
    if ((e.ctrlKey || e.metaKey) && e.key === "Enter") { e.preventDefault(); if (selected() && !summonBlocker() && !ui.busy.has("spawn")) summon(); return; }
    const card = e.target.closest?.(".card-main");
    if (card) {
      if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key)) { e.preventDefault(); moveGridFocus(card, e.key); return; }
      const team = { b: "blue", r: "red", n: "neutral" }[e.key.toLowerCase()];
      if (team && !e.ctrlKey && !e.altKey && !e.metaKey) {
        e.preventDefault();
        const id = card.dataset.id;
        if (ui.selectedId !== id) selectUnit(id);
        if (!ui.busy.has("spawn")) summon(id, team, ui.count);
      }
    }
    if (e.target.id === "search" && e.key === "ArrowDown") { e.preventDefault(); $(".card-main[tabindex='0']")?.focus(); }
  });

  // ---------- Runtime events ----------
  RT.subscribe(event => {
    switch (event.type) {
      case "game":
        // Closing the game removes every summoned unit, so the lineup goes with it.
        if (S.game === "offline") ui.roster = { blue: {}, red: {}, neutral: {}, companion: {} };
        renderTopbar();
        if (ui.page === "arena") renderDock(); else if (ui.page === "hotkeys" || ui.page === "settings") renderPage();
        if (S.game === "ready" && event.type === "game" && ui.prevGame && ui.prevGame !== "ready" && ui.prevGame !== "mismatch") toast({ kind: "success", title: t("toast.connected"), body: t("toast.connected.body") });
        if (RT.online()) scheduleSync();
        ui.prevGame = S.game;
        break;
      case "casualty":
        renderBattle();
        break;
      case "soloDown":
        renderSolo();
        if (!S.neutral) toast({ kind: "info", title: t("toast.solo.allDown"), body: t("toast.solo.allDown.body"), actions: ui.lastSolo ? [{ label: soloAgainLabel(), action: "solo-again" }] : [] });
        break;
      case "freeCam":
        if (ui.page === "arena") renderDock();
        break;
      case "fightEnd":
        renderBattle();
        toast({ kind: "success", title: t("field.winner." + event.winner), body: (event.winner === "draw" ? t("field.result.draw") : t("field.result.left", { n: S[event.winner] }))
          + (S.clock.state === "ended" ? ` · ${t("field.time", { time: fmtClock(S.clock.seconds) })}` : "") });
        break;
      case "spectator":
        if (ui.page === "arena") renderDock();
        toast({ kind: "info", title: t("toast.spectator.off") });
        break;
      case "teamKey":
        ui.team = event.team;
        renderSelection();
        renderSolo();
        renderCompanion();
        toast({ kind: "info", title: t("toast.teamKey", { team: teamName(event.team) }), body: t("toast.teamKey.body") });
        break;
      case "job":
        renderTopbar();
        if (dlg?.kind === "history") setDialog(historyHTML());
        if (event.job.action === "toggle_spectator" && ui.page === "arena") renderDock();
        if (event.job.action === "select_unit") renderSelection();
        break;
      case "scan":
        if (ui.page === "settings") renderPage();
        break;
      case "scanDone":
        if (ui.page === "settings") renderPage();
        toast({ kind: "success", title: t("toast.scanDone"), body: t("toast.scanDone.body", { n: fmtNum(UNITS.length) }) });
        break;
      case "demo":
        renderTopbar();
        if (ui.page === "arena") renderDock();
        if (dlg?.kind === "update") setDialog(updateHTML());
        break;
      case "host":
        // Version, game folder and components arrived from the native window.
        renderTopbar();
        if (ui.page === "arena") renderBanner();
        if (ui.onboarding) renderOnboarding();
        else if (ui.page === "settings" || ui.page === "about") renderPage();
        break;
      case "state": {
        // RealRuntime names the parts whose data changed, so polling never re-renders what the player is using.
        const p = event.parts;
        if (p.has("names")) applyNames(S.unitNames);
        if (p.has("topbar")) renderTopbar();
        if (p.has("queue")) {
          if (ui.page === "arena" && !p.has("sel")) renderBanner();
          if (dlg?.kind === "history") setDialog(historyHTML());
        }
        if (ui.page === "arena") {
          if (p.has("sel")) { renderBanner(); renderSelection(); }
          if (p.has("solo")) renderSolo();
          if (p.has("companion")) renderCompanion();
          if (p.has("diff")) renderDifficulty();
          if (p.has("match")) renderMatch();
          if (p.has("battle")) renderBattle();
          else if (p.has("clock")) renderClock();
          if (p.has("view")) renderView();
          if (p.has("grid") && !ui.capture) renderGrid();
        } else if (ui.page === "hotkeys" && p.has("keys") && !ui.capture && !ui.keysSaving) renderPage();
        else if (ui.page === "settings" && p.has("settings")) renderPage();
        else if (ui.page === "fun" && p.has("fun")) renderPage();
        if (dlg?.kind === "update" && p.has("update")) setDialog(updateHTML());
        break;
      }
    }
    if (ui.demoOpen) renderDemo();
  });

  // A codex bust that fails to load leaves the name's first character in its place.
  document.addEventListener("error", e => {
    const img = e.target;
    if (!img?.classList?.contains("avatar-art")) return;
    img.closest(".avatar")?.classList.remove("has-art");
    img.remove();
  }, true);

  // ---------- Boot ----------
  if (!RT.demo) $("#demo-fab")?.remove();
  ui.prevGame = S.game;
  renderAll();
  scheduleAutoUpdate();
})();
