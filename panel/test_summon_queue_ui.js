const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const app = readFileSync(path.join(__dirname, "prototype", "app.js"), "utf8");
function section(start, end) {
  const first = app.indexOf(start);
  const last = app.indexOf(end, first + 1);
  assert(first >= 0 && last > first);
  return app.slice(first, last);
}

const calls = [], notices = [];
let connected = true;
const S = { summonQueue: { supported: true, ready: true, on: false }, statMatch: {} };
const ui = { busy: new Set(), selectedId: "unit-a", team: "blue", count: 1, roster: { blue: {} } };
const context = {
  S, ui, esc: text => String(text ?? ""),
  RT: { ready: () => true, online: () => connected,
    command: async (action, payload) => {
      calls.push({ action, payload });
      return action === "queue_spawn" ? { status: "pending" } : { status: "succeeded", spawned: 1 };
    },
  },
  byId: new Map([["unit-a", { name: "甲" }]]),
  cleanupBlocker: () => "", renderSelection() {}, renderDock() {},
  toast: event => notices.push(event), t: key => key, teamName: team => team, matchNote: () => "",
};
vm.createContext(context);
vm.runInContext(section("  function summonQueueSettingsHTML()", "  function renderSummonQueueSettings()") +
  section("  async function summon(", "  async function run("), context);

(async () => {
  assert.match(context.summonQueueSettingsHTML(), /aria-checked="false"/);
  assert.doesNotMatch(context.summonQueueSettingsHTML(), /取消待执行|disabled/);
  connected = false;
  assert.match(context.summonQueueSettingsHTML(), /启动游戏并进入地图后可开启。/);
  connected = true;
  S.summonQueue.supported = false;
  assert.match(context.summonQueueSettingsHTML(), /请更新并重载模组。/);
  S.summonQueue.supported = true;
  S.summonQueue.ready = false;
  assert.match(context.summonQueueSettingsHTML(), /进入可操作的地图后可开启。/);
  assert.match(context.summonQueueSettingsHTML(), /disabled/);
  S.summonQueue.ready = true;
  assert.match(section("  function queuePageHTML()", "  function poolList()"), /id="summon-queue-settings"/);
  assert.doesNotMatch(section("  function settingsHTML()", "  function aboutHTML()"), /id="summon-queue-settings"/);
  const rail = readFileSync(path.join(__dirname, "prototype", "index.html"), "utf8");
  assert.match(rail, /<details id="arena-extra"[\s\S]*data-page="queue"[\s\S]*data-page="pool"/);

  await context.summon();
  assert.equal(calls[0].action, "spawn");
  assert.equal(ui.roster.blue["unit-a"], 1);

  S.summonQueue = { supported: true, on: true, waiting: 14, transit: 2, completed: 5, message: "读回完成" };
  const html = context.summonQueueSettingsHTML();
  assert.match(html, /aria-checked="true"/);
  assert.match(html, /待执行 14 · 待游戏接收 2 · 已完成 5/);
  assert.match(html, /data-action="cancel-summon-queue"/);
  await Promise.all(Array.from({ length: 100 }, () => context.summon("unit-a", "blue", 1)));
  assert.equal(calls.length, 101);
  assert(calls.slice(1).every(row => row.action === "queue_spawn" && row.payload.unit_id === "unit-a"));
  assert.equal(ui.roster.blue["unit-a"], 1, "enqueue receipts must not increase the spawned roster");
  assert(!ui.busy.has("spawn"));
  assert.equal(notices.at(-1).title, "已提交排队");
  console.log("summon_queue_ui: default summon preserved; settings placement; 100 enqueue submissions without invented spawn counts");
})().catch(error => { console.error(error); process.exitCode = 1; });
