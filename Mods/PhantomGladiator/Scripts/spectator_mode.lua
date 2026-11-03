-- 观战免仇恨请求。仅在游戏线程调用；不修改镜头、标签或NPC互相仇恨，不调用ForceOffCombat。
-- 头文件：BP_SGameHatredManagerComponent.hpp:8-10,23；SGameCombatSystem.hpp:1783-1788。
-- 原覆盖是否存在不可读，关闭仅验证有效关系；不会宣称恢复了未知覆盖结构。
-- 玩家一方（options.isPlayerSide：随从、随从的召唤物、玩家阵营）不接管；之后才加入玩家一方的，关闭时设为友好，
-- 不恢复它当敌人时的关系（v0.37.3 及以前：开着无仇恨召唤的随从，关闭后对玩家变回敌对）。
local Spectator = {}

local function limit(value, default, low, high)
    value = tonumber(value) or default
    if value ~= value then value = default end
    return math.floor(math.max(low, math.min(high, value)))
end

function Spectator.new(options)
    options = options or {}
    local cfg = options.config or {}
    local batch = limit(cfg.BatchSize, 16, 1, 64)
    local maxNPCs = limit(cfg.MaxNPCs, 512, 1, 2048)
    local maxRecords = limit(cfg.MaxRecords, 1024, 1, 4096)
    local maxHatred = limit(cfg.MaxHatredEntries, 512, 1, 2048)
    local relations, flags = {}, {}
    local componentClasses,componentReports={},{ }
    local componentPaths={['Faction Component']='/Script/SGameCombatSystem.FactionComponent',
        BP_PBZHatredManagerComponent='/PBZCombatAsset/Prototypes/AI/BP_PBZHatredManagerComponent.BP_PBZHatredManagerComponent_C'}
    local enabled, silenced, offset, ticks, restoreOffset = false, false, 0, 0, 0
    local counters = { overrides_verified = 0, removed_player_entries = 0, readFailures = 0,
        effective_restored = 0, override_structure_unknown = 0, arena_preserved = 0, flag_writes_verified = 0,
        flag_restores_verified = 0, invalid_records_discarded = 0, destroying_records_discarded = 0,
        destroying_actors_skipped = 0, npc_truncated = false, player_side_skipped = 0, player_side_released = 0 }
    local message, playerFlagReadback, currentPlayerKey = "未请求免仇恨", "unknown", nil
    local sideNoted, sideNotedCount = {}, 0
    local instance = {}

    local function log(text)
        if options.log then pcall(options.log, "[Spectator] " .. text) end
    end

    local function fail(text)
        counters.readFailures = counters.readFailures + 1
        if counters.readFailures <= 10 or counters.readFailures % 50 == 0 then
            log("未验证: " .. tostring(text) .. "；readFailures=" .. counters.readFailures)
        end
    end

    local function valid(object)
        if object == nil then return false end
        local ok, result
        if options.valid then ok, result = pcall(options.valid, object)
        else ok, result = pcall(function() return object:IsValid() end) end
        if not ok or type(result) ~= "boolean" then return nil end
        return result
    end

    -- 只用于已知Actor。不能对component/UClass调用IsActorBeingDestroyed。
    local function actor_valid(actor)
        local alive = valid(actor)
        if alive ~= true then return alive, alive == false and "invalid" or "unknown" end
        if not options.isActorDestroying then return true, "valid" end
        local ok, destroying = pcall(options.isActorDestroying, actor)
        if not ok or type(destroying) ~= "boolean" then return nil, "unknown" end
        if destroying then return false, "destroying" end
        return true, "valid"
    end

    local function key(object)
        if valid(object) ~= true then return nil end
        local ok, address = pcall(function() return object:GetAddress() end)
        if ok and (type(address) == "number" or type(address) == "string") then return tostring(address) end
        return nil
    end

    -- Preserve restoration snapshots across a Lua reload, including automatic F6
    -- requests. Only paths plus exact object identities are serialized.
    local fs=options.io or io
    local journal=options.path and (options.path..'/spectator-state.tsv')
    local pendingJournal,lastJournal={}
    if journal then
        local file=fs.open(journal,'r')
        if file then
            local text=file:read('*a');file:close()
            if text:match('^SpectatorV1\n') then
                for line in text:gmatch('[^\r\n]+')do
                    if line~='SpectatorV1' then
                        local cells={};for value in (line..'\t'):gmatch('(.-)\t')do cells[#cells+1]=value end
                        if (cells[1]=='F' and #cells==6) or (cells[1]=='R' and #cells==8) then pendingJournal[#pendingJournal+1]=cells end
                    end
                end
            end
        end
    end
    local function identity(object)
        local id=key(object);if not id then return nil end
        local ok,name=pcall(function()return object:GetFullName()end)
        local path=ok and type(name)=='string' and name:match('^%S+ (/.+)$')
        if not path or path:find('[\t\r\n]') then return nil end
        return path,id
    end
    local function persistent(record,kind)
        if not journal then return true end
        local row={kind}
        for _,field in ipairs(kind=='F' and {'player','hm'} or {'npc','fc','player'})do
            local path,id=identity(record[field]);if not path then return false end
            row[#row+1]=path;row[#row+1]=id
        end
        row[#row+1]=kind=='F' and (record.original and '1' or '0') or tostring(record.original)
        record.journal=row;return true
    end
    local function persist()
        if not journal then return true end
        local lines={'SpectatorV1'}
        local rows={}
        for _,map in ipairs({flags,relations})do for _,r in pairs(map)do
            if r.journal then rows[#rows+1]=table.concat(r.journal,'\t') end
        end end
        for _,row in ipairs(pendingJournal)do rows[#rows+1]=table.concat(row,'\t')end
        table.sort(rows);for _,row in ipairs(rows)do lines[#lines+1]=row end
        local text=table.concat(lines,'\n')..'\n';if text==lastJournal then return true end
        local file=fs.open(journal,'w');if not file then return false end
        local wrote=file:write(text);local closed=file:close()
        file=fs.open(journal,'r');local actual=file and file:read('*a');if file then file:close()end
        if wrote and closed and actual==text then lastJournal=text;return true end
        return false
    end
    local function recoverJournal()
        if #pendingJournal==0 then return end
        local function resolve(path,id)
            local ok,obj=pcall(StaticFindObject,path)
            if not ok then return nil,true end
            local live=valid(obj);if live==nil then return nil,true end
            if live==false then return nil,false end
            local actualPath,actualId=identity(obj)
            if not actualPath then return nil,true end
            if actualId==id and actualPath==path then return obj,false end
            return nil,false
        end
        local remaining={}
        for _,row in ipairs(pendingJournal)do
            if row[1]=='F' then
                local player,unknownPlayer=resolve(row[2],row[3]);local hm,unknownHM=resolve(row[4],row[5])
                if player and hm and (row[6]=='0' or row[6]=='1') then
                    flags[row[5]]={player=player,playerKey=row[3],hm=hm,original=row[6]=='1',journal=row}
                elseif unknownPlayer or unknownHM then remaining[#remaining+1]=row end
            else
                local npc,unknownNPC=resolve(row[2],row[3]);local fc,unknownFC=resolve(row[4],row[5]);local player,unknownPlayer=resolve(row[6],row[7])
                local original=tonumber(row[8])
                if npc and fc and player and (original==0 or original==1 or original==2) then
                    relations[row[3]..':'..row[5]..':'..row[7]]={npc=npc,npcKey=row[3],fc=fc,player=player,playerKey=row[7],original=original,journal=row}
                elseif unknownNPC or unknownFC or unknownPlayer then remaining[#remaining+1]=row end
            end
        end
        log('已读取上次恢复记录，按原对象路径和身份核验后恢复；条数='..#pendingJournal)
        pendingJournal=remaining
    end

    local function discarded(map, id, reason)
        map[id] = nil
        counters.invalid_records_discarded = counters.invalid_records_discarded + 1
        if reason == "destroying" then
            counters.destroying_records_discarded = counters.destroying_records_discarded + 1
            log("丢弃过期快照 " .. id .. "；Actor销毁读回=true（IsValid可能仍true），未再访问组件")
        end
    end

    local function discard_destroying(actor, role)
        local actorKey = key(actor)
        for id, record in pairs(relations) do
            local target = role == "player" and record.player or record.npc
            local targetKey = role == "player" and record.playerKey or record.npcKey
            if target == actor or (actorKey and targetKey == actorKey) then discarded(relations, id, "destroying") end
        end
        if role == "player" then
            for id, record in pairs(flags) do
                if record.player == actor or (actorKey and record.playerKey == actorKey) then discarded(flags, id, "destroying") end
            end
        end
        counters.destroying_actors_skipped = counters.destroying_actors_skipped + 1
        if counters.destroying_actors_skipped <= 10 or counters.destroying_actors_skipped % 50 == 0 then
            log("跳过" .. role .. "；Actor销毁读回=true；未读取其组件")
        end
    end

    local function component(actor, property)
        if actor_valid(actor) ~= true then return nil end
        local ok, result = pcall(function() return actor[property] end)
        if ok and valid(result) == true then return result end
        local path=componentPaths[property]
        local cls=componentClasses[property]
        if path and valid(cls)~=true then
            local found,value=pcall(function()return StaticFindObject(path)end)
            if found and valid(value)==true then cls=value;componentClasses[property]=cls end
        end
        if valid(cls)==true then
            local found,value=pcall(function()return actor:GetComponentByClass(cls)end)
            if found and valid(value)==true then
                local owned,owner=pcall(function()return value:GetOwner()end)
                local actorKey=key(actor)
                if owned and actorKey and key(owner)==actorKey then
                    local id=tostring(key(actor))..property
                    if not componentReports[id] then componentReports[id]=true;log('按组件类定位 '..property..' actor='..tostring(key(actor)))end
                    return value
                end
            end
        end
    end

    local function size(map)
        local n = 0
        for _ in pairs(map) do n = n + 1 end
        return n
    end

    local function relation(npc, fc, player)
        if actor_valid(npc) ~= true or actor_valid(player) ~= true then return nil end
        if valid(fc) ~= true then return nil end
        local ok, value = pcall(function() return fc:GetFactionRelation(player) end)
        if ok and (value == 0 or value == 1 or value == 2) then return value end
    end

    local function player_side(npc)
        if not options.isPlayerSide then return false end
        local ok, side = pcall(options.isPlayerSide, npc)
        return ok and side == true
    end

    local function set_relation(npc, fc, player, value)
        if actor_valid(npc) ~= true or actor_valid(player) ~= true then return false, nil end
        if valid(fc) ~= true then return false, nil end
        local ok = pcall(function() fc:SetFactionRelationOverride(player, value, false) end)
        local actual = relation(npc, fc, player)
        return ok and actual == value, actual
    end

    local function read_flag(player, hm)
        if actor_valid(player) ~= true then return nil end
        if valid(hm) ~= true then return nil end
        local ok, value = pcall(function() return hm.CanBeHatredNow end)
        if ok and type(value) == "boolean" then return value end
    end

    local function apply_player_flag(player)
        local hm = component(player, "BP_PBZHatredManagerComponent")
        local id = key(hm)
        local before = read_flag(player, hm)
        if not id or before == nil then fail("玩家CanBeHatredNow不可读"); return end
        if not flags[id] then
            if size(flags) >= 8 then fail("玩家快照达到上限，未改新对象"); return end
            local record={ player = player, playerKey = key(player), hm = hm, original = before }
            if not persistent(record,'F') then fail('玩家恢复身份不可保存，未修改');return end
            flags[id]=record
            if not persist() then fail('玩家恢复记录写入失败，未修改');return end
        end
        if before == false then playerFlagReadback = false; return end
        if not persist() then fail('玩家恢复记录未保存，未修改');return end
        if actor_valid(player) ~= true then fail("玩家组件写入前Actor不可用"); return end
        if valid(hm) ~= true then fail("玩家组件写入前失效"); return end
        local ok = pcall(function() hm.CanBeHatredNow = false end)
        local actual = read_flag(player, hm)
        playerFlagReadback = actual == nil and "unknown" or actual
        log("玩家CanBeHatredNow 操作=false；原值=" .. tostring(flags[id].original) .. "；读回=" .. tostring(actual))
        if ok and actual == false then counters.flag_writes_verified = counters.flag_writes_verified + 1
        else fail("CanBeHatredNow写后未读回false") end
    end

    local function contains_player(npc, hm, player)
        if actor_valid(npc) ~= true or actor_valid(player) ~= true then return nil end
        if valid(hm) ~= true then return nil end
        local playerKey = key(player)
        if not playerKey then return nil end
        local found, scanned, truncated, unreadable = false, 0, false, false
        local ok = pcall(function()
            local list = hm.HatredList
            if list == nil then error("HatredList unavailable") end
            local total = #list
            list:ForEach(function(_, entry)
                if scanned >= maxHatred then truncated = true; return true end
                scanned = scanned + 1
                -- TArray.ForEach 的 entry 是参数代理，不是 UObject；解包后逐级核验。
                local actor = entry:get()
                local actorValid = valid(actor)
                local actorKey = key(actor)
                if actorValid == nil or (actorValid == true and not actorKey) then unreadable = true end
                if actorKey and actorKey == playerKey then found = true; return true end
            end)
            if scanned < total and not found then truncated = true end
        end)
        if found then return true end
        if not ok or truncated or unreadable then return nil end
        return false
    end

    local function process_npc(npc, player, playerKey)
        local usable, reason = actor_valid(npc)
        if usable ~= true then
            if reason == "destroying" then discard_destroying(npc, "npc")
            elseif usable == nil then fail("NPC销毁状态/有效性读回未知，保留快照") end
            return
        end
        local npcKey = key(npc)
        if not npcKey or npcKey == playerKey then return end
        if player_side(npc) then
            counters.player_side_skipped = counters.player_side_skipped + 1
            if not sideNoted[npcKey] and sideNotedCount < 50 then
                sideNoted[npcKey], sideNotedCount = true, sideNotedCount + 1
                log("NPC=" .. npcKey .. " 是玩家一方（随从、其召唤物或玩家阵营）；不改关系、不记录旧关系")
            end
            return
        end
        if options.releasePlayerTarget then
            local ok,released=pcall(options.releasePlayerTarget,npc,player)
            if not ok or released~=true then fail('玩家AI目标释放未确认') end
        end
        local fc = component(npc, "Faction Component")
        local fcKey = key(fc)
        local before = relation(npc, fc, player)
        if not fcKey or before == nil then fail("NPC " .. npcKey .. " 阵营关系不可读")
        elseif before ~= 1 then
            local id = npcKey .. ":" .. fcKey .. ":" .. playerKey
            if not relations[id] then
                if size(relations) >= maxRecords then fail("关系快照达到上限，未改新NPC"); return end
                local record={ npc = npc, npcKey = npcKey, fc = fc, player = player, playerKey = playerKey, original = before }
                if not persistent(record,'R') then fail('关系恢复身份不可保存，未修改');return end
                relations[id]=record
                if not persist() then fail('关系恢复记录写入失败，未修改');return end
            end
            if not persist() then fail('关系恢复记录未保存，未修改');return end
            local verified, actual = set_relation(npc, fc, player, 1)
            log("NPC=" .. npcKey .. " 操作=对玩家单向Neutral Both=false；原关系=" .. relations[id].original .. "；读回=" .. tostring(actual))
            if verified then counters.overrides_verified = counters.overrides_verified + 1
            else fail("NPC中立覆盖未读回") end
        end
        local hm = component(npc, "BP_PBZHatredManagerComponent")
        local hadPlayer = contains_player(npc, hm, player)
        if hadPlayer == nil then fail("NPC " .. npcKey .. " 仇恨成员不可读"); return end
        if hadPlayer == true then
            if actor_valid(npc) ~= true or actor_valid(player) ~= true then fail("移除仇恨前Actor不可用"); return end
            if valid(hm) ~= true then fail("移除仇恨前对象失效"); return end
            local ok = pcall(function() hm:RemoveActorFromHatredList(player) end)
            local actual = contains_player(npc, hm, player)
            log("NPC=" .. npcKey .. " 操作=RemoveActorFromHatredList(仅玩家)；原存在=true；读回存在=" .. tostring(actual))
            if ok and actual == false then counters.removed_player_entries = counters.removed_player_entries + 1
            else fail("玩家仇恨成员移除未验证") end
        end
    end

    local function restore_flags()
        for id, record in pairs(flags) do
            local playerValid, playerReason = actor_valid(record.player)
            local hmValid
            if playerValid == true then hmValid = valid(record.hm) end
            if playerValid == false then
                discarded(flags, id, playerReason)
                if playerReason == "destroying" then playerFlagReadback = "unknown(actor_destroying)" end
            elseif hmValid == false then
                discarded(flags, id, "invalid")
            elseif playerValid == true and hmValid == true then
                local ok = pcall(function() record.hm.CanBeHatredNow = record.original end)
                local actual = read_flag(record.player, record.hm)
                if key(record.player) == currentPlayerKey then playerFlagReadback = actual == nil and "unknown" or actual end
                log("关闭：CanBeHatredNow恢复目标=" .. tostring(record.original) .. "；读回=" .. tostring(actual))
                if ok and actual == record.original then
                    flags[id] = nil; counters.flag_restores_verified = counters.flag_restores_verified + 1
                else fail("玩家资格恢复未验证，保留快照") end
            else fail("玩家资格恢复有效性未知，保留快照") end
        end
    end

    local function desired_relation(npc, player)
        if not options.getDesiredPlayerRelation then return true, nil end
        local ok, value = pcall(options.getDesiredPlayerRelation, npc, player)
        if not ok then return false, nil end
        if value == nil or value == 0 or value == 1 or value == 2 then return true, value end
        return false, nil
    end

    local function restore_relations()
        local ids = {}
        for id in pairs(relations) do ids[#ids + 1] = id end
        table.sort(ids)
        if #ids == 0 then restoreOffset = 0; return end
        restoreOffset = restoreOffset % #ids
        local work = math.min(batch, #ids)
        for step = 1, work do
            local id = ids[(restoreOffset + step - 1) % #ids + 1]
            local record = relations[id]
            local npcValid, npcReason = actor_valid(record.npc)
            local playerValid, playerReason = actor_valid(record.player)
            local fcValid
            if npcValid == true and playerValid == true then fcValid = valid(record.fc) end
            if npcValid == false or playerValid == false then
                discarded(relations, id, (npcReason == "destroying" or playerReason == "destroying") and "destroying" or "invalid")
            elseif fcValid == false then
                discarded(relations, id, "invalid")
            elseif npcValid ~= true or playerValid ~= true or fcValid ~= true then
                fail("关系恢复对象有效性未知，保留快照")
            elseif player_side(record.npc) then
                -- Joined the player's side after it was recorded (a companion's summon, or a companion recorded by
                -- an older version while it was still the enemy): friendly, never the relation it had back then.
                local ok, actual = set_relation(record.npc, record.fc, record.player, 0)
                log("关闭：NPC=" .. record.npcKey .. " 已是玩家一方，设为友好，不恢复旧关系=" .. record.original .. "；读回=" .. tostring(actual))
                if ok then relations[id] = nil; counters.player_side_released = counters.player_side_released + 1
                else fail("玩家一方单位友好关系未读回，保留快照") end
            else
                local okPolicy, desired = desired_relation(record.npc, record.player)
                if not okPolicy then fail("arena关系策略不可读，未清覆盖")
                elseif desired ~= nil then
                    local ok, actual = set_relation(record.npc, record.fc, record.player, desired)
                    log("关闭：保留arena关系=" .. desired .. "；读回=" .. tostring(actual))
                    if ok then relations[id] = nil; counters.arena_preserved = counters.arena_preserved + 1
                    else fail("arena关系未读回，保留快照") end
                else
                    local okClear = pcall(function()
                        if actor_valid(record.npc) ~= true or actor_valid(record.player) ~= true then
                            error("clear前Actor不可用")
                        end
                        if valid(record.fc) ~= true then
                            error("clear前对象失效")
                        end
                        record.fc:ClearFactionRelationOverride(record.player)
                    end)
                    local actual = relation(record.npc, record.fc, record.player)
                    local effective = okClear and actual == record.original
                    if actual ~= record.original then
                        effective, actual = set_relation(record.npc, record.fc, record.player, record.original)
                    end
                    log("关闭：ClearOverride后必要时恢复原有效值=" .. record.original .. "；读回=" .. tostring(actual)
                        .. "；原覆盖结构未知，未宣称结构恢复")
                    if effective then
                        relations[id] = nil
                        counters.effective_restored = counters.effective_restored + 1
                        counters.override_structure_unknown = counters.override_structure_unknown + 1
                    else fail("原有效关系恢复未验证，保留快照") end
                end
            end
        end
        restoreOffset = (restoreOffset + work) % #ids
    end

    function instance:status()
        local result = { enabled_requested = enabled, silenced = silenced, pending_relations = size(relations)+#pendingJournal,
            pending_flags = size(flags), player_can_be_hatred_readback = playerFlagReadback, message = message }
        for k, v in pairs(counters) do result[k] = v end
        return result
    end

    function instance:tick()
        if silenced then return self:status() end
        recoverJournal()
        ticks = ticks + 1
        if not enabled then
            restore_flags(); restore_relations()
            if not persist() then fail('恢复账本保存未确认') end
            -- Also observe the current player when this Mod never enabled F8.
            -- A requested-off switch alone cannot establish the game flag state.
            local okPlayer,player=pcall(options.getPlayer or function() end)
            local current
            if okPlayer and actor_valid(player)==true then
                current=read_flag(player,component(player,'BP_PBZHatredManagerComponent'))
            end
            if current==nil then playerFlagReadback='unknown' else playerFlagReadback=current end
            return self:status()
        end
        local okPlayer, player = pcall(options.getPlayer or function() end)
        local playerUsable, playerReason
        if okPlayer then playerUsable, playerReason = actor_valid(player) end
        if playerReason == "destroying" then
            discard_destroying(player, "player")
            playerFlagReadback = "unknown(actor_destroying)"
            return self:status()
        end
        if playerUsable ~= true then fail("当前玩家Actor状态未知/无效，保留快照"); return self:status() end
        local playerKey = okPlayer and key(player)
        if not playerKey then fail("当前玩家无效或身份不可读"); return self:status() end
        currentPlayerKey = playerKey
        apply_player_flag(player)
        local okNPCs, npcs = pcall(options.getNPCs or function() return {} end)
        if not okNPCs or type(npcs) ~= "table" then fail("NPC列表不可读"); return self:status() end
        local n = math.min(#npcs, maxNPCs)
        counters.npc_truncated = #npcs > maxNPCs
        if n > 0 then
            offset = offset % n
            for step = 1, math.min(batch, n) do
                local currentValid, currentReason = actor_valid(player)
                if currentValid ~= true then
                    if currentReason == "destroying" then discard_destroying(player, "player") end
                    fail("处理NPC期间玩家Actor不可用"); break
                end
                process_npc(npcs[(offset + step - 1) % n + 1], player, playerKey)
            end
            offset = (offset + math.min(batch, n)) % n
        end
        if ticks % 20 == 0 then
            log("请求仍开启；已验证覆盖次数=" .. counters.overrides_verified .. "；移除玩家次数=" .. counters.removed_player_entries
                .. "；readFailures=" .. counters.readFailures .. "；实际无仇恨效果待用户观察")
        end
        return self:status()
    end

    function instance:applyTo(npc)
        if not enabled or silenced then return end
        recoverJournal()
        local ok,player=pcall(options.getPlayer or function()end)
        if not ok or actor_valid(player)~=true then return end
        apply_player_flag(player)
        process_npc(npc,player,key(player))
    end

    function instance:setEnabled(value)
        if type(value) ~= "boolean" then return { ok = false, message = "enabled必须是boolean" } end
        if not value and options.isObserverActive and options.isObserverActive() then
            local result=self:status();result.ok=false
            result.message='自由观战正在保持无仇恨、隐身和锁血；请先退出自由观战，再切换独立无仇恨'
            return result
        end
        enabled, silenced = value, false
        message = value and "已请求免仇恨；只报告具体读回，效果待实测" or "已请求关闭；恢复原有效关系和玩家资格"
        log(message)
        local result = self:tick()
        result.ok = not value and result.pending_relations == 0 and result.pending_flags == 0 or value
        return result
    end

    function instance:toggle() return self:setEnabled(not enabled) end
    function instance:on() return self:setEnabled(true) end
    function instance:off() return self:setEnabled(false) end
    function instance:silence(reason)
        -- OnUnload只能静默；不访问任何UObject、不注销hook、不伪装已恢复。
        enabled, silenced = false, true
        message = "Lua已静默；尚存快照未在游戏中恢复: " .. tostring(reason or "unload")
        log(message)
    end

    return instance
end

return Spectator
