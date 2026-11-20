const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(__dirname+'/prototype/app.js','utf8');
const i18n=require('./test_i18n_runtime')();
const first=source.indexOf('  const UNIT_RULE_OF ='),last=source.indexOf('  function cardHTML(',first);
const sent=[];let online=true;
const c={S:{unitRulesSupported:true,xianzhePhantomSupported:true,unitRules:{}},ui:{busy:new Set()},RT:{online:()=>online},
  t:(key,p)=>i18n.t(key,p),esc:String,renderGrid(){},run:(action,options)=>sent.push({action,...options})};
vm.createContext(c);vm.runInContext(source.slice(first,last),c);
const unit={id:'BP_Monster_XianZhe',name:'弦者'};
assert(c.unitRuleHTML(unit).includes('技能虚化无敌：原版'));
assert(!c.unitRuleHTML(unit).includes('is-changed'));
assert(c.unitRuleHTML(unit).includes('下次召唤生效')&&c.unitRuleHTML(unit).includes('视觉特效'));
(async()=>{
  await c.toggleUnitRule(unit.id,'phantom');assert.equal(sent.length,1);
  assert.equal(JSON.stringify(sent[0].payload),JSON.stringify({unit:unit.id,rule:'phantom',value:'off'}));
  assert(c.unitRuleHTML(unit).includes('技能虚化无敌：原版'),'settings change waits for the real runtime receipt');
  c.S.unitRules[unit.id]={phantom:'off'};
  assert(c.unitRuleHTML(unit).includes('技能虚化无敌：关闭')&&c.unitRuleHTML(unit).includes('is-changed'));
  c.ui.busy.add('set_unit_rule');await c.toggleUnitRule(unit.id,'phantom');assert.equal(sent.length,1);c.ui.busy.clear();
  c.S.xianzhePhantomSupported=false;assert.equal(c.unitRuleHTML(unit),'','old game scripts must not advertise the new rule');
  const mask={id:'BP_Monster_MoTian_LongZhu_01',name:'金面具黑衣人'};
  assert.equal(c.unitRuleHTML(mask),'');
  c.S.longzhuProtectionSupported=true;
  assert(c.unitRuleHTML(mask).includes('龙柱试炼') && !c.unitRuleHTML(mask).includes('is-changed'));
  await c.toggleUnitRule(mask.id,'phantom');
  assert.equal(sent[sent.length-1].payload.value,'off');
  online=false;assert(c.unitRuleHTML(unit).includes('技能虚化无敌'));
  console.log('xianzhe_rule_ui: PASS (native default, next spawn, capability guard, busy and confirmed state)');
})().catch(error=>{console.error(error);process.exitCode=1});
