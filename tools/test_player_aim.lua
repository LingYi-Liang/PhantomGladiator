package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Aim=arg[1] and assert(loadfile(arg[1]))() or require('player_aim')
local Flash=require('attack_flash')
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
    local h={lines={},hooks={},posts={},unhooked={},now=0,fighting=false,members={},ids=0,targets={},paused=false}
    local paths={}
    for _,path in pairs(Aim.paths)do paths[path]=true end
    StaticFindObject=function(path)return paths[path] and object(path) or nil end
    RegisterHook=function(path,pre,post)
        assert(paths[path] and type(pre)=='function' and type(post)=='function')
        h.ids=h.ids+1;h.hooks[path]=pre;h.posts[path]=post;return h.ids,100+h.ids
    end
    UnregisterHook=function(path,pre,post)h.unhooked[#h.unhooked+1]={path,pre,post};h.hooks[path]=nil end
    h.player=object('BP_RenewalPlayer_C')
    -- The game calling GetPlayerCharacter/GetPlayerPawn: the pre-hook's return value replaces the player.
    function h.ask(name,context,index)
        local hook=h.hooks[Aim.paths[name]]
        local answer=hook and hook(object('Default__GameplayStatics'),context,index or 0)
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
            world=h.world and function()return h.world end,
            members=function()return h.members end,fighting=function()return h.fighting end,statics=function()return h.statics end,
            opponentOf=function(key)return h.targets[key] end,companionTargetOf=h.mapEnemy and function()return h.mapEnemy end,
            phaseAimOpponent=h.phaseAimOpponent,
            hp=h.hp,inGameThread=function()return true end,attackFlash=h.attackFlash,readRelation=h.readRelation,
            formationPlayerLookup=h.formationPlayerLookup,formationCast=h.formationCast,
            abilityTargets=function()return h.abilityTargets end,player=function()return h.player end,
            actorOf=function(key)for _,m in ipairs(h.members)do if tostring(m.actor.GetAddress())==key then return m.actor end end end,
            paused=function()return h.paused end,phaseBusyKey=h.phaseBusyKey,phaseBusy=h.phaseBusy})
    end
    function h.all()return table.concat(h.lines,'\n')end
    return h
end
local function key(actor)return tostring(actor.GetAddress())end
local function test(name,fn)fn();print('ok - '..name)end

test('HuaShan support camera and input are scoped to the original lookup and registered ability',function()
    local h=harness();h.unit('red');h.unit('blue');h.fighting=true
    local heal=object('GA_HuaShan_Troop_Healing_C');local mapHeal=object('GA_HuaShan_Troop_Healing_C')
    local counter=object('GA_HuaShan_RedTroop_BigBro_Skill_08_01_C')
    local empty={IsValid=function()return false end};local casts=0
    h.formationPlayerLookup=function(a)if a==heal or a==counter then return empty end end
    h.formationCast=function(a,name)assert(a==heal and name=='GA_HuaShan_Troop_Healing_C');casts=casts+1 end
    local aim=h.new();aim:tick()
    assert(h.ask('character',heal)==empty and h.ask('pawn',heal)==h.player)
    assert(h.ask('character',mapHeal)==h.player and h.ask('pawn',counter)==empty)
    h.hooks[Aim.paths.skillStart](heal);assert(casts==1)
end)

test('only the C4 warning action of a fighting unit gets an NPC instead of the player',function()
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.fighting=true;aim:tick()
    local base=object('NPCBase',{GetFullName=function()return 'Class /Script/ProjectPBZ.PBZCharacter_NPC'end})
    red.GetClass=function()
        return object('Class',{GetFullName=function()return 'BlueprintGeneratedClass /Test/NPC.NPC_C'end,
            GetSuperStruct=function()return base end})
    end
    local avatar=blue
    local skill=object('GA_MBoss_Skill_02_C4_C')
    local warning=object('GAAction_ParticleOnPlayer_C',{GetAbility=function()return skill end,GetAvatarActor=function()return avatar end})
    assert(h.ask('pawn',warning)==red,'the native warning receives the opponent pawn')
    assert(h.ask('character',warning)==h.player,'the warning calls GetPlayerPawn only')
    skill=object('GA_Other_C');assert(h.ask('pawn',warning)==h.player)
    skill=object('GA_MBoss_Skill_02_C4_C');avatar=h.player;assert(h.ask('pawn',warning)==h.player)
    avatar=blue;h.paused=true;assert(h.ask('pawn',warning)==h.player)
end)

test('arena and companion red and blue flashes are independently enabled for the native visual check',function()
    local h=harness()
    local files={}
    local writable=true
    local settings={path='fixture',read=function(path)return files[path]end,
        write=function(path,text)if writable then files[path]=text;return true end return false end}
    h.attackFlash=Flash.new(settings)
    local blue,red=h.unit('blue'),h.unit('red')
    local companion=h.unit('companion')
    local enemy=object('BP_Monster_MapEnemy_C')
    local npc=object('NPCBase',{GetFullName=function()return 'Class /Script/ProjectPBZ.PBZCharacter_NPC'end})
    for _,actor in ipairs({red,enemy}) do
        actor.GetClass=function()
            return object('Class',{GetFullName=function()return 'BlueprintGeneratedClass /Test/NPC.NPC_C'end,
                GetSuperStruct=function()return npc end})
        end
    end
    h.fighting=true;h.targets[key(blue)]=red;h.mapEnemy=enemy
    local towardPlayer=1
    local towardTarget=2
    h.readRelation=function(_,target)return target==h.player and towardPlayer or towardTarget end
    local aim=h.new();aim:tick()
    local avatar=blue
    local function cue(name)
        local path='/PBZVFXPack/VFX/BattleFX/Common/'..name..'.'..name
        local system=object('NiagaraSystem',{GetFullName=function()return 'NiagaraSystem '..path end})
        return object('GAAction_WeaponParticle_BlueRedEye_C',{GetAvatarActor=function()return avatar end,NiagaraEffect=system})
    end
    local redCue,blueCue=cue('NS_AttackAlert_Red_004'),cue('NS_AttackAlert_Blue_002')
    assert(h.ask('pawn',redCue)==h.player and h.ask('pawn',blueCue)==h.player)
    assert(h.attackFlash:set('red','ON').ok and h.ask('pawn',redCue)==red)
    assert(h.ask('pawn',blueCue)==h.player and h.ask('character',redCue)==h.player and h.ask('pawn',redCue,1)==h.player)
    assert(h.ask('pawn',cue('NS_Troop_Howl_001'))==h.player)
    assert(h.attackFlash:set('blue','ON').ok and h.ask('pawn',blueCue)==red)
    assert(h.attackFlash:set('red','OFF').ok and h.ask('pawn',redCue)==h.player)
    assert(Flash.new(settings):status().blue and not Flash.new(settings):status().red)
    writable=false
    assert(not h.attackFlash:set('blue','OFF').ok and h.ask('pawn',blueCue)==red)
    assert(not h.attackFlash:set('neutral','ON').ok and not h.attackFlash:set('blue','bad').ok)
    towardPlayer=2;assert(h.ask('pawn',blueCue)==h.player)
    towardPlayer=0;avatar=companion;assert(h.ask('pawn',blueCue)==enemy)
    towardTarget=0;assert(h.ask('pawn',blueCue)==h.player)
    towardTarget=2;avatar=object('BP_Monster_Unregistered_C');assert(h.ask('pawn',blueCue)==h.player)
    avatar=h.player;assert(h.ask('pawn',blueCue)==h.player)
    avatar=blue;h.fighting=false;aim:tick();assert(h.ask('pawn',blueCue)==h.player)
    avatar=companion;enemy.alive=false;assert(h.ask('pawn',blueCue)==h.player)
end)

