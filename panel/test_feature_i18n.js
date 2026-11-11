const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const i18n = require("./test_i18n_runtime")();
const app = fs.readFileSync(path.join(__dirname, "prototype", "app.js"), "utf8");
function section(start, end) {
  const first = app.indexOf(start), last = app.indexOf(end, first + 1);
  assert(first >= 0 && last > first);
  return app.slice(first, last);
}
const pool = { id: "pool-test", name: "Test Pool", team: "blue", count: 2, key_code: 0, modifiers: 0, unit_ids: ["alpha"] };
const unit = { id: "alpha", name: "Alpha", boss: false, species: "GuaiMian" };
const context = {
  TEAMS: ["blue", "red", "neutral", "companion"],
  t: (key, params) => i18n.t(key, params), esc: value => String(value ?? ""), icon: () => "", kbd: String,
  teamName: team => team, avatarArt: () => "", artClass: () => "", fmtBytes: String,
  ui: { busy: new Set(), poolId: pool.id, capture: null,
    manualBeta: { checking: false, installing: false, installation: "test-id", offer: null } },
  S: { monsterPools: { revision: 1, pools: [pool] }, poolStatus: { scope: "test", revision: 1, supported: true, keys: {} },
    summonQueue: { on: true, supported: true, ready: true, waiting: 3, transit: 1, completed: 2, running: true } },
  RT: { online: () => true, poolUnitId: id => id },
  byId: new Map([[unit.id, unit]]), store: { get: (_, fallback) => fallback },
};
vm.createContext(context);
vm.runInContext(section("  function poolList()", "  function settingsHTML()"), context);
vm.runInContext(section("  function summonQueueSettingsHTML()", "  function renderSummonQueueSettings()"), context);
vm.runInContext(section("  function supportHTML()", "  function aboutHTML()"), context);
const featureKeys = i18n.keys("zh").filter(k => /^(pool\.|cycle\.|spawnQueue\.|beta\.|dock\.|unit\.source\.|unit\.note\.|unit\.permanent\.)/.test(k));
for (const lang of ["zh", "en", "ja", "fr", "de", "es"]) {
  i18n.set(lang);
  for (const key of ["app.title", "conn.ready", "nav.settings", "common.close", "nav.support", "support.description", "support.scan", "support.imageAlt", "support.enlarge", ...featureKeys]) {
    assert(i18n.keys(lang).includes(key), `${lang}: missing ${key}`);
    assert.notEqual(i18n.t(key), key, `${lang}: unresolved ${key}`);
  }
  const page = context.poolPageHTML();
  assert(page.includes(i18n.t("nav.pool")), lang);
  assert(page.includes(i18n.t("pool.summon")), lang);
  assert(page.includes(i18n.t("pool.team.blue")), lang);
  assert(!page.includes("{count}") && !page.includes("{kinds}"), lang);
  const queue = context.summonQueueSettingsHTML();
  assert(queue.includes(i18n.t("spawnQueue.title")), lang);
  assert(queue.includes(i18n.t("spawnQueue.progress", { waiting: 3, transit: 1, completed: 2 })), lang);
  assert(context.betaDialogHTML().includes(i18n.t("beta.checkTitle")), lang);
  const support = context.supportHTML();
  assert(support.includes(i18n.t("nav.support")) && support.includes(i18n.t("support.scan")), lang);
  assert(support.includes('src="support-wechat.png"') && !support.includes("https://"), lang);
  assert(context.supportImageHTML().includes('data-action="dialog-close"'), lang);
  if (lang !== "zh") assert(!page.includes("每只各自从池里随机") && !queue.includes("待游戏接收"), lang);
}
assert(fs.existsSync(path.join(__dirname, "prototype", "support-wechat.png")));
console.log("feature_i18n: PASS (six-language pools, queues, manual tests, support images, language changes and existing labels)");
