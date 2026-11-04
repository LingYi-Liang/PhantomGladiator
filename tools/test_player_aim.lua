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
            opponentOf=function(key)return h.targets[key] end,abilityTargets=function()return h.abilityTargets end,
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
    assert(h.ids==3 and aim:status().state=='running')
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
    assert(#h.unhooked==3 and aim:status().state=='idle' and h.all():find('摘除挂钩（战斗已结束）',1,true),h.all())
    h.fighting=true;aim:tick();assert(h.ids==6,'hooked again for the next fight')
    aim:silence('test');assert(#h.unhooked==6)
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
print('player_aim: all tests passed')
