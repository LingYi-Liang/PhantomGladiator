const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const app=fs.readFileSync(__dirname+'/prototype/app.js','utf8');
function section(a,b){return app.slice(app.indexOf(a),app.indexOf(b,app.indexOf(a)+a.length));}
const box={innerHTML:''};let dialog='';
const q={on:true,supported:true,settingsSupported:true,ready:true,mode:'WAVE',intervalMs:1750,blueSlots:3,redSlots:2,blueReserve:3,redReserve:2,relayStarted:false,generated:0};
const c={S:{summonQueue:q,blue:0,red:0,down:{blue:0,red:0},immortal:{failures:0},clock:{state:'',seconds:0},fight:'idle',keys:{start:''}},
 ui:{busy:new Set(),roster:{blue:{},red:{}},lastCounts:{}},RT:{online:()=>true},t:k=>k,esc:v=>String(v??''),icon:()=>'',
 $:selector=>selector==='#dock-battle'?box:null,teamName:String,rosterHTML:()=>'',guardHTML:()=>'',fmtNum:String,
 gameBlocker:()=>'',fieldTotal:()=>0,summonsWaiting:()=>true,keyCap:()=>'',openDialog:(_,html)=>{dialog=html;}};
vm.createContext(c);vm.runInContext(section('  function renderBattle()', '  function renderView()'),c);
vm.runInContext(section('  function summonQueueSettingsHTML()', '  function renderSummonQueueSettings()'),c);
vm.runInContext(section('  function openQueueSettings()', '  async function saveQueueSettings()'),c);
c.renderBattle();
assert(/data-action="start"\s*>/.test(box.innerHTML),'reserve-only teams must be able to start before actors exist');
assert(box.innerHTML.includes('开始接力'));
let html=c.summonQueueSettingsHTML();assert(html.includes('整队接力')&&html.includes('1.75')&&html.includes('蓝 3 / 红 2'));
c.openQueueSettings();assert(dialog.includes('value="SINGLE"')&&dialog.includes('value="WAVE"')&&dialog.includes('value="TIMED"'));
assert(dialog.includes('id="queue-mode" disabled'),'mode cannot change during an enabled queue');
q.relayStarted=true;c.S.fight='fighting';c.renderBattle();assert(/data-action="start" disabled/.test(box.innerHTML));
q.relayStarted=false;c.S.blue=1;c.S.red=1;c.renderBattle();assert(box.innerHTML.includes('开始接力')&&!/data-action="start" disabled/.test(box.innerHTML),'cleared reserves can resume relay during an existing fight');
console.log('relay_ui: PASS (configurable cadence, three modes, reserve-only start and resumed relay)');
