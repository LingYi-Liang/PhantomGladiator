-- 文件协议/幂等测试；内存文件系统模拟重载和失败，不调用游戏handler。
local Bridge = dofile("Mods/PhantomGladiator/Scripts/panel_bridge.lua")
local tests = 0
local function test(name, body)
    body()
    tests = tests + 1
    print("PASS " .. name)
end

local function filesystem()
    local fs = { files = {}, session = { game_session = "test-session", game_ready = true } }
    fs.open = function(path, mode)
        if mode == "rb" and fs.files[path] == nil then return nil, "not found", 2 end
        if fs.failAckOnce and path:match("/ack%.tsv$") and mode == "wb" then
            fs.failAckOnce = false
            return nil, "ack disk unavailable", 13
        end
        if mode == "wb" then fs.files[path] = "" end
        if mode == "ab" and fs.files[path] == nil then fs.files[path] = "" end
        local cursor, closed = 1, false
        return {
            read = function(_, count)
                assert(not closed)
                local content = fs.files[path]
                if cursor > #content then return nil end
                local value = content:sub(cursor, cursor + count - 1)
                cursor = cursor + #value
                return value
            end,
            write = function(self, content)
                assert(not closed)
                if fs.failDoneOnce and path:match("/command%-journal%.tsv$") and content:find("\tdone\t", 1, true) then
                    fs.failDoneOnce = false
                    return nil, "journal write unavailable"
                end
                fs.files[path] = fs.files[path] .. content
                return self
            end,
            flush = function() assert(not closed) return true end,
            close = function()
                assert(not closed)
                closed = true
                if fs.failStartCloseOnce and mode == "ab" and fs.files[path]:match("\tstarted\n$") then
                    fs.failStartCloseOnce = false
                    return nil, "close unconfirmed"
                end
                return true
            end,
        }
    end
    return fs
end

local function command(id, action, unit, team, count, keys)
    keys = keys or { "", "", "", "" }
    return table.concat({ id, action or "spawn", unit == nil and "unit_a" or unit,
        team or "blue", tostring(count or 1), keys[1], keys[2], keys[3], keys[4], "1" }, "\t") .. "\n"
end

local function deliver(fs, payload, session)
    local id=assert(payload:match("^([^\t]+)"))
    fs.files["runtime/inbox.session.tsv"]=id.."\t"..(session or fs.session.game_session).."\n"
    fs.files["runtime/inbox.tsv"]=payload
end

local function create(fs, handler, extra)
    local options = { path = "runtime", io = fs, handlers = { spawn = handler },
        status = function() return { game_running = false } end,
        session = function() return fs.session end, clock = function() return 123456 end }
    for key, value in pairs(extra or {}) do options[key] = value end
    return Bridge.new(options)
end

test("persistent reload duplicate only resends stored ACK", function()
    local fs, calls = filesystem(), 0
    local function handler() calls = calls + 1 return { ok = true, message = "spawned", spawned_count = 1 } end
    deliver(fs,command("one"))
    create(fs, handler):tick()
    local ack = fs.files["runtime/ack.tsv"]
    assert(ack == "one\tok\tspawned\t1\n" and calls == 1)
    local reloaded = create(fs, handler)
    reloaded:tick()
    assert(calls == 1 and fs.files["runtime/ack.tsv"] == ack)
    deliver(fs,command("one", "spawn", "different_unit", "red", 8))
    reloaded:tick()
    assert(calls == 1 and fs.files["runtime/ack.tsv"] == ack)
end)

test("interrupted started command is uncertain and never replayed", function()
    local fs, calls = filesystem(), 0
    fs.files["runtime/command-journal.tsv"] = "interrupted\tstarted\n"
    deliver(fs,command("interrupted"))
    local function handler() calls = calls + 1 return { ok = true, spawned_count = 1 } end
    create(fs, handler):tick()
    assert(calls == 0)
    assert(fs.files["runtime/ack.tsv"] == "interrupted\tuncertain\tuncertain: previous execution interrupted; not replayed\tunknown\n")
    create(fs, handler):tick()
    assert(calls == 0)
end)

