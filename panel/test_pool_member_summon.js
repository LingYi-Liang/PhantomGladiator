const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = fs.readFileSync(__dirname + '/prototype/app.js', 'utf8');
const pool = { id: 'pool-test', team: 'red', count: 7, unit_ids: ['alpha', 'beta'] };
const stored = new Map(), sent = [];
let ready = true, cleanup = '', rejectSave = false, release;
const c = {
  ui: { busy: new Set(), poolMemberCounts: new Map() },
  S: { poolStatus: { scope: 'fixture' }, summonLimits: { alpha: 100, beta: 2 }, summonQueue: { ready: true, on: false } },
  RT: { poolUnitId: value => value, ready: () => ready, demo: false },
  byId: new Map([['alpha', { name: 'Alpha' }], ['beta', { name: 'Beta' }]]),
  selectedPool: () => pool, t: key => key, cleanupBlocker: () => cleanup,
  store: { get: (key, fallback) => stored.get(key) ?? fallback, set: (key, value) => { if (!rejectSave) stored.set(key, JSON.parse(JSON.stringify(value))); } },
  $: () => null, $$: () => [], toast() {}, renderPoolSummon() {},
  summon: async (...args) => { sent.push(args); if (release !== undefined) await new Promise(done => release = done); },
};
vm.createContext(c);
const segment = (a, b) => source.slice(source.indexOf(a), source.indexOf(b, source.indexOf(a)));
vm.runInContext(segment('  const poolMemberIds =', '  // Units a pool can hold:'), c);
c.poolMemberCount = vm.runInContext('poolMemberCount', c);
vm.runInContext(segment('  const poolRoom =', '  function renderPoolSummon()'), c);
vm.runInContext(segment('  async function summonPoolMember(', '  function betaDialogHTML()'), c);
(async () => {
  await c.summonPoolMember('alpha', pool.id, 'fixture'); assert.deepEqual(sent.pop(), ['alpha', 'red', 7]);
  await c.summonPoolMember('beta', pool.id, 'fixture'); assert.deepEqual(sent.pop(), ['beta', 'red', 2]);
  assert(c.savePoolMemberCount(pool, 'beta', '1'));
  await c.summonPoolMember('beta', pool.id, 'fixture'); assert.deepEqual(sent.pop(), ['beta', 'red', 1]);
  assert.equal(pool.count, 7, 'per-card counts must not change the random pool count');
  c.ui.poolMemberCounts = new Map(Object.entries(stored.get('poolMemberCounts')));
  await c.summonPoolMember('beta', pool.id, 'fixture'); assert.deepEqual(sent.pop(), ['beta', 'red', 1]);
  assert(c.savePoolMemberCount(pool, 'beta', '')); assert.equal(c.poolMemberCount(pool, 'beta'), 2);
  assert(c.savePoolMemberCount(pool, 'alpha', '3'));
  for (const value of ['0', '101', '1.5', '-1', '1e2']) assert(!c.savePoolMemberCount(pool, 'alpha', value));
  rejectSave = true; assert(!c.savePoolMemberCount(pool, 'alpha', '5')); assert.equal(c.poolMemberCount(pool, 'alpha'), 3); rejectSave = false;
  c.S.poolStatus.scope = 'another-runtime'; assert.equal(c.poolMemberCount(pool, 'alpha'), 7); c.S.poolStatus.scope = 'fixture';
  for (const [id, poolId, scope] of [['missing', pool.id, 'fixture'], ['alpha', 'old-pool', 'fixture'], ['alpha', pool.id, 'old-runtime']]) await c.summonPoolMember(id, poolId, scope);
  ready = false; await c.summonPoolMember('alpha', pool.id, 'fixture'); ready = true;
  cleanup = 'pending'; await c.summonPoolMember('alpha', pool.id, 'fixture'); cleanup = '';
  c.ui.poolDraft = {}; await c.summonPoolMember('alpha', pool.id, 'fixture'); c.ui.poolDraft = null;
  assert.equal(sent.length, 0);
  release = null; const first = c.summonPoolMember('alpha', pool.id, 'fixture');
  await c.summonPoolMember('alpha', pool.id, 'fixture'); assert.equal(sent.length, 1); release(); await first; release = undefined; sent.length = 0;
  // Use the actual shared summon entry for queue mode: one explicit unit, never a random draw.
  vm.runInContext(segment('  async function summon(id =', '  async function run('), c);
  c.RT.command = async (action, payload) => { sent.push({ action, payload }); return { status: 'succeeded' }; };
  c.S.summonQueue.on = true;
  await c.summonPoolMember('alpha', pool.id, 'fixture');
  assert.equal(JSON.stringify(sent.pop()), JSON.stringify({ action: 'queue_spawn', payload: { unit_id: 'alpha', team: 'red', count: 3 } }));
  console.log('pool_member_summon: PASS (inherit/custom/reset, limit, durable readback, scope, stale/busy gates and shared queue route)');
})().catch(error => { console.error(error); process.exitCode = 1; });
