-- 生成观察白名单，不是“保证安全”或“战斗已通过”的声明。
-- 原生图鉴直接敌人的有限试召唤清单由离线核对产生；不等于兼容性通过。
local Policy = {}
local VESSEL = "/PBZCombatAsset/ActorData/Mobs/023_Vessel_Child/BP_Monster_Vessel_Child.BP_Monster_Vessel_Child_C"
local FLAME_DOG = "/PBZCombatAsset/ActorData/Mobs/005_ModDog/BP_Monster_FlameDog.BP_Monster_FlameDog_C"
local SWORD_THUG = "/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue.BP_Monster_MaleThug_Sword_Blue_C"
local SPEAR_THUG = "/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Spear_Blue.BP_Monster_MaleThug_Spear_Blue_C"
local trials,trialCount={},0
local allCatalog=false
function Policy.enableAllCatalog() allCatalog=true end
function Policy.loadTrials(path,log)
    trials,trialCount={},0
    log=log or function() end
    local function fail(reason)
        log('[SpawnPolicy] 读取单只试召唤清单失败；读回=未启用，原因='..tostring(reason))
        return false,reason
    end
    local file=io.open(path,'rb')
    if not file then return fail('清单不存在') end
    local content=file:read(65537);file:close()
    if not content or #content>65536 or not content:match('^PhantomGladiatorSpawnTrialsV1\r?\n') then return fail('格式或大小不符') end
    local parsed,count={},0
    for line in content:gmatch('[^\r\n]+') do
        if line~='PhantomGladiatorSpawnTrialsV1' then
            local class,kind=line:match('^(/[%w_/%-%.]+)\t(%a+)$')
            if not class or #class>512 or (kind~='mob' and kind~='boss') or parsed[class]
                or class==FLAME_DOG or class==VESSEL or class:find('..',1,true) or class:find('//',1,true) then
                return fail('非法、重复或隔离的路径')
            end
            local package,name=class:match('^(.+)%.([%w_%-]+_C)$')
            local asset=package and package:match('([^/]+)$')
            if not asset or asset..'_C'~=name or name:lower():match('_base_c$') then
                return fail('不是具体蓝图类路径')
            end
            count=count+1;if count>256 then return fail('条目超过256') end
            parsed[class]=kind
        end
    end
    trials,trialCount=parsed,count
    log('[SpawnPolicy] 已读取原生图鉴许可；读回='..count..'条；新单位每次1只，已观察暴徒每次最多8只；擂台管理上限24')
    return true
end
function Policy.status()
    return {version=trialCount>0 and 'codex_primary_npc_v1' or '',count=trialCount,mode=allCatalog and 'all_catalog' or 'validated'}
end
function Policy.check(path)
    if allCatalog then
        if type(path)~='string' or #path>512 or not path:match('^/[%w_/%-%.]+$') or path:find('..',1,true) or path:find('//',1,true) then return false,'非法类路径','unverified' end
        local package,name=path:match('^(.+)%.([%w_%-]+_C)$')
        local asset=package and package:match('([^/]+)$')
        if not asset or asset..'_C'~=name then return false,'不是蓝图生成类路径','unverified' end
        return true,'用户开启全部目录尝试召唤；实际Actor类及对象仍需读回验证','experimental_spawn'
    end
    if path == SWORD_THUG then
        return true,"普通持刀暴徒已有生成、受击和NPC互伤死亡实测；每次最多8只，长期稳定性仍待验证","verified_spawn_observation"
    end
    if path == SPEAR_THUG then
        return true,'长枪暴徒已确认生成、AI及正血量；每次最多8只，互斗尚未验收','verified_spawn_observation'
    end
    if path == VESSEL then
        return true,"已有该类的生成与HP读回观察；战斗兼容性未验收","verified_spawn_observation"
    end
    if path == FLAME_DOG then
        return false,"该类召唤曾处于未定位的原生崩溃窗口，暂禁生成（尚未单独定因）","quarantined_incident"
    end
    if type(path)=='string' and trials[path] then
        return true,'原生图鉴直接敌人；允许单只试召唤，生成兼容与战斗尚未实测','controlled_test'
    end
    return false,"该单位尚未完成生成与战斗初始化验证，暂不可直接召唤","unverified"
end
function Policy.limits(path)
    if allCatalog then return nil end
    if path==SWORD_THUG or path==SPEAR_THUG then return {max_count=8,max_live=24} end
    if type(path)=='string' and trials[path] then return {max_count=1,max_live=2} end
end
function Policy.canBattle(path)
    if allCatalog then return Policy.check(path) end
    if path == VESSEL then return false,"机灵鬼自带穿透/无敌特性，不用于互伤测试；请选普通暴徒" end
    return Policy.check(path)
end
function Policy.knownPaths() return {SWORD_THUG,VESSEL} end
return Policy