test('prepared teams arm only three walk guards, with no repeated native lookup; combat opens regular aim',function()
    local h=harness();local aim=h.new()
    aim:tick()
    assert(next(h.hooks)==nil and aim:status().state=='idle')
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    local originalFind,lookups=StaticFindObject,0
    StaticFindObject=function(path)lookups=lookups+1;return originalFind(path)end
    aim:tick()
    assert(h.ids==3 and lookups==3 and aim:status().state=='idle')
    assert(h.hooks[Aim.paths.character] and h.hooks[Aim.paths.walkInputAdd] and h.hooks[Aim.paths.walkInputRemove])
    assert(not h.hooks[Aim.paths.pawn] and not h.hooks[Aim.paths.bullet])
    for _=1,40 do aim:tick() end
    assert(h.ids==3 and lookups==3,'preparing must not re-register or re-resolve the three guards')
    h.fighting=true;aim:tick();aim:tick()
    assert(h.ids==10 and aim:status().state=='running','no flying-weapon hooks without a ZuoShang caster')
    assert(h.all():find('自检（临时放行该单位的类）：以 BP_Monster_',1,true) and aim:status().redirected==0 and h.all():find('改写生效=true',1,true),h.all())
end)

test('a listed attack of a fighting unit gets its opponent; anything else keeps the player',function()
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    h.fighting=true;aim:tick()
    local ability=object('GA_MoTian_Skill_08_C',{outer=red})
    local action=object('GAA_ForceLockTarget_C',{outer=object('GA_Any_Skill_C',{outer=red})})
    assert(h.ask('character',ability)==blue and h.ask('pawn',action)==blue,'an ability, and the shared force-lock action inside one')
    local eye=object('BP_Bullet_EyeSP1_C',{BulletOwnerAvatar=red})
    local weapon=object('BP_ZuoShang_GroundWeapon_Base_Knife_C',{Owner=blue})
    local parent={GetFName=function()return {ToString=function()return 'BP_ZuoShang_GroundWeapon_Base_C' end}end,IsValid=function()return true end}
    local knifeClass={GetFName=function()return {ToString=function()return 'BP_ZuoShang_GroundWeapon_Base_Knife_C' end}end,
        IsValid=function()return true end,GetSuperStruct=function()return parent end}
    weapon.GetClass=function()return knifeClass end
    assert(h.ask('character',eye)==blue and h.ask('character',weapon)==red,'a bullet by its owner avatar; a subclass of a listed class by its owner')
    assert(h.ask('pawn',red)==h.player,'the unit itself is not a listed attack')
    local template=object('GAA_ForceLockTarget_C',{outer=object('GA_Some_Skill_C_Class'),GetAvatarActor=function()return blue end})
    assert(h.ask('pawn',template)==red,'a shared action template: by its avatar, not its outer')
    local skill=object('GA_XuKong_Skill_04_C',{GetAvatarActorFromActorInfo=function()return red end})
    assert(h.ask('character',skill)==blue,'an ability by its avatar')
    -- Not listed: what already works (summons placed by the player), input checks, the AI framework.
    assert(h.ask('character',object('GA_LengTu_SummonPassive_P1_PengMeng_C',{outer=red}))==h.player)
    assert(h.ask('pawn',object('GA_ZuoShang_Skill_04_A_C',{outer=red}))==h.player)
    assert(h.ask('pawn',object('STTask_SetPlayerTarget_C',{outer=red}))==h.player)
    assert(h.ask('character',object('GA_MoTian_Skill_08_C',{outer=h.player}))==h.player,'a listed class acting for nobody of ours')
    assert(h.all():find('改写 取玩家角色 调用方=GA_MoTian_Skill_08_C → BP_Monster_blue_C',1,true),h.all())
    assert(aim:status().redirected==6)
    assert(Aim.aims['GA_DangHui_SwitchSelf_C'] and not Aim.aims['GA_GuiChai_Red_P2_CA_04_C'] and not Aim.aims['GA_PengMeng_Skill_BEd_Fail_C'])
end)

test('nothing changes while an execution plays',function()
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    h.fighting=true;aim:tick()
    local ability=object('GA_XianZhe_Skill_01_C',{outer=red})
    h.paused=true
    assert(h.ask('character',ability)==h.player)
    h.paused=false
    assert(h.ask('character',ability)==blue)
end)

