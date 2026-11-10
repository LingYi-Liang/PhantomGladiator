-- 文件桥接：tick 由 main 在游戏线程调用，每次至多处理一条命令。
-- 目录由部署方创建。只读写约定TSV，不扫描目录、不执行shell或Lua文件。
local Bridge = {}
Bridge.__index = Bridge
local MAX_INBOX, MAX_JOURNAL, MAX_MESSAGE = 2048, 2097152, 512
-- The journal heals itself (v0.38.1); before, each of these stopped every later command for good, through game and
-- app restarts, and the app's selection never reached the game (a player's summon key kept giving the old unit):
--   a last line cut off by a crash is dropped (a cut "started" line never ran: commands run only after it reads
--   back; a cut "done" line leaves its "started" line, so the command is answered uncertain, never run again);
--   a full journal is rewritten with the newest KEEP_COMMANDS commands (the panel never sends an id twice);
--   a record that cannot be read sets the file aside and starts a new one, the command in the inbox marked started.
local KEEP_COMMANDS = 500
local JOURNAL, COMPACT = "command-journal.tsv", "command-journal.compact.tsv"
-- Status entries per write. The panel reports about 120 today; v0.36.0 went past the old cap of 100
-- and each Lua state dropped a random few (the battle clock, fun_supported, current_count...).
local MAX_STATUS = 256
local MAX_COUNT = 100   -- units per summon, as arena_controller.lua MAX_BATCH
local ACTIONS = { spawn = true, queue_spawn = true, set_summon_queue = true, cancel_summon_queue = true, start = true, stop = true, refresh_catalog = true, set_unit_rule = true,
    toggle_track = true, track_pick = true, track_next = true, set_camera_track = true,
    configure_keys = true,configure_unit_key=true, select_unit = true, toggle_spectator = true,clear_neutral=true,toggle_stat_match=true,
    toggle_camera=true,exit_camera=true,cycle_team=true,set_spawn_difficulty=true,dismiss_companions=true,recall_companions=true,toggle_time_stop=true,set_free_camera=true,set_fun_feature=true,set_boss_combos=true,set_team_immortal=true,set_clock_hud=true,set_execution_camera=true,set_companion_executions=true,set_stat_mode=true,set_companion_stats=true,set_ai_params=true,set_spawn_level=true,repair_save=true }
local ACK_STATUS = { ok = true, error = true, uncertain = true }

local function clean(value, limit)
    local text = (value == nil and "" or tostring(value)):gsub("%c", " ")
    limit = limit or MAX_MESSAGE
    if #text <= limit then return text end
    text = text:sub(1, limit - 3)
    while #text > 0 and text:byte(-1) >= 128 and text:byte(-1) <= 191 do text = text:sub(1, -2) end
    if #text > 0 and text:byte(-1) >= 192 then text = text:sub(1, -2) end
    return text .. "..."
end

