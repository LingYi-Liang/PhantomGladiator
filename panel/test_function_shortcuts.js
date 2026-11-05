const assert=require('node:assert/strict');
global.UnitShortcuts=require('./static/unit_shortcuts.js');
const keys=require('./static/function_shortcuts.js');
const empty=()=>Object.fromEntries(Object.keys(UnitShortcuts.functionNames).map(name=>[name,{key_code:0,modifiers:0}]));
const duplicate=empty();duplicate.toggle_camera={key_code:117,modifiers:0};duplicate.exit_camera={key_code:117,modifiers:4};
assert(keys.conflict(duplicate).includes('自由观战')&&keys.conflict(duplicate).includes('退出自由观战'));
assert.equal(keys.conflict(empty()),'');
const unit={id:'u',display_name:'测试暴徒',unit_shortcut:{key_code:117,modifiers:1}};
assert(keys.conflict({...empty(),toggle_camera:{key_code:117,modifiers:0}},[unit]).includes('测试暴徒'));

class Element{
  constructor(){this.children=[];this.events={};this.attributes={};this.classList={toggle(){}};}
  append(...children){this.children.push(...children);}
  replaceChildren(){this.children=[];}
  addEventListener(name,fn){this.events[name]=fn;}
  setAttribute(name,value){this.attributes[name]=value;}
}
const elements=Object.fromEntries(['key-fields','save-keys','clear-function-keys','keys-state'].map(id=>[id,new Element()]));
let keydown;global.document={getElementById:id=>elements[id],createElement:()=>new Element(),querySelectorAll:()=>[],addEventListener:(name,fn)=>{if(name==='keydown')keydown=fn;}};
const requests=[],notices=[];let units=[];
keys.init({available:()=>true,units:()=>units,request:async bindings=>{requests.push(bindings);return {id:1};},refresh:async()=>{},changed(){},notify:text=>notices.push(text)});
keys.observe({available:true,bindings:empty(),errors:[]},[]);
const rows=elements['key-fields'].children;
assert.equal(rows.length,13);for(const row of rows)assert.equal(row.children[1].children[0].textContent,'未绑定');
const button=name=>rows[Object.keys(UnitShortcuts.functionNames).indexOf(name)].children[1].children[0];
const press=(code,key=code,mods={})=>keydown({code,key,preventDefault(){},stopPropagation(){},...mods});
button('toggle_camera').events.click();press('F6');
button('exit_camera').events.click();press('F6');
assert(elements['save-keys'].disabled&&elements['keys-state'].textContent.includes('退出自由观战'));
button('exit_camera').events.click();press('F7');assert(!elements['save-keys'].disabled);
units=[unit];keys.paint();assert(elements['save-keys'].disabled&&elements['keys-state'].textContent.includes('测试暴徒'));
units=[];keys.paint();assert(!elements['save-keys'].disabled);
(async()=>{
  await elements['save-keys'].events.click();assert.equal(requests.length,1);
  assert.deepEqual(requests[0].toggle_camera,{key_code:117,modifiers:0});
  const applied=Object.fromEntries(Object.entries(requests[0]).map(([name,e])=>[name,{...e,active:e.key_code>0}]));
  keys.observe({available:true,bindings:applied},[{id:1,status:'succeeded'}]);
  assert(elements['save-keys'].disabled&&elements['keys-state'].textContent.includes('已保存'));
  elements['clear-function-keys'].events.click();
  for(const row of rows)assert.equal(row.children[1].children[0].textContent,'未绑定');
  assert(!elements['save-keys'].disabled);keys.cancel();
  console.log('function_shortcuts: PASS (ten blank defaults, capture, specific conflicts, save ACK, clear draft)');
})().catch(error=>{console.error(error);process.exitCode=1;});
