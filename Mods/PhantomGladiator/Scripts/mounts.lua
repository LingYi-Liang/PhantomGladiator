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
-- The mount is an AI of its own and does the walking. AIScript_Rider hands it the rider's list (SyncHatredList ->
-- AddActorToHatredList -> CheckCanHatredTarget), which needs the mount hostile to the target; the game's own player is, an
-- arena opponent is not, so the mount stayed idle and the rider swung at the air where it stood. A rider sent at a target
-- now sends its mount as well (fight), which is kept at it (hold) and sent back when it drops out of combat (dropped).
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
local FIGHT_LINES=24 -- log lines about mounts in a fight
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
    local fightLines=0
    local function say(text)log('[Mount] '..text)end
    local function className(actor)
        return U.className(actor) or '?'
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

    -- The mount under a rider right now: nil once it has got off.
    local function riding(record)
        if not record or not U.valid(record.mount) or gone(record.mount) then return nil end
        local current=U.field(U.field(record.rider,'BP_SGameDriverComponent'),'DrivingVehicle')
        return U.valid(current) and U.key(current)==U.key(record.mount) and record.mount or nil
    end
    -- Move the physical carrier, and wait while a rider's initial mount is unresolved.
    function self:carrierOf(rider)
        if gone(rider) then return nil end
        local record=self.records[U.key(rider) or '']
        if not record or record.anchorOnly then return rider end
        local mount=riding(record)
        if mount then return mount end
        if not record.mount and not record.gaveUp then return nil end
        local driver=U.field(rider,'BP_SGameDriverComponent')
        local current,read=U.field(driver,'DrivingVehicle')
        if read and not U.valid(current) then return rider end
        return nil
    end
    local function sayFight(text)
        if fightLines<FIGHT_LINES then fightLines=fightLines+1;say(text) end
    end
    -- A rider was sent at a target. Returns whether a mount went too.
    function self:fight(rider,target)
        local record=self.records[U.key(rider) or '']
        local mount=riding(record)
        if not mount or not U.valid(target) or not options.attack then return false end
        local ok,sent=pcall(options.attack,mount,target)
        record.target=target;record.targetKey=U.key(target)
        sayFight(string.format('骑兵 %s：坐骑 %s 跟着攻击 %s 调用=%s 读回=%s',record.name,className(mount),className(target),tostring(ok),tostring(ok and sent)))
        return ok and sent==true
    end
    -- Every few seconds of a fight: a mount found after the order, or one that dropped out of combat, goes after the target.
    function self:hold(rider,target)
        local record=self.records[U.key(rider) or '']
        local mount=riding(record)
        if not mount or not U.valid(target) then return false end
        if record.targetKey~=U.key(target) then return self:fight(rider,target) end
        if not options.inCombat or not options.engage then return false end
        local okState,combat=pcall(options.inCombat,mount)
        if not okState or combat~=false then return false end
        local ok,engaged,after=pcall(options.engage,mount,target)
        sayFight(string.format('骑兵 %s：坐骑不在战斗状态，重新迎敌 调用=%s 状态读回=%s',record.name,tostring(ok and engaged),tostring(after)))
        return ok and engaged==true
    end
    -- A mount's AI dropped out of combat (combat_lock.lua). True when the address was a mount's.
    function self:dropped(key)
        for _,record in pairs(self.records)do
            if U.key(record.mount)==key then
                local mount=riding(record)
                if mount and U.valid(record.target) and options.engage then pcall(options.engage,mount,record.target) end
                return true
            end
        end
        return false
    end
    -- The mounts carrying a living fighter of blue or red, for the hatred hooks.
    function self:vehicles(members)
        local list={}
        for _,member in ipairs(members or {})do
            local record=(member.team=='blue' or member.team=='red') and self.records[U.key(member.actor) or ''] or nil
            local mount=riding(record)
            local hp=mount and options.hp and options.hp(member.actor)
            if mount and not (type(hp)=='number' and hp<=0) then list[#list+1]={actor=mount,team=member.team,rider=member.actor} end
        end
        return list
    end
    -- Whether an actor is a mount this mod holds: its hatred entry may be written the way a fighter's is.
    function self:holds(actor)
        local key=U.key(actor)
        if not key then return false end
        for _,record in pairs(self.records)do
            if U.key(record.mount)==key then return true end
        end
        return false
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
