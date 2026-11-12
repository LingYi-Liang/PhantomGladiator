package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Level=require('spawn_level')
local HomeLevels=require('home_levels')
local address=0
-- A character with the BP_RenewalNPC Level property (nil level: a class without it) and the AI spawner that put it
-- out, as the game's own enemies have (`loose`: none, like a summon).
local function object(name,level,at,attrs,loose)
    address=address+1;local a=address
    return {IsValid=function()return true end,GetAddress=function()return a end,Level=level,at=at,attrs=attrs or {},
        Spawner=not loose and {IsValid=function()return true end} or nil,
        GetCombatLevel=function(self)return self.Level end,
        GetClass=function()return {IsValid=function()return true end,GetFName=function()return {ToString=function()return name..'_C' end}end}end}
end
local function harness(npcs,files,homeLevels,world)
    local h={lines={},scans=0,clock=0,files=files or {},world=world or 'PBZ_Test_WP'}
    h.io={open=function(path,mode)
        if mode=='r' and h.files[path]==nil then return nil end
        local text=h.files[path] or ''
        return {read=function()return text end,write=function(_,s)text=s;return true end,
            close=function()if mode=='w' then h.files[path]=text end;return true end}
    end}
    h.stats={read=function(_,actor,field)
        local v=actor.attrs[field];return v and {base=v,current=v} or nil
    end}
    h.player=object('BP_RenewalPlayer',nil,{X=0,Y=0,Z=0})
    h.npcs=npcs
    h.ours={}
    h.level=Level.new({log=function(s)h.lines[#h.lines+1]=s end,attributes=h.stats,clock=function()return h.clock end,
        path='R',io=h.io,
        getPlayer=function()return h.player end,getLocation=function(a)return a.at end,
        collect=function()h.scans=h.scans+1;return h.npcs end,ours=function()return h.ours end,homeLevels=homeLevels,
        getWorldName=function()return h.world end})
    function h.all()return table.concat(h.lines,'\n')end
    return h
end

-- Before FinishSpawn: written up to the highest Level among nearby map NPCs; ours and far ones don't count.
do
    local summoned=object('BP_Monster_MoTian',0,{X=0,Y=0,Z=0},{Health_Max=12000})
    local other=object('BP_Monster_MoTian',30,{X=100,Y=0,Z=0})
    local mob=object('Mob_B',15,{X=5000,Y=0,Z=0},{Level=15,Health_Max=3000})
    local h=harness({object('Mob_A',12,{X=1000,Y=0,Z=0}),mob,object('Far_Boss',40,{X=900000,Y=0,Z=0}),other})
    h.ours[tostring(other.GetAddress())]=true
    local r=h.level:prepare(summoned,'MoTian')
    assert(r.applied and summoned.Level==15,h.all())
    assert(h.all():find('玩家附近地图怪=2只 最高=15.00(Mob_B)',1,true),h.all())
    assert(h.all():find('写入等级 0.00→15.00 调用=true 读回=15.00',1,true),h.all())
    -- After activation the unit is logged next to the map NPC its level came from.
    summoned.attrs={Level=15,Health_Max=30000}
    h.level:verify(summoned)
    assert(h.all():find('出生后 召唤 BP_Monster_MoTian 等级字段=15.00 战斗等级=15.00 Level=15.00 Health_Max=30000.00',1,true),h.all())
    assert(h.all():find('出生后 对照地图怪 Mob_B 等级字段=15.00',1,true),h.all())
    -- A second summon in the same batch reuses the scan.
    local second=object('BP_Monster_MoTian',0,{X=0,Y=0,Z=0})
    h.level:prepare(second,'MoTian')
    assert(second.Level==15 and h.scans==1 and h.level:status().raised==2)
end

-- Only units the game's spawners put out are map enemies: a summon left from before Restart All Mods (no spawner,
-- no group) is not, however high its level.
do
    local h=harness({object('Leftover',60,{X=10,Y=0,Z=0},nil,true),object('Mob',3,{X=20,Y=0,Z=0})})
    local unit=object('Unit',0,{X=0,Y=0,Z=0})
    assert(h.level:prepare(unit,'Unit').applied and unit.Level==3,h.all())
    assert(h.all():find('玩家附近地图怪=1只 最高=3.00(Mob) 样本=[Mob=3] 不是刷怪点刷出的=1只',1,true),h.all())
    local grouped=object('Grouped',7,{X=30,Y=0,Z=0},nil,true)
    grouped.MobGroup={IsValid=function()return true end}
    local g=harness({grouped})
    local other=object('Unit',0,{X=0,Y=0,Z=0})
    assert(g.level:prepare(other,'Unit').applied and other.Level==7,'a unit in a mob group counts too')
    -- A summoned rider left from before a reload sits on the mod's own tagged spawner (mounts.lua): still not a map enemy.
    local rider=object('Rider',60,{X=10,Y=0,Z=0})
    rider.Spawner.SpawnerID={ToString=function()return 'PhantomGladiator_Mount' end}
    local r=harness({rider,object('Mob',4,{X=20,Y=0,Z=0})})
    local third=object('Unit',0,{X=0,Y=0,Z=0})
    assert(r.level:prepare(third,'Unit').applied and third.Level==4,r.all())
    assert(r.all():find('不是刷怪点刷出的=1只',1,true),r.all())
