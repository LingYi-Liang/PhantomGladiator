package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Y=require('companion_yubi')
local Aim=require('player_aim')
local id=0
local function obj(label,outer)
    id=id+1;local k=id
    local cls={IsValid=function()return true end,GetFName=function()return {ToString=function()return label end}end}
    return {IsValid=function(a)return not a.dead end,GetAddress=function()return k end,GetOuter=function()return outer end,
        GetFullName=function()return label..' /Game/Test.a'..k end,GetClass=function()return cls end}
end
FName=function(s)return s end
local function fixture()
    local h={hooks={},calls=0,lines={},now=0,opponents={}}
    local w=obj('World');local player=obj('Player',w);local control=obj('PlayerController',w)
    local source=obj('BP_Monster_YuBi_C',w);local target=obj('MapBoss',w);local ability=obj('GA_YuBi_CA_02_C',w)
    local cls=source:GetClass();cls.GetFullName=function()return 'BlueprintGeneratedClass '..Y.actor end
    for _,a in ipairs({source,player,target})do a.AbilitySystemComponent=obj('ASC',a)end
    local native=obj('npcClass');native.GetFullName=function()return 'Class /Script/ProjectPBZ.PBZCharacter_NPC' end
    cls.GetSuperStruct=function()return native end
    local component=obj('MotionWarpingComponent',source);component.GetOwner=function()return source end
    function component:AddOrUpdateWarpTargetFromLocation(n,p)
        assert(n=='SnapPoint');h.calls=h.calls+1
        if not h.refuse then self.WarpTargets={{Name=n,Location=p}} end
    end
    function component:RemoveWarpTarget(n)assert(n=='SnapPoint');self.WarpTargets={}end
    component.WarpTargets={};source.GetComponentByClass=function()return component end
    source.at={X=100,Y=200,Z=240};target.at={X=500,Y=400,Z=220}
    ability.GetAvatarActorFromActorInfo=function()return h.caster or source end
    local invalid={IsValid=function()return false end}
    local function reg(p,cb)h.hooks[p]=cb;return 1,2 end
    StaticFindObject=function(p)return obj(p)end
    RegisterHook=reg;UnregisterHook=function(p)h.hooks[p]=nil end
    h.enemy=target;h.roster={{actor=source,team='companion',class_path=Y.actor}}
    local lib=obj('GameplayStatics')
    function lib:GetPlayerCharacter(ctx,index)
        local cb=h.hooks[Aim.paths.character]
        return (not h.badChar and cb and cb(nil,ctx,index)) or player
    end
    function lib:GetPlayerController(ctx,index)
        local cb=h.hooks[Y.controller]
        return (not h.badCtrl and cb and cb(nil,ctx,index)) or control
    end
    local function current(a)local t=a==source and h.enemy or h.opponents[a];if t and not t.dead then return t end end
    h.y=Y.new({current=current,arenaOpponent=function(a)return h.arena:aggroOpponent(a)end,
        player=function()return player end,world=function()return w end,statics=function()return lib end,
        fname=FName,invalid=function()return invalid end,find=StaticFindObject,register=reg,unregister=UnregisterHook,
        clock=function()return h.now end,location=function(a)return a.at end,ground=function(_,_,_,_,_,ignored)
            local enemy=h.arena and h.arena:aggroOpponent(ignored[1]) or current(ignored[1])
            assert(ignored[1] and ignored[2]==enemy);return h.floor end,
        log=function(s)h.lines[#h.lines+1]=s end})
    h.floor=140
    h.aim=Aim.new({log=function()end,clock=function()return h.now end,members=function()return h.roster end,
        fighting=function()
            local s=h.arena and h.arena:status()
            return s and s.battle_active and s.blue_count>0 and s.red_count>0 or false
        end,companionTargetOf=current,
        actorOf=function(key)if h.arena then return h.arena:actorOf(key) end;return source end,
        opponentOf=function(key)return h.arena and h.arena:opponentOf(key)end,
        statics=function()return lib end,player=function()return player end,
        boundaryCharacter=function(...)return h.y:character(...)end})
    function h:tick() self.aim:tick();self.y:tick(self.roster)end
    function h:wall(owner)
        local a=obj('BP_YuBi_CA02_Arena_C',w);a.GetOwner=function()return owner end
        a.StormFeedbackActive=false
        function a:StartStormAudio()self.StormSoundPlayingID=5 end
        function a:RetireArena()self.bRetiring=true end
        return a
    end
    function h:activate(wall)
        wall.SourceBoss=wall:GetOwner();wall.BossASC=wall.SourceBoss.AbilitySystemComponent
        wall.PlayerCharacter=lib:GetPlayerCharacter(wall,0);wall.PlayerASC=lib:GetPlayerCharacter(wall,0).AbilitySystemComponent
        wall.StormFeedbackController=lib:GetPlayerController(wall,0)
        self.hooks[Y.activate](wall)
    end
    function h:second()
        local a=obj('BP_Monster_YuBi_C',w);a.GetClass=source.GetClass;a.at={X=900,Y=400,Z=230};a.AbilitySystemComponent=obj('ASC',a)
        local b=obj('OtherBoss',w);b.at={X=1100,Y=400,Z=230};b.AbilitySystemComponent=obj('ASC',b)
        self.opponents[a]=b
        local c=obj('MotionWarpingComponent',a);c.GetOwner=function()return a end;c.WarpTargets={}
        c.AddOrUpdateWarpTargetFromLocation=component.AddOrUpdateWarpTargetFromLocation;c.RemoveWarpTarget=component.RemoveWarpTarget
        a.GetComponentByClass=function()return c end
        local skill=obj('GA_YuBi_CA_02_C',w);skill.GetAvatarActorFromActorInfo=function()return a end
        self.roster[#self.roster+1]={actor=a,team='companion',class_path=Y.actor}
        return a,b,c,skill
    end
    function h:prepare()self.hooks[Y.prepare](ability)end
    h.source,h.target,h.player,h.control,h.lib,h.comp,h.ability,h.invalid=source,target,player,control,lib,component,ability,invalid
    return h
end
local h=fixture();h:tick();h:prepare();assert(h.calls==1 and #h.comp.WarpTargets==1,'missing level marker gets a private cast warp')
local p=h.comp.WarpTargets[1].Location;assert(p.X==300 and p.Y==300 and p.Z==140)
local wall=h:wall(h.source);h:activate(wall)
assert(wall.PlayerCharacter==h.target and wall.PlayerASC==h.target.AbilitySystemComponent and wall.StormFeedbackController==h.invalid)
assert(wall.StormSoundPlayingID==5 and not wall.bRetiring)
assert(h.lib:GetPlayerController(h.source,0)==h.control)
local mapWall=h:wall(obj('story boss'));assert(h.lib:GetPlayerCharacter(mapWall,0)==h.player and h.lib:GetPlayerController(mapWall,0)==h.control)
h.hooks[Y.finish](h.ability);assert(#h.comp.WarpTargets==0 and not wall.bRetiring)
h.enemy=nil;assert(h.lib:GetPlayerCharacter(wall,0)==h.invalid);h:tick();assert(wall.bRetiring)
for _,case in ipairs({'player','noEnemy','wrongCaster','missingFloor','failedPlayerHook','failedControllerHook','existing','distant','unconfirmed'})do
    h=fixture();h:tick()
    if case=='player' then h.enemy=h.player elseif case=='noEnemy' then h.enemy=nil
    elseif case=='wrongCaster' then h.caster=obj('unowned') elseif case=='missingFloor' then h.floor=nil
    elseif case=='failedPlayerHook' then h.badChar=true elseif case=='failedControllerHook' then h.badCtrl=true
    elseif case=='existing' then h.comp.WarpTargets={{Name='SnapPoint',Location=h.source.at}}
    elseif case=='distant' then h.target.at.X=9000 else h.refuse=true end
    h:prepare();assert(h.calls==(case=='unconfirmed' and 1 or 0),case)
    if case=='existing' then h.hooks[Y.finish](h.ability);assert(#h.comp.WarpTargets==1,'existing native warp remains native-owned')end
end
h=fixture();h:tick();h:prepare();wall=h:wall(h.source);assert(h.lib:GetPlayerCharacter(wall,0)==h.target)
h.roster={};h:tick();assert(wall.bRetiring and #h.comp.WarpTargets==0)
h=fixture();local a2,b2,c2,ability2=h:second();h:tick();h:prepare();h.hooks[Y.prepare](ability2)
local w1,w2=h:wall(h.source),h:wall(a2);h:activate(w1);h:activate(w2)
assert(w1.PlayerASC==h.target.AbilitySystemComponent and w2.PlayerASC==b2.AbilitySystemComponent)
assert(h.comp.WarpTargets[1].Location.X==300 and c2.WarpTargets[1].Location.X==1000)
w1.PlayerCharacter=h.player;h:tick();assert(w1.bRetiring and not w1.PlayerCharacter and not w1.PlayerASC and not w2.bRetiring,'foreign participant readback retires only its own wall')
h.y:silence(true);assert(w2.bRetiring and #c2.WarpTargets==0)
print('PASS companion YuBi native CA02, private warp, participant/controller routing, ownership and cleanup')

-- Use the real arena's confirmed opponent assignments, even when both casters have a different companion target.
do
    local saved=arg;arg={nil,'fixture'}
    local makeArena=assert(loadfile('tools/test_arena_controller.lua'))();arg=saved
    local f=fixture();local blue,spare,blueComp,blueAbility=f:second()
    local red=f.source
    local companion,companionFoe,_,companionAbility=f:second()
    local initial={red,blue,spare,companion}
    for _,a in ipairs(initial)do a.alive=true;a.name=a:GetFullName();a.hp=100 end
    f.arena=makeArena({spawnClass=function()return table.remove(initial,1)end,
        actorKey=function(a)return a:GetAddress()end,activate=function()return true end,
        onUnitsChanged=function(units)f.roster=units;f.y:roster(units)end,
        destroy=function(a)f.y:releaseActor(a);a.alive=false;a.dead=true end,
        forceAttack=function(a,b)a.assigned=b;return true end}).arena
    assert(f.arena:spawn(Y.actor,'red',1).ok and f.arena:spawn(Y.actor,'blue',1).ok)
    f:tick()
    assert(f.hooks[Y.prepare],'red and blue Yu Bi were omitted from the barrier roster')
    f:prepare();assert(f.calls==0,'no field before battle / no companion target fallback')
    assert(f.arena:start().ok);f:tick()
    assert(f.arena:aggroOpponent(red)==blue and f.arena:aggroOpponent(blue)==red)
    f:prepare();f.hooks[Y.prepare](blueAbility)
    assert(f.calls==2 and #f.comp.WarpTargets==1 and #blueComp.WarpTargets==1)
    local rw,bw=f:wall(red),f:wall(blue);f:activate(rw);f:activate(bw)
    assert(rw.PlayerCharacter==blue and rw.PlayerASC==blue.AbilitySystemComponent)
    assert(bw.PlayerCharacter==red and bw.PlayerASC==red.AbilitySystemComponent)
    assert(rw.StormFeedbackController==f.invalid and bw.StormFeedbackController==f.invalid)
    f.hooks[Y.finish](f.ability);f.hooks[Y.finish](blueAbility)
    assert(f.arena:spawn('/Game/OtherBoss.OtherBoss_C','blue',1).ok)
    f.arena:tickReinforcements();blue.hp=0
    assert(f.lib:GetPlayerCharacter(rw,0)==f.invalid)
    f.arena:tickReinforcements();f:tick();assert(rw.bRetiring and bw.bRetiring)
    assert(f.arena:aggroOpponent(red)==spare)
    f:prepare();local nextWall=f:wall(red);f:activate(nextWall)
    assert(nextWall.PlayerCharacter==spare and not nextWall.bRetiring)
    assert(f.lib:GetPlayerCharacter(rw,0)==f.invalid,'a dissolving old wall cannot claim the next opponent')
    assert(f.arena:spawn(Y.actor,'companion',1).ok);f:tick();f.hooks[Y.prepare](companionAbility)
    local companionWall=f:wall(companion);f:activate(companionWall)
    assert(f.arena:stop().ok and nextWall.bRetiring)
    f:tick();assert(f.lib:GetPlayerCharacter(companionWall,0)==companionFoe and not companionWall.bRetiring)
    print('PASS red and blue native CA02 with actual arena start, mutual casting, reinforcement, death, reassignment and cleanup')
end
for _,case in ipairs({'neutral','reserve','stand','aid','variant'})do
    local f=fixture();local member=f.roster[1];member.team='red'
    if case=='neutral' then member.team='neutral' elseif case=='variant' then member.class_path='/Game/Other.Other_C'
    else member[case]=true end
    f.y:roster(f.roster);assert(f.hooks[Y.prepare]==nil,case)
end
