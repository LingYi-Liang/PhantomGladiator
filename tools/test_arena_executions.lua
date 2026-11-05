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
        e=actor(opts.class or 'BP_Monster_GuiChai',{Mesh=mesh,['Execution Component']=component,at=at,yaw=0,
            Controller=object('AIController',{BrainComponent=brain})})
        e.AbilitySystemComponent=object('ASC',{GetGameplayTagCount=function(_,tag)return tagCount(e,tag.TagName)end})
        e.brain=brain
        e.nativeAnim=nativeAnim
        function e:K2_GetActorLocation()return self.at end
        function e:K2_SetActorRotation(rotation)h.calls[#h.calls+1]=string.format('turn %.0f',rotation.Yaw);self.yaw=rotation.Yaw;return true end
        function e:K2_GetActorRotation()return {Pitch=0,Yaw=self.yaw,Roll=0} end
        function e:AddComponentByClass(cls,manual,transform,deferred)
            local comp=object('SkeletalMeshComponent_0',{})
            function comp:K2_AttachToComponent(parent,socket)self.parent=parent;self.socket=socket end
            function comp:SetSkeletalMeshAsset(asset)self.asset=asset end
            function comp:SetVisibility(visible)self.visible=visible end
            function comp:PlayAnimation(anim,loop)self.playing=anim:GetFName():ToString();self.position=0;self.rate=1 end
            function comp:SetPosition(position)self.position=position end
            function comp:GetPosition()return self.position end
            function comp:SetPlayRate(rate)self.rate=rate end
            function comp:GetPlayRate()return self.rate end
            function comp:GetAnimInstance()return object('SingleNode',{SetRootMotionMode=function(_,mode)comp.rootMotion=mode end})end
            function comp:IsPlaying()return self.playing~=nil end
            function comp:K2_DestroyComponent(target)self.destroyed=(target==self);h.calls[#h.calls+1]='destroy body' end
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
        local exec=h.new({companions=function()return on end,isStand=opts.isStand})
        return h,exec,boss,mate,function(value)on=value end
    end
    regression('the switch off: a boss a companion is after is left to the player',function()
        local h,exec=companionCase({on=false})
        h.run(exec,2);assert(exec:status().started==0)
        exec:stop('regression')
    end)
    regression('the switch on: the companion executes a boss of the map, with no arena fight on',function()
        local h,exec,boss,mate=companionCase()
        h.run(exec,0.5)
        assert(exec:status().started==1,h.all())
        assert(exec:executing(mate) and not exec:executing(boss),'it can say who is executing')
        assert(h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Boss_0 at 0.0'),table.concat(h.calls,' | '))
        assert(h.all():find('随从处决登记 BP_Boss（UltimateBoss）',1,true),h.all())
        exec:stop('regression')
        assert(not exec:executing(mate))
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
    local _,waits=h.all():gsub('附近 20 米内没有对手','')
    assert(exec:status().started==0 and waits==1,h.all())
    dog.at={X=400,Y=0,Z=0}
    h.run(exec,0.5)
    assert(exec:status().started==1 and #h.components==0,h.all())
    assert(h.all():find('借身体没成，执行方原地站着：执行方不是人形骨架（没有 pelvis）',1,true),h.all())
    assert(h.has('play GA_Hun_BEx_MoYuan_C + GA_Hun_BEd_MoYuan_C on BP_Monster_MoTian_0 at 0.0'))
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
print('arena_executions ok')
