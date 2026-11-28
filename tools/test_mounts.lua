package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Mounts=dofile('Mods/PhantomGladiator/Scripts/mounts.lua')
local address=0
local function object(fields,name)
    address=address+1;local a=address
    fields.alive=true
    fields.IsValid=function(self)return self.alive end
    fields.GetAddress=function()return a end
    local class={IsValid=function()return true end,GetFName=function()return {ToString=function()return name end}end}
    fields.GetClass=function()return class end
    return fields
end
FName=function(s)return {ToString=function()return s end}end
local lines,now,spawned,finished,destroyed={},0,{},{},{}
local locations={}
local spawnerClass=object({},'BP_AISpawner_C')
local findable=true
local world=object({},'World')
local statics=object({
    BeginDeferredActorSpawnFromClass=function(_,w,cls,t,collision,owner,scale)
        assert(w==world and cls==spawnerClass and collision==1 and owner==nil and scale==1)
        local spawner=object({InitialSpawn=true,SpawnerID=FName('None'),SpawnedAI=nil},'BP_AISpawner_C')
        locations[spawner]=t.Translation
        spawned[#spawned+1]=spawner
        return spawner
    end,
    FinishSpawningActor=function(_,actor,t,scale)
        -- The spawner begins play here: InitialSpawn and the tag must already be set.
        finished[#finished+1]={actor=actor,initial=actor.InitialSpawn,tag=actor.SpawnerID:ToString()}
    end},'Default__GameplayStatics')
local mapSpawners={}
local m=Mounts.new({log=function(s)lines[#lines+1]=s end,now=function()return now end,
    scripts=function(a)return a.scripts end,
    location=function(a)return locations[a] end,
    isDestroying=function(a)return a.destroying==true end,
    findClass=function(path)assert(path=='/SGameAI/Tools/Spawner/BP_AISpawner.BP_AISpawner_C');return findable and spawnerClass or nil end,
    statics=function()return statics end,
    findAll=function(name)
        assert(name=='BP_AISpawner_C')
        local list={}
        for _,s in ipairs(mapSpawners)do list[#list+1]=s end
        for _,s in ipairs(spawned)do list[#list+1]=s end
        return list
    end,
    destroy=function(a)a.destroying=true;destroyed[#destroyed+1]=a end})
local function all()return table.concat(lines,'\n')end
local function test(name,fn)fn();print('ok - '..name)end
local transform={Translation={X=100,Y=200,Z=300},Rotation={},Scale3D={X=1,Y=1,Z=1}}
local function rider(name)
    return object({Spawner=nil,BP_SGameDriverComponent=object({DrivingVehicle=nil},'BP_SGameDriverComponent_C')},name)
end

test('only the nine rider classes are riders',function()
    assert(Mounts.isRider('BP_Monster_JingYe_C') and Mounts.isRider('BP_Monster_Bandit_Sword_Rider'))
    assert(Mounts.isRider('BP_Monster_GuiChai_Black_TwinBlade_Rider_HorseCartCombat_L_C'))
    assert(not Mounts.isRider('BP_Monster_Horse_JingYe_C') and not Mounts.isRider('BP_Monster_MoTian_C') and not Mounts.isRider(nil))
end)

test('a unit that is not a rider is left alone',function()
    local unit=rider('BP_Monster_MoTian_C')
    assert(m:prepare(unit,transform,world)==nil)
    assert(#spawned==0 and unit.Spawner==nil and #lines==0 and m:placeholderOf(unit)==nil)
end)

local jingye=rider('BP_Monster_JingYe_C')
test('a rider gets a quiet spawner of the mod at its summon transform before it starts',function()
    local r=m:prepare(jingye,transform,world)
    assert(r and r.ok,'readback')
    assert(#spawned==1 and jingye.Spawner==spawned[1] and m:placeholderOf(jingye)==spawned[1])
    assert(#finished==1 and finished[1].actor==spawned[1] and finished[1].initial==false and finished[1].tag==Mounts.TAG,
        'InitialSpawn off and the tag set before it begins play')
    assert(Mounts.isOurs(spawned[1]) and not Mounts.isOurs(object({SpawnerID=FName('Horse')},'BP_AISpawner_C')))
    assert(all():find('骑兵 BP_Monster_JingYe_C：在召唤点放刷怪点',1,true) and all():find('写进 Spawner 调用=true 读回=true',1,true))
    assert(m:status().mount_prepared==1 and m:count()==1)
end)

local horse,horseSpawner
test('the mount it gets on is found with the spawner its script made for it',function()
    now=1;m:tick()
    assert(not all():find('坐骑',1,true),'not on a mount yet: nothing to say')
    horse=object({},'BP_Monster_Horse_JingYe_C');locations[horse]={X=100,Y=200,Z=250}
    horseSpawner=object({SpawnedAI=horse,SpawnerID=FName('None')},'BP_AISpawner_C');locations[horseSpawner]=transform.Translation
    local other=object({SpawnedAI=object({},'BP_Monster_MoTian_C'),SpawnerID=FName('None')},'BP_AISpawner_C')
    mapSpawners={other,horseSpawner}
    jingye.BP_SGameDriverComponent.DrivingVehicle=horse
    now=2;m:tick()
    assert(all():find('坐骑 BP_Monster_Horse_JingYe_C 已骑上，2.0 秒，位置=100,200,250 离召唤点=0.5 米；坐骑的刷怪点=BP_AISpawner_C',1,true),all())
    local keys=m:keys()
    local k=function(a)return keys[tostring(a.GetAddress())]end
    assert(k(horse) and k(horseSpawner) and k(spawned[1]) and not k(other))
    local before=#lines;now=3;m:tick()
    assert(#lines==before,'found once')
end)

test('clearing the rider takes its mount and both spawners with it',function()
    m:releaseActor(jingye,'随骑兵清理')
    assert(#destroyed==3 and destroyed[1]==horse and destroyed[2]==horseSpawner and destroyed[3]==spawned[1])
    assert(all():find('骑兵 BP_Monster_JingYe_C 随骑兵清理，一并移除：坐骑=BP_Monster_Horse_JingYe_C 调用=true 读回=已移除；坐骑刷怪点=BP_AISpawner_C 调用=true 读回=已移除；Mod刷怪点=BP_AISpawner_C 调用=true 读回=已移除',1,true),all())
    assert(m:count()==0 and m:status().mount_released==1 and next(m:keys())==nil)
    local before=#destroyed;m:releaseActor(jingye);assert(#destroyed==before,'nothing twice')
end)

test('an unseated rider uses its own script even when two mounts spawn at the same spot',function()
    local bandit=rider('BP_Monster_Bandit_Sword_Rider_C')
    now=10;assert(m:prepare(bandit,{Translation={X=0,Y=0,Z=0}},world).ok)
    local ours=spawned[#spawned]
    local mount=object({},'BP_Monster_Horse_MonsterHorse_C')
    local standing=object({SpawnedAI=mount,SpawnerID=FName('None')},'BP_AISpawner_C');locations[standing]={X=10,Y=0,Z=0}
    local foreignMount=object({},'BP_Monster_Horse_MonsterHorse_C')
    local foreign=object({SpawnedAI=foreignMount},'BP_AISpawner_C');locations[foreign]=locations[standing]
    local other=rider('BP_Monster_Bandit_Sword_Rider_C')
    bandit.scripts={object({Pawn=other,VehiclePawn=foreignMount,VehicleSpawner=foreign},'AIScript_Rider_C'),
        object({Pawn=bandit,VehiclePawn=mount,VehicleSpawner=standing},'AIScript_Rider_C')}
    mapSpawners={foreign,standing}
    now=20;m:tick()
    assert(not all():find('BP_Monster_Bandit_Sword_Rider_C：坐骑',1,true),'waits before looking around')
    now=26;m:tick()
    assert(m.records[tostring(bandit:GetAddress())].mount==mount,'a nearby map or other rider mount is not ours')
    -- Gone by itself (fell out of the world, killed by the game): the next tick clears the rest.
    bandit.alive=false;m:tick()
    assert(destroyed[#destroyed]==ours and destroyed[#destroyed-1]==standing and destroyed[#destroyed-2]==mount)
    assert(not foreign.destroying and not foreignMount.destroying)
    assert(all():find('骑兵 BP_Monster_Bandit_Sword_Rider_C 已不在场上，一并移除',1,true))
end)

test('no mount at all is said once',function()
    local spear=rider('BP_Monster_SpearMan_Spear_Blue_Rider_C')
    mapSpawners={}
    now=30;m:prepare(spear,transform,world)
    now=46;m:tick();m:tick()
    local _,n=all():gsub('15 秒内没骑上坐骑',''); assert(n==1,all())
    local late=object({},'BP_Monster_Horse_MonsterHorse_C')
    spear.BP_SGameDriverComponent.DrivingVehicle=late
    now=50;m:tick();assert(m:carrierOf(spear)==late,'a native mount can arrive after the initial timeout')
    m:releaseActor(spear)
end)

test('a boss that aims a move at its spawner gets one too, and no mount is looked for',function()
    assert(Mounts.isAnchored('BP_Monster_LeiDang_P2_C') and Mounts.isAnchored('BP_Monster_LengTu'))
    assert(not Mounts.isAnchored('BP_Monster_LeiDang_C') and not Mounts.isRider('BP_Monster_LeiDang_P2_C'))
    local leidang=rider('BP_Monster_LeiDang_P2_C')
    local before=#spawned
    local r=m:prepare(leidang,transform,world)
    assert(r and r.ok and #spawned==before+1 and leidang.Spawner==spawned[#spawned])
    assert(m:placeholderOf(leidang)==leidang.Spawner)
    assert(all():find('BOSS BP_Monster_LeiDang_P2_C：在召唤点放刷怪点 BP_AISpawner_C',1,true),all())
    now=100;m:tick()
    assert(not all():find('BP_Monster_LeiDang_P2_C：坐骑',1,true) and not all():find('BP_Monster_LeiDang_P2_C：15 秒内没骑上',1,true))
    leidang.alive=false;m:tick()
    assert(destroyed[#destroyed]==spawned[before+1] and all():find('BOSS BP_Monster_LeiDang_P2_C 已不在场上，一并移除：坐骑=无；坐骑刷怪点=无；Mod刷怪点=BP_AISpawner_C 调用=true 读回=已移除',1,true),all())
end)

test('without the spawner class the rider is summoned as before',function()
    findable=false
    local before=#spawned
    local unit=rider('BP_Monster_JingYe_C')
    local r=m:prepare(unit,transform,world)
    assert(r and r.ok==false and #spawned==before and unit.Spawner==nil)
    assert(all():find('不能放刷怪点；照旧生成，坐骑会出在世界原点',1,true))
    findable=true
end)
-- In a fight: the mount goes where the rider is sent, is kept at it and sent back, and stops counting once the rider is off.
do
    local attacks,engages={},{}
    local attackOK,current,assigned=true,nil,nil
    local state='AI.State.Idle'
    local health={}
    local local_lines={}
    local observer=object({},'BP_RenewalPlayer_C')
    local fight=Mounts.new({log=function(s)local_lines[#local_lines+1]=s end,now=function()return now end,player=function()return observer end,
        location=function(a)return locations[a] end,isDestroying=function(a)return a.destroying==true end,
        findClass=function()return spawnerClass end,statics=function()return statics end,findAll=function()return {} end,
        destroy=function(a)a.destroying=true end,hp=function(a)return health[a] end,
        attack=function(mount,target)attacks[#attacks+1]={mount,target};return attackOK end,
        nativeTarget=function()return current end,assignedTarget=function()return assigned end,
        inCombat=function()return state:find('Combat',1,true)~=nil,state end,
        engage=function(mount,target)engages[#engages+1]={mount,target};return true,'AI.State.Combat' end})
    local function text()return table.concat(local_lines,'\n') end
    local jingye=rider('BP_Monster_JingYe_C')
    local lists=0
    local lock=object({},'TargetingComponent')
    local locked=object({GetOwner=function()return jingye end},'Mesh')
    lock.LockTarget={Component=locked}
    lock.TargetingSubsystem=object({GetTargetsByTag=function(_,tag,exact,out)
        assert(exact and tag.TagName:ToString()=='Targeting.Target.Combat');lists=lists+1;out.OutTargets={jingye}
    end},'TargetingWorldSubsystem')
    observer['Targeting Component']=lock
    observer['Faction Component']=object({GetFactionRelation=function(_,r)assert(r==jingye);return 2 end},'Faction')
    jingye.Mesh=object({DoesSocketExist=function(_,s)return s:ToString()=='spine_04' end},'Mesh')
    jingye.AbilitySystemComponent=object({GetGameplayTagCount=function()return 0 end},'ASC')
    local target=object({},'BP_Monster_MoTian_C')
    local second=object({},'BP_Monster_AHua_C')
    assert(fight:prepare(jingye,transform,world).ok)
    -- Not on its mount yet: nothing goes.
    assert(fight:fight(jingye,target)==false and #attacks==0)
    local horse=object({},'BP_Monster_Horse_JingYe_C')
    jingye.BP_SGameDriverComponent.DrivingVehicle=horse
    fight:tick()
    now=now+2;fight:tick();assert(lists==1 and text():find('骑手在战斗目标列表=true spine_04=true 不可选标签数=0 玩家当前锁住骑手=true',1,true))
    now=now+1;fight:tick();assert(lists==1,'steady riding does not rescan the target registry every tick')
    assert(fight:holds(horse) and not fight:holds(jingye))
    local members={{actor=jingye,team='blue'},{actor=target,team='red'}}
    local list=fight:vehicles(members)
    assert(#list==1 and list[1].actor==horse and list[1].team=='blue' and list[1].rider==jingye)
    assert(#fight:vehicles({{actor=jingye,team='companion'}})==0,'only blue and red')
    -- Mounted after the order: the regular check sends it.
    assert(fight:hold(jingye,target)==true and #attacks==1 and attacks[1][1]==horse and attacks[1][2]==target)
    assert(text():find('坐骑 BP_Monster_Horse_JingYe_C 跟着攻击 BP_Monster_MoTian_C 调用=true 读回=true',1,true),text())
    -- Same target: an idle mount is sent back, one in combat is left alone.
    assert(fight:hold(jingye,target)==true and #engages==1 and #attacks==1)
    state='AI.State.Combat'
    assert(fight:hold(jingye,target)==false and #engages==1,'never forces a mount already fighting')
    -- A new target goes straight through.
    assert(fight:fight(jingye,second)==true and attacks[2][2]==second)
    assert(fight:hold(jingye,second)==false and #attacks==2)
    -- Its AI drops: by the mount's address, at the current target.
    assigned=second
    assert(fight:dropped(tostring(horse:GetAddress()))==true and #engages==2 and engages[2][2]==second)
    assert(fight:dropped('nobody')==false)
    current=target;assert(fight:hold(jingye,second) and #attacks==3,'a mount in combat against the wrong actor needs the rider target')
    current=second;assert(not fight:hold(jingye,second) and #attacks==3)
    assigned=nil;assert(fight:dropped(tostring(horse:GetAddress())) and #engages==2,'expired assignments cannot restart a fight')
    attackOK=false;assert(not fight:fight(jingye,target))
    current=nil;attackOK=true;assert(fight:hold(jingye,target) and #attacks==5,'a rejected command must be retried even in combat')
    -- A dead rider's mount is out of the hatred hooks.
    health[jingye]=0
    assert(#fight:vehicles(members)==0)
    health[jingye]=100
    -- Off the mount: no longer sent, no longer counted, still cleared with the rider.
    jingye.BP_SGameDriverComponent.DrivingVehicle=nil
    now=now+1;fight:tick();assert(lists==2 and text():find('骑乘=false',1,true))
    assert(#fight:vehicles(members)==0 and fight:fight(jingye,target)==false and fight:hold(jingye,target)==false)
    assert(fight:holds(horse),'the mod still holds it for the clean-up')
    fight:releaseActor(jingye,'已清理')
    assert(not fight:holds(horse) and horse.destroying==true)
    print('ok - a mount follows its rider into a fight')
end
test('a companion sends only its native mount at its current map foe',function()
    local calls,target={},nil
    local valid={GetOuter=function()return world end}
    local companion=rider('BP_Monster_JingYe_C')
    companion.GetOuter=valid.GetOuter
    local original=object({GetOuter=valid.GetOuter},'BP_Monster_Horse_JingYe_C')
    local nearby=object({GetOuter=valid.GetOuter},'BP_Monster_Horse_JingYe_C')
    local foe=object({GetOuter=valid.GetOuter},'BP_Monster_MoYuan_C')
    local sp=object({GetOuter=valid.GetOuter,SpawnedAI=original},'BP_AISpawner_C')
    local mounted=Mounts.new({
        log=function()end,now=function()return now end,world=function()return world end,
        hp=function()return 100 end,statics=function()return statics end,
        scripts=function(a)return a.scripts end,
        findClass=function()return spawnerClass end,findAll=function()return {sp}end,
        isDestroying=function()return false end,destroy=function()end,
        companionOpponent=function(actor)assert(actor==companion);return target end,
        syncCompanionMount=function(mount,actor,enemy)
            assert(actor==companion and enemy==foe)
            calls[#calls+1]=mount;return true
        end})
    assert(mounted:prepare(companion,transform,world).ok)
    companion.scripts={object({Pawn=companion,VehiclePawn=original,VehicleSpawner=sp},'AIScript_Rider_C')}
    local roster={{actor=companion,team='companion'}}
    target=foe
    companion.BP_SGameDriverComponent.DrivingVehicle=nearby
    mounted:tick(roster);assert(#calls==0)
    companion.BP_SGameDriverComponent.DrivingVehicle=original
    now=now+2;mounted:tick(roster);mounted:tick(roster)
    assert(#calls==1 and calls[1]==original,'the owned native mount has one confirmed target')
    target=nil;now=now+2;mounted:tick(roster);assert(#calls==1)
    target=object({GetOuter=function()return object({},'OtherWorld') end},'BP_Monster_MoYuan_C')
    now=now+2;mounted:tick(roster);assert(#calls==1,'a foreign world enemy does not reach the mount')
    target=foe;now=now+2;mounted:tick({});assert(#calls==1,'removing the rider from the companion roster stops dispatch')
    roster[1].stand=true;now=now+2;mounted:tick(roster);assert(#calls==1)
    roster[1].stand=false
    companion.BP_SGameDriverComponent.DrivingVehicle=nil
    now=now+2;mounted:tick(roster);assert(#calls==1,'dismount stops dispatch')
end)
print('mounts: all tests passed')
