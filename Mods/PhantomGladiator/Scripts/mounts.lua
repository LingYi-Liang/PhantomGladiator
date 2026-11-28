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
    local fightLines,aimLines=0,0
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

    function self:placeholderOf(rider)
        local record=self.records[U.key(rider)]
        if record and Mounts.isOurs(record.spawner) then return record.spawner end
    end

    -- Stacked summons and map spawners can share the same position.
    local function scriptMount(record)
        local scripts=options.scripts and options.scripts(record.rider)
        for _,script in ipairs(scripts or {})do
            if U.className(script)=='AIScript_Rider_C' and U.key(U.field(script,'Pawn'))==record.key then
                local mount=U.field(script,'VehiclePawn')
                local spawner=U.field(script,'VehicleSpawner')
                local spawned=U.field(spawner,'SpawnedAI')
                if U.valid(spawned) and (not U.valid(mount) or U.key(spawned)==U.key(mount)) then
                    return spawned,spawner
                end
            end
        end
    end
    local function mountSpawner(record,mount)
        local mountKey=U.key(mount)
        if not mountKey then return nil end
        local own=U.field(mount,'Spawner')
        if U.key(U.field(own,'SpawnedAI'))==mountKey then return own end
        local ok,list=pcall(options.findAll,'BP_AISpawner_C')
        if not ok or type(list)~='table' then return nil end
        local ours=U.key(record.spawner)
        for _,spawner in ipairs(list)do
            local key=U.key(spawner)
            if key and key~=ours then
                if U.key(U.field(spawner,'SpawnedAI'))==mountKey then return spawner end
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

    -- Jing Ye's horse is natively unselectable. Sample the rider separately, after spawn and a change of seat.
    local function read(obj,method,...)
        if not U.valid(obj) then return nil end
        local args={...}
        local ok,value=pcall(function()return obj[method](obj,table.unpack(args))end)
        if ok then return U.unwrap(value) end
    end
    local function lockSnapshot()
        local player=options.player()
        if not U.valid(player) then return end
        local targeting=U.field(player,'Targeting Component')
        local sub=U.field(targeting,'TargetingSubsystem')
        local out={}
        local listed=U.valid(sub) and pcall(function()sub:GetTargetsByTag({TagName=FName('Targeting.Target.Combat')},true,out)end)
        local list=listed and U.array(out.OutTargets or (out[1] and out)) or nil
        local members
        if list then
            members={}
            for _,actor in ipairs(list)do local key=U.key(actor);if key then members[key]=true end end
        end
        local component,known=U.struct(U.field(targeting,'LockTarget'),'Component')
        local locked=U.key(read(component,'GetOwner'))
        return {player=player,listed=members,locked=locked,lockKnown=known and (not U.valid(component) or locked~=nil)}
    end
    local function sampleLock(record,seat,snapshot)
        local rider=record.rider
        local registered=snapshot.listed and tostring(snapshot.listed[record.key]==true) or '?'
        local relation=read(U.field(snapshot.player,'Faction Component'),'GetFactionRelation',rider)
        local blocked=read(U.field(rider,'AbilitySystemComponent'),'GetGameplayTagCount',{TagName=FName('CharacterState.Unselectable')})
        local socket=read(U.field(rider,'Mesh'),'DoesSocketExist',FName('spine_04'))
        local distance=metres(where(snapshot.player),where(rider))
        say(string.format('荆野锁定读回 实例=%s 骑乘=%s 玩家对骑手关系=%s 骑手在战斗目标列表=%s spine_04=%s 不可选标签数=%s 玩家当前锁住骑手=%s 距离=%s米',
            record.key,tostring(seat),tostring(relation or '?'),registered,socket==nil and '?' or tostring(socket),
            tostring(blocked or '?'),snapshot.lockKnown and tostring(snapshot.locked==record.key) or '?',distance and string.format('%.1f',distance) or '?'))
    end
    function self:tick(members)
        if not next(self.records) then return end
        local t=now()
        local snapshot
        local companions={}
        if options.companionOpponent and options.syncCompanionMount then
            for _,member in ipairs(members or {})do
                if member.team=='companion' and not member.stand and not member.reserve and not member.aid then
                    local key=U.key(member.actor)
                    if key and self.records[key] then companions[key]=true end
                end
            end
        end
        for key,record in pairs(self.records)do
            if gone(record.rider) then self:release(record,'已不在场上')
            elseif not record.anchorOnly and not record.mount then
                local mount=U.field(U.field(record.rider,'BP_SGameDriverComponent'),'DrivingVehicle')
                local late=t-record.at>WAIT
                local seated=U.valid(mount)
                local vehicleSpawner
                if companions[key] then
                    if (seated or late) and t>=(record.nextScriptRead or 0) then
                        record.nextScriptRead=t+2
                        local native,spawner=scriptMount(record)
                        if U.valid(native) and (not seated or U.key(native)==U.key(mount)) then
                            mount,vehicleSpawner=native,spawner
                        else mount=nil end
                    end
                elseif not seated and late and t>=(record.nextScriptRead or 0) then
                    record.nextScriptRead=t+2
                    mount,vehicleSpawner=scriptMount(record)
                end
                if U.valid(mount) and U.key(mount)~=key then
                    record.mount=mount
                    record.vehicleSpawner=vehicleSpawner or mountSpawner(record,mount)
                    self.mounted=self.mounted+1
                    local at,origin=where(mount),record.origin
                    say(string.format('骑兵 %s：坐骑 %s %s，%.1f 秒，位置=%s 离召唤点=%s 米；坐骑的刷怪点=%s',record.name,className(mount),
                        seated and '已骑上' or '尚未骑上（原生骑兵脚本确认）',t-record.at,
                        at and string.format('%.0f,%.0f,%.0f',at.X,at.Y,at.Z) or '?',
                        metres(at,origin) and string.format('%.1f',metres(at,origin)) or '?',
                        record.vehicleSpawner and className(record.vehicleSpawner) or '没找到'))
                elseif late and not record.warned then
                    record.warned=true;self.failures=self.failures+1
                    say(string.format('骑兵 %s：%d 秒内没骑上坐骑，继续等本体的坐骑记录',record.name,WAIT))
                end
            end
            if companions[key] and self.records[key]==record and U.valid(record.mount) and t>=(record.nextCompanionAim or 0) then
                record.nextCompanionAim=t+1
                local rider=record.rider
                local seat=U.field(U.field(rider,'BP_SGameDriverComponent'),'DrivingVehicle')
                if U.key(seat)==U.key(record.mount) and Mounts.isOurs(record.spawner)
                    and U.key(U.field(rider,'Spawner'))==U.key(record.spawner) and (options.hp(rider) or 0)>0 then
                    local world=options.world()
                    local target=options.companionOpponent(rider)
                    if U.inWorld(rider,world) and U.inWorld(seat,world) and U.inWorld(target,world) then
                        local native,spawner=scriptMount(record)
                        if U.key(native)==U.key(seat) and U.key(spawner)==U.key(record.vehicleSpawner) then
                            local aligned=options.syncCompanionMount(seat,rider,target)==true
                            if record.companionAim~=U.key(target) or record.companionAimOk~=aligned then
                                record.companionAim,record.companionAimOk=U.key(target),aligned
                                say(string.format('随从骑兵 %s 坐骑目标 %s 读回=%s',record.name,className(target),tostring(aligned)))
                            end
                        end
                    end
                end
            end
            if self.records[key]==record and record.name=='BP_Monster_JingYe_C' and options.player and t-record.at>=2
                and (record.lockSamples or 0)<4 and t>=(record.nextLockCheck or 0) then
                record.nextLockCheck=t+1
                local seat=U.key(U.field(U.field(record.rider,'BP_SGameDriverComponent'),'DrivingVehicle')) or false
                if record.lastSeat~=seat or record.lockSamples==1 and t-record.at>=8 then
                    if snapshot==nil then snapshot=lockSnapshot() or false end
                    if snapshot then
                        sampleLock(record,seat,snapshot)
                        record.lastSeat=seat;record.lockSamples=(record.lockSamples or 0)+1
                    end
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
        if not record.mount and not record.warned then return nil end
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
        record.target=target;record.targetKey=ok and sent==true and U.key(target) or nil
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
        if not okState then return false end
        if combat~=false then
            if combat==true and options.nativeTarget then
                local current=options.nativeTarget(mount)
                if aimLines<36 and (record.aimSamples or 0)<6 and now()>=(record.aimSampleAt or 0) then
                    local from,to=where(rider),where(target)
                    local ok,forward=pcall(function()return rider:GetActorForwardVector()end)
                    if from and to and ok and forward then
                        local dx,dy=to.X-from.X,to.Y-from.Y
                        local length=math.sqrt(dx*dx+dy*dy)
                        local facing=length>0 and (dx*forward.X+dy*forward.Y)/length or 1
                        aimLines=aimLines+1
                        record.aimSampleAt=now()+3;record.aimSamples=(record.aimSamples or 0)+1
                        say(string.format('骑兵索敌采样 骑手=%s 分配=%s 马的目标=%s 水平距离=%.1fm 朝向差=%.0f度 高差=%.1fm',
                            record.name,U.key(target) or '?',U.key(current) or '?',length/100,
                            math.deg(math.acos(math.max(-1,math.min(1,facing)))),(to.Z-from.Z)/100))
                    end
                end
                if U.valid(current) and U.key(current)~=record.targetKey then return self:fight(rider,target) end
            end
            return false
        end
        local ok,engaged,after=pcall(options.engage,mount,target)
        sayFight(string.format('骑兵 %s：坐骑不在战斗状态，重新迎敌 调用=%s 状态读回=%s',record.name,tostring(ok and engaged),tostring(after)))
        return ok and engaged==true
    end
    -- A mount's AI dropped out of combat (combat_lock.lua). True when the address was a mount's.
    function self:dropped(key)
        for _,record in pairs(self.records)do
            if U.key(record.mount)==key then
                local mount=riding(record)
                local target=record.target
                if options.assignedTarget then target=options.assignedTarget(record.rider) end
                if mount and U.valid(target) and options.engage then pcall(options.engage,mount,target) end
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
