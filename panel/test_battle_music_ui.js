const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = fs.readFileSync(__dirname + '/prototype/app.js', 'utf8');
let online = true;
const nodes = { '#battle-music-mode': { value: 'TRACK' }, '#battle-music-track': { value: 'MOYUAN_P1' }, '#battle-music-save': {}, '#battle-music-status': {} };
const requests = [];
const c = { window: {}, S: { battleMusic: { supported: true, mode: 'NATIVE', track: 'MOYUAN_P1', message: '原版读回', state: 'native' } },
  ui: { busy: new Set() }, RT: { online: () => online }, esc: String, $: key => nodes[key],
  run: async (action, options) => { requests.push({ action, payload: options.payload }); return { status: 'succeeded' }; } };
vm.createContext(c);vm.runInContext(fs.readFileSync(__dirname + '/prototype/battle-music.js', 'utf8'), c);
const first = source.indexOf('  function battleMusicHTML()'), last = source.indexOf('  function settingsHTML()', first);
vm.runInContext(source.slice(first, last), c);
(async () => {
  assert(c.battleMusicHTML().includes('保留原版') && c.battleMusicHTML().includes('魔渊 · 一阶段'));
  assert(c.battleMusicHTML().includes('来源死亡') && c.battleMusicHTML().includes('阶段曲可手动指定'));
  c.renderBattleMusicState();assert.equal(nodes['#battle-music-status'].textContent, '原版读回');
  await c.saveBattleMusic();assert.equal(JSON.stringify(requests.pop()), JSON.stringify({ action: 'set_battle_music', payload: { mode: 'TRACK', track: 'MOYUAN_P1' } }));
  online = false; c.renderBattleMusicState();assert(nodes['#battle-music-save'].disabled);await c.saveBattleMusic();assert.equal(requests.length, 0);
  online = true;c.S.battleMusic.supported = false;await c.saveBattleMusic();assert.equal(requests.length, 0);
  c.S.battleMusic.supported = true;nodes['#battle-music-track'].value = '../BAD';await c.saveBattleMusic();assert.equal(requests.length, 0);
  console.log('battle_music_ui: PASS (native default, explicit catalog choice, readback display and capability guards)');
})().catch(error => { console.error(error); process.exitCode = 1; });
