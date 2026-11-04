package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Aim=require('player_aim')
local Combos=require('boss_combos')
local Stands=require('arena_stands')
local Retry=require('lookup_retry')
local passed,failed=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1;print('ok - '..name)
    else failed=failed+1;print('FAIL - '..name..': '..tostring(err)) end
end
local serial=0
local function object(name,fields)
    serial=serial+1;local address=serial
    local o=fields or {};o.live=true
    o.IsValid=function(self)return self.live end
    o.GetAddress=function()return address end
    o.GetFName=function()return {ToString=function()return name end}end
    o.GetClass=function()return {IsValid=function()return true end,GetFName=o.GetFName,GetSuperStruct=function()return nil end}end
    return o
end
local function fixture(module)
    local h={now=0,members={},counts={},hooks={},loaded={},logs={},scans={}}
    StaticFindObject=function(path)
        h.counts[path]=(h.counts[path] or 0)+1
        return h.loaded[path]
    end
    RegisterHook=function(path,callback)assert(h.loaded[path],'cannot hook missing function');h.hooks[path]=callback;return 1,2 end
    UnregisterHook=function(path)h.hooks[path]=nil end
    FindAllOf=function(class)h.scans[class]=(h.scans[class] or 0)+1;return {}end
    FName=function(s)return s end
    h.mod=module.new({clock=function()return h.now end,now=function()return h.now end,
        members=function()return h.members end,fighting=function()return true end,
        log=function(s)h.logs[#h.logs+1]=s end,opponentOf=function()return h.target end,world=function()return h.world end})
    function h.add(class,team,stand)
        local actor=object(class)
        h.members[#h.members+1]={actor=actor,team=team or 'blue',stand=stand}
        return actor
    end
    function h.load(name)
        local path=module.paths[name];h.loaded[path]=object(name);return path
    end
    function h.count(name)return h.counts[module.paths[name]] or 0 end
    function h.run(first,last)
        for i=first*4,last*4 do h.now=i/4;h.mod:tick() end
    end
    return h
end
local function aimFixture(class)
    local h=fixture(Aim)
    for _,name in ipairs({'character','pawn','force'})do h.load(name)end
    h.add(class or 'BP_Monster_MoYuan_C');h.add('BP_Monster_Yuu_C','red')
    return h
end
local flying={'FlyingSwordStart','FlyingSwordEnd','FlyingSpearStart','FlyingSpearEnd',
    'FlyingHammer_BigStart','FlyingHammer_BigEnd','FlyingGunStart','FlyingGunEnd'}
local function totalFlying(h)local n=0;for _,name in ipairs(flying)do n=n+h.count(name)end;return n end
local function report(label,h)
    local total=0;for _,n in pairs(h.counts)do total=total+n end
    print('MEASURE '..label..' flying='..totalFlying(h)..' all='..total)
end

test('180 seconds without ZuoShang never looks up flying hooks, including battle start',function()
    local h=aimFixture();h.run(0,180)
    report('no_caster',h)
    assert(totalFlying(h)==0,'flying queries='..totalFlying(h))
    for _,name in ipairs({'lock','bullet','bulletAbility','launch','skillStart'})do
        assert(h.count(name)>0 and h.count(name)<=8,name..' queries='..h.count(name))
    end
end)
test('180 seconds with dragon ZuoShang loads one weapon and backs off the other six paths',function()
    local h=aimFixture('BP_Monster_ZuoShang_P2_C');h.load('FlyingSwordStart');h.load('FlyingSwordEnd');h.run(0,180)
    report('partial_weapons',h)
    assert(h.count('FlyingSwordStart')==1 and h.hooks[Aim.paths.FlyingSwordEnd])
    for _,name in ipairs(flying)do assert(h.count(name)<=8,name..' queries='..h.count(name))end
    assert(#h.logs<150,'logs must remain bounded')
end)
test('ZuoShang arriving halfway starts discovery immediately, with no earlier weapon queries',function()
    local h=aimFixture();h.run(0,90)
    local before=totalFlying(h);h.add('BP_Monster_ZuoShang_C');h.load('FlyingSwordStart')
    h.now=90.25;h.mod:tick();h.run(90.5,180)
    assert(before==0,'queried before the caster arrived: '..before)
    assert(h.hooks[Aim.paths.FlyingSwordStart] and h.count('FlyingSwordStart')==1)
    assert(h.count('FlyingGunStart')<=7)
end)
test('all eight absent flying paths have an exact 64-query polling bound over 180 seconds',function()
    local h=aimFixture('BP_Monster_ZuoShang_C');h.run(0,180)
    local total=0;for _,n in pairs(h.counts)do total=total+n end
    report('all_missing',h)
    assert(totalFlying(h)==64 and total==107)
end)
test('a new unit resets pending discovery even during the long backoff',function()
    local h=aimFixture('BP_Monster_ZuoShang_C');h.run(0,80)
    local before=h.count('FlyingGunStart');h.load('bullet');h.add('BP_Monster_MoYuan_C','red')
    h.now=80.25;h.mod:tick()
    assert(h.hooks[Aim.paths.bullet],'new unit must wake the late selector')
    assert(h.count('FlyingGunStart')==before+1,'new unit must reset weapon discovery')
    h.run(80.5,180);assert(h.count('FlyingGunStart')<=15)
end)
test('late blueprints install on the next due retry within 60 seconds',function()
    local h=aimFixture('BP_Monster_ZuoShang_C');h.run(0,62)
    for _,name in ipairs({'FlyingGunStart','bullet','lock','launch','skillStart'})do h.load(name)end
    h.run(62.25,120.75)
    for _,name in ipairs({'FlyingGunStart','bullet','lock','launch','skillStart'})do
        assert(not h.hooks[Aim.paths[name]],'blueprint retried before its deadline: '..name)
    end
    h.now=121;h.mod:tick()
    for _,name in ipairs({'FlyingGunStart','bullet','lock','launch','skillStart'})do
        assert(h.hooks[Aim.paths[name]],'late blueprint missed its due retry: '..name)
    end
    h.target=h.members[2].actor
    h.target.RootComponent=object('Root',{GetOwner=function()return h.target end})
    local sword=object('BP_Bullet_ZuoShang_FlyingGun_C',{BulletOwnerAvatar=h.members[1].actor})
    h.hooks[Aim.paths.FlyingGunStart](sword)
    assert(sword.CurrentTarget.Component==h.target.RootComponent,'installed hook must aim at the opponent')
    h.run(121.25,180);assert(h.count('FlyingGunStart')==8)
end)
test('combo hook misses back off during a three minute linked pair',function()
    local h=fixture(Combos);h.mod.enabled=true
    h.add('BP_Monster_TieGui_C');h.add('BP_Monster_Yuu_C')
    h.run(0,180)
    print('  combo gate queries='..h.count('gateYuu'))
    for name in pairs(Combos.paths)do assert(h.count(name)>0 and h.count(name)<=8,name..' queries='..h.count(name))end
    for path,n in pairs(h.counts)do assert(n<=8,path..' queries='..n)end
end)
test('a fixed stand roster backs off all six missing hooks and empty passive scans',function()
    local h=fixture(Stands);h.add('BP_Monster_Yuu_Stand_C','blue',true);h.run(0,180)
    print('  stand enable queries='..h.count('enable')..' passive scans='..tostring(h.scans.GA_Stand_Passive_C))
    for name in pairs(Stands.paths)do assert(h.count(name)==8,name..' queries='..h.count(name))end
    assert(h.scans.GA_Stand_Passive_C==8,'empty passive scans='..tostring(h.scans.GA_Stand_Passive_C))
end)
test('stand hook misses and empty passive scans back off and wake on a new stand',function()
    local h=fixture(Stands);h.add('BP_Monster_Yuu_Stand_C','blue',true);h.run(0,80)
    h.load('enable');h.add('BP_Monster_TieGui_Stand_C','blue',true);h.now=80.25;h.mod:tick()
    assert(h.hooks[Stands.paths.enable],'new stand must wake pending discovery')
    h.run(80.5,180)
    for name in pairs(Stands.paths)do assert(h.count(name)<=15,name..' queries='..h.count(name))end
    assert((h.scans.GA_Stand_Passive_C or 0)<=15,'empty passive scans='..tostring(h.scans.GA_Stand_Passive_C))
end)
test('only the verified ZuoShang families and their subclasses discover flying weapons',function()
    for _,class in ipairs({'BP_Monster_ZuoShang_C','BP_Monster_ZuoShang_Ending_C','BP_Monster_ZuoShang_P2_C','BP_Monster_ZuoShang_P2_Stand_C'})do
        local h=aimFixture(class);h.mod:tick();assert(totalFlying(h)==8,class)
    end
    for _,class in ipairs({'BP_Monster_ZuoShang_Young_C','BP_Monster_ZuoShang_Young_Tutorial_C','BP_NotZuoShang_C'})do
        local h=aimFixture(class);h.run(0,180);assert(totalFlying(h)==0,class)
    end
    local h=aimFixture('BP_DerivedDragon_C')
    local parent=object('BP_Monster_ZuoShang_P2_C'):GetClass()
    local cls=h.members[1].actor:GetClass();cls.GetSuperStruct=function()return parent end
    h.members[1].actor.GetClass=function()return cls end
    h.mod:tick();assert(totalFlying(h)==8,'derived caster was missed')
end)
test('missing effect libraries and collection do not cause per-frame global lookups',function()
    local h=aimFixture('BP_Monster_ZuoShang_P2_C');h.load('skillStart')
    h.target=object('Target',{K2_GetActorLocation=function()return {X=0,Y=0,Z=0}end})
    h.world=object('World')
    local loop
    LoopInGameThreadWithDelay=function(_,fn)loop=fn;return 1 end
    CancelDelayedAction=function()loop=nil end
    local ability=object('GA_ZuoShang_P2_Skill_17_C',{GetAvatarActorFromActorInfo=function()return h.members[1].actor end})
    h.mod:tick()
    for i=0,18000 do
        h.now=i/100
        if i%1000==0 then h.hooks[Aim.paths.skillStart](ability)end
        if loop then loop()end
    end
    for path,n in pairs(h.counts)do assert(n<=8,path..' effect queries='..n)end
    assert((h.counts['/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'] or 0)>0)
    assert((h.counts['/PBZVFXPack/VFX/A_Niagara/CommonNPC/MPC_CharInfo_001.MPC_CharInfo_001'] or 0)>0)
end)
test('successful collection lookup remains available on the first frame of every later cast',function()
    local h=aimFixture('BP_Monster_ZuoShang_P2_C');h.load('skillStart')
    h.target=object('Target',{K2_GetActorLocation=function()return {X=100,Y=0,Z=0}end});h.world=object('World')
    FName=function(text)return text end
    local writes,loop=0,nil
    local collection=object('Collection',{GetColorParameter=function()return {R=100,G=0,B=0,A=1}end})
    h.loaded['/Script/Niagara.Default__NiagaraFunctionLibrary']=object('Library',{GetNiagaraParameterCollection=function()return collection end})
    h.loaded['/PBZVFXPack/VFX/A_Niagara/CommonNPC/NPC_CharInfo_001.NPC_CharInfo_001']=object('CollectionAsset')
    h.loaded['/Script/Engine.Default__KismetMaterialLibrary']=object('MaterialLibrary',{SetVectorParameterValue=function()writes=writes+1 end,
        GetVectorParameterValue=function()return {R=100,G=0,B=0,A=1}end})
    h.loaded['/PBZVFXPack/VFX/A_Niagara/CommonNPC/MPC_CharInfo_001.MPC_CharInfo_001']=object('MaterialCollection')
    LoopInGameThreadWithDelay=function(_,fn)loop=fn;return 1 end;CancelDelayedAction=function()loop=nil end
    local ability=object('GA_ZuoShang_P2_Skill_17_C',{GetAvatarActorFromActorInfo=function()return h.members[1].actor end})
    h.mod:tick()
    for cast=0,7 do
        h.now=cast*25;h.hooks[Aim.paths.skillStart](ability);loop()
        assert(writes==cast+1,'cast '..cast..' was delayed by a successful lookup backoff')
        h.now=h.now+20;loop();assert(loop==nil)
    end
end)
test('continuous reinforcements reset pending lookups at most once every ten seconds',function()
    local h=aimFixture('BP_Monster_ZuoShang_C')
    local last,early=0,false
    for i=0,720 do
        h.now=i/4
        if i>0 and i%4==0 then
            h.add('BP_Monster_MoYuan_C','red')
        end
        h.mod:tick()
        if i==4 then last=h.count('FlyingGunStart') end
        if i==8 then early=h.count('FlyingGunStart')~=last end
    end
    report('reinforcements',h)
    assert(not early,'reinforcement bypassed backoff at second 2')
    -- Each ten-second window retries at offsets 0, 1, 3 and 7; t=180 is included.
    assert(totalFlying(h)==584,'continuous reinforcement queries='..totalFlying(h))
    local resets=0;for _,line in ipairs(h.logs)do if line:find('重置查询退避',1,true)then resets=resets+1 end end
    assert(resets==18,'effective resets with pending records='..resets)
end)
test('retry intervals and the reset boundary follow the fake clock exactly',function()
    local now=0;local retry=Retry.new({clock=function()return now end})
    for _,due in ipairs({0,1,3,7,15,31,61,121,181})do
        if due>0 then now=due-0.001;assert(not retry:ready('missing'),'early retry at '..now)end
        now=due;assert(retry:ready('missing'),'missed deadline '..now)
    end
    now=182;retry:reset();assert(retry:ready('missing'))
    for _,due in ipairs({183,185,189})do now=due;assert(retry:ready('missing'))end
    now=191.999;retry:reset();assert(not retry:ready('missing'),'reset took effect before ten seconds')
    now=192;retry:reset();assert(retry:ready('missing'),'reset at ten seconds did not restart discovery')
end)
test('roster class discovery runs only for newly seen addresses and forgets departures',function()
    local h=aimFixture();local reads=0
    for _,member in ipairs(h.members)do
        local actor=member.actor;local getClass,getName=actor.GetClass,actor.GetFName
        actor.GetClass=function(...)reads=reads+1;return getClass(...)end
        actor.GetFName=function(...)reads=reads+1;return getName(...)end
    end
    h.mod:tick();local before=reads;assert(before>0)
    h.run(0.25,20);assert(reads==before,'stable roster re-read identities '..(reads-before)..' times')
    local old=h.members[1].actor;h.members[1]=h.members[2];h.members[2]=nil
    h.now=20.25;h.mod:tick()
    local fresh=object('BP_Monster_ZuoShang_C');fresh.GetAddress=old.GetAddress
    h.members[#h.members+1]={actor=fresh,team='blue'};h.now=20.5;h.mod:tick()
    assert(totalFlying(h)==8,'departed address kept the old caster classification')
end)
test('a replacement stand at the same address wakes discovery after the reset interval',function()
    local h=fixture(Stands);local old=h.add('BP_Monster_Yuu_Stand_C','blue',true);h.run(0,80)
    local fresh=object('BP_Monster_Yuu_Stand_C');fresh.GetAddress=old.GetAddress
    old.live=false;h.members[1].actor=fresh;h.load('enable');h.now=80.25;h.mod:tick()
    assert(h.hooks[Stands.paths.enable],'replacement stand ignored pending hook')
end)
print(string.format('lookup retries: %d passed, %d failed',passed,failed))
if failed>0 then os.exit(1)end
