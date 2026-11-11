-- ============================================================
-- PhantomGladiator — 《影之刃零》斗蛐蛐 Mod (UE4SS Lua)
-- 让 NPC 互相为敌、召唤单位、观战、慢动作、自由镜头。
-- 功能快捷键在面板配置；首次使用全部未绑定。
-- ============================================================
local Config = require("config")
local UEHelpers = require("UEHelpers")
local Session = require("battle_session")
local CombatProbe = require("combat_probe")
local AttackProfile = require("attack_profile")
local Catalog = require("npc_catalog")
local AssetExporter = require("asset_inventory")
local ArenaController = require("arena_controller")
local PanelRuntime = require("panel_runtime")
local SpectatorMode = require("spectator_mode")
local SpawnPolicy = require("spawn_policy")
local RuntimeSession = require("runtime_session")
local SpawnAudit = require("spawn_audit")
local CodexExporter = require("codex_catalog_export")
local SpawnGuard = require("spawn_guard")
local SpawnInspector = require("spawn_inspector")
local WorldMapCatalog = require("world_map_catalog")
local SpawnCatalog = require("spawn_catalog_export")
local ReferenceAudit = require("asset_reference_audit")
local TableCatalog = require("table_catalog_export")
local SummonLinks = require('arena_summon_links')
local BossHUD = require('arena_hud')
local EngineObjectState = require('engine_object_state')
local UEObserve = require('ue_observe')
local UnitKeys = require('unit_keybinds')
local ArenaActivity = require('arena_activity')
local FreeCamera = require('free_camera')
local GrabStudy = require('grab_study')
local ArenaGrabs = require('arena_grabs')
local StatMatch = require('stat_match')
local ObserverGuard = require('observer_guard')
local SpectatorTargets = require('spectator_targets')
local KeyRouter = require('key_router')
local KeyPoll = require('key_poll')
local SpawnDifficulty=require('spawn_difficulty')
local AIDifficulty=require('ai_difficulty')
local Companion=require('companion')
local FunFeatures=require('fun_features')
local SpawnLevel=require('spawn_level')
local StatFormulaProbe=require('stat_formula_probe')
local StatFieldProbe=require('stat_field_probe')
local CompanionHitProbe=require('companion_hit_probe')
local AttackFactionScan=require('attack_faction_scan')
local CodexArtProbe=require('codex_art_probe')
local CodexIcons=require('codex_icons')
local ImmortalTeams=require('immortal_teams')
local BattleClockHUD=require('battle_clock_hud')
local CombatLock=require('combat_lock')
local CompanionBars=require('companion_bars')
local AreaLevels=require('area_levels')
local HomeLevels=require('home_levels')
local Escorts=require('escorts')
local Mounts=require('mounts')
local BossStages=require('boss_stages')
local ArenaExecutions=require('arena_executions')
local ExecutionCamera=require('execution_camera')

local MOD = "[PhantomGladiator]"
local runLogPath=Config.RuntimePath..'/run-'..os.date('%Y%m%d-%H%M%S')..'.log'
local runLogBytes,runLogWarning=0,false
local function log(msg)
    local line=string.format('%s %s\n',MOD,tostring(msg))
    print(line)
    -- UE4SS.log is overwritten on game restart. Preserve bounded per-load UTF-8
    -- evidence outside the source tree, without touching game save data.
    local durable=os.date('%Y-%m-%d %H:%M:%S')..' '..line
    if runLogBytes+#durable>8*1024*1024 then return end
    local ok,saved=pcall(function()
        local file=io.open(runLogPath,'ab')
        if not file then return false end
        local wrote=file:write(durable)
        local flushed=file:flush()
        local closed=file:close()
        return wrote~=nil and flushed~=nil and closed~=nil
    end)
    if ok and saved then runLogBytes=runLogBytes+#durable
    elseif not runLogWarning then runLogWarning=true;print(MOD..' 独立运行日志写入未确认；UE4SS日志仍保留\n') end
end
local BUILD = "v0.40.11-guillotine-native-test-1"
SpawnPolicy.loadTrials(Config.RuntimePath..'/spawn-trials.tsv',log)
SpawnPolicy.enableAllCatalog()
log('[SpawnPolicy] 用户开启全部目录尝试召唤；总量不设上限；运行时检查Actor继承和对象有效性')
local function safeValid(obj)
    if obj == nil then return false end
    local ok, value = pcall(function() return obj:IsValid() end)
    return ok and value == true
end
local engineObjectState=EngineObjectState.new({log=log})
local function engineValid(obj)
    return safeValid(obj) and engineObjectState:check(obj)~=false
end
UEObserve.setEngineValidator(function(obj) return engineObjectState:check(obj) end)
local function checked(obj)
    if not safeValid(obj) then error("object invalid; access refused") end
    return obj
end
local function objectName(obj)
    if not safeValid(obj) then return "UNKNOWN(invalid)" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and tostring(value) or "UNKNOWN(name)"
end
local function actorIsDestroying(actor)
    checked(actor)
    return actor:IsActorBeingDestroyed()
end
-- A valid wrapper can still point to an Actor already entering destruction.
local function summonActorLive(actor)
    local ok,destroying=pcall(actorIsDestroying,actor)
    return ok and destroying==false
end
local battle = Session.new(log)
local probeFinished
local probe = CombatProbe.new({log=log, valid=safeValid, config=Config.Probe,
    onStop=function(state) if probeFinished then probeFinished(state) end end})
local probeSampleGen = 0
local attackProfile = AttackProfile.new({log=log,valid=safeValid})
local arenaActors = {}
local spawnRoutes={}
local arena
local panelRuntime
local spectator
local bossHUD
local arenaActivity
local arenaGrabs
local statMatch
local spawnDifficulty
local spawnLevel
local statProbe
local fieldProbe
local companionHitProbe
local attackScan
local codexArt
local codexIcons
local companions
local aiDifficulty
local funFeatures
local immortalTeams
local clockHUD
local combatLock
local playerAim
local aiParams
local bossCombos
local fightWatch
local onGround
local arenaExecutions
local executionCamera
local mounts
local arenaSupport={}
local bossStages
local BeginArenaObservation
local spawnAudit=SpawnAudit.new(Config.RuntimePath.."/spawn-attempts.tsv",log)
local spawnGuard=SpawnGuard.new()
local spawnInspector=SpawnInspector.new({log=log,canSpawn=SpawnPolicy.check})


local function FNameToString(v)
    local ok, s = pcall(function() return v:ToString() end)
    if ok and s then return s end
    return tostring(v)
end

-- ---------- 基础工具 ----------

-- 真正的玩家控制器：持有 UPlayer、且不是调试相机
local function GetRealPlayerController()
    local ok, list = pcall(FindAllOf, "PlayerController")
    if not ok or not list then return nil end
    for _, pc in ipairs(list) do
        local okP, good = pcall(function()
            if not pc:IsValid() then return false end
            local cls = pc:GetClass()
            if not safeValid(cls) or objectName(cls):find("DebugCameraController") then return false end
            local player = pc.Player
            return safeValid(player)
        end)
        if okP and good then return pc end
    end
    return nil
end

local function GetPlayerPawn()
    local pc = GetRealPlayerController()
    if pc then
        local ok, p = pcall(function() return pc.Pawn end)
        if ok and p and p:IsValid() then return p end
    end
    local ok, pawn = pcall(function()
        local upc = UEHelpers.GetPlayerController()
        return upc and upc:IsValid() and upc.Pawn or nil
    end)
    if ok and pawn and pawn:IsValid() then return pawn end
    return nil
end

local function GetLocation(actor)
    if not safeValid(actor) then return nil end
    local ok, loc = pcall(function() return actor:K2_GetActorLocation() end)
    if ok and loc then return loc end
    return nil
end

-- World time in seconds (stops while the game is paused, follows slow motion); nil before a world exists.
local gameplayStatics
local function GameSeconds()
    if not safeValid(gameplayStatics) then gameplayStatics=StaticFindObject('/Script/Engine.Default__GameplayStatics') end
    local world=UEHelpers.GetWorld()
    if not safeValid(gameplayStatics) or not safeValid(world) then return nil end
    local ok,seconds=pcall(function()return gameplayStatics:GetTimeSeconds(world)end)
    return ok and type(seconds)=='number' and seconds or nil
end

