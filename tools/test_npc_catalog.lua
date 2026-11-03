-- 纯 Lua 目录/持久化/加载边界测试，不证明游戏资产能加载或NPC能战斗。
local Catalog = dofile("Mods/PhantomGladiator/Scripts/npc_catalog.lua")
local tests = 0
local function test(name, body)
    body()
    tests = tests + 1
    print("PASS " .. name)
end

local function obj(fullName, fields)
    local value = fields or {}
    value.alive, value.fullName = true, fullName
    function value:GetFullName() assert(self.alive) return self.fullName end
    function value:IsAnyClass() assert(self.alive) return self.isClass == true end
    function value:GetSuperStruct() assert(self.alive) return self.parent end
    function value:GetClass() assert(self.alive) return self.class end
    function value:K2_GetActorLocation() assert(self.alive) return self.location end
    return value
end
local function valid(value) return type(value) == "table" and value.alive == true end
local base = obj("Class /Script/ProjectPBZ.PBZCharacter_NPC", { isClass = true })
local otherBase = obj("Class /Script/Engine.Actor", { isClass = true })
local function classPath(name) return "/Test/" .. name .. "." .. name .. "_C" end
local function class(name, parent)
    return obj("BlueprintGeneratedClass " .. classPath(name), { isClass = true, parent = parent or base })
