"use strict";
const FunctionShortcuts=(()=>{
  let options,source={available:false,bindings:{}},draft={},dirty=false,capture=null,timer=null,pending=null,message='';
  const rows=new Map();
  const names=UnitShortcuts.functionNames;
  const ready=()=>source.available&&(!options.available||options.available());
  const copy=value=>Object.fromEntries(Object.keys(names).map(name=>[name,UnitShortcuts.parseBinding(value?.[name])]));
  function conflict(bindings,units=[]){
    const seen=new Map();
    for(const [action,name] of Object.entries(names)){
      const {key_code:key,modifiers:mods}=UnitShortcuts.parseBinding(bindings[action]);if(!key)continue;
      const system=UnitShortcuts.systemConflict(key,mods);if(system)return system;
      if(seen.has(key))return `${UnitShortcuts.label(key,mods)} 的主键同时用于「${names[seen.get(key)]}」和「${name}」。`;
      seen.set(key,action);
      const owner=units.find(unit=>Number(unit.unit_shortcut?.key_code)===key);
      if(owner)return `${UnitShortcuts.label(key,mods)} 的主键已被单位「${owner.display_name||owner.internal_name||owner.name||owner.id}」占用，当前绑定为 ${UnitShortcuts.label(key,owner.unit_shortcut.modifiers)}。`;
    }
    return '';
  }
  function paint(){
    if(!options)return;
    const issue=conflict(draft,options.units());
    for(const [name,row] of rows){
      const value=draft[name]||{key_code:0,modifiers:0},current=source.bindings?.[name];
      row.key.textContent=capture===name?'请按键…':UnitShortcuts.label(value.key_code,value.modifiers);
      row.key.disabled=!ready()||!!pending;row.clear.disabled=row.key.disabled;
      row.key.classList.toggle('capturing',capture===name);
      row.clear.hidden=!value.key_code;
      row.state.textContent=!ready()?'等待新版游戏端连接':!current?.key_code?'当前：未绑定':current.active?`当前：${UnitShortcuts.label(current.key_code,current.modifiers)}`:current.message||'已保存，生效待确认';
    }
    const save=document.getElementById('save-keys');save.disabled=!ready()||!!pending||!dirty||!!issue;
    document.getElementById('clear-function-keys').disabled=!ready()||!!pending;
    document.getElementById('keys-state').textContent=issue||(!ready()?'等待游戏与新版改键模块连接。':message||source.errors?.join('；')||(dirty?'修改尚未保存。':Object.values(source.bindings||{}).some(e=>e.key_code)?'以上显示游戏端当前设置。':'功能快捷键全部未绑定；仍可使用面板按钮。'));
  }
  function cancel(){clearTimeout(timer);capture=null;paint();}
  function observe(data,jobs){
    source=data||{available:false,bindings:{}};
    if(pending){
      const job=jobs?.find(item=>item.id===pending);
      if(job&&!['queued','pending'].includes(job.status)){
        pending=null;
        if(job.status==='succeeded'){dirty=false;message='快捷键已保存，游戏端已确认生效。';options.changed();}
        else{dirty=true;message=job.message||'保存未确认，旧绑定继续生效。';}
        options.notify(message);
      }
    }
    if(!dirty&&!pending)draft=copy(source.bindings);
    paint();
  }
  async function save(){
    if(!ready()||pending)return;
    cancel();const issue=conflict(draft,options.units());if(issue){message=issue;paint();return;}
    const request=copy(draft);pending=-1;message='正在提交快捷键…';paint();
    try{const result=await options.request(request);pending=result.id;message='已提交，等待游戏端保存与注册读回。';await options.refresh();}
    catch(error){pending=null;message=error.message;options.notify(message);}
    paint();
  }
  function init(config){
    options=config;draft=copy({});
    const container=document.getElementById('key-fields');container.replaceChildren();
    for(const [name,label] of Object.entries(names)){
      const row=document.createElement('div');row.className='function-key-row';
      const caption=document.createElement('label');caption.textContent=label;caption.htmlFor='key-'+name;
      const controls=document.createElement('div');controls.className='function-key-controls';
      const key=document.createElement('button');key.type='button';key.className='function-keybox';key.id='key-'+name;key.textContent='未绑定';key.setAttribute('aria-label','设置'+label+'快捷键');
      key.addEventListener('click',()=>{if(!ready()||pending)return;cancel();UnitShortcuts.cancel();capture=name;message='按下快捷键，可组合 Ctrl / Alt / Shift；Esc 取消。';paint();timer=setTimeout(cancel,15000);});
      const clear=document.createElement('button');clear.type='button';clear.className='function-keyclear';clear.textContent='×';clear.setAttribute('aria-label','清空'+label+'快捷键');
      clear.addEventListener('click',()=>{cancel();draft[name]={key_code:0,modifiers:0};dirty=true;message='修改尚未保存。';paint();});
      const status=document.createElement('small');status.className='hint';
      controls.append(key,clear);row.append(caption,controls,status);container.append(row);rows.set(name,{key,clear,state:status});
    }
    document.getElementById('save-keys').addEventListener('click',save);
    document.getElementById('clear-function-keys').addEventListener('click',()=>{cancel();draft=copy({});dirty=true;message='已清空功能键草稿，点击保存后生效。';paint();});
    document.addEventListener('keydown',event=>{
      if(!capture)return;event.preventDefault();event.stopPropagation();
      if(event.key==='Escape'){cancel();return;}if(event.repeat)return;
      if(event.metaKey){options.notify('Windows 系统快捷键不能用于绑定。');return;}
      if(['Control','Alt','Shift'].includes(event.key))return;
      const key=UnitShortcuts.keyCode(event);if(!key){options.notify('未识别这个按键，请使用键盘按键。');return;}
      const mods=(event.ctrlKey?1:0)|(event.altKey?2:0)|(event.shiftKey?4:0);
      const name=capture;cancel();draft[name]={key_code:key,modifiers:mods};dirty=true;message='修改尚未保存。';paint();
      const issue=conflict(draft,options.units());if(issue)options.notify(issue);
    },true);
    paint();
  }
  return {init,observe,cancel,conflict,paint};
})();
if(typeof module!=='undefined')module.exports=FunctionShortcuts;
