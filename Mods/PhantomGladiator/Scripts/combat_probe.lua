-- 有界、只读的战斗探针。start/stop 应由游戏线程调用。
-- 头文件依据：SGameCombatSystem.hpp、SGameAttributes.hpp、ProjectPBZ.hpp。
-- 当前诊断默认关闭。dff435dd实际用FUNC_Native/FuncPtr分派，不仅看资源路径；
-- 本模块历史script分类还需按真实flag纠正，尤其/Script下的BP事件与Puerts函数。
-- https://docs.ue4ss.com/lua-api/global-functions/registerhook.html
-- https://docs.ue4ss.com/lua-api/global-functions/unregisterhook.html
-- UE4SS dff435dd LuaMod.cpp:304-320: native post 有返回值时在实际参数前插入原返回值。
-- https://github.com/UE4SS-RE/RE-UE4SS/blob/dff435dd/UE4SS/src/Mod/LuaMod.cpp#L304
-- 探针只记录观察结果；安装成功 != 已观测执行，零回调 != 函数从未执行。

local Probe = {}

local function clipped(value, limit)
    local s = tostring(value or "unknown"):gsub("[\r\n]", " ")
    return #s > limit and s:sub(1, limit) .. "..." or s
end

local function bounded(value, default, low, high)
    local n = tonumber(value) or default
    if n ~= n then n = default end
    return math.floor(math.max(low, math.min(high, n)))
end

-- 这些是回调中的参数/结构体访问，不是 UObject 链式调用。
local function get(param)
    if param == nil then return nil end
    if type(param) == "number" or type(param) == "boolean" or type(param) == "string" then
        return param
    end
    local ok, value = pcall(function() return param:get() end)
    if ok then return value end
    return nil
end

local function field(struct, name)
    if struct == nil then return nil end
    local ok, value = pcall(function() return struct[name] end)
    if ok then return value end
    return nil
end

local function scalar(value)
    local t = type(value)
    if t == "number" or t == "boolean" or t == "string" then return tostring(value) end
    return "unknown"
end

local function fname(value)
    if type(value) == "string" then return clipped(value, 120) end
    if value == nil then return "unknown" end
    local ok, s = pcall(function() return value:ToString() end)
    if ok and type(s) == "string" then return clipped(s, 120) end
    return "unknown"
end

local function tag(value)
    return fname(field(value, "TagName"))
end

