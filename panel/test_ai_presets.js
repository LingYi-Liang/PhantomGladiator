const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const i18n = require("./test_i18n_runtime")();
const uiDir = path.join(__dirname, "prototype");
const app = fs.readFileSync(path.join(uiDir, "app.js"), "utf8");
function part(start, end) {
  const from = app.indexOf(start), to = app.indexOf(end, from + start.length);
  assert(from >= 0 && to > from, start);
  return app.slice(from, to);
}
const previous = {"近距离进攻概率": 0.25, "立回-近距离闪避权重": 0};
const ui = {aiValues: {...previous}};
let html, sent;
const context = vm.createContext({
  window: {}, ui, I18N: i18n, t: (key, args) => i18n.t(key, args), esc: String, icon: () => "",
  openDialog: (_, body) => { html = body; }, closeDialog() {}, renderAi() {},
  async run(action, {payload}) { assert.equal(action, "set_ai_params"); sent = payload.values; return {status: "succeeded"}; },
});
vm.runInContext(fs.readFileSync(path.join(uiDir, "ai-params.js"), "utf8"), context);
vm.runInContext(part("  const AI_GROUPS =", "  function renderAi()") +
  "\nthis.choose = ({" + part('    "ai-preset":', '    "boss-combos":') + '})["ai-preset"];', context);

async function check() {
  const fields = context.window.PG_AI_PARAMS;
  i18n.set("zh");
  context.aiDialog();
  assert.equal(ui.aiDraft["立回-近距离闪避权重"], "0", "opening an old manual save must not change it");
  context.choose({dataset: {}});
  const all = {...ui.aiDraft};
  for (const key of ["近距离进攻概率", "中距离进攻概率", "远距离进攻概率", "重新规划-进攻欲望"]) assert.equal(all[key], "1", key);
  assert.equal(all["立回-近距离闪避权重"], "500", "full attack must not turn off close dodges");
  assert.equal(all["立回-中距离闪避权重"], "300", "full attack must not turn off mid-range dodges");
  assert.equal(all["玩家开始近战攻击-闪避权重"], "200");
  assert.equal(all["远程攻击发射-闪避权重"], "500");
  for (const event of ["玩家开始近战攻击", "远程攻击发射"]) {
    const dodge = Number(all[event + "-闪避权重"]);
    const block = Number(all[event + "-格挡权重"]), counter = Number(all[event + "-针对动作权重"]);
    assert(block > 0 && counter > 0 && dodge >= block + counter, event);
    assert.equal(all[event + "-无行为权重"], "0");
  }
  assert(Number(all["闪避敌人近战攻击的距离"]) > 0 && Number(all["玩家开始近战攻击-闪避距离"]) > 0);
  assert.equal(all["无视子弹开始事件"], "0");
  assert(Number(all["立回-退出立回距离"]) < Number(all["立回-近距离分界线"]));
  assert.deepEqual(Object.keys(all).sort(), Array.from(fields, field => field.name).sort());
  assert.deepEqual(ui.aiValues, previous, "preview must not replace the last saved settings");
  assert.equal(sent, undefined);
  assert(html.includes(">全部拉满</button>"));
  i18n.set("en"); context.aiDialog();
  assert(html.includes(">Max everything</button>"));

  ui.aiDraft = {"近距离进攻概率": "0.25"};
  context.choose({dataset: {group: "movement"}});
  assert.equal(ui.aiDraft["近距离进攻概率"], "0.25", "a group button must not replace another group's values");
  const movement = Array.from(fields).filter(field => field.group === "movement").map(field => field.name);
  assert.deepEqual(Object.keys(ui.aiDraft).sort(), [...movement, "近距离进攻概率"].sort());
  for (const group of ["attack", "range", "defense"]) context.choose({dataset: {group}});
  assert.deepEqual({...ui.aiDraft}, all, "combining the four groups is the same full preset");
  ui.aiDraft["玩家开始近战攻击-闪避权重"] = "155";
  await context.saveAi();
  assert.equal(sent["玩家开始近战攻击-闪避权重"], 155, "manual change after preview");
  assert.equal(sent["立回-近距离闪避权重"], 500);
  assert.equal(sent["中距离进攻概率"], 1);
  assert.equal(sent["无视子弹开始事件"], 0);
  assert.equal(Object.keys(sent).length, fields.length);
  context.aiDialog();
  assert.equal(ui.aiDraft["玩家开始近战攻击-闪避权重"], "155", "reopen the saved values");
  console.log("PASS full AI preset, scoped group buttons, manual editing and combined numeric payload");
}
check().catch(error => { console.error(error); process.exitCode = 1; });
