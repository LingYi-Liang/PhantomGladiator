-- 纯 Lua 擂台控制：引擎访问全部由注入回调完成，调用方负责游戏线程。
-- 只管理本控制器创建的参赛者；不枚举地图、不补伤害、不操作镜头。
local Arena = {}
-- MAX_BATCH is not a gameplay limit: a batch spawns inside one game-thread call (about 0.1 s per unit),
-- so this only keeps one mistyped number from freezing the game. The total on the field has no cap.
local MAX_UNITS, MAX_BATCH = 24, 100

local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function vector(v)
    if v == nil then return nil end
    local ok, x, y, z = pcall(function() return v.X, v.Y, v.Z end)
    if ok and finite(x) and finite(y) and finite(z) then return { X = x, Y = y, Z = z } end
end

local function team_name(value)
    local aliases = { blue = "blue", red = "red", neutral = "neutral", companion = "companion", ["蓝"] = "blue",
        ["蓝队"] = "blue", ["红"] = "red", ["红队"] = "red", ["中立"] = "neutral", ["随从"] = "companion" }
    return type(value) == "string" and aliases[value:lower()] or nil
end

function Arena.new(options)
    options = options or {}
    local maxUnits=options.maxUnits or MAX_UNITS
    assert(finite(maxUnits) and maxUnits%1==0 and maxUnits>=0,'invalid arena unit limit')
    local catalog = options.catalog
    local units, selected, team, count = {}, nil, "blue", 1
    local corpseGroups,lastCorpseCheck={},nil
    local rosterRevision,indexRevision=0,-1
    local rosterSerial=0
    local rosterOrdinals={blue={},red={}}
    local byKey,unkeyed={},{}
    local state, message, busy = "idle", "请选择单位与队伍", false
    local lastRestoreConfirmed = true
    local unknownSpawn = false
    local battleActive=false
    local relay={enabled=false,blue=0,red=0}
    -- Battle clock in game seconds (options.now): from the first status after the start in which both
    -- sides stand, to the first in which one side has nobody alive or unreadable. It starts over when a
    -- beaten side gets new units; stop clears it.
    local fight={}
    local reportOpen=false
    local teamRevision=0
    local instance = {}
    function instance:intentContext()
        if not battleActive or busy or state=='cleanup_pending'or state=='restore_pending'then return nil end
        return rosterRevision
    end

    local function log(text)
        if options.log then pcall(options.log, "[Arena] " .. text) end
    end

    local function invoke(name, ...)
        local fn = options[name]
        if type(fn) ~= "function" then return false, "缺少回调 " .. name end
        return pcall(fn, ...)
    end

    local function finishReport(result)
        if not reportOpen then return end
        reportOpen=false
        if options.onMatchEnded then
            local ok,err=pcall(options.onMatchEnded,result)
            if not ok then log('对局记录收尾失败: '..tostring(err)) end
        end
    end

    local function spawn_block()
        if unknownSpawn then return '生成结果未知，不能确认全部对象的所有权；请重新启动游戏后再试' end
        if options.spawnGuard then
            local ok,reason=pcall(options.spawnGuard.reason,options.spawnGuard)
            if not ok then return '生成保护状态读取失败' end
            return reason
        end
    end

    local function guard_call(method)
        if not options.spawnGuard then return true end
        local ok,result,reason=pcall(options.spawnGuard[method],options.spawnGuard)
        return ok and result==true,reason or (not ok and tostring(result) or nil)
    end

    local function live(actor)
        if actor == nil then return false end
        local ok, value = invoke("valid", actor)
        if not ok or type(value) ~= "boolean" then return nil end
        return value
    end

    local function actor_name(actor)
        if live(actor) ~= true then return "unknown(invalid_or_unreadable)" end
        local ok, value = invoke("name", actor)
        return ok and tostring(value) or "unknown(name)"
    end

    -- Read back how far a unit has to turn to face its opponent (0° facing it, 180° its back to it).
    local function facing_gap(actor, opponent)
        local okF, f = invoke("getForward", actor)
        local okA, a = invoke("getLocation", actor)
        local okB, b = invoke("getLocation", opponent)
        f, a, b = okF and vector(f), okA and vector(a), okB and vector(b)
        if not f or not a or not b then return "?" end
        local dx, dy = b.X - a.X, b.Y - a.Y
        local length = math.sqrt(dx * dx + dy * dy) * math.sqrt(f.X * f.X + f.Y * f.Y)
        if length < 0.0001 then return "?" end
        local cosine = math.max(-1, math.min(1, (dx * f.X + dy * f.Y) / length))
        return string.format("%.0f°", math.deg(math.acos(cosine)))
    end

    local function actor_key(actor)
        if live(actor)~=true then return nil end
        if options.actorKey then
            local ok,key=invoke('actorKey',actor)
            return ok and key~=nil and tostring(key) or nil
        end
        return tostring(actor)
    end

    local function health(actor)
        if live(actor) ~= true then return "unknown" end
        local ok, value = invoke("hp", actor)
        return ok and value ~= nil and tostring(value) or "unknown"
    end

    -- Actor进入销毁流程后，UObject仍可留在内存中；不能只等GC使IsValid变false。
    local function removed(actor)
        local validity=live(actor)
        if validity==false then return true,"IsValid=false" end
        if validity==nil then return nil,"IsValid=UNKNOWN" end
        if type(options.isDestroying)=="function" then
            local ok,destroying=invoke("isDestroying",actor)
            if not ok or type(destroying)~="boolean" then return nil,"IsActorBeingDestroyed=UNKNOWN" end
            return destroying,"IsActorBeingDestroyed="..tostring(destroying)
        end
        return false,"IsValid=true"
    end

    local function alive_readback(unit)
        local gone,why=removed(unit.actor)
        if gone==true then return false,why end
        if gone==nil then return nil,why end
        if options.hasCombatHealth then
            local ok,tracked=invoke('hasCombatHealth',unit.actor)
            if not ok then return nil,'血量类别未知' end
            if tracked==false then return true,'Actor有效；无战斗血量' end
        end
        local ok,hp=invoke('hp',unit.actor)
        if not ok or not finite(hp) then return nil,'HP=UNKNOWN' end
        if hp<=0 and options.holdsDeath then
            local checked,pending=invoke('holdsDeath',unit.actor)
            if checked and pending==true then return nil,'HP=0；原生重生判定中',hp end
        end
        if hp>0 and options.confirmedDead then
            local checked,dead=invoke('confirmedDead',unit.actor)
            if checked and dead then return false,'原生死亡已确认；HP='..tostring(hp),hp end
        end
        return hp>0,'HP='..tostring(hp),hp
    end

    -- A summon its summoner keeps hidden in reserve for a later phase (冷荼's seven stand-by dolls,
    -- GA_LengTu_SummonPassive_General: DeactivateAI and SetActorHiddenInGame on spawn) is not in the
    -- fight yet: not counted alive, not sent at an enemy and not chosen as anyone's target until shown.
    local function dormant(unit)
        if not unit.summoner or not options.dormant then return false end
        local ok,hidden=invoke('dormant',unit.actor)
        return ok and hidden==true
    end
    -- Stands are invulnerable skill participants, not independent combatants. Their type survives a fade.
    local function stand(unit)
        if unit.stand then return true end
        if not unit.summoner or not options.isStand then return false end
        -- Asked from hot paths (opponentOf answers the player hooks). A summon that is not one gets its tags with its AI,
        -- so it is asked again now and then rather than on every call.
        local clock=os.clock()
        if unit.standAskedAt and clock-unit.standAskedAt<1 then return false end
        unit.standAskedAt=clock
        local ok,result,proof=invoke('isStand',unit.actor,unit.class_path)
        if ok and result==true then
            unit.stand=true;unit.dormant=false;unit.assignedTarget,unit.assignedKey=nil,nil;unit.needsJoin=true
            log('替身身份读回 actor='..actor_name(unit.actor)..' 依据='..tostring(proof)..'；保留阵营关系和清理，不计存活、不迎敌、不作为对手')
            return true
        end
        return false
    end
    -- Out of reach by its own design for now (冷荼 until she comes down to fight herself, boss_stages.lua):
    -- it still fights, but nobody is sent at it.
    local function untargetable(unit)
        if not unit then return true end
        if options.targetProtected then
            local ok,result=invoke('targetProtected',unit.actor)
            if not ok or result~=false then return true end
        end
        if not options.untargetable then return false end
        local ok,result=invoke('untargetable',unit.actor)
        return not ok or result~=false
    end
    local function summonFactionReady(unit)
        if not unit.summoner or not options.factionReady then return true end
        local ok,ready=invoke('factionReady',unit.actor)
        if ok and ready==true then unit.awaitingFaction=nil;return true end
        unit.awaitingFaction,unit.needsJoin,unit.joinedPeers=true,true,nil
        return false
    end
    -- In the fight as a body: what a skill asking for "the player" may be given, out of reach or not.
    local function fighting(unit)
        return unit and not unit.awaitingFaction and not stand(unit) and not dormant(unit) and alive_readback(unit)==true
    end
    -- And what a unit may be sent at.
    local function targetable(unit)
        return fighting(unit) and not untargetable(unit)
    end
    local function unit_by_key(key)
        if not key then return nil end
        if indexRevision~=rosterRevision then
            byKey,unkeyed={},{}
            for _,unit in ipairs(units)do
                unit.key=unit.key or actor_key(unit.actor)
                if unit.key then
                    if not byKey[unit.key] then byKey[unit.key]=unit end
                else unkeyed[#unkeyed+1]=unit end
            end
            indexRevision=rosterRevision
        end
        if byKey[key] then return byKey[key] end
        -- Unknown identities can become readable without changing the roster; retry only those records.
        if #unkeyed>0 then
            local pending={}
            for _,unit in ipairs(unkeyed)do
                unit.key=unit.key or actor_key(unit.actor)
                if unit.key then
                    if not byKey[unit.key] then byKey[unit.key]=unit end
                else pending[#pending+1]=unit end
            end
            unkeyed=pending
        end
        return byKey[key]
    end

    local function notify_units()
        rosterRevision=rosterRevision+1
        indexRevision=-1;byKey,unkeyed=nil,nil
        corpseGroups={}
        local copy={}
        for _,unit in ipairs(units) do
            local group=unit.formationGroup
            if group and group.retire then
                local rows=corpseGroups[group] or {}
                rows[#rows+1]=unit;corpseGroups[group]=rows
            end
            if options.onUnitsChanged then
                copy[#copy+1]={actor=unit.actor,team=unit.team,class_path=unit.class_path,formation=unit.formation,
                    formationGroup=group,summoner=unit.summoner,aid=unit.aid==true}
            end
        end
        if not options.onUnitsChanged then return true end
        local ok, err = pcall(options.onUnitsChanged, copy)
        if not ok then log("参赛者同步失败: " .. tostring(err)) end
        return ok
    end

    -- Companions follow the player and are dismissed on their own; cleanup state is about the rest.
    local function arena_records()
        local n=0
        for _,unit in ipairs(units) do if unit.team~='companion' then n=n+1 end end
        return n
    end

    local function prune()
        local kept, changed
        for i, unit in ipairs(units) do
            -- 有效性读回未知时保留所有权，不能把回调错误当作已销毁。
            local gone,proof=removed(unit.actor)
            if gone==true then
                if not kept then
                    kept={};for j=1,i-1 do kept[#kept+1]=units[j] end
                end
                changed=true;log('移出已销毁登记：'..tostring(unit.class_path)..'；读回='..proof)
            elseif kept then kept[#kept+1]=unit end
        end
        if changed then
            units = kept
            notify_units()
            if arena_records()==0 and state=="cleanup_pending" then
                state=lastRestoreConfirmed and "idle" or "restore_pending"
                message=lastRestoreConfirmed and "清理已读回完成" or "参赛者已清理，部分恢复仍待确认"
                log(message)
            end
        end
    end

    local function response(ok, text, extra)
        message = text
        local result = { ok = ok, message = text }
        for key, value in pairs(extra or {}) do result[key] = value end
        log(text)
        return result
    end

    local function run(fn)
        if busy then return response(false, "上一个擂台操作尚未完成") end
        busy = true
        local ok, result = pcall(fn)
        busy = false
        if not ok then
            state = "operation_failed"
            return response(false, "操作异常，已登记参赛者保留供清理: " .. tostring(result), { remaining_count = #units })
        end
        return result
    end

    local function choose(path, requestedTeam, requestedCount, preserveSelection)
        local newTeam = requestedTeam == nil and team or team_name(requestedTeam)
        local newCount = requestedCount == nil and count or tonumber(requestedCount)
        if not newTeam then return false, "队伍只允许 blue/red/neutral/companion" end
        if not finite(newCount) or newCount % 1 ~= 0 or newCount < 1 or newCount > MAX_BATCH then
            return false, "单次数量必须是1到" .. MAX_BATCH .. "的整数"
        end
        local batchEntry
        if path ~= nil then
            if type(path) ~= "string" or path == "" then return false, "单位类路径为空" end
            local okPolicy,allowed,why=invoke("canSpawn",path)
            if not okPolicy or allowed~=true then return false,tostring(why or "未取得该单位的生成验证许可") end
            if type(catalog) ~= "table" or type(catalog.registerPath) ~= "function" or (not preserveSelection and type(catalog.select) ~= "function") then
                return false, "目录不支持路径登记和选择"
            end
            local okRegister, entry, why = pcall(catalog.registerPath, catalog, path)
            if not okRegister or not entry then return false, "登记失败: " .. tostring(why or entry) end
            if preserveSelection then
                if type(entry)~='table' or entry.path~=path then return false,'本批单位路径未读回' end
                batchEntry=entry
            else
                local okSelect, chosen, selectError = pcall(catalog.select, catalog, path)
                if not okSelect or not chosen then return false, "选择失败: " .. tostring(selectError or chosen) end
                selected = path
            end
        end
        if not preserveSelection then team,count=newTeam,newCount end
        return true,nil,newTeam,newCount,batchEntry
    end

    function instance:select(path, requestedTeam, requestedCount)
        return run(function()
            local ok, why = choose(path, requestedTeam, requestedCount)
            if not ok then return response(false, why) end
            return response(true, "已选择 " .. tostring(selected or "目录默认单位") .. "，队伍=" .. team .. "，数量=" .. count)
        end)
    end
    function instance:cycleTeam()
        return run(function()
            local before=team
            team=({blue='red',red='neutral',neutral='companion',companion='blue'})[team] or 'blue'
            teamRevision=teamRevision+1
            return response(true,'召唤队伍切换 '..before..' -> '..team..'（'..({blue='蓝队',red='红队',neutral='暂不配队',companion='随从'})[team]..'）；读回 revision='..teamRevision..' count='..count..'，未生成或改动场上单位',{spawned_count=0})
        end)
    end

    local function next_slot(whichTeam)
        local used = {}
        for _, unit in ipairs(units) do
            if unit.team == whichTeam and (not relay.enabled or (unit.formationGroup and unit.formationGroup.forming)
                or alive_readback(unit)~=false) then used[unit.slot] = true end
        end
        for slot = 1, #units+1 do if not used[slot] then return slot end end
    end

    -- Plain selection values are safe to snapshot when accepting a shortcut.
    function instance:selection()
        return selected or (catalog and catalog.selectedPath),team,count
    end

    local function memberRow(unit,isStand)
        return {actor=unit.actor,team=unit.team,class_path=unit.class_path,dual=unit.companionSpec~=nil,formation=unit.formation,
            formationGroup=unit.formationGroup,summoner=unit.summoner,stand=isStand,
            reserve=unit.dormant==true or isStand,untargetable=unit.untargetable==true,aid=unit.aid==true}
    end
    function instance:members()
        prune()
        local copy={}
        for _,unit in ipairs(units) do
            copy[#copy+1]=memberRow(unit,stand(unit))
        end
        return copy
    end

    -- A submitted unit identifier binds to one owned actor in this controller's lifetime.
    -- Escorts and skill summons stay attached to the explicit spawning record.
    local function registerRoster(unit, worldKey, parent)
        local ordinals=rosterOrdinals[unit.team]
        if not ordinals then return end
        unit.rosterWorld=worldKey
        unit.rosterKey=actor_key(unit.actor)
        unit.rosterName=actor_name(unit.actor)
        unit.rosterParent=parent
        if parent then return end
        rosterSerial=rosterSerial+1
        unit.rosterId='A'..rosterSerial
        local ordinal=(ordinals[unit.class_path] or 0)+1
        ordinals[unit.class_path]=ordinal
        unit.rosterOrdinal=ordinal
    end

    -- side 'opposing': the summon is there to fight its summoner's side (arena_summon_links.lua, 冷荼's _NPC helpers).
    -- main.lua takes such a helper out as it comes; this is for one that could not be. In a blue/red fight it joins the other team as a helper (unit.aid): its attacks land on the summoner's side, the
    -- game's own summon combat picks its targets, it is not sent at anyone nor sent at, and it does not count among
    -- its team's survivors, so a side whose own units are all down has lost. With a companion summoner it stays
    -- with the summoner as before.
    function instance:adoptSummon(actor,parent,classPath,evidence,side)
        local childKey,parentKey=actor_key(actor),actor_key(parent)
        if not childKey or not parentKey or childKey==parentKey then return {ok=false,message='召唤关系对象无效'} end
        local owner
        for _,unit in ipairs(units) do
            local key=actor_key(unit.actor)
            if key==childKey then return {ok=true,existing=true} end
            if key==parentKey then owner=unit end
        end
        if not owner then return {ok=false,message='召唤者不在本擂台，未接管单位'} end
        local team,aid=owner.team,nil
        if side=='opposing' and (owner.team=='blue' or owner.team=='red') then team=owner.team=='blue' and 'red' or 'blue';aid=true end
        local unit={actor=actor,team=team,class_path=classPath,slot=next_slot(team),summoner=owner.actor,needsJoin=true,aid=aid}
        units[#units+1]=unit
        registerRoster(unit,owner.rosterWorld,owner)
        local synced=notify_units()
        -- The numbers the player set for this side go on what its units summon too.
        if options.summonAdopted then
            local wrote,result=invoke('summonAdopted',actor,classPath,team)
            if not wrote then log('召唤物数值未写入：'..tostring(result))
            elseif type(result)=='table' and result.ok==false then
                log('召唤物数值未确认：'..tostring(result.message)..'；回滚读回='..tostring(result.rollback_verified))
                if result.rollback_verified~=true then
                    state='cleanup_pending'
                    return response(false,'原生召唤物数值未确认，保留登记供清理',{adopted=true,cleanup_required=true,team=team,aid=aid==true})
                end
            end
        end
        log('接管原生召唤物：team='..team..(aid and ('（召唤者在 '..owner.team..' 队；按原版它打召唤者这边，所以站对面，不计存活，目标由游戏自己选）') or '')
            ..' parent='..actor_name(owner.actor)..' child='..actor_name(actor)..'；归属证据='..tostring(evidence)..'；登记读回='..tostring(synced))
        return {ok=synced,adopted=true,team=team,aid=aid==true}
    end

    -- After a round of attacks a unit's AI can leave combat and walk back to where it spawned: 50 against
    -- one boss left the boss untouched for 26 s and later 69 s while the units
    -- stood at their spawn slots. combat_lock.lua keeps them in combat during a fight; as a safety net,
    -- every second a unit found out of combat is sent at its target again. A unit in combat is never forced
    -- (forcing every tick interrupts its attacks).
    local REENGAGE_SECONDS,REENGAGE_LINES,SUMMARY_SECONDS=1,20,10
    local reengage={lines=0,total=0}
    local failedAssignments={lines=0,total=0}
    local phaseWarnings=0
    local function phase_busy(unit)
        if not options.phaseBusy then return false end
        local called,busy=invoke('phaseBusy',unit.actor)
        if not called or type(busy)~='boolean' then
            if phaseWarnings<12 then phaseWarnings=phaseWarnings+1;log('原生阶段状态未确认，暂缓该单位强制索敌：'..actor_name(unit.actor)) end
            busy=true
        end
        if busy then unit.phaseHeld=true end
        return busy
    end
    local function current_time()
        local called,now=invoke('now')
        return called and finite(now) and now or os.clock()
    end
    local function action_busy(unit)
        if not options.actionBusy then return false end
        local ok,value=invoke('actionBusy',unit.actor)
        return not ok or value~=false
    end
    local function keep_opponent(unit,fresh)
        if not options.keepOpponent or not unit then return false end
        local ok,keep=invoke('keepOpponent',unit.actor,fresh)
        return ok and keep==true and fighting(unit)
    end
    local function may_maintain(unit,revision)
        return battleActive and not busy and rosterRevision==revision and fighting(unit)
            and not unit.phaseHeld and not phase_busy(unit) and not action_busy(unit)
    end
    local function resume_intent(unit)
        if not unit.intentWaiting then return true end
        local revision=rosterRevision
        local ok,done=invoke('resumeIntent',unit.actor)
        if not ok or done~=true or not battleActive or busy or revision~=rosterRevision then return false end
        unit.intentWaiting,unit.waitRetryAt,unit.waitingKey=nil,nil,nil
        unit.attackRetryAt,unit.attackFailures=nil,nil
        return true
    end
    local function wait_for_target(unit,target,now,immediate)
        if not options.waitForTarget or not target or not fighting(target)then return false end
        unit.intentWaiting=true
        unit.waitingKey=target.key or actor_key(target.actor)
        if action_busy(unit)then return true end
        if not immediate and unit.waitRetryAt and now<unit.waitRetryAt then return true end
        unit.waitRetryAt=now+1
        invoke('waitForTarget',unit.actor,target.actor)
        return true
    end
    -- A call returning normally is not proof that native target assignment succeeded.
    -- Retain only confirmed targets; retry partial failures without repeatedly interrupting active combat.
    local function assign_target(unit,target,now)
        local revision=rosterRevision
        local started,locked=battleActive,busy
        if not fighting(unit) or not targetable(target) then return false end
        local previous=unit_by_key(unit.assignedKey)
        if previous~=target and keep_opponent(previous,true) then return false end
        if action_busy(unit)then unit.attackPending=true;return false end
        if not resume_intent(unit)then return false end
        if battleActive~=started or busy~=locked or revision~=rosterRevision or not fighting(unit)or not targetable(target)or action_busy(unit)then return false end
        if keep_opponent(target,true) or (previous~=target and keep_opponent(previous,true)) then return false end
        local called,verified=invoke('forceAttack',unit.actor,target.actor)
        if revision~=rosterRevision then return false end
        local confirmed=called and verified==true
        if confirmed then
            unit.assignedTarget,unit.assignedKey=target.actor,target.key or actor_key(target.actor)
            unit.attackPending,unit.attackRetryAt,unit.attackFailures=nil,nil,nil
            unit.rejectedPeers=nil
            unit.protectedPair=nil
            if options.onAssigned then invoke('onAssigned',unit.actor,target.actor) end
        else
            unit.attackPending=true
            unit.rejectedPeers=unit.rejectedPeers or setmetatable({},{__mode='k'})
            unit.rejectedPeers[target]=now
            unit.attackFailures=math.min((unit.attackFailures or 0)+1,4)
            local delay=2^(unit.attackFailures-1)
            unit.attackRetryAt=now+delay
            failedAssignments.total=failedAssignments.total+1
            if failedAssignments.lines<REENGAGE_LINES then
                failedAssignments.lines=failedAssignments.lines+1
                log('目标指派未确认 '..actor_name(unit.actor)..' -> '..actor_name(target.actor)
                    ..'；调用='..tostring(called)..' 读回='..tostring(verified)..'；'..delay..'秒后重试，累计='..failedAssignments.total)
            end
        end
        return confirmed
    end
    -- The opponent fewest units are already sent at, so a crowd spreads over several enemies.
    local function leastAttacked(unit,active,preferred)
        local load={}
        for _,other in ipairs(active) do
            if other.assignedKey and not other.attackPending then load[other.assignedKey]=(load[other.assignedKey] or 0)+1 end
        end
        local refused={}
        while true do
            local best,bestLoad,bestRejected
            for _,other in ipairs(active) do
                if other.team~=unit.team and not other.untargetable and not refused[other] and (not preferred or preferred[other.key]) then
                    local n=load[other.key] or 0
                    local rejected=unit.rejectedPeers and unit.rejectedPeers[other] or -math.huge
                    if not best or rejected<bestRejected or (rejected==bestRejected and n<bestLoad) then
                        best,bestLoad,bestRejected=other,n,rejected
                    end
                end
            end
            if not best or targetable(best) then return best end
            refused[best]=true
        end
    end

    -- The moment a fighting unit's AI drops out of combat (combat_lock.lua sees its CombatToIdle
    -- transition), send it back at its target, before it walks away. Unit by its address key.
    local instant={lines=0,total=0}
    function instance:reengage(key)
        if not battleActive or busy or not key then return false end
        for _,unit in ipairs(units) do
            if unit.key==key and (unit.team=='blue' or unit.team=='red') then
                if phase_busy(unit) or unit.phaseHeld then return false end
                if stand(unit) or dormant(unit) or alive_readback(unit)~=true then return false end
                local target=unit_by_key(unit.assignedKey)
                if keep_opponent(unit,true) then return false end
                if keep_opponent(target,true) then
                    unit.protectedPair=target
                    return wait_for_target(unit,target,current_time(),true)
                end
                if target and fighting(target)and untargetable(target)then return wait_for_target(unit,target,current_time(),true)end
                if not targetable(target)or action_busy(unit)or not resume_intent(unit)then return false end
                if options.maintainTarget then
                    local ok,done=invoke('maintainTarget',unit.actor,target.actor)
                    return ok and done==true
                end
                local called,engaged,after,detail=invoke('engage',unit.actor,unit.assignedTarget)
                instant.total=instant.total+1
                if instant.lines<REENGAGE_LINES then
                    instant.lines=instant.lines+1
                    log('即时重新迎敌 '..actor_name(unit.actor)..' -> '..actor_name(unit.assignedTarget)..'；调用='..tostring(called and engaged)
                        ..' 状态读回='..tostring(after)..' '..tostring(detail or '')..' 累计='..instant.total)
                end
                return called and engaged==true
            end
        end
        return false
    end

    -- The AI's targeting (PBZ_TargetingHandler_AI) reads the blackboard's TargetActor and, when that is empty, its
    -- Last Sensed Actor, which perception sets to the player: skills then went for the player, hidden and out of
    -- everyone's hatred as the player was (左殇's flying swords). When a fighting
    -- unit's fallback is the player it goes to the unit's opponent, or is cleared with no opponent in reach; any other
    -- value is left alone (options.holdTarget).
    local function hold_target(unit,why)
        if not options.holdTarget or stand(unit) or dormant(unit) then return end
        if phase_busy(unit) or unit.phaseHeld then return end
        local target=unit.assignedTarget
        if target and not targetable(unit_by_key(unit.assignedKey)) then target=nil end
        invoke('holdTarget',unit.actor,target,why)
    end
    -- A lock (what its skills aim at) on a unit nobody is sent at goes to its opponent, or is dropped with none in reach
    -- (options.releaseLock, lock_release.lua): a lock taken before her summons came stayed on 冷荼.
    local function release_lock(unit)
        if not options.releaseLock or stand(unit) or dormant(unit) then return end
        if phase_busy(unit) or unit.phaseHeld then return end
        local target=unit.assignedTarget
        if target and not targetable(unit_by_key(unit.assignedKey)) then target=nil end
        invoke('releaseLock',unit.actor,target)
    end
    -- The unit a fighting unit acts against when one of its skills asks for "the player" (player_aim.lua): its
    -- assigned opponent while alive, else the nearest living, shown unit of the other side; nil when none.
    function instance:actorOf(key)
        local unit=key and unit_by_key(key)
        return unit and unit.actor or nil
    end
    function instance:ownsDirectCompanion(actor)
        local key=actor_key(actor);local unit=unit_by_key(key)
        return unit~=nil and unit.team=='companion' and not unit.summoner and removed(unit.actor)==false
            and actor_key(unit.actor)==key and actor_name(unit.actor)==actor_name(actor) and not stand(unit)
    end
    function instance:aggroOpponent(actor)
        if not self:intentContext() then return end
        local u=unit_by_key(actor_key(actor))
        if not u or not u.assignedKey or u.aid or u.needsJoin or (u.team~='blue' and u.team~='red') or not fighting(u) then return end
        local target=unit_by_key(u.assignedKey)
        if target and target.team==(u.team=='blue' and 'red' or 'blue') and not target.aid and not target.needsJoin
            and fighting(target) then return target.actor end
    end
    function instance:canReplaceDefeatedTarget(actor,old,wanted)
        local revision=self:intentContext()
        if not revision then return false end
        local fallen=unit_by_key(actor_key(old))
        if not fallen or (fallen.team~='red' and fallen.team~='blue') or alive_readback(fallen)~=false then return false end
        if options.finalDeath then
            local checked,dead=invoke('finalDeath',old)
            if not checked or dead~=true then return false end
        end
        local unit,target=unit_by_key(actor_key(actor)),unit_by_key(actor_key(wanted))
        return unit and target and not unit.aid and not unit.needsJoin and not target.aid and not target.needsJoin
            and (unit.team=='red' or unit.team=='blue') and (target.team=='red' or target.team=='blue')
            and unit.team~=target.team and unit.assignedKey==target.key and targetable(target) and may_maintain(unit,revision)
    end
    -- Skill code can ask for a target before the next AI update is allowed to
    -- replace the old assignment. Resolve only the protected boss's own wave.
    function instance:phaseOpponent(key,original)
        if not battleActive or not original or not options.phaseBlocksAim or not options.preferredTargets then return end
        local me=unit_by_key(key)
        if not me or me.aid or me.needsJoin or (me.team~='red' and me.team~='blue') then return end
        local checked,blocked=invoke('phaseBlocksAim',me.actor,original)
        if not checked or blocked~=true then return end
        local ok,set=invoke('preferredTargets',me.actor,me.team,actor_key(original))
        if not ok or type(set)~='table' then return end
        local function eligible(candidate)
            return candidate and candidate.team~=me.team and not candidate.aid and not candidate.needsJoin and targetable(candidate)
        end
        local assigned=me.assignedKey and set[me.assignedKey] and unit_by_key(me.assignedKey)
        if eligible(assigned) then return assigned.actor end
        local got,here=invoke('getLocation',me.actor)
        here=got and vector(here) or nil
        local best,bestDistance,bestKey
        for candidateKey in pairs(set)do
            local candidate=unit_by_key(candidateKey)
            if eligible(candidate) then
                local read,there=invoke('getLocation',candidate.actor)
                there=read and vector(there) or nil
                local d=here and there and ((here.X-there.X)^2+(here.Y-there.Y)^2) or math.huge
                if not best or d<bestDistance or (d==bestDistance and candidateKey<bestKey) then
                    best,bestDistance,bestKey=candidate.actor,d,candidateKey
                end
            end
        end
        return best
    end

    function instance:opponentOf(key)
        local me=key and unit_by_key(key)
        if not me or (me.team~='blue' and me.team~='red') then return nil end
        if stand(me) then
            me=unit_by_key(actor_key(me.summoner))
            if not me or stand(me) or alive_readback(me)~=true then return nil end
        end
        if me.assignedTarget then
            local priority=self:phaseOpponent(me.key or key,me.assignedTarget)
            if priority then return priority end
            if fighting(unit_by_key(me.assignedKey)) then return me.assignedTarget end
        end
        local okHere,here=invoke('getLocation',me.actor)
        here=okHere and vector(here) or nil
        local best,bestDistance
        for _,other in ipairs(units)do
            if (other.team=='blue' or other.team=='red') and other.team~=me.team and not other.aid and fighting(other) then
                local okThere,there=invoke('getLocation',other.actor)
                there=okThere and vector(there) or nil
                local d=here and there and ((here.X-there.X)^2+(here.Y-there.Y)^2) or math.huge
                if not best or d<bestDistance then best,bestDistance=other.actor,d end
            end
        end
        return best
    end

    -- After a perception event of a fighting unit (combat_lock.lua), on the next game-thread tick.
    function instance:holdSensed(key)
        if not battleActive or busy or not key then return false end
        local revision=rosterRevision
        for _,unit in ipairs(units)do
            if unit.key==key and (unit.team=='blue' or unit.team=='red') and not unit.aid and may_maintain(unit,revision) then
                if keep_opponent(unit) or keep_opponent(unit_by_key(unit.assignedKey)) then return false end
                hold_target(unit,'感知更新后')
                if not may_maintain(unit,revision) then return false end
                release_lock(unit);return true
            end
        end
        return false
    end

    local function is_story_team_actor(unit)
        if not options.isStoryTeamActor or unit.summoner then return false end
        local called,matched=invoke('isStoryTeamActor',unit.actor)
        return called and matched==true
    end

    local function prepare_story_team_actor(actor)
        local called,ready=invoke('prepareStoryTeamActor',actor)
        return called and ready==true
    end

    -- Keep the original resurrection window. Only a whole, finally defeated summoned party is retired.
    function instance:tickDefeatedFormations()
        if busy or not next(corpseGroups) or state=='cleanup_pending' or state=='restore_pending' then return end
        local got,now=invoke('now')
        if not got or not finite(now) then return end
        if lastCorpseCheck and now>=lastCorpseCheck and now-lastCorpseCheck<1 then return end
        lastCorpseCheck=now
        local candidate
        local revision=rosterRevision
        for group,rows in pairs(corpseGroups) do
            local ready=true
            for _,unit in ipairs(rows) do
                local checked,dead=invoke('finalDeath',unit.actor,true)
                if not checked or dead~=true or not unit.formationName or actor_name(unit.actor)~=unit.formationName then
                    ready=false;break
                end
            end
            if not ready then group.deadSince=nil
            elseif not group.deadSince or now<group.deadSince then
                group.deadSince=now
                log('剑阵全员阵亡读回 '..rows[1].formationName..'；等待 10 秒后复核')
            elseif not candidate and now-group.deadSince>=10 then
                for _,unit in ipairs(rows) do
                    if not unit.retireAt or now>=unit.retireAt then
                        candidate=unit;break
                    end
                end
            end
        end
        if not candidate or rosterRevision~=revision or busy then return end
        candidate.retireAt=now+5
        local called=invoke('destroy',candidate.actor)
        local gone,proof=removed(candidate.actor)
        log('整组阵亡后清理 '..candidate.formationName..' 调用='..tostring(called)..' 读回='..proof)
        if gone==true then prune() end
    end

    function instance:tickReinforcements()
        if not battleActive or busy or state=='cleanup_pending' or state=='restore_pending' or spawn_block() then return end
        prune()
        local revision=rosterRevision
        local active,participants={},{}
        for _,unit in ipairs(units) do
            if (unit.team=='blue' or unit.team=='red') and alive_readback(unit)==true then
                local isStand=stand(unit)
                if (isStand or not dormant(unit)) and summonFactionReady(unit) then
                    local ok,ready=invoke('combatReady',unit.actor)
                    if not isStand and ok and ready==true and unit.needsJoin and is_story_team_actor(unit) then
                        ready=prepare_story_team_actor(unit.actor)
                    end
                    if isStand or (ok and ready==true) then
                        unit.key=unit.key or actor_key(unit.actor);participants[#participants+1]=unit
                        if not isStand and not unit.aid then unit.untargetable=untargetable(unit);active[#active+1]=unit end
                    end
                end
            end
        end
        local okNow,now=invoke('now')
        if not okNow or not finite(now) then now=os.clock() end
        local scan=not reengage.scanAt or now-reengage.scanAt>=REENGAGE_SECONDS
        if scan then reengage.scanAt=now end
        local remaining=32
        local waiting=false
        for _,unit in ipairs(participants) do
            if not battleActive or busy or revision~=rosterRevision then return end
            if unit.needsJoin then
                local verified=true
                unit.joinedPeers=unit.joinedPeers or setmetatable({},{__mode='k'})
                for _,other in ipairs(participants) do
                    if other~=unit then
                        local relation=unit.team==other.team and 0 or 2
                        local receipt=unit.joinedPeers[other]
                        if receipt~=relation then
                            if remaining<=0 then verified=false;break end
                            if type(receipt)=='table' and now<receipt.retry then verified=false
                            else
                                if live(unit.actor)~=true or live(other.actor)~=true then verified=false;break end
                                remaining=remaining-1
                                local ok,readback=invoke('setRelation',unit.actor,other.actor,relation)
                                if not battleActive or busy or revision~=rosterRevision then return end
                                local result=ok and readback==true and relation or {retry=now+1}
                                unit.joinedPeers[other]=result
                                if other.needsJoin then
                                    other.joinedPeers=other.joinedPeers or setmetatable({},{__mode='k'})
                                    other.joinedPeers[unit]=result
                                end
                                if result~=relation then verified=false end
                            end
                        end
                    end
                end
                unit.needsJoin=not verified
                if not verified then waiting=true end
                if verified then
                    unit.joinedPeers=nil
                    log('增援关系读回 team='..unit.team..' actor='..actor_name(unit.actor)..' verified=true')
                end
            end
        end
        -- A reinforcement may act once all of its own relationships have been confirmed.
        if waiting then
            local ready={}
            for _,unit in ipairs(active) do if not unit.needsJoin then ready[#ready+1]=unit end end
            active=ready
        end
        local protectedPeer,available={},{}
        for _,u in ipairs(active) do
            if u.untargetable then protectedPeer[u.team]=protectedPeer[u.team] or u
            else available[u.team]=true end
        end
        for _,unit in ipairs(active) do
          if not battleActive or busy or revision~=rosterRevision then return end
          if fighting(unit) and not phase_busy(unit) then
            local original=unit_by_key(unit.assignedKey)
            if keep_opponent(unit) then
                unit.protectedPair=original
                goto continueCombat
            end
            if keep_opponent(original) then
                unit.protectedPair=original
                wait_for_target(unit,original,now)
                goto continueCombat
            end
            if options.preferredTargets and not (unit.attackRetryAt and now<unit.attackRetryAt) then
                local ok,preferred=invoke('preferredTargets',unit.actor,unit.team,unit.assignedKey)
                if ok and preferred and not (preferred[unit.assignedKey] and targetable(original)) and not action_busy(unit) then
                    local nextTarget=leastAttacked(unit,active,preferred)
                    if nextTarget then
                        assign_target(unit,nextTarget,now)
                        goto continueCombat
                    end
                end
            end
            if unit.phaseHeld then
                unit.phaseHeld=nil;unit.attackPending=true;unit.attackRetryAt=nil;unit.attackFailures=nil;unit.heldTargetKey=nil
            end
            if unit.protectedPair then
                if original and original==unit.protectedPair and targetable(original) then
                    if action_busy(unit) or not resume_intent(unit) then goto continueCombat end
                    if not may_maintain(unit,revision) or not targetable(original) then goto continueCombat end
                    local read,bound=invoke('engagedWith',unit.actor,original.actor)
                    if not may_maintain(unit,revision) or not targetable(original) then goto continueCombat end
                    if read and bound==true then
                        unit.protectedPair,unit.attackPending,unit.attackRetryAt,unit.attackFailures=nil,nil,nil,nil
                    elseif now>=(unit.attackRetryAt or 0) then assign_target(unit,original,now) end
                    goto continueCombat
                end
                unit.protectedPair=nil
            end
            -- The game's fall safety can hold a unit in the air with combat blocked (options.unstick, main.lua).
            if scan and options.unstick and not action_busy(unit)then
                invoke('unstick',unit.actor,unit.assignedTarget,unit.class_path)
                if not battleActive or busy or revision~=rosterRevision then return end
                if not fighting(unit) or phase_busy(unit) then goto continueCombat end
            end
            if scan and options.holdMount and unit.assignedTarget and not action_busy(unit)then
                invoke('holdMount',unit.actor,unit.assignedTarget)
                if not battleActive or busy or revision~=rosterRevision then return end
                if not fighting(unit) or phase_busy(unit) then goto continueCombat end
            end
            -- Issue once for a new unit, after its assigned opponent dies or goes out of reach.
            -- Never force the same live target every tick and interrupt attacks.
            local held=unit_by_key(unit.assignedKey)
            local waited=unit.intentWaiting and unit_by_key(unit.waitingKey)
            local resumed=waited and targetable(waited)
            if unit.intentWaiting and(not waited or not fighting(waited)or resumed)then
                if not resume_intent(unit)then goto continueCombat end
            end
            if held and not (fighting(held) and untargetable(held)) then held=nil end
            if unit.attackPending or not unit.assignedTarget or not targetable(unit_by_key(unit.assignedKey)) then
                -- A failed request cannot be retried before its deadline. Only a protected held
                -- opponent needs an earlier scan to distinguish waiting from switching targets.
                local retryDue=not unit.attackRetryAt or now>=unit.attackRetryAt
                local otherSide=unit.team=='red' and 'blue' or 'red'
                local target=available[otherSide] and (retryDue or held)and leastAttacked(unit,active)or nil
                if target and (not unit.attackRetryAt or now>=unit.attackRetryAt) then
                    if assign_target(unit,target,now) then
                        log('增援/换敌请求 '..actor_name(unit.actor)..' -> '..actor_name(target.actor)..'；读回=true')
                    end
                    if not battleActive or busy or revision~=rosterRevision then return end
                    if not fighting(unit) then goto continueCombat end
                elseif not target and (held or (options.waitForTarget and not available[otherSide] and protectedPeer[otherSide])) then
                    local standby=held or protectedPeer[otherSide]
                    if wait_for_target(unit,standby,now)then
                        -- Logical opponent identity survives protection; no attack is issued against it.
                        if action_busy(unit)then goto continueCombat end
                    elseif held then
                        unit.assignedTarget,unit.assignedKey=nil,nil
                        log('暂不迎敌 '..actor_name(unit.actor)..'：对手 '..actor_name(held.actor)..' 按游戏设定暂时不能被锁定，等新的对手出现')
                    end
                end
            elseif options.maintainTarget and(scan or resumed)then
                invoke('maintainTarget',unit.actor,unit.assignedTarget)
                if not scan and not may_maintain(unit,revision) then goto continueCombat end
            elseif scan and options.inCombat and options.engage and not action_busy(unit)then
                local okState,combat,stateName=invoke('inCombat',unit.actor)
                if okState and combat==false then
                    local called,engaged,after,detail=invoke('engage',unit.actor,unit.assignedTarget)
                    if not battleActive or busy or revision~=rosterRevision then return end
                    if not fighting(unit) then goto continueCombat end
                    reengage.total=reengage.total+1
                    reengage.window=(reengage.window or 0)+1
                    if reengage.lines<REENGAGE_LINES then
                        reengage.lines=reengage.lines+1
                        log('重新迎敌 '..actor_name(unit.actor)..' 状态='..tostring(stateName)..' -> '..actor_name(unit.assignedTarget)
                            ..'；调用='..tostring(called and engaged)..' 状态读回='..tostring(after)..' '..tostring(detail or ''))
                    end
                end
            end
            if not battleActive or busy or revision~=rosterRevision then return end
            local heldKey=targetable(unit_by_key(unit.assignedKey)) and unit.assignedKey or false
            if scan or unit.heldTargetKey~=heldKey then
                if not may_maintain(unit,revision) then goto continueCombat end
                hold_target(unit,'定时检查');unit.heldTargetKey=heldKey
                if not may_maintain(unit,revision) then goto continueCombat end
            end
            if not battleActive or busy or revision~=rosterRevision then return end
            release_lock(unit)
          end
          ::continueCombat::
        end
        if not reengage.since then reengage.since=now end
        if now-reengage.since>=SUMMARY_SECONDS then
            if (reengage.window or 0)>0 then
                log(string.format('重新迎敌汇总：近 %.0f 秒 %d 次，累计 %d 次，参战 %d 个',now-reengage.since,reengage.window,reengage.total,#active))
            end
            reengage.since,reengage.window=now,0
        end
    end

    local function spawn_transform(origin, forward, whichTeam, slot)
        local length = math.sqrt(forward.X * forward.X + forward.Y * forward.Y)
        if length < 0.0001 then return nil end
        local x, y = forward.X / length, forward.Y / length
        -- Rows of five (companions: four) 3 m apart, so a batch of 50 stays within about 33 m ahead.
        local distance, lateral
        local row, col = math.floor((slot - 1) / 5), (slot - 1) % 5
        if whichTeam == "neutral" then
            distance, lateral = 600 + row * 300, ({ 0, -300, 300, -600, 600 })[col + 1]
        elseif whichTeam == "companion" then
            row, col = math.floor((slot - 1) / 4), (slot - 1) % 4
            distance, lateral = 150 - row * 250, ({ -300, 300, -600, 600 })[col + 1]
        else
            distance = 600 + row * 300
            lateral = (360 + col * 300) * (whichTeam == "blue" and -1 or 1)
        end
        -- Blue (left of the player) and red (right) face each other, a no-team unit faces the player and a companion
        -- looks where the player does. Up to v0.38.3 every unit came out at world yaw 0: depending on where the
        -- player looked, one side could stand with its back to the other and only fight back after taking hits
        -- (one side's first hit came 4-9 s after the start, the other's up to 20 s).
        local dx, dy = x, y
        if whichTeam == "blue" then dx, dy = -y, x
        elseif whichTeam == "red" then dx, dy = y, -x
        elseif whichTeam == "neutral" then dx, dy = -x, -y end
        local half = math.atan(dy, dx) / 2
        return { Rotation = { X = 0, Y = 0, Z = math.sin(half), W = math.cos(half) }, Scale3D = { X = 1, Y = 1, Z = 1 },
            Translation = { X = origin.X + x * distance - y * lateral,
                Y = origin.Y + y * distance + x * lateral, Z = origin.Z + 50 } }
    end

    -- Keep uncertain staged objects owned until both they and their positively linked helpers are gone.
    local retiring,syncPending={},false
    local function remember(actor,world)
        local key=actor_key(actor)
        if key and not retiring[key] then retiring[key]={actor=actor,name=actor_name(actor),world=world} end
        return key
    end
    -- Take one ownership snapshot per group on the game thread, before destroying any of its actors.
    -- Missing evidence stays pending. A snapshot is never reused on another cleanup pass.
    local function childGroups(actors,world)
        if #actors<2 or not options.companionChildGroups then return nil end
        local ok,groups=invoke('companionChildGroups',actors,world)
        if not ok or type(groups)~='table' then return {} end
        local result={}
        for _,owner in ipairs(actors)do
            local key=actor_key(owner);local group=groups[key]
            if key and type(group)=='table' then
                local children={}
                for _,child in ipairs(group)do
                    local id,name=actor_key(child),actor_name(child)
                    if id and type(name)=='string' and not name:lower():match('^unknown%(') then
                        children[#children+1]={actor=child,key=id,name=name}
                    elseif removed(child)~=true then children=nil;break end
                end
                result[key]=children
            end
        end
        return result
    end
    local function retryRetirement(item)
        item.delay=math.min(8,(item.delay or .5)*2)
        item.retryAt=current_time()+item.delay
        invoke('quarantineCompanion',item.actor)
        return false
    end
    local function retire(actor,world,withChildren,groups)
        local gone=removed(actor)
        if gone==true then return true end
        local key=remember(actor,world)
        if not key then return false end
        local item=retiring[key]
        if item.name~=actor_name(actor) or actor_key(item.world)~=actor_key(world) then return false end
        item.children=item.children or withChildren
        if gone~=false then return false end
        if options.inCompanionWorld then
            local checked,same=invoke('inCompanionWorld',actor,world)
            if not checked or same~=true then item.retryAt=current_time()+2;return false end
        end
        if item.children then
            if groups then
                local children=groups[key]
                if not children then return retryRetirement(item) end
                for _,child in ipairs(children)do
                    if actor_key(child.actor)==child.key and actor_name(child.actor)==child.name then retire(child.actor,world,false) end
                end
            else
                local read,children=invoke('companionChildren',actor,world)
                if not read or type(children)~='table' then return retryRetirement(item) end
                for _,child in ipairs(children)do retire(child,world,false) end
            end
            item.children=nil
        end
        invoke('destroy',actor)
        if removed(actor)==true then retiring[key]=nil;return true end
        return retryRetirement(item)
    end
    local function cleanupStep(action,...)
        if busy then return false end
        busy=true
        local ok,clean=pcall(action,...)
        busy=false
        if not ok then log('随从回收未确认：'..tostring(clean)) end
        return ok and clean==true
    end
    local function recoverRetired()
        if syncPending then syncPending=not notify_units() end
        if not next(retiring) then return not syncPending end
        local got,world=invoke('getWorld')
        if not got or live(world)~=true then return false end
        local now=current_time();local due,owners={},{}
        for key,item in pairs(retiring)do
            local gone=removed(item.actor)
            if actor_key(item.world)~=actor_key(world) or gone==true or gone==false and actor_name(item.actor)~=item.name then
                retiring[key]=nil
            elseif gone==false and (not item.retryAt or now>=item.retryAt) then
                due[#due+1]=item
                if item.children then owners[#owners+1]=item.actor end
            end
        end
        local groups=childGroups(owners,world)
        for _,item in ipairs(due)do retire(item.actor,item.world,false,groups) end
        return next(retiring)==nil and not syncPending
    end
    function instance:recoverCompanionCleanup()
        if not syncPending and not next(retiring) then return not busy end
        return cleanupStep(recoverRetired)
    end

    function instance:spawn(path, requestedTeam, requestedCount, preserveSelection, dual)
        return run(function()
            prune()
            local block=spawn_block()
            if block then return response(false,block,{uncertain=true,spawned_count='unknown'}) end
            if state=="cleanup_pending" or state=="restore_pending" then
                return response(false,"上次清理或恢复未完成，已阻止继续生成；请先完成清理",{spawned_count=0})
            end
            -- A custom fighter has a batch of its own. Keep the ordinary arena
            -- selection visible to callbacks, including throughout a failed spawn.
            local okChoose,whyChoose,team,count,batchEntry=choose(path,requestedTeam,requestedCount,preserveSelection)
            if not okChoose then return response(false, whyChoose, { spawned_count = 0 }) end
            -- 必须先有可控制玩家与当前World；启动/读档期间不能先加载类再发现玩家无效。
            local okPlayer, player = invoke("getPlayer")
            if not okPlayer or live(player) ~= true then return response(false, "玩家无效，未加载资产", { spawned_count = 0 }) end
            local okWorld, world = invoke("getWorld", player)
            if not okWorld or live(world) ~= true then return response(false, "World无效，未加载资产", { spawned_count = 0 }) end
            prune()
            if maxUnits>0 and #units + count > maxUnits then
                return response(false, "擂台总数上限"..maxUnits.."；当前=" .. #units .. "，请求=" .. count, { spawned_count = 0 })
            end
            if type(catalog)~='table' or (batchEntry and type(catalog.resolvePath)~='function') or
                (not batchEntry and (type(catalog.selected)~='function' or type(catalog.resolveSelected)~='function')) then
                return response(false, "目录接口不可用", { spawned_count = 0 })
            end
            log("召唤阶段=直接读取所选路径；跳过全量类扫描")
            local okEntry,entry=true,batchEntry
            if not batchEntry then okEntry,entry=pcall(catalog.selected,catalog) end
            if not okEntry or type(entry)~="table" or type(entry.path)~="string" then
                return response(false,"没有可用的明确单位路径",{spawned_count=0})
            end
            local policyOk,allowed,policyReason=invoke("canSpawn",entry.path)
            if not policyOk or allowed~=true then
                return response(false,tostring(policyReason or "未取得该单位的生成验证许可"),{spawned_count=0})
            end
            if options.spawnLimits then
                local limitsOk,limits=invoke('spawnLimits',entry.path)
                if not limitsOk then return response(false,'单位测试限制不可读',{spawned_count=0}) end
                if limits then
                    local existing=0
                    for _,unit in ipairs(units) do if unit.class_path==entry.path then existing=existing+1 end end
                    if count>limits.max_count or existing+count>limits.max_live then
                        return response(false,'该单位当前仅允许每次1只、场上最多2只的有限测试',{spawned_count=0})
                    end
                end
            end
            log('召唤阶段=解析本批单位 '..entry.path)
            local okClass,cls,classError,resolved
            if batchEntry then okClass,cls,classError,resolved=pcall(catalog.resolvePath,catalog,entry.path)
            else okClass,cls,classError=pcall(catalog.resolveSelected,catalog) end
            if not okClass or live(cls) ~= true then
                return response(false, "类解析未通过: " .. tostring(classError or cls), { spawned_count = 0 })
            end
            if batchEntry then
                if type(resolved)~='table' or resolved.path~=entry.path then return response(false,'本批单位类与目录不一致',{spawned_count=0}) end
                batchEntry=resolved
            elseif not preserveSelection then
                local okEntry, entry = pcall(catalog.selected, catalog)
                if okEntry and type(entry) == "table" and type(entry.path) == "string" then selected = entry.path end
            end
            if live(player)~=true or live(world)~=true then return response(false,"加载后玩家或World失效",{spawned_count=0}) end
            if live(player) ~= true then return response(false, "玩家已失效", { spawned_count = 0 }) end
            local okLoc, location = invoke("getLocation", player)
            if live(player) ~= true then return response(false, "玩家已失效", { spawned_count = 0 }) end
            local okForward, forward = invoke("getForward", player)
            location, forward = okLoc and vector(location) or nil, okForward and vector(forward) or nil
            if not location or not forward then return response(false, "位置或朝向读回无效", { spawned_count = 0 }) end
            -- In the free camera the batch goes where the view points (spawn_spot.lua).
            local relaySide=relay.enabled and (team=='blue' or team=='red')
            if relaySide and relay.anchor then
                location,forward=vector(relay.anchor.location),vector(relay.anchor.forward)
            elseif options.spawnOrigin then
                local okOrigin,at,look=invoke('spawnOrigin',location,forward,team,world)
                at,look=okOrigin and vector(at) or nil,okOrigin and vector(look) or nil
                if at and look then location,forward=at,look end
            end
            local spawned, activated, failures = 0, 0, 0
            local formation
            if options.formationEnabled then local ok,value=invoke("formationEnabled",entry.path);if ok then formation=value end end
            local escorted, escortsWanted = 0, 0
            local spawnWarning
            local refusal   -- why a unit was not started (spawnClass outcome not_started), said in the reply
            local cleanupRequired=false
            local staged
            local function finish_one(actor,transform,parent)
                if not options.finishSpawn then return true end
                local called,done,why=invoke('finishSpawn',actor,transform,world,parent)
                if called and done==true then return true end
                failures=failures+1;cleanupRequired=true
                log('FinishSpawn未确认；保留对象供F4清理: '..tostring(why or done))
                return false
            end
            local function activate_one(actor,unitPath,escort,spec)
                local ok,active,detail,warning
                if removed(actor)==false then ok,active,detail,warning=invoke('activate',actor,unitPath,team,escort,spec)
                else detail='生成后对象已失效、进入销毁或状态不可读' end
                if ok and active==true then activated=activated+1 else failures=failures+1;cleanupRequired=true end
                if type(warning)=='string' and warning~='' then spawnWarning=warning end
                log('召唤读回 actor='..actor_name(actor)..' HP='..health(actor)..' activate='..tostring(ok and active)
                    ..' detail='..tostring(ok and (detail or 'unknown') or detail or active))
            end
            local function formation_step(name,group)
                local called,ok,why=invoke(name,group,staged,world,team)
                if called and ok==true then
                    if type(why)=='string' and why~='' then spawnWarning=why end
                    return true
                end
                failures=failures+1;cleanupRequired=true
                refusal='原班配合未确认：'..tostring(why or ok)
                log(refusal);return false
            end
            local function rollback_group(group)
                if unknownSpawn or not options.abortFormation then return end
                local called,detached=invoke('abortFormation',group)
                if not called or detached~=true then return end
                local complete=true
                for _,row in ipairs(staged)do
                    if removed(row.actor)==false then invoke('destroy',row.actor)end
                    if removed(row.actor)==true then
                        if row.parent then escorted=escorted-1 else spawned=spawned-1 end
                        if row.activated then activated=activated-1 end
                    else complete=false end
                end
                prune()
                cleanupRequired=not complete
                log('本次未完成的剑阵已回收读回='..tostring(complete))
            end
            -- One unit: spawn, take ownership, finish and activate it. Returns the actor once it is owned and
            -- whether the batch has to stop. escort = {parent=, parent_path=, entry=} for a unit that comes with another.
            local function spawn_one(unitCls,unitPath,slot,transform,escort,group)
                local guarded,guardError=guard_call('begin')
                if not guarded then failures=failures+1; log(tostring(guardError)); return nil,true end
                local okSpawn, actor, spawnError, outcome = invoke("spawnClass", unitCls, transform, world, escort and escort.entry or batchEntry,team)
                local duplicate = false
                for _, unit in ipairs(units) do if unit.actor == actor then duplicate = true; break end end
                if okSpawn and live(actor) == true and not duplicate then
                    -- 先接管所有权并通知root，再调用可能失败的登场操作。
                    local spec=dual==true and team=='companion' and not escort and require('companion_profile').phase(unitPath) and {} or nil
                    local parent=escort and unit_by_key(actor_key(escort.parent))
                    local unit={actor=actor,team=team,slot=slot,class_path=unitPath,needsJoin=battleActive,companionSpec=spec,
                        formationGroup=group,reportEscort=escort~=nil}
                    units[#units+1]=unit
                    if not escort or parent then registerRoster(unit,actor_key(world),parent) end
                    if group and group.retire then
                        local got,name=invoke('name',actor)
                        if got and type(name)=='string' and name~='' then units[#units].formationName=name end
                        group.deadSince=nil
                    end
                    if not escort then units[#units].formation=formation end
                    if escort then escorted=escorted+1 else spawned = spawned + 1 end
                    if group and group.nativeFormation then
                        staged[#staged+1]={actor=actor,path=unitPath,transform=transform,parent=escort and escort.parent}
                    end
                    if spawnError~=nil then failures=failures+1; log("生成返回警告: "..tostring(spawnError)) end
                    if not notify_units() then failures = failures + 1; cleanupRequired=true; return actor,true end
                    local ownedConfirmed,ownedError=guard_call('complete')
                    if not ownedConfirmed then
                        unknownSpawn=true; failures=failures+1; log(tostring(ownedError)); return actor,true
                    end
                    if group and group.nativeFormation then
                        return actor,false
                    end
                    local finished=finish_one(actor,transform,escort and escort.parent)
                    if finished then activate_one(actor,unitPath,escort~=nil,spec) end
                    if cleanupRequired and team=='companion' and options.companionChildren and require('companion_profile').phase(unitPath) then
                        if retire(actor,world,unitPath==require('companion_profile').second) then
                            spawned=spawned-1;prune();cleanupRequired=false
                        end
                        refusal='沐小葵登场未验证，已请求回收'
                        return nil,true
                    end
                    return actor,cleanupRequired
                end
                failures = failures + 1
                log("生成未确认新有效实例: " .. (duplicate and "返回了已登记对象" or tostring(spawnError or actor)))
                if okSpawn and outcome=='not_started' then
                    if type(spawnError)=='string' and not refusal then refusal=spawnError end
                    local cleared=guard_call('complete')
                    if not cleared then unknownSpawn=true; return nil,true end
                    return nil,false
                end
                -- A Lua conversion error or nil return does not prove that the
                -- C++ call created nothing. Stop the batch; never retry/fallback.
                unknownSpawn=true; return nil,true
            end
            -- Units the game places with this one (options.escortsFor, escorts.lua: a 驯犬客's two 狂犬), same team.
            local function spawn_escorts(parent,group)
                local okList,list=invoke('escortsFor',entry.path,formation)
                if not okList or type(list)~='table' then return false end
                for _,spec in ipairs(list) do
                    escortsWanted=escortsWanted+spec.count
                    if maxUnits>0 and #units+spec.count+(count-spawned)>maxUnits then
                        failures=failures+1;log("随行名额不足，未生成这一组队员");return false
                    end
                    local okResolve,escortCls,why,escortEntry=invoke('resolveEscort',spec.path)
                    if not okResolve or live(escortCls)~=true or type(escortEntry)~='table' then
                        failures=failures+1
                        log('随行单位类解析未通过，未生成: '..tostring(spec.path)..'；'..tostring(okResolve and why or escortCls))
                    else
                        for index=1,spec.count do
                            if live(parent)~=true or live(world)~=true then failures=failures+1; log('随行中止：带队单位或World已失效'); return false end
                            local slot=next_slot(team)
                            local transform=slot and spawn_transform(location,forward,team,slot)
                            if not transform then failures=failures+1; log('随行中止：站位无效'); return false end
                            log(string.format('召唤阶段=随行 %d/%d unit=%s 跟随=%s team=%s slot=%d position=%.1f,%.1f,%.1f',index,spec.count,
                                spec.path,actor_name(parent),team,slot,transform.Translation.X,transform.Translation.Y,transform.Translation.Z))
                            local _,stop=spawn_one(escortCls,spec.path,slot,transform,{parent=parent,parent_path=entry.path,entry=escortEntry},spec.formation and group or nil)
                            if stop then return true end
                        end
                    end
                end
                return false
            end
            for index = 1, count do
                if live(player) ~= true or live(world) ~= true or live(cls) ~= true then
                    failures = failures + 1; log("召唤中止：玩家/World/Class已失效"); break
                end
                local slot = next_slot(team)
                local transform = slot and spawn_transform(location, forward, team, slot)
                if not transform then failures = failures + 1; log("召唤中止：朝向或站位无效"); break end
                log(string.format("召唤阶段=生成 %d/%d team=%s slot=%d position=%.1f,%.1f,%.1f",
                    index, count, team, slot, transform.Translation.X, transform.Translation.Y, transform.Translation.Z))
                local group=formation and {} or nil
                if group and options.retireFormation then group.retire=options.retireFormation(entry.path)==true end
                staged=nil
                local nativeTeam=team=='blue' or team=='red' or (team=='companion' and options.companionFormation
                    and options.companionFormation(entry.path)==true)
                if group and group.retire and options.prepareFormation and nativeTeam then
                    group.nativeFormation=true;group.forming=true;staged={}
                end
                local actor,stop=spawn_one(cls,entry.path,slot,transform,nil,group)
                if stop then
                    if staged then rollback_group(group) end
                    break
                end
                if actor and options.escortsFor and spawn_escorts(actor,group) then
                    if staged then cleanupRequired=true;rollback_group(group) end
                    break
                end
                if actor and staged then
                    if not formation_step('prepareFormation',group) then rollback_group(group);break end
                    for _,row in ipairs(staged) do if not finish_one(row.actor,row.transform,row.parent) then break end end
                    if cleanupRequired or not formation_step('formationReady',group) then rollback_group(group);break end
                    group.forming=nil
                    for _,row in ipairs(staged) do
                        activate_one(row.actor,row.path,row.parent~=nil)
                        if cleanupRequired then break end
                        row.activated=true
                    end
                    if cleanupRequired or (options.formationActivated and not formation_step('formationActivated',group)) then
                        rollback_group(group);break
                    end
                end
            end
            if relaySide and spawned>0 and not relay.anchor then
                relay.anchor={location=vector(location),forward=vector(forward)}
                log('接力落点已固定；后续批次复用位置和朝向，停止/换图后重置')
            end
            state = unknownSpawn and 'spawn_uncertain' or (cleanupRequired and 'cleanup_pending'
                or (spawned > 0 and "units_ready" or "spawn_failed"))
            if unknownSpawn then
                return response(false,'生成调用结果未知，已立即停止；已登记'..spawned..'只，未重试。请重新启动游戏，避免遗留未知对象',
                    {uncertain=true,spawned_count='unknown',confirmed_spawned_count=spawned,remaining_count=#units})
            end
            return response(spawned == count and failures == 0,
                string.format("生成读回 %d/%d；激活确认=%d；失败/未验证=%d；已生成者保留，开战需蓝红双方", spawned, count, activated, failures)
                    ..(escortsWanted>0 and string.format('；随行单位 %d/%d',escorted,escortsWanted) or '')..(spawnWarning and ('；提示：'..spawnWarning) or '')
                    ..(refusal and ('；没召唤：'..refusal) or ''),
                { spawned_count = spawned, escort_count = escorted, activated_count = activated, failure_count = failures, remaining_count = #units })
        end)
    end

    function instance:companionRollbackReady(actor)
        if busy or syncPending or next(retiring) or spawn_block() then return false end
        local unit=unit_by_key(actor_key(actor))
        return unit and unit.team=='companion' and unit.companionSpec~=nil and removed(actor)==false
    end
    local function clearCompanionHelpers(actor)
        local unit=unit_by_key(actor_key(actor))
        if not unit or unit.team~='companion' or unit.class_path~=require('companion_profile').second then return false end
        local got,world=invoke('getWorld');local read,children=invoke('companionChildren',actor,world)
        if not got or live(world)~=true or not read or type(children)~='table' then return false end
        local clean=true;for _,child in ipairs(children)do if not retire(child,world) then clean=false end end
        return clean
    end
    function instance:clearCompanionHelpers(actor)return cleanupStep(clearCompanionHelpers,actor)end
    function instance:replaceCompanion(record,wanted,why,initial)
        return run(function()
            local fail=function(message,uncertain)return {ok=false,message=message,uncertain=uncertain}end
            local P=require('companion_profile')
            local path=wanted==2 and P.second or P.first
            local unit=unit_by_key(actor_key(record.actor))
            if syncPending or not unit or unit.team~='companion' or not unit.companionSpec or not P.phase(unit.class_path)
                or unit.class_path==path or removed(unit.actor)~=false or next(retiring)
                or spawn_block() or state=='cleanup_pending' or state=='restore_pending' then return fail('当前单位或生成保护尚未就绪') end
            local old=unit.actor
            local okW,world=invoke('getWorld')
            local allowed,yes,reason=invoke('canSpawn',path)
            if not okW or live(world)~=true or not allowed or not yes then return fail(reason or '地图或目标类不可用') end
            local okReg,registered=pcall(catalog.registerPath,catalog,path)
            if not okReg or not registered then return fail('目标形态登记失败') end
            local resolved,cls,err,entry=pcall(catalog.resolvePath,catalog,path)
            if not resolved or live(cls)~=true or not entry or entry.path~=path then return fail(err or '目标形态未解析') end
            local got,transfer,detail=invoke('companionTransfer',record,world,why,initial)
            if not got or not transfer then return fail(detail or '切换前状态未确认') end
            local guarded,guardError=guard_call('begin');if not guarded then return fail(guardError) end
            local spawned,new,errorText,outcome=invoke('spawnClass',cls,transfer.transform,world,entry,'companion')
            if not spawned or live(new)~=true or unit_by_key(actor_key(new)) then
                if spawned and outcome=='not_started' and guard_call('complete') then return fail(errorText) end
                unknownSpawn=true;return fail('生成结果未知，已停止切换',true)
            end
            local newKey=remember(new,world)
            local function abort(message)
                local gone=retire(new,world,transfer.finished and wanted==2)
                return fail(message,not gone or next(retiring)~=nil)
            end
            if not newKey or not guard_call('complete') then unknownSpawn=true;return abort('暂存所有权未确认') end
            transfer.finished=true
            local finished,ok,detail=invoke('finishSpawn',new,transfer.transform,world,nil,true)
            if not finished or ok~=true then return abort(detail or '新形态初始化失败') end
            local activated,ready,note=invoke('activate',new,path,'companion',false,unit.companionSpec)
            if not activated or ready~=true then return abort(note or '新形态身份或属性未确认') end
            local wrote,verified,problem=invoke('companionRestore',record,new,transfer,why,world)
            if not wrote or verified~=true then return abort(problem or '生命、目标或场景变化，保留原形态') end
            local read,children=invoke('companionChildren',old,world)
            if not read or type(children)~='table' then return abort('原形态配合单位未确认') end
            if options.companionCommitReady then
                local readCurrent,current=invoke('companionCommitReady',record,new,transfer,world)
                if not readCurrent or current~=true then return abort('提交前战斗或资源发生变化，保留原形态') end
            end
            -- Record the replacement identity before committing, while both actors are still owned.
            local named,newName=invoke('name',new)
            if not named or type(newName)~='string' or newName=='' or newName:lower():match('^unknown%(') then return abort('新形态身份读回失败') end
            -- A failed destroy leaves the original in charge. An unreadable result blocks further swaps.
            invoke('destroy',old)
            local gone=removed(old)
            if gone~=true then
                local result=abort('原形态回收未确认');result.uncertain=result.uncertain or gone==nil;return result
            end
            for _,child in ipairs(children)do retire(child,world) end
            if removed(new)~=false or actor_key(new)~=newKey then return abort('原形态已回收，新形态失效，请检查场上状态') end
            unit.actor,unit.key,unit.class_path=new,newKey,path;retiring[newKey]=nil
            syncPending=not notify_units()
            return {ok=true,actor=new,key=newKey,name=newName}
        end)
    end

    function instance:start()
        return run(function()
            prune()
            local block=spawn_block()
            if block then return response(false,block,{uncertain=true}) end
            if state=="cleanup_pending" or state=="restore_pending" then
                return response(false,"清理或恢复尚未完成，未下达交战指令")
            end
            local blue, red = {}, {}
            local opening=options.onMatchSnapshot and (not battleActive or fight.ended) and {} or nil
            local reachable={blue={},red={}}
            local relations={blue={},red={}}
            local storyActors={}
            local deferred=0
            for _, unit in ipairs(units) do
              if unit.team=='blue' or unit.team=='red' then
                local alive=alive_readback(unit)
                local isStand=stand(unit)
                local reserve=not isStand and dormant(unit)
                if alive==nil and not unit.summoner then return response(false,'参赛者存活状态未读回，未下达交战指令') end
                local factionReady=alive==false or reserve or summonFactionReady(unit)
                if alive~=false and not isStand and not unit.aid and not reserve then
                    if options.canBattle then
                        local allowed,battleAllowed,reason=invoke('canBattle',unit.class_path)
                        if not allowed or battleAllowed~=true then
                            return response(false,tostring(reason or '该单位未开放交战'))
                        end
                    end
                    local okHP,hp=invoke("hp",unit.actor)
                    local okCombat,combat=invoke("combatReady",unit.actor)
                    if alive~=true or not okHP or not finite(hp) or hp<=0 or not okCombat or combat~=true or not factionReady then
                        if unit.summoner then
                            unit.needsJoin=true;deferred=deferred+1
                            goto nextStartUnit
                        end
                        return response(false,"参赛者没有已确认的正血量或战斗AI；未修改关系、未发起攻击")
                    end
                    if unit.team == "blue" then blue[#blue + 1] = unit.actor end
                    if unit.team == "red" then red[#red + 1] = unit.actor end
                    if opening then
                        opening[#opening+1]={actor=unit.actor,team=unit.team,class_path=unit.class_path,
                            slot=unit.slot,formation=unit.formation,escort=unit.reportEscort==true,summoned=unit.summoner~=nil}
                    end
                    unit.untargetable=untargetable(unit)
                    if not unit.untargetable then local list=reachable[unit.team];list[#list+1]=unit.actor end
                    if is_story_team_actor(unit) then storyActors[unit.actor]=true end
                end
                if alive==true and not reserve and factionReady then
                    local list=relations[unit.team];list[#list+1]=unit.actor
                end
              end
              ::nextStartUnit::
            end
            if deferred>0 then log('召唤物等待生命、阵营或战斗AI就绪 '..deferred..' 只；就绪后按增援入场') end
            if #blue == 0 or #red == 0 then return response(false, "开战至少需要蓝队和红队各一名有效参赛者") end
            local okPlayer, player = invoke("getPlayer")
            if not okPlayer or live(player) ~= true then return response(false, "玩家无效，未修改战斗关系") end
            if options.prepareBattle then
                local prepared,readback=invoke('prepareBattle',instance:members())
                if not prepared or readback~=true then return response(false,'交战前配置未确认；未发起攻击') end
            end
            for actor in pairs(storyActors) do
                if not prepare_story_team_actor(actor) then
                    return response(false,'剧情援军的阵营或仇恨资格未确认，未下达交战指令')
                end
            end
            if next(storyActors) then
                -- Other units keep their existing pair relations. These former story allies
                -- need an explicit Friendly relation with every current teammate.
                for _, side in ipairs({relations.blue, relations.red}) do
                    for i, a in ipairs(side) do
                        for j=i+1,#side do
                            local b=side[j]
                            if storyActors[a] or storyActors[b] then
                                local called, friendly=invoke('setRelation',a,b,0)
                                if not called or friendly~=true then
                                    return response(false,'剧情援军的同队关系未确认，未下达交战指令')
                                end
                            end
                        end
                    end
                end
            end
            local failures, requests = 0, 0
            -- Player neutrality belongs exclusively to the F8 spectator switch.
            -- Starting a duel must not silently grant a separate no-aggro mode.
            for _, a in ipairs(relations.blue) do
                for _, b in ipairs(relations.red) do
                    if live(a) == true and live(b) == true then
                        local ok, readback = invoke("setRelation", a, b, 2)
                        if not ok or readback ~= true then failures = failures + 1 end
                    end
                end
            end
            local function request_attack(attackers, opponents)
                if #opponents==0 then
                    log('开战请求暂缓：这 '..#attackers..' 名参赛者的对手按游戏设定暂时都不能被锁定，等新的对手出现')
                    return
                end
                local now=current_time()
                for i, attacker in ipairs(attackers) do
                    local opponent = opponents[(i - 1) % #opponents + 1]
                    if live(attacker) == true and live(opponent) == true then
                        local attackerKey=actor_key(attacker)
                        local verified,phaseHeld=false,false
                        for _,unit in ipairs(units) do
                            if attackerKey and actor_key(unit.actor)==attackerKey then
                              if phase_busy(unit) then
                                phaseHeld=true
                                verified=true -- the native phase owns this actor's current action
                              else
                                unit.phaseHeld=nil
                                local target=unit_by_key(actor_key(opponent))
                                if target then verified=assign_target(unit,target,now) end
                                if verified then unit.needsJoin=false end
                                requests=requests+1
                              end
                                break
                            end
                        end
                        if not verified then failures = failures + 1 end
                        if phaseHeld then
                            log('暂缓普通攻击 '..actor_name(attacker)..'；保留该单位原生阶段或待确认状态，其他参赛者继续')
                        else log("开战请求 " .. actor_name(attacker) .. " -> " .. actor_name(opponent)
                            .. "；读回=" .. tostring(verified) .. "；HP=" .. health(attacker) .. "/" .. health(opponent)
                            .. "；朝向与对手方向夹角=" .. facing_gap(attacker, opponent)) end
                    else failures = failures + 1 end
                end
            end
            if opening then
                local ok,err=pcall(options.onMatchSnapshot,opening,{enabled=relay.enabled,blue=relay.blue,red=relay.red})
                reportOpen=ok
                if not ok then log('对局开战记录失败: '..tostring(err)) end
            end
            request_attack(blue, reachable.red); request_attack(red, reachable.blue)
            if options.onBattleStarted and live(blue[1]) == true and live(red[1]) == true then
                local ok, err = pcall(options.onBattleStarted, blue[1], red[1])
                if not ok then failures = failures + 1; log("开战观察回调失败: " .. tostring(err)) end
            end
            state = "battle_requested"
            battleActive=true
            return response(failures == 0, string.format("已请求%d名参赛者攻击；失败/未验证=%d；实际伤害仍待读回", requests, failures),
                { battle_active = battleActive, attack_requests = requests, failure_count = failures })
        end)
    end

    function instance:stop()
        return run(function()
            finishReport({reason='stopped',seconds=fight.started and fight.now and math.max(0,fight.now-fight.started) or nil})
            battleActive=false
            fight={}
            log("停止阶段=恢复会话；随后仅销毁本控制器登记的参赛者")
            local okRestore, restored = invoke("restore")
            lastRestoreConfirmed=okRestore and restored==true
            local kept, destroyed, companions = {}, 0, {}
            for _, unit in ipairs(units) do
                local before = live(unit.actor)
                if unit.team == "companion" then companions[#companions + 1] = unit
                elseif before == true then
                    local okDestroy, detail = invoke("destroy", unit.actor)
                    local after = live(unit.actor)
                    local gone,proof=removed(unit.actor)
                    log("清理 actor=" .. (after == true and actor_name(unit.actor) or "invalid_or_unreadable")
                        .. " 调用=" .. tostring(okDestroy) .. " 有效性读回=" .. tostring(after) .. " 销毁读回="..proof.." detail=" .. tostring(detail))
                    if gone == true then destroyed = destroyed + 1 else kept[#kept + 1] = unit end
                elseif before == false then destroyed = destroyed + 1
                else kept[#kept + 1] = unit end
            end
            local pending = #kept
            for _, unit in ipairs(companions) do kept[#kept + 1] = unit end
            units = kept
            local synced = notify_units()
            local block=spawn_block()
            state = block and 'spawn_uncertain' or (pending > 0 and "cleanup_pending" or (okRestore and restored == true and synced and "idle" or "restore_pending"))
            return response(not block and pending == 0 and okRestore and restored == true and synced,
                string.format("清理读回：已失效/进入销毁=%d，待确认=%d；恢复确认=%s；随从保留=%d", destroyed, pending, tostring(okRestore and restored == true), #companions)..(block and ('；'..block) or ''),
                { destroyed_count = destroyed, remaining_count = pending, restored = okRestore and restored == true })
        end)
    end

    -- Removes only this team's records; Blue and Red, a running fight and the other teams stay.
    local function clear_team(which,label)
        return run(function()
            local kept,pending,destroyed={},0,0
            local world,groups,queen
            if which=='companion' and options.companionChildren then
                queen=require('companion_profile').second
                local owners={}
                for _,unit in ipairs(units)do
                    if unit.team==which and unit.class_path==queen and removed(unit.actor)==false then owners[#owners+1]=unit.actor end
                end
                if #owners>0 then
                    local ok,current=invoke('getWorld')
                    if ok and live(current)==true then world=current;groups=childGroups(owners,world) end
                end
            end
            log('清理'..label..'：仅处理本Mod的'..which..'记录，不停止蓝红交战')
            for _,unit in ipairs(units) do
                if unit.team~=which then kept[#kept+1]=unit
                else
                    if removed(unit.actor)==false then
                        if queen and unit.class_path==queen then
                            if world then retire(unit.actor,world,true,groups) end
                        else invoke('destroy',unit.actor) end
                    end
                    local gone,proof=removed(unit.actor)
                    log(label..'清理读回 actor='..actor_name(unit.actor)..'；'..proof)
                    if gone==true then destroyed=destroyed+1
                    else kept[#kept+1]=unit;pending=pending+1 end
                end
            end
            units=kept;notify_units()
            if arena_records()==0 and state=='cleanup_pending' then state=lastRestoreConfirmed and 'idle' or 'restore_pending' end
            return response(pending==0,label..'清理：已确认='..destroyed..'，待确认='..pending,{destroyed_count=destroyed,remaining_count=pending})
        end)
    end
    function instance:clearNeutral() return clear_team('neutral','未配队') end
    function instance:clearCompanions()
        local result=clear_team('companion','随从')
        if not self:recoverCompanionCleanup() then return response(false,'部分切换中的随从仍待回收') end
        return result
    end

    function instance:setRelayPending(enabled,blue,red,epoch)
        if not enabled or epoch~=relay.epoch then relay.anchor=nil end
        relay.epoch=epoch
        relay.enabled=enabled==true
        relay.blue=relay.enabled and blue or 0;relay.red=relay.enabled and red or 0
    end

    local function currentRosterWorld()
        local gotPlayer,player=invoke('getPlayer')
        if not gotPlayer or live(player)~=true then return end
        local gotWorld,world=invoke('getWorld',player)
        if gotWorld then return actor_key(world),world end
    end

    local function readStatus(members,roster)
        prune()
        local rosterWorld=roster and currentRosterWorld()
        local blue, red, neutral, unreadable, dead,neutralOwned,summons = 0, 0, 0, 0, 0,0,0
        local companions,companionOwned,reserve,stands,aids=0,0,0,0,0
        local unread={}
        for _, unit in ipairs(units) do
            if unit.summoner then summons=summons+1 end
            if unit.team=='neutral' then neutralOwned=neutralOwned+1 end
            if unit.team=='companion' then companionOwned=companionOwned+1 end
            local alive,proof,hp=alive_readback(unit)
            local isStand=stand(unit)
            local hidden=not isStand and alive==true and dormant(unit)
            if hidden~=(unit.dormant==true) then
                log((hidden and '备用召唤物（隐藏、AI 未启动），不计存活 team=' or '备用召唤物登场，计入存活 team=')..unit.team..' actor='..actor_name(unit.actor))
                unit.dormant=hidden
            end
            if unit.aid then
                if alive==true then aids=aids+1 elseif alive==false then dead=dead+1 end
            elseif isStand then stands=stands+1
            elseif hidden then reserve=reserve+1
            elseif alive==true then
                if unit.team == "blue" then blue = blue + 1 elseif unit.team == "red" then red = red + 1
                elseif unit.team == "companion" then companions = companions + 1 else neutral = neutral + 1 end
            elseif alive==false then dead=dead+1
            else unreadable=unreadable+1;unread[unit.team]=(unread[unit.team] or 0)+1 end
            if unit.countedAlive~=alive and (alive==false or unit.countedAlive==false) then
                log('存活人数更新 team='..unit.team..(unit.aid and '（对面召来的帮手，不计入）' or '')..' actor='..actor_name(unit.actor)
                    ..'；读回='..proof..' alive='..tostring(alive)..'；保留所有权供清理')
            end
            if unit.countedAlive~=alive and type(alive)=='boolean' and unit.formationGroup
                and unit.formationGroup.nativeFormation and options.formationLifeChanged then
                invoke('formationLifeChanged',unit.formationGroup,unit.actor,alive)
            end
            unit.countedAlive=alive
            if members then members[#members+1]=memberRow(unit,isStand) end
            if rosterWorld and unit.rosterId and unit.rosterWorld==rosterWorld then
                roster[#roster+1]={id=unit.rosterId,team=unit.team,path=unit.class_path,ordinal=unit.rosterOrdinal,
                    state=alive==nil and 'unknown' or alive and 'alive' or 'down',hp=hp}
            end
        end
        local over=battleActive and (blue+(unread.blue or 0)+relay.blue==0 or red+(unread.red or 0)+relay.red==0)
        if over then fight.winner=fight.winner or (blue>0 and 'blue' or red>0 and 'red' or 'draw') end
        local okNow,now=invoke('now')
        if okNow and finite(now) then
            if battleActive and blue>0 and red>0 and (not fight.started or fight.ended) then
                fight={started=now};log('战斗计时开始 蓝='..blue..' 红='..red..' 游戏时间='..string.format('%.2f',now))
            elseif over and fight.started and not fight.ended then
                fight.ended=now;log(string.format('战斗计时结束 用时=%.2f秒 蓝=%d 红=%d',now-fight.started,blue,red))
            end
            if over then
                local winner=blue>0 and 'blue' or red>0 and 'red' or nil
                finishReport({reason='completed',blueAlive=blue,redAlive=red,winner=winner,
                    seconds=fight.started and math.max(0,(fight.ended or now)-fight.started) or nil})
            end
            fight.now=now
        end
        return { blue_count = blue, red_count = red, blue_unreadable=unread.blue or 0,red_unreadable=unread.red or 0,neutral_count = neutral, total = blue + red + neutral,
            owned_records = #units,neutral_owned=neutralOwned,companion_count=companions,companion_owned=companionOwned,unreadable_count = unreadable, dead_count=dead,max_units=maxUnits,summon_count=summons,reserve_count=reserve,stand_count=stands,aid_count=aids,battle_active=battleActive,current_unit = selected or "", current_team = team,
            current_count = count,team_revision=teamRevision, state = state, message = message, busy = busy,
            roster=roster,roster_editable=(not battleActive or over) and state~='cleanup_pending'
                and state~='restore_pending' and state~='spawn_uncertain' and state~='operation_failed',
            winner=over and fight.winner or nil,
            battle_clock=fight.started and (fight.ended and 'ended' or 'running') or '',
            battle_seconds=fight.started and math.max(0,(fight.ended or fight.now)-fight.started) or 0 }
    end

    function instance:status(includeRoster)
        return readStatus(nil,includeRoster and {} or nil)
    end

    function instance:removeRosterUnit(id)
        return run(function()
            if type(id)~='string' or not id:match('^A[1-9]%d*$') then return response(false,'单位编号无效') end
            local status=readStatus()
            if not status.roster_editable or spawn_block() then
                return response(false,'战斗或清理进行中，暂时无法移除单位')
            end
            local root
            for _,unit in ipairs(units)do if unit.rosterId==id then root=unit;break end end
            if not root then return response(false,'该单位已离场，请刷新阵容') end
            local worldKey,world=currentRosterWorld()
            if not worldKey or root.rosterWorld~=worldKey then return response(false,'单位已不在当前地图') end

            -- Spawn records precede their children. Recheck identities before destroying the owned group
            -- and leave the selected unit registered if any of its helpers could not be removed.
            local picked,plan={},{}
            for _,unit in ipairs(units)do
                if unit==root or picked[unit.rosterParent] then
                    picked[unit]=true
                    plan[#plan+1]=unit
                end
            end
            local function matches(unit)
                if unit.rosterWorld~=worldKey or not unit.rosterKey or actor_key(unit.actor)~=unit.rosterKey
                    or actor_name(unit.actor)~=unit.rosterName or unit.rosterName:lower():match('^unknown%(') then return false end
                if options.inCompanionWorld then
                    local checked,same=invoke('inCompanionWorld',unit.actor,world)
                    return checked and same==true
                end
                return true
            end
            for _,unit in ipairs(plan)do
                if removed(unit.actor)~=false or not matches(unit) then
                    return response(false,'单位身份或所属地图未确认，移除未执行')
                end
            end
            for i=#plan,1,-1 do
                local unit=plan[i]
                if removed(unit.actor)==false and matches(unit) then invoke('destroy',unit.actor) end
                local gone,proof=removed(unit.actor)
                log('阵容移除 '..id..' actor='..tostring(unit.rosterName)..'；读回='..proof)
                if gone~=true then
                    prune()
                    return response(false,'移除尚未确认，名单保留未回收单位')
                end
            end
            prune()
            return response(true,'已移除选中的单位',{destroyed_count=#plan})
        end)
    end
    -- Both consumers in one support tick see the same reserve state. Commands still take fresh reads.
    function instance:snapshot()
        local members={}
        local status=readStatus(members)
        return members,status
    end

    -- Called by the existing panel loop once a second, including before a duel.
    -- This is observation only; a health change does not identify its attacker.
    function instance:sampleHealth()
        local okNow,now=invoke('now')
        if not okNow or not finite(now) then now=os.clock() end
        -- With a crowd on the field each unit logs at most every 5 s, and always when it falls.
        local crowded=#units>12
        for _,unit in ipairs(units) do
            if removed(unit.actor)==false then
                local ok,hp=invoke('hp',unit.actor)
                if ok and finite(hp) and hp~=unit.lastHP then
                    if not crowded or hp<=0 or not unit.hpLoggedAt or now-unit.hpLoggedAt>=5 then
                        log('生命读回 team='..unit.team..' actor='..actor_name(unit.actor)
                            ..' HP='..tostring(unit.lastHP or 'initial')..' -> '..tostring(hp)..'；只读，伤害来源待画面核对')
                        unit.hpLoggedAt=now
                    end
                    unit.lastHP=hp
                end
            end
        end
    end

    return instance
end

return Arena
