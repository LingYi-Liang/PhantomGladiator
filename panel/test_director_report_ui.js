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
  locale: () => "en-US", fmtNum: String, avatarArt: () => "", artClass: () => "", esc: value => String(value ?? "").replaceAll("<", "&lt;").replaceAll(">", "&gt;"),
  byId: new Map([["BP_Boss_Blue", { name: "生死对照" }]]),
  RT: { ready: () => true, online: () => true }, ui: { busy: new Set(), roster: { blue: { One: 1, Two: 1, Three: 2 } } },
  icon: () => "", keyCap: () => "", keyLineHTML: () => "",
  S: { blue: 1, red: 1, frozen: false, keys: {}, cinemaKeysSupported: true,
    cinema: { supported: true, active: false, shot: "" }, battleHud: { supported: true, mode: "compact" } },
};
vm.createContext(context);
vm.runInContext(section("  const MATCH_STATS =", "  function selfieRow()"), context);
vm.runInContext(section("  function attackFlashRows()", "  // 时停 (toggle_time_stop"), context);
vm.runInContext(section("  function executionAppearanceRow()", "  // ---------- Commands ----------"), context);
vm.runInContext(section("  function rosterAvailable()", "  // 不倒下 (set_team_immortal"), context);
const report = { schema: 1, build: "beta", saveNg: 3, map: "<script>", levelMode: "HOME", defaultDifficulty: "NORMAL", units: [
  { team: "blue", classPath: "/Game/BP_Boss_Blue.BP_Boss_Blue_C", slot: 1, combatLevel: 18, ng: 2, difficulty: "Hard", storyLink: "skip",
    stats: { Health_Max: { current: 1500, base: 1250 }, Attack: {current: 43.25, base: 40}, ShachiAttack: { current: 0 } },
    levelCurve: { Attack: { level: 18, raw: 40, adjusted: 43.25, mods: [{source: "difficulty", type: "add", value: 3.25}] } } },
  { team: "red", classPath: "/Game/Other.Other_C", slot: 1, stats: { Health_Max: { current: 2400 } } },
], damageFormula: { npcPhysicalBase: "known", npcShachiBase: "known", examples: { blue: { attackerSlot: 1, defenderSlot: 1, npcPhysicalBase: 165 } } } };
for (const lang of ["zh", "en"]) {
  i18n.set(lang);
  context.S.executionAppearance = { supported: true, on: false };
  let appearance = context.executionAppearanceRow();
  assert(appearance.includes(i18n.t("view.execAppearance.hint")) && appearance.includes('aria-checked="false"'));
  context.S.executionAppearance.on = true;
  appearance = context.executionAppearanceRow();
  assert(appearance.includes('aria-checked="true"') && appearance.includes('aria-describedby="exec-appearance-hint"'));
  context.S.arenaRosterSession = "active";
  context.S.arenaRosterRevision = 1;
  context.S.fight = "idle";
  const roster = {team:"blue",removed:new Set(),feedback:"",data:{ready:true,editable:true,session:"active",units:[
    {id:"A1",team:"blue",path:"/Game/BP_Boss_Blue.BP_Boss_Blue_C",ordinal:1,state:"alive",hp:500},
    {id:"A2",team:"blue",path:"/Game/BP_Boss_Blue.BP_Boss_Blue_C",ordinal:2,state:"down",hp:0},
    {id:"A3",team:"red",path:"/Game/BP_Boss_Red.BP_Boss_Red_C",ordinal:1,state:"alive",hp:510}
  ]}};
  const rosterMarkup = context.arenaRosterHTML(roster);
  assert(rosterMarkup.includes(i18n.t("field.rosterManage")));
  assert(rosterMarkup.includes("生死对照 #1") && rosterMarkup.includes("生死对照 #2"));
  assert(rosterMarkup.includes('data-id="A2"') && !rosterMarkup.includes('data-id="A3"'));
  assert(context.rosterHTML("blue").includes('data-action="arena-roster-open"'));
  context.S.fight = "fighting";
  assert.equal((context.arenaRosterHTML(roster).match(/ disabled>/g) || []).length, 2);
  roster.removed.add("A2");
  assert(!context.arenaRosterHTML(roster).includes('data-id="A2"'));
  context.S.arenaRosterSession = "other";
  assert(!context.arenaRosterHTML(roster).includes('data-id="A1"'));
  const html = context.matchReportHTML(report, "empty");
  const note = context.reportCopyText(report);
  assert(html.includes("生死对照") && html.includes("&lt;script&gt;") && !html.includes("<script>"));
  assert(html.includes("1,250") && html.includes("43.25") && html.includes("2400".replace(/(\d)(\d{3})/,"$1,$2")));
  assert(html.includes(i18n.t("matchReport.unknown")) && html.includes(">0<"), "unread and genuine zero are distinct");
  assert(note.includes(i18n.t("matchReport.storyLink")) && note.includes(i18n.t("matchReport.storyLink.skip")));
  assert(note.includes(i18n.t("matchReport.ngN", {n: 2})) && note.includes("165") && note.includes("1250".replace(/(\d)(\d{3})/,"$1,$2")));
  assert(!html.includes("matchReport."));
  assert(context.matchReportHTML(null, "empty").includes(i18n.t("matchReport.empty")));
  context.S.attackFlash = { supported: true, red: true, blue: false };
  const flashes = context.attackFlashRows();
  const buttonFor = color => flashes.match(new RegExp("<button[^>]+data-color=\"" + color + "\"[^>]*>"))?.[0] || "";
  assert(buttonFor("red").includes('aria-checked="true"') && buttonFor("red").includes(i18n.t("view.attackFlash.red")));
  assert(buttonFor("blue").includes('aria-checked="false"') && buttonFor("blue").includes(i18n.t("view.attackFlash.blue")));
  context.S.attackFlash.supported = false;
  assert.equal((context.attackFlashRows().match(/disabled>/g) || []).length, 2);
}
i18n.set("zh");
assert(context.directorRows().includes("电影运镜") && context.directorRows().includes("始终紧凑"));
context.S.cinema.active = true;
context.S.cinema.shot = "aerial";
assert(context.directorRows().includes("高位推近"));
context.S.cinema.supported = false;
assert(!context.directorRows().includes("电影运镜"));
console.log("director report UI: PASS (both teams, numeric provenance, escaped labels, creator copy, cinema, HUD and independent attack flash states)");