end

-- Never lowered; no Level property or nothing to compare with leaves the unit as it is.
do
    local h=harness({object('Mob',20,{X=10,Y=0,Z=0})})
    local strong=object('Boss',50,{X=0,Y=0,Z=0})
    assert(not h.level:prepare(strong,'Boss').applied and strong.Level==50 and h.all():find('不调整',1,true))
    local plain=object('Actor',nil,{X=0,Y=0,Z=0})
    assert(not h.level:prepare(plain,'Actor').applied and plain.Level==nil)
    local lonely=harness({})
    local unit=object('Unit',0,{X=0,Y=0,Z=0})
    assert(not lonely.level:prepare(unit,'Unit').applied and unit.Level==0)
    assert(lonely.level:status().message=='附近没有地图怪可参照')
    local far=harness({object('Far',25,{X=900000,Y=0,Z=0})})
    local unit2=object('Unit',0,{X=0,Y=0,Z=0})
    far.level:prepare(unit2,'Unit')
    assert(unit2.Level==25 and far.all():find('已加载地图地图怪=1只',1,true),far.all())
end

-- A write the actor refuses is a failure, not a raise.
do
    local h=harness({object('Mob',20,{X=10,Y=0,Z=0})})
    local stuck=setmetatable({},{__index=object('Unit',0,{X=0,Y=0,Z=0}),__newindex=function()end})
    assert(not h.level:prepare(stuck,'Unit').applied)
    assert(h.level:status().failures==1 and h.level:status().raised==0)
end

-- The last level found is remembered and saved with its world: a summon with no map NPC loaded (and no spawner
-- data for the world) uses it in that world only, also after a reload.
do
    local h=harness({object('Mob_A',18,{X=10,Y=0,Z=0})})
    local first=object('Unit',0,{X=0,Y=0,Z=0})
    h.level:prepare(first,'Unit')
    assert(first.Level==18 and h.files['R/spawn-level.tsv']=='SpawnLevelV1\t18.00\tMob_A\tPBZ_Test_WP\n',h.files['R/spawn-level.tsv'])
    h.npcs={};h.clock=10
    local second=object('Unit',0,{X=0,Y=0,Z=0})
    assert(h.level:prepare(second,'Unit').applied and second.Level==18)
    assert(h.all():find('附近没有地图怪，沿用这张图上次记录的等级 18.00（来自 Mob_A）',1,true),h.all())
    local reloaded=harness({},h.files)
    local third=object('Unit',0,{X=0,Y=0,Z=0})
    assert(reloaded.level:prepare(third,'Unit').applied and third.Level==18,reloaded.all())
    -- Another world never takes it (v0.37.6: 22 from 正道大营 went into 悲泣溪谷).
    local elsewhere=harness({},h.files,nil,'PBZ_Other_WP')
    local away=object('Unit',0,{X=0,Y=0,Z=0})
    assert(not elsewhere.level:prepare(away,'Unit').applied and away.Level==0 and elsewhere.level:status().message=='附近没有地图怪可参照')
    -- A file from before v0.37.6 has no world and is not reused.
    local old=harness({},{['R/spawn-level.tsv']='SpawnLevelV1\t18.00\tMob_A\n'})
    local stale=object('Unit',0,{X=0,Y=0,Z=0})
    assert(not old.level:prepare(stale,'Unit').applied and stale.Level==0)
    -- A new area found later replaces it.
    local moved=harness({object('Mob_C',6,{X=10,Y=0,Z=0})},h.files)
    local fourth=object('Unit',0,{X=0,Y=0,Z=0})
    moved.level:prepare(fourth,'Unit')
    assert(fourth.Level==6 and h.files['R/spawn-level.tsv']=='SpawnLevelV1\t6.00\tMob_C\tPBZ_Test_WP\n')
    -- A damaged file is ignored.
    local broken=harness({},{['R/spawn-level.tsv']='junk'})
    local fifth=object('Unit',0,{X=0,Y=0,Z=0})
    assert(not broken.level:prepare(fifth,'Unit').applied and fifth.Level==0)
