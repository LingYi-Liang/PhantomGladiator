-- Riders: units the game seats on a mount of their own when their AI starts. Their blueprint carries an
-- AIScript_Rider (/PBZCombatAsset/Prototypes/AI/AIScript_Rider) that takes the mount's place from the unit's own
-- spawner (GetAISpawner():GetTransform()), spawns a BP_AISpawner_C there for the mount and drives it. A summoned
-- unit has no spawner: the call gave a default transform, the mount came at the world origin and carried the
-- rider off with it, so only its health bar stayed in the arena (亡命徒：荆野).
-- Found offline in the game files: the nine classes below carry the script.
-- Before FinishSpawn a rider gets an empty spawner of the mod's at its summon transform: Class unset and
-- InitialSpawn off, so it spawns nothing itself, and SpawnerID marks it as the mod's (spawn_level.lua does not take
-- a unit sitting on it for a map enemy). It goes straight into the rider's Spawner variable, so OnSpawnFromSpawner
-- and its Init Level do not run. Then the mount is read from the rider (BP_SGameDriverComponent.DrivingVehicle)
-- with the spawner the script made for it, and all three leave with the rider.
local U=require('ue_observe')
local Mounts={}
local SPAWNER='/SGameAI/Tools/Spawner/BP_AISpawner.BP_AISpawner_C'
Mounts.TAG='PhantomGladiator_Mount'
local RIDERS={
    BP_Monster_JingYe=true,                                            -- 亡命徒：荆野, on BP_Monster_Horse_JingYe
    BP_Monster_Bandit_Sword_Rider=true,                                -- 马匪, on BP_Monster_Horse_MonsterHorse
    BP_Monster_SpearMan_Spear_Blue_Rider=true,                         -- 无面枪骑兵, on BP_Monster_Horse_MonsterHorse
    BP_Monster_GuiChai_Black_Gun_Rider=true,                           -- on BP_Monster_Horse_GuiChaiHorse_HorseCartCombat
    BP_Monster_GuiChai_Black_TwinBlade_Rider=true,
    BP_Monster_GuiChai_Black_Gun_Rider_HorseCartCombat_L=true,         -- 鬼差火枪骑兵
    BP_Monster_GuiChai_Black_Gun_Rider_HorseCartCombat_R=true,
    BP_Monster_GuiChai_Black_TwinBlade_Rider_HorseCartCombat_L=true,   -- 鬼差骑兵
    BP_Monster_GuiChai_Black_TwinBlade_Rider_HorseCartCombat_R=true,
}
-- Bosses that aim a move at their own spawner (GetAISpawner): 雷当：独臂虎's leap GA_LeiDang_P2_CA lands on it, its
-- warning, sound and bullet burst start there and his falling rocks fall toward it; 冷荼's bullet burst
-- GA_LengTu_SA_01 starts there (GAA_BulletBurstWithDeflect origin 7). Summoned, that was the world origin. They get
-- the same quiet spawner at their summon point; no mount is looked for.
local ANCHORED={
    BP_Monster_LeiDang_P2=true,                                        -- 雷当：独臂虎
    BP_Monster_LeiDang_P2_ForSeq=true,
    BP_Monster_LengTu=true,                                            -- 梦差：冷荼
}
local WAIT=15        -- seconds a rider may take to get on its mount before the log says it never did
local NEAR=50        -- cm: the script puts the mount's spawner exactly where ours stands

function Mounts.isRider(className)
    return type(className)=='string' and RIDERS[(className:gsub('_C$',''))]==true
end

function Mounts.isAnchored(className)
    return type(className)=='string' and ANCHORED[(className:gsub('_C$',''))]==true
end

-- Whether a spawner is one of the mod's (its SpawnerID carries the tag).
function Mounts.isOurs(spawner)
    if not U.valid(spawner) then return false end
    local id=U.field(spawner,'SpawnerID')
    local ok,name=pcall(function()return id:ToString()end)
    return ok and name==Mounts.TAG
end

