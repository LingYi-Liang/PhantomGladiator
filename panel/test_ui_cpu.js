const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const args = Object.fromEntries(process.argv.filter(a => a.startsWith('--')).map(a => a.slice(2).split('=')));
const app = fs.readFileSync(args.app || __dirname + '/prototype/app.js', 'utf8');
const runtime = fs.readFileSync(args.runtime || __dirname + '/prototype/real-runtime.js', 'utf8');
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };

async function jobBatch() {
  const calls = { topbar: 0, history: 0, dock: 0, selection: 0 }, ui = { page: 'arena' };
  let subscribed;
  const c = { RT: { subscribe(fn) { subscribed = fn; } }, S: {}, ui, dlg: { kind: 'history' }, Promise,
    renderTopbar: () => calls.topbar++, historyHTML: () => { calls.history++; return 'history'; }, setDialog: () => {},
    renderDock: () => calls.dock++, renderSelection: () => calls.selection++ };
  vm.runInNewContext(app.slice(app.indexOf('  // ---------- Runtime events ----------'), app.indexOf('  // A codex bust that fails')), c);
  for (let i = 0; i < 100; i++) subscribed({ type: 'job', job: { action: i % 2 ? 'toggle_spectator' : 'select_unit' } });
  await flush();
  console.log('MEASURE one 100-job status batch: ' + JSON.stringify(calls));
  if (!args.measure) assert.deepEqual(calls, { topbar: 1, history: 1, dock: 1, selection: 1 }, 'one poll may change many jobs but needs only one rendering pass');
  subscribed({ type: 'job', job: { action: 'spawn' } });c.dlg = { kind: 'confirm' };ui.page = 'settings';
  await flush();
  assert.equal(calls.history, args.measure ? 101 : 1, 'deferred repaint must recheck the currently open dialog');
  if (!args.measure) {
    assert.equal(calls.dock, 1);assert.equal(calls.selection, 1);
    subscribed({ type: 'job', job: { action: 'select_unit' } });await flush();assert.equal(calls.selection, 2);
  }
}

async function signatureCost() {
  let serial = 0, now = 1000000, bytes = 0, serializations = 0;
  const timers = new Map(), events = [];
  const status = { csrf_token: 'fixture', local_audio: { supported: true, revision: 1, volume: 50, message: '等待开战', importing: false,
    bosses: Array.from({ length: 89 }, (_, i) => ({ id: 'BP_Monster_' + i, name: '测试单位' + i })),
    mapping: Object.fromEntries(Array.from({ length: 25 }, (_, i) => ['BP_Monster_' + i, { name: 'music-' + i + '.mp3', seconds: 180 }])) },
    game: { online: true, ready: true, game_session: 'fixture', values: { unit_rules_supported: 'true', unit_keys_revision: '1',
      track_targets: Array.from({ length: 100 }, (_, i) => i + ':BP_Monster_' + i + ':blue').join(';') } }, queue: [], catalog: { total: 191 } };
  const c = { window: {}, document: { documentElement: { lang: 'zh' } }, AbortController, Date: { now: () => now },
    JSON: { parse: JSON.parse, stringify(value) { serializations++; const result = JSON.stringify(value);bytes += result?.length || 0;return result; } },
    setTimeout(fn, delay) { const id = ++serial;timers.set(id, { fn, delay });return id; }, clearTimeout(id) { timers.delete(id); },
    fetch: async path => ({ ok: true, json: async () => path.startsWith('/api/status') ? structuredClone(status) : {} }) };
  vm.runInNewContext(runtime, c);await flush();
  c.window.PGRuntime.subscribe(e => events.push(e));bytes = serializations = 0;
  async function poll() {
    const timer = [...timers].find(([, t]) => t.delay === 500);assert(timer);timers.delete(timer[0]);now += 500;timer[1].fn();await flush();
  }
  for (let i = 0; i < 100; i++) await poll();
  console.log('MEASURE 100 unchanged polls: JSON calls=' + serializations + ' chars=' + bytes);
  assert.equal(events.filter(e => e.type === 'state').length, 0, 'unchanged values must not repaint controls');
  if (!args.measure && args.case !== 'capability') assert(bytes < 2000000 && serializations < 3000, 'compare current signatures once without serializing previous snapshots or encoded nested strings');
  status.game.values.execution_minions_rule_supported = 'true';await poll();
  if (!args.measure) assert(events.some(e => e.parts?.has('grid')), 'new execution capability must refresh card controls without requiring unrelated rules to change');
  events.length = 0;status.local_audio.message = '已导入本地音乐';await poll();
  assert(events.some(e => e.parts?.has('battleMusic')), 'local music progress remains visible on the next normal poll');
  events.length = 0;status.game.values.track_target = '99';await poll();
  assert(events.some(e => e.parts?.has('view')), 'target changes still repaint the view controls immediately');
  events.length = 0;
  status.queue = Array.from({ length: 100 }, (_, i) => ({ id: i + 1, action: 'spawn', status: 'succeeded',
    payload: { unit_id: '/Game/BP_Monster_' + i + '.BP_Monster_' + i + '_C', count: 1, team: 'blue' }, completed: 1000 }));
  await poll();
  assert.equal(events.filter(e => e.type === 'job').length, 100, 'render batching must preserve all individual job receipts');
}
(async () => { if (!args.case || args.case === 'jobs') await jobBatch();if (!args.case || args.case !== 'jobs') await signatureCost();console.log('ui_cpu: PASS job render coalescing, change detection and capability updates; no game accessed'); })()
  .catch(error => { console.error(error);process.exitCode = 1; });
