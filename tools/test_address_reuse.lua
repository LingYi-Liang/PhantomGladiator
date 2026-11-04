package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Ground=require('on_ground')
local Aim=require('player_aim')
local passed,failed=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1;print('ok - '..name)
    else failed=failed+1;print('FAIL - '..name..': '..tostring(err))end
end
local serial=0
local function object(cls,fields)
    serial=serial+1
    local identity=serial
    local o=fields or {};o.key=serial;o.live=true
    o.IsValid=function(self)return self.live end;o.GetAddress=function(self)return self.key end
    o.GetFName=function()return {ToString=function()return cls..'_'..identity end}end
    o.GetClass=function()return {IsValid=function()return true end,GetFName=function()return {ToString=function()return cls end}end}end
    return o
end
test('recycled actor addresses get fall protection, and repeated reads do not write or exhaust logs',function()
    local logs,writes={},0
    local g=Ground.new({log=function(s)logs[#logs+1]=s end,label=function()return 'unit'end})
    for _=1,100 do
        local depth=2000
        local o=object('NPC');o.key=42
        setmetatable(o,{__index=function(_,key)if key=='DeadDepth'then return depth end end,
            __newindex=function(t,key,v)if key=='DeadDepth'then writes=writes+1;depth=v else rawset(t,key,v)end end})
        g:keepFromFallDeath(o);g:keepFromFallDeath(o)
        assert(depth==1e9,'new actor inherited old guarded flag')
        o.live=false
    end
    assert(writes==100,'already protected actors must only be read')
    assert(#logs==6,'depth log cap must survive address reuse')
end)
test('fall protection reads again after an unsuccessful write or a later reset',function()
    local g=Ground.new({label=function()return 'unit'end})
    local o=object('NPC',{DeadDepth=2000});g:keepFromFallDeath(o)
    o.DeadDepth=2000;g:keepFromFallDeath(o)
    assert(o.DeadDepth==1e9,'cached success hid the current value')
end)
test('a recycled ability address uses its current avatar, even when its class is unchanged',function()
    local now,hooks=0,{}
    StaticFindObject=function()return object('Function')end
    RegisterHook=function(path,cb)hooks[path]=cb;return 1,2 end
    UnregisterHook=function()end
    local blue,red=object('Blue'),object('Red')
    local members={{actor=blue,team='blue'},{actor=red,team='red'}}
    local aim=Aim.new({members=function()return members end,fighting=function()return true end,clock=function()return now end,
        opponentOf=function(key)return key==tostring(blue.key) and red or blue end})
    aim:tick()
    local old=object('GA_MoTian_Skill_08_C',{GetAvatarActorFromActorInfo=function()return blue end})
    assert(hooks[Aim.paths.character](nil,old)==red)
    local new=object('GA_MoTian_Skill_08_C',{GetAvatarActorFromActorInfo=function()return red end});new.key=old.key;old.live=false
    now=1
    assert(hooks[Aim.paths.character](nil,new)==blue,'new ability inherited old owner after one second')
    new.GetAvatarActorFromActorInfo=function()return blue end
    now=2
    assert(hooks[Aim.paths.character](nil,new)==red,'pooled actions must follow current avatar after one second')
end)
test('a recycled lock ability cannot inherit the five second already-locked result',function()
    StaticFindObject=function()return object('Function')end
    RegisterHook=function()return 1,2 end;UnregisterHook=function()end;FName=function(s)return s end
    local blue,red=object('Blue'),object('Red');blue.RootComponent=object('Root')
    local aim=Aim.new({clock=function()return 0 end,fighting=function()return true end,
        members=function()return {{actor=blue,team='blue'},{actor=red,team='red'}}end,opponentOf=function()return blue end})
    aim:tick()
    local old=object('GA_ZuoShang_CA_02_C',{GetAvatarActorFromActorInfo=function()return red end})
    assert(aim:lockAbilityOf(object('Weapon',{['Source Ability']=old})))
    local new=object('GA_ZuoShang_CA_02_C',{GetAvatarActorFromActorInfo=function()return red end});new.key=old.key;old.live=false
    assert(aim:lockAbilityOf(object('Weapon',{['Source Ability']=new})))
    assert(new['Lock Target'] and new['Lock Target'].Component==blue.RootComponent,'new ability never received its lock')
end)
test('unitOf walks the same context outer chain only once within one second',function()
    local now,hooks,walks=0,{},0
    StaticFindObject=function()return object('Function')end
    RegisterHook=function(path,cb)hooks[path]=cb;return 1,2 end;UnregisterHook=function()end
    local blue,red=object('Blue'),object('Red')
    local members={{actor=blue,team='blue'},{actor=red,team='red'}}
    local owner=blue
    local context=object('BP_Bullet_Eye_C',{GetOuter=function()walks=walks+1;return owner end})
    local aim=Aim.new({clock=function()return now end,fighting=function()return true end,
        members=function()return members end,opponentOf=function(key)return key==tostring(blue.key) and red or blue end})
    aim:tick()
    for i=0,99 do now=i/100;assert(hooks[Aim.paths.pawn](nil,context)==red)end
    assert(walks==1,'same context outer walks='..walks)
    owner=red;now=1;assert(hooks[Aim.paths.pawn](nil,context)==blue)
    assert(walks==2,'cache must expire at one second')
    members[3]={actor=object('New'),team='red'};owner=blue;now=1.1;aim:tick()
    assert(hooks[Aim.paths.pawn](nil,context)==red and walks==3,'new roster must clear the owner cache')
    members[1]=members[3];members[3]=nil;now=1.2;aim:tick()
    assert(hooks[Aim.paths.pawn](nil,context)==nil,'departed owner must not remain cached')
end)
print(string.format('address reuse: %d passed, %d failed',passed,failed))
if failed>0 then os.exit(1)end