end
-- With no map NPC loaded, the game's own spawners where the player is give the level (home_levels.lua nearest()),
-- before any remembered level.
do
    local asked
    local home={target=function()return nil end,nearest=function(_,world,at,radius,actor)
        asked={world=world,at=at,radius=radius,actor=actor}
        return world=='PBZ_Test_WP' and {level=3,distance=42.4,near=true} or nil
    end}
    local h=harness({},{['R/spawn-level.tsv']='SpawnLevelV1\t22.00\tMob_Far\tPBZ_Test_WP\n'},home)
    local unit=object('Unit',0,{X=0,Y=0,Z=0})
    assert(h.level:prepare(unit,'Unit').applied and unit.Level==3,h.all())
    assert(asked.world=='PBZ_Test_WP' and asked.at==h.player.at and asked.radius==200 and asked.actor==unit)
    assert(h.all():find('附近没有地图怪，按玩家附近的游戏刷怪点 3.00 级（42 米外，PBZ_Test_WP）',1,true),h.all())
    local lost=harness({},nil,home,'PBZ_Unknown')
    local other=object('Unit',0,{X=0,Y=0,Z=0})
    assert(not lost.level:prepare(other,'Unit').applied and other.Level==0,'a world without spawner data and nothing remembered')
end
-- An explicit cycle replaces the save's contribution to the live map level, even when reducing it.
do
    local ctx={cycle=1,difficulty='Normal'}
    local home=HomeLevels.new({context=function()return ctx end,cycleExempt=function(actor)return actor.exempt end,
        native={},places={PBZ_Test_WP={{0,0,0,8}}}})
    home.mode='HERE'
    local mob=object('MapNPC',41,{X=10,Y=0,Z=0})
    mob.exempt=false
    local h=harness({mob},nil,home)
    local first=object('Unit',0)
    assert(h.level:prepare(first,'Unit').applied and first.Level==41,'follow uses the live level as read')

    home.cycle=7
    local seventh=object('Unit',0)
    assert(h.level:prepare(seventh,'Unit').applied and seventh.Level==166,h.all())
    local immune=object('Immune',0)
    immune.exempt=true
    assert(h.level:prepare(immune,'Immune').applied and immune.Level==16,'summon immunity skips the selected bonus')

    home.cycle=1
    local reduced=object('Unit',41)
    assert(h.level:prepare(reduced,'Unit').applied and reduced.Level==16,'an explicit lower cycle can reduce the spawn level')
    assert(first.Level==41 and seventh.Level==166 and mob.Level==41,'earlier summons and the reference are untouched')

    home.cycle=7
    mob.exempt=true
    mob.Level=16
    h.clock=h.clock+10
    local other=object('Unit',0)
    assert(h.level:prepare(other,'Unit').applied and other.Level==166,'do not subtract the save bonus from an exempt reference')
    mob.exempt=nil
    local fallback=object('Unit',0)
    assert(h.level:prepare(fallback,'Unit').applied and fallback.Level==158,'unknown reference contribution falls back to the spawner data')
