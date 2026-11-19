package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Aim=arg[1] and assert(loadfile(arg[1]))() or require('player_aim')
local address=0
local function object(name,fields)
    address=address+1;local a=address
    local o=fields or {}
    o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function()return a end
    o.GetFullName=o.GetFullName or function()return name..'_'..a end
    local class={GetFName=function()return {ToString=function()return name end}end,IsValid=function()return true end}
    o.GetClass=function()return class end
    o.GetOuter=function(self)return self.outer end
    return o
end
local function harness()
    local h={lines={},hooks={},unhooked={},now=0,fighting=false,members={},ids=0,targets={},paused=false}
    local paths={}
    for _,path in pairs(Aim.paths)do paths[path]=true end
    StaticFindObject=function(path)return paths[path] and object(path) or nil end
    RegisterHook=function(path,pre,post)
        assert(paths[path] and type(pre)=='function' and type(post)=='function')
        h.ids=h.ids+1;h.hooks[path]=pre;return h.ids,100+h.ids
    end
    UnregisterHook=function(path,pre,post)h.unhooked[#h.unhooked+1]={path,pre,post};h.hooks[path]=nil end
    h.player=object('BP_RenewalPlayer_C')
    -- The game calling GetPlayerCharacter/GetPlayerPawn: the pre-hook's return value replaces the player.
    function h.ask(name,context)
        local hook=h.hooks[Aim.paths[name]]
        local answer=hook and hook(object('Default__GameplayStatics'),context,0)
        if answer~=nil then return answer end
        return h.player
    end
    h.statics=object('Default__GameplayStatics',{GetPlayerCharacter=function(_,context,index)return h.ask('character',context)end})
    -- The game asking whether a skill must go for the player: the pre-hook's return value replaces its answer.
    h.gameAnswer=true
    function h.askForce(ability)
        local hook=h.hooks[Aim.paths.force]
        local answer=hook and hook(object('Default__PBZPlayerAbilityTargetLibrary'),ability)
        if answer~=nil then return answer end
        return h.gameAnswer
    end
    h.abilityTargets=object('Default__PBZPlayerAbilityTargetLibrary',{ShouldForcePlayerAbilityTarget=function(_,ability)return h.askForce(ability)end})
    function h.unit(team,reserve)
        local actor=object('BP_Monster_'..team..'_C')
        h.members[#h.members+1]={actor=actor,team=team,reserve=reserve}
        return actor
    end
    function h.new()
        return Aim.new({log=function(s)h.lines[#h.lines+1]=s end,clock=function()return h.now end,
            members=function()return h.members end,fighting=function()return h.fighting end,statics=function()return h.statics end,
            opponentOf=function(key)return h.targets[key] end,abilityTargets=function()return h.abilityTargets end,player=function()return h.player end,
            actorOf=function(key)for _,m in ipairs(h.members)do if tostring(m.actor.GetAddress())==key then return m.actor end end end,
            paused=function()return h.paused end,phaseBusyKey=h.phaseBusyKey,phaseBusy=h.phaseBusy,
            companionTargetOf=function(actor,target,name)
                if h.companionTarget then return h.companionTarget(actor,target,name) end
                return h.targets[tostring(actor:GetAddress())]
            end})
    end
    function h.all()return table.concat(h.lines,'\n')end
    return h
end
local function key(actor)return tostring(actor.GetAddress())end
local function test(name,fn)fn();print('ok - '..name)end
if arg[2]=='fixture'then return harness,object,key end


local only=arg[2]
if not only or only=='scope' then test('ordinary companion attacks redirect to the current enemy without a blue-red fight',function()
    local h=harness();local aim=h.new();local buddy=h.unit('companion');local enemy=object('BP_Monster_MapEnemy_C')
    h.targets[key(buddy)]=enemy;aim:tick()
    local dragon=object('GA_ZuoShang_P2_Skill_23_C',{GetAvatarActorFromActorInfo=function()return buddy end})
    assert(h.ask('character',dragon)==enemy,'dragon pillar must receive the companion enemy, not the player')
    local spell=object('GA_ZuoShang_Skill_19_C',{GetAvatarActorFromActorInfo=function()return buddy end})
    assert(h.askForce(spell)==false,'a companion skill must not force the player target')
    local playerSpell=object('GA_ZuoShang_Skill_19_C',{GetAvatarActorFromActorInfo=function()return h.player end})
    assert(h.askForce(playerSpell)==true,'the player ability must keep the native result')
    local follow=object('GAA_FollowPlayer_C',{GetAvatarActor=function()return buddy end})
    assert(h.ask('pawn',follow)==h.player,'follow and unrelated player queries stay native')
    local another=object('BP_Monster_AnotherEnemy_C');h.targets[key(buddy)]=another
    assert(h.ask('character',dragon)==another,'target is live, not a cached enemy')
end)end
if not only or only=='handoff' then test('a shared action changes avatar to the player without keeping an old NPC owner cache',function()
    local h=harness();local aim=h.new();local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.fighting=true;aim:tick()
    local avatar=blue
    local action=object('GAA_ForceLockTarget_C',{GetAvatarActor=function()return avatar end})
    assert(h.ask('pawn',action)==red)
    avatar=h.player
    assert(h.ask('pawn',action)==h.player,'same-frame shared template reuse must not redirect player skills')
end)end
if not only or only=='effects' then test('companion particle skills arm isolated effects while player and native phase skills stay untouched',function()
    local h=harness();h.phaseBusyKey=function(k)return h.busy==k end
    local aim=h.new();local buddy=h.unit('companion');h.targets[key(buddy)]=object('BP_Enemy_C');aim:tick()
    local armed=0;aim.effects={arm=function()armed=armed+1 end}
    local start=h.hooks[Aim.paths.skillStart]
    for name in pairs(Aim.effectSkills)do
        local avatar=buddy
        local ability=object(name,{GetAvatarActorFromActorInfo=function()return avatar end})
        start(ability);assert(armed>0)
        local before=armed;avatar=h.player;start(ability);assert(armed==before,'same template handed to the player stays native')
        avatar=buddy;h.busy=key(buddy);start(ability);assert(armed==before,'native story pairing keeps its target');h.busy=nil
    end
    assert(armed==7)
end)end
if not only or only=='reuse' then test('an address reused by a different companion class refreshes flying-weapon hooks',function()
    local h=harness();local buddy=h.unit('companion');local aim=h.new();aim:tick()
    assert(h.hooks[Aim.paths.FlyingSwordStart]==nil)
    local replacement=object('BP_Monster_ZuoShang_C');replacement.GetAddress=buddy.GetAddress
    h.members[1].actor=replacement;aim:tick()
    assert(h.hooks[Aim.paths.FlyingSwordStart]~=nil,'a reused address cannot inherit another class capability')
end)end
if not only or only=='rain' then test('silver-haired companion sword rain acquires late particles and keeps simultaneous casts separate',function()
    local h=harness();local first=object('BP_Monster_ZuoShang_Ending_C');local second=object('BP_Monster_ZuoShang_Ending_C')
    h.members={{actor=first,team='companion'},{actor=second,team='companion'}}
    local aim=h.new();aim:tick()
    FName=function(s)return s end
    local loop,scans,list=nil,0,{}
    LoopInGameThreadWithDelay=function(ms,fn)assert(ms==50 and not loop);loop=fn;return 1 end
    CancelDelayedAction=function()loop=nil end
    FindAllOf=function(kind)assert(kind=='PBZ_ParticleBullet');scans=scans+1;return list end
    local function step(n)for _=1,n do h.now=h.now+.05;if loop then loop()end end end
    local function named(s)return object(s,{GetFName=function()return {ToString=function()return s end}end})end
    local rain=named('BD_ZuoShang_Skill_19')
    local asset=named('NS_ZuoShang_SwordShooting_001')
    local function enemy(x)return object('BP_MapBoss_C',{K2_GetActorLocation=function()return {X=x,Y=0,Z=0}end})end
    h.targets[key(first)]=enemy(400);h.targets[key(second)]=enemy(900)
    local reads=0
    h.companionTarget=function(actor,previous,name)
        reads=reads+1
        return h.targets[key(actor)] or (previous and previous:GetFullName()==name and previous)
    end
    local function bullet(owner)
        local b=object('PBZ_ParticleBullet',{BulletOwnerAvatar=owner,BulletData=rain,BulletStatus=2})
        b.ParticleComponent=object('NiagaraComponent',{Asset=asset,GetOwner=function()return b end,
            SetVariableBool=function(c,_,v)c.use=v end,SetVariablePosition=function(c,_,p)c.x=p.X end})
        return b
    end
    local launch=h.hooks[Aim.paths.launch]
    local function fire(owner)launch(object('GAA_DelayDeflectProjectileBullet_C',{['Bullet Data']=rain,GetAvatarActor=function()return owner end}))end
    fire(first);fire(second);step(5);h.targets[key(first)]=nil
    local a,b,playerShot=bullet(first),bullet(second),bullet(h.player)
    list={a,b,playerShot};step(12)
    assert(a.ParticleComponent.use and a.ParticleComponent.x==400,'late companion sword rain kept its native player position')
    assert(b.ParticleComponent.use and b.ParticleComponent.x==900 and playerShot.ParticleComponent.use==nil)
    local done=scans;h.targets[key(first)]=enemy(600);step(6)
    assert(a.ParticleComponent.x==600 and b.ParticleComponent.x==900 and scans==done,'acquired particles should only track their own targets')
    a.BulletStatus=3;b.BulletStatus=3;step(2);assert(not loop)
    local skill=h.hooks[Aim.paths.skillStart];assert(skill)
    local function cast(owner)skill(object('GA_ZuoShang_Skill_19_C',{GetAvatarActorFromActorInfo=function()return owner end}))end
    cast(h.player);assert(not loop)
    cast(second);step(11)
    list={bullet(second),bullet(second),bullet(second),bullet(second),bullet(second),playerShot};step(16)
    for i=1,5 do assert(list[i].ParticleComponent.x==900,'cast start must cover a missing launcher notification')end
    reads=0;step(1);assert(reads==1,'five emitters from one volley share a fresh target read per tick')
    for i=1,5 do list[i].BulletStatus=3 end
    step(3);assert(not loop and playerShot.ParticleComponent.use==nil)
    done=scans;list={};fire(first);step(120);assert(not loop and scans-done<=9,'an absent volley must retire its bounded search')
    LoopInGameThreadWithDelay,CancelDelayedAction,FindAllOf=nil,nil,nil
end)end
print('companion_aim: PASS (ordinary view and actual player isolation)')
