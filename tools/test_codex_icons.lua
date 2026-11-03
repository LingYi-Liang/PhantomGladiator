package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Icons=require('codex_icons')
local address=0
local function object(fields)
    address=address+1;local a=address
    fields.IsValid=function()return true end
    fields.GetAddress=function()return a end
    return fields
end
local function soft(path)return {GetObjectID=function()return {GetAssetPathName=function()return path end} end} end
local PNG='\137PNG'
local function harness(opts)
    opts=opts or {}
    local h={logs={},files={},now=0,ready=true,loaded={},draws={},exports={},clears=0}
    h.world=object({})
    local function icon(n)return '/Game/PBZContent/UI/InGame/Literature/Gallery/T_'..n..'_w.T_'..n..'_w' end
    local function class(dir,n)return '/PBZCombatAsset/ActorData/Mobs/'..dir..'/'..n..'.'..n..'_C' end
    h.entries={
        {EnemyClass=soft(class('042_AHua','BP_Monster_AHua_GuiTouDao')),WhiteIcon=soft(icon('BP_Monster_AHua_GuiTouDao')),
            AliasEnemyClasses={soft(class('042_AHua','BP_Monster_AHua_Story'))}},
        {EnemyClass=soft(class('003_MaleThug','BP_Monster_MaleThug_Sword')),WhiteIcon=soft(icon('BP_Monster_MaleThug_Sword'))},
        {EnemyClass=soft(class('003_MaleThug','BP_Monster_MaleThug_Sword_Blue')),WhiteIcon=soft(icon('BP_Monster_MaleThug_Sword'))},
        {EnemyClass=soft(class('025_FemaleThug','BP_Monster_FemaleThug_TwinHoe')),WhiteIcon=soft(icon('BP_Monster_FemaleThug_TwinHoe'))},
        {EnemyClass=soft(class('999','BP_NoIcon'))},
    }
    h.codex=object({GetOuter=function()return h.world end,GetAllEnemyCodexEntries=function()return h.entries end})
    h.textures={}
    for _,row in ipairs(h.entries)do
        local path=row.WhiteIcon and row.WhiteIcon.GetObjectID().GetAssetPathName()
        if path then h.textures[path]=object({path=path,Blueprint_GetSizeX=function()return 256 end,Blueprint_GetSizeY=function()return 256 end}) end
    end
    local canvas=object({K2_DrawTexture=function(_,tex,pos,size)h.draws[#h.draws+1]={tex=tex,x=pos.X,y=pos.Y,w=size.X,h=size.Y} end})
    h.krl=object({CreateRenderTarget2D=function(_,world,w,hgt,format)h.rt=object({w=w,h=hgt,format=format});return h.rt end,
        ClearRenderTarget2D=function()h.clears=h.clears+1 end,
        BeginDrawCanvasToRenderTarget=function(_,world,rt,out)out.Canvas=canvas;out.Context='ctx' end,
        EndDrawCanvasToRenderTarget=function()end,
        ReleaseRenderTarget2D=function(_,rt)rt.released=true end,
        ExportRenderTarget=function(_,world,rt,dir,name)
            h.exports[#h.exports+1]=dir..'/'..name
            if opts.noFolder and dir:find('/codex%-icons$') then return end
            h.files[dir..'/'..name]=PNG
        end})
    h.opens=0
    local fs={open=function(path,mode)
        if mode=='rb' then
            h.opens=h.opens+1
            local f=h.files[path];if not f then return nil end
            return {seek=function()return #f end,close=function()end}
        end
        if mode=='r' then
            local f=h.files[path];if not f then return nil end
            return {read=function()return f end,close=function()end}
        end
        local text=''
        return {write=function(self,s)text=text..s;return self end,close=function()h.files[path]=text end}
    end}
    local options={log=function(s)h.logs[#h.logs+1]=s end,io=fs,path='rt',clock=function()return h.now end,
        ready=function()return h.ready end,getWorld=function()return h.world end,
        findAll=function(name)assert(name=='PBZCodexSubsystem');return {h.codex} end,
        staticFind=function(path)
            if path=='/Script/Engine.Default__KismetRenderingLibrary' then return h.krl end
            return h.loaded[path] and h.textures[path] or nil
        end,
        loadAsset=function(path)h.loaded[path]=true end}
    h.icons=Icons.new(options)
    function h:reload()self.icons=Icons.new(options)end
    function h:run(times)for _=1,times do self.icons:tick() end end
    function h:line(pattern)for _,s in ipairs(self.logs)do if s:find(pattern,1,true) then return s end end end
    return h
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('ten seconds after the game is ready, each icon is drawn on one sRGB target and saved, two per tick',function()
    local h=harness();h.ready=false;h:run(3);assert(#h.logs==0)
    h.ready=true;h:run(1);h.now=9;h:run(1);assert(#h.logs==0,'waits 10 s')
    h.now=10;h:run(1)
    assert(h:line('图鉴 3 张图标，已有 0，待导出 3'),h.logs[1])
    assert(#h.exports==2,'two per tick')
    h:run(1)
    assert(#h.exports==3 and h.rt.format==3 and h.rt.w==256 and h.rt.released and h.clears==3)
    assert(h.draws[1].x==0 and h.draws[1].y==0 and h.draws[1].w==256 and h.draws[1].h==256)
    assert(h.files['rt/codex-icons/T_BP_Monster_AHua_GuiTouDao_w.png'],'saved in the folder')
    local done=assert(h:line('完成：图标 3 张（本次新存 3、已有 0、失败 0），对应单位 5 个，索引写入=true'))
    local index=h.files['rt/codex-icons.tsv']
    assert(index:sub(1,10)=='unit\tfile\n',index)
    assert(index:find('BP_Monster_AHua_GuiTouDao\tcodex-icons/T_BP_Monster_AHua_GuiTouDao_w.png',1,true))
    assert(index:find('BP_Monster_AHua_Story\tcodex-icons/T_BP_Monster_AHua_GuiTouDao_w.png',1,true),'aliases share the icon')
    assert(index:find('BP_Monster_MaleThug_Sword_Blue\tcodex-icons/T_BP_Monster_MaleThug_Sword_w.png',1,true),'two rows, one picture')
    assert(not index:find('BP_NoIcon',1,true))
    local n=#h.logs;h.now=100;h:run(3);assert(#h.logs==n,'once per load')
end)
test('icons already on disk are not saved again; the index still lists them',function()
    local h=harness()
    h.files['rt/codex-icons/T_BP_Monster_AHua_GuiTouDao_w.png']=PNG
    h.files['rt/codex-icon-T_BP_Monster_MaleThug_Sword_w.png']=PNG
    h:run(1);h.now=10;h:run(2)
    assert(#h.exports==1 and h:line('已有 2，待导出 1'))
    local index=h.files['rt/codex-icons.tsv']
    assert(index:find('BP_Monster_MaleThug_Sword\tcodex-icon-T_BP_Monster_MaleThug_Sword_w.png',1,true),'an earlier flat file is kept')
end)
test('when the folder cannot be written, icons go flat into Runtime',function()
    local h=harness({noFolder=true});h:run(1);h.now=10;h:run(3)
    assert(h:line('codex-icons 文件夹写不进去，改存在 Runtime 根目录'))
    assert(h.files['rt/codex-icon-T_BP_Monster_AHua_GuiTouDao_w.png'] and h.files['rt/codex-icon-T_BP_Monster_FemaleThug_TwinHoe_w.png'])
    assert(h:line('失败 0') and h:line('（存在 Runtime 根目录）'))
    assert(h.files['rt/codex-icons.tsv']:find('BP_Monster_FemaleThug_TwinHoe\tcodex-icon-T_BP_Monster_FemaleThug_TwinHoe_w.png',1,true))
end)
test('a world change stops the pass; a missing codex stops before saving',function()
    local h=harness();h:run(1);h.now=10;h:run(1)
    h.world.IsValid=function()return false end;h:run(2)
    assert(h:line('World 已变化，本次停止') and #h.exports==2)
    local g=harness();g.codex.GetOuter=function()return object({})end;g:run(1);g.now=10;g:run(1)
    assert(g:line('未导出：当前World的图鉴子系统没找到') and #g.exports==0)
end)
test('a later load takes the index on trust once one listed file checks out; without that file every one is checked',function()
    local h=harness();h:run(1);h.now=10;h:run(3)
    assert(h:line('完成：图标 3 张（本次新存 3'))
    h:reload();h.opens,h.exports,h.logs=0,{},{}
    h.now=20;h:run(1);h.now=30;h:run(1)
    assert(h:line('图鉴 3 张图标，已有 3，待导出 0；其中按索引认定 3'),h.logs[1])
    assert(h.opens==1 and #h.exports==0,'one file opened at load, nothing saved')
    assert(h:line('对应单位 5 个，索引写入=true'))
    -- The folder deleted (what the README suggests to export again): every file is checked and saved again.
    for path in pairs(h.files)do if path:find('/codex-icons/',1,true) then h.files[path]=nil end end
    h:reload();h.exports,h.logs={},{}
    h.now=40;h:run(1);h.now=50;h:run(3)
    assert(h:line('已有 0，待导出 3；其中按索引认定 0') and #h.exports==3)
end)
print('codex_icons: PASS ('..count..' timing, saving, index, fallback, stop and index-trust regressions)')
