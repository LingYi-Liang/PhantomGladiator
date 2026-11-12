-- 本地面板与快捷键共用同一组动作。所有游戏回调均在游戏线程执行。
local Bridge = require("panel_bridge")
local KeyRouter=require('key_router')
local FunctionKeys=require('function_keybinds')
local SummonQueue=require("summon_queue")
local PoolKeys=require("monster_pool_keys")
local Runtime = {}
Runtime.__index = Runtime
local ACTIONS = FunctionKeys.actions
local GLOBAL_KEYS={stop=true,exit_camera=true,refresh_catalog=true,cycle_team=true}

local function read(path)
    local file=io.open(path,'r');if not file then return nil end
    local text=file:read('*a');file:close();return text
end

function Runtime.new(options)
    local self=setmetatable({options=options,alive=true,pumpReady=false},Runtime)
    self.log=options.log or function() end
    self.summonQueue=SummonQueue.new({log=self.log,
        session=function()return options.session and options.session:status() end,
        spawn=function(path,team,count)return self:summon(path,team,count)end})
    -- Monster pool keys while the summon queue above is off: every press is kept here instead of being dropped as a
    -- held key would be (queueSummon). It is always on, and takes turns with the other summon shortcuts.
    self.poolQueue=SummonQueue.new({log=function(line)self.log((line:gsub('^%[SummonQueue%]','[PoolQueue]')))end,
        session=function()return options.session and options.session:status() end,
        spawn=function(path,team,count)return self:summon(path,team,count)end})
    self.poolQueue.enabled=true
    self.router=options.router or KeyRouter.new({log=self.log})
    local function unitOwner(vk,mask)
        local unit=options.unitKeys and options.unitKeys:owner(vk,mask)
        return unit and ((unit:match('%.([^%.]+)$') or unit):gsub('_C$',''))
    end
    local function sessionStatus()return self:sessionStatus() end
    self.functionKeys=FunctionKeys.new({path=options.path,router=self.router,log=self.log,
        unitOwner=unitOwner,poolOwner=function(vk,mask)return self.poolKeys:owner(vk,mask)end,
        queueSpawn=function(callback)self:queueSummon(callback)end,
        queue=function(callback,action)self:queueAction(callback,action)end,
        dispatch=function(action)self:dispatch(action,{})end})
    self.poolKeys=PoolKeys.new({path=options.path,router=self.router,log=self.log,session=sessionStatus,
        conflict=function(vk,mask)
            local _,label=self.functionKeys:owner(vk,mask)
            if label then return '功能「'..label..'」' end
            local unit=unitOwner(vk,mask)
            if unit then return '单位「'..unit..'」' end
        end,
        -- How many of this unit one summon may hold; 0 when it cannot be summoned.
        capacity=function(path)
            local policy=options.spawnPolicy
            if not policy or not policy.check(path) then return 0 end
            local limit=policy.limits(path)
            return limit and limit.max_count or 100
        end,
        queue=function(path,team,count)return self:queuePoolSummon(path,team,count)end})
    self.router.dispatch=function(vk,mask)
        if not self.alive or self.functionKeys:press(vk,mask) then return end
        if options.unitKeys and options.unitKeys:dispatch(vk,mask) then return end
        self.poolKeys:dispatch(vk,mask)
    end
    local function readyError()
        if not options.session then return "未配置游戏会话校验" end
        local status=options.session:status()
        if status.game_ready~=true then return status.game_ready_reason or "游戏尚未就绪" end
    end
    -- nil once the free camera is running; otherwise why it could not be opened.
    local function openCamera()
        if not options.camera then return {ok=false,message='自由观战模块未加载',spawned_count=0} end
        if options.camera:status().active then return nil end
        local why=readyError();if why then return {ok=false,message=why,spawned_count=0} end
        local entered=options.camera:toggle()
        if not entered or entered.ok~=true then return entered or {ok=false,message='自由观战没有打开',spawned_count=0} end
    end
    self.handlers={
        spawn=function(command)
            local why=readyError(); if why then return {ok=false,message=why,spawned_count=0} end
            if self.summonQueue.enabled then return {ok=false,message='排队模式已开启，请重新提交召唤',spawned_count=0} end
            return self:summon(command.unit_id,command.team,command.count)
        end,
        queue_spawn=function(command)
            self.summonQueue:sync(options.session and options.session:status())
            return self.summonQueue:enqueue(command.unit_id,command.team,command.count,command.key_spawn)
        end,
        set_summon_queue=function(command)
            if command.key_start~='ON' and command.key_start~='OFF' then return {ok=false,message='无效的排队召唤设置'} end
            return self:setSummonQueue(command.key_start=='ON')
        end,
        cancel_summon_queue=function()
            local cancelled=self.summonQueue:cancel('清空召唤队列')
            return {ok=true,message='已取消 '..cancelled..' 条游戏内待执行召唤'}
        end,
        select_unit=function(command) return options.arena:select(command.unit_id,command.team,command.count) end,
        cycle_team=function() return options.arena:cycleTeam() end,
        toggle_camera=function()
            if not options.camera then return {ok=false,message='自由观战模块未加载',spawned_count=0}end
            local status=options.camera:status()
            if status.active or status.pending then return options.camera:exit()end
            local why=readyError();if why then return {ok=false,message=why,spawned_count=0}end
            return options.camera:toggle()
        end,
        exit_camera=function()
            if not options.camera then return {ok=false,message='自由观战模块未加载',spawned_count=0}end
            return options.camera:exit()
        end,
        -- 时停 (the app's switch and the function key of the same name): in the free camera on or off; outside it the
        -- camera opens first, frozen, for a screenshot. Leaving the camera ends it.
        toggle_time_stop=function()
            if not options.camera or not options.camera.freeze then return {ok=false,message='自由观战模块未加载',spawned_count=0}end
            local status=options.camera:status()
            if status.active then return options.camera:freeze(not status.frozen) end
            local why=readyError();if why then return {ok=false,message=why,spawned_count=0} end
            local entered=options.camera:toggle()
            if not entered or entered.ok~=true then return entered or {ok=false,message='自由观战没有打开，未时停',spawned_count=0} end
            local frozen=options.camera:freeze(true)
            return {ok=frozen.ok==true,message='已进入自由观战；'..tostring(frozen.message),spawned_count=0}
        end,
        -- 镜头跟踪 (camera_track.lua). Outside the free camera it opens first, like 时停; leaving the camera ends it.
        toggle_track=function()
            if not options.track then return {ok=false,message='镜头跟踪模块未加载',spawned_count=0} end
            if options.track:status().on then return options.track:finish() end
            local failed=openCamera();if failed then return failed end
            return options.track:start()
        end,
        track_pick=function()
            if not options.track then return {ok=false,message='镜头跟踪模块未加载',spawned_count=0} end
            local failed=openCamera();if failed then return failed end
            return options.track:pick()
        end,
        track_next=function()
            if not options.track then return {ok=false,message='镜头跟踪模块未加载',spawned_count=0} end
            local failed=openCamera();if failed then return failed end
            return options.track:next()
        end,
        -- Framing upper case in key_spawn, the seconds before automatic comes back in key_start, the unit's address in unit_id.
        set_camera_track=function(command)
            if not options.track then return {ok=false,message='镜头跟踪模块未加载',spawned_count=0} end
            return options.track:set((command.key_spawn or ''):lower(),command.key_start,command.unit_id)
        end,
        -- Speed, turn and smoothing as whole numbers in the key_spawn, key_start and key_stop columns.
        set_free_camera=function(command)
            if not options.camera or not options.camera.configure then return {ok=false,message='自由观战模块未加载',spawned_count=0}end
            return options.camera:configure(tonumber(command.key_spawn),tonumber(command.key_start),tonumber(command.key_stop))
        end,
        toggle_stat_match=function()
            if not options.statMatch then return {ok=false,message='数值统一模块未加载',spawned_count=0} end
            return options.statMatch:toggle()
        end,
        -- GAME, MATCH or CUSTOM in key_spawn; for CUSTOM the revision of Runtime/stat-custom-request.tsv in key_start.
        set_stat_mode=function(command)
            if not options.statMatch then return {ok=false,message='数值设定模块未加载',spawned_count=0} end
            return options.statMatch:setMode(command.key_spawn,command.key_start)
        end,
        -- The companions' own set: GAME or CUSTOM in key_spawn; for CUSTOM the revision of Runtime/companion-stats-request.tsv in key_start.
        set_companion_stats=function(command)
            if not options.companionStats then return {ok=false,message='随从数值模块未加载',spawned_count=0} end
            return options.companionStats:setMode(command.key_spawn,command.key_start)
        end,
        -- The revision of Runtime/ai-params-request.tsv in key_spawn.
        set_ai_params=function(command)
            if not options.aiParams then return {ok=false,message='AI 参数模块未加载',spawned_count=0} end
            return options.aiParams:setRequest(command.key_spawn)
        end,
        set_boss_combos=function(command)
            if not options.bossCombos then return {ok=false,message='连携技模块未加载',spawned_count=0} end
            return options.bossCombos:set(command.key_spawn=='ON')
        end,
        -- The difficulty token travels in the key_spawn column (FOLLOW, EASY, NORMAL, HARD, NIGHTMARE).
        set_spawn_difficulty=function(command)
            if not options.spawnDifficulty then return {ok=false,message='召唤难度模块未加载',spawned_count=0} end
            return options.spawnDifficulty:set(command.key_spawn)
        end,
        -- Feature token (SHACHI, DEFLECT, DODGE) in key_spawn, ON or OFF in key_start.
        set_fun_feature=function(command)
            if not options.funFeatures then return {ok=false,message='趣味功能模块未加载',spawned_count=0} end
            return options.funFeatures:set(command.key_spawn,command.key_start)
        end,
        -- Team (blue, red, companion) in the team column, ON or OFF in key_start (immortal_teams.lua).
        set_team_immortal=function(command)
            if not options.immortal then return {ok=false,message='不倒下模块未加载',spawned_count=0} end
            return options.immortal:set(command.team,command.key_start)
        end,
        -- HOME, HERE, CUSTOM, UNIT or CYCLE in key_spawn. CYCLE takes 0–7 in key_start.
        set_spawn_level=function(command)
            if not options.homeLevels then return {ok=false,message='召唤等级模块未加载',spawned_count=0} end
            return options.homeLevels:configure(command.unit_id,command.key_spawn,command.key_start)
        end,
        -- ON or OFF in key_start (battle_clock_hud.lua).
        set_clock_hud=function(command)
            if not options.clockHUD then return {ok=false,message='画面计时模块未加载',spawned_count=0} end
            return options.clockHUD:set(command.key_start)
        end,
        -- ON or OFF in key_start (execution_camera.lua).
        set_execution_camera=function(command)
            if not options.executionCamera then return {ok=false,message='处决镜头模块未加载',spawned_count=0} end
            return options.executionCamera:set(command.key_start)
        end,
        -- The unit in unit_id, the rule in key_spawn and its value in key_start, upper case on the wire (unit_rules.lua).
        set_unit_rule=function(command)
            if not options.unitRules then return {ok=false,message='单位规则模块未加载',spawned_count=0} end
            return options.unitRules:set(command.unit_id,command.key_spawn:lower(),command.key_start:lower())
        end,
        -- ON or OFF in key_start (companion_executions.lua).
        set_companion_executions=function(command)
            if not options.companionExecutions then return {ok=false,message='随从处决模块未加载',spawned_count=0} end
            return options.companionExecutions:set(command.key_start)
        end,
        start=function()
            local why=readyError(); if why then return {ok=false,message=why,spawned_count=0} end
            return options.arena:start()
        end,
        stop=function()
            if self.summonQueue.enabled then self.summonQueue:cancel('停止并清理') end
            if #self.poolQueue.jobs>0 then self.poolQueue:cancel('停止并清理') end
            if options.support then options.support:discover() end
            return options.arena:stop()
        end,
        clear_neutral=function()
            if options.support then options.support:discover() end
            return options.arena:clearNeutral()
        end,
        dismiss_companions=function()
            if options.support then options.support:discover() end
            return options.arena:clearCompanions()
        end,
        -- The app's 修复存档 (save_repair.lua): arms the repairs of what earlier versions did to saves, and reports.
        repair_save=function()
            local why=readyError(); if why then return {ok=false,message=why,spawned_count=0} end
            local repair=options.support and options.support.saveRepair
            if not repair then return {ok=false,message='存档修复模块未加载',spawned_count=0} end
            local result=repair:run()
            return {ok=result.ok==true,message=result.message,spawned_count=0}
        end,
        -- The app's 召回到身边 and the function key of the same name.
        recall_companions=function()
            if not options.companions then return {ok=false,message='随从模块未加载',spawned_count=0} end
            return options.companions:recall()
        end,
        toggle_spectator=function()
            local why=readyError(); if why then return {ok=false,message=why,spawned_count=0} end
            if not options.spectator then return {ok=false,message="无仇恨模块未加载",spawned_count=0} end
            local result=options.spectator:toggle()
            return {ok=result.ok==true,message=result.message or "观战模式已请求切换",spawned_count=0}
        end,
        refresh_catalog=function()
            if options.references then options.references:silence('重新核对目录');self.referencesStarted=false end
            if options.spawnCatalog and not readyError() then options.spawnCatalog:export() end
            if options.tableCatalog and not readyError() then options.tableCatalog:export() end
            if options.areaLevels and not readyError() then options.areaLevels:export() end
            if options.homeLevels and not readyError() then options.homeLevels:refresh() end
            if options.codex and not readyError() then
                local codex=options.codex:export()
                self.log("原生图鉴读取="..tostring(codex.ok).."；"..tostring(codex.message))
            end
            if options.exporter:status().active then
                return {ok=true,message="正在读取单位目录，请等待进度更新",spawned_count=0}
            end
            local ok,status=options.exporter:start()
            return {ok=ok,message=ok and "已开始读取游戏资源目录" or tostring(status.message or status.error or status.reason or "目录扫描未启动"),spawned_count=0}
        end,
        configure_keys=function(command)
            local proposal={}
            for _,name in ipairs(ACTIONS)do
                proposal[name]=command['key_'..name] or self.functionKeys.entries[name]
            end
            return self:configure(proposal)
        end,
        configure_unit_key=function(command)
            if not options.unitKeys then return {ok=false,message='单位快捷键模块未加载',spawned_count=0} end
            self.poolKeys:refresh(self.poolKeys.session)
            local key=command.key_spawn=='UNBOUND' and 0 or tonumber((command.key_spawn or ''):match('^VK_(%d+)$'))
            local mask=tonumber((command.key_start or ''):match('^MOD_(%d+)$'))
            -- FIXED in the key_stop column: the row's team and count belong to this unit's key.
            if command.key_stop=='FIXED' then return options.unitKeys:configure(command.unit_id,key,mask,command.team,command.count) end
            return options.unitKeys:configure(command.unit_id,key,mask)
        end,
    }
    self.bridge=Bridge.new({path=options.path,log=self.log,handlers=self.handlers,
        session=function() return options.session and options.session:status() or {} end,status=function()
        local arena=options.arena:status()
        local catalog=options.exporter:status()
        local spectator=options.spectator and options.spectator:status() or {}
        local out={build=options.build,blue_count=arena.blue_count,red_count=arena.red_count,
            neutral_count=arena.neutral_count,total=arena.total,current_unit=arena.current_unit,
            current_team=arena.current_team,current_count=arena.current_count,
            arena_state=arena.state,arena_message=arena.message,
            catalog_state=catalog.active and "scanning" or (catalog.complete and "complete" or catalog.reason),
            catalog_message=string.format("%s / %s 路径 · %s 个候选 · %s",tostring(catalog.paths_done),tostring(catalog.paths_total),tostring(catalog.candidates),tostring(catalog.reason)),catalog_paths_done=catalog.paths_done,
            catalog_paths_total=catalog.paths_total,catalog_truncated=catalog.truncated,
            catalog_started_at=catalog.started_at,
            catalog_coverage=catalog.coverage,catalog_candidates=catalog.candidates}
        local session=sessionStatus()
        self.poolKeys:refresh(session.game_session)
        out.monster_pool_keys_schema=1
        local queue=self.summonQueue
        if queue.enabled then queue:sync(session) end
        self.poolQueue:sync(session)
        out.summon_queue_enabled=queue.enabled
        out.summon_queue_epoch=queue:epoch()
        out.summon_queue_waiting=#queue.jobs
        out.summon_queue_running=queue.running==true
        out.summon_queue_completed=queue.completed
        out.summon_queue_message=queue.message
        out.monster_pool_queue_waiting=#self.poolQueue.jobs
        local policy=options.spawnPolicy and options.spawnPolicy.status() or {}
        out.spawn_trial_policy=policy.version or ''
        out.spawn_trial_count=policy.count or 0
        out.spawn_mode=policy.mode or 'validated'
        out.arena_owned_records=arena.owned_records
        out.arena_dead_count=arena.dead_count
        out.arena_unreadable_count=arena.unreadable_count
        out.arena_max_units=arena.max_units
        out.neutral_owned_records=arena.neutral_owned
        out.companion_count=arena.companion_count or 0
        out.companion_owned_records=arena.companion_owned or 0
        local companion=options.companions and options.companions:status() or {}
        out.companion_supported=not not options.companions
        out.companion_follow=companion.follow or 0
        out.companion_friendly=companion.friendly or 0
        out.companion_failures=companion.failures or 0
        out.companion_stuck_teleports=companion.stuck or 0
        out.companion_recalls=companion.recalls or 0
        out.companion_message=companion.message or ''
        out.arena_team_revision=arena.team_revision or 0
        out.arena_summon_count=arena.summon_count or 0
        out.battle_clock=arena.battle_clock or ''
        out.battle_seconds=string.format('%.1f',arena.battle_seconds or 0)
        local immortal=options.immortal and options.immortal:status() or {}
        out.immortal_supported=not not options.immortal
        out.immortal_blue=immortal.blue==true
        out.immortal_red=immortal.red==true
        out.immortal_companion=immortal.companion==true
        out.immortal_locked=immortal.locked or 0
        out.immortal_failures=immortal.failures or 0
        out.immortal_breaches=immortal.breaches or 0
        out.immortal_message=immortal.message or ''
        local clockHUD=options.clockHUD and options.clockHUD:status() or {}
        out.clock_hud_supported=not not options.clockHUD
        out.clock_hud=clockHUD.on==true
        out.clock_hud_state=clockHUD.state or 'off'
        out.clock_hud_failures=clockHUD.failures or 0
        local executionCamera=options.executionCamera and options.executionCamera:status() or {}
        out.execution_camera_supported=not not options.executionCamera
        out.execution_camera=executionCamera.on==true
        out.execution_camera_state=executionCamera.state or 'off'
        out.execution_camera_failures=executionCamera.failures or 0
        out.companion_executions_supported=not not options.companionExecutions
        out.companion_executions=options.companionExecutions and options.companionExecutions:status().on==true or false
        local track=options.track and options.track:status() or nil
        out.track_supported=track~=nil
        if track then
            out.track_on=track.on==true;out.track_framing=track.framing;out.track_resume=track.resume
            out.track_target=track.target;out.track_target_class=track.target_class;out.track_other_class=track.other_class
            out.track_targets=options.camera and options.camera:status().active and options.track:targets() or ''
        end
        out.unit_rules_supported=not not options.unitRules
        out.unit_rules=options.unitRules and options.unitRules:status().text or ''
        out.clock_hud_message=clockHUD.message or ''
        -- The level a summon gets: the highest map enemy near the player at the last look (spawn_level.lua).
        local level=options.spawnLevel and options.spawnLevel:status() or {}
        out.spawn_level=level.last_level and string.format('%.0f',level.last_level) or ''
        out.spawn_level_unit=level.last_unit or ''
        local home=options.homeLevels and options.homeLevels:status() or {}
        out.spawn_level_mode=home.mode or ''
        out.spawn_level_custom=home.custom or ''
        out.spawn_cycle=home.cycle or ''
        local support=options.support and options.support:status() or {}
        out.boss_hud_registered=support.registered or 0
        out.boss_hud_visible=support.visible or 0
        out.boss_hud_pending=support.pending or 0
        out.boss_hud_health_verified=support.health_verified or 0
        out.boss_hud_names_verified=support.names_verified or 0
        out.boss_hud_numbers_verified=support.numbers_verified or 0
        out.arena_full_update_count=support.full_update_count or 0
        out.arena_bone_refresh_count=support.bone_refresh_count or 0
        out.npc_grab_events=support.grab_events or 0
        out.npc_grab_pairs=support.grab_pairs or 0
        out.npc_grab_restore_pending=support.grab_restore_pending==true
        out.arena_free_camera=support.free_camera==true
        -- 时停 and the free camera's speed, turn and smoothing (free_camera.lua).
        local camera=options.camera and options.camera.status and options.camera:status() or {}
        out.free_camera_frozen=camera.frozen==true
        if camera.settings then
            out.free_camera_settings_supported=true
            out.free_camera_speed=camera.settings.speed;out.free_camera_turn=camera.settings.turn;out.free_camera_smooth=camera.settings.smooth
        end
        out.observer_health_verified=support.observer_health_verified==true
        out.observer_message=support.observer_message or ''
        local matching=options.statMatch and options.statMatch:status() or {}
        out.stat_match_supported=not not options.statMatch
        out.stat_match_enabled=matching.enabled
        out.stat_match_baseline_unit=matching.baseline_unit or ''
        out.stat_match_health=matching.health
        out.stat_match_shachi=matching.shachi
        out.stat_match_attack=matching.attack
        out.stat_match_shachi_attack=matching.shachi_attack
        out.stat_match_count=matching.matched or 0
        out.stat_match_failures=matching.failures or 0
        out.stat_match_message=matching.message or ''
        out.stat_match_fields=matching.field_count or 0
        out.stat_match_mode=matching.mode or 'game'
        out.stat_match_customized=matching.customized or 0
        out.stat_custom_count=matching.custom_count or 0
        local custom=matching.custom or {}
        out.stat_custom_health=custom.Health_Max or ''
        out.stat_custom_shachi=custom.Shachi_Max or ''
        out.stat_custom_attack=custom.Attack or ''
        out.stat_custom_shachi_attack=custom.ShachiAttack or ''
        -- The fields the game did not take on the last custom unit; the app names the first few.
        local rejected=matching.rejected or {}
        out.stat_custom_rejected=#rejected
        out.stat_custom_rejected_fields=table.concat(rejected,',',1,math.min(#rejected,12))
        local companionStats=options.companionStats and options.companionStats:status() or {}
        local companionRejected=companionStats.rejected or {}
        out.companion_stats_supported=not not options.companionStats
        out.companion_stats_mode=companionStats.mode or 'game'
        out.companion_stats_count=companionStats.custom_count or 0
        out.companion_stats_customized=companionStats.customized or 0
        out.companion_stats_failures=companionStats.failures or 0
        out.companion_stats_message=companionStats.message or ''
        out.companion_stats_rejected=#companionRejected
        out.companion_stats_rejected_fields=table.concat(companionRejected,',',1,math.min(#companionRejected,12))
        local difficulty=options.spawnDifficulty and options.spawnDifficulty:status() or {}
        out.spawn_difficulty_supported=not not options.spawnDifficulty
        out.spawn_difficulty=difficulty.level or ''
        out.spawn_difficulty_game=difficulty.game or ''
        out.spawn_difficulty_applied=difficulty.applied or 0
        out.spawn_difficulty_skipped=difficulty.skipped or 0
        out.spawn_difficulty_failures=difficulty.failures or 0
        out.spawn_difficulty_message=difficulty.message or ''
        -- ai_difficulty.lua: whether the summoned units' AI checks answered their own level on readback.
        local ai=options.aiDifficulty and options.aiDifficulty:status() or {}
        out.spawn_difficulty_ai=ai.state or ''
        out.spawn_difficulty_ai_verified=ai.verified or 0
        out.spawn_difficulty_ai_failed=ai.failed or 0
        local fun=options.funFeatures and options.funFeatures:status() or {}
        out.boss_combos_supported=not not options.bossCombos
        out.boss_combos=options.bossCombos and options.bossCombos:status().enabled==true or false
        out.fun_supported=not not options.funFeatures
        out.fun_shachi=fun.shachi==true
        out.fun_deflect=fun.deflect==true
        out.fun_dodge=fun.dodge==true
        out.fun_shachi_state=fun.shachi_state or 'off'
        out.fun_shachi_failures=fun.shachi_failures or 0
        out.fun_guard_state=fun.guard_state or 'off'
        out.fun_guard_message=fun.guard_message or ''
        out.fun_deflect_pressed=fun.deflect_pressed or 0
        out.fun_deflect_received=fun.deflect_received or 0
        out.fun_dodge_pressed=fun.dodge_pressed or 0
        out.fun_perfect_dodges=fun.perfect_dodges or 0
        local unitKeys=options.unitKeys and options.unitKeys:status() or {}
        out.unit_keys_epoch=unitKeys.epoch or ''
        out.unit_keys_revision=unitKeys.revision or 0
        out.unit_keys_event=unitKeys.event or 0
        out.unit_keys_last_unit=unitKeys.unit or ''
        out.unit_keys_message=unitKeys.message or ''
        out.game_session=session.game_session
        out.game_ready=session.game_ready
        out.game_ready_reason=session.game_ready_reason
        out.spectator_enabled=spectator.enabled_requested
        out.spectator_flag_readback=spectator.player_can_be_hatred_readback
        out.spectator_pending_relations=spectator.pending_relations
        out.spectator_pending_flags=spectator.pending_flags
        out.spectator_message=spectator.message
        out.spectator_read_failures=spectator.readFailures
        local functions=self.functionKeys:status()
        -- 4: thirteen function keys, the last three toggle_track, track_pick and track_next; configure_keys comes in 19 columns.
        out.function_keys_schema=4;out.function_keys_epoch=functions.epoch;out.function_keys_revision=functions.revision
        for _,action in ipairs(ACTIONS) do out['key_'..action]=self.functionKeys:token(action)end
        return out
    end})
    return self
end
function Runtime:unitKeyReserved(vk,mask)
    local _,label=self.functionKeys:owner(vk,mask)
    local pool=self.poolKeys:owner(vk,mask)
    return label or (pool and ('怪物池：'..pool))
end
function Runtime:unitKeyShared(vk)
    return self.router.installed[vk..':0']~=nil
end
function Runtime:configure(proposal)
    self.poolKeys:refresh(self.poolKeys.session)
    local result=self.functionKeys:configure(proposal)
    if result.ok and self.options.unitKeys then self.options.unitKeys:refresh()end
    return result
end
function Runtime:setSummonQueue(enabled)
    local queue=self.summonQueue
    if enabled==queue.enabled then return {ok=true,message=enabled and '排队召唤已开启' or '排队召唤已关闭'} end
    if enabled then
        queue:sync(self.options.session and self.options.session:status())
        if not queue.session then return {ok=false,message='进入地图后才能开启排队召唤'} end
        if type(LoopInGameThreadWithDelay)~='function' or type(CancelDelayedAction)~='function' then
            return {ok=false,message='排队召唤需要游戏线程定时器'}
        end
        local token={}
        local ok,handle=pcall(LoopInGameThreadWithDelay,25,function()
            if self.alive and self.summonLoopToken==token then queue:tick() end
        end)
        if not ok or handle==nil or handle==false then return {ok=false,message='召唤队列定时器注册未确认'} end
        self.summonLoopToken,self.summonLoop=token,handle
        self.summonPending=nil
        queue.enabled=true
        if #self.poolQueue.jobs>0 then self.poolQueue:cancel('排队召唤已开启') end
        if self.nextSummonAt and (not queue.nextAt or self.nextSummonAt>queue.nextAt) then queue.nextAt=self.nextSummonAt end
        queue.completed=0
        queue:cancel('排队召唤已开启')
        return {ok=true,message='排队召唤已开启'}
    end

    queue.enabled=false
    queue:cancel('排队召唤已关闭')
    local handle=self.summonLoop
    self.summonLoopToken,self.summonLoop=nil,nil
    if handle~=nil then
        local ok,result=pcall(CancelDelayedAction,handle)
        if not ok or result==false then self.log('[SummonQueue] 定时器取消未读回；回调已失效') end
    end
    return {ok=true,message='排队召唤已关闭'}
end


function Runtime:summon(path,team,count)
    local result=self.options.arena:spawn(path,team,count)
    self.nextSummonAt=os.clock()+0.25
    return result
end

function Runtime:sessionStatus()
    local ok,state=pcall(function()return self.options.session and self.options.session:status()end)
    if not ok or type(state)~='table' then state={} end
    self.hotkeySession=type(state.game_session)=='string' and state.game_session~='' and state.game_session or nil
    self.hotkeyReady=state.game_ready==true and self.hotkeySession~=nil
    return state
end

function Runtime:inputContext()
    -- Native game state is read only when this input already runs on the game thread.
    local readyAtInput
    if type(IsInGameThread)=='function' and IsInGameThread() then
        self:sessionStatus()
        readyAtInput=self.hotkeyReady
    end
    return {session=self.hotkeySession,ready=readyAtInput}
end

function Runtime:inputCurrent(request)
    self:sessionStatus()
    return request.ready~=false and self.hotkeyReady and (not request.session or request.session==self.hotkeySession)
end

function Runtime:existingModeInput(action,request)
    if action~='toggle_camera' and action~='toggle_track' and action~='toggle_time_stop' then return false end
    local mode=action=='toggle_track' and self.options.track or self.options.camera
    if not mode then return false end
    local ok,status=pcall(function()return mode:status()end)
    if not ok or type(status)~='table' then return false end
    if action=='toggle_camera' then return status.active==true or status.pending==true end
    if action=='toggle_track' then return status.on==true end
    if action=='toggle_time_stop' and status.active==true then
        return status.frozen==true or not request.session or request.session==self.hotkeySession
    end
    return false
end

function Runtime:queueAction(callback,action)
    if not self.alive then return end
    local request=not GLOBAL_KEYS[action] and self:inputContext() or nil
    local queued,err=pcall(ExecuteInGameThread,function()
        if not self.alive then return end
        if request and not self:inputCurrent(request) and not self:existingModeInput(action,request) then
            self.log('[InputKey] 取消旧会话或未就绪的待执行操作 action='..tostring(action)
                ..' 原会话='..tostring(request.session)..' 当前会话='..tostring(self.hotkeySession))
            return
        end
        callback()
    end)
    if not queued then self.log('[InputKey] 无法排入游戏线程：'..tostring(err)) end
end

-- A held or rapidly repeated summon key must not fill the engine's callback queue.
-- Both summon shortcuts share one pending request and leave a gap after it runs.
function Runtime:queueSummon(callback,path,team,count)
    if not self.alive then return end
    if self.summonQueue.enabled then
        local selected,defaultTeam,defaultCount=self.options.arena:selection()
        return self.summonQueue:enqueue(path or selected,team or defaultTeam,count or defaultCount)
    end
    if self.summonPending or (self.nextSummonAt and os.clock()<self.nextSummonAt) then
        self.summonSkipped=(self.summonSkipped or 0)+1
        return
    end
    local request=self:inputContext()
    self.summonPending=request
    local queued,queueError=pcall(ExecuteInGameThread,function()
        if not self.alive or self.summonPending~=request then return end
        if not self:inputCurrent(request) then
            self.summonPending=nil;self.summonSkipped=0
            self.log('[SummonKey] 取消待执行召唤；原会话='..tostring(request.session)
                ..' 当前会话='..tostring(self.hotkeySession)..' 就绪读回='..tostring(self.hotkeyReady))
            return
        end
        local skipped=self.summonSkipped or 0
        self.summonSkipped=0
        local ok,err=xpcall(callback,debug.traceback)
        self.summonPending=nil
        if skipped>0 then self.log('[SummonKey] 跳过密集的召唤按键='..skipped..'；已处理一次召唤请求') end
        if not ok then self.log('[SummonKey] 回调失败: '..tostring(err)) end
    end)
    if not queued and self.summonPending==request then
        self.summonPending=nil
        self.log('[SummonKey] 无法排入游戏线程: '..tostring(queueError))
    end
end

-- A monster pool key. With the summon queue on it joins that queue; otherwise it waits in poolQueue, which runs one
-- summon at a time from the game thread: at once when nothing is in the way, then from the panel pump.
function Runtime:queuePoolSummon(path,team,count)
    if not self.alive then return end
    if self.summonQueue.enabled then return self.summonQueue:enqueue(path,team,count) end
    -- The status pump keeps poolQueue's session current and tick() reads it again before each summon.
    local queue=self.poolQueue
    local result=queue:enqueue(path,team,count)
    if result.ok and #queue.jobs==1 and not self.poolKick then
        self.poolKick=true
        local queued=pcall(ExecuteInGameThread,function()
            self.poolKick=nil
            self:tickPoolQueue()
        end)
        if not queued then self.poolKick=nil end
    end
    return result
end
function Runtime:tickPoolQueue()
    if not self.alive or self.summonQueue.enabled or self.summonPending then return end
    if self.nextSummonAt and os.clock()<self.nextSummonAt then return end
    self.poolQueue:tick()
end

function Runtime:dispatch(action,command)
    if not self.alive then return end
    local handler=self.handlers[action]
    if not handler then return end
    local ok,result=xpcall(function() return handler(command or {}) end,debug.traceback)
    if not ok then self.log(action.." Lua失败: "..tostring(result)); return end
    self.log(action.." 结果="..tostring(result and result.ok).."；"..tostring(result and result.message))
    return result
end
function Runtime:start()
    if self.started then return self.pumpReady end
    self.started=true
    self.functionKeys:start()
    if self.options.unitKeys then self.options.unitKeys:start() end
    if type(LoopInGameThreadWithDelay)~="function" or type(CancelDelayedAction)~="function" then
        self.log("面板轮询未启动：缺少LoopInGameThreadWithDelay或CancelDelayedAction；未回退异步排队循环")
        return false
    end
    -- 宿主持有一个稳定的周期回调引用；每轮不再注册新的游戏线程闭包。
    local function pumpBody()
        if not self.codexChecked and self.options.codex and self.options.session
            and self.options.session:status().game_ready==true then
            self.codexChecked=true
            local result=self.options.codex:export()
            self.log("原生中文图鉴首次读取="..tostring(result.ok).."；"..tostring(result.message))
        end
        if not self.spawnCatalogChecked and self.options.spawnCatalog and self.options.session
            and self.options.session:status().game_ready==true then
            self.spawnCatalogChecked=true
            local result=self.options.spawnCatalog:export()
            self.log('已加载地图刷怪配置读取='..tostring(result.ok)..'；不是全部World分区覆盖')
        end
        if not self.tableCatalogChecked and self.options.tableCatalog and self.options.session
            and self.options.session:status().game_ready==true then
            self.tableCatalogChecked=true;self.options.tableCatalog:export()
        end
        if not self.areaLevelsChecked and self.options.areaLevels and self.options.session
            and self.options.session:status().game_ready==true then
            self.areaLevelsChecked=true;self.options.areaLevels:export()
            -- The codex and area exports above are what each unit's home level is worked out from.
            if self.options.homeLevels then self.options.homeLevels:refresh() end
        end
        -- The level a summon would get, for the app: map enemies stream in after the world is ready, so it is looked
        -- up every 10 s until some are found, then every 60 s to follow the player into another area.
        if self.options.spawnLevel and self.options.session and self.options.session:status().game_ready==true then
            local now=os.clock()
            if not self.spawnLevelAt or now-self.spawnLevelAt>=(self.spawnLevelFound and 60 or 10) then
                self.spawnLevelAt=now
                self.spawnLevelFound=self.options.spawnLevel:refresh() or self.spawnLevelFound
            end
        end
        if not self.initialScanChecked and (not self.options.fullInventory or (self.options.session and self.options.session:status().game_ready==true)) then
            self.initialScanChecked=true
            local inventoryStatus=self.options.fullInventory and read(self.options.path..'/asset-index-status.tsv') or nil
            local needed=self.options.fullInventory and (not inventoryStatus or not inventoryStatus:find('\ncomplete\ttrue\n',1,true))
                or (not self.options.fullInventory and not read(self.options.path..'/catalog.tsv'))
            if self.options.autoScan and needed then
                local started,state=self.options.exporter:start()
                self.log("首次目录自动读取="..tostring(started).."；读回状态="..tostring(state.reason))
            end
        end
        self.options.exporter:tick()
        if self.options.references then
            local inventory=self.options.exporter:status()
            if not self.referencesStarted and not inventory.active and inventory.paths_total>0
                and inventory.paths_done==inventory.paths_total and self.options.exporter.referencePackages then
                self.referencesStarted=true;self.options.references:start(self.options.exporter:referencePackages())
            end
            self.options.references:tick()
        end
        if self.options.spectator then self.options.spectator:tick() end
        self:tickPoolQueue()
        self.healthTicks=(self.healthTicks or 0)+1
        if self.healthTicks%4==0 and self.options.arena.sampleHealth then self.options.arena:sampleHealth() end
        if self.healthTicks%2==0 and self.options.support then self.options.support:tick() end
        self.bridge:tick()
    end
    -- A whole pump slower than 15 ms is logged (at most 60 times per Lua lifetime) to find stutter; every minute a summary
    -- of all pumps keeps coming after that (perf_meter.lua). Pumps run every 250 ms: a gap of 400 ms is a stalled game thread.
    local slowPumps=0
    local pumpMeter=require('perf_meter').new({label='面板轮询',log=function(line)self.log(line)end,slow=15,hitch=400})
    self.pumpCallback=function()
        if not self.alive or not self.pumpReady then return end
        local started=os.clock()
        local ok,err=xpcall(pumpBody,debug.traceback)
        local spent=(os.clock()-started)*1000
        if spent>=15 and slowPumps<60 then
            slowPumps=slowPumps+1
            self.log(string.format('[Perf] 面板轮询耗时 %.1fms',spent))
        end
        pumpMeter:add(spent,started)
        if not ok and self.lastError~=tostring(err) then
            self.lastError=tostring(err); self.log("面板轮询失败: "..tostring(err))
        end
        -- 此API忽略回调返回值；停止必须明确CancelDelayedAction(handle)。
    end
    local ok,handle=pcall(LoopInGameThreadWithDelay,250,self.pumpCallback)
    if not ok or handle==nil or handle==false then
        self.log("面板轮询注册未确认："..tostring(handle).."；未回退异步排队循环")
        return false
    end
    self.pumpHandle=handle
    self.pumpReady=true
    self.log("面板周期任务已注册；handle读回="..tostring(handle).."；实际心跳待tick验证；目录: "..self.options.path)
    return true
end
function Runtime:silence()
    self.alive=false
    if self.summonQueue.enabled then self:setSummonQueue(false) end
    self.poolQueue.enabled=false;self.poolQueue.jobs={}
    self.functionKeys:silence();self.router:silence()
    if self.options.unitKeys then self.options.unitKeys:silence() end
    self.pumpReady=false
    if self.pumpHandle~=nil then
        local handle=self.pumpHandle
        local ok,result=pcall(CancelDelayedAction,handle)
        self.log("面板宿主任务取消调用="..tostring(ok).."；handle="..tostring(handle).."；返回="..tostring(result).."；未执行游戏对象恢复")
        if ok and result~=false then self.pumpHandle=nil end
    end
    self.options.exporter:silence("Mod卸载")
    if self.options.references then self.options.references:silence('Mod卸载') end
    if self.options.spectator then self.options.spectator:silence("Mod卸载") end
end
return Runtime
