package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Stands=require('arena_stands')
local n,passed=0,0
local function object(fields)
    n=n+1;local key=n
    local o=fields or {};o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function()assert(o.alive);return key end
    o.GetFName=o.GetFName or function()assert(o.alive);return 'Object'..key end
    return o
end
-- The code under test wraps its calls in pcall, so an error alone would go unnoticed: each access is counted. In the
-- game such an access is a native crash that pcall does not stop.
local illegal=0
local function dead()
    return setmetatable({IsValid=function()return false end,type=function()return 'UObject' end},
        {__index=function(_,key)illegal=illegal+1;error('invalid dereference: '..key)end})
end
local function class(name,parent)
    return object({GetFName=function()return name end,GetSuperStruct=function()return parent end})
end
local function actor(name,tags)
    local cls=class(name)
    return object({GetClass=function()return cls end,bHidden=false,
        AbilitySystemComponent=object({GetGameplayTagCount=function(_,tag)return (tags or {})[tag.TagName] or 0 end})})
end
-- As in the game: FName is callable but is not a Lua function.
FName=setmetatable({},{__call=function(_,s)return s end})
local function test(name,fn)fn();passed=passed+1;print('ok - '..name)end
test('tag identifies a stand without a class-name guess',function()
    local a=actor('BP_Unknown_C',{['CharacterType.Stand']=1})
    local ok,proof=Stands.isStand(a)
    assert(ok and proof=='CharacterType.Stand=1')
    assert(not Stands.isStand(actor('BP_Unknown_Stand_C')),'an unverified suffix is not enough')
    assert(not Stands.isStand(actor('BP_LengTu_Doll_C')))
end)
test('known classes and their subclasses are detected before tag initialization',function()
    for _,name in ipairs({'BP_Monster_Yuu_Stand_C','BP_Monster_TieGui_Stand_C','BP_Monster_ZuoShang_P2_Stand_C'})do
        local a=actor(name)
        assert(Stands.isStand(a))
        a.GetClass=function()return class('BP_Derived_C',class(name))end
        assert(Stands.isStand(a))
    end
end)
test('invalid actors, components and classes are never dereferenced',function()
    assert(not Stands.isStand(dead()))
    local a=actor('BP_Test_C');a.AbilitySystemComponent=dead();a.GetClass=function()return dead()end
    assert(not Stands.isStand(a))
    assert(illegal==0,'accessed an invalid object '..illegal..' times')
end)

