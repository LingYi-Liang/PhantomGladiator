package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Router=require('key_router');local Functions=require('function_keybinds')
local function fixture(initial)
    local h={files=initial or {},slots={},queue={},calls={},inGame=false,unitOwner=nil,renameCalls=0}
    local keys={};for i=1,24 do keys['F'..i]=111+i end;for i=65,90 do keys[string.char(i)]=i end
    for i=0,9 do keys['DIGIT'..i]=48+i;keys['NUM'..i]=96+i end
    local function slot(vk,mods)local mask=0;for _,v in ipairs(mods or {})do mask=mask+v end;return vk..':'..mask end
    h.router=Router.new({keys=keys,modifiers={CONTROL=1,ALT=2,SHIFT=4},
        occupied=function(vk,mods)return h.slots[slot(vk,mods)]~=nil end,
        register=function(vk,mods,callback)
            if type(mods)=='function'then callback=mods;mods={}end
            if not h.rejectRegister then h.slots[slot(vk,mods)]=callback end
        end})
    local fs={open=function(path,mode)
        local writing=mode:sub(1,1)=='w'
        if (writing and h.failWrite) or (not writing and h.files[path]==nil)then return nil end
        local value=h.files[path] or ''
        return {write=function(_,s)value=s;return true end,flush=function()return true end,
            close=function()if writing then h.files[path]=value end;return true end,
            read=function()
                if h.onRead then h.onRead(path)end
                if h.badTargetReadOnce and path=='memory/function-keybinds.tsv' then h.badTargetReadOnce=false;return 'bad'end
                return h.corruptRead and 'bad' or value
            end}
    end}
    local ops={remove=function(path)h.files[path]=nil;return true end,
        rename=function(from,to)
            h.renameCalls=h.renameCalls+1
            if h.failRename or h.renameCalls==h.failRenameAt or not h.files[from] or h.files[to] then return nil end
            h.files[to]=h.files[from];h.files[from]=nil;return true
        end}
    h.options={path='memory',router=h.router,io=fs,os=ops,
        unitOwner=function(vk)return h.unitOwner and h.unitOwner[vk]end,
        queue=function(fn)h.queue[#h.queue+1]=fn end,
        dispatch=function(action)assert(h.inGame);h.calls[#h.calls+1]=action end}
    h.functions=Functions.new(h.options);h.functions:start()
    h.router.dispatch=function(vk,mask)h.functions:press(vk,mask)end
    function h:drain()self.inGame=true;while #self.queue>0 do table.remove(self.queue,1)()end;self.inGame=false end
    function h:proposal(changes)
        local out={};for _,action in ipairs(Functions.actions)do out[action]={key_code=0,modifiers=0}end
        for action,value in pairs(changes or {})do out[action]=value end;return out
    end
    return h
end
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
test('all eight functions default unbound and install no hidden fixed callbacks',function()
    local h=fixture();assert(next(h.slots)==nil)
    for _,name in ipairs(Functions.actions)do assert(h.functions.entries[name].key_code==0 and h.functions:token(name)=='')end
end)
test('new functions save with modifiers and dispatch only on the game queue',function()
    local h=fixture();local p=h:proposal({toggle_camera={key_code=117,modifiers=1},exit_camera='F7',cycle_team='F2',toggle_spectator='F8'})
    assert(h.functions:configure(p).ok)
    h.slots['117:1']();h.slots['118:0']();h.slots['113:0']();h.slots['119:0']()
    assert(#h.calls==0 and #h.queue==4);h:drain()
    assert(table.concat(h.calls,',')=='toggle_camera,exit_camera,cycle_team,toggle_spectator')
    local reloaded=Functions.new(h.options);assert(reloaded.entries.toggle_camera.key_code==117 and reloaded.entries.toggle_camera.modifiers==1)
end)
test('old callbacks and already queued presses become inert after a successful remap or clear',function()
    local h=fixture();assert(h.functions:configure(h:proposal({toggle_camera='F6'})).ok)
    h.slots['117:0']();assert(#h.queue==1)
    assert(h.functions:configure(h:proposal({toggle_camera='F7'})).ok)
    h:drain();h.slots['117:0']();assert(#h.queue==0 and #h.calls==0)
    h.slots['118:0']();h:drain();assert(h.calls[1]=='toggle_camera')
    assert(h.functions:configure(h:proposal()).ok);h.slots['118:0']();assert(#h.queue==0)
end)
test('functions can swap their owned keys in one transaction',function()
    local h=fixture();assert(h.functions:configure(h:proposal({toggle_camera='F6',exit_camera='F7'})).ok)
    assert(h.functions:configure(h:proposal({toggle_camera='F7',exit_camera='F6'})).ok)
    h.slots['117:0']();h:drain();assert(h.calls[1]=='exit_camera')
end)
test('conflicts identify the function or unit and preserve the previous binding',function()
    local h=fixture();assert(h.functions:configure(h:proposal({toggle_camera='F6'})).ok)
    local result=h.functions:configure(h:proposal({toggle_camera='F6',exit_camera='F6'}))
    assert(not result.ok and result.message:find('自由观战',1,true) and result.message:find('退出自由观战',1,true))
    h.unitOwner={[113]='测试暴徒'};result=h.functions:configure(h:proposal({cycle_team='F2'}))
    assert(not result.ok and result.message:find('测试暴徒',1,true) and h.functions:token('toggle_camera')=='VK_117_MOD_0')
end)
test('external modifiers and host registration failures never activate or overwrite a key',function()
    local h=fixture();h.slots['119:4']=function()end
    assert(not h.functions:configure(h:proposal({toggle_spectator='F8'})).ok and not h.slots['119:0'])
    h.rejectRegister=true;assert(not h.functions:configure(h:proposal({toggle_camera='F6'})).ok)
    assert(h.functions:token('toggle_camera')=='')
end)
test('failed writes, verification and rename keep active and durable settings unchanged',function()
    for _,mode in ipairs({'failWrite','corruptRead','failRename'})do
        local h=fixture();assert(h.functions:configure(h:proposal({toggle_camera='F6'})).ok)
        local old=h.files['memory/function-keybinds.tsv'];h[mode]=true
        assert(not h.functions:configure(h:proposal({toggle_camera='F7'})).ok)
        assert(h.functions.entries.toggle_camera.key_code==117 and h.files['memory/function-keybinds.tsv']==old)
    end
end)
test('explicit legacy saves migrate without assigning the four former fixed keys',function()
    local h=fixture({['memory/keybinds.tsv']='spawn\tF9\nstart\tF3\nstop\tF4\nrefresh_catalog\tF1\n'})
    assert(h.functions.entries.spawn.key_code==120 and h.functions.entries.start.key_code==114)
    for _,name in ipairs({'toggle_camera','exit_camera','cycle_team','toggle_spectator'})do assert(h.functions.entries[name].key_code==0)end
end)
test('a failed final rename restores the original durable file after the backup move',function()
    local h=fixture();assert(h.functions:configure(h:proposal({toggle_camera='F6'})).ok)
    local before=h.files['memory/function-keybinds.tsv'];h.failRenameAt=h.renameCalls+2
    assert(not h.functions:configure(h:proposal({toggle_camera='F7'})).ok)
    assert(h.files['memory/function-keybinds.tsv']==before and h.functions.entries.toggle_camera.key_code==117)
end)
test('backup recovery and unload preserve preferences without executing stale callbacks',function()
    local h=fixture();assert(h.functions:configure(h:proposal({toggle_camera='F6'})).ok)
    local saved=h.files['memory/function-keybinds.tsv'];h.files['memory/function-keybinds.tsv.bak']=saved;h.files['memory/function-keybinds.tsv']='incomplete'
    local recovered=Functions.new(h.options);assert(recovered.entries.toggle_camera.key_code==117)
    h.slots['117:0']();h.functions:silence();h.router:silence();h:drain();assert(#h.calls==0)
end)
test('a save from before recall keeps its eight keys and leaves recall unbound; a recall key dispatches recall',function()
    -- Written up to v0.38.1: eight lines, no recall_companions. It must not count as invalid (all keys unbound).
    local old='FunctionKeysV2\t4\nspawn\t120\t0\nstart\t114\t0\nstop\t115\t0\nrefresh_catalog\t0\t0\n'
        ..'toggle_camera\t117\t0\nexit_camera\t118\t0\ncycle_team\t113\t0\ntoggle_spectator\t119\t0\n'
    local h=fixture({['memory/function-keybinds.tsv']=old})
    assert(h.functions.revision==4 and h.functions.entries.toggle_camera.key_code==117)
    assert(h.functions.entries.recall_companions.key_code==0 and h.functions:token('recall_companions')=='')
    assert(h.functions.entries.toggle_time_stop.key_code==0 and h.functions:token('toggle_time_stop')=='')
    -- Still incomplete without one of the original eight.
    local broken=fixture({['memory/function-keybinds.tsv']='FunctionKeysV2\t5\nspawn\t120\t0\n'})
    assert(broken.functions.entries.spawn.key_code==0 and broken.functions.message:find('无效',1,true))
    assert(h.functions:configure(h:proposal({toggle_camera='F6',recall_companions='F5'})).ok)
    assert(h.files['memory/function-keybinds.tsv']:find('recall_companions\t116\t0',1,true))
    h.slots['116:0']();h:drain();assert(h.calls[#h.calls]=='recall_companions')
    -- The recall key is the recall key's alone: a second function on its main key is refused.
    local clash=h.functions:configure(h:proposal({toggle_camera='F5',recall_companions='F5'}))
    assert(not clash.ok and clash.message:find('召回随从到身边',1,true),clash.message)
end)
print('function_keybinds: PASS ('..passed..' persistence, routing and conflict regressions)')
