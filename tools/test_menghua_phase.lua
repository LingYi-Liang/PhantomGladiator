package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Phase=require('menghua_phase')
local M='/PBZCombatAsset/ActorData/Mobs/'
local P=M..'078_MengHua/BP_Monster_MengHua.BP_Monster_MengHua_C'
local C=M..'079_XuKong/BP_Monster_XuKong.BP_Monster_XuKong_C'
local S=M..'078_MengHua/Ability/Passive/GA_MengHua_SummonPassive.GA_MengHua_SummonPassive_C'
local PASSIVE=M..'078_MengHua/Ability/Passive/GA_MengHua_XuKong_Passive.GA_MengHua_XuKong_Passive_C'
local EX=M..'079_XuKong/Ability/GA_XuKong_GEx_01.GA_XuKong_GEx_01_C'
local ED=M..'079_XuKong/Ability/GA_XuKong_GEd_01.GA_XuKong_GEd_01_C'
local ENTER=M..'079_XuKong/Ability/GA_XuKong_EnterCombat_02.GA_XuKong_EnterCombat_02_C'
local LOCK=M..'078_MengHua/GameplayEffects/GE_MengHua_XuKong_LockHealth.GE_MengHua_XuKong_LockHealth_C'
local serial=0
local function object(name,class,outer)
    serial=serial+1;local id=serial
    local v={valid=true,full=name,key=id,outer=outer}
    function v:IsValid()return self.valid end
    function v:GetAddress()assert(self.valid);return id end
    function v:GetFullName()assert(self.valid);return self.full end
    function v:GetOuter()assert(self.valid);return self.outer end
    if class then
        local cls=object('BlueprintGeneratedClass '..class)
        function v:GetClass()assert(self.valid);return cls end
    end
    return v
end
local function weak(actor)return {type=function()return 'WeakObjectPtr'end,Get=function()return actor end}end
local function typed(values,deny)
    local data={};for k,v in pairs(values)do data[k]=v end
    return setmetatable({_typed=true,type=function()return 'UScriptStruct'end},{__index=data,__newindex=function(_,key,value)if not deny then data[key]=value end end})
end
local function parameter(values,deny)
    local out={value=typed(values,deny),type=function()return 'RemoteUnrealParam'end,get=function(s)return s.value end}
    function out:set(value)assert(value._typed,'a raw table cannot replace a native struct');if not deny then self.value=value end end
    return out
