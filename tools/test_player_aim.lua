package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Aim=require('player_aim')
local address=0
local function object(name,fields)
    address=address+1;local a=address
    local o=fields or {}
    o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function()return a end
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
            paused=function()return h.paused end})
    end
    function h.all()return table.concat(h.lines,'\n')end
    return h
end
local function key(actor)return tostring(actor.GetAddress())end
local function test(name,fn)fn();print('ok - '..name)end

test('no fight: no hooks; a fight hooks both getters once and checks the answer',function()
    local h=harness();local aim=h.new()
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    aim:tick()
    assert(next(h.hooks)==nil and aim:status().state=='idle')
    h.fighting=true;aim:tick();aim:tick()
    assert(h.ids==8 and aim:status().state=='running','no flying-weapon hooks without a ZuoShang caster')
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
    assert(#h.unhooked==8 and aim:status().state=='idle' and h.all():find('摘除挂钩（战斗已结束）',1,true),h.all())
    h.fighting=true;aim:tick();assert(h.ids==16,'hooked again for the next fight')
    aim:silence('test');assert(#h.unhooked==16)
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
    local h=harness();local aim=h.new()
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
        return object('PBZ_ParticleBullet',{BulletOwnerAvatar=owner,BulletData=data,BulletStatus=status,ParticleComponent=comp,
            BulletSourceAbility=object('GA_ZuoShang_Skill_19_C'),K2_GetActorLocation=function()return {X=1500,Y=0,Z=0} end})
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
    assert(scans==3,'looks only a few times')
    local replacement=bullet(red,rain,2)
    mine.BulletOwnerAvatar=red;mine.ParticleComponent=replacement.ParticleComponent
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
    h.fighting=false;aim:tick();h.now=h.now+20;aim:tick()
    assert(again.ParticleComponent.sets.UE_UseTestTargetPos==false and loop==nil and h.hooks[Aim.paths.launch]==nil)
    LoopInGameThreadWithDelay,CancelDelayedAction,FindAllOf=nil,nil,nil
end)
test('a skill whose effect only reads the player position: the global value follows the opponent while it runs',function()
    local h=harness()
    FName=function(text)return text end
    local blue,red=h.unit('blue'),h.unit('red')
    h.targets[key(blue)]=red;h.targets[key(red)]=blue
    local redAt={X=100,Y=0,Z=0}
    blue.K2_GetActorLocation=function()return {X=1000,Y=0,Z=0} end
    red.K2_GetActorLocation=function()return redAt end
    h.player.K2_GetActorLocation=function()return {X=5000,Y=0,Z=0} end
    -- As in the game: the Niagara variable is a colour taken from the material collection, so its vector calls find nothing.
    local value={R=5000,G=0,B=0,A=0.5}
    local copied={R=5000,G=0,B=0,A=0.5}
    local vectorWrites=0
    local instance=object('NiagaraParameterCollectionInstance',{
        SetVectorParameter=function()vectorWrites=vectorWrites+1 end,GetVectorParameter=function()return {X=0,Y=0,Z=0} end,
        GetColorParameter=function(_,name)assert(name=='CharRootPos');return copied end})
    local materialLib=object('KismetMaterialLibrary',{
        SetVectorParameterValue=function(_,world,collection,name,v)assert(world and collection and name=='CharRootPos');value=v end,
        GetVectorParameterValue=function(_,world,collection,name)assert(world and collection and name=='CharRootPos');return value end})
    local real=StaticFindObject
    local active=true
    StaticFindObject=function(path)
        if path:find('NiagaraFunctionLibrary') then return object('NiagaraFunctionLibrary',{GetNiagaraParameterCollection=function()return instance end}) end
        if path:find('NPC_CharInfo_001') then return object('NPC_CharInfo_001') end
        if path:find('KismetMaterialLibrary') then return materialLib end
        if path:find('MPC_CharInfo_001') then return object('MPC_CharInfo_001') end
        if path:find('AbilitySystemBlueprintLibrary') then return object('AbilitySystemBlueprintLibrary',{IsGameplayAbilityActive=function(_,ability)return active and not ability.over end}) end
        return real(path)
    end
    local loop,cancelled=nil,0
    LoopInGameThreadWithDelay=function(ms,fn)assert(ms==1 and loop==nil);loop=fn;return 'handle' end
    CancelDelayedAction=function()cancelled=cancelled+1;loop=nil end
    local aim=Aim.new({log=function(s)h.lines[#h.lines+1]=s end,clock=function()return h.now end,members=function()return h.members end,fighting=function()return h.fighting end,
        statics=function()return h.statics end,opponentOf=function(k)return h.targets[k] end,abilityTargets=function()return h.abilityTargets end,player=function()return h.player end,
        world=function()return object('World') end,paused=function()return h.paused end})
    h.fighting=true;aim:tick()
    local start=h.hooks[Aim.paths.skillStart]
    assert(start,'hooked during a fight')
    local function skill(name,owner)return object(name,{GetAvatarActorFromActorInfo=function()return owner end}) end
    start(skill('GA_Other_C',blue));assert(loop==nil,'any other skill costs nothing')
    start(skill('GA_MengHua_CA_03_C',object('BP_Monster_MengHua_C')));assert(loop==nil,'not a fighting unit: as the game made it')
    start(skill('GA_MengHua_CA_03_C',blue));assert(loop~=nil)
    loop()
    assert(value.R==100 and value.G==0 and value.B==0 and value.A==0.5,'the opponent, in the material collection, keeping the alpha')
    assert(vectorWrites==0,'the Niagara vector call does nothing in the game')
    assert(h.all():find('全局角色位置改成对手 招式=GA_MengHua_CA_03_C 第1次 对手=BP_Monster_red_C 材质集合写入前距玩家=0.0m 距对手=49.0m 写入=true 读回距对手=0.0m Niagara集合距玩家=0.0m 距对手=49.0m',1,true),h.all())
    -- The world tick copied the value to the Niagara instance, and the player class then wrote its own to the material collection.
    copied=value;redAt={X=300,Y=0,Z=0};value={R=5000,G=0,B=0,A=0.5};loop();assert(value.R==300,'follows it, and wins over what the player class wrote')
    assert(h.all():find('第2次 对手=BP_Monster_red_C 材质集合写入前距玩家=0.0m 距对手=47.0m 写入=true 读回距对手=0.0m Niagara集合距玩家=49.0m 距对手=2.0m',1,true),h.all())
    h.paused=true;redAt={X=999,Y=0,Z=0};loop();assert(value.R==300,'not while time stands still');h.paused=false
    active=false;h.now=h.now+1;loop();assert(loop~=nil,'the effect may outlive the skill')
    value={R=5000,G=0,B=0,A=0.5}
    h.now=h.now+7;loop();assert(loop==nil and cancelled==1 and h.all():find('全局角色位置还原 招式=GA_MengHua_CA_03_C 写入=3次（招式结束） 还原时读回距玩家=0.0m',1,true),h.all())
    -- A second skill while one runs takes over; the fight ending stops it.
    active=true;start(skill('GA_LengTu_CA_02_C',red));assert(loop~=nil);redAt={X=0,Y=0,Z=0};loop();assert(value.R==1000,'its own opponent')
    start(skill('GA_ZuoShang_P2_Skill_17_C',blue));loop();assert(value.R==0)
    h.now=h.now+25;loop();assert(loop==nil,'capped')
    -- A subclass plays the same effect.
    local child=skill('GA_ZuoShang_P2_Skill_17_NoCD_C',blue)
    child.GetClass().GetSuperStruct=function()return {GetFName=function()return {ToString=function()return 'GA_ZuoShang_P2_Skill_17_C' end}end,IsValid=function()return true end} end
    start(child);assert(loop~=nil,'a subclass counts');h.now=h.now+25;loop();assert(loop==nil)
    -- Two at once: the newest has the value; when it ends the older one gets it back, not the player.
    redAt={X=300,Y=0,Z=0}
    local first,second=skill('GA_MengHua_CA_03_C',blue),skill('GA_LengTu_CA_02_C',red)
    start(first);start(second);loop();assert(value.R==1000,'the newer skill: its opponent')
    second.over=true;h.now=h.now+0.5;loop();h.now=h.now+7;loop()
    assert(loop~=nil and value.R==300,'the older skill again: its opponent')
    assert(h.all():find('全局角色位置还原 招式=GA_LengTu_CA_02_C',1,true),h.all())
    first.over=true;h.now=h.now+0.5;loop();h.now=h.now+7;loop();assert(loop==nil)
    start(skill('GA_MengHua_CA_03_C',blue));assert(loop~=nil)
    h.fighting=false;aim:tick();h.now=h.now+20;aim:tick();assert(loop==nil and h.hooks[Aim.paths.skillStart]==nil)
    StaticFindObject=real;LoopInGameThreadWithDelay,CancelDelayedAction=nil,nil
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
print('player_aim: all tests passed')