test("partial and incomplete inbox never executes", function()
    local fs, calls = filesystem(), 0
    local bridge = create(fs, function() calls = calls + 1 return { ok = true, spawned_count = 1 } end)
    deliver(fs,command("partial"):sub(1, -2))
    bridge:tick()
    assert(calls == 0 and fs.files["runtime/command-journal.tsv"] == nil)
    deliver(fs,"short\tspawn\tunit_a\n")
    bridge:tick()
    assert(calls == 0 and fs.files["runtime/ack.tsv"]:find("short\terror\t", 1, true))
    deliver(fs,command("complete"))
    bridge:tick()
    assert(calls == 1)
end)

test("different command ids execute once each", function()
    local fs, calls = filesystem(), 0
    local bridge = create(fs, function() calls = calls + 1 return { ok = true, message = "ok", spawned_count = 1 } end)
    for _, id in ipairs({ "a", "a", "b", "b", "c" }) do
        deliver(fs,command(id))
        bridge:tick()
    end
    assert(calls == 3 and fs.files["runtime/ack.tsv"] == "c\tok\tok\t1\n")
end)

test("illegal payloads never reach handlers", function()
    local fs, calls = filesystem(), 0
    local bridge = create(fs, function() calls = calls + 1 return { ok = true, spawned_count = 1 } end)
    local invalid = {
        command("bad_action", "shell"), command("bad_team", "spawn", "u", "evil"),
        command("bad_count", "spawn", "u", "blue", 101), command("zero_count", "spawn", "u", "blue", 0),
        command("padded_count", "spawn", "u", "blue", "050"), command("empty_unit", "spawn", ""),
        command("tab_unit", "spawn", "u\tmore"), command("newline", "spawn", "u\nmore"),
        command("bad_keys", "configure_keys", "", "blue", 1, { "F9", "F3", "F4", "bad key" }),
    }
    for _, payload in ipairs(invalid) do deliver(fs,payload) bridge:tick() end
    assert(calls == 0)
    assert(fs.files["runtime/ack.tsv"]:find("bad_keys\terror\t", 1, true))
end)

test("a summon of 50 or 100 reaches the handler and its count is acknowledged", function()
    for _, n in ipairs({ 50, 100 }) do
        local fs, seen = filesystem(), nil
        local bridge = create(fs, function(command) seen = command.count return { ok = true, spawned_count = n } end)
        deliver(fs, command("many" .. n, "spawn", "u", "red", n))
        bridge:tick()
        assert(seen == n and fs.files["runtime/ack.tsv"]:find("many" .. n .. "\tok\t", 1, true), tostring(fs.files["runtime/ack.tsv"]))
        assert(fs.files["runtime/ack.tsv"]:find("\t" .. n .. "\n", 1, true), "spawned_count " .. n .. " must be acknowledged as is")
    end
end)

