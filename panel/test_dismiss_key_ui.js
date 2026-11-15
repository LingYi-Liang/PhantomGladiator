const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const i18n = require('./test_i18n_runtime')();
const source = fs.readFileSync(__dirname + '/prototype/app.js', 'utf8');
assert(source.includes('["companion", ["recall_companions", "dismiss_companions"]]'));
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
console.log('dismiss_key_ui: PASS (independent companion shortcut, blank default and old-Mod capability gate)');
