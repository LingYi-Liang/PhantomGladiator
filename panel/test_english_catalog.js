const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const i18n = require('./test_i18n_runtime')();
const ui = path.join(__dirname, 'prototype');
const source = fs.readFileSync(path.join(ui, 'app.js'), 'utf8');
const context = vm.createContext({window:{}, I18N:i18n});
vm.runInContext(fs.readFileSync(path.join(ui, 'units.js'), 'utf8'), context);
const rows = context.window.PG_UNITS;
const hasHan = /[\u3400-\u9fff]/u;
for (const row of rows) {
  assert(row.enName && row.enMap && (!row.chName || row.enChapter), row.id);
  assert(!hasHan.test([row.enName,row.enMap,row.enChapter,row.enNote].join('')),row.id);
}
const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, 'hun-catalog.json'), 'utf8'));
for (const row of catalog.items) {
  assert(row.en.name && (!row.description || row.en.description) && (!row.variant || row.en.variant),row.id);
  assert(!hasHan.test(Object.values(row.en).join('')),row.id);
  assert(!/<[^>]+>/.test(row.en.description),row.id);
}
// The English UI must work offline, with a Chinese game, and after changing languages in place.
const first = rows[0];
const english = {lang:'en-US',units:{[first.id]:{name:'Name from game'}}};
const chinese = {lang:'zh-Hans',units:{[first.id]:{name:'游戏内名称'}}};
Object.assign(context,{PG_UNITS:rows,initialOf:s=>s.slice(0,1),t:(key,params)=>i18n.t(key,params)});
const start=source.indexOf('  const UNITS ='), end=source.indexOf('  // ---------- State',start);
assert(start>=0 && end>start);
vm.runInContext(source.slice(start,end)+'\nthis.unit=UNITS[0];',context);
i18n.set('en');context.applyNames(null);assert.equal(context.unit.name,first.enName);
context.applyNames(chinese);assert.equal(context.unit.name,first.enName);
context.applyNames(english);assert.equal(context.unit.name,'Name from game');
i18n.set('zh');context.applyNames(english);assert.equal(context.unit.name,first.name);
context.applyNames(chinese);assert.equal(context.unit.name,'游戏内名称');
i18n.set('en');context.applyNames(chinese);assert.equal(context.unit.name,first.enName);
assert(context.unit.search.includes(first.name) && context.unit.search.includes(first.enName.toLowerCase()));
for (const key of i18n.keys('en')) {
  if (!['credit.tooltip','onb.credit','languageSupport.menu'].includes(key))
    assert(!hasHan.test(i18n.t(key)), key);
}
assert.equal(i18n.combatMessage('音频文件为空或超过 512 MB'),'The file is empty or exceeds 512 MB.');
console.log('PASS English catalog, offline names, game-language mismatch, live language changes and localized messages');
const trials=rows.filter(u=>u.dragonTrial);
const ids=['BP_Monster_MoTian_LongZhu_01','BP_Monster_MoTian_LongZhu_03','BP_Monster_MoTian_LongZhu_02','BP_Monster_MoTian_LongZhu_04','BP_Monster_MoTian'];
assert.deepEqual(Array.from(trials,u=>u.id),ids);
for(const lang of ['en','zh']){
  i18n.set(lang);context.applyNames({lang,units:Object.fromEntries(ids.map(id=>[id,{name:lang==='en'?'Shared boss':'金面具黑衣人'}]))});
  const names=vm.runInContext('UNITS.filter(u=>u.dragonTrial).map(u=>u.name)',context);
  assert.equal(new Set(names).size,5,'online alias translations must retain the trial number');
  assert(names.every((n,i)=>n.includes(String(i+1))));
  assert(vm.runInContext('UNITS.filter(u=>u.dragonTrial).every(u=>u.search.includes(t("longzhu.sites").toLowerCase()))',context));
}