test("queue spawn transport accepts a batch only once and checks the actual session", function()
    local fs, calls, time=filesystem(),0,100
    local Queue=dofile("Mods/PhantomGladiator/Scripts/summon_queue.lua")
    local queue=Queue.new({now=function()return time end,session=function()return fs.session end,
        spawn=function(path,team,count)
            assert(path=="unit_a" and team=="red" and count==3)
            calls=calls+1
            return {ok=true,message="spawned",spawned_count=3}
        end})
    queue.enabled=true
    queue:sync(fs.session)
    local epoch=queue:epoch()
    local bridge=create(fs, nil, {handlers={queue_spawn=function(request)
        queue:sync(fs.session)
        return queue:enqueue(request.unit_id,request.team,request.count,request.key_spawn)
    end}})
    deliver(fs,command("one", "queue_spawn", "unit_a", "red", 3, {epoch,"","",""}))
    bridge:tick()
    bridge:tick()
    assert(calls==0 and #queue.jobs==1 and fs.files["runtime/ack.tsv"]:match("^one\tok\t[^\n]+\t0\n$"))
    queue:tick()
    assert(calls==1 and #queue.jobs==0)
    fs.session={game_session="another-world",game_ready=true}
    deliver(fs,command("two", "queue_spawn", "unit_a", "red", 3, {epoch,"","",""}),"test-session")
    bridge:tick()
    assert(calls==1 and #queue.jobs==0 and fs.files["runtime/ack.tsv"]:find("stale_game_session",1,true))
end)

test("handler exception remains uncertain across reload", function()
    local fs, calls = filesystem(), 0
    local function handler() calls = calls + 1 error("partial game action") end
    deliver(fs,command("throws"))
    create(fs, handler):tick()
    assert(calls == 1 and fs.files["runtime/ack.tsv"]:find("throws\tuncertain\t", 1, true))
    assert(fs.files["runtime/ack.tsv"]:match("\tunknown\n$"))
    create(fs, handler):tick()
    assert(calls == 1)
end)

test("completion I/O failure retains result and does not execute new inbox early", function()
    local fs, calls = filesystem(), 0
    local bridge = create(fs, function() calls = calls + 1 return { ok = true, message = "ok", spawned_count = 1 } end)
    fs.failDoneOnce = true
    deliver(fs,command("first"))
    bridge:tick()
    assert(calls == 1 and bridge.pending and bridge.pending.phase == "done" and fs.files["runtime/ack.tsv"] == nil)
    deliver(fs,command("second"))
    bridge:tick()
    assert(calls == 1 and fs.files["runtime/ack.tsv"] == "first\tok\tok\t1\n")
    bridge:tick()
    assert(calls == 2 and fs.files["runtime/ack.tsv"] == "second\tok\tok\t1\n")
end)

test("started close must be confirmed before handler runs", function()
    local fs, calls = filesystem(), 0
    local bridge = create(fs, function() calls = calls + 1 return { ok = true, spawned_count = 1 } end)
    fs.failStartCloseOnce = true
    deliver(fs,command("close"))
    bridge:tick()
    assert(calls == 0 and bridge.pending.phase == "start")
    bridge:tick()
    assert(calls == 1)
end)

test("ACK I/O failure keeps durable result without replay", function()
    local fs, calls = filesystem(), 0
    local function handler() calls = calls + 1 return { ok = true, message = "ok", spawned_count = 1 } end
    fs.failAckOnce = true
    deliver(fs,command("ack_retry"))
    create(fs, handler):tick()
    assert(calls == 1 and fs.files["runtime/ack.tsv"] == nil)
    create(fs, handler):tick()
    assert(calls == 1 and fs.files["runtime/ack.tsv"] == "ack_retry\tok\tok\t1\n")
end)

test("heartbeat status reserves protocol fields and preserves scalar false", function()
    local fs = filesystem()
    fs.files["runtime/command-journal.tsv"] = "" -- 合法空文件，不是读取失败。
    local bridge = create(fs, function() error("must not execute") end,
        { status = function() return { schema_version = 99, heartbeat_unix = 0, game_running = false, alive = 4 } end })
    bridge:tick()
    local status = fs.files["runtime/status.tsv"]
    assert(status:find("schema_version\t1\n", 1, true))
    assert(status:find("heartbeat_unix\t123456\n", 1, true))
    assert(status:find("game_running\tfalse\n", 1, true) and status:find("alive\t4\n", 1, true))
end)

test("every status entry the panel reports is written, well past the old cap of 100", function()
    local fs = filesystem()
    fs.files["runtime/command-journal.tsv"] = ""
    local values = {}
    for i = 1, 150 do values["entry_" .. i] = i end
    local bridge = create(fs, function() error("must not execute") end, { status = function() return values end })
    bridge:tick()
    local status = fs.files["runtime/status.tsv"]
    for i = 1, 150 do assert(status:find("entry_" .. i .. "\t" .. i .. "\n", 1, true), "entry_" .. i .. " dropped") end
end)

test("select_unit validates target fields but does not imply spawning", function()
    local fs, selected, spawns = filesystem(), nil, 0
    local bridge = create(fs, nil, { handlers = {
        spawn = function() spawns = spawns + 1 return { ok = true, spawned_count = 1 } end,
        select_unit = function(c) selected = c.unit_id return { ok = true, message = "selected" } end,
    } })
    deliver(fs,command("select", "select_unit", "chosen", "red", 3))
    bridge:tick()
    assert(selected == "chosen" and spawns == 0 and fs.files["runtime/ack.tsv"] == "select\tok\tselected\t0\n")
    deliver(fs,command("bad_select", "select_unit", "", "red", 3))
    bridge:tick()
    assert(spawns == 0 and fs.files["runtime/ack.tsv"]:find("bad_select\terror\t", 1, true))
end)

test("toggle_spectator fixed wire executes once and duplicate ACK does not toggle it back", function()
    local fs, calls, enabled = filesystem(), 0, false
    local options = { handlers = { toggle_spectator = function(c)
        assert(c.unit_id == "" and c.team == "blue" and c.count == 1)
        calls = calls + 1
        enabled = not enabled
        return { ok = true, message = "spectator requested", spawned_count = 0 }
    end }, status = function() return { spectator_enabled = enabled } end }
    deliver(fs,command("spectator", "toggle_spectator", "", "blue", 1))
    create(fs, nil, options):tick()
    assert(calls == 1 and enabled)
    assert(fs.files["runtime/ack.tsv"] == "spectator\tok\tspectator requested\t0\n")
    create(fs, nil, options):tick()
    assert(calls == 1 and enabled)
    assert(fs.files["runtime/status.tsv"]:find("spectator_enabled\ttrue\n", 1, true))
end)

test("startup inbox from an old session is rejected and a new matching request can execute", function()
    local fs,calls=filesystem(),0
    fs.session.game_session="new-session"
    local bridge=create(fs,function()calls=calls+1;return {ok=true,message="new session",spawned_count=1}end)
    deliver(fs,command("old_startup"),"old-session")
    bridge:tick()
    assert(calls==0 and fs.files["runtime/ack.tsv"]:find("old_startup\terror\tstale_game_session",1,true))
    deliver(fs,command("old_startup"),"new-session")
    bridge:tick();assert(calls==0,"re-binding a completed rejected ID must not execute it")
    deliver(fs,command("fresh_request"),"new-session")
    bridge:tick()
    assert(calls==1 and fs.files["runtime/ack.tsv"]=="fresh_request\tok\tnew session\t1\n")
end)

test("missing malformed or wrong-id sidecars never reach handlers",function()
    local fs,calls=filesystem(),0
    local bridge=create(fs,function()calls=calls+1;return {ok=true,spawned_count=1}end)
    local invalid={false,"other-id\ttest-session\n","bad_session\tother-session\n","bad_session\ttest-session","bad_session\ttest-session\nextra\n"}
    for index,sidecar in ipairs(invalid)do
        local id="sidecar_"..index
        deliver(fs,command(id))
        fs.files["runtime/inbox.session.tsv"]=sidecar or nil
        bridge:tick()
        assert(calls==0 and fs.files["runtime/ack.tsv"]:find(id.."\terror\tstale_game_session",1,true))
    end
end)

test("matching session is insufficient until readiness is literal true",function()
    local fs,calls=filesystem(),0
    local function handler()calls=calls+1;return {ok=true,spawned_count=1}end
    local bridge=create(fs,nil,{handlers={spawn=handler,start=handler,toggle_spectator=handler}})
    for _,action in ipairs({"spawn","start","toggle_spectator"})do
        for index,case in ipairs({{value=false},{},{value="true"}})do
            fs.session.game_ready=case.value
            local id=action.."_not_ready_"..index
            deliver(fs,command(id,action,action=="spawn" and "unit_a" or ""))
            bridge:tick()
            assert(calls==0 and fs.files["runtime/ack.tsv"]:find(id.."\terror\tgame_not_ready",1,true))
        end
    end
    fs.session.game_ready=true;deliver(fs,command("now_ready"));bridge:tick();assert(calls==1)
end)

test("session and readiness are rechecked after parsing when journal confirmation delays execution",function()
    for _,change in ipairs({"session","readiness"})do
        local fs,calls=filesystem(),0
        local bridge=create(fs,function()calls=calls+1;return {ok=true,spawned_count=1}end)
        fs.failStartCloseOnce=true
        deliver(fs,command("delayed_"..change))
        bridge:tick()
        assert(calls==0 and bridge.pending and bridge.pending.phase=="start")
        if change=="session" then fs.session.game_session="changed-after-parse" else fs.session.game_ready=false end
        bridge:tick()
        local expected=change=="session" and "stale_game_session" or "game_not_ready"
        assert(calls==0 and fs.files["runtime/ack.tsv"]:find(expected,1,true))
    end
end)

test("completed IDs only resend the durable ACK even after session change",function()
    local fs,calls=filesystem(),0
    local function handler()calls=calls+1;return {ok=true,message="original outcome",spawned_count=1}end
    deliver(fs,command("completed"));create(fs,handler):tick();assert(calls==1)
    local ack=fs.files["runtime/ack.tsv"]
    fs.files["runtime/inbox.session.tsv"]=nil
    create(fs,handler,{session=function()error("done replay must not evaluate a new execution session")end}):tick()
    assert(calls==1 and fs.files["runtime/ack.tsv"]==ack)
end)

test("omitting the production session provider fails closed",function()
    local fs,calls=filesystem(),0
    deliver(fs,command("no_provider"))
    Bridge.new({path="runtime",io=fs,handlers={spawn=function()calls=calls+1;return {ok=true,spawned_count=1}end}}):tick()
    assert(calls==0,"missing session provider must never bypass the production gate")
    assert(fs.files["runtime/ack.tsv"]:find("game_session_unavailable",1,true))
end)

test('explicit native uncertainty preserves the user-facing reason and never replays',function()
    local fs,calls=filesystem(),0
    local function handler()
        calls=calls+1
        return {ok=false,uncertain=true,spawned_count='unknown',message='native result unknown; restart game'}
    end
    deliver(fs,command('native_unknown'))
    create(fs,handler):tick()
    assert(fs.files['runtime/ack.tsv']=='native_unknown\tuncertain\tnative result unknown; restart game\tunknown\n')
    create(fs,handler):tick();assert(calls==1)
end)

test('v2 key configuration carries eight explicit bindings including unbound values',function()
    local fs=filesystem();local calls=0
    local payload='newkeys\tconfigure_keys\t\tblue\t1\tUNBOUND\tUNBOUND\tUNBOUND\tUNBOUND\tVK_117_MOD_1\tVK_118_MOD_0\tVK_113_MOD_0\tUNBOUND\t2\n'
    local bridge=create(fs,nil,{handlers={configure_keys=function(command)
        calls=calls+1;assert(command.schema_version==2 and command.key_toggle_camera=='VK_117_MOD_1')
        assert(command.key_exit_camera=='VK_118_MOD_0' and command.key_cycle_team=='VK_113_MOD_0' and command.key_toggle_spectator=='UNBOUND')
        return {ok=true,message='configured',spawned_count=0}
    end}})
    deliver(fs,payload);bridge:tick();bridge:tick();assert(calls==1)
    deliver(fs,payload:gsub('newkeys','invalidkeys'):gsub('\t2\n','\t3\n'));bridge:tick();assert(calls==1)
end)

test('v3 key configuration adds recall and time stop as keys nine and ten; both are plain commands too',function()
    local fs=filesystem();local got,recalls,stops,camera,cameraTrack={},0,0,nil,nil
    local payload='keys3\tconfigure_keys\t\tblue\t1\tUNBOUND\tUNBOUND\tUNBOUND\tUNBOUND\tVK_117_MOD_1\tUNBOUND\tUNBOUND\tUNBOUND\tVK_116_MOD_0\tVK_80_MOD_0\t3\n'
    local bridge=create(fs,nil,{handlers={
        configure_keys=function(command)got[#got+1]=command;return {ok=true,message='configured',spawned_count=0}end,
        recall_companions=function()recalls=recalls+1;return {ok=true,message='已召回 1/1 个随从到身边',spawned_count=0}end,
        toggle_time_stop=function()stops=stops+1;return {ok=true,message='已解除时停',spawned_count=0}end,
        set_unit_rule=function(command)unitRule=command;return {ok=true,message='saved',spawned_count=0}end,
        set_camera_track=function(command)cameraTrack=command;return {ok=true,message='saved',spawned_count=0}end,
        set_free_camera=function(command)camera=command;return {ok=true,message='saved',spawned_count=0}end}})
    deliver(fs,payload);bridge:tick()
    assert(#got==1 and got[1].schema_version==3 and got[1].key_toggle_camera=='VK_117_MOD_1')
    assert(got[1].key_recall_companions=='VK_116_MOD_0' and got[1].key_toggle_time_stop=='VK_80_MOD_0')
    -- Ten keys with the eight-key schema number, nine keys with schema 3, or a blank tenth key never reach the handler.
    deliver(fs,payload:gsub('keys3','bad3a'):gsub('\t3\n','\t2\n'));bridge:tick()
    deliver(fs,payload:gsub('keys3','bad3b'):gsub('\tVK_80_MOD_0',''));bridge:tick()
    deliver(fs,payload:gsub('keys3','bad3c'):gsub('VK_80_MOD_0',''));bridge:tick()
    assert(#got==1)
    deliver(fs,command('r1','recall_companions',''));bridge:tick()
    assert(recalls==1 and fs.files['runtime/ack.tsv']=='r1\tok\t已召回 1/1 个随从到身边\t0\n')
    deliver(fs,command('t1','toggle_time_stop',''));bridge:tick()
    assert(stops==1 and fs.files['runtime/ack.tsv']=='t1\tok\t已解除时停\t0\n')
    -- Speed, turn and smoothing travel as whole numbers in the first three key columns.
    deliver(fs,'keys4\tconfigure_keys\t\tblue\t1\tUNBOUND\tUNBOUND\tUNBOUND\tUNBOUND\tVK_117_MOD_1\tUNBOUND\tUNBOUND\tUNBOUND\tUNBOUND\tUNBOUND\tVK_84_MOD_0\tVK_89_MOD_0\tVK_85_MOD_0\t4\n');bridge:tick()
    assert(#got==2 and got[2].schema_version==4 and got[2].key_toggle_track=='VK_84_MOD_0' and got[2].key_track_pick=='VK_89_MOD_0' and got[2].key_track_next=='VK_85_MOD_0')
    assert(got[2].key_recall_companions=='UNBOUND' and got[2].key_toggle_camera=='VK_117_MOD_1')
    deliver(fs,command('c0','set_unit_rule','BP_Monster_MoTian','blue',1,{'LOCK','KILL','',''}));bridge:tick()
    assert(unitRule and unitRule.unit_id=='BP_Monster_MoTian' and unitRule.key_spawn=='LOCK' and unitRule.key_start=='KILL')
    deliver(fs,command('c1','set_free_camera','','blue',1,{'1500','150','25',''}));bridge:tick()
    assert(camera and camera.key_spawn=='1500' and camera.key_start=='150' and camera.key_stop=='25')
    deliver(fs,command('c2','set_camera_track','2147468727','blue',1,{'SHOULDER','5','',''}));bridge:tick()
    assert(cameraTrack and cameraTrack.unit_id=='2147468727' and cameraTrack.key_spawn=='SHOULDER' and cameraTrack.key_start=='5')
    cameraTrack=nil
    deliver(fs,command('c3','set_camera_track','','blue',1,{'SIDE','0','',''}));bridge:tick()
    assert(cameraTrack and cameraTrack.unit_id=='' and cameraTrack.key_start=='0')
end)

test('camera exit is a session-bound recovery action that remains available while loading',function()
    local fs=filesystem();fs.session.game_ready=false;local exits=0
    local bridge=create(fs,nil,{handlers={exit_camera=function()exits=exits+1;return {ok=true,message='restored',spawned_count=0}end}})
    deliver(fs,command('exit','exit_camera',''));bridge:tick();assert(exits==1)
end)

-- The journal heals itself (v0.38.1): before, each of these stopped every later command until the file was fixed by hand.
local function withOs(fs)
    fs.remove = function(path)
        if fs.files[path] == nil then return nil, "not found" end
        if fs.lockedRemove then return nil, "file in use" end
        fs.files[path] = nil return true
    end
    fs.rename = function(from, to)
        if fs.files[from] == nil or fs.files[to] ~= nil then return nil, "rename refused" end
        fs.files[to], fs.files[from] = fs.files[from], nil return true
    end
    return { remove = fs.remove, rename = fs.rename }
end
local JOURNAL_PATH = "runtime/command-journal.tsv"

test("a journal line cut off by a crash is dropped: a cut start runs, a cut completion answers uncertain", function()
    local fs, calls, lines = filesystem(), 0, {}
    local function handler() calls = calls + 1 return { ok = true, message = "ok", spawned_count = 1 } end
    fs.files[JOURNAL_PATH] = "a\tstarted\na\tdone\tok\tok\t1\nb\tsta"
    deliver(fs, command("b"))
    local bridge = create(fs, handler, { os = withOs(fs), log = function(s) lines[#lines + 1] = s end })
    assert(fs.files[JOURNAL_PATH] == "a\tstarted\na\tdone\tok\tok\t1\n" and table.concat(lines):find("没写完", 1, true))
    bridge:tick()
    assert(calls == 1 and fs.files["runtime/ack.tsv"] == "b\tok\tok\t1\n")
    local fs2, calls2 = filesystem(), 0
    fs2.files[JOURNAL_PATH] = "c\tstarted\nc\tdone\tok\tsp"
    deliver(fs2, command("c"))
    create(fs2, function() calls2 = calls2 + 1 return { ok = true, spawned_count = 1 } end, { os = withOs(fs2) }):tick()
    assert(calls2 == 0 and fs2.files["runtime/ack.tsv"] == "c\tuncertain\tuncertain: previous execution interrupted; not replayed\tunknown\n")
end)

test("a line cut off while the game runs is dropped before the next command is written", function()
    local fs, calls = filesystem(), 0
    local bridge = create(fs, function() calls = calls + 1 return { ok = true, message = "ok", spawned_count = 1 } end, { os = withOs(fs) })
    fs.files[JOURNAL_PATH] = "x\tstarted\nx\tdone\tok\tok\t1\ny\tst"
    deliver(fs, command("y"))
    bridge:tick()
    assert(calls == 1 and fs.files[JOURNAL_PATH] == "x\tstarted\nx\tdone\tok\tok\t1\ny\tstarted\ny\tdone\tok\tok\t1\n", fs.files[JOURNAL_PATH])
end)

-- Records of fixed width (35 bytes plus the message) up to `size` bytes exactly.
local function fullJournal(size)
    local parts, total, n = {}, 0, 0
    local function add(length)
        n = n + 1
        local id = string.format("id%05d", n)
        local record = id .. "\tstarted\n" .. id .. "\tdone\tok\t" .. string.rep("m", length) .. "\t1\n"
        parts[#parts + 1] = record total = total + #record
    end
    while size - total >= 535 + 36 do add(500) end
    add(size - total - 35)
    assert(total == size)
    return table.concat(parts), n
end

test("a full journal keeps the newest 500 commands and the next one runs", function()
    local fs, calls, lines = filesystem(), 0, {}
    local journal0, n = fullJournal(2097152 - 5)
    fs.files[JOURNAL_PATH] = journal0
    local bridge = create(fs, function() calls = calls + 1 return { ok = true, message = "ok", spawned_count = 1 } end,
        { os = withOs(fs), log = function(s) lines[#lines + 1] = s end })
    deliver(fs, command("new"))
    bridge:tick()
    local journal = fs.files[JOURNAL_PATH]
    assert(calls == 1 and fs.files["runtime/ack.tsv"] == "new\tok\tok\t1\n")
    assert(journal:find("^" .. string.format("id%05d", n - 499) .. "\tstarted\n") and not journal:find(string.format("id%05d", n - 500), 1, true), journal:sub(1, 40))
    assert(journal:find("new\tstarted\nnew\tdone\tok\tok\t1\n$") and #journal < 300000 and fs.files["runtime/command-journal.compact.tsv"] == nil)
    assert(table.concat(lines):find("只留最近 500 条指令（原有 " .. n .. " 条）", 1, true), table.concat(lines))
    -- A kept command delivered again still only gets its stored answer.
    local kept = string.format("id%05d", n - 1)
    deliver(fs, command(kept))
    bridge:tick()
    assert(calls == 1 and fs.files["runtime/ack.tsv"] == kept .. "\tok\t" .. string.rep("m", 500) .. "\t1\n")
end)

test("a journal already over the limit is compacted when it is loaded", function()
    local fs, calls = filesystem(), 0
    local journal0, n = fullJournal(2097152 + 1000)
    fs.files[JOURNAL_PATH] = journal0
    deliver(fs, command("after"))
    create(fs, function() calls = calls + 1 return { ok = true, message = "ok", spawned_count = 1 } end, { os = withOs(fs) }):tick()
    assert(calls == 1 and fs.files["runtime/ack.tsv"] == "after\tok\tok\t1\n")
    assert(fs.files[JOURNAL_PATH]:find("^" .. string.format("id%05d", n - 499) .. "\t"))
end)

test("a compaction stopped before its rename is finished from the copy", function()
    local fs, calls = filesystem(), 0
    fs.files["runtime/command-journal.compact.tsv"] = "k\tstarted\nk\tdone\tok\tkept\t1\n"
    deliver(fs, command("k"))
    create(fs, function() calls = calls + 1 return { ok = true, spawned_count = 1 } end, { os = withOs(fs) }):tick()
    assert(calls == 0 and fs.files["runtime/ack.tsv"] == "k\tok\tkept\t1\n" and fs.files[JOURNAL_PATH] and fs.files["runtime/command-journal.compact.tsv"] == nil)
end)

test("an unreadable record sets the journal aside; the inbox command is answered uncertain, later ones run", function()
    local fs, calls, lines = filesystem(), 0, {}
    local function handler() calls = calls + 1 return { ok = true, message = "ok", spawned_count = 1 } end
    fs.files[JOURNAL_PATH] = "ok1\tstarted\nnot an id at all\n"
    deliver(fs, command("z"))
    local bridge = create(fs, handler, { os = withOs(fs), log = function(s) lines[#lines + 1] = s end })
    assert(fs.files["runtime/command-journal.bad-123456.tsv"] == "ok1\tstarted\nnot an id at all\n")
    assert(table.concat(lines):find("收件箱里的指令 z 按结果未知回复", 1, true), table.concat(lines))
    bridge:tick()
    assert(calls == 0 and fs.files["runtime/ack.tsv"]:find("^z\tuncertain\t"))
    deliver(fs, command("w"))
    bridge:tick()
    assert(calls == 1 and fs.files["runtime/ack.tsv"] == "w\tok\tok\t1\n")
end)

test("a journal that cannot be set aside stays blocked and is tried again", function()
    local fs, calls = filesystem(), 0
    local os2 = withOs(fs)
    os2.rename = function() return nil, "locked" end
    fs.files[JOURNAL_PATH] = "bad record\n"
    deliver(fs, command("q"))
    local bridge = create(fs, function() calls = calls + 1 return { ok = true, spawned_count = 1 } end, { os = os2 })
    bridge:tick()
    assert(calls == 0 and bridge.state == "unknown" and bridge.message:find("not set aside", 1, true) and fs.files["runtime/ack.tsv"] == nil)
    bridge.os = withOs(fs)
    bridge:tick()
    bridge:tick()
    assert(calls == 0 and fs.files["runtime/ack.tsv"]:find("^q\tuncertain\t"), tostring(fs.files["runtime/ack.tsv"]))
end)

-- 可选真实磁盘 smoke：外部测试命令负责创建/删除这个专用临时目录。
test("stat mode reaches its handler with the mode and the custom revision (backend.py wire)", function()
    local fs, got = filesystem(), nil
    deliver(fs, command("s1", "set_stat_mode", "", "blue", 1, { "CUSTOM", "R0123456789AB", "", "" }))
    local bridge = create(fs, nil, { handlers = { set_stat_mode = function(c)
        got = c return { ok = true, message = "custom", spawned_count = 0 } end } })
    bridge:tick()
    assert(got and got.key_spawn == "CUSTOM" and got.key_start == "R0123456789AB", fs.files["runtime/ack.tsv"])
    assert(fs.files["runtime/ack.tsv"] == "s1\tok\tcustom\t0\n", fs.files["runtime/ack.tsv"])
end)
test("the companions' stat set reaches its handler the same way", function()
    local fs, got = filesystem(), nil
    deliver(fs, command("s1", "set_companion_stats", "", "blue", 1, { "CUSTOM", "R0123456789AB", "", "" }))
    local bridge = create(fs, nil, { handlers = { set_companion_stats = function(c)
        got = c return { ok = true, message = "companion", spawned_count = 0 } end } })
    bridge:tick()
    assert(got and got.key_spawn == "CUSTOM" and got.key_start == "R0123456789AB", fs.files["runtime/ack.tsv"])
    assert(fs.files["runtime/ack.tsv"] == "s1\tok\tcompanion\t0\n", fs.files["runtime/ack.tsv"])
end)

if arg and arg[1] then
    test("real disk journal survives a new Bridge instance", function()
        local directory, calls = arg[1], 0
        local file = assert(io.open(directory .. "/inbox.tsv", "wb"))
        assert(file:write(command("disk"))) assert(file:close())
        file = assert(io.open(directory .. "/inbox.session.tsv", "wb"))
        assert(file:write("disk\tdisk-session\n")) assert(file:close())
        local options = { path = directory, handlers = { spawn = function()
            calls = calls + 1 return { ok = true, message = "disk ok", spawned_count = 1 }
        end }, session = function() return {game_session="disk-session",game_ready=true} end }
        Bridge.new(options):tick()
        Bridge.new(options):tick()
        assert(calls == 1)
        file = assert(io.open(directory .. "/ack.tsv", "rb"))
        local ack = file:read("*a") file:close()
        assert(ack == "disk\tok\tdisk ok\t1\n")
    end)
end

print(string.format("%d panel bridge tests passed; no game actions executed.", tests))
