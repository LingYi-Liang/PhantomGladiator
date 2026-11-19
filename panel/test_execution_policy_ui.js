const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(__dirname+'/prototype/app.js','utf8');
const requests=[],dialogs=[];
const nodes={'#execution-minions-chance':{value:'50'},'#execution-minions-on':{checked:true}};
const c={S:{unitRules:{}},byId:new Map([['BOSS',{id:'BOSS',name:'Test',boss:true}],['MOB',{id:'MOB',boss:false}]]),ui:{busy:new Set()},
 esc:String,$:s=>nodes[s],openDialog:(kind,html)=>dialogs.push(html),renderGrid:()=>{},run:async(a,o)=>requests.push({a,p:o.payload})};
c.I18N=require('./test_i18n_runtime')();c.I18N.set('zh');c.t=c.I18N.t;
vm.createContext(c);
const begin=source.indexOf('  function openExecutionOptions('),end=source.indexOf('  async function toggleUnitRule(',begin);
vm.runInContext(source.slice(begin,end),c);
(async()=>{
 c.openExecutionOptions('MOB');assert.equal(dialogs.length,0);
 c.openExecutionOptions('BOSS');assert(dialogs[0].includes('概率')&&dialogs[0].includes('value="100"'));
 await c.saveExecutionOptions('BOSS');assert.equal(requests[0].p.value,'on_50');assert.equal(requests[0].p.rule,'execution_minions');
 nodes['#execution-minions-on'].checked=false;await c.saveExecutionOptions('BOSS');assert.equal(requests[1].p.value,'off_50');
 nodes['#execution-minions-chance'].value='101';await c.saveExecutionOptions('BOSS');assert.equal(requests.length,2);
 c.S.unitRules.BOSS={execution_minions:'off_37'};c.openExecutionOptions('BOSS');assert(dialogs[1].includes('value="37"'));
 console.log('execution policy UI: PASS boss scope, atomic toggle/chance, retained probability and limits');
})().catch(e=>{console.error(e);process.exitCode=1;});
