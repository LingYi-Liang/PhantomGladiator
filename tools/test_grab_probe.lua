package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
FName=setmetatable({},{__call=function(_,s)return s end})
local Probe=require('grab_probe')
local serial=0
local function object(name,fields)
    serial=serial+1;local address=serial
    local o=fields or {};o.live=true
    o.IsValid=function(self)return self.live end
    o.GetAddress=function()return address end
    o.GetFName=function()return {ToString=function()return name end}end
    return o
end
local function unit(class,tags,montage,position)
    local actor=object(class)
    actor.GetClass=function()return {IsValid=function()return true end,GetFName=function()return {ToString=function()return class end}end}end
    actor.AbilitySystemComponent=object('ASC',{GetGameplayTagCount=function(_,tag)return tags[tag.TagName] or 0 end})
    local current=montage and object(montage) or nil
    actor.Mesh=object('Mesh',{GetAnimInstance=function()return object('Anim',{
        GetCurrentActiveMontage=function()return current end,
        Montage_GetPosition=function()return position end})end})
    return actor
end
local function harness(loaded)
    local h={now=0,members={},lines={},hooks={},finds=0,removed=0,at={}}
    StaticFindObject=function(path)
        h.finds=h.finds+1
        assert(path==Probe.path)
        return loaded and object('Trigger') or nil
    end
    RegisterHook=function(path,callback,post)
        assert(path==Probe.path and type(post)=='function')
        h.callback=callback
        return 7,8
    end
    UnregisterHook=function(path,pre,post)
        assert(path==Probe.path and pre==7 and post==8)
        h.callback=nil;h.removed=h.removed+1
    end
    h.mod=Probe.new({log=function(s)h.lines[#h.lines+1]=s end,clock=function()return h.now end,
        members=function()return h.members end,location=function(a)return h.at[a] end,
        isPlayer=function(a)return a==h.player end})
    function h.all()return table.concat(h.lines,'\n')end
    return h
end
local function param(value)return {type=function()return 'RemoteUnrealParam' end,get=function()return value end} end

-- No units: no hook. With units: hooked once. A grab logs both sides at once, then 0.4 s and 1.5 s after, and no more.
do
    local h=harness(true)
    h.mod:tick()
    assert(h.finds==0 and not h.callback,'no units, no lookup')
    h.members={{actor=object('Unit'),team='blue'}}
    h.mod:tick();h.mod:tick()
    assert(h.callback and h.finds==1)
    assert(h.all():find('挂钩注册ID读回 pre=7 post=8',1,true),h.all())
    local grabber=unit('BP_Monster_XiaoXue_C',{},'XiaoXue_CriticalArt_01_XiaoXue_Montage',0.5)
    local target=unit('BP_Monster_MobMan_Elite_Sword_C',{['Ability.Executed']=1},'XiaoXue_CriticalArt_01_Hun_Montage',1.25)
    h.at[grabber],h.at[target]={X=0,Y=0,Z=0},{X=120,Y=0,Z=0}
    local event=object('BP_BulletEvent_Grab_C_0',{['Success Timeline']={ToString=function()return 'GrabSuccess' end}})
    local bullet=object('Bullet',{GetOwnerAvatar=function()return grabber end})
    assert(h.callback(param(event),param(bullet),param({EventActor=target}))==nil,'changes nothing')
    assert(h.mod.grabs==1)
    assert(h.all():find('第 1 次 事件=BP_BulletEvent_Grab_C_0 跳到时间轴=GrabSuccess',1,true),h.all())
    assert(h.all():find('命中后 目标=BP_Monster_MobMan_Elite_Sword_C 被抓标签=1 Executing=0 Dead=0 蒙太奇=XiaoXue_CriticalArt_01_Hun_Montage@1.25s 施法方=BP_Monster_XiaoXue_C 蒙太奇=XiaoXue_CriticalArt_01_XiaoXue_Montage@0.50s 距离=1.2m',1,true),h.all())
    h.now=0.2;h.mod:tick()
    local _,count=h.all():gsub('目标=BP_Monster_MobMan_Elite_Sword_C','')
    assert(count==1,'not yet')
    h.now=0.5;h.mod:tick()
    assert(h.all():find('+0.5s 目标=',1,true),h.all())
    h.now=1.6;h.mod:tick()
    assert(h.all():find('+1.6s 目标=',1,true),h.all())
    h.now=5;h.mod:tick();h.now=9;h.mod:tick()
    _,count=h.all():gsub('目标=BP_Monster_MobMan_Elite_Sword_C','')
    assert(count==3,'once and twice more')
end
-- The player being grabbed is the game's own business. A target that cannot be read is said, not guessed.
do
    local h=harness(true)
    h.members={{actor=object('Unit'),team='blue'}}
    h.mod:tick()
    h.player=unit('BP_Player_C',{})
    local event=object('Event')
    h.callback(event,object('Bullet'),{EventActor=h.player})
    assert(h.mod.grabs==0 and not h.all():find('第 1 次',1,true))
    h.callback(event,object('Bullet'),{})
    assert(h.all():find('命中事件读不到目标 事件=Event',1,true),h.all())
end
-- A target gone before the check, no mesh, no grabber: logged as far as it reads.
do
    local h=harness(true)
    h.members={{actor=object('Unit'),team='blue'}}
    h.mod:tick()
    local target=unit('BP_Monster_AHua_C',{})
    target.Mesh=nil
    h.callback(object('Event'),object('Bullet'),{EventActor=target})
    assert(h.all():find('蒙太奇=无网格 施法方=无效 蒙太奇=无网格 距离=?',1,true),h.all())
    target.live=false
    h.now=1;h.mod:tick()
    assert(h.all():find('目标=无效 被抓标签=? Executing=? Dead=? 蒙太奇=无网格',1,true),h.all())
end
-- The class not loaded yet: asked again with growing gaps, not every tick. The hook goes when the units do, and at unload.
do
    local h=harness(false)
    h.members={{actor=object('Unit'),team='blue'}}
    h.mod:tick();h.mod:tick();h.mod:tick()
    assert(h.finds==1 and not h.callback)
    h.now=1.1;h.mod:tick()
    assert(h.finds==2)
    local loaded=harness(true)
    loaded.members={{actor=object('Unit'),team='blue'}}
    loaded.mod:tick()
    loaded.members={}
    loaded.mod:tick()
    assert(loaded.removed==1 and loaded.all():find('摘除挂钩（场上没有单位） 累计抓取=0',1,true),loaded.all())
    loaded.members={{actor=object('Unit'),team='blue'}}
    loaded.mod:tick()
    assert(loaded.callback)
    loaded.mod:silence()
    assert(loaded.removed==2 and loaded.mod.alive==false)
    loaded.mod:tick()
    assert(not loaded.callback,'stays off')
end
print('grab_probe: PASS')
