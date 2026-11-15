const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const context = vm.createContext({ Intl });
for (const file of ['i18n.js', 'i18n-more.js', 'i18n-runtime14.js', 'language-support.js']) {
  vm.runInContext(fs.readFileSync(__dirname + '/prototype/' + file, 'utf8'), context);
}
const i18n = vm.runInContext('I18N', context), support = vm.runInContext('PGLanguageSupport', context);
assert.equal(i18n.ACTIVE_LANGS.map(l => l.id).join(','), 'zh,en');
assert.equal(Object.keys(support.notices).sort().join(','), 'de,es,fr,ja');
for (const lang of ['zh', 'en']) assert.equal(support.resolve(lang), lang);
const source = fs.readFileSync(__dirname + '/prototype/app.js', 'utf8');
const migration = source.slice(source.indexOf('  const requestedLanguage ='), source.indexOf('  I18N.set(ui.lang);'));
function boot(mode, stored, detected, seen = '') {
  const saved = { lang: stored, languageSupportNotice: seen };
  const c = { ui: { langMode: mode }, store: { get: (key, fallback) => saved[key] ?? fallback },
    PGLanguageSupport: support, detectedOriginal: { lang: detected } };
  vm.createContext(c); vm.runInContext(migration, c); return c.ui;
}
for (const lang of Object.keys(support.notices)) {
  assert.equal(boot('manual', lang, 'zh').lang, 'en');
  assert.equal(boot('manual', lang, 'zh').languageNotice, lang);
  assert.equal(boot('auto', 'zh', lang).languageNotice, lang);
  assert.equal(boot('manual', lang, 'zh', support.version).languageNotice, null);
  assert(support.notices[lang].body.length > 150);
  assert(support.notices[lang].fallback.includes('Settings → Language'));
}
assert.equal(boot('manual', 'zh', 'fr').languageNotice, null);
assert.equal(boot('manual', 'en', 'ja').languageNotice, null);
assert.equal(boot('auto', 'fr', 'zh').lang, 'zh');
assert.equal(boot('manual', 'invalid', 'zh').lang, 'zh');

let dialog, writes = {}, scheduled = 0;
const c = { PGLanguageSupport: support, I18N: i18n, REPO: 'https://github.com/LingYi-Liang/PhantomGladiator',
  t: (key, p) => i18n.t(key, p), esc: value => String(value),
  ui: { languageNotice: 'fr', lang: 'en', onboarding: false }, dlg: null,
  openDialog(kind, html) { dialog = { kind, html }; }, $: () => ({}),
  store: { set: (key, value) => writes[key] = value }, scheduleAutoUpdate() { scheduled++; },
  document: { body: { classList: { remove() {} } }, contains: () => false },
};
vm.createContext(c);
const first = source.indexOf('  function languageNoticeBody('), last = source.indexOf('  function settingsHTML()', first);
vm.runInContext(source.slice(first, last), c);
c.showLanguageNotice(); assert.equal(dialog.kind, 'language-support');
assert(dialog.html.includes(support.notices.fr.body));
assert(dialog.html.includes('/issues/new') && dialog.html.includes('mailto:' + support.email));
assert.equal(Object.keys(writes).length, 0, 'showing must not acknowledge the notice');
dialog = null; c.ui.onboarding = true; c.showLanguageNotice(); assert.equal(dialog, null);
c.ui.onboarding = false; c.dlg = { kind: 'update' }; c.showLanguageNotice(); assert.equal(dialog, null);

const closeFirst = source.indexOf('  function closeDialog('), closeLast = source.indexOf('  // ---------- Toasts', closeFirst);
vm.runInContext(source.slice(closeFirst, closeLast), c);
c.dlg = { kind: 'language-support', wrap: { remove() {} } }; c.closeDialog(false);
assert.equal(Object.keys(writes).length, 0, 'replacement dialogs must not acknowledge it');
c.dlg = { kind: 'language-support', wrap: { remove() {} } }; c.closeDialog();
assert.equal(writes.languageSupportNotice, support.version); assert.equal(writes.lang, 'en');
assert.equal(c.ui.languageNotice, null); assert.equal(scheduled, 1);
for (const lang of ['zh', 'en']) {
  i18n.set(lang); const html = c.languageSupportHTML();
  for (const notice of Object.values(support.notices)) assert(html.includes(notice.body) && html.includes(notice.name));
  const keys = i18n.keys('zh').filter(key => /^(languageSupport|xianzhePhantom|menghuaStage|offcombatRegen)\./.test(key));
  for (const key of keys) assert(i18n.keys(lang).includes(key));
}
assert.equal((source.match(/I18N\.ACTIVE_LANGS\.map/g) || []).length, 3);
assert(!source.includes('I18N.LANGS.map'));
i18n.set('en'); assert.equal(support.message('无效的脱战回血设置'), 'Invalid out-of-combat healing setting.');
assert.equal(support.message('unknown detail'), 'unknown detail');
assert.equal(support.message('__proto__'), '__proto__');
i18n.set('zh'); assert.equal(support.message('无效的脱战回血设置'), '无效的脱战回血设置');
console.log('language_support: PASS (legacy manual/auto migration, deferred acknowledgement, bilingual UI and permanent four-language notices)');