local function fixture()
    local f={now=0,logs={},hooks={},ids=0,members={},abilities={},missing={}}
    StaticFindObject=function(path)return not f.missing[path] and object() or nil end
    RegisterHook=function(path,callback)f.ids=f.ids+1;f.hooks[path]=callback;return f.ids,f.ids+100 end
    UnregisterHook=function(path)f.hooks[path]=nil end
    FindAllOf=function(name)assert(name=='GA_Stand_Passive_C');return f.abilities end
    f.owner=actor('BP_Monster_MuXiaoKui_P2_C')
    f.stand=actor('BP_Monster_Yuu_Stand_C',{['CharacterType.Stand']=1})
    f.stand.AttributeSetBase=object({Health={CurrentValue=100}})
    f.ai=object({bAIStarted=false,CurrentStateTag={TagName='None'}})
    f.action=object({UseIdleSummonPool=false,GetAvatarActor=function()return f.owner end})
    f.passive=object({GetAvatarActorFromActorInfo=function()return f.stand end,
        Enabled=false,EnableCount=0,IsOwnerBreak=false,NormalFade=object({IsActive=function()return false end})})
    f.abilities={f.passive}
    f.members={{actor=f.owner,team='blue'},{actor=f.stand,team='blue',stand=true,summoner=f.owner}}
    f.watch=Stands.new({members=function()return f.members end,clock=function()return f.now end,
        aiOf=function()return f.ai end,log=function(s)f.logs[#f.logs+1]=s end})
    function f.all()return table.concat(f.logs,'\n')end
    function f.call(kind,...)return f.hooks[Stands.paths[kind]](...)end
    return f
end
local function param(value)
    return {type=function()return 'RemoteUnrealParam' end,get=function()return value end,
        set=function()error('read-only hooks must not alter out parameters')end}
end
test('no owned stand installs nothing; a newly discovered stand registers all six paths',function()
    local f=fixture();local keep=f.members;f.members={};f.watch:tick();assert(f.ids==0)
    f.members=keep;f.watch:tick();f.watch:tick();assert(f.ids==6)
    assert(f.all():find('bAIStarted=false',1,true) and f.all():find('NormalFade=false',1,true))
end)
test('find, idle and growth diagnostics read out parameters and never replace results',function()
    local f=fixture();f.watch:tick()
    assert(f.call('find',param(f.action),param(f.stand),param(f.stand))==nil)
    assert(f.call('idle',f.action,f.stand,f.stand,param(false))==nil)
    local summoner=object({MaxSummonCount=2,SpawnedSummonInstances={{Pawn=f.stand}}})
    assert(f.call('grow',f.action,summoner,f.stand,param(nil))==nil)
    assert(f.all():find('UseIdleSummonPool=false',1,true) and f.all():find('结果=false',1,true))
    assert(f.all():find('MaxSummonCount=2 实例记录数=1',1,true))
    assert(f.all():find('Dead=0 Action=0 StandEnable=0 bHidden=false',1,true))
end)
test('passive callbacks report event, counter and flags after the game ran',function()
    local f=fixture();f.watch:tick()
    f.passive.Enabled=true;f.passive.EnableCount=1
    assert(f.call('enable',f.passive)==nil)
    assert(f.call('event',f.passive,param({EventTag={TagName='GameplayEvent.EnableStand.True'}}))==nil)
    f.passive.Enabled=false;f.passive.EnableCount=0
    assert(f.call('disable',f.passive)==nil)
    assert(f.all():find('事件=GameplayEvent.EnableStand.True',1,true))
    assert(f.all():find('Enabled=true EnableCount=1',1,true) and f.all():find('Enabled=false EnableCount=0',1,true))
end)
test('foreign actors and expired UObject references are ignored',function()
    local f=fixture();f.watch:tick();local before=#f.logs
    local foreign=object({GetAvatarActor=function()return actor('BP_Other_C')end})
    f.call('find',foreign,f.stand,param(nil));f.call('find',dead(),dead(),param(nil))
    f.call('disable',object({GetAvatarActorFromActorInfo=function()return actor('BP_Other_C')end}))
    f.call('enable',dead());assert(#f.logs==before)
    f.ai=dead();f.passive.NormalFade=dead();f.stand.AttributeSetBase=dead();f.stand.AbilitySystemComponent=dead()
    f.now=15;f.watch:tick();assert(f.all():find('HP=nil',1,true))
    assert(illegal==0,'accessed an invalid object '..illegal..' times')
end)
test('late blueprint loading retries without duplicate registrations',function()
    local f=fixture();f.missing[Stands.paths.find]=true;f.watch:tick();assert(f.ids==5)
    f.missing={};f.now=0.5;f.watch:tick();assert(f.ids==5)
    f.now=1;f.watch:tick();assert(f.ids==6 and f.hooks[Stands.paths.find])
end)
test('detail is bounded while summary counts keep selected and empty results',function()
    local f=fixture();f.watch:tick()
    for i=1,1000 do f.call('find',f.action,f.stand,param(i%2==0 and f.stand or nil)) end
    assert(#f.logs<40,'success and failure have separate bounded logs')
    f.now=15;f.watch:tick();assert(f.all():find('selected=500 empty=500',1,true))
    for i=1,1000 do f.now=f.now+15;f.watch:tick() end
    assert(#f.logs<=240,'a long fight has a global log budget')
end)
test('a companion\'s stands are watched like an arena unit\'s',function()
    local f=fixture()
    f.members={{actor=f.owner,team='companion'},{actor=f.stand,team='companion',stand=true,summoner=f.owner}}
    f.watch:tick()
    assert(next(f.hooks)~=nil,'hooked for a companion')
end)
test('no stands and unload remove hooks; saved callbacks become inert',function()
    local f=fixture();f.watch:tick();f.members={};f.watch:tick();assert(next(f.hooks)==nil)
    f.members={{actor=f.stand,team='blue',stand=true,summoner=f.owner}};f.now=6;f.watch:tick()
    local saved=f.hooks[Stands.paths.find];assert(saved)
    f.watch:silence();assert(next(f.hooks)==nil)
    local before=#f.logs;assert(saved(f.action,f.stand,param(f.stand))==nil);f.watch:tick();assert(#f.logs==before)
end)
print('arena_stands: '..passed..' tests passed')
