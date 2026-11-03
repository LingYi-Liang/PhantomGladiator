package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Probe=require('codex_art_probe')
local function object(fields)
    fields.IsValid=function()return true end
    return fields
end
local function soft(path)return {GetObjectID=function()return {GetAssetPathName=function()return path end} end} end
local PNG='\137PNG\r\n\26\n..'
local function harness()
    local h={logs={},files={},now=0,ready=true,loaded={},draws={},rts={}}
    h.world=object({GetAddress=function()return 1 end})
    local function row(class,name,boss,pictures)
        local r={EnemyClass=soft(class),Enemy_CH_Hans_Name=name,bIsBoss=boss}
        for k,v in pairs(pictures)do r[k]=soft(v) end
        return r
    end
    local entries={
        row('/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword.BP_Monster_MaleThug_Sword_C','暴徒',false,
            {WhiteIcon='/Game/UI/T_Thug_W.T_Thug_W',HalfBodyTexture='/Game/UI/T_Thug_H.T_Thug_H'}),
        row('/PBZCombatAsset/ActorData/Mobs/042_AHua/BP_Monster_AHua_GuiTouDao.BP_Monster_AHua_GuiTouDao_C','新娘阿花',true,
            {WhiteIcon='/Game/UI/T_AHua_W.T_AHua_W',HighPrecisionTexture='/Game/UI/T_AHua_HP.T_AHua_HP',HalfBodyTexture='/Game/UI/T_AHua_H.T_AHua_H'}),
        row('/PBZCombatAsset/ActorData/Mobs/999_None/BP_None.BP_None_C','没有图',false,{}),
    }
    h.codex=object({GetOuter=function()return h.world end,GetAllEnemyCodexEntries=function()return entries end})
    local function texture(path,w,hgt)
        return object({path=path,Blueprint_GetSizeX=function()return w end,Blueprint_GetSizeY=function()return hgt end})
    end
    h.textures={['/Game/UI/T_Thug_W.T_Thug_W']=texture('/Game/UI/T_Thug_W.T_Thug_W',256,256),
        ['/Game/UI/T_Thug_H.T_Thug_H']=texture('/Game/UI/T_Thug_H.T_Thug_H',2048,2048),
        ['/Game/UI/T_AHua_W.T_AHua_W']=texture('/Game/UI/T_AHua_W.T_AHua_W',256,256),
        ['/Game/UI/T_AHua_HP.T_AHua_HP']=texture('/Game/UI/T_AHua_HP.T_AHua_HP',2048,1024),
        ['/Game/UI/T_AHua_H.T_AHua_H']=texture('/Game/UI/T_AHua_H.T_AHua_H',2200,2048)}
    local canvas=object({K2_DrawTexture=function(_,tex,pos,size)h.draws[#h.draws+1]={tex=tex,w=size.X,h=size.Y} end})
    h.krl=object({CreateRenderTarget2D=function(_,world,w,hgt,format)
            assert(world==h.world and (format==2 or format==3));local rt=object({rt=true,w=w,h=hgt,format=format});h.rts[#h.rts+1]=rt;return rt end,
        BeginDrawCanvasToRenderTarget=function(_,world,rt,out)out.Canvas=canvas;out.Context='ctx' end,
        EndDrawCanvasToRenderTarget=function(_,world,ctx)assert(ctx=='ctx')end,
        ReleaseRenderTarget2D=function(_,rt)rt.released=true end,
        -- A render target goes out as PNG; a texture as it is goes out as HDR (what older engines write).
        ExportRenderTarget=function(_,world,rt,dir,name)h.files[dir..'/'..name]={head=PNG,size=rt.w*rt.h}end,
        ExportTexture2D=function(_,world,tex,dir,name)h.files[dir..'/'..name]={head='#?RADIANCE',size=77}end})
    local fs={open=function(path,mode)
        if mode=='rb' then
            local f=h.files[path];if not f then return nil end
            return {read=function()return f.head end,seek=function()return f.size end,close=function()end}
        end
        local text=''
        return {write=function(_,s)text=text..s end,close=function()h.files[path]={text=text}end}
    end}
    h.probe=Probe.new({log=function(s)h.logs[#h.logs+1]=s end,io=fs,path='rt',clock=function()return h.now end,
        ready=function()return h.ready end,getWorld=function()return h.world end,findAll=function(name)assert(name=='PBZCodexSubsystem');return {h.codex} end,
        staticFind=function(path)
            if path=='/Script/Engine.Default__KismetRenderingLibrary' then return h.krl end
            return h.loaded[path] and h.textures[path] or nil
        end,
        loadAsset=function(path)h.loaded[path]=true end})
    function h:line(pattern)for _,s in ipairs(self.logs)do if s:find(pattern,1,true) then return s end end end
    return h
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('runs once, 20 s after the game is ready, wanted units first',function()
    local h=harness();h.ready=false;h.probe:tick();h.now=100;h.probe:tick();assert(#h.logs==0)
    h.ready=true;h.probe:tick();h.now=119;h.probe:tick();assert(#h.logs==0,'waits 20 s')
    h.now=120;h.probe:tick()
    assert(h:line('图鉴 2 条有图，试导出 2 只；渲染函数库=true'),h.logs[1])
    assert(h.logs[2]:find('新娘阿花 白色图标',1,true),'Ah Hua is wanted before the thug: '..h.logs[2])
    local n=#h.logs;h.now=500;h.probe:tick();assert(#h.logs==n,'once per load')
end)
test('each picture is drawn on an sRGB target of at most 1024 and exported as PNG; the first unit also tries the rest',function()
    local h=harness();h.probe:tick();h.now=20;h.probe:tick()
    local half=assert(h:line('新娘阿花 半身像'))
    assert(half:find('原尺寸=2200x2048 画布导出调用=true 尺寸=1024x953 字节=975872 格式=PNG',1,true),half)
    assert(half:find('线性画布=true/975872/PNG 直接导出=true/77/HDR',1,true),half)
    local thug=assert(h:line('暴徒 半身像'))
    assert(thug:find('尺寸=1024x1024 字节=1048576 格式=PNG',1,true) and not thug:find('线性画布',1,true),'only the first unit tries the extras: '..thug)
    for _,rt in ipairs(h.rts)do assert(rt.released,'every render target is released') end
    assert(h.rts[1].format==3 and h.rts[2].format==2,'sRGB first, then the linear comparison')
    local tsv=h.files['rt/codex-art-probe.tsv'].text
    assert(tsv:find('1\t新娘阿花\t/PBZCombatAsset/ActorData/Mobs/042_AHua/BP_Monster_AHua_GuiTouDao.BP_Monster_AHua_GuiTouDao_C\tHalfBodyTexture\t/Game/UI/T_AHua_H.T_AHua_H\t2200\t2048\tcanvas-srgb\t975872\tPNG\tcodex-art-1-BP_Monster_AHua_GuiTouDao_C-HalfBodyTexture.png',1,true),tsv)
    assert(tsv:find('\ttexture2d\t77\tHDR\t',1,true) and not tsv:find('没有图',1,true))
    assert(h:line('导出结束'))
end)
test('a missing codex subsystem stops without exporting',function()
    local h=harness();h.codex.GetOuter=function()return object({GetAddress=function()return 2 end})end
    h.probe:tick();h.now=20;h.probe:tick();assert(h:line('图鉴子系统没找到') and next(h.files)==nil)
end)
print('codex_art_probe: PASS ('..count..' timing, selection, export path and failure regressions)')
