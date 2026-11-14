const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const sourceArg = process.argv.find(arg => arg.startsWith('--source='));
const source = fs.readFileSync(sourceArg ? sourceArg.slice(9) : __dirname + '/prototype/real-runtime.js', 'utf8');
const flush = async () => { for (let i = 0; i < 35; i++) await Promise.resolve(); };
function deferred() { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; }
const response = (data, ok = true, status = 200) => ({ ok, status, json: async () => data });
function harness(post) {
  let now = 0, serial = 0;
  const timers = new Map(), requests = [], queue = [];
  const context = { window: {}, document: { documentElement: { lang: 'zh' } }, AbortController,
    Date: { now: () => now + 1000000 },
    setTimeout(fn, ms) { const id = ++serial; timers.set(id, { fn, at: now + ms }); return id; },
    clearTimeout(id) { timers.delete(id); },
    fetch(path, options) {
      requests.push({ path, options });
      if (options?.method === 'POST') return post(path, options);
      if (path.split('?')[0] === '/api/status') {
        const watched = (new URL(path, 'http://fixture')).searchParams.get('watch')?.split(',') || [];
        return Promise.resolve(response({ csrf_token: 'token', game: {
        online: true, ready: true, game_session: 'session', values: { unit_keys_revision: '1' } }, catalog: { total: 1 },
        queue: queue.slice(-100), watched_commands: watched.map(id => queue.find(q => String(q.id) === id)).filter(Boolean) }));
      }
      if (path === '/api/catalog') return Promise.resolve(response({ units: [{ internal_name: 'BP_Test', id: '/Game/BP_Test.BP_Test_C' }] }));
      return Promise.resolve(response({}));
    },
  };
  vm.runInNewContext(source, context);
  return { rt: context.window.PGRuntime, requests, queue,
    async advance(ms) {
      const end = now + ms;
      while (true) {
        const next = [...timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        timers.delete(next[0]); now = next[1].at; next[1].fn(); await flush();
      }
      now = end; await flush();
    },
  };
}
(async () => {
  for (const bodyOnly of [false, true]) {
    const pending = deferred();
    const h = harness(() => bodyOnly ? Promise.resolve({ ok: true, status: 200, json: () => pending.promise }) : pending.promise);
    await flush(); let result, failed;
    h.rt.command('spawn', { unit_id: 'BP_Test', team: 'blue', count: 1 }).then(value => { result = value; }, error => { failed = error; });
    await h.advance(15000);
    assert(result && result.status === 'uncertain' && result.code === 'submissionUnknown', 'hung command submission must return uncertainty instead of staying busy forever');
    assert.equal(failed, undefined);
    assert.equal(h.rt.jobs.length, 0, 'no synthetic job without a backend id');
    await h.advance(5000); assert.equal(h.requests.filter(r => r.options?.method === 'POST').length, 1, 'ambiguous commands must never be automatically replayed');
    pending.resolve(bodyOnly ? { id: 10 } : response({ id: 10 })); await flush();
    assert.equal(h.rt.jobs.length, 0, 'late receipt after uncertainty cannot invent a second command lifecycle');
  }
  for (const reply of [{}, { id: null }, { id: -1 }, { id: '01' }, { id: '9223372036854775808' }, { id: 9007199254740992 }]) {
    const h = harness(() => Promise.resolve(response(reply))); await flush();
    const result = await h.rt.command('queue_spawn', { unit_id: 'BP_Test', team: 'blue', count: 1 });
    assert.equal(result.status, 'uncertain'); assert.equal(result.code, 'submissionUnknown');
    assert.equal(h.rt.jobs.length, 0);
  }
  for (const post of [() => Promise.reject(new Error('connection closed')),
    () => Promise.resolve({ ok: true, status: 200, json: async () => { throw new SyntaxError('truncated JSON'); } })]) {
    const h = harness(post); await flush();
    const result = await h.rt.command('spawn', { unit_id: 'BP_Test', team: 'blue', count: 1 });
    assert.equal(result.status, 'uncertain'); assert.equal(result.code, 'submissionUnknown');
  }
  const rejected = harness(() => Promise.resolve(response({ error: 'rejected by validation' }, false, 400))); await flush();
  await assert.rejects(rejected.rt.command('start'), error => error.code === 'rejected' && error.detail === 'rejected by validation');
  const queued = harness(() => Promise.resolve(response({ id: 14 }))); await flush();
  const receipt = await queued.rt.command('queue_spawn', { unit_id: 'BP_Test', team: 'red', count: 1 });
  assert.equal(receipt.id, '14'); assert.equal(receipt.status, 'pending');
  const valid = harness(() => Promise.resolve(response({ id: 15 }))); await flush();
  const done = valid.rt.command('spawn', { unit_id: 'BP_Test', team: 'blue', count: 1 }); await flush();
  valid.queue.push({ id: 15, action: 'spawn', status: 'succeeded', spawned_count: 1, payload: {} });
  await valid.advance(500); assert.equal((await done).status, 'succeeded');
  const long = harness(() => Promise.resolve(response({ id: '9007199254740993' }))); await flush();
  const longDone = long.rt.command('start'); await flush();
  long.queue.push({ id: '9007199254740993', action: 'start', status: 'succeeded', payload: {} });
  await long.advance(500); assert.equal((await longDone).id, '9007199254740993');
  assert(long.requests.some(r => r.path === '/api/status?watch=9007199254740993'), 'string ids remain exact in watched requests');

  const history = harness(() => Promise.resolve(response({ id: 1 }))); await flush();
  const old = history.rt.command('start'); await flush();
  history.queue.push({ id: 1, action: 'start', status: 'pending', payload: {} });
  for (let id = 2; id <= 101; id++) history.queue.push({ id, action: 'select_unit', status: 'succeeded', payload: {} });
  await history.advance(500);
  assert.equal(history.rt.jobs.length, 100, 'visible history remains bounded');
  let repeatedOldUpdates = 0;
  history.rt.subscribe(e => { if (e.type === 'job' && e.job.id === '1') repeatedOldUpdates++; });
  await history.advance(500); assert.equal(repeatedOldUpdates, 0, 'waiting cache prevents repeated remapping of an evicted pending job');
  history.queue[0].status = 'succeeded'; await history.advance(500);
  assert.equal((await old).status, 'succeeded', 'a watched result is not lost behind 100 newer jobs');
  assert.equal(history.requests.filter(r => r.options?.method === 'POST').length, 1);
  assert.equal(history.rt.jobs.length, 100);

  let nextId = 0;
  const capped = harness(() => Promise.resolve(response({ id: ++nextId }))); await flush();
  const batch = Array.from({ length: 100 }, () => capped.rt.command('start')); await flush();
  await assert.rejects(capped.rt.command('start'), e => e.code === 'rejected');
  assert.equal(nextId, 100, 'excess active lifecycles are refused before POST');
  for (let id = 1; id <= 100; id++) capped.queue.push({ id, action: 'start', status: 'succeeded', payload: {} });
  await capped.advance(500); assert((await Promise.all(batch)).every(j => j.status === 'succeeded'));
  const watch = capped.requests.find(r => r.path.startsWith('/api/status?watch='));
  assert.equal(new URL(watch.path, 'http://fixture').searchParams.get('watch').split(',').length, 100);
  console.log('runtime_commands: PASS (bounded ambiguous submission, valid ids, no replay or fabricated failure, confirmed jobs preserved)');
})().catch(error => { console.error(error); process.exitCode = 1; });
