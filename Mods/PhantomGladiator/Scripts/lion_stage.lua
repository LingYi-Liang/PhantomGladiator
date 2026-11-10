-- The real Lion Dance trigger volume owns pole selection, registration and player input.
-- Its map instances have baked collision. A runtime-spawned instance needs a query shape.
local U = require('ue_observe')
local LionStage = {}

local BOSS = '/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_LionDancer_P2.BP_Monster_LionDancer_P2_C'
local AREA = '/Game/PBZContent/Blueprint/TriggerVolume/BP_LionDance_Area.BP_LionDance_Area_C'
local AREA_NAME = 'BP_LionDance_Area_C'
local MESH_LIBRARY = '/Script/GeometryScriptingCore.Default__GeometryScriptLibrary_MeshPrimitiveFunctions'
local COLLISION_LIBRARY = '/Script/GeometryScriptingCore.Default__GeometryScriptLibrary_CollisionFunctions'
local WIDTH, HEIGHT, UP = 10400, 3800, 360
local FADE_SECONDS = 4.5 -- the native pole deactivation timelines wait four seconds

local function call(object, method, ...)
    if not U.valid(object) then return false end
    local ok, result = pcall(function(target, key, ...) return target[key](target, ...) end, object, method, ...)
    return ok, U.unwrap(result)
end

local function identity(location)
    return {Translation=location, Rotation={X=0,Y=0,Z=0,W=1}, Scale3D={X=1,Y=1,Z=1}}
end

local function belongsTo(object, owner)
    local key = U.key(owner)
    if not key then return false end
    for _=1,5 do
        local current = U.key(object)
        if not current then return false end
        if current == key then return true end
        local ok, outer = call(object, 'GetOuter')
        if not ok then return false end
        object = outer
    end
    return false
end

local function sameActor(a, b)
    local key = U.key(a)
    return key ~= nil and key == U.key(b)
end