local function DistSq(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return dx * dx + dy * dy + dz * dz
end

local function IsExcluded(pawn)
    if not safeValid(pawn) then return true end
    local ok, name = pcall(function() return pawn:GetFullName() end)
    if not ok or not name then return true end
    for _, kw in ipairs(Config.ExcludeClassKeywords) do
        if name:find(kw) then return true end
    end
    return false
end

local function GetGameplayStatics()
    local gps = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if gps and gps:IsValid() then return gps end
    return nil
end

local playerNeutral = false
local dilationIndex = 1

-- 旧态度返回值修改已移除。脚本态度函数由 CombatProbe 正确注册只读回调。

-- 单位类型目录与活怪列表分开；已知路径及选择跨热重载保存。
local npcCatalog=Catalog.new({log=log,valid=safeValid,getPlayer=GetPlayerPawn,
    path=Config.CatalogPath,knownPaths=Config.KnownMonsterClasses,canSpawn=SpawnPolicy.check,allowActors=true,
    audit=function(stage,unit,detail) return spawnAudit:record(stage,unit,detail) end})
local exporter=AssetExporter.new({log=log,path=Config.RuntimePath,
    config=Config.AssetCatalog})
local worldMaps=WorldMapCatalog.new({log=log,getWorld=UEHelpers.GetWorld})
local codexExporter=CodexExporter.new({log=log,path=Config.RuntimePath.."/codex.tsv",getWorld=UEHelpers.GetWorld,
    locationsPath=Config.RuntimePath..'/codex-locations.tsv',
    maps=worldMaps,onWritten=function()if bossHUD then bossHUD:reloadCodex()end end})

-- ---------- 强制锁敌：走 SGameAI 自家的作战指令 ----------
-- SGameAIComponent:ForceIntoCombat(Target) = "进入战斗，目标是他"；
-- 另把目标写进 AI 的黑板目标键（PBZ_TargetingHandler_AI 从那里读目标）做双保险。

local function GetAIComp(pawn)
    if not safeValid(pawn) then return nil end
    local ok, sg = pcall(function()
        local ctrl = pawn.Controller
        if not ctrl or not ctrl:IsValid() then return nil end
        local c = ctrl.SGameAIComponent
        return (c ~= nil and c:IsValid()) and c or nil
    end)
    if ok then return sg end
    return nil
end

-- 本作的原生仇恨组件（挂在每个 NPC/玩家身上，感知与索敌都以它为准）
local function GetHatredComp(pawn)
    if not safeValid(pawn) then return nil end
    local ok, h = pcall(function() return pawn.BP_PBZHatredManagerComponent end)
    if ok and h ~= nil then
        local okV, v = pcall(function() return h:IsValid() end)
        if okV and v then return h end
    end
    return nil
end

local function HatredListContains(hm, actor)
    if not safeValid(hm) or not safeValid(actor) then return nil end
    local found, unreadable = false, false
    local ok = pcall(function()
        local hl = hm.HatredList
        local addr = actor:GetAddress()
        for i = 1, #hl do
            local okE, hit = pcall(function()
                local entry = hl[i]
                return safeValid(entry) and entry:GetAddress() == addr
            end)
            if not okE then unreadable = true end
            if okE and hit then found = true; return end
        end
    end)
    if found then return true end
    if not ok or unreadable then return nil end
    return false
end

local function AddHatred(attacker, victim)
    local hm = GetHatredComp(attacker)
    if not hm or not safeValid(victim) then return false, "对象无效" end
    local before = HatredListContains(hm, victim)
    if before == nil then return false, "成员读取失败" end
    if before then return true, "原本存在" end
    -- A record whose objects are gone has nothing left to put back, whoever's unit it was. Kept, it would hold up every
    -- later cleanup and summon: an adopted summon is engaged before the arena registers it as its own.
    battle:remember("hatred:" .. hm:GetAddress() .. ":" .. victim:GetAddress(), function()
        if not engineValid(hm) or not engineValid(victim) then
            return true,"参赛对象有效性读回=false，目标已不存在；丢弃过期成员记录"
        end
        checked(hm); checked(victim)
        hm:RemoveActorFromHatredList(victim)
        local has = HatredListContains(hm, victim)
        return has == false, "成员读回=" .. tostring(has)
    end)
    local ok, err = pcall(function() hm:AddActorToHatredList(victim, false) end)
    local has = HatredListContains(hm, victim)
    -- 仅对本Mod创建的两名参赛者保留历史已观察到出招的数组配对路径。
    local ownA,ownB=false,false
    for _,actor in ipairs(arenaActors) do
        if safeValid(actor) then
            ownA=ownA or actor:GetAddress()==attacker:GetAddress()
            ownB=ownB or actor:GetAddress()==victim:GetAddress()
        end
    end
    -- A rider's mount carries the fight for its rider (mounts.lua).
    if mounts and mounts:holds(attacker) then ownA=true end
    if not has and ownA and ownB then
        local wrote=pcall(function()
            checked(hm); checked(victim)
            local list=hm.HatredList
            list[#list+1]=victim
        end)
        has=HatredListContains(hm,victim)
        log("参赛者配对数组写入=" .. tostring(wrote) .. "；成员读回=" .. tostring(has))
        return wrote and has==true,"参赛者数组配对（官方门禁尚未修复）"
    end
    log("官方Add调用=" .. tostring(ok) .. "；成员读回=" .. tostring(has))
    return ok and has == true, ok and (has and "官方Add读回存在" or "官方Add未接纳") or tostring(err)
end


-- ---------- 原生阵营系统 ----------
-- NPC 和玩家身上的 "Faction Component"（UFactionComponent）决定谁和谁是敌人，
-- 伤害、格挡、攻击开关等系统都引用它。SetFactionRelationOverride(对手, 关系, Both)
-- 可以针对单个对手覆盖敌我关系，Both=true 时双方同时生效。
-- ETeamAttitude: 0=Friendly 1=Neutral 2=Hostile

local ATTITUDE_NAME = { [0] = "友好", [1] = "中立", [2] = "敌对" }
local HOSTILE, NEUTRAL = 2, 1

local function GetFactionComp(pawn)
    if not safeValid(pawn) then return nil end
    local ok, fc = pcall(function() return pawn["Faction Component"] end)
    if ok and fc ~= nil then
        local okV, v = pcall(function() return fc:IsValid() end)
        if okV and v then return fc end
    end
    return nil
end

local function ReadRelation(a, b)
    if not safeValid(b) then return nil end
    local fc = GetFactionComp(a)
    if not fc then return nil end
    local ok, r = pcall(function() return fc:GetFactionRelation(b) end)
    if ok and type(r) == "number" then return r end
    return nil
end

local function RelationName(r)
    if r == nil then return "?" end
    return ATTITUDE_NAME[r] or tostring(r)
end

local function ReadFactionTag(pawn)
    local fc = GetFactionComp(pawn)
    if not fc then return "无阵营组件" end
    local ok, tag = pcall(function() return fc:GetCurrnetFaction() end)
    if not ok or tag == nil then return "?" end
    local okN, n = pcall(function() return FNameToString(tag.TagName) end)
    return okN and n or "?"
end

local function SetFactionRelation(a, b, relation)
    local fa, fb = GetFactionComp(a), GetFactionComp(b)
    if not fa or not fb then return false,nil,nil end
    local beforeA,beforeB = ReadRelation(a,b),ReadRelation(b,a)
    if beforeA == nil or beforeB == nil then return false,beforeA,nil end
    local function rememberOne(source,target,fc,original)
        battle:remember("relation:" .. source:GetAddress() .. ":" .. target:GetAddress(), function()
            if not engineValid(source) or not engineValid(target) or not engineValid(fc) then
                return true,"参赛对象有效性读回=false，目标已不存在；丢弃过期关系记录"
            end
            checked(source); checked(target); checked(fc)
            -- 停止擂台时仍开启的全局观战模式继续生效，不撤销它的单向中立关系。
            if spectator and spectator:status().enabled_requested then
                local player=GetPlayerPawn()
                if safeValid(player) and target:GetAddress()==player:GetAddress()
                    and source:GetAddress()~=player:GetAddress() then
                    fc:SetFactionRelationOverride(target,NEUTRAL,false)
                    local neutral=ReadRelation(source,target)
                    return neutral==NEUTRAL,"观战模式仍开启，保留单向中立；读回="..tostring(neutral)
                end
            end
            fc:ClearFactionRelationOverride(target)
            local actual=ReadRelation(source,target)
            return actual==original,"清除本轮覆盖；原关系=" .. tostring(original)
                .. "；读回=" .. tostring(actual) .. "；原覆盖结构未知"
        end)
    end
    rememberOne(a,b,fa,beforeA); rememberOne(b,a,fb,beforeB)
    local ok=pcall(function() fa:SetFactionRelationOverride(b,relation,true) end)
    local afterA,afterB=ReadRelation(a,b),ReadRelation(b,a)
    log(string.format("关系写入=%s；A %s→%s；B %s→%s",tostring(relation),tostring(beforeA),tostring(afterA),tostring(beforeB),tostring(afterB)))
    return ok and afterA==relation and afterB==relation,beforeA,afterA
end


local function GetASC(pawn)
    if not safeValid(pawn) then return nil end
    local ok, asc = pcall(function() return pawn.AbilitySystemComponent end)
    if ok and asc ~= nil then
        local okV, v = pcall(function() return asc:IsValid() end)
        if okV and v then return asc end
    end
    return nil
end

local aiLib = nil
local function GetAILib()
    if aiLib then
        local okV, v = pcall(function() return aiLib:IsValid() end)
        if okV and v then return aiLib end
    end
    for _, path in ipairs({
        "/SGameAI/BP_SGameAIFunctionLibrary.Default__BP_SGameAIFunctionLibrary_C",
        "/SGameAI/Utils/BP_SGameAIFunctionLibrary.Default__BP_SGameAIFunctionLibrary_C",
    }) do
        local ok, obj = pcall(StaticFindObject, path)
        if ok and obj ~= nil and pcall(function() return obj:IsValid() end) and obj:IsValid() then
            aiLib = obj
            return obj
        end
    end
    local ok, obj = pcall(FindObject, "BP_SGameAIFunctionLibrary_C",
        "Default__BP_SGameAIFunctionLibrary_C")
    if ok and obj ~= nil and pcall(function() return obj:IsValid() end) and obj:IsValid() then
        aiLib = obj
        return obj
    end
    return nil
end

-- 碰撞诊断：胶囊体和模型的碰撞是否开启、用的什么碰撞配置
-- ECollisionEnabled: 0=关 1=仅查询 2=仅物理 3=查询+物理
local function DescribeCollision(pawn)
    if not safeValid(pawn) then return "UNKNOWN(invalid pawn)" end
    local function comp(c)
        if c == nil then return "无" end
        local okV, v = pcall(function() return c:IsValid() end)
        if not okV or not v then return "无" end
        local en, prof = "?", "?"
        pcall(function() en = tostring(c:GetCollisionEnabled()) end)
        pcall(function() prof = FNameToString(c:GetCollisionProfileName()) end)
        return en .. "/" .. prof
    end
    local cap, mesh = nil, nil
    pcall(function() cap = pawn.CapsuleComponent end)
    pcall(function() mesh = pawn.Mesh end)
    return string.format("胶囊=%s 模型=%s", comp(cap), comp(mesh))
end

-- 延迟生成只负责拿到Actor；控制器登记所有权后才会调用FinishSpawn。
-- given: the catalog entry of a unit summoned along with the selected one (escorts.lua).
local function SpawnViaAILib(cls, t, world, given)
    if not safeValid(cls) or not safeValid(world) then return nil,"Class/World无效","not_started" end
    local className=objectName(cls)
    local classPath=className:match(" (/.+)$")
    local allowed,why=SpawnPolicy.check(classPath)
    if not allowed then return nil,why,"not_started" end
    -- A unit that writes story progress itself only once the story holds what it would write (story_writes.lua).
    local storyAllowed,storyWhy=arenaSupport.storyWrites:allowsUnit(classPath)
    if not storyAllowed then return nil,storyWhy,"not_started" end
    local entry=given or npcCatalog:selected()
    if not entry or entry.path~=classPath or type(entry.isNPC)~='boolean' then return nil,'实体类型未读回','not_started' end
    local npc=entry.isNPC
    local lib=npc and GetAILib() or StaticFindObject('/Script/Engine.Default__GameplayStatics')
    if not safeValid(lib) then return nil,'找不到函数库','not_started' end
    if not spawnAudit:record("spawn_deferred_begin",classPath,objectName(world)) then return nil,"阶段日志写入失败；未生成","not_started" end
    if not safeValid(cls) or not safeValid(lib) or not safeValid(world) then return nil,"生成前对象失效","not_started" end
    local pawn = nil
    local ok, err = pcall(function()
        if npc then pawn=lib:SpawnAIDefered(cls,t,nil,world)
        else pawn=lib:BeginDeferredActorSpawnFromClass(world,cls,t,1,nil,1) end
    end)
    spawnAudit:record("spawn_deferred_return",classPath,"call="..tostring(ok).." valid="..tostring(safeValid(pawn)))
    if not ok then return nil, "延迟生成接口报错，创建结果未知: " .. tostring(err),"uncertain" end
    local okV = safeValid(pawn)
    if not okV then return nil, "延迟生成接口未返回有效实例；创建结果未知","uncertain" end
    spawnRoutes[pawn]=npc and 'npc' or 'actor'
    log('生成路径读回='..spawnRoutes[pawn]..'；actor='..objectName(pawn))
    return pawn,nil,"created"
end

-- leader: the unit an escort comes with; the escort takes its level, as a map group shares its domain's.
local function FinishSpawnViaAILib(pawn,t,world,leader)
    if not summonActorLive(pawn) or not safeValid(world) then return false,"Actor/World无效或Actor正在销毁，保留清理记录" end
    local route=spawnRoutes[pawn]
    if route~='npc' and route~='actor' then return false,'生成路径未登记，保留清理记录' end
    if route=='npc' and arenaActivity then arenaActivity:prepare(pawn) end
    -- The app's chosen difficulty goes into this actor's own config slots before it initialises.
    if route=='npc' and spawnDifficulty then
        local applied=spawnDifficulty:prepare(pawn,objectName(pawn))
        -- Its AI asks for the difficulty while it initialises, so the hooks must be in place first.
        if applied and applied.applied and aiDifficulty then aiDifficulty:ensure(pawn,spawnDifficulty:levelOf(pawn)) end
    end
    -- Map NPCs get their Level from their spawner before they start; a summoned one gets it here.
    if route=='npc' and spawnLevel then
        local leveled,levelError=pcall(function()spawnLevel:prepare(pawn,objectName(pawn),leader)end)
        if not leveled then log('[SpawnLevel] 出生前失败: '..tostring(levelError)) end
    end
    -- A spot behind a wall comes back to this side of it (spawn_spot.lua).
    if route=='npc' and arenaSupport.spawnSpot then
        local cleared,clearError=pcall(function()arenaSupport.spawnSpot:clear(world,t)end)
        if not cleared then log('[SpawnSpot] 查墙失败: '..tostring(clearError)) end
    end
    -- A summon starts on the ground, not over it (on_ground.lua).
    local placedOnGround=route=='npc' and onGround and onGround:place(pawn,t,world) or nil
    -- A rider's script puts its mount where the rider's spawner stands, and a few bosses aim a move at their spawner;
    -- a summon gets one where it is summoned (mounts.lua).
    if route=='npc' and mounts then
        local placed,placeError=pcall(function()mounts:prepare(pawn,t,world)end)
        if not placed then log('[Mount] 出生前失败: '..tostring(placeError)) end
    end
    -- 冷荼's abilities find her arena by class; its markers go around her before she starts (boss_stages.lua).
    if route=='npc' and bossStages then
        local placed,placeError=pcall(function()bossStages:prepare(pawn,t,world)end)
        if not placed then log('[BossStage] 出生前失败: '..tostring(placeError)) end
    end
    local lib=route=='npc' and GetAILib() or StaticFindObject('/Script/Engine.Default__GameplayStatics')
    if not summonActorLive(pawn) or not safeValid(lib) or not safeValid(world) then
        return false,"FinishSpawn前对象失效或进入销毁，保留清理记录"
    end
    local name=objectName(pawn)
    local standalone
    if route=='npc' and not leader and arenaSupport.standaloneStoryUnits:matches(name) then
        local why
        standalone,why=arenaSupport.standaloneStoryUnits:prepare(pawn)
        if not standalone then return false,why end
    end
    if not spawnAudit:record("finish_spawn_begin",name,"所有权已登记；"..objectName(world)) then
        return false,"FinishSpawn阶段日志写入失败；未继续初始化"
    end
    if not safeValid(pawn) or not safeValid(lib) or not safeValid(world) then return false,"FinishSpawn前对象失效" end
    local ok2, err2 = pcall(function()
        if route=='npc' then lib:FinishSpawnAIDefered(pawn,t,world)
        else lib:FinishSpawningActor(pawn,t,1) end
    end)
    local live=summonActorLive(pawn)
    local audited=spawnAudit:record("finish_spawn_return",name,"call="..tostring(ok2).." live="..tostring(live))
    if not ok2 or not audited then return false,"FinishSpawn未确认: "..tostring(err2).."；保留对象供F4清理" end
    if not live then return false,"FinishSpawn 后对象进入销毁或状态不可读" end
    if standalone and not arenaSupport.standaloneStoryUnits:verify(standalone) then
        return false,'出场时的剧情查找未读回；保留对象供清理'
    end
    -- 冷荼 born under her old save ID (a checkpoint cleared for the save-repair button) moves to the mod's now.
    if route=='npc' and bossStages then
        local moved,moveError=pcall(function()bossStages:finished(pawn)end)
        if not moved then log('[BossStage] 出生后失败: '..tostring(moveError)) end
    end
    if not summonActorLive(pawn) then return false,"出生后对象进入销毁或状态不可读" end
    if onGround then onGround:settle(pawn,placedOnGround) end
    return summonActorLive(pawn),nil
end

-- 请求原生登场并读回可见状态；不移除游戏效果。
local function FinishEntrance(pawn)
    local lib=GetAILib()
    local world=UEHelpers.GetWorld()
    local live=summonActorLive(pawn)
    if not live or not safeValid(lib) or not safeValid(world) then return false,live end
    local name=objectName(pawn)
    if not spawnAudit:record("activate_begin",name,objectName(world)) then return false,live end
    local activated=pcall(function() lib:ActivateAI(pawn,world) end)
    live=summonActorLive(pawn)
    spawnAudit:record("activate_return",name,"call="..tostring(activated).." live="..tostring(live))
    if live then
        log(string.format("  登场处理: ActivateAI调用=%s（行为未验收） | %s",tostring(activated),DescribeCollision(pawn)))
    end
    return activated,live
end

-- ---------- 战况只读采样 ----------

local function GetHP(pawn)
    if not safeValid(pawn) then return nil end
    -- APBZCharacter.AttributeSetBase 已由本地头文件确认；优先直接读，避免每秒全局扫描。
    local okDirect, direct = pcall(function()
        local attributes = pawn.AttributeSetBase
        if not safeValid(attributes) then return nil end
        return attributes.Health.CurrentValue
    end)
    if okDirect and type(direct) == "number" then return direct end
    local hp = nil
    pcall(function()
        local ok, sets = pcall(FindAllOf, "BasicAttributeSet")
        if not ok or not sets then return end
        local pawnAddr = pawn:GetAddress()
        local ascAddr = nil
        pcall(function()
            local asc = pawn.AbilitySystemComponent
            if asc and asc:IsValid() then ascAddr = asc:GetAddress() end
        end)
        for _, s in ipairs(sets) do
            local okO, outer = pcall(function()
                if not safeValid(s) then return nil end
                return s:GetOuter()
            end)
            if okO and outer and outer:IsValid() then
                local oa = outer:GetAddress()
                if oa == pawnAddr or oa == ascAddr then
                    hp = s.Health.CurrentValue
                    return
                end
            end
        end
    end)
    return hp
end

local function StartDuelWatch(a,b)
    local token=battle:begin("两只NPC对照")
    attackProfile=AttackProfile.new({log=log,valid=safeValid})
    local ticks,handle=0,nil
    local function cancel()
        if handle then pcall(CancelDelayedAction,handle); handle=nil end
    end
    local function sample()
        if not battle:isCurrent(token) then cancel(); return end
        if not safeValid(a) or not safeValid(b) then
            log("对象失效，停止采样；无法据此判定死亡/胜负")
            battle:cancel("对象失效"); cancel(); return
        end
        ticks=ticks+1
        attackProfile:sample({a,b},"duel_sample_"..ticks,GetPlayerPawn())
        if ticks==1 or ticks==20 or ticks==80 then
            local ok,err=pcall(function()
                spawnInspector:combat(a,b,'tick'..ticks)
                spawnInspector:combat(b,a,'tick'..ticks)
            end)
            if not ok then log('[SpawnInspect] 战斗状态读取失败: '..tostring(err)) end
        end
        if ticks%8~=0 then return end
        local hpA,hpB=GetHP(a),GetHP(b)
        log(string.format("战况[%d] HP=%s/%s 关系=%s/%s；只读",ticks,tostring(hpA),tostring(hpB),RelationName(ReadRelation(a,b)),RelationName(ReadRelation(b,a))))
        if ticks>=240 or (hpA and hpA<=0) or (hpB and hpB<=0) then
            battle:cancel("采样结束；F4恢复当前账本"); cancel()
        end
    end
    handle=LoopInGameThreadWithDelay(250,sample)
end

-- A fighting unit's fallback target (arena_controller.lua hold_target): PBZ_TargetingHandler_AI, the AI's default
-- targeting handler, reads the blackboard key "Target Key" and, when that holds nothing, "LastSensedActorKey"; the
-- handler instance is the unit's own (Targeting Component.DefaultTargetHandler, its Blackboard set in Initialize).
-- Written only when it holds the player; never restored, perception overwrites it and the units are the mod's own.
local senseHold={written=0,cleared=0,failed=0,lines=0,summaryAt=nil}
local function HoldSensedTarget(actor,target,why)
    local handler=UEObserve.field(UEObserve.field(actor,'Targeting Component'),'DefaultTargetHandler')
    local bb=UEObserve.field(handler,'Blackboard')
    local key=UEObserve.field(handler,'LastSensedActorKey')
    if not safeValid(bb) or key==nil then return false end
    local okNow,current=pcall(function()return UEObserve.unwrap(bb:GetValueAsObject(key))end)
    if not okNow then return false end
    -- Only when it holds the player: anything else it holds is the game's own and is left alone.
    local wanted=safeValid(target) and target or nil
    local player=GetPlayerPawn()
    if not player or UEObserve.key(current)~=UEObserve.key(player) then return true end
    if wanted then pcall(function()bb:SetValueAsObject(key,wanted)end)
    else pcall(function()bb:ClearValue(key)end) end
    local _,after=pcall(function()return UEObserve.unwrap(bb:GetValueAsObject(key))end)
    local ok=wanted and UEObserve.key(after)==UEObserve.key(wanted) or (not wanted and not safeValid(after))
    if not ok then senseHold.failed=senseHold.failed+1 elseif wanted then senseHold.written=senseHold.written+1 else senseHold.cleared=senseHold.cleared+1 end
    local wasPlayer=player~=nil and UEObserve.key(current)==UEObserve.key(player)
    if senseHold.lines<12 or not ok then
        senseHold.lines=senseHold.lines+1
        log(string.format('[Arena] 锁定回退目标 %s 的 Last Sensed Actor：%s%s -> %s；读回=%s；%s',objectName(actor),
            safeValid(current) and objectName(current) or '空',wasPlayer and '（玩家）' or '',wanted and objectName(wanted) or '清空',
            safeValid(after) and objectName(after) or '空',tostring(why)))
    end
    local now=os.clock()
    senseHold.summaryAt=senseHold.summaryAt or now
    if now-senseHold.summaryAt>=30 then
        senseHold.summaryAt=now
        log(string.format('[Arena] 锁定回退目标累计：改成对手=%d 从玩家身上清空=%d 读回不符=%d',senseHold.written,senseHold.cleared,senseHold.failed))
    end
    return ok
end

local function ForceAttack(attacker, victim)
    if not safeValid(attacker) or not safeValid(victim) then return false end
    local okF = SetFactionRelation(attacker, victim, HOSTILE)
    local okH, how = AddHatred(attacker, victim)
    local sg = GetAIComp(attacker)
    local okForce = false
    if sg then okForce = pcall(function() sg:ForceIntoCombat(victim) end) end
    -- 只写实际绑定该控制器的黑板键，并保留原目标供F4恢复。
    if sg then pcall(function()
        local bb=sg.BlackboardComponent
        if not safeValid(bb) then return end
        local okHandlers,handlers=pcall(FindAllOf,"PBZ_TargetingHandler_AI_C")
        if not okHandlers or not handlers then return end
        for _,handler in ipairs(handlers) do
            if safeValid(handler) then
                local bound=handler.Blackboard
                if safeValid(bound) and bound:GetAddress()==bb:GetAddress() then
                    local key=handler["Target Key"]
                    local original=bb:GetValueAsObject(key)
                    local originalValid=safeValid(original)
                    battle:remember("blackboard:" .. bb:GetAddress() .. ":" .. FNameToString(key),function()
                        if not engineValid(bb) then
                            return true,"参赛黑板有效性读回=false，目标已不存在；丢弃过期记录"
                        end
                        checked(bb)
                        -- The old target is gone too: no target is the nearest there is to put back.
                        local back=originalValid and engineValid(original)
                        if back then bb:SetValueAsObject(key,original)
                        else bb:ClearValue(key) end
                        local actual=bb:GetValueAsObject(key)
                        local restored=back and safeValid(actual) and actual:GetAddress()==original:GetAddress()
                            or (not back and not safeValid(actual))
                        return restored,"目标读回=" .. objectName(actual)
                            .. ((originalValid and not back) and "；原目标已不存在，改为清空" or "")
                    end)
                    checked(victim)
                    bb:SetValueAsObject(key,victim)
                    log("参赛目标写入=" .. objectName(victim) .. "；黑板读回=" .. objectName(bb:GetValueAsObject(key)))
                    break
                end
            end
        end
    end) end
    local state = "UNKNOWN"
    if sg then pcall(function() state = FNameToString(sg.CurrentStateTag.TagName) end) end
    log("作战请求=" .. tostring(okForce) .. "；状态读回=" .. state
        .. "；仇恨=" .. tostring(okH) .. "/" .. tostring(how) .. "；实际出招待观察")
    return okF and okH and okForce
end

-- 不再调用通用ApplyDamage种仇恨；本版不执行假伤害或假死亡。

-- ---------- 扫描 ----------

local function CollectNPCs()
    local player = GetPlayerPawn()
    local playerAddr = player and player:GetAddress() or nil
    local result, seen = {}, {}
    for _, className in ipairs(Config.EnemyClasses) do
        local ok, found = pcall(FindAllOf, className)
        if ok and found then
            for _, pawn in ipairs(found) do
                if safeValid(pawn) then
                    local addr = pawn:GetAddress()
                    if addr ~= playerAddr and not seen[addr] and not IsExcluded(pawn) then
                        seen[addr] = true
                        table.insert(result, pawn)
                    end
                end
            end
        end
    end
    return result
end

-- ---------- 解剖：把最近一只怪的 AI 大脑结构写到文件（Shift+扫描键） ----------
-- 注意：UE4SS 对象的空指针链式调用会原生崩溃，pcall 拦不住，
-- 所以每一步都先取引用、IsValid 之后再往下走。

local function DumpBrain()
    ExecuteInGameThread(function()
        local player = GetPlayerPawn()
        local pLoc = player and GetLocation(player)
        local npcs = CollectNPCs()
        if pLoc then
            table.sort(npcs, function(a, b)
                local la, lb = GetLocation(a), GetLocation(b)
                if not la then return false end
                if not lb then return true end
                return DistSq(la, pLoc) < DistSq(lb, pLoc)
            end)
        end
        local target = nil
        for _, pawn in ipairs(npcs) do
            local ok, ctrl = pcall(function() return pawn.Controller end)
            if ok and safeValid(ctrl) then
                target = { pawn = pawn, ctrl = ctrl }
                break
            end
        end
        if not target then
            log("解剖失败：附近没有带可用控制器的怪")
            return
        end

        local lines = {}
        local function emit(s) table.insert(lines, s) end
        emit("== 解剖对象: " .. target.pawn:GetFullName())

        -- 把一个对象的类链（属性+函数）全部倒出来
        local function dumpClassChain(obj, label)
            emit("")
            emit("######## " .. label)
            if not safeValid(obj) then emit("UNKNOWN(invalid)"); return end
            local okCls, cls = pcall(function() return obj:GetClass() end)
            while okCls and safeValid(cls) do
                local okN, clsName = pcall(function() return cls:GetFullName() end)
                emit("")
                emit("==== " .. (okN and clsName or "?"))
                pcall(function()
                    cls:ForEachProperty(function(prop)
                        pcall(function() emit("  prop " .. prop:GetFullName()) end)
                    end)
                end)
                pcall(function()
                    cls:ForEachFunction(function(fn)
                        pcall(function() emit("  func " .. fn:GetFullName()) end)
                    end)
                end)
                local nxt = nil
                pcall(function() nxt = cls:GetSuperStruct() end)
                cls = nxt
                okCls = safeValid(cls)
            end
        end

        -- 1) 控制器 + 它的 SGameAI 组件 + 感知组件 + 怪物本体
        dumpClassChain(target.ctrl, "AIController")
        local okSG, sg = pcall(function() return target.ctrl.SGameAIComponent end)
        if okSG and safeValid(sg) then
            dumpClassChain(sg, "SGameAIComponent")
        end
        local okPC, perc = pcall(function() return target.ctrl.PerceptionComponent end)
        if okPC and safeValid(perc) then
            dumpClassChain(perc, "PerceptionComponent")
        end
        dumpClassChain(target.pawn, "Pawn 本体")

        -- 2) AI 黑板的键（"打谁"大概率藏在这里）
        local okBB, bb = pcall(function() return target.ctrl.Blackboard end)
        if okBB and safeValid(bb) then
            emit("")
            emit("==== Blackboard keys")
            local okData, data = pcall(function() return bb.DefaultBlackboardAsset end)
            if okData and safeValid(data) then
                pcall(function()
                    local keys = data.Keys
                    for i = 1, #keys do
                        pcall(function()
                            local entry = keys[i]
                            emit(string.format("  key [%d] %s", i,
                                tostring(entry.EntryName)))
                        end)
                    end
                end)
            else
                emit("  (DefaultBlackboardAsset 不可用)")
            end
        else
            emit("")
            emit("==== 无 Blackboard 组件")
        end

        local f, usedPath = nil, nil
        for _, path in ipairs({
            "ue4ss\\Mods\\PhantomGladiator\\brain_dump.txt",
            "ue4ss/Mods/PhantomGladiator/brain_dump.txt",
            "brain_dump.txt",
        }) do
            f = io.open(path, "w")
            if f then usedPath = path break end
        end
        if f then
            f:write(table.concat(lines, "\n"))
            f:close()
            log(string.format("解剖完成：%d 行已写入 %s（游戏 exe 目录下）", #lines, usedPath))
        else
            log("解剖完成但写文件失败，改打到日志（共 " .. #lines .. " 行）")
            for _, s in ipairs(lines) do print(s .. "\n") end
        end
    end)
end

-- ---------- 目标系统诊断（Shift+互殴键）：读出双方的目标类型标签 ----------

local function ReadTargetTypes(pawn, label)
    if not safeValid(pawn) then log(label .. " 目标类型=UNKNOWN(invalid)"); return end
    local ok, err = pcall(function()
        local out = {}
        pawn:GetTargetTypes(out)
        local names = {}
        for i = 1, #out do
            local tag = out[i]
            local okN, n = pcall(function() return FNameToString(tag.TagName) end)
            table.insert(names, okN and n or "?")
        end
        log(string.format("%s 可打类型 [%d 个]: %s", label, #out,
            table.concat(names, ", ")))
    end)
    if not ok then
        log(string.format("%s 读取目标类型失败: %s", label, tostring(err)))
    end
end

local function ReadActorTags(pawn, label)
    -- 已知本构建没有 GetOwnedGameplayTags 反射入口，不重复失败调用。
    log(label .. " 身份标签=UNKNOWN（GetOwnedGameplayTags非反射函数；不据此推断无标签）")
end

local function TargetDiag()
    ExecuteInGameThread(function()
        local player = GetPlayerPawn()
        if player then
            ReadTargetTypes(player, "玩家")
            ReadActorTags(player, "玩家")
        end
        local npcs = CollectNPCs()
        if player then
            log("玩家 阵营: " .. ReadFactionTag(player))
        end
        -- 附近每只 NPC 的阵营标签和它对玩家的关系（在原生 NPC 互打的场景按这个键，
        -- 能直接看到双方用的阵营）
        for i = 1, math.min(#npcs, 8) do
            local rel = player and RelationName(ReadRelation(npcs[i], player)) or "?"
            local okN, n = pcall(function()
                return objectName(npcs[i]):match("([%w_]+)$")
            end)
            log(string.format("  NPC[%d] %s 阵营=%s 对玩家=%s %s", i,
                okN and n or "?", ReadFactionTag(npcs[i]), rel,
                DescribeCollision(npcs[i])))
        end
        if #npcs >= 2 then
            log(string.format("  NPC[1]→NPC[2] 关系=%s",
                RelationName(ReadRelation(npcs[1], npcs[2]))))
        end
        if #npcs > 0 then
            ReadTargetTypes(npcs[1], "怪物")
            ReadActorTags(npcs[1], "怪物")
            -- 怪物的 TargetingComponent 挂了哪些 handler
            pcall(function()
                local tc = npcs[1]["Targeting Component"]
                if tc and tc:IsValid() then
                    local hs = tc.TargetingHandlers
                    for i = 1, #hs do
                        pcall(function()
                            local entry = hs[i]
                            log(string.format("  handler[%d] tag=%s", i,
                                FNameToString(entry.Tag.TagName)))
                        end)
                    end
                end
            end)
            -- 它的原生仇恨列表里现在有谁
            pcall(function()
                local hm = GetHatredComp(npcs[1])
                if hm then
                    local hl = hm.HatredList
                    log(string.format("  仇恨列表 %d 个:", #hl))
                    for i = 1, math.min(#hl, 5) do
                        pcall(function()
                            log("    " .. objectName(hl[i]))
                        end)
                    end
                else
                    log("  （没有仇恨组件）")
                end
            end)
            -- 它的感知里现在装着谁
            pcall(function()
                local ctrl = npcs[1].Controller
                if ctrl and ctrl:IsValid() then
                    local perc = ctrl.PerceptionComponent
                    if perc and perc:IsValid() then
                        local seen = {}
                        perc:GetPerceivedHostileActors(seen)
                        log(string.format("  感知到的敌对者 %d 个:", #seen))
                        for i = 1, math.min(#seen, 5) do
                            local okE, nameE = pcall(function()
                                local a = seen[i]
                                if safeValid(a) then return objectName(a) end
                                local okGet,resolved=pcall(function() return a:get() end)
                                return okGet and objectName(resolved) or "UNKNOWN"
                            end)
                            log("    " .. (okE and nameE or "?"))
                        end
                    end
                end
            end)
        end
    end)
end

-- ---------- 碰撞通道对照（Shift+决斗键）：玩家 vs 最近的怪 ----------
-- 每个碰撞组件输出：对象类型、碰撞开关、对 32 个通道的反应（0 忽略 1 重叠 2 阻挡）。
-- 怪物攻击检测线如果只扫"玩家受击框"那类通道，而怪物身上没有对应反应的组件，
-- 怪打怪就会打空——对照这张表能直接看出来。

local function DumpCollisionMatrix()
    ExecuteInGameThread(function()
        local primClass = StaticFindObject("/Script/Engine.PrimitiveComponent")
        if not primClass or not primClass:IsValid() then
            log("碰撞对照失败：找不到 PrimitiveComponent 类")
            return
        end
        local lines = {}
        local function emit(s) table.insert(lines, s) end
        -- K2_GetComponentsByClass 在本作返回空数组（实测），改为遍历几类碰撞相关组件，
        -- 按拥有者筛选；武器等挂件是独立 Actor，拥有者链再往上查一层
        local allComps = {}
        for _, cn in ipairs({ "ShapeComponent", "SkeletalMeshComponent", "StaticMeshComponent" }) do
            local ok, list = pcall(FindAllOf, cn)
            if ok and list then
                for _, c in ipairs(list) do table.insert(allComps, c) end
            end
        end
        local function ownedBy(c, actorAddr)
            local ok, hit = pcall(function()
                if not safeValid(c) then return false end
                local o = c:GetOwner()
                if not safeValid(o) then return false end
                if o:GetAddress() == actorAddr then return true end
                local o2 = o:GetOwner()
                return o2 ~= nil and o2:IsValid() and o2:GetAddress() == actorAddr
            end)
            return ok and hit
        end
        local function dumpActor(actor, label)
            if not safeValid(actor) then return end
            emit("######## " .. label .. " " .. actor:GetFullName())
            local actorAddr = actor:GetAddress()
            local comps = {}
            for _, c in ipairs(allComps) do
                if ownedBy(c, actorAddr) then table.insert(comps, c) end
            end
            emit(string.format("  （找到 %d 个碰撞相关组件，全局扫描 %d 个）", #comps, #allComps))
            for i = 1, #comps do
                pcall(function()
                    local c = comps[i]
                    if not c:IsValid() then return end
                    local name = c:GetFullName():match("([%w_]+)$") or "?"
                    pcall(function()
                        local o = c:GetOwner()
                        if not safeValid(o) then return end
                        if o:GetAddress() ~= actor:GetAddress() then
                            name = (o:GetFullName():match("([%w_]+)$") or "?") .. "." .. name
                        end
                    end)
                    local objType, enabled, prof = "?", "?", "?"
                    pcall(function() objType = tostring(c:GetCollisionObjectType()) end)
                    pcall(function() enabled = tostring(c:GetCollisionEnabled()) end)
                    pcall(function() prof = FNameToString(c:GetCollisionProfileName()) end)
                    local resp = {}
                    for ch = 0, 31 do
                        local r = "?"
                        pcall(function() r = tostring(c:GetCollisionResponseToChannel(ch)) end)
                        table.insert(resp, r)
                    end
                    emit(string.format("  %-40s 类型=%s 开关=%s 配置=%s", name, objType, enabled, prof))
                    emit("    通道0-31: " .. table.concat(resp, ""))
                end)
            end
        end
        local player = GetPlayerPawn()
        if player then dumpActor(player, "玩家") end
        local pLoc = player and GetLocation(player)
        local npcs = CollectNPCs()
        if pLoc then
            table.sort(npcs, function(a, b)
                local la, lb = GetLocation(a), GetLocation(b)
                if not la then return false end
                if not lb then return true end
                return DistSq(la, pLoc) < DistSq(lb, pLoc)
            end)
        end
        if npcs[1] then dumpActor(npcs[1], "怪物") end
        local f = io.open("collision_matrix.txt", "w")
        if f then
            f:write(table.concat(lines, "\n"))
            f:close()
            log(string.format("碰撞对照完成：%d 行已写入 collision_matrix.txt", #lines))
        else
            log("碰撞对照写文件失败")
        end
    end)
end

-- ---------- 慢动作 ----------

local function CycleSlowMo()
    ExecuteInGameThread(function()
        dilationIndex = dilationIndex % #Config.TimeDilationSteps + 1
        local target = Config.TimeDilationSteps[dilationIndex]
        local count = 0
        local ok, list = pcall(FindAllOf, "WorldSettings")
        if ok and list then
            for _, ws in ipairs(list) do
                if safeValid(ws) then
                    local okChange=battle:change("time:" .. ws:GetAddress(),
                        function() checked(ws); return ws.TimeDilation end,
                        function(value) checked(ws); ws.TimeDilation=value end,target,
                        function(a,b) return type(a)=="number" and math.abs(a-b)<0.0001 end)
                    if okChange then count=count+1 end
                end
            end
        end
        if count > 0 then
            log(string.format("时间流速: %.2fx（%d 个世界）", target, count))
        else
            log("设置 TimeDilation 失败")
        end
    end)
end

-- ---------- 自由镜头 ----------

-- Shipping 版的 DebugCameraController 没有自己的 CheatManager（被编译剔除），
-- 而原生退出流程恰恰依赖它：现场构造一个再调 DisableDebugCamera。实测有效。
local function ExitFreeCam(dcc)
    checked(dcc)
    local cm = dcc.CheatManager
    if not cm or not cm:IsValid() then
        local cmClass = StaticFindObject("/Script/Engine.CheatManager")
        if not cmClass or not cmClass:IsValid() then
            error("CheatManager class not found")
        end
        cm = StaticConstructObject(cmClass, dcc)
        if not cm or not cm:IsValid() then
            error("construct CheatManager failed")
        end
        dcc.CheatManager = cm
    end
    cm:DisableDebugCamera()
end

-- 找"当前真正掌权"的调试相机：每次进出都会生成新实例，旧的会残留，
-- 只有持有 UPlayer 的那个才是激活中的
local function FindActiveDebugCam()
    local ok, list = pcall(FindAllOf, "DebugCameraController")
    if not ok or not list then return nil end
    for _, dcc in ipairs(list) do
        local okP, active = pcall(function()
            return dcc:IsValid() and dcc.Player and dcc.Player:IsValid()
        end)
        if okP and active then return dcc end
    end
    return nil
end

local observerGuard=ObserverGuard.new({log=log,getSpectator=function()return spectator end})
local freeCamera=FreeCamera.new({path=Config.RuntimePath,log=log,getController=GetRealPlayerController,guard=observerGuard,
    getWorld=UEHelpers.GetWorld,moveSpeed=Config.FreeCamera.MoveSpeed,mouseSensitivity=Config.FreeCamera.MouseSensitivity,
    track=function()return arenaSupport.track end})
-- Real seconds less the time 时停 held the game: timers about units that cannot move meanwhile (a companion stuck
-- for 6 s is teleported) wait while it lasts.
local frozenSince,frozenTotal=nil,0
local function LiveSeconds()
    local now=os.clock()
    local frozen=freeCamera:isFrozen()
    if frozen and not frozenSince then frozenSince=now
    elseif not frozen and frozenSince then frozenTotal=frozenTotal+(now-frozenSince);frozenSince=nil end
    return (frozenSince or now)-frozenTotal
end

local function ToggleFreeCam()
    local dcc=FindActiveDebugCam()
    if dcc then local ok,why=pcall(ExitFreeCam,dcc);return {ok=ok,message=ok and '已退出原生调试镜头' or tostring(why),spawned_count=0}end
    local ok,result=pcall(function()return freeCamera:toggle()end)
    local confirmed=ok and result==true
    local protection=observerGuard:status()
    return {ok=confirmed,message=confirmed and (freeCamera:isActive() and (protection.health_verified and '自由观战已开启：无仇恨、隐身、无敌锁血；声音跟随镜头' or '自由观战已开启；锁血状态待确认，请查看面板保护状态') or '已退出自由观战并恢复')
        or ('相机操作未确认，可点击退出观战重试：'..tostring(result)),spawned_count=0}
end

local function ForceExitFreeCam()
    local ok,restored=pcall(function()return freeCamera:stop('面板/自定义退出键')end)
    local dcc=FindActiveDebugCam();local legacyOK=true
    if dcc then legacyOK=pcall(ExitFreeCam,dcc)end
    return {ok=ok and restored==true and legacyOK,message=ok and restored==true and legacyOK and '已退出自由观战并恢复原状态' or '退出恢复待确认，可再次点击退出观战',spawned_count=0}
end

-- ---------- 只读攻击追踪 ----------
local function LogProbeScene(label)
    local player=GetPlayerPawn()
    log("[Scene] " .. label .. " 玩家=" .. objectName(player) .. " HP=" .. tostring(GetHP(player)))
    local origin=player and GetLocation(player)
    local npcs=CollectNPCs()
    if origin then
        table.sort(npcs,function(a,b)
            local la,lb=GetLocation(a),GetLocation(b)
            return (la and DistSq(la,origin) or math.huge)<(lb and DistSq(lb,origin) or math.huge)
        end)
    end
    local subjects = {}
    if safeValid(player) then subjects[#subjects+1]=player end
    for i=1,math.min(#npcs,4) do
        local npc=npcs[i]
        subjects[#subjects+1]=npc
        log("[Scene] NPC=" .. objectName(npc) .. " HP=" .. tostring(GetHP(npc))
            .. " 阵营=" .. ReadFactionTag(npc) .. " 对玩家=" .. RelationName(ReadRelation(npc,player)))
    end
    return subjects
end
local healthSubjects = {}
probeFinished = function(state)
    probeSampleGen=probeSampleGen+1
    for _,entry in ipairs(healthSubjects) do
        local hp=GetHP(entry.actor)
        log("[HPWatch] 结束 " .. objectName(entry.actor) .. " start=" .. tostring(entry.initial)
            .. " final=" .. tostring(hp) .. " reason=" .. tostring(state.reason))
    end
    healthSubjects={}
end
local function StartHealthWatch(subjects,token)
    healthSubjects={}
    for _,actor in ipairs(subjects) do
        local hp=GetHP(actor)
        healthSubjects[#healthSubjects+1]={actor=actor,initial=hp,last=hp}
    end
    local ticks,lines,handle=0,0,nil
    local function cancel()
        if handle then pcall(CancelDelayedAction,handle); handle=nil end
    end
    local function sample()
        if token~=probeSampleGen or not probe:status().active then cancel(); return end
        ticks=ticks+1
        for _,entry in ipairs(healthSubjects) do
            local hp=GetHP(entry.actor)
            if hp~=entry.last and lines<40 then
                log("[HPWatch] sample="..ticks.." "..objectName(entry.actor)
                    .." HP="..tostring(entry.last).."→"..tostring(hp).."（只读，不据此判断伤害来源）")
                lines=lines+1
            end
            entry.last=hp
        end
        if ticks>=60 then cancel() end
    end
    handle=LoopInGameThreadWithDelay(1000,sample)
end
BeginArenaObservation=function(a,b)
    probe:stop("开始参赛者对照")
    local subjects={a,b}
    local player=GetPlayerPawn()
    if safeValid(player) then subjects[#subjects+1]=player end
    probeSampleGen=probeSampleGen+1
    if probe:start("arena_duel",subjects) then StartHealthWatch(subjects,probeSampleGen) end
end
local function ToggleProbe()
    ExecuteInGameThread(function()
        local state=probe:status()
        probeSampleGen=probeSampleGen+1
        if state.active or state.stopPending then
            probe:stop("F11手动结束"); LogProbeScene("结束"); return
        end
        local subjects=LogProbeScene("开始；只读阳性对照")
        local ok=probe:start("native_baseline",subjects)
        if not ok then return end
        local token=probeSampleGen
        StartHealthWatch(subjects,token)
        ExecuteInGameThreadWithDelay(60050,function()
            if token~=probeSampleGen then return end
            LogProbeScene("60秒窗口结束")
        end)
    end)
end
-- ---------- 单位控制器：按钮与快捷键共用，只有本Mod的参赛者受管理 ----------
local runtimeSession=RuntimeSession.new({valid=safeValid,getWorld=UEHelpers.GetWorld,
    getPlayer=GetPlayerPawn,isDestroying=actorIsDestroying,hp=GetHP})
local spectatorTargets=SpectatorTargets.new({log=log})
local spectatorExcluded={}
-- The player's side: companions (their adopted summons included) and anything carrying the player's faction tag.
-- No-aggro leaves these alone and never brings back the relation one had before it joined.
local sideKeys,sideAt={},-1
local function IsPlayerSide(npc)
    local now=os.clock()
    if now-sideAt>=0.5 or now<sideAt then
        sideAt,sideKeys=now,{}
        for _,member in ipairs(arena and arena:members() or {})do
            local key=member.team=='companion' and UEObserve.key(member.actor)
            if key then sideKeys[key]=true end
        end
    end
    local key=UEObserve.key(npc)
    if key and sideKeys[key] then return true end
    local tag=ReadFactionTag(npc)
    return tag~='?' and tag~='无阵营组件' and tag==ReadFactionTag(GetPlayerPawn())
end
spectator=SpectatorMode.new({log=log,valid=engineValid,getPlayer=GetPlayerPawn,path=Config.RuntimePath,
    isActorDestroying=actorIsDestroying,
    isObserverActive=function()return freeCamera:isActive()end,
    isPlayerSide=IsPlayerSide,
    releasePlayerTarget=function(npc,player)return spectatorTargets:release(npc,player)end,
    getNPCs=function()
        spectatorTargets:refresh()
        local out={}
        local world=UEHelpers.GetWorld()
        for _,npc in ipairs(CollectNPCs()) do
            if UEObserve.inWorld(npc,world) then
                local ok,destroying=pcall(function() checked(npc); return npc:IsActorBeingDestroyed() end)
                if not (ok and destroying==true) then out[#out+1]=npc end
            else
                local key=UEObserve.key(npc)
                if key and not spectatorExcluded[key] then
                    spectatorExcluded[key]=true;log('[Spectator] 跳过非当前世界对象：'..objectName(npc))
                end
            end
        end
        return out
    end})
arena=ArenaController.new({catalog=npcCatalog,log=log,valid=engineValid,name=objectName,now=GameSeconds,
    actorKey=function(actor) checked(actor);return actor:GetAddress() end,
    hp=function(actor) if spawnRoutes[actor]=='actor' then return nil end;return GetHP(actor) end,
    hasCombatHealth=function(actor) return spawnRoutes[actor]~='actor' end,
    canSpawn=SpawnPolicy.check,maxUnits=0,
    escortsFor=function(path)return Config.SummonEscorts and Escorts.of(path) or nil end,
    resolveEscort=function(path)return npcCatalog:resolvePath(path)end,
    spawnLimits=SpawnPolicy.limits,canBattle=SpawnPolicy.canBattle,
    spawnGuard=spawnGuard,
    combatReady=function(actor) return safeValid(actor) and spawnRoutes[actor]~='actor' and GetAIComp(actor)~=nil end,
    isStand=require('arena_stands').isStand,
    -- Kept in reserve by its summoner: hidden in game with its AI not started (冷荼's stand-by dolls show ai_state=None).
    dormant=function(actor)
        if UEObserve.field(actor,'bHidden')~=true then return false end
        local ai=GetAIComp(actor)
        if not ai then return true end
        local okTag,name=pcall(function()return FNameToString(ai.CurrentStateTag.TagName)end)
        return okTag and (name=='None' or name=='')
    end,
    untargetable=function(actor)return bossStages~=nil and bossStages:untargetable(actor)end,
    isStoryTeamActor=function(actor)
        return arenaSupport.standaloneStoryUnits:isTeamActor(actor)
    end,
    prepareStoryTeamActor=function(actor)
        return arenaSupport.standaloneStoryUnits:prepareTeamActor(actor)
    end,
    holdTarget=function(actor,target,why)
        if not arenaSupport.standaloneStoryUnits:assignOpponent(actor,target) then return false end
        return HoldSensedTarget(actor,target,why)
    end,
    releaseLock=function(actor,target)return arenaSupport.lockRelease~=nil and arenaSupport.lockRelease:release(actor,target)end,
    unstick=function(actor,target,classPath)
        return onGround~=nil and not (arenaSupport.lionNPC and arenaSupport.lionNPC:keepsMovement(actor,classPath))
            and onGround:free(actor,target)
    end,
    getPlayer=GetPlayerPawn,getWorld=UEHelpers.GetWorld,getLocation=GetLocation,
    getForward=function(actor) checked(actor); return actor:GetActorForwardVector() end,
    spawnClass=SpawnViaAILib,
    finishSpawn=FinishSpawnViaAILib,
    activate=function(actor,unitPath,team,escort)
        if spawnRoutes[actor]=='actor' then return safeValid(actor),'通用Actor初始化完成；未调用PBZ战斗AI，不保证具有血量或战斗能力' end
        -- A companion is never handed to no-aggro: up to v0.37.3 it was recorded here while still the enemy, and
        -- turning no-aggro off (leaving the free camera) set that back, so its attacks hit the player.
        if team~='companion' then spectator:applyTo(actor)
        elseif spectator:status().enabled_requested then
            log('[Spectator] 随从不交给无仇恨接管 unit='..objectName(actor)..' 召唤时对玩家关系='..RelationName(ReadRelation(actor,GetPlayerPawn()))
                ..'（v0.37.3 及以前会记下这个关系，关闭无仇恨时改回去）')
        end
        -- Companions get the official follow state, the player's faction and a friendly relation before their AI starts.
        if team=='companion' and companions then
            local prepared,prepareError=pcall(function()companions:prepare(actor,unitPath)end)
            if not prepared then log('[Companion] 准备失败: '..tostring(prepareError)) end
        end
        if arenaSupport.lionStage then
            local called,ready,reason=pcall(function()
                return arenaSupport.lionStage:prepare(actor,unitPath,UEHelpers.GetWorld(),escort)
            end)
            if not called or not ready then
                local detail=called and reason or tostring(ready)
                log('[LionStage] 场地准备失败 '..tostring(detail))
                local reasonText=tostring(detail or '烈焰舞狮场地准备失败')
                return false,reasonText,reasonText
            end
        end
        local spawnWarning
        if arenaSupport.phantom then
            local called,ok,reason=pcall(function()return arenaSupport.phantom:beforeActivate(actor,unitPath,escort)end)
            if not called or not ok then
                if not called then log('[Phantom] 虚空登场前处理失败：'..tostring(ok)) end
                spawnWarning=reason or '虚空常驻无敌解除未确认'
            end
        end
        if not summonActorLive(actor) then return false,'登场前对象已失效' end
        local activationRequested,live=FinishEntrance(actor)
        if not live then return false,"原生登场时对象进入销毁或状态不可读" end
        if spectator:status().enabled_requested then spectatorTargets:refresh(true) end
        if not summonActorLive(actor) then return false,"刷新观战目标时对象进入销毁或状态不可读" end
        if team~='companion' then spectator:applyTo(actor) end
        if not summonActorLive(actor) then return false,"应用观战关系后对象进入销毁或状态不可读" end
        local ai=GetAIComp(actor)
        local hp=GetHP(actor)
        log("召唤激活读回 ControllerAI="..tostring(ai~=nil).." HP="..tostring(hp))
        local verified,verifyError=pcall(function()spawnDifficulty:verify(actor,unitPath)end)
        if not verified then log('[SpawnDifficulty] 生成后读回失败: '..tostring(verifyError)) end
        -- What the level written before FinishSpawn changed, next to a map NPC of that level (read only),
        -- and how both units' numbers are built from their configs (stat_formula_probe.lua, read only).
        if activationRequested==true and spawnLevel then
            local reference
            local compared,compareError=pcall(function()reference=spawnLevel:verify(actor)end)
            if not compared then log('[SpawnLevel] 出生后读回失败: '..tostring(compareError)) end
            if statProbe then
                local game=spawnDifficulty and spawnDifficulty:status().game or nil
                if game=='' then game=nil end
                local probed,probeError=pcall(function()
                    statProbe:unit(actor,'召唤',spawnDifficulty and spawnDifficulty:levelOf(actor) or game)
                    if reference then statProbe:unit(reference,'地图怪',game) end
                end)
                if not probed then log('[StatFormula] 失败: '..tostring(probeError)) end
            end
        end
        if team=='companion' and companions then
            local checked,checkError=pcall(function()companions:afterActivate(actor,unitPath)end)
            if not checked then log('[Companion] 激活后读回失败: '..tostring(checkError)) end
        end
        -- Companions have a set of their own, separate from the arena's. An escort (a 驯犬客's 狂犬) takes the numbers the player
        -- set, but it is part of the unit it came with, not a contestant to be matched.
        if escort and team~='companion' and statMatch and statMatch.mode=='match' then
            log('[Escort] 随行单位不参与数值统一，保持自身数值 unit='..objectName(actor)..' HP='..tostring(hp))
        end
        local stats=team=='companion' and arenaSupport.companionStats or statMatch
        local combatReady=activationRequested==true and ai~=nil and type(hp)=='number' and hp>0
        if combatReady and escort then
            local wrote,why=pcall(function()stats:onSummon(actor,unitPath)end)
            if not wrote then log('[Escort] 数值未写入: '..tostring(why)) end
        end
        if combatReady and not escort then
            local result=stats:onSpawn(actor,unitPath)
            if not result.ok then
                if result.rollback_verified then return true,'初始化通过；数值统一失败已回滚',result.message..'；单位保留原生数值，可正常交战' end
                return false,'单位已生成；'..result.message..'；保留对象供清理'
            end
            -- An experiment: whatever it does, the summon stands.
            if fieldProbe and team~='companion' then
                local probed,probeError=pcall(function()fieldProbe:start(actor,unitPath)end)
                if not probed then log('[StatProbe] 启动失败: '..tostring(probeError)) end
            end
        end
        if activationRequested and safeValid(actor) then
            local inspected,inspectError=pcall(function() return spawnInspector:inspect(actor,UEHelpers.GetWorld()) end)
            if not inspected then log('[SpawnInspect] 只读检查失败: '..tostring(inspectError)) end
        end
        return combatReady,'仅确认初始化调用、AI组件和正HP；行为待验收',spawnWarning
    end,
    -- A unit's own summons take the custom numbers of its side (arena adoptSummon).
    summonAdopted=function(actor,unitPath,team)
        local stats=team=='companion' and arenaSupport.companionStats or statMatch
        return stats:onSummon(actor,unitPath)
    end,
    spawnOrigin=function(body,look,team,world)
        local watching=team~='companion' and freeCamera:status().active==true
        if watching and not spawnAudit:record("camera_spawn_origin_begin",team,"观战落点检测") then return body,look end
        local position,forward=arenaSupport.spawnSpot:origin(body,look,team,world)
        if watching then spawnAudit:record("camera_spawn_origin_return",team,"position="..tostring(position~=nil)) end
        return position,forward
    end,
    setRelation=SetFactionRelation,
    forceAttack=function(attacker,victim)
        if not arenaSupport.standaloneStoryUnits:assignOpponent(attacker,victim) then return false end
        local sent=ForceAttack(attacker,victim)
        if mounts then mounts:fight(attacker,victim) end
        return sent
    end,
    holdMount=function(rider,target)if mounts then mounts:hold(rider,target) end end,
    -- Whether the unit's AI state is combat (AI.State.Combat; Idle and Search are not), and its state name.
    inCombat=function(actor)
        local sg=GetAIComp(actor)
        if not sg then return nil end
        local ok,tag=pcall(function()return FNameToString(sg.CurrentStateTag.TagName)end)
        if not ok or type(tag)~='string' then return nil end
        return tag:find('Combat',1,true)~=nil,tag
    end,
    -- Sends a unit that left combat back at its opponent: hatred entry and ForceIntoCombat. The faction
    -- relation and blackboard target written by ForceAttack at the start still hold.
    engage=function(attacker,victim)
        if not arenaSupport.standaloneStoryUnits:assignOpponent(attacker,victim) then return false end
        return arenaSupport:engage(attacker,victim)
    end,
    prepareBattle=function(members)
        local prepared=arenaGrabs:sync(Config.EnableNPCGrabs and members or {},true,true)
        if prepared and arenaSupport.guillotine then arenaSupport.guillotine:prepare(members) end
        return prepared
    end,
    destroy=function(actor)
        checked(actor)
        if arenaSupport.lionNPC and not arenaSupport.lionNPC:releaseActor(actor) then error('下桩清理未读回') end
        if arenaSupport.lionStage then arenaSupport.lionStage:releaseActor(actor) end
        checked(actor); actor:K2_DestroyActor()
        if mounts then mounts:releaseActor(actor,'随单位清理') end
        if bossStages then bossStages:releaseActor(actor,'随 BOSS 清理') end
    end,
    isDestroying=actorIsDestroying,
    restore=function()
        probeSampleGen=probeSampleGen+1
        probe:stop("停止参赛者")
        local guillotineRestored=not arenaSupport.guillotine or arenaSupport.guillotine:stop()
        if arenaExecutions then arenaExecutions:stop('停止参赛者') end
        local polesRestored=not arenaSupport.lionNPC or arenaSupport.lionNPC:stop('停止并清理')
        if bossHUD then bossHUD:clear(true) end
        local grabRestored=not arenaGrabs or arenaGrabs:restore()
        local battleRestored=battle:reset("停止参赛者")
        return guillotineRestored and polesRestored and grabRestored and battleRestored
    end,
    onUnitsChanged=function(units)
        if statMatch then statMatch:roster(units) end
        if arenaSupport.standaloneStoryUnits then arenaSupport.standaloneStoryUnits:prune(units) end
        arenaActors={}
        local routes={}
        for _,entry in ipairs(units) do
            arenaActors[#arenaActors+1]=entry.actor
            routes[entry.actor]=spawnRoutes[entry.actor]
        end
        spawnRoutes=routes
    end,
    onBattleStarted=function(a,b)
        StartDuelWatch(a,b)
        BeginArenaObservation(a,b)
    end})

local summonLinks=SummonLinks.new({getWorld=UEHelpers.GetWorld,getNPCs=CollectNPCs,log=log})
arenaActivity=ArenaActivity.new({log=log,isNPC=function(actor)return spawnRoutes[actor]~='actor' end,
    freeCam=function()return freeCamera:isActive() or safeValid(FindActiveDebugCam()) end,
    context=function()
        local debugCamera=FindActiveDebugCam()
        local original=UEObserve.field(debugCamera,'OriginalControllerRef')
        local originalPawn=UEObserve.field(original,'Pawn')
        local world=UEHelpers.GetWorld()
        local level=UEObserve.field(world,'PersistentLevel')
        local settings=UEObserve.field(level,'WorldSettings')
        return 'mod_player='..tostring(UEObserve.key(GetPlayerPawn()))
            ..' debug_original_pawn='..tostring(UEObserve.key(originalPawn))
            ..' world_time='..tostring(UEObserve.field(settings,'TimeDilation'))
            ..' cinematic_time='..tostring(UEObserve.field(settings,'CinematicTimeDilation'))
    end})
local function GetMaxHP(actor)
    if not engineValid(actor) then return nil end
    local attributes=actor.AttributeSetBase
    if not engineValid(attributes) then return nil end
    return attributes.Health_Max.CurrentValue
end
bossHUD=BossHUD.new({getController=GetRealPlayerController,getWorld=UEHelpers.GetWorld,hp=GetHP,maxHP=GetMaxHP,
    codexPath=Config.RuntimePath..'/codex.tsv',log=log,
    extraBossName=function(unit)
        local story=arenaSupport.standaloneStoryUnits
        return story and story:teamBossName(unit.actor)
    end})
-- Companions show the game's own health bar above their heads, as enemies do (companion_bars.lua).
local companionBars=Config.ShowCompanionHealthBars and CompanionBars.new({log=log,hp=GetHP,maxHP=GetMaxHP}) or nil
-- One copy of the arena's members and status per support tick: a dozen modules ask for them, and each
-- call re-checks every unit with the engine (50 units made the support tick take 20-50 ms in v0.37.2).
-- Outside a tick the arena is asked directly.
local tickMembers,tickStatus
local function ArenaMembers()return tickMembers or arena:members() end
local function ArenaStatus()return tickStatus or arena:status() end
statMatch=StatMatch.new({path=Config.RuntimePath,log=log})
arenaSupport.companionStats=StatMatch.new({path=Config.RuntimePath,log=log,tag='[CompanionStats]',customOnly=true,
    settings='companion-stats-settings.tsv',request='companion-stats-request.tsv'})
spawnDifficulty=SpawnDifficulty.new({path=Config.RuntimePath,log=log,getWorld=UEHelpers.GetWorld,
    ready=function()return runtimeSession:status().game_ready==true end})
statProbe=Config.EnableStatFormulaProbe and StatFormulaProbe.new({log=log}) or nil
fieldProbe=Config.EnableStatFieldProbe and StatFieldProbe.new({log=log}) or nil
-- The game cycle (new game plus count): the game adds 25 levels per cycle to its own enemies (BP_RenewalNPC
-- "Init Level"). Read with the same library call, at most every 10 s, logged when it changes.
local cycleRead={}
local function GameCycle()
    local world=UEHelpers.GetWorld()
    local key=UEObserve.key(world)
    if not key then cycleRead={};return nil end
    local now=os.clock()
    if cycleRead.world==key and now-cycleRead.at<10 then return cycleRead.value end
    local library=StaticFindObject('/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary')
    if not safeValid(library) then return nil end
    local ok,value=pcall(function()return library:GetGameCycle(world)end)
    local cycle=ok and tonumber(UEObserve.unwrap(value)) or nil
    if cycleRead.world~=key or cycle~=cycleRead.value then
        log('[HomeLevels] 读游戏周目 调用='..tostring(ok)..' 读回='..tostring(cycle)..(ok and '' or ' 错误='..tostring(value)))
    end
    cycleRead={world=key,at=now,value=cycle}
    return cycle
end
-- Where a summon's level comes from: its home (default), the map enemies near the player, or one level (home_levels.lua).
local homeLevels=HomeLevels.new({log=log,path=Config.RuntimePath,
    context=function(actor)
        local slot=actor and spawnDifficulty and spawnDifficulty:levelOf(actor) or (spawnDifficulty and spawnDifficulty:status().game) or nil
        return {difficulty=slot~='' and slot or nil,cycle=GameCycle()}
    end,
    cycleExempt=function(actor)
        if not summonActorLive(actor) then return nil end
        local asc=UEObserve.field(actor,'AbilitySystemComponent')
        if not safeValid(asc) then return nil end
        local ok,value=pcall(function()return asc:GetGameplayTagCount({TagName=FName('CharacterState.NotUpgradeLevel')})end)
        local count=ok and tonumber(UEObserve.unwrap(value))
        if count then return count>0 end
    end})
spawnLevel=SpawnLevel.new({log=log,path=Config.RuntimePath,getPlayer=GetPlayerPawn,getLocation=GetLocation,collect=CollectNPCs,homeLevels=homeLevels,
    -- The loaded world's name (PBZ_Xigu_WP): spawner places and the remembered level are per world.
    getWorldName=function()
        local world=UEHelpers.GetWorld()
        if not safeValid(world) then return nil end
        local ok,name=pcall(function()return world:GetFName():ToString()end)
        return ok and type(name)=='string' and name or nil
    end,
    ours=function()
        -- A summoned rider's mount came out of a spawner too; it is the mod's, not a map enemy.
        local keys=mounts and mounts:keys() or {}
        for _,entry in ipairs(ArenaMembers())do local key=UEObserve.key(entry.actor);if key then keys[key]=true end end
        return keys
    end})
-- Riders: an empty spawner of the mod's where they are summoned, their mount found and cleared with them (mounts.lua).
mounts=Config.SummonRiderMounts and Mounts.new({log=log,location=GetLocation,isDestroying=actorIsDestroying,
    findClass=function(path)return StaticFindObject(path)end,statics=GetGameplayStatics,
    findAll=function(name)return FindAllOf(name)end,hp=GetHP,attack=ForceAttack,
    inCombat=function(actor)
        local sg=GetAIComp(actor)
        if not sg then return nil end
        local ok,tag=pcall(function()return FNameToString(sg.CurrentStateTag.TagName)end)
        if not ok or type(tag)~='string' then return nil end
        return tag:find('Combat',1,true)~=nil,tag
    end,
    engage=function(attacker,victim)return arenaSupport:engage(attacker,victim)end,
    destroy=function(actor)checked(actor);actor:K2_DestroyActor()end}) or nil
-- The ground under a spot: a visibility trace from 3 m over the summon height down 30 m; nil when it hits nothing.
-- The first few misses are logged with what the trace returned.
local groundMisses,groundRead=0,false
-- up: how far over z the trace starts (a unit's own body would stop one started over it).
local function GroundZ(world,x,y,z,up)
    local lib=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
    if not safeValid(lib) or not safeValid(world) then return nil end
    local out,none={},{R=0,G=0,B=0,A=0}
    local start,finish=z+(up or 300),z-3000
    local ok,hit=pcall(function()return lib:LineTraceSingle(world,{X=x,Y=y,Z=start},{X=x,Y=y,Z=finish},0,false,{},0,out,true,none,none,0)end)
    -- The table passed as OutHit comes back with the hit's own fields. bStartPenetrating reads true on every hit there
    -- (seen with Distance 183 and PenetrationDepth 0), so a start inside something is told by a Distance of 0. The trace
    -- goes straight down, so its Distance gives the height when the point does not read.
    local found,how
    local distance=ok and hit==true and UEObserve.unwrap(out.Distance)
    if ok and hit==true and not (type(distance)=='number' and distance<=0) then
        local okZ,impact=pcall(function()return out.ImpactPoint.Z end)
        local time=UEObserve.unwrap(out.Time)
        if okZ and type(impact)=='number' then found,how=impact,'ImpactPoint'
        elseif type(distance)=='number' then found,how=start-distance,'Distance'
        elseif type(time)=='number' then found,how=start+(finish-start)*time,'Time' end
        if found and (found>start+1 or found<finish-1) then found=nil end
    end
    if found then
        if not groundRead then
            groundRead=true
            log(string.format('[Ground] 地面检测读回 来源=%s Z=%.1f 起点Z=%.1f 距离=%s',how,found,start,tostring(out.Distance)))
        end
        return found
    end
    if ok and hit~=true then return nil end
    groundMisses=groundMisses+1
    if groundMisses<=3 then
        local keys={}
        for key in pairs(type(out)=='table' and out or {})do keys[#keys+1]=tostring(key) end
        log(string.format('[Ground] 地面检测没结果：调用=%s 返回=%s 输出字段=[%s] 命中点Z=%s%s',tostring(ok),tostring(hit),table.concat(keys,','),
            tostring(found),ok and '' or ' 错误='..tostring(hit)))
        local okDump,dump=pcall(function()
            local impact=out.ImpactPoint
            local parts={'ImpactPoint类型='..type(impact),'Distance='..tostring(out.Distance)..'('..type(out.Distance)..')','Time='..tostring(out.Time)..'('..type(out.Time)..')',
                'bStartPenetrating='..tostring(out.bStartPenetrating),'bBlockingHit='..tostring(out.bBlockingHit),'PenetrationDepth='..tostring(out.PenetrationDepth)}
            if type(impact)=='table' then
                local inner={}
                for key,value in pairs(impact)do inner[#inner+1]=tostring(key)..'='..tostring(value) end
                parts[#parts+1]='ImpactPoint内容=['..table.concat(inner,',')..']'
            end
            return table.concat(parts,' ')
        end)
        log('[Ground] 命中内容 起点Z='..tostring(start)..' '..tostring(dump))
    end
    -- The caller can tell a start inside something solid from nothing under the start.
    return nil,(type(distance)=='number' and distance<=0) and 'inside' or nil
end
onGround=require('on_ground').new({log=log,location=GetLocation,ground=GroundZ,label=objectName,player=GetPlayerPawn,world=function()return UEHelpers.GetWorld()end,
    anchor=function()return arenaSupport.spawnSpot and arenaSupport.spawnSpot:anchor() end,
    name=function(text)return FName(text)end})
-- A straight line through the world: where it hits and which way that surface faces, for the summon spot and the view.
-- Starting inside something solid reads as Distance 0.
-- channel: ETraceTypeQuery, 0 = visibility (the default), 1 = camera.
function arenaSupport:traceLine(world,from,to,channel)
    local lib=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
    if not safeValid(lib) or not safeValid(world) then return nil end
    local out,none={},{R=0,G=0,B=0,A=0}
    local query=channel==1 and 1 or 0
    local ok,hit=pcall(function()return lib:LineTraceSingle(world,from,to,query,false,{},0,out,true,none,none,0)end)
    if not ok or hit~=true then return nil end
    local distance=UEObserve.unwrap(out.Distance)
    if type(distance)=='number' and distance<=0 then return {inside=true} end
    local got,at=pcall(function()
        local point=out.ImpactPoint
        return {X=point.X,Y=point.Y,Z=point.Z}
    end)
    if not got or type(at.X)~='number' or type(at.Y)~='number' or type(at.Z)~='number' then
        local time=UEObserve.unwrap(out.Time)
        if type(time)~='number' then return nil end
        at={X=from.X+(to.X-from.X)*time,Y=from.Y+(to.Y-from.Y)*time,Z=from.Z+(to.Z-from.Z)*time}
    end
    local okNormal,normal=pcall(function()
        local face=out.ImpactNormal
        return {X=face.X,Y=face.Y,Z=face.Z}
    end)
    -- A skeleton answers with the bone it was hit on; a wall, the ground or a capsule with None.
    local okBone,bone=pcall(function()return out.BoneName:ToString() end)
    return {at=at,normal=okNormal and normal or nil,distance=distance,bone=okBone and type(bone)=='string' and bone~='None' and bone~='' and bone or nil}
end
arenaSupport.spawnSpot=require('spawn_spot').new({log=log,ground=GroundZ,view=function()return freeCamera:view() end,
    trace=function(world,from,to)return arenaSupport:traceLine(world,from,to) end})
-- 镜头跟踪: the free camera follows a unit and keeps its opponent in the picture (camera_track.lua).
arenaSupport.track=require('camera_track').new({log=log,path=Config.RuntimePath,members=ArenaMembers,hp=GetHP,location=GetLocation,player=GetPlayerPawn,
    view=function()return freeCamera:view() end,fov=function()return freeCamera:fieldOfView() end,
    trace=function(world,from,to,channel)return arenaSupport:traceLine(world,from,to,channel) end,
    isBoss=function(actor)
        local asc=UEObserve.field(actor,'AbilitySystemComponent')
        if not safeValid(asc) then return false end
        local ok,count=pcall(function()return asc:GetGameplayTagCount({TagName=FName('CharacterType.AI.Boss')})end)
        count=ok and UEObserve.unwrap(count) or 0
        return type(count)=='number' and count>0
    end,
    -- The arena's opponent for blue and red; a companion or a unit with no team: whoever its AI is after, unless that is the player.
    opponentOf=function(actor)
        local who=arena:opponentOf(UEObserve.key(actor))
        if safeValid(who) then return who end
        local board=UEObserve.field(GetAIComp(actor),'BlackboardComponent')
        if not safeValid(board) then return nil end
        local ok,value=pcall(function()return board:GetValueAsObject(FName('TargetActor'))end)
        value=ok and UEObserve.unwrap(value) or nil
        local player=GetPlayerPawn()
        if safeValid(value) and not (safeValid(player) and value:GetAddress()==player:GetAddress()) then return value end
    end})
arenaSupport.lionStage=require('lion_stage').new({log=log,location=GetLocation,player=GetPlayerPawn,
    world=UEHelpers.GetWorld,isDestroying=actorIsDestroying,hp=GetHP,now=GameSeconds,statics=GetGameplayStatics})
arenaSupport.lionNPC=require('lion_npc').new({log=log,location=GetLocation,ground=GroundZ,
    world=UEHelpers.GetWorld,isDestroying=actorIsDestroying,hp=GetHP,now=GameSeconds,statics=GetGameplayStatics,
    area=function(actor,world)return arenaSupport.lionStage:areaFor(actor,world)end,
    opponent=function(actor)return arena:opponentOf(UEObserve.key(actor))end,
    busy=function(actor)
        return arenaExecutions and (arenaExecutions:executing(actor) or arenaExecutions:guillotineHeld(actor)) or false
    end,
    carrier=function(actor)if mounts then return mounts:carrierOf(actor) end;return actor end,
    library=function()return StaticFindObject('/Script/ProjectPBZ.Default__PBZAbilityBlueprintLibrary')end,
    combat=require('lion_pole_combat').new({log=log,location=GetLocation,hp=GetHP,isDestroying=actorIsDestroying,
        pose=function(actor,clip,looping)if arenaExecutions then return arenaExecutions:borrowPolePose(actor,clip,looping) end end}),
    range=function(actor)
        local controller=UEObserve.field(GetAIComp(actor),'AIController')
        local library=StaticFindObject('/Script/SGameAI.Default__SGameAIFunctionLibrary')
        if not safeValid(library) or not safeValid(controller) then return nil end
        local ok,value=pcall(function()return library:FindFloatParameter(controller,FName('立回-近距离分界线'))end)
        return ok and type(value)=='number' and value>0 and value or nil
    end})
-- Staged bosses: the markers of their own arena placed around them, and their phase marks logged (boss_stages.lua).
bossStages=BossStages.new({log=log,location=GetLocation,isDestroying=actorIsDestroying,player=GetPlayerPawn,hp=GetHP,
    onUsed=function(actor)if playerAim then playerAim:lockAbilityOf(actor) end end,
    saveData=function(id)return arenaSupport:actorSaveData(id)end,
    -- The save-repair button asks for 冷荼's old checkpoint to be cleared (save_repair.lua).
    checkpoint={wants=function(id)return arenaSupport.saveRepair~=nil and arenaSupport.saveRepair:wantsCheckpoint(id)end,
        done=function(id,ok,read)if arenaSupport.saveRepair then arenaSupport.saveRepair:checkpointDone(id,ok,read) end end},
    findClass=function(path)return StaticFindObject(path)end,loadClass=function(path)return LoadAsset(path)end,
    statics=GetGameplayStatics,findAll=function(name)return FindAllOf(name)end,ground=GroundZ,
    -- How many actors of a targeting type are registered in this world (左殇's ground weapons, what CA_02 will find).
    targetsByTag=function(tag)
        local world=UEHelpers.GetWorld()
        local ok,sub=pcall(FindFirstOf,'TargetingWorldSubsystem')
        if not ok or not safeValid(sub) or not UEObserve.inWorld(sub,world) then return nil end
        local out={}
        local called=pcall(function()sub:GetTargetsByTag({TagName=FName(tag)},true,out)end)
        local list=called and UEObserve.array(out.OutTargets) or nil
        return list and #list or nil
    end,
    tagCount=function(actor,tag)
        local asc=UEObserve.field(actor,'AbilitySystemComponent')
        if not safeValid(asc) then return nil end
        local ok,n=pcall(function()return asc:GetGameplayTagCount({TagName=FName(tag)})end)
        return ok and type(n)=='number' and n or nil
    end,
    destroy=function(actor)checked(actor);actor:K2_DestroyActor()end})
local grabStudy=Config.EnableGrabStudy and GrabStudy.new({path=Config.RuntimePath,log=log,ready=function()return runtimeSession:status().game_ready==true end}) or nil
arenaGrabs=ArenaGrabs.new({path=Config.RuntimePath,log=log,hp=GetHP,ready=function()return runtimeSession:status().game_ready==true end})
-- Sends a unit that left combat back at its opponent: hatred entry and ForceIntoCombat. The faction
-- relation and blackboard target written by ForceAttack at the start still hold.
function arenaSupport:engage(attacker,victim)
    local sg=GetAIComp(attacker)
    if not sg or not safeValid(victim) then return false,'AI组件或目标无效' end
    local hm=GetHatredComp(attacker)
    local hatred='?';pcall(function()hatred=#hm.HatredList end)
    AddHatred(attacker,victim)
    local ok=pcall(function()sg:ForceIntoCombat(victim)end)
    local state='?';pcall(function()state=FNameToString(sg.CurrentStateTag.TagName)end)
    local a,b=GetLocation(attacker),GetLocation(victim)
    local d=a and b and math.sqrt(DistSq(a,b))/100
    return ok,state,'迎敌前仇恨数='..tostring(hatred)..' 距目标='..(d and string.format('%.1fm',d) or '?')
end
-- A summon sent to fight its own summoner's side (opposing: SummonCombatTargetMode EncounterSummons or Summoner, its
-- faction set to the player's) is the player's help in that story fight: 冷荼's 彭猛, 峨眉/华山, 风雪刀客, 舞狮 and
-- 雷当, 梦华's 虚空. In the arena it is taken out as it comes; true once it is gone or going.
function arenaSupport:removeHelper(link)
    local actor=link.actor
    if not safeValid(actor) then return true end
    local name=objectName(actor)
    local called,callError=pcall(function()actor:K2_DestroyActor()end)
    local okRead,going=pcall(actorIsDestroying,actor)
    local gone=not safeValid(actor) or (okRead and going==true)
    if gone then self.helpersRemoved=(self.helpersRemoved or 0)+1 end
    self.helperLines=(self.helperLines or 0)+1
    if self.helperLines<=30 then
        log(string.format('[SummonLinks] 移除剧情帮手 %s（召唤者 %s；%s；原版是来帮玩家打召唤者的）调用=%s%s 读回 正在销毁=%s 累计=%d',
            name,objectName(link.parent),tostring(link.evidence and link.evidence:match('SummonCombatTargetMode=[%w_]+') or '?'),tostring(called),
            called and '' or '('..tostring(callError)..')',tostring(gone),self.helpersRemoved or 0))
    end
    return gone
end
function arenaSupport:discover()
    for _,link in ipairs(summonLinks:scan(ArenaMembers(),function(ability)self.summonKeep:passive(ability)end)) do
        if not (link.opposing and self:removeHelper(link)) then
            -- A summon's own summon that writes story progress: its summoner was let in only with the story holding
            -- that already; logged once here if not (story_writes.lua says it once per class).
            if self.storyWrites then self.storyWrites:allowsUnit(link.class_path) end
            -- A helper that could not be taken out joins the team it fights for (arena_controller.lua aid).
            local result=arena:adoptSummon(link.actor,link.parent,link.class_path,link.evidence,link.opposing and 'opposing' or nil)
            if not result.ok then log('[SummonLinks] 接管未确认：'..tostring(result.message)) end
        end
    end
end
arenaSupport.stands=require('arena_stands').new({log=log,members=ArenaMembers,aiOf=GetAIComp})
function arenaSupport:cameraAt()
    local lib,world=GetGameplayStatics(),UEHelpers.GetWorld()
    if not safeValid(lib) or not safeValid(world) then return nil end
    local ok,manager=pcall(function()return lib:GetPlayerCameraManager(world,0)end)
    if not ok or not safeValid(manager) then return nil end
    local okLocation,location=pcall(function()return manager:GetCameraLocation()end)
    return okLocation and location or nil
end
arenaSupport.standKeep=require('stand_keep').new({log=log,members=ArenaMembers,clock=LiveSeconds,location=GetLocation,ground=onGround,label=objectName,
    camera=function()return arenaSupport:cameraAt() end})
-- The loaded world's subsystem of a class (its outer chain reaches the world; the class default object's does not), kept per world.
arenaSupport.subsystems={}
function arenaSupport:worldSubsystem(name)
    local world=UEHelpers.GetWorld()
    local worldKey=safeValid(world) and UEObserve.key(world)
    if not worldKey then return nil end
    local kept=self.subsystems[name]
    if kept and kept.world==worldKey and safeValid(kept.object) then return kept.object end
    self.subsystems[name]=nil
    local ok,list=pcall(FindAllOf,name)
    if not ok or type(list)~='table' then return nil end
    for _,object in ipairs(list)do
        if safeValid(object) and UEObserve.inWorld(object,world) then
            self.subsystems[name]={world=worldKey,object=object}
            return object
        end
    end
end
-- A summoned phase-one 雷当 must not write the story's 雷当-killed tag, and a save that already has it does not keep phase one's spawner on (story_guard.lua).
arenaSupport.storyGuard=require('story_guard').new({log=log,members=ArenaMembers,clock=LiveSeconds,label=objectName,
    tagCount=function(actor,tag)return onGround:tagCount(actor,tag)end,
    aiSubsystem=function()return arenaSupport:worldSubsystem('SGameAIWorldSubsystem')end,
    pipeline=function()return arenaSupport:worldSubsystem('EventPipelineManager')end})
-- Finishers and units that write story progress (story_writes.lua) and the fifth 龙柱 trial's ending (longzhu_check.lua).
arenaSupport.storyWrites=require('story_writes').new({log=log,clock=LiveSeconds,
    pipeline=function()return arenaSupport:worldSubsystem('EventPipelineManager')end})
arenaSupport.longzhu=require('longzhu_check').new({log=log,clock=LiveSeconds,
    pipeline=function()return arenaSupport:worldSubsystem('EventPipelineManager')end})
-- Whether the save holds an entry under this actor ID (PBZLevelActorManager): true, false, or nil when unread.
function arenaSupport:actorSaveData(id)
    local manager=self:worldSubsystem('PBZLevelActorManager')
    if not safeValid(manager) then return nil end
    local ok,value=pcall(function()return manager:HasSaveDataByActorID(FName(id))end)
    if ok then value=UEObserve.unwrap(value) else value=nil end
    if type(value)=='boolean' then return value end
    return nil
end
-- The app's save-repair button (save_repair.lua): arms the repairs above and 冷荼's, and reports what it found.
arenaSupport.saveRepair=require('save_repair').new({log=log,longzhu=arenaSupport.longzhu,guard=arenaSupport.storyGuard,
    has=function(text)return arenaSupport.storyWrites:has(text)end,
    pipeline=function()return arenaSupport:worldSubsystem('EventPipelineManager')end,
    hasSaveData=function(id)return arenaSupport:actorSaveData(id)end})
arenaSupport.summonKeep=require('summon_keep').new({log=log,members=ArenaMembers,aiOf=GetAIComp})
-- A fighter locked on a boss the game keeps out of reach is moved to its opponent (lock_release.lua).
arenaSupport.lockRelease=require('lock_release').new({log=log,
    untargetable=function(actor)return bossStages~=nil and bossStages:untargetable(actor)end})
companions=Companion.new({log=log,busy=function(actor)return arenaExecutions and arenaExecutions:executing(actor) or false end,getPlayer=GetPlayerPawn,getWorld=UEHelpers.GetWorld,aiLib=GetAILib,getLocation=GetLocation,hp=GetHP,
    members=ArenaMembers,clock=LiveSeconds})
-- Read-only: which of a companion's attacks may hit the player, and why (companion_hit_probe.lua).
companionHitProbe=Config.EnableCompanionHitProbe and CompanionHitProbe.new({log=log,getPlayer=GetPlayerPawn,hp=GetHP,location=GetLocation,
    members=ArenaMembers,factionSubsystem=function()local ok,found=pcall(FindFirstOf,'FactionSubSystem');return ok and found or nil end}) or nil
-- Read-only: every loaded attack that can reach the attacker's own allies (attack_faction_scan.lua).
attackScan=Config.EnableAttackFactionScan and AttackFactionScan.new({log=log,path=Config.RuntimePath,
    ready=function()return runtimeSession:status().game_ready==true end}) or nil
-- Experiment: save a few codex pictures as PNG on this PC (codex_art_probe.lua).
codexArt=Config.EnableCodexArtProbe and CodexArtProbe.new({log=log,path=Config.RuntimePath,getWorld=UEHelpers.GetWorld,
    ready=function()return runtimeSession:status().game_ready==true end}) or nil
-- The codex busts for the app's unit cards, saved on this PC from the player's own game (codex_icons.lua).
codexIcons=Config.EnableCodexIcons and CodexIcons.new({log=log,path=Config.RuntimePath,getWorld=UEHelpers.GetWorld,
    ready=function()return runtimeSession:status().game_ready==true end}) or nil
-- Units summoned at a chosen difficulty also get that difficulty when their AI asks for it.
aiDifficulty=AIDifficulty.new({log=log,getWorld=UEHelpers.GetWorld,
    ready=function()return runtimeSession:status().game_ready==true end,members=ArenaMembers,
    levelOf=function(actor)return spawnDifficulty:levelOf(actor)end})
-- Infinite Shachi and auto deflect/dodge for the player only; paused while the free camera observes.
funFeatures=FunFeatures.new({log=log,path=Config.RuntimePath,getPlayer=GetPlayerPawn,getController=GetRealPlayerController,
    members=ArenaMembers,
    ready=function()return runtimeSession:status().game_ready==true end,paused=function()return freeCamera:isActive()end})
-- 不倒下: units of a switched-on team keep a health floor; after a reload the journal frees the old ones.
immortalTeams=ImmortalTeams.new({log=log,path=Config.RuntimePath,members=ArenaMembers,collect=CollectNPCs,hp=GetHP,
    ready=function()return runtimeSession:status().game_ready==true end})
-- The fight time at the top centre of the game screen, when switched on in the app (battle_clock_hud.lua).
clockHUD=BattleClockHUD.new({log=log,path=Config.RuntimePath,getController=GetRealPlayerController,getWorld=UEHelpers.GetWorld,
    getPlayer=GetPlayerPawn,ready=function()return runtimeSession:status().game_ready==true end,
    clock=function()local s=ArenaStatus();return s.battle_clock,s.battle_seconds end})
-- 不死不休: while a fight runs, blue and red do not leave combat after an action and may hate each
-- other through the game's own hatred checks (combat_lock.lua).
combatLock=CombatLock.new({log=log,members=ArenaMembers,aiOf=GetAIComp,hatredOf=GetHatredComp,hp=GetHP,label=objectName,
    hates=HatredListContains,vehicles=function(members)return mounts and mounts:vehicles(members) or {} end,
    -- Called inside the game's transition; the send-back runs on the next game-thread tick instead.
    onDropped=function(key)ExecuteInGameThread(function()if not (mounts and mounts:dropped(key)) then arena:reengage(key) end end)end,
    onSensed=function(key)ExecuteInGameThread(function()arena:holdSensed(key)end)end,
    fighting=function()local s=ArenaStatus();return s.battle_active==true and s.blue_count>0 and s.red_count>0 end})
-- 招式锁玩家（二）: while a fight runs, a skill of a blue or red unit that asks GameplayStatics for the player gets the
-- unit's opponent instead; executions keep the player (player_aim.lua).
fightWatch=require('fight_watch').new({log=log,members=ArenaMembers,location=GetLocation,hp=GetHP,
    camera=function()return arenaSupport:cameraAt() end,
    read=function(actor)
        local ai=GetAIComp(actor)
        local state
        if ai then pcall(function()state=FNameToString(ai.CurrentStateTag.TagName)end) end
        return {mode=(onGround:mode(actor)),hidden=UEObserve.field(actor,'bHidden')==true,state=state,blocked=onGround:blocked(actor)}
    end,
    scripts=function(actor)
        local ai=GetAIComp(actor)
        return ai and UEObserve.array(UEObserve.field(ai,'SpawnedAIScripts')) or nil
    end})
playerAim=require('player_aim').new({log=log,members=ArenaMembers,statics=GetGameplayStatics,world=function()return UEHelpers.GetWorld() end,
    abilityTargets=function()return StaticFindObject('/Script/PBZAbilityTargetRuntime.Default__PBZPlayerAbilityTargetLibrary')end,
    player=GetPlayerPawn,
    opponentOf=function(key)return arena:opponentOf(key)end,actorOf=function(key)return arena:actorOf(key)end,
    paused=function()return arenaExecutions and arenaExecutions:status().active==true or false end,
    fighting=function()local s=ArenaStatus();return s.battle_active==true and s.blue_count>0 and s.red_count>0 end})
-- AI 行为参数: the panel's values for the AI's named parameters (ai_params.lua).
bossCombos=require('boss_combos').new({path=Config.RuntimePath,log=log,members=ArenaMembers,
    fighting=function()local s=ArenaStatus();return s.battle_active==true and s.blue_count>0 and s.red_count>0 end})
aiParams=require('ai_params').new({path=Config.RuntimePath,log=log,members=ArenaMembers,aiComp=GetAIComp,
    tension=function()return StaticFindObject('/Script/TensionMeter.Default__TensionLibrary'),UEHelpers.GetWorld() end})
-- 怪对怪处决（实验）: a boss stuck on its health lock is executed by the nearest enemy with the game's own pair of
-- abilities; the enemy borrows the player's skeleton for its half (arena_executions.lua).
-- 处决镜头: the app switch; during an execution the view plays that execution's own camera (execution_camera.lua).
executionCamera=ExecutionCamera.new({log=log,path=Config.RuntimePath,getController=GetRealPlayerController,
    getWorld=UEHelpers.GetWorld,getPlayer=GetPlayerPawn,freeCamera=freeCamera})
arenaSupport.companionExecutions=require('companion_executions').new({log=log,path=Config.RuntimePath})
-- What a unit's card says (unit_rules.lua), and 琴女's 虚化, which nothing an NPC does can break (phantom_break.lua).
arenaSupport.unitRules=require('unit_rules').new({log=log,path=Config.RuntimePath})
arenaSupport.phantom=require('phantom_break').new({log=log,members=ArenaMembers,rule=function(actor)return arenaSupport.unitRules:get(actor,'phantom') end})
-- Read only: what a monster's grab did to the unit it hit (grab_probe.lua).
arenaSupport.grabProbe=Config.EnableGrabProbe and require('grab_probe').new({log=log,members=ArenaMembers,location=GetLocation,
    isPlayer=function(actor)
        local player=GetPlayerPawn()
        return safeValid(player) and safeValid(actor) and player:GetAddress()==actor:GetAddress()
    end}) or nil
arenaExecutions=Config.EnableArenaExecutions and ArenaExecutions.new({log=log,members=ArenaMembers,now=GameSeconds,
    companions=function()return arenaSupport.companionExecutions.on end,isStand=require('arena_stands').isStand,
    killOnLock=function(actor)return arenaSupport.unitRules:get(actor,'lock')=='kill' end,
    getPlayer=GetPlayerPawn,getWorld=UEHelpers.GetWorld,getLocation=GetLocation,camera=executionCamera,
    onPole=function(actor)return arenaSupport.lionNPC:holds(actor)end,
    lionPickup=function(actor,victim)return arenaSupport.lionNPC:beginPickup(actor,victim,ArenaMembers(),ArenaStatus())end,
    lionPickupReady=function(actor)return arenaSupport.lionNPC:pickupReady(actor)end,
    lionPickupEnded=function(actor)arenaSupport.lionNPC:pickupEnded(actor)end,
    fighting=function()local s=ArenaStatus();return s.battle_active==true and s.blue_count>0 and s.red_count>0 end,
    storyAllows=function(ability)return arenaSupport.storyWrites:allows(ability)end,
    isImmortal=function(team)return immortalTeams.on[team]==true end}) or nil
arenaSupport.guillotine=Config.EnableNPCGrabs and require('arena_guillotine').new({log=log,live=summonActorLive,
    opponentOf=function(key)return arena:opponentOf(key)end,
    session=function()return runtimeSession:status()end,now=GameSeconds,
    playGrab=function(actor,stillValid)
        if not arenaExecutions then return false,'借用骨架模块已关闭' end
        return arenaExecutions:startGuillotineHold(actor,stillValid)
    end,
    grabHeld=function(actor)
        if not arenaExecutions then return false end
        return arenaExecutions:guillotineHeld(actor)
    end,
    finishGrab=function(actor)
        if not arenaExecutions then return false end
        return arenaExecutions:finishGuillotineHold(actor)
    end,
    stopGrab=function(why,actor)
        if not arenaExecutions then return true end
        return arenaExecutions:stopGrabPose(why,actor)
    end,
    isImmortal=function(team)return immortalTeams.on[team]==true end}) or nil
arenaSupport.standaloneStoryUnits=require('standalone_story_units').new({log=log,statics=GetGameplayStatics,
    boardOf=function(actor)return UEObserve.field(GetAIComp(actor),'BlackboardComponent')end,
    remember=function(key,restore)return battle:remember(key,restore)end,
    live=summonActorLive,isDestroying=actorIsDestroying})
-- A support tick slower than this is logged with the time of each step, to find the source of stutter (60 a session);
-- every minute a summary of all ticks and their costliest steps (perf_meter.lua) keeps coming after that.
local SLOW_TICK_MS,slowTicks=10,0
local supportMeter=require('perf_meter').new({label='支持循环',log=log,slow=SLOW_TICK_MS,hitch=1000})
local function supportSteps(self)
    local started,parts,costs=os.clock(),{},{}
    local function step(name,fn)
        local t=os.clock();fn()
        local spent=(os.clock()-t)*1000
        parts[#parts+1]=string.format('%s=%.1f',name,spent);costs[name]=spent
    end
    step('prune',function()
        local memberKeys={}
        for _,entry in ipairs(tickMembers)do local key=UEObserve.key(entry.actor);if key then memberKeys[key]=true end end
        spawnDifficulty:prune(memberKeys)
    end)
    step('aiDifficulty',function()aiDifficulty:tick()end)
    step('companions',function()companions:tick()end)
    step('fun',function()funFeatures:tick()end)
    step('freeCamera',function()freeCamera:recover()end)
    if grabStudy then step('grabStudy',function()grabStudy:tick()end) end
    if fieldProbe then step('fieldProbe',function()fieldProbe:tick()end) end
    if companionHitProbe then step('companionHit',function()companionHitProbe:tick()end) end
    if attackScan then step('attackScan',function()attackScan:tick()end) end
    if codexArt then step('codexArt',function()codexArt:tick()end) end
    if codexIcons then step('codexIcons',function()codexIcons:tick()end) end
    step('summonKeep',function()self.summonKeep:tick()end)
    step('phantom',function()self.phantom:tick()end)
    if self.grabProbe then step('grabProbe',function()self.grabProbe:tick()end) end
    step('summonLinks',function()self:discover()end)
    step('stands',function()self.stands:tick()end)
    step('standKeep',function()self.standKeep:tick()end)
    step('storyGuard',function()self.storyGuard:tick()end)
    step('longzhu',function()self.longzhu:tick()end)
    if mounts then step('mounts',function()mounts:tick()end) end
    if bossStages then step('bossStages',function()bossStages:tick()end) end
    -- Before reinforcements: a unit joining an immortal team is locked before it is sent at the enemy.
    step('immortal',function()immortalTeams:tick()end)
    step('activity',function()arenaActivity:sync(tickMembers)end)
    step('grabs',function()arenaGrabs:sync(Config.EnableNPCGrabs and tickMembers or {},tickStatus.battle_active)end)
    step('combatLock',function()combatLock:tick()end)
    step('playerAim',function()playerAim:tick()end)
    step('aiParams',function()aiParams:tick()end)
    step('bossCombos',function()bossCombos:tick()end)
    step('fightWatch',function()fightWatch:tick()end)
    step('reinforce',function()arena:tickReinforcements()end)
    if self.guillotine then step('guillotine',function()self.guillotine:tick(tickMembers,tickStatus)end) end
    if arenaExecutions then step('executions',function()arenaExecutions:tick()end) end
    step('lionNPC',function()self.lionNPC:tick(tickMembers,tickStatus)end)
    if self.lionStage then step('lionStage',function()self.lionStage:tick()end) end
    step('executionCamera',function()executionCamera:sweep()end)
    step('bossHUD',function()
        local state=tickStatus.state
        if state=='cleanup_pending' or state=='restore_pending' or state=='spawn_uncertain' then bossHUD:clear()
        else bossHUD:sync(tickMembers) end
    end)
    step('clockHUD',function()clockHUD:tick()end)
    if companionBars then step('companionBars',function()companionBars:sync(tickMembers)end) end
    local total=(os.clock()-started)*1000
    if total>=SLOW_TICK_MS and slowTicks<60 then
        slowTicks=slowTicks+1
        log(string.format('[Perf] 支持循环耗时 %.1fms：%s',total,table.concat(parts,' ')))
    end
    supportMeter:add(total,started,costs)
end
function arenaSupport:tick()
    tickMembers,tickStatus=arena:members(),arena:status()
    local ok,err=pcall(supportSteps,self)
    tickMembers,tickStatus=nil,nil
    if not ok then error(err,0) end
end
function arenaSupport:status()
    local result=bossHUD:status();local activity=arenaActivity:status()
    result.full_update_count=activity.full_update_count;result.bone_refresh_count=activity.bone_refresh_count;result.free_camera=activity.free_camera
    local grabs=arenaGrabs:status()
    result.grab_events=grabs.events;result.grab_pairs=grabs.observed_pairs;result.grab_restore_pending=grabs.restore_pending
    local observer=observerGuard:status()
    result.observer_health_verified=observer.health_verified;result.observer_message=observer.message
    if mounts then for key,value in pairs(mounts:status())do result[key]=value end end
    if bossStages then for key,value in pairs(bossStages:status())do result[key]=value end end
    return result
end

-- Every hotkey of this mod is read once a frame in the game thread (key_poll.lua); none is a UE4SS key bind, whose
-- callback would run this mod's Lua on UE4SS's own thread.
local keyPoll=KeyPoll.new({log=log,controller=GetRealPlayerController,
    meter=require('perf_meter').new({label='按键读取',log=log,slow=2,hitch=1000})})
local keyRouter=KeyRouter.new({log=log,register=keyPoll.register,occupied=keyPoll.occupied})
local unitKeys=UnitKeys.new({path=Config.RuntimePath,log=log,router=keyRouter,
    queue=function(callback,path,team,count)
        if panelRuntime then panelRuntime:queueSummon(callback,path,team,count) end
    end,
    reserved=function(vk,mask)return panelRuntime and panelRuntime:unitKeyReserved(vk,mask) end,
    shared=function(vk)return panelRuntime and panelRuntime:unitKeyShared(vk) end,
    ready=function()local status=runtimeSession:status();return status.game_ready,status.game_ready_reason end,
    -- A unit key carries its own team and count; a key saved before that follows the panel selection.
    spawn=function(path,team,count)
        return panelRuntime:summon(path,team,count)
    end})

-- Developer probes are opt-in, never hidden default key reservations.
if Config.EnableDeveloperKeybinds then
keyPoll.register(Key.F1,{ModifierKey.SHIFT},DumpBrain)
keyPoll.register(Key.F2,{ModifierKey.SHIFT},TargetDiag)
keyPoll.register(Key.F3,{ModifierKey.SHIFT},DumpCollisionMatrix)
keyPoll.register(Key.F9,{ModifierKey.SHIFT},function()
    ExecuteInGameThread(function()
        for _,path in ipairs(SpawnPolicy.knownPaths()) do
            local result=arena:select(path,"blue",1)
            log("验证目录切换="..tostring(result.ok).."；"..tostring(result.message))
            break
        end
    end)
end)
end
panelRuntime=PanelRuntime.new({arena=arena,exporter=exporter,path=Config.RuntimePath,
    build=BUILD,log=log,unitRules=arenaSupport.unitRules,track=arenaSupport.track,autoScan=true,fullInventory=true,spectator=spectator,statMatch=statMatch,companionStats=arenaSupport.companionStats,aiParams=aiParams,bossCombos=bossCombos,spawnDifficulty=spawnDifficulty,aiDifficulty=aiDifficulty,companions=companions,funFeatures=funFeatures,immortal=immortalTeams,clockHUD=clockHUD,executionCamera=executionCamera,companionExecutions=arenaSupport.companionExecutions,session=runtimeSession,codex=codexExporter,spawnPolicy=SpawnPolicy,support=arenaSupport,unitKeys=unitKeys,
    router=keyRouter,camera={status=function()return {active=freeCamera:isActive(),pending=freeCamera:hasPending(),
            frozen=freeCamera:isFrozen(),settings=freeCamera:settings()}end,
        toggle=ToggleFreeCam,exit=ForceExitFreeCam,
        -- 时停 (the app's switch and its function key) and the app's speed, turn and smoothing (free_camera.lua).
        freeze=function(_,on)return freeCamera:freeze(on)end,
        configure=function(_,speed,turn,smooth)return freeCamera:configure(speed,turn,smooth)end},
    spawnCatalog=SpawnCatalog.new({log=log,path=Config.RuntimePath,getWorld=UEHelpers.GetWorld}),
    tableCatalog=TableCatalog.new({log=log,path=Config.RuntimePath,maps=worldMaps}),
    areaLevels=AreaLevels.new({log=log,path=Config.RuntimePath}),
    spawnLevel=spawnLevel,
    homeLevels=homeLevels,
    references=ReferenceAudit.new({log=log,path=Config.RuntimePath})})
panelRuntime:start()
keyPoll:start()

if ModRef then
    ModRef.OnUnload=function()
        freeCamera:silence()
        arenaSupport.lionNPC:silence()
        keyPoll:silence()
        panelRuntime:silence()
        probeSampleGen=probeSampleGen+1
        probe:silence("Mod卸载")
        aiDifficulty:silence("Mod卸载")
        companions:silence()
        funFeatures:silence()
        immortalTeams:silence()
        clockHUD:silence()
        combatLock:silence('Mod卸载')
        arenaSupport.stands:silence()
        arenaSupport.summonKeep:silence()
        if arenaSupport.grabProbe then arenaSupport.grabProbe:silence() end
        playerAim:silence('Mod卸载')
        aiParams:silence()
        bossCombos:silence()
        if arenaSupport.guillotine then arenaSupport.guillotine:silence() end
        arenaSupport.standaloneStoryUnits:silence()
        if arenaExecutions then arenaExecutions:silence() end
        battle:cancel("Mod卸载")
        if battle:pendingCount()>0 or #arenaActors>0 then
            log("卸载时仍有参赛者或恢复记录；重载不会替代停止清理")
        end
        if mounts and mounts:count()>0 then
            log('[Mount] 卸载时仍有 '..mounts:count()..' 个骑兵的坐骑记录；重载后它们的坐骑和刷怪点不会随清理移除')
        end
        if arenaSupport.lionStage and arenaSupport.lionStage:count()>0 then
            log('[LionStage] 卸载前还有召唤舞狮场地，请先停止并清理')
        end
        if arenaSupport.lionNPC:count()>0 then log('[LionNPC] 卸载前还有NPC独立桩，请先停止并清理') end
        if bossStages and bossStages:count()>0 then
            log('[BossStage] 卸载时仍有 '..bossStages:count()..' 个 BOSS 的场地物件记录；重载后这些物件不会随清理移除')
        end
        local spectatorState=spectator:status()
        if spectatorState.pending_relations>0 or spectatorState.pending_flags>0 then
            log("无仇恨快照尚未恢复；热重载前必须先关闭无仇恨并等待恢复读回")
        end
    end
end
log("loaded ✓ "..BUILD.."；全部功能键默认未绑定，可在面板自定义；自由观战包含无仇恨、隐身、无敌锁血及镜头收音。")
