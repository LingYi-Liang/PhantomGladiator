"use strict";
window.PGLocalAudio = (() => {
  const escape = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" })[c]);
  let busy = false, shown = "", localMessage = "";
  function html() {
    return `<div class="local-music"><h3>指定 BOSS 的本地音乐</h3><p class="muted">导入后，将上方播放方式改为「本地替换指定 BOSS」并保存。开战后循环播放，来源死亡、离场或停止对战后结束；多个 BOSS 同时参战只播放一首。需要保持助手运行。</p>
      <p class="muted">支持 MP3、WAV、FLAC、AAC、M4A、OGG、OPUS、WMA 等可解码音频；单文件最多 512 MB、30 分钟。损坏、受保护或处理超时的文件会跳过。</p>
      <div class="music-controls"><label>BOSS<select class="select" id="local-music-boss"></select></label><button class="btn btn-secondary" data-action="local-music-import" id="local-music-import">选择本地音频</button><label>音量<input class="input" id="local-music-volume" type="number" min="0" max="100" value="50"></label><button class="btn btn-secondary" data-action="local-music-volume">保存音量</button><button class="btn btn-secondary" data-action="local-music-retry">重试本场播放</button></div>
      <div id="local-music-list"></div><p class="muted" id="local-music-status" aria-live="polite"></p></div>`;
  }
  function render() {
    const s=window.PGRuntime.state.localAudio || {}, select=document.querySelector("#local-music-boss");if(!select)return;
    const rows=s.bosses || [], signature=JSON.stringify([s.revision,rows,s.mapping]);
    if(shown!==signature || !select.options.length) {
      const current=select.value;select.innerHTML=rows.map(b=>`<option value="${escape(b.id)}">${escape(b.name)}</option>`).join("");
      if(rows.some(b=>b.id===current))select.value=current;
      const names=new Map(rows.map(b=>[b.id,b.name]));
      document.querySelector("#local-music-list").innerHTML=Object.entries(s.mapping || {}).map(([id,row])=>`<div class="row"><div class="row-main"><div class="row-title">${escape(names.get(id) || id)}</div><div class="row-desc">${escape(row.name)} · ${Math.ceil(row.seconds || 0)} 秒</div></div><button class="btn btn-secondary btn-sm" data-action="local-music-remove" data-id="${escape(id)}">移除</button></div>`).join("");
      const volume=document.querySelector("#local-music-volume");if(document.activeElement!==volume)volume.value=s.volume ?? 50;
      shown=signature;
    }
    for(const button of document.querySelectorAll(".local-music button"))button.disabled=!s.supported || busy || !!s.importing;
    document.querySelector("#local-music-status").textContent=localMessage || (!s.supported ? "本地音频组件不可用，请使用完整桌面版。" : s.message || "尚未配置本地音乐。");
  }
  async function act(action,element) {
    const rt=window.PGRuntime;if(busy || !rt.localAudio)return;busy=true;localMessage="";render();
    try {
      let request;
      if(action==="import") {
        const boss=document.querySelector("#local-music-boss").value;if(!boss)return;
        const path=await rt.localAudio.pick();if(!path)return;request={action:"import",boss,path};
      } else if(action==="remove")request={action:"remove",boss:element.dataset.id};
      else if(action==="volume") {
        const value=document.querySelector("#local-music-volume").value;
        if(!/^\d{1,3}$/.test(value) || Number(value)>100)throw new Error("音量请输入 0～100");
        request={action:"volume",volume:Number(value)};
      } else request={action:"retry"};
      await rt.localAudio.change(request);
    } catch(error) { localMessage=error.message || "本地音乐操作失败，原配置继续保留。"; }
    finally {busy=false;render();}
  }
  return {html,render,act};
})();
