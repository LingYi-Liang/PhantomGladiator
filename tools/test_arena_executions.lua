package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Exec=require('arena_executions')
local DATA=require('execution_data')
local address=0
local function object(name,fields)
    address=address+1;local a=address
    local o=fields or {}
    o.IsValid=function()return true end
    o.GetAddress=function()return a end
    o.GetFName=function()return {ToString=function()return name end}end
    return o
end
local function class(name)return object(name)end
local function actor(className,fields)
    local o=object(className..'_0',fields)
    o.GetFullName=function()return className..' '..className..'_'..o:GetAddress()end
    o.GetClass=function()return class(className..'_C')end
    return o
end
local function pair(kind,exec,executed)
    return {ExecutionType={TagName={ToString=function()return kind end}},ExecutionAbility=class(exec),ExecutedAbility=class(executed)}
end
local MOYUAN=pair('Execution.Type.Combat','GA_Hun_BEx_MoYuan_C','GA_Hun_BEd_MoYuan_C')
local GUN=pair('Execution.Type.Combat','GA_Hun_BEx_Common_GuiChai_Gun_02_C','GA_Hun_BEd_Common_GuiChai_Gun_02_C')
local PENG_EXEC,PENG_EXECUTED=class('GA_Hun_BEx_Common_PengMeng_V2_C'),class('GA_Hun_BEd_Common_PengMeng_C')
local LOCK=class('GE_MoYuan_LockHealth_C')
local OTHER_GE=class('GE_Boss_C')
local MOBS_PATH='/PBZCombatAsset/ActorData/Mobs/'
local MOYUAN_RUN=DATA.GA_Hun_BEx_MoYuan_C.executor+0.3
local PENG_RUN=DATA.GA_Hun_BEx_Common_PengMeng_V2_C.executor+0.3