function LionStage.new(options)
    local self = {}
    local log = options.log or function() end
    local find = options.find or StaticFindObject
    local load = options.load or LoadAsset
    local findAll = options.findAll or FindAllOf
    local name = options.fname or FName
    local active

    local function say(message)
        log('[LionStage] '..message)
    end

    local function gone(actor)
        if not U.valid(actor) then return true end
        local ok, destroying = pcall(options.isDestroying, actor)
        return ok and destroying == true
    end

    local function findObject(path)
        local ok, object = pcall(find, path)
        return ok and U.valid(object) and object or nil
    end

    local function areaClass()
        local cls = findObject(AREA)
        if not cls then
            local ok, loaded = pcall(load, AREA)
            cls = ok and U.valid(loaded) and loaded or findObject(AREA)
        end
        local ok, full = call(cls, 'GetFullName')
        return ok and full == 'BlueprintGeneratedClass '..AREA and cls or nil
    end

    local function overlaps(actor, area)
        if not U.valid(area) then return nil end
        local ok, hit = call(actor, 'IsOverlappingActor', area)
        if ok and type(hit) == 'boolean' then return hit end
    end

    local function nearbyArea(actor, world)
        local ok, objects = pcall(findAll, AREA_NAME)
        if not ok then return nil, false end
        local list = objects == nil and {} or U.array(objects)
        if not list then return nil, false end
        for _, area in ipairs(list) do
            if not gone(area) and U.inWorld(area, world) then
                local hit = overlaps(actor, area)
                if hit == nil then return nil, false end
                if hit then return area, true end
            end
        end
        return nil, true
    end

    local function destroy(actor)
        if gone(actor) then return true end
        call(actor, 'K2_DestroyActor')
        return gone(actor)
    end

    local function buildTrigger(area, primitives, collisions)
        local component = U.field(area, 'DynamicMeshComponent')
        local okMesh, mesh = call(component, 'GetDynamicMesh')
        -- Never write the class template's mesh or one shared by another volume.
        if not okMesh or not belongsTo(component, area) or not belongsTo(mesh, area) then
            return false, '新场地的独立网格未读回'
        end
        local sync = pcall(function()component.bUseAsyncCooking=false end)
        if not sync or U.field(component,'bUseAsyncCooking')~=false then
            return false, '场地同步碰撞设置未读回'
        end
        if not call(component, 'SetDeferredCollisionUpdatesEnabled', true, false)
            or not call(component, 'SetComplexAsSimpleCollisionEnabled', false, false)
            or not call(mesh, 'Reset') then
            return false, '场地网格初始化未确认'
        end
        if not U.valid(mesh) then return false, '独立场地网格已失效' end
        local okBox, result = call(primitives, 'AppendBox', mesh,
            {PolygroupMode=0,bFlipOrientation=false,UVMode=0,MaterialID=0},
            identity({X=0,Y=0,Z=0}), WIDTH, WIDTH, HEIGHT, 0, 0, 0, 0, nil)
        if not okBox or not sameActor(mesh, result) then return false, '场地碰撞体积生成未读回' end
        if not U.valid(component) or not call(collisions, 'SetDynamicMeshCollisionFromMesh', mesh, component,
            {bEmitTransaction=false,Method=0,bAutoDetectBoxes=true,MinThickness=1}, nil)
            or not call(component, 'SetDeferredCollisionUpdatesEnabled', false, true)
            or not call(component, 'UpdateCollision', false) then
            return false, '场地碰撞更新未确认'
        end
        local setup = U.field(component, 'MeshBodySetup')
        local boxes = U.array(U.struct(U.field(setup, 'AggGeom'), 'BoxElems'))
        if not call(component, 'SetCollisionProfileName', name('Profile_Trigger'), false)
            or not call(component, 'SetCollisionResponseToChannel', 1, 1)
            or not call(component, 'SetCollisionResponseToChannel', 2, 1)
            or not call(component, 'SetCollisionResponseToChannel', 19, 1)
            or not call(component, 'SetCollisionEnabled', 1)
            or not call(component, 'SetGenerateOverlapEvents', true)
            or not call(area, 'SetActorEnableCollision', true) then
            return false, '场地重叠未启用'
        end
        local modeRead, mode = call(component, 'GetCollisionEnabled')
        return modeRead and tonumber(mode) == 1,
            '场地碰撞模式='..tostring(mode)..' 碰撞盒数='..(boxes and tostring(#boxes) or '未读取')
    end

    local function registered(area, actor)
        for _, inside in ipairs(U.array(U.field(area, 'InTriggerActors')) or {}) do
            if sameActor(inside, actor) then return true end
        end
        return false
    end

    local function enter(area, actor)
        if not registered(area, actor) and overlaps(actor, area) == true then
            call(area, 'TryUpdateActorInTriggerState', actor, true)
        end
        return registered(area, actor)
    end

    local function snapshot(record)
        local area = record.area
        local checked = true
        local parts, seen = {}, {}
        local function add(field, links)
            local list = U.array(U.field(area, field))
            if not list then checked = false; return end
            for _, actor in ipairs(list) do
                if not gone(actor) then
                    local owned
                    if links then
                        local a = U.field(actor, 'LinkedPoleA')
                        local b = U.field(actor, 'LinkedPoleB')
                        owned = sameActor(U.field(a,'Area'), area) and sameActor(U.field(b,'Area'), area)
                    else
                        owned = sameActor(U.field(actor,'Area'), area)
                    end
                    if owned then
                        local key = U.key(actor)
                        if not seen[key] then seen[key] = true; parts[#parts+1] = actor end
                    else
                        checked = false
                    end
                else
                    checked = false
                end
            end
        end
        add('ActivatedLinks', true)
        add('DeactivatedLinks', true)
        add('ActivatedPoles', false)
        add('DeactivatedPoles', false)
        return parts, checked
    end

    local function close(record, why)
        if record.closing then return end
        record.closing = true
        record.parts = {}
        if not gone(record.area) and U.inWorld(record.area, record.world) then
            local deactivated, complete = false, true
            if record.finished then
                record.parts, complete = snapshot(record)
                -- ForceExit must run while the poles and player ability still exist.
                if complete then deactivated = call(record.area, 'DeactivateAllPoles') end
                call(record.area, 'SetEnabled', false)
            end
            local stopped = call(record.area, 'SetActorEnableCollision', false)
            local collisionRead, collision = call(record.area, 'GetActorEnableCollision')
            say(string.format('退出舞狮场地 %s 下桩调用=%s 碰撞关闭调用=%s 碰撞读回=%s 自有桩/连接=%d',
                why,tostring(deactivated),tostring(stopped),collisionRead and tostring(collision) or '未读取',#record.parts))
        end
        record.closedAt = options.now()
    end

    function self:prepare(actor, path, world, escort)
        if path ~= BOSS or escort then return true end
        local actorKey=U.key(actor)
        if not actorKey or not U.valid(world) or gone(actor) or not U.inWorld(actor, world) then
            return false, '烈焰场地准备时角色或地图无效'
        end
        if active and not sameActor(active.world, world) then active = nil end
        if active and active.closing then self:tick() end
        local cls = areaClass()
        if not cls then return false, '舞狮场地蓝图类未读回' end
        local existing, checked = nearbyArea(actor, world)
        if not checked then return false, '烈焰身边的舞狮区域无法读回' end
        if existing then
            if active and sameActor(existing, active.area) then
                if active.closing or not active.ready then return false, '舞狮场地还在清理' end
                active.bosses[actorKey] = actor
            end
            say('烈焰已重叠舞狮区域，沿用当前场地 读回=true')
            return true
        end
        if active then return false, '上一处召唤舞狮场地仍在使用或清理，请先清理' end
        local player = options.player()
        if U.valid(player) then
            local playerArea, playerChecked = nearbyArea(player, world)
            if not playerChecked or playerArea then
                return false, '玩家已在舞狮区域或区域读回未确认，请把烈焰召唤到同一场地'
            end
        end
        local at = options.location(actor)
        local statics = options.statics()
        local primitives, collisions = findObject(MESH_LIBRARY), findObject(COLLISION_LIBRARY)
        if not at or type(at.X) ~= 'number' or type(at.Y) ~= 'number' or type(at.Z) ~= 'number'
            or not U.valid(cls) or not U.valid(statics) or not primitives or not collisions then
            return false, '舞狮场地所需的类、位置或碰撞工具未读回'
        end
        local transform = identity({X=at.X,Y=at.Y,Z=at.Z+UP})
        local began, area = call(statics, 'BeginDeferredActorSpawnFromClass', world, cls, transform, 1, actor, 1)
        if not began or not U.valid(area) then
            say('舞狮场地生成返回对象未确认')
            return false, '舞狮场地生成未确认'
        end
        local record = {area=area,world=world,bosses={[actorKey]=actor}}
        active = record
        local disabled = call(area, 'SetActorEnableCollision', false)
        local finished = disabled and not gone(area) and call(statics, 'FinishSpawningActor', area, transform, 1)
        record.finished = finished
        local built, detail = false, '场地初始化未确认'
        if finished and U.inWorld(area, world) and sameActor(U.field(area,'Owner'), actor) then
            built, detail = buildTrigger(area, primitives, collisions)
        end
        local bossInside = built and overlaps(actor, area) == true
        record.ready = bossInside
        local aiRegistered = bossInside and enter(area, actor)
        local playerInside = U.valid(player) and built and overlaps(player, area) == true
        local playerRegistered = playerInside and enter(area, player)
        say(string.format('烈焰舞狮区域 %s Boss重叠=%s 登记=%s 玩家重叠=%s 登记=%s',
            tostring(detail),tostring(bossInside),tostring(aiRegistered),tostring(playerInside),tostring(playerRegistered)))
        if not bossInside or not aiRegistered or (playerInside and not playerRegistered) then
            close(record, '场地读回失败')
            return false, '烈焰舞狮区域重叠或登记未确认，请先停止并清理'
        end
        return true
    end

    function self:areaFor(actor, world)
        if gone(actor) or not U.inWorld(actor, world) then return nil end
        if active and active.ready and not active.closing and sameActor(active.world, world)
            and not gone(active.area) and overlaps(actor, active.area) == true then
            return active.area
        end
        local area, checked = nearbyArea(actor, world)
        return checked and area or nil
    end

    function self:releaseActor(actor)
        local key = U.key(actor)
        if not active or not key or not active.bosses[key] then return end
        active.bosses[key] = nil
        if not next(active.bosses) then close(active, '停止或清理') end
    end

    function self:tick()
        local record = active
        if not record then return end
        local world = options.world()
        if not U.valid(world) then return end
        if not sameActor(world, record.world) or gone(record.area) or not U.inWorld(record.area, world) then
            active = nil
            return
        end
        if not record.closing then
            for key, actor in pairs(record.bosses) do
                local hp = not gone(actor) and options.hp(actor)
                if gone(actor) or (type(hp) == 'number' and hp <= 0) then record.bosses[key] = nil end
            end
            if not next(record.bosses) then close(record, '烈焰离场') end
            return
        end
        local now = options.now()
        if #record.parts > 0 and (type(now) ~= 'number' or type(record.closedAt) ~= 'number'
            or now-record.closedAt < FADE_SECONDS) then return end
        local remaining = {}
        for _, actor in ipairs(record.parts) do
            if U.inWorld(actor, record.world) and not destroy(actor) then remaining[#remaining+1] = actor end
        end
        record.parts = remaining
        if #remaining == 0 and destroy(record.area) then
            say('舞狮场地与已登记自有桩、连接清理 读回=true')
            active = nil
        end
    end

    function self:count() return active and 1 or 0 end
    return self
end

return LionStage
