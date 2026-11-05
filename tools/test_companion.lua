package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Companion=dofile('Mods/PhantomGladiator/Scripts/companion.lua')
local address=0
local function object(fields,name)
    address=address+1;local a=address
    fields.IsValid=function()return true end
    fields.GetAddress=function()return a end
    fields.GetFName=function()return {ToString=function()return name end}end
    return fields
end
local function tag(name)return {TagName=name}end
local function factionComponent(start)
    local fc={faction=tag(start),relations={}}
    fc.GetCurrnetFaction=function(self)return self.faction end
    fc.SetFaction=function(self,t)self.faction=t end
    fc.GetFactionRelation=function(self,other)return self.relations[other] or 2 end
    return object(fc,'Faction Component')
end
local followCalls,followWrites={},{}
local followCDO=object({FollowDistance=400,BehaviorTreeAsset=object({},'BT_SGameAI_Idle_NpcHelper_FollowPlayer'),Bindings={}},'Default__IdleStateData_Follow_C')
local followClass=object({GetCDO=function()return followCDO end,
    ForEachProperty=function(_,fn)fn(object({},'FollowDistance'))end,
    ForEachFunction=function(_,fn)fn(object({ForEachProperty=function(_,f)f(object({},'Blackboard'))end},'AssignParameters'))end},'IdleStateData_Follow_C')
local loaded=false
StaticFindObject=function(path)
    if path=='/SGameAI/Data/IdleStateData_Follow.IdleStateData_Follow_C' then return loaded and followClass or nil end
