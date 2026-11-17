const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const i18n = require('./test_i18n_runtime')();
const source = fs.readFileSync(__dirname + '/prototype/app.js', 'utf8');
assert(source.includes('["companion", ["recall_companions", "dismiss_companions"]], ["hun", ["hun_blue", "hun_red", "hun_companion", "hun_neutral"]]'));
const context = { S: { keys: {}, dismissKeySupported: false }, ui: { capture: null, keyNote: null, keysSaving: false },
  RT: { online: () => true }, t: (key, p) => i18n.t(key, p), esc: String, icon: () => '', keyCap: () => '', KEY_ICONS: {} };
vm.createContext(context);
const first = source.indexOf('  function keyRowHTML('), last = source.indexOf('  function hotkeysHTML()', first);
vm.runInContext(source.slice(first, last), context);
for (const lang of ['zh', 'en']) {
  i18n.set(lang);
  assert(context.keyRowHTML('dismiss_companions').includes('disabled'));
  assert(!context.keyRowHTML('recall_companions').includes('disabled'), 'old Mod keeps its existing hotkeys');
  context.S.dismissKeySupported = true;
  const row = context.keyRowHTML('dismiss_companions');
  assert(row.includes(i18n.t('keys.action.dismiss_companions')) && row.includes(i18n.t('keys.unbound')) && !row.includes('disabled'));
  context.S.dismissKeySupported = false;
}
i18n.set('zh');
for (const action of ['hun_blue', 'hun_red', 'hun_companion', 'hun_neutral']) {
  context.S.hunKeysSupported = false;
  assert(context.keyRowHTML(action).includes('disabled') && context.keyRowHTML(action).includes(i18n.t('keys.hun.update')), 'an old Mod cannot take a Hun key');
  context.S.hunKeysSupported = true;
  const row = context.keyRowHTML(action);
  assert(row.includes(i18n.t('keys.action.' + action)) && row.includes(i18n.t('keys.unbound')) && !row.includes('disabled'));
  assert(i18n.t('keys.action.' + action) !== 'keys.action.' + action && i18n.t('keys.desc.' + action) !== 'keys.desc.' + action);
}
assert(i18n.t('keys.group.hun') !== 'keys.group.hun');
console.log('dismiss_key_ui: PASS (independent companion shortcut, four Hun summon keys, blank defaults and old-Mod capability gates)');
