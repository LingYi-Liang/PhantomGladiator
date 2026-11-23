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
        if mode=="r" and h.files[path]==nil then return nil,"missing",2 end
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
            seek=function()return 0 end,
            read=function()
                h.ioEvents[#h.ioEvents+1]="read"
                if h.onRead then h.onRead(path) end
                return h.corruptRead and "corrupt readback" or content
            end,
        }
    end}
    local arena={
        selection=function()return table.unpack(h.selection or {'/Game/BP_Default.BP_Default_C','blue',1})end,
        spawn=function(_,...) if h.spawnStep then h.spawnStep() end;return record("spawn",...) end,
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
        if name=='hun_body' then return {path='/Game/FixtureHun.FixtureHun_C'} end
        if name=='hun_loadout' then return assert(loadfile('Mods/PhantomGladiator/Scripts/hun_loadout.lua','t',env))() end
        assert(name=='map_weather' or name=='ue_observe' or name=='key_router' or name=='function_keybinds' or name=='perf_meter' or name=='unit_keybinds' or name=='summon_queue' or name=='monster_pool_keys' or name=='teleport_places' or name=='teleport_keys')
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

test("an accepted ordinary summon key is cancelled when its game session changes before execution",function()
    local h=harness()
    h.runtime:start();h:tick()
    h.keys.F9()
    assert(#h.queue==1 and count(h,'spawn')==0)
    h.sessionState.game_session='different-world'
    h:drain()
    assert(count(h,'spawn')==0,'a key from the previous world must not summon in the next one')
    assert(h.runtime.summonPending==nil,'cancelled requests must release the shared summon slot')
    h:tick();h.keys.F9();h:drain()
    assert(count(h,'spawn')==1,'a separate key press in the new world still works')
end)

test("stop cancels an ordinary summon already waiting for its game-thread callback",function()
    local h=harness();h.runtime:start();h:tick()
    h.keys.F9();assert(h.runtime.summonPending and #h.queue==1)
    h:run(function()return h.runtime.handlers.stop()end)
    assert(count(h,'stop')==1,'the cleanup handler must have run before the pending callback')
    h:drain()
    assert(count(h,'spawn')==0,'stop must invalidate a summon accepted before cleanup')
    h.keys.F9();h:drain()
    assert(count(h,'spawn')==1,'a separate new request after cleanup must still work')
end)

test("a new summon queued after stop survives the stale callback that was cancelled",function()
    local h=harness();h.runtime:start();h:tick()
    h.keys.F9();h:run(function()return h.runtime.handlers.stop()end)
    h.keys.F9()
    assert(#h.queue==2,'fixture must retain both the old and the new callback')
    h:drain()
    assert(count(h,'spawn')==1 and not h.runtime.summonPending,'the stale callback must not run or clear the new request')
end)

test("a running callback cannot clear a replacement summon accepted after reentrant stop",function()
    local h=harness();h.runtime:start();h:tick()
    h.env.IsInGameThread=function()return h.inGame end
    local replacementRuns=0
    h.runtime:queueSummon(function()
        h.runtime.handlers.stop()
        h.runtime:queueSummon(function()replacementRuns=replacementRuns+1 end)
    end)
    h:run(table.remove(h.queue,1))
    assert(#h.queue==1 and h.runtime.summonPending,'running retired callback must leave its replacement slot intact')
    h:drain()
    assert(replacementRuns==1 and h.runtime.summonPending==nil,'the replacement executes once and releases its own slot')
end)

test("game-thread input snapshots the live session without waiting for the status pump",function()
    local h=harness()
    h.env.IsInGameThread=function()return h.inGame end
    h.runtime:start()
    h:run(function()h.keys.F9()end)
    h.sessionState.game_session='world-after-input'
    h:drain()
    assert(count(h,'spawn')==0,'the first game-thread key also belongs to its original world')
    h:run(function()h.keys.F9()end);h:drain()
    assert(count(h,'spawn')==1,'a fresh game-thread key must not inherit an old cached session')
end)

test("a queued battle action cannot cross worlds but cleanup remains available",function()
    local h=harness()
    h.runtime:start();h:tick()
    h.keys.F3();h.keys.F4()
    h.sessionState.game_session='different-world'
    h:drain()
    assert(count(h,'start')==0,'an old start key must not start a battle in the next world')
    assert(count(h,'stop')==1,'cleanup must still run after a world transition')
end)

test("repeated game-thread world changes discard old input and keep fresh summons usable",function()
    local h=harness()
    local now=10
    h.env.os.clock=function()return now end
    h.env.IsInGameThread=function()return h.inGame end
    h.runtime:start()
    for i=1,100 do
        now=now+1
        h.sessionState.game_session='old-world-'..i
        h:run(function()h.keys.F9();h.keys.F3()end)
        h.sessionState.game_session='new-world-'..i
        h:drain()
        assert(count(h,'spawn')==i-1 and count(h,'start')==0)
        h:run(function()h.keys.F9()end);h:drain()
        assert(count(h,'spawn')==i and h.runtime.summonPending==nil)
    end
end)

test("unit and general summon shortcuts share a single pending game-thread request",function()
    local h=harness()
    local now=10
    h.env.os.clock=function() return now end
    local unit='/Game/BP_A.BP_A_C'
    local units=h.env.require('unit_keybinds').new({path='memory',router=h.runtime.router,
        queue=function(callback)h.runtime:queueSummon(callback)end,
        ready=function()return true end,
        spawn=function(path,team,count)return h.runtime:summon(path,team,count)end})
    h.runtime.options.unitKeys=units
    h.runtime:start()
    assert(units:configure(unit,81,0,'red',3).ok)
    for _=1,40 do h.keys.Q();h.keys.F9() end
    print("burst fixture queued="..#h.queue.." before game-thread drain")
    assert(#h.queue==1 and count(h,'spawn')==0, "both shortcuts share the one pending summon")
    h:drain()
    local spawn
    for _,call in ipairs(h.calls)do if call.name=='spawn' then spawn=call end end
    assert(count(h,'spawn')==1 and spawn.args[1]==unit and spawn.args[2]=='red' and spawn.args[3]==3,
        "the accepted key keeps its selected unit, team and count")
    for _=1,40 do h.keys.Q();h.keys.F9() end
    assert(#h.queue==0, "the next burst is ignored during the gap")
    now=10.25
    h.keys.F9()
    assert(#h.queue==1)
    h:drain()
    assert(count(h,'spawn')==2, "the next separate press still summons")
end)

test("opt-in queue keeps the first 100 summons, paces completion and cancels before cleanup or a new session",function()
    local h=harness()
    local now=10
    h.env.os.clock=function()return now end
    h.runtime=h.new()
    h.spawnStep=function()now=now+0.125 end
    h.selection={'/Game/BP_Initial.BP_Initial_C','red',3}
    local unit='/Game/BP_Key.BP_Key_C'
    local units=h.env.require('unit_keybinds').new({path='memory',router=h.runtime.router,
        queue=function(callback,path,team,n)h.runtime:queueSummon(callback,path,team,n)end})
    h.runtime.options.unitKeys=units
    h.runtime:start()
    assert(#h.loops==1 and not h.runtime.summonQueue.enabled,'default off creates no extra loop')
    assert(h:run(function()return h.runtime.handlers.set_summon_queue({key_start='ON'})end).ok)
    local loop=h.loops[2]
    assert(loop.ms==25 and not loop.cancelled)

    assert(units:configure(unit,81,0,'neutral',2).ok)
    h.keys.F9()
    h.keys.Q()
    local epoch=h.runtime.summonQueue:epoch()
    h.selection={'/Game/BP_Changed.BP_Changed_C','blue',9}
    for i=3,100 do
        local request={unit_id='/Game/BP_'..i..'.BP_Test_C',team='blue',count=1,key_spawn=epoch}
        local ack=h:run(function()return h.runtime.handlers.queue_spawn(request)end)
        assert(ack.ok and ack.spawned_count==0)
    end
    assert(#h.queue==0 and #h.runtime.summonQueue.jobs==100 and count(h,'spawn')==0)
    local overflow=h:run(function()return h.runtime.handlers.queue_spawn({
        unit_id='/Game/BP_Overflow.BP_Test_C',team='blue',count=1,key_spawn=epoch})end)
    assert(not overflow.ok and #h.runtime.summonQueue.jobs==100)

    h:run(loop.fn)
    assert(count(h,'spawn')==1 and now==10.125)
    local first=h.calls[#h.calls]
    assert(first.name=='spawn' and first.args[1]=='/Game/BP_Initial.BP_Initial_C' and first.args[2]=='red' and first.args[3]==3)
    now=10.25
    h:run(loop.fn)
    assert(count(h,'spawn')==1,'0.25 s from the start is too soon if spawn took 0.125 s')
    now=10.375
    h:run(loop.fn)
    local second=h.calls[#h.calls]
    assert(count(h,'spawn')==2 and second.args[1]==unit and second.args[2]=='neutral' and second.args[3]==2)
    now=10.75
    h:run(loop.fn)
    assert(count(h,'spawn')==3 and h.calls[#h.calls].args[1]=='/Game/BP_3.BP_Test_C')

    h.keys.F4();h:drain()
    assert(count(h,'stop')==1 and #h.runtime.summonQueue.jobs==0)
    local stale=h:run(function()return h.runtime.handlers.queue_spawn({
        unit_id='/Game/BP_Old.BP_Test_C',team='blue',count=1,key_spawn=epoch})end)
    assert(not stale.ok)
    h.keys.F9();assert(#h.runtime.summonQueue.jobs==1)
    h.sessionState.game_session='test-next-world'
    now=20
    h:run(loop.fn)
    assert(count(h,'spawn')==3 and #h.runtime.summonQueue.jobs==0)

    assert(h:run(function()return h.runtime.handlers.set_summon_queue({key_start='OFF'})end).ok)
    assert(loop.cancelled and not h.runtime.summonQueue.enabled)
    h.keys.F9();h:drain()
    assert(count(h,'spawn')==4,'the original shortcut path resumes once off')
end)

test("two pool keys dispatch their own members and team, obey queueing and drop an old-map key",function()
    local h=harness()
    local a,b='/Game/BP_A.BP_A_C','/Game/BP_B.BP_B_C'
    local bad='/Game/BP_Blocked.BP_Blocked_C'
    h.files['memory/monster-pools.tsv']='MonsterPoolsV1\t1\npool-small\tSmall\tred\t3\t81\t1\t'..a..';'..bad..
        '\npool-ally\tAlly\tcompanion\t1\t81\t2\t'..b..'\n'
    h.runtime=h.new({spawnPolicy={check=function(path)return path~=bad end,
        limits=function(path)if path==b then return {max_count=1}end end,status=function()return {}end}})
    assert(h.runtime:start());h:tick()
    assert(h.reported.monster_pool_keys_schema==1)
    assert(h.files['memory/monster-pools-state.tsv']=='MonsterPoolKeysV1\t1\ttest-session\npool-small\t1\t\npool-ally\t1\t\n')
    h.keys['Q:1']();assert(#h.queue==1 and count(h,'spawn')==0)
    h:drain()
    local spawn
    for _,call in ipairs(h.calls)do if call.name=='spawn' then spawn=call end end
    assert(spawn and table.concat(spawn.args,'|')==a..'|red|3')
    h.runtime.nextSummonAt=nil
    h.keys['Q:2']();h.sessionState.game_session='next-map';h:drain()
    assert(count(h,'spawn')==1,'a request queued for the previous map is stale')
    h:tick()
    assert(h:run(function()return h.runtime:setSummonQueue(true)end).ok)
    for _=1,100 do h.keys['Q:2']() end
    assert(#h.runtime.summonQueue.jobs==100 and count(h,'spawn')==1)
    local job=h.runtime.summonQueue.jobs[1]
    assert(job.path==b and job.team=='companion' and job.count==1)
    assert(h:run(function()return h.runtime:setSummonQueue(false)end).ok and #h.runtime.summonQueue.jobs==0)
    h.files['memory/monster-pools.tsv']='MonsterPoolsV1\t2\npool-small\tSmall\tblue\t1\t81\t1\t'..a..'\n'
    h:tick();h.keys['Q:2']();assert(#h.queue==0,'removed key is inert')
    assert(h.files['memory/monster-pools-state.tsv']=='MonsterPoolKeysV1\t2\tnext-map\npool-small\t1\t\n')
end)

test("pool keys keep every press with the summon queue off, one summon at a time, and stop clears them",function()
    local h=harness()
    local now=10
    h.env.os.clock=function() return now end
    local a='/Game/BP_A.BP_A_C'
    h.files['memory/monster-pools.tsv']='MonsterPoolsV1\t1\npool-gift\tGift\tneutral\t1\t81\t1\t'..a..'\n'
    h.runtime=h.new({spawnPolicy={check=function()return true end,limits=function()end,status=function()return {}end}})
    assert(h.runtime:start());h:tick()
    for _=1,5 do h.keys['Q:1']() end
    assert(#h.runtime.poolQueue.jobs==5 and #h.queue==1 and count(h,'spawn')==0,'five presses wait; one game-thread kick')
    h:drain()
    assert(count(h,'spawn')==1 and #h.runtime.poolQueue.jobs==4,'the first runs at once')
    h:tick();assert(count(h,'spawn')==1,'the gap after a summon is kept')
    for n=2,5 do now=now+0.3;h:tick();assert(count(h,'spawn')==n) end
    assert(#h.runtime.poolQueue.jobs==0 and h.reported.monster_pool_queue_waiting==0)
    -- Stop and clear empties the pool queue.
    now=now+0.3
    for _=1,3 do h.keys['Q:1']() end
    h:drain();assert(count(h,'spawn')==6)
    h.inbox={action='stop'};h:tick()
    assert(#h.runtime.poolQueue.jobs==0,'stop and clear drops waiting pool presses')
    now=now+1;h:tick();assert(count(h,'spawn')==6)
    -- The queue holds 100; the press after that is refused, not run twice.
    for _=1,101 do h.keys['Q:1']() end
    assert(#h.runtime.poolQueue.jobs==100)
end)

test("a pool key draws each unit on its own and never beyond a member's own limit",function()
    local h=harness()
    local a,b,c='/Game/BP_A.BP_A_C','/Game/BP_B.BP_B_C','/Game/BP_C.BP_C_C'
    h.files['memory/monster-pools.tsv']='MonsterPoolsV1\t1\npool-mix\tMix\tcompanion\t5\t81\t1\t'..a..';'..b..';'..c..'\n'
    -- b is a boss that may only come one at a time; c cannot be summoned here.
    h.runtime=h.new({spawnPolicy={check=function(path)return path~=c end,
        limits=function(path)if path==b then return {max_count=1}end end,status=function()return {}end}})
    -- The draws ask for the 2nd, then the 1st of what is left: b, then a for the rest once b is used up.
    local asks={2,1,1,1,1}
    h.env.math=setmetatable({random=function(n)local want=table.remove(asks,1);assert(want<=n,'draw beyond the choices left');return want end},{__index=math})
    assert(h.runtime:start());h:tick()
    h.keys['Q:1']()
    local jobs=h.runtime.poolQueue.jobs
    assert(#jobs==2,'one queued summon per kind drawn')
    assert(jobs[1].path==b and jobs[1].count==1 and jobs[1].team=='companion')
    assert(jobs[2].path==a and jobs[2].count==4)
    -- Only the boss left to draw: the summon comes out short instead of breaking its limit.
    h.files['memory/monster-pools.tsv']='MonsterPoolsV1\t2\npool-mix\tMix\tred\t3\t81\t1\t'..b..';'..c..'\n'
    h.runtime.poolQueue.jobs={};asks={1}
    h:tick();h.keys['Q:1']()
    jobs=h.runtime.poolQueue.jobs
    assert(#jobs==1 and jobs[1].path==b and jobs[1].count==1)
    local short=false
    for _,line in ipairs(h.logs)do if line:find('只抽出 1/3',1,true)then short=true end end
    assert(short,'a short draw is logged')
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
    h:tick();assert(count(h,"bridge_tick")==1 and #h.loops==1)
    assert(table.concat(h.logs," "):find("面板轮询失败",1,true))
    h:tick();assert(count(h,"bridge_tick")==2 and #h.queue==0 and h.legacyCalls==0)
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
test("the first ready pump and manual refresh spread the five catalog reads over separate callbacks",function()
    local h=harness();local countReads,maxPerPump=0,0;local order={}
    local function source(name)
        local function read()countReads=countReads+1;order[#order+1]=name;return {ok=true,message=name}end
        return {export=read,refresh=read,status=function()return {}end}
    end
    h.runtime=h.new({codex=source("codex"),spawnCatalog=source("spawners"),tableCatalog=source("tables"),
        areaLevels=source("areas"),homeLevels=source("home")})
    h.runtime:start()
    for i=1,16 do
        if i==9 then h.inbox={action="refresh_catalog"}end
        local previous=countReads;h:tick();maxPerPump=math.max(maxPerPump,countReads-previous)
    end
    print("MEASURE startup and manual refresh: total exports="..countReads.."; max in a single pump="..maxPerPump)
    assert(countReads==10 and maxPerPump==1 and count(h,"bridge_tick")==16)
    assert(table.concat(order,",")=="codex,spawners,tables,areas,home,codex,spawners,tables,areas,home")
end)
test("catalog work is spread across heartbeats and failed sources can be retried without blocking input",function()
    local h=harness();local reads={};local generation,homes=0,{}
    local function work(name)
        return function()
            assert(h.inGame);reads[#reads+1]=name
            if name=="codex" then
                generation=generation+1
                if generation==1 then error("catalog source temporarily unavailable") end
            elseif name=="home" then homes[#homes+1]=generation end
            return {ok=true,message=name}
        end
    end
    local function source(name)return {export=work(name),status=function()return {}end}end
    h.env.os.clock=function()return h.now or 0 end
    h.runtime=h.new({codex=source("codex"),spawnCatalog=source("spawners"),tableCatalog=source("tables"),
        areaLevels=source("areas"),homeLevels={refresh=work("home"),status=function()return {}end}})
    h.runtime:start();h.inbox={action="select_unit",unit_id="chosen",team="red",count=1}
    for i=1,32 do
        local before=#reads;h.now=i*.5;h:tick()
        assert(#reads-before<=1,"several directory exports still ran in one callback")
        if i==1 then assert(count(h,"select_unit")==1,"optional data failure swallowed the command")end
    end
    local seen={};for _,s in ipairs(reads)do seen[s]=(seen[s] or 0)+1 end
    assert(generation==2 and seen.spawners==1 and seen.tables==1 and seen.areas==1 and homes[#homes]==2,"retry, then rebuild dependent home levels")
    assert(count(h,"bridge_tick")==32,"one heartbeat for each timer callback")
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
test("a new world refreshes local levels promptly, without rescanning the codex or blocking a heartbeat",function()
    local h=harness(nil,false,true);local now,reads=0,0
    h.env.os.clock=function()return now end
    h.runtime=h.new({spawnLevel={status=function()return {}end,refresh=function()reads=reads+1;return true end}})
    h.runtime:start()
    for i=1,5 do now=i*.25;h:tick()end
    assert(reads==1 and count(h,"codex_export")==1)
    h.sessionState.game_ready=false;now=2;h:tick();assert(reads==1)
    h.sessionState.game_session="other-map";h.sessionState.game_ready=true
    for i=1,4 do now=2+i*.25;h:tick()end
    assert(reads==2 and count(h,"codex_export")==1 and count(h,"bridge_tick")==10)
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
test("the companions' own stat set has its command and status beside the arena's",function()
    local h=harness();local got,arena
    local set={setMode=function(_,mode,revision)
        assert(h.inGame);got={mode,revision};return {ok=true,message='fixture companion mode',spawned_count=0}
    end,status=function()return {mode='custom',customized=2,custom_count=4,failures=1,message='已写入',
        rejected={'Shield','A1','A2','A3','A4','A5','A6','A7','A8','A9','A10','A11','A12'}}end}
    local matching={setMode=function()arena=true;return {ok=true,message='',spawned_count=0}end,status=function()return {mode='game'}end}
    h.runtime=h.new({statMatch=matching,companionStats=set});h.runtime:start()
    h.inbox={action='set_companion_stats',key_spawn='CUSTOM',key_start='R0A1B2C3D4E5F'};h:tick()
    assert(h.result.ok and got[1]=='CUSTOM' and got[2]=='R0A1B2C3D4E5F' and not arena,'only the companions set takes it')
    assert(h.reported.companion_stats_supported==true and h.reported.companion_stats_mode=='custom' and h.reported.stat_match_mode=='game')
    assert(h.reported.companion_stats_count==4 and h.reported.companion_stats_customized==2 and h.reported.companion_stats_failures==1)
    assert(h.reported.companion_stats_rejected==13 and h.reported.companion_stats_rejected_fields=='Shield,A1,A2,A3,A4,A5,A6,A7,A8,A9,A10,A11')
    local missing=harness();missing.runtime:start();missing.inbox={action='set_companion_stats',key_spawn='GAME'};missing:tick()
    assert(not missing.result.ok and missing.reported.companion_stats_supported==false)
end)
test("companions are dismissed on their own and reported apart from the arena",function()
    local h=harness()
    h.runtime=h.new({companions={status=function()return {follow=2,friendly=2,failures=1,message='m'}end}});h.runtime:start()
    h.inbox={action='dismiss_companions'};h:tick()
    assert(count(h,'dismiss_companions')==1 and count(h,'stop')==0,'dismissing does not stop the arena')
    assert(h.reported.companion_count==2 and h.reported.companion_owned_records==3 and h.reported.companion_supported)
    assert(h.reported.companion_follow==2 and h.reported.companion_failures==1)
end)
test("recall goes to the companions from the app and from its function key; keys report schema 6",function()
    local h=harness();local recalls=0
    h.runtime=h.new({companions={status=function()return {stuck=1,recalls=recalls}end,
        recall=function()assert(h.inGame);recalls=recalls+1;return {ok=true,message='已召回 2/2 个随从到身边',spawned_count=0}end}})
    h.runtime:start()
    h.inbox={action='recall_companions'};h:tick()
    assert(recalls==1 and h.result.ok and h.result.message=='已召回 2/2 个随从到身边')
    assert(h.reported.function_keys_schema==8 and h.reported.key_recall_companions=='' and h.reported.companion_stuck_teleports==1)
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
    -- A real session reports about 27 more than this fixture (230 lines against 199 before the Hun keys).
    local entries=0;for _ in pairs(h.reported)do entries=entries+1 end
    -- 227 with longzhu_protection_supported; a session with the teleport module adds three more, far below the cap of 288.
    assert(entries<=227,'status entries: '..entries)
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

test('off-combat regen uses a game-thread switch and reports verified state',function()
    local h=harness();local on=false
    local feature={set=function(_,token)assert(h.inGame);assert(token=='ON' or token=='OFF');on=token=='ON';return {ok=true,message='saved'}end,
        status=function()return {supported=true,on=on,state=on and 'on' or 'off',blocked=2,cleared=1,failures=0,hooks=1}end}
    h.runtime=h.new({support={offCombatRegen=feature,status=function()return {}end,tick=function()end}});h.runtime:start()
    h.inbox={action='set_offcombat_regen',key_start='ON'};h:tick()
    assert(h.result.ok and on and h.reported.offcombat_regen_supported and h.reported.offcombat_regen_disabled)
    assert(h.reported.offcombat_regen_blocked==2 and h.reported.offcombat_regen_state=='on')
    h.inbox={action='set_offcombat_regen',key_start='OFF'};h:tick();assert(h.result.ok and not on and not h.reported.offcombat_regen_disabled)
    local missing=harness();missing.runtime:start();missing.inbox={action='set_offcombat_regen',key_start='ON'};missing:tick()
    assert(not missing.result.ok and missing.reported.offcombat_regen_supported==false)
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
test('camera tracking: the keys open the free camera first, the settings reach the module, and the app reads it back',function()
    local h=harness()
    local active,opened=false,0
    local calls={}
    local track={on=false,
        status=function(self)return {on=self.on,framing='side',resume=3,target=self.on and '42' or '',target_class=self.on and 'BP_A_C' or '',other_class=''} end,
        targets=function()return '42:BP_A_C:blue' end,
        start=function(self)calls[#calls+1]='start';self.on=true;return {ok=true,message='on',spawned_count=0} end,
        finish=function(self)calls[#calls+1]='finish';self.on=false;return {ok=true,message='off',spawned_count=0} end,
        pick=function()calls[#calls+1]='pick';return {ok=true,message='pick',spawned_count=0} end,
        next=function()calls[#calls+1]='next';return {ok=true,message='next',spawned_count=0} end,
        set=function(_,framing,resume,target)calls[#calls+1]=table.concat({framing,resume,target},'|');return {ok=true,message='set',spawned_count=0} end}
    local camera={status=function()return {active=active,pending=false} end,
        toggle=function()opened=opened+1;active=true;return {ok=true,message='in',spawned_count=0} end,
        exit=function()active=false;return {ok=true,message='out',spawned_count=0} end}
    h.runtime=h.new({track=track,camera=camera});h.runtime:start()
    h:tick()
    assert(h.reported.track_supported==true and h.reported.track_on==false and h.reported.track_framing=='side' and h.reported.track_resume==3)
    assert(h.reported.track_targets=='','the list only while the camera runs')
    h.inbox={action='toggle_track'};h:tick()
    assert(h.result.ok and opened==1 and active and calls[1]=='start')
    assert(h.reported.track_on==true and h.reported.track_target=='42' and h.reported.track_target_class=='BP_A_C' and h.reported.track_targets=='42:BP_A_C:blue')
    h.inbox={action='toggle_track'};h:tick()
    assert(h.result.ok and calls[2]=='finish' and opened==1 and active,'turning it off leaves the camera')
    h.inbox={action='track_pick'};h:tick();assert(calls[3]=='pick' and opened==1)
    h.inbox={action='track_next'};h:tick();assert(calls[4]=='next')
    h.inbox={action='set_camera_track',unit_id='42',key_spawn='SHOULDER',key_start='5'};h:tick()
    assert(h.result.ok and calls[5]=='shoulder|5|42',calls[5])
    -- Not in a map: the camera does not open for it.
    active=false;h.sessionState.game_ready=false
    for _,action in ipairs({'toggle_track','track_pick','track_next'})do
        local before=#calls
        h.inbox={action=action};h:tick()
        assert(not h.result.ok and not active and #calls==before,action)
    end
    -- No module: says so.
    local none=harness()
    none.runtime=none.new({});none.runtime:start()
    for _,action in ipairs({'toggle_track','track_pick','track_next','set_camera_track'})do
        none.inbox={action=action};none:tick()
        assert(not none.result.ok)
    end
    assert(none.reported.track_supported==false)
end)
test('unit rules: the card reaches the module, its value goes lower case, and the app reads them back',function()
    local h=harness()
    local set={}
    local rules={set=function(_,id,rule,value)set[#set+1]={id,rule,value};return {ok=true,message='saved',spawned_count=0} end,
        status=function()return {text='BP_Monster_MoTian:lock=kill'} end}
    h.runtime=h.new({unitRules=rules});h.runtime:start()
    h.inbox={action='set_unit_rule',unit_id='BP_Monster_MoTian',key_spawn='LOCK',key_start='KILL'};h:tick()
    assert(h.result.ok and set[1][1]=='BP_Monster_MoTian' and set[1][2]=='lock' and set[1][3]=='kill')
    assert(h.reported.unit_rules_supported==true and h.reported.unit_rules=='BP_Monster_MoTian:lock=kill')
    local none=harness()
    none.runtime=none.new({});none.runtime:start()
    none.inbox={action='set_unit_rule',unit_id='BP_Monster_MoTian',key_spawn='LOCK',key_start='KILL'};none:tick()
    assert(not none.result.ok and none.reported.unit_rules_supported==false and none.reported.unit_rules=='')
end)
test('relay settings, intake and start use the same panel and key dispatcher',function()
    local h=harness();local time=0;h.env.os.clock=function()return time end
    local state={blue_count=0,red_count=0,blue_unreadable=0,red_unreadable=0,battle_active=false,total=0}
    local calls,begins={},0
    local arena={status=function()return state end,selection=function()return '/Game/B.B_C','blue',1 end,
        spawn=function(_,path,team,n)assert(h.inGame);calls[#calls+1]={path,team,n};state[team..'_count']=state[team..'_count']+n;return {ok=true,spawned_count=n}end,
        start=function()assert(h.inGame);begins=begins+1;state.battle_active=true;return {ok=true}end,
        stop=function()state.battle_active=false;return {ok=true}end,
        setRelayPending=function(_,enabled,blue,red)state.pending={enabled,blue,red}end}
    h.runtime=h.new({arena=arena});h.runtime:start()
    h.inbox={action='configure_summon_queue',key_spawn='SINGLE',key_start='1500',key_stop='2',key_refresh_catalog='3'};h:tick()
    assert(h.result.ok and h.reported.summon_queue_interval_ms==1500 and h.reported.summon_queue_mode=='SINGLE')
    assert(h.new().summonQueue.mode=='SINGLE','saved mode survives runtime restart while the switch stays off')
    h.inbox={action='set_summon_queue',key_start='ON'};h:tick()
    local loop=h.loops[2]
    h:run(function()h.runtime.handlers.queue_spawn({unit_id='/Game/B.B_C',team='blue',count=1});h.runtime.handlers.queue_spawn({unit_id='/Game/R.R_C',team='red',count=2})end)
    h:run(loop.fn);assert(#calls==0)
    h.inbox={action='start'};h:tick();assert(h.result.ok)
    for _=1,4 do time=time+1.5;h:run(loop.fn)end
    assert(#calls==2 and begins==1 and state.pending[3]==1)
    state.red_count=0
    for _=1,3 do time=time+1.5;h:run(loop.fn)end
    assert(#calls==3 and begins==1 and calls[3][2]=='red')
    h.inbox={action='stop'};h:tick();assert(not h.runtime.summonQueue.relayStarted and #h.runtime.summonQueue.jobs==0)
end)
test('dismiss shortcut uses the game-thread companion-only handler and rejects stale sessions',function()
    local h=harness();h.runtime:start();h:tick()
    local proposal={};for name,value in pairs(h.runtime.functionKeys.entries)do proposal[name]=value end
    proposal.dismiss_companions='VK_119_MOD_1'
    h:run(function()assert(h.runtime:configure(proposal).ok)end)
    h.keys['F8:1']();assert(count(h,'dismiss_companions')==0)
    h:drain();assert(count(h,'dismiss_companions')==1 and count(h,'stop')==0)
    h.keys['F8:1']();h.sessionState.game_session='new-session';h:tick();h:drain()
    assert(count(h,'dismiss_companions')==1,'an old-map press must not dismiss the new roster')
    h.keys['F8:1']();h:drain();assert(count(h,'dismiss_companions')==2)
end)
test('battle music commands report native readback and stop cannot hide pending recovery',function()
    local h=harness();local mode,track,pending='NATIVE','MOYUAN_P1',false
    local feature={set=function(_,m,t)assert(h.inGame);mode,track=m,t;return {ok=true,message='saved'}end,
        stop=function()assert(h.inGame);return {ok=not pending,message='music restore pending'}end,
        status=function()return {supported=true,mode=mode,track=track,state='waiting',message='readback',playing=0,pending=pending}end}
    h.runtime=h.new({support={discover=function()assert(h.inGame)end,status=function()return {}end,tick=function()assert(h.inGame)end,battleMusic=feature}});h.runtime:start()
    h.inbox={action='set_battle_music',key_spawn='TRACK',key_start='LEIDANG_P2'};h:tick()
    assert(h.result.ok and h.reported.battle_music_mode=='TRACK' and h.reported.battle_music_track=='LEIDANG_P2' and h.reported.battle_music_state=='waiting')
    pending=true;h.inbox={action='stop'};h:tick();assert(not h.result.ok and h.result.message:find('music restore pending',1,true))
    pending=false;h.inbox={action='stop'};h:tick();assert(h.result.ok)
end)
test('first-person hotkeys use the observation camera and unwind only their own failed entry',function()
    local h=harness();local active=false;local seen={}
    local camera={status=function()return {active=active}end,toggle=function()active=not active;return {ok=true}end,
        exit=function()active=false;return {ok=true}end}
    local track={firstPerson=function(_,who)seen[#seen+1]=who;return {ok=who=='player'} end,status=function()return {} end,targets=function()return ''end}
    h.runtime=h.new({camera=camera,track=track});h.runtime:start();h:tick()
    local keys={};for k,v in pairs(h.runtime.functionKeys.entries)do keys[k]=v end
    keys.eyes_player='VK_119_MOD_0';keys.eyes_npc='VK_119_MOD_1'
    h:run(function()assert(h.runtime:configure(keys).ok)end)
    h.keys['F8:1']();h:drain();assert(not active and seen[1]=='npc')
    h.keys.F8();h:drain();assert(active and seen[2]=='player')
    h.keys['F8:1']();h:drain();assert(active and seen[3]=='npc')
end)
test('weather hotkeys directly dispatch different presets and all three navigation actions',function()
    local h=harness();local seen={}
    local weather={status=function()return 'map' end,set=function(_,id)seen[#seen+1]=id;return {ok=true,message='weather.applied'}end}
    h.runtime=h.new({support={weather=weather}});h.runtime:start();h:tick()
    local proposal={};for k,v in pairs(h.runtime.functionKeys.entries)do proposal[k]=v end
    for i,id in ipairs({'rain','snow','next','previous','restore'})do
        proposal['weather_'..id]='VK_119_MOD_'..(i-1)
    end
    h:run(function()assert(h.runtime:configure(proposal).ok)end)
    for i,id in ipairs({'rain','snow','next','previous','restore'})do
        h.keys[i==1 and 'F8' or 'F8:'..(i-1)]();h:drain();assert(seen[i]==id)
    end
    h:run(function()assert(h.runtime.handlers.set_weather({key_spawn='FOGGY'}).ok)end);assert(seen[6]=='foggy')
end)
test('teleport takes a place code and looks the coordinates up in the mod table, never in the command',function()
    local h=harness();local went,back={},0
    local module={status=function()return {pending=true,can_return=true,last={ok=true,message='已到达',place='左殇'}}end,
        go=function(_,place)went[#went+1]=place;return {ok=true,message='已发起传送'}end,
        goBack=function()back=back+1;return {ok=false,message='没有可返回的位置'}end}
    h.runtime=h.new({support={teleport=module}});h.runtime:start();h:tick()
    local places=assert(loadfile('Mods/PhantomGladiator/Scripts/teleport_places.lua'))()
    local code,place=next(places)
    h:run(function()
        local r=h.runtime.handlers.teleport({key_spawn=code,unit_id='x=1,y=2,z=3',team='blue',count=1})
        assert(r.ok and r.spawned_count==0 and #went==1 and went[1].world==place.world and went[1].x==place.x and went[1].z==place.z)
        r=h.runtime.handlers.teleport({key_spawn='TNOPE'})
        assert(not r.ok and #went==1 and r.message:find('不在本版模组的地点表',1,true),'an unknown code calls nothing')
        r=h.runtime.handlers.teleport({})
        assert(not r.ok and #went==1,'an empty code is not a place')
        r=h.runtime.handlers.teleport_back({})
        assert(not r.ok and back==1 and r.spawned_count==0 and r.message=='没有可返回的位置')
    end)
    h.runtime=h.new({support={}});h.runtime:start();h:tick()
    h:run(function()assert(h.runtime.handlers.teleport({key_spawn=code}).message=='传送模块未加载')end)
end)
test('the walk-through-companions switch reaches its module and is reported only when the module is there',function()
    local h=harness();local seen={}
    local module={on=true,set=function(self,value)seen[#seen+1]=value;self.on=value=='ON';return {ok=true,message='fixture',spawned_count=0}end,
        status=function(self)return {on=self.on,applied=0}end}
    h.runtime=h.new({support={companionPassage=module,status=function()return {}end,tick=function()end}});h.runtime:start()
    h.inbox={action='set_companion_passage',key_start='OFF'};h:tick()
    assert(h.result.ok and seen[1]=='OFF' and h.reported.companion_passage_supported==true and h.reported.companion_passage==false)
    h.inbox={action='set_companion_passage',key_start='ON'};h:tick()
    assert(seen[2]=='ON' and h.reported.companion_passage==true)
    local missing=harness();missing.runtime:start();missing.inbox={action='set_companion_passage',key_start='ON'};missing:tick()
    assert(not missing.result.ok and missing.reported.companion_passage_supported==nil,'an old or partial mod reports nothing')
end)
test('a teleport key goes through the shared router, and a chord another feature owns is refused',function()
    local h=harness();local went={}
    local module={status=function()return {pending=false,can_return=false}end,
        go=function(_,place)went[#went+1]=place.name;return {ok=true,message='已发起传送'}end,
        goBack=function()went[#went+1]='BACK';return {ok=true,message='已发起传送'}end}
    h.runtime=h.new({support={teleport=module}});h.runtime:start();h:tick()
    local places=assert(loadfile('Mods/PhantomGladiator/Scripts/teleport_places.lua'))()
    local code,place=next(places)
    local owned
    for _,token in pairs(h.runtime.functionKeys.entries)do
        local vk,mask=tostring(token):match('^VK_(%d+)_MOD_(%d+)$');if vk then owned={vk,mask};break end
    end
    h:run(function()
        assert(h.runtime.handlers.configure_teleport_key({key_spawn=code,key_start='VK_122',key_stop='MOD_7'}).ok)
        assert(h.runtime.handlers.configure_teleport_key({key_spawn='BACK',key_start='VK_122',key_stop='MOD_6'}).ok)
        assert(not h.runtime.handlers.configure_teleport_key({key_spawn='TNOPE',key_start='VK_123',key_stop='MOD_7'}).ok)
        if owned then
            local r=h.runtime.handlers.configure_teleport_key({key_spawn=code,key_start='VK_'..owned[1],key_stop='MOD_'..owned[2]})
            assert(not r.ok and r.message:find('功能「',1,true),'a function key keeps its chord: '..tostring(r.message))
        end
        assert(h.runtime:unitKeyReserved(122,7)=='传送：'..place.name,'unit keys see the chord as taken')
    end)
    h.keys['F11:7']();h:drain();assert(went[1]==place.name,'one press teleports')
    h.keys['F11:6']();h:drain();assert(went[2]=='BACK')
    h:run(function()assert(h.runtime.handlers.configure_teleport_key({key_spawn=code,key_start='UNBOUND',key_stop='MOD_0'}).ok)end)
    h.keys['F11:7']();h:drain();assert(#went==2,'an unbound chord does nothing')
end)
test('a Hun summon key uses the Hun entry with the saved count and respects the queue',function()
    local h=harness();local summons,frozen={},{}
    local profile={kit=true,count=3,revision=7,resources={medicine_count=2}}
    local body={spawn=function(_,arena,team,count,revision,snapshot)
            summons[#summons+1]=team..':'..count..':'..tostring(revision)
            frozen[#summons]=snapshot
            return {ok=true,message='fixture hun',spawned_count=count}
        end,
        status=function()return {probe_supported=true,full_ready=false,prepared=0,message='m'}end}
    h.runtime=h.new({support={hunBody=body},hunLoadout=function()return profile end});h.runtime:start();h:tick()
    local proposal={};for name,value in pairs(h.runtime.functionKeys.entries)do proposal[name]=value end
    proposal.hun_blue='VK_119_MOD_0';proposal.hun_neutral='VK_119_MOD_1'
    h:run(function()assert(h.runtime:configure(proposal).ok)end)
    h.keys.F8();assert(#summons==0);h:drain();assert(#summons==1 and summons[1]=='blue:3:7',summons[1])
    assert(frozen[1] and frozen[1].revision==7 and frozen[1].resources.medicine_count==2,
        'the immediate key must pass the loadout it used for the revision and count')
    h.keys['F8:1']();h:drain();assert(summons[2]=='neutral:3:7')
    local queue=h.runtime.summonQueue
    queue.enabled=true;h.keys.F8();h:drain()
    assert(#summons==2 and #queue.jobs==1,'queued Hun is not an immediate spawn')
    profile.revision=8;profile.resources.medicine_count=99
    h:run(function()queue:tick()end)
    assert(summons[3]=='blue:3:7' and frozen[3].resources.medicine_count==2)
    h.files['memory/hun-queued-loadout.tsv']='123\t'..queue:epoch()..'\nHunLoadoutV1\t4\ncount\t2\nkit\t1\n'
    local packet={id='123',unit_id='',team='red',count=2,key_spawn='4',key_start=queue:epoch(),action='hun_body_probe'}
    local function submit()return h:run(function()return h.runtime.handlers.hun_body_probe(packet)end) end
    assert(submit().ok and #queue.jobs==1)
    h.files['memory/hun-queued-loadout.tsv']='invalid'
    queue.nextAt=0;h:run(function()queue:tick()end)
    assert(summons[4]=='red:2:4' and frozen[4].revision==4)
    assert(not submit().ok and #queue.jobs==0,'unreadable snapshot never runs')
    h:run(function()queue:cancel('test')end)
    assert(not submit().ok and #queue.jobs==0,'expired epoch must never run')
    h.keys.F8();h:run(function()queue:cancel('cancel between keypress and game-thread callback')end)
    h:drain();assert(#queue.jobs==0 and #summons==4,'stale Hun key must not rejoin after cancellation')
end)
test('a profile save between the hotkey read and direct spawn cannot cancel the accepted batch',function()
    local oldPath=package.path;package.path='Mods/PhantomGladiator/Scripts/?.lua;'..oldPath
    local Body=require('hun_body')
    local h=harness();local reads=0
    local function loadout()
        reads=reads+1
        return reads==1 and {kit=true,count=3,revision=7} or {kit=true,count=1,revision=8}
    end
    local world={IsValid=function()return true end,GetAddress=function()return 35 end}
    local body=Body.new({world=function()return world end,loadout=loadout,requireProfile=true})
    local arena={spawn=function(_,path,team,count)
        assert(path==Body.path and team=='red');return {ok=true,spawned_count=count}
    end}
    h.runtime=h.new({arena=arena,support={hunBody=body},hunLoadout=loadout})
    local result=h:run(function()return h.runtime.handlers.hun_red({})end)
    package.path=oldPath
    assert(result.ok and result.spawned_count==3 and reads==1,'a single key press must use one complete saved profile')
end)
test('a legacy Hun selection uses the saved kit through both the regular key and its queued copy',function()
    local h=harness();local seen={}
    local profile={kit=true,count=5,revision=4,resources={medicine_count=2}}
    h.selection={'/Game/FixtureHun.FixtureHun_C','red',2}
    local body={spawn=function(_,arena,team,count,revision,snapshot)
        assert(team=='red' and count==2 and revision=='4' and snapshot.resources.medicine_count==2)
        seen[#seen+1]=snapshot;return {ok=true,spawned_count=count}
    end,status=function()return {}end}
    h.runtime=h.new({support={hunBody=body},hunLoadout=function()return profile end})
    h.runtime:start();h:tick()
    h:run(function()assert(h.runtime:dispatch('spawn',{}).ok)end);assert(#seen==1 and count(h,'spawn')==0)
    local queue=h.runtime.summonQueue;queue.enabled=true
    h:run(function()assert(h.runtime:queueSummon(function()error('must use queue')end).ok)end)
    profile.revision=5;profile.resources.medicine_count=9
    h:run(function()queue:tick()end);assert(#seen==2 and count(h,'spawn')==0)
end)
print("panel_runtime: PASS ("..passed.." real-module control regressions; no game accessed)")