end
LoadAsset=function(path)followCalls[#followCalls+1]=path;loaded=true end
FName=function(s)return s end
StaticConstructObject=function(cls,outer,name)
    assert(cls==followClass and name:find('PG_CompanionFollow_',1,true))
    -- The follow state refuses writes: setting its ActorToFollow soft pointer from Lua crashed the game (v0.35.1).
    return setmetatable(object({outer=outer},name),{__newindex=function(_,k)followWrites[#followWrites+1]=k end})
end

local player=object({['Faction Component']=factionComponent('Faction.Player'),BP_PBZHatredManagerComponent=object({HatredList={}},'Hatred')},'Hun')
local function unit(started)
    local ai=object({SpawnInfo={IdleStateData=nil},bAIStarted=started,CurrentStateTag=tag('AI.State.Idle'),stops=0,starts=0},'SGameAIComponent')
    ai.StopAI=function(self)self.stops=self.stops+1 end
    ai.StartAI=function(self)self.starts=self.starts+1 end
    local actor=object({Controller=object({SGameAIComponent=ai},'Controller'),['Faction Component']=factionComponent('Faction.Monster'),
        BP_PBZHatredManagerComponent=object({HatredList={}},'Hatred')},'BP_Monster_MoTian_C')
    local class=object({},'BP_Monster_MoTian_C')
    actor.GetClass=function()return class end
    -- SetFactionRelationOverride(Both) writes both directions, as the game's does.
    actor['Faction Component'].SetFactionRelationOverride=function(self,other,rel,both)
        self.relations[other]=rel
        if both then other['Faction Component'].relations[actor]=rel end
    end
    return actor,ai
end
player['Faction Component'].SetFactionRelationOverride=function()end
local synced=0
local lib=object({SyncHatredList=function(_,from,to,world)
    synced=synced+1
    to.BP_PBZHatredManagerComponent.HatredList={table.unpack(from.BP_PBZHatredManagerComponent.HatredList)}
end},'BP_SGameAIFunctionLibrary')
local world=object({},'World')
local lines,members,now={}, {}, 0
local locations={}
local c=Companion.new({log=function(s)lines[#lines+1]=s end,getPlayer=function()return player end,getWorld=function()return world end,
    aiLib=function()return lib end,members=function()return members end,clock=function()return now end,
    getLocation=function(a)return locations[a] or {X=0,Y=0,Z=0} end})
local function all()return table.concat(lines,'\n')end
local function test(name,fn)fn();print('ok - '..name)end

local a,aiA=unit(true)
test('a companion gets the official follow state, the player faction and a friendly relation',function()
    local r=c:prepare(a,'/Mobs/MoTian.BP_Monster_MoTian_C')
    assert(r.ok,r.message)
    assert(followCalls[1]=='/SGameAI/Data/IdleStateData_Follow.IdleStateData_Follow_C','the follow class is loaded on demand')
    assert(aiA.SpawnInfo.IdleStateData and aiA.SpawnInfo.IdleStateData.outer==aiA,'the follow state is owned by the unit\'s AI')
    assert(a['Faction Component'].faction.TagName=='Faction.Player')
    assert(a['Faction Component'].relations[player]==0 and player['Faction Component'].relations[a]==0)
    assert(all():find('官方跟随状态类 IdleStateData_Follow_C 自身字段=FollowDistance=400',1,true),'the follow class is described once')
    assert(all():find('BehaviorTreeAsset=BT_SGameAI_Idle_NpcHelper_FollowPlayer',1,true))
    assert(all():find('跟随写入=true 读回=true',1,true) and all():find('阵营 Faction.Monster -> Faction.Player 写入=true 读回=true',1,true))
    assert(#followWrites==0,'nothing is written into the follow state object (its ActorToFollow soft pointer crashed the game)')
end)
test('an AI that had already started is restarted once so its idle state uses the follow data',function()
    c:afterActivate(a,'/Mobs/MoTian.BP_Monster_MoTian_C')
    assert(aiA.stops==1 and aiA.starts==1 and all():find('跟随数据保留=true 重启AI stop=true start=true',1,true))
    local b,aiB=unit(false);c:prepare(b,'/Mobs/B.B_C');c:afterActivate(b,'/Mobs/B.B_C')
    assert(aiB.stops==0 and aiB.starts==0)
    members={{actor=a,team='companion'},{actor=b,team='companion'}}
end)
test('assist shares the player\'s enemies only while the player has some',function()
    c:tick();assert(synced==0,'no enemies, nothing synced')
    local enemy=object({},'Enemy')
    player.BP_PBZHatredManagerComponent.HatredList={enemy}
    now=1;c:tick();assert(synced==0,'assist waits two seconds between syncs')
    now=2;c:tick();assert(synced==2 and a.BP_PBZHatredManagerComponent.HatredList[1]==enemy)
    assert(all():find('协助 同步玩家仇恨到随从 调用=true 玩家仇恨=1 随从仇恨 0 -> 1',1,true))
    assert(c:status().count==2 and c:status().follow==2 and c:status().friendly==2)
end)
test('follow is watched for ninety seconds, then companions that left are forgotten',function()
    locations[a]={X=500,Y=0,Z=0}
    now=5;c:tick();assert(all():find('跟随观察 BP_Monster_MoTian_C 距玩家=5.0m 状态=AI.State.Idle 闲置数据=PG_CompanionFollow_1',1,true))
    local watched=select(2,all():gsub('跟随观察',''))
    now=200;c:tick();assert(select(2,all():gsub('跟随观察',''))==watched,'no watch lines after ninety seconds')
    members={{actor=a,team='companion'},{actor=object({},'Arena'),team='blue'}}
    c:tick();assert(c:status().count==1)
    members={};c:tick();assert(c:status().count==0 and c:status().message=='随从已全部离场')
end)
test('an adopted companion (its summoner\'s summon) joins the player\'s side and stops hating the player',function()
    local child=unit(false)
    local hm=child.BP_PBZHatredManagerComponent
    hm.HatredList={player}
    hm.RemoveActorFromHatredList=function(self,target)
        local kept={};for _,entry in ipairs(self.HatredList)do if entry~=target then kept[#kept+1]=entry end end
        self.HatredList=kept
    end
    members={{actor=child,team='companion',class_path='/Mobs/Child.Child_C'}};c:tick()
    assert(all():find('登记随从（未经召唤准备',1,true))
    assert(child['Faction Component'].faction.TagName=='Faction.Player')
    assert(child['Faction Component'].relations[player]==0 and player['Faction Component'].relations[child]==0)
    for _,entry in ipairs(hm.HatredList)do assert(entry~=player,'the player is off its hatred list (the assist may add the player\'s enemies)')end
    assert(all():find('召唤物加入玩家一方 unit=/Mobs/Child.Child_C 第1次 阵营 Faction.Monster -> Faction.Player 写入=true 读回=true',1,true))
    assert(all():find('原本在仇恨玩家=true 移出玩家仇恨 调用=true 读回仍在=false',1,true))
    local tries=select(2,all():gsub('召唤物加入玩家一方',''))
    now=now+1;c:tick();assert(select(2,all():gsub('召唤物加入玩家一方',''))==tries,'done once it reads back')
    -- A summon that will not change sides is tried three times, then counted as a failure.
    local stubborn=unit(false)
    stubborn['Faction Component'].SetFaction=function()error('refused')end
    local failures=c:status().failures
    members={{actor=stubborn,team='companion',class_path='/Mobs/Stubborn.Stubborn_C'}}
    for _=1,5 do now=now+1;c:tick() end
    assert(select(2,all():gsub('召唤物加入玩家一方 unit=/Mobs/Stubborn',''))==3 and c:status().failures==failures+1)
end)
test('a missing follow class is reported without blocking',function()
    local d=unit(false);loaded=false;LoadAsset=function()end
    local fresh=Companion.new({log=function(s)lines[#lines+1]=s end,getPlayer=function()return player end})
    local r=fresh:prepare(d,'/Mobs/D.D_C')
    assert(not r.ok and fresh:status().failures==1 and d['Faction Component'].relations[player]==0,'friendly even without follow')
    assert(all():find('跟随=官方跟随状态类加载失败',1,true))
end)

test('follow keys point at the player; walk near, run far, MoveToActor when stuck, teleport from 100 m but not in a boss fight',function()
    local helper
    local mechanic=object({['Walking Tag']=tag('Movement.Walk'),['Jogging Tag']=tag('Movement.Jog'),['Sprinting Tag']=tag('Movement.Sprint')},'GlobalConfig_Mechanic')
    local find=StaticFindObject
    StaticFindObject=function(path)
        if path=='/PBZCombatAsset/Config/GlobalConfig_Mechanic.GlobalConfig_Mechanic' then return mechanic end
        if path=='/Script/AIModule.Default__AIBlueprintHelperLibrary' then return helper end
        return find(path)
    end
    loaded=true
    local values={}
    local keyType=object({},'BlackboardKeyType_Object');local objectClass=object({},'BlackboardKeyType_Object')
    keyType.GetClass=function()return objectClass end
    local data=object({Keys={{EntryName='FollowTarget',KeyType=keyType},{EntryName='TargetActor',KeyType=keyType}}},'BB_SGameAI')
    local bb=object({BlackboardAsset=data,GetValueAsObject=function(_,k)return values[k]end,SetValueAsObject=function(_,k,v)values[k]=v end},'Blackboard')
    local e,aiE=unit(false);aiE.BlackboardComponent=bb
    e.CharacterMovement=object({MaxWalkSpeed=80},'CharacterMovement')
    -- The driver owns the speed: a custom max speed holds until stopped, a plain write would not.
    local custom
    e['Locomotion Driver']=object({UseCustomMaxSpeed=function(_,speed,blend)custom=speed;e.CharacterMovement.MaxWalkSpeed=speed end,
        StopUseCustomMovementParameters=function()custom=nil;e.CharacterMovement.MaxWalkSpeed=80 end},'LocomotionDriver')
    player.CharacterMovement=object({MaxWalkSpeed=600},'PlayerMovement')
    local moves=0
    local moveStatus=0
    rawset(e.Controller,'GetMoveStatus',function()return moveStatus end)
    helper=object({SimpleMoveToActor=function(_,controller,goal)assert(controller==e.Controller and goal==player);moves=moves+1 end},'AIBlueprintHelperLibrary')
    e.SetMovementMode=function(self,t)self.AIMovementMode=t end
    e.K2_GetActorRotation=function()return {Pitch=0,Yaw=90,Roll=0}end
    e.K2_TeleportTo=function(_,dest)locations[e]=dest;return true end
    local here=Companion.new({log=function(s)lines[#lines+1]=s end,getPlayer=function()return player end,getWorld=function()return world end,
        aiLib=function()return lib end,members=function()return {{actor=e,team='companion'}} end,clock=function()return now end,
        getLocation=function(a)return locations[a] or {X=0,Y=0,Z=0} end})
    now=1000;here:prepare(e,'/Mobs/E.E_C');here:afterActivate(e,'/Mobs/E.E_C')
    player.BP_PBZHatredManagerComponent.HatredList={}
    locations[e]={X=800,Y=0,Z=0};here:tick()
    assert(values.FollowTarget==player and values.TargetActor==nil,'only the follow key is pointed at the player')
    assert(all():find('跟随对象键=FollowTarget',1,true) and all():find('跟随对象键指向玩家 读回=1/1',1,true))
    assert(e.AIMovementMode.TagName=='Movement.Walk','8 m: walk')
    assert(e.CharacterMovement.MaxWalkSpeed==80,'walking speed is left to the AI')
    locations[e]={X=1500,Y=0,Z=0};now=1001;here:tick()
    assert(e.AIMovementMode.TagName=='Movement.Jog','15 m: run, using the jog state NPCs chase in')
    assert(custom and math.abs(custom-660)<0.01,'running asks the driver for 1.1x the player when no sprint speed is configured')
    now=1002;here:tick();assert(all():find('跑步1秒后读回 BP_Monster_MoTian_C 最大速度=660',1,true) and all():find('跑步动画只读 BP_Monster_MoTian_C',1,true))
    locations[e]={X=800,Y=0,Z=0};now=1003;here:tick()
    assert(custom==nil and e.CharacterMovement.MaxWalkSpeed==80,'back within 10 m: the driver takes its own speed back')
    locations[e]={X=1500,Y=0,Z=0};now=1004;here:tick()
    now=1005;here:tick();assert(moves==1,'no progress for three seconds: SimpleMoveToActor takes over')
    assert(all():find('备用跟随 SimpleMoveToActor',1,true))
    moveStatus=3;now=1009;here:tick();assert(moves==1,'a move still under way is left alone')
    moveStatus=0;now=1010;here:tick();assert(moves==2,'once it stops short of the player a new move starts')
    -- 120 m away in a boss fight: stays; once the boss is gone it teleports beside the player.
    local boss=object({['Actor Config']=object({['Difficulty Tag']=tag('CharacterType.Difficulty.UltimateBoss')},'PDA_ActorConfig')},'Boss')
    e.BP_PBZHatredManagerComponent.HatredList={boss}
    locations[e]={X=12000,Y=0,Z=0};now=1010;here:tick()
    assert(locations[e].X==12000 and all():find('正在和BOSS打斗',1,true))
    e.BP_PBZHatredManagerComponent.HatredList={};now=1011;here:tick()
    assert(math.abs(locations[e].X-250)<1 and here:status().teleports==1 and all():find('传送到玩家身边',1,true))
    StaticFindObject=find
end)
test('out of combat it engages the nearest live hostile it perceives near the player, never the mod\'s own units',function()
    local f,aiF=unit(false)
    local near=object({},'Near');local nearer=object({},'Nearer');local far=object({},'Far');local dead=object({},'Dead');local arena=object({},'Arena')
    local hps={[near]=100,[nearer]=100,[far]=100,[dead]=0,[arena]=100}
    for actor,_ in pairs(hps)do actor.GetClass=function()return object({},actor.GetFName().ToString())end end
    locations[f]={X=0,Y=0,Z=0}
    locations[near]={X=600,Y=0,Z=0};locations[nearer]={X=300,Y=0,Z=0};locations[far]={X=5000,Y=0,Z=0}
    locations[dead]={X=100,Y=0,Z=0};locations[arena]={X=50,Y=0,Z=0}
    aiF.AIPerception=object({GetPerceivedHostileActors=function(_,out)out.OutActors={near,far,dead,arena,nearer}end},'AIPerception')
    local fought={}
    aiF.ForceIntoCombat=function(_,target)fought[#fought+1]=target end
    local list={{actor=f,team='companion'},{actor=arena,team='blue'}}
    local here=Companion.new({log=function(s)lines[#lines+1]=s end,getPlayer=function()return player end,members=function()return list end,
        clock=function()return now end,getLocation=function(a)return locations[a] or {X=0,Y=0,Z=0} end,
        hp=function(a)return hps[a] or 100 end})
    now=2000;here:tick()
    assert(fought[1]==nearer and #fought==1,'nearest live hostile within 20 m of the player, not the arena unit, the dead or the far one')
    assert(all():find('主动迎敌 BP_Monster_MoTian_C -> Nearer',1,true))
    here:tick();assert(#fought==1,'at most once a second')
    aiF.CurrentStateTag=tag('AI.State.Combat');now=2002;here:tick();assert(#fought==1,'not while already fighting')
end)
test('a companion is always friendly: a relation, faction or hatred that drifts is put back and logged',function()
    local g=unit(false)
    local hm=g.BP_PBZHatredManagerComponent
    hm.RemoveActorFromHatredList=function(self,target)
        local kept={};for _,entry in ipairs(self.HatredList)do if entry~=target then kept[#kept+1]=entry end end
        self.HatredList=kept
    end
    local list={{actor=g,team='companion'}}
    local here=Companion.new({log=function(s)lines[#lines+1]=s end,getPlayer=function()return player end,members=function()return list end,
        clock=function()return now end,getLocation=function(a)return locations[a] or {X=0,Y=0,Z=0} end})
    player.BP_PBZHatredManagerComponent.HatredList={}
    now=3000;here:prepare(g,'/Mobs/G.G_C');here:tick()
    assert(here:status().repairs==0,'nothing to put back right after it joined')
    -- What leaving the free camera did up to v0.37.3: hostile to the player, one way.
    g['Faction Component'].relations[player]=2
    now=3001;here:tick()
    assert(g['Faction Component'].relations[player]==0 and here:status().repairs==1)
    assert(all():find('随从对玩家不再是友好，改回 unit=/Mobs/G.G_C 改回前 随从→玩家=2 玩家→随从=0 阵营=Faction.Player 仇恨里有玩家=false',1,true))
    assert(all():find('结果=true',1,true))
    now=3002;here:tick();assert(here:status().repairs==1,'nothing more once it reads back friendly')
    -- The faction tag and the hatred list are kept too.
    g['Faction Component'].faction=tag('Faction.Monster');hm.HatredList={player}
    now=3003;here:tick()
    assert(g['Faction Component'].faction.TagName=='Faction.Player' and #hm.HatredList==0 and here:status().repairs==2)
    assert(all():find('阵营=Faction.Monster 仇恨里有玩家=true',1,true) and all():find('移出玩家仇恨 调用=true',1,true))
    -- A unit that refuses is counted as a failure and tried again every ten seconds, not every second.
    local failures=here:status().failures
    g['Faction Component'].SetFactionRelationOverride=function()end
    g['Faction Component'].relations[player]=2
    now=3004;here:tick();assert(here:status().repairs==3 and here:status().failures==failures+1)
    now=3005;here:tick();assert(here:status().repairs==3,'waits after a failed repair')
    now=3014;here:tick();assert(here:status().repairs==4)
end)
test("a rider companion's mount, a pawn of its own, is put on the player's side as well",function()
    local r=unit(false)
    local horse=unit(false)
    local horseClass=object({},'BP_Monster_Horse_C');horse.GetClass=function()return horseClass end
    r.BP_SGameDriverComponent=object({DrivingVehicle=horse},'BP_SGameDriverComponent')
    local list={{actor=r,team='companion'}}
    local here=Companion.new({log=function(s)lines[#lines+1]=s end,getPlayer=function()return player end,members=function()return list end,
        clock=function()return now end,getLocation=function(a)return locations[a] or {X=0,Y=0,Z=0} end})
    now=4000;here:prepare(r,'/Mobs/Rider.Rider_C');here:tick()
    assert(horse['Faction Component'].faction.TagName=='Faction.Player')
    assert(horse['Faction Component'].relations[player]==0 and player['Faction Component'].relations[horse]==0)
    assert(all():find('改回 unit=坐骑 BP_Monster_Horse_C（随从 /Mobs/Rider.Rider_C） 改回前 随从→玩家=2',1,true))
    local repairs=here:status().repairs
    now=4001;here:tick();assert(here:status().repairs==repairs,'once friendly, left alone')
    r.BP_SGameDriverComponent.DrivingVehicle=nil;now=4002;here:tick()
    assert(here:status().repairs==repairs,'no mount, nothing to do')
end)
test('stuck closer than 100 m (a ledge, steps) it is teleported beside the player; running along or coming closer it is not',function()
    -- One companion per case, so no case inherits another's progress.
    local function case()
        local s=unit(false)
        s.K2_GetActorRotation=function()return {Pitch=0,Yaw=0,Roll=0}end
        local count={n=0}
        s.K2_TeleportTo=function(_,dest)locations[s]=dest;count.n=count.n+1;return true end
        local here=Companion.new({log=function(l)lines[#lines+1]=l end,getPlayer=function()return player end,
            members=function()return {{actor=s,team='companion'}} end,
            clock=function()return now end,getLocation=function(a)return locations[a] or {X=0,Y=0,Z=0} end})
        return s,here,count
    end
    player.BP_PBZHatredManagerComponent.HatredList={}
    locations[player]={X=0,Y=0,Z=0}
    -- Left on a platform 25 m off and 4 m up, standing still (the fallback move finds no way down).
    local s,here,count=case()
    locations[s]={X=2500,Y=0,Z=400}
    now=5000;here:tick()
    now=5003;here:tick();assert(count.n==0,'not before six seconds')
    now=5006;here:tick()
    assert(count.n==1 and math.abs(locations[s].X-250)<1 and here:status().stuck==1,'six seconds no closer, not moving: beside the player')
    assert(all():find('卡住6秒跟不上（自己移动0.0m，高差4.0m），传送到玩家身边',1,true),all())
    -- Pacing at a ledge on the same floor, never closer: stuck as well.
    s,here,count=case()
    for i=0,7 do locations[s]={X=2000+(i%2)*150,Y=0,Z=0};now=5100+i;here:tick() end
    assert(count.n==1,'pacing without coming closer: stuck')
    -- Coming closer the long way round: left alone however long it takes.
    s,here,count=case()
    for i=0,12 do locations[s]={X=3000-i*120,Y=0,Z=0};now=5200+i;here:tick() end
    assert(count.n==0,'coming closer: left to walk')
    -- Running along behind a player who keeps going (no closer, but moving well): not stuck either.
    s,here,count=case()
    for i=0,10 do locations[player]={X=i*600,Y=0,Z=0};locations[s]={X=i*600+2000,Y=0,Z=0};now=5300+i;here:tick() end
    assert(count.n==0,'running along behind the player: not stuck')
    locations[player]={X=0,Y=0,Z=0}
    -- A floor apart in a boss fight: stays, as at 100 m.
    s,here,count=case()
    local boss=object({['Actor Config']=object({['Difficulty Tag']=tag('CharacterType.Difficulty.NormalBoss')},'PDA_ActorConfig')},'Boss')
    player.BP_PBZHatredManagerComponent.HatredList={boss}
    locations[s]={X=2500,Y=0,Z=400};now=5400;here:tick();now=5407;here:tick()
    assert(count.n==0 and all():find('卡住跟不上，但正在和BOSS打斗，不传送',1,true))
    player.BP_PBZHatredManagerComponent.HatredList={}
end)
test('recall brings every live companion beside the player at once, fanned out; the fallen and the arena stay',function()
    local list,hps={},{}
    local function companion(x)
        local c=unit(false)
        c.K2_GetActorRotation=function()return {Pitch=0,Yaw=0,Roll=0}end
        c.K2_TeleportTo=function(_,dest)locations[c]=dest;return true end
        locations[c]={X=x,Y=0,Z=0};hps[c]=100
        list[#list+1]={actor=c,team='companion'}
        return c
    end
    local a1,a2,fallen=companion(5000),companion(5000),companion(-3000)
    hps[fallen]=0
    local blue=unit(false);list[#list+1]={actor=blue,team='blue'};locations[blue]={X=9000,Y=0,Z=0}
    locations[player]={X=0,Y=0,Z=0}
    local here=Companion.new({log=function(l)lines[#lines+1]=l end,getPlayer=function()return player end,members=function()return list end,
        clock=function()return now end,getLocation=function(a)return locations[a] or {X=0,Y=0,Z=0} end,hp=function(a)return hps[a] end})
    local r=here:recall()
    assert(r.ok and r.message=='已召回 2/2 个随从到身边',r.message)
    local function off(c)local p=locations[c];return math.sqrt(p.X^2+p.Y^2)/100 end
    assert(off(a1)<=2.6 and off(a2)<=2.6,'both beside the player')
    assert(math.abs(locations[a1].Y-locations[a2].Y)>100,'fanned out, not on one spot')
    assert(locations[fallen].X==-3000 and locations[blue].X==9000,'the fallen one and the arena unit stay where they are')
    -- One that does not arrive (the ground in the way): the answer names it.
    a2.K2_TeleportTo=function()return false end;locations[a2]={X=5000,Y=0,Z=0}
    local partial=here:recall()
    assert(not partial.ok and partial.message:find('已召回 1/2 个随从到身边；没到位：BP_Monster_MoTian_C(50.0m)',1,true),partial.message)
    list={}
    local none=here:recall()
    assert(none.ok and none.message=='没有可召回的随从' and here:status().recalls==3)
end)
test('a stand keeps the player\'s side but takes no follow, teleport, target or recall orders and is not counted',function()
    local boss,stand,standAI=unit(false),unit(false)
    standAI=stand.Controller.SGameAIComponent
    local moved,orders,syncedTo=0,0,{}
    stand.K2_GetActorRotation=function()return {Pitch=0,Yaw=0,Roll=0}end
    stand.K2_TeleportTo=function()moved=moved+1;return true end
    standAI.ForceIntoCombat=function()orders=orders+1 end
    standAI.AIPerception=object({GetPerceivedHostileActors=function(_,out)out.OutActors={object({},'Enemy')}end},'Perception')
    stand.SetMovementMode=function()orders=orders+1 end
    boss.K2_GetActorRotation=function()return {Pitch=0,Yaw=0,Roll=0}end
    boss.K2_TeleportTo=function(_,dest)locations[boss]=dest;return true end
    local list={{actor=boss,team='companion',class_path='/Mobs/Boss.Boss_C'},
        {actor=stand,team='companion',stand=true,summoner=boss,class_path='/Mobs/Stand.Stand_C'}}
    local aiLib=object({SyncHatredList=function(_,_,to)syncedTo[to]=true end},'Lib')
    player.BP_PBZHatredManagerComponent.HatredList={object({},'Enemy')}
    locations[player]={X=0,Y=0,Z=0};locations[boss]={X=100,Y=0,Z=0};locations[stand]={X=50000,Y=0,Z=0}
    local clockNow,logs=1000,{}
    local here=Companion.new({log=function(s)logs[#logs+1]=s end,getPlayer=function()return player end,getWorld=function()return world end,
        aiLib=function()return aiLib end,members=function()return list end,clock=function()return clockNow end,
        getLocation=function(a)return locations[a] or {X=0,Y=0,Z=0} end,hp=function()return 100 end})
    for _=1,12 do clockNow=clockNow+1;here:tick() end
    assert(stand['Faction Component'].faction.TagName=='Faction.Player','it fights for the player')
    assert(stand['Faction Component'].relations[player]==0 and player['Faction Component'].relations[stand]==0)
    assert(moved==0,'500 m from the player and it stays where it is')
    assert(orders==0,'no movement mode or combat order')
    assert(syncedTo[boss] and not syncedTo[stand],'the assist goes to the companion, not its stand')
    assert(here:status().count==1,'one companion')
    locations[boss]={X=5000,Y=0,Z=0}
    local r=here:recall()
    assert(r.ok and r.message=='已召回 1/1 个随从到身边' and moved==0,r.message)
    player.BP_PBZHatredManagerComponent.HatredList={}
end)
test('a companion executing a boss takes no follow, teleport or recall orders meanwhile, and goes back to them after',function()
    local one=unit(false)
    local moved=0
    one.K2_GetActorRotation=function()return {Pitch=0,Yaw=0,Roll=0}end
    one.K2_TeleportTo=function()moved=moved+1;return true end
    local list={{actor=one,team='companion',class_path='/Mobs/One.One_C'}}
    locations[player]={X=0,Y=0,Z=0};locations[one]={X=50000,Y=0,Z=0}
    local executing,clockNow=true,5000
    local here=Companion.new({log=function()end,getPlayer=function()return player end,getWorld=function()return world end,
        members=function()return list end,clock=function()return clockNow end,busy=function(a)return executing and a==one end,
        getLocation=function(a)return locations[a] or {X=0,Y=0,Z=0} end,hp=function()return 100 end})
    for _=1,8 do clockNow=clockNow+1;here:tick() end
    assert(moved==0,'it stays through the clip')
    assert(one['Faction Component'].faction.TagName=='Faction.Player','it keeps its side')
    assert(here:status().count==1,'it still counts')
    assert(here:recall().message=='没有可召回的随从' and moved==0)
    executing=false
    clockNow=clockNow+1;here:tick()
    assert(moved==1,'500 m away with the clip over: teleported as usual')
end)
print('companion: PASS (official follow state, player faction, friendly relation, AI restart, gated assist, follow watch, roster, missing class, follow keys, walk/run, stuck fallback, teleport and boss fights, always friendly, mounts, stuck teleport, recall)')
