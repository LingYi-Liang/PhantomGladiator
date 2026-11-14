const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const sourceFile = process.argv.find(arg => arg.startsWith('--source='))?.slice('--source='.length);
const only = process.argv.find(arg => arg.startsWith('--case='))?.slice('--case='.length);
const source = fs.readFileSync(sourceFile || __dirname + '/prototype/real-runtime.js', 'utf8');
const flush = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const response = (data, ok = true) => ({ ok, status: ok ? 200 : 503, json: async () => data });
const status = (revision = 1, blue = 1) => ({
  csrf_token: 'token', game: { online: true, ready: true, game_session: 'session',
    values: { unit_keys_epoch: 'epoch', unit_keys_revision: String(revision), blue_count: String(blue) } },
  catalog: { total: 1 }, queue: [],
});
const catalog = code => ({ units: [{ id: '/Game/BP_Test.BP_Test_C', internal_name: 'BP_Test', spawnable: true,
  codex_entry_kind: 'primary', unit_shortcut: { key_code: code } }] });
function harness(handler) {
  let now = 0, serial = 0;
  const timers = new Map(), requests = [];
  const context = { window: {}, document: { documentElement: { lang: 'zh' } }, AbortController,
    Date: { now: () => 1000000 + now },
    setTimeout(fn, ms) { const id = ++serial; timers.set(id, { fn, at: now + ms }); return id; },
    clearTimeout(id) { timers.delete(id); },
    fetch(path, options) { const r = { path, options }; requests.push(r); return handler(path, options, requests); },
  };
  vm.runInNewContext(source, context);
  return {
    rt: context.window.PGRuntime, requests,
    async advance(ms) {
      const end = now + ms;
      while (true) {
        const next = [...timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        const [id, timer] = next; timers.delete(id); now = timer.at; timer.fn(); await flush();
      }
      now = end; await flush();
    },
  };
}

(async () => {
  if (!only || only === 'timeouts') for (const bodyOnly of [false, true]) {
    let polls = 0;
    const delayed = deferred();
    const h = harness(path => {
      if (path === '/api/status') {
        polls++;
        if (polls === 2) return bodyOnly ? Promise.resolve({ ok: true, json: () => delayed.promise }) : delayed.promise;
        return Promise.resolve(response(status(1, polls === 1 ? 1 : 2)));
      }
      return Promise.resolve(response(path === '/api/catalog' ? catalog(65) : {}));
    });
    await flush(); assert.equal(h.rt.state.game, 'ready');
    await h.advance(500); assert.equal(polls, 2);
    await h.advance(5000);
    assert.equal(h.rt.state.game, 'offline', `hung ${bodyOnly ? 'JSON body' : 'fetch'} must expire stale ready state`);
    await h.advance(500);
    assert.equal(h.rt.state.game, 'ready'); assert.equal(h.rt.state.blue, 2);
    delayed.resolve(bodyOnly ? status(1, 99) : response(status(1, 99))); await flush();
    assert.equal(h.rt.state.blue, 2, 'late timed-out status must not overwrite the recovered state');
  }

  if (!only || only === 'catalog') {
  const first = deferred(), second = deferred(); let revision = 1, catalogs = 0;
  const h = harness(path => {
    if (path === '/api/status') return Promise.resolve(response(status(revision)));
    if (path === '/api/catalog') return ++catalogs === 1 ? first.promise : second.promise;
    return Promise.resolve(response({}));
  });
  await flush(); revision = 2; await h.advance(500); assert.equal(catalogs, 2);
  let catalogRepaints = 0;
  h.rt.subscribe(event => { if (event.parts?.has('grid')) catalogRepaints++; });
  second.resolve(response(catalog(66))); await flush(); assert.equal(h.rt.state.unitKeys.BP_Test.code, 66);
  first.resolve(response(catalog(65))); await flush();
  assert.equal(h.rt.state.unitKeys.BP_Test.code, 66, 'older catalog response must not revert a newer key revision');
  assert.equal(catalogRepaints, 1, 'an obsolete catalog must not trigger an additional grid rebuild');
  }

  if (!only || only === 'retry') {
  let retryCatalogs = 0;
  const retry = harness(path => {
    if (path === '/api/status') return Promise.resolve(response(status()));
    if (path === '/api/catalog') return Promise.resolve(++retryCatalogs === 1 ? response({}, false) : response(catalog(67)));
    return Promise.resolve(response({}));
  });
  await flush(); await retry.advance(500);
  assert.equal(retryCatalogs, 2, 'temporary catalog HTTP errors must retry without requiring a session/key change');
  assert.equal(retry.rt.state.unitKeys.BP_Test.code, 67);
  }
  if (!only || only === 'invalid') {
    let polls = 0;
    const invalid = harness(path => Promise.resolve(response(path === '/api/status' ? (++polls === 1 ? status() : null) : {})));
    await flush(); await invalid.advance(2000);
    assert.equal(invalid.rt.state.game, 'offline', 'successful HTTP with invalid data must not reset the failure counter');
  }
  console.log('runtime_resilience: PASS (hung reads expire and recover, late status/catalog ignored, catalog HTTP retry)');
})().catch(error => { console.error(error); process.exitCode = 1; });
