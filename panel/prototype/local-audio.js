"use strict";
window.PGLocalAudio = (() => {
  const t = (key, params) => I18N.t(key, params);
  const escape = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" })[c]);
  let busy = false, shown = "", localMessage = "";
  function html() {
    return `<div class="local-music"><h3>${t("localAudio.bossAudio")}</h3><p class="muted">${t("localAudio.audioHint")}</p>
      <p class="muted">${t("localAudio.formats")}</p>
      <div class="music-controls"><label>BOSS<select class="select" id="local-music-boss"></select></label><button class="btn btn-secondary" data-action="local-music-import" id="local-music-import">${t("localAudio.choose")}</button><label>${t("localAudio.volume")}<input class="input" id="local-music-volume" type="number" min="0" max="100" value="50"></label><button class="btn btn-secondary" data-action="local-music-volume">${t("localAudio.saveVolume")}</button><button class="btn btn-secondary" data-action="local-music-retry">${t("localAudio.retryAudio")}</button></div>
      <div id="local-music-list"></div><p class="muted" id="local-music-status" aria-live="polite"></p></div>`;
  }
  function render() {
    const s=window.PGRuntime.state.localAudio || {}, select=document.querySelector("#local-music-boss");if(!select)return;
    const rows=s.bosses || [], signature=JSON.stringify([I18N.lang,s.revision,rows,s.mapping]);
    if(shown!==signature || !select.options.length) {
      const current=select.value;select.innerHTML=rows.map(b=>`<option value="${escape(b.id)}">${escape(window.PGUnitName?.(b.id) || b.name)}</option>`).join("");
      if(rows.some(b=>b.id===current))select.value=current;
      const names=new Map(rows.map(b=>[b.id,window.PGUnitName?.(b.id) || b.name]));
      document.querySelector("#local-music-list").innerHTML=Object.entries(s.mapping || {}).map(([id,row])=>`<div class="row"><div class="row-main"><div class="row-title">${escape(names.get(id) || id)}</div><div class="row-desc">${escape(row.name)} · ${Math.ceil(row.seconds || 0)} ${t("localAudio.seconds")}</div></div><button class="btn btn-secondary btn-sm" data-action="local-music-remove" data-id="${escape(id)}">${t("localAudio.remove")}</button></div>`).join("");
      const volume=document.querySelector("#local-music-volume");if(document.activeElement!==volume)volume.value=s.volume ?? 50;
      shown=signature;
    }
    for(const button of document.querySelectorAll(".local-music button"))button.disabled=!s.supported || busy || !!s.importing;
    document.querySelector("#local-music-status").textContent=I18N.combatMessage(localMessage) || (!s.supported ? t("localAudio.unavailable") : I18N.combatMessage(s.message) || t("localAudio.noAudio"));
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
        if(!/^\d{1,3}$/.test(value) || Number(value)>100)throw new Error(`${t("localAudio.invalidVolume")}100`);
        request={action:"volume",volume:Number(value)};
      } else request={action:"retry"};
      await rt.localAudio.change(request);
    } catch(error) { localMessage=error.message || t("localAudio.failed"); }
    finally {busy=false;render();}
  }
  return {html,render,act};
})();
