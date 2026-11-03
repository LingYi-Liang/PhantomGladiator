"use strict";
const UnitShortcuts=(()=>{
  const codes={Space:32,Tab:9,Enter:13,NumpadEnter:13,Backspace:8,Delete:46,Insert:45,Home:36,End:35,PageUp:33,PageDown:34,ArrowLeft:37,ArrowUp:38,ArrowRight:39,ArrowDown:40,Pause:19,CapsLock:20,NumLock:144,ScrollLock:145,Backquote:192,Minus:189,Equal:187,BracketLeft:219,BracketRight:221,Backslash:220,Semicolon:186,Quote:222,Comma:188,Period:190,Slash:191,NumpadAdd:107,NumpadSubtract:109,NumpadMultiply:106,NumpadDivide:111,NumpadDecimal:110};
  const names={8:'Backspace',9:'Tab',13:'Enter',19:'Pause',20:'CapsLock',32:'Space',33:'PageUp',34:'PageDown',35:'End',36:'Home',37:'←',38:'↑',39:'→',40:'↓',45:'Insert',46:'Delete',106:'Num*',107:'Num+',109:'Num-',110:'Num.',111:'Num/',144:'NumLock',145:'ScrollLock',186:';',187:'=',188:',',189:'-',190:'.',191:'/',192:'`',219:'[',220:'\\',221:']',222:"'"};
  let options,capture=null,timer=null;const pending=new Map(),errors=new Map();
  const functionNames={spawn:'召唤所选单位',start:'开始交战',stop:'停止并清理',refresh_catalog:'刷新单位目录',toggle_camera:'自由观战（无仇恨＋隐身＋无敌锁血）',exit_camera:'退出自由观战并恢复',cycle_team:'切换召唤队伍',toggle_spectator:'单独切换无仇恨',recall_companions:'召回随从到身边',toggle_time_stop:'时停（游戏暂停，自由视角照常移动）'};
  function parseBinding(value){
    if(value&&typeof value==='object')return {key_code:Number(value.key_code)||0,modifiers:Number(value.modifiers)||0};
    const match=/^VK_(\d+)_MOD_(\d+)$/.exec(value||'');if(match)return {key_code:Number(match[1]),modifiers:Number(match[2])};
    if(/^F\d+$/.test(value||''))return {key_code:111+Number(value.slice(1)),modifiers:0};
    const numpad=['ZERO','ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE'];
    const num=numpad.indexOf((value||'').replace('NUM_',''));if(num>=0)return {key_code:96+num,modifiers:0};
    return {key_code:0,modifiers:0};
  }
  function systemConflict(key,mods){
    const owner={121:'游戏控制台',192:'游戏控制台',91:'Windows系统键',92:'Windows系统键'}[key]
      ||(key===82&&(mods&1)?'UE4SS重载Mod（Ctrl+R）':null)
      ||(key===115&&(mods&2)?'关闭窗口（Alt+F4）':null)
      ||(key===9&&(mods&2)?'切换窗口（Alt+Tab）':null)
      ||(key===46&&(mods&3)===3?'Windows安全界面（Ctrl+Alt+Delete）':null);
    return owner?`${label(key,mods)} 已被「${owner}」占用。`:'';
  }
  function keyCode(event){
    if(/^Key[A-Z]$/.test(event.code))return event.code.charCodeAt(3);
    if(/^Digit\d$/.test(event.code))return Number(event.code.slice(5))+48;
    if(/^Numpad\d$/.test(event.code))return Number(event.code.slice(6))+96;
    if(/^F\d{1,2}$/.test(event.code)){const n=Number(event.code.slice(1));if(n>=1&&n<=24)return 111+n;}
    return codes[event.code]||null;
  }
  function label(key,mods=0){
    if(!key)return '未绑定';
    const base=key>=65&&key<=90?String.fromCharCode(key):key>=48&&key<=57?String.fromCharCode(key):key>=96&&key<=105?'Num'+(key-96):key>=112&&key<=135?'F'+(key-111):names[key]||('VK'+key);
    return [(mods&1)?'Ctrl':null,(mods&2)?'Alt':null,(mods&4)?'Shift':null,base].filter(Boolean).join('+');
  }
  function conflict(id,key,mods,units=[],status={},functions={}){
    if(!key)return '';
    const owner=units.find(unit=>unit.id!==id&&Number(unit.unit_shortcut?.key_code)===key);
    if(owner){
      const name=owner.display_name||owner.internal_name||owner.name||owner.id;
      return `${label(key,mods)} 的主键已被「${name}」占用，当前绑定为 ${label(key,owner.unit_shortcut.modifiers)}。请先解除该单位的绑定。`;
    }
    for(const [action,name] of Object.entries(functionNames)){
      const binding=parseBinding(functions[action]||status['key_'+action]);
      if(binding.key_code===key)return `${label(key,mods)} 的主键已被功能「${name}」占用，当前绑定为 ${label(key,binding.modifiers)}。`;
    }
    return systemConflict(key,mods);
  }
  function paint(){
    for(const button of document.querySelectorAll('.unit-keybox')){
      const id=button.dataset.unitKeyId,unit=options.unit(id),binding=unit?.unit_shortcut,waiting=pending.get(id);
      button.textContent=capture===id?'按键…':waiting?(waiting.key?label(waiting.key,waiting.mods)+'…':'清除中…'):binding?label(binding.key_code,binding.modifiers):'未绑定';
      button.disabled=!options.available()||pending.has(id);
      button.classList.toggle('capturing',capture===id);
      button.classList.toggle('key-error',errors.has(id)||!!(binding&&!binding.active));
      button.title=errors.get(id)||(binding&&!binding.active?binding.message:'点击后按键；Esc取消。默认不绑定。');
      if(!options.available())button.title='游戏与新版单位快捷键模块连接后可设置';
    }
    for(const button of document.querySelectorAll('.unit-keyclear')){
      const id=button.dataset.unitKeyId;
      button.hidden=!options.unit(id)?.unit_shortcut;
      button.disabled=!options.available()||pending.has(id);
    }
  }
  function cancel(){clearTimeout(timer);capture=null;paint();}
  async function submit(id,key,mods){
    cancel();errors.delete(id);
    const job={key,mods};pending.set(id,job);paint();
    try{
      if(options.refreshBindings)await options.refreshBindings();
      const reason=conflict(id,key,mods,options.units?.()||[],options.status?.()||{},options.functions?.()||{});
      if(reason)throw new Error(reason);
      const result=await options.request(id,key,mods);job.id=result.id;options.refresh();
    }
    catch(error){pending.delete(id);errors.set(id,error.message);options.notify(error.message);paint();}
  }
  function render(unit){
    const row=document.createElement('div');row.className='unit-key-row';
    const caption=document.createElement('span');caption.textContent='快捷键';
    const button=document.createElement('button');button.type='button';button.className='unit-keybox';button.dataset.unitKeyId=unit.id;button.textContent=unit.unit_shortcut?label(unit.unit_shortcut.key_code,unit.unit_shortcut.modifiers):'未绑定';button.setAttribute('aria-label','设置'+(unit.display_name||unit.name)+'的召唤快捷键');
    button.addEventListener('click',event=>{event.stopPropagation();cancel();options.cancelOther?.();if(!options.available())return;capture=unit.id;errors.delete(unit.id);paint();timer=setTimeout(cancel,15000);});
    const clear=document.createElement('button');clear.type='button';clear.className='unit-keyclear';clear.dataset.unitKeyId=unit.id;clear.textContent='×';clear.hidden=!unit.unit_shortcut;clear.setAttribute('aria-label','清除'+(unit.display_name||unit.name)+'的召唤快捷键');
    clear.addEventListener('click',event=>{event.stopPropagation();submit(unit.id,0,0);});
    row.append(caption,button,clear);return row;
  }
  function observe(jobs){
    for(const [id,request] of pending){
      const job=jobs?.find(j=>j.id===request.id);
      if(!job||['queued','pending'].includes(job.status))continue;
      pending.delete(id);
      if(job.status==='succeeded'){errors.delete(id);options.changed();}
      else errors.set(id,conflict(id,request.key,request.mods,options.units?.()||[],options.status?.()||{},options.functions?.()||{})||job.message||'绑定未确认');
      options.notify(errors.get(id)||job.message||'快捷键状态已更新');
    }
    paint();
  }
  function init(config){
    options=config;
    document.addEventListener('keydown',event=>{
      if(!capture)return;
      event.preventDefault();event.stopPropagation();
      if(event.key==='Escape'){cancel();return;}
      if(event.repeat)return;
      if(event.metaKey){options.notify('Win等系统快捷键无法可靠捕获，请换一个键。');return;}
      if(['Control','Shift','Alt'].includes(event.key))return;
      const key=keyCode(event);
      if(!key){options.notify('这个按键未识别，请使用普通键或 Ctrl / Alt / Shift 组合。');return;}
      const mods=(event.ctrlKey?1:0)|(event.altKey?2:0)|(event.shiftKey?4:0);
      submit(capture,key,mods);
    },true);
  }
  return {init,render,paint,observe,label,keyCode,conflict,cancel,parseBinding,systemConflict,functionNames};
})();
if(typeof module!=='undefined')module.exports=UnitShortcuts;
