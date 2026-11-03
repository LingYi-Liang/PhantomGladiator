-- PhantomGladiator 配置
-- ============================================================
-- v0.16：新增F8无仇恨观战与销毁状态读回，所有周期工作在游戏线程执行。
-- 操作和恢复边界见 docs/HANDOFF.md。
-- ============================================================

local Config = {}
-- The app's installer writes the player's own game folder here.
Config.RuntimePath = "C:/Program Files (x86)/Steam/steamapps/common/PBZ/platform/steam/ue4ss/Mods/PhantomGladiator/Runtime"
Config.CatalogPath = Config.RuntimePath .. "/known-classes.tsv"
-- 来自原生图鉴/已观察实例的完整路径；仅普通暴徒开放有限测试，许可不等于验收。
Config.KnownMonsterClasses = {
    "/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue.BP_Monster_MaleThug_Sword_Blue_C",
    "/PBZCombatAsset/ActorData/Mobs/023_Vessel_Child/BP_Monster_Vessel_Child.BP_Monster_Vessel_Child_C",
}
Config.AssetCatalog = {PathsPerTick=32,MaxSeconds=1800}
-- 只限制旧的全场互殴/全场中立；F3/F9的一对参赛者流程默认可用。
Config.EnableBattleExperiments = false
-- 曾两次在同一地址原生崩溃，其中一次紧邻玩家Health Post Func回调。
-- 关闭诊断挂钩做隔离验证；游戏互斗依靠原生流程，不依赖这些hook。
Config.Probe = {Enabled=false,DurationMs=60000,MaxEvents=2000,MaxLogs=100,MaxLogsPerHook=12}

-- 敌人搜索：FindAllOf 会按这些类名找 Pawn。
-- 使用本地头文件确认的NPC基类；仍不能据此保证都是可用于竞技场的敌人。
Config.EnemyClasses = { "PBZCharacter_NPC" }

-- 类名里含有这些关键词的 Pawn 视为玩家/友方，永不参与斗蛐蛐
Config.ExcludeClassKeywords = { "Player", "Hero", "Soul", "Protagonist",
    -- 影之刃零: 主角"魂"的 Blueprint 类 (实测)
    "Renewal_Hun" }

-- 全局互殴时把敌人分成几个阵营（2 = 捉对厮杀，更大 = 混战）
Config.TeamCount = 2
-- 八项功能统一在面板改键，首次使用全部留空；相机保留玩家控制器。
-- Saved function bindings live in Runtime/function-keybinds.tsv; no default keys.
Config.EnableDeveloperKeybinds = false
Config.FreeCamera = { MoveSpeed = 900, MouseSensitivity = 1.0 }
-- Existing native hit-triggered grabs; snapshots restore the shared event resources on F4.
Config.EnableNPCGrabs = true
Config.EnableGrabStudy = false
-- 召唤后只读记录召唤单位和参照地图怪的数值来源（等级曲线、难度系数），每只约14行日志；调查数值时再开。
Config.EnableStatFormulaProbe = false
-- 召唤的第一只蓝/红方单位把223项属性逐项写入测试值、隔0.5秒读回再恢复，每项一行日志，约15秒；核对自定义数值时再开。
Config.EnableStatFieldProbe = false
-- 随从在场时只读记录它的每种攻击（类型、打谁、能否打同阵营、能否打到玩家）和玩家掉血；查随从范围攻击误伤玩家时再开。
Config.EnableCompanionHitProbe = false
-- 每分钟把已加载的全部攻击数据过一遍，列出设成「打友方/都打/能打同阵营」的（只读，明细写入 Runtime/attack-faction-scan.tsv）。
Config.EnableAttackFactionScan = false
-- 进游戏20秒后，把几只怪的图鉴图片（图标/高清图/半身像）存成 PNG 到 Runtime，看能不能本地导出给助手显示。
Config.EnableCodexArtProbe = false
-- 进游戏后在后台把图鉴头像（白色图标，头肩像）存到本机 Runtime/codex-icons/，给助手的单位卡片用；游戏图片不随助手发布。
Config.EnableCodexIcons = true
-- 随从头顶显示游戏自带的血条（和小兵一样）；关掉后不再管随从的头顶血条。
Config.ShowCompanionHealthBars = true
-- 召唤驯犬客时同队带上2只狂犬（他老家血色森林的摆法，escorts.lua），狗的等级跟他一样、不参与数值统一；关掉就只召唤驯犬客本人。
Config.SummonEscorts = true
-- 召唤骑兵（荆野、马匪、无面枪骑兵、鬼差骑兵等）时，在召唤点给它放一个空的刷怪点，坐骑就刷在这里（mounts.lua）；
-- 清理时坐骑和刷怪点一起移除。关掉就和原来一样：坐骑刷到世界原点，人跟着被带走，擂台上只剩血条。
Config.SummonRiderMounts = true
-- 实验：擂台里的怪到了玩家能处决它的时候（破防或血量低于处决线，游戏自己挂的标记），或锁血 BOSS 卡在锁血线 1 秒，
-- 由最近的对手用游戏原版那对处决技能处决它（对手先转向目标，借玩家的骨架做动作，会穿模；动作播完才收尾）。
-- 有成对处决动作的怪才会被处决；锁血 BOSS 播完还站着就去掉锁血、判死（arena_executions.lua）。关掉就和原来一样。
Config.EnableArenaExecutions = true

-- 历史碰撞复制实验，默认关；响应差异不证明实际攻击查询通道。
Config.CopyPlayerHurtChannels = false

-- 可选的NPC阵营标签实验，默认不改；不能据此推定攻击模块同样敌对。
Config.SwitchFactionTo = ""

-- 召唤位置：玩家前方多少厘米、抬高多少厘米
Config.SummonDistance = 600
Config.SummonHeightOffset = 50

-- 慢动作档位（循环切换）
Config.TimeDilationSteps = { 1.0, 0.5, 0.2, 0.05 }

return Config
