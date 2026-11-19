package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Keys=require('teleport_keys')
local dir=os.getenv('TEMP') or os.getenv('TMP') or '.'
local stamp=tostring(os.time())..tostring(math.random(1,1e6))
local runs=0
local function fixture(opts)
    opts=opts or {}
    runs=runs+1
    local h={logs={},went={},ready=true,taken={},path=opts.path or (dir..'/pg-tpkeys-'..stamp..'-'..runs)}
    os.execute('mkdir "'..h.path:gsub('/','\\')..'" >nul 2>nul')
    h.router={slots={},ensure=function(self,vk,mask)
        if h.routerFails then return false,'按键注册没有得到确认' end
        self.slots[vk..':'..mask]=true;return true
    end}
    h.mod=Keys.new({path=h.path,log=function(s)h.logs[#h.logs+1]=s end,router=h.router,
        keys={F8=119,F9=120,A=65,F10=121},
        valid=function(target)return ({TAAA='沐小葵',TBBB='左殇'})[target]end,
        go=function(target)h.went[#h.went+1]=target;return {ok=true,message='已发起传送'}end,
        ready=function()return h.ready,'游戏尚未就绪'end,
        reserved=function(vk,mask)return h.taken[vk..':'..mask]end})
    function h:logged(text)local n=0;for _,line in ipairs(self.logs)do if line:find(text,1,true)then n=n+1 end end;return n end
    function h:file(name)local f=io.open(self.path..'/'..name,'rb');if not f then return nil end;local s=f:read('a');f:close();return s end
    return h
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end

test('a place key and the return key are saved, routed and teleport on one press',function()
    local h=fixture();h.mod:start()
    assert(h.mod:configure('TAAA',119,0).ok and h.mod:configure('BACK',120,1).ok)
    assert(h.router.slots['119:0'] and h.router.slots['120:1'] and h.mod.revision==2)
    assert(h:file('teleport-keybinds.tsv')=='TeleportKeysV1\t2\nBACK\t120\t1\nTAAA\t119\t0\n')
    assert(h:file('teleport-keybinds-state.tsv'):find('\nBACK\t120\t1\t1\t\nTAAA\t119\t0\t1\t\n',1,true),'the app reads the keys and whether each is live')
    assert(h.mod:dispatch(119,0)==true and #h.went==1 and h.went[1]=='TAAA','one press, no confirmation')
    assert(h.mod:dispatch(120,1)==true and h.went[2]=='BACK')
    assert(h.mod:dispatch(120,0)==nil and h.mod:dispatch(65,0)==nil and #h.went==2,'another chord is not ours')
    assert(h.mod:owner(119,0)=='传送：沐小葵' and h.mod:owner(120,1)=='传送：返回传送前的位置' and h.mod:owner(119,1)==nil)
    assert(h:logged('传送快捷键 vk=119 modifiers=0 目标=沐小葵；读回=已发起传送')==1)
    h.ready=false;h.mod:dispatch(119,0);assert(#h.went==2 and h.mod.message=='未传送：游戏尚未就绪')
end)
test('keys that are taken, unknown or malformed are refused and nothing is saved',function()
    local h=fixture();h.mod:start()
    assert(h.mod:configure('TAAA',119,0).ok)
    local r=h.mod:configure('TBBB',119,0);assert(not r.ok and r.message:find('已被「传送：沐小葵」占用',1,true))
    h.taken['120:0']='功能「开战」';r=h.mod:configure('TBBB',120,0);assert(not r.ok and r.message=='该键已被功能「开战」占用')
    assert(not h.mod:configure('TBBB',121,0).ok,'the console key')
    assert(not h.mod:configure('TBBB',66,0).ok,'a key this UE4SS does not offer')
    assert(not h.mod:configure('TZZZ',65,0).ok and not h.mod:configure('t aaa',65,0).ok and not h.mod:configure('TBBB',65,9).ok and not h.mod:configure('TBBB',300,0).ok)
    h.routerFails=true;assert(not h.mod:configure('TBBB',65,0).ok)
    assert(h.mod.revision==1 and h:file('teleport-keybinds.tsv')=='TeleportKeysV1\t1\nTAAA\t119\t0\n')
end)
test('a key can be moved and removed, and the saved file comes back after a restart',function()
    local h=fixture();h.mod:start()
    assert(h.mod:configure('TAAA',119,0).ok and h.mod:configure('TAAA',65,2).ok)
    assert(h.mod:dispatch(119,0)==nil and h.mod:dispatch(65,2)==true and h.went[1]=='TAAA','the old chord is free again')
    local again=fixture({path=h.path});again.mod:start()
    assert(again.mod.revision==2 and again.mod:dispatch(65,2)==true and again.went[1]=='TAAA')
    assert(again.mod:configure('TAAA',0,0).ok and again.mod:dispatch(65,2)==nil and again:file('teleport-keybinds.tsv')=='TeleportKeysV1\t3\n')
    local f=io.open(h.path..'/teleport-keybinds.tsv','wb');f:write('TeleportKeysV1\t4\nTAAA\t119\t0\nTBBB\t119\t0\n');f:close()
    local broken=fixture({path=h.path});broken.mod:start()
    assert(broken.mod.revision==0 and broken.mod:dispatch(119,0)==nil and broken:logged('文件格式无效')==1,'a file with one chord twice enables nothing')
    f=io.open(h.path..'/teleport-keybinds.tsv','wb');f:write('TeleportKeysV1\t5\nTGONE\t119\t0\n');f:close()
    local stale=fixture({path=h.path});stale.mod:start()
    assert(stale.mod:dispatch(119,0)==nil and stale:file('teleport-keybinds-state.tsv'):find('TGONE\t119\t0\t0\t这个地点不在本版模组的地点表里',1,true))
end)
print('teleport keys: PASS '..n..' save/route/press/conflict/restart checks; no game accessed')