end
local function fixture(overrides)
    local f = { classes = {}, objects = {}, logs = {}, loads = {}, staticCalls = {} }
    local options = {
        valid = valid,
        canSpawn = function() return true end, -- Explicit test permission; production must provide its own policy.
        log = function(line) f.logs[#f.logs + 1] = line end,
        findAll = function(name) assert(name == "BlueprintGeneratedClass") return f.classes end,
        findObjects = function(count, kind, shortName)
            if shortName then return {} end
            assert(count == 4096 and kind == "BlueprintGeneratedClass")
            return f.classes
        end,
        staticFind = function(path) f.staticCalls[#f.staticCalls + 1] = path return f.objects[path] end,
        loadAsset = function(path) f.loads[#f.loads + 1] = path return nil, false, false end,
    }
    for k, v in pairs(overrides or {}) do options[k] = v end
    f.options = options
    f.catalog = Catalog.new(options)
    return f
end

test("configured default resolves only its exact path without global discovery", function()
    local path=classPath('BP_Monster_Direct')
    local cls=class('BP_Monster_Direct')
    local f=fixture({knownPaths={path},findAll=function()error('global scan forbidden during summon')end,
        findObjects=function()error('global scan forbidden during summon')end,
        staticFind=function(p)assert(p==path);return cls end})
    assert(f.catalog:selected().path==path)
    assert(f.catalog:resolveSelected()==cls and #f.loads==0)
end)

test("empty battlefield can choose a loaded generated class", function()
    local f = fixture()
    local regular, vessel = class("BP_Monster_Archer"), class("BP_Monster_Vessel_Child")
    f.classes = { regular, vessel }
    local status = f.catalog:refresh({})
    assert(status.known == 2 and status.loaded == 2)
    local selected = f.catalog:selected()
    assert(selected.name == "BP_Monster_Vessel_Child_C" and selected.class == vessel)
end)

test("invalid objects, non NPC classes and base blueprints are rejected", function()
    local f = fixture()
    local dead = setmetatable({ alive = false }, { __index = function() error("invalid dereference") end })
    f.classes = { dead, class("BP_Monster_Fake", otherBase), class("BP_Monster_Test_Base"),
        obj("Actor " .. classPath("BP_Monster_NotClass")) }
    local status = f.catalog:refresh({})
    assert(status.known == 0 and f.catalog:selected() == nil)
end)
test('explicit Actor mode accepts an Actor class and preserves its non-NPC identity',function()
    local f=fixture({allowActors=true})
    local actor=class('BP_Seq_Actor',otherBase)
    f.objects[classPath('BP_Seq_Actor')]=actor
    assert(f.catalog:registerPath(classPath('BP_Seq_Actor')))
    assert(f.catalog:select(classPath('BP_Seq_Actor')))
    assert(f.catalog:resolveSelected()==actor and f.catalog:selected().isNPC==false)
end)

test("an empty directory fails clearly without trying guessed assets", function()
    local f = fixture()
    f.catalog:refresh({})
    local selected, reason = f.catalog:selected()
    assert(selected == nil and type(reason) == "string")
    local resolved, resolveReason = f.catalog:resolveSelected()
    assert(resolved == nil and type(resolveReason) == "string" and #f.loads == 0)
end)

test("duplicate loaded and live registrations share one entry", function()
    local f = fixture()
    local cls = class("BP_Monster_Archer")
    local npc = obj("Actor NPC", { class = cls })
    f.classes = { cls, cls }
    local status = f.catalog:refresh({ npc, npc })
    assert(status.known == 1 and status.loaded == 1)
end)

test("selection persists through reload using non executable text", function()
    local path = os.tmpname()
    local file = assert(io.open(path, "w"))
    file:write("PhantomGladiatorCatalogV1\n")
    file:close()
    local first = fixture({ path = path })
    local archer, vessel = class("BP_Monster_Archer"), class("BP_Monster_Vessel_Child")
    first.classes = { archer, vessel }
    first.catalog:refresh({})
    local selected = first.catalog:next()
    assert(selected.name == "BP_Monster_Archer_C")
    local second = fixture({ path = path })
    second.objects[classPath("BP_Monster_Archer")] = archer
    second.objects[classPath("BP_Monster_Vessel_Child")] = vessel
    second.catalog:refresh({})
    assert(second.catalog:selected().path == selected.path)
    assert(second.catalog:resolveSelected() == archer and #second.loads == 0)
    assert(os.remove(path))
end)

test("nearest valid live NPC precedes the known unloaded fallback", function()
    local known = classPath("BP_Monster_Known")
    local player = obj("Player", { location = { X = 0, Y = 0, Z = 0 } })
    local f = fixture({ knownPaths = { known }, getPlayer = function() return player end })
    local nearClass, farClass = class("BP_Monster_Near"), class("BP_Monster_Far")
    local near = obj("Near", { class = nearClass, location = { X = 10, Y = 0, Z = 0 } })
    local far = obj("Far", { class = farClass, location = { X = 1000, Y = 0, Z = 0 } })
    f.catalog:refresh({ far, near })
    assert(f.catalog:selected().class == nearClass)
end)

test("known concrete path precedes other loaded classes", function()
    local known = classPath("BP_Monster_Known")
    local f = fixture({ knownPaths = { known } })
    f.classes = { class("BP_Monster_Archer") }
    f.catalog:refresh({})
    assert(f.catalog:selected().path == known and f.catalog:selected().class == nil)
end)

test("known unloaded class resolves without any live NPC", function()
    local path = classPath("BP_Monster_Known")
    local generated = class("BP_Monster_Known")
    local loadedPaths, loaded = {}, {}
    local f = fixture({ knownPaths = { path }, staticFind = function(p) return loaded[p] end,
        loadAsset = function(request)
            loadedPaths[#loadedPaths + 1] = request
            if request == path then return nil, false, false end
            assert(request == path:sub(1, -3))
            loaded[path] = generated
            return obj("Blueprint " .. request), true, true
        end })
    local status = f.catalog:refresh({})
    assert(status.known == 1 and status.loaded == 0 and f.catalog:selected().path == path)
    assert(f.catalog:resolveSelected() == generated)
    assert(#loadedPaths == 2 and f.catalog:status().loaded == 1)
end)

test("failed known loading is bounded and never substitutes a Blueprint or base", function()
    local path, attempts = classPath("BP_Monster_Known"), 0
    local f = fixture({ knownPaths = { path }, loadAsset = function(request)
        attempts = attempts + 1
        if attempts == 1 then return nil, false, false end
        return obj("Blueprint " .. request), true, true
    end })
    f.catalog:refresh({})
    local cls, reason = f.catalog:resolveSelected()
    assert(cls == nil and attempts == 2 and reason:find(path, 1, true))
    assert(f.catalog:status().loaded == 0)
end)

test("registered front end path still needs validated class resolution", function()
    local f = fixture()
    assert(f.catalog:registerPath("/Bad/../file.lua") == nil)
    assert(f.catalog:registerPath("/.BP_Monster_Invalid_C") == nil)
    local path = classPath("BP_Monster_Known")
    assert(f.catalog:registerPath(path))
    assert(f.catalog:select(path).class == nil)
    f.objects[path] = class("BP_Monster_Known", otherBase)
    assert(f.catalog:resolveSelected() == nil)
end)

test("FindObjects fallback can discover classes when FindAllOf returns nil", function()
    local cls = class("BP_Monster_Archer")
    local f = fixture({ findAll = function() return nil end,
        findObjects = function(_, _, shortName) return shortName and {} or { cls } end })
    assert(f.catalog:refresh({}).loaded == 1)
    assert(f.catalog:selected().class == cls)
end)

test("non Monster NPC names are discoverable and registered names use inheritance", function()
    local f = fixture()
    f.classes = { class("BP_Boss_Captain"), class("BP_NPC_Guard"), class("BP_Enemy_Scout") }
    assert(f.catalog:refresh({}).loaded == 3)
    local path = classPath("BP_Guard") -- 不含名称提示，来自前端已登记的实际路径。
    local guard = class("BP_Guard")
    f.objects[path] = guard
    assert(f.catalog:registerPath(path))
    assert(f.catalog:select(path).path == path)
    assert(f.catalog:resolveSelected() == guard)
end)

test("a legal generated UI class path cannot pass NPC validation", function()
    local f = fixture()
    local path = classPath("WBP_Inventory")
    f.objects[path] = class("WBP_Inventory", otherBase)
    assert(f.catalog:registerPath(path))
    assert(f.catalog:select(path))
    local resolved, reason = f.catalog:resolveSelected()
    assert(resolved == nil and reason:find("PBZCharacter_NPC", 1, true))
    assert(f.catalog:status().loaded == 0)
end)

test("generated class format still rejects traversal controls base and oversized paths", function()
    local f = fixture()
    for _, path in ipairs({ "/Test/../BP_Guard.BP_Guard_C", "/Test/./BP_Guard.BP_Guard_C",
        "/Test//BP_Guard.BP_Guard_C", "/Test/BP_Guard.BP_Guard_C\t", classPath("BP_NPC_Base"),
        "/" .. string.rep("a", 1024) .. "/BP_Guard.BP_Guard_C" }) do
        assert(f.catalog:registerPath(path) == nil)
    end
end)

test("denied or missing spawn policy blocks lookup and loading even for a cached class", function()
    local path = classPath("BP_Monster_Known")
    for _, mode in ipairs({ "missing", "denied", "throws", "non_boolean" }) do
        local f = fixture()
        if mode == "missing" then f.options.canSpawn = nil
        elseif mode == "denied" then f.options.canSpawn = function(candidate)
            assert(candidate == path) return false, "not verified"
        end
        elseif mode == "throws" then f.options.canSpawn = function() error("policy unavailable") end
        else f.options.canSpawn = function() return "true" end end
        f.catalog = Catalog.new(f.options)
        local entry = assert(f.catalog:registerPath(path))
        entry.class, entry.loaded = class("BP_Monster_Known"), true
        f.objects[path] = entry.class
        assert(f.catalog:select(path))
        local resolved, reason = f.catalog:resolveSelected()
        assert(resolved == nil and type(reason) == "string", mode)
        assert(#f.staticCalls == 0 and #f.loads == 0,
            mode .. ": policy must deny before StaticFindObject or LoadAsset, including a cached UClass")
    end
end)

test("an escort path resolves with its own entry and leaves the selection alone", function()
    local tamerPath, dogPath = classPath('BP_Monster_DogTamer'), classPath('BP_Monster_Dog')
    local tamer, dog = class('BP_Monster_DogTamer'), class('BP_Monster_Dog')
    local denied = {}
    local f = fixture({knownPaths={tamerPath},
        findAll=function()error('global scan forbidden during summon')end,
        findObjects=function()error('global scan forbidden during summon')end,
        canSpawn=function(path) if denied[path] then return false,'policy' end return true end,
        staticFind=function(p) return ({[tamerPath]=tamer,[dogPath]=dog})[p] end})
    assert(f.catalog:resolveSelected()==tamer)
    local cls, reason, entry = f.catalog:resolvePath(dogPath)
    assert(cls==dog and reason==nil and entry.path==dogPath and entry.isNPC==true and entry.source=='escort')
    assert(f.catalog:selected().path==tamerPath,'the selection stays on the tamer')
    assert(select(3,f.catalog:resolvePath(dogPath))==entry,'the same record is reused')
    denied[dogPath]=true
    assert(f.catalog:resolvePath(dogPath)==nil,'the spawn policy still decides')
    assert(f.catalog:resolvePath('not a path')==nil)
end)

print(string.format("%d NPC catalog tests passed; no UE asset loading assertions made.", tests))
