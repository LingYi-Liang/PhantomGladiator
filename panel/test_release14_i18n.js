const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const i18n = require('./test_i18n_runtime')();
const keys = i18n.keys('zh').filter(key => /^(queueSettings\.|shieldReflect\.)/.test(key));
assert.equal(keys.length, 50);
const params = { seconds: 1.75, blue: 3, red: 2, generated: 7, n: 4, team: 'Blue', reason: 'Stopped', detail: 'Detail', name: 'Unit' };
const placeholders = value => [...value.matchAll(/\{(\w+)\}/g)].map(m => m[1]).sort().join(',');
const original = new Map();
i18n.set('zh');
for (const key of keys) original.set(key, placeholders(i18n.t(key)));
for (const lang of ['zh', 'en', 'ja', 'fr', 'de', 'es']) {
  i18n.set(lang);
  for (const key of keys) {
    assert(i18n.keys(lang).includes(key), `${lang}: missing ${key}`);
    assert.notEqual(i18n.t(key), key);
    assert.equal(placeholders(i18n.t(key)), original.get(key), `${lang}: placeholders ${key}`);
    assert(!/\{\w+\}/.test(i18n.t(key, params)), `${lang}: unresolved parameters ${key}`);
  }
}
// Both history entries and runtime state text use the same language catalog.
const app = fs.readFileSync(__dirname + '/prototype/app.js', 'utf8');
const first = app.indexOf('  function jobTitle('), last = app.indexOf('  function historyHTML()', first);
const context = { t: (key, p) => i18n.t(key, p), byId: new Map(), diffName: String, teamName: String };
vm.createContext(context);vm.runInContext(app.slice(first, last), context);
for (const lang of ['zh', 'en', 'ja', 'fr', 'de', 'es']) {
  i18n.set(lang);
  assert.equal(context.jobTitle({ action:'configure_summon_queue',payload:{interval_ms:1750} }), i18n.t('queueSettings.history',{seconds:1.75}));
  const title = context.jobTitle({action:'set_unit_rule',payload:{unit:'Unit',rule:'remote_reflect',value:'off'}});
  assert(title.includes(i18n.t('shieldReflect.off')) && !title.includes('unitRule.remote_reflect'));
}
console.log('release14_i18n: PASS (50 keys in six languages, parameters, history and thorns semantics)');
