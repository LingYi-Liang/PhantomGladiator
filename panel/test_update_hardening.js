const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const i18n = require("./test_i18n_runtime")();
const app = fs.readFileSync(path.join(__dirname, "prototype/app.js"), "utf8");
function section(start, end) {
  const at = app.indexOf(start), last = app.indexOf(end, at + 1);
  assert(at >= 0 && last > at);
  return app.slice(at, last);
}
const context = {
  ui: { update: { phase: "error", error: { code: "updateUnconfirmed", tried: ["cdn"] } }, page: "battle" },
  S: { appVersion: "0.40.13", gameRunning: false },
  t: (key, params) => i18n.t(key, params), esc: v => String(v ?? ""), icon: () => "",
  fromNexus: () => false, releaseHistoryHTML: () => "", releaseNotes: () => [],
  noteHTML: v => String(v), lineFor: info => info.lines[0], LINE_IDS: ["auto", "github"],
  fmtDate: String, fmtBytes: String, REPO: "https://github.com/example/project",
  dlg: null, store: { set() {} }, renderTopbar() {}, renderPage() {},
  RT: { update: { check: async options => {
    context.options = options;
    throw { code: "updateUnconfirmed", tried: ["cdn"] };
  } } },
};
vm.createContext(context);
vm.runInContext(section("  function updateHTML()", "  // Asks for the older version"), context);
for (const lang of ["zh", "en", "ja", "fr", "de", "es"]) {
  i18n.set(lang);
  for (const key of ["update.unconfirmedTitle", "update.unconfirmedBody", "update.stableTitle", "update.stableBody", "update.stableDownload", "update.notesUnavailable"]) {
    assert(i18n.keys(lang).includes(key), `${lang}: missing ${key}`);
  }
  context.ui.update = { phase: "error", error: { code: "updateUnconfirmed", tried: ["cdn"] } };
  const uncertain = context.updateHTML();
  assert(uncertain.includes(i18n.t("update.unconfirmedTitle")) && !uncertain.includes(i18n.t("update.error.body")), lang);
  context.ui.update = { phase: "available", line: "auto", info: {
    version: "0.40.13", currentBuild: "v0.40.13-beta-3", switchToStable: true,
    lines: [{ id: "github", ms: 1 }], notes: [], date: "date", size: 100,
  } };
  const stable = context.updateHTML();
  assert(stable.includes(i18n.t("update.stableTitle", { v: "0.40.13" })), lang);
  assert(stable.includes(i18n.t("update.stableDownload")) && stable.includes("v0.40.13-beta-3"), lang);
  assert(stable.includes(i18n.t("update.notesUnavailable")) && !stable.includes(i18n.t("update.note1")), lang);
}
(async () => {
  context.ui.update = { phase: "idle" };
  await context.checkUpdate();
  assert.equal(context.ui.update.error.code, "updateUnconfirmed");
  assert.equal(context.options.silent, false);
  await context.checkUpdate({ silent: true });
  assert.equal(context.options.silent, true);
  assert.equal(context.ui.update.phase, "idle", "unconfirmed automatic checks do not interrupt the player");
  console.log("update_hardening: PASS (six-language uncertainty, stable promotion, unavailable notes and manual/automatic checks)");
})().catch(error => { console.error(error); process.exitCode = 1; });