end
-- The map level is looked up for the log and remembered; logged when it changes. status() shows what the last
-- summon got (the app's "上次召唤"), nothing before the first.
do
    local h=harness({object('Mob_D',20,{X=10,Y=0,Z=0})})
    assert(h.level:status().last_level==nil)
    assert(h.level:refresh()==true,'map enemies were found')
    assert(h.level:status().last_level==nil and h.files['R/spawn-level.tsv']=='SpawnLevelV1\t20.00\tMob_D\tPBZ_Test_WP\n')
    assert(h.all():find('读召唤等级 玩家附近地图怪=1只 最高=20.00(Mob_D)；记录的等级=20.00',1,true),h.all())
    local lines=#h.lines;h.clock=h.clock+10;h.level:refresh()
    assert(#h.lines==lines,'the same level again is not logged again')
    h.npcs={object('Mob_E',22,{X=10,Y=0,Z=0})};h.clock=h.clock+10;h.level:refresh()
    assert(h.all():find('最高=22.00(Mob_E)；记录的等级=22.00',1,true),'a new area is followed and logged')
    local unit=object('Unit',0,{X=0,Y=0,Z=0})
    h.level:prepare(unit,'Unit')
    assert(h.level:status().last_level==22 and h.level:status().last_unit=='Unit','the last summon\'s level')
    local empty=harness({},h.files)
    assert(empty.level:refresh()==false,'nothing loaded yet: the caller looks again soon')
end
-- HOME and CUSTOM (home_levels.lua) give the level outright, even below the map's.
do
    local picks={Unit={level=6,source='native',map='血色森林',part='C',count=11,difficulty='Hard',cycle=0},Custom={level=12,source='custom'}}
    local asked
    local home={target=function(_,unit,actor)asked=actor;return picks[unit] end}
    local h=harness({object('Mob_F',20,{X=10,Y=0,Z=0})},nil,home)
    local unit=object('Unit',0,{X=0,Y=0,Z=0})
    assert(h.level:prepare(unit,'Unit').applied and unit.Level==6,'its home level, below the map enemies around')
    assert(asked==unit,'the unit itself is passed on, for its difficulty')
    assert(h.all():find('按老家等级（血色森林 C 刷怪点11个 难度=Hard 周目=0）写入等级 0.00→6.00 调用=true 读回=6.00',1,true),h.all())
    local custom=object('Custom',0,{X=0,Y=0,Z=0})
    assert(h.level:prepare(custom,'Custom').applied and custom.Level==12 and h.all():find('按自定义等级写入等级 0.00→12.00',1,true))
    local other=object('Other',0,{X=0,Y=0,Z=0})
    assert(h.level:prepare(other,'Other').applied and other.Level==20,'no choice: the nearby rule')
end

-- An escort (a 驯犬客's 狂犬) takes its leader's level, whatever the mode would give it; the status keeps the leader.
do
    local h=harness({object('Mob_A',9,{X=1000,Y=0,Z=0})})
    local tamer=object('BP_Monster_DogTamer',0,{X=0,Y=0,Z=0})
    assert(h.level:prepare(tamer,'Tamer').applied and tamer.Level==9)
    local dog=object('BP_Monster_Dog',3,{X=0,Y=0,Z=0},nil,true)
    assert(h.level:prepare(dog,'Dog',tamer).applied and dog.Level==9,h.all())
    assert(h.all():find('随行 unit=Dog 跟随 BP_Monster_DogTamer 的等级 3.00→9.00 调用=true 读回=9.00',1,true),h.all())
    assert(h.level:status().last_level==9 and h.level:status().raised==1,'the dog is not counted as a summon of its own')
    local same=object('BP_Monster_Dog',9,{X=0,Y=0,Z=0},nil,true)
    assert(h.level:prepare(same,'Dog',tamer).applied and same.Level==9,'already at the leader level')
    -- A leader whose level cannot be read: the dog goes by the summon level setting.
    local gone=object('Gone',nil,{X=0,Y=0,Z=0})
    local stray=object('BP_Monster_Dog',0,{X=0,Y=0,Z=0},nil,true)
    assert(h.level:prepare(stray,'Dog',gone).applied and stray.Level==9,h.all())
    assert(h.all():find('带队单位的等级读不到',1,true))
end
print('spawn_level ok')