local function split(line)
    local fields, start = {}, 1
    while true do
        local at = line:find("\t", start, true)
        if not at then fields[#fields + 1] = line:sub(start) break end
        fields[#fields + 1] = line:sub(start, at - 1)
        start = at + 1
    end
    return fields
end

local function validID(id)
    return type(id) == "string" and #id >= 1 and #id <= 80 and id:match("^[%w_%-]+$") ~= nil
end

local function countText(value)
    if value == "unknown" then return value end
    if type(value) == "number" and value >= 0 and value <= MAX_COUNT and value % 1 == 0 then return tostring(value) end
    if type(value) == "string" and value:match("^%d%d?%d?$") and tonumber(value) <= MAX_COUNT then return value end
    return nil
end

local function ackLine(ack)
    return table.concat({ ack.id, ack.status, ack.message, ack.spawned_count }, "\t") .. "\n"
end

local function doneLine(ack)
    return table.concat({ ack.id, "done", ack.status, ack.message, ack.spawned_count }, "\t") .. "\n"
end

local function parseInbox(content)
    if content == "" then return nil, "empty" end
    if content:sub(-1) ~= "\n" then return nil, "incomplete: inbox has no terminating newline" end
    local line = content:sub(1, -2)
    if line:sub(-1) == "\r" then line = line:sub(1, -2) end
    local fields = split(line)
    local id = validID(fields[1]) and fields[1] or nil
    if #content > MAX_INBOX then return nil, "invalid payload: inbox too long", id end
    -- configure_keys: schema 2 carries eight keys in 14 columns, schema 3 ten in 16 (recall_companions and
    -- toggle_time_stop, v0.38.2), schema 4 thirteen in 19 (toggle_track, track_pick and track_next).
    local extended=fields[2]=='configure_keys' and ((#fields==14 and fields[14]=='2') or (#fields==16 and fields[16]=='3') or (#fields==19 and fields[19]=='4'))
    if line:find("[\r\n]") or (not extended and #fields~=10) then return nil, "invalid payload: expected one line with 10, 14, 16 or 19 columns", id end
    if not id then return nil, "invalid payload: command id", nil end
    if not ACTIONS[fields[2]] then return nil, "invalid payload: unknown action", id end
    if #fields[3] > 512 or fields[3]:find("%c") then return nil, "invalid payload: unit_id", id end
    if (fields[2] == "spawn" or fields[2] == "queue_spawn" or fields[2] == "select_unit" or fields[2]=='configure_unit_key') and fields[3] == "" then
        return nil, "invalid payload: unit_id is required", id
    end
    if fields[4] ~= "blue" and fields[4] ~= "red" and fields[4] ~= "neutral" and fields[4] ~= "companion" then
        return nil, "invalid payload: team", id
    end
    if not fields[5]:match("^[1-9]%d?%d?$") or tonumber(fields[5]) > MAX_COUNT then
        return nil, "invalid payload: count must be 1.." .. MAX_COUNT, id
    end
    for i = 6, extended and #fields - 1 or 9 do
        if #fields[i] > 32 or (fields[i] ~= "" and not fields[i]:match("^[A-Z0-9_]+$")) then
            return nil, "invalid payload: key name", id
        end
        if fields[2] == "configure_keys" and fields[i] == "" then
            return nil, "invalid payload: four key names are required", id
        end
    end
    if not extended and fields[10] ~= "1" then return nil, "invalid payload: schema_version", id end
    local command={ id = id, action = fields[2], unit_id = fields[3], team = fields[4], count = tonumber(fields[5]),
        key_spawn = fields[6], key_start = fields[7], key_stop = fields[8],
        key_refresh_catalog = fields[9], schema_version = extended and tonumber(fields[#fields]) or 1 }
    if extended then
        command.key_toggle_camera=fields[10];command.key_exit_camera=fields[11]
        command.key_cycle_team=fields[12];command.key_toggle_spectator=fields[13]
        if #fields>=16 then command.key_recall_companions=fields[14];command.key_toggle_time_stop=fields[15] end
        if #fields==19 then command.key_toggle_track=fields[16];command.key_track_pick=fields[17];command.key_track_next=fields[18] end
    end
    return command,nil,id
end

function Bridge.new(options)
    options = options or {}
    assert(type(options.path) == "string" and #options.path > 0 and #options.path <= 1024
        and not options.path:find("%c"), "bridge requires an explicit runtime directory")
    local self = setmetatable({
        path = options.path:gsub("[\\/]+$", ""), log = options.log or function() end,
        handlers = options.handlers or {}, provider = options.status or function() return {} end,
        session = options.session,
        io = options.io or io, os = options.os or os, clock = options.clock or os.time,
        records = {}, recovery = {}, pending = nil, journalReady = false,
        state = "ready", message = "bridge ready", lastIssue = nil,
    }, Bridge)
    self:_loadJournal()
    return self
end

function Bridge:_sessionError(command)
    if not self.session then return "game_session_unavailable: 未配置会话校验，指令未执行" end
    local ok,current=pcall(self.session)
    if not ok or type(current)~="table" or type(current.game_session)~="string" or current.game_session=="" then
        return "game_session_unavailable: 当前游戏会话未确认，指令未执行"
    end
    local sidecar=self:_read("inbox.session.tsv",512)
    local id,session
    if type(sidecar)=="string" then id,session=sidecar:match("^([%w_%-]+)\t([%w_%-]+)\r?\n$") end
    if id~=command.id or session~=current.game_session then
        return "stale_game_session: 指令属于旧会话或缺少绑定，请重新请求"
    end
    if (command.action=="spawn" or command.action=="queue_spawn" or command.action=="start" or command.action=="toggle_spectator")
        and current.game_ready~=true then
        return "game_not_ready: 尚未进入可控制场景，指令未执行"
    end
    return nil
end

function Bridge:_unknown(message)
    self.state, self.message = "unknown", clean(message)
    if self.lastIssue ~= self.message then self.log("面板桥接unknown: " .. self.message) self.lastIssue = self.message end
end

function Bridge:_read(name, limit)
    local okOpen, file, errorText, code = pcall(self.io.open, self.path .. "/" .. name, "rb")
    if not okOpen then return nil, clean(file), false end
    if not file then return nil, clean(errorText), code == 2 end
    local okRead, content, readError = pcall(function() return file:read(limit + 1) end)
    local okClose, closed, closeError = pcall(function() return file:close() end)
    if okRead and content == nil and readError == nil then content = "" end -- 空文件的正常EOF。
    if not okRead or type(content) ~= "string" then return nil, "read failed: " .. clean(readError or content), false end
    if not okClose or not closed then return nil, "read close failed: " .. clean(closeError or closed), false end
    if #content > limit then return nil, "file exceeds size limit", false end
    return content
end

function Bridge:_writeVerified(name, content, append, previous)
    local okOpen, file, errorText = pcall(self.io.open, self.path .. "/" .. name, append and "ab" or "wb")
    if not okOpen or not file then return false, "open failed: " .. clean(errorText or file) end
    local okWrite, written, writeError = pcall(function() return file:write(content) end)
    local okFlush, flushed, flushError = pcall(function() return file:flush() end)
    local okClose, closed, closeError = pcall(function() return file:close() end)
    if not okWrite or not written or not okFlush or not flushed or not okClose or not closed then
        return false, "write/flush/close not confirmed: " .. clean(writeError or flushError or closeError or "I/O failure")
    end
    local expected = append and (previous .. content) or content
    local readback, readError = self:_read(name, (name == JOURNAL or name == COMPACT) and MAX_JOURNAL or 65536)
    if readback ~= expected then return false, "readback differs: " .. clean(readError or "content mismatch") end
    return true
end

-- A journal whose last write was cut off loses that line (see KEEP_COMMANDS above for why that is safe).
function Bridge:_repairTail(content)
    if content == "" or content:sub(-1) == "\n" then return content end
    local whole = content:match("^(.*\n)") or ""
    local ok, errorText = self:_writeVerified(JOURNAL, whole, false)
    if not ok then return nil, "journal incomplete and not repaired: " .. errorText end
    self.log("指令日志末尾有一行没写完（上次写入中断），已去掉这 " .. (#content - #whole) .. " 字节；这一行的指令不会重复执行")
    return whole
end

-- The newest KEEP_COMMANDS commands of a journal, each with all its lines, in journal order.
local function newest(content)
    local order, lines = {}, {}
    for line in content:gmatch("([^\n]+)\n") do
        local id = line:match("^([^\t\r]+)")
        if id then
            if not lines[id] then lines[id] = {}; order[#order + 1] = id end
            local list = lines[id]; list[#list + 1] = line .. "\n"
        end
    end
    local out = {}
    for i = math.max(1, #order - KEEP_COMMANDS + 1), #order do out[#out + 1] = table.concat(lines[order[i]]) end
    return table.concat(out), math.min(#order, KEEP_COMMANDS), #order
end

-- Written beside the journal and renamed over it; a stop in between leaves the copy, which _loadJournal takes.
function Bridge:_compactJournal(content)
    local kept, count, total = newest(content)
    local ok, errorText = self:_writeVerified(COMPACT, kept, false)
    if not ok then return nil, "compact copy not confirmed: " .. errorText end
    local journal, copy = self.path .. "/" .. JOURNAL, self.path .. "/" .. COMPACT
    local okRemove, removed, removeError = pcall(self.os.remove, journal)
    if not okRemove or not removed then return nil, "old journal not removed: " .. clean(removeError or removed) end
    local okRename, renamed, renameError = pcall(self.os.rename, copy, journal)
    if not okRename or not renamed then return nil, "compact copy not renamed: " .. clean(renameError or renamed) end
    self.log(string.format("指令日志到了 %d 字节上限，只留最近 %d 条指令（原有 %d 条）", MAX_JOURNAL, count, total))
    return kept
end

-- A journal with a record it cannot read is renamed and kept, and a new one begins with the command in the inbox,
-- if any, marked started: it is answered uncertain and never run a second time.
function Bridge:_setAside(reason)
    -- The new journal is read straight away; a fault in that one is not set aside again.
    if self.settingAside then self:_unknown(reason .. "; execution blocked") return false end
    local name = "command-journal.bad-" .. tostring(self.clock()) .. ".tsv"
    local okRename, renamed, renameError = pcall(self.os.rename, self.path .. "/" .. JOURNAL, self.path .. "/" .. name)
    if not okRename or not renamed then
        self:_unknown(reason .. "; journal not set aside: " .. clean(renameError or renamed)) return false
    end
    local inbox = self:_read("inbox.tsv", MAX_INBOX + 1)
    local id = type(inbox) == "string" and inbox:match("^([^\t\r\n]+)\t") or nil
    if id and not validID(id) then id = nil end
    local ok, errorText = self:_writeVerified(JOURNAL, id and (id .. "\tstarted\n") or "", false)
    if not ok then self:_unknown(reason .. "; new journal not written: " .. errorText) return false end
    self.log("指令日志有读不懂的记录（" .. reason .. "），已改名为 " .. name .. " 保留，重新开始记录"
        .. (id and ("；收件箱里的指令 " .. id .. " 按结果未知回复，不会执行") or ""))
    self.settingAside = true
    local loaded = self:_loadJournal()
    self.settingAside = false
    return loaded
end

function Bridge:_appendJournal(line)
    local content, errorText, missing = self:_read(JOURNAL, MAX_JOURNAL)
    if content == nil then
        if missing then content = "" else return false, errorText end
    end
    content, errorText = self:_repairTail(content)
    if not content then return false, errorText end
    if #content + #line > MAX_JOURNAL then
        content, errorText = self:_compactJournal(content)
        if not content then return false, "journal full and not compacted: " .. errorText end
        if #content + #line > MAX_JOURNAL then return false, "journal size limit reached; pending command retained" end
    end
    return self:_writeVerified(JOURNAL, line, true, content)
end

function Bridge:_loadJournal()
    local content, errorText, missing = self:_read(JOURNAL, MAX_JOURNAL)
    if content == nil and missing then
        local copy = self:_read(COMPACT, MAX_JOURNAL)
        if copy then
            local okRename, renamed, renameError = pcall(self.os.rename, self.path .. "/" .. COMPACT, self.path .. "/" .. JOURNAL)
            if not okRename or not renamed then self:_unknown("compact journal not restored: " .. clean(renameError or renamed)) return false end
            self.log("指令日志压缩时中断过，已用压缩后的副本接上")
            content, missing = copy, false
        end
    end
    if content == nil and errorText == "file exceeds size limit" then
        content = self:_read(JOURNAL, 4 * MAX_JOURNAL)
        if content then content, errorText = self:_compactJournal(content) end
        if not content then self:_unknown("journal over size limit and not compacted: " .. tostring(errorText)) return false end
    end
    if content == nil and not missing then self:_unknown("journal read failed: " .. errorText) return false end
    content = content or ""
    content, errorText = self:_repairTail(content)
    if not content then self:_unknown(errorText) return false end
    local records, order = {}, {}
    for line in content:gmatch("([^\n]+)\n") do
        if line:sub(-1) == "\r" then line = line:sub(1, -2) end
        local f = split(line)
        if not validID(f[1]) then return self:_setAside("journal invalid id") end
        if f[2] == "started" and #f == 2 then
            if records[f[1]] and records[f[1]].state == "done" then
                return self:_setAside("journal started after done")
            end
            if not records[f[1]] then order[#order + 1] = f[1] end
            records[f[1]] = { state = "started" }
        elseif f[2] == "done" and #f == 5 and ACK_STATUS[f[3]] and #f[4] <= MAX_MESSAGE
            and not f[4]:find("%c") and countText(f[5]) then
            local ack = { id = f[1], status = f[3], message = f[4], spawned_count = f[5] }
            local old = records[f[1]]
            if not old or (old.state == "done" and ackLine(old.ack) ~= ackLine(ack)) then
                return self:_setAside("journal invalid completion")
            end
            records[f[1]] = { state = "done", ack = ack }
        else return self:_setAside("journal invalid record") end
    end
    self.records, self.recovery, self.journalReady = records, {}, true
    for _, id in ipairs(order) do
        if records[id].state == "started" then self.recovery[#self.recovery + 1] = id end
    end
    return true
end

function Bridge:_execute(command, validationError)
    validationError=validationError or self:_sessionError(command)
    if validationError then
        return { id = command.id, status = "error", message = clean(validationError), spawned_count = "0" }
    end
    local handler = self.handlers[command.action]
    if type(handler) ~= "function" then
        return { id = command.id, status = "error", message = "handler unavailable: " .. command.action, spawned_count = "0" }
    end
    self.log("面板命令执行：id=" .. command.id .. " action=" .. command.action .. "；journal started已关闭且读回确认")
    local ok, result = pcall(handler, command)
    if not ok or type(result) ~= "table" or type(result.ok) ~= "boolean" then
        return { id = command.id, status = "uncertain", message = clean("uncertain: handler failed or returned invalid result; not replayed: " .. clean(result)), spawned_count = "unknown" }
    end
    local count = countText(result.spawned_count)
    if result.uncertain==true then
        return {id=command.id,status='uncertain',message=clean(result.message or '生成结果未确认，未重试'),spawned_count=count or 'unknown'}
    end
    if not count and command.action ~= "spawn" and result.spawned_count == nil then count = "0" end
    if not count or count == "unknown" then
        return { id = command.id, status = "uncertain", message = "uncertain: handler returned invalid spawned_count; not replayed", spawned_count = "unknown" }
    end
    return { id = command.id, status = result.ok and "ok" or "error",
        message = clean(result.message or "handler returned no message"), spawned_count = count }
end

function Bridge:_advancePending()
    local pending = self.pending
    if pending.phase == "start" then
        local ok, errorText = self:_appendJournal(pending.command.id .. "\tstarted\n")
        if not ok then self:_unknown("journal started not confirmed; command not run: " .. errorText) return end
        self.records[pending.command.id] = { state = "started" }
        pending.ack = self:_execute(pending.command, pending.validationError)
        pending.phase = "done"
    end
    if pending.phase == "done" then
        local ok, errorText = self:_appendJournal(doneLine(pending.ack))
        if not ok then self:_unknown("journal completion not confirmed; result pending, not replayed: " .. errorText) return end
        self.records[pending.ack.id] = { state = "done", ack = pending.ack }
        pending.phase = "ack"
    end
    if pending.phase == "ack" then
        local ok, errorText = self:_writeVerified("ack.tsv", ackLine(pending.ack), false)
        if not ok then self:_unknown("ack not confirmed; completed result retained: " .. errorText) return end
        self.state = pending.ack.status == "ok" and "ready" or pending.ack.status
        self.message, self.lastIssue = pending.ack.message, nil
        self.pending = nil
    end
end

function Bridge:_writeStatus()
    local values = {}
    local ok, supplied = pcall(self.provider)
    if not ok or type(supplied) ~= "table" then
        self:_unknown("status provider failed: " .. clean(supplied))
    else
        local count = 0
        for key, value in pairs(supplied) do
            if count >= MAX_STATUS then
                if not self.statusCapped then self.statusCapped = true; self.log("状态项超过 " .. MAX_STATUS .. " 项，多出的未写入") end
                break
            end
            if type(key) == "string" and #key <= 64 and key:match("^[%w_]+$")
                and (type(value) == "string" or type(value) == "number" or type(value) == "boolean") then
                values[key], count = clean(value), count + 1
            end
        end
    end
    values.schema_version, values.heartbeat_unix = "1", tostring(self.clock())
    values.state, values.message = self.state, clean(self.message)
    local keys, lines = {}, {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do lines[#lines + 1] = key .. "\t" .. values[key] end
    local written, errorText = self:_writeVerified("status.tsv", table.concat(lines, "\n") .. "\n", false)
    if not written then self:_unknown("status write not confirmed: " .. errorText) end
end

function Bridge:tick()
    if not self.journalReady and not self:_loadJournal() then self:_writeStatus() return end
    if self.pending then
        self:_advancePending()
    elseif #self.recovery > 0 then
        local id = table.remove(self.recovery, 1)
        self.pending = { phase = "done", ack = { id = id, status = "uncertain",
            message = "uncertain: previous execution interrupted; not replayed", spawned_count = "unknown" } }
        self:_advancePending()
    else
        local content, errorText, missing = self:_read("inbox.tsv", MAX_INBOX + 1)
        if content == nil then
            if not missing then self:_unknown("inbox read failed; command remains pending: " .. errorText) end
        else
            local command, parseError, id = parseInbox(content)
            if id then
                local old = self.records[id]
                if old and old.state == "done" then
                    self.pending = { phase = "ack", ack = old.ack }
                elseif old then
                    self.pending = { phase = "done", ack = { id = id, status = "uncertain",
                        message = "uncertain: previous execution interrupted; not replayed", spawned_count = "unknown" } }
                else
                    self.pending = { phase = "start", command = command or { id = id }, validationError = parseError }
                end
                self:_advancePending()
            elseif parseError ~= "empty" then
                self.state, self.message = "pending", clean(parseError)
                if not parseError:find("^incomplete") then self:_unknown(parseError) end
            end
        end
    end
    self:_writeStatus()
end

return Bridge