test('a unit in reserve, a unit without an opponent, and the end of the fight',function()
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    local doll=h.unit('blue',true)
    h.targets[key(red)]=blue
    h.fighting=true;aim:tick()
    assert(h.ask('character',object('GA_A_C',{outer=doll}))==h.player,'a reserve doll is not fighting')
    assert(h.ask('character',object('GA_B_C',{outer=blue}))==h.player,'no opponent: the game\'s answer')
    h.fighting=false;h.now=5;aim:tick()
    assert(h.ask('character',object('GA_C_C',{outer=red}))==h.player,'after the fight the player again at once')
    h.now=9;aim:tick();assert(#h.unhooked==0)
    h.now=16;aim:tick()
    assert(#h.unhooked==7 and aim:status().state=='idle' and h.all():find('摘除挂钩（战斗已结束）',1,true),h.all())
    assert(h.hooks[Aim.paths.character] and h.hooks[Aim.paths.walkInputAdd],'the defeated roster can still use native walk actions')
    h.fighting=true;aim:tick();assert(h.ids==17,'only combat hooks are reinstalled for the next fight')
    aim:silence('test');assert(#h.unhooked==17)
end)

test('a skill of a fighting unit is not forced onto the player; the first call per class logs what the game would say',function()
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    h.fighting=true;aim:tick()
    local skill=object('GA_ChiLian_P2_CA_01_C',{GetAvatarActorFromActorInfo=function()return red end})
    assert(h.askForce(skill)==false,'answered false')
    assert(h.all():find('不强制锁玩家 调用方=GA_ChiLian_P2_CA_01_C 游戏原本=true 挂钩后=false 累计=1',1,true),h.all())
    local count=#h.lines
    assert(h.askForce(skill)==false and #h.lines==count,'told once per class')
    assert(aim:status().redirected==2)
    h.gameAnswer=false
    local other=object('GA_LeiDang_CA_C',{outer=blue})
    assert(h.askForce(other)==false and h.all():find('不强制锁玩家 调用方=GA_LeiDang_CA_C 游戏原本=false 挂钩后=false 累计=3',1,true),h.all())
    -- Not ours, or an execution playing, or an empty argument: the game's own answer.
    h.gameAnswer=true
    assert(h.askForce(object('GA_YuBi_CA_02_C',{outer=h.player}))==true,'a skill of a unit that is not fighting')
    assert(h.askForce(nil)==true)
    h.paused=true
    assert(h.askForce(object('GA_LengTu_CA_03_C',{outer=red}))==true)
    h.paused=false
    h.fighting=false;h.now=1;aim:tick()
    assert(h.askForce(object('GA_LengTu_SA_02_C',{outer=red}))==true,'after the fight the game again at once')
end)
test('万剑归宗: the ability of a weapon locks onto the opponent before any bullet; a weapon without an owner goes by its ability',function()
    FName=function(text)return {name=text} end
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    blue.RootComponent=object('Capsule')
    h.fighting=true;aim:tick()
    local playerRoot=object('PlayerCapsule',{GetOwner=function()return h.player end})
    local ability=object('GA_ZuoShang_CA_02_C',{GetAvatarActorFromActorInfo=function()return red end,
        ['Lock Target']={Component=playerRoot},['Lock Target Selected']=true})
    local weapon=object('BP_ZuoShang_GroundWeapon_Base_C',{['Source Ability']=ability})
    assert(aim:lockAbilityOf(weapon)==true,h.all())
    assert(ability['Lock Target'].Component==blue.RootComponent and ability['Lock Target Selected']==true)
    assert(h.all():find('招式锁定 GA_ZuoShang_CA_02_C：原目标=BP_RenewalPlayer_C -> BP_Monster_blue_C 写入=true 读回=生效',1,true),h.all())
    local count=#h.lines
    assert(aim:lockAbilityOf(object('BP_ZuoShang_GroundWeapon_Base_C',{['Source Ability']=ability}))==true and #h.lines==count,'42 weapons, one change')
    assert(h.ask('character',weapon)==blue,'its turn toward the target too, with no Owner set (weapons the map placed)')
    assert(aim:lockAbilityOf(object('BP_ZuoShang_GroundWeapon_Base_C'))==false,'no ability yet')
    local stranger=object('GA_Other_C',{outer=h.player,['Lock Target']={}})
    assert(aim:lockAbilityOf(object('BP_ZuoShang_GroundWeapon_Base_C',{['Source Ability']=stranger}))==false and stranger['Lock Target'].Component==nil,'not a fighting unit: left alone')
end)
test('any skill whose own lock came out on the player goes to the opponent; a lock on anything else is left',function()
    FName=function(text)return {name=text} end
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    blue.RootComponent=object('Capsule')
    h.fighting=true;aim:tick()
    local playerRoot=object('PlayerCapsule',{GetOwner=function()return h.player end})
    local ability=object('GA_ZuoShang_CA_01_C',{GetAvatarActorFromActorInfo=function()return red end,['Lock Target']={Component=playerRoot}})
    local answered
    local out={set=function(_,value)answered=value end}
    h.hooks[Aim.paths.lock](ability,false,false,out)
    assert(ability['Lock Target'].Component==blue.RootComponent and answered.Component==blue.RootComponent)
    assert(h.all():find('招式的锁定落在玩家，改成对手 招式=GA_ZuoShang_CA_01_C -> BP_Monster_blue_C 写入=true 返回值=true 读回=生效 累计=1',1,true),h.all())
    local onOpponent=object('GA_Other_C',{GetAvatarActorFromActorInfo=function()return red end,['Lock Target']={Component=blue.RootComponent}})
    blue.RootComponent.GetOwner=function()return blue end
    h.hooks[Aim.paths.lock](onOpponent,false,false,out)
    assert(aim:status().redirected==1,'a lock on the opponent stays')
    local notOurs=object('GA_Player_C',{outer=h.player,['Lock Target']={Component=playerRoot}})
    h.hooks[Aim.paths.lock](notOurs,false,false,out)
    assert(notOurs['Lock Target'].Component==playerRoot,'not a fighting unit')
end)

test('a caller outside the list acting for a fighting unit keeps the player and is named once',function()
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    h.fighting=true;aim:tick()
    local other=object('GA_NewSkill_C',{outer=red})
    assert(h.ask('pawn',other)==h.player and h.ask('pawn',other)==h.player)
    assert(h.all():find('没改写的取玩家调用 调用方=GA_NewSkill_C 函数=取玩家Pawn',1,true),h.all())
    local _,n=h.all():gsub('没改写的取玩家调用','')
    assert(n==1)
    assert(h.ask('pawn',object('UI_Widget_C'))==h.player and not h.all():find('UI_Widget_C',1,true),'acts for nobody')
end)
test('a bullet of a fighting unit aimed at the player goes to its opponent; aimed at a fighter it stays; others are left',function()
    FName=function(text)return {name=text} end
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    blue.RootComponent=object('Capsule',{GetOwner=function()return blue end})
    red.RootComponent=object('RedCapsule',{GetOwner=function()return red end})
    h.fighting=true;aim:tick()
    local playerRoot=object('PlayerCapsule',{GetOwner=function()return h.player end})
    local function param(component)
        local value={Component=component}
        return {type=function()return 'RemoteUnrealParam' end,get=function()return value end,set=function(_,v)value=v end,read=function()return value end}
    end
    local skill=object('GA_ZuoShang_SpecialAttack_12_C')
    local out=param(playerRoot)
    local select=h.hooks[Aim.paths.bullet]
    assert(select(object('Selector'),red,nil,skill,nil,true,out)==true,'the selector now has a target')
    assert(out:read().Component==blue.RootComponent)
    assert(h.all():find('子弹目标改成对手 招式=GA_ZuoShang_SpecialAttack_12_C 原目标=BP_RenewalPlayer_C -> BP_Monster_blue_C 写入=true 读回=生效 累计=1',1,true),h.all())
    local empty=param(nil)
    assert(select(object('Selector'),red,nil,skill,nil,true,empty)==true and empty:read().Component==blue.RootComponent,'no target at all goes to the opponent')
    local fine=param(blue.RootComponent)
    assert(select(object('Selector'),red,nil,object('GA_Other_C'),nil,true,fine)==nil and fine:read().Component==blue.RootComponent)
    assert(h.all():find('子弹目标 招式=GA_Other_C 目标=BP_Monster_blue_C（参战单位，不改）',1,true),h.all())
    local playerBullet=param(red.RootComponent)
    assert(select(object('Selector'),h.player,nil,skill,nil,true,playerBullet)==nil and playerBullet:read().Component==red.RootComponent,'the player own bullets stay')
    h.paused=true
    local during=param(playerRoot)
    assert(select(object('Selector'),red,nil,skill,nil,true,during)==nil and during:read().Component==playerRoot,'an execution keeps its own')
    h.paused=false
end)

test('companion projectile selectors only accept verified output, including live struct writes',function()
    FName=function(text)return text end
    local h=harness()
    local caster=h.unit('companion')
    local enemy=object('MapBoss');h.mapEnemy=enemy
    enemy.RootComponent=object('TargetRoot',{GetOwner=function()return enemy end})
    local playerRoot=object('PlayerRoot',{GetOwner=function()return h.player end})
    local aim=h.new();aim:tick()
    local skill=object('GA_MengHua_Skill_08_Lightning_C')
    for _,route in ipairs({'bullet','bulletAbility'})do
        local select=h.hooks[Aim.paths[route]]
        local value={Component=playerRoot}
        local out={type=function()return 'RemoteUnrealParam'end,get=function()return value end,set=function()end}
        local before=aim.counts[route]
        assert(select(nil,caster,nil,skill,nil,true,out)==false and value.Component==playerRoot)
        out.set=function()error('setter rejected')end;value={}
        assert(select(nil,caster,nil,skill,nil,true,out)==false and value.Component==nil)
        assert(aim.counts[route]==before)
        value={Component=playerRoot,type=function()return 'UScriptStruct'end}
        assert(select(nil,caster,nil,skill,nil,true,out)==true and value.Component==enemy.RootComponent)
        value={Component=playerRoot};out.set=function(_,v)value=v end
        assert(select(nil,caster,nil,skill,nil,true,out)==true and value.Component==enemy.RootComponent)
        assert(aim.counts[route]==before+2)
        value={Component=playerRoot}
        assert(select(nil,h.player,nil,skill,nil,true,out)==nil and value.Component==playerRoot)
    end
end)

test('only companion Meng Hua reports actual bullet targets and pre/post HP, with a per-type limit',function()
    local h=harness();h.mapEnemy=object('Boss');local actor=h.unit('companion')
    h.members[1].class_path='/Game/Test/BP_Monster_MengHua.BP_Monster_MengHua_C'
    h.mapEnemy.hp=500;h.hp=function(a)return a.hp end
    local aim=h.new();aim:tick()
    local route=Aim.paths.menghuaHit
    local data=object('BulletData',{GetFName=function()return {ToString=function()return 'BD_MengHua_CA_02'end}end})
    local module=object('AttackModule',{LastOwnerAvatar=actor,BulletData=data})
    local function hit(source)
        module.LastOwnerAvatar=source
        h.hooks[route](module,h.mapEnemy,nil,nil,nil,nil)
        h.mapEnemy.hp=h.mapEnemy.hp-25
        h.posts[route](module,h.mapEnemy,nil,nil,nil,nil)
    end
    hit(actor);hit(actor);hit(actor);hit(h.player)
    local _,n=h.all():gsub('梦华随从弹体伤害调用','')
    assert(n==2 and h.all():find('BD_MengHua_CA_02',1,true) and h.all():find('HP=500 -> 475',1,true))
    h.members={};aim:tick();assert(h.hooks[route]==nil)
end)

test('a flying weapon holding the player when it starts goes to the opponent; its end says where it was',function()
    FName=function(text)return {name=text} end
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    red.GetClass=object('BP_Monster_ZuoShang_C').GetClass
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    local spot=function(x)return function()return {X=x,Y=0,Z=0} end end
    blue.K2_GetActorLocation=spot(1000);red.K2_GetActorLocation=spot(0);h.player.K2_GetActorLocation=spot(5000)
    blue.RootComponent=object('Capsule',{GetOwner=function()return blue end})
    h.fighting=true;aim:tick()
    local playerRoot=object('PlayerCapsule',{GetOwner=function()return h.player end})
    local skill=object('GA_ZuoShang_Skill_12_C')
    local sword=object('BP_Bullet_ZuoShang_FlyingSword_C',{BulletOwnerAvatar=red,BulletSourceAbility=skill,CurrentTarget={Component=playerRoot},K2_GetActorLocation=spot(4000)})
    h.hooks[Aim.paths.FlyingSwordStart](sword)
    assert(sword.CurrentTarget.Component==blue.RootComponent)
    assert(h.all():find('BP_Bullet_ZuoShang_FlyingSword_C 起飞 招式=GA_ZuoShang_Skill_12_C 当前目标=BP_Monster_blue_C 距玩家=10.0m 距对手=30.0m 距施法者=40.0m 原目标=BP_RenewalPlayer_C 改成对手 写入=true 读回=生效',1,true),h.all())
    h.hooks[Aim.paths.FlyingSwordEnd](sword)
    assert(h.all():find('BP_Bullet_ZuoShang_FlyingSword_C 结束 招式=GA_ZuoShang_Skill_12_C 当前目标=BP_Monster_blue_C 距玩家=10.0m 距对手=30.0m 距施法者=40.0m',1,true),h.all())
    local fine=object('BP_Bullet_ZuoShang_FlyingSpear_C',{BulletOwnerAvatar=red,CurrentTarget={Component=blue.RootComponent},K2_GetActorLocation=spot(500)})
    h.hooks[Aim.paths.FlyingSpearStart](fine)
    assert(aim:status().redirected==1,'already on a fighter')
    local playerSword=object('BP_Bullet_ZuoShang_FlyingSword_C',{BulletOwnerAvatar=h.player,CurrentTarget={Component=playerRoot}})
    h.hooks[Aim.paths.FlyingSwordStart](playerSword)
    assert(playerSword.CurrentTarget.Component==playerRoot,'not a fighting unit')
end)

test('a selector not loaded yet is hooked once it is there',function()
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    local real=StaticFindObject
    StaticFindObject=function(path)if path==Aim.paths.bullet then return nil end;return real(path) end
    h.fighting=true;aim:tick()
    assert(h.hooks[Aim.paths.bullet]==nil and h.all():find('读回=未找到，退避重试',1,true),h.all())
    local _,once=h.all():gsub('读回=未找到，退避重试','');assert(once==1)
    h.now=1;aim:tick()
    StaticFindObject=real
    h.now=2;aim:tick();assert(h.hooks[Aim.paths.bullet]==nil,'not before the wait')
    h.now=7;aim:tick();assert(h.hooks[Aim.paths.bullet]~=nil,'hooked on the next try')
end)
test('an effect that reads the player position by itself follows the opponent while its bullet runs',function()
  for _,ending in ipairs({'battle','game-thread unload','off-thread unload'}) do
    local h=harness();h.phaseBusyKey=function(k)return h.phaseOwner==k end;local aim=h.new()
    FName=function(text)return text end
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    local redAt={X=100,Y=0,Z=0}
    blue.K2_GetActorLocation=function()return {X=1000,Y=0,Z=0} end
    red.K2_GetActorLocation=function()return redAt end
    h.player.K2_GetActorLocation=function()return {X=5000,Y=0,Z=0} end
    local loop,cancelled,scans,list=nil,0,0,{}
    LoopInGameThreadWithDelay=function(ms,fn)assert(ms==50 and loop==nil);loop=fn;return 'handle' end
    CancelDelayedAction=function(handle)assert(handle=='handle');cancelled=cancelled+1;loop=nil end
    FindAllOf=function(class)assert(class=='PBZ_ParticleBullet');scans=scans+1;return list end
    local function named(text)return object(text,{GetFName=function()return {ToString=function()return text end} end}) end
    local function bullet(owner,data,status)
        local comp=object('NiagaraComponent',{sets={}})
        comp.SetVariableBool=function(self,name,value)self.sets[name]=value end
        comp.SetVariablePosition=function(self,name,value)self.sets[name]=value;self.sets.position=true end
        comp.SetVariableVec3=function(self,name,value)self.sets[name]=value;self.sets.vector=true end
        local bullet=object('PBZ_ParticleBullet',{BulletOwnerAvatar=owner,BulletData=data,BulletStatus=status,ParticleComponent=comp,
            BulletSourceAbility=object('GA_ZuoShang_Skill_19_C'),K2_GetActorLocation=function()return {X=1500,Y=0,Z=0} end})
        comp.GetOwner=function()return bullet end
        comp.Asset=named('NS_ZuoShang_SwordShooting_001')
        return bullet
    end
    local rain=named('BD_ZuoShang_Skill_19')
    h.fighting=true;aim:tick()
    local launch=h.hooks[Aim.paths.launch]
    assert(launch,'the launcher is hooked during a fight')
    -- Another skill's launcher costs nothing: no scan, no loop.
    launch(object('GAA_DelayDeflectProjectileBullet_C',{['Bullet Data']=named('BD_ZuoShang_FlyingSword_Skill_12_01'),GetAvatarActor=function()return blue end}))
    assert(loop==nil and scans==0)
    -- A unit outside the fight uses the effect as the game made it.
    local stranger=object('BP_Monster_ZuoShang_C')
    launch(object('GAA_DelayDeflectProjectileBullet_C',{['Bullet Data']=rain,GetAvatarActor=function()return stranger end}))
    assert(loop==nil and scans==0,'not a fighting unit')
    local mine=bullet(blue,rain,2)
    local mapBoss=bullet(stranger,rain,2)
    local otherEffect=bullet(blue,named('BD_MengHua_CA_03'),2)
    local spent=bullet(blue,rain,3)
    list={mapBoss,otherEffect,spent,mine}
    launch(object('GAA_DelayDeflectProjectileBullet_C',{['Bullet Data']=rain,GetAvatarActor=function()return blue end}))
    assert(loop~=nil and scans==0,'the look happens on the loop, after the launcher ran')
    loop()
    local sets=mine.ParticleComponent.sets
    assert(scans==1 and sets.UE_UseTestTargetPos==true and sets.UE_TestTargetPos.X==100,'switch on, position on the opponent')
    assert(sets.position and sets.vector)
    assert(next(mapBoss.ParticleComponent.sets)==nil and next(otherEffect.ParticleComponent.sets)==nil and next(spent.ParticleComponent.sets)==nil)
    assert(h.all():find('特效目标改成对手 子弹=BD_ZuoShang_Skill_19 招式=GA_ZuoShang_Skill_19_C 对手=BP_Monster_red_C 开关=UE_UseTestTargetPos 写入=true 坐标写入=true/true 发射点距对手=14.0m 距玩家=35.0m',1,true),h.all())
    assert(aim:status().redirected==1)
    redAt={X=300,Y=0,Z=0};loop()
    assert(sets.UE_TestTargetPos.X==300,'follows the opponent')
    loop();loop()
    assert(scans==1,'a launch that already found its particle needs no more world scans')
    local replacement=bullet(red,rain,2)
    mine.BulletOwnerAvatar=red;mine.ParticleComponent=replacement.ParticleComponent
    mine.ParticleComponent.GetOwner=function()return mine end
    loop()
    assert(mine.ParticleComponent.sets.UE_TestTargetPos and mine.ParticleComponent.sets.UE_TestTargetPos.X==1000,
        'a reused bullet must follow its current owner opponent')
    assert(sets.UE_UseTestTargetPos==false,'a replaced but still-valid component must be released')
    local logStart=#h.lines
    for i=1,100 do mine.BulletOwnerAvatar=i%2==0 and blue or red;loop()end
    assert(#h.lines-logStart<=60,'reused effect objects must not reset the lifetime log budget')
    h.paused=true;redAt={X=999,Y=0,Z=0};loop();assert(sets.UE_TestTargetPos.X==300,'nothing while time stands still');h.paused=false
    mine.BulletStatus=3;loop()
    assert(sets.UE_UseTestTargetPos==false and cancelled==1 and loop==nil,'switch back off, loop gone once it is over')
    assert(h.all():find('特效目标还原 子弹=BD_ZuoShang_Skill_19',1,true))
    -- A fight that ends with one in the air leaves nothing behind.
    local again=bullet(blue,rain,2);list={again}
    launch(object('GAA_DelayDeflectProjectileBullet_C',{['Bullet Data']=rain,GetAvatarActor=function()return blue end}))
    loop();assert(again.ParticleComponent.sets.UE_UseTestTargetPos==true)
    h.phaseOwner=key(blue);h.paused=true;loop()
    assert(again.ParticleComponent.sets.UE_UseTestTargetPos==false,'an existing owned override is released for the native pair, even during global pause')
    while loop do loop()end
    launch(object('GAA_DelayDeflectProjectileBullet_C',{['Bullet Data']=rain,GetAvatarActor=function()return blue end}))
    assert(loop==nil,'a busy phase cannot start a new particle redirect')
    h.phaseOwner=nil;h.paused=false
    launch(object('GAA_DelayDeflectProjectileBullet_C',{['Bullet Data']=rain,GetAvatarActor=function()return blue end}));loop()
    assert(again.ParticleComponent.sets.UE_UseTestTargetPos==true)
    if ending=='battle' then
        h.fighting=false;aim:tick();h.now=h.now+20;aim:tick()
        assert(again.ParticleComponent.sets.UE_UseTestTargetPos==false)
    else
        local checks=0;local onThread=ending=='game-thread unload'
        local lateTick=loop;local U=require('ue_observe')
        U.setEngineValidator(function()checks=checks+1;return true end)
        aim:silence('unload',onThread);lateTick()
        U.setEngineValidator(nil)
        assert(again.ParticleComponent.sets.UE_UseTestTargetPos==not onThread)
        assert(onThread and checks>0 or not onThread and checks==0,'engine checks during '..ending..'='..checks)
    end
    assert(loop==nil and h.hooks[Aim.paths.launch]==nil)
    LoopInGameThreadWithDelay,CancelDelayedAction,FindAllOf=nil,nil,nil
  end
end)
test('effect skills delegate to isolated instances and never write the world player position',function()
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red');h.targets[key(blue)]=red;h.fighting=true;aim:tick()
    local armed=0;aim.effects={arm=function()armed=armed+1 end}
    local oldLoop=LoopInGameThreadWithDelay
    LoopInGameThreadWithDelay=function()error('a global player-position loop must not be started')end
    local function skill(name,owner)return object(name,{GetAvatarActorFromActorInfo=function()return owner end})end
    local start=h.hooks[Aim.paths.skillStart]
    start(skill('GA_Other_C',blue));start(skill('GA_MengHua_CA_03_C',h.player));assert(armed==0)
    for name in pairs(Aim.effectSkills)do start(skill(name,blue))end
    assert(armed==7,'all known collection-based offensive skills arm instance isolation')
    local child=skill('GA_ZuoShang_P2_Skill_17_NoCD_C',blue)
    child.GetClass().GetSuperStruct=function()return {GetFName=function()return {ToString=function()return 'GA_ZuoShang_P2_Skill_17_C'end}end,IsValid=function()return true end}end
    start(child);assert(armed==8,'subclasses retain the effect adapter')
    aim.effects=nil;start(skill('GA_MengHua_CA_03_C',blue));assert(armed==8,'an absent adapter never falls back to a global write')
    LoopInGameThreadWithDelay=oldLoop
end)

test('stands keep offensive aiming but are never accepted as bullet or lock targets',function()
    FName=function(text)return {name=text} end
    local h=harness();local aim=h.new()
    local blue,red,stand=h.unit('blue'),h.unit('red'),h.unit('blue')
    stand.GetClass=object('BP_Monster_ZuoShang_P2_Stand_C').GetClass
    h.members[3].stand=true
    h.targets[key(blue)]=red;h.targets[key(red)]=blue;h.targets[key(stand)]=red
    for _,actor in ipairs({blue,red,stand})do actor.RootComponent=object('Capsule',{GetOwner=function()return actor end}) end
    h.fighting=true;aim:tick()
    local value={Component=stand.RootComponent}
    local out={type=function()return 'RemoteUnrealParam' end,get=function()return value end,set=function(_,v)value=v end}
    local skill=object('GA_Test_C',{GetAvatarActorFromActorInfo=function()return red end,['Lock Target']=value})
    assert(h.hooks[Aim.paths.bullet](nil,red,nil,skill,nil,true,out)==true and value.Component==blue.RootComponent)
    h.hooks[Aim.paths.lock](skill,nil,nil,out)
    assert(skill['Lock Target'].Component==blue.RootComponent,'native locks on a stand are corrected')
    h.members[3].reserve=true;aim:tick()
    local ownSkill=object('GAA_ForceLockTarget_C',{GetAvatarActor=function()return stand end})
    assert(h.ask('pawn',ownSkill)==red,'stand skills still aim at their summoner opponent, even on first reveal')
    local sword=object('BP_Bullet_ZuoShang_FlyingSword_C',{BulletOwnerAvatar=red,CurrentTarget={Component=stand.RootComponent}})
    h.hooks[Aim.paths.FlyingSwordStart](sword)
    assert(sword.CurrentTarget.Component==blue.RootComponent)
end)
test('native pair phases retain only their own player getters and target selectors',function()
    FName=function(text)return {name=text}end
    local h=harness();local blue,red=h.unit('blue'),h.unit('red');local busy=true
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    local checks=0
    h.phaseBusyKey=function(k)checks=checks+1;return busy and k==key(blue)end
    local aim=h.new();h.fighting=true;aim:tick()
    for _,a in ipairs({blue,red,h.player})do a.RootComponent=object('Capsule',{GetOwner=function()return a end})end
    local blueSkill=object('GA_MoTian_Skill_08_C',{GetAvatarActorFromActorInfo=function()return blue end,['Lock Target']={Component=h.player.RootComponent}})
    local redSkill=object('GA_MoTian_Skill_08_C',{GetAvatarActorFromActorInfo=function()return red end})
    assert(h.ask('character',blueSkill)==h.player and h.askForce(blueSkill)==true,'the phase owner keeps its native player selection')
    assert(h.ask('character',redSkill)==blue and h.askForce(redSkill)==false,'another fight participant keeps ordinary redirection')
    local value={Component=h.player.RootComponent}
    local out={type=function()return 'RemoteUnrealParam'end,get=function()return value end,set=function(_,v)value=v end}
    h.hooks[Aim.paths.bullet](nil,blue,nil,blueSkill,nil,true,out)
    h.hooks[Aim.paths.lock](blueSkill,nil,nil,out)
    assert(value.Component==h.player.RootComponent and blueSkill['Lock Target'].Component==h.player.RootComponent)
    local before=checks
    h.ask('character',object('GA_MoTian_Skill_08_C',{GetAvatarActorFromActorInfo=function()return h.player end}))
    assert(checks==before,'unowned contexts must not query the phase manager')
    busy=false
    assert(h.ask('character',blueSkill)==red and h.askForce(blueSkill)==false,'phase completion re-enables ordinary redirection')
end)
test('an old lock on the on-pole boss goes to its wave cub without changing other enemy locks',function()
    FName=function(v)return v end
    local h=harness()
    local caster,boss,cub,unrelated=h.unit('blue'),h.unit('red'),h.unit('red'),h.unit('red')
    for _,actor in ipairs({boss,cub,unrelated})do
        actor.RootComponent=object('Mesh',{GetOwner=function()return actor end})
    end
    h.targets[key(caster)]=cub
    h.phaseAimOpponent=function(id,old)if id==key(caster) and old==boss then return cub end end
    h.fighting=true;h.new():tick()
    local ability=object('GA_ZuoShang_CA_02_C',{GetAvatarActorFromActorInfo=function()return caster end})
    local function target(owner)return {Component=owner.RootComponent} end
    local function out(owner)
        local socket=target(owner)
        return {type=function()return 'RemoteUnrealParam' end,get=function()return socket end,
            set=function(_,value)socket=value end}
    end
    local selection=out(boss)
    h.hooks[Aim.paths.bullet](nil,caster,nil,ability,nil,nil,selection)
    assert(selection:get().Component==cub.RootComponent)
    local other=out(unrelated)
    h.hooks[Aim.paths.bullet](nil,caster,nil,ability,nil,nil,other)
    assert(other:get().Component==unrelated.RootComponent)
    ability['Lock Target']=target(boss)
    h.hooks[Aim.paths.lock](ability,nil,nil,out(boss))
    assert(ability['Lock Target'].Component==cub.RootComponent)
end)

test('the optional actor-based phase guard uses only a live owned actor',function()
    local h=harness();local blue,red=h.unit('blue'),h.unit('red');h.targets[key(blue)]=red;h.targets[key(red)]=blue
    local asked
    h.phaseBusy=function(actor)asked=actor;return actor==blue end
    local aim=h.new();h.fighting=true;aim:tick()
    local skill=object('GA_MoTian_Skill_08_C',{GetAvatarActorFromActorInfo=function()return blue end})
    assert(h.ask('character',skill)==h.player and asked==blue)
end)
test('shutdown makes retained callbacks inert before invoking native unregistration',function()
    local h=harness();local blue,red=h.unit('blue'),h.unit('red');h.targets[key(blue)]=red;h.targets[key(red)]=blue
    local aim=h.new();h.fighting=true;aim:tick()
    local skill=object('GA_MoTian_Skill_08_C',{GetAvatarActorFromActorInfo=function()return blue end})
    local callback=h.hooks[Aim.paths.character];local original=UnregisterHook;local asked,redirected=0,0
    assert(callback(nil,skill)==red,'the fixture must exercise a live redirect before shutdown')
    UnregisterHook=function(...)
        asked=asked+1;if callback(nil,skill)~=nil then redirected=redirected+1 end
        return original(...)
    end
    aim:silence('fixture shutdown');assert(asked==10)
    print('shutdown native callback redirects='..redirected)
    assert(redirected==0,'shutdown cannot redirect through a reentrant native callback')
    UnregisterHook=original
end)
test('loaded registration failures already follow lookup backoff',function()
    local h=harness();local blue,red=h.unit('blue'),h.unit('red');h.targets[key(blue)]=red;h.targets[key(red)]=blue
    local original=RegisterHook;local attempts=0
    RegisterHook=function(path,...)
        if path==Aim.paths.bullet then attempts=attempts+1;error('registration fixture')end
        return original(path,...)
    end
    local aim=h.new();h.fighting=true
    for i=0,1200 do h.now=i*0.05;aim:tick()end
    print('registration failure 60seconds attempts='..attempts)
    assert(attempts==6,'keep the existing exponential function-path backoff')
    RegisterHook=original;aim:silence('fixture cleanup')
end)
test('throwing unregistration has a retry deadline',function()
    local h=harness();local aim=h.new();local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue;h.fighting=true;aim:tick()
    local original=UnregisterHook;local attempts=0
    UnregisterHook=function()attempts=attempts+1;error('native retry fixture')end
    h.fighting=false;h.members={};aim:tick();h.now=16;aim:tick()
    for i=1,19 do h.now=16+i*0.05;aim:tick()end
    print('unregister throwing ticks=20 attempts='..attempts)
    assert(attempts==10,'a native failure must not be retried every support tick')
    UnregisterHook=original;aim:silence('fixture cleanup')
end)
test('failed unregistration is paced and its bookkeeping survives explicit false',function()
    local h=harness();local aim=h.new();local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue;h.fighting=true;aim:tick()
    local original=UnregisterHook;local attempts=0;local failure=true
    UnregisterHook=function(...)
        attempts=attempts+1
        if failure then return false end
        return original(...)
    end
    h.fighting=false;h.members={};aim:tick();h.now=16;aim:tick()
    for i=1,19 do h.now=16+i*0.05;aim:tick()end
    print('unregister failed ticks=20 attempts='..attempts)
    assert(attempts==10,'failed hooks must stay tracked and be attempted only once within one second')
    failure=false;h.now=17.1;aim:tick();assert(attempts==20 and aim:status().state=='idle')
    assert(next(h.hooks)==nil,'successful retry removes every retained native hook')
    UnregisterHook=original
end)
test('Skill 19 tracks five native pooled or attached emitters and never writes to a shared or unrelated effect',function()
    for _,mode in ipairs({'worldPool','casterPool','attachedChild','lifecycle','actorList','laterShared','sharedAtFinish','shared','wrongSystem','wrongSource','otherWorld'})do
        local h=harness();h.world=object('World')
        local shooter,target=h.unit('blue'),h.unit('red')
        h.targets[key(shooter)]=target;h.targets[key(target)]=shooter
        local function named(n)return object(n,{GetFName=function()return {ToString=function()return n end}end})end
        FName=function(n)return n end
        local expected=named('NS_ZuoShang_SwordShooting_001');local unrelated=named('OtherNiagara')
        local cls=object('Class',{GetFullName=function()return 'Class /Script/Niagara.NiagaraComponent' end})
        local baseFind=StaticFindObject
        StaticFindObject=function(path)if path=='/Script/Niagara.NiagaraComponent' then return cls end;return baseFind(path)end
        local data=named('BD_ZuoShang_Skill_19');data.Particle=expected
        local ability=object('GA_ZuoShang_Skill_19_C',{GetAvatarActorFromActorInfo=function()return shooter end,outer=shooter})
        target.K2_GetActorLocation=function()return {X=375,Y=0,Z=0}end
        local loop;local list,components={},{};local writes=0
        for _=1,5 do
            local bullet=object('PBZ_ParticleBullet',{outer=h.world,BulletData=data,BulletStatus=2,BulletSourceAbility=ability,BulletOwnerAvatar=shooter})
            local root=object('SceneComponent',{outer=bullet,GetOwner=function()return bullet end});bullet.SceneRoot=root
            local comp=object('NiagaraComponent',{outer=mode=='otherWorld' and object('DifferentWorld') or h.world,IsActive=function()return true end,
                GetAsset=function()return mode=='wrongSystem' and unrelated or expected end,
                GetOwner=function()return mode=='casterPool' and shooter or h.world end,
                SetVariablePosition=function(self,_,p)self.x=p.X end,SetVariableVec3=function(self,_,p)self.x=p.X end,
                SetVariableBool=function(self,_,v)self.redirect=v;if v then writes=writes+1 end end})
            bullet.ParticleComponent=comp
            if mode=='attachedChild' or mode=='lifecycle' then
                bullet.ParticleComponent=nil;comp.GetAttachParent=function()return root end
                if mode=='attachedChild' then root.AttachChildren={comp}
                else bullet.EffectInstanceData={InstanceData={ForEach=function(_,fn)fn('start',{NiagaraComponents={comp}})end}} end
            end
            if mode=='actorList' then
                bullet.ParticleComponent=nil;comp.GetOwner=function()return bullet end
                bullet.K2_GetComponentsByClass=function(_,c)assert(c==cls);return {comp}end
            end
            if mode=='wrongSource' then bullet.BulletSourceAbility=object('GA_ZuoShang_Skill_19_C',{outer=h.player})end
            list[#list+1]=bullet;components[#components+1]=comp
            if mode=='shared' then list[#list+1]=object('PBZ_ParticleBullet',{outer=h.world,BulletData=data,BulletStatus=2,BulletOwnerAvatar=h.player,ParticleComponent=comp})end
        end
        LoopInGameThreadWithDelay=function(_,fn)loop=fn;return 31 end
        CancelDelayedAction=function()loop=nil;return true end
        FindAllOf=function(n)assert(n=='PBZ_ParticleBullet');return list end
        local aim=h.new();h.fighting=true;aim:tick();h.ask('pawn',ability);assert(loop)
        for i=1,81 do h.now=i*0.05;if loop then loop()end end
        local ok=mode=='worldPool' or mode=='casterPool' or mode=='attachedChild' or mode=='lifecycle' or mode=='actorList' or mode=='laterShared' or mode=='sharedAtFinish'
        assert(writes==(ok and 5 or 0),mode..' '..h.all())
        if ok then
            for _,comp in ipairs(components)do assert(comp.x==375 and comp.redirect==true,mode) end
            if mode=='laterShared' or mode=='sharedAtFinish' then
                local c=components[5];c.x=0;c.redirect=nil
                list[#list+1]=object('PBZ_ParticleBullet',{outer=h.world,BulletData=data,BulletStatus=2,BulletOwnerAvatar=h.player,ParticleComponent=c})
                if mode=='sharedAtFinish' then
                    h.hooks[Aim.paths.rainFinished](list[5],c)
                else
                    h.now=6;h.ask('pawn',ability)
                    for i=1,8 do h.now=h.now+0.05;if loop then loop()end end
                end
                assert(c.x==0 and c.redirect==nil,'discard a reassigned pool slot without writing to its new owner')
                components[5]=nil
            end
            h.hooks[Aim.paths.rainFinished](list[1],components[2]);assert(components[2].redirect==true)
            h.hooks[Aim.paths.rainDeactivated](list[1],components[1]);assert(components[1].redirect==false)
            aim:silence('test',true)
            for _,comp in ipairs(components)do assert(comp.redirect==false,mode..' restore')end
        else
            assert(h.all():find('首次拒绝=',1,true));aim:silence('test',true)
        end
    end
end)
print('player_aim: all tests passed')
