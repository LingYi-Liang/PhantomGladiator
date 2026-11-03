-- 会话/就绪防护测试；不接触真实ModRef或游戏，不是崩溃复现。
local file = "Mods/PhantomGladiator/Scripts/runtime_session.lua"
local Session = dofile(file)
assert(type(Session) == "table", "runtime_session must return its module table")
local previousModRef, realTime = ModRef, os.time
os.time = function() return 1000 end
local function process(initial)
    local shared, writes = initial or {}, {}
    ModRef = {
        GetSharedVariable = function(_, key) return shared[key] end,
        SetSharedVariable = function(_, key, value)
            assert(type(value) == "string", "no UObject/table may cross Lua reload through ModRef")
            shared[key] = value
            writes[#writes + 1] = { key = key, value = value }
        end,
    }
    return shared, writes
end
local function fixture()
    local trace = {}
    local world = { alive = true, address = 12345 }
    local player = { alive = true, hp = 400, destroying = false }
    world.GetAddress = function(self)
        trace[#trace + 1] = "world_address"
        assert(self.alive, "invalid World must not be dereferenced")
        return self.address
    end
    local options = {
        valid = function(object)
            assert(object == world or object == player)
            trace[#trace + 1] = object == world and "valid_world" or "valid_player"
            return object.alive
        end,
        getWorld = function() trace[#trace + 1] = "get_world"; return world end,
        getPlayer = function() trace[#trace + 1] = "get_player"; return player end,
        isDestroying = function(actor)
            assert(actor == player and actor.alive, "Actor destruction API must only receive a valid player")
            trace[#trace + 1] = "player_destroying"
            return actor.destroying
        end,
        hp = function(actor)
            assert(actor == player and actor.alive, "invalid player must not reach HP read")
            trace[#trace + 1] = "player_hp"
            return actor.hp
        end,
    }
    return { world = world, player = player, options = options, trace = trace }
end
local shared, writes = process()
local f = fixture()
local session = Session.new(f.options)
local first = session:status()
assert(first.game_ready == true)
local position = {}
for i, event in ipairs(f.trace) do if not position[event] then position[event] = i end end
assert(position.valid_world < position.world_address)
assert(position.valid_player < position.player_destroying and position.valid_player < position.player_hp)
assert(session:status().game_session == first.game_session, "same world address must retain session")
local Reloaded = dofile(file)
local reloadedSession = Reloaded.new(f.options)
assert(reloadedSession:status().game_session ~= first.game_session, "hot reload loses actor ownership, so queued control commands must become stale")
assert(#writes == 3 and type(shared["PhantomGladiator.session.v1"]) == "string"
    and shared["PhantomGladiator.session_generation.v1"] == "2")
f.world.address = 98765
assert(session:status().game_session ~= first.game_session, "world change must change session")
f.world.address = 12345
assert(session:status().game_session == first.game_session)
process()
local newProcess = Reloaded.new(f.options)
assert(newProcess:status().game_session ~= first.game_session, "new ModRef/process must generate a distinct token")

for _, oldValue in ipairs({ {}, 123, "bad token with spaces", "unsafe\nvalue" }) do
    local store, changed = process({ ["PhantomGladiator.session.v1"] = oldValue })
    local replacement = Session.new(f.options)
    assert(type(store["PhantomGladiator.session.v1"]) == "string" and #changed == 2)
    assert(replacement:status().game_ready == true)
end

process(); f = fixture(); session = Session.new(f.options)
f.world.alive = false
local noWorld = session:status()
assert(not noWorld.game_ready and noWorld.game_session:match("%-no%-world$"))
assert(table.concat(f.trace, ",") == "get_world,valid_world", "invalid World must stop before address or player access")

process(); f = fixture(); session = Session.new(f.options)
f.player.alive = false
assert(not session:status().game_ready)
assert(not table.concat(f.trace, ","):find("player_destroying", 1, true))
assert(not table.concat(f.trace, ","):find("player_hp", 1, true))

process(); f = fixture(); session = Session.new(f.options)
f.player.destroying = true
assert(not session:status().game_ready)
assert(not table.concat(f.trace, ","):find("player_hp", 1, true))
f.player.destroying = "unknown"
assert(not session:status().game_ready)
f.player.destroying = nil
assert(not session:status().game_ready)
f.player.destroying = false
for _, hp in ipairs({ 0, -1, 0 / 0, "400", false }) do
    f.player.hp = hp
    assert(not session:status().game_ready, "unready/dead/unreadable HP must reject readiness")
end
f.player.hp = nil
assert(not session:status().game_ready)
f.options.hp = function() error("HP unavailable") end
assert(not session:status().game_ready)
f.options.isDestroying = function() error("destroy status unavailable") end
assert(not session:status().game_ready)
f.options.getPlayer = function() error("player not initialized") end
assert(not session:status().game_ready)
f.options.getWorld = function() error("world not initialized") end
assert(not session:status().game_ready)
ModRef, os.time = previousModRef, realTime
print("runtime_session: PASS (string-only reload token, world/process identity, guarded readiness, dead/destroying/NaN rejection; no native crash reproduced)")
