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
  fromNexus: () => false, I18N: i18n, QQ_GROUP: "", BILI: "",
  window: { PG_CHANGELOG: [{ version: "0.40.13", date: "2026-11-01", notes: { en: ["Release"] } }] },
  noteHTML: v => String(v), lineFor: info => info.lines[0], LINE_IDS: ["auto", "github"],
  fmtDate: String, fmtBytes: String, REPO: "https://github.com/example/project",
  dlg: null, store: { set() {} }, renderTopbar() {}, renderPage() {},
  RT: { update: { check: async options => {
    context.options = options;
    throw { code: "updateUnconfirmed", tried: ["cdn"] };
  } } },
};
vm.createContext(context);
vm.runInContext(section("  function aboutHTML()", "  // ---------- Update flow") +
  section("  const versionParts", "  // The lines") +
  section("  function updateHTML()", "  // Asks for the older version") +
  section("  function helpMenuHTML()", "  function shortcutsDialog()"), context);
vm.runInContext(section("  function compState(", "  // ---------- Fun features"), context);
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
// The desktop manifest identifies this package even when the game is closed or running a different mod.
for (const lang of ["zh", "en"]) {
  i18n.set(lang);
  context.S.expectedBuild = "v0.40.13-beta-4";
  context.S.modVersion = "v0.40.12";
  context.ui.update = { phase: "latest", info: { latest: true, version: "0.40.13" } };
  assert(context.aboutHTML().includes("v0.40.13-beta-4"), "About lost the installed build");
  assert(context.helpMenuHTML().includes("v0.40.13-beta-4"), "Help lost the installed build");
  const history = context.releaseHistoryHTML();
  const currentChip = i18n.t("update.history.current");
  assert(history.indexOf("v0.40.13-beta-4") >= 0 && history.indexOf(currentChip) < history.indexOf("v0.40.13</strong>"));
  assert.equal(history.split(currentChip).length, 2, "only one installed version");
  assert(!history.includes("v0.40.12") && !context.aboutHTML().includes("v0.40.12"));
  assert(context.updateHTML().includes(i18n.t("update.previewInstalled", { v: "0.40.13-beta-4" })));
  context.ui.update = { phase: "available", line: "auto", info: { version: "0.40.14", date: "", size: 1, notes: [], lines: [{ id: "github", ms: 1 }] } };
  assert(context.updateHTML().includes(i18n.t("update.available.meta", { date: "", size: "1", current: "0.40.13-beta-4" })));
  context.ui.update.phase = "done";
  assert(context.updateHTML().includes(i18n.t("update.done.body", { v: "0.40.14" })), "completion identifies the installed update target");
  context.S.expectedBuild = "v0.40.13";
  context.ui.update = { phase: "latest" };
  assert(context.aboutHTML().includes(i18n.t("about.stableChannel")));
  assert(context.updateHTML().includes(i18n.t("update.latest.body", { v: "0.40.13" })));
  assert(!context.releaseHistoryHTML().includes("beta-") && context.releaseHistoryHTML().includes(currentChip));
  for (const code of ["offline", "updateUnconfirmed"]) {
    context.ui.update = { phase: "error", error: { code, tried: ["cdn"] } };
    const error = context.updateHTML();
    assert(error.includes(i18n.t("update.installedVersion", { v: "0.40.13" })));
    assert(!error.includes("v0.40.12"), "update errors must report the assistant version, not the running mod");
  }
  delete context.S.expectedBuild;
  assert(context.helpMenuHTML().includes("v0.40.13"), "older hosts fall back to app version");
}
vm.runInContext(fs.readFileSync(path.join(__dirname, "prototype/preview-notes.js"), "utf8"), context);
context.S.appVersion = "0.40.18";
context.S.expectedBuild = "v0.40.18-beta-6";
context.window.PG_CHANGELOG = [{version: "0.40.18", date: "2026-11-20", notes: {zh: ["STABLE_HISTORY"], en: ["STABLE_HISTORY"]}}];
for (const lang of ["zh", "en"]) {
  i18n.set(lang);
  context.ui.update = { phase: "available", line: "auto", info: {
    version: "0.40.18", currentBuild: context.S.expectedBuild, switchToStable: true, date: "", size: 1,
    lines: [{id: "github", ms: 1}], notes: ["TARGET_RELEASE_ONLY"],
  }};
  const modal = context.updateHTML();
  const issueIds = [22, 21, 19, 18, 17, 16, 15, 14, 13, 12, 8];
  for (const n of issueIds) assert(modal.includes(context.REPO + "/issues/" + n), "missing issue " + n);
  assert(modal.includes("0.01") && modal.includes("65"));
  const detailStart = modal.indexOf('<details class="release-history preview-details">');
  assert(detailStart > 0 && modal.indexOf("/issues/22") > detailStart, "issue references belong in the collapsed detail");
  const bulletin = modal.slice(modal.indexOf('<article class="installed-notes">'), detailStart);
  assert.equal((bulletin.match(/class="preview-group"/g) || []).length, 3);
  assert.equal((bulletin.match(/<li>/g) || []).length, 9, "one player-facing point per topic");
  for (const section of ["added", "combat", "fixes"]) assert(bulletin.includes(i18n.t("update.group." + section)));
  assert(!bulletin.includes("/issues/") && !bulletin.includes("0.01") && bulletin.includes("65"));
  const stableNotes = modal.indexOf('<details class="release-history target-notes">');
  assert(stableNotes > modal.indexOf("/issues/22") && modal.indexOf("TARGET_RELEASE_ONLY") > stableNotes);
  assert(context.aboutHTML().includes("/issues/22") && context.releaseHistoryHTML().includes("/issues/21"));
  context.ui.update = {phase: "error", error: {code: "offline", tried: []}};
  assert(context.updateHTML().includes("/issues/19"), "installed notes must be readable offline");
  context.ui.update = {phase: "checking"};
  assert(context.updateHTML().includes("/issues/14"));
  context.ui.update = {phase: "latest"};
  assert(context.updateHTML().includes("/issues/17"));
  context.S.expectedBuild = "v0.40.18-beta-2";
  assert(!context.aboutHTML().includes("/issues/22") && context.aboutHTML().includes("/issues/17"), "older builds must not claim a later fix");
  context.S.expectedBuild = "v0.40.18";
  assert(!context.updateHTML().includes("/issues/22") && context.updateHTML().includes("STABLE_HISTORY"));
  context.S.expectedBuild = "v0.40.18-beta-6";
}
(async () => {
  context.S.components = [{ id: "game", ok: true }, { id: "mod", ok: false, present: true, detail: "v0.40.24" }];
  context.S.gamePath = "C:/Test Game";
  context.RT.setup = { uninstall: async selected => { context.selectedUninstallPath = selected; return { backup: "C:/Backups/old-scripts" }; } };
  context.openDialog = (kind, html) => { context.dlg = { kind }; context.gameDialog = html; };
  context.setDialog = html => { context.gameDialog = html; };
  context.toast = () => {};
  for (const lang of ["zh", "en"]) {
    i18n.set(lang);
    assert(context.componentsHTML(true).includes('data-action="uninstall-components"'));
    assert(!context.componentsHTML().includes('data-action="uninstall-components"'), "onboarding stays focused on installation");
    context.S.gameRunning = true;
    context.openUninstall();
    assert(context.gameDialog.includes(i18n.t("comp.uninstall.closeGame")));
    assert(/data-action="uninstall-confirm" disabled/.test(context.gameDialog));
    await context.confirmUninstall();
    assert.equal(context.selectedUninstallPath, undefined);
    context.S.gameRunning = false;
    const uninstall = context.confirmUninstall();
    assert(context.gameDialog.includes(i18n.t("comp.uninstall.busy")) && context.gameDialog.includes(i18n.t("common.close")));
    await uninstall;
    assert.equal(context.selectedUninstallPath, context.S.gamePath);
    assert(context.gameDialog.includes("C:/Backups/old-scripts") && context.gameDialog.includes(i18n.t("comp.uninstall.done")));
    delete context.selectedUninstallPath;
  }
  context.dlg = null;
  context.ui.update = { phase: "idle" };
  await context.checkUpdate();
  assert.equal(context.ui.update.error.code, "updateUnconfirmed");
  assert.equal(context.options.silent, false);
  await context.checkUpdate({ silent: true });
  assert.equal(context.options.silent, true);
  assert.equal(context.ui.update.phase, "idle", "unconfirmed automatic checks do not interrupt the player");
  console.log("update_hardening: PASS (six-language uncertainty, stable promotion, unavailable notes and manual/automatic checks and uninstall confirmation)");
})().catch(error => { console.error(error); process.exitCode = 1; });