end
local function harness(team)
    local h={now=0,callbacks={},finds=0,loads=0,destroyed=0,logs={},ready=true}
    h.world=object('World /Map');h.parent=object('BP_Monster_MengHua_C /Map.Parent',P,h.world);h.parent.hp=500
    h.child=object('BP_Monster_XuKong_C /Map.Helper',C,h.world)
    h.board=object('Blackboard /Map.Parent.BB');h.parent.board=h.board
    h.asc=object('AbilitySystemComponent /Map.Parent.ASC');h.parent.AbilitySystemComponent=h.asc;h.asc.lock=1;h.asc.active=1
    function h.asc:GetGameplayEffectCount(cls)assert(cls:IsValid());h.reads=(h.reads or 0)+1;if h.badLock then return nil end;return self.lock end
    function h.asc:GetGameplayTagCount()return self.active end
    h.summon=object('GA_MengHua_SummonPassive_C /Map.Parent.Passive',S,h.parent)
    function h.summon:GetAvatarActorFromActorInfo()return self.parent end;h.summon.parent=h.parent
    function h.summon:DestroySummons(child)h.destroyed=h.destroyed+1;if not h.failDestroy then child.going=true end end
    h.summon.bIsActive=true;function h.summon:K2_CancelAbility()self.bIsActive=false end
    h.nativePhase=object('GA_MengHua_XuKong_Passive_C /Map.Parent.Phase',PASSIVE,h.parent);h.nativePhase.bIsActive=true
    function h.nativePhase:GetAvatarActorFromActorInfo()return h.parent end
    function h.nativePhase:K2_CancelAbility()if not h.failPassiveEnd then self.bIsActive=false;h.asc.lock=0 end end
    function h.child:K2_DestroyActor()h.destroyed=h.destroyed+1;if not h.failDestroy then self.going=true end end
    h.null={IsValid=function()return false end}
    h.ai=object('FunctionLibrary /Script/SGameAI.Default__SGameAIFunctionLibrary')
    function h.ai:GetValueAsObjectByTag(board)if h.badBindingRead then error('unknown board')end;return board.assign end
    function h.ai:SetValueAsObjectByTag(board,tag,value)if not h.failBinding then board.assign=value end end
    h.utils=object('FunctionLibrary /Script/SGameUtils.Default__AbilityUtils')
    function h.utils:SetLooseGameplayTagCount(parent,tag,count)if not h.failTag then parent.AbilitySystemComponent.active=count end end
    h.ge=object('BlueprintGeneratedClass '..LOCK);function h.ge:IsAnyClass()return true end
    h.motionClass=object('Class /Script/MotionWarping.MotionWarpingComponent');function h.motionClass:IsAnyClass()return true end
    function h.child:GetComponentByClass(cls)assert(cls==h.motionClass);return h.motion end
    h.members={{actor=h.parent,team=team or 'blue'}}
    h.options={clock=function()return h.now end,fname=function(s)return s end,createInvalid=function()return h.null end,
        find=function(path)
            h.finds=h.finds+1
            if path==LOCK then return h.ge elseif path:find('Default__SGameAIFunctionLibrary',1,true)then return h.ai
            elseif path:find('Default__AbilityUtils',1,true)then return h.utils end
            if path=='/Script/MotionWarping.MotionWarpingComponent' then return h.motionClass end
            if h.missingHook==path then return nil end
            return object('Function '..path)
        end,
        load=function()h.loads=h.loads+1 end,
        findAll=function(class)if class=='GA_MengHua_XuKong_Passive_C' then return {h.nativePhase} elseif class=='GA_MengHua_SummonPassive_C' then return {h.summon} else return {}end end,
        register=function(path,cb)if h.denyRegister then error('not registered')end;h.callbacks[path]=cb;return serial+1,serial+2 end,
        unregister=function(path)if h.denyUnregister then return false end;h.callbacks[path]=nil;return true end,
        inGameThread=function()return h.gameThread~=false end,ready=function()return h.ready end,
        world=function()return h.world end,boardOf=function(parent)return parent.board end,hp=function(parent)return parent.hp end,
        isDestroying=function(actor)return actor.going==true end,log=function(line)h.logs[#h.logs+1]=line end}
    h.phase=Phase.new(h.options)
    function h:sync()self.phase:syncParents(self.members);if self.callbacks[Phase.paths.passive] then self.callbacks[Phase.paths.passive](self.nativePhase)end end
    function h:spawn(summon,child)self.callbacks[Phase.paths.spawn](summon or self.summon,child or self.child,0,{SummonInfoIndex=0,InstanceIndex=0})end
    function h:lookup(context)return self.callbacks[Phase.paths.lookup](nil,context or self.child,self.parent:GetClass())end
    function h:player(context)return self.callbacks[Phase.paths.player](nil,context or self.child,0)end
    function h:pair(role,helper,parent)
        helper,parent=helper or self.child,parent or self.parent
        local ability=object('GA_XuKong_'..role..'_01_C /Map.Ability.'..role,role=='ex' and EX or ED,parent)
        ability['Execution Info']={Executor=weak(helper),Target=weak(parent)};ability.bIsActive=true
        function ability:GetAvatarActorFromActorInfo()return role=='ex' and helper or parent end
        function ability:K2_CancelAbility()self.bIsActive=false;h.callbacks[Phase.paths[role..'End']](self,true)end
        self.callbacks[Phase.paths[role..'Start']](ability);return ability
    end
    function h:finish(ex,ed)
        ex.bIsActive=false;ed.bIsActive=false;self.asc.lock=0
        self.callbacks[Phase.paths.exEnd](ex,false);self.callbacks[Phase.paths.edEnd](ed,false)
    end
    function h:tick()h.now=h.now+0.5;h.phase:tick()end
    function h:warpSetup(path,half,scale)
        self.position={X=25,Y=-40,Z=700};self.rotation={Pitch=8,Yaw=33,Roll=4}
        local root=object('CapsuleComponent /Map.Helper.Root');self.child.RootComponent=root;self.child.CapsuleComponent=root
        function root:GetOwner()return h.child end
        function root:GetUnscaledCapsuleHalfHeight()return half or 60 end
        function root:K2_GetComponentScale()return typed({X=3,Y=0.5,Z=scale or 1})end
        function self.child:K2_GetActorLocation()return typed(h.position)end
        function self.child:K2_GetActorRotation()return typed(h.rotation)end
        self.motion=object('MotionWarpingComponent /Map.Helper.Motion')
        function self.motion:GetOwner()return h.child end
        function self.motion:AddOrUpdateWarpTargetFromLocationAndRotation(name,position,rotation)
            -- Recursive native hook entry must not consume its own external-frame window.
            h.callbacks[Phase.paths.warp](self,name,position,rotation)
            self.WarpTargets={{Name=name,Location=typed({X=position.X,Y=position.Y,Z=position.Z}),Rotation=typed({Pitch=rotation.Pitch,Yaw=rotation.Yaw,Roll=rotation.Roll})}}
        end
        local ability=object('Ability /Map.Helper.Warp',path or EX,self.child);ability.bIsActive=true
        function ability:GetAvatarActorFromActorInfo()return h.child end
        function ability:K2_CancelAbility()self.bIsActive=false;h.cancelled=(h.cancelled or 0)+1 end
        self.warpAbility=ability
        self.warpLocation=parameter({X=9000,Y=8000,Z=6000})
        self.warpRotation=parameter({Pitch=0,Yaw=170,Roll=0},self.denyRotation)
        self.callbacks[Phase.paths[path==ENTER and 'enterWindow' or 'exWindow']](ability)
        return ability
    end
    function h:warp(name,component)
        self.callbacks[Phase.paths.warp](component or self.motion,name or 'SnapPoint',self.warpLocation,self.warpRotation)
    end
    return h
end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
test('idle does not install hooks, scan or load assets',function()
    local h=harness();h.phase:tick();assert(h.finds==0 and h.loads==0 and h.phase:status().hooks==0)
end)
test('deferred native ownership isolates class lookup before BeginPlay',function()
    local h=harness();h:sync();assert(h.phase:prepare(h.parent));h:spawn()
    assert(h:lookup()==h.parent and h:player()==h.parent and h.phase:busy(h.parent))
    assert(h.phase:handle({parent=h.parent,actor=h.child,mode='Summoner'}));h:tick()
    assert(h.phase:handle({parent=h.parent,actor=h.child}),'pre-finish proof must survive pending summon rows before a mode is listed')
    assert(h.destroyed==0 and h.asc.lock==1,'stage partner and stage lock must survive')
end)
test('map story, manual helper and unrelated ability contexts keep native lookup',function()
    local h=harness();h:sync();h:spawn()
    local outsider=object('BP_Monster_XuKong_C /Map.Manual',C,h.world)
    assert(h:lookup(outsider)==nil and h:player(outsider)==nil)
    local ability=object('GA_Other_C /Map.Other','/Game/GA_Other.GA_Other_C');function ability:GetAvatarActorFromActorInfo()return outsider end
    assert(h:player(ability)==nil)
    assert(not h.phase:handle({parent=outsider,actor=h.child,mode='Summoner'}))
end)
test('helper ability and shared subaction contexts are scoped to their exact avatar',function()
    local h=harness();h:sync();h:spawn()
    local ability=object('GA_XuKong_C /Map.Ability','/Game/GA_XuKong.GA_XuKong_C')
    function ability:GetAvatarActorFromActorInfo()return h.child end
    assert(h:player(ability)==h.parent)
    local action=object('GAA_Shared_C /Map.Action','/Game/GAA_Shared.GAA_Shared_C')
    function action:GetAvatarActor()return h.child end
    assert(h:player(action)==h.parent)
end)
test('multiple owned mothers never exchange their native helper or completion',function()
    local h=harness();local other=harness('red')
    -- Give the second parent/helper the same actual world and use this module's callbacks.
    other.parent.outer=h.world;other.child.outer=h.world
    h.members[2]={actor=other.parent,team='red'};h:sync();h:spawn();h:spawn(other.summon,other.child)
    assert(h:lookup(h.child)==h.parent and h:lookup(other.child)==other.parent)
    local ex,ed=h:pair('ex'),h:pair('ed');h:finish(ex,ed);h:tick()
    assert(h.child.going and not other.child.going and other.asc.lock==1)
    assert(h.phase:busy(other.parent) and not h.phase:busy(h.parent))
end)
test('execution info initialized after activation is still captured by native setter hook',function()
    local h=harness();h:sync();h:spawn()
    local ex=h:pair('ex');local ed=object('GA_XuKong_GEd_01_C /Map.Late',ED,h.parent);ed.bIsActive=true
    function ed:GetAvatarActorFromActorInfo()return h.parent end
    h.callbacks[Phase.paths.edStart](ed)
    local info={Executor=weak(h.child),Target=weak(h.parent)};ed['Execution Info']=info
    h.callbacks[Phase.paths.edInfo](ed,info);h:finish(ex,ed);h:tick();assert(h.child.going)
end)
test('normal pair ends and native lock zero before helper cleanup',function()
    local h=harness();h:sync();h:spawn();h.board.assign=h.child
    local ex,ed=h:pair('ex'),h:pair('ed');h:tick();assert(h.destroyed==0)
    h:finish(ex,ed);h:tick()
    assert(h.destroyed==1 and h.child.going and h.asc.active==0 and not h.board.assign:IsValid())
    assert(not h.phase:busy(h.parent) and h.asc.lock==0)
end)
test('unresolved lock is never deleted or bypassed by time',function()
    local h=harness();h:sync();h:spawn();local ex,ed=h:pair('ex'),h:pair('ed')
    ex.bIsActive=false;ed.bIsActive=false;h.callbacks[Phase.paths.edEnd](ed,false)
    for _=1,120 do h:tick()end
    assert(h.destroyed==0 and h.asc.lock==1 and h.phase:busy(h.parent))
end)
test('unknown lock readback does not retire a phase',function()
    local h=harness();h:sync();h:spawn();local ex,ed=h:pair('ex'),h:pair('ed');h:finish(ex,ed);h.badLock=true;h:tick();assert(h.destroyed==0)
end)
test('wrong execution counterpart is never accepted as a completed pair',function()
    local h=harness();h:sync();h:spawn();local other=object('Other /Map.Other',P,h.world)
    local ed=h:pair('ed',h.child,other);ed.bIsActive=false;h.asc.lock=0;h.callbacks[Phase.paths.edEnd](ed,false);h:tick()
    assert(h.destroyed==0 and h.phase:busy(h.parent))
end)
test('late helper without pre-finish proof is preserved and quarantined',function()
    local h=harness();h:sync();assert(h.phase:handle({parent=h.parent,actor=h.child,mode='Summoner'}))
    assert(h:lookup()==h.null and h:player()==h.null);h:tick();assert(h.destroyed==0 and h.phase:status().failures>0)
end)
test('retired helper lookup tombstones cannot fall through to a map boss',function()
    local h=harness();h:sync();h:spawn();local ex,ed=h:pair('ex'),h:pair('ed');h:finish(ex,ed);h:tick()
    assert(h:lookup()==h.null and h:player()==h.null,'destroying but still valid actor must remain isolated')
end)
test('stop and parent destruction require helper cleanup readback',function()
    local h=harness();h:sync();h:spawn();h.board.assign=h.child;h.failDestroy=true
    assert(not h.phase:releaseActor(h.parent));assert(not h.child.going)
    h.failDestroy=false;assert(h.phase:releaseActor(h.parent) and h.child.going)
end)
test('battle cleanup leaves companion phase alone',function()
    local h=harness('companion');h:sync();h:spawn();assert(h.phase:stop());assert(h.destroyed==0)
    assert(h.phase:stop({companion=true}));assert(h.child.going)
end)
test('all four direct summon teams are scoped while automatic summons are excluded',function()
    for _,team in ipairs({'blue','red','neutral','companion'})do local h=harness(team);h:sync();h:spawn();assert(h:lookup()==h.parent,team)end
    local h=harness();h.members[1].summoner=object('Native /Map.Summoner');h:sync();assert(h.phase:status().parents==0 and h.finds==0)
end)
test('target binding changed by native logic is not overwritten on cleanup',function()
    local h=harness();h:sync();h:spawn();local other=object('Other /Map.Target',C,h.world);h.board.assign=other
    local ex,ed=h:pair('ex'),h:pair('ed');h:finish(ex,ed);h:tick();assert(h.board.assign==other and h.child.going)
end)
test('failed binding readback retains cleanup rather than claiming completion',function()
    local h=harness();h:sync();h:spawn();h.badBindingRead=true;assert(not h.phase:releaseActor(h.parent) and not h.child.going)
end)
test('failed hook or invalid null return is not reported as ready',function()
    local h=harness();h.denyRegister=true;h:sync();assert(not h.phase:prepare(h.parent))
    h=harness();h.options.createInvalid=function()return object('Actor /Map.Real')end;h.phase=Phase.new(h.options);h:sync();assert(not h.phase:prepare(h.parent))
end)
test('non-game-thread callback and invalid objects make no native edits',function()
    local h=harness();h:sync();h.gameThread=false;h:spawn();assert(h.phase:status().helpers==0)
    h.gameThread=true;h.parent.valid=false;h:spawn();assert(h.phase:status().helpers==0)
end)
test('unload silences callbacks even when unregister fails',function()
    local h=harness();h:sync();h:spawn();local lookup=h.callbacks[Phase.paths.lookup];h.denyUnregister=true
    h.phase:silence();assert(lookup(nil,h.child,h.parent:GetClass())==nil)
end)
test('GEx anchor preserves actual actor centre for small large and nonuniform scale',function()
    for _,shape in ipairs({{40,0.5},{60,1},{120,3}})do
        local h=harness();h:sync();h:spawn();h:warpSetup(EX,shape[1],shape[2]);h:warp()
        local p,r=h.warpLocation.value,h.warpRotation.value
        assert(p.X==h.position.X and p.Y==h.position.Y and p.Z+shape[1]*shape[2]+2==h.position.Z)
        assert(r.Yaw==h.rotation.Yaw and r.Pitch==0 and r.Roll==0)
        assert(h.phase:status().anchors==1 and h.cancelled==nil)
    end
end)
test('EnterCombat02 uses the same local floor anchor and a single window',function()
    local h=harness();h:sync();h:spawn();h:warpSetup(ENTER);h:warp();assert(h.warpLocation.value.X==25)
    h.warpLocation=parameter({X=999,Y=999,Z=999});h:warp();assert(h.warpLocation.value.X==999,'one window owns one write')
end)
test('missing scene marker still has a verified local target without an outer write',function()
    local h=harness();h:sync();h:spawn();h:warpSetup(EX,120,0.4)
    local target=h.motion.WarpTargets[1]
    assert(target.Name=='SnapPoint' and target.Location.X==25 and target.Location.Z+120*0.4+2==700)
    assert(target.Rotation.Yaw==33 and h.warpLocation.value.X==9000,'preseed must not consume the external parameter window')
    h:warp();assert(h.warpLocation.value.X==25)
end)
test('ready deferred components receive a private anchor before helper BeginPlay',function()
    local h=harness();h:sync();h:warpSetup(EX);assert(h.motion.WarpTargets==nil)
    h:spawn();local target=h.motion.WarpTargets[1]
    assert(target.Location.X==25 and target.Location.Z+60+2==700)
    assert(h.phase:status().anchors==0,'deferred preseed is not a parameter interception')
end)
test('unknown late binding cannot clear an unrelated active-stage marker',function()
    local h=harness();h:sync();h.phase:handle({parent=h.parent,actor=h.child,mode='Summoner'})
    h.nativePhase.valid=false;h.options.findAll=function()return {}end;h.asc.lock=0
    h.board.assign=object('Other /Map.OtherBinding',C,h.world)
    assert(not h.phase:releaseActor(h.parent))
    assert(h.asc.active==1 and not h.child.going)
end)
test('explicit cancelled GEx with zero native lock can retire without a GEd instance',function()
    local h=harness();h:sync();h:spawn();local ex=h:pair('ex');h.asc.lock=0;ex:K2_CancelAbility();h:tick()
    assert(h.child.going and not h.phase:busy(h.parent))
end)
test('unknown active flag aborts the known scope instead of silently accepting a scene anchor',function()
    local h=harness();h:sync();h:spawn();h:warpSetup(EX);h.warpAbility.bIsActive=nil;h:warp()
    assert(h.warpAbility.bIsActive==false and h.phase:status().failures>0 and h.phase:status().anchors==0)
end)
test('outer post closes the scoped window before a later Skill04 write',function()
    local h=harness();h:sync();h:spawn();local ability=h:warpSetup(ENTER)
    h.callbacks[Phase.paths.enterClose](ability);h:warp();assert(h.warpLocation.value.X==9000)
end)
test('nested Skill04 preserves its landing then restores the active outer GEx window',function()
    local h=harness();h:sync();h:spawn();h:warpSetup(EX)
    local skill=object('GA_XuKong_Skill_04_C /Map.Helper.Skill',M..'079_XuKong/Ability/GA_XuKong_Skill_04.GA_XuKong_Skill_04_C')
    skill.bIsActive=true
    function skill:GetAvatarActorFromActorInfo()return h.child end
    h.callbacks[Phase.paths.enterWindow](skill);h:warp();assert(h.warpLocation.value.X==9000)
    h.callbacks[Phase.paths.skill4Close](skill);h:warp();assert(h.warpLocation.value.X==25 and h.warpAbility.bIsActive)
end)
test('matching owner without an exact ability window and outside owners remain unchanged',function()
    local h=harness();h:sync();h:spawn();h:warpSetup(EX)
    local outside=object('MotionWarpingComponent /Map.Outside');function outside:GetOwner()return h.parent end
    h:warp(nil,outside);assert(h.warpLocation.value.X==9000)
    h:warp('OtherTarget');assert(h.warpLocation.value.X==9000)
    h:warp();assert(h.warpLocation.value.X==25)
end)
test('slow but valid synchronous K2 window does not permit the stale scene marker',function()
    local h=harness();h:sync();h:spawn();h:warpSetup(EX);h.now=0.2;h:warp();assert(h.warpLocation.value.X==25 and h.cancelled==nil)
end)
test('expired old window aborts only its action instead of writing the stale marker as success',function()
    local h=harness();h:sync();h:spawn();h:warpSetup(EX);h.now=6;h:warp()
    assert(h.warpAbility.bIsActive==false and h.warpLocation.value.X==9000 and h.phase:status().failures>0)
end)
test('half-written typed inputs are rolled back and the scoped action is cancelled',function()
    local h=harness();h:sync();h:spawn();h.denyRotation=true;h:warpSetup(EX);h:warp()
    assert(h.warpLocation.value.X==9000 and h.warpRotation.value.Yaw==170)
    assert(h.cancelled==1 and not h.warpAbility.bIsActive and h.phase:status().anchors==0)
end)
test('unload before GEd exists restores companion lock by the original passive End',function()
    local h=harness('companion');h:sync();h:spawn();assert(h.asc.lock==1)
    h.phase:silence();assert(h.asc.lock==0 and not h.nativePhase.bIsActive and h.child.going)
end)
test('unconfirmed original passive End is never hidden by helper destruction',function()
    local h=harness('companion');h:sync();h:spawn();h.failPassiveEnd=true
    assert(not h.phase:releaseActor(h.parent));assert(h.asc.lock==1 and not h.child.going)
end)
print('menghua_phase: '..tests..' checks passed')
