const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(__dirname+'/prototype/app.js','utf8');
const first=source.indexOf('  const UNIT_RULE_OF ='),last=source.indexOf('  function cardHTML(',first);
const sent=[];let online=true;
const c={S:{unitRulesSupported:true,menghuaStageSupported:true,unitRules:{}},ui:{busy:new Set(),selectedId:'BP_Monster_MengHua'},
  RT:{online:()=>online},t:k=>k,esc:String,renderGrid(){},run:(action,options)=>sent.push({action,...options})};
vm.createContext(c);vm.runInContext(source.slice(first,last),c);
const unit={id:'BP_Monster_MengHua',name:'梦华'};
let html=c.unitRuleHTML(unit);assert(html.includes('剧情联动：保留')&&html.includes('role="switch"')&&html.includes('aria-checked="false"'));
assert(html.includes('地图剧情不改')&&html.includes('重新召唤生效')&&html.includes('其他血量下限和不倒下仍生效'));
(async()=>{
  await c.toggleUnitRule(unit.id,'menghua_stage');assert.equal(sent.length,1);
  assert.equal(JSON.stringify(sent[0].payload),JSON.stringify({unit:unit.id,rule:'menghua_stage',value:'skip'}));
  assert(c.unitRuleHTML(unit).includes('剧情联动：保留'),'wait for the saved choice, not optimistic UI');
  c.S.unitRules[unit.id]={menghua_stage:'skip'};html=c.unitRuleHTML(unit);
  assert(html.includes('剧情联动：跳过')&&html.includes('aria-checked="true"')&&html.includes('is-changed'));
  c.ui.busy.add('set_unit_rule');assert(c.unitRuleHTML(unit).includes('disabled'));await c.toggleUnitRule(unit.id,'menghua_stage');assert.equal(sent.length,1);
  c.ui.busy.clear();c.S.menghuaStageSupported=false;assert.equal(c.unitRuleHTML(unit),'','old Mod must not advertise a new stage rule');
  online=false;assert(c.unitRuleHTML(unit).includes('剧情联动：跳过'));
  assert(!c.unitRuleHTML({id:'BP_Monster_AHua'}).includes('menghua_stage'));
  console.log('menghua_stage_ui: PASS (native default, bounded scope, next spawn and confirmed setting)');
})().catch(error=>{console.error(error);process.exitCode=1});
