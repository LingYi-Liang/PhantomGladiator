-- Tests the real panel_runtime.lua dispatcher with in-memory I/O and game queue.
-- No game process or runtime directory is accessed.
local SOURCE = "Mods/PhantomGladiator/Scripts/panel_runtime.lua"
assert(loadfile(SOURCE))
local passed = 0
local function test(name, fn) fn(); passed=passed+1; print("PASS "..name) end

local function harness(saved,withSpectator,withCodex)
    local h={files={},keys={},queue={},loops={},calls={},inGame=false,ioEvents={},occupied={},logs={},cancellations={},legacyCalls=0}
    if saved then h.files["memory/keybinds.tsv"]=saved
    else h.files['memory/function-keybinds.tsv']='FunctionKeysV2\t0\nspawn\t120\t0\nstart\t114\t0\nstop\t115\t0\nrefresh_catalog\t112\t0\ntoggle_camera\t0\t0\nexit_camera\t0\t0\ncycle_team\t113\t0\ntoggle_spectator\t'..(withSpectator and '119' or '0')..'\t0\n' end
    function h:run(fn)
        assert(not self.inGame); self.inGame=true
        local ok,result=pcall(fn); self.inGame=false; assert(ok,result); return result
    end
    function h:drain() while #self.queue>0 do self:run(table.remove(self.queue,1)) end end
    function h:tick()
        local loop=assert(self.loops[1],"no registered host timer")
        if not loop.cancelled then return self:run(loop.fn) end
    end
    local function record(name,...)
        assert(h.inGame,"handler outside game thread: "..name)
        h.calls[#h.calls+1]={name=name,args={...}}
        return {ok=true,message=name,spawned_count=0}
    end
    h.sessionState={game_session="test-session",game_ready=true,game_ready_reason="fixture ready"}
    local session={status=function()
        record("session_status")
        return {game_session=h.sessionState.game_session,game_ready=h.sessionState.game_ready,
            game_ready_reason=h.sessionState.game_ready_reason}
    end}
    local codex={export=function() record("codex_export");return {ok=true,message="fixture codex readback"} end}
    local memoryIO={open=function(path,mode)
        mode=mode:sub(1,1)
        h.ioEvents[#h.ioEvents+1]="open:"..mode
        if mode=="r" and h.files[path]==nil then return nil,"missing" end
        if mode=="w" and h.failWrite then return nil,"simulated write failure" end
        local content=h.files[path] or ""
        return {
            write=function(_,value) h.ioEvents[#h.ioEvents+1]="write";content=value;return true end,
            flush=function() h.ioEvents[#h.ioEvents+1]="flush";return true end,
            close=function()
                h.ioEvents[#h.ioEvents+1]="close"
                if mode=="w" then h.files[path]=content end
                return true
            end,
            read=function()
                h.ioEvents[#h.ioEvents+1]="read"
                if h.onRead then h.onRead(path) end
                return h.corruptRead and "corrupt readback" or content
            end,
        }
    end}
    local arena={
        spawn=function(_,...) return record("spawn",...) end,
        select=function(_,...) return record("select_unit",...) end,
        cycleTeam=function() return record("cycle_team") end,
        start=function() return record("start") end,
        stop=function() return record("stop") end,
        clearCompanions=function() return record("dismiss_companions") end,
        status=function()
            record("arena_status")
            return {blue_count=1,red_count=2,neutral_count=0,total=3,current_unit="unit",current_team="blue",current_count=1,state="ready",companion_count=2,companion_owned=3}
        end,
    }
    local exporter={
        start=function() record("refresh_catalog");return true,{} end,
        tick=function()
            record("export_tick")
            if h.failExportOnce then h.failExportOnce=false;error("simulated exporter tick failure") end
        end,
        status=function() record("catalog_status");return {active=false,complete=true,paths_done=1,paths_total=1,candidates=2,reason="complete"} end,
        silence=function() h.silenced=(h.silenced or 0)+1 end,
    }
    h.spectatorRequested=false
    local spectator={
        toggle=function()
            record("toggle_spectator")
            if h.spectatorToggleResult then return h.spectatorToggleResult end
            h.spectatorRequested=not h.spectatorRequested
            return {ok=true,message="spectator toggle readback"}
        end,
        tick=function() record("spectator_tick") end,
        status=function()
            record("spectator_status")
            return {enabled_requested=h.spectatorRequested,message="spectator status readback",readFailures=0}
        end,
        silence=function() h.spectatorSilences=(h.spectatorSilences or 0)+1 end,
        restore=function() error("unload must not restore game objects") end,
    }
    local Bridge={new=function(options)
        h.bridgeOptions=options
        local bridge={tick=function()
            record("bridge_tick")
            if h.inbox then
                local command=h.inbox;h.inbox=nil
                h.result=options.handlers[command.action](command)
            end
            h.reported=options.status()
        end}
        return bridge
    end}
    local env=setmetatable({io=memoryIO},{__index=_G})
    env._G=env
    env.require=function(name)
        if name=='panel_bridge'then return Bridge end
        assert(name=='key_router' or name=='function_keybinds')
        return assert(loadfile('Mods/PhantomGladiator/Scripts/'..name..'.lua','t',env))()
    end
    env.Key={};local keyNames={}
    for n=1,24 do env.Key['F'..n]=111+n;keyNames[111+n]='F'..n end
    for n,name in ipairs({'ZERO','ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE'})do env.Key['NUM_'..name]=95+n;keyNames[95+n]='NUM_'..name end
    for n=65,90 do env.Key[string.char(n)]=n;keyNames[n]=string.char(n)end
    env.ModifierKey={CONTROL=1,ALT=2,SHIFT=4}
    local function slot(key,mods)local mask=0;for _,value in ipairs(mods or {})do mask=mask+value end;return keyNames[key]..(mask==0 and '' or ':'..mask)end
    env.IsKeyBindRegistered=function(key,mods)return h.occupied[slot(key,mods)] or false end
    env.RegisterKeyBind=function(key,mods,fn)
        if type(mods)=='function'then fn=mods;mods={}end
        local name=slot(key,mods)
        assert(not h.keys[name],"duplicate registration");h.keys[name]=fn
        if not h.rejectRegistration then h.occupied[name]=true end
    end
    env.os=setmetatable({rename=function(from,to)if not h.files[from] or h.files[to]then return nil end;h.files[to]=h.files[from];h.files[from]=nil;return true end,
        remove=function(path)h.files[path]=nil;return true end},{__index=os})
    env.ExecuteInGameThread=function(fn)h.queue[#h.queue+1]=fn end
    env.LoopAsync=function()h.legacyCalls=h.legacyCalls+1;error("legacy async pump forbidden") end
    env.LoopInGameThreadWithDelay=function(ms,fn)
        local handle=100+#h.loops
        h.loops[#h.loops+1]={ms=ms,fn=fn,handle=handle,cancelled=false}
        return handle
    end
    env.CancelDelayedAction=function(handle)
        h.cancellations[#h.cancellations+1]=handle
        if h.cancelError then error("simulated host cancellation failure") end
        for _,loop in ipairs(h.loops)do
            if loop.handle==handle then loop.cancelled=true;return true end
        end
        return false
    end
    h.env=env
    local Runtime=assert(loadfile(SOURCE,"t",env))()
    h.new=function(extra)
        local options={path="memory",build="test",arena=arena,exporter=exporter,session=session,
            codex=withCodex and codex or nil,
            spectator=withSpectator and spectator or nil,log=function(s)h.logs[#h.logs+1]=s end}
        for key,value in pairs(extra or {})do options[key]=value end
        return Runtime.new(options)
    end
    h.runtime=h.new()
    return h
end
local function count(h,name)local n=0;for _,call in ipairs(h.calls)do if call.name==name then n=n+1 end end;return n end
local NEW={spawn="NUM_ONE",start="NUM_TWO",stop="NUM_THREE",refresh_catalog="NUM_FOUR",toggle_camera='UNBOUND',exit_camera='UNBOUND',cycle_team='F2',toggle_spectator='UNBOUND'}

test("explicit saved fixture keys dispatch only in game thread",function()
    local h=harness();h.runtime:start()
    local n=0;for _ in pairs(h.keys)do n=n+1 end
    assert(n==5 and h.keys.F6==nil and h.keys.F7==nil and h.keys.F8==nil and h.keys.F10==nil and h.keys.F12==nil)
    for _,key in ipairs({"F9","F3","F4","F1"})do h.keys[key]() end
    assert(#h.calls==0 and #h.queue==4)
    h:drain()
    for _,name in ipairs({"spawn","start","stop","refresh_catalog"})do assert(count(h,name)==1) end
end)
test("new bindings activate only after persisted readback; old keys stop dispatching",function()
    local h=harness();h.runtime:start()
    local checkedReadback=false
    h.onRead=function(path)
        if path=='memory/function-keybinds.tsv.tmp' or path=='memory/function-keybinds.tsv' then
            assert(h.runtime.functionKeys.entries.spawn.key_code==120,"mapping changed before readback")
            checkedReadback=true
        end
    end
    local result=h:run(function()return h.runtime:configure(NEW)end)
    assert(result.ok and checkedReadback and h.files["memory/function-keybinds.tsv"]:find("spawn\t97\t0",1,true))
    h.onRead=nil
    h.keys.F9();assert(#h.queue==0)
    h.keys.NUM_ONE();assert(#h.calls==0);h:drain();assert(count(h,"spawn")==1)
    assert(h.new().functionKeys.entries.spawn.key_code==97,"restart must read persisted mapping")
end)
test("configured team key cycles only spawn settings and participates in conflict checks",function()
    local h=harness();h.runtime:start()
    h.keys.F2();assert(#h.calls==0 and #h.queue==1)
    h:drain();assert(count(h,'cycle_team')==1 and count(h,'spawn')==0 and count(h,'start')==0)
    assert(h.runtime:unitKeyReserved(113)=='切换召唤队伍')
    local result=h:run(function()return h.runtime:configure({spawn='F2',start='F3',stop='F4',refresh_catalog='F1'})end)
    assert(not result.ok and h.files['memory/keybinds.tsv']==nil)
    h:tick();assert(h.reported,table.concat(h.logs,'\n'));assert(h.reported.key_cycle_team=='VK_113_MOD_0')
    h.keys.F2();h.runtime:silence();h:drain()
    assert(count(h,'cycle_team')==1,'queued team changes must be inert after unload')
end)
test("F2 activation requires host registration readback",function()
    local h=harness();h.rejectRegistration=true;h.runtime:start()
    h.keys.F2();h:drain();h:tick()
    assert(count(h,'cycle_team')==0 and h.reported.key_cycle_team=='')
    assert(h.runtime.functionKeys.active.cycle_team~=true)
end)
test("failed writes or wrong readback never change active bindings",function()
    for _,mode in ipairs({"failWrite","corruptRead"})do
        local h=harness();h.runtime:start();h[mode]=true
        local result=h:run(function()return h.runtime:configure(NEW)end)
        assert(not result.ok and h.runtime.functionKeys.entries.spawn.key_code==120)
        h.keys.NUM_ONE();assert(#h.queue==0)
        h.keys.F9();h:drain();assert(count(h,"spawn")==1)
    end
end)
test("duplicate reserved and occupied keys are rejected without replacing another mod",function()
    local h=harness();h.occupied.NUM_ONE=true;h.runtime:start();assert(h.keys.NUM_ONE==nil)
    for _,bad in ipairs({"F10","VK_82_MOD_1","NUM_TWO","NUM_ONE"})do
        local proposal={};for name,value in pairs(NEW)do proposal[name]=value end;proposal.spawn=bad
        local result=h:run(function()return h.runtime:configure(proposal)end)
        assert(not result.ok and h.runtime.functionKeys.entries.spawn.key_code==120)
    end
    assert(h.files["memory/keybinds.tsv"]==nil)
end)
test("one stable host timer runs repeated IPC ticks without per-tick game closures",function()
    local h=harness();h.runtime:start();local loop=h.loops[1]
    assert(loop.ms==250 and #h.loops==1 and h.runtime.pumpHandle==loop.handle and #h.queue==0 and #h.calls==0)
    h.inbox={action="select_unit",unit_id="chosen",team="red",count=3}
    assert(h:tick()==nil)
    assert(count(h,"export_tick")==1 and count(h,"bridge_tick")==1 and count(h,"select_unit")==1)
    assert(h.reported.key_spawn=="VK_120_MOD_0" and h.reported.blue_count==1)
    h.inbox={action="configure_keys",key_spawn="NUM_ONE",key_start="NUM_TWO",key_stop="NUM_THREE",key_refresh_catalog="NUM_FOUR"}
    h:tick();assert(h.result.ok and h.reported.key_spawn=="VK_97_MOD_0")
    h:tick();assert(count(h,"bridge_tick")==3 and #h.queue==0 and h.legacyCalls==0)
    assert(h.runtime:start() and #h.loops==1,"start must not duplicate the stable handle")
end)
test("unload makes queued hotkeys and IPC work inert without accessing handlers",function()
    local h=harness();h.runtime:start()
    h.keys.F9();h.queue[#h.queue+1]=h.loops[1].fn;assert(#h.queue==2)
    h.runtime:silence();assert(h.silenced==1 and h.loops[1].cancelled)
    assert(#h.cancellations==1 and h.cancellations[1]==h.loops[1].handle)
    local calls=#h.calls;h:drain();assert(#h.calls==calls)
    h.keys.F9();assert(#h.queue==0)
    assert(h:run(h.loops[1].fn)==nil and #h.queue==0 and #h.calls==calls)
    assert(h.runtime:dispatch("spawn",{})==nil and #h.calls==calls)
end)
test("configured spectator key and IPC use the same game-thread handler and reported state",function()
    local h=harness(nil,true);h.runtime:start()
    local n=0;for _ in pairs(h.keys)do n=n+1 end
    assert(n==6 and h.keys.F8 and h.keys.F6==nil and h.keys.F7==nil)
    h.keys.F8();assert(count(h,"toggle_spectator")==0 and #h.queue==1)
    h:drain();assert(count(h,"toggle_spectator")==1 and h.spectatorRequested==true)
    h:tick()
    assert(count(h,"spectator_tick")==1 and h.reported.spectator_enabled==true)
    assert(h.reported.spectator_message=="spectator status readback")
    h.inbox={action="toggle_spectator"};h:tick()
    assert(count(h,"toggle_spectator")==2 and h.result.ok and h.result.spawned_count==0)
    assert(h.reported.spectator_enabled==false)
    local invalid={spawn="F8",start="F3",stop="F4",refresh_catalog="F1"}
    assert(not h:run(function()return h.runtime:configure(invalid)end).ok)
    assert(h.runtime.functionKeys.entries.spawn.key_code==120 and h.files["memory/keybinds.tsv"]==nil)
    h.spectatorRequested=nil;h:tick()
    assert(h.reported.spectator_enabled==nil,"unknown must not become enabled")
end)
test("spectator rejection or missing module is not reported as success",function()
    local h=harness(nil,true);h.runtime:start()
    h.spectatorToggleResult={ok=false,message="readback failed"}
    h.inbox={action="toggle_spectator"};h:tick()
    assert(h.result.ok==false and h.result.message=="readback failed" and h.reported.spectator_enabled==false)
    h=harness();h.runtime:start();h.inbox={action="toggle_spectator"};h:tick()
    assert(h.result.ok==false and h.reported.spectator_enabled==nil and h.keys.F8==nil)
end)
test("spectator unload only silences and invalidates queued F8 and IPC work",function()
    local h=harness(nil,true);h.runtime:start()
    h.keys.F8();h.queue[#h.queue+1]=h.loops[1].fn;assert(#h.queue==2)
    h.inbox={action="toggle_spectator"}
    h.runtime:silence();assert(h.silenced==1 and h.spectatorSilences==1)
    local calls=#h.calls;h:drain();assert(#h.calls==calls and h.inbox~=nil)
    h.keys.F8();assert(#h.queue==0)
    assert(#h.cancellations==1 and h.loops[1].cancelled)
    assert(h:run(h.loops[1].fn)==nil)
    assert(count(h,"toggle_spectator")==0 and count(h,"spectator_tick")==0)
end)
test("missing stable timer APIs do not fall back to the old async pump",function()
    for _,missing in ipairs({"LoopInGameThreadWithDelay","CancelDelayedAction"})do
        local h=harness();h.env[missing]=false
        assert(h.runtime:start()==false and #h.loops==0 and #h.queue==0 and h.legacyCalls==0)
        assert(table.concat(h.logs," "):find("缺少LoopInGameThreadWithDelay或CancelDelayedAction",1,true))
    end
end)
test("unconfirmed registration leaves any host callback inert",function()
    local h=harness()
    local register=h.env.LoopInGameThreadWithDelay
    h.env.LoopInGameThreadWithDelay=function(ms,fn)register(ms,fn);return nil end
    assert(h.runtime:start()==false and h.runtime.pumpHandle==nil and not h.runtime.pumpReady)
    h:tick();assert(#h.calls==0 and h.legacyCalls==0)
end)
test("a tick exception does not wedge future ticks or claim a repair",function()
    local h=harness();h.runtime:start();h.failExportOnce=true
    h:tick();assert(count(h,"bridge_tick")==0 and #h.loops==1)
    assert(table.concat(h.logs," "):find("面板轮询失败",1,true))
    h:tick();assert(count(h,"bridge_tick")==1 and #h.queue==0 and h.legacyCalls==0)
end)
test("cancel failure is logged while the retained callback remains silent",function()
    local h=harness(nil,true);h.runtime:start();h.cancelError=true
    h.runtime:silence()
    assert(#h.cancellations==1 and not h.loops[1].cancelled and h.runtime.pumpHandle~=nil)
    assert(table.concat(h.logs," "):find("取消调用=false",1,true))
    local calls=#h.calls;h:run(h.loops[1].fn);assert(#h.calls==calls)
    h.cancelError=false;h.runtime:silence()
    assert(#h.cancellations==2 and h.loops[1].cancelled and h.runtime.pumpHandle==nil)
end)
test("F9 F3 and F8 check readiness at execution time and do not touch gameplay handlers while loading",function()
    local h=harness(nil,true);h.runtime:start()
    for _,key in ipairs({"F9","F3","F8"})do h.keys[key]() end
    h.sessionState.game_ready=false;h.sessionState.game_ready_reason="loading fixture"
    h:drain()
    assert(count(h,"spawn")==0 and count(h,"start")==0 and count(h,"toggle_spectator")==0)
    h:tick()
    assert(h.reported.game_session=="test-session" and h.reported.game_ready==false)
    assert(h.reported.game_ready_reason=="loading fixture")
    h.inbox={action="spawn",unit_id="chosen",team="blue",count=1};h:tick()
    assert(not h.result.ok and count(h,"spawn")==0)
    h.keys.F4();h:drain();assert(count(h,"stop")==1,"cleanup remains available while loading")
    h.sessionState.game_ready=true
    for _,key in ipairs({"F9","F3","F8"})do h.keys[key]() end
    h:drain()
    assert(count(h,"spawn")==1 and count(h,"start")==1 and count(h,"toggle_spectator")==1)
end)
test("missing session and non-boolean readiness fail closed for hotkeys",function()
    for _,mode in ipairs({"missing","unknown","string_true"})do
        local h=harness(nil,true)
        if mode=="missing" then h.runtime=h.new({session=false})
        elseif mode=="unknown" then h.sessionState.game_ready=nil
        else h.sessionState.game_ready="true" end
        h.runtime:start()
        for _,key in ipairs({"F9","F3","F8"})do h.keys[key]() end
        h:drain()
        assert(count(h,"spawn")==0 and count(h,"start")==0 and count(h,"toggle_spectator")==0,mode)
    end
end)
test("automatic codex export waits for the first ready tick and runs only once",function()
    local h=harness(nil,false,true);h.sessionState.game_ready=false;h.runtime:start()
    h:tick();h:tick();assert(count(h,"codex_export")==0)
    h.sessionState.game_ready=true;h:tick();h:tick()
    assert(count(h,"codex_export")==1 and h.reported.game_ready==true)
    h.sessionState.game_ready=false;h:tick();h.sessionState.game_ready=true;h:tick()
    assert(count(h,"codex_export")==1)
    local without=harness();without.runtime:start();without:tick();assert(count(without,"codex_export")==0)
end)
test("stat matching toggle uses native settings and status; missing module fails visibly",function()
    local h=harness();local enabled=false
    local matching={toggle=function()
        assert(h.inGame);enabled=not enabled;return {ok=true,message='fixture match toggle',spawned_count=0}
    end,status=function()return {enabled=enabled,baseline_unit='A',health=100,shachi=80,attack=20,shachi_attack=15,matched=2,field_count=117}end}
    h.runtime=h.new({statMatch=matching});h.runtime:start()
    h.inbox={action='toggle_stat_match'};h:tick()
    assert(h.result.ok and enabled and h.reported.stat_match_enabled and h.reported.stat_match_supported)
    assert(h.reported.stat_match_baseline_unit=='A' and h.reported.stat_match_health==100 and h.reported.stat_match_count==2)
    local missing=harness();missing.runtime:start();missing.inbox={action='toggle_stat_match'};missing:tick()
    assert(not missing.result.ok and missing.reported.stat_match_supported==false)
end)
test("stat mode command passes mode and revision through and reports the custom values",function()
    local h=harness();local got={}
    local matching={setMode=function(_,mode,revision)
        assert(h.inGame);got={mode,revision};return {ok=true,message='fixture mode',spawned_count=0}
    end,status=function()return {enabled=true,mode='custom',customized=3,custom_count=5,custom={Health_Max=50000,Attack=120},
        rejected={'Shield','Health','A1','A2','A3','A4','A5','A6','A7','A8','A9','A10','A11'}}end}
    h.runtime=h.new({statMatch=matching});h.runtime:start()
    h.inbox={action='set_stat_mode',key_spawn='CUSTOM',key_start='R0A1B2C3D4E5F'};h:tick()
    assert(h.result.ok and got[1]=='CUSTOM' and got[2]=='R0A1B2C3D4E5F')
    assert(h.reported.stat_match_mode=='custom' and h.reported.stat_match_customized==3 and h.reported.stat_custom_count==5)
    assert(h.reported.stat_custom_health==50000 and h.reported.stat_custom_attack==120 and h.reported.stat_custom_shachi=='')
    assert(h.reported.stat_custom_rejected==13 and h.reported.stat_custom_rejected_fields=='Shield,Health,A1,A2,A3,A4,A5,A6,A7,A8,A9,A10')
    local missing=harness();missing.runtime:start();missing.inbox={action='set_stat_mode',key_spawn='GAME'};missing:tick()
    assert(not missing.result.ok)
end)
test("companions are dismissed on their own and reported apart from the arena",function()
    local h=harness()
    h.runtime=h.new({companions={status=function()return {follow=2,friendly=2,failures=1,message='m'}end}});h.runtime:start()
    h.inbox={action='dismiss_companions'};h:tick()
    assert(count(h,'dismiss_companions')==1 and count(h,'stop')==0,'dismissing does not stop the arena')
    assert(h.reported.companion_count==2 and h.reported.companion_owned_records==3 and h.reported.companion_supported)
    assert(h.reported.companion_follow==2 and h.reported.companion_failures==1)
end)
test("recall goes to the companions from the app and from its function key; keys report schema 3",function()
    local h=harness();local recalls=0
    h.runtime=h.new({companions={status=function()return {stuck=1,recalls=recalls}end,
        recall=function()assert(h.inGame);recalls=recalls+1;return {ok=true,message='已召回 2/2 个随从到身边',spawned_count=0}end}})
    h.runtime:start()
    h.inbox={action='recall_companions'};h:tick()
    assert(recalls==1 and h.result.ok and h.result.message=='已召回 2/2 个随从到身边')
    assert(h.reported.function_keys_schema==3 and h.reported.key_recall_companions=='' and h.reported.companion_stuck_teleports==1)
    h.inbox={action='configure_keys',key_spawn='UNBOUND',key_start='UNBOUND',key_stop='UNBOUND',key_refresh_catalog='UNBOUND',
        key_toggle_camera='UNBOUND',key_exit_camera='UNBOUND',key_cycle_team='UNBOUND',key_toggle_spectator='UNBOUND',key_recall_companions='F5'}
    h:tick();assert(h.result.ok,h.result.message)
    h.keys.F5();h:drain();assert(recalls==2,'the recall key recalls')
    assert(h.reported.key_recall_companions=='VK_116_MOD_0' or h.runtime.functionKeys:token('recall_companions')=='VK_116_MOD_0')
end)
test("spawn difficulty takes its token from the key_spawn column and reports the game difficulty",function()
    local h=harness();local level='FOLLOW'
    local difficulty={set=function(_,token)
        assert(h.inGame);level=token;return {ok=true,message='fixture difficulty',spawned_count=0}
    end,status=function()return {level=level,game='Easy',applied=1,skipped=0,failures=0,message='m'}end}
    local ai={status=function()return {state='running',verified=4,failed=0}end}
    h.runtime=h.new({spawnDifficulty=difficulty,aiDifficulty=ai});h.runtime:start()
    h.inbox={action='set_spawn_difficulty',key_spawn='HARD'};h:tick()
    assert(h.result.ok and level=='HARD' and h.reported.spawn_difficulty=='HARD' and h.reported.spawn_difficulty_game=='Easy')
    assert(h.reported.spawn_difficulty_ai=='running' and h.reported.spawn_difficulty_ai_verified==4 and h.reported.spawn_difficulty_ai_failed==0)
    assert(h.reported.spawn_difficulty_supported and h.reported.spawn_difficulty_applied==1)
    local missing=harness();missing.runtime:start();missing.inbox={action='set_spawn_difficulty',key_spawn='HARD'};missing:tick()
    assert(not missing.result.ok and missing.reported.spawn_difficulty_supported==false)
end)
test("不倒下 takes its team from the team column and ON/OFF from key_start; the battle clock is reported",function()
    local h=harness();local on={blue=false,red=false,companion=false}
    local immortal={set=function(_,team,value)
        assert(h.inGame);on[team]=value=='ON';return {ok=true,message='fixture immortal',spawned_count=0}
    end,status=function()return {blue=on.blue,red=on.red,companion=on.companion,locked=3,failures=1,breaches=2,message='m'}end}
    h.runtime=h.new({immortal=immortal});h.runtime:start()
    h.inbox={action='set_team_immortal',team='red',key_start='ON'};h:tick()
    assert(h.result.ok and on.red and h.reported.immortal_red and not h.reported.immortal_blue and h.reported.immortal_supported)
    assert(h.reported.immortal_locked==3 and h.reported.immortal_failures==1 and h.reported.immortal_breaches==2)
    assert(h.reported.battle_clock=='' and h.reported.battle_seconds=='0.0','no clock in the arena fixture')
    -- panel_bridge.lua writes at most 256 entries; v0.36.0 lost random ones past the old cap of 100.
    local entries=0;for _ in pairs(h.reported)do entries=entries+1 end
    assert(entries<200,'status entries: '..entries)
    local missing=harness();missing.runtime:start();missing.inbox={action='set_team_immortal',team='red',key_start='ON'};missing:tick()
    assert(not missing.result.ok and missing.reported.immortal_supported==false)
end)
test("the on-screen clock switch takes ON/OFF from key_start and reports its state",function()
    local h=harness();local on=false
    local clock={set=function(_,value)assert(h.inGame);on=value=='ON';return {ok=true,message='fixture clock',spawned_count=0}end,
        status=function()return {on=on,state=on and 'waiting' or 'off',failures=0,message=''}end}
    h.runtime=h.new({clockHUD=clock});h.runtime:start()
    h.inbox={action='set_clock_hud',key_start='ON'};h:tick()
    assert(h.result.ok and on and h.reported.clock_hud and h.reported.clock_hud_state=='waiting' and h.reported.clock_hud_supported)
    local missing=harness();missing.runtime:start();missing.inbox={action='set_clock_hud',key_start='ON'};missing:tick()
    assert(not missing.result.ok and missing.reported.clock_hud_supported==false)
end)

test('camera buttons and configured keys use synchronous game-thread handlers; exit survives loading',function()
    local h=harness();local active=false;local toggles,exits=0,0
    h.runtime=h.new({camera={status=function()assert(h.inGame);return {active=active,pending=false}end,
        toggle=function()assert(h.inGame);toggles=toggles+1;active=true;return {ok=true,message='entered',spawned_count=0}end,
        exit=function()assert(h.inGame);exits=exits+1;active=false;return {ok=true,message='restored',spawned_count=0}end}})
    h.runtime:start()
    local proposal={};for name,value in pairs(NEW)do proposal[name]=value end
    proposal.toggle_camera='F6';proposal.exit_camera='F7'
    assert(h:run(function()return h.runtime:configure(proposal)end).ok)
    h.keys.F6();assert(toggles==0);h:drain();assert(toggles==1 and active)
    h.sessionState.game_ready=false
    h.keys.F6();h:drain();assert(exits==1 and not active,'toggle while active must still exit during loading')
    h.keys.F6();h:drain();assert(toggles==1,'entry during loading must remain blocked')
    h.keys.F7();h:drain();assert(exits==2)
    h.inbox={action='exit_camera'};h:tick();assert(h.result.ok and exits==3 and #h.queue==0)
end)
test('time stop opens the camera frozen when it is off and toggles inside it; the settings are numbers from the key columns',function()
    local h=harness();local active,frozen,configured=false,false,nil
    local settings={speed=900,turn=100,smooth=40}
    h.runtime=h.new({camera={
        status=function()assert(h.inGame);return {active=active,pending=false,frozen=frozen,settings=settings}end,
        toggle=function()active=true;return {ok=true,message='entered',spawned_count=0}end,
        exit=function()active,frozen=false,false;return {ok=true,message='restored',spawned_count=0}end,
        freeze=function(_,on)assert(h.inGame and active);frozen=on;return {ok=true,message=on and '时停' or '已解除时停',spawned_count=0}end,
        configure=function(_,speed,turn,smooth)configured={speed,turn,smooth};return {ok=true,message='saved',spawned_count=0}end}})
    h.runtime:start()
    h.inbox={action='toggle_time_stop'};h:tick()
    assert(h.result.ok and active and frozen and h.result.message=='已进入自由观战；时停')
    h.inbox={action='toggle_time_stop'};h:tick();assert(h.result.ok and active and not frozen)
    h.inbox={action='toggle_time_stop'};h:tick();assert(frozen)
    assert(h.reported.free_camera_frozen==true and h.reported.free_camera_speed==900 and h.reported.free_camera_settings_supported==true)
    h.inbox={action='set_free_camera',key_spawn='1500',key_start='150',key_stop='25'};h:tick()
    assert(h.result.ok and configured[1]==1500 and configured[2]==150 and configured[3]==25)
    -- Not in a map: the camera does not open for it.
    active,frozen=false,false;h.sessionState.game_ready=false
    h.inbox={action='toggle_time_stop'};h:tick();assert(not h.result.ok and not active)
end)
print("panel_runtime: PASS ("..passed.." real-module control regressions; no game accessed)")
