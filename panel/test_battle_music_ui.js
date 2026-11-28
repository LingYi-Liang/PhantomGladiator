const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = fs.readFileSync(__dirname + '/prototype/app.js', 'utf8');
let online = true;
const nodes = { '#battle-music-mode': { value: 'TRACK' }, '#battle-music-track': { value: 'MOYUAN_P1' }, '#battle-music-save': {}, '#battle-music-status': {} };
const requests = [];
const c = { window: {}, S: { battleMusic: { supported: true, mode: 'NATIVE', track: 'MOYUAN_P1', message: '原版读回', state: 'native' } },
  ui: { busy: new Set() }, RT: { online: () => online }, esc: String, $: key => nodes[key],
  run: async (action, options) => { requests.push({ action, payload: options.payload }); return { status: 'succeeded' }; } };
c.I18N=require('./test_i18n_runtime')();c.I18N.set('zh');c.t=c.I18N.t;
vm.createContext(c);vm.runInContext(fs.readFileSync(__dirname + '/prototype/battle-music.js', 'utf8'), c);
const first = source.indexOf('  function battleMusicHTML()'), last = source.indexOf('  function settingsHTML()', first);
vm.runInContext(source.slice(first, last), c);
(async () => {
  assert(c.battleMusicHTML().includes('保留原版') && c.battleMusicHTML().includes('魔渊 · 一阶段'));
  assert(c.battleMusicHTML().includes('来源死亡') && c.battleMusicHTML().includes('阶段曲可手动指定'));
  c.renderBattleMusicState();assert.equal(nodes['#battle-music-status'].textContent, '原版读回');
  await c.saveBattleMusic();assert.equal(JSON.stringify(requests.pop()), JSON.stringify({ action: 'set_battle_music', payload: { mode: 'TRACK', track: 'MOYUAN_P1' } }));
  assert(c.battleMusicHTML().includes('心湖'));
  c.I18N.set('en');assert(c.battleMusicHTML().includes('Heart Lake'));c.I18N.set('zh');
  nodes['#battle-music-track'].value = 'HEART_LAKE';
  await c.saveBattleMusic();assert.equal(JSON.stringify(requests.pop().payload), JSON.stringify({ mode: 'TRACK', track: 'HEART_LAKE' }));
  const groups = new Set(c.window.PG_MUSIC_TRACKS.map(row => row.group));
  for (const lang of ['zh', 'en']) {
    c.I18N.set(lang);
    const html = c.battleMusicHTML();
    for (const group of groups) {
      const key = 'musicGroup.' + group;
      assert.notEqual(c.t(key), key);
      assert(html.includes('<optgroup label="' + c.t(key) + '">'));
    }
    if (lang === 'en') {
      for (const row of c.window.PG_MUSIC_TRACKS) {
        const key = 'musicTrack.' + row.id;
        assert.notEqual(c.t(key), key);
      }
    }
  }
  c.I18N.set('zh');
  nodes['#battle-music-track'].value = 'MUXIAOKUI_P3';
  await c.saveBattleMusic();assert.equal(requests.pop().payload.track, 'MUXIAOKUI_P3');
  assert(c.battleMusicHTML().includes('<option value="MUXIAOKUI_P3" selected>沐小葵 · 三阶段</option>'));
  online = false; c.renderBattleMusicState();assert(nodes['#battle-music-save'].disabled);await c.saveBattleMusic();assert.equal(requests.length, 0);
  online = true;c.S.battleMusic.supported = false;await c.saveBattleMusic();assert.equal(requests.length, 0);
  c.S.battleMusic.supported = true;nodes['#battle-music-track'].value = '../BAD';await c.saveBattleMusic();assert.equal(requests.length, 0);
  console.log('battle_music_ui: PASS (native default, explicit catalog choice, readback display and capability guards)');
})().catch(error => { console.error(error); process.exitCode = 1; });
