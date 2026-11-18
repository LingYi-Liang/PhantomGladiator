const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const createI18n = require('./test_i18n_runtime');
const sourceArg = process.argv.find(arg => arg.startsWith('--source='));
const source = fs.readFileSync(sourceArg ? sourceArg.slice(9) : __dirname + '/prototype/real-runtime.js', 'utf8');
const flush = async () => { for (let i = 0; i < 35; i++) await Promise.resolve(); };
function deferred() { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; }
const response = (data, ok = true, status = 200) => ({ ok, status, json: async () => data });
function harness(post, lang = 'zh', values = {}) {
  let now = 0, serial = 0;
  const i18n = createI18n();i18n.set(lang);
  const timers = new Map(), requests = [], queue = [];
  const context = { window: { PG_I18N: i18n }, document: { documentElement: { lang } }, AbortController,
    Date: { now: () => now + 1000000 },
    setTimeout(fn, ms) { const id = ++serial; timers.set(id, { fn, at: now + ms }); return id; },
    clearTimeout(id) { timers.delete(id); },
    fetch(path, options) {
      requests.push({ path, options });
      if (options?.method === 'POST') return post(path, options);
      if (path.split('?')[0] === '/api/status') {
        const watched = (new URL(path, 'http://fixture')).searchParams.get('watch')?.split(',') || [];
        return Promise.resolve(response({ csrf_token: 'token', game: {
        online: true, ready: true, game_session: 'session', values: { unit_keys_revision: '1', ...values } }, catalog: { total: 1 },
        queue: queue.slice(-100), watched_commands: watched.map(id => queue.find(q => String(q.id) === id)).filter(Boolean) }));
      }
      if (path === '/api/catalog') return Promise.resolve(response({ units: [{ internal_name: 'BP_Test', id: '/Game/BP_Test.BP_Test_C' }] }));
      return Promise.resolve(response({}));
    },
  };
  vm.runInNewContext(source, context);
  return { rt: context.window.PGRuntime, requests, queue, i18n,
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
  {
    const h = harness(() => Promise.resolve(response({ id: 7 })));
    await flush();
    const events = [];
    h.rt.subscribe(e => { if (e.type === 'job' && e.job.id === '7') events.push(e.job.status); });
    const job = await h.rt.command('hun_body_probe', { team:'blue', count:1, profile_revision:0 });
    assert.equal(job.status,'pending');
    h.queue.push({id:7,action:'hun_body_probe',status:'succeeded',spawned_count:1});
    for(let id=8;id<113;id++) h.queue.push({id,action:'select_unit',status:'succeeded'});
    await h.advance(500);
    assert(events.includes('succeeded'),'the Hun page must receive its own summon receipt after it leaves the latest 100');
    await h.advance(500);
    assert.equal(h.requests.filter(r=>r.path.includes('watch=7')).length,1,'a confirmed receipt stops background watching');
  }
  {
    const h = harness(() => Promise.resolve(response({id:8})));
    await flush();
    const outcomes=[];
    h.rt.subscribe(e => { if (e.type==='job' && e.job.id==='8') outcomes.push(e.job.status); });
    await h.rt.command('hun_body_probe',{team:'red',count:1,profile_revision:0});
    await h.advance(91000);
    assert(outcomes.includes('uncertain'),'a missing receipt must release the summon controls');
    assert.equal(h.requests.filter(r=>r.options?.method==='POST').length,1);
    h.queue.push({id:8,action:'hun_body_probe',status:'succeeded',spawned_count:1});
    await h.advance(500);
    assert.equal(outcomes.at(-1),'succeeded','a late game receipt wins');
  }
  {
    const values = { battle_music_supported: 'true', battle_music_mode: 'NATIVE', battle_music_track: 'MOYUAN_P1', battle_music_state: 'native' };
    const h = harness(() => Promise.resolve(response({ id: 62 })), 'zh', values);await flush();
    assert.equal(h.rt.state.battleMusic.supported, true);
    const pending = h.rt.command('set_battle_music', { mode: 'TRACK', track: 'LEIDANG_P2' });await flush();
    assert.deepEqual(JSON.parse(h.requests.find(r => r.options?.method === 'POST').options.body), { action: 'set_battle_music', mode: 'TRACK', track: 'LEIDANG_P2' });
    h.queue.push({ id: 62, action: 'set_battle_music', status: 'succeeded', payload: { mode: 'TRACK', track: 'LEIDANG_P2' } });
    await h.advance(500);await pending;
    assert.equal(h.rt.state.battleMusic.mode, 'NATIVE', 'the receipt must not invent a playing state');
    Object.assign(values, { battle_music_mode: 'TRACK', battle_music_track: 'LEIDANG_P2', battle_music_state: 'playing', battle_music_playing_id: '123' });
    await h.advance(500);assert.equal(h.rt.state.battleMusic.mode, 'TRACK');assert.equal(h.rt.state.battleMusic.playing, 123);
  }
  for (const succeeded of [true, false]) {
    const h = harness(() => Promise.resolve(response({ id: 61 })), 'zh', { menghua_stage_rule_supported: 'true' });
    await flush();assert.equal(h.rt.state.menghuaStageSupported, true);
    const pending = h.rt.command('set_unit_rule', { unit: 'BP_Monster_MengHua', rule: 'menghua_stage', value: 'skip' });await flush();
    assert.deepEqual(JSON.parse(h.requests.find(r => r.options?.method === 'POST').options.body), { action: 'set_unit_rule', unit_id: 'BP_Monster_MengHua', rule: 'menghua_stage', value: 'skip' });
    assert.equal(h.rt.state.unitRules.BP_Monster_MengHua, undefined);
    h.queue.push({ id: 61, action: 'set_unit_rule', status: succeeded ? 'succeeded' : 'failed', payload: { unit_id: 'BP_Monster_MengHua', rule: 'menghua_stage', value: 'skip' } });
    await h.advance(500);await pending;
    assert.equal(h.rt.state.unitRules.BP_Monster_MengHua?.menghua_stage, succeeded ? 'skip' : undefined);
  }
  for (const succeeded of [true, false]) {
    const h = harness(() => Promise.resolve(response({ id: 60 })), 'zh', { offcombat_regen_supported: 'true', offcombat_regen_disabled: 'false', offcombat_regen_state: 'off' });
    await flush();assert.equal(h.rt.state.offCombatRegen.supported, true);
    const pending = h.rt.command('set_offcombat_regen', { enabled: true });await flush();
    assert.deepEqual(JSON.parse(h.requests.find(r => r.options?.method === 'POST').options.body), { action: 'set_offcombat_regen', enabled: true });
    assert.equal(h.rt.state.offCombatRegen.on, false, 'do not enable before a receipt');
    h.queue.push({ id: 60, action: 'set_offcombat_regen', status: succeeded ? 'succeeded' : 'failed', payload: { enabled: true } });
    await h.advance(500);await pending;
    assert.equal(h.rt.state.offCombatRegen.on, succeeded, 'a failed save must not flip the switch');
  }
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
  for (const lang of ['zh', 'en', 'ja', 'fr', 'de', 'es']) {
    const uncertain = harness(() => Promise.reject(new Error('connection closed')), lang);await flush();
    const result = await uncertain.rt.command('start');
    assert.equal(result.message, uncertain.i18n.t('reason.submissionUnknown'), lang);
    const denied = harness(() => Promise.resolve(response({}, false, 503)), lang);await flush();
    await assert.rejects(denied.rt.command('start'), error => error.code === 'rejected' &&
      error.detail === denied.i18n.t('runtime14.httpRejected', { status: 503 }));
    const body = deferred();
    const deniedBody = harness(() => Promise.resolve({ ok: false, status: 429, json: () => body.promise }), lang);await flush();
    const failure = deniedBody.rt.command('start').then(() => null, error => error);
    await deniedBody.advance(15000);
    assert.equal((await failure).detail, deniedBody.i18n.t('runtime14.httpRejected', { status: 429 }), lang);
    let id = 0;
    const limit = harness(() => Promise.resolve(response({ id: ++id })), lang);await flush();
    const pending = Array.from({ length: 100 }, () => limit.rt.command('start'));await flush();
    await assert.rejects(limit.rt.command('start'), error => error.code === 'rejected' &&
      error.detail === limit.i18n.t('runtime14.commandLimit', { n: 100 }));
    for (let n = 1; n <= 100; n++) limit.queue.push({ id: n, action: 'start', status: 'succeeded', payload: {} });
    await limit.advance(500);await Promise.all(pending);
  }
  // Pending transport errors use the language selected when the result arrives, not at startup.
  const delayed = deferred();const changed = harness(() => delayed.promise, 'en');await flush();
  let changedResult;changed.rt.command('start').then(result => { changedResult = result; });
  changed.i18n.set('de');await changed.advance(15000);
  assert.equal(changedResult.message, changed.i18n.t('reason.submissionUnknown'));
  // Run the actual POST -> status-poll -> receipt path for stat cleanup failures, including queue submissions.
  for (const action of ['spawn', 'queue_spawn']) {
    for (const message of [
      '单位已生成；自定义数值失败：部分属性回滚未确认，单位保留供清理',
      '单位已生成；随行数值未确认：读取失败；保留对象供清理',
      '原生召唤物数值未确认，保留登记供清理'
    ]) {
      const h = harness(() => Promise.resolve(response({ id: 32 })), 'en');await flush();
      const receipt = h.rt.command(action, { unit_id: 'BP_Test', team: 'blue', count: 1 });await flush();
      h.queue.push({ id: 32, action, status: 'failed', message, payload: {} });await h.advance(500);
      const result = await receipt;
      assert.equal(result.status, 'failed');assert.equal(result.code, 'statApplyAbort');
      assert.equal(h.i18n.t('reason.' + result.code), h.i18n.t('reason.statApplyAbort'));
    }
    const restored = harness(() => Promise.resolve(response({ id: 33 })));await flush();
    const receipt = restored.rt.command(action, { unit_id: 'BP_Test', team: 'blue', count: 1 });await flush();
    restored.queue.push({ id: 33, action, status: 'succeeded', message: '初始化通过；数值统一失败已回滚', payload: {} });
    await restored.advance(500);const result = await receipt;
    assert.equal(result.status, 'succeeded');assert.equal(result.warning, 'matchFailed');assert.equal(result.code, undefined);
    const clean = harness(() => Promise.resolve(response({ id: 34 })));await flush();
    const safe = clean.rt.command(action, { unit_id: 'BP_Test', team: 'blue', count: 1 });await flush();
    clean.queue.push({ id: 34, action, status: 'failed', message: '自定义数值失败，已成功回滚，无需清理', payload: {} });
    await clean.advance(500);assert.equal((await safe).code, undefined, 'a cleanup word alone is not an unsafe rollback');
  }
  const unrelated = harness(() => Promise.resolve(response({ id: 35 })));await flush();
  const other = unrelated.rt.command('select_unit', { unit_id: 'BP_Test' });await flush();
  unrelated.queue.push({ id: 35, action: 'select_unit', status: 'failed', message: '自定义数值失败，单位保留供清理', payload: {} });
  await unrelated.advance(500);assert.equal((await other).code, undefined, 'only summon commands map stat cleanup failures');
  console.log('runtime_commands: PASS (bounded ambiguous submission, valid ids, no replay or fabricated failure, confirmed jobs preserved)');
})().catch(error => { console.error(error); process.exitCode = 1; });
