const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const i18n=require('./test_i18n_runtime')();i18n.set('zh');
const app=fs.readFileSync(__dirname+'/prototype/app.js','utf8');
function section(a,b){return app.slice(app.indexOf(a),app.indexOf(b,app.indexOf(a)+a.length));}
const box={innerHTML:''};let dialog='';
const q={on:true,supported:true,settingsSupported:true,ready:true,mode:'WAVE',intervalMs:1750,blueSlots:3,redSlots:2,blueReserve:3,redReserve:2,relayStarted:false,generated:0};
const c={S:{summonQueue:q,blue:0,red:0,down:{blue:0,red:0},immortal:{failures:0},clock:{state:'',seconds:0},fight:'idle',keys:{start:''}},
 ui:{busy:new Set(),roster:{blue:{},red:{}},lastCounts:{}},RT:{online:()=>true},t:(k,p)=>i18n.t(k,p),esc:v=>String(v??''),icon:()=>'',
 $:selector=>selector==='#dock-battle'?box:null,teamName:String,rosterHTML:()=>'',guardHTML:()=>'',fmtNum:String,
 gameBlocker:()=>'',fieldTotal:()=>0,summonsWaiting:()=>true,keyCap:()=>'',openDialog:(_,html)=>{dialog=html;}};
vm.createContext(c);vm.runInContext(section('  function renderBattle()', '  function renderView()'),c);
vm.runInContext(section('  function queueSettingsMessage(', '  function renderSummonQueueSettings()'),c);
vm.runInContext(section('  function openQueueSettings()', '  async function saveQueueSettings()'),c);
c.renderBattle();
assert(/data-action="start"\s*>/.test(box.innerHTML),'reserve-only teams must be able to start before actors exist');
assert(box.innerHTML.includes(i18n.t('queueSettings.start')));
let html=c.summonQueueSettingsHTML();assert(html.includes(i18n.t('queueSettings.mode.WAVE'))&&html.includes(i18n.t('queueSettings.summaryWave',{seconds:1.75,blue:3,red:2})));
c.openQueueSettings();assert(dialog.includes('value="SINGLE"')&&dialog.includes('value="WAVE"')&&dialog.includes('value="TIMED"'));
assert(dialog.includes('id="queue-mode" disabled'),'mode cannot change during an enabled queue');
q.relayStarted=true;c.S.fight='fighting';c.renderBattle();assert(/data-action="start" disabled/.test(box.innerHTML));
q.relayStarted=false;c.S.blue=1;c.S.red=1;c.renderBattle();assert(box.innerHTML.includes(i18n.t('queueSettings.start'))&&!/data-action="start" disabled/.test(box.innerHTML),'cleared reserves can resume relay during an existing fight');
for(const lang of ['zh','en','ja','fr','de','es']) {
 i18n.set(lang);c.renderBattle();assert(box.innerHTML.includes(i18n.t('queueSettings.start')),lang);
 c.openQueueSettings();assert(dialog.includes(i18n.t('queueSettings.title'))&&dialog.includes(i18n.t('queueSettings.intro')),lang);
 q.message='等待存活状态读回';assert(c.summonQueueSettingsHTML().includes(i18n.t('queueSettings.message.waitAlive')),lang);
 q.message='首批存活未确认，未自动重复生成，已取消 3 条待执行召唤';
 assert(c.summonQueueSettingsHTML().includes(i18n.t('queueSettings.message.cancelled',{reason:i18n.t('queueSettings.reason.initialUnknown'),n:3})),lang);
 q.message='接力结束：蓝方已无在场单位和候补';assert(c.summonQueueSettingsHTML().includes(i18n.t('queueSettings.message.finished',{team:'blue'})),lang);
 if(lang!=='zh')assert(!dialog.includes('接力先加蓝红候补')&&!c.summonQueueSettingsHTML().includes('接力结束：'),lang);
}
console.log('relay_ui: PASS (configurable cadence, three modes, reserve-only start and resumed relay)');