local function harness()
    local h={lines={},clock=0,attrs={},tags={},members={},fighting=true,immortal={},calls={},components={},meshes={},found={}}
    h.found['/Script/Engine.SkeletalMeshComponent']=class('SkeletalMeshComponent')
    h.found['/Game/PBZContent/Blueprint/Ability/GameplayEffects/GE_Kill.GE_Kill_C']=class('GE_Kill_C')
    h.found['/Script/SGameAI.Default__SGameAIFunctionLibrary']=object('Default__SGameAIFunctionLibrary',{
        PauseLogic=function(_,brain,reason)h.calls[#h.calls+1]='pause '..reason;brain.paused=true end,
        ResumeLogic=function(_,brain,reason)h.calls[#h.calls+1]='resume '..reason;brain.paused=false end})
    local function addClip(entry)
        if entry.clip then h.found[entry.clip]=object(entry.clip:match('%.([^%.]+)$')) end
        for _,stage in pairs(entry.stages or {})do addClip(stage)end
        for _,variant in pairs(entry.variants or {})do addClip(variant)end
    end
    for _,entry in pairs(DATA)do addClip(entry)end
    h.abilities={}      -- ability class name -> its live instances
    local skeleton=object('Hun_Skin_Skeleton')
    h.found['/HuaShira/Characters/EliteBoss/MBoss/Anim/Hun_EXD_ByMBoss.Hun_EXD_ByMBoss']=
        object('Hun_EXD_ByMBoss',{Skeleton=skeleton})
    h.player=actor('BP_Player_Hero_Hun',{Mesh=object('CharacterMesh0',{GetSkeletalMeshAsset=function()return object('Hun_Skin',{Skeleton=skeleton})end})})
    h.stats={read=function(_,a,field)local v=h.attrs[a] and h.attrs[a][field];return v and {base=v,current=v} end}
    local function tagCount(actor,key)
        local tags=h.tags[actor] or {}
        if tags[key]~=nil then return tags[key] end
        if key=='CharacterState.Space.Ground' then return 1 end
        local n=0;for tag,count in pairs(tags)do if tag:sub(1,#key+1)==key..'.' then n=n+count end end
        return n
    end
    function h.anim(montage)
        local anim={montage=montage}
        function anim:GetCurrentActiveMontage()
            if not self.montage then return nil end
            if self.cachedName~=self.montage then self.cachedName=self.montage;self.cached=object(self.montage)end
            return self.cached
        end
        return object('AnimInstance',anim)
    end
    -- A unit to be executed: opts.locks (default 魔渊's lock), opts.pairs (default 魔渊's pair, {} for none),
    -- opts.rank (its config's Difficulty Tag, default UltimateBoss).
    function h.boss(className,hp,floor,opts)
        opts=opts or {}
        local rank=opts.rank or 'UltimateBoss'
        local config=object('ActorC',{['Passive GameplayEffects']=opts.locks or {OTHER_GE,LOCK},TargetExecutionAnims=opts.pairs or {MOYUAN},
            ['Difficulty Tag']={TagName={ToString=function()return 'CharacterType.Difficulty.'..rank end}}})
        local anim=h.anim(nil)
        local asc=object('ASC')
        local b
        function asc:RemoveActiveGameplayEffectBySourceEffect(ge,instigator,stacks)
            h.calls[#h.calls+1]='remove '..ge:GetFName():ToString()..' '..tostring(instigator)..' '..stacks
            h.attrs[b].Health_Min=0
        end
        function asc:BP_ApplyGameplayEffectToSelf(ge,level,context)
            h.calls[#h.calls+1]='apply '..ge:GetFName():ToString()..' level='..level..' context='..type(context)
            h.attrs[b].Health=0
        end
        function asc:GetGameplayTagCount(tag)return tagCount(b,tag.TagName) end
        b=actor(className,{['Actor Config']=config,Mesh=object('BossMesh',{GetAnimInstance=function()return anim end}),
            AbilitySystemComponent=asc,['Execution Component']=object('BossExec',{CurrentExecutionInfo={IsTarget=false}}),at=opts.at or {X=0,Y=0,Z=0}})
        function b:K2_GetActorLocation()return self.at end
        b.anim=anim
        h.attrs[b]={Health=hp,Health_Min=floor}
        return b
    end
    local function follows(m)
        if m.bFollowerShouldTickPose==nil then m.bFollowerShouldTickPose=false end
        function m:SetLeaderPoseComponent(leader,force,tick)
            h.calls[#h.calls+1]='leader '..self:GetFName():ToString()..' -> '..(leader and leader:GetFName():ToString() or 'nil')
            self.LeaderPoseComponent=leader
            self.bFollowerShouldTickPose=tick
            if self.handOver and leader and leader~=self.handOver.leader then
                -- Like an engine that hands a leader's followers over: a part found only later now follows the new one.
                self.handOver.part.LeaderPoseComponent=leader;h.cloths[#h.cloths+1]=self.handOver.part;self.handOver=nil
            end
        end
        function m:ResetAnimInstanceDynamics(kind)h.calls[#h.calls+1]='dynamics '..self:GetFName():ToString()..' '..kind end
        function m:ForceClothNextUpdateTeleportAndReset()end
        function m:ForceNextUpdateTeleportAndReset()h.calls[#h.calls+1]='cloth reset '..self:GetFName():ToString() end
        return m
    end
    h.cloths={}
    -- An enemy; humanoid unless told otherwise, with a head mesh that follows its body mesh and, with opts.cloth,
    -- Chaos cloth hair that does too (opts.handOver: a cape the engine moves to the new leader on its own).
    function h.enemy(at,opts)
        opts=opts or {}
        local e
        local nativeAnim=h.anim(nil)
        nativeAnim.position=0
        function nativeAnim:Montage_GetPosition()return self.position end
        local mesh=follows(object('CharacterMesh0',{GetBoneIndex=function(_,bone)return (bone=='pelvis' and not opts.animal) and 3 or -1 end,
            GetAnimInstance=function()return nativeAnim end,GetOwner=function()return e end,
            bFollowerShouldTickPose=opts.originalTickPose==true}))
        local head=follows(object('Head',{GetOwner=function()return e end,LeaderPoseComponent=mesh}))
        local loose=follows(object('Weapon',{GetOwner=function()return e end}))
        for _,m in ipairs({mesh,head,loose})do h.meshes[#h.meshes+1]=m end
        if opts.cloth then
            h.cloths[#h.cloths+1]=follows(object('CA_Hair01',{GetOwner=function()return e end,LeaderPoseComponent=mesh}))
        end
        if opts.handOver then
            mesh.handOver={leader=nil,part=follows(object('CA_Cape01',{GetOwner=function()return e end,LeaderPoseComponent=mesh}))}
        end
        local component=object('EnemyExec',{CurrentExecutionInfo={IsTarget=false}})
        function component:PlayExactExecution(data,target,startTime)
            if opts.fails then error('native refused') end
            h.calls[#h.calls+1]='play '..data.ExecutionAbility:GetFName():ToString()..' + '..data.ExecutedAbility:GetFName():ToString()
                ..' on '..target:GetFName():ToString()..' at '..startTime
            self.CurrentExecutionInfo={Executor=e,Target=target,IsTarget=false}
            nativeAnim.montage=opts.executorMontage or 'Executor_Montage';nativeAnim.position=startTime
            if not opts.silent then target.anim.montage=opts.montage or 'BeingExecuted_Montage' end
        end
        local brain=object('BrainComponent',{IsPaused=function(self)return self.paused==true end})
        local movement=object('Movement',{MovementMode=1,CustomMovementMode=0})
        function movement:SetMovementMode(mode,custom)
            self.MovementMode,self.CustomMovementMode=mode,custom
        end
        e=actor(opts.class or 'BP_Monster_GuiChai',{Mesh=mesh,['Execution Component']=component,at=at,yaw=0,
            CharacterMovement=movement,Controller=object('AIController',{BrainComponent=brain})})
        e.AbilitySystemComponent=object('ASC',{GetGameplayTagCount=function(_,tag)return tagCount(e,tag.TagName)end})
        e.brain=brain
        e.nativeAnim=nativeAnim
        function e:K2_GetActorLocation()return self.at end
        function e:K2_SetActorRotation(rotation)h.calls[#h.calls+1]=string.format('turn %.0f',rotation.Yaw);self.yaw=rotation.Yaw;return true end
        function e:K2_GetActorRotation()return {Pitch=0,Yaw=self.yaw,Roll=0} end
        function e:AddComponentByClass(cls,manual,transform,deferred)
            local comp=object('SkeletalMeshComponent_0',{visible=true})
            function comp:GetOwner()return e end
            function comp:K2_AttachToComponent(parent,socket)self.parent=parent;self.socket=socket end
            function comp:SetSkeletalMeshAsset(asset)
                if asset then self.visibleAtInstall=self.visible and not self.bHiddenInGame end
                self.asset=asset
                if opts.unhideOnMesh and asset then self.visible=true;self.bHiddenInGame=false end
            end
            function comp:IsVisible()return self.visible end
            function comp:SetVisibility(visible)
                if not (opts.ignoreHide or (opts.unhideOnMesh and self.asset)) then self.visible=visible end
            end
            function comp:SetHiddenInGame(hidden)
                if not (opts.ignoreHide or (opts.unhideOnMesh and self.asset)) then self.bHiddenInGame=hidden end
            end
            function comp:IsBeingDestroyed()return self.destroyed==true end
            function comp:PlayAnimation(anim,loop)self.playing=anim:GetFName():ToString();self.position=0;self.rate=1 end
            function comp:SetPosition(position)self.position=position end
            function comp:GetPosition()return self.position end
            function comp:SetPlayRate(rate)self.rate=rate end
            function comp:GetPlayRate()return self.rate end
            function comp:GetAnimInstance()return object('SingleNode',{SetRootMotionMode=function(_,mode)comp.rootMotion=mode end})end
            function comp:IsPlaying()return self.playing~=nil end
            function comp:K2_DestroyComponent(target)
                if not opts.ignoreDestroy then self.destroyed=(target==self) end
                h.calls[#h.calls+1]='destroy body'
            end
            h.components[#h.components+1]=comp
            h.calls[#h.calls+1]='add '..cls:GetFName():ToString()..' manual='..tostring(manual)
            return comp
        end
        h.attrs[e]={Health=500,Health_Min=0}
        return e
    end
    function h.new(extra)
        local options={log=function(s)h.lines[#h.lines+1]=s end,attributes=h.stats,now=function()return h.clock end,
            members=function()return h.members end,fighting=function()return h.fighting end,getPlayer=function()return h.player end,
            getLocation=function(a)return a.at end,isImmortal=function(team)return h.immortal[team]==true end,
            staticFind=function(path)return h.found[path] end,loadAsset=function()return nil end,
            findAll=function(kind)
                if h.abilities[kind] then return h.abilities[kind] end
                if kind=='ChaosClothComponent' then return h.cloths end
                assert(kind=='SkeletalMeshComponent');return h.meshes
            end,fname=function(s)return s end}
        for k,v in pairs(extra or {})do options[k]=v end
        return Exec.new(options)
    end
    function h.all()return table.concat(h.lines,'\n')end
    function h.has(text)for _,c in ipairs(h.calls)do if c==text then return true end end;return false end
    function h.count(text)local n=0;for _,c in ipairs(h.calls)do if c==text then n=n+1 end end;return n end
    function h.run(exec,seconds)for _=1,math.floor(seconds/0.5+0.5)do h.clock=h.clock+0.5;exec:tick()end end
    return h
end

if arg[1]=='fixture'then return harness end
do
    local h=harness()
    local victim=h.enemy({X=100,Y=0,Z=0},{})
    victim.nativeAnim.montage='NativeHitReaction'
    local alive=true
    local timers,cancelled={},{}
    local exec=h.new({loop=function(_,fn)timers[#timers+1]=fn;return #timers end,
        cancel=function(id)cancelled[id]=true end})
    local action=object('ActiveNPCStrike',{
        bIsActive=true,AbilityTags={GameplayTags={{TagName={ToString=function()return 'Ability.Action' end}}}},
        GetAvatarActorFromActorInfo=function()return victim end,
        K2_CancelAbility=function(self)self.bIsActive=false end,
    })
    victim.AbilitySystemComponent.LocalAnimMontageInfo={AnimatingAbility=action}
    local currentHit='None'
    victim['Hitreact Component']=object('Hitreact',{
        GetCurrentHitState=function()return {TagName={ToString=function()return currentHit end}}end,
        ChangeHitState=function(_,tag)currentHit=tag.TagName end,
    })
    assert(exec:startGuillotineHold(victim,function()return alive end))
    local pose=h.components[1]
    assert(pose.playing=='Hun_EXD_ByMBoss' and pose.rate==0.6000000238418579 and victim.Mesh.LeaderPoseComponent==pose)
    assert(victim.brain:IsPaused() and victim.CharacterMovement.MovementMode==0 and action.bIsActive==false)
    assert(currentHit=='CharacterState.Hitreact.State.Custom')
    assert(victim.nativeAnim.montage=='NativeHitReaction' and h.attrs[victim].Health==500)
    assert(not exec:startGuillotineHold(victim,function()return true end),'duplicate capture must not borrow another skeleton')
    pose.position=0.53;timers[1]()
    assert(not pose.destroyed and pose.rate==0.6000000238418579)
    pose.position=0.54;timers[1]()
    assert(pose.position==0.54 and pose.rate==0,'wait for the native lethal point rather than advancing independently')
    assert(exec:finishGuillotineHold(victim))
    assert(pose.position==0.4 and pose.rate==3 and victim.brain:IsPaused())
    pose.position=0.7;timers[1]()
    assert(pose.position==0.7 and pose.rate==1.5 and victim.CharacterMovement.MovementMode==0)
    local held,finished=exec:guillotineHeld(victim)
    assert(held and not finished and not cancelled[1],'a partial victim visual cannot be marked finished')
    pose.position=6.24;timers[1]()
    held,finished=exec:guillotineHeld(victim)
    assert(held and finished and pose.position==6.233333 and pose.rate==0 and not pose.destroyed)
    assert(victim.brain:IsPaused() and victim.CharacterMovement.MovementMode==0 and h.attrs[victim].Health==500)
    assert(exec:stopGrabPose('收尾读回'))
    assert(cancelled[1] and pose.destroyed and victim.Mesh.LeaderPoseComponent==nil)
    assert(not victim.brain:IsPaused() and victim.CharacterMovement.MovementMode==1 and not exec:guillotineHeld(victim))
    assert(currentHit=='None')
    assert(victim.nativeAnim.montage=='NativeHitReaction' and h.attrs[victim].Health==500)

    victim.brain.paused=true
    victim.CharacterMovement:SetMovementMode(6,2)
    assert(exec:startGuillotineHold(victim,function()return alive end))
    alive=false;timers[2]()
    assert(cancelled[2] and h.components[2].destroyed and victim.Mesh.LeaderPoseComponent==nil)
    assert(victim.brain:IsPaused() and victim.CharacterMovement.MovementMode==6 and victim.CharacterMovement.CustomMovementMode==2)
    alive=true
    assert(exec:startGuillotineHold(victim,function()return alive end))
    exec:stop('F4')
    assert(cancelled[3] and h.components[3].destroyed and victim.brain:IsPaused() and victim.CharacterMovement.MovementMode==6)
    print('PASS guillotine hold advances both original victim segments, waits for release, and restores on completion, invalidation and F4')
end

do
    local h=harness()
    local first=h.enemy({X=100,Y=0,Z=0},{})
    local second=h.enemy({X=200,Y=0,Z=0},{})
    local timers={}
    local exec=h.new({loop=function(_,fn)timers[#timers+1]=fn;return #timers end,cancel=function()end})
    assert(exec:startGuillotineHold(first,function()return true end))
    assert(exec:startGuillotineHold(second,function()return true end))
    assert(first.Mesh.LeaderPoseComponent~=second.Mesh.LeaderPoseComponent)
    assert(exec:finishGuillotineHold(first) and exec:finishGuillotineHold(second))
    assert(exec:stopGrabPose('只释放第一组',first))
    assert(not exec:guillotineHeld(first) and exec:guillotineHeld(second))
    assert(exec:stopGrabPose('停止全部') and not exec:guillotineHeld(second))
    print('PASS concurrent guillotine victims own separate poses, controls and restoration')
end

do
    local h=harness()
    local victim=h.enemy({X=100,Y=0,Z=0},{})
    local timers={}
    local exec=h.new({loop=function(_,fn)timers[#timers+1]=fn;return #timers end,cancel=function()end})
    assert(exec:startGuillotineHold(victim,function()return true end))
    h.attrs[victim].Health=0
    victim.brain.paused=false
    victim.CharacterMovement:SetMovementMode(3,0)
    assert(exec:finishGuillotineHold(victim))
    local pose=h.components[1]
    pose.position=0.7;timers[1]()
    pose.position=6.24;timers[1]()
    local held,finished=exec:guillotineHeld(victim)
    assert(held and finished,'native death taking over AI or movement does not discard the finishing pose')
    assert(exec:stopGrabPose('尸体收尾',victim))
    assert(victim.CharacterMovement.MovementMode==3 and h.attrs[victim].Health==0)
    print('PASS native death control changes preserve the full victim finish without reviving it')
end

do
    local failures={}
    local function regression(name,fn)
        local ok,err=pcall(fn)
        print((ok and 'ok - ' or 'FAIL - ')..name..(ok and '' or ': '..tostring(err)))
        if not ok then failures[#failures+1]=name end
    end
    -- 随从处决 BOSS: a companion, its hatred list and a boss it is after.
    local function companionCase(opts)
        opts=opts or {}
        local h=harness()
        local on=opts.on~=false
        local boss=h.boss('BP_Boss',opts.hp or 100,opts.floor or 0,opts.boss)
        local mate=h.enemy(opts.at or {X=300,Y=0,Z=0})
        mate.BP_PBZHatredManagerComponent=object('Hatred',{HatredList={boss}})
        h.tags[boss]={['CharacterState.CanWeakExecute.Weak']=1}
        h.fighting=false
        h.members={{actor=mate,team='companion'}}
        local exec=h.new({companions=function()return on end,companionMinions=opts.minions and function()return true end or nil,isStand=opts.isStand,phaseBusy=opts.phaseBusy})
        return h,exec,boss,mate,function(value)on=value end
    end
    regression('the switch off: a boss a companion is after is left to the player',function()
        local h,exec=companionCase({on=false})
        h.run(exec,2);assert(exec:status().started==0)
        exec:stop('regression')
    end)
    regression('a verified map last cub reaches its specific native execution outside the arena',function()
        local h=harness()
        local lion=pair('Execution.Type.Combat','GA_Hun_BEx_HouHouHou_01_C','GA_Hun_BEd_HouHouHou_01_C')
        local cub=h.boss('BP_Monster_DaTouWaWa_HouHouHou',100,0,{rank='Elite',pairs={lion}})
        local mate=h.enemy({X=300,Y=0,Z=0})
        local stranger=h.enemy({X=100,Y=0,Z=0})
        h.members={{actor=mate,team='companion'},{actor=stranger,team='companion'}}
        h.tags[cub]={['CharacterState.CanWeakExecute.Weak']=1,['CharacterType.HouHouHou.LastOne']=1}
        h.fighting=false
        local may=false
        local pickups=0
        local exec=h.new({
            fieldLastCubs=function()return {{actor=cub,key=tostring(cub:GetAddress())}} end,
            fieldLionTarget=function(a,v)return may and a==mate and v==cub end,
            lionPickup=function(a,v)assert(a==mate and v==cub);pickups=pickups+1;return true end,
            lionPickupEnded=function()end,
        })
        h.run(exec,1);assert(exec:status().started==0)
        may=true
        h.run(exec,1);assert(exec:status().started==1 and pickups==1)
        exec:stop('arena only',true)
        assert(exec:status().active)
        exec:stop('full cleanup')
    end)
    regression('a tagged last cub on its native 20% floor requests only the native lion-head pair',function()
        local function arenaCase(opts)
            local h=harness()
            local lion=pair('Execution.Type.Combat','GA_Hun_BEx_HouHouHou_01_C','GA_Hun_BEd_HouHouHou_01_C')
            lion.TargetRequiredTags={'CharacterType.HouHouHou.LastOne'}
            local owner=h.boss('BP_Monster_LionDancer_P2',4000,0)
            local cub=h.boss('BP_Monster_DaTouWaWa_HouHouHou',opts.hp or 6807,opts.floor or 6807,{rank='Mob',pairs={lion},locks={}})
            local close=h.enemy({X=100,Y=0,Z=0})
            local assigned=h.enemy({X=300,Y=0,Z=0})
            local unrelated=h.enemy({X=50,Y=0,Z=0})
            h.attrs[cub].Health_Max=34035
            h.tags[cub]={['CharacterType.HouHouHou.LastOne']=opts.missingTag and 0 or 1}
            if opts.blocked then h.tags[cub]['CharacterState.Stand.Invulnerable']=1 end
            if opts.noGround then h.tags[close]={['CharacterState.Space.Ground']=0} end
            if opts.weak then h.tags[cub]['CharacterState.CanWeakExecute.Weak']=1 end
            close['Faction Component']=object('Faction',{GetFactionRelation=function(_,target)
                assert(target==cub);return opts.friendly and 0 or 2
            end})
            unrelated['Faction Component']=object('Faction',{GetFactionRelation=function()return 2 end})
            h.members={{actor=unrelated,team='blue'},{actor=close,team='blue'},{actor=assigned,team='blue'},
                {actor=owner,team='red'},{actor=cub,team='red',class_path=require('lion_challenge').CUB,summoner=owner}}
            local chosen,completion
            local exec=h.new({
                lastLionOwner=function(a)if a==cub then return opts.wrongWave and unrelated or owner end end,
                assignedOpponent=function(a)
                    if a==close then return owner end
                    if a==assigned and opts.preferAssigned then return cub end
                    if a==unrelated then return close end
                end,
                lionPickup=function(actor,victim)
                    assert(victim==cub);chosen=actor;return not opts.noTicket
                end,
                lionPickupEnded=function(_,done) completion=done end,
            })
            h.run(exec,2)
            local status=exec:status()
            if opts.noTicket then assert(chosen==close and status.started==0 and #h.calls==0);return end
            if opts.expectNone then assert(not chosen and status.started==0);return end
            assert(chosen==(opts.preferAssigned and assigned or close) and status.started==1)
            h.run(exec,8)
            assert(h.attrs[cub].Health==6807 and h.attrs[cub].Health_Min==6807 and completion~=true,
                'a refused native death cannot spend the authentic cub or claim a head')
        end
        arenaCase({})
        arenaCase({preferAssigned=true})
        arenaCase({noTicket=true})
        arenaCase({missingTag=true,expectNone=true})
        arenaCase({wrongWave=true,weak=true,expectNone=true})
        arenaCase({floor=6000,expectNone=true})
        arenaCase({hp=7000,expectNone=true})
        arenaCase({blocked=true,expectNone=true})
        arenaCase({noGround=true,expectNone=true})
        arenaCase({friendly=true,expectNone=true})
    end)
    regression('a scripted phase is not borrowed as a target or executor and resumes after the phase',function()
        for _,which in ipairs({'boss','executor'})do
            local busy=true;local held
            local h,exec,boss,mate=companionCase({phaseBusy=function(actor)return busy and actor==held end})
            held=which=='boss' and boss or mate
            h.run(exec,2);assert(exec:status().started==0,'scripted actor cannot be borrowed')
            busy=false;h.run(exec,0.5);assert(exec:status().started==1,'normal executions resume after the phase')
            exec:stop('phase fixture')
        end
    end)
    regression('the switch on: the companion executes a boss of the map, with no arena fight on',function()
        local h,exec,boss,mate=companionCase()
        h.run(exec,0.5)
        assert(exec:status().started==1,h.all())
        assert(exec:executing(mate) and not exec:executing(boss),'it can say who is executing')
        assert(exec:participant(mate) and exec:participant(boss),'both roles own their protected animation')
        assert(h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Boss_0 at 0.0'),table.concat(h.calls,' | '))
        assert(h.all():find('随从处决登记 BP_Boss（UltimateBoss）',1,true),h.all())
        exec:stop('regression')
        assert(not exec:executing(mate))
        assert(not exec:participant(mate) and not exec:participant(boss))
    end)
    regression('the same for a boss summoned with no team, and a fight in the arena does not stop it',function()
        local h,exec,boss,mate=companionCase()
        local blue,red=h.enemy({X=9000,Y=0,Z=0}),h.enemy({X=9000,Y=300,Z=0})
        h.fighting=true
        h.members={{actor=mate,team='companion'},{actor=boss,team='neutral'},{actor=blue,team='blue'},{actor=red,team='red'}}
        h.run(exec,0.5);assert(exec:status().started==1,h.all())
        exec:stop('regression')
    end)
    regression('minions stay the player\'s: only a boss is taken',function()
        local h,exec=companionCase({boss={rank='Elite'}})
        h.run(exec,2);assert(exec:status().started==0,h.all())
        exec:stop('regression')
    end)
    regression('the minion switch: a minion a companion is after is executed by it, the boss switch on or off; never one the player has taken',function()
        for _,on in ipairs({true,false})do
            local h,exec,minion,mate=companionCase({boss={rank='Elite'},minions=true,on=on})
            h.run(exec,0.5);assert(exec:status().started==1 and exec:executing(mate),h.all())
            exec:stop('regression')
        end
        local h,exec,minion=companionCase({boss={rank='Elite'},minions=true,on=false})
        minion['Execution Component'].CurrentExecutionInfo={Executor=h.player,Target=minion,IsTarget=true}
        h.run(exec,2);assert(exec:status().started==0,'the player has it')
        exec:stop('regression')
        local h2,exec2=companionCase({minions=true,on=false})
        h2.run(exec2,2);assert(exec2:status().started==0,'the minion switch does not take bosses')
        exec2:stop('regression')
    end)
    regression('a boss the player is executing stays the player\'s',function()
        local h,exec,boss=companionCase()
        boss['Execution Component'].CurrentExecutionInfo={Executor=h.player,Target=boss,IsTarget=true}
        h.run(exec,2);assert(exec:status().started==0)
        assert(h.all():find('玩家处决过或正在处决，随从不抢：BP_Boss',1,true),h.all())
        exec:stop('regression')
    end)
    regression('the player and the arena\'s own units are never taken, whatever is on the list',function()
        local h,exec,boss,mate=companionCase()
        local arena=h.boss('BP_ArenaBoss',100,0);h.tags[arena]={['CharacterState.CanWeakExecute.Weak']=1}
        local friend=h.boss('BP_FriendBoss',100,0);h.tags[friend]={['CharacterState.CanWeakExecute.Weak']=1}
        -- A player that reads like a boss: only its being the player keeps it off the list.
        h.player=h.boss('BP_Player',100,0);h.tags[h.player]={['CharacterState.CanWeakExecute.Weak']=1}
        mate.BP_PBZHatredManagerComponent.HatredList={h.player,arena,friend}
        h.members={{actor=mate,team='companion'},{actor=friend,team='companion'},{actor=arena,team='blue'}}
        h.run(exec,2);assert(exec:status().started==0,h.all())
        exec:stop('regression')
    end)
    regression('a companion does not step into the arena: nobody on the arena\'s teams is executed by one',function()
        local h=harness()
        local boss=h.boss('BP_Boss',100,0);h.tags[boss]={['CharacterState.CanWeakExecute.Weak']=1}
        local mate=h.enemy({X=300,Y=0,Z=0})
        h.members={{actor=boss,team='red'},{actor=mate,team='companion'}}
        local exec=h.new({companions=function()return true end})
        h.run(exec,2);assert(exec:status().started==0,h.all())
        exec:stop('regression')
    end)
    regression('a stand is no boss to execute, and no executor either',function()
        local h,exec=companionCase({isStand=function()return true end})
        h.run(exec,2);assert(exec:status().started==0,h.all())
        exec:stop('regression')
        -- The boss is on the summoner's list, out of her reach, and her parked stand is right beside it.
        local h2,exec2,boss,mate=companionCase()
        local summoner=h2.enemy({X=50000,Y=0,Z=0})
        summoner.BP_PBZHatredManagerComponent=object('Hatred',{HatredList={boss}})
        mate.BP_PBZHatredManagerComponent=nil
        h2.members={{actor=summoner,team='companion'},{actor=mate,team='companion',stand=true,reserve=true}}
        h2.run(exec2,2);assert(exec2:status().started==0,'a parked stand does not execute')
        exec2:stop('regression')
    end)
    regression('out of reach it waits; once the companion is close it goes',function()
        local h,exec,boss,mate=companionCase({at={X=5000,Y=0,Z=0}})
        h.run(exec,2);assert(exec:status().started==0)
        mate.at={X=300,Y=0,Z=0};h.run(exec,0.5);assert(exec:status().started==1,h.all())
        exec:stop('regression')
    end)
    regression('a boss on its death lock is ended by the companion\'s execution, as in the arena',function()
        local h,exec,boss=companionCase({hp=2,floor=1})
        h.tags[boss]={}
        h.run(exec,2.5);assert(exec:status().started==1,h.all())
        assert(h.all():find('开始（卡在锁血线）目标=BP_Boss',1,true),h.all())
        h.run(exec,MOYUAN_RUN+1)
        assert(h.has('apply GE_Kill_C level=0.0 context=table') and exec:status().kills==1,table.concat(h.calls,' | '))
    end)
    regression('a boss that leaves the list is forgotten without a line, and the switch going off stops the look',function()
        local h,exec,boss,mate,set=companionCase()
        h.tags[boss]={}
        h.run(exec,0.5)
        mate.BP_PBZHatredManagerComponent.HatredList={}
        h.run(exec,0.5)
        assert(not h.all():find('单位已离场',1,true),h.all())
        mate.BP_PBZHatredManagerComponent.HatredList={boss}
        h.run(exec,0.5)
        assert(select(2,h.all():gsub('随从处决登记 BP_Boss',''))==2,'looked at afresh when it comes back: '..h.all())
        h.tags[boss]={['CharacterState.CanWeakExecute.Weak']=1}
        set(false);h.run(exec,1);assert(exec:status().started==0)
        set(true);h.run(exec,0.5);assert(exec:status().started==1)
        exec:stop('regression')
    end)
    regression('execution eligibility is discarded when a unit leaves and its address is reused',function()
        local h=harness();local old=h.boss('BP_Same',100,0,{pairs={},locks={}})
        local enemy=h.enemy({X=300,Y=0,Z=0})
        h.members={{actor=old,team='red'},{actor=enemy,team='blue'}}
        local exec=h.new();h.run(exec,0.5)
        h.members={{actor=enemy,team='blue'}};h.run(exec,0.5)
        local fresh=h.boss('BP_Same',100,0)
        fresh.GetAddress=old.GetAddress
        h.tags[fresh]={['CharacterState.CanWeakExecute.Weak']=1}
        h.members={{actor=fresh,team='red'},{actor=enemy,team='blue'}};h.run(exec,0.5)
        assert(exec:status().started==1,'new unit inherited nopair')
        exec:stop('regression')
    end)
    regression('a new humanoid can execute after an animal used the same address',function()
        local h=harness();local boss=h.boss('BP_Target',100,0)
        local old=h.enemy({X=300,Y=0,Z=0},{animal=true})
        h.tags[boss]={['CharacterState.CanWeakExecute.Weak']=1}
        h.members={{actor=boss,team='red'},{actor=old,team='blue'}}
        local exec=h.new();h.run(exec,0.5);assert(exec:status().started==0)
        h.members={{actor=boss,team='red'}};h.run(exec,0.5)
        local fresh=h.enemy({X=300,Y=0,Z=0});fresh.GetAddress=old.GetAddress
        old.IsValid=function()return false end
        h.members={{actor=boss,team='red'},{actor=fresh,team='blue'}};h.run(exec,0.5)
        assert(exec:status().started==1,'new mesh inherited animal classification')
        exec:stop('regression')
    end)
    assert(#failures==0,table.concat(failures,'; '))
end

-- The native executor montage must keep updating while its rendered pose follows the borrowed skeleton.
-- Model only UE's documented TickPose gate: a follower with false never advances its own montage/root motion.
-- This reproduces the runtime evidence (native position stuck at 0 while the borrowed clip advances).
do
    for _,originalTick in ipairs({false,true}) do
        local h=harness()
        local boss=h.boss('BP_Monster_MoTian',10,10)
        local enemy=h.enemy({X=300,Y=0,Z=0},{originalTickPose=originalTick,cloth=true})
        h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
        local exec=h.new()
        h.run(exec,1.5)
        local x0=enemy.at.X
        for _=1,4 do
            if not enemy.Mesh.LeaderPoseComponent or enemy.Mesh.bFollowerShouldTickPose then
                enemy.nativeAnim.position=enemy.nativeAnim.position+0.25
                enemy.at={X=enemy.at.X-25,Y=0,Z=0}
            end
        end
        assert(enemy.nativeAnim.position==1 and enemy.at.X==x0-100,
            'native executor montage/root motion froze while following the borrowed skeleton')
        assert(enemy.Mesh.LeaderPoseComponent==h.components[1],'rendered body must still follow the borrowed skeleton')
        assert(h.meshes[2].bFollowerShouldTickPose==false,'do not start extra head/cloth animation graphs')
        exec:stop('tick-pose regression')
        assert(enemy.Mesh.LeaderPoseComponent==nil and enemy.Mesh.bFollowerShouldTickPose==originalTick,
            'restore the original follower TickPose policy')
    end
end

-- 魔渊 on his lock: after a second the nearest enemy turns to face him and executes him with his config pair on the
-- player's borrowed skeleton; the executor's clip plays to its end; then the body goes back, the lock comes off and
-- GE_Kill (level 0) ends him.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',5000,100)
    local near,far=h.enemy({X=300,Y=0,Z=0},{cloth=true,handOver=true}),h.enemy({X=1500,Y=0,Z=0})
    local friend=h.enemy({X=100,Y=0,Z=0})
    h.members={{actor=boss,team='red'},{actor=far,team='blue'},{actor=near,team='blue'},{actor=friend,team='red'}}
    local exec=h.new()
    h.run(exec,2)
    assert(not h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Monster_MoTian_0 at 0.0') and exec:status().started==0,'above the floor nothing happens')
    assert(h.all():find('登记 BP_Monster_MoTian（UltimateBoss）：锁血效果=1 个 技能对=GA_Hun_BEx_MoYuan_C / GA_Hun_BEd_MoYuan_C（配置 TargetExecutionAnims Execution.Type.Combat）',1,true),h.all())
    assert(h.all():find('读处决标签 CharacterState.CanWeakExecute.Weak 单位=BP_Monster_MoTian 调用=true 读回=0',1,true),'the tag read is logged once')
    h.attrs[boss].Health=100.5
    h.run(exec,0.5)
    assert(exec:status().started==0,'not yet a second on the floor')
    h.run(exec,1)
    assert(exec:status().started==1 and exec:status().active,h.all())
    assert(h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Monster_MoTian_0 at 0.0'),'the nearest enemy, not a teammate, starts it')
    assert(h.has('turn 180') and h.all():find('开始（卡在锁血线）',1,true) and h.all():find('转向目标 朝向=180 调用=true 读回=180',1,true),h.all())
    local body=h.components[1]
    assert(body and body.asset and body.asset:GetFName():ToString()=='Hun_Skin' and body.visible==false and body.rootMotion==0)
    assert(body.playing=='Hun_MoYuan_SpecialExE_01' and body.parent==near.Mesh and body.socket=='None')
    assert(h.has('leader CharacterMesh0 -> SkeletalMeshComponent_0') and h.has('leader Head -> SkeletalMeshComponent_0'))
    assert(h.has('leader CA_Hair01 -> SkeletalMeshComponent_0') and h.has('cloth reset CA_Hair01'),'cloth hair follows the borrowed body too, reset')
    assert(not h.has('leader Weapon -> SkeletalMeshComponent_0'),'a mesh that follows nothing is left alone')
    assert(h.all():find('借身体 执行方=BP_Monster_GuiChai 玩家模型=Hun_Skin 骨架=Hun_Skin_Skeleton 动画=Hun_MoYuan_SpecialExE_01（已加载） 跟随=3/3 播放中=true',1,true),h.all())
    assert(h.all():find('调用 PlayExactExecution=true',1,true) and h.all():find('目标动作=BeingExecuted_Montage',1,true),h.all())
    assert(near.brain.paused and h.all():find('暂停AI=true 读回暂停=true',1,true),'the executor stops choosing its own moves')
    h.run(exec,3)
    boss.anim.montage=nil
    h.run(exec,2)
    assert(exec:status().active,'the target side ending early does not end the executor clip')
    h.run(exec,MOYUAN_RUN-4)
    assert(not exec:status().active and exec:status().finished==1 and exec:status().kills==1,h.all())
    assert(h.all():find('结束（播完）',1,true),h.all())
    assert(h.has('leader CharacterMesh0 -> nil') and h.has('leader Head -> CharacterMesh0') and body.destroyed,'the body goes back')
    assert(h.has('leader CA_Hair01 -> CharacterMesh0') and h.has('leader CA_Cape01 -> CharacterMesh0'),'tracked and handed-over cloth both go back')
    assert(not near.brain.paused and h.all():find('恢复AI=true 读回暂停=false',1,true),'and its AI runs again')
    assert(h.has('remove GE_MoYuan_LockHealth_C nil -1') and not h.has('remove GE_Boss_C nil -1'),'only the lock effects come off')
    assert(h.has('apply GE_Kill_C level=0.0 context=table'))
    assert(h.all():find('还原跟随=3/3 补回=1 移除借来的骨架=true 重置布料=2 重置模型物理=3',1,true),h.all())
    assert(h.all():find('锁血 BOSS 收尾（UltimateBoss）：去锁血[GE_MoYuan_LockHealth_C=true] 读回底线=0.0；GE_Kill=true 读回HP=0.0',1,true),h.all())
    h.attrs[boss].Health=100;h.attrs[boss].Health_Min=100
    h.run(exec,5)
    assert(exec:status().started==1,'one try per boss')
end

-- The replacement mesh is never installed on a pose driver that cannot be hidden.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',100,100)
    local enemy=h.enemy({X=300,Y=0,Z=0},{ignoreHide=true})
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    local exec=h.new();h.run(exec,2)
    local body=assert(h.components[1])
    assert(not body.asset and body.destroyed and enemy.Mesh.LeaderPoseComponent==nil,h.all())
    assert(exec:status().active,'the original execution still proceeds without the temporary effect')
    print('PASS a declined hide skips loading the player appearance entirely')
end

do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',100,100)
    local enemy=h.enemy({X=300,Y=0,Z=0},{unhideOnMesh=true})
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    local exec=h.new();h.run(exec,2)
    local body=assert(h.components[1])
    assert(body.visibleAtInstall==false and not body.asset and body.destroyed and enemy.Mesh.LeaderPoseComponent==nil,h.all())
    print('PASS a render asset that re-enables its own visibility is dropped')
end

do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',100,100)
    local settings={ignoreDestroy=true}
    local enemy=h.enemy({X=300,Y=0,Z=0},settings)
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    local exec=h.new();h.run(exec,2)
    local body=assert(h.components[1])
    assert(body.visibleAtInstall==false and not body.visible,h.all())
    h.run(exec,MOYUAN_RUN+1)
    assert(not exec:status().active and not body.destroyed and not body.visible and not enemy.Mesh.LeaderPoseComponent,h.all())
    assert(h.all():find('移除借来的骨架=false',1,true),h.all())
    settings.ignoreDestroy=false
    h.run(exec,1.5)
    assert(body.destroyed and h.all():find('重试移除借用骨架，读回=true',1,true),h.all())
    print('PASS destruction is reported from readback and retried while the driver remains hidden')
end

do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',100,100)
    local enemy=h.enemy({X=300,Y=0,Z=0},{ignoreHide=true})
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    local exec=h.new({legacyBorrowedAppearance=function()return true end})
    h.run(exec,2)
    local body=assert(h.components[1])
    assert(body.visibleAtInstall==true and body.visible and body.asset and enemy.Mesh.LeaderPoseComponent==body,h.all())
    h.run(exec,MOYUAN_RUN+1)
    assert(body.destroyed and not body.asset and enemy.Mesh.LeaderPoseComponent==nil,h.all())
    print('PASS opt-in red versus blue execution preserves legacy visual setup and still verifies removal')
end

-- A deleted driver no longer owns a native mesh, but the surviving NPC still has the
-- pose policies set at setup. Undo only those; don't overwrite outside reassignment.
do
    for _,variant in ipairs({'engine removed driver', 'outside leader', 'executor invalid'}) do
        local h=harness()
        local boss=h.boss('BP_Monster_MoTian',100,100)
        local executor=h.enemy({X=300,Y=0,Z=0})
        h.members={{actor=boss,team='red'},{actor=executor,team='blue'}}
        local exec=h.new();h.run(exec,2)
        local body=assert(h.components[1])
        assert(executor.Mesh.bFollowerShouldTickPose==true)
        if variant=='executor invalid' then
            local prior=h.count('leader CharacterMesh0 -> nil')
            function executor:IsValid()return false end
            exec:stop(variant)
            assert(h.count('leader CharacterMesh0 -> nil')==prior and not body.destroyed,h.all())
        else
            body.destroyed=true
            function body:IsValid()return false end
            local external=variant=='outside leader' and object('OutsideLeader') or nil
            executor.Mesh.LeaderPoseComponent=external
            exec:stop(variant)
            if external then
                assert(executor.Mesh.LeaderPoseComponent==external and executor.Mesh.bFollowerShouldTickPose==true,h.all())
            else
                assert(executor.Mesh.LeaderPoseComponent==nil and executor.Mesh.bFollowerShouldTickPose==false,h.all())
            end
            assert(h.count('destroy body')==0,'the removed component must not be destroyed a second time')
        end
    end
    print('PASS a removed or invalid pose driver still releases owned state without touching a foreign leader or invalid actor')
end

-- 彭猛: his pair is in his own finishing skill, found by class. He falls during the execution: the executor's clip
-- still plays to its end, and nothing is applied to him afterwards.
do
    local h=harness()
    h.found['/PBZCombatAsset/ActorData/Mobs/044_PengMeng/Ability/Axe/Abilities/CA/GA_Hun_BEx_Common_PengMeng_V2.GA_Hun_BEx_Common_PengMeng_V2_C']=PENG_EXEC
    h.found['/PBZCombatAsset/ActorData/Mobs/044_PengMeng/Ability/Axe/Abilities/CA/GA_Hun_BEd_Common_PengMeng.GA_Hun_BEd_Common_PengMeng_C']=PENG_EXECUTED
    local boss=h.boss('BP_Monster_PengMeng_Axe',1,1,{pairs={},locks={class('GE_PengMeng_LockHealth_C')},rank='NormalBoss'})
    local enemy=h.enemy({X=0,Y=200,Z=0})
    h.members={{actor=boss,team='blue'},{actor=enemy,team='red'}}
    local exec=h.new()
    h.run(exec,1.5)
    assert(h.has('play GA_Hun_BEx_Common_PengMeng_V2_C + GA_Hun_BEd_Common_PengMeng_C on BP_Monster_PengMeng_Axe_0 at 0.0'),h.all())
    assert(h.has('turn -90'),'facing the boss below it')
    assert(h.all():find('来源=BOSS 自己的收尾技能（执行方 已加载，被处决方 已加载）',1,true),h.all())
    assert(h.components[1].playing=='Hun_PengMeng_GEx_01')
    h.run(exec,3);h.attrs[boss].Health=0;h.run(exec,0.5)
    assert(h.all():find('倒下，执行方的动作继续播完',1,true) and exec:status().active,h.all())
    h.run(exec,PENG_RUN-3)
    assert(not exec:status().active and h.all():find('结束（播完，目标已倒下）',1,true) and exec:status().kills==0,h.all())
    assert(not h.has('apply GE_Kill_C level=0.0 context=table') and h.all():find('目标已倒下或失效',1,true))
end
-- 彭猛's finisher kills whatever his health, so only his lock starts it: broken or marked executable at half health
-- he fights on, and the same marks do nothing on his way down to the lock.
do
    local h=harness()
    h.found['/PBZCombatAsset/ActorData/Mobs/044_PengMeng/Ability/Axe/Abilities/CA/GA_Hun_BEx_Common_PengMeng_V2.GA_Hun_BEx_Common_PengMeng_V2_C']=PENG_EXEC
    h.found['/PBZCombatAsset/ActorData/Mobs/044_PengMeng/Ability/Axe/Abilities/CA/GA_Hun_BEd_Common_PengMeng.GA_Hun_BEd_Common_PengMeng_C']=PENG_EXECUTED
    local boss=h.boss('BP_Monster_PengMeng_Axe',9000,1,{pairs={},locks={class('GE_PengMeng_LockHealth_C')},rank='NormalBoss'})
    local enemy=h.enemy({X=0,Y=200,Z=0})
    h.members={{actor=boss,team='blue'},{actor=enemy,team='red'}}
    h.tags[boss]={['CharacterState.Stand.Break']=1,['CharacterState.CanWeakExecute.Weak']=1,['CharacterState.CanWeakExecute.LowHealth']=1}
    local exec=h.new()
    h.run(exec,3)
    assert(exec:status().started==0,h.all())
    h.attrs[boss].Health=1;h.run(exec,1.5)
    assert(exec:status().started==1 and h.all():find('开始（卡在锁血线）',1,true),h.all())
end

-- Any unit with a pair: executed when the game marks it executable (CharacterState.CanWeakExecute.*), by the nearest
-- humanoid enemy within 6 m; an animal is passed over. A minion still standing after it is ended, as the player's
-- execution ends it.
do
    local h=harness()
    local gunner=h.boss('BP_Monster_GuiChai_Black_Gun',300,0,{locks={},pairs={GUN},rank='Standard'})
    local dog=h.enemy({X=100,Y=0,Z=0},{animal=true,class='BP_Monster_Dog'})
    local farMan=h.enemy({X=0,Y=800,Z=0},{class='BP_Monster_FarMan'})
    local man=h.enemy({X=0,Y=-400,Z=0},{class='BP_Monster_MaleThug'})
    h.members={{actor=gunner,team='red'},{actor=dog,team='blue'},{actor=farMan,team='blue'},{actor=man,team='blue'}}
    local exec=h.new()
    h.run(exec,2)
    assert(exec:status().started==0,'not executable: nothing')
    h.tags[gunner]={['CharacterState.CanWeakExecute.LowHealth']=1}
    h.run(exec,0.5)
    assert(exec:status().started==1 and h.has('play GA_Hun_BEx_Common_GuiChai_Gun_02_C + GA_Hun_BEd_Common_GuiChai_Gun_02_C on BP_Monster_GuiChai_Black_Gun_0 at 0.0'),h.all())
    assert(h.all():find('开始（CharacterState.CanWeakExecute.LowHealth）',1,true) and h.all():find('执行方=BP_Monster_MaleThug',1,true),h.all())
    assert(h.has('turn 90'),'facing the gunner')
    h.run(exec,DATA.GA_Hun_BEx_Common_GuiChai_Gun_02_C.executor+1)
    assert(not exec:status().active and exec:status().kills==1 and h.attrs[gunner].Health==0,h.all())
    assert(h.all():find('小怪处决完还站着，判死（Standard）：去锁血[] 读回底线=0.0；GE_Kill=true 读回HP=0.0',1,true),h.all())
    assert(not h.has('remove GE_MoYuan_LockHealth_C nil -1'),'a minion has no lock to take off')
    -- Only enemies further than 6 m: no execution, nothing waits.
    local g=harness()
    local lone=g.boss('BP_Monster_GuiChai_Black_Gun',300,0,{locks={},pairs={GUN},rank='Standard'})
    g.tags[lone]={['CharacterState.CanWeakExecute.Weak']=1}
    g.members={{actor=lone,team='red'},{actor=g.enemy({X=0,Y=800,Z=0}),team='blue'}}
    local exec2=g.new()
    g.run(exec2,3)
    assert(exec2:status().started==0 and not g.all():find('等对手靠近',1,true),g.all())
end

-- A boss executed because it broke is left standing (it may have another phase) and may be executed again 15 s
-- later; once it sits on its lock, the next execution ends it.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',3000,24)
    local enemy=h.enemy({X=100,Y=0,Z=0})
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    h.tags[boss]={['CharacterState.CanWeakExecute.Weak']=1}
    local exec=h.new()
    h.run(exec,0.5)
    assert(exec:status().started==1 and h.all():find('开始（CharacterState.CanWeakExecute.Weak）',1,true),h.all())
    h.run(exec,MOYUAN_RUN+0.5)
    assert(not exec:status().active and exec:status().kills==0 and h.attrs[boss].Health==3000,h.all())
    assert(h.all():find('BOSS（UltimateBoss）处决完还站着，不强制判死，15 秒后可再被处决 HP=3000.0',1,true),h.all())
    assert(not h.has('remove GE_MoYuan_LockHealth_C nil -1') and not h.has('apply GE_Kill_C level=0.0 context=table'))
    h.run(exec,10)
    assert(exec:status().started==1,'not again before 15 s')
    h.tags[boss]={};h.attrs[boss].Health=24.1;boss.anim.montage=nil
    h.run(exec,6)
    assert(exec:status().started==2 and h.all():find('开始（卡在锁血线）',1,true),h.all())
    h.run(exec,MOYUAN_RUN+0.5)
    assert(exec:status().kills==1 and h.all():find('锁血 BOSS 收尾（UltimateBoss）',1,true),h.all())
end

-- Which pairs: Combat first, then the generals' Custom.JiangJun; a mounted-only pair is not used; a pair whose executor
-- has no data is said once and skipped. Locked but no pair: said once. An immortal team is left alone.
do
    local h=harness()
    local general=h.boss('BP_Monster_JiangJun_ZhuoBi',300,0,{locks={},rank='NormalBoss',pairs={pair('Execution.Type.Custom.JiangJun','GA_Hun_BEx_Common_ZhuoBi_C','GA_Hun_BEd_Common_ZhuoBi_C')}})
    local rider=h.boss('BP_Monster_SpearMan_Rider',300,0,{locks={},pairs={pair('Execution.Type.CombatRider','GA_Hun_BEx_Common_Rider_01_C','GA_Hun_BEd_Common_Rider_01_Rider_C')}})
    local nodata=h.boss('BP_Monster_UnknownExecution',300,0,{locks={},pairs={pair('Execution.Type.Combat','GA_Unknown_Execution_C','GA_Unknown_Executed_C')}})
    local lonely=h.boss('BP_Monster_LeiDang',10,10,{pairs={},locks={class('GE_LockHealth_C')}})
    local guarded=h.boss('BP_Monster_MoTian',10,10)
    h.members={{actor=general,team='red'},{actor=rider,team='red'},{actor=nodata,team='red'},{actor=lonely,team='red'},{actor=guarded,team='red'},
        {actor=h.enemy({X=100,Y=0,Z=0}),team='blue'}}
    h.immortal.red=true
    local exec=h.new()
    h.run(exec,3)
    assert(exec:status().started==0,h.all())
    assert(h.all():find('登记 BP_Monster_JiangJun_ZhuoBi（NormalBoss）：锁血效果=0 个 技能对=GA_Hun_BEx_Common_ZhuoBi_C / GA_Hun_BEd_Common_ZhuoBi_C（配置 TargetExecutionAnims Execution.Type.Custom.JiangJun）',1,true),h.all())
    assert(h.all():find('登记 BP_Monster_SpearMan_Rider',1,true),'mounted data is registered but still requires the native contextual type')
    local _,said=h.all():gsub('有处决动作但没有执行方动作数据，不处决：BP_Monster_UnknownExecution GA_Unknown_Execution_C','')
    local _,lock=h.all():gsub('锁血但没有成对的处决动作，不处决：BP_Monster_LeiDang','')
    assert(said==1 and lock==1,h.all())
    h.immortal.red=false
    h.tags[general]={['CharacterState.CanWeakExecute.Weak']=1,['CharacterState.Stand.Break']=1}
    h.run(exec,0.5)
    assert(exec:status().started==1 and h.has('play GA_Hun_BEx_Common_ZhuoBi_C + GA_Hun_BEd_Common_ZhuoBi_C on BP_Monster_JiangJun_ZhuoBi_0 at 0.0'),h.all())
end

-- A locked boss with nobody within 20 m waits, said once; then anyone, even an animal (no borrowed body), executes it.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',10,10)
    local dog=h.enemy({X=5000,Y=0,Z=0},{animal=true,class='BP_Monster_Dog'})
    h.members={{actor=boss,team='red'},{actor=dog,team='blue'}}
    local exec=h.new()
    h.run(exec,3)
    local _,waits=h.all():gsub('附近 20 米内没有符合处决条件的对手','')
    assert(exec:status().started==0 and waits==1,h.all())
    dog.at={X=400,Y=0,Z=0}
    h.run(exec,0.5)
    assert(exec:status().started==1 and #h.components==0,h.all())
    assert(h.all():find('借身体没成，执行方原地站着：执行方不是人形骨架（没有 pelvis）',1,true),h.all())
    assert(h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Monster_MoTian_0 at 0.0'))
end

-- A helper the boss's side brought out against it (member.aid) does not finish it, however close; the real
-- opponent does once it comes within reach.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',10,10)
    local helper=h.enemy({X=100,Y=0,Z=0},{class='BP_Monster_Helper'})
    local enemy=h.enemy({X=5000,Y=0,Z=0})
    h.members={{actor=boss,team='red'},{actor=helper,team='blue',aid=true},{actor=enemy,team='blue'}}
    local exec=h.new()
    h.run(exec,3)
    assert(exec:status().started==0 and h.all():find('附近 20 米内没有符合处决条件的对手',1,true),h.all())
    enemy.at={X=400,Y=0,Z=0}
    h.run(exec,0.5)
    assert(exec:status().started==1 and h.all():find('执行方=BP_Monster_GuiChai',1,true) and not h.all():find('执行方=BP_Monster_Helper',1,true),h.all())
end
-- A finisher whose move writes story progress (story_writes.lua) is not started while that progress is missing: the
-- boss is registered as such, said once, and a locked one is ended the usual way after 20 s. Allowed, it runs as before.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',1,1)
    local enemy=h.enemy({X=100,Y=0,Z=0})
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    local asked={}
    local exec=h.new({storyAllows=function(ability)asked[#asked+1]=ability:GetFName():ToString();return false,'会给剧情加 [lz.龙柱.战斗胜利5]，剧情里还没有' end})
    h.run(exec,3)
    assert(exec:status().started==0 and asked[1]=='GA_Hun_BEx_MoYuan_C',h.all())
    local _,said=h.all():gsub('处决会改剧情，不用它：BP_Monster_MoTian GA_Hun_BEx_MoYuan_C 会给剧情加 %[lz.龙柱.战斗胜利5%]，剧情里还没有','')
    assert(said==1,h.all())
    assert(not h.all():find('登记 BP_Monster_MoTian',1,true),h.all())
    h.run(exec,20)
    assert(exec:status().started==0 and h.has('apply GE_Kill_C level=0.0 context=table'),'ended the usual way: '..h.all())
    local g=harness()
    local boss2=g.boss('BP_Monster_MoTian',10,10)
    local enemy2=g.enemy({X=100,Y=0,Z=0})
    g.members={{actor=boss2,team='red'},{actor=enemy2,team='blue'}}
    local exec2=g.new({storyAllows=function()return true end})
    g.run(exec2,1.5)
    assert(exec2:status().started==1 and g.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Monster_MoTian_0 at 0.0'),g.all())
    -- Allowed when it was registered, refused when the finisher would start: not started, said once.
    local k=harness()
    local boss3=k.boss('BP_Monster_MoTian',10,10)
    local enemy3=k.enemy({X=100,Y=0,Z=0})
    k.members={{actor=boss3,team='red'},{actor=enemy3,team='blue'}}
    local calls=0
    local exec3=k.new({storyAllows=function()calls=calls+1;if calls==1 then return true end;return false,'读不到剧情系统' end})
    k.run(exec3,3)
    local _,again=k.all():gsub('处决会改剧情，不用它：BP_Monster_MoTian GA_Hun_BEx_MoYuan_C 读不到剧情系统','')
    assert(exec3:status().started==0 and again==1 and k.all():find('登记 BP_Monster_MoTian',1,true),k.all())
end
-- Nor is such a helper finished when it sits on its own lock: its summoner's script takes it away.
do
    local h=harness()
    local helper=h.boss('BP_Monster_MoTian',10,10)
    local enemy=h.enemy({X=100,Y=0,Z=0})
    h.members={{actor=helper,team='blue',aid=true},{actor=enemy,team='red'}}
    local exec=h.new()
    h.run(exec,3)
    assert(exec:status().started==0 and not h.all():find('登记 BP_Monster_MoTian',1,true),h.all())
end

-- The call refused: counted, the body given back, the boss left locked. F4 mid-run gives the body back too.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',10,10)
    local enemy=h.enemy({X=100,Y=0,Z=0},{fails=true})
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    local exec=h.new()
    h.run(exec,1.5)
    assert(exec:status().failures==1 and not exec:status().active and h.components[1].destroyed and h.attrs[boss].Health==10,h.all())
    assert(h.all():find('调用 PlayExactExecution=false',1,true) and h.all():find('没能开始：还原跟随=2/2',1,true) and h.all():find('；恢复AI=true 读回暂停=false',1,true) and not enemy.brain.paused,h.all())

    local g=harness()
    local boss2=g.boss('BP_Monster_MoTian',10,10)
    local enemy2=g.enemy({X=100,Y=0,Z=0})
    g.members={{actor=boss2,team='red'},{actor=enemy2,team='blue'}}
    local exec2=g.new()
    g.run(exec2,1.5)
    assert(exec2:status().active)
    exec2:stop('停止参赛者')
    assert(not exec2:status().active and g.components[1].destroyed and g.attrs[boss2].Health==10)
    assert(g.all():find('中止（停止参赛者）：还原跟随=2/2 补回=0 移除借来的骨架=true',1,true) and g.all():find('；恢复AI=true 读回暂停=false',1,true) and not enemy2.brain.paused,g.all())
end

-- The call goes through but the target never starts its side: given up after 1.5 s, the lock kept, nobody killed.
-- The executor's own Mesh is borrowed even when the component search finds nothing.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',10,10)
    boss.anim.montage='Hit_Front'
    local enemy=h.enemy({X=100,Y=0,Z=0},{silent=true})
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    local exec=h.new({findAll=function()return {} end})
    h.run(exec,1.5)
    assert(exec:status().active and h.all():find('跟随=1/1',1,true),h.all())
    h.run(exec,1.5)
    assert(not exec:status().active and exec:status().failures==1 and exec:status().kills==0,h.all())
    assert(h.attrs[boss].Health==10 and not h.has('apply GE_Kill_C level=0.0 context=table') and h.components[1].destroyed)
    assert(h.all():find('结束（目标没有播被处决动作）',1,true) and h.all():find('没有处决起来，保留锁血',1,true),h.all())
end

-- 处决镜头: started right after the call with the executor ability, the borrowed skeleton and the executor's new
-- facing, ended before that skeleton is removed; a camera that throws does not stop the execution.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',10,10)
    local enemy=h.enemy({X=100,Y=0,Z=0})
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    local seen={}
    local camera={begin=function(_,info)seen.info=info;h.calls[#h.calls+1]='camera begin' end,
        finish=function(_,why)seen.why=why;seen.bodyAlive=not h.components[1].destroyed;h.calls[#h.calls+1]='camera finish' end}
    local exec=h.new({camera=camera})
    h.run(exec,1.5)
    assert(seen.info and seen.info.executor==enemy and seen.info.target==boss and seen.info.ability=='GA_Hun_BEx_MoYuan_C')
    assert(seen.info.body==h.components[1] and seen.info.yaw==180,'the camera follows the borrowed skeleton and the new facing')
    h.run(exec,MOYUAN_RUN+0.5)
    assert(seen.why=='播完' and seen.bodyAlive,'the camera ends while the skeleton is still there')
    local g=harness()
    local boss2=g.boss('BP_Monster_MoTian',10,10)
    g.members={{actor=boss2,team='red'},{actor=g.enemy({X=100,Y=0,Z=0}),team='blue'}}
    local broken=g.new({camera={begin=function()error('camera broke')end,finish=function()error('camera broke')end}})
    g.run(broken,1.5)
    assert(broken:status().active and g.all():find('处决镜头出错：',1,true),g.all())
end

-- 火流星：磷火意识: its lock is GE_LockHealth from its blueprint, not its config, and its execution is the player's QTE.
-- On the lock the nearest enemy starts the success pair at 0.1 s and the lock comes off as it starts, as its skill
-- does. Then the mod presses: the game's QTE event goes to the player, where the executed side counts it and picks its
-- hit; the executor's ability, borrowed body and camera play the matching hit, then the finale once the executed side
-- shows its own. The run lasts until that finale's end; the boss still standing is ended, the abilities left active
-- are cancelled. Without the event counted the executed side's timelines are played directly.
local P2=DATA.GA_GuiChai_Red_P2_BEx_01_C
local function huoLiuXing(counts)
    local h=harness()
    local EX,ED='GA_GuiChai_Red_P2_BEx_01_C','GA_GuiChai_Red_P2_BEd_01_C'
    local ABILITY=MOBS_PATH..'075_GuiChai_Red_P2/Ability/'
    h.found[ABILITY..'GA_GuiChai_Red_P2_BEx_01.GA_GuiChai_Red_P2_BEx_01_C']=class(EX)
    h.found[ABILITY..'GA_GuiChai_Red_P2_BEd_01.GA_GuiChai_Red_P2_BEd_01_C']=class(ED)
    h.found['/PBZCombatAsset/Prototypes/GameplayEffects/GE_LockHealth.GE_LockHealth_C']=class('GE_LockHealth_C')
    local boss=h.boss('BP_Monster_GuiChai_Red_P2',0.01,0.01,{pairs={},locks={OTHER_GE},rank='NormalBoss'})
    h.attrs[boss].Health_Max=50
    local enemy=h.enemy({X=200,Y=0,Z=0},{montage='Hun_GuiChai_Red_P2_GEd_01_Start_Montage'})
    h.members={{actor=boss,team='blue'},{actor=enemy,team='red'}}
    local function ability(cls,avatar,label)
        local a=object(cls,{bIsActive=true,ClickCount=0,FirstThreshold=3,SecondThreshold=5,ThirdThreshold=7})
        function a:GetAvatarActorFromActorInfo()return avatar end
        function a:PlayTimelineByName(n)h.calls[#h.calls+1]=label..' '..n end
        function a:K2_CancelAbility()h.calls[#h.calls+1]='cancel '..label;self.bIsActive=false end
        return a
    end
    local own,theirs=ability(EX,enemy,'own'),ability(ED,boss,'theirs')
    h.abilities[EX]={ability(EX,h.enemy({X=9000,Y=0,Z=0}),'other'),own};h.abilities[ED]={theirs}
    h.found['/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary']=object('Default__AbilitySystemBlueprintLibrary',{
        SendGameplayEventToActor=function(_,actor,tag,payload)
            h.calls[#h.calls+1]='event '..tag.TagName..' to '..actor:GetFName():ToString()..' from '..payload.Instigator:GetFName():ToString()
            if counts and actor==h.player then
                theirs.ClickCount=theirs.ClickCount+1
                boss.anim.montage=theirs.ClickCount>=7 and 'Hun_GuiChai_Red_P2_GEd_01_End_Montage' or 'Hun_GuiChai_Red_P2_GEd_01_B_Montage'
            end
        end})
    local stages={}
    local camera={begin=function()end,finish=function()end,stage=function(_,anim,label)stages[#stages+1]=anim;stages[anim]=label end}
    return h,boss,enemy,h.new({camera=camera}),stages
end
do
    local h,boss,enemy,exec,stages=huoLiuXing(true)
    h.run(exec,1.5)
    assert(exec:status().started==1 and h.has('play GA_GuiChai_Red_P2_BEx_01_C + GA_GuiChai_Red_P2_BEd_01_C on BP_Monster_GuiChai_Red_P2_0 at 0.1'),h.all())
    assert(h.all():find('登记 BP_Monster_GuiChai_Red_P2（NormalBoss）：锁血效果=1 个',1,true) and h.all():find('开始（卡在锁血线）',1,true),h.all())
    assert(h.count('remove GE_LockHealth_C nil -1')==1 and h.all():find('处决一开始就去锁血[GE_LockHealth_C=true] 读回底线=0.0',1,true),h.all())
    assert(h.components[1].playing=='Hun_GuiChai_Red_P2_GEx_01_Start',h.components[1].playing)
    assert(h.all():find('QTE 处决由 Mod 代按：2.75s 起每 0.5 秒一下，GameplayEvent.QTE.HuoLiuXing 发给玩家的能力系统（被处决方在那儿听）；执行方技能=找到 被处决方技能=找到 门槛=3/5/7 动画[hit=已加载 finale=已加载]',1,true),h.all())
    h.run(exec,2.5)
    assert(h.count('event GameplayEvent.QTE.HuoLiuXing to BP_Player_Hero_Hun_0 from BP_Monster_GuiChai_0')==0,'no press during the opening')
    h.run(exec,0.5)
    assert(h.count('event GameplayEvent.QTE.HuoLiuXing to BP_Player_Hero_Hun_0 from BP_Monster_GuiChai_0')==1 and h.has('own SingleA'),h.all())
    assert(h.components[1].playing=='Hun_GuiChai_Red_P2_GEx_01_B' and stages[1]==P2.cameras.SingleA and stages[P2.cameras.SingleA]=='SingleA',
        'the body and camera play the hit')
    h.run(exec,3)
    assert(h.count('own SingleA')==2 and h.count('own SingleB')==2 and h.count('own SingleTransition')==1 and h.count('own SingleC')==1,h.all())
    assert(h.has('own End') and h.components[1].playing=='Hun_GuiChai_Red_P2_GEx_01_End' and stages[#stages]==P2.stages.finale.camera,h.all())
    assert(stages[5]==P2.cameras.SingleTransition and stages[6]==P2.cameras.SingleC and P2.cameras.SingleC~=P2.cameras.SingleA,
        'each hit gets its own timeline camera')
    assert(#P2.camera.frames==11 and #P2.stages.finale.camera.frames==25,'the opening camera without activation tags, the finale camera')
    assert(h.all():find('代按第 7 下 6.0s：事件=true 被处决方计数 6→7 目标动作=Hun_GuiChai_Red_P2_GEd_01_End_Montage；进结局',1,true),h.all())
    assert(not h.has('other SingleA') and not h.has('theirs SingleA'),'only the executor\'s own ability; the executed side picks its own')
    h.run(exec,P2.stages.finale.length)
    assert(exec:status().active and h.count('event GameplayEvent.QTE.HuoLiuXing to BP_Player_Hero_Hun_0 from BP_Monster_GuiChai_0')==7,'no presses in the finale')
    h.run(exec,1)
    assert(not exec:status().active and exec:status().kills==1 and h.has('apply GE_Kill_C level=0.0 context=table'),h.all())
    assert(h.has('cancel own') and h.has('cancel theirs') and h.all():find('QTE 代按 7 下 进了结局，执行方技能还在，取消=true 读回仍在=false',1,true),h.all())
    assert(h.all():find('锁血 BOSS 收尾（NormalBoss）',1,true),h.all())
    -- Not a broken-stagger finisher: its lock is its only trigger.
    local g=huoLiuXing(true)
    local b2=g.members[1].actor
    g.attrs[b2].Health=40;g.tags[b2]={['CharacterState.CanWeakExecute.Weak']=1}
    local e2=g.new()
    g.run(e2,3)
    assert(e2:status().started==0,g.all())
end
do
    local h,boss,enemy,exec=huoLiuXing(false)
    local live=h.abilities
    h.abilities={GA_GuiChai_Red_P2_BEx_01_C={},GA_GuiChai_Red_P2_BEd_01_C={}}
    h.run(exec,1.5)
    assert(h.all():find('执行方技能=没找到 被处决方技能=没找到 门槛=nil/nil/nil',1,true),h.all())
    h.abilities=live
    h.run(exec,6)
    assert(h.all():find('执行方技能这时才找到 被处决方技能这时才找到',1,true),h.all())
    assert(h.count('theirs SingleA')==2 and h.count('theirs SingleB')==2 and h.has('theirs SingleTransition') and h.has('theirs SingleC'),h.all())
    assert(h.has('theirs End') and h.has('own End') and h.all():find('事件没算上，被处决方直接播 End=true',1,true),h.all())
end

-- A lock of unknown source (a blueprint's GE_LockHealth) counts when its floor is at most 1% of Health_Max: the unit
-- is executed on it and the generic lock comes off at the end. A higher floor is a phase, not a lock. A unit on a
-- lock with no usable pair is said once, and nothing is done to it.
do
    local h=harness()
    h.found['/PBZCombatAsset/Prototypes/GameplayEffects/GE_LockHealth.GE_LockHealth_C']=class('GE_LockHealth_C')
    local troop=h.boss('BP_Monster_HuaShan_RedTroop',0.01,0.01,{locks={},pairs={GUN},rank='Elite'})
    local phase=h.boss('BP_Monster_PhaseBoss',150,150,{locks={},pairs={GUN},rank='NormalBoss'})
    local stuck=h.boss('BP_Monster_LengTu',1,1,{locks={},pairs={},rank='GreatBoss'})
    for _,b in ipairs({troop,phase,stuck}) do h.attrs[b].Health_Max=300 end
    h.members={{actor=phase,team='red'},{actor=stuck,team='red'},{actor=troop,team='red'},{actor=h.enemy({X=100,Y=0,Z=0}),team='blue'}}
    local exec=h.new()
    h.run(exec,1.5)
    assert(exec:status().started==1 and h.has('play GA_Hun_BEx_Common_GuiChai_Gun_02_C + GA_Hun_BEd_Common_GuiChai_Gun_02_C on BP_Monster_HuaShan_RedTroop_0 at 0.0'),h.all())
    assert(h.all():find('开始（卡在锁血线）目标=BP_Monster_HuaShan_RedTroop',1,true),h.all())
    local _,said=h.all():gsub('卡在锁血线，但它没有能用的处决动作，不处决（也不按倒下算）：BP_Monster_LengTu HP=1.0 底线=1.0','')
    assert(said==1,h.all())
    h.run(exec,DATA.GA_Hun_BEx_Common_GuiChai_Gun_02_C.executor+1)
    assert(h.all():find('小怪处决完还站着，判死（Elite）：去锁血[GE_LockHealth_C=true] 读回底线=0.0；GE_Kill=true',1,true),h.all())
    h.run(exec,5)
    assert(exec:status().started==1 and h.attrs[phase].Health==150 and h.attrs[stuck].Health==1,'the phase floor and the pairless one are left alone')
    -- Still on its death lock after 20 s with nothing to end it: the lock comes off and GE_Kill ends it. The phase floor stays.
    h.run(exec,20)
    assert(h.all():find('卡在锁血线 20 秒，没有处决动作，按倒下收尾（GreatBoss）BP_Monster_LengTu',1,true),h.all())
    assert(h.attrs[phase].Health==150,'a floor over 1% of its health is a phase')
    local kills=exec:status().kills
    h.run(exec,25);assert(exec:status().kills==kills,'once')
end
-- The prologue boss reaches its final floor in the arena, but the story's finish never releases it there.
do
    local h=harness()
    local finalLock=class('GE_ZuoShang_MinHealth_04_C')
    h.found[MOBS_PATH..'054_ZuoShang/AIConfig/GE_ZuoShang_MinHealth_04.GE_ZuoShang_MinHealth_04_C']=finalLock
    local boss=h.boss('BP_Monster_ZuoShang',320,320,{locks={},pairs={}})
    local hp=h.attrs[boss]
    hp.Health_Max=8000
    local asc=boss.AbilitySystemComponent
    local present=true
    function asc:GetGameplayEffectCount(effect) return effect==finalLock and present and 1 or 0 end
    function asc:RemoveActiveGameplayEffectBySourceEffect(effect)
        assert(effect==finalLock,'only the prologue final lock may be removed')
        h.calls[#h.calls+1]='release prologue lock'
        present=false
        hp.Health_Min=0
    end
    h.members={{actor=boss,team='red'},{actor=h.enemy({X=100,Y=0,Z=0}),team='blue'}}
    local receiving=false
    local exec=h.new({nativeExecution=function(actor)return actor==boss and receiving end})
    hp.Health,hp.Health_Min=3200,3200
    h.run(exec,21)
    assert(hp.Health_Min==3200,'preserve the 40 percent stage floor')
    hp.Health,hp.Health_Min=320,320
    present=false
    h.run(exec,21)
    assert(hp.Health_Min==320 and h.count('release prologue lock')==0,'another effect at 4 percent stays')
    hp.Health=350
    exec:tick()
    hp.Health,present=320,true
    h.run(exec,19)
    assert(hp.Health_Min==320,'give the native phase time to play out')
    h.fighting=false
    h.run(exec,4)
    h.fighting=true
    h.run(exec,2)
    assert(hp.Health_Min==320,'a later fight starts a new waiting period')
    receiving=true
    h.run(exec,19)
    assert(hp.Health_Min==320 and h.count('release prologue lock')==0,'do not drop the final floor midway through a native grab')
    receiving=false
    h.run(exec,0.5)
    assert(hp.Health_Min==0 and hp.Health==320 and not present,'stalled prologue floor should release without dealing damage')
    assert(h.all():find('血量下限=320.0→0.0 HP读回=320.0 验证=true',1,true),h.all())
    h.run(exec,25)
    assert(h.count('release prologue lock')==1)
end
-- 打到死 on a unit's card: on its death lock it dies at once, whatever team, with no execution. A phase floor stays, an
-- immortal team stays, and a unit without the rule is executed as ever.
do
    local h=harness()
    local killed=h.boss('BP_Monster_MoTian',1,1,{locks={LOCK},pairs={MOYUAN},rank='UltimateBoss'})
    local executed=h.boss('BP_Monster_PengMeng_Axe',1,1,{locks={LOCK},pairs={GUN},rank='GreatBoss'})
    local phase=h.boss('BP_Monster_PhaseBoss',150,150,{locks={},pairs={},rank='NormalBoss'})
    local alone=h.boss('BP_Monster_Solo',1,1,{locks={LOCK},pairs={},rank='NormalBoss'})
    local notYet=h.boss('BP_Monster_NotYet',400,1,{locks={LOCK},pairs={},rank='NormalBoss'})
    for _,b in ipairs({killed,executed,phase,alone,notYet})do h.attrs[b].Health_Max=300 end
    local rule={[killed]=true,[phase]=true,[alone]=true,[notYet]=true}
    h.members={{actor=killed,team='red'},{actor=phase,team='red'},{actor=alone,team='neutral'},{actor=notYet,team='red'},
        {actor=executed,team='red'},{actor=h.enemy({X=100,Y=0,Z=0}),team='blue'}}
    local exec=h.new({killOnLock=function(actor)return rule[actor]==true end})
    exec:tick()
    assert(h.all():find('到锁血线直接打死（卡面设置）BP_Monster_MoTian：去锁血[GE_MoYuan_LockHealth_C=true',1,true),h.all())
    assert(h.all():find('到锁血线直接打死（卡面设置）BP_Monster_Solo',1,true),'a unit with no team too: '..h.all())
    assert(exec:status().kills==2,exec:status().kills)
    assert(not h.all():find('打死（卡面设置）BP_Monster_PhaseBoss',1,true),'a floor over 1% of its health is a phase')
    assert(not h.all():find('打死（卡面设置）BP_Monster_NotYet',1,true),'not on the line yet')
    exec:tick();assert(exec:status().kills==2,'once')
    assert(not h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Monster_MoTian_0 at 0.0'),'no execution for it')
    h.run(exec,1.5)
    assert(h.has('play GA_Hun_BEx_Common_GuiChai_Gun_02_C + GA_Hun_BEd_Common_GuiChai_Gun_02_C on BP_Monster_PengMeng_Axe_0 at 0.0'),'the unit without the rule is executed: '..h.all())
    -- Reached later: it dies when it gets there.
    h.attrs[notYet].Health=1
    h.run(exec,DATA.GA_Hun_BEx_Common_GuiChai_Gun_02_C.executor+1)
    assert(h.all():find('到锁血线直接打死（卡面设置）BP_Monster_NotYet',1,true),h.all())
    -- A team held up by its 不倒下 switch stays up: that floor is the switch's.
    local g=harness()
    local guarded=g.boss('BP_Monster_Guarded',1,1,{locks={LOCK},pairs={},rank='NormalBoss'})
    g.attrs[guarded].Health_Max=300
    g.immortal.red=true
    g.members={{actor=guarded,team='red'}}
    local held=g.new({killOnLock=function()return true end})
    held:tick()
    assert(held:status().kills==0 and not g.all():find('打死（卡面设置）',1,true),g.all())
end
-- Time stop may leave a fighter exactly at a final health floor. Resolving it would mutate the frozen match.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',1,1,{locks={LOCK},pairs={MOYUAN},rank='UltimateBoss'})
    h.attrs[boss].Health_Max=300
    h.members={{actor=boss,team='red'},{actor=h.enemy({X=100,Y=0,Z=0}),team='blue'}}
    local frozen=true
    local exec=h.new({paused=function()return frozen end,killOnLock=function(actor)return actor==boss end})
    exec:tick()
    assert(h.attrs[boss].Health==1 and h.attrs[boss].Health_Min==1 and exec:status().kills==0,
        'a frozen match must not start final health-floor cleanup')
    frozen=false
    exec:tick()
    assert(h.attrs[boss].Health==0 and exec:status().kills==1,'the same confirmed floor resolves after unpausing')
end
-- A native execution can leave only a temporary 1-HP floor. It is not permission for an extra finisher.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',1,1,{locks={},pairs={MOYUAN},rank='UltimateBoss'})
    h.attrs[boss].Health_Max=300
    h.members={{actor=boss,team='red'},{actor=h.enemy({X=100,Y=0,Z=0}),team='blue'}}
    local native=true
    local exec=h.new({nativeExecution=function(actor)return actor==boss and native end,
        killOnLock=function(actor)return actor==boss end})
    h.run(exec,3)
    assert(h.attrs[boss].Health==1 and h.attrs[boss].Health_Min==1 and exec:status().kills==0
        and exec:status().started==0,'do not interpret native execution protection as a terminal lock')
    native=false
    h.attrs[boss].Health_Min=0
    h.run(exec,3)
    assert(h.attrs[boss].Health==1 and exec:status().kills==0,'a released temporary floor must not leave a pending kill')
end
-- A living original squad can keep its leader at 1%. Only the original squad may release that floor.
do
    local path='/PBZCombatAsset/ActorData/Mobs/035_HuaShan/GameplayEffects/GE_HuaShan_Troop_MinHealth.GE_HuaShan_Troop_MinHealth_C'
    for _,id in ipairs({'BP_Monster_HuaShan_Blue','BP_Monster_HuaShan_JianOu'})do
        local h=harness()
        local effect=object('GE_HuaShan_Troop_MinHealth_C',{GetFullName=function()return 'BlueprintGeneratedClass '..path end})
        h.found[path]=effect
        local count=1
        local leader=h.boss(id,3,3,{locks={},pairs={MOYUAN},rank='GreatBoss'})
        function leader.AbilitySystemComponent:GetGameplayEffectCount(ge)
            assert(ge==effect)
            return count
        end
        h.attrs[leader].Health_Max=300
        h.members={{actor=leader,team='red'},{actor=h.enemy({X=100,Y=0,Z=0}),team='blue'}}
        local exec=h.new({killOnLock=function(actor)return actor==leader end})
        h.run(exec,4)
        assert(h.attrs[leader].Health==3 and h.attrs[leader].Health_Min==3 and exec:status().kills==0
            and exec:status().started==0,'living squad keeps the original leader protection')
        count=0
        h.attrs[leader].Health_Min=0
        h.run(exec,3)
        assert(h.attrs[leader].Health==3 and exec:status().kills==0,'the released squad floor must not leave a pending kill')
    end
end
-- Out of reach by design, a minion, or off the lock again: not ended.
do
    local h=harness()
    local reach=h.boss('BP_Monster_LengTu',1,1,{locks={},pairs={},rank='UltimateBoss'})
    local minion=h.boss('BP_Monster_Vessel_Child',1,1,{locks={},pairs={},rank='Standard'})
    local back=h.boss('BP_Monster_LeiDang',1,1,{locks={},pairs={},rank='GreatBoss'})
    for _,b in ipairs({reach,minion,back}) do h.attrs[b].Health_Max=300 end
    h.members={{actor=reach,team='red',untargetable=true},{actor=minion,team='red'},{actor=back,team='red'},{actor=h.enemy({X=100,Y=0,Z=0}),team='blue'}}
    local exec=h.new()
    h.run(exec,10);h.attrs[back].Health=100;h.run(exec,5);h.attrs[back].Health=1;h.run(exec,15)
    assert(exec:status().kills==0 and not h.all():find('按倒下收尾',1,true),h.all())
    h.run(exec,10)
    assert(h.all():find('按倒下收尾（GreatBoss）BP_Monster_LeiDang',1,true) and exec:status().kills==1,h.all())
end

-- Off, or no fight running: nothing.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',10,10)
    local enemy=h.enemy({X=200,Y=0,Z=0},{class='BP_Monster_MoTian'})
    local copyClass=class('Hun_CopyPose_C')
    local relative={Translation={X=0,Y=0,Z=2},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
    local head=object('meshhead',{parent=enemy.Mesh,relative=relative,reinitialized=0})
    function head:GetOwner()return enemy end
    function head:GetAttachParent()return self.parent end
    function head:GetAttachSocketName()return 'None' end
    function head:GetRelativeTransform()return self.relative end
    function head:K2_AttachToComponent(parent)self.parent=parent;return true end
    function head:K2_SetRelativeTransform(t)self.relative=t end
    function head:GetAnimInstance()return object('CopyPose',{GetClass=function()return copyClass end,
        AnimGraphNode_CopyPoseFromMesh={bUseAttachedParent=true}})end
    function head:SetAnimInstanceClass(cls)assert(cls==copyClass);self.reinitialized=self.reinitialized+1 end
    function head:ResetAnimInstanceDynamics()end
    function head:ForceClothNextUpdateTeleportAndReset()end
    h.meshes[#h.meshes+1]=head
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    local exec=h.new();h.run(exec,1.5)
    assert(head.parent==h.components[1] and head.LeaderPoseComponent==nil,
        'MoYuan CopyPose head must read the animated source directly, keeping its own face pose buffer')
    exec:stop('face restore')
    assert(head.parent==enemy.Mesh and head.relative.Translation.Z==2 and head.reinitialized==2,
        'restore the original attachment, transform and CopyPose instance')
    assert(h.components[1].destroyed,'detach original head before destroying the borrowed source')
end

-- Off, or no fight running: nothing.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',10,10)
    h.members={{actor=boss,team='red'},{actor=h.enemy({X=100,Y=0,Z=0}),team='blue'}}
    local off=h.new({enabled=false})
    h.run(off,3)
    h.fighting=false
    local idle=h.new()
    h.run(idle,3)
    assert(#h.calls==0 and off:status().started==0 and idle:status().started==0)
end
-- The native continuous-execution action otherwise returns true even with no second enemy.
-- Check the actual execution integration, preserving native rejection when a candidate does exist.
do
    local h=harness()
    local path='/PBZCombatAsset/Prototypes/Actions/GAA_ContinuousExecution.GAA_ContinuousExecution_C:K2_CanActivateAction'
    h.found[path]=object('CanActivateAction')
    local hooks,removed={},0
    local boss=h.boss('BP_Monster_GuiChai_Gun',10,10,{rank='Standard',pairs={GUN}})
    local enemy=h.enemy({X=200,Y=0,Z=0})
    local nextEnemy=h.boss('BP_Monster_GuiChai_Gun',500,0,{rank='Standard',pairs={GUN},at={X=250,Y=0,Z=0}})
    h.members={{actor=boss,team='red'},{actor=enemy,team='blue'}}
    local exec=h.new({registerHook=function(p,callback)assert(p==path);hooks[p]=callback;return 11,12 end,
        unregisterHook=function(p,pre,post)assert(p==path and pre==11 and post==12);hooks[p]=nil;removed=removed+1 end})
    h.run(exec,1.5)
    local ability=object('ExecutionAbility',{GetClass=function()return GUN.ExecutionAbility end})
    local avatar=enemy
    local action=object('ContinuousExecution',{GetAvatarActor=function()return avatar end,GetAbility=function()return ability end,
        TargetingHandlerTag={TagName='Targeting.Handler.ContinuousExecution.Execution'},ExecutionType={TagName='Execution.Type.Combat'}})
    local function nativeDecision(original)
        local override=hooks[path] and hooks[path](action)
        if override~=nil then return override end
        return original
    end
    action.K2_CanActivateAction=function()return nativeDecision(true)end
    assert(nativeDecision(true)==false,'no next enemy: must not enter native slow-motion/QTE window')
    for _=1,100 do assert(nativeDecision(true)==false)end
    h.run(exec,0.5)
    assert(h.all():find('后续读回 CanActivate=false',1,true),h.all())
    local _,decisionLines=h.all():gsub('阻止空连携窗口：','')
    assert(decisionLines==1,'frame-by-frame predicate calls must not exhaust the readback log budget')
    h.members[3]={actor=nextEnemy,team='blue'}
    assert(nativeDecision(true)==false,'a teammate is not a chain target')
    h.members[3].team='red';h.attrs[nextEnemy].Health=0
    assert(nativeDecision(true)==false,'a corpse is not a chain target')
    h.attrs[nextEnemy].Health=500
    assert(nativeDecision(true)==true,'a nearby full-health chain-eligible enemy must remain allowed')
    assert(nativeDecision(false)==false,'never force a native angle/path rejection into true')
    nextEnemy.at={X=2000,Y=0,Z=0}
    assert(nativeDecision(true)==false,'the native standard chain range is 1600 cm')
    nextEnemy.at={X=250,Y=0,Z=0};h.tags[nextEnemy]={['CharacterType.AI.Boss']=1}
    assert(nativeDecision(true)==false,'native standard chain filter excludes bosses')
    h.tags[nextEnemy]={['CharacterState.Unselectable']=1}
    assert(nativeDecision(true)==false,'unselectable without KeepLock is excluded')
    h.tags[nextEnemy]['CharacterState.Unselectable.KeepLock']=1
    assert(nativeDecision(true)==true,'preserve the native KeepLock exception')
    h.tags[nextEnemy]={};nextEnemy['Actor Config'].TargetExecutionAnims={}
    assert(nativeDecision(true)==true,'chain skills choose their own follow-up; do not require the ordinary execution-pair list')
    avatar=h.player
    assert(nativeDecision(true)==true and nativeDecision(false)==false,'the player keeps the original result')
    avatar=enemy
    local extension=object('OwnedExtension',{bFinished=false})
    function extension:Deactivate()self.bFinished=true;self.deactivated=true end
    local qte=object('OwnedQTE',{ExtensionObj=extension})
    function qte:EndTask()self.ended=true end
    action['QTE Task']=qte;action.ExecutionEnabled=true
    action.SelectedTarget=nextEnemy
    local chainPresses=0
    function action:ManualCallExecutionInput()chainPresses=chainPresses+1 end
    h.attrs[nextEnemy].Health=500
    nativeDecision(true);h.run(exec,0.5);h.run(exec,0.5)
    assert(chainPresses==1,'a live native-selected enemy gets one automatic NPC continuation input')
    h.attrs[nextEnemy].Health=0
    assert(nativeDecision(true)==true,'a started window must reach its native end/cleanup even if its candidate disappears')
    local foreignTask=object('PlayerQTE',{EndTask=function()error('must not end player QTE')end})
    local foreignAction=object('PlayerContinuous',{GetAvatarActor=function()return h.player end,['QTE Task']=foreignTask})
    assert(hooks[path](foreignAction)==nil)
    local old=hooks[path]
    exec:stop('chain guard regression')
    assert(removed==1 and old(action)==nil,'remove the hook and silence stale callbacks when stopping')
    assert(qte.ended and extension.deactivated and extension.bFinished,'owned QTE and UI extension must be closed on stop')
end
-- Contextual types use live target tags/type, and rider clips follow the native montage selection.
do
    local h=harness()
    local left=pair('Execution.Type.Custom.HorseCartCombat','GA_Hun_BEx_Common_GuiChai_TwinBlade_HorseCartCombat_L_01_C','GA_Hun_BEd_Common_GuiChai_TwinBlade_HorseCartCombat_L_01_C')
    local right=pair('Execution.Type.Custom.HorseCartCombat','GA_Hun_BEx_Common_GuiChai_TwinBlade_HorseCartCombat_R_01_C','GA_Hun_BEd_Common_GuiChai_TwinBlade_HorseCartCombat_R_01_C')
    left.TargetRequiredTags={GameplayTags={{TagName='Cart.Left'}}};right.TargetRequiredTags={GameplayTags={{TagName='Cart.Right'}}}
    local target=h.boss('CartGuard',100,0,{rank='Standard',locks={},pairs={left,right}})
    target.BP_SGameDriverComponent=object('Driver',{DrivingVehicle=object('Cart')})
    local enabled=false
    target['Execution Component'].HasExecutionType=function()return enabled end
    h.tags[target]={['CharacterState.CanWeakExecute.Weak']=1,['Cart.Right']=1}
    h.members={{actor=target,team='red'},{actor=h.enemy({X=200,Y=0,Z=0}),team='blue'}}
    local exec=h.new();h.run(exec,1)
    assert(exec:status().started==0,'a configured cart pair is not an active cart opportunity')
    enabled=true;h.run(exec,0.5)
    assert(exec:status().started==1 and h.components[1].playing=='HorseCart_SimpleExE_Right_02_Hun','select the right-side pair from live tags')
    exec:stop('cart regression')
end
do
    local h=harness()
    local riderPair=pair('Execution.Type.CombatRider','GA_Hun_BEx_Common_Rider_01_C','GA_Hun_BEd_Common_Rider_01_Rider_C')
    local target=h.boss('Rider',100,0,{rank='Standard',locks={},pairs={riderPair}})
    target.BP_SGameDriverComponent=object('Driver',{DrivingVehicle=object('Horse')})
    target['Execution Component'].HasExecutionType=function()return true end
    h.tags[target]={['Driver.Driving']=1,['CharacterState.CanRiderExecute']=1}
    local enemy=h.enemy({X=200,Y=0,Z=0},{executorMontage='SpearMan_Ride_GEx_01_R_Montage'})
    local native=object('RiderAbility',{bIsActive=true,GetAvatarActorFromActorInfo=function()return enemy end,
        GetClass=function()return riderPair.ExecutionAbility end,GetCurrentMontage=function()return enemy.nativeAnim:GetCurrentActiveMontage()end,
        K2_CancelAbility=function(self)self.bIsActive=false end})
    h.abilities.GA_Hun_BEx_Common_Rider_01_C={native}
    h.members={{actor=target,team='red'},{actor=enemy,team='blue'}}
    local loops,cancelled={},{}
    local exec=h.new({loop=function(_,fn)loops[#loops+1]=fn;return #loops end,cancel=function(id)cancelled[id]=true end})
    h.run(exec,0.5)
    local def=DATA.GA_Hun_BEx_Common_Rider_01_C.variants.SpearMan_Ride_GEx_01_R_Montage
    assert(h.components[1].playing==def.clip:match('%.([^%.]+)$') and h.components[1].rate==0,'start with the native R branch')
    enemy.nativeAnim.montage='SpearMan_Ride_GEx_01_L_Montage';enemy.nativeAnim.position=0.75;h.clock=1;loops[1]()
    def=DATA.GA_Hun_BEx_Common_Rider_01_C.variants.SpearMan_Ride_GEx_01_L_Montage
    assert(h.components[1].playing==def.clip:match('%.([^%.]+)$') and h.components[1].position==0.75,'follow a native branch change and clock')
    enemy.nativeAnim.montage=nil;h.clock=2;loops[1]();h.clock=2.4;loops[1]()
    assert(not exec:status().active and cancelled[1] and h.components[1].destroyed,'finish and cancel the body driver after the native montage ends')
end
assert(DATA.GA_Hun_BEx_Common_EMei_EMeiCi_01_C and DATA.GA_Hun_BEx_Common_WuXuan_C,'inherited execution data must exist')
assert(DATA.GA_Hun_BEx_Common_WuXuan_C.clip:find('Hun_WuXuan_GEx_01',1,true),'WuXuan must use its GUID-overridden clip')
do
    local h=harness()
    local O=require('execution_opportunities')
    h.found[O.executionPath]=object('PlayExactExecution');h.found[O.qtePath]=object('QTEBegin')
    local boss=h.boss('BP_Monster_LionDancer',1000,0,{pairs={},locks={},rank='UltimateBoss'})
    local executor=h.enemy({X=200,Y=0,Z=0})
    executor.brain.paused=true
    local key='GA_Hun_BDEx_Common_LionDancer_01_C'
    local def=DATA[key]
    local execClass,edClass=class(key),class('GA_Hun_BDEd_Common_LionDancer_01_C')
    executor.nativeAnim.montage=def.montage:match('%.([^%.]+)$');executor.nativeAnim.position=0.4
    boss.anim.montage='NativeCounterEd_Montage'
    local own=object('CounterAbility',{bIsActive=true,GetClass=function()return execClass end,
        GetAvatarActorFromActorInfo=function()return executor end,GetCurrentMontage=function()return executor.nativeAnim:GetCurrentActiveMontage()end,
        K2_CancelAbility=function(self)self.bIsActive=false end})
    h.abilities[key]={own}
    local hooks,queue,loops={},{},{}
    h.members={{actor=boss,team='red'},{actor=executor,team='blue'}}
    local e=h.new({registerHook=function(path,pre,post)hooks[path]=post or pre;return 1,2 end,
        unregisterHook=function(path)hooks[path]=nil end,defer=function(fn)queue[#queue+1]=fn;return #queue end,
        loop=function(_,fn)loops[#loops+1]=fn;return #loops end,cancel=function()end})
    h.run(e,0.5)
    assert(e:status().started==0,'a counter-only boss is not offered an ordinary finisher')
    hooks[O.executionPath](object('Component',{GetOwner=function()return executor end}),{ExecutionAbility=execClass,ExecutedAbility=edClass},boss,0)
    queue[1]()
    assert(e:status().started==1 and h.components[1].position==0.4,'adopt the already-running native counter and its clock')
    for _,c in ipairs(h.calls)do assert(not c:match('^play '),'never replay a native execution that already began')end
    executor.nativeAnim.montage=nil;h.clock=1;loops[1]();h.clock=1.4;loops[1]()
    assert(not e:status().active and e:status().kills==0 and executor.brain.paused,'keep boss phases and pre-existing AI pauses')
    h.tags[boss]={['CharacterState.CanWeakExecute.Weak']=1};h.run(e,20)
    assert(e:status().started==1,'do not cache the counter as a health/stagger finisher')
end
-- The Hun body (its mesh on Hun_Skin_Skeleton, like the executor clips) as executor and as guillotine victim.
local HUN_SKELETON_PATH='/HuaShira/Characters/EliteBoss/MBoss/Anim/Hun_EXD_ByMBoss.Hun_EXD_ByMBoss'
local MOYUAN_MONTAGE=DATA.GA_Hun_BEx_MoYuan_C.montage:match('%.([^%.]+)$')
local function hunExecutor(h,at,montage)
    local skeleton=h.found[HUN_SKELETON_PATH].Skeleton
    h.found[DATA.GA_Hun_BEx_MoYuan_C.clip].Skeleton=skeleton
    local hun=h.enemy(at,{class='BP_Monster_Hun',executorMontage=montage})
    hun.Mesh.GetSkeletalMeshAsset=function()return object('Hun_Skin',{Skeleton=skeleton})end
    return hun,skeleton
end
local function lines(h,text)local n=0;for _,line in ipairs(h.lines)do if line:find(text,1,true)then n=n+1 end end;return n end
-- 1-3: the executor's own mesh is on its clip's skeleton: no borrowed body, and that is no failure.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',100.5,100)
    local hun=hunExecutor(h,{X=300,Y=0,Z=0},MOYUAN_MONTAGE)
    h.members={{actor=boss,team='red'},{actor=hun,team='blue'}}
    local exec=h.new()
    h.run(exec,1.5)
    assert(exec:status().started==1 and exec:executing(hun),h.all())
    assert(#h.components==0 and hun.Mesh.LeaderPoseComponent==nil,'no borrowed body')
    assert(lines(h,'同骨架，直接用本体（不借身体，不算失败）：执行方=BP_Monster_Hun 网格骨架=Hun_Skin_Skeleton 动画=Hun_MoYuan_SpecialExE_01 骨架=Hun_Skin_Skeleton')==1,h.all())
    assert(lines(h,'同骨架直播读回 执行方动作='..MOYUAN_MONTAGE)==1 and lines(h,'借身体没成')==0 and lines(h,'改回借身体')==0,h.all())
    h.run(exec,MOYUAN_RUN)
    assert(not exec:status().active and exec:status().failures==0 and lines(h,'没有借身体')==1 and not hun.brain.paused,h.all())
    print('PASS a same-skeleton executor plays the execution on its own mesh, without borrowing, and it counts as no failure')
end
-- When its own montage does not show within 0.3 s it borrows a body from then on, until the battle is stopped.
do
    local h=harness()
    local boss=h.boss('BP_Monster_MoTian',100.5,100)
    local second=h.boss('BP_Monster_MoTian',100.5,100,{at={X=0,Y=100,Z=0}})
    local hun=hunExecutor(h,{X=300,Y=0,Z=0},'Some_Other_Montage')
    h.members={{actor=boss,team='red'},{actor=second,team='red'},{actor=hun,team='blue'}}
    local exec=h.new()
    h.run(exec,1.5)
    assert(exec:status().started==1 and #h.components==0 and lines(h,'同骨架，直接用本体')==1,h.all())
    h.run(exec,0.5)
    assert(#h.components==1 and hun.Mesh.LeaderPoseComponent==h.components[1],'it borrows after 0.3 s without its own montage')
    local clip=DATA.GA_Hun_BEx_MoYuan_C
    assert(h.components[1].playing=='Hun_MoYuan_SpecialExE_01' and math.abs(h.components[1].position-((clip.clip_from or 0)+0.5*(clip.rate or 1)))<1e-6)
    assert(lines(h,'同骨架直播失败，改回借身体：执行方=BP_Monster_Hun 0.5s 内执行方动作=Some_Other_Montage 期望='..MOYUAN_MONTAGE..'；借身体=成功')==1,h.all())
    h.run(exec,MOYUAN_RUN)
    assert(h.components[1].destroyed and exec:status().started==2,'the second boss follows: '..h.all())
    assert(lines(h,'同骨架，直接用本体')==1 and #h.components==2,'the second execution borrows at once')
    h.run(exec,MOYUAN_RUN)
    exec:stop('F4')
    local third=h.boss('BP_Monster_MoTian',100.5,100,{at={X=0,Y=-100,Z=0}})
    h.members={{actor=third,team='red'},{actor=hun,team='blue'}}
    h.run(exec,1.5)
    assert(exec:status().started==3 and lines(h,'同骨架，直接用本体')==2,'a stop gives the executor its own mesh back')
    exec:stop('F4')
    print('PASS an own-mesh execution that does not show borrows a body after 0.3 s, for the rest of the battle')
end
-- 1-4: a target with no pair of its own, a Hun body the nearest executor of the Hun bodies: the Hun weapon's pair,
-- only when the target's skeleton is the executed montage's.
local HUN_PAIRS=require('hun_execution_pairs')
local function weaponPairCase(targetSkeleton,isHun)
    local h=harness()
    local hun,skeleton=hunExecutor(h,{X=500,Y=0,Z=0},'Hun_JueYing_ExE_F_01_Montage')
    local thug=object('MaleThug_Skeleton')
    for _,entry in ipairs(HUN_PAIRS)do
        h.found[entry.execution]=class(entry.execution:match('%.([^%.]+)$'))
        h.found[entry.executed]=class(entry.executed:match('%.([^%.]+)$'))
        h.found[entry.victim]=object(entry.victim:match('%.([^%.]+)$'),{Skeleton=entry.victim_skeleton=='MaleThug_Skeleton' and thug or object(entry.victim_skeleton)})
        h.found[entry.timing.clip]=object(entry.timing.clip:match('%.([^%.]+)$'),{Skeleton=skeleton})
    end
    local target=h.boss('BP_Monster_MaleThug',500,0,{pairs={},locks={},rank='Standard'})
    h.attrs[target].Health_Max=5000
    local asset=object('MaleThug',{Skeleton=targetSkeleton=='thug' and thug or object(targetSkeleton)})
    target.Mesh.GetSkeletalMeshAsset=function()return asset end
    local nearer=h.enemy({X=100,Y=0,Z=0})
    h.tags[target]={['CharacterState.CanWeakExecute.Weak']=1}
    h.members={{actor=target,team='red'},{actor=nearer,team='blue'},{actor=hun,team='blue'}}
    local exec=h.new({isHun=isHun or function(actor)return actor==hun end})
    return h,exec,target,hun,nearer
end
do
    local h,exec,target,hun,nearer=weaponPairCase('thug')
    h.run(exec,0.5)
    assert(exec:status().started==1 and exec:executing(hun) and not exec:executing(nearer),'the Hun body, not the nearer enemy: '..h.all())
    assert(h.has('play GA_Hun_BEx_JueYing_M_01_C + GA_Hun_BEd_JueYing_M_01_C on BP_Monster_MaleThug_0 at 0.0'),table.concat(h.calls,' | '))
    assert(lines(h,'魂武器处决对 目标=BP_Monster_MaleThug 目标骨架=MaleThug_Skeleton 受害方骨架=MaleThug_Skeleton（MaleThug_Skeleton） 技能对=GA_Hun_BEx_JueYing_M_01_C 采用=true')==1,h.all())
    assert(lines(h,'来源=魂武器通用处决对')==1 and lines(h,'同骨架，直接用本体')==1 and #h.components==0,h.all())
    h.run(exec,HUN_PAIRS[1].timing.executor+1)
    assert(not exec:status().active and exec:status().kills==1 and h.has('apply GE_Kill_C level=0.0 context=table'),'a minion still standing is ended: '..h.all())
    print('PASS a Hun body executes a target with no pair of its own with its weapon pair when the skeletons match')
end
do
    local h,exec=weaponPairCase('GuiChai_Skeleton')
    h.run(exec,3)
    assert(exec:status().started==0 and lines(h,'采用=false')==#HUN_PAIRS and lines(h,'采用=true')==0,'each pair checked once and none taken: '..h.all())
    local h2,exec2=weaponPairCase('thug',function()return false end)
    h2.run(exec2,2)
    assert(exec2:status().started==0 and lines(h2,'魂武器处决对')==0,'without a Hun body nothing is looked at')
    local saved=require('hun_look').STEPS.weaponPairs
    require('hun_look').STEPS.weaponPairs=false
    local h3,exec3=weaponPairCase('thug')
    h3.run(exec3,2);require('hun_look').STEPS.weaponPairs=saved
    assert(exec3:status().started==0 and lines(h3,'魂武器处决对')==0,'the switch off leaves targets with no pair alone')
    print('PASS a weapon pair whose executed skeleton differs is not taken, and nothing changes without a Hun body or with the switch off')
end
-- 1-6: a guillotine victim on Hun_Skin_Skeleton plays the original montages on its own anim instance.
local function guillotineHun(h,takes)
    local skeleton=object('Hun_Skin_Skeleton')
    h.found[HUN_SKELETON_PATH].Skeleton=skeleton
    h.player.Mesh.GetSkeletalMeshAsset=function()return object('Hun_Skin',{Skeleton=skeleton})end
    local start=object('Hun_EXD_ByMBoss_Start_Montage',{Skeleton=skeleton})
    local finish=object('Hun_EXD_ByMBoss_Montage',{Skeleton=skeleton})
    h.found['/PBZCombatAsset/ActorData/Players/Hun/Montage/Execution/Hun_EXD_ByMBoss_Start_Montage.Hun_EXD_ByMBoss_Start_Montage']=start
    h.found['/PBZCombatAsset/ActorData/Players/Hun/Montage/Execution/Hun_EXD_ByMBoss_Montage.Hun_EXD_ByMBoss_Montage']=finish
    local victim=h.enemy({X=100,Y=0,Z=0},{class='BP_Monster_Hun'})
    victim.Mesh.GetSkeletalMeshAsset=function()return object('Hun_Skin',{Skeleton=skeleton})end
    local anim=victim.nativeAnim
    anim.rates={}
    function anim:Montage_Play(m,rate,_,at,stopAll)
        h.calls[#h.calls+1]='montage play '..m:GetFName():ToString()..' stopAll='..tostring(stopAll)
        if takes==false then return 0 end
        self.playingM=m;self.pos=at;self.rates[m]=rate;self.stopped=false;return 1
    end
    function anim:GetCurrentActiveMontage()return self.playingM end
    function anim:Montage_IsPlaying(m)return self.playingM==m and not self.stopped end
    function anim:Montage_GetPosition()return self.pos end
    function anim:Montage_SetPlayRate(m,r)self.rates[m]=r end
    function anim:Montage_GetPlayRate(m)return self.rates[m] end
    function anim:Montage_Stop(_,m)h.calls[#h.calls+1]='montage stop '..m:GetFName():ToString();self.stopped=true;self.playingM=nil end
    local action=object('ActiveNPCStrike',{bIsActive=true,AbilityTags={GameplayTags={{TagName={ToString=function()return 'Ability.Action' end}}}},
        GetAvatarActorFromActorInfo=function()return victim end,K2_CancelAbility=function(self)self.bIsActive=false end})
    victim.AbilitySystemComponent.LocalAnimMontageInfo={AnimatingAbility=action}
    local currentHit='None'
    victim['Hitreact Component']=object('Hitreact',{GetCurrentHitState=function()return {TagName={ToString=function()return currentHit end}}end,
        ChangeHitState=function(_,tag)currentHit=tag.TagName end})
    return victim,anim,start,finish
end
do
    local h=harness()
    local victim,anim,start,finish=guillotineHun(h)
    local timers,cancelled,alive={},{},true
    local exec=h.new({loop=function(_,fn)timers[#timers+1]=fn;return #timers end,cancel=function(id)cancelled[id]=true end})
    local ok,detail=exec:startGuillotineHold(victim,function()return alive end)
    assert(ok and tostring(detail):find('受害方=BP_Monster_Hun 本体播放=true 读回蒙太奇=Hun_EXD_ByMBoss_Start_Montage 播放中=true',1,true),tostring(detail))
    assert(#h.components==0 and victim.Mesh.LeaderPoseComponent==nil and h.has('montage play Hun_EXD_ByMBoss_Start_Montage stopAll=true'))
    assert(victim.brain:IsPaused(),'the same control hold as the borrowed path')
    anim.pos=0.5;timers[1]();assert(anim.rates[start]==1.0)
    anim.pos=0.91;timers[1]();assert(anim.rates[start]==0 and lines(h,'铡刀本体起手停在 位置=0.910 速率读回=0')==1,'held at the 0.9 s catch')
    h.clock=1;assert(exec:finishGuillotineHold(victim))
    assert(anim.playingM==finish and lines(h,'铡刀本体后半段 播放=true 读回蒙太奇=Hun_EXD_ByMBoss_Montage')==1 and lines(h,'验证=true')==1)
    local held,finished=exec:guillotineHeld(victim);assert(held and not finished)
    h.clock=4.8;timers[1]();held,finished=exec:guillotineHeld(victim);assert(held and finished,'finished once the finish montage has had its length')
    assert(exec:stopGrabPose('收尾读回',victim) and lines(h,'本体收尾蒙太奇保留')==1 and not h.has('montage stop Hun_EXD_ByMBoss_Montage'))
    assert(not victim.brain:IsPaused())
    -- Released before the catch point: the start montage is stopped.
    assert(exec:startGuillotineHold(victim,function()return alive end))
    alive=false;timers[2]()
    assert(cancelled[2] and h.has('montage stop Hun_EXD_ByMBoss_Start_Montage') and lines(h,'本体起手蒙太奇停止=true 读回播放中=false')==1,h.all())
    print('PASS a Hun-skeleton guillotine victim plays the original start and finish montages on its own body, held at the catch')
end
do
    local h=harness()
    local victim=guillotineHun(h,false)
    local timers={}
    local exec=h.new({loop=function(_,fn)timers[#timers+1]=fn;return #timers end,cancel=function()end})
    assert(exec:startGuillotineHold(victim,function()return true end))
    assert(lines(h,'铡刀本体播放没成，退回借身体：受害方=BP_Monster_Hun 本体播放=true 读回蒙太奇=无')==1,h.all())
    assert(h.has('montage stop Hun_EXD_ByMBoss_Start_Montage') and #h.components==1 and h.components[1].playing=='Hun_EXD_ByMBoss','falls back to the borrowed body')
    exec:stop('F4')
    local saved=require('hun_look').STEPS.guillotineSelf
    require('hun_look').STEPS.guillotineSelf=false
    local h2=harness();local v2=guillotineHun(h2)
    local e2=h2.new({loop=function(_,fn)return 1 end,cancel=function()end})
    assert(e2:startGuillotineHold(v2,function()return true end));require('hun_look').STEPS.guillotineSelf=saved
    assert(#h2.components==1 and not h2.has('montage play Hun_EXD_ByMBoss_Start_Montage stopAll=true'),'switch off: the borrowed body as before')
    print('PASS a Hun victim whose own montage does not read back falls back to the borrowed body, as does the switch off')
end
-- 随从魂: a Hun body summoned as a companion finishes what the player could, minions too, with the BOSS switch off.
local function companionHunCase(rank)
    local h=harness()
    local foe=h.boss('BP_Foe',100,0,{rank=rank or 'Elite'})
    h.attrs[foe].Health_Max=1000
    local hun=h.enemy({X=300,Y=0,Z=0},{class='BP_Monster_Hun'})
    local other=h.enemy({X=100,Y=0,Z=0})
    other.BP_PBZHatredManagerComponent=object('Hatred',{HatredList={foe}})
    h.tags[foe]={['CharacterState.CanWeakExecute.Weak']=1}
    h.fighting=false
    h.members={{actor=hun,team='companion'},{actor=other,team='companion'}}
    return h,foe,hun,other
end
do
    local h,foe,hun,other=companionHunCase('Elite')
    local exec=h.new({companions=function()return false end,isHun=function(actor)return actor==hun end})
    h.run(exec,0.5)
    assert(exec:status().started==1 and exec:executing(hun) and not exec:executing(other),'the Hun, not the nearer companion: '..h.all())
    exec:stop('regression')
    h,foe,hun,other=companionHunCase('UltimateBoss')
    exec=h.new({companions=function()return false end,isHun=function(actor)return actor==hun end})
    h.run(exec,0.5);assert(exec:status().started==1 and exec:executing(hun),'a boss too, with the switch off: '..h.all())
    exec:stop('regression')
    print('PASS a companion Hun executes a minion and a boss the player could execute, with the companion-boss switch off')
end
do
    local h,foe,hun=companionHunCase('Elite')
    foe['Execution Component'].CurrentExecutionInfo={Executor=h.player,Target=foe,IsTarget=true}
    local exec=h.new({companions=function()return false end,isHun=function(actor)return actor==hun end})
    h.run(exec,2);assert(exec:status().started==0,'the player has it: left alone')
    exec:stop('regression')
    h,foe,hun=companionHunCase('Elite')
    exec=h.new({companions=function()return false end,isHun=function()return false end})
    h.run(exec,2);assert(exec:status().started==0,'no Hun among the companions: minions stay with the player')
    exec:stop('regression')
    h,foe,hun=companionHunCase('Elite');h.tags[foe]={}
    exec=h.new({companions=function()return false end,isHun=function(actor)return actor==hun end})
    h.run(exec,2);assert(exec:status().started==0,'a foe that cannot be executed is not')
    exec:stop('regression')
    h,foe,hun=companionHunCase('Elite')
    h.members={{actor=hun,team='companion',reserve=true}}
    hun.BP_PBZHatredManagerComponent=object('Hatred',{HatredList={foe}})
    exec=h.new({companions=function()return false end,isHun=function(actor)return actor==hun end})
    h.run(exec,2);assert(exec:status().started==0,'a Hun in reserve is not in the field')
    exec:stop('regression')
    local saved=require('hun_look').STEPS.companionExecutions
    require('hun_look').STEPS.companionExecutions=false
    h,foe,hun=companionHunCase('Elite')
    exec=h.new({companions=function()return false end,isHun=function(actor)return actor==hun end})
    h.run(exec,2);require('hun_look').STEPS.companionExecutions=saved
    assert(exec:status().started==0,'the step switch off')
    exec:stop('regression')
    print('PASS a companion Hun leaves alone what the player has taken, what cannot be executed, and everything when it is absent or switched off')
end
do
    local h,exec,target,hun,nearer=weaponPairCase('thug')
    hun.BP_PBZHatredManagerComponent=object('Hatred',{HatredList={target}})
    h.fighting=false
    h.members={{actor=hun,team='companion'},{actor=nearer,team='companion'}}
    exec=h.new({isHun=function(actor)return actor==hun end,companions=function()return false end})
    h.run(exec,0.5)
    assert(exec:status().started==1 and exec:executing(hun) and not exec:executing(nearer),'the weapon pair for a foe with no pair: '..h.all())
    assert(lines(h,'来源=魂武器通用处决对')==1,h.all())
    exec:stop('regression')
    print('PASS a companion Hun uses its weapon pair on a foe with no pair of its own')
end
-- 随从的处决对: a companion Hun takes the pair of the weapon it holds, then the generic one, then the foe's own (a boss
-- its own first); a companion that is no Hun finishes a minion with no pair with the generic one, on a borrowed body.
local WEAPON='/PBZCombatAsset/ActorData/Players/Hun/Weapon/YanYueDao/Weapon_Hun_YanYueDao.Weapon_Hun_YanYueDao'
local WEAPON_PAIRS=require('hun_weapon_execution_data').forConfig(WEAPON)
assert(#WEAPON_PAIRS>0 and WEAPON_PAIRS[1].victim_skeleton=='MaleThug_Skeleton','the fixture weapon has a thug pair')
local WEAPON_GA=WEAPON_PAIRS[1].execution:match('%.([^%.]+)$')
local WEAPON_GD=WEAPON_PAIRS[1].executed:match('%.([^%.]+)$')
assert(WEAPON_GA~='GA_Hun_BEx_JueYing_M_01_C')
-- The wooden sword's own pairs are all for another skeleton.
local WOODEN='/PBZCombatAsset/ActorData/Players/Hun/Weapon/WoodenSword/Weapon_Hun_WoodenSword.Weapon_Hun_WoodenSword'
local WOODEN_PAIRS=require('hun_weapon_execution_data').forConfig(WOODEN)
assert(#WOODEN_PAIRS>0)
for _,entry in ipairs(WOODEN_PAIRS)do assert(entry.victim_skeleton~='MaleThug_Skeleton')end
local function known(h,list,thug)
    local skeleton=h.found[HUN_SKELETON_PATH].Skeleton
    for _,entry in ipairs(list)do
        h.found[entry.execution]=class(entry.execution:match('%.([^%.]+)$'))
        h.found[entry.executed]=class(entry.executed:match('%.([^%.]+)$'))
        h.found[entry.victim]=object(entry.victim:match('%.([^%.]+)$'),{Skeleton=entry.victim_skeleton=='MaleThug_Skeleton' and thug or object(entry.victim_skeleton)})
        h.found[entry.timing.clip]=object(entry.timing.clip:match('%.([^%.]+)$'),{Skeleton=skeleton})
    end
end
-- A thug with no pair of its own that two companions are after: a Hun body 5 m away and a nearer one that is no Hun.
local function companionPairCase(options,weaponKnown)
    local h,_,target,hun,nearer=weaponPairCase('thug')
    if weaponKnown then known(h,weaponKnown,target.Mesh.GetSkeletalMeshAsset().Skeleton) end
    nearer.BP_PBZHatredManagerComponent=object('Hatred',{HatredList={target}})
    h.fighting=false
    h.members={{actor=hun,team='companion'},{actor=nearer,team='companion'}}
    local extra={companions=function()return false end,isHun=function(actor)return actor==hun end}
    for k,v in pairs(options or {})do extra[k]=v end
    return h,h.new(extra),target,hun,nearer
end
do
    local h,exec,target,hun,nearer=companionPairCase({hunWeapon=function()return WEAPON end},WEAPON_PAIRS)
    h.run(exec,0.5)
    assert(exec:status().started==1 and exec:executing(hun),h.all())
    assert(h.has('play '..WEAPON_GA..' + '..WEAPON_GD..' on BP_Monster_MaleThug_0 at 0.0'),h.all())
    assert(lines(h,'来源=魂手持武器的处决对')==1 and lines(h,'来源=魂武器通用处决对')==0,h.all())
    assert(lines(h,'技能对='..WEAPON_GA..' 采用=true 来自=手持武器')==1 and lines(h,'技能对=GA_Hun_BEx_JueYing_M_01_C 采用=true 来自=通用')==1,'both lists are looked at, the weapon first: '..h.all())
    exec:stop('regression')
    print('PASS a companion Hun finishes a foe with the pair of the weapon it holds')
end
do
    -- The held weapon has no pair made for this skeleton: the generic pair.
    local h,exec,target,hun=companionPairCase({hunWeapon=function()return WOODEN end},WOODEN_PAIRS)
    h.run(exec,0.5)
    assert(exec:status().started==1 and exec:executing(hun),h.all())
    assert(h.has('play GA_Hun_BEx_JueYing_M_01_C + GA_Hun_BEd_JueYing_M_01_C on BP_Monster_MaleThug_0 at 0.0'),table.concat(h.calls,' | '))
    assert(lines(h,'来源=魂武器通用处决对')==1 and lines(h,'采用=false 来自=手持武器')==#WOODEN_PAIRS,h.all())
    exec:stop('regression')
    -- In the arena a Hun holding a weapon keeps to that weapon's pairs, as before.
    local h2,_,target2,hun2=weaponPairCase('thug')
    known(h2,WOODEN_PAIRS,target2.Mesh.GetSkeletalMeshAsset().Skeleton)
    local exec2=h2.new({isHun=function(actor)return actor==hun2 end,hunWeapon=function()return WOODEN end})
    h2.run(exec2,2)
    assert(exec2:status().started==0 and lines(h2,'来自=通用')==0 and lines(h2,'来自=手持武器')==#WOODEN_PAIRS,'the arena does not fall back: '..h2.all())
    print('PASS a companion Hun whose weapon has no fitting pair uses the generic pair; an arena Hun does not')
end
-- A minion that has its own pair, on the thug skeleton, with the generic pairs there.
local function ownPairCase(rank,options)
    local h,foe,hun,other=companionHunCase(rank)
    local thug=object('MaleThug_Skeleton')
    foe.Mesh.GetSkeletalMeshAsset=function()return object('MaleThug',{Skeleton=thug})end
    known(h,HUN_PAIRS,thug)
    local extra={companions=function()return false end,isHun=function(actor)return actor==hun end}
    for k,v in pairs(options or {})do extra[k]=v end
    return h,h.new(extra),foe,hun,other
end
do
    local h,exec,foe,hun=ownPairCase('Elite')
    h.run(exec,0.5)
    assert(exec:status().started==1 and exec:executing(hun),h.all())
    assert(h.has('play GA_Hun_BEx_JueYing_M_01_C + GA_Hun_BEd_JueYing_M_01_C on BP_Foe_0 at 0.0') and lines(h,'来源=魂武器通用处决对')==1,'the Hun pair before the minion own pair: '..h.all())
    exec:stop('regression')
    h,exec,foe,hun=ownPairCase('UltimateBoss')
    h.run(exec,0.5)
    assert(exec:status().started==1 and h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Foe_0 at 0.0') and lines(h,'魂武器处决对')==0,'a boss keeps its own pair: '..h.all())
    exec:stop('regression')
    local saved=require('hun_look').STEPS.companionWeaponFirst
    require('hun_look').STEPS.companionWeaponFirst=false
    h,exec,foe,hun=ownPairCase('Elite')
    h.run(exec,0.5);require('hun_look').STEPS.companionWeaponFirst=saved
    assert(exec:status().started==1 and h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Foe_0 at 0.0') and lines(h,'魂武器处决对')==0,'the step switch off: the minion own pair, as before: '..h.all())
    exec:stop('regression')
    -- A skeleton no Hun pair fits: the minion's own pair.
    h,exec,foe,hun=ownPairCase('Elite')
    foe.Mesh.GetSkeletalMeshAsset=function()return object('Doll',{Skeleton=object('Doll_Skeleton')})end
    h.run(exec,0.5)
    assert(exec:status().started==1 and h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Foe_0 at 0.0') and lines(h,'采用=true')==0,h.all())
    exec:stop('regression')
    print('PASS a companion Hun prefers its Hun pair on a minion that has its own, and falls back to the own pair; a boss keeps its own')
end
do
    -- A minion that outlives a Hun pair still has its own pair afterwards.
    local h,exec,foe,hun=ownPairCase('Elite',{immune=function(_,kind)return kind=='lethal' end})
    h.run(exec,0.5);assert(exec:status().started==1 and lines(h,'来源=魂武器通用处决对')==1,h.all())
    h.run(exec,HUN_PAIRS[1].timing.executor+1)
    assert(not exec:status().active and h.attrs[foe].Health>0,'it is still standing: '..h.all())
    local saved=require('hun_look').STEPS.companionWeaponFirst
    require('hun_look').STEPS.companionWeaponFirst=false
    h.run(exec,16);require('hun_look').STEPS.companionWeaponFirst=saved
    assert(exec:status().started==2 and h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Foe_0 at 0.0'),'its own pair is still its own: '..h.all())
    exec:stop('regression')
    print('PASS a minion that survives a Hun pair keeps its own pair')
end
do
    -- No Hun among the companions, 随从处决小怪 on: the nearest companion borrows a body for the generic pair.
    local h,exec,target,hun,nearer=companionPairCase({isHun=function()return false end,companionMinions=function()return true end})
    h.run(exec,0.5)
    assert(exec:status().started==1 and exec:executing(nearer) and not exec:executing(hun),h.all())
    assert(h.has('play GA_Hun_BEx_JueYing_M_01_C + GA_Hun_BEd_JueYing_M_01_C on BP_Monster_MaleThug_0 at 0.0') and lines(h,'来源=魂武器通用处决对')==1,table.concat(h.calls,' | '))
    assert(#h.components==1 and lines(h,'同骨架，直接用本体')==0,'it is no Hun body: it borrows one: '..h.all())
    exec:stop('regression')
    h,exec=companionPairCase({isHun=function()return false end})
    h.run(exec,2);assert(exec:status().started==0 and lines(h,'魂武器处决对')==0,'the switch off: left to the player')
    exec:stop('regression')
    h,exec,target=companionPairCase({isHun=function()return false end,companionMinions=function()return true end})
    target['Execution Component'].CurrentExecutionInfo={Executor=h.player,Target=target,IsTarget=true}
    h.run(exec,2);assert(exec:status().started==0,'the player has it: left alone')
    exec:stop('regression')
    h,exec,target=companionPairCase({isHun=function()return false end,companionMinions=function()return true end})
    target.Mesh.GetSkeletalMeshAsset=function()return object('Doll',{Skeleton=object('Doll_Skeleton')})end
    h.run(exec,2);assert(exec:status().started==0 and lines(h,'采用=true')==0,'a skeleton the generic pair was not made for is not executed')
    exec:stop('regression')
    local saved=require('hun_look').STEPS.weaponPairs
    require('hun_look').STEPS.weaponPairs=false
    h,exec=companionPairCase({isHun=function()return false end,companionMinions=function()return true end})
    h.run(exec,2);require('hun_look').STEPS.weaponPairs=saved
    assert(exec:status().started==0,'the Hun pair step switch off')
    exec:stop('regression')
    print('PASS with the minion switch on a companion that is no Hun finishes a minion with no pair by the generic Hun pair, on a borrowed body')
end
-- 随从魂谁都能处决: a foe on a skeleton no Hun pair was made for, with no pair of its own.
local function anyoneCase(rank,options,silent)
    local h,_,target,hun,nearer=weaponPairCase('GuiChai_Skeleton')
    if rank then
        target['Actor Config']['Difficulty Tag']={TagName={ToString=function()return 'CharacterType.Difficulty.'..rank end}}
    end
    local brain=object('BrainComponent',{IsPaused=function(self)return self.paused==true end})
    target.Controller=object('AIController',{BrainComponent=brain})
    target.brain=brain
    if silent then
        -- The game does not show the being-executed montage on this skeleton.
        local component=hun['Execution Component']
        local play=component.PlayExactExecution
        function component:PlayExactExecution(data,victim,startTime)
            local before=victim.anim.montage
            play(self,data,victim,startTime)
            victim.anim.montage=before
        end
    end
    hun.BP_PBZHatredManagerComponent=object('Hatred',{HatredList={target}})
    h.fighting=false
    h.members={{actor=hun,team='companion'},{actor=nearer,team='companion'}}
    local extra={companions=function()return false end,isHun=function(actor)return actor==hun end}
    for k,v in pairs(options or {})do extra[k]=v end
    return h,h.new(extra),target,hun,nearer
end
do
    local h,exec,target,hun,nearer=anyoneCase()
    h.run(exec,0.5)
    assert(exec:status().started==1 and exec:executing(hun) and not exec:executing(nearer),h.all())
    assert(h.has('play GA_Hun_BEx_JueYing_M_01_C + GA_Hun_BEd_JueYing_M_01_C on BP_Monster_MaleThug_0 at 0.0'),table.concat(h.calls,' | '))
    assert(lines(h,'来源=魂武器通用处决对（不是给目标骨架做的）')==1 and lines(h,'采用=true')==0,h.all())
    assert(lines(h,'魂处决对里没有给 BP_Monster_MaleThug 的骨架（GuiChai_Skeleton）做的：随从魂照样处决，可用 '..#HUN_PAIRS..' 对')==1,h.all())
    h.run(exec,HUN_PAIRS[1].timing.executor+1)
    assert(not exec:status().active and exec:status().kills==1 and exec:status().failures==0 and h.has('apply GE_Kill_C level=0.0 context=table'),'a minion is ended as after any execution: '..h.all())
    assert(lines(h,'处决对不是给目标骨架做的')==0 and not target.brain.paused,'its montage showed: it is not held')
    print('PASS a companion Hun executes a foe on a skeleton no Hun pair was made for')
end
do
    local h,exec,target,hun=anyoneCase(nil,nil,true)
    h.run(exec,0.5);assert(exec:status().started==1,h.all())
    h.run(exec,2)
    assert(exec:status().active and exec:executing(hun),'no being-executed montage in 1.5 s does not end it: '..h.all())
    assert(target.brain.paused and lines(h,'处决对不是给目标骨架做的')==1 and lines(h,'目标没有播被处决动作')==1,'the target is held where it stands, said once: '..h.all())
    h.run(exec,HUN_PAIRS[1].timing.executor+1)
    assert(not exec:status().active and exec:status().failures==0 and exec:status().kills==1 and h.has('apply GE_Kill_C level=0.0 context=table'),h.all())
    assert(not target.brain.paused and lines(h,'目标恢复AI=true')==1,'its AI is given back at the end: '..h.all())
    print('PASS a foe that shows no being-executed montage is held, the Hun plays its half out, and the foe is ended as usual')
end
do
    -- A boss with no pair of its own stays after the Hun's half, as after any execution off its lock.
    local h,exec,target,hun=anyoneCase('UltimateBoss')
    h.run(exec,0.5);assert(exec:status().started==1,h.all())
    h.run(exec,HUN_PAIRS[1].timing.executor+1)
    assert(not exec:status().active and h.attrs[target].Health>0 and not h.has('apply GE_Kill_C level=0.0 context=table'),h.all())
    exec:stop('regression')
    -- The player has it; the step switch off; no Hun among the companions.
    h,exec,target=anyoneCase()
    target['Execution Component'].CurrentExecutionInfo={Executor=h.player,Target=target,IsTarget=true}
    h.run(exec,2);assert(exec:status().started==0,'the player has it: left alone')
    exec:stop('regression')
    local saved=require('hun_look').STEPS.companionAnyone
    require('hun_look').STEPS.companionAnyone=false
    h,exec=anyoneCase()
    h.run(exec,2);require('hun_look').STEPS.companionAnyone=saved
    assert(exec:status().started==0 and lines(h,'魂处决对里没有给')==0,'the step switch off: only pairs made for the skeleton')
    exec:stop('regression')
    h,exec=anyoneCase(nil,{isHun=function()return false end,companionMinions=function()return true end})
    h.run(exec,2);assert(exec:status().started==0,'a companion that is no Hun keeps to pairs made for the skeleton')
    exec:stop('regression')
    print('PASS a boss with no pair stays standing after it; the player hold, the step switch and other companions are respected')
end
do
    -- A foe whose own pair cannot be used now (its tag condition is not met), on a skeleton that cannot be read.
    local function conditionCase(rank)
        local own=pair('Execution.Type.Combat','GA_Hun_BEx_MoYuan_C','GA_Hun_BEd_MoYuan_C')
        own.TargetRequiredTags={'CharacterState.NotCarried'}
        local h=harness()
        local foe=h.boss('BP_Foe',100,0,{rank=rank,pairs={own}})
        h.attrs[foe].Health_Max=1000
        local hun=h.enemy({X=300,Y=0,Z=0},{class='BP_Monster_Hun'})
        hun.BP_PBZHatredManagerComponent=object('Hatred',{HatredList={foe}})
        h.tags[foe]={['CharacterState.CanWeakExecute.Weak']=1}
        h.fighting=false
        h.members={{actor=hun,team='companion'}}
        known(h,HUN_PAIRS,object('MaleThug_Skeleton'))
        return h,h.new({companions=function()return false end,isHun=function(actor)return actor==hun end}),foe,hun
    end
    local h,exec,foe,hun=conditionCase('Elite')
    h.run(exec,0.5)
    assert(exec:status().started==1 and exec:executing(hun),h.all())
    assert(h.has('play GA_Hun_BEx_JueYing_M_01_C + GA_Hun_BEd_JueYing_M_01_C on BP_Foe_0 at 0.0') and lines(h,'（不是给目标骨架做的）')==1,'a minion whose own pair is closed gets the Hun pair: '..h.all())
    assert(lines(h,'的骨架（读不到）做的')==1,h.all())
    exec:stop('regression')
    h,exec=conditionCase('UltimateBoss')
    h.run(exec,2)
    assert(exec:status().started==0 and lines(h,'魂处决对里没有给')==0,'a boss that has its own pair is executed with that pair or not at all: '..h.all())
    exec:stop('regression')
    print('PASS a minion whose own pair is closed is still executed by a companion Hun; a boss that has its own pair is not')
end
-- An execution opportunity still needs the victim's remaining HP to be in range.
do
    local function attempt(hp,maximum,broken,overrides,own)
        local options={hunProfile=function()return {attributes=overrides} end}
        local h,exec,foe
        if own then h,exec,foe=ownPairCase('Elite',options)
        else h,exec,foe=companionPairCase(options) end
        h.attrs[foe].Health,h.attrs[foe].Health_Max=hp,maximum
        if broken then h.tags[foe]={['CharacterState.Stand.Break']=1} end
        h.run(exec,1)
        local started=exec:status().started
        exec:stop('test')
        return started
    end
    for _,own in ipairs({true,false})do
        assert(attempt(201,1000,true,{},own)==0,'a break above the default HP cap must not start a finisher')
        assert(attempt(200,1000,true,{},own)==1)
        assert(attempt(101,1000,false,{},own)==0 and attempt(100,1000,false,{},own)==1)
        local limits={ExecutionExecutorBreakHealthThreshold=.01,ExecutionExecutorNormalHealthThreshold=0}
        assert(attempt(11,1000,true,limits,own)==0 and attempt(10,1000,true,limits,own)==1)
        assert(attempt(1,1000,false,limits,own)==0)
        limits.ExecutionExecutorBreakHealthThreshold=0
        assert(attempt(1,1000,true,limits,own)==0)
        assert(attempt(10,nil,true,{},own)==0 and attempt(10,0,true,{},own)==0)
    end
    local arena,arenaExec,arenaTarget=weaponPairCase('thug')
    arena.tags[arenaTarget]['CharacterState.Stand.Break']=1
    arena.attrs[arenaTarget].Health_Max=1000
    arena.run(arenaExec,1)
    assert(arenaExec:status().started==0 and lines(arena,'魂暂缓自动处决')==1)
    arena.attrs[arenaTarget].Health=199
    arena.run(arenaExec,0.5);assert(arenaExec:status().started==1)
    arenaExec:stop('test')
    local h,foe,far,near=companionHunCase('UltimateBoss')
    local thresholds={[near]=0.01,[far]=0.20}
    local exec=h.new({isHun=function(actor)return thresholds[actor]~=nil end,
        hunProfile=function(actor)return {attributes={ExecutionExecutorBreakHealthThreshold=thresholds[actor]}} end})
    h.tags[foe]['CharacterState.Stand.Break']=1
    h.attrs[foe].Health=201
    h.run(exec,1);assert(exec:status().started==0)
    h.attrs[foe].Health=200
    h.run(exec,1);assert(exec:executing(far) and not exec:executing(near),'the nearer ineligible Hun must not hide the eligible one: '..h.all())
    exec:stop('test')
    print('PASS Hun automatic finishers respect separate normal/break HP caps, zero and unavailable maxima')
end
print('arena_executions ok')

-- Drive the registered ability callback through Exec.new, not just the eligibility predicate.
do
    local C,O=require('arena_counter_windows'),require('execution_opportunities')
    for _,mode in ipairs({'arena-red','arena-blue','companion','map'})do
        local h=harness()
        local world=object('World');local function outer()return world end
        local boss=h.boss('BP_Monster_GreatBladeMan',71487,1,{pairs={},locks={}})
        h.attrs[boss].Health_Max=636480
        local npc=h.enemy({X=600,Y=0,Z=0})
        boss.GetOuter,npc.GetOuter,h.player.GetOuter=outer,outer,outer
        local function pathClass(path)
            return object(path:match('%.(.+)$'),{GetFullName=function()return 'LegoAbilityBlueprintGeneratedClass '..path end})
        end
        local npcBase=object('NPC',{GetFullName=function()return 'Class /Script/ProjectPBZ.PBZCharacter_NPC' end})
        local cls=pathClass(C.BLADE);cls.GetSuperStruct=function()return npcBase end;boss.GetClass=function()return cls end
        local npcClass=pathClass('/Test/BP_Monster_GuiChai.BP_Monster_GuiChai_C')
        npcClass.GetSuperStruct=function()return npcBase end;npc.GetClass=function()return npcClass end
        local bossTeam=mode=='arena-red' and 'red' or mode=='arena-blue' and 'blue' or mode=='companion' and 'companion'
        local npcTeam=bossTeam=='red' and 'blue' or bossTeam=='blue' and 'red' or mode=='map' and 'companion'
        if bossTeam then h.members[#h.members+1]={actor=boss,class_path=C.BLADE,team=bossTeam} end
        if npcTeam then h.members[#h.members+1]={actor=npc,team=npcTeam} end
        local companion=mode=='map' and npc or mode=='companion' and boss
        if companion then companion.BP_PBZHatredManagerComponent=object('Hatred',{HatredList={companion==npc and boss or npc}}) end
        h.fighting=not companion
        local exPath=MOBS_PATH..'008_GreatBladeMan/Ability/Abilities/GA_Hun_BEx_Common_BladeMan.GA_Hun_BEx_Common_BladeMan_C'
        local edPath='/PBZCombatAsset/ActorData/Players/Hun/Abilities/Common/ExE/GA_Hun_BDEd_Common_AttackBladeMan_01.GA_Hun_BDEd_Common_AttackBladeMan_01_C'
        h.found[exPath]=pathClass(exPath);h.found[edPath]=pathClass(edPath);h.found[O.bladePath]=object('Callback')
        local hooks={};local gameThread,canAct=false,true
        local exec=h.new({getWorld=outer,assignedOpponent=function(a)return a==boss and npc or boss end,
            companions=function()return true end,inGameThread=function()return gameThread end,
            registerHook=function(p,pre,post)hooks[p]=post or pre;return 1,2 end,unregisterHook=function(p)hooks[p]=nil end})
        exec:tick()
        local event=assert(hooks[O.bladePath],mode)
        local timeline=object('Timeline',{CurrentTime=2.333})
        local gc=pathClass(C.BLADE_GRAB)
        local ability=object('Grab',{GetClass=function()return gc end,bIsActive=true,GetPlayTimelineTask=function()return timeline end,
            GetAvatarActorFromActorInfo=function()return boss end,['Execution Info']={Executor=boss,Target=npc}})
        npc['Actor State Component']=object('State',{GetOwner=function()return npc end,
            CanActivateNewState=function(_,t)return t.TagName=='CharacterState.Action' and canAct end})
        h.tags[boss]={[C.JUDGE]=1};event(ability);assert(not exec:status().active,mode..' off game thread')
        gameThread=true;canAct=false;event(ability);assert(not exec:status().active,mode..' cannot act')
        canAct=true;ability['Execution Info'].Target=h.player;event(ability);assert(not exec:status().active,mode..' real player owns encounter')
        ability['Execution Info'].Target=npc
        if companion then
            local manager=companion.BP_PBZHatredManagerComponent;local saved=manager.HatredList
            manager.HatredList={};event(ability);assert(not exec:status().active,'lost hostility')
            manager.HatredList=saved
        end
        event(ability);event(ability)
        local play='play GA_Hun_BEx_Common_BladeMan_C + GA_Hun_BDEd_Common_AttackBladeMan_01_C on '..boss:GetFName():ToString()..' at 2.333'
        assert(h.count(play)==1 and exec:status().active and h.all():find('启动读回=true',1,true),mode..' '..h.all())
        assert(h.attrs[boss].Health==71487 and h.attrs[boss].Health_Min==1,'the counter does not write HP or clear the native floor')
        if mode=='arena-red' then
            local second=h.boss('BP_Monster_GreatBladeMan',89000,1,{pairs={},locks={}})
            local helper=h.enemy({X=100,Y=20,Z=0});second.GetOuter,helper.GetOuter=outer,outer
            second.GetClass=function()return cls end;h.tags[second]={[C.JUDGE]=1}
            helper['Actor State Component']=object('State',{GetOwner=function()return helper end,CanActivateNewState=function()return true end})
            h.members[#h.members+1]={actor=second,class_path=C.BLADE,team='red'};h.members[#h.members+1]={actor=helper,team='blue'}
            exec:tick();ability.GetAvatarActorFromActorInfo=function()return second end
            ability['Execution Info']={Executor=second,Target=helper};event(ability)
            assert(helper['Execution Component'].CurrentExecutionInfo.Target==second,'the other pair may respond during the first presentation')
            assert(npc['Execution Component'].CurrentExecutionInfo.Target==boss and exec:status().active)
        end
        local plays=h.count(play);exec:stop('complete');event(ability);assert(h.count(play)==plays,'retained hook after stop')
    end
    print('PASS native Bi Feng handoff through full arena and companion handlers in both roles')
end
