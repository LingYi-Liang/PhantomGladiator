package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Probe=require('companion_hit_probe')
local writes=0
-- A read-only fake UObject: any write through the proxy is counted.
local function object(id,full,fields)
    local inner=fields or {}
    inner.IsValid=function()return true end
    inner.GetAddress=function()return id end
    inner.GetFullName=function()return full end
    return setmetatable({},{__index=inner,__newindex=function()writes=writes+1 end})
end
local function class(full)return object('class:'..full,full) end
local function typed(id,classFull,full,fields)
    fields=fields or {}
    local cls=class(classFull)
    fields.GetClass=function()return cls end
    return object(id,full or (classFull..'#'..id),fields)
end
local function tag(name)return {TagName={ToString=function()return name end}} end
local function faction(name,relation)
    return object('fc:'..name,'FactionComponent',{GetCurrnetFaction=function()return tag(name)end,
        GetFactionRelation=function()return relation end})
end
local function harness()
    local h={logs={},now=0,hp=1000}
    h.player=typed(1,'BlueprintGeneratedClass /Game/Player/BP_Hun.BP_Hun_C',nil,{['Faction Component']=faction('Faction.Player',0)})
    h.enemy=typed(2,'BlueprintGeneratedClass /Game/Mobs/BP_Monster_Enemy.BP_Monster_Enemy_C')
    h.companion=typed(3,'BlueprintGeneratedClass /Game/Mobs/BP_Monster_MoTian.BP_Monster_MoTian_C',nil,{
        ['Faction Component']=faction('Faction.Player',0),
        BP_PBZHatredManagerComponent=object('hm',"HatredManager",{HatredList={h.enemy}})})
    local function data(id,target,self)
        return object(id,'PBZ_DamageBulletDataBase /PBZCombatAsset/Mobs/'..id..'.'..id,{FactionTarget=target,FactionCanTargetSelf=self})
    end
    local function module(id,hitsPlayer)
        return typed('m'..id,'Class /Script/PBZCombatAsset.PBZ_BulletAttackModule',nil,{
            TargetRequiredTags={GameplayTags={}},TargetIgnoredTags={GameplayTags={tag('State.Dead')}},
            FactionCalculator=object('calc','FactionRelationCalculator_Map /PBZCombatAsset/Config/FactionCalc.FactionCalc'),
            IsValidTarget=function(_,target)return target~=h.player or hitsPlayer end})
    end
    local function bullet(id,classFull,owner,status,d,m)
        return typed(id,classFull,nil,{BulletOwnerAvatar=owner,BulletStatus=status,Destroyed=false,BulletData=d,AttackModule=m,
            BulletSourceAbility=typed('ga'..id,'BlueprintGeneratedClass /Game/GA/GA_'..id..'.GA_'..id..'_C')})
    end
    h.objects={
        bullet(11,'Class /Script/PBZCombatAsset.PBZ_SweepTraceBullet',h.companion,2,data('DA_Swing',0,false),module(11,false)),
        bullet(12,'Class /Script/PBZCombatAsset.PBZ_OverlapBullet',h.companion,2,data('DA_Slam',0,true),module(12,true)),
        bullet(13,'Class /Script/PBZCombatAsset.PBZ_SweepTraceBullet',h.enemy,2,data('DA_EnemySwing',0,false),module(13,true)),
        bullet(14,'Class /Script/PBZCombatAsset.PBZ_OverlapBullet',h.companion,3,data('DA_Done',2,true),module(14,true)),
    }
    h.members={{team='companion',actor=h.companion},{team='blue',actor=typed(4,'BlueprintGeneratedClass /Game/Mobs/BP_Blue.BP_Blue_C')}}
    h.probe=Probe.new({log=function(s)h.logs[#h.logs+1]=s end,clock=function()return h.now end,
        findAll=function(name)return name=='BulletObjectBase' and h.objects or {} end,
        members=function()return h.members end,getPlayer=function()return h.player end,
        hp=function()return h.hp end,location=function(actor)return {X=actor==h.player and 0 or 500,Y=0,Z=0} end,
        factionSubsystem=function()return object('fs','FactionSubSystem',{GetFactionRelationFromTags=function()return 0 end})end})
    function h:line(pattern)for _,s in ipairs(self.logs)do if s:find(pattern,1,true) then return s end end end
    function h:count(pattern)local n=0;for _,s in ipairs(self.logs)do if s:find(pattern,1,true) then n=n+1 end end;return n end
    return h
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('each kind of companion attack is described once with its rules and both target answers',function()
    local h=harness();h.probe:tick()
    assert(h:line('阵营 随从=BP_Monster_MoTian_C 随从阵营=Faction.Player 玩家阵营=Faction.Player 组件关系 随从→玩家=友好 玩家→随从=友好 阵营表 随从阵营→玩家阵营=友好'),h.logs[1])
    local swing=assert(h:line('数据=DA_Swing'))
    assert(swing:find('类型=挥砍(PBZ_SweepTraceBullet)',1,true) and swing:find('打谁=只打敌人',1,true) and swing:find('能打同阵营=false',1,true),swing)
    assert(swing:find('能打玩家=false',1,true) and swing:find('能打当前敌人(BP_Monster_Enemy_C)=true',1,true) and swing:find('招式=GA_11_C',1,true),swing)
    assert(swing:find('忽略标签=State.Dead',1,true) and swing:find('阵营计算器=FactionCalc',1,true),swing)
    local slam=assert(h:line('数据=DA_Slam'))
    assert(slam:find('类型=范围(PBZ_OverlapBullet)',1,true) and slam:find('能打同阵营=true',1,true) and slam:find('能打玩家=true',1,true),slam)
    assert(not h:line('DA_EnemySwing'),'other owners are not described outside an HP drop')
    assert(not h:line('DA_Done'),'finished bullets are skipped')
    h.now=0.5;h.probe:tick();h.now=1.0;h.probe:tick()
    assert(h:count('数据=DA_Slam')==1 and h:count('阵营 随从=')==1,'described once')
end)
test('a player HP drop lists every live attack that may hit the player, companion and others',function()
    local h=harness();h.probe:tick()
    h.now=0.5;h.hp=900;h.probe:tick()
    local drop=assert(h:line('玩家掉血'))
    assert(drop:find('1000.0→900.0（-100.0）',1,true) and drop:find('最近的随从=BP_Monster_MoTian_C 5.0m',1,true),drop)
    assert(drop:find('随从 BP_Monster_MoTian_C:DA_Slam',1,true) and drop:find('BP_Monster_Enemy_C:DA_EnemySwing',1,true),drop)
    assert(not drop:find('DA_Swing；',1,true) and not drop:find(':DA_Swing',1,true),'an attack the module keeps off the player is not a suspect')
end)
test('the summary counts only companion attacks',function()
    local h=harness();h.probe:tick();h.now=0.5;h.hp=900;h.probe:tick()
    h.now=10;h.probe:tick()
    local summary=assert(h:line('近10秒'))
    assert(summary:find('随从至今用过 2 种攻击，能打到玩家的 1 种：BP_Monster_MoTian_C:DA_Slam',1,true),summary)
    assert(summary:find('玩家掉血 1 次共 100.0',1,true) and summary:find('子弹对象 4 个',1,true),summary)
end)
test('nothing happens without a companion, and nothing is ever written',function()
    local h=harness();h.members={{team='blue',actor=h.enemy}}
    h.probe:tick();h.now=20;h.hp=10;h.probe:tick()
    assert(#h.logs==0)
    local busy=harness();for i=1,30 do busy.now=i*0.5;busy.hp=1000-i;busy.probe:tick() end
    assert(writes==0,'the probe only reads: '..writes)
end)
print('companion_hit_probe: PASS ('..count..' description, drop attribution, summary and read-only regressions)')
