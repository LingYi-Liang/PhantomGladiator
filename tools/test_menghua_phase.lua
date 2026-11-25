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
local ACTIVE='CharacterState.AbilityState.MengHua.XuKong.Active'
local INIT='CharacterState.AbilityState.MengHua.InitCA'
local CAN_SUMMON='CharacterState.AbilityState.MengHua.CanSummonXuKong'
local CA=M..'078_MengHua/GameplayEffects/GE_MengHua_XuKong_CA.GE_MengHua_XuKong_CA_C'
local TIMER=M..'078_MengHua/GameplayEffects/GE_MengHua_XuKong_Timer.GE_MengHua_XuKong_Timer_C'
local SEQ=M..'078_MengHua/GameplayEffects/GE_MengHua_SeqCA.GE_MengHua_SeqCA_C'
local SEQ_TAG='CharacterState.AbilityState.MengHua.SeqCA'
local CAN_USE='CharacterState.AbilityState.MengHua.CanUseCA'
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
    h.parentClass=h.parent:GetClass()
    h.child=object('BP_Monster_XuKong_C /Map.Helper',C,h.world)
    h.board=object('Blackboard /Map.Parent.BB');h.parent.board=h.board
    h.asc=object('AbilitySystemComponent /Map.Parent.ASC');h.parent.AbilitySystemComponent=h.asc;h.asc.lock=1;h.asc.active=1
    function h.asc:GetGameplayEffectCount(cls)assert(cls:IsValid());h.reads=(h.reads or 0)+1;if h.badLock then return nil end;return self.lock end
    h.asc.tags={}
    function h.asc:GetGameplayTagCount(tag)
        if tag.TagName==ACTIVE then return self.active end
        return self.tags[tag.TagName] or 0
    end
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
    function h.utils:SetLooseGameplayTagCount(parent,tag,count)
        if not h.failTag then
            if tag.TagName==ACTIVE then parent.AbilitySystemComponent.active=count
            else parent.AbilitySystemComponent.tags[tag.TagName]=count end
        end
    end
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
        isDestroying=function(actor)return actor.going==true end,log=function(line)h.logs[#h.logs+1]=line end,
        rule=function()return h.rule or 'keep'end}
    h.phase=Phase.new(h.options)
    function h:sync()self.phase:syncParents(self.members);if self.callbacks[Phase.paths.passive] then self.callbacks[Phase.paths.passive](self.nativePhase)end end
    function h:spawn(summon,child)self.callbacks[Phase.paths.spawn](summon or self.summon,child or self.child,0,{SummonInfoIndex=0,InstanceIndex=0})end
    function h:lookup(context)return self.callbacks[Phase.paths.lookup](nil,context or self.child,self.parentClass)end
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
    function h:story(index,world)
        world=world or self.world
        local parent=object('BP_Monster_MengHua_C /Map.StoryMother_'..index,P,world)
        parent.hp=900;parent.lock=1;parent.active=1
        local child=object('BP_Monster_XuKong_C /Map.StoryHelper_'..index,C,world)
        local passive=object('GA_MengHua_SummonPassive_C /Map.StoryPassive_'..index,S,parent)
        function passive:GetAvatarActorFromActorInfo()return parent end
        function passive:K2_CancelAbility()error('story passive must not be cancelled')end
        function child:K2_DestroyActor()error('story actor must not be destroyed')end
        self.callbacks[Phase.paths.spawn](passive,child,0,{SummonInfoIndex=0,InstanceIndex=0})
        return parent,child,passive
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
test('streamed-in story mother after an owned mother keeps her actual native source',function()
    local h=harness();h:sync();h:spawn()
    local mapParent,mapChild=h:story(1)
    local nativeFirstOfClass=h.parent -- the earlier mod actor would otherwise win the vanilla class query
    local override=h:lookup(mapChild)
    assert((override or nativeFirstOfClass)==mapParent)
    assert(h:player(mapChild)==nil,'story GetPlayerCharacter must still resolve the real player')
    assert(h.phase:status().parents==1 and h.phase:status().helpers==1 and h.phase:status().storyGuards==1)
    assert(not h.phase:busy(mapParent) and not h.phase:busy(mapChild))
end)
test('several story and owned groups remain isolated from manual actors',function()
    local h=harness();h:sync();h:spawn()
    local p1,c1=h:story(1);local p2,c2=h:story(2)
    local manual=object('BP_Monster_XuKong_C /Map.ManualExtra',C,h.world)
    assert(h:lookup()==h.parent and h:lookup(c1)==p1 and h:lookup(c2)==p2)
    assert(h:lookup(manual)==nil and h:player(c1)==nil and h:player(c2)==nil)
    local ability=object('GA_XuKong_Ability_C /Map.StoryAbility',EX,c1)
    function ability:GetAvatarActorFromActorInfo()return c1 end
    assert(h:lookup(ability)==p1 and h:player(ability)==nil)
end)
test('story binding survives loss of all owned units until the actual helper becomes invalid',function()
    local h=harness();h:sync();local parent,child=h:story(1)
    h.parent.valid=false;h.members={};h.phase:syncParents({});h:tick();h:tick()
    assert(h.phase:status().parents==0 and h.phase:status().helpers==0 and h.phase:status().storyGuards==1)
    assert(h.phase:status().hooks==1 and h:lookup(child)==parent,'only the source lookup guard remains installed')
    child.going=true;h:tick();assert(h:lookup(child)==parent,'destroying but valid story helper still needs its delayed OnDead source')
    child.valid=false;h:tick();h:tick();assert(h.phase:status().storyGuards==0 and h.phase:status().hooks==0)
end)
test('invalid or changed story source returns safe null without selecting another mother',function()
    local h=harness();h:sync();local parent,child=h:story(1)
    parent.valid=false;assert(h:lookup(child)==h.null)
    parent.valid=true;parent.full='BP_Monster_MengHua_C /Map.ReusedDifferent';assert(h:lookup(child)==h.null)
end)
test('story stages player getter anchor and cleanup are all untouched',function()
    local h=harness();h:sync();local parent,child=h:story(1)
    local link={parent=parent,actor=child,mode='Summoner'}
    assert(not h.phase:handle(link) and h.phase:releaseActor(parent))
    local ability=object('GA_XuKong_GEx_01_C /Map.StoryGEx',EX,child);ability.bIsActive=true
    function ability:GetAvatarActorFromActorInfo()return child end
    h.callbacks[Phase.paths.exWindow](ability)
    local component=object('MotionWarpingComponent /Map.StoryHelperMotion');function component:GetOwner()return child end
    local position=parameter({X=100,Y=200,Z=300});local rotation=parameter({Pitch=1,Yaw=2,Roll=3})
    h.callbacks[Phase.paths.warp](component,'SnapPoint',position,rotation)
    assert(position.value.X==100 and position.value.Z==300 and rotation.value.Yaw==2)
    assert(h:player(child)==nil and not h.phase:busy(parent))
    h.phase:stop();assert(parent.lock==1 and parent.active==1 and parent.hp==900)
    h.phase:silence();assert(parent.valid and child.valid and parent.lock==1 and parent.active==1)
end)
test('story source observation rejects another world and never starts hooks without owned actors',function()
    local h=harness();h.members={};h.phase:syncParents({});h:tick()
    assert(h.phase:status().hooks==0 and h.finds==0 and h.callbacks[Phase.paths.spawn]==nil)
    h=harness();h:sync();local parent,child=h:story(1,object('World /OtherMap'))
    assert(h.phase:status().storyGuards==0 and h:lookup(child)==nil)
end)
test('skip is opt in and birth frozen, keeping the original choice leaves the stage intact',function()
    local h=harness();h:sync();h.rule='skip';h.phase:syncParents(h.members);h:tick()
    assert(h.nativePhase.bIsActive and h.summon.bIsActive and h.asc.lock==1,'a later click does not alter a living native-stage actor')
    assert(h.phase:status().skip_supported==true)
end)
test('skip ends only native linked passives, verifies zero lock and clears linked tags without changing HP',function()
    for _,team in ipairs({'blue','red','neutral','companion'})do
        local h=harness(team);h.rule='skip';h.asc.tags[INIT]=1;h.asc.tags[CAN_SUMMON]=1
        h.asc.tags['CharacterState.AbilityState.MengHua.P2']=1
        h:sync();assert(not h.nativePhase.bIsActive and h.asc.lock==0)
        h:tick();assert(not h.summon.bIsActive and h.asc.lock==0 and h.asc.active==0)
        assert(h.asc.tags[INIT]==0 and h.asc.tags[CAN_SUMMON]==0 and h.parent.hp==500)
        assert(h.asc.tags['CharacterState.AbilityState.MengHua.P2']==1,'do not invent or erase an unrelated phase flag')
        assert(not h.phase:busy(h.parent),'normal battle may proceed only after the bypass is verified')
        local reads=h.reads;h:tick();assert(h.reads==reads,'a completed bypass must not poll native stats every tick')
    end
end)
test('skip retires a late native helper and does not seed or bind it to the mother',function()
    local h=harness();h.rule='skip';h:sync();h:tick();assert(not h.phase:busy(h.parent))
    h:spawn();assert(h.phase:busy(h.parent) and h:lookup()==h.null and h:player()==h.null)
    assert(h.phase:status().anchors==0 and not h.motion,'do not run the skipped phase movement')
    h:tick();assert(h.child.going and h.phase:status().helpers==0 and not h.phase:busy(h.parent))
end)
test('skip clears only a helper counterpart and preserves another chosen target',function()
    local h=harness();h.rule='skip';h:sync();h:spawn();h.board.assign=h.child;h:tick();assert(h.board.assign==h.null)
    h=harness();h.rule='skip';h:sync();h:spawn();local enemy=object('Pawn /Map.OtherTarget',P,h.world);h.board.assign=enemy
    h:tick();assert(h.board.assign==enemy and h.child.going)
end)
test('skip retries rejected passive End and does not claim the actor is ready',function()
    local h=harness();h.rule='skip';h.failPassiveEnd=true;h:sync();h:spawn();h:tick()
    assert(h.asc.lock==1 and h.phase:busy(h.parent) and h.phase:status().state=='pending' and not h.child.going)
    h.failPassiveEnd=false;h:tick();assert(h.asc.lock==0 and h.child.going and not h.phase:busy(h.parent))
end)
test('skip does not hide tag write failure after the original passive has ended',function()
    local h=harness();h.rule='skip';h.asc.tags[INIT]=1;h.failTag=true;h:sync();h:tick()
    assert(h.asc.lock==0 and h.asc.tags[INIT]==1 and h.phase:busy(h.parent) and h.phase:status().state=='pending')
    h.failTag=false;h:tick();assert(h.asc.tags[INIT]==0 and not h.phase:busy(h.parent))
end)
test('skip clears the native permission effect when cancelling its passive leaves the tag granted',function()
    local h=harness();h.rule='skip'
    local permission=object('BlueprintGeneratedClass '..CA)
    function permission:IsAnyClass()return true end
    local find=h.options.find
    h.options.find=function(path)return path==CA and permission or find(path) end
    h.phase=Phase.new(h.options)
    h.asc.otherFloor=123
    h.asc.tags[CAN_SUMMON]=1
    h.permissionCount=1
    local read=h.asc.GetGameplayEffectCount
    function h.asc:GetGameplayEffectCount(cls,...)
        if cls==permission then return h.permissionCount end
        return read(self,cls,...)
    end
    function h.asc:GetOwner()return h.parent end
    local tagRead=h.asc.GetGameplayTagCount
    function h.asc:GetGameplayTagCount(tag)
        local count=tagRead(self,tag)
        if tag.TagName==CAN_SUMMON then return count+h.permissionCount+(h.otherGrant or 0) end
        return count
    end
    function h.asc:RemoveActiveGameplayEffectBySourceEffect(cls,instigator,stacks)
        assert(cls==permission and instigator==nil and stacks==-1)
        h.removals=(h.removals or 0)+1
        if not h.failRemove then h.permissionCount=0 end
    end
    h.failRemove=true;h:sync();h:tick()
    assert(h.asc.lock==0 and h.asc.tags[CAN_SUMMON]==0 and h.permissionCount==1 and h.phase:busy(h.parent))
    assert(h.removals==1,'native permission can remain after the loose tag is gone')
    h.failRemove=false;h.otherGrant=1;h:tick()
    assert(h.removals==2 and h.permissionCount==0 and h.phase:busy(h.parent),'an unrelated permission source stays active')
    h.otherGrant=0;h:tick()
    assert(not h.phase:busy(h.parent) and h.asc.otherFloor==123 and h.parent.hp==500)
end)
test('skip prevents later reactivation of the exact linked native passives',function()
    local h=harness();h.rule='skip';h:sync();h:tick()
    h.nativePhase.bIsActive=true;h.asc.lock=1;h.callbacks[Phase.paths.passive](h.nativePhase)
    h.summon.bIsActive=true;h.callbacks[Phase.paths.summonPassive](h.summon)
    assert(not h.nativePhase.bIsActive and not h.summon.bIsActive and h.phase:busy(h.parent))
    h:tick();assert(h.asc.lock==0 and not h.phase:busy(h.parent))
end)
test('confirmed End survives the native passive dropping its avatar or being collected',function()
    for _,collected in ipairs({false,true})do
        local h=harness();h.rule='skip'
        for _,ability in ipairs({h.nativePhase,h.summon})do
            ability.GetAvatarActorFromActorInfo=function(self)if self.bIsActive then return h.parent end end
        end
        h:sync();h.callbacks[Phase.paths.summonPassive](h.summon)
        assert(not h.nativePhase.bIsActive and not h.summon.bIsActive)
        if collected then h.nativePhase.valid=false;h.summon.valid=false end
        h:tick()
        assert(not h.phase:busy(h.parent) and h.phase:status().state=='ready','acknowledged Ends must release the combat gate')
    end
end)
test('owned ASC spec distinguishes an inactive passive from a still-active unresolved instance',function()
    local h=harness();h.rule='skip';h:sync()
    h.asc.GetOwner=function()return h.parent end
    local spec={Ability=object('CDO /Summon',S),ActiveCount=1};h.asc.ActivatableAbilities={Items={spec}}
    h.summon.valid=false;h:tick();assert(h.phase:busy(h.parent))
    spec.ActiveCount=0;h:tick();assert(not h.phase:busy(h.parent))
end)
test('skip unknown lock or absent passive evidence remains pending instead of claiming ready',function()
    local h=harness();h.rule='skip';h.badLock=true;h:sync();h:tick()
    assert(h.phase:busy(h.parent) and h.phase:status().state=='pending')
    h.badLock=false;h:tick();assert(not h.phase:busy(h.parent))
    h=harness();h.rule='skip';h.nativePhase.valid=false;h.summon.valid=false;h.asc.lock=0
    h.options.findAll=function()error('unconfirmed native ability read')end
    h:sync();h:tick();assert(h.phase:busy(h.parent) and h.phase:status().state=='pending')
end)
test('skip cannot hide a helper destruction failure or change another health floor',function()
    local h=harness();h.rule='skip';h.asc.otherFloor=123;h:sync();h:spawn();h.failDestroy=true;h:tick()
    assert(h.phase:busy(h.parent) and not h.child.going and h.asc.otherFloor==123)
    h.failDestroy=false;h:tick();assert(h.child.going and not h.phase:busy(h.parent) and h.asc.otherFloor==123)
end)
test('native summon End may already invalidate the helper before bypass cleanup',function()
    local h=harness();h.rule='skip';h:sync();h:spawn();h.board.assign=h.child
    local invalidCalls=0
    function h.summon:K2_CancelAbility()self.bIsActive=false;h.child.valid=false end
    function h.summon:DestroySummons(child)if not child:IsValid()then invalidCalls=invalidCalls+1;error('invalid native argument')end end
    h:tick();assert(invalidCalls==0 and h.board.assign==h.null and h.phase:status().helpers==0 and not h.phase:busy(h.parent))
end)
test('skip rule never pauses or cancels story source actors',function()
    local h=harness();h.rule='skip';h:sync();local parent,child,summon=h:story(9)
    summon.bIsActive=true;local cancelled=false;summon.K2_CancelAbility=function()cancelled=true end
    h.callbacks[Phase.paths.summonPassive](summon);h:tick()
    assert(not cancelled and not child.going and not h.phase:busy(parent) and h:lookup(child)==parent)
    assert(h:player(child)==nil,'a real story helper continues to query the real player')
end)
local function stalledPhase(team)
    local h=harness(team)
    local event='GameplayEvent.SelfSummon.MengHua'
    local library=object('Library /Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
    local find=h.options.find
    h.effects={}
    for _,path in ipairs({CA,TIMER,SEQ})do
        local class=object('BlueprintGeneratedClass '..path)
        function class:IsAnyClass()return true end
        h.effects[path]=class
    end
    h.effectsCount={[CA]=0,[TIMER]=0,[SEQ]=0}
    local oldCount=h.asc.GetGameplayEffectCount
    function h.asc:GetGameplayEffectCount(class)
        for path,effect in pairs(h.effects)do
            if class==effect then return h.effectsCount[path] end
        end
        return oldCount(self,class)
    end
    function h.asc:BP_ApplyGameplayEffectToSelf(class,level,context)
        assert(class==h.effects[CA] and level==0 and type(context)=='table')
        h.appliedPermission=(h.appliedPermission or 0)+1
        if not h.rejectPermission then h.effectsCount[CA]=1;h.asc.tags[CAN_SUMMON]=1 end
    end
    function h.nativePhase:TryTriggerXuKongByHealth()
        h.phaseReplay=(h.phaseReplay or 0)+1
        if h.effectsCount[TIMER]==1 then
            h.effectsCount[TIMER]=0;h.effectsCount[CA]=1;h.asc.tags[CAN_SUMMON]=1
        end
    end
    h.options.find=function(path)
        if path=='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary' then return library end
        return h.effects[path] or find(path)
    end
    local foe=object('Enemy /Map.Enemy',nil,h.world);foe.hp=100;foe.Mesh=object('Mesh')
    h.opponent=foe;h.pending=0;h.actionIdle=true;h.sent=0
    h.options.opponent=function(_,side)
        assert(side==team or team==nil and side=='blue')
        return h.opponent
    end
    h.options.canRequest=function()return h.actionIdle end
    h.options.gameTime=function()return h.now end
    h.options.attributes={read=function(_,a,k)
        assert(a==h.parent)
        return {current=k=='Health_Max' and 725100 or h.floor}
    end}
    h.floor=297291;h.parent.hp=h.floor
    h.asc.active=0
    h.asc.tags[CAN_SUMMON]=1;h.asc.tags['AI.State.Combat']=1
    function h.asc:GetOwner()return h.parent end
    h.summon.SummonEventTag={TagName=event};h.summon.MaxSummonCount=1;h.summon.SpawnedSummonInstances={}
    function h.ai:GetPendingSummonCount(ability)assert(ability==h.summon);return h.pending end
    function library:SendGameplayEventToActor(actor,tag,payload)
        assert(actor==h.parent and tag.TagName==event and payload.EventTag.TagName==event and payload.EventMagnitude==1)
        h.sent=h.sent+1
        h.spawnTarget=h:player(h.summon)
        if not h.rejectSummon then
            h:spawn();h.board.assign=h.child;h.asc.active=1
            h.summon.SpawnedSummonInstances={{Pawn=h.child,bPawnPending=false}}
        end
    end
    h.phase=Phase.new(h.options);h:sync()
    return h
end

test('stalled 41% phase requests the original summon event when the native window is open',function()
    local h=stalledPhase()
    for _=1,12 do h:tick()end
    assert(h.sent==0,'give the original transition a chance')
    h.actionIdle=false
    for _=1,30 do h:tick()end
    assert(h.sent==0,'never start while a native grab or other action is active')
    h.actionIdle=true;h:tick()
    assert(h.sent==1 and h.phase:busy(h.parent) and h.asc.lock==1)
    for _=1,30 do h:tick()end
    assert(h.sent==1 and not h.child.going,'a native helper blocks duplicate requests')
    local ex,ed=h:pair('ex'),h:pair('ed');h:finish(ex,ed);h:tick()
    assert(h.child.going and h.asc.lock==0 and not h.phase:busy(h.parent))
end)
test('native summon recovery waits for verified state and retries only twice',function()
    local h=stalledPhase('red');h.rejectSummon=true
    h.asc.tags[CAN_SUMMON]=0;h.nativePhase.bIsActive=false
    for _=1,40 do h:tick()end
    assert(h.sent==0,'without an active stage passive the missing permission must not be renewed')
    h.nativePhase.bIsActive=true;h.asc.tags[CAN_SUMMON]=1;h.pending=1
    for _=1,40 do h:tick()end
    assert(h.sent==0)
    h.pending=0;h.summon.SpawnedSummonInstances={{bPawnPending=true}}
    for _=1,40 do h:tick()end
    assert(h.sent==0)
    h.summon.SpawnedSummonInstances={}
    for _=1,160 do h:tick()end
    assert(h.sent==2 and h.asc.lock==1 and h.parent.hp==297291)
    local neutral=stalledPhase('neutral')
    for _=1,50 do neutral:tick()end
    assert(neutral.sent==0)
end)
test('companion can recover the same native 41% phase against a confirmed foe',function()
    local h=stalledPhase('companion')
    local foe=h.opponent
    h.opponent=nil
    for _=1,24 do h:tick()end
    assert(h.sent==0)
    foe.outer=object('World /Other')
    h.opponent=foe
    for _=1,24 do h:tick()end
    assert(h.sent==0)
    foe.outer=h.world
    for _=1,24 do h:tick()end
    assert(h.sent==1 and h.phase:busy(h.parent))
    assert(h:lookup()==h.parent)
end)
test('no fallback during a native transition or without the original phase lock',function()
    local h=stalledPhase()
    for _=1,6 do h:tick()end
    h:spawn()
    for _=1,200 do h:tick()end
    assert(h.sent==0 and h.phase:busy(h.parent))

    local unrelated=stalledPhase()
    unrelated.asc.lock=0
    for _=1,40 do unrelated:tick()end
    assert(unrelated.sent==0)
    unrelated.asc.lock=1
    unrelated.asc.tags['CharacterState.AbilityState.MengHua.CanEnterP2']=1
    for _=1,40 do unrelated:tick()end
    assert(unrelated.sent==0)
    unrelated.phase:syncParents({})
    unrelated.asc.tags['CharacterState.AbilityState.MengHua.CanEnterP2']=0
    for _=1,40 do unrelated:tick()end
    assert(unrelated.sent==0)
end)
test('an interrupted native sequence with consumed permission still completes its summon',function()
    local h=stalledPhase('red')
    h.asc.tags[CAN_SUMMON]=0;h.asc.tags[SEQ_TAG]=1;h.asc.tags[CAN_USE]=1
    h.effectsCount[SEQ]=1
    for _=1,24 do h:tick()end
    assert(h.sent==1 and h.asc.lock==1 and h.phase:busy(h.parent))
    assert(not h.appliedPermission and not h.phaseReplay,'do not renew permission for an already consumed sequence')
    assert(h.spawnTarget==h.opponent and h:player(h.summon)==nil,'only the original summon request uses the verified opponent as anchor')
end)
test('only the exact native completion receipt can retry an interrupted sequence',function()
    for _,mode in ipairs({'noEffect','noNormalCA','phase2','busy','pending','live'})do
        local h=stalledPhase()
        h.asc.tags[CAN_SUMMON]=0;h.asc.tags[SEQ_TAG]=1;h.asc.tags[CAN_USE]=1;h.effectsCount[SEQ]=1
        if mode=='noEffect' then h.effectsCount[SEQ]=0
        elseif mode=='noNormalCA' then h.asc.tags[CAN_USE]=0
        elseif mode=='phase2' then h.asc.tags['CharacterState.AbilityState.MengHua.P2']=1
        elseif mode=='busy' then h.actionIdle=false
        elseif mode=='pending' then h.pending=1
        elseif mode=='live' then
            h.child.hp=100;h.summon.SpawnedSummonInstances={{Pawn=h.child,bPawnPending=false}}
        end
        for _=1,28 do h:tick()end
        assert(h.sent==0 and not h.appliedPermission,mode)
    end
end)
test('missing permission uses the original health check or its own native effect',function()
    for _,timer in ipairs({0,1})do
        local h=stalledPhase()
        h.asc.tags[CAN_SUMMON]=0;h.effectsCount[TIMER]=timer
        for _=1,42 do h:tick()end
        assert(h.phaseReplay==1 and h.sent==1 and h.asc.lock==1)
        assert((h.appliedPermission or 0)==1-timer)
    end
    local rejected=stalledPhase();rejected.asc.tags[CAN_SUMMON]=0;rejected.rejectPermission=true
    for _=1,80 do rejected:tick()end
    assert(rejected.phaseReplay==1 and rejected.appliedPermission==1 and rejected.sent==0)
end)
test('native helper lost before pairing can retry from a proven nonpending dead slot',function()
    local h=stalledPhase()
    for _=1,24 do h:tick()end
    assert(h.sent==1)
    h.child.valid=false;h.asc.active=0;h.board.assign=h.null;h.rejectSummon=true
    for _=1,32 do h:tick()end
    assert(h.sent==2 and h.asc.lock==1)
    for _=1,80 do h:tick()end
    assert(h.sent==2)
end)
test('a helper with native pair receipts is never treated as a failed initial spawn',function()
    local h=stalledPhase()
    for _=1,24 do h:tick()end
    assert(h.sent==1)
    h:pair('ex')
    h.child.valid=false;h.asc.active=0;h.board.assign=h.null;h.summon.SpawnedSummonInstances={}
    for _=1,80 do h:tick()end
    assert(h.sent==1 and h.asc.lock==1)
end)
test('a stalled phase can find a brief idle window between one second samples',function()
    local h=stalledPhase()
    for i=1,28 do
        h.actionIdle=i%2==0
        h:tick()
    end
    assert(h.sent==1)
end)
test('the original off-combat reset begins a new limited recovery encounter',function()
    local h=stalledPhase('companion');h.rejectSummon=true
    h.asc.tags[CAN_SUMMON]=0
    for _=1,64 do h:tick()end
    assert(h.sent==2 and h.phaseReplay==1)
    local function offCombat(nativeReset,transition)
        h.asc.tags['AI.State.Combat']=0
        h.asc.tags['CharacterState.OffCombat']=nativeReset and 1 or 0
        h.asc.tags['CharacterState.AbilityState.MengHua.P2']=transition and 1 or 0
        h.asc.tags[CAN_SUMMON]=0;h.asc.lock=0;h.effectsCount[CA]=0
        for _=1,4 do h:tick()end
        h.asc.tags['CharacterState.OffCombat']=0
        h.asc.tags['CharacterState.AbilityState.MengHua.P2']=0
        h.asc.tags['AI.State.Combat']=1;h.asc.lock=1
    end
    offCombat(false,false)
    for _=1,38 do h:tick()end
    assert(h.sent==2 and h.phaseReplay==1,'a missing Combat tag alone is not a new encounter')
    offCombat(true,true)
    for _=1,38 do h:tick()end
    assert(h.sent==2 and h.phaseReplay==1,'a remaining P2 blocks the reset')
    offCombat(true,false)
    for _=1,64 do h:tick()end
    assert(h.sent==4 and h.phaseReplay==2,'only the proven native reset renews the bounded recovery')
end)
test('off-combat cannot reset a live native helper or pair on the same actor',function()
    local h=stalledPhase()
    for _=1,24 do h:tick()end
    assert(h.sent==1)
    local ex,ed=h:pair('ex'),h:pair('ed')
    h.asc.tags['AI.State.Combat']=0
    h.asc.tags['CharacterState.OffCombat']=1
    h.asc.tags[CAN_SUMMON]=0;h.asc.active=0;h.asc.lock=0
    h.summon.SpawnedSummonInstances={}
    for _=1,4 do h:tick()end
    h.asc.tags['AI.State.Combat']=1
    h.asc.tags['CharacterState.OffCombat']=0
    h.asc.tags[CAN_SUMMON]=1;h.asc.lock=1
    for _=1,48 do h:tick()end
    assert(h.sent==1 and h.phase:busy(h.parent) and ex.bIsActive and ed.bIsActive)
end)
print('menghua_phase: '..tests..' checks passed')
