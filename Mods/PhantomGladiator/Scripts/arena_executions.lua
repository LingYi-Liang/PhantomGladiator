-- 怪对怪处决（实验，v0.37.7）. The player executes a unit through its execution component:
--   PlayExactExecution({ExecutionAbility=<executor side>, ExecutedAbility=<target side>}, target, StartTime)
-- and each side plays its own montage: the target its being-executed one on its own skeleton, the executor one made
-- for the player's skeleton (Hun_Skin_Skeleton). The pair is the target config's TargetExecutionAnims (60 configs:
-- 魔渊, 金面/铁面, 鬼差, 暴徒, 人偶, 大头娃娃, 武轩/浊碧 …) or, for 彭猛 and 毕峰, the one their own finishing skill
-- starts. Every NPC has the same component (BP_RenewalNPC 'Execution Component'), so in a fight the nearest enemy makes
-- that call when the target could be executed by the player: it carries CharacterState.CanWeakExecute.Weak (broken)
-- or .LowHealth (under its execution threshold), which GA_CommonUtilitiesPassive sets through GE_CanWeakExecute /
-- GE_CanLowHealthExecute; or it is a boss that has sat on its health lock for a second.
-- The executor turns to face the target first (the game warps the player that way). Its body cannot play the player's
-- montage, so it borrows one: a hidden component with the player's mesh plays the clip inside that montage, and the
-- executor's meshes follow that component's bones by name (SetLeaderPoseComponent; 176 of the game's character
-- skeletons share the player's core bone names). The primary mesh keeps TickPose enabled for its native montage
-- and root-motion warping. Other parts retain their prior tick policy; original policies are restored at the end.
-- Proportions differ, so it clips. The executor's clip plays to its
-- end even when the target falls earlier; then the borrowed body goes. A minion (config Difficulty Tag Mob, Standard
-- or Elite, the app's 小怪) still standing is ended with GE_Kill, as an execution ends it for the player; a boss
-- (MiniBoss … UltimateBoss) is left standing, it may have another phase, and can be executed again later, except one
-- executed on its health lock: that lock comes off and GE_Kill ends it. One execution at a time;
-- every step is logged with what it read back. Found offline (audit-tools), see REVERSE_ENGINEERING v0.37.7.
-- A lock is the config's own *LockHealth* effect, a pair's, or any Health_Min floor at most 1% of the unit's health:
-- 火流星：磷火意识 gets GE_LockHealth from its blueprint. Its execution is the player's QTE (GA_GuiChai_Red_P2_CA_04: a
-- dodge prompt at the lock, then heavy attack mashed through the execution), which another monster cannot press, so
-- the mod presses for it: the game's GameplayEvent.QTE.HuoLiuXing goes to the player's ability system, where the
-- executed side listens, every GAP seconds; the executor's ability and borrowed body play a hit each time and their
-- finale once the executed side has moved to its own.
-- 随从处决 BOSS (the app switch, companion_executions.lua): outside the arena's teams, a boss on a companion's hatred list,
-- summoned with no team or of the map, can be executed the same way by the nearest companion. Minions stay the player's.
local U=require('ue_observe')
local Stats=require('character_stats')
local PoseProbe=require('execution_pose_probe')
local Chain=require('execution_chain')
local CopyPose=require('execution_copy_pose')
local Playback=require('execution_playback')
local Opportunities=require('execution_opportunities')
local Rules=require('execution_rules')
local Exec={}

local MOBS='/PBZCombatAsset/ActorData/Mobs/'
local GE_LOCK='/PBZCombatAsset/Prototypes/GameplayEffects/GE_LockHealth.GE_LockHealth_C'
-- Bosses whose pair is started from their own skill, not listed in their config. start: the StartTime the skill
-- passes; locks: the lock effects it removes, with unlock='start' when it removes them as the execution starts.
local PAIRS={
    BP_Monster_GuiChai_Red_P2={
        execution=MOBS..'075_GuiChai_Red_P2/Ability/GA_GuiChai_Red_P2_BEx_01.GA_GuiChai_Red_P2_BEx_01_C',
        executed=MOBS..'075_GuiChai_Red_P2/Ability/GA_GuiChai_Red_P2_BEd_01.GA_GuiChai_Red_P2_BEd_01_C',
        start=0.1,locks={GE_LOCK},unlock='start'},
    BP_Monster_PengMeng_Axe={
        execution=MOBS..'044_PengMeng/Ability/Axe/Abilities/CA/GA_Hun_BEx_Common_PengMeng_V2.GA_Hun_BEx_Common_PengMeng_V2_C',
        executed=MOBS..'044_PengMeng/Ability/Axe/Abilities/CA/GA_Hun_BEd_Common_PengMeng.GA_Hun_BEd_Common_PengMeng_C'},
    BP_Monster_GreatBladeMan={
        execution=MOBS..'008_GreatBladeMan/Ability/Abilities/GA_Hun_BEx_Common_BladeMan.GA_Hun_BEx_Common_BladeMan_C',
        executed='/PBZCombatAsset/ActorData/Players/Hun/Abilities/Common/ExE/GA_Hun_BDEd_Common_AttackBladeMan_01.GA_Hun_BDEd_Common_AttackBladeMan_01_C'},
}
local TYPES={'Execution.Type.Custom.HorseCartCombat','Execution.Type.CombatRider','Execution.Type.Combat','Execution.Type.Custom.JiangJun'}
local CONTEXTUAL={['Execution.Type.CombatRider']=true,['Execution.Type.Custom.HorseCartCombat']=true}
-- The player could execute it now (GA_CommonUtilitiesPassive).
local EXECUTABLE={'CharacterState.CanWeakExecute.Weak','CharacterState.CanWeakExecute.LowHealth'}
local GE_KILL='/Game/PBZContent/Blueprint/Ability/GameplayEffects/GE_Kill.GE_Kill_C'
-- Locks applied outside configs (blueprints, skills, AI scripts, summons); taken off too when they are loaded.
local GENERIC_LOCKS={GE_LOCK,'/PBZCombatAsset/Prototypes/GameplayEffects/GE_LockHealthButCanExecuted.GE_LockHealthButCanExecuted_C'}
local DEATH_LOCK=0.01       -- a floor of unknown source counts as a lock up to this share of Health_Max (not a phase)
local ABILITY_LIBRARY='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
-- The executor's own AI kept choosing moves during the first test (魔渊 started attacks 1.1 s in and his capsule
-- wandered from 2 m to 14 m off the boss while his body played the execution), so its brain is paused meanwhile.
local AI_LIBRARY='/Script/SGameAI.Default__SGameAIFunctionLibrary'
local PAUSE_REASON='PhantomGladiator execution'
local MESH_CLASS='/Script/Engine.SkeletalMeshComponent'
local IDENTITY={Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}
-- Skinned parts that can follow a body: meshes, and Chaos cloth (魔渊's hair CA_Motian_Hair01 and three cloth pieces,
-- 彭猛's cape). The first build left the cloth on the body while the body followed the borrowed skeleton, and the
-- hair and cloth were left floating after the execution.
local MESH_KINDS={'SkeletalMeshComponent','ChaosClothComponent'}
local RESET_PHYSICS=2       -- ETeleportType::ResetPhysics
local SNAP=2                -- EAttachmentRule::SnapToTarget
local TICK_REFRESH=0        -- EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones (hidden, still posed)
local KEEP_ROOT_MOTION=0    -- ERootMotionMode::NoRootMotionExtraction: the borrowed body moves as the montage does
local HOLD=1.0              -- seconds on the floor before an execution starts
local REACH=600             -- cm: the executor is the nearest enemy within this (the game's Combat point: 500)
local LOCK_REACH=2000       -- a locked boss waits for no one else, so its executor may come from further away
local TAIL=0.3              -- the run ends this long after the executor's clip
local AGAIN=15              -- seconds before a boss that survived an execution can be executed again
-- 雷当, 献祭之蛇's second phase and 冷荼 lock at the end of their fight with no pair to be executed by: in their own fight
-- a level script ends them, here nothing would and the fight could not finish. After this long on the death lock they are
-- ended the way that script does it (SpawnerToDieNS: the lock off, GE_Kill), unless they are out of reach by design.
local STUCK_SECONDS=20
local GAP=0.5               -- seconds between the presses the mod makes in a QTE execution
local PRESSES=30            -- presses before it stops waiting for the executed side's finale and plays it itself
local THRESHOLDS={'FirstThreshold','SecondThreshold','ThirdThreshold'}
local LOG_CAP=160

local function short(object)
    if not U.valid(object) then return '?' end
    local ok,name=pcall(function()return object:GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end
local function className(actor)
    if not U.valid(actor) then return '?' end
    local ok,cls=pcall(function()return actor:GetClass()end)
    return ok and (short(cls):gsub('_C$','')) or '?'
end
local function fmt(v)return type(v)=='number' and string.format('%.1f',v) or tostring(v) end
-- A TWeakObjectPtr property may come back as the object or as a wrapper with Get().
local function weak(value)
    value=U.unwrap(value)
    if U.valid(value) then return value end
    local ok,object=pcall(function()return value:Get()end)
    return ok and U.valid(object) and object or nil
end
local function tickPoseOf(component)
    local value=U.field(component,'bFollowerShouldTickPose')
    if type(value)=='boolean' then return value end
    if value==0 or value==1 then return value==1 end
end

function Exec.new(options)
    local log=options.log or function()end
    local stats=options.attributes or Stats.new()
    local find=options.staticFind or function(path)return StaticFindObject(path)end
    local load=options.loadAsset or function(path)return LoadAsset(path)end
    local findAll=options.findAll or FindAllOf
    local name=options.fname or FName
    local now=options.now
    local data=options.data or require('execution_data')
    local dataFold={};for key,value in pairs(data)do dataFold[key:lower()]=value end
    local function animationData(key)return data[key] or dataFold[key:lower()]end
    local poseProbe=PoseProbe.new({log=log,now=now,fname=name,staticFind=find})
    local chain=Chain.new({log=log,fname=name,staticFind=find,loadAsset=load,findAll=findAll,getPlayer=options.getPlayer,getWorld=options.getWorld,
        members=options.members,isImmortal=options.isImmortal,registerHook=options.registerHook,unregisterHook=options.unregisterHook,
        health=function(actor)local value=stats:read(actor,'Health');return value and value.current end})
    local self={enabled=options.enabled~=false,started=0,finished=0,failures=0,kills=0,message=''}
    local units={}      -- actor key -> {state='none'|'nopair'|'nodata'|'ready'|'done', pair, locks, timing, since, waited}
    local humanoidLines=0
    local tagRead=nil   -- how the executable tags read back the first time, logged once
    local active=nil
    local finish
    local callingNative=false
    local pendingBodies={}
    local lines=0
    local function say(m)if lines<LOG_CAP then lines=lines+1;log('[Execution] '..m)end end
    local function call(object,method,...)
        if not U.valid(object) then return false,'对象无效' end
        local n,args=select('#',...),{...}
        return pcall(function()return object[method](object,table.unpack(args,1,n))end)
    end
    local function object(path)
        local ok,found=pcall(find,path)
        if ok and U.valid(found) then return found,'已加载' end
        local loaded,value=pcall(load,path)
        if loaded and U.valid(value) then return value,'LoadAsset' end
        ok,found=pcall(find,path)
        if ok and U.valid(found) then return found,'LoadAsset 后找到' end
        return nil,'找不到'
    end
    local function read(actor,field)local v=stats:read(actor,field);return v and v.current or nil end
    local function montageOf(actor)
        local mesh=U.field(actor,'Mesh')
        local ok,anim=call(mesh,'GetAnimInstance')
        anim=ok and U.unwrap(anim) or nil
        local got,montage=call(anim,'GetCurrentActiveMontage')
        montage=got and U.unwrap(montage) or nil
        return U.valid(montage) and short(montage) or nil
    end
    local function distance(a,b)
        local okA,pa=pcall(options.getLocation,a);local okB,pb=pcall(options.getLocation,b)
        if not okA or not okB or not pa or not pb then return nil end
        local dx,dy,dz=pa.X-pb.X,pa.Y-pb.Y,pa.Z-pb.Z
        return math.sqrt(dx*dx+dy*dy+dz*dz)
    end

    -- A unit's lock effects (its config's passive *LockHealth* effects) and its execution pair, with the executor's clip,
    -- lengths and camera from execution_data.lua.
    local function tagsMatch(actor,container,required)
        for _,t in ipairs(U.array(U.struct(container,'GameplayTags')) or U.array(container) or {}) do
            local ok,n=pcall(function()return t:ToString()end)
            local gameTag=type(t)=='string' and {TagName=name(t)} or (U.struct(t,'TagName') and t or {TagName=ok and name(n) or t})
            local got,count=call(U.field(actor,'AbilitySystemComponent'),'GetGameplayTagCount',gameTag)
            count=got and U.unwrap(count) or nil
            if type(count)~='number' or (required and count<=0) or (not required and count>0) then return false end
        end
        return true
    end
    local function ruleAllows(actor,rule,role)
        if not rule then return true end
        if not tagsMatch(actor,rule[role..'_required'],true) or not tagsMatch(actor,rule[role..'_ignored'],false) then return false end
        if role=='target' and #(rule.any_target or {})>0 then
            for _,t in ipairs(rule.any_target)do if tagsMatch(actor,{t},true)then return true end end
            return false
        end
        return true
    end
    local function inspect(actor,checkConditions,locked)
        local info={state='none',locks={}}
        local config=U.field(actor,'Actor Config')
        if not U.valid(config) then return info end
        local rank=U.struct(U.field(config,'Difficulty Tag'),'TagName')
        local okRank,text=pcall(function()return rank:ToString()end)
        info.rank=okRank and type(text)=='string' and text:gsub('^CharacterType%.Difficulty%.','') or '?'
        info.boss=info.rank:find('Boss$')~=nil
        info.mob=info.rank=='Mob' or info.rank=='Standard' or info.rank=='Elite'
        for _,ge in ipairs(U.array(U.field(config,'Passive GameplayEffects')) or {}) do
            if U.valid(ge) and short(ge):find('LockHealth',1,true) then info.locks[#info.locks+1]=ge end
        end
        local execution,executed,source,missing
        local entries=U.array(U.field(config,'TargetExecutionAnims')) or {}
        for _,wanted in ipairs(TYPES) do
            for _,entry in ipairs(entries) do
                local tag=U.struct(U.struct(entry,'ExecutionType'),'TagName')
                local ok,text=pcall(function()return tag:ToString()end)
                local a,b=U.struct(entry,'ExecutionAbility'),U.struct(entry,'ExecutedAbility')
                local eligible=true
                if checkConditions and ok and text==wanted then
                    eligible=tagsMatch(actor,U.struct(entry,'TargetRequiredTags'),true) and tagsMatch(actor,U.struct(entry,'TargetIgnoredTags'),false)
                    if not locked or CONTEXTUAL[wanted] then eligible=eligible and ruleAllows(actor,Rules[wanted],'target') end
                    if CONTEXTUAL[wanted] then
                        local readType,hasType=call(U.field(actor,'Execution Component'),'HasExecutionType',{TagName=name(wanted)})
                        eligible=eligible and readType and U.unwrap(hasType)==true
                        -- These points are serialized even for an unmounted spearman. The rider/cart actions
                        -- dereference the current vehicle, so a static point alone is not a mounted opportunity.
                        if wanted=='Execution.Type.CombatRider' then
                            local driver=U.field(actor,'BP_SGameDriverComponent')
                            if not U.valid(driver) then local got,found=call(actor,'GetDriverComponent');driver=got and U.unwrap(found) end
                            eligible=eligible and U.valid(U.field(driver,'DrivingVehicle'))
                        end
                    end
                end
                if ok and text==wanted and U.valid(a) and U.valid(b) and eligible then
                    if animationData(short(a)) then execution,executed,source=a,b,'配置 TargetExecutionAnims '..text;info.executionType=text;break end
                    missing=missing or a
                end
            end
            if execution then break end
        end
        if not execution and missing and not PAIRS[className(actor)] then info.state='nodata';info.pair={execution=missing};return info end
        local known=not execution and PAIRS[className(actor)] or nil
        if known then
            local why1,why2
            execution,why1=object(known.execution);executed,why2=object(known.executed)
            source='BOSS 自己的收尾技能（执行方 '..why1..'，被处决方 '..why2..'）'
            for _,path in ipairs(known.locks or {}) do
                local ge=object(path)
                if ge then info.locks[#info.locks+1]=ge end
            end
        end
        if not (U.valid(execution) and U.valid(executed)) then info.state='nopair';return info end
        -- A move that writes story progress (story_writes.lua) only when that progress is already there.
        if options.storyAllows then
            local allowed,why=options.storyAllows(execution)
            if not allowed then info.state='story';info.storyWhy=why;info.pair={execution=execution,executed=executed,source=source};return info end
        end
        info.timing=animationData(short(execution))
        if not info.timing then info.state='nodata';info.pair={execution=execution};return info end
        info.state='ready'
        info.pair={execution=execution,executed=executed,source=source,start=known and known.start,unlock=known and known.unlock,type=info.executionType}
        if info.executionType and info.executionType~='Execution.Type.Combat' then
            for _,point in ipairs(U.array(U.field(config,'Execution Target Points')) or {})do
                local tagName=U.struct(U.struct(point,'ExecutionTag'),'TagName')
                local got,text=pcall(function()return tagName:ToString()end)
                if type(tagName)=='string' then got,text=true,tagName end
                local radius=U.struct(point,'Radius')
                if got and text==info.executionType and type(radius)=='number' and radius>0 then
                    info.pair.reach=math.min(1000,math.max(info.pair.reach or 0,radius))
                end
            end
        end
        -- A pair taken from the boss's own skill is its finisher (彭猛's last segment kills whatever its health): the
        -- skill starts it on the lock, so that lock is its only trigger, not a break or a low-health mark.
        info.lockOnly=known~=nil
        return info
    end
    -- Sitting on a health lock: a Health_Min floor, the unit's known lock or one low enough to be a death lock.
    local function onLock(actor,unit,hp)
        local floor=read(actor,'Health_Min')
        if not floor or floor<=0 or hp>floor+1+floor*0.01 then return false end
        return #unit.locks>0 or floor<=DEATH_LOCK*(read(actor,'Health_Max') or 0)+1
    end
    -- CharacterState.CanWeakExecute.* the player's execution prompt waits for, read with GetGameplayTagCount.
    local function executable(actor)
        local asc=U.field(actor,'AbilitySystemComponent')
        for _,tag in ipairs(EXECUTABLE) do
            local ok,count=call(asc,'GetGameplayTagCount',{TagName=name(tag)})
            count=ok and U.unwrap(count) or nil
            if not tagRead then
                tagRead=true
                say('读处决标签 '..tag..' 单位='..className(actor)..' 调用='..tostring(ok)..' 读回='..tostring(count))
            end
            if type(count)=='number' and count>0 then return tag end
        end
    end
    local function isHumanoid(actor)
        local ok,bone=call(U.field(actor,'Mesh'),'GetBoneIndex',name('pelvis'))
        bone=ok and U.unwrap(bone) or nil
        local yes=type(bone)=='number' and bone>=0
        if humanoidLines<6 then
            humanoidLines=humanoidLines+1
            say('检查当前身体 '..className(actor)..' pelvis读回='..tostring(bone)..' 人形='..tostring(yes))
        end
        return yes
    end
    -- The nearest living enemy within reach; a locked boss takes anyone, any other target a humanoid only.
    -- team: the target's arena team, or nil for a companion's foe, which only companions go for.
    -- A helper the other side's boss brought out (member.aid, arena_controller.lua) does not finish anyone.
    local function opponent(target,team,reach,anyone,executionType)
        local best,bestDistance
        for _,member in ipairs(options.members() or {}) do
            local other=member.actor
            local against
            if team then against=(member.team=='blue' or member.team=='red') and member.team~=team
            else against=member.team=='companion' end
            if against and not member.reserve and not member.aid and U.valid(other) then
                local hp=read(other,'Health')
                local d=hp and hp>0 and distance(target,other)
                if d and d<=reach and (not bestDistance or d<bestDistance) and (anyone or isHumanoid(other))
                    and (anyone or ruleAllows(other,Rules[executionType],'executor')) then
                    best,bestDistance=other,d
                end
            end
        end
        return best,bestDistance
    end
    -- The executor faces its target before the call, as the game warps the player to; read back.
    local function face(executor,target)
        local okA,a=call(executor,'K2_GetActorLocation');local okB,b=call(target,'K2_GetActorLocation')
        a,b=okA and U.unwrap(a),okB and U.unwrap(b)
        local ax,ay,bx,by=U.struct(a,'X'),U.struct(a,'Y'),U.struct(b,'X'),U.struct(b,'Y')
        if type(ax)~='number' or type(bx)~='number' or (ax==bx and ay==by) then return nil,'读不到双方位置，没转向' end
        local yaw=math.deg(math.atan(by-ay,bx-ax))
        local ok,err=call(executor,'K2_SetActorRotation',{Pitch=0,Yaw=yaw,Roll=0},false)
        local okR,rotation=call(executor,'K2_GetActorRotation')
        local after=okR and U.struct(U.unwrap(rotation),'Yaw')
        local diff=type(after)=='number' and math.abs((after-yaw+180)%360-180) or nil
        return yaw,string.format('转向目标 朝向=%.0f 调用=%s 读回=%s%s',yaw,tostring(ok),type(after)=='number' and string.format('%.0f',after) or '?',
            ok and ((diff and diff<=2) and '' or '（没转过去）') or '('..tostring(err)..')')
    end

    -- Every skinned part the executor owns, with whom it follows.
    local function partsOf(actor)
        local list,owner,seen={},U.key(actor),{}
        for _,kind in ipairs(MESH_KINDS) do
            local ok,all=pcall(findAll,kind)
            for _,comp in ipairs(ok and U.array(all) or {}) do
                local key=U.key(comp)
                if key and not seen[key] then
                    seen[key]=true
                    local got,o=call(comp,'GetOwner')
                    if got and U.key(U.unwrap(o))==owner then
                        list[#list+1]={comp=comp,cloth=kind=='ChaosClothComponent',leader=weak(U.field(comp,'LeaderPoseComponent')),
                            tickPose=tickPoseOf(comp)}
                    end
                end
            end
        end
        return list
    end
    -- The executor's Mesh and the parts that follow it.
    local function meshesOf(actor,main)
        local list={{comp=main,leader=weak(U.field(main,'LeaderPoseComponent')),tickPose=tickPoseOf(main)}}
        for _,part in ipairs(partsOf(actor)) do
            if U.key(part.comp)~=U.key(main) and part.leader and U.key(part.leader)==U.key(main) then list[#list+1]=part end
        end
        return list
    end
    -- Cloth and physics start over from the pose they now follow, instead of stretching from the old one.
    local function settle(parts)
        local cloth,meshes=0,0
        for _,part in ipairs(parts) do
            if part.cloth then
                if call(part.comp,'ForceNextUpdateTeleportAndReset') then cloth=cloth+1 end
            else
                local a=call(part.comp,'ResetAnimInstanceDynamics',RESET_PHYSICS)
                local b=call(part.comp,'ForceClothNextUpdateTeleportAndReset')
                if a and b then meshes=meshes+1 end
            end
        end
        return string.format('重置布料=%d 重置模型物理=%d',cloth,meshes)
    end
    local function borrowBody(executor,timing)
        if not timing then return nil,'这对技能没有登记执行方动画' end
        local mesh=U.field(executor,'Mesh')
        if not U.valid(mesh) then return nil,'执行方没有 Mesh' end
        local okBone,bone=call(mesh,'GetBoneIndex',name('pelvis'))
        if not okBone or type(U.unwrap(bone))~='number' or U.unwrap(bone)<0 then return nil,'执行方不是人形骨架（没有 pelvis）' end
        local montage,how=object(timing.clip)
        if not montage then return nil,'执行方动画'..how end
        local player=options.getPlayer and options.getPlayer() or nil
        local okAsset,asset=call(U.field(player,'Mesh'),'GetSkeletalMeshAsset')
        asset=okAsset and U.unwrap(asset) or nil
        if not U.valid(asset) then return nil,'读不到玩家的模型' end
        local skeleton=U.field(asset,'Skeleton')
        local cls=object(MESH_CLASS)
        if not cls then return nil,'找不到 SkeletalMeshComponent 类' end
        local okAdd,comp=call(executor,'AddComponentByClass',cls,true,IDENTITY,false)
        comp=okAdd and U.unwrap(comp) or nil
        if not U.valid(comp) then return nil,'加组件失败: '..tostring(comp) end
        local body={comp=comp,followers={},executor=executor,main=mesh,key=U.key(comp)}
        local steps={}
        local function step(label,ok,err)steps[#steps+1]=label..'='..tostring(ok)..(ok and '' or '('..tostring(err)..')')end
        step('挂到执行方模型',call(comp,'K2_AttachToComponent',mesh,name('None'),SNAP,SNAP,SNAP,false))
        step('换玩家模型',call(comp,'SetSkeletalMeshAsset',asset))
        step('隐藏时照样算骨骼',pcall(function()comp.VisibilityBasedAnimTickOption=TICK_REFRESH end))
        step('隐藏',call(comp,'SetVisibility',false,false))
        step('播动画',call(comp,'PlayAnimation',montage,false))
        if (timing.clip_from or 0)~=0 then
            local set=call(comp,'SetPosition',timing.clip_from,false)
            local got,at=call(comp,'GetPosition');at=got and U.unwrap(at)
            local verified=set and type(at)=='number' and math.abs(at-timing.clip_from)<0.002
            step('片段起点',verified,'读回='..tostring(at))
            if not verified then return body,'动画片段起点写后读回失败' end
        end
        if (timing.rate or 1)~=1 then
            local set=call(comp,'SetPlayRate',timing.rate)
            local got,rate=call(comp,'GetPlayRate');rate=got and U.unwrap(rate)
            local verified=set and rate==timing.rate
            step('片段速率',verified,'读回='..tostring(rate))
            if not verified then return body,'动画片段速率写后读回失败' end
        end
        local okAnim,anim=call(comp,'GetAnimInstance');anim=okAnim and U.unwrap(anim) or nil
        step('保留根运动',call(anim,'SetRootMotionMode',KEEP_ROOT_MOTION))
        for _,part in ipairs(meshesOf(executor,mesh)) do
            -- Its rendered pose follows the player skeleton, but the primary mesh must still tick its native
            -- montage so CharacterMovement/MotionWarping can advance. false froze it at 0 / StartTime in logs.
            local primary=U.key(part.comp)==U.key(mesh)
            local wantTick=primary or part.tickPose==true
            local ok,err=call(part.comp,'SetLeaderPoseComponent',comp,true,wantTick)
            local leader=weak(U.field(part.comp,'LeaderPoseComponent'))
            local verified=ok and leader~=nil and U.key(leader)==U.key(comp)
            body.followers[#body.followers+1]={comp=part.comp,leader=part.leader,cloth=part.cloth,verified=verified,tickPose=part.tickPose}
            step('跟随['..short(part.comp)..(part.cloth and '（布料）' or '')..']',verified,
                not ok and err or (leader==nil and '调用成功，读回不可读' or '读回不是借来的骨架'))
            if primary then
                local actual=tickPoseOf(part.comp)
                step('原生动画更新',actual==true,'请求=true 读回='..tostring(actual))
                say('主网格保留 TickPose：原值='..tostring(part.tickPose)..' 请求=true 读回='..tostring(actual))
            end
        end
        body.copyFollowers=CopyPose.follow(partsOf(executor),mesh,comp,log)
        if #body.copyFollowers>0 then say('独立CopyPose部件改接数='..#body.copyFollowers..'；执行方='..className(executor)) end
        local followed=0;for _,f in ipairs(body.followers)do if f.verified then followed=followed+1 end end
        local okPlaying,playing=call(comp,'IsPlaying')
        say(string.format('借身体 执行方=%s 玩家模型=%s 骨架=%s 动画=%s（%s） 跟随=%d/%d 播放中=%s；%s；%s',className(executor),short(asset),short(skeleton),
            short(montage),how,followed,#body.followers,tostring(okPlaying and U.unwrap(playing)),table.concat(steps,' '),settle(body.followers)))
        if followed==0 then return body,'执行方的模型没有跟上借来的骨架' end
        return body
    end
    local function returnBody(body)
        if not body then return '没有借身体' end
        local back=0
        for _,f in ipairs(body.followers) do
            local ok=call(f.comp,'SetLeaderPoseComponent',f.leader,true,f.tickPose==true)
            local leader=weak(U.field(f.comp,'LeaderPoseComponent'))
            local actualTick=tickPoseOf(f.comp)
            local tickRestored=f.tickPose==nil or actualTick==f.tickPose
            if U.valid(f.comp) and U.key(f.comp)==U.key(body.main) then
                say('恢复主网格 TickPose：原值='..tostring(f.tickPose)..' 读回='..tostring(actualTick)..' 验证='..tostring(tickRestored))
            end
            if ok and tickRestored and ((f.leader==nil and leader==nil) or (f.leader and leader and U.key(leader)==U.key(f.leader))) then back=back+1 end
        end
        -- Anything still on the borrowed skeleton (the engine may hand a follower's followers to the new leader)
        -- goes back to the executor's Mesh before that skeleton is removed.
        local swept,parts=0,U.valid(body.executor) and partsOf(body.executor) or {}
        for _,part in ipairs(parts) do
            if part.leader and U.key(part.leader)==U.key(body.comp) and U.valid(body.main) then
                if call(part.comp,'SetLeaderPoseComponent',body.main,true,false) then swept=swept+1 end
            end
        end
        if not CopyPose.restore(body.copyFollowers,log) then
            pendingBodies[body.key]=body
            return string.format('还原跟随=%d/%d；独立面部附着未恢复，保留借用骨架，等待停止/清场重试',back,#body.followers)
        end
        pendingBodies[body.key]=nil
        local destroyed=call(body.comp,'K2_DestroyComponent',body.comp)
        local settled=U.valid(body.executor) and settle(partsOf(body.executor)) or '执行方已失效'
        return string.format('还原跟随=%d/%d 补回=%d 移除借来的骨架=%s %s',back,#body.followers,swept,tostring(destroyed),settled)
    end

    -- Pause (on=true) or resume the executor's brain through the game's AI library, read back with IsPaused.
    local function holdAI(actor,on)
        local okLib,lib=pcall(find,AI_LIBRARY)
        local brain=U.field(U.field(actor,'Controller'),'BrainComponent')
        if not U.valid(brain) then return false,'读不到 AI 大脑' end
        local ok,err=call(okLib and lib or nil,on and 'PauseLogic' or 'ResumeLogic',brain,PAUSE_REASON)
        local okRead,paused=call(brain,'IsPaused')
        paused=okRead and U.unwrap(paused)
        return ok and paused==on,string.format('%s=%s 读回暂停=%s%s',on and '暂停AI' or '恢复AI',tostring(ok),tostring(paused),ok and '' or '('..tostring(err)..')')
    end

    local function ascOf(actor)
        local asc=U.field(actor,'AbilitySystemComponent')
        if U.valid(asc) then return asc end
        local okLib,lib=pcall(find,ABILITY_LIBRARY)
        local got,found=call(okLib and lib or nil,'GetAbilitySystemComponent',actor)
        return got and U.unwrap(found) or nil
    end
    -- The unit's own lock effects, then the generic ones that are loaded, each removed once; read back as Health_Min.
    local function unlock(actor,info)
        local asc=ascOf(actor)
        local list,seen,removed={},{},{}
        for _,ge in ipairs(info.locks) do list[#list+1]=ge end
        for _,path in ipairs(GENERIC_LOCKS) do
            local ok,ge=pcall(find,path)
            if ok and U.valid(ge) then list[#list+1]=ge end
        end
        for _,ge in ipairs(list) do
            local key=U.key(ge)
            if key and not seen[key] then
                seen[key]=true
                removed[#removed+1]=short(ge)..'='..tostring((call(asc,'RemoveActiveGameplayEffectBySourceEffect',ge,nil,-1)))
            end
        end
        return asc,removed,read(actor,'Health_Min')
    end
    -- An actor's active instance of an (instanced) ability class.
    local function abilityOn(actor,cls)
        if not U.valid(actor) then return nil end
        local ok,all=pcall(findAll,cls)
        for _,ability in ipairs(ok and U.array(all) or {}) do
            local got,avatar=call(ability,'GetAvatarActorFromActorInfo')
            if got and U.key(U.unwrap(avatar))==U.key(actor) and U.field(ability,'bIsActive')~=false then return ability end
        end
    end

    local function executionInfo(actor)
        local info=U.field(U.field(actor,'Execution Component'),'CurrentExecutionInfo')
        if info==nil then return '读不到' end
        local target=weak(U.struct(info,'Target'));local executor=weak(U.struct(info,'Executor'))
        return string.format('执行方=%s 目标=%s 是目标=%s',className(executor),className(target),tostring(U.struct(info,'IsTarget')))
    end

    -- A QTE execution's presses (see the header): own and theirs are the executor's and the executed side's ability.
    local function setupMash(executor,boss,info)
        local stages=info.timing.stages
        local m={spec=info.timing.mash,stages=stages,cameras=info.timing.cameras,presses=0,next=stages.open.length,clips={},thresholds={},
            ownClass=short(info.pair.execution),theirClass=short(info.pair.executed)}
        m.own,m.theirs=abilityOn(executor,m.ownClass),abilityOn(boss,m.theirClass)
        local loaded={}
        for _,key in ipairs({'hit','finale'}) do
            local clip,how=object(stages[key].clip)
            m.clips[key]=clip;loaded[#loaded+1]=key..'='..how
        end
        for i,field in ipairs(THRESHOLDS) do
            local v=U.field(m.own,field)
            if type(v)~='number' then v=U.field(m.theirs,field) end
            m.thresholds[i]=type(v)=='number' and v or nil
        end
        say(string.format('QTE 处决由 Mod 代按：%.2fs 起每 %.1f 秒一下，%s 发给玩家的能力系统（被处决方在那儿听）；执行方技能=%s 被处决方技能=%s 门槛=%s/%s/%s 动画[%s]',
            m.next,GAP,m.spec.event,m.own and '找到' or '没找到',m.theirs and '找到' or '没找到',tostring(m.thresholds[1]),
            tostring(m.thresholds[2]),tostring(m.thresholds[3]),table.concat(loaded,' ')))
        return m
    end
    -- The hit the executor plays on press c, picked as the executed side picks its own (GA_GuiChai_Red_P2_BEd_01).
    local function hitTimeline(m,c)
        local hit,th=m.spec.hit,m.thresholds
        if not (th[1] and th[2] and th[3]) then return hit[1] end
        if c<th[1] then return hit[1] elseif c<th[2] then return hit[2] end
        if not m.transition then m.transition=true;return hit[3] end
        return hit[4]
    end
    -- The executor's ability plays a timeline, its borrowed body that stage's clip and the camera that stage's track.
    local function stage(run,key,timeline)
        poseProbe:sample('before:'..timeline)
        local m=run.mash
        local played=m.own~=nil and (call(m.own,'PlayTimelineByName',name(timeline),1.0,0.0,0.0))
        local swapped=run.body~=nil and m.clips[key]~=nil and (call(run.body.comp,'PlayAnimation',m.clips[key],false))
        poseProbe:sample('after-call:'..timeline)
        -- Each hit timeline has its own camera track.
        local track=(m.cameras and m.cameras[timeline]) or m.stages[key].camera
        if options.camera and options.camera.stage and track then
            local ok,err=pcall(options.camera.stage,options.camera,track,timeline)
            if not ok then say('处决镜头换段出错：'..tostring(err)) end
        end
        return string.format('执行方技能 %s=%s 借来的骨架换动画=%s',timeline,tostring(played),tostring(swapped))
    end
    local function press(run,t)
        local m=run.mash
        m.presses=m.presses+1;m.next=t+GAP
        -- The abilities may only be live a frame after the call.
        local late=''
        if not m.own then m.own=abilityOn(run.executor,m.ownClass);if m.own then late=late..' 执行方技能这时才找到' end end
        if not m.theirs then m.theirs=abilityOn(run.boss,m.theirClass);if m.theirs then late=late..' 被处决方技能这时才找到' end end
        for i,field in ipairs(THRESHOLDS) do
            if not m.thresholds[i] then
                local v=U.field(m.own,field)
                if type(v)~='number' then v=U.field(m.theirs,field) end
                m.thresholds[i]=type(v)=='number' and v or nil
            end
        end
        local key,timeline,line
        if run.fell then
            key,timeline,line='finale',m.spec.finale,string.format('目标已倒下，执行方直接收尾 %.1fs',t)
        else
            local before=U.field(m.theirs,'ClickCount')
            local okLib,lib=pcall(find,ABILITY_LIBRARY)
            local player=options.getPlayer and options.getPlayer() or nil
            local tag={TagName=name(m.spec.event)}
            local sent,err=call(okLib and lib or nil,'SendGameplayEventToActor',player,tag,{EventTag=tag,Instigator=run.executor,Target=run.boss})
            local after=U.field(m.theirs,'ClickCount')
            local counted=type(before)=='number' and type(after)=='number' and after>before
            local montage=montageOf(run.boss)
            local finale=counted and (montage==m.spec.executed_finale or (m.thresholds[3]~=nil and after>=m.thresholds[3]))
            local direct=''
            if not counted then
                -- The event did not reach it: its timeline is played directly, picked by the mod's own count.
                local th=m.thresholds[3]
                local last=m.presses>=PRESSES or (th and m.presses>=th)
                local own=last and m.spec.finale or hitTimeline(m,m.presses)
                finale=last
                direct=string.format('；事件没算上，被处决方直接播 %s=%s',own,tostring((call(m.theirs,'PlayTimelineByName',name(own),1.0,0.0,0.0))))
                timeline=own
            elseif m.presses>=PRESSES and not finale then
                finale=true
                direct=string.format('；按满 %d 下还没进结局，被处决方直接播 %s=%s',PRESSES,m.spec.finale,
                    tostring((call(m.theirs,'PlayTimelineByName',name(m.spec.finale),1.0,0.0,0.0))))
            end
            key=finale and 'finale' or 'hit'
            timeline=finale and m.spec.finale or timeline or hitTimeline(m,after)
            line=string.format('代按第 %d 下 %.1fs：事件=%s%s 被处决方计数 %s→%s 目标动作=%s%s%s',m.presses,t,tostring(sent),
                sent and '' or '('..tostring(err)..')',tostring(before),tostring(after),tostring(montage),direct,late)
        end
        local played=stage(run,key,timeline)
        if key=='finale' then
            m.finale=t;run.length=t+m.stages.finale.length+TAIL
            say(string.format('%s；进结局，%s，%.1fs 后结束',line,played,m.stages.finale.length+TAIL))
        elseif m.presses<=3 or m.presses%5==0 then
            say(line..'；'..played)
        end
    end
    -- An ability the run left active is cancelled, read back.
    local function release(run)
        local m=run.mash
        local own=(m and m.own) or run.own or abilityOn(run.executor,short(run.info.pair.execution))
        local theirs=(m and m.theirs) or run.theirs or abilityOn(run.boss,short(run.info.pair.executed))
        local parts={}
        for _,side in ipairs({{'执行方',own,run.executor},{'被处决方',theirs,run.boss}}) do
            local ability=side[2]
            local got,avatar=call(ability,'GetAvatarActorFromActorInfo')
            if U.valid(ability) and U.valid(side[3]) and got and U.key(U.unwrap(avatar))==U.key(side[3]) and U.field(ability,'bIsActive')~=false then
                local ok=call(ability,'K2_CancelAbility')
                parts[#parts+1]=string.format('%s技能还在，取消=%s 读回仍在=%s',side[1],tostring(ok),tostring(U.field(ability,'bIsActive')))
            end
        end
        if m then return string.format('；QTE 代按 %d 下 %s%s',m.presses,m.finale and '进了结局' or '没进结局',#parts>0 and '，'..table.concat(parts,'，') or '') end
        return #parts>0 and '；本次普通处决收尾 '..table.concat(parts,'，') or ''
    end

    local function showCamera(run,timing,continuing)
        if not options.camera then return end
        local shown,err=pcall(options.camera.begin,options.camera,{executor=run.executor,target=run.boss,
            ability=short(run.info.pair.execution),body=run.body and run.body.comp or nil,yaw=run.yaw,camera=timing.camera,
            clip_from=timing.clip_from or 0,rate=timing.rate or 1,timeline_start=timing.start or 0,continuing=continuing})
        if not shown then say('处决镜头出错：'..tostring(err)) end
    end
    local function start(executor,boss,info,d,reason,adopted)
        local unit=units[U.key(boss)]
        if unit and not adopted then unit.state='done' end
        self.started=self.started+1
        local hp,floor=read(boss,'Health'),read(boss,'Health_Min')
        local yaw,turned
        if adopted then
            local got,rotation=call(executor,'K2_GetActorRotation')
            yaw=got and U.struct(U.unwrap(rotation),'Yaw') or 0;turned='沿用原生处决朝向'
        else yaw,turned=face(executor,boss) end
        say(string.format('开始（%s）目标=%s HP=%s 底线=%s 执行方=%s 距离=%.1fm 技能对=%s / %s 来源=%s；%s',reason,className(boss),fmt(hp),fmt(floor),
            className(executor),(d or 0)/100,short(info.pair.execution),short(info.pair.executed),info.pair.source,turned))
        local wantPlayback=info.timing.dynamic or (adopted and not info.timing.mash and info.timing.montage~=nil)
        local body,why
        if not wantPlayback then body,why=borrowBody(executor,info.timing) end
        poseProbe:begin(executor,boss,body and body.comp or nil)
        if why then say('借身体没成，执行方原地站着：'..why) end
        local paused,held
        if adopted and adopted.paused then paused,held=true,'沿用上段由Mod持有的AI暂停'
        else
            local got,wasPaused=call(U.field(U.field(executor,'Controller'),'BrainComponent'),'IsPaused')
            if got and U.unwrap(wasPaused)==true then paused,held=false,'AI原本已暂停，结束时保留原状态'
            else paused,held=holdAI(executor,true) end
        end
        local before=montageOf(boss)
        local component=U.field(executor,'Execution Component')
        chain:begin(executor,boss,info.pair.execution)
        local ok,err=true,'接到原生调用，只接管表现，不重复播放技能'
        if not adopted then
            callingNative=true
            ok,err=call(component,'PlayExactExecution',{ExecutionAbility=info.pair.execution,ExecutedAbility=info.pair.executed},boss,info.pair.start or 0.0)
            callingNative=false
        end
        poseProbe:sample('after-PlayExactExecution')
        say(string.format('调用 PlayExactExecution=%s %s；%s；执行方组件：%s；目标组件：%s；目标动作=%s 执行方动作=%s',tostring(ok),ok and '' or tostring(err),
            held,executionInfo(executor),executionInfo(boss),tostring(montageOf(boss)),tostring(montageOf(executor))))
        if not ok then
            self.failures=self.failures+1
            chain:stop('PlayExactExecution failed')
            poseProbe:stop('PlayExactExecution failed')
            local resumed=paused and select(2,holdAI(executor,false)) or '没有暂停 AI'
            say('没能开始：'..returnBody(body)..'；'..resumed);self.message='调用失败';return
        end
        -- The executor's clip plays to its end, past the target's fall: the game's execution does too.
        local length=(info.timing.executor or 120)+TAIL
        local after=montageOf(boss)
        if info.pair.unlock=='start' then
            local _,removed,floor=unlock(boss,info)
            say(string.format('照它自己的技能，处决一开始就去锁血[%s] 读回底线=%s',table.concat(removed,' '),fmt(floor)))
        end
        local mash=info.timing.mash and setupMash(executor,boss,info) or nil
        if mash then length=mash.next+PRESSES*GAP+info.timing.stages.finale.length+TAIL end
        active={executor=executor,boss=boss,info=info,body=body,t0=now(),length=length,before=before,mash=mash,yaw=yaw,
            dynamic=wantPlayback,adopted=adopted~=nil,
            own=abilityOn(executor,short(info.pair.execution)),theirs=abilityOn(boss,short(info.pair.executed)),
            montage=after~=before and after or nil,gone=nil,samples=0,paused=paused,byLock=reason=='卡在锁血线'}
        self.message='处决中：'..className(executor)..' → '..className(boss)
        local run=active
        if run.dynamic then
            local variants=info.timing.variants or {[info.timing.montage:match('%.([^%.]+)$')]=info.timing}
            run.playback=Playback.start({actor=executor,variants=variants,now=now,loop=options.loop,cancel=options.cancel,
                ability=function()run.own=run.own or abilityOn(executor,short(info.pair.execution));return run.own end,
                onVariant=function(def,key,position)
                    if not run.body then
                        local b,problem=borrowBody(executor,def);run.body=b
                        if problem then return false,problem end
                        showCamera(run,def,adopted and adopted.continuing)
                    else
                        local clip=object(def.clip)
                        if not clip or not call(run.body.comp,'PlayAnimation',clip,false) then return false,'切换片段失败' end
                        local got,anim=call(run.body.comp,'GetAnimInstance')
                        call(got and U.unwrap(anim),'SetRootMotionMode',KEEP_ROOT_MOTION)
                        showCamera(run,def,true)
                    end
                    local set=call(run.body.comp,'SetPlayRate',0)
                    local got,rate=call(run.body.comp,'GetPlayRate');rate=got and U.unwrap(rate)
                    if not set or rate~=0 then return false,'未能交给原生时间驱动：'..tostring(rate) end
                    say(string.format('动态分支 读回原生蒙太奇=%s 时间轴=%s 原生位置=%.3f 片段起点=%.3f',key,def.timeline,position,def.clip_from or 0))
                    return true
                end,
                onPosition=function(desired,position,def)
                    local ok=call(run.body and run.body.comp,'SetPosition',desired,false)
                    local got,actual=call(run.body and run.body.comp,'GetPosition');actual=got and U.unwrap(actual)
                    return ok and type(actual)=='number' and math.abs(actual-desired)<0.003,'要求='..desired..' 读回='..tostring(actual)
                end,
                onEnd=function(why,failed)if active==run then finish(why,failed) end end})
        else
            if adopted and run.body and U.valid(run.own) then
                local gm,montage=call(run.own,'GetCurrentMontage')
                local ga,anim=call(U.field(executor,'Mesh'),'GetAnimInstance')
                montage=gm and U.unwrap(montage)
                local gp,position=false,nil
                if U.valid(montage) then gp,position=call(ga and U.unwrap(anim),'Montage_GetPosition',montage) end
                position=gp and U.unwrap(position)
                if type(position)=='number' and position>=0 then
                    call(run.body.comp,'SetPosition',(info.timing.clip_from or 0)+position*(info.timing.rate or 1),false)
                    run.length=math.max(0,info.timing.executor-position)+TAIL
                end
            end
            showCamera(run,info.timing,adopted and adopted.continuing)
        end
    end
    local function endCamera(why)
        if not options.camera then return end
        local ok,err=pcall(options.camera.finish,options.camera,why)
        if not ok then say('处决镜头收尾出错：'..tostring(err)) end
    end

    -- keep: the boss never started its side, so it is not ended either (no bare "down at the lock").
    local function resume(run)
        if not run.paused then return '没有暂停 AI' end
        if not U.valid(run.executor) then return '执行方已失效，不恢复 AI' end
        return select(2,holdAI(run.executor,false))
    end
    finish=function(why,keep,handoff)
        local run=active;active=nil
        if run.playback then run.playback:stop() end
        poseProbe:stop(why)
        if not handoff then endCamera(why) end
        chain:closeTasks()
        local released=not handoff and release(run) or '；旧技能由原生切换处理'
        chain:stop(why)
        local back=returnBody(run.body)..'；'..(handoff and 'AI暂停交给下一段' or resume(run))..released
        local boss=run.boss
        local hp=U.valid(boss) and read(boss,'Health') or nil
        local kill='目标已倒下或失效'
        if handoff then
            kill='转交原生下一段，不对旧目标额外判死'
        elseif keep then
            self.failures=self.failures+1
            kill=#run.info.locks>0 and '没有处决起来，保留锁血' or '没有处决起来'
        elseif hp and hp>0 and run.info.boss and not run.byLock then
            -- A boss may have another phase: it stays, and may be executed again a little later.
            local unit=units[U.key(boss)]
            if unit and not run.adopted then unit.state='ready';unit.since=nil;unit.waited=nil;unit.again=now()+AGAIN end
            if run.adopted then kill='原生BOSS处决结束，保留后续阶段 HP='..fmt(hp)
            else kill=string.format('BOSS（%s）处决完还站着，不强制判死，%d 秒后可再被处决 HP=%s',run.info.rank,AGAIN,fmt(hp)) end
        elseif hp and hp>0 and (run.info.mob or (run.info.boss and run.byLock)) then
            local asc,removed,floor=unlock(boss,run.info)
            local ge=object(GE_KILL)
            local applied,err=false,'没有 GE_Kill'
            -- Level 0 and an empty context, exactly as the game's SpawnerToDieNS node ends a locked boss.
            if ge then applied,err=call(asc,'BP_ApplyGameplayEffectToSelf',ge,0.0,{}) end
            kill=string.format('%s（%s）：去锁血[%s] 读回底线=%s；GE_Kill=%s%s 读回HP=%s',run.info.boss and '锁血 BOSS 收尾' or '小怪处决完还站着，判死',
                run.info.rank,table.concat(removed,' '),fmt(floor),tostring(applied),applied and '' or '('..tostring(err)..')',fmt(read(boss,'Health')))
            if applied then self.kills=self.kills+1 end
        elseif hp and hp>0 then
            kill='角色类型未确认，保留原生结果 HP='..fmt(hp)
        end
        self.finished=self.finished+1
        say(string.format('结束（%s）用时=%.1fs；%s；%s',why,now()-run.t0,back,kill))
        self.message='上次处决：'..className(run.executor)..' → '..className(boss)..'（'..why..'）'
    end

    local function watch()
        local run=active
        local t=now()-run.t0
        chain:tick()
        poseProbe:sample('tick')
        if not U.valid(run.executor) then finish('执行方失效');return end
        local hp=U.valid(run.boss) and read(run.boss,'Health') or nil
        local montage=U.valid(run.boss) and montageOf(run.boss) or nil
        if not run.montage and montage and montage~=run.before then run.montage=montage end
        run.samples=run.samples+1
        if run.samples<=3 and run.body then CopyPose.sample(run.body.copyFollowers,run.body.comp,log,name) end
        if run.samples<=3 or run.samples%4==0 then
            local playing=run.body and select(2,call(run.body.comp,'IsPlaying'))
            local d=distance(run.executor,run.boss)
            say(string.format('进行中 %.1fs 目标HP=%s 目标动作=%s 执行方动作=%s 借来的骨架播放中=%s 距离=%s',t,fmt(hp),tostring(montage),
                tostring(montageOf(run.executor)),tostring(playing and U.unwrap(playing)),d and string.format('%.1fm',d/100) or '?'))
        end
        if hp and hp<=0 and not run.fell then run.fell=t;say(string.format('目标在 %.1fs 倒下，执行方的动作继续播完',t)) end
        if run.mash and not run.mash.finale and t>=run.mash.next then press(run,t) end
        if t>=1.5 and not run.montage and not run.fell then finish('目标没有播被处决动作',true);return end
        if not run.dynamic and t>=run.length then finish(run.fell and '播完，目标已倒下' or '播完');return end
    end

    local function adoptNative(event)
        if next(pendingBodies) or not (U.valid(event.executor) and U.valid(event.target)) then return end
        local timing=animationData(short(event.execution))
        if not timing then return end
        local continuing,paused=false,false
        if active then
            if U.key(active.executor)==U.key(event.executor) and U.key(active.boss)==U.key(event.target)
                and U.key(active.info.pair.execution)==U.key(event.execution) then return end
            if U.key(active.executor)~=U.key(event.executor) then
                say('另一对原生处决已开始，当前表现未结束，暂不接管：'..short(event.execution));return
            end
            continuing=true;paused=active.paused
            finish('衔接原生下一段',false,true)
            if next(pendingBodies) then return end
        end
        local info=inspect(event.target)
        info.timing=timing
        info.pair={execution=event.execution,executed=event.executed,start=event.start,source='原生PlayExactExecution读回'}
        start(event.executor,event.target,info,distance(event.executor,event.target),'原生反制/连携',
            {continuing=continuing,paused=paused})
    end
    local opportunities=Opportunities.new({log=log,staticFind=find,loadAsset=load,members=options.members,getPlayer=options.getPlayer,
        registerHook=options.registerHook,unregisterHook=options.unregisterHook,defer=options.defer,cancel=options.cancel,
        fighting=options.fighting or function()return true end,internal=function()return callingNative end,
        available=function(executor)return self.enabled and next(pendingBodies)==nil
            and (not executor or not active or U.key(active.executor)==U.key(executor))end,data=animationData,adopt=adoptNative})

    -- Starts an execution of the target if it can be executed now and someone is there to do it; true once it has.
    local function tryExecute(target,unit,t,team)
        local hp=read(target,'Health')
        if not hp or hp<=0 then return false end
        local locked=onLock(target,unit,hp)
        if locked then unit.since=unit.since or t else unit.since=nil end
        local reason=locked and t-unit.since>=HOLD and '卡在锁血线' or (not unit.lockOnly and executable(target))
        if not reason and not unit.lockOnly then
            for _,tag in ipairs({'CharacterState.CanRiderExecute','CharacterState.Stand.Break','CharacterState.CanWeakExecute'})do
                if tagsMatch(target,{tag},true)then reason=tag;break end
            end
        end
        if not reason then return false end
        local selected=inspect(target,true,locked)
        if selected.state=='story' then
            unit.state='story';unit.storyWhy=selected.storyWhy
            say('处决会改剧情，不用它：'..className(target)..' '..short(selected.pair.execution)..' '..tostring(selected.storyWhy))
            return false
        end
        local executor,d
        if selected.state=='ready' then executor,d=opponent(target,team,locked and LOCK_REACH or selected.pair.reach or REACH,locked,selected.pair.type)end
        if executor then start(executor,target,selected,d,reason);return true end
        if selected.state~='ready' and not unit.conditionWait then unit.conditionWait=true;say('有处决数据，当前原生标签/骑乘条件未满足：'..className(target)) end
        if locked and selected.state=='ready' and not unit.waited then unit.waited=true;say('卡在锁血线，附近 20 米内没有对手，等对手靠近：'..className(target)) end
        return false
    end
    -- What the companions are after, while the switch is on: anything on their hatred lists but the player and the arena's
    -- own units. A unit summoned with no team is summoned to be fought, so it counts.
    local function companionFoes(members)
        if not (options.companions and options.companions()) then return {} end
        local skip,seen,foes={},{},{}
        local playerKey=U.key(options.getPlayer and options.getPlayer())
        if playerKey then skip[playerKey]=true end
        for _,member in ipairs(members)do
            local key=member.team~='neutral' and U.key(member.actor)
            if key then skip[key]=true end
        end
        for _,member in ipairs(members)do
            if member.team=='companion' and not member.reserve then
                local list=U.field(U.field(member.actor,'BP_PBZHatredManagerComponent'),'HatredList')
                for _,enemy in ipairs(U.array(list) or {})do
                    local key=U.key(enemy)
                    if key and not skip[key] and not seen[key] then seen[key]=true;foes[#foes+1]={actor=enemy,key=key} end
                end
            end
        end
        return foes
    end
    -- The player has this one (the game keeps the last executor on the target's component): it stays the player's.
    local function theirExecutorIsPlayer(target)
        local info=U.field(U.field(target,'Execution Component'),'CurrentExecutionInfo')
        local executor=weak(U.struct(info,'Executor'))
        local playerKey=U.key(options.getPlayer and options.getPlayer())
        return playerKey~=nil and U.key(executor)==playerKey
    end
    local function considerFoes(foes,t)
        for _,foe in ipairs(foes)do
            local unit=units[foe.key]
            if not unit then
                unit=inspect(foe.actor);unit.foe=true;units[foe.key]=unit
                if unit.boss and options.isStand and options.isStand(foe.actor) then unit.state='none' end
                if unit.boss and unit.state=='ready' then
                    say(string.format('随从处决登记 %s（%s）：锁血效果=%d 个 技能对=%s / %s（%s）',className(foe.actor),unit.rank,#unit.locks,
                        short(unit.pair.execution),short(unit.pair.executed),unit.pair.source))
                elseif unit.boss then
                    say('随从处决：这个 BOSS 没有能用的处决动作，不处决：'..className(foe.actor)..' 状态='..unit.state)
                end
            end
            if unit.boss and unit.state=='ready' and not (unit.again and t<unit.again) then
                if theirExecutorIsPlayer(foe.actor) then
                    if not unit.playerHeld then unit.playerHeld=true;say('玩家处决过或正在处决，随从不抢：'..className(foe.actor)) end
                elseif tryExecute(foe.actor,unit,t,nil) then return end
            end
        end
    end
    -- 打到死 (a unit's card, unit_rules.lua): a unit on its death lock dies there, without waiting for anyone. Any team: the
    -- same lock stops the player and the companions. The way a level script ends it (SpawnerToDieNS): the lock off, GE_Kill.
    local function endLocks(members)
        if not options.killOnLock then return end
        for _,member in ipairs(members)do
            local target=member.actor
            local key=U.key(target)
            if key and not member.stand and options.killOnLock(target) and not (options.isImmortal and options.isImmortal(member.team)) then
                local unit=units[key]
                if not unit then unit=inspect(target);units[key]=unit end
                local hp=read(target,'Health')
                if unit.state~='done' and hp and hp>0 and onLock(target,unit,hp)
                    and (read(target,'Health_Min') or 0)<=DEATH_LOCK*(read(target,'Health_Max') or 0)+1 then
                    local asc,removed,after=unlock(target,unit)
                    local ge=object(GE_KILL)
                    local applied,err=false,'没有 GE_Kill'
                    if ge then applied,err=call(asc,'BP_ApplyGameplayEffectToSelf',ge,0.0,{}) end
                    if applied then self.kills=self.kills+1 end
                    unit.state='done'
                    say(string.format('到锁血线直接打死（卡面设置）%s：去锁血[%s] 读回底线=%s；GE_Kill=%s%s 读回HP=%s',className(target),table.concat(removed,' '),
                        fmt(after),tostring(applied),applied and '' or '('..tostring(err)..')',fmt(read(target,'Health'))))
                end
            end
        end
    end
    function self:tick()
        local members=options.members() or {}
        local present={}
        for _,member in ipairs(members)do
            local key=U.key(member.actor)
            if key then present[key]=true end
        end
        local foes=companionFoes(members)
        for _,foe in ipairs(foes)do present[foe.key]=true end
        for key,unit in pairs(units)do
            if not present[key] then
                units[key]=nil
                if not unit.foe then say('单位已离场，清除处决判断 读回=不在当前名单') end
            end
        end
        if not self.enabled then return end
        chain:auditExisting()
        opportunities:tick()
        for key,body in pairs(pendingBodies) do if not U.valid(body.comp) then pendingBodies[key]=nil end end
        if next(pendingBodies) then self.message='面部附着恢复待重试，请停止/清场';return end
        if active then watch();return end
        local t=now()
        endLocks(members)
        if options.fighting and not options.fighting() then considerFoes(foes,t);return end
        for _,member in ipairs(members) do
            local target=member.actor
            local key=U.key(target)
            -- A helper the other side's boss brought out is left to that boss's script, not finished here.
            if key and (member.team=='blue' or member.team=='red') and not member.aid then
                local unit=units[key]
                if not unit then
                    unit=inspect(target);units[key]=unit
                    if unit.state=='nopair' and #unit.locks>0 then say('锁血但没有成对的处决动作，不处决：'..className(target)) end
                    if unit.state=='nodata' then say('有处决动作但没有执行方动作数据，不处决：'..className(target)..' '..short(unit.pair.execution)) end
                    if unit.state=='story' then say('处决会改剧情，不用它：'..className(target)..' '..short(unit.pair.execution)..' '..tostring(unit.storyWhy)) end
                    if unit.state=='ready' then say(string.format('登记 %s（%s）：锁血效果=%d 个 技能对=%s / %s（%s）',className(target),unit.rank,#unit.locks,
                        short(unit.pair.execution),short(unit.pair.executed),unit.pair.source)) end
                end
                local immortal=options.isImmortal and options.isImmortal(member.team)
                if unit.state~='ready' and unit.state~='done' and not immortal then
                    local hp=read(target,'Health')
                    if hp and hp>0 and onLock(target,unit,hp) then
                        if not unit.stuck then
                            unit.stuck=t
                            say(string.format('卡在锁血线，但它没有能用的处决动作，不处决（也不按倒下算）：%s HP=%s 底线=%s',className(target),fmt(hp),
                                fmt(read(target,'Health_Min'))))
                        end
                        local floor=read(target,'Health_Min') or 0
                        if unit.boss and not member.untargetable and t-unit.stuck>=STUCK_SECONDS and floor<=DEATH_LOCK*(read(target,'Health_Max') or 0)+1 then
                            local asc,removed,after=unlock(target,unit)
                            local ge=object(GE_KILL)
                            local applied,err=false,'没有 GE_Kill'
                            if ge then applied,err=call(asc,'BP_ApplyGameplayEffectToSelf',ge,0.0,{}) end
                            if applied then self.kills=self.kills+1 end
                            unit.state='done'
                            say(string.format('卡在锁血线 %d 秒，没有处决动作，按倒下收尾（%s）%s：去锁血[%s] 读回底线=%s；GE_Kill=%s%s 读回HP=%s',STUCK_SECONDS,unit.rank,className(target),
                                table.concat(removed,' '),fmt(after),tostring(applied),applied and '' or '('..tostring(err)..')',fmt(read(target,'Health'))))
                        end
                    else
                        unit.stuck=nil
                    end
                end
                if unit.state=='ready' and not (unit.again and t<unit.again) and not immortal and tryExecute(target,unit,t,member.team) then return end
            end
        end
        considerFoes(foes,t)
    end
    -- F4 / stop: give the body back; the boss is left as it is.
    function self:stop(why)
        opportunities:stop(why)
        if active then
            local run=active;active=nil
            if run.playback then run.playback:stop() end
            poseProbe:stop(why)
            endCamera(why)
            chain:closeTasks()
            local released=release(run)
            chain:stop(why)
            say('中止（'..tostring(why)..'）：'..returnBody(run.body)..'；'..resume(run)..released)
        else
            chain:stop(why)
        end
        local retry={};for _,body in pairs(pendingBodies)do retry[#retry+1]=body end
        for _,body in ipairs(retry)do say('重试身体恢复：'..returnBody(body)) end
        units={}
    end
    function self:silence()chain:silence();opportunities:silence();if active and active.playback then active.playback:stop() end end
    function self:executing(actor)
        local key=U.key(actor)
        return key~=nil and active~=nil and U.key(active.executor)==key
    end
    function self:status()
        return {enabled=self.enabled,active=active~=nil,started=self.started,finished=self.finished,failures=self.failures,
            kills=self.kills,message=self.message}
    end
    return self
end
return Exec