local function array_text(array, render)
    if array == nil then return "unknown" end
    local parts = {}
    local ok = pcall(function()
        array:ForEach(function(_, item)
            if #parts >= 6 then return true end
            parts[#parts + 1] = render(get(item))
            if #parts >= 6 then return true end
        end)
    end)
    if not ok then return "unknown" end
    local okN, n = pcall(function() return #array end)
    return "[" .. table.concat(parts, ",") .. "] count=" .. (okN and tostring(n) or "unknown")
end

local function tags(container)
    return array_text(field(container, "GameplayTags"), tag)
end

local function damage_map(map)
    if map == nil then return "unknown" end
    local parts = {}
    local ok = pcall(function()
        map:ForEach(function(key, value)
            if #parts >= 6 then return true end
            parts[#parts + 1] = tag(get(key)) .. "=" .. scalar(get(value))
            if #parts >= 6 then return true end
        end)
    end)
    if not ok then return "unknown" end
    local okN, n = pcall(function() return #map end)
    return "{" .. table.concat(parts, ",") .. "} count=" .. (okN and tostring(n) or "unknown")
end

function Probe.new(options)
    options = options or {}
    local cfg = options.config or {}
    local duration = bounded(cfg.DurationMs, 60000, 1000, 60000)
    local maxEvents = bounded(cfg.MaxEvents, 2000, 1, 5000)
    local maxLogs = bounded(cfg.MaxLogs, 100, 1, 200)
    local perHookLogs = bounded(cfg.MaxLogsPerHook, 12, 1, 24)
    local generation, active, stopPending, sessionOpen = 0, false, false, false
    local hooks, counts, emitted, candidates = {}, {}, {}, {}
    local timerHandles, timerRegistrationUncertain = {}, false
    local discovery = { subjects = 0, classes = 0, functions = 0, selected = 0, errors = 0, limited = false }
    local total, lines, errors, mismatches, started, label = 0, 0, 0, 0, 0, "none"
    local lastReason, unavailable, registrationUncertain = "not_started", 0, false
    local instance = {}

    local function log(message)
        local output = "[CombatProbe] " .. message
        if options.log then pcall(options.log, output) else print(output .. "\n") end
    end

    local function valid(object)
        if object == nil then return false end
        local ok, value = pcall(function() return object:IsValid() end)
        if not ok or value ~= true then return false end
        if options.valid then
            local okExtra, extra = pcall(options.valid, object)
            return okExtra and extra == true
        end
        return true
    end

    local function property(object, name)
        if not valid(object) then return nil end
        return field(object, name)
    end

    local function describe(object)
        if not valid(object) then return "unknown(invalid_or_unavailable)" end
        local ok, address = pcall(function() return object:GetAddress() end)
        local addr = ok and tostring(address) or "unknown"
        local name
        if options.describe then
            local okName, s = pcall(options.describe, object)
            if okName and type(s) == "string" then name = s end
        end
        if not name then
            if not valid(object) then return "unknown(invalidated)" end
            local okName, s = pcall(function() return object:GetFullName() end)
            if okName and type(s) == "string" then name = s end
        end
        return clipped(name, 210) .. "@" .. addr
    end

    local function owner(component)
        if not valid(component) then return nil end
        local ok, actor = pcall(function() return component:GetOwner() end)
        if ok and valid(actor) then return actor end
        return nil
    end

    local function hp(actor)
        if not valid(actor) then return "unknown" end
        local attributes = property(actor, "AttributeSetBase")
        if not valid(attributes) then return "unknown" end
        local health = property(attributes, "Health")
        return scalar(field(health, "CurrentValue"))
    end

    -- TScriptInterface 的 Lua 表示未在本构建验证；不猜 ObjectPointer 等字段。
    -- 只有参数本身确实是有效 UObject 时才记录身份，不调用未知接口 getter。
    local function interface_identity(value)
        if valid(value) then return describe(value) end
        return "unknown(interface_not_resolved)"
    end

    local function snapshot(candidate, context, raw, phase)
        local kind, offset = candidate.kind, 0
        if not candidate.script and phase == "post" and raw.n == candidate.params + 1 then
            offset = 1
        elseif raw.n ~= candidate.params then
            -- 在读任何 UObject / 参数代理之前拒绝不符合已核实签名的布局。
            return string.format("readback=unknown(signature_mismatch) argc=%d expected=%d%s", raw.n,
                candidate.params, not candidate.script and phase == "post" and " or expected+return" or ""), false
        end
        local args = { n = candidate.params }
        for i = 1, candidate.params do args[i] = raw[i + offset] end
        local self = get(context)
        local parts = { "context=" .. describe(self), "argc=" .. tostring(raw.n), "return_offset=" .. offset }
        if phase == "post" then
            local original = "unknown(not_present)"
            if offset == 1 then original = scalar(get(raw[1])) end
            if candidate.script then original = "unknown(script_return_not_assumed)" end
            parts[#parts + 1] = "original_return=" .. original
        end
        if kind == "bullet_component" or kind == "bullet_actor" or kind == "valid_target" then
            local attacker = property(self, "LastOwnerAvatar")
            local target = get(args[1])
            if kind == "bullet_component" then
                parts[#parts + 1] = "hit_component=" .. describe(target)
                target = owner(target)
            end
            parts[#parts + 1] = "source=" .. describe(attacker)
            parts[#parts + 1] = "target=" .. describe(target)
            parts[#parts + 1] = "target_hp=" .. hp(target)
            if kind == "valid_target" then
                parts[#parts + 1] = "required=" .. tags(property(self, "TargetRequiredTags"))
                parts[#parts + 1] = "ignored=" .. tags(property(self, "TargetIgnoredTags"))
            end
        elseif kind == "damage" then
            local target = owner(self)
            parts[#parts + 1] = "source=" .. interface_identity(get(args[1]))
            parts[#parts + 1] = "target=" .. describe(target)
            parts[#parts + 1] = "target_hp=" .. hp(target)
            parts[#parts + 1] = "cause=" .. tag(get(args[2]))
            parts[#parts + 1] = "attack=" .. damage_map(get(args[6]))
            if phase == "post" then
                parts[#parts + 1] = "final_damage=" .. damage_map(get(args[10]))
            end
        elseif kind == "hitreact" then
            parts[#parts + 1] = "source=" .. interface_identity(get(args[1]))
            parts[#parts + 1] = "target=" .. describe(owner(self))
            parts[#parts + 1] = "hit_component=" .. describe(get(args[2]))
            parts[#parts + 1] = "hit_bone=" .. fname(get(args[3]))
        elseif kind == "trace" then
            local query = get(args[1])
            local requirements = field(query, "TagRequirements")
            parts[#parts + 1] = "source=" .. describe(get(args[2]))
            parts[#parts + 1] = "by_profile=" .. scalar(field(query, "bTraceByProfile"))
            parts[#parts + 1] = "profile=" .. fname(field(query, "ProfileName"))
            parts[#parts + 1] = "object_types=" .. array_text(field(query, "ObjectTypes"), scalar)
            parts[#parts + 1] = "required=" .. tags(field(requirements, "RequireTags"))
            parts[#parts + 1] = "ignored_tags=" .. tags(field(requirements, "IgnoreTags"))
            parts[#parts + 1] = "ignored_actors=" .. array_text(field(query, "ActorsToIgnore"), describe)
        elseif kind == "attitude" then
            parts[#parts + 1] = "other=" .. describe(get(args[1]))
        elseif kind == "health_post" then
            parts[#parts + 1] = "new_value=" .. scalar(get(args[1]))
            parts[#parts + 1] = "old_value=" .. scalar(get(args[2]))
            parts[#parts + 1] = "hp_readback=" .. hp(self)
        elseif kind == "attribute_change" then
            parts[#parts + 1] = "attribute=" .. fname(field(get(args[1]), "AttributeName"))
            parts[#parts + 1] = "new_value=" .. scalar(get(args[2]))
            parts[#parts + 1] = "old_value=" .. scalar(get(args[3]))
            parts[#parts + 1] = "hp_readback=" .. hp(self)
        elseif kind == "gameplay_event" then
            local payload = get(args[1])
            parts[#parts + 1] = "event_tag=" .. tag(field(payload, "EventTag"))
            parts[#parts + 1] = "instigator=" .. describe(field(payload, "Instigator"))
            parts[#parts + 1] = "target=" .. describe(field(payload, "Target"))
            parts[#parts + 1] = "magnitude=" .. scalar(field(payload, "EventMagnitude"))
            parts[#parts + 1] = "hp_readback=" .. hp(self)
        elseif kind == "on_damage" then
            parts[#parts + 1] = "damage_amount=" .. scalar(get(args[1]))
            parts[#parts + 1] = "damage_tags=" .. tags(get(args[2]))
            parts[#parts + 1] = "hp_readback=" .. hp(self)
            parts[#parts + 1] = "effect_context=unknown(opaque_handle)"
        elseif kind == "death_callback" then
            parts[#parts + 1] = "hp_readback=" .. hp(self)
        end
        return table.concat(parts, " | ")
    end

    local nativeCombat = {
        { name = "TryAttack", path = "/Script/SGameCombatSystem.BulletAttackModule:TryAttack", kind = "bullet_component", params = 6 },
        { name = "IsValidTarget", path = "/Script/SGameCombatSystem.BulletAttackModule:IsValidTarget", kind = "valid_target", params = 1 },
        { name = "DealDamageToAvatar", path = "/Script/SGameCombatSystem.BulletAttackModule:DealDamageToAvatar", kind = "bullet_actor", params = 5 },
        { name = "TakeDamage", path = "/Script/SGameAttributes.AttributeComponent:TakeDamage", kind = "damage", params = 10 },
        { name = "PlayHitreact", path = "/Script/SGameCombatSystem.HitreactComponent:PlayHitreact", kind = "hitreact", params = 7 },
        { name = "EnableHitTrace", path = "/Script/ProjectPBZ.PBZHitTraceComponent:EnableHitTrace", kind = "trace", params = 2 },
    }
    local attitude = {
        { name = "PBZAttitude", path = "/PBZCombatAsset/Prototypes/AI/BP_PBZAIController.BP_PBZAIController_C:BlueprintGetTeamAttitudeTowards", kind = "attitude", params = 1, script = true },
        { name = "SGameAttitude", path = "/SGameAI/BP_SGameAIController.BP_SGameAIController_C:BlueprintGetTeamAttitudeTowards", kind = "attitude", params = 1, script = true },
    }

    -- 仅这些方法的签名已在当前游戏头文件核实；不匹配 EventReceived_/Changed_ 通配符。
    local whitelist = {
        ["Health Post Func"] = { kind = "health_post", params = 2 },
        ["Health Post Func__puerts_mixin__"] = { kind = "health_post", params = 2 },
        ["Changed_65C423C64D9460919B5AC49EEE1A1401"] = { kind = "attribute_change", params = 3 },
        ["Changed_343661D44F5A56AF1FB43D80F0C4E471"] = { kind = "attribute_change", params = 3 },
        ["Changed_292EEC1441513CBF4DDBDEB97B4DA1E4"] = { kind = "attribute_change", params = 3 },
        ["Changed_A4A9527E4940BCFDC36F31A30C6E7D19"] = { kind = "attribute_change", params = 3 },
        ["On Dead"] = { kind = "death_callback", params = 0 },
        ["EventReceived_13CF76504740A063984FCAB3DC9EAF88"] = { kind = "gameplay_event", params = 1 },
        ["EventReceived_BBCE3D294DBB64EC44FB3E8A0BC2B34A"] = { kind = "gameplay_event", params = 1 },
        ["EventReceived_82A5AC00445AE3F15CD7A285F43CBE03"] = { kind = "gameplay_event", params = 1 },
        ["EventReceived_B1FF86534050CD4041F4E69109D6C58E"] = { kind = "gameplay_event", params = 1 },
        ["EventReceived_BB0EB7934EE9267E314D6D913AE454B2"] = { kind = "gameplay_event", params = 1 },
    }

    local function build_candidates(subjects)
        candidates = {}
        discovery = { subjects = 0, classes = 0, functions = 0, selected = 0, errors = 0, limited = false }
        local seenPath, seenClass = {}, {}
        local lookupLines = 0
        local function lookup_log(message)
            if lookupLines >= 48 then return end
            lookupLines = lookupLines + 1
            log(message)
        end
        local function append(candidate)
            if seenPath[candidate.path] then return end
            seenPath[candidate.path] = true
            candidates[#candidates + 1] = candidate
        end
        if cfg.IncludeNativeCombat ~= false then
            for _, candidate in ipairs(nativeCombat) do append(candidate) end
        end
        append({ name = "OnDamage", path = "/Script/ProjectPBZ.PBZCharacter:OnDamage", kind = "on_damage", params = 3 })
        if cfg.IncludeAttitude == true then
            for _, candidate in ipairs(attitude) do append(candidate) end
        end
        if type(subjects) ~= "table" then subjects = {} end
        for index, subject in ipairs(subjects) do
            if index > 8 then discovery.limited = true; break end
            discovery.subjects = discovery.subjects + 1
            local cls
            if valid(subject) then
                local ok, value = pcall(function() return subject:GetClass() end)
                if ok and valid(value) then cls = value end
            end
            if not cls then
                discovery.errors = discovery.errors + 1
                lookup_log("动态查找 subject=" .. index .. " class=unknown(invalid_or_unavailable)")
            end
            for depth = 1, 12 do
                if not valid(cls) then break end
                local okName, className = pcall(function() return cls:GetFullName() end)
                if not okName or type(className) ~= "string" then
                    discovery.errors = discovery.errors + 1
                    break
                end
                if seenClass[className] then break end
                seenClass[className] = true
                discovery.classes = discovery.classes + 1
                if not valid(cls) then break end
                local localFunctions = 0
                local okEnum = pcall(function()
                    cls:ForEachFunction(function(fn)
                        if localFunctions >= 512 or discovery.functions >= 4096 or discovery.selected >= 32 then
                            discovery.limited = true
                            return true
                        end
                        localFunctions, discovery.functions = localFunctions + 1, discovery.functions + 1
                        if not valid(fn) then return end
                        local okFull, full = pcall(function() return fn:GetFullName() end)
                        if not okFull or type(full) ~= "string" then return end
                        local path = full:match("^Function (/.+)$")
                        if not path or path:find("[\r\n]") then return end
                        local method = path:match(":([^:]+)$")
                        local rule = whitelist[method]
                        if not rule or path:find("__DelegateSignature", 1, true) or seenPath[path] then return end
                        if not valid(fn) then return end
                        local okFlags, flags = pcall(function() return fn:GetFunctionFlags() end)
                        -- EFunctionFlags: Delegate=0x00100000, MulticastDelegate=0x00010000。
                        if not okFlags or type(flags) ~= "number" or flags ~= math.floor(flags) then
                            discovery.errors = discovery.errors + 1
                            lookup_log("动态函数跳过（flags未读回） " .. path)
                            return
                        end
                        if (flags & 0x00110000) ~= 0 then
                            lookup_log("动态函数跳过（delegate） " .. path)
                            return
                        end
                        discovery.selected = discovery.selected + 1
                        append({ name = path, path = path, kind = rule.kind, params = rule.params,
                            script = path:sub(1, 8) ~= "/Script/", dynamic = true })
                        lookup_log("动态查找读回 depth=" .. depth .. " function=" .. path .. " params=" .. rule.params .. " flags=" .. flags .. "（尚未注册/未验证执行）")
                    end)
                end)
                if not okEnum then discovery.errors = discovery.errors + 1 end
                if not valid(cls) then break end
                local okSuper, super = pcall(function() return cls:GetSuperStruct() end)
                if not okSuper or not valid(super) then break end
                if depth == 12 then discovery.limited = true end
                cls = super
            end
        end
        log(string.format("动态查找汇总 subjects=%d classes=%d functions=%d selected=%d errors=%d limited=%s；仅使用已读回的函数路径。",
            discovery.subjects, discovery.classes, discovery.functions, discovery.selected, discovery.errors, tostring(discovery.limited)))
    end

    local function timer_count()
        local count = 0
        for _ in pairs(timerHandles) do count = count + 1 end
        return count
    end

    local function schedule_stop(delayMs, callbackFn)
        local ok, handle = pcall(ExecuteInGameThreadWithDelay, delayMs, callbackFn)
        if not ok then return false, handle end
        if type(handle) ~= "number" or handle ~= math.floor(handle) or handle < 0 or handle == math.huge then
            timerRegistrationUncertain = true
            return false, "游戏线程timer未返回有效handle: " .. tostring(handle)
        end
        timerHandles[handle] = true
        return true
    end

    local function cancel_timers()
        local remaining = {}
        for handle in pairs(timerHandles) do
            local ok, cancelled = pcall(CancelDelayedAction, handle)
            if not ok then
                remaining[handle] = true
                log("取消timer失败，旧回调已静默 handle=" .. handle .. ": " .. clipped(cancelled, 160))
            elseif cancelled ~= true and cancelled ~= false then
                remaining[handle] = true
                log("取消timer返回未识别，保留重试 handle=" .. handle)
            end
            -- 官方false表示未找到可取消项（包括已完成/PendingRemoval）；不当作取消成功宣称。
            -- Executing one-shot也允许标记PendingRemoval，故当前回调的handle仍在此集合中。
        end
        timerHandles = remaining
    end

    local function deferred_stop(reason, token)
        if token ~= generation or stopPending then return end
        active, stopPending = false, true
        -- 延迟到下一次游戏线程调度；不在当前hook内注销自身，也不经过异步Lua线程。
        local ok, err = schedule_stop(1, function()
            if token == generation then instance:stop(reason) end
        end)
        if not ok then
            log("停止计时失败，回调已静默；请再次手动停止以注销: " .. clipped(err, 160))
        end
    end

    local function callback(candidate, phase, token)
        return function(context, ...)
            -- 所有返回路径均不返回值，不覆盖原函数返回值/出参。
            if not active or token ~= generation then return end
            if os.time() - started >= math.ceil(duration / 1000) then
                deferred_stop("time_limit", token)
                return
            end
            if total >= maxEvents then
                deferred_stop("event_limit", token)
                return
            end
            total = total + 1
            local c = counts[candidate.name]
            c[phase] = c[phase] + 1
            if lines < maxLogs and emitted[candidate.name] < perHookLogs then
                local args = table.pack(...)
                local ok, details, signatureOk = pcall(snapshot, candidate, context, args, phase)
                if signatureOk == false then mismatches = mismatches + 1 end
                lines = lines + 1
                emitted[candidate.name] = emitted[candidate.name] + 1
                if not ok then
                    errors = errors + 1
                    details = "readback=unknown(lua_error:" .. clipped(details, 160) .. ")"
                end
                log(string.format("样本=%s event=%d %s %s | %s", label, total, candidate.name, phase, details))
            end
            if total >= maxEvents then deferred_stop("event_limit", token) end
        end
    end

    function instance:status()
        local summary = {}
        for name, count in pairs(counts) do
            summary[name] = { pre = count.pre, post = count.post }
        end
        local lookup = {}
        for key, value in pairs(discovery) do lookup[key] = value end
        return { active = active, stopPending = stopPending, label = label, generation = generation,
            events = total, detailLines = lines, snapshotErrors = errors, signatureMismatches = mismatches, hooks = #hooks,
            unavailable = unavailable, durationMs = duration, reason = lastReason, counts = summary,
            registrationUncertain = registrationUncertain, discovery = lookup,
            timerHandles = timer_count(), timerRegistrationUncertain = timerRegistrationUncertain }
    end

    -- OnUnload 专用：不碰 UObject，不新建任务；仅取消宿主延迟队列。
    -- hook 的实际注销交给宿主卸载；旧回调因 generation 变化立即失效。
    function instance:silence(reason)
        active, stopPending, sessionOpen = false, false, false
        generation = generation + 1
        lastReason = clipped(reason or "unload", 100)
        cancel_timers()
        log(string.format("静默 样本=%s reason=%s events=%d remaining_timers=%d；采样已静默，hook注销由宿主卸载处理。", label, lastReason, total, timer_count()))
        return self:status()
    end

    function instance:stop(reason)
        local notifyStop = sessionOpen
        local hadSession = sessionOpen or active or stopPending or #hooks > 0 or timer_count() > 0
        active, stopPending, sessionOpen = false, false, false
        generation = generation + 1
        lastReason = clipped(reason or "manual", 100)
        cancel_timers()
        local remaining = {}
        for _, hook in ipairs(hooks) do
            local ok, err = pcall(UnregisterHook, hook.path, hook.preId, hook.postId)
            if not ok then
                remaining[#remaining + 1] = hook
                log("注销失败（旧回调已静默） " .. hook.name .. ": " .. clipped(err, 160))
            end
        end
        hooks = remaining
        if hadSession then
            log(string.format("停止 样本=%s reason=%s events=%d detailLines=%d snapshotErrors=%d signatureMismatches=%d remaining_hooks=%d remaining_timers=%d", label, lastReason, total, lines, errors, mismatches, #hooks, timer_count()))
            for _, candidate in ipairs(candidates) do
                local c = counts[candidate.name]
                if c then log(string.format("计数 %s pre=%d post=%d", candidate.name, c.pre, c.post)) end
            end
            log("读回说明：unknown/零回调/安装失败均不能证明该函数未执行；须与正常 NPC→玩家样本对照。")
        end
        local status = self:status()
        if notifyStop and options.onStop then
            local ok, err = pcall(options.onStop, status)
            if not ok then log("onStop失败: " .. clipped(err, 160)) end
        end
        return #hooks == 0 and timer_count() == 0 and not registrationUncertain and not timerRegistrationUncertain, status
    end

    function instance:start(newLabel, subjects)
        if options.config and options.config.Enabled==false then
            log('诊断挂钩已关闭；未查找或注册任何战斗/玩家血量hook')
            return false,self:status()
        end
        if active or stopPending or #hooks > 0 or timer_count() > 0 then self:stop("restart") end
        if #hooks > 0 or timer_count() > 0 or registrationUncertain or timerRegistrationUncertain then
            log("未启动：旧hook/timer未完全清理或注册ID不明；需清理或Restart All Mods后重试。")
            return false, self:status()
        end
        for _, name in ipairs({ "StaticFindObject", "RegisterHook", "UnregisterHook", "ExecuteInGameThreadWithDelay", "CancelDelayedAction" }) do
            if type(_G[name]) ~= "function" then
                log("未启动：缺少 " .. name .. "，无法保证有界采样与停止。")
                return false, self:status()
            end
        end
        generation = generation + 1
        local token = generation
        total, lines, errors, mismatches, unavailable = 0, 0, 0, 0, 0
        counts, emitted = {}, {}
        started, label, lastReason = os.time(), clipped(newLabel or "unlabelled", 100), "running"
        sessionOpen = true
        log(string.format("开始 样本=%s 操作=只读挂钩 durationMs=%d maxEvents=%d maxDetailLogs=%d；不更改目标/阵营/血量/动画", label, duration, maxEvents, maxLogs))
        build_candidates(subjects)
        for _, candidate in ipairs(candidates) do
            counts[candidate.name], emitted[candidate.name] = { pre = 0, post = 0 }, 0
            local okFind, fn = pcall(StaticFindObject, candidate.path)
            if not okFind or not valid(fn) then
                unavailable = unavailable + 1
                log("读回=函数当前不可用 " .. candidate.path)
            else
                local ok, preId, postId
                if candidate.script then
                    ok, preId, postId = pcall(RegisterHook, candidate.path, callback(candidate, "post", token))
                else
                    ok, preId, postId = pcall(RegisterHook, candidate.path,
                        callback(candidate, "pre", token), callback(candidate, "post", token))
                end
                if ok and type(preId) == "number" and type(postId) == "number" then
                    hooks[#hooks + 1] = { name = candidate.name, path = candidate.path, preId = preId, postId = postId }
                    log(string.format("读回=注册ID %s pre=%s post=%s mode=%s（待实际回调验证）", candidate.name, tostring(preId), tostring(postId), candidate.script and "script_post" or "native_pre_post"))
                else
                    unavailable = unavailable + 1
                    if ok then registrationUncertain = true end
                    log("读回=注册失败或ID不明 " .. candidate.name .. ": " .. clipped(preId, 160))
                end
            end
        end
        if #hooks == 0 or registrationUncertain then
            self:stop("no_hooks_or_uncertain_registration")
            return false, self:status()
        end
        active = true
        local ok, err = schedule_stop(duration, function()
            -- 此回调已在游戏线程，直接停止；stop会取消含当前Executing项的全部handle。
            if token == generation and active then instance:stop("time_limit") end
        end)
        if not ok then
            log("自动停止计时器安装失败: " .. clipped(err, 160))
            self:stop("timer_failed")
            return false, self:status()
        end
        log(string.format("读回=采样已启用 installed=%d unavailable=%d events=0；仅在实际回调出现后确认观测入口有效。", #hooks, unavailable))
        return true, self:status()
    end

    return instance
end

return Probe
