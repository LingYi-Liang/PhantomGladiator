"use strict";
const DiskBrowser=(()=>{
  let offset=0,token=0,previousSearch="",api=null,lastKey="",lastData=null;
  const limit=100,$=id=>document.getElementById(id);
  const labels={package:"资源包／地图",script:"脚本",config:"配置",bulk:"大块数据",other:"其它"};
  function node(tag,cls,text){const el=document.createElement(tag);el.className=cls;el.textContent=text;return el;}
  function show(active){
    $("disk-panel").hidden=!active;
    for(const selector of ['.taxonomy-filters','.filter-options','#inventory-summary','#taxonomy-note','#unit-key-help','#catalog','.workspace>.catalog-footer','aside .selection']){
      const el=document.querySelector(selector);if(el)el.hidden=active;
    }
    $("search").placeholder=active?"搜索解密文件名、目录或资源包路径":"搜索角色、章节或地图";
    $("catalog-eyebrow").textContent=active?"磁盘资源":"单位图鉴";
    $("catalog-heading").textContent=active?"浏览原始文件":"选择你的参赛者";
    if(!active)++token;
  }
  function paint(data){
    const list=$("disk-files");list.replaceChildren();
    if(!data.available){$("disk-summary").textContent="尚未读取到已验证的解密目录。";$("disk-count").textContent="目录未就绪";$("disk-prev").hidden=true;$("disk-next").hidden=true;return;}
    const cross=data.registry_crosscheck;
    $("disk-summary").textContent=`已验证 ${data.total.toLocaleString()} 个文件条目${cross?` · ${cross.matched.toLocaleString()} 个资源包与注册表对应`:""}`;
    if(!data.files.length)list.append(node("p","hint","没有符合当前搜索条件的文件。"));
    for(const file of data.files){
      const row=node("div","disk-row","");
      const details=node("div","disk-path","");details.append(node("strong","",file.file_path.split('/').pop()),node("code","",file.file_path));
      if(file.virtual_package)details.append(node("small","muted",file.virtual_package));
      row.append(details,node("span","disk-kind",labels[file.kind]||file.kind),node("small","muted",file.container));list.append(row);
    }
    $("disk-count").textContent=`匹配 ${data.matched.toLocaleString()} 条 · ${data.files.length?offset+1:0}–${offset+data.files.length}`;
    $("disk-prev").hidden=offset===0;$("disk-next").hidden=offset+limit>=data.matched;
  }
  async function render(loader){
    api=loader;const query=$("search").value.trim(),kind=$("disk-kind").value;
    const search=JSON.stringify([query,kind]);if(search!==previousSearch){offset=0;previousSearch=search;}
    const key=JSON.stringify([search,offset]),generation=++token;if(key===lastKey&&lastData){paint(lastData);return;}
    $("disk-summary").textContent="正在检索已解密目录…";
    try{
      const data=await api(`/api/disk-directory?q=${encodeURIComponent(query)}&kind=${encodeURIComponent(kind)}&offset=${offset}&limit=${limit}`);
      if(generation!==token)return;lastData=data;lastKey=key;paint(data);
    }catch(error){if(generation===token)$("disk-summary").textContent=`目录读取失败：${error.message}`;}
  }
  function bind(){
    $("disk-kind").addEventListener("change",()=>{offset=0;if(api)render(api);});
    $("disk-prev").addEventListener("click",()=>{offset=Math.max(0,offset-limit);if(api)render(api);});
    $("disk-next").addEventListener("click",()=>{offset+=limit;if(api)render(api);});
  }
  return {show,render,bind};
})();
