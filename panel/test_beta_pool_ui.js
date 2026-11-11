const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const i18n = require("./test_i18n_runtime")();

const app = readFileSync(path.join(__dirname, "prototype", "app.js"), "utf8");
function section(start, end) {
  const first = app.indexOf(start);
  const last = app.indexOf(end, first + 1);
  assert(first >= 0 && last > first);
  return app.slice(first, last);
}

const units = [{ id: "alpha", ch: 1, boss: false }, { id: "beta", ch: 1, boss: true }, { id: "blocked", ch: 2, boss: false }]
  .map(u => ({ ...u, name: u.id, zhName: u.id }));
const ui = { legacyPool: ["alpha"], poolQuery: "alp", count: 3, team: "red", busy: new Set() };
const S = { summonLimits: { alpha: 100, beta: 1 }, gameRunning: false,
  monsterPools: { revision: 0, pools: [] }, poolStatus: { scope: "fixture", keys: {} } };
const values = new Map(), calls = [], button = { disabled: true };
let code = "", nexus = false;
const context = {
  t: (key, params) => i18n.t(key, params),
  ui, S, UNITS: units, byId: new Map(units.map(u => [u.id, u])),
  RT: { ready: () => true, online: () => false, demo: true, poolUnitId: id => id, poolUnitPath: id => id,
    async saveMonsterPools(pools, revision) { S.monsterPools = { revision: revision + 1, pools }; },
    beta: {
    installation: async () => { calls.push("installation"); return "test-installation"; },
    check: async invite => {
      calls.push(["check", invite]);
      if (invite !== "test-pass") throw { detail: "签名无效" };
      return { id: "offer", version: "0.40.11", build: "queue-test", size: 42, note: "选定版本" };
    },
    install: async id => calls.push(["install", id]),
  } },
  store: { get: (key, fallback) => values.get(key) ?? fallback, set: (key, value) => values.set(key, value) },
  $: id => id === "#pool-summon" ? button : id === "#manual-beta-code" ? { value: code } : null,
  cleanupBlocker: () => "", renderPage() {}, toast() {}, summon: async (...args) => calls.push(args),
  dlg: null, openDialog: kind => { context.dlg = { kind }; },
  setDialog: html => { context.dialog = html; }, fromNexus: () => nexus,
  esc: value => String(value ?? ""), icon: () => "", fmtBytes: value => String(value),
  reasonText: (key, detail) => detail || key,
};
vm.createContext(context);
vm.runInContext(section("  function poolList()", "  function settingsHTML()"), context);

(async () => {
  assert.equal(context.selectedPool().unit_ids.join(), "alpha", "the prior single list is imported");
  context.createPool();
  context.updatePool({ name: "随从池", team: "companion", count: 1, key_code: 81, modifiers: 2 });
  // The "add units" dialog: type, chapter and search narrow the list; ticked units go in together, once each.
  ui.poolPick = { type: "all", chapter: "all", query: "", checked: new Set() };
  assert.equal(context.poolPickUnits().map(u => u.id).join(), "alpha,beta,blocked");
  ui.poolPick.type = "boss";
  assert.equal(context.poolPickUnits().map(u => u.id).join(), "beta");
  ui.poolPick.type = "minion"; ui.poolPick.chapter = "2";
  assert.equal(context.poolPickUnits().map(u => u.id).join(), "blocked");
  ui.poolPick.chapter = "all"; ui.poolPick.query = "ALP";
  assert.equal(context.poolPickUnits().map(u => u.id).join(), "alpha");
  context.changePool("beta", true);
  context.changePool("beta", true);
  assert.equal(context.selectedPool().unit_ids.join(), "beta");
  context.changePool(["blocked", "beta", "alpha", "blocked", "missing"], true);
  assert.equal(context.selectedPool().unit_ids.join(), "beta,blocked,alpha", "several at once, no repeats, unknown ids skipped");
  // Each unit is drawn on its own; a member leaves the draw at its own limit and one that cannot be summoned never enters.
  context.RT.demo = false;
  // Members beta (one per summon), blocked (not summonable), alpha: the draws take alpha, beta, then alpha for the rest.
  const rolls = [0.9, 0, 0, 0, 0];
  assert.equal(JSON.stringify(context.poolDraw({ ...context.selectedPool(), count: 5 }, () => rolls.shift())), '[["alpha",4],["beta",1]]');
  assert.equal(JSON.stringify(context.poolDraw({ unit_ids: ["beta", "blocked"], count: 3 }, () => 0)), '[["beta",1]]', "short when the limits run out");
  context.RT.demo = true;
  context.changePool("blocked", false);
  context.changePool("alpha", false);
  assert.equal(context.selectedPool().unit_ids.join(), "beta");
  // A copy keeps members, team and count, and takes no key.
  context.createPool(context.selectedPool());
  const copy = context.selectedPool();
  assert.equal(copy.name, "随从池 副本");
  assert.equal([copy.team, copy.count, copy.key_code, copy.modifiers, copy.unit_ids.join()].join(), "companion,1,0,0,beta");
  context.deletePool();
  ui.poolId = context.poolList().find(p => p.name === "随从池").id;
  context.renderPoolSummon();
  assert.equal(button.disabled, true);
  await context.summonFromPool();
  assert.equal(calls.length, 0);
  await context.savePoolList();
  context.renderPoolSummon();
  assert.equal(button.disabled, false);
  assert.equal(S.monsterPools.pools.length, 2);
  assert.equal(S.monsterPools.pools[1].modifiers, 2);
  await context.summonFromPool();
  assert.deepEqual(calls.shift(), ["beta", "companion", 1]);
  ui.poolId = "pool-default";
  await context.summonFromPool();
  assert.deepEqual(calls.shift(), ["alpha", "red", 3]);
  context.deletePool();
  await context.savePoolList();
  assert.equal(S.monsterPools.pools[0].name, "随从池");

  assert.doesNotMatch(section("  function scheduleAutoUpdate()", "  // ---------- Events"), /[Bb]eta/);
  await context.openManualBeta();
  assert.deepEqual(calls.splice(0), ["installation"]);
  assert.match(context.dialog, /test-installation/);
  code = "bad-pass";
  await context.checkManualBeta();
  assert.deepEqual(calls.splice(0), [["check", "bad-pass"]]);
  assert.equal(values.has("manualBetaInvite"), false);
  assert.match(context.dialog, /签名无效/);
  code = "  test-pass  ";
  await context.checkManualBeta();
  assert.deepEqual(calls.splice(0), [["check", "test-pass"]]);
  assert.equal(values.get("manualBetaInvite"), "test-pass");
  assert.match(context.dialog, /指定内测版 0\.40\.11/);
  S.gameRunning = true;
  await context.installManualBeta();
  assert.equal(calls.length, 0);
  S.gameRunning = false;
  await context.installManualBeta();
  assert.deepEqual(calls.splice(0), [["install", "offer"]]);
  await context.openManualBeta();
  assert.deepEqual(calls.splice(0), ["installation", ["check", "test-pass"]]);
  nexus = true;
  await context.openManualBeta();
  assert.equal(calls.length, 0);
  console.log("beta_pool_ui: persisted pool, eligible random summon, manual signed check and explicit install");
})().catch(error => { console.error(error); process.exitCode = 1; });
