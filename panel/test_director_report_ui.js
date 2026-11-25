const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const i18n = require("./test_i18n_runtime")();
const app = fs.readFileSync(__dirname + "/prototype/app.js", "utf8");
const section = (start, end) => {
  const a = app.indexOf(start), b = app.indexOf(end, a + 1);
  assert(a >= 0 && b > a);
  return app.slice(a, b);
};
const context = {
  t: (key, params) => i18n.t(key, params), teamName: team => i18n.t("team." + team), fmtClock: String,
  locale: () => "en-US", esc: value => String(value ?? "").replaceAll("<", "&lt;").replaceAll(">", "&gt;"),
  byId: new Map([["BP_Boss_Blue", { name: "生死对照" }]]),
  RT: { ready: () => true, online: () => true }, ui: { busy: new Set() }, icon: () => "", keyCap: () => "", keyLineHTML: () => "",
  S: { blue: 1, red: 1, frozen: false, keys: {}, cinemaKeysSupported: true,
    cinema: { supported: true, active: false, shot: "" }, battleHud: { supported: true, mode: "compact" } },
};
vm.createContext(context);
vm.runInContext(section("  const MATCH_STATS =", "  function selfieRow()"), context);
vm.runInContext(section("  function directorRows()", "  // 时停 (toggle_time_stop"), context);
const report = { schema: 1, build: "beta", saveNg: 3, map: "<script>", levelMode: "HOME", defaultDifficulty: "NORMAL", units: [
  { team: "blue", classPath: "/Game/BP_Boss_Blue.BP_Boss_Blue_C", slot: 1, combatLevel: 18, ng: 2, difficulty: "Hard", storyLink: "skip",
    stats: { Health_Max: { current: 1500, base: 1250 }, Attack: {current: 43.25, base: 40}, ShachiAttack: { current: 0 } },
    levelCurve: { Attack: { level: 18, raw: 40, adjusted: 43.25, mods: [{source: "difficulty", type: "add", value: 3.25}] } } },
  { team: "red", classPath: "/Game/Other.Other_C", slot: 1, stats: { Health_Max: { current: 2400 } } },
], damageFormula: { npcPhysicalBase: "known", npcShachiBase: "known", examples: { blue: { attackerSlot: 1, defenderSlot: 1, npcPhysicalBase: 165 } } } };
for (const lang of ["zh", "en"]) {
  i18n.set(lang);
  const html = context.matchReportHTML(report, "empty");
  const note = context.reportCopyText(report);
  assert(html.includes("生死对照") && html.includes("&lt;script&gt;") && !html.includes("<script>"));
  assert(html.includes("1,250") && html.includes("43.25") && html.includes("2400".replace(/(\d)(\d{3})/,"$1,$2")));
  assert(html.includes(i18n.t("matchReport.unknown")) && html.includes(">0<"), "unread and genuine zero are distinct");
  assert(note.includes(i18n.t("matchReport.storyLink")) && note.includes(i18n.t("matchReport.storyLink.skip")));
  assert(note.includes(i18n.t("matchReport.ngN", {n: 2})) && note.includes("165") && note.includes("1250".replace(/(\d)(\d{3})/,"$1,$2")));
  assert(!html.includes("matchReport."));
  assert(context.matchReportHTML(null, "empty").includes(i18n.t("matchReport.empty")));
}
i18n.set("zh");
assert(context.directorRows().includes("电影运镜") && context.directorRows().includes("始终紧凑"));
context.S.cinema.active = true;
context.S.cinema.shot = "aerial";
assert(context.directorRows().includes("高位推近"));
context.S.cinema.supported = false;
assert(!context.directorRows().includes("电影运镜"));
console.log("director report UI: PASS (both teams, numeric provenance, escaped labels, creator copy, cinema and HUD states)");
