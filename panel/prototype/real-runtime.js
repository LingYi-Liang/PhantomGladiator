"use strict";
// Runtime for the packaged app. Same interface as MockRuntime, but backed by panel/backend.py
// (served from the same origin; /api/status polled every 500 ms like the old panel) and by the
// native window (desktop/PhantomGladiator.cs) over chrome.webview messages for install, game launch
// and updates. The UI keeps the short unit ids of units.js; this file maps them to class paths.
const RealRuntime = (() => {
  const listeners = new Set();
  const emit = event => { for (const fn of listeners) fn(event || {}); };
  const fail = (code, detail = "") => Object.assign(new Error(detail || code), { code, detail });
  const runtimeFallback = {
    "reason.readTimeout": "Reading from the local assistant timed out. Try again shortly.",
    "reason.submissionUnknown": "It is not yet clear whether the assistant received this command. Check the operation history and the game before submitting it again. The assistant will not resend it automatically.",
    "runtime14.httpRejected": "The assistant rejected this command (HTTP {status}).",
    "runtime14.commandLimit": "There are already {n} commands awaiting confirmation. Wait for their results.",
    "runtime14.poolsReadFailed": "Could not read the monster pools.",
    "runtime14.poolsSaveFailed": "Could not save the monster pools.",
    "runtime14.unitMissing": "The current catalog does not contain {unit}. Check the catalog or remove this entry from the pool.",
    "runtime14.catalogReadFailed": "Could not read the unit catalog."
  };
  const runtimeText = (key, params) => {
    const translated = window.PG_I18N?.t(key, params);
    const value = typeof translated === "string" && translated !== key ? translated : runtimeFallback[key] || key;
    return params ? value.replace(/\{(\w+)\}/g, (slot, name) => params[name] ?? slot) : value;
  };
  const webview = window.chrome && window.chrome.webview;
  const KEY_NAMES = ["spawn", "start", "stop", "refresh_catalog", "toggle_camera", "exit_camera", "cycle_team", "toggle_spectator", "recall_companions", "toggle_time_stop", "toggle_track", "track_pick", "track_next", "dismiss_companions", "hun_blue", "hun_red", "hun_companion", "hun_neutral"];
  const TEAMS = ["blue", "red", "neutral", "companion"];
  const EYE_KEYS = ["eyes_player","eyes_npc"];
  const SELFIE_KEYS = ["toggle_selfie", "selfie_pose", "selfie_next", "selfie_shot"];
  const STUDIO_KEYS = ["toggle_photo", "photo_panel"];
  const DIRECTOR_KEYS = ["toggle_cinema", "cycle_battle_hud"];
  const CINEMA_SHOTS = ["shoulder", "low", "side", "aerial", "action"];
  const BATTLE_HUD_MODES = ["full", "compact", "hidden"];
  const SELFIE_DEFAULT = {supported: false, studio: false, mode: "", on: false, ready: false, target: "", posed: 0, style: 0, next: false, message: ""};
  const WEATHER_KEYS = window.PG_I18N?.weatherKeys || [];
  const HUN_KEYS = ["hun_blue", "hun_red", "hun_companion", "hun_neutral"];
  const QUEUE_STUCK_MS = 12000;
  const READ_TIMEOUT_MS = 5000;
  // Reads may be retried; mutation POSTs must not be replayed after an ambiguous network failure.
  async function readJSON(path, controller = new AbortController()) {
    let timer;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => {
        reject(fail("readTimeout", runtimeText("reason.readTimeout")));
        controller.abort();
      }, READ_TIMEOUT_MS);
    });
    try {
      return await Promise.race([(async () => {
        const response = await fetch(path, { cache: "no-store", signal: controller.signal });
        if (controller.signal.aborted) throw fail("readCancelled");
        const data = await response.json();
        if (controller.signal.aborted) throw fail("readCancelled");
        return { response, data };
      })(), timeout]);
    } finally { clearTimeout(timer); }
  }
  const SUBMIT_TIMEOUT_MS = 15000;
  const submissionMessage = () => runtimeText("reason.submissionUnknown");
  async function submitCommand(path, body) {
    const controller = new AbortController();
    let timer, response;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => {
        reject(response && !response.ok ? fail("rejected", runtimeText("runtime14.httpRejected", { status: response.status }))
          : fail("submissionUnknown", submissionMessage()));
        controller.abort();
      }, SUBMIT_TIMEOUT_MS);
    });
    try {
      return await Promise.race([(async () => {
        response = await fetch(path, { method: "POST", signal: controller.signal,
          headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf }, body: JSON.stringify(body) });
        if (!response.ok) {
          const detail = await response.json().catch(() => ({}));
          throw fail("rejected", detail?.error || runtimeText("runtime14.httpRejected", { status: response.status }));
        }
        return response.json();
      })(), timeout]);
    } finally { clearTimeout(timer); }
  }

  const s = {
    icons: {},                  // unit id -> codex bust URL (codex_icons.lua, backend.py /api/codex-icons)
    summonLimits: {},
    unitNames: null,            // names in the game's language (codex_catalog_export.lua, backend.py /api/unit-names)
    game: "offline",            // offline | connecting | notInMap | ready | mismatch
    gameRunning: false,
    appVersion: "",
    channel: "github",          // "nexus": the Nexus Mods build, which has no update check or download
    modVersion: "",             // build the running mod reports
    expectedBuild: "",          // build this app installs
    gamePath: "",
    blue: 0, red: 0, neutral: 0, companion: 0,
    down: { blue: 0, red: 0, neutral: 0, companion: 0 },
    summonQueue: { supported: false, ready: false, on: false, waiting: 0, transit: 0, completed: 0, running: false, message: "" },
    monsterPools: null,
    poolStatus: { scope: "", revision: 0, supported: false, keys: {}, error: "" },
    companionFailures: 0,       // companions whose follow state or side did not read back (companion.lua)
    unreadable: 0,
    freeCam: false,
    team: "blue",
    spectator: false,
    spectatorPhase: "",
    // mode: game | match | custom (stat_match_mode); custom values: the core four here, all of them from /api/stat-settings.
    statMatch: { enabled: false, mode: "game", modeSupported: false, baseline: null, matched: 0, failures: 0, reset: false, customCount: 0, customized: 0, rejected: [], rejectedCount: 0, values: {} },
    // companion_stats_*: the companions' own set; game | custom (stat_match.lua). All the values come from /api/companion-stats.
    companionManagerRevision: null,
    companionSquad: null,
    arenaRosterRevision: null,
    arenaRosterSession: null,
    companionStats: { supported: false, mode: "game", customCount: 0, customized: 0, failures: 0, rejected: [], rejectedCount: 0, values: {} },
    // spawn_difficulty_*: the level new units take (FOLLOW = the game's), the game's own level, counts.
    // spawn_level: the level a summon gets (the highest map enemy near the player at the last look), and that enemy.
    difficulty: { level: "FOLLOW", game: "", supported: false, failures: 0, skipped: 0, aiFailed: 0, summonLevel: null, summonLevelUnit: "" },
    // spawn_level_mode / spawn_level_custom (home_levels.lua): where a summon's level comes from, HOME | HERE | CUSTOM;
    // homes: each unit's places in the game with the default and the player's pick (backend.py /api/home-levels).
    level: { supported: false, mode: "HOME", custom: null, cycle: null, homes: {} },
    // boss_combos*: the 连携技 switch (boss_combos.lua).
    combo: { supported: false, on: false },
    // fun_*: the player-only switches saved by fun_features.lua and what each one reads back.
    fun: { supported: false, shachi: false, deflect: false, dodge: false, shachiState: "off", guardState: "off", deflects: 0, dodges: 0 },
    // immortal_*: the 不倒下 switch of each team (immortal_teams.lua), units locked, locks that did not take.
    immortal: { supported: false, blue: false, red: false, companion: false, locked: 0, failures: 0 },
    // battle_clock / battle_seconds: game seconds of the current or last fight (arena_controller.lua).
    clock: { state: "", seconds: 0 },
    // clock_hud_*: the on-screen clock switch and whether the game shows it (battle_clock_hud.lua).
    clockHud: { supported: false, on: false, state: "off" },
    executionAppearance: { supported: false, on: false },
    // execution_camera_*: the execution camera switch, and whether it is playing now (execution_camera.lua).
    executionCamera: { supported: false, on: false, state: "off" },
    // companion_executions*: whether companions may execute bosses (companion_executions.lua).
    companionExec: { supported: false, on: false },
    offCombatRegen: { supported: false, on: false, state: "off", failures: 0 },
    battleMusic: { supported: false, mode: "NATIVE", track: "MOYUAN_P1", state: "native", message: "", playing: 0 },
    // track_*: 镜头跟踪 (camera_track.lua). targets: { key, cls, team } of the units it can follow, while the free camera runs.
    track: { supported: false, on: false, framing: "side", resume: 3, target: "", targetClass: "", otherClass: "", targets: [] },
    // unit_rules: what each unit's card says, BP_X:lock=kill;BP_Y:phantom=keep (unit_rules.lua).
    unitRules: {},
    unitRulesSupported: false,
    remoteReflectSupported: false,
    longzhuProtectionSupported: false,
    xianzhePhantomSupported: false,
    menghuaStageSupported: false,
    // free_camera_*: 时停 and the free camera's speed (cm/s), turn and smoothing (%) as free_camera.lua saved them.
    frozen: false,
    camSettings: { supported: false, speed: 900, turn: 100, smooth: 40 },
    fight: "idle",
    winner: "",
    // arena_state after a cleanup the mod could not confirm: cleanup_pending / restore_pending need
    // another cleanup, spawn_uncertain needs a game restart. Spawning is blocked meanwhile.
    cleanup: "",
    selfie: { ...SELFIE_DEFAULT },
    cinemaKeysSupported: false,
    cinema: { supported: false, active: false, shot: "" },
    battleHud: { supported: false, mode: "full" },
    attackFlash: { supported: false, red: false, blue: false },
    keys: Object.fromEntries([...KEY_NAMES, ...WEATHER_KEYS, ...EYE_KEYS, ...SELFIE_KEYS, ...STUDIO_KEYS, ...DIRECTOR_KEYS].map(k => [k, null])),
    unitKeys: {},
    scan: null,
    synced: null,
    // Commands the game has not answered (backend.py queue): how many, since when, and what the backend says holds them
    // (transport_code). stuck: waited long enough to show the banner with the way to clear them.
    queue: null,
    installed: false,
    components: null,
  };
  const jobs = [], jobById = new Map(), waiters = new Map();
  const MAX_COMMANDS = 100;
  let activeCommands = 0;
  function jobId(value) {
    if (typeof value === "number") return Number.isSafeInteger(value) && value > 0 ? String(value) : null;
    return typeof value === "string" && /^[1-9][0-9]{0,18}$/.test(value) &&
      (value.length < 19 || value <= "9223372036854775807") ? value : null;
  }
  function newestJob(a, b) { return b.id.length - a.id.length || (a.id < b.id ? 1 : a.id > b.id ? -1 : 0); }
  function pruneJobs() {
    jobs.sort(newestJob);
    for (const j of jobs.splice(MAX_COMMANDS)) if (!waiters.has(j.id)) jobById.delete(j.id);
    const visible = new Set(jobs.map(j => j.id));
    for (const id of jobById.keys()) if (!visible.has(id) && !waiters.has(id)) jobById.delete(id);
  }
  let csrf = "", owned = 0, launching = 0, failedPolls = 0;
  let teamRev = null, session = "", catalogKey = "", lastSig = {}, iconsAt = 0, homesAt = 0;
  let toGame = new Map(), toShort = new Map(), poolRead = null;
  let catalogRequest = 0, catalogController = null;

  // ---------- Native host ----------
  let rpcSeq = 0;
  const rpcWaiting = new Map(), progress = new Map();
  if (webview) {
    webview.addEventListener("message", e => {
      const m = e.data || {};
      if (m.reply) {
        const w = rpcWaiting.get(m.reply);
        if (!w) return;
        rpcWaiting.delete(m.reply);
        if (m.ok) w.resolve(m.result);
        else w.reject(Object.assign(fail(m.error?.code || "host", m.error?.message || ""), { tried: m.error?.tried || [] }));
      } else if (m.event === "progress") progress.get(m.task)?.(m);
      else if (m.event === "gameRunning" && s.gameRunning !== !!m.running) { s.gameRunning = !!m.running; emit({ type: "state", parts: new Set(["update"]) }); }
    });
  }
  function host(method, params = {}) {
    if (!webview) return Promise.reject(fail("noHost"));
    const id = ++rpcSeq;
    return new Promise((resolve, reject) => {
      rpcWaiting.set(id, { resolve, reject });
      webview.postMessage({ id, method, params });
    });
  }

  // ---------- Unit ids ----------
  const shortOf = path => toShort.get(path) || String(path || "").split("/").pop().split(".")[0];
  function gameId(short) {
    const id = toGame.get(short);
    if (!id) throw fail("unknownUnit");
    return id;
  }
  const poolUnitId = member => member.startsWith("/") ? shortOf(member) : member;
  async function loadMonsterPools() {
    const scope = s.poolStatus.scope;
    const revision = s.poolStatus.revision;
    if (!scope || s.poolStatus.error || (poolRead?.scope === scope && (!poolRead.retryAt ||
        (poolRead.revision === revision && poolRead.retryAt > Date.now())))) return;
    const request = { scope, revision };
    poolRead = request;
    try {
      const { response: r, data: reply } = await readJSON("/api/monster-pools");
      if (s.poolStatus.scope !== scope) return;
      if (!r.ok) throw fail("rejected", reply.error || runtimeText("runtime14.poolsReadFailed"));
      if (!s.monsterPools || reply.revision >= s.monsterPools.revision) {
        s.monsterPools = reply;
        emit({ type: "state", parts: new Set(["poolConfig"]) });
      }
    } catch (error) {
      if (s.poolStatus.scope === scope) {
        request.error = error.detail || runtimeText("runtime14.poolsReadFailed");
        request.retryAt = Date.now() + 5000;
        s.poolStatus.error = request.error;
        emit({ type: "state", parts: new Set(["poolStatus"]) });
      }
    } finally {
      if (poolRead === request && !request.retryAt) poolRead = null;
    }
  }

  async function saveMonsterPools(pools, revision) {
    const scope = s.poolStatus.scope;
    const body = { revision, pools: pools.map(pool => ({ ...pool,
      unit_ids: pool.unit_ids.map(member => {
        const path = member.startsWith("/") ? member : toGame.get(member);
        if (!path) throw fail("rejected", runtimeText("runtime14.unitMissing", { unit: member }));
        return path;
      }),
    })) };
    const r = await fetch("/api/monster-pools", { method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf }, body: JSON.stringify(body) });
    const reply = await r.json().catch(() => ({}));
    if (!r.ok) throw fail("rejected", reply.error || runtimeText("runtime14.poolsSaveFailed"));
    if (s.poolStatus.scope === scope && (!s.monsterPools || reply.revision >= s.monsterPools.revision)) {
      s.monsterPools = reply;
      emit({ type: "state", parts: new Set(["poolConfig"]) });
    }
    return reply;
  }

  async function loadCatalog() {
    const request = ++catalogRequest, key = catalogKey;
    catalogController?.abort();
    const controller = new AbortController();
    catalogController = controller;
    let r, data;
    try {
      ({ response: r, data } = await readJSON("/api/catalog", controller));
      if (request !== catalogRequest || key !== catalogKey) return;
      if (!r.ok) throw fail("rejected", runtimeText("runtime14.catalogReadFailed"));
    } catch (error) {
      if (request === catalogRequest && key === catalogKey) throw error;
      return;
    } finally {
      if (catalogController === controller) catalogController = null;
    }
    const game = new Map(), short = new Map(), unitKeys = {}, summonLimits = {};
    // Primary codex rows first, so a short name always means the entry units.js shows.
    const rows = [...(data.units || [])].sort((a, b) => (b.codex_entry_kind === "primary") - (a.codex_entry_kind === "primary"));
    for (const u of rows) {
      const name = u.internal_name || String(u.id).split("/").pop().split(".")[0];
      if (!game.has(name)) {
        game.set(name, u.id);
        if (u.spawnable !== false) summonLimits[name] = Number(u.max_count) || 100;
      }
      short.set(u.id, name);
      const k = u.unit_shortcut;
      if (k && k.key_code) unitKeys[name] = { code: k.key_code, mods: k.modifiers || 0, team: k.team || null, count: k.count || null };
    }
    toGame = game;
    toShort = short;
    s.unitKeys = unitKeys;
    s.summonLimits = summonLimits;
    s.synced = s.synced && { ...s.synced };
    emit({ type: "state", parts: new Set(["sel", "keys", "grid"]) });
  }

  // The codex busts the mod has saved on this PC. They appear while the game exports them, so the list is
  // asked for again every 15 s until there are some, then every minute.
  async function loadIcons() {
    iconsAt = Date.now();
    const { response: r, data } = await readJSON("/api/codex-icons");
    if (!r.ok) return;
    const icons = data.icons || {};
    if (JSON.stringify(icons) === JSON.stringify(s.icons)) return;
    s.icons = icons;
    emit({ type: "state", parts: new Set(["sel", "grid", "match", "keys"]) });
  }

  // Unit, chapter and map names in the player's game language, exported by the mod on every load; asked for with
  // the icons. Until the game has run with v0.37.5+ the list is empty and the app keeps its Chinese names.
  async function loadNames() {
    const { response: r, data } = await readJSON("/api/unit-names");
    if (!r.ok) return;
    const names = data.count ? { lang: data.lang || "", units: data.units || {} } : null;
    if (JSON.stringify(names) === JSON.stringify(s.unitNames)) return;
    s.unitNames = names;
    emit({ type: "state", parts: new Set(["names", "sel", "grid", "match", "keys", "solo", "companion"]) });
  }

  // Each unit's level choices: the mod rewrites them when a map loads and after every change, so they are asked for
  // every 30 s while the game runs and again right after the player changes a level.
  async function loadHomeLevels() {
    homesAt = Date.now();
    const { response: r, data } = await readJSON("/api/home-levels");
    if (!r.ok) return;
    const homes = data.units || {};
    if (JSON.stringify(homes) === JSON.stringify(s.level.homes)) return;
    s.level.homes = homes;
    emit({ type: "state", parts: new Set(["sel"]) });
  }

  // ---------- Status ----------
  function mapJob(q) {
    const id = jobId(q.id);
    if (!id) return null;
    let j = jobById.get(id);
    const p = q.payload || {};
    if (!j) {
      j = { id, action: q.action, created: (q.created || Date.now() / 1000) * 1000 };
      jobById.set(id, j);
      jobs.push(j);
    }
    j.payload = { ...p, unit_id: p.unit_id ? shortOf(p.unit_id) : undefined };
    const status = q.status === "queued" || q.status === "pending" ? "pending" : q.status;
    const changed = j.status !== status;
    j.status = status;
    j.message = q.message || "";
    if (q.spawned_count != null) j.spawned = q.spawned_count;
    if (status !== "pending") j.finished = (q.completed || Date.now() / 1000) * 1000;
    // stat_match.lua reports through the ack text: a rolled-back match still spawns, an unconfirmed
    // rollback stops the batch and leaves that unit for cleanup.
    if (status === "succeeded" && /数值统一失败已回滚/.test(j.message)) j.warning = "matchFailed";
    if (status === "failed" && (j.action === "spawn" || j.action === "queue_spawn") &&
        /保留[^；。\n]*清理/.test(j.message)) {
      if (/数值统一/.test(j.message)) j.code = "matchAbort";
      else if (/自定义数值失败|随行数值未确认|召唤物数值未确认/.test(j.message)) j.code = "statApplyAbort";
    }
    // stop(): every unit removed ("待确认=0") but a restore record left for the next pass.
    if (status === "failed" && j.action === "stop" && /待确认=0/.test(j.message) && /恢复确认=false/.test(j.message) && !/生成结果未知/.test(j.message)) j.code = "restorePending";
    // backend.py's own reasons, shown in the player's language.
    if (status === "failed" && /^已手动清理/.test(j.message)) j.code = "cleared";
    if (status === "failed" && /一直没进入可操作的地图/.test(j.message)) j.code = "notReadyTimeout";
    if (status === "failed" && /^旧游戏会话的排队指令已取消/.test(j.message)) j.code = "staleSession";
    // companion.lua recall(): "已召回 n/m 个随从到身边；没到位：…" when one did not land beside the player.
    if (status === "failed" && j.action === "recall_companions" && /^已召回/.test(j.message)) j.code = "recallPartial";
    return changed ? j : null;
  }

  function apply(data) {
    csrf = data.csrf_token || csrf;
    s.localAudio = data.local_audio || { supported: false };
    const g = data.game || {}, v = g.values || {};
    const num = k => Number(v[k]) || 0, yes = k => v[k] === "true";
    const online = !!(g.online && g.game_session);
    if (online) launching = 0;
    const was = { game: s.game, blue: s.blue, red: s.red, neutral: s.neutral, soloHeld: s.neutral + s.down.neutral, fight: s.fight, freeCam: s.freeCam, phase: s.spectatorPhase, scanning: !!s.scan, base: s.statMatch.baseline };

    let game = online ? (g.ready ? "ready" : "notInMap") : launching && Date.now() - launching < 180000 ? "connecting" : "offline";
    s.modVersion = v.build || "";
    s.executionAppearance = {
      supported: online && v.execution_appearance_legacy != null,
      on: online && yes("execution_appearance_legacy"),
    };
    if (online && s.expectedBuild && s.modVersion && s.modVersion !== s.expectedBuild) game = "mismatch";
    s.game = game;
    s.arenaRosterRevision = online && v.arena_roster_revision != null ? num("arena_roster_revision") : null;
    s.arenaRosterSession = online ? g.game_session : null;
    s.hunBodySupported = online && yes('hun_body_probe_supported');
    s.summonQueue = {
      supported: online && typeof v.summon_queue_enabled === "string",
      ready: online && g.ready === true,
      on: online && yes("summon_queue_enabled"),
      waiting: online ? num("summon_queue_waiting") : 0,
      transit: Number(data.summon_queue_transit) || 0,
      completed: online ? num("summon_queue_completed") : 0,
      running: online && yes("summon_queue_running"),
      message: online ? (v.summon_queue_message || "") : "",
      settingsSupported: online && v.summon_queue_settings_schema === "1",
      mode: v.summon_queue_mode || "TIMED", intervalMs: num("summon_queue_interval_ms") || 250,
      blueSlots: num("summon_queue_blue_slots") || 3, redSlots: num("summon_queue_red_slots") || 3,
      relayStarted: online && yes("summon_queue_relay_started"), generated: num("summon_queue_generated"),
      blueReserve: num("summon_queue_blue_reserve"), redReserve: num("summon_queue_red_reserve"),
    };

    if (data.monster_pools && data.runtime_dir) {
      if (s.poolStatus.scope !== data.runtime_dir) s.monsterPools = null;
      s.poolStatus = { ...data.monster_pools, scope: data.runtime_dir };
      if (!s.monsterPools || s.monsterPools.revision < s.poolStatus.revision) loadMonsterPools();
      if (poolRead?.scope === data.runtime_dir && poolRead.revision === s.poolStatus.revision &&
          poolRead.retryAt > Date.now() && !s.poolStatus.error) s.poolStatus.error = poolRead.error;
    } else {
      s.poolStatus = { ...s.poolStatus, supported: false, keys: {} };
    }

    if (online) {
      s.blue = num("blue_count");
      s.red = num("red_count");
      s.neutral = num("neutral_count");
      s.companion = num("companion_count");
      s.companionFailures = num("companion_failures");
      const soloDown = Math.max(0, num("neutral_owned_records") - s.neutral);
      const companionDown = Math.max(0, num("companion_owned_records") - s.companion);
      s.down = { blue: Math.max(0, num("arena_dead_count") - soloDown - companionDown), red: 0, neutral: soloDown, companion: companionDown };
      s.unreadable = num("arena_unreadable_count");
      // Companions stay through "stop and clear"; everything counted as the arena's leaves them out.
      owned = Math.max(0, num("arena_owned_records") - num("companion_owned_records"));
      s.freeCam = yes("arena_free_camera");
      s.spectator = yes("spectator_enabled");
      if (TEAMS.includes(v.current_team)) s.team = v.current_team;
      s.synced = v.current_unit ? { unit_id: shortOf(v.current_unit), team: v.current_team, count: num("current_count") } : null;
      const battle = yes("arena_battle_active") || v.arena_state === "battle_requested";
      s.fight = s.summonQueue.relayStarted ? "fighting" : !battle ? "idle" : s.blue > 0 && s.red > 0 ? "fighting" : "ended";
      const reportedWinner = ["blue", "red", "draw"].includes(v.arena_winner) ? v.arena_winner : "";
      s.winner = s.fight === "ended" ? (reportedWinner || (s.blue ? "blue" : s.red ? "red" : "draw")) : "";
      s.cleanup = ["cleanup_pending", "restore_pending", "spawn_uncertain"].includes(v.arena_state) ? v.arena_state : "";
      const m = s.statMatch, base = v.stat_match_baseline_unit;
      m.enabled = yes("stat_match_enabled");
      m.modeSupported = !!v.stat_match_mode;
      m.mode = ["game", "match", "custom"].includes(v.stat_match_mode) ? v.stat_match_mode : m.enabled ? "match" : "game";
      m.customCount = num("stat_custom_count");
      m.customized = num("stat_match_customized");
      // The fields the game did not take on the last custom unit (stat_match.lua), first twelve by name.
      m.rejectedCount = num("stat_custom_rejected");
      m.rejected = String(v.stat_custom_rejected_fields || "").split(",").filter(Boolean);
      m.baseline = base ? { id: shortOf(base), hp: num("stat_match_health"), shachi: num("stat_match_shachi"), atk: num("stat_match_attack"), satk: num("stat_match_shachi_attack") } : null;
      m.matched = num("stat_match_count");
      m.failures = num("stat_match_failures");
      // stat_match.lua drops the baseline once the app holds no units; say so until something is summoned.
      if (base || !m.enabled) m.reset = false;
      else if (was.base && owned === 0) m.reset = true;
      const d = s.difficulty;
      d.supported = yes("spawn_difficulty_supported");
      if (DIFFICULTIES.includes(v.spawn_difficulty)) d.level = v.spawn_difficulty;
      d.game = v.spawn_difficulty_game || "";
      d.failures = num("spawn_difficulty_failures");
      d.skipped = num("spawn_difficulty_skipped");
      // ai_difficulty.lua reads its override back on every unit; a failure means stats changed but the AI did not.
      d.aiFailed = num("spawn_difficulty_ai_failed");
      d.summonLevel = v.spawn_level ? num("spawn_level") : null;
      d.summonLevelUnit = v.spawn_level_unit || "";
      const L = s.level;
      L.supported = ["HOME", "HERE", "CUSTOM"].includes(v.spawn_level_mode);
      if (L.supported) L.mode = v.spawn_level_mode;
      L.custom = v.spawn_level_custom ? num("spawn_level_custom") : null;
      L.cycle = /^[0-7]$/.test(v.spawn_cycle) ? Number(v.spawn_cycle) : null;
      const f = s.fun;
      s.combo.supported = yes("boss_combos_supported");
      s.combo.on = yes("boss_combos");
      s.offCombatRegen = { supported: yes("offcombat_regen_supported"), on: yes("offcombat_regen_disabled"),
        state: v.offcombat_regen_state || "off", failures: num("offcombat_regen_failures") };
      s.battleMusic = { supported: yes("battle_music_supported"), mode: v.battle_music_mode || "NATIVE", track: v.battle_music_track || "MOYUAN_P1",
        state: v.battle_music_state || "native", message: v.battle_music_message || "", playing: num("battle_music_playing_id"), pending: yes("battle_music_pending") };
      s.localMusicSupported=yes("battle_local_supported");
      f.supported = yes("fun_supported");
      f.shachi = yes("fun_shachi");
      f.deflect = yes("fun_deflect");
      f.dodge = yes("fun_dodge");
      f.shachiState = v.fun_shachi_state || "off";
      f.guardState = v.fun_guard_state || "off";
      f.deflects = num("fun_deflect_pressed");
      f.dodges = num("fun_dodge_pressed");
      const im = s.immortal;
      im.supported = yes("immortal_supported");
      for (const team of ["blue", "red", "companion"]) im[team] = yes("immortal_" + team);
      im.locked = num("immortal_locked");
      im.failures = num("immortal_failures");
      s.clock = { state: v.battle_clock || "", seconds: num("battle_seconds") };
      s.clockHud = { supported: yes("clock_hud_supported"), on: yes("clock_hud"), state: v.clock_hud_state || "off" };
      s.executionCamera = { supported: yes("execution_camera_supported"), on: yes("execution_camera"), state: v.execution_camera_state || "off" };
      s.companionExec = { supported: yes("companion_executions_supported"), on: yes("companion_executions") };
      // companion_minion_executions*: whether companions also execute minions (companion_executions.lua).
      s.companionMinionExec = { supported: yes("companion_minion_executions_supported"), on: yes("companion_minion_executions") };
      // companion_passage*: whether the player walks through companions (companion_passage.lua).
      s.companionManagerRevision = v.companion_manager_revision == null ? null : num("companion_manager_revision");
      s.companionSquad = v.companion_squad_state ? { state: v.companion_squad_state, total: num("companion_squad_total"), revision: v.companion_squad_revision } : null;
      s.companionPass = { supported: yes("companion_passage_supported"), on: yes("companion_passage") };
      Object.assign(s.companionStats, { supported: yes("companion_stats_supported"), mode: v.companion_stats_mode === "custom" ? "custom" : "game", customCount: num("companion_stats_count"),
        customized: num("companion_stats_customized"), failures: num("companion_stats_failures"), rejectedCount: num("companion_stats_rejected"),
        rejected: String(v.companion_stats_rejected_fields || "").split(",").filter(Boolean) });
      s.track = { supported: yes("track_supported"), eyesSupported:yes("first_person_supported"), on: yes("track_on"), framing: v.track_framing || "side", resume: num("track_resume"),
        target: v.track_target || "", targetClass: v.track_target_class || "", otherClass: v.track_other_class || "",
        targets: (v.track_targets || "").split(";").filter(Boolean).map(item => { const [key, cls, team] = item.split(":"); return { key, cls, team }; }) };
      s.entourageSupported = yes("entourage_rule_supported");
      s.unitRulesSupported = yes("unit_rules_supported");
      s.executionMinionsSupported = yes("execution_minions_rule_supported");
      s.remoteReflectSupported = yes("remote_reflect_supported");
      s.longzhuProtectionSupported = yes("longzhu_protection_supported");
      s.xianzhePhantomSupported = yes("xianzhe_phantom_supported");
      s.menghuaStageSupported = yes("menghua_stage_rule_supported");
      s.unitRules = {};
      for (const item of (v.unit_rules || "").split(";")) {
        const m = item.match(/^([A-Za-z0-9_]+):(\w+)=(\w+)$/);
        if (m) (s.unitRules[m[1]] ||= {})[m[2]] = m[3];
      }
      s.frozen = yes("free_camera_frozen");
      if (yes("free_camera_settings_supported")) s.camSettings = { supported: true, speed: num("free_camera_speed"), turn: num("free_camera_turn"), smooth: num("free_camera_smooth") };
      s.scan = v.catalog_state === "scanning" ? { done: num("catalog_paths_done"), total: Math.max(1, num("catalog_paths_total")) } : null;
    } else {
      // Closing the game removes everything the mod spawned.
      Object.assign(s, { blue: 0, red: 0, neutral: 0, companion: 0, down: { blue: 0, red: 0, neutral: 0, companion: 0 }, unreadable: 0, freeCam: false, frozen: false, spectator: false, fight: "idle", winner: "", cleanup: "", synced: null, scan: null });
      Object.assign(s.statMatch, { baseline: null, matched: 0, failures: 0, reset: false });
      s.difficulty.game = "";
      s.clock = { state: "", seconds: 0 };
      Object.assign(s.track, { on: false, target: "", targetClass: "", otherClass: "", targets: [] });
      owned = 0;
    }
    const toggling = jobs.some(j => j.action === "toggle_spectator" && j.status === "pending");
    const restoring = online && !s.spectator && (num("spectator_pending_relations") > 0 || num("spectator_pending_flags") > 0);
    s.spectatorPhase = restoring ? "restoring" : toggling ? (s.spectator ? "restoring" : "switching") : "";

    const bindings = data.function_keys?.bindings || {};
    s.dismissKeySupported = online && data.function_keys?.dismiss_supported === true;
    s.weather = {supported: online && yes("weather_supported"), choice: v.weather_choice || "map"};
    s.teleport = {supported: online && yes("teleport_supported"), pending: yes("teleport_pending"), canReturn: yes("teleport_can_return"), message: v.teleport_message || "", keysRevision: num("teleport_keys_revision")};
    s.eyesKeysSupported = online && data.function_keys?.eyes_supported === true;
    s.selfieKeysSupported = online && data.function_keys?.selfie_supported === true;
    s.studioKeysSupported = online && data.function_keys?.studio_supported === true;
    s.cinemaKeysSupported = online && data.function_keys?.cinema_supported === true;
    s.cinema = {
      supported: online && yes("cinema_supported"),
      active: online && yes("cinema_active"),
      shot: online && CINEMA_SHOTS.includes(v.cinema_shot) ? v.cinema_shot : "",
    };
    s.battleHud = {
      supported: online && yes("battle_hud_supported"),
      mode: online && BATTLE_HUD_MODES.includes(v.battle_hud_mode) ? v.battle_hud_mode : "full",
    };
    s.attackFlash = {
      supported: online && yes("attack_flash_supported"),
      red: online && yes("attack_flash_red"),
      blue: online && yes("attack_flash_blue"),
    };
    s.selfie = online && yes("selfie_supported") ? {
      supported: true, studio: yes("photo_studio"), mode: v.photo_mode || "", on: yes("selfie_on"), ready: yes("selfie_ready"),
      target: (v.selfie_target || "").split(".").pop(), posed: num("selfie_posed"),
      style: num("selfie_style"), next: yes("selfie_next"), message: v.selfie_message || "",
    } : { ...SELFIE_DEFAULT };
    s.xboxKeysSupported = online && yes("xbox_keys_supported");
    s.weatherKeysSupported = online && data.function_keys?.weather_supported === true;
    s.hunKeysSupported = online && data.function_keys?.hun_supported === true;
    for (const k of [...KEY_NAMES, ...WEATHER_KEYS, ...EYE_KEYS, ...SELFIE_KEYS, ...STUDIO_KEYS, ...DIRECTOR_KEYS]) {
      const binding = bindings[k];
      s.keys[k] = binding?.key_code ? { code: binding.key_code, mods: binding.modifiers || 0 } : null;
      if (s.keys[k] && online && binding.error) s.keys[k].error = binding.error;
    }

    const updates = new Map();
    for (const q of [...(data.watched_commands || []), ...(data.queue || [])]) {
      const id = jobId(q.id); if (id) updates.set(id, q);
    }
    const changedJobs = [...updates.values()].map(mapJob).filter(Boolean);
    pruneJobs();
    // Waiting commands (queued, or handed over and not answered): a banner after QUEUE_STUCK_MS, at once for a leftover
    // command file, which holds them until it is cleared.
    const waiting = [...updates.values()].filter(q => q.status === "queued" || q.status === "pending");
    const code = data.transport_code || "";
    if (online && waiting.length) {
      const since = Math.min(...waiting.map(q => (q.created || Date.now() / 1000) * 1000));
      s.queue = { count: waiting.length, since, code, detail: data.transport_error || "", stuck: code === "orphan_inbox" || Date.now() - since >= QUEUE_STUCK_MS };
    } else s.queue = null;

    // Catalog: once per session, after a scan, and when unit keys change.
    const key = [g.game_session || "", data.catalog?.total || 0, v.unit_keys_revision || "", v.unit_keys_epoch || ""].join("|");
    if (key !== catalogKey) {
      catalogKey = key;
      loadCatalog().catch(() => { if (catalogKey === key) catalogKey = ""; });
    }
    if (Date.now() - iconsAt > (Object.keys(s.icons).length ? 60000 : 15000)) { loadIcons().catch(() => {}); loadNames().catch(() => {}); }
    if (online && s.level.supported && Date.now() - homesAt > 30000) loadHomeLevels().catch(() => {});

    // Events, in the same shapes MockRuntime sends.
    if (s.game !== was.game) emit({ type: "game" });
    for (const j of changedJobs) emit({ type: "job", job: j });
    for (const j of changedJobs) if (j.status !== "pending") waiters.get(j.id)?.(j);
    pruneJobs();
    if (online && (g.game_session !== session)) { session = g.game_session; teamRev = null; }
    const rev = num("arena_team_revision");
    if (online && teamRev !== null && rev > teamRev) emit({ type: "teamKey", team: s.team });
    if (online) teamRev = rev;
    if (s.blue < was.blue || s.red < was.red) emit({ type: "casualty" });
    if (was.fight === "fighting" && s.fight === "ended") emit({ type: "fightEnd", winner: s.winner });
    if (s.neutral < was.neutral && s.neutral + s.down.neutral >= was.soloHeld) emit({ type: "soloDown" });
    if (s.freeCam !== was.freeCam) emit({ type: "freeCam" });
    if (was.phase === "restoring" && !s.spectator && !s.spectatorPhase) emit({ type: "spectator" });
    if (was.scanning && !s.scan) emit({ type: "scanDone" });
    else if (s.scan) emit({ type: "scan" });

    // Re-render only the parts whose data moved, so a 500 ms poll never resets what the player is doing.
    const sig = {
      topbar: [s.game, jobs.filter(j => j.status === "failed" || j.status === "uncertain").length],
      sel: [s.game, s.cleanup, s.team, s.synced, s.spectator, s.statMatch.mode, s.statMatch.customCount, s.statMatch.baseline?.id, s.companionStats.mode, s.companionStats.customCount, s.companionStats.supported, s.keys.spawn?.code, s.keys.spawn?.mods, s.level.supported, s.level.mode, s.level.custom, s.level.cycle],
      solo: [s.game, s.neutral, s.down.neutral, s.spectator, s.spectatorPhase, s.freeCam],
      companionManager: [s.companionManagerRevision],
      arenaRoster: [s.game, s.arenaRosterSession, s.arenaRosterRevision],
      companion: [s.game, s.companion, s.down.companion, s.companionFailures, s.immortal.supported, s.immortal.companion, s.companionExec.supported, s.companionExec.on, s.companionPass.on, s.companionMinionExec.on, s.companionSquad, { ...s.companionStats, values: undefined }],
      match: [s.game, { ...s.statMatch, values: undefined }],
      diff: [s.game, s.difficulty, s.level.supported, s.level.mode, s.level.custom, s.level.cycle],
      fun: [s.game, s.fun, s.weather, s.weatherKeysSupported, WEATHER_KEYS.map(k => s.keys[k])],
      battle: [s.game, s.cleanup, s.blue, s.red, s.neutral, s.down.blue, s.down.neutral, s.unreadable, s.fight, s.winner, owned, s.arenaRosterRevision != null, [s.keys.start, s.keys.stop],
        s.immortal.supported, s.immortal.blue, s.immortal.red, s.immortal.failures, s.clock.state, !!(s.summonQueue.on && (s.summonQueue.waiting || s.summonQueue.transit || s.summonQueue.running))],
      // Only the clock text moves every second; the battle card is not rebuilt for it.
      clock: [s.clock.state, s.clock.seconds],
      view: [s.game, s.companion, s.blue > 0 && s.red > 0, s.spectator, s.spectatorPhase, s.freeCam, s.frozen, s.camSettings, [s.keys.toggle_camera, s.keys.toggle_spectator, s.keys.toggle_time_stop, s.keys.toggle_track, s.keys.track_pick, s.keys.track_next], s.track, s.clockHud, s.executionCamera, s.executionAppearance, s.selfie, s.cinema, s.battleHud, s.attackFlash, s.cinemaKeysSupported, [...SELFIE_KEYS, ...STUDIO_KEYS, ...DIRECTOR_KEYS].map(k => s.keys[k])],
      keys: [s.game, s.keys, s.eyesKeysSupported, s.selfieKeysSupported, s.studioKeysSupported, s.cinemaKeysSupported, s.weatherKeysSupported, s.dismissKeySupported, s.hunKeysSupported, s.xboxKeysSupported],
      grid: [s.entourageSupported, s.unitRulesSupported, s.remoteReflectSupported, s.longzhuProtectionSupported, s.xianzhePhantomSupported, s.menghuaStageSupported, s.executionMinionsSupported, s.unitRules],
      settings: [s.game, s.scan],
      battleMusic: [s.game, s.battleMusic, s.localAudio],
      summonQueue: [s.game, s.summonQueue],
      hun: [s.game, s.hunBodySupported, s.summonQueue.on, s.hunKeysSupported, HUN_KEYS.map(k => s.keys[k])],
      poolStatus: [s.poolStatus],
      queue: [s.queue?.stuck || false, s.queue?.code || "", s.queue?.count || 0, s.queue?.stuck ? Math.floor((Date.now() - s.queue.since) / 5000) : 0],
    };
    const parts = new Set();
    for (const key of Object.keys(sig)) {
      const value = JSON.stringify(sig[key]);
      if (value !== lastSig[key]) parts.add(key);
      lastSig[key] = value;
    }
    if (parts.size) emit({ type: "state", parts });
  }

  let pollTimer = null, polling = false;
  const needsStatus = () => !document.hidden || waiters.size > 0;
  function schedulePoll(delay) {
    if (pollTimer !== null) clearTimeout(pollTimer);
    pollTimer = null;
    if (!polling && needsStatus()) pollTimer = setTimeout(poll, delay);
  }
  async function poll() {
    pollTimer = null;
    if (polling || !needsStatus()) return;
    polling = true;
    try {
      const watched = [...waiters.keys()].slice(0, MAX_COMMANDS);
      const { response: r, data } = await readJSON("/api/status" + (watched.length ? "?watch=" + watched.join(",") : ""));
      if (!r.ok) throw new Error(String(r.status));
      apply(data);
      failedPolls = 0;
    } catch (error) {
      // The native window restarts the backend when the game folder changes; ride out short gaps.
      if (++failedPolls === 4 || error.code === "readTimeout") apply({ game: {}, queue: [] });
    } finally {
      polling = false;
      schedulePoll(500);
    }
  }
  document.addEventListener?.("visibilitychange", () => schedulePoll(0));

  // ---------- Commands ----------
  const online = () => ["notInMap", "ready", "mismatch"].includes(s.game);
  const ready = () => s.game === "ready" || s.game === "mismatch";
  const DIFFICULTIES = ["FOLLOW", "EASY", "NORMAL", "HARD", "NIGHTMARE"];
  const wireKey = b => (b ? { key_code: b.code, modifiers: b.mods || 0 } : { key_code: 0, modifiers: 0 });

  async function command(action, payload = {}) {
    if (activeCommands >= MAX_COMMANDS) throw fail("rejected", runtimeText("runtime14.commandLimit", { n: MAX_COMMANDS }));
    activeCommands++;
    try { return await executeCommand(action, payload); } finally { activeCommands--; }
  }
  async function executeCommand(action, payload) {
    if (!online()) throw fail("offline");
    if (["spawn", "queue_spawn", "hun_body_probe", "start", "toggle_spectator", "remove_arena_unit"].includes(action) && !ready()) throw fail("notInMap");
    if ((action === "toggle_camera" || action === "toggle_time_stop") && !s.freeCam && !ready()) throw fail("notInMap");
    let path = "/api/command", body;
    if (action === "spawn" || action === "queue_spawn" || action === "select_unit") body = { action, unit_id: gameId(payload.unit_id), team: payload.team, count: payload.count };
    else if (action === "configure_unit_key") {
      body = { action, unit_id: gameId(payload.unit_id), key_code: payload.code || 0, modifiers: payload.code ? payload.mods || 0 : 0 };
      if (payload.code && payload.team) Object.assign(body, { team: payload.team, count: payload.count });
    }
    else if (action === "set_spawn_difficulty") body = { action, difficulty: payload.difficulty };
    else if (action === "set_spawn_level") {
      body = { action, level_mode: payload.mode };
      if (payload.level != null) body.level = payload.level;
      if (payload.mode === "UNIT") body.unit_id = payload.unit;
    }
    else if (action === "set_fun_feature") body = { action, feature: payload.feature, enabled: payload.enabled };
    else if (action === "set_boss_combos" || action === "set_summon_queue") body = { action, enabled: payload.enabled };
    else if (action === "configure_summon_queue") body = { action, ...payload };
    else if (action === "set_team_immortal") body = { action, team: payload.team, enabled: payload.enabled };
    else if (action === "set_clock_hud") body = { action, enabled: payload.enabled };
    else if (action === "set_attack_flash") body = { action, color: payload.color, enabled: payload.enabled };
    else if (action === "manage_companion" || action === "remove_arena_unit") body = { action, unit_id: payload.unit_id };
    else if (action === "set_offcombat_regen") body = { action, enabled: payload.enabled };
    else if (action === "set_weather") body = {action, mode:payload.mode};
    else if (action === "teleport") body = { action, place: payload.place };
    else if (action === "configure_teleport_key") body = { action, place: payload.place, key_code: payload.key_code, modifiers: payload.modifiers };
    else if (action === "set_battle_music") body = { action, mode: payload.mode, track: payload.track };
    else if (action === 'hun_body_probe') body = { action, team: payload.team, count: payload.count, profile_revision: payload.profile_revision };
    else if (action === "set_execution_camera" || action === "set_execution_appearance") body = { action, enabled: payload.enabled };
    else if (action === "set_companion_executions") body = { action, enabled: payload.enabled };
    else if (action === "set_companion_passage") body = { action, enabled: payload.enabled };
    else if (action === "set_companion_minion_executions") body = { action, enabled: payload.enabled };
    else if (action === "set_unit_rule") body = { action, unit_id: payload.unit, rule: payload.rule, value: payload.value };
    else if (action === "set_camera_track") { body = { action, framing: payload.framing, resume: payload.resume }; if (payload.target) body.unit_id = payload.target; }
    else if (action === "set_free_camera") body = { action, speed: payload.speed, turn: payload.turn, smooth: payload.smooth };
    else if (action === "set_stat_mode" || action === "set_companion_stats") body = payload.mode === "custom" ? { action, mode: payload.mode, values: payload.values } : { action, mode: payload.mode };
    else if (action === "set_ai_params") body = { action, values: payload.values };
    else if (action === "configure_keys") {
      path = "/api/keybinds";
      const names = [...KEY_NAMES, ...(s.weatherKeysSupported ? WEATHER_KEYS : []),
        ...(s.eyesKeysSupported ? EYE_KEYS : []), ...(s.selfieKeysSupported ? SELFIE_KEYS : []),
        ...(s.studioKeysSupported ? STUDIO_KEYS : []),
        ...(s.cinemaKeysSupported ? DIRECTOR_KEYS : [])];
      body = Object.fromEntries(names.map(k => [k, wireKey(payload.bindings[k])]));
    }
    else body = { action };
    const held = action === "stop" ? owned : action === "clear_neutral" ? s.neutral + s.down.neutral : 0;
    const companionsHeld = action === "dismiss_companions" ? s.companion + s.down.companion : 0;
    let reply;
    try {
      reply = await submitCommand(path, body);
    } catch (error) {
      if (error?.code === "rejected") throw error;
      return { action, payload: body, status: "uncertain", code: "submissionUnknown", message: submissionMessage() };
    }
    const id = reply && jobId(reply.id);
    if (!id) {
      return { action, payload: body, status: "uncertain", code: "submissionUnknown", message: submissionMessage() };
    }
    // Show it in the history right away; the status poll fills in the game's answer.
    // A poll may already have picked the job up (and even its answer); never step it back to pending.
    const job = jobById.get(id) || mapJob({ id, action, payload: body, status: "pending", created: Date.now() / 1000 });
    emit({ type: "job", job });
    if (action === "queue_spawn") { pruneJobs(); return job; }
    const receipt = new Promise(resolve => {
      const timer = setTimeout(() => { waiters.delete(id); pruneJobs(); resolve(null); }, action === "refresh_catalog" ? 20000 : 90000);
      waiters.set(id, j => { clearTimeout(timer); waiters.delete(id); pruneJobs(); resolve(j); });
      if (document.hidden) schedulePoll(0);
      jobById.set(id, job);
      pruneJobs();
      if (job.status !== "pending") waiters.get(job.id)(job);
    });
    if (action === "hun_body_probe") {
      // Return the submission immediately but reserve its watch slot until the page gets a result.
      activeCommands++;
      receipt.then(result => {
        activeCommands--;
        if (!result) emit({ type: "job", job: { ...job, status: "uncertain", code: "noAck" } });
      });
      return job;
    }
    const done = await receipt;
    if (!done) return { ...job, status: "uncertain", code: "noAck" };
    if (held) done.cleared = Math.max(0, held - owned);
    // arena_controller.lua answers "随从清理：已确认=N"; fall back to the counts before and after.
    if (action === "dismiss_companions") done.cleared = Number((done.message || "").match(/已确认=(\d+)/)?.[1] ?? Math.max(0, companionsHeld - s.companion - s.down.companion));
    // The mod saved and read the choice back; show it before the next poll does.
    if (action === "set_spawn_difficulty" && done.status === "succeeded") s.difficulty.level = payload.difficulty;
    if (action === "set_spawn_level" && done.status === "succeeded") {
      if (payload.mode === "CYCLE") s.level.cycle = payload.level;
      else if (payload.mode !== "UNIT") s.level.mode = payload.mode;
      if (payload.mode === "CUSTOM") s.level.custom = payload.level;
      await loadHomeLevels().catch(() => {});
    }
    if (action === "set_fun_feature" && done.status === "succeeded") s.fun[payload.feature.toLowerCase()] = payload.enabled;
    if (action === "set_boss_combos" && done.status === "succeeded") s.combo.on = payload.enabled;
    if (action === "set_team_immortal" && done.status === "succeeded") s.immortal[payload.team] = payload.enabled;
    if (action === "set_clock_hud" && done.status === "succeeded") s.clockHud.on = payload.enabled;
    if (action === "set_attack_flash" && done.status === "succeeded") s.attackFlash[payload.color] = payload.enabled;
    if (action === "set_offcombat_regen" && done.status === "succeeded") Object.assign(s.offCombatRegen, { on: payload.enabled, state: payload.enabled ? "waiting" : "off" });
    if (action === "set_execution_camera" && done.status === "succeeded") s.executionCamera.on = payload.enabled;
    if (action === "set_execution_appearance" && done.status === "succeeded") s.executionAppearance.on = payload.enabled;
    if (action === "set_companion_executions" && done.status === "succeeded") s.companionExec.on = payload.enabled;
    if (action === "set_companion_passage" && done.status === "succeeded") s.companionPass.on = payload.enabled;
    if (action === "set_companion_minion_executions" && done.status === "succeeded") s.companionMinionExec.on = payload.enabled;
    if (action === "set_unit_rule" && done.status === "succeeded") (s.unitRules[payload.unit] ||= {})[payload.rule] = payload.value;
    if (action === "set_camera_track" && done.status === "succeeded") Object.assign(s.track, { framing: payload.framing, resume: payload.resume }, payload.target ? { target: payload.target } : {});
    if (action === "set_free_camera" && done.status === "succeeded") Object.assign(s.camSettings, { speed: payload.speed, turn: payload.turn, smooth: payload.smooth });
    if ((action === "set_stat_mode" || action === "set_companion_stats") && done.status === "succeeded") {
      const set = action === "set_stat_mode" ? s.statMatch : s.companionStats;
      set.mode = payload.mode;
      if (payload.mode === "custom") { set.values = { ...payload.values }; set.customCount = Object.keys(payload.values).length; }
    }
    return done;
  }

  // backend.py clear_queue(): every command the game has not answered is dropped with its delivery files; the next
  // poll shows them failed (never sent) or uncertain (handed over, not answered).
  async function clearQueue() {
    const r = await fetch("/api/queue/clear", { method: "POST", headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf }, body: "{}" });
    const reply = await r.json().catch(() => ({}));
    if (!r.ok) throw fail("rejected", reply.error || "");
    return reply;
  }

  function launchGame() {
    if (online() || s.game === "connecting") return;
    launching = Date.now();
    s.game = "connecting";
    emit({ type: "game" });
    host("launchGame").catch(() => { launching = 0; s.game = "offline"; emit({ type: "game" }); });
  }

  function trackProgress(task, onProgress) {
    progress.set(task, onProgress);
    return () => progress.delete(task);
  }

  const setup = {
    detectGame: () => host("detectGame"),
    pickFolder: () => host("pickFolder", { lang: document.documentElement.lang }),
    async setGamePath(path) {
      const info = await host("setGamePath", { path });
      s.gamePath = info.path;
      return info;
    },
    async components() {
      const list = await host("components");
      s.components = list;
      s.installed = list.every(c => c.ok);
      return list;
    },
    async install(onProgress) {
      const stop = trackProgress("install", m => onProgress({ step: m.step, ratio: m.ratio }));
      try { await host("install"); } finally { stop(); }
      await setup.components();
    },
    async uninstall(path) {
      const result = await host("uninstall", { path });
      s.installed = false;
      if (s.components) {
        s.components = s.components.map(c => c.id === "mod" ? { ...c, ok: false, present: false, detail: "" } : c);
      }
      return result;
    },
  };

  const update = {
    check: ({ silent = false } = {}) => host("checkUpdate", { lang: (document.documentElement.lang || "zh").slice(0, 2), silent }),
    selectVersion: version => host("selectVersion", { version, lang: (document.documentElement.lang || "zh").slice(0, 2) }),
    download(lineId, size, onProgress) {
      const stop = trackProgress("download", m => onProgress({ done: m.done, total: m.total || size, speed: m.speed || 0 }));
      const promise = host("downloadUpdate", { line: lineId }).finally(stop);
      return { promise, cancel() { host("cancelDownload").catch(() => {}); } };
    },
    verify: () => host("verifyUpdate"),
    install: () => host("installUpdate"),
    restart: () => host("restart"),
  };

  host("info").then(info => {
    s.appVersion = info.appVersion;
    s.channel = info.channel || "github";
    s.expectedBuild = info.modBuild;
    s.gamePath = info.gamePath || "";
    s.gameRunning = !!info.gameRunning;
    emit({ type: "host" });
    if (info.gamePath) setup.components().then(() => emit({ type: "host" }), () => {});
  }).catch(() => {});
  poll();

  return {
    demo: false,
    hasHost: !!webview,
    state: s,
    jobs,
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    online,
    ready,
    owned: () => owned,
    command,
    clearQueue,
    poolUnitId,
    poolUnitPath: id => toGame.get(id) || id,
    saveMonsterPools,
    hun: {
      async load() {
        const {response,data}=await readJSON('/api/hun');
        if(!response.ok)throw fail('rejected',data.error || '魂方案读取失败');
        return data;
      },
      save: request => submitCommand('/api/hun-profile',request),
    },
    teleport: {
      async load() {
        const {response,data}=await readJSON('/api/teleport-places');
        if(!response.ok)throw fail('rejected',data.error || '地点清单读取失败');
        return data;
      },
    },
    localAudio: {
      pick: () => host("pickAudio", { lang: document.documentElement.lang }),
      async change(request) {
        const reply = await submitCommand("/api/local-audio", request);
        s.localAudio = reply;
        emit({ type: "state", parts: new Set(["battleMusic"]) });
        return reply;
      },
    },
    launchGame,
    setup,
    update,
    openFolder: () => host("openFolder"),
    // The AI parameter values the mod saved (backend.py ai_params).
    async aiParams() {
      const { response: r, data } = await readJSON("/api/ai-params");
      if (!r.ok) throw fail("rejected");
      return data;
    },
    // The spawn stat mode and every custom value the mod saved (backend.py stat_settings).
    async statSettings() {
      const { response: r, data } = await readJSON("/api/stat-settings");
      if (!r.ok) throw fail("rejected");
      return data;
    },
    // The companions' own set, from its own file.
    saveCompanionSquad: request => submitCommand('/api/companion-squad', request),
    async companionManager() {
      const { response, data } = await readJSON("/api/companion-manager");
      if (!response.ok) throw fail("rejected");
      return data;
    },
    async arenaRoster() {
      const { response, data } = await readJSON("/api/arena-roster");
      if (!response.ok) throw fail("rejected");
      return data;
    },
    async companionStats() {
      const { response: r, data } = await readJSON("/api/companion-stats");
      if (!r.ok) throw fail("rejected");
      return data;
    },
    beta: {
      installation: () => host("betaInstallation"),
      check: code => host("checkBeta", { code }),
      install: id => host("installBeta", { id }),
    },
    async latestMatchReport() {
      const { response, data } = await readJSON("/api/match-report");
      if (!response.ok) throw fail("rejected");
      return data.report;
    },
    exportReport: () => host("exportReport"),
    // Prototype demo hooks; the packaged app has no demo panel.
    setGame() {}, cycleTeam() {}, defeatSolo() {}, toggleFreeCam() {}, set() {},
  };
})();
window.PGRuntime = RealRuntime;
