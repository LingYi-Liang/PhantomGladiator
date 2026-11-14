const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const app = fs.readFileSync(path.join(__dirname, 'prototype/app.js'), 'utf8');
const start = app.indexOf('  const UNIT_RULE_OF =');
const end = app.indexOf('  function cardHTML(', start);
assert(start >= 0 && end > start);
const calls = [];
const context = {
  S: { unitRulesSupported: true, remoteReflectSupported: true, unitRules: {} },
  ui: { busy: new Set(), selectedId: 'BP_Monster_JingYe' },
  RT: { online: () => true }, t: key => key,
  esc: value => String(value).replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;'),
  run: (action, options) => calls.push({ action, ...options }), renderGrid() {},
};
vm.createContext(context);
vm.runInContext(app.slice(start, end), context);
const unitContext = { window: {} };
vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'prototype/units.js'), 'utf8'), unitContext);
for (const unit of unitContext.window.PG_UNITS) {
  const html = context.unitRuleHTML(unit);
  assert.equal((html.match(/data-rule="remote_reflect"/g) || []).length, 1, unit.id);
  assert(html.includes('aria-checked="false"') && html.includes('下次召唤生效'), unit.id);
}
const jingye = { id: 'BP_Monster_JingYe', name: '荆野' };
let html = context.unitRuleHTML(jingye);
assert(html.includes('物理伤害与出血积累') && html.includes('原版已排除飞行弹丸'));
context.toggleUnitRule(jingye.id, 'remote_reflect');
assert.equal(calls[0].action, 'set_unit_rule');
assert.equal(JSON.stringify(calls[0].payload), JSON.stringify({ unit: jingye.id, rule: 'remote_reflect', value: 'off' }));
context.S.unitRules[jingye.id] = { remote_reflect: 'off' };
html = context.unitRuleHTML(jingye);
assert(html.includes('aria-checked="true"') && html.includes('远程反伤：已关闭'));
assert(context.unitRuleHTML({ id: 'BP_Monster_XuKong', name: '虚空' }).includes('data-rule="phantom"'));
context.ui.busy.add('set_unit_rule');
assert(context.unitRuleHTML(jingye).includes('disabled'));
context.ui.busy.clear();
context.S.remoteReflectSupported = false;
assert.equal(context.unitRuleHTML(jingye), '', 'an older Mod must not advertise the new switch');
context.S.unitRulesSupported = false;
assert.equal(context.unitRuleHTML({ id: 'BP_Monster_XuKong', name: '虚空' }), '');
// Exercise the actual command lifecycle: the final grid must render after run() drops its busy flag.
context.S.unitRulesSupported = context.S.remoteReflectSupported = true;
context.ui.busy.clear();
context.S.unitRules = {};
context.renderDock = () => {};
context.toast = () => {};
context.reasonText = () => '';
context.dismissToast = () => {};
let resolve, sent = 0;
context.RT.command = () => { sent++; return new Promise(done => { resolve = done; }); };
let latestHTML = '';
context.renderGrid = () => { latestHTML = context.unitRuleHTML(jingye); };
const runStart = app.indexOf('  async function run(');
const runEnd = app.indexOf('  function confirmStop()', runStart);
vm.runInContext(app.slice(runStart, runEnd), context);
(async () => {
  const pending = context.toggleUnitRule(jingye.id, 'remote_reflect');
  assert(latestHTML.includes('disabled'));
  await context.toggleUnitRule(jingye.id, 'remote_reflect');
  assert.equal(sent, 1, 'rapid clicks do not enqueue a second change');
  context.S.unitRules[jingye.id] = { remote_reflect: 'off' };
  resolve({ status: 'succeeded' });
  await pending;
  assert(latestHTML.includes('已关闭') && !latestHTML.includes('disabled'), 'successful save re-enables the switch');
  const failed = context.toggleUnitRule(jingye.id, 'remote_reflect');
  resolve({ status: 'failed' });
  await failed;
  assert(latestHTML.includes('已关闭') && !latestHTML.includes('disabled'), 'failed save keeps the confirmed choice and re-enables retry');
  console.log('remote_reflect_ui: PASS (all cards, native help, command roundtrip, busy lifecycle, old-Mod capability gate)');
})().catch(error => { console.error(error); process.exitCode = 1; });
