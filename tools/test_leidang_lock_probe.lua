package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Probe=require('leidang_lock_probe')
local CLASS='/PBZCombatAsset/ActorData/Mobs/050_LeiDang_P2/BP_Monster_LeiDang_P2.BP_Monster_LeiDang_P2_C'
FName=function(value)return value end

local function fixture()
    local h={time=0,mode=false,listed=true,rated=true,path=true,valid=true,bone=true,
        terminal=false,tag={},inGame=true,lines={},reads=0}
    local serial=0
    local function object(label,outer)
        serial=serial+1
        local id=serial
        local o={alive=true,outer=outer}
        function o:IsValid()return self.alive end
        function o:GetAddress()assert(self.alive);return id end
        function o:GetOuter()return self.outer end
        function o:GetClass()return self end
        function o:GetFName()return {ToString=function()return label end} end
        return o
    end
    local world=object('World')
    local player=object('Player',world)
    local tiger=object('BP_Monster_LeiDang_P2_C',world)
    local mesh=object('Mesh',tiger)
    function mesh:GetOwner()return tiger end
    function mesh:DoesSocketExist(socket)assert(socket=='spine_04');return h.bone end
    function mesh:GetSocketLocation()return {X=500,Y=0,Z=100} end
    local body={Component=mesh,SocketName='spine_04'}
    tiger.Mesh=mesh
    player.AbilitySystemComponent=object('PlayerASC',player)
    function player.AbilitySystemComponent:GetGameplayTagCount(tag)return h.tag[tag.TagName] or 0 end
    tiger.AbilitySystemComponent=object('BossASC',tiger)
    function tiger.AbilitySystemComponent:GetGameplayTagCount(tag)
        return h.terminal and tag.TagName=='CharacterState.Unselectable' and 1 or 0
    end
    local tc=object('TargetingComponent',player)
    player['Targeting Component']=tc
    function tc:GetOwner()return player end
    tc.LockTarget={}
    tc.LockWidget=object('LockWidget',tc)
    function tc.LockWidget:IsVisible()return false end
    tc.TargetingSubsystem=object('TargetingWorldSubsystem',world)
    function tc.TargetingSubsystem:GetTargetsByTag(tag,exact,out)
        assert(tag.TagName=='Targeting.Target.Combat' and exact)
        if h.listed~=nil then out.OutTargets=h.listed and {tiger} or {} end
    end
    local handler=object('PBZ_TargetingHandler_CombatLock_Combined_C',tc)
    handler.ValidatorTag={TagName='Targeting.Validator.Combat.Default'}
    handler.Avatar,handler.TargetingComponent=player,tc
    tc.DefaultTargetHandler=handler
    local child=object('PBZ_TargetingHandler_CombatLock_C',handler)
    child.Avatar,child.TargetingComponent=player,tc
    handler.Handlers={{Handler=child}}
    function child:FindTargetsRated(ignore,out,relock)
        assert(#ignore==0 and relock==false)
        out.Targets={{Target=body,Score=1}}
    end
    function handler:FindTargetsRated(ignore,out,relock)
        assert(#ignore==0 and relock==false)
        h.reads=h.reads+1
        if h.rated~=nil then out.Targets=h.rated and {{Target=body,Score=1}} or {} end
    end
    function tc:FindTarget(out)
        if h.best==false then return false end
        out.Target=body;return true
    end
    function tc:IsTargetValid(validator,target)
        assert(validator.TagName==handler.ValidatorTag.TagName and target.Component==mesh)
        return h.valid
    end
    local utils=object('TargetingUtils')
    function utils:GetPrimaryTargetingData(actor,tag,out)
        assert(actor==tiger and tag.TagName=='Targeting.Target.Combat')
        if h.primary==false then return false end
        out.OutTarget=body;return true
    end
    function utils:IsLockPathValid(p,target,kind)
        assert(p==player and target.Component==mesh and kind==5)
        return h.path
    end
    local camera=object('PlayerCameraManager',world)
    function camera:GetCameraLocation()return {X=0,Y=0,Z=100} end
    function camera:GetCameraRotation()return {Yaw=0,Pitch=0} end
    local probe=Probe.new({
        clock=function()return h.time end,inGameThread=function()return h.inGame end,
        world=function()return h.newWorld or world end,player=function()return player end,
        relation=function(a,b)
            assert(a~=b and (a==tiger or b==tiger))
            if a==tiger and h.mode then return 1 end
            return 2
        end,
        freeCam=function()return h.freeCam end,
        spectator=function()return {enabled_requested=h.mode,player_can_be_hatred_readback=not h.mode} end,
        utils=function()return utils end,camera=function()return camera end,
        log=function(s)h.lines[#h.lines+1]=s end,
    })
    h.body,h.targeting,h.tiger,h.object,h.handler=body,tc,tiger,object,handler
    function h:sample()
        h.time=h.time+2
        probe:sync({{actor=tiger,class_path=CLASS,team='blue'}})
        return h.lines[#h.lines]
    end
    function h:sampleOther()
        probe:sync({{actor=tiger,class_path='/DifferentClass',team='blue'}})
    end
    return h
end

local function expect(line, ...)
    assert(line,'missing diagnostic')
    for _,part in ipairs({...})do assert(line:find(part,1,true),part..'\n'..line) end
end
local h=fixture()
h:sampleOther()
h.inGame=false;h:sample()
h.inGame=true;h.freeCam=true;h:sample();h.freeCam=false
assert(#h.lines==0 and h.reads==0,'scope and game-thread guards')
h.mode=true
expect(h:sample(),'无仇恨=true','玩家对雷当=2','雷当对玩家=1','注册=true','原生锁点=true',
    '验证通过=true','进入候选=true','镜头距离偏航俯仰=5.0m/0.0°/0.0°','判断=进入原生候选')
h.mode=false
expect(h:sample(),'无仇恨=false','雷当对玩家=2','进入候选=true')
h.targeting.LockTarget=h.body
expect(h:sample(),'当前锁住=true','锁定标记可见=false','判断=已锁定')
h.targeting.LockTarget={}
h.path=false;h.rated=false
expect(h:sample(),'镜头路径=false','进入候选=false','判断=未通过镜头路径检查')
h.path=true;h.valid=false
expect(h:sample(),'判断=原生验证器拒绝')
h.valid=true;h.terminal=true
expect(h:sample(),'不可选=1','判断=目标状态被过滤')
h.terminal=false;h.tag['CharacterState.InCombat']=1
expect(h:sample(),'普通处理器通过=true','判断=进战处理器筛掉目标')
h.tag['CharacterState.InCombat']=0;h.tag['CharacterState.Native.FindingLockTarget']=1
expect(h:sample(),'普通处理器通过=true','判断=重试锁定时普通处理器未入选')
h.tag['CharacterState.Native.FindingLockTarget']=0;h.primary=false
expect(h:sample(),'原生锁点=false','判断=未取得原生锁点')
h.primary=true;h.listed=false
expect(h:sample(),'注册=false','判断=未注册为战斗目标')
h.listed=nil;h.rated=nil
expect(h:sample(),'注册=?','进入候选=?','回退首选=BP_Monster_LeiDang_P2_C','判断=候选结果未读回')
local n=#h.lines
h:sample();assert(#h.lines==n,'each no-aggro condition has a limited number of samples')
h.mode=true;h:sample();assert(#h.lines==n+1,'an A/B toggle opens a new sampling window')
h.newWorld=h.object('OtherWorld');h:sample()
h.newWorld=nil;h.tiger.alive=false;h:sample()
assert(#h.lines==n+1,'foreign world and invalid actors are skipped')
local loading=fixture()
loading.handler.Avatar=nil
expect(loading:sample(),'搜索组件就绪=false','进入候选=?')
assert(loading.reads==0,'an uninitialized native handler is not called')
print('leidang_lock_probe: PASS (scope, throttle, A/B readback and native rejection stages)')