function Mounts.new(options)
    local log=options.log or function()end
    local now=options.now or os.clock
    local self={records={},prepared=0,mounted=0,released=0,failures=0}
    local function say(text)log('[Mount] '..text)end
    local function className(actor)
        local ok,name=pcall(function()return actor:GetClass():GetFName():ToString()end)
        return ok and type(name)=='string' and name or '?'
    end
    local function where(actor)
        local at=U.valid(actor) and options.location and options.location(actor) or nil
        return at and type(at.X)=='number' and at or nil
    end
    local function metres(a,b)
        if not a or not b then return nil end
        local dx,dy,dz=a.X-b.X,a.Y-b.Y,a.Z-b.Z
        return math.sqrt(dx*dx+dy*dy+dz*dz)/100
    end
    local function gone(actor)
        if not U.valid(actor) then return true end
        local ok,destroying=pcall(options.isDestroying,actor)
        return ok and destroying==true
    end
    -- Destroys one actor of a rider's and reads it back.
    local function remove(actor,label)
        if actor==nil then return label..'=无' end
        if gone(actor) then return label..'=已不在' end
        local ok,err=pcall(options.destroy,actor)
        local after=gone(actor)
        if not after then self.failures=self.failures+1 end
        return label..'='..className(actor)..' 调用='..tostring(ok)..' 读回='..(after and '已移除' or '仍在')..(ok and '' or ' 错误='..tostring(err))
    end

    -- Before FinishSpawn. Neither a rider nor anchored to its spawner: nothing happens and nil comes back.
    function self:prepare(rider,transform,world)
        local name=className(rider)
        local isRider=Mounts.isRider(name)
        if not isRider and not Mounts.isAnchored(name) then return nil end
        local kind=isRider and '骑兵' or 'BOSS'
        local key=U.key(rider)
        local cls=options.findClass and options.findClass(SPAWNER)
        local lib=options.statics and options.statics()
        if not key or not U.valid(cls) or not U.valid(lib) or not U.valid(world) then
            self.failures=self.failures+1
            say(string.format('%s %s：刷怪点类=%s 函数库=%s World=%s，不能放刷怪点；照旧生成，%s',kind,name,
                tostring(U.valid(cls)),tostring(U.valid(lib)),tostring(U.valid(world)),isRider and '坐骑会出在世界原点' or '按刷怪点放的招式会朝世界原点'))
            return {ok=false}
        end
        local began,spawner=pcall(function()return lib:BeginDeferredActorSpawnFromClass(world,cls,transform,1,nil,1)end)
        spawner=began and U.unwrap(spawner) or nil
        if not U.valid(spawner) then
            self.failures=self.failures+1
            say(kind..' '..name..'：刷怪点生成未返回有效对象（'..tostring(began and 'nil' or spawner)..'）；照旧生成')
            return {ok=false}
        end
        -- Before it begins play: InitialSpawn would make it spawn its Class (unset) at once.
        local quiet=pcall(function()spawner.InitialSpawn=false end)
        local tagged=pcall(function()spawner.SpawnerID=FName(Mounts.TAG)end)
        local finished,finishError=pcall(function()lib:FinishSpawningActor(spawner,transform,1)end)
        local record={rider=rider,key=key,name=name,kind=kind,anchorOnly=not isRider,spawner=spawner,at=now(),
            origin=where(spawner) or (transform and transform.Translation)}
        self.records[key]=record
        local initial=U.field(spawner,'InitialSpawn')
        local written,writeError=pcall(function()rider.Spawner=spawner end)
        local linked=U.key(U.field(rider,'Spawner'))==U.key(spawner)
        if linked then self.prepared=self.prepared+1 else self.failures=self.failures+1 end
        say(string.format('%s %s：在召唤点放刷怪点 %s 完成生成=%s InitialSpawn 写入=%s 读回=%s 标记 写入=%s 读回=%s；写进 Spawner 调用=%s 读回=%s%s',
            kind,name,className(spawner),tostring(finished),tostring(quiet),tostring(initial),tostring(tagged),tostring(Mounts.isOurs(spawner)),
            tostring(written),tostring(linked),
            (finished and '' or ' 生成错误='..tostring(finishError))..(written and '' or ' 写入错误='..tostring(writeError))))
        return {ok=linked}
    end

    -- The spawner the rider's script made for the mount: its SpawnedAI is the mount, or it stands where ours does.
    local function mountSpawner(record,mount)
        local ok,list=pcall(options.findAll,'BP_AISpawner_C')
        if not ok or type(list)~='table' then return nil end
        local ours=U.key(record.spawner)
        local mountKey=mount and U.key(mount)
        for _,spawner in ipairs(list)do
            local key=U.key(spawner)
            if key and key~=ours then
                local spawned=U.key(U.field(spawner,'SpawnedAI'))
                if mountKey and spawned==mountKey then return spawner end
                local d=not mountKey and spawned and metres(where(spawner),record.origin)
                if d and d*100<NEAR then return spawner end
            end
        end
    end

    function self:release(record,why)
        if not record then return end
        self.records[record.key]=nil
        self.released=self.released+1
        local parts={remove(record.mount,'坐骑'),remove(record.vehicleSpawner,'坐骑刷怪点'),remove(record.spawner,'Mod刷怪点')}
        say((record.kind or '骑兵')..' '..record.name..' '..why..'，一并移除：'..table.concat(parts,'；'))
    end

    -- After the rider is destroyed (the arena's own clean-up).
    function self:releaseActor(rider,why)
        local key=U.key(rider)
        if key then self:release(self.records[key],why or '已清理') end
    end

    function self:tick()
        local t=now()
        for key,record in pairs(self.records)do
            if gone(record.rider) then self:release(record,'已不在场上')
            elseif not record.anchorOnly and not record.mount and not record.gaveUp then
                local mount=U.field(U.field(record.rider,'BP_SGameDriverComponent'),'DrivingVehicle')
                local late=t-record.at>WAIT
                local vehicleSpawner
                if not U.valid(mount) and late then
                    -- Never got on: its mount may still stand by the spawner the script made.
                    vehicleSpawner=mountSpawner(record,nil)
                    mount=vehicleSpawner and U.field(vehicleSpawner,'SpawnedAI') or nil
                end
                if U.valid(mount) and U.key(mount)~=key then
                    record.mount=mount
                    record.vehicleSpawner=vehicleSpawner or mountSpawner(record,mount)
                    self.mounted=self.mounted+1
                    local at,origin=where(mount),record.origin
                    say(string.format('骑兵 %s：坐骑 %s %s，%.1f 秒，位置=%s 离召唤点=%s 米；坐骑的刷怪点=%s',record.name,className(mount),
                        late and '没骑上（按刷怪点找到）' or '已骑上',t-record.at,
                        at and string.format('%.0f,%.0f,%.0f',at.X,at.Y,at.Z) or '?',
                        metres(at,origin) and string.format('%.1f',metres(at,origin)) or '?',
                        record.vehicleSpawner and className(record.vehicleSpawner) or '没找到'))
                elseif late then
                    record.gaveUp=true;self.failures=self.failures+1
                    say(string.format('骑兵 %s：%d 秒内没骑上坐骑，也没找到坐骑的刷怪点',record.name,WAIT))
                end
            end
        end
    end

    -- The mounts and spawners the mod holds, by address: not map enemies (spawn_level.lua).
    function self:keys()
        local keys={}
        for _,record in pairs(self.records)do
            for _,actor in ipairs({record.mount,record.vehicleSpawner,record.spawner})do
                local key=U.key(actor)
                if key then keys[key]=true end
            end
        end
        return keys
    end

    function self:count()
        local n=0
        for _ in pairs(self.records)do n=n+1 end
        return n
    end

    function self:status()
        return {mount_riders=self:count(),mount_prepared=self.prepared,mount_mounted=self.mounted,
            mount_released=self.released,mount_failures=self.failures}
    end
    return self
end
return Mounts
