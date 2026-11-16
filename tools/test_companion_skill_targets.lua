package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Aim=arg[1]and assert(loadfile(arg[1]))()or require('player_aim')
local sequence=0
local function object(cls,fields)
    sequence=sequence+1;local id=sequence;local v=fields or{}
    v.IsValid=function(self)return self.live~=false end
    v.GetAddress=function()return id end
    v.GetFullName=function()return cls..'_'..id end
    v.GetClass=function()return {IsValid=function()return true end,GetFName=function()return {ToString=function()return cls end}end}end
    v.GetOuter=function(self)return self.outer end
    return v
end
local function fixture()
    local h={hooks={},members={},targets={},logs={}}
    h.player=object('BP_Renewal_Hun_C');h.actor=object('BP_Monster_QiShu_Bing_C');h.enemy=object('BP_MapEnemy_C')
    h.world=object('World');h.actor.outer=h.world;h.enemy.outer=h.world;h.player.outer=h.world
    local key=tostring(h.actor:GetAddress());h.members={{actor=h.actor,team='companion'}};h.targets[key]=h.enemy;h.key=key
    StaticFindObject=function()return object('Function')end
    RegisterHook=function(path,callback)h.hooks[path]=callback;return 1,2 end
    UnregisterHook=function(path)h.hooks[path]=nil end
    h.aim=Aim.new({members=function()return h.members end,fighting=function()return false end,player=function()return h.player end,
        clock=function()return 0 end,log=function(text)h.logs[#h.logs+1]=text end,
        actorOf=function(k)return k==key and h.actor or nil end,opponentOf=function()return nil end,
        phaseBusyKey=function()return h.busy end,companionTargetOf=function()return not h.noTarget and h.enemy or nil end,
        paused=function()return h.paused end,world=function()return h.world end})
    h.aim:tick()
    function h:get(actor)
        local fn=self.hooks[Aim.paths.character];return fn and fn(nil,actor,0)or self.player
    end
    return h
end
local function remote(value)
    return {type=function()return 'RemoteUnrealParam'end,get=function()return value end,set=function(_,v)value=v end}
end
local passed=0;local only=arg[2]
local function test(label,fn)fn();passed=passed+1;print('PASS '..label)end
if not only or only=='arena'then test('owned YuBi arena caches the enemy actor and ASC instead of the player',function()
    local h=fixture();local arena=object('BP_YuBi_CA02_Arena_C',{Owner=h.actor})
    local actor=h:get(arena);assert(actor==h.enemy,'arena CacheParticipants must receive the companion enemy')
    local asc={[h.player]='playerASC',[h.enemy]='enemyASC'}
    assert(asc[h:get(arena)]=='enemyASC','boundary damage must use the same enemy ASC')
    arena.Owner=h.player;assert(h:get(arena)==h.player,'a player-owned arena retains the original player')
end)end
if not only or only=='wire'then test('sticky wire skeletal-mesh targeting follows its live caster opponent',function()
    local h=fixture();local wire=object('BP_Bullet_LengTu_StickyWire_C',{BulletOwnerAvatar=h.actor})
    assert(h:get(wire)==h.enemy,'sticky wire UE_SK02 must bind the enemy mesh')
    h.enemy=object('BP_AnotherMapEnemy_C');assert(h:get(wire)==h.enemy)
    wire.BulletOwnerAvatar=h.player;assert(h:get(wire)==h.player,'pooled player bullets cannot inherit the companion target')
end)end
if not only or only=='ice'then test('only an owned caster can give its deferred ice pillar a source owner',function()
    local h=fixture();local source=h.actor
    local ability=object('GA_Qishu_Bing_Test_C',{GetAvatarActorFromActorInfo=function()return source end})
    local spawner=object('BP_QiShu_Bing_IcicleSpawner_C',{['Source Ability']=ability,outer=h.world})
    local owner=remote(nil);local cls=object('BP_QiShu_Bing_Icicle_C')
    cls.GetFName=function()return {ToString=function()return 'BP_QiShu_Bing_Icicle_C'end}end
    local fn=Aim.paths.iceSpawn and h.hooks[Aim.paths.iceSpawn]
    if fn then fn(nil,spawner,cls,nil,nil,owner)end
    assert(owner:get()==h.actor,'deferred native spawn must retain the confirmed mod caster')
    local pillar=object('BP_QiShu_Bing_Icicle_C',{Owner=owner:get()})
    assert(h:get(pillar)==h.enemy,'frost comparison and application must receive the enemy')
    source=h.player;owner:set(nil);fn(nil,spawner,cls,nil,nil,owner);assert(owner:get()==nil,'player spells keep native ownership')
end)end
if not only or only=='subga'then test('shared SubGA abilities resolve their live avatar before forced-player targeting',function()
    local h=fixture();local avatar=h.actor
    local ability=object('SubGA_Qishu_Huo_Skill05_AirMoving_L_C',{GetAvatarActorFromActorInfo=function()return avatar end,outer=object('SharedClass')})
    local function forced()
        local answer=h.hooks[Aim.paths.force](nil,ability)
        if answer~=nil then return answer end
        return true
    end
    assert(forced()==false,'a SubGA companion spell must reach the forced-player guard')
    avatar=h.player;assert(forced()==true,'a shared SubGA handed to the real player stays native')
end)end
if not only or only=='horse_warning'then test('the catalog horse-cart HookMan warning follows the enemy instead of the player',function()
    local h=fixture()
    local native=object('Native');native.GetFullName=function()return 'Class /Script/ProjectPBZ.PBZCharacter_NPC'end
    local cls=object('Class');cls.GetFullName=function()return 'BlueprintGeneratedClass /Test/Enemy.Enemy_C'end
    cls.GetSuperStruct=function()return native end;h.enemy.GetClass=function()return cls end
    local skill=object('GA_HookMan_HorseCart_Skill_06_C')
    local avatar=h.actor
    local warning=object('GAAction_ParticleOnPlayer_C',{GetAbility=function()return skill end,GetAvatarActor=function()return avatar end})
    local function target()
        local answer=h.hooks[Aim.paths.pawn](nil,warning,0)
        if answer~=nil then return answer end
        return h.player
    end
    assert(target()==h.enemy,'the second offensive ParticleOnPlayer user must not be excluded')
    avatar=h.player;assert(target()==h.player,'player warning actions remain native')
end)end
if not only then
test('native map pillars and existing owners are never reassigned',function()
    local h=fixture();local ability=object('GA_Test_C',{GetAvatarActorFromActorInfo=function()return h.actor end})
    local ctx=object('BP_QiShu_Bing_IcicleSpawner_C',{['Source Ability']=ability,outer=h.world})
    local cls=object('Class');cls.GetFName=function()return {ToString=function()return 'BP_QiShu_Bing_Icicle_C'end}end
    local fn=h.hooks[Aim.paths.iceSpawn];local owner=remote(h.player)
    fn(nil,ctx,cls,nil,nil,owner);assert(owner:get()==h.player)
    owner:set(nil);ctx['Source Ability']=nil;fn(nil,ctx,cls,nil,nil,owner);assert(owner:get()==nil)
    ctx['Source Ability']=ability;h.busy=true;fn(nil,ctx,cls,nil,nil,owner);assert(owner:get()==nil)
    h.busy=false;h.noTarget=true;fn(nil,ctx,cls,nil,nil,owner);assert(owner:get()==nil)
    assert(h:get(object('BP_QiShu_Bing_Icicle_C'))==h.player,'unowned map ice stays native')
end)
test('ice ownership stops for foreign worlds, failed writes and a retired roster',function()
    local h=fixture();local ability=object('GA_Test_C',{GetAvatarActorFromActorInfo=function()return h.actor end})
    local ctx=object('BP_QiShu_Bing_IcicleSpawner_C',{['Source Ability']=ability,outer=object('OtherWorld')})
    local cls=object('Class');cls.GetFName=function()return {ToString=function()return 'BP_QiShu_Bing_Icicle_C'end}end
    local owner=remote(nil);local fn=h.hooks[Aim.paths.iceSpawn]
    fn(nil,ctx,cls,nil,nil,owner);assert(owner:get()==nil)
    ctx.outer=h.world;owner.set=function()error('native write unavailable')end
    fn(nil,ctx,cls,nil,nil,owner);assert(owner:get()==nil)
    owner=remote(nil);h.members={};h.aim:tick();fn(nil,ctx,cls,nil,nil,owner);assert(owner:get()==nil)
end)
test('ice spawn discovery stays absent until a relevant caster arrives',function()
    local h=fixture();local other=object('BP_Monster_Other_C',{outer=h.world})
    h.members={{actor=other,team='companion'}};h.aim:silence();h.hooks={}
    -- A fresh controller with an ordinary companion never asks for the global spawn function.
    local queries=0;StaticFindObject=function(path)if path==Aim.paths.iceSpawn then queries=queries+1 end;return object('Function')end
    h.aim=Aim.new({members=function()return h.members end,fighting=function()return false end,
        companionTargetOf=function()return h.enemy end,actorOf=function()return other end,player=function()return h.player end})
    for _=1,40 do h.aim:tick()end
    assert(queries==0,'ordinary companions do not discover the native actor-spawn hook')
    h.members={{actor=h.actor,team='companion'}};h.aim:tick();assert(queries==1)
end)
test('cinematic and player-interaction queries retain the player',function()
    local h=fixture()
    for _,cls in ipairs({'GAA_EffectOnGroundTrace_C','GA_ZuoShang_Skill_04_A_C','GA_HookMan_CriticalArt_01_C','GA_QinNv_Passive_C'})do
        assert(h:get(object(cls,{GetAvatarActor=function()return h.actor end,GetAvatarActorFromActorInfo=function()return h.actor end}))==h.player)
    end
end)
end
print('companion skill target audit: PASS '..passed..' isolation checks; no game accessed')
