const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync(__dirname+'/prototype/local-audio.js','utf8');
const requests=[];
const nodes={
 '#local-music-boss':{value:'BOSS',options:[{}]},'#local-music-volume':{value:'50'},
 '#local-music-list':{},'#local-music-status':{}
};
const c={window:{PGRuntime:{state:{localAudio:{supported:true,bosses:[{id:'BOSS',name:'Test <Boss>'}],mapping:{BOSS:{name:'<script>.mp3',seconds:1}},volume:50}},
 localAudio:{pick:async()=> 'selected-local-file',change:async r=>requests.push(r)}}},
 document:{querySelector:s=>nodes[s],querySelectorAll:()=>[],activeElement:null},Map,Set};
c.I18N=require('./test_i18n_runtime')();c.I18N.set('zh');c.t=c.I18N.t;
vm.createContext(c);vm.runInContext(src,c);
(async()=>{
 const ui=c.window.PGLocalAudio;assert(ui.html().includes('30 分钟'));ui.render();
 assert(nodes['#local-music-list'].innerHTML.includes('&lt;script&gt;'));assert(!nodes['#local-music-list'].innerHTML.includes('<script>'));
 await ui.act('import');assert.equal(requests[0].boss,'BOSS');assert.equal(requests[0].path,'selected-local-file');
 nodes['#local-music-volume'].value='101';await ui.act('volume');assert.equal(requests.length,1);
 nodes['#local-music-volume'].value='25';await ui.act('volume');assert.equal(requests[1].volume,25);
 await ui.act('remove',{dataset:{id:'BOSS'}});assert.equal(requests[2].action,'remove');
 console.log('local audio UI: PASS mapped import, volume validation, removal and escaped file names');
})().catch(e=>{console.error(e);process.exitCode=1;});
