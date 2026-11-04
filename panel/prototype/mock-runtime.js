"use strict";
// Prototype-only stand-in for panel/backend.py and the game. It keeps the real command names
// (spawn, select_unit, start, stop, clear_neutral, toggle_spectator, toggle_stat_match, toggle_camera,
// exit_camera, configure_keys, configure_unit_key, refresh_catalog) and the same job states, but uses timers
// instead of the file bridge. Nothing in this file touches the game.
const MockRuntime = (() => {
  const listeners = new Set();
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  // Equal stats mirrors stat_match.lua: the switch is saved (Runtime/stat-match-settings.tsv),
  // the baseline only lives while the game runs. Two spawn-stat sets are the ones read in game.
  const MATCH_KEY = "pg-proto.statMatch";
  const KNOWN_STATS = {
    BP_Monster_AHua_GuiTouDao: { hp: 9000, shachi: 800, atk: 70, satk: 33 },
    BP_Monster_MoTian: { hp: 12000, shachi: 1200, atk: 84, satk: 39.6 },
  };
  function statsFor(id) {
    if (KNOWN_STATS[id]) return KNOWN_STATS[id];
    let h = 0;
    for (const c of id) h = (h * 31 + c.charCodeAt(0)) >>> 0;
    const boss = PG_UNITS.find(u => u.id === id)?.boss;
    const atk = boss ? 55 + (h >> 5) % 40 : 18 + (h >> 5) % 25;
    return {
      hp: boss ? 6000 + (h % 10) * 900 : 800 + (h % 12) * 150,
      shachi: boss ? 600 + ((h >> 3) % 8) * 100 : 150 + ((h >> 3) % 6) * 50,
      atk,
      satk: Math.round(atk * (boss ? 4.5 : 4)) / 10,
    };
  }
  let savedMatch = false;
  try { savedMatch = localStorage.getItem(MATCH_KEY) === "true"; } catch { /* storage may be unavailable */ }
  // Summon difficulty mirrors spawn_difficulty.lua: saved like Runtime/spawn-difficulty.tsv; the game plays on Easy.
  const DIFF_KEY = "pg-proto.difficulty";
  let savedDiff = "FOLLOW";
  try { savedDiff = localStorage.getItem(DIFF_KEY) || "FOLLOW"; } catch { /* storage may be unavailable */ }
  // The summon level choice mirrors Runtime/spawn-level-settings.tsv: the mode, the custom level, each unit's pick.
  const LEVEL_KEY = "pg-proto.level";
  let savedLevel = {};
  try { savedLevel = JSON.parse(localStorage.getItem(LEVEL_KEY) || "{}") || {}; } catch { /* storage may be unavailable */ }
  // Fun features mirror fun_features.lua: player-only switches saved like Runtime/fun-features.tsv.
  const FUN_KEY = "pg-proto.fun";
  let savedFun = {};
  try { savedFun = JSON.parse(localStorage.getItem(FUN_KEY) || "{}") || {}; } catch { /* storage may be unavailable */ }
  // 不倒下 mirrors immortal_teams.lua: one saved switch per team (Runtime/immortal-teams.tsv).
  const IMMORTAL_KEY = "pg-proto.immortal";
  let savedImmortal = {};
  try { savedImmortal = JSON.parse(localStorage.getItem(IMMORTAL_KEY) || "{}") || {}; } catch { /* storage may be unavailable */ }
  // The on-screen clock switch mirrors battle_clock_hud.lua (Runtime/clock-hud.tsv).
  const CLOCK_HUD_KEY = "pg-proto.clockHud";
  let savedClockHud = false;
  try { savedClockHud = localStorage.getItem(CLOCK_HUD_KEY) === "true"; } catch { /* storage may be unavailable */ }
  // The execution camera switch mirrors execution_camera.lua (Runtime/execution-camera.tsv).
  const EXEC_CAM_KEY = "pg-proto.executionCamera";
  let savedExecCam = false;
  try { savedExecCam = localStorage.getItem(EXEC_CAM_KEY) === "true"; } catch { /* storage may be unavailable */ }
  const s = {
    game: "ready",              // offline | connecting | notInMap | ready | mismatch
    gameRunning: true,          // the updater refuses to replace mod files while the game runs
    appVersion: "0.26.2",
    modVersion: "0.26.2",
    blue: 0, red: 0, neutral: 0,  // alive (HP above 0), like blue_count / red_count / neutral_count
    companion: 0,               // companions follow the player and stay through "stop and clear" (companion_count)
    companionFailures: 0,
    // Fallen units stay registered until cleanup (arena_dead_count, neutral_owned_records).
    down: { blue: 0, red: 0, neutral: 0, companion: 0 },
    unreadable: 0,              // HP could not be read (arena_unreadable_count); not counted as alive or fallen
    freeCam: false,             // F6 observer camera: forces spectator on, locks HP, hides the player
    team: "blue",               // the game's current summon team (F2 cycles it)
    spectator: false,
    spectatorPhase: "",         // "" | "switching" | "restoring"
    // baseline: { id, hp, shachi, atk, satk } spawn stats; reset: cleared because the field emptied
    icons: {},                  // the prototype has no game pictures: cards show the first character
    unitNames: null,            // and no game names: units.js's Chinese names
    statMatch: { enabled: savedMatch, mode: savedMatch ? "match" : "game", modeSupported: true, baseline: null, matched: 0, failures: 0, reset: false, customCount: 0, customized: 0, rejected: [], rejectedCount: 0, values: {} },
    // level: FOLLOW | EASY | NORMAL | HARD | NIGHTMARE for new units; game: the game's own level
    difficulty: { level: savedDiff, game: "Easy", supported: true, failures: 0, skipped: 0, aiFailed: 0, summonLevel: 18, summonLevelUnit: "BP_Monster_BaiheDisciple_Knife" },
    // Where a summon's level comes from (HOME | HERE | CUSTOM) and each unit's places in the game, as the mod writes them.
    combo: { supported: true, on: false },
    level: { supported: true, mode: savedLevel.mode || "HOME", custom: savedLevel.custom ?? null, homes: mockHomes(savedLevel.picks || {}) },
    // shachiState: off | locked | failed; guardState: off | waiting | ready | failed; deflects/dodges pressed so far
    fun: { supported: true, shachi: !!savedFun.shachi, deflect: !!savedFun.deflect, dodge: !!savedFun.dodge,
      shachiState: savedFun.shachi ? "locked" : "off", guardState: savedFun.deflect || savedFun.dodge ? "waiting" : "off", deflects: 0, dodges: 0 },
    // A side switched on here never loses a unit; locked counts the units held up right now.
    immortal: { supported: true, blue: !!savedImmortal.blue, red: !!savedImmortal.red, companion: !!savedImmortal.companion, locked: 0, failures: 0 },
    clock: { state: "", seconds: 0 },   // the fight's game seconds: running while fighting, ended once one side is out
    clockHud: { supported: true, on: savedClockHud, state: savedClockHud ? "waiting" : "off" },  // off | waiting | shown | failed
    executionCamera: { supported: true, on: savedExecCam, state: savedExecCam ? "waiting" : "off" },  // off | waiting | running
    fight: "idle",              // idle | fighting | ended
    winner: "",                 // blue | red | draw
    cleanup: "",                // "" | restore_pending (one more cleanup) | spawn_uncertain (restart the game)
    stopOutcome: "ok",          // ok | partial (next cleanup leaves one restore record) | stuck (every cleanup does)
    // The eight function keys (BINDING_NAMES in backend.py) start unbound; each is null or { code, mods }.
    keys: { spawn: null, start: null, stop: null, refresh_catalog: null, toggle_camera: null, exit_camera: null, cycle_team: null, toggle_spectator: null, recall_companions: null, toggle_time_stop: null },
    unitKeys: {},               // unitId -> { code, mods }
    nextOutcome: "ok",          // ok | error | uncertain | matchWarn | matchAbort (next spawn only)
    updateScenario: "available",// available | latest | offline
    scan: null,                 // { done, total } while a full scan runs
    synced: null,               // last select_unit payload the game confirmed
    // The queue (backend.py): commands the game has not answered. queueScenario "stuck" (demo panel) holds every new
    // command behind a leftover command file, as a player's queue was held up to v0.38.0, until it is cleared.
    queue: null,
    queueScenario: "ok",
    // 时停 and the free camera settings (free_camera.lua: Runtime/free-camera-settings.tsv).
    frozen: false,
    camSettings: { supported: true, speed: 900, turn: 100, smooth: 40 },
    installed: false,           // loader + mod present in the chosen game folder
  };
  const jobs = [];
  let seq = 270, fightTimer = null, scanTimer = null, clockTimer = null, releaseHeld = null;

  const emit = event => { for (const fn of listeners) fn(event || {}); };
  const online = () => ["notInMap", "ready", "mismatch"].includes(s.game);
  const ready = () => s.game === "ready" || s.game === "mismatch";
  const fail = code => Object.assign(new Error(code), { code });
  // Every unit the app still holds, alive or fallen; cleanup and the equal-stats reset go by this.
  const owned = () => s.blue + s.red + s.neutral + s.down.blue + s.down.red + s.down.neutral;   // companions are not the arena's

  // A few units' places in the game (native_levels.lua), with the default the mod would pick and the player's own pick.
  function mockHomes(picks) {
    const homes = {
      BP_Monster_YuCong_FirstTime: { default: 0, options: [{ level: 15, source: "native", map: "悲泣溪谷", part: "A", count: 1 }] },
      BP_Monster_AHua_GuiTouDao: { default: 0, options: [{ level: 3, source: "native", map: "悲泣溪谷", part: "C", count: 1 }] },
      BP_Monster_MaleThug_Sword_Blue: { default: 1, options: [{ level: 2, source: "native", map: "悲泣溪谷", part: "B", count: 4 }, { level: 3, source: "native", map: "悲泣溪谷", part: "C", count: 9 }, { level: 10, source: "native", map: "庞镇地区", part: "A", count: 2 }] },
      BP_Monster_BaiheDisciple_Knife: { default: 0, options: [{ level: 4, source: "native", map: "血色森林", part: "A", count: 4 }, { level: 7, source: "native", map: "陆家村地区", part: "A", count: 9 }, { level: 13, source: "native", map: "庞镇地区", part: "A", count: 4 }, { level: 18, source: "native", map: "梅谷湖", part: "", count: 2 }, { level: 19, source: "native", map: "梅谷湖", part: "B", count: 24 }] },
    };
    for (const [id, h] of Object.entries(homes)) {
      const level = picks[id], i = h.options.findIndex(o => o.level === level);
      if (level != null && i < 0) h.options.push({ level, source: "picked", map: "", part: "", count: 0 });
      h.picked = level == null ? null : i < 0 ? h.options.length - 1 : i;
    }
    return homes;
  }
  function saveLevel() {
    const picks = {};
    for (const [id, h] of Object.entries(s.level.homes)) if (h.picked != null) picks[id] = h.options[h.picked].level;
    try { localStorage.setItem(LEVEL_KEY, JSON.stringify({ mode: s.level.mode, custom: s.level.custom, picks })); } catch { /* ignore */ }
  }

  async function command(action, payload = {}) {
    if (!online()) throw fail("offline");
    if (["spawn", "start", "toggle_spectator"].includes(action) && !ready()) throw fail("notInMap");
    if (action === "toggle_camera" && !s.freeCam && !ready()) throw fail("notInMap");
    const job = { id: ++seq, action, payload, status: "pending", created: Date.now() };
    jobs.unshift(job);
    if (jobs.length > 50) jobs.pop();
    if (action === "toggle_spectator") s.spectatorPhase = s.spectator ? "restoring" : "switching";
    emit({ type: "job", job });
    if (s.queueScenario === "stuck") {
      const held = jobs.filter(j => j.status === "pending");
      s.queue = { count: held.length, since: s.queue?.since || Date.now(), code: "orphan_inbox", detail: "", stuck: true };
      emit({ type: "state", parts: new Set(["queue"]) });
      await new Promise(resolve => { const before = releaseHeld; releaseHeld = () => { before?.(); resolve(); }; });
      return job;
    }
    await wait(action === "select_unit" ? 240 : 600 + Math.random() * 500);
    apply(job);
    job.finished = Date.now();
    emit({ type: "job", job });
    return job;
  }

  function apply(job) {
    const p = job.payload;
    job.status = "succeeded";
    switch (job.action) {
      case "spawn": {
        if (s.cleanup) { job.status = "failed"; job.code = s.cleanup === "spawn_uncertain" ? "uncertainSpawn" : "unfinished"; return; }
        const outcome = s.nextOutcome;
        s.nextOutcome = "ok";
        if (outcome === "error") { job.status = "failed"; job.code = "spawnFailed"; return; }
        if (outcome === "uncertain") { job.status = "uncertain"; job.code = "noAck"; return; }
        const m = s.statMatch;
        m.reset = false;            // units are about to appear, so "the field was cleared" no longer holds
        if (m.mode === "custom" && p.team !== "companion") {
          s[p.team] += p.count; job.spawned = p.count; m.customized += p.count;
          const v = m.values;
          m.rejected = [["Health", "Health_Max"], ["Shield", "Shield_Max"], ["Shachi", "Shachi_Max"]].filter(([c, max]) => v[c] != null && v[max] != null && v[c] > v[max]).map(([c]) => c);
          m.rejectedCount = m.rejected.length;
          return;
        }
        if (m.enabled && outcome === "matchAbort") {
          // The rollback could not be confirmed: the batch stops and that unit stays for cleanup.
          s[p.team] += 1;
          job.spawned = 1;
          m.failures++;
          job.status = "failed";
          job.code = "matchAbort";
          return;
        }
        s[p.team] += p.count;
        job.spawned = p.count;
        if (!m.enabled) return;
        if (outcome === "matchWarn") { m.failures += p.count; job.warning = "matchFailed"; return; }
        if (!m.baseline) { m.baseline = { id: p.unit_id, ...statsFor(p.unit_id) }; m.matched += p.count - 1; }
        else m.matched += p.count;
        return;
      }
      case "select_unit":
        s.synced = { ...p };
        s.team = p.team;
        return;
      case "start":
        if (!s.blue || !s.red) { job.status = "failed"; job.code = "needBoth"; return; }
        startFight();
        return;
      case "stop":
        job.cleared = owned();
        clearTimeout(fightTimer);
        clearInterval(clockTimer);
        s.clock = { state: "", seconds: 0 };
        // Like arena_controller.lua: units go, but an unconfirmed restore leaves restore_pending.
        const partial = (s.stopOutcome === "partial" && job.cleared > 0) || s.stopOutcome === "stuck";
        if (s.stopOutcome === "partial") s.stopOutcome = "ok";
        Object.assign(s, { blue: 0, red: 0, neutral: 0, down: { blue: 0, red: 0, neutral: 0, companion: s.down.companion }, unreadable: 0, fight: "idle", winner: "", cleanup: partial ? "restore_pending" : "" });
        if (partial) { job.status = "failed"; job.code = "restorePending"; job.message = `清理读回：已失效/进入销毁=${job.cleared}，待确认=0；恢复确认=false`; }
        releaseBaseline();
        return;
      case "toggle_time_stop":
        // Outside the free camera it opens first, frozen; leaving the camera ends it.
        if (!s.freeCam) { setFreeCam(true); s.frozen = true; job.message = "已进入自由观战；时停：游戏已暂停，镜头照常移动"; return; }
        s.frozen = !s.frozen;
        job.message = s.frozen ? "时停：游戏已暂停，镜头照常移动" : "已解除时停";
        return;
      case "set_free_camera":
        Object.assign(s.camSettings, { speed: job.payload.speed, turn: job.payload.turn, smooth: job.payload.smooth });
        return;
      case "recall_companions":
        // companion.lua recall(): the live ones beside the player.
        job.message = s.companion ? `已召回 ${s.companion}/${s.companion} 个随从到身边` : "没有可召回的随从";
        return;
      case "dismiss_companions":
        job.cleared = s.companion + s.down.companion;
        s.companion = 0;
        s.down.companion = 0;
        return;
      case "clear_neutral":
        // Only the app's no-team units, fallen ones included; Blue, Red and a running fight stay as they are.
        job.cleared = s.neutral + s.down.neutral;
        s.neutral = 0;
        s.down.neutral = 0;
        releaseBaseline();
        return;
      case "set_boss_combos": s.combo = { supported: true, on: p.enabled }; return;
      case "set_fun_feature": {
        const f = s.fun;
        f[p.feature.toLowerCase()] = p.enabled;
        f.shachiState = f.shachi ? "locked" : "off";
        f.guardState = f.deflect || f.dodge ? (f.deflects || f.dodges ? "ready" : "waiting") : "off";
        try { localStorage.setItem(FUN_KEY, JSON.stringify({ shachi: f.shachi, deflect: f.deflect, dodge: f.dodge })); } catch { /* ignore */ }
        return;
      }
      case "set_stat_mode": {
        const m = s.statMatch;
        Object.assign(m, { mode: p.mode, enabled: p.mode !== "game", baseline: null, matched: 0, failures: 0, reset: false, customized: 0, rejected: [], rejectedCount: 0 });
        if (p.mode === "custom") Object.assign(m, { values: { ...p.values }, customCount: Object.keys(p.values).length });
        return;
      }
      case "set_ai_params":
        s.aiParamValues = { ...p.values };
        return;
      case "set_clock_hud":
        s.clockHud = { supported: true, on: p.enabled, state: p.enabled ? (s.fight === "idle" ? "waiting" : "shown") : "off" };
        try { localStorage.setItem(CLOCK_HUD_KEY, String(p.enabled)); } catch { /* ignore */ }
        return;
      case "set_execution_camera":
        s.executionCamera = { supported: true, on: p.enabled, state: p.enabled ? "waiting" : "off" };
        try { localStorage.setItem(EXEC_CAM_KEY, String(p.enabled)); } catch { /* ignore */ }
        return;
      case "set_team_immortal":
        s.immortal[p.team] = p.enabled;
        try { localStorage.setItem(IMMORTAL_KEY, JSON.stringify({ blue: s.immortal.blue, red: s.immortal.red, companion: s.immortal.companion })); } catch { /* ignore */ }
        return;
      case "set_spawn_difficulty":
        s.difficulty.level = p.difficulty;
        try { localStorage.setItem(DIFF_KEY, p.difficulty); } catch { /* ignore */ }
        return;
      case "set_spawn_level":
        if (p.mode === "UNIT") {
          const picks = {};
          for (const [id, h] of Object.entries(s.level.homes)) if (h.picked != null) picks[id] = h.options[h.picked].level;
          if (p.level == null) delete picks[p.unit]; else picks[p.unit] = p.level;
          s.level.homes = mockHomes(picks);
        } else {
          s.level.mode = p.mode;
          if (p.mode === "CUSTOM") s.level.custom = p.level;
        }
        saveLevel();
        return;
      case "toggle_stat_match":
        // Either direction re-picks the baseline; units already on the field keep their numbers.
        Object.assign(s.statMatch, { enabled: !s.statMatch.enabled, baseline: null, matched: 0, failures: 0, reset: false });
        try { localStorage.setItem(MATCH_KEY, String(s.statMatch.enabled)); } catch { /* ignore */ }
        return;
      case "toggle_spectator":
        if (s.spectator) {
          // Turning off restores the original hostility records before reporting "off".
          setTimeout(() => { s.spectator = false; s.spectatorPhase = ""; emit({ type: "spectator" }); }, 900);
        } else {
          s.spectator = true;
          s.spectatorPhase = "";
        }
        return;
      case "configure_keys":
        s.keys = { ...p.bindings };
        return;
      case "toggle_camera":
        setFreeCam(!s.freeCam);
        return;
      case "exit_camera":
        setFreeCam(false);
        return;
      case "configure_unit_key":
        if (p.code) s.unitKeys[p.unit_id] = { code: p.code, mods: p.mods, team: p.team || null, count: p.count || null };
        else delete s.unitKeys[p.unit_id];
        return;
      case "refresh_catalog":
        startScan();
        return;
    }
  }

  // stat_match.lua drops the baseline only once none of the app's units are left.
  function releaseBaseline() {
    const m = s.statMatch;
    if (owned() > 0 || !m.baseline) return;
    Object.assign(m, { baseline: null, matched: 0, failures: 0, reset: true });
  }

  function startFight() {
    clearTimeout(fightTimer);
    clearInterval(clockTimer);
    s.fight = "fighting";
    s.winner = "";
    // Wall-clock seconds here; the mod reports game seconds twice a second.
    const started = Date.now();
    s.clock = { state: "running", seconds: 0 };
    clockTimer = setInterval(() => {
      s.clock.seconds = (Date.now() - started) / 1000;
      emit({ type: "state", parts: new Set(["clock"]) });
    }, 1000);
    const tick = () => {
      if (s.fight !== "fighting") return;
      // A side that does not go down never loses a unit; with both sides held the fight runs on.
      const sides = ["blue", "red"].filter(team => !s.immortal[team]);
      if (s.blue && s.red && sides.length) {
        // The larger side is less likely to lose the next unit.
        const loser = sides.length === 1 ? sides[0] : Math.random() < s.red / (s.blue + s.red) ? "blue" : "red";
        s[loser]--;
        s.down[loser]++;
        emit({ type: "casualty" });
      }
      if (!s.blue || !s.red) {
        clearInterval(clockTimer);
        s.clock = { state: "ended", seconds: (Date.now() - started) / 1000 };
        s.fight = "ended";
        s.winner = s.blue ? "blue" : s.red ? "red" : "draw";
        emit({ type: "fightEnd", winner: s.winner });
        return;
      }
      fightTimer = setTimeout(tick, 1100 + Math.random() * 1400);
    };
    fightTimer = setTimeout(tick, 1500);
  }

  function startScan() {
    clearInterval(scanTimer);
    s.scan = { done: 0, total: 19736 };
    scanTimer = setInterval(() => {
      s.scan.done = Math.min(s.scan.total, s.scan.done + 600 + Math.floor(Math.random() * 900));
      if (s.scan.done >= s.scan.total) {
        clearInterval(scanTimer);
        s.scan = null;
        emit({ type: "scanDone" });
      } else emit({ type: "scan" });
    }, 220);
  }

  function launchGame() {
    if (online() || s.game === "connecting") return;
    s.game = "connecting";
    s.gameRunning = true;
    emit({ type: "game" });
    setTimeout(() => { s.game = "notInMap"; emit({ type: "game" }); }, 2200);
    setTimeout(() => { if (s.game === "notInMap") { s.game = "ready"; emit({ type: "game" }); } }, 5000);
  }

  function setGame(state) {
    s.game = state;
    if (state === "offline") {
      clearTimeout(fightTimer);
      clearInterval(clockTimer);
      s.clock = { state: "", seconds: 0 };
      Object.assign(s, { blue: 0, red: 0, neutral: 0, down: { blue: 0, red: 0, neutral: 0 }, unreadable: 0, fight: "idle", winner: "", cleanup: "", spectator: false, spectatorPhase: "", freeCam: false, synced: null });
      // The mod's memory is gone with the game; only the saved switch survives.
      Object.assign(s.statMatch, { baseline: null, matched: 0, failures: 0, reset: false });
    }
    s.modVersion = state === "mismatch" ? "0.25.4" : s.appVersion;
    emit({ type: "game" });
  }

  function cycleTeam() {
    if (!online()) return;
    s.team = { blue: "red", red: "neutral", neutral: "companion", companion: "blue" }[s.team];
    emit({ type: "teamKey", team: s.team });
  }

  // The player beats one of the no-team units in game (prototype demo only).
  function defeatSolo() {
    if (!s.neutral) return;
    s.neutral--;
    s.down.neutral++;
    emit({ type: "soloDown" });
  }

  // The observer camera turns spectator on for its lifetime, then puts it back the way it was.
  function setFreeCam(on) {
    if (on === s.freeCam) return;
    if (on) Object.assign(s, { freeCam: true, spectatorBeforeCam: s.spectator, spectator: true });
    else Object.assign(s, { freeCam: false, frozen: false, spectator: s.spectatorBeforeCam });
  }
  // The camera key pressed in game (prototype demo only).
  function toggleFreeCam() {
    if (!online()) return;
    setFreeCam(!s.freeCam);
    emit({ type: "freeCam" });
  }

  const update = {
    async check() {
      await wait(1200 + Math.random() * 600);
      if (s.updateScenario === "offline") throw Object.assign(fail("offline"), { tried: ["github", "cdn", "mirror"] });
      if (s.updateScenario === "latest") return { latest: true, version: s.appVersion };
      return {
        latest: false,
        version: "0.27.0",
        date: "2026-11-08T10:00:00+08:00",
        size: 19874816,
        lines: [
          { id: "parts", ms: 31 + Math.floor(Math.random() * 20) },
          { id: "cn1", ms: 38 + Math.floor(Math.random() * 20) },
          { id: "cn2", ms: 110 + Math.floor(Math.random() * 60) },
          { id: "github", ms: null },
        ],
      };
    },
    async selectVersion(version) {
      await wait(600);
      if (s.updateScenario === "offline") throw Object.assign(fail("offline"), { tried: ["github", "cdn", "mirror"] });
      return {
        latest: false,
        rollback: true,
        version,
        date: (window.PG_CHANGELOG || []).find(r => r.version === version)?.date || "",
        size: 20822497,
        lines: [
          { id: "parts", ms: 35 },
          { id: "cn1", ms: 42 },
          { id: "cn2", ms: 128 },
          { id: "github", ms: null },
        ],
      };
    },
    download(lineId, size, onProgress) {
      const rate = lineId === "github" ? 420000 : lineId === "cn2" ? 1900000 : 3600000;
      let done = 0, timer = null, cancelled = false, stop = null;
      const promise = new Promise((resolve, reject) => {
        stop = () => reject(fail("cancelled"));
        const step = () => {
          const speed = rate * (0.75 + Math.random() * 0.5);
          done = Math.min(size, done + speed / 5);
          onProgress({ done, total: size, speed });
          if (done >= size) resolve(); else timer = setTimeout(step, 200);
        };
        timer = setTimeout(step, 300);
      });
      return { promise, cancel() { cancelled = true; clearTimeout(timer); stop(); } };
    },
    async verify() { await wait(1000); return true; },
    async install() { await wait(1700); s.appVersion = "0.27.0"; s.modVersion = online() ? s.modVersion : "0.27.0"; return true; },
  };

  const setup = {
    async detectGame() {
      await wait(1500);
      return { path: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\PBZ", store: "Steam", build: "26367565" };
    },
    async components() {
      await wait(700);
      return [
        { id: "game", ok: true, detail: "build 26367565" },
        { id: "loader", ok: s.installed, detail: "UE4SS 3.0.1" },
        { id: "mod", ok: s.installed, detail: "v" + s.appVersion },
      ];
    },
    async install(onProgress) {
      const steps = ["loader", "config", "mod"];
      for (let i = 0; i < steps.length; i++) {
        for (let k = 1; k <= 10; k++) {
          await wait(70 + Math.random() * 60);
          onProgress({ step: steps[i], ratio: (i * 10 + k) / (steps.length * 10) });
        }
      }
      s.installed = true;
    },
  };

  // backend.py clear_queue(): held commands fail as cleared by hand and the queue runs again.
  async function clearQueue() {
    await wait(250);
    const held = jobs.filter(j => j.status === "pending");
    for (const job of held) { job.status = "failed"; job.code = "cleared"; job.finished = Date.now(); emit({ type: "job", job }); }
    s.queue = null;
    s.queueScenario = "ok";
    const release = releaseHeld;
    releaseHeld = null;
    release?.();
    emit({ type: "state", parts: new Set(["queue"]) });
    emit({ type: "demo" });
    return { cleared: held.length, interrupted: 0, files_left: [] };
  }

  return {
    demo: true,
    hasHost: false,
    state: s,
    jobs,
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    online,
    ready,
    owned,
    command,
    clearQueue,
    launchGame,
    setGame,
    cycleTeam,
    defeatSolo,
    toggleFreeCam,
    update,
    setup,
    async aiParams() { await wait(150); return { values: { ...(s.aiParamValues || {}) } }; },
    async statSettings() { await wait(150); return { mode: s.statMatch.mode, values: { ...s.statMatch.values } }; },
    set(patch) { Object.assign(s, patch); emit({ type: "demo" }); },
  };
})();
window.PGRuntime = MockRuntime;
