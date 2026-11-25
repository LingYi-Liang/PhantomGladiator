-- Keep each owned MengHua's native stage partner until the verified execution pair has finished.
-- The native actor-by-class lookup is scoped before the helper's BeginPlay, never applied to map actors.
local U=require('ue_observe')
local Retry=require('lookup_retry')
local Phase={}
local MOBS='/PBZCombatAsset/ActorData/Mobs/'
local PARENT=MOBS..'078_MengHua/BP_Monster_MengHua.BP_Monster_MengHua_C'
local CHILD=MOBS..'079_XuKong/BP_Monster_XuKong.BP_Monster_XuKong_C'
local SUMMON=MOBS..'078_MengHua/Ability/Passive/GA_MengHua_SummonPassive.GA_MengHua_SummonPassive_C'
local PASSIVE=MOBS..'078_MengHua/Ability/Passive/GA_MengHua_XuKong_Passive.GA_MengHua_XuKong_Passive_C'
local EX=MOBS..'079_XuKong/Ability/GA_XuKong_GEx_01.GA_XuKong_GEx_01_C'
local ED=MOBS..'079_XuKong/Ability/GA_XuKong_GEd_01.GA_XuKong_GEd_01_C'
local ENTER=MOBS..'079_XuKong/Ability/GA_XuKong_EnterCombat_02.GA_XuKong_EnterCombat_02_C'
local SKILL4=MOBS..'079_XuKong/Ability/GA_XuKong_Skill_04.GA_XuKong_Skill_04_C'
local EFFECTS=MOBS..'078_MengHua/GameplayEffects/'
local LOCK=EFFECTS..'GE_MengHua_XuKong_LockHealth.GE_MengHua_XuKong_LockHealth_C'
local PERMISSION=EFFECTS..'GE_MengHua_XuKong_CA.GE_MengHua_XuKong_CA_C'
local TIMER=EFFECTS..'GE_MengHua_XuKong_Timer.GE_MengHua_XuKong_Timer_C'
local SEQUENCE=EFFECTS..'GE_MengHua_SeqCA.GE_MengHua_SeqCA_C'
local AI='/Script/SGameAI.Default__SGameAIFunctionLibrary'
local UTILS='/Script/SGameUtils.Default__AbilityUtils'
local GAS='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
local ACTIVE='CharacterState.AbilityState.MengHua.XuKong.Active'
local CAN_SUMMON='CharacterState.AbilityState.MengHua.CanSummonXuKong'
local SUMMON_EVENT='GameplayEvent.SelfSummon.MengHua'
local SEQ_CA='CharacterState.AbilityState.MengHua.SeqCA'
local CAN_USE_CA='CharacterState.AbilityState.MengHua.CanUseCA'
local PHASE_SETTLED={'CharacterState.AbilityState.MengHua.CanEnterP2','CharacterState.AbilityState.MengHua.P2'}
local STALL_SECONDS,RETRY_SECONDS=8,12
local ASSIGN='AI.BlackboardKey.Object.AssignActor1'
local SKIP_TAGS={'CharacterState.AbilityState.MengHua.InitCA',CAN_SUMMON,
    'CharacterState.AbilityState.MengHua.CanUseCA',ACTIVE}
local COMBAT_TEAMS={blue=true,red=true,companion=true}
local TEAMS={blue=true,red=true,neutral=true,companion=true}
local WINDOW_SECONDS=5 -- outer-post closes normally; this only retires a missing/aborted outer call
Phase.paths={lookup='/Script/Engine.GameplayStatics:GetActorOfClass',player='/Script/Engine.GameplayStatics:GetPlayerCharacter',
    spawn='/SGameAI/Core/AIScript/GA_SummonPassive.GA_SummonPassive_C:OnSummonSpawnPreFinish',
    exStart=EX..':K2_ActivateAbility',exEnd=EX..':K2_OnEndAbility',edStart=ED..':K2_ActivateAbility',edEnd=ED..':K2_OnEndAbility',
    exInfo='/SGameExecution/GA/GA_ExecutionAbilityBase.GA_ExecutionAbilityBase_C:SetCurrentExecutionInfo',
    edInfo='/SGameExecution/GA/GA_ExecutedAbilityBase.GA_ExecutedAbilityBase_C:SetCurrentExecutionInfo',
    exWindow='/SGameExecution/GA/GA_ExecutionAbilityBase_Grab.GA_ExecutionAbilityBase_Grab_C:K2_ActivateAbility',
    enterWindow='/MagCombatAbilities/Abilities/BP_ActionAbilityBase_Simple.BP_ActionAbilityBase_Simple_C:K2_ActivateAbility',
    enterClose=ENTER..':K2_ActivateAbility',
    warp='/Script/MotionWarping.MotionWarpingComponent:AddOrUpdateWarpTargetFromLocationAndRotation',passive=PASSIVE..':K2_ActivateAbility',
    summonPassive=SUMMON..':K2_ActivateAbility',skill4Close=SKILL4..':K2_ActivateAbility'}
local PACKAGES={spawn='/SGameAI/Core/AIScript/GA_SummonPassive.GA_SummonPassive_C',exStart=EX,exEnd=EX,edStart=ED,edEnd=ED,
    exInfo='/SGameExecution/GA/GA_ExecutionAbilityBase.GA_ExecutionAbilityBase_C',edInfo='/SGameExecution/GA/GA_ExecutedAbilityBase.GA_ExecutedAbilityBase_C',
    exWindow='/SGameExecution/GA/GA_ExecutionAbilityBase_Grab.GA_ExecutionAbilityBase_Grab_C',
    enterWindow='/MagCombatAbilities/Abilities/BP_ActionAbilityBase_Simple.BP_ActionAbilityBase_Simple_C',enterClose=ENTER,passive=PASSIVE,
    summonPassive=SUMMON,skill4Close=SKILL4}
local ORDER={'lookup','player','spawn','exStart','exEnd','edStart','edEnd','exInfo','edInfo','exWindow','enterWindow','enterClose','warp','passive','summonPassive','skill4Close'}
local function call(object,method,...)
    if not U.valid(object) then return nil end
    local args={...};local ok,value=pcall(function()return object[method](object,table.unpack(args))end)
    if ok then return U.unwrap(value) end
end
local function full(object)return call(object,'GetFullName')end
local function classPath(object)
    local name=full(call(object,'GetClass'));return type(name)=='string' and name:match('^%S+ (/.+)$') or nil
end
local function same(a,b)local key=U.key(a);local name=full(a);return key~=nil and key==U.key(b) and type(name)=='string' and name==full(b)end
local function actorRef(value)
    value=U.unwrap(value);local kind=U.kind(value)
    if kind=='WeakObjectPtr' or kind=='FWeakObjectPtr' or kind=='TWeakObjectPtr' then
        local ok,actor=pcall(function()return value:Get()end);return ok and U.valid(actor) and actor or nil
    end
    return U.valid(value) and value or nil
end
function Phase.new(options)
    local self={failures=0,kept=0,completed=0,anchors=0,state='idle'}
    local find,load=options.find or StaticFindObject,options.load or LoadAsset
    local register,unregister=options.register or RegisterHook,options.unregister or UnregisterHook
    local createInvalid=options.createInvalid or CreateInvalidObject
    local findAll=options.findAll or FindAllOf
    local clock,fname=options.clock or os.clock,options.fname or FName
    local inGameThread=options.inGameThread or IsInGameThread
    local stats=options.attributes
    local parents,children,pairRecords,hooks,loads={},{},{},{},{}
    local storyLinks={} -- source-only bindings; never adopted, paused, cleaned up or given local anchors
    local warpWindows={}
    local internalWarp=false
    local dispatch
    local seedAnchor
    local alive,nullActor=true,nil
    local installAt,unhookAt,nextTick=0,0,0
    local lines={}
    local function say(kind,text)
        lines[kind]=(lines[kind] or 0)+1
        if lines[kind]<=16 then (options.log or function()end)('[MengHuaPhase] '..text) end
    end
    local retry=Retry.new({clock=clock,log=function(text)say('lookup',text)end})
    local function lookup(path)return retry:find(path,find)end
    local function thread()
        if type(inGameThread)~='function' then return true end
        local ok,result=pcall(inGameThread);return ok and result==true
    end
    local function ready()return not options.ready or options.ready()==true end
    local function supported()return type(find)=='function' and type(register)=='function' and type(unregister)=='function' and type(createInvalid)=='function' and fname~=nil end
    local function parentOf(actor)
        local row=parents[U.key(actor) or '']
        return row and row.name==full(actor) and same(row.actor,actor) and row or nil
    end
    local function childOf(actor)
        local row=children[U.key(actor) or '']
        return row and row.name==full(actor) and same(row.actor,actor) and row or nil
    end
    local function storyOf(actor)
        local row=storyLinks[U.key(actor) or '']
        return row and row.name==full(actor) and same(row.actor,actor) and row or nil
    end
    local function scope(context,includeStory)
        if not next(children) and (not includeStory or not next(storyLinks)) then return nil end
        local object=U.unwrap(context);local visited={}
        for _=1,5 do
            local key=U.key(object);if not key or visited[key] then return nil end;visited[key]=true
            local row=childOf(object) or (includeStory and storyOf(object));if row then return row end
            local path=classPath(object) or '';local name=path:match('%.([^%.]+)$') or ''
            local avatar
            if name:match('^GA_') then avatar=call(object,'GetAvatarActorFromActorInfo')
            elseif name:match('^GAA?_') or name:match('^LGAAction') then avatar=call(object,'GetAvatarActor') end
            if U.valid(avatar) then return childOf(avatar) or (includeStory and storyOf(avatar)) end
            if name:match('^GA_') or name:match('^GAA?_') or name:match('^LGAAction') then return nil end
            -- Non-ability children may be outered to their ability or helper. World/level contexts cannot be one.
            if not path:find('/PBZCombatAsset/ActorData/Mobs/079_XuKong/',1,true) then return nil end
            object=call(object,'GetOuter')
        end
    end
    local function effect(asc,path)
        local cls=lookup(path)
        local name=full(cls)
        if not U.valid(asc) or not U.valid(cls) or type(name)~='string' or name:match('^%S+ (/.+)$')~=path
            or call(cls,'IsAnyClass')~=true then return end
        local count=call(asc,'GetGameplayEffectCount',cls,nil,false)
        if type(count)=='number' and count>=0 then return count,cls end
    end
    local function lockCount(parent)
        local count=effect(U.field(parent,'AbilitySystemComponent'),LOCK)
        return count
    end
    local function going(actor)
        if not U.valid(actor) then return true end
        if type(options.isDestroying)=='function' then local ok,value=pcall(options.isDestroying,actor);return ok and value==true end
        return call(actor,'IsActorBeingDestroyed')==true
    end
    local function parentDead(row)
        if not U.valid(row.actor) or row.name~=full(row.actor) or going(row.actor) then return true end
        if type(options.hp)=='function' then
            local ok,value=pcall(options.hp,row.actor)
            return ok and type(value)=='number' and value<=0
        end
        return false
    end
    local function otherLive(row)
        for _,other in pairs(children)do if other~=row and other.parent==row.parent and not other.retired and not going(other.actor) then return true end end
        return false
    end
    local function clearBinding(row)
        local parent=row.parent.actor
        if not parentOf(parent) or parentDead(row.parent) then return true end
        if type(options.boardOf)~='function' then return false end
        local board=options.boardOf(parent);local lib=lookup(AI)
        if not U.valid(board) or not U.valid(lib) then return false end
        local ok,tagName=pcall(fname,ASSIGN);if not ok then return false end
        local tag={TagName=tagName}
        local read,current=pcall(function()return U.unwrap(lib:GetValueAsObjectByTag(board,tag))end)
        if not read then return false end
        if same(current,row.actor) or row.parent.skip and not U.valid(current) then
            row.bindingConfirmed=true
            call(lib,'SetValueAsObjectByTag',board,tag,nullActor)
            if not U.valid(board) or not U.valid(lib) then return false end
            local readAfter,after=pcall(function()return U.unwrap(lib:GetValueAsObjectByTag(board,tag))end)
            if not readAfter or U.valid(after) then return false end
            say('binding','清理本次配对AssignActor1；读回为空=true')
        end
        if not otherLive(row) then
            local asc=U.field(parent,'AbilitySystemComponent');local utils=lookup(UTILS)
            local made,name=pcall(fname,ACTIVE);if not made or not U.valid(asc) or not U.valid(utils) then return false end
            local activeTag={TagName=name};local before=call(asc,'GetGameplayTagCount',activeTag)
            if type(before)~='number' then return false end
            if before>0 then
                if not row.pairEnded and not row.bindingConfirmed and not row.parent.nativeStageEnded then return false end
                call(utils,'SetLooseGameplayTagCount',parent,activeTag,0)
                local after=call(asc,'GetGameplayTagCount',activeTag)
                say('active','清理本次剧情虚空Active；读回='..tostring(before)..'→'..tostring(after))
                if after~=0 then return false end
            end
        end
        return true
    end
    local function pairAlive(row)
        for _,entry in pairs(pairRecords)do
            if entry.child==row and not entry.ended and U.valid(entry.ability) then
                local active=U.field(entry.ability,'bIsActive')
                if active~=false then return true end
            end
        end
        return false
    end
    local function cleanup(row,force)
        if row.retired then return true end
        if pairAlive(row) then
            if not force then return false end
            for _,entry in pairs(pairRecords)do if entry.child==row and not entry.ended then call(entry.ability,'K2_CancelAbility') end end
            if pairAlive(row) then return false end
        end
        if not clearBinding(row) then return false end
        if U.valid(row.actor) and U.valid(row.ability) and same(call(row.ability,'GetAvatarActorFromActorInfo'),row.parent.actor) then call(row.ability,'DestroySummons',row.actor) end
        if force and not going(row.actor) then call(row.actor,'K2_DestroyActor') end
        local gone=going(row.actor)
        say('cleanup','回收本组阶段虚空；配对完成='..tostring(row.pairEnded==true)..' 停止='..tostring(force)..' 销毁读回='..tostring(gone))
        if gone then row.retired=true;row.parent.busy=false;return true end
        return false
    end
    local function scopedPassive(parent,path,field)
        local cached=parent[field]
        if cached and cached.name==full(cached.ability) and classPath(cached.ability)==path and same(call(cached.ability,'GetAvatarActorFromActorInfo'),parent.actor) then return cached.ability end
        if type(findAll)~='function' then return nil end
        local class=path:match('%.([^%.]+)$')
        local ok,objects=pcall(findAll,class)
        for _,ability in ipairs(ok and U.array(objects) or {})do
            if classPath(ability)==path and same(call(ability,'GetAvatarActorFromActorInfo'),parent.actor) then
                parent[field]={ability=ability,name=full(ability)};return ability
            end
        end
    end
    local function tagCount(asc,tag)
        local ok,id=pcall(fname,tag)
        if ok then return call(asc,'GetGameplayTagCount',{TagName=id}) end
    end
    local function stageWait(parent,reason)
        if reason~=parent.stageReason then
            parent.stageReason=reason
            say('stage-wait','41%阶段待转 '..parent.name..'；'..reason)
        end
    end
    local function nativeSlotAvailable(ability)
        local rows=U.array(U.field(ability,'SpawnedSummonInstances'))
        local pending=call(lookup(AI),'GetPendingSummonCount',ability)
        if not rows or pending~=0 then return false end
        for _,row in ipairs(rows)do
            local value,known=U.struct(row,'Pawn')
            if not known or U.struct(row,'bPawnPending')~=false then return false end
            local pawn=actorRef(value)
            if pawn and not going(pawn) then
                local hp=options.hp(pawn)
                if type(hp)~='number' or not (hp<=0) then return false end
            end
        end
        return true
    end
    local function recoverPermission(parent,asc,lock)
        if parent.permissionTried then return end
        local permission,cls=effect(asc,PERMISSION)
        local timer=effect(asc,TIMER)
        if lock~=1 or permission~=0 or (timer~=0 and timer~=1) then return end
        local passive=scopedPassive(parent,PASSIVE,'phasePassive')
        if U.field(passive,'bIsActive')~=true then return end
        parent.permissionTried=true
        local actor=parent.actor
        call(passive,'TryTriggerXuKongByHealth')
        local allowed=tagCount(asc,CAN_SUMMON)
        if allowed==0 and effect(asc,TIMER)==0 and effect(asc,PERMISSION)==0
            and parentOf(actor)==parent and not parentDead(parent) and same(call(asc,'GetOwner'),actor)
            and lockCount(actor)==1 and (tagCount(asc,'AI.State.Combat') or 0)>0
            and tagCount(asc,SEQ_CA)==0 and tagCount(asc,ACTIVE)==0 then
            for _,tag in ipairs(PHASE_SETTLED)do if tagCount(asc,tag)~=0 then return end end
            -- The same effect is applied by the native timer and the native health callback.
            call(asc,'BP_ApplyGameplayEffectToSelf',cls,0,{})
            allowed=tagCount(asc,CAN_SUMMON)
        end
        say('stage-permission','41%原生召唤许可复核 '..parent.name..'；计时效果='..timer..' 许可读回='..tostring(allowed))
    end
    local function resetRecoveryAfterOffCombat(parent)
        if parent.skip or parent.stopping or parent.departed
            or not (parent.observedSummon or parent.stageAttempts or parent.permissionTried) then return end
        local actor=parent.actor
        if parentDead(parent) or not same(parent.world,options.world()) or not U.inWorld(actor,parent.world) then return end
        local asc=U.field(actor,'AbilitySystemComponent')
        if not same(call(asc,'GetOwner'),actor) then return end
        local offCombat=tagCount(asc,'CharacterState.OffCombat')
        if type(offCombat)~='number' or offCombat<1 or tagCount(asc,'AI.State.Combat')~=0 then return end
        -- The original passive clears the linked effects and tags on OffCombat and can stage a new encounter.
        if lockCount(actor)~=0 or tagCount(asc,ACTIVE)~=0 or tagCount(asc,CAN_SUMMON)~=0
            or tagCount(asc,SEQ_CA)~=0 or tagCount(asc,CAN_USE_CA)~=0 then return end
        for _,tag in ipairs(PHASE_SETTLED)do if tagCount(asc,tag)~=0 then return end end
        for _,child in pairs(children)do if child.parent==parent and not child.retired then return end end
        for _,entry in pairs(pairRecords)do
            if entry.child.parent==parent and not entry.ended and U.valid(entry.ability)
                and U.field(entry.ability,'bIsActive')~=false then return end
        end
        local ability=scopedPassive(parent,SUMMON,'summonPassive')
        if not U.valid(ability) or not nativeSlotAvailable(ability) then return end
        parent.observedSummon=nil;parent.lostBeforePair=nil;parent.permissionTried=nil
        parent.stageAttempts=nil;parent.stageRequestAt=nil;parent.floorSince=nil
        parent.stageSample=nil;parent.stageReason=nil;parent.summonProbe=nil
        say('stage-reset','原生脱战后的专属锁与本组召唤槽已清；更新下一次联动重试额度 '..parent.name)
    end
    local function requestStageSummon(parent,now)
        if not options.opponent or not options.canRequest
            or parent.skip or parent.stopping or parent.departed or parent.observedSummon and not parent.lostBeforePair
            or (parent.stageAttempts or 0)>=2 then return end
        if type(now)~='number' or now~=now then return end
        local awaitingAction=parent.floorSince and now-parent.floorSince>=STALL_SECONDS
        if not awaitingAction and parent.stageSample and now>=parent.stageSample and now-parent.stageSample<1 then return end
        parent.stageSample=now
        local actor=parent.actor
        if parentDead(parent) or not same(parent.world,options.world()) or not U.inWorld(actor,parent.world) then return end
        local hp=options.hp(actor)
        if type(hp)~='number' or hp<=0 then parent.floorSince=nil;return end
        stats=stats or require('character_stats').new()
        local max=stats:read(actor,'Health_Max')
        if not max or max.current<=0 then parent.floorSince=nil;return end
        local limit,tolerance=max.current*.41,math.max(.1,max.current*.000001)
        if math.abs(hp-limit)>tolerance then parent.floorSince=nil;return end
        local min=stats:read(actor,'Health_Min')
        local count=lockCount(actor)
        if not min or math.abs(min.current-limit)>tolerance or type(count)~='number' or count<1 then
            parent.floorSince=nil;stageWait(parent,'专属41%锁或实际下限不可确认');return
        end
        local asc=U.field(actor,'AbilitySystemComponent')
        if not same(call(asc,'GetOwner'),actor) then parent.floorSince=nil;stageWait(parent,'能力组件归属未确认');return end
        local combat=tagCount(asc,'AI.State.Combat')
        if type(combat)~='number' or combat<1 then parent.floorSince=nil;stageWait(parent,'原生战斗状态未确认');return end
        local foe=options.opponent(actor,parent.team)
        if not U.inWorld(foe,parent.world) or going(foe) or (options.hp(foe) or 0)<=0 then
            parent.floorSince=nil;stageWait(parent,'本场没有读回存活对手');return
        end
        if not parent.floorSince or now<parent.floorSince then parent.floorSince=now end
        if now-parent.floorSince<STALL_SECONDS then return end
        if parent.stageRequestAt and now>=parent.stageRequestAt and now-parent.stageRequestAt<RETRY_SECONDS then return end
        if tagCount(asc,ACTIVE)~=0 then stageWait(parent,'虚空已激活或状态不可读');return end
        for _,tag in ipairs(PHASE_SETTLED)do
            if tagCount(asc,tag)~=0 then stageWait(parent,'正转阶段或阶段标记不可读');return end
        end
        if tagCount(asc,'Ability.Action')~=0 or not options.canRequest(actor) then
            stageWait(parent,'等待当前动作结束');return
        end
        if parent.summonProbe and now>=parent.summonProbe and now-parent.summonProbe<3 then return end
        local ability=scopedPassive(parent,SUMMON,'summonPassive')
        local eventName=U.struct(U.field(ability,'SummonEventTag'),'TagName')
        local event=eventName
        if type(event)~='string' then
            local ok,text=pcall(function()return event:ToString()end)
            event=ok and text or nil
        end
        if U.field(ability,'bIsActive')~=true or U.field(ability,'MaxSummonCount')~=1 or event~=SUMMON_EVENT then
            parent.summonProbe=now
            stageWait(parent,'原生召唤被动未确认');return
        end
        if not nativeSlotAvailable(ability) then stageWait(parent,'原生召唤仍有活体或在途槽');return end
        if parent.lostBeforePair then
            if not same(parent.lostBeforePair,ability) then stageWait(parent,'失败的出生与当前被动归属不一致');return end
            for _,child in pairs(children)do
                if child.parent==parent and not child.retired then return end
            end
        end
        local canSummon,seq=tagCount(asc,CAN_SUMMON),tagCount(asc,SEQ_CA)
        if type(canSummon)~='number' or type(seq)~='number' then stageWait(parent,'原生召唤或转场标签不可读');return end
        local route
        if seq>0 then
            local canUse,sequenceEffect=tagCount(asc,CAN_USE_CA),effect(asc,SEQUENCE)
            if canSummon~=0 or canUse~=1 or not sequenceEffect or sequenceEffect<1 then
                stageWait(parent,'未确认原生起手结束并消费召唤许可');return
            end
            -- ForSeq's original End grants SeqCA and CanUseCA even on cancellation before the event.
            route='原生起手已结束，补发漏掉的事件'
        elseif canSummon==0 then
            recoverPermission(parent,asc,count)
            stageWait(parent,'等待原生召唤许可读回');return
        else
            route='原生召唤许可仍在'
        end
        local lib=lookup(GAS)
        if not U.valid(lib) then stageWait(parent,'原生事件接口未就绪');return end
        if parent.lostBeforePair then
            parent.lostBeforePair=nil;parent.observedSummon=false
            say('stage-early-loss','上次虚空在配对前失效；原生空槽与本组归属读回，允许补召')
        end
        parent.stageAttempts=(parent.stageAttempts or 0)+1;parent.stageRequestAt=now
        local tag={TagName=eventName}
        local previous=dispatch
        if U.valid(U.field(foe,'Mesh')) then dispatch={ability=ability,parent=parent,target=foe} end
        local called=pcall(function()lib:SendGameplayEventToActor(actor,tag,{EventTag=tag,EventMagnitude=1})end)
        dispatch=previous
        say('stage-retry','41%阶段重新请求同一虚空 '..parent.name..'；尝试='..parent.stageAttempts..' '..route
            ..' 调用='..tostring(called)..' 原生出生回调='..tostring(parent.observedSummon==true))
    end
    local function inactiveSpec(parent,path)
        local asc=U.field(parent.actor,'AbilitySystemComponent')
        if not same(call(asc,'GetOwner'),parent.actor) or not hooks.passive or not hooks.summonPassive then return false end
        local specs=U.array(U.struct(U.field(asc,'ActivatableAbilities'),'Items'))
        if not specs or #specs==0 then return false end
        local matched=false
        for _,spec in ipairs(specs)do
            local cls=classPath(U.struct(spec,'Ability'))
            if not cls then return false end
            if cls==path then
                if U.struct(spec,'ActiveCount')~=0 then return false end
                matched=true
            end
        end
        -- A known inactive spec, or one confirmed End plus an initialized list without the other passive.
        return matched or (parent.phasePassive and parent.phasePassive.ended==true) or (parent.summonPassive and parent.summonPassive.ended==true)
    end
    local function endPassive(parent,path,field,requireReceipt)
        -- Confirmed End is tied to this parent's exact instance, even after GAS drops its avatar.
        local record=parent[field]
        if record and record.ended then
            local previous=record.ability
            if not U.valid(previous) or (record.name==full(previous) and classPath(previous)==path and U.field(previous,'bIsActive')==false) then return true end
        end
        local ability=scopedPassive(parent,path,field)
        if not U.valid(ability) then return not requireReceipt or inactiveSpec(parent,path) end
        record=parent[field]
        if U.field(ability,'bIsActive')~=false then call(ability,'K2_CancelAbility') end
        if parent[field]~=record or U.field(ability,'bIsActive')~=false then return false end
        record.ended=true
        return true
    end
    local function endParentStage(parent,requireReceipt)
        local phase=endPassive(parent,PASSIVE,'phasePassive',requireReceipt)
        local summon=endPassive(parent,SUMMON,'summonPassive',requireReceipt)
        local count=lockCount(parent.actor)
        local confirmed=count==0 and phase and summon
        say('restore','清理时结束本父原生阶段被动；专属锁数量读回='..tostring(count)..' 被动结束确认='..tostring(confirmed)
            ..' 联动='..tostring(phase)..' 召唤='..tostring(summon))
        if confirmed and parent.phasePassive and parent.phasePassive.ended then parent.nativeStageEnded=true end
        return confirmed
    end
    local function prepareCleanup(parent,requireReceipt)
        -- Pair actors must finish/cancel before the summon's passive is allowed to destroy the helper.
        for _,entry in pairs(pairRecords)do
            if entry.child.parent==parent and not entry.ended and U.valid(entry.ability) then call(entry.ability,'K2_CancelAbility') end
        end
        for _,entry in pairs(pairRecords)do
            if entry.child.parent==parent and not entry.ended and U.valid(entry.ability) and U.field(entry.ability,'bIsActive')~=false then return false end
        end
        return parentDead(parent) or endParentStage(parent,requireReceipt)
    end
    local callbacks={}
    local function stageActivated(ability,parent,record)
        if parent.skip then
            parent.skipReady=false;parent.busy=true;parent.nativeStageEnded=false
            call(ability,'K2_CancelAbility')
            record.ended=U.field(ability,'bIsActive')==false
            say('skip-activate','跳过本次直召剧情被动；原生结束读回='..tostring(U.field(ability,'bIsActive')==false))
        elseif parent.stopping then call(ability,'K2_CancelAbility') end
    end
    callbacks.passive=function(context)
        local ability=U.unwrap(context);if classPath(ability)~=PASSIVE then return end
        local parent=parentOf(call(ability,'GetAvatarActorFromActorInfo'));if not parent then return end
        parent.phasePassive={ability=ability,name=full(ability)}
        stageActivated(ability,parent,parent.phasePassive)
    end
    callbacks.summonPassive=function(context)
        local ability=U.unwrap(context);if classPath(ability)~=SUMMON then return end
        local parent=parentOf(call(ability,'GetAvatarActorFromActorInfo'));if not parent then return end
        parent.summonPassive={ability=ability,name=full(ability)}
        stageActivated(ability,parent,parent.summonPassive)
    end
    local function pendingSkip(parent,reason)
        if parent.skipReason~=reason then parent.skipReason=reason;say('skip-wait','跳过联动等待 '..parent.name..' '..reason)end
        return false
    end
    local function skipStage(parent)
        -- Empty/failed discovery is not proof that the actor's native stage has been disabled.
        if not prepareCleanup(parent,true) then return pendingSkip(parent,'被动结束、配对或专属血线未确认') end
        local complete=true
        for _,row in pairs(children)do
            if row.parent==parent and not row.retired and not cleanup(row,true) then complete=false end
        end
        if not complete then return pendingSkip(parent,'本组帮手尚未回收')end
        local asc=U.field(parent.actor,'AbilitySystemComponent');local utils=lookup(UTILS)
        if not U.valid(asc) or not U.valid(utils) then return pendingSkip(parent,'能力组件或标签接口未就绪') end
        for _,tag in ipairs(SKIP_TAGS)do
            local made,name=pcall(fname,tag);if not made then return pendingSkip(parent,tag) end
            local value={TagName=name};local before=call(asc,'GetGameplayTagCount',value)
            if type(before)~='number' then return pendingSkip(parent,'无法读取 '..tag) end
            if before>0 then
                call(utils,'SetLooseGameplayTagCount',parent.actor,value,0)
                local after=call(asc,'GetGameplayTagCount',value)
                if tag==CAN_SUMMON and type(after)=='number' and after>0 and same(call(asc,'GetOwner'),parent.actor) then
                    -- The passive's End removes the timer and the loose tag, not the separate permission effect.
                    local count,class=effect(asc,PERMISSION)
                    if count and count>0 then
                        call(asc,'RemoveActiveGameplayEffectBySourceEffect',class,nil,-1)
                        local remaining=effect(asc,PERMISSION)
                        say('skip-permission','清理已结束联动的原生召唤许可效果；数量读回='..count..'→'..tostring(remaining))
                        if remaining~=0 then return pendingSkip(parent,'原生召唤许可效果仍未清理') end
                        after=call(asc,'GetGameplayTagCount',value)
                    end
                end
                say('skip-tags','清理本次跳过联动标记 '..tag..'；数量读回='..tostring(before)..'→'..tostring(after))
                if after~=0 then return pendingSkip(parent,'仍有联动标签 '..tag) end
            end
        end
        parent.skipReason=nil
        say('skip-ready','本次梦华跳过联动；原生被动结束、专属锁0、帮手和联动标记清理读回=true')
        return true
    end
    local function finite(v)return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
    local function fields(value,names)
        local result={}
        for _,name in ipairs(names)do local number=U.struct(value,name);if not finite(number) then return nil end;result[name]=number end
        return result
    end
    local function equalFields(value,wanted,names)
        local actual=fields(U.unwrap(value),names);if not actual then return false end
        for _,name in ipairs(names)do if math.abs(actual[name]-wanted[name])>0.001 then return false end end
        return true
    end
    local XYZ,ROT={'X','Y','Z'},{'Pitch','Yaw','Roll'}
    local function anchorPose(actor)
        local root=U.field(actor,'RootComponent');local capsule=U.field(actor,'CapsuleComponent')
        if not U.valid(root) or not same(call(root,'GetOwner'),actor) or not U.valid(capsule) or not same(call(capsule,'GetOwner'),actor) then return end
        local position,rotation=call(actor,'K2_GetActorLocation'),call(actor,'K2_GetActorRotation')
        local pos,rot=fields(position,XYZ),fields(rotation,ROT)
        local half=call(capsule,'GetUnscaledCapsuleHalfHeight');local scale=U.struct(call(capsule,'K2_GetComponentScale'),'Z')
        if not pos or not rot or not finite(half) or half<=0 or not finite(scale) or scale<=0 then return end
        pos.Z=pos.Z-half*scale-2;rot.Pitch,rot.Roll=0,0
        if not finite(pos.Z) then return end
        local ok=pcall(function()position.Z=pos.Z;rotation.Pitch=0;rotation.Roll=0 end)
        if ok then return position,rotation,pos,rot,half,scale end
    end
    seedAnchor=function(child,where)
        if child.retired or child.quarantine or child.parent.skip or child.parent.stopping or child.parent.departed then return false end
        local cls=lookup('/Script/MotionWarping.MotionWarpingComponent')
        local className=full(cls)
        if not U.valid(cls) or type(className)~='string' or className:match('^%S+ (/.+)$')~='/Script/MotionWarping.MotionWarpingComponent' or call(cls,'IsAnyClass')~=true then return false end
        local component=call(child.actor,'GetComponentByClass',cls)
        if not same(call(component,'GetOwner'),child.actor) then return false end
        local position,rotation,pos,rot=anchorPose(child.actor)
        if not position then return false end
        local made,name=pcall(fname,'SnapPoint');if not made then return false end
        local previousInternal=internalWarp;internalWarp=component
        local wrote=pcall(function()component:AddOrUpdateWarpTargetFromLocationAndRotation(name,position,rotation)end)
        internalWarp=previousInternal
        local confirmed=false
        local targets=U.array(U.field(component,'WarpTargets'))
        for _,target in ipairs(targets or {})do
            local tag=U.struct(target,'Name');local text=type(tag)=='string' and tag or nil
            if not text then local ok,value=pcall(function()return tag:ToString()end);text=ok and value or nil end
            if text=='SnapPoint' then confirmed=wrote and equalFields(U.struct(target,'Location'),pos,XYZ) and equalFields(U.struct(target,'Rotation'),rot,ROT);break end
        end
        child.seeded=confirmed
        say('seed','预置本组局部锚点 '..where..'；组件目标六分量读回='..tostring(confirmed))
        return confirmed
    end
    local function setStruct(parameter,value,wanted,names)
        local ok=pcall(function()parameter:set(value)end)
        if ok and equalFields(parameter,wanted,names) then return true end
        -- Both paths retain the reflected struct type; a Lua table is never assigned to a struct parameter.
        local raw=U.unwrap(parameter)
        if U.kind(raw)~='UScriptStruct' then return false end
        pcall(function()for _,name in ipairs(names)do raw[name]=wanted[name] end end)
        return equalFields(parameter,wanted,names)
    end
    local function warpWindow(context,path,blocked)
        if not next(children) then return end
        local ability=U.unwrap(context)
        if classPath(ability)~=path then return end
        local child=childOf(call(ability,'GetAvatarActorFromActorInfo'))
        if not child or child.retired or child.quarantine or child.parent.departed or child.parent.stopping then return end
        if child.parent.skip then call(ability,'K2_CancelAbility');return end
        local key=U.key(child.actor)
        local stack=warpWindows[key] or {};warpWindows[key]=stack
        if #stack>=8 then self.failures=self.failures+1;call(ability,'K2_CancelAbility');return end
        stack[#stack+1]={ability=ability,name=full(ability),child=child,at=clock(),blocked=blocked==true}
        if not blocked and not seedAnchor(child,'原生父调用返回') then
            child.anchorFailed=true;self.failures=self.failures+1;say('seed-pending','能力窗口局部锚点尚未确认；后续仅按本组参数写入读回处理')
        end
    end
    local function closeWindow(context)
        local ability=U.unwrap(context)
        for key,stack in pairs(warpWindows)do
            for i=#stack,1,-1 do if same(stack[i].ability,ability) then table.remove(stack,i);break end end
            if #stack==0 then warpWindows[key]=nil end
        end
    end
    local function finishWarpWindow(context)
        closeWindow(context)
        local ability=U.unwrap(context)
        if classPath(ability)~=EX and classPath(ability)~=ENTER then return end
        local child=childOf(call(ability,'GetAvatarActorFromActorInfo'))
        if child then seedAnchor(child,'原生外层返回收敛') end
    end
    callbacks.exWindow=function(context)warpWindow(context,EX)end
    callbacks.enterWindow=function(context)
        if not next(children) then return end
        local ability=U.unwrap(context)
        if classPath(ability)==ENTER then warpWindow(context,ENTER);return end
        -- Skill_04 owns its own landing target. Its nested frame suspends, then restores, an outer stage frame.
        if classPath(ability)==SKILL4 then warpWindow(context,SKILL4,true) end
    end
    callbacks.enterClose=finishWarpWindow
    callbacks.skill4Close=closeWindow
    callbacks.warp=function(context,name,location,rotation)
        if not next(warpWindows) then return end
        local component=U.unwrap(context);local actor=call(component,'GetOwner')
        if internalWarp and same(component,internalWarp) then return end
        local key=U.key(actor);local stack=key and warpWindows[key];local window=stack and stack[#stack]
        if not window or window.child~=childOf(actor) then return end
        if window.blocked or window.consumed then return end
        local text=U.unwrap(name)
        if type(text)~='string' then local ok,value=pcall(function()return text:ToString()end);text=ok and value or nil end
        if text~='SnapPoint' then return end
        window.consumed=true -- a frame owns exactly one update, even when it cannot be confirmed
        local child=window.child
        local active=U.field(window.ability,'bIsActive')
        if window.name~=full(window.ability) or active==false or child.retired then return end
        local usable=active==true and clock()>=window.at and clock()-window.at<=WINDOW_SECONDS and not child.quarantine and not child.parent.stopping
        local originalLocation,originalRotation=fields(U.unwrap(location),XYZ),fields(U.unwrap(rotation),ROT)
        local localPosition,localRotation,pos,rot,half,scale=anchorPose(actor)
        local valid=usable and originalLocation and originalRotation and pos and rot
        if valid then
            valid=setStruct(location,localPosition,pos,XYZ) and setStruct(rotation,localRotation,rot,ROT)
                and equalFields(location,pos,XYZ) and equalFields(rotation,rot,ROT)
        end
        if valid then
            self.anchors=self.anchors+1;child.anchorFailed=false
            say('anchor','本组私有SnapPoint；地面Z='..tostring(pos.Z)..' 胶囊半高='..tostring(half)..' 世界Z缩放='..tostring(scale)..'；六分量参数读回=true')
            return
        end
        -- Retire this verified group's native action on an unconfirmed write. Its own End handles restoration.
        -- Restore the input snapshot first, using the existing typed values, so no half-written transform remains.
        local restored=false
        if originalLocation and originalRotation and U.kind(localPosition)=='UScriptStruct' and U.kind(localRotation)=='UScriptStruct' then
            local ok=pcall(function()
                for _,n in ipairs(XYZ)do localPosition[n]=originalLocation[n] end
                for _,n in ipairs(ROT)do localRotation[n]=originalRotation[n] end
            end)
            restored=ok and setStruct(location,localPosition,originalLocation,XYZ) and setStruct(rotation,localRotation,originalRotation,ROT)
        end
        child.anchorFailed=true;self.failures=self.failures+1
        call(window.ability,'K2_CancelAbility')
        for _,entry in pairs(pairRecords)do if entry.child==child and not entry.ended then call(entry.ability,'K2_CancelAbility') end end
        say('anchor-failed','本组锚点未确认；输入恢复='..tostring(restored)..' 当前动作取消读回='..tostring(U.field(window.ability,'bIsActive')==false))
    end
    callbacks.lookup=function(_,context,cls)
        if not alive or not thread() then return end
        local row=scope(context,true);if not row then return end
        local name=full(U.unwrap(cls));local path=type(name)=='string' and name:match('^%S+ (/.+)$')
        if path~=PARENT then return end
        local parent=row.parent
        if row.story then
            local valid=not row.conflict and parent.name==full(parent.actor) and classPath(parent.actor)==PARENT
                and U.valid(row.world) and U.inWorld(row.actor,row.world) and U.inWorld(parent.actor,row.world)
            say('story-lookup','剧情原生来源搭档查询隔离；源父对象读回='..tostring(not not valid))
            return valid and parent.actor or nullActor
        end
        if not row.seeded and not parent.skip then seedAnchor(row,'原生BeginPlay搭档绑定前') end
        local valid=not parent.skip and not row.retired and not row.quarantine and not parent.stopping and not parent.departed and parentOf(parent.actor) and not parentDead(parent)
        say('actor-lookup','阶段搭档查找实例隔离；父对象有效读回='..tostring(not not valid))
        return valid and parent.actor or nullActor
    end
    callbacks.player=function(_,context,playerIndex)
        if not alive or not thread() then return end
        -- The original summon event synchronously computes its position and yaw from GetPlayerCharacter(self,0).
        if dispatch and U.unwrap(playerIndex)==0 and same(U.unwrap(context),dispatch.ability)
            and parentOf(dispatch.parent.actor)==dispatch.parent and not parentDead(dispatch.parent)
            and same(dispatch.parent.world,options.world()) and U.inWorld(dispatch.target,dispatch.parent.world)
            and not going(dispatch.target) and U.valid(U.field(dispatch.target,'Mesh')) then
            say('stage-position','原生补召定位使用本场对手 '..tostring(full(dispatch.target)))
            return dispatch.target
        end
        local row=scope(context);if not row then return end
        local parent=row.parent
        return not parent.skip and not row.retired and not row.quarantine and not parent.stopping and not parent.departed and parentOf(parent.actor) and not parentDead(parent) and parent.actor or nullActor
    end
    callbacks.spawn=function(context,pawn)
        if not alive or not thread() then return end
        local ability,actor=U.unwrap(context),U.unwrap(pawn)
        if classPath(ability)~=SUMMON or classPath(actor)~=CHILD then return end
        local sourceParent=call(ability,'GetAvatarActorFromActorInfo')
        local parent=parentOf(sourceParent)
        if not parent then
            -- An owned actor may precede a streamed-in story boss in the world's actor list.
            -- Preserve the story helper's real native source rather than letting a first-of-class query choose ours.
            if classPath(sourceParent)~=PARENT or childOf(actor) then return end
            local world=options.world and options.world()
            local key,name=U.key(actor),full(actor);local parentName=full(sourceParent)
            if not key or type(name)~='string' or type(parentName)~='string' or not U.valid(world)
                or not U.inWorld(actor,world) or not U.inWorld(sourceParent,world) then return end
            local prior=storyLinks[key]
            if prior and prior.name==name and prior.conflict then return end
            if prior and prior.name==name and not same(prior.parent.actor,sourceParent) then
                prior.conflict=true;self.failures=self.failures+1;say('story-conflict','剧情来源父对象冲突，未选择任一组');return
            end
            storyLinks[key]={story=true,actor=actor,name=name,parent={actor=sourceParent,name=parentName},world=world}
            say('story-source','只读登记剧情原生召唤来源；辅助='..name..' 源父='..parentName..'；未接管或修改阶段')
            return
        end
        local world=parent.world
        if world and (not U.inWorld(actor,world) or not U.inWorld(parent.actor,world)) then return end
        local key,name=U.key(actor),full(actor);if not key or type(name)~='string' then return end
        local prior=children[key]
        if prior and prior.name==name and prior.parent~=parent then
            self.failures=self.failures+1;prior.quarantine=true;say('conflict','原生阶段虚空归属冲突，未改其他梦华');return
        end
        if not prior or prior.name~=name then
            children[key]={actor=actor,name=name,parent=parent,ability=ability,preFinished=true}
            self.kept=self.kept+1
        end
        parent.observedSummon=true;parent.lostBeforePair=nil
        parent.summonPassive={ability=ability,name=full(ability)}
        if not parent.skip then seedAnchor(children[key],'FinishSpawn前') else parent.skipReady=false end
        parent.busy=not parent.stopping and not parent.departed
        say('spawn','FinishSpawn前登记原生阶段父子；父='..parent.name..' 子='..name..' 归属读回=true')
    end
    local function pairStart(context,role,supplied)
        if not next(children) then return end
        local ability=U.unwrap(context);if classPath(ability)~=(role=='ex' and EX or ED) then return end
        local info=supplied and U.unwrap(supplied) or U.field(ability,'Execution Info')
        local executor=actorRef(U.struct(info,'Executor'));local target=actorRef(U.struct(info,'Target'))
        local child=childOf(executor);local parent=parentOf(target)
        if not child or child.parent~=parent or child.quarantine or child.retired then return end
        local avatar=call(ability,'GetAvatarActorFromActorInfo')
        if not same(avatar,role=='ex' and child.actor or parent.actor) then return end
        local key=U.key(ability);local name=full(ability)
        if not key or type(name)~='string' then return end
        pairRecords[key]={ability=ability,name=name,child=child,role=role}
        child.pairStarted=true;parent.busy=true
        say('pair','原生配对启动 '..role..'；Execution Info双方归属读回=true')
    end
    local function pairEnd(context,role,cancelled)
        local ability=U.unwrap(context);local entry=pairRecords[U.key(ability) or '']
        if not entry or entry.role~=role or entry.name~=full(ability) then return end
        entry.ended=true
        entry.child.pairEnded=true
        entry.child.pairCancelled=U.unwrap(cancelled)==true
        say('pair-end','已确认原生配对结束 '..role..'；取消='..tostring(entry.child.pairCancelled)..'；后续核对专属锁再回收')
    end
    callbacks.exStart=function(context)finishWarpWindow(context);pairStart(context,'ex')end
    callbacks.edStart=function(context)pairStart(context,'ed')end
    callbacks.exInfo=function(context,info)pairStart(context,'ex',info)end
    callbacks.edInfo=function(context,info)pairStart(context,'ed',info)end
    callbacks.exEnd=function(context,cancelled)closeWindow(context);pairEnd(context,'ex',cancelled)end
    callbacks.edEnd=function(context,cancelled)pairEnd(context,'ed',cancelled)end
    local function install()
        local complete=true;for _,name in ipairs(ORDER)do if not hooks[name] then complete=false end end
        if complete then return true end
        if not supported() or clock()<installAt then return false end;installAt=clock()+1
        if nullActor==nil then
            local ok,value=pcall(createInvalid)
            if not ok or value==nil or (type(value)~='table' and type(value)~='userdata') or U.valid(value) then return false end;nullActor=value
        end
        for _,name in ipairs(ORDER)do
            if not hooks[name] then
                local fn=lookup(Phase.paths[name])
                if not U.valid(fn) and PACKAGES[name] and type(load)=='function' and (not loads[PACKAGES[name]] or clock()>=loads[PACKAGES[name]]) then
                    loads[PACKAGES[name]]=clock()+5
                    pcall(load,PACKAGES[name]);local ok,value=pcall(find,Phase.paths[name]);fn=ok and value or nil
                end
                if U.valid(fn) then
                    local ok,pre,post=pcall(register,Phase.paths[name],function(...)
                        if not alive or not thread() then return end
                        local args={...};local worked,value=pcall(callbacks[name],table.unpack(args))
                        if worked then return value end
                        self.failures=self.failures+1;say('callback','回调未确认 '..name..' '..tostring(value))
                    end,function()end)
                    if ok and pre~=nil and pre~=false then hooks[name]={pre,post};say('hook','安装 '..name..'；ID读回='..tostring(pre)) end
                end
            end
        end
        for _,name in ipairs(ORDER)do if not hooks[name] then return false end end
        return true
    end
    local function uninstall(force,keepStoryLookup)
        if not force and clock()<unhookAt then return end;unhookAt=clock()+1
        for name,ids in pairs(hooks)do
            if not keepStoryLookup or name~='lookup' then
                local ok,value=pcall(unregister,Phase.paths[name],ids[1],ids[2]);if ok and value~=false then hooks[name]=nil end
            end
        end
    end
    function self:syncParents(units)
        local seen={}
        for _,unit in ipairs(units or {})do
            local actor=unit.actor;local key,name=U.key(actor),full(actor)
            if key and type(name)=='string' and TEAMS[unit.team] and not unit.summoner and not unit.aid and not unit.stand and classPath(actor)==PARENT then
                seen[key]=true
                if not parents[key] or parents[key].name~=name then
                    local skip=options.rule and options.rule('BP_Monster_MengHua')=='skip' or false
                    parents[key]={actor=actor,name=name,team=unit.team,skip=skip,busy=skip,skipReady=false,world=options.world and options.world()}
                    say('rule','登记本次梦华剧情联动='..(skip and '跳过' or '保留')..'；下次召唤选择已冻结')
                end
                parents[key].departed=false
            end
        end
        for key,row in pairs(parents)do if not seen[key] then row.departed=true;row.busy=false end end
        if next(seen) and ready() and thread() then install() end
    end
    function self:prepare(actor)
        if classPath(actor)~=PARENT then return true end
        if not thread() or not ready() or not parentOf(actor) or not install() then
            local parent=parentOf(actor)
            return false,parent and parent.skip and '梦华跳过阶段接口未就绪，不能确认剧情联动已关闭' or '梦华阶段实例隔离接口未就绪，不能确认原版阶段收尾'
        end
        return true
    end
    function self:handle(link)
        local parent=parentOf(link.parent)
        if not parent or classPath(link.actor)~=CHILD then return false end
        local row=childOf(link.actor)
        if not row and link.mode~='Summoner' then return false end
        if not row then
            -- Preserve a precisely linked but unobserved helper for diagnosis rather than deleting the stage dependency.
            local key,name=U.key(link.actor),full(link.actor)
            if key and type(name)=='string' then
                children[key]={actor=link.actor,name=name,parent=parent,quarantine=true};parent.busy=true
                parent.observedSummon=true;parent.lostBeforePair=nil
                if parent.skip then parent.skipReady=false end
                self.failures=self.failures+1;say('late','阶段虚空出生隔离未读回，保留原生对象并报告，不接入普通对战')
            end
        elseif row.parent~=parent then self.failures=self.failures+1;row.quarantine=true end
        return true
    end
    function self:busyKey(key)
        local row=parents[key or ''];return row~=nil and row.busy==true and row.name==full(row.actor) and not row.departed
    end
    function self:busy(actor)
        if not next(parents) then return false end
        return self:busyKey(U.key(actor))
    end
    function self:storyLink(actor)
        local parent=parentOf(actor)
        if not parent or parent.stopping or parent.departed then return end
        if not parent.skip then return 'keep' end
        if parent.skipReady then return 'skip' end
    end
    function self:tick()
        if not alive or not thread() or clock()<nextTick then return end;nextTick=clock()+0.5
        for key,row in pairs(storyLinks)do
            if not U.valid(row.actor) or row.name~=full(row.actor) then storyLinks[key]=nil end
        end
        if not next(parents) and not next(children) then
            uninstall(false,next(storyLinks)~=nil);self.state=next(storyLinks) and 'story_guard' or 'idle';return
        end
        if not ready() then self.state='waiting';return end
        local installed=install()
        local pending=0
        local gameTime
        for _,parent in pairs(parents)do
            if parent.stopping then parent.cleanupReady=prepareCleanup(parent);if not parent.cleanupReady then pending=pending+1 end end
            if parent.skip and not parent.skipReady and not parent.stopping and not parent.departed and not parentDead(parent) then
                parent.skipReady=skipStage(parent);parent.busy=not parent.skipReady
                if not parent.skipReady then pending=pending+1 end
            elseif installed and options.gameTime and COMBAT_TEAMS[parent.team] then
                if gameTime==nil then gameTime=options.gameTime() or false end
                resetRecoveryAfterOffCombat(parent)
                requestStageSummon(parent,gameTime)
            end
        end
        for key,row in pairs(children)do
            if not U.valid(row.actor) or row.name~=full(row.actor) then
                if row.preFinished and not row.retired and not row.quarantine and not row.pairStarted
                    and not row.parent.skip and not row.parent.stopping and not row.parent.departed then
                    row.parent.lostBeforePair=row.ability
                end
                children[key]=nil
            elseif not row.retired and (not row.parent.skip or row.parent.stopping or row.parent.departed or parentDead(row.parent)) then
                local finish=row.parent.stopping or row.parent.departed or parentDead(row.parent)
                if not finish and row.pairEnded and not pairAlive(row) then
                    local count=lockCount(row.parent.actor)
                    if count==0 then finish=true end
                    say('lock','原生收尾后专属锁数量读回='..tostring(count))
                end
                if finish then
                    if row.parent.stopping and not row.parent.cleanupReady then pending=pending+1
                    elseif cleanup(row,row.parent.stopping or row.parent.departed or parentDead(row.parent)) then
                        if row.pairEnded and not row.anchorFailed and not row.parent.stopping and not row.parent.departed and not parentDead(row.parent) then self.completed=self.completed+1 end
                    else pending=pending+1 end
                else
                    row.parent.busy=true
                    if row.quarantine or row.anchorFailed then pending=pending+1 end
                end
            end
        end
        for key,row in pairs(parents)do
            local retained=false;for _,child in pairs(children)do if child.parent==row and not child.retired then retained=true end end
            if not retained then
                row.busy=row.skip and not row.skipReady and not row.stopping and not row.departed and not parentDead(row) or false
                if not U.valid(row.actor) or row.name~=full(row.actor) then parents[key]=nil end
            end
        end
        for key,entry in pairs(pairRecords)do if entry.ended or not U.valid(entry.ability) or entry.child.retired then pairRecords[key]=nil end end
        for key,stack in pairs(warpWindows)do
            for i=#stack,1,-1 do
                local entry=stack[i]
                if clock()<entry.at or clock()-entry.at>WINDOW_SECONDS then
                    if not entry.blocked then
                        call(entry.ability,'K2_CancelAbility');self.failures=self.failures+1
                        say('window-expired','过期本组锚点窗口退休；动作取消读回='..tostring(U.field(entry.ability,'bIsActive')==false))
                    end
                    if stack[i]==entry then table.remove(stack,i)end
                elseif not childOf(entry.child.actor) or not U.valid(entry.ability) then table.remove(stack,i)end
            end
            if #stack==0 then warpWindows[key]=nil end
        end
        if not next(parents) and not next(children) then uninstall(false,next(storyLinks)~=nil) end
        local retained=false;for _,row in pairs(children)do if not row.retired then retained=true;break end end
        self.state=pending>0 and 'pending' or retained and 'stage' or next(parents) and 'ready' or next(storyLinks) and 'story_guard' or 'idle'
    end
    function self:stop(teams)
        teams=teams or {blue=true,red=true,neutral=true}
        local confirmed=true
        for _,row in pairs(parents)do
            if teams[row.team] then row.stopping=true;row.busy=false;row.cleanupReady=prepareCleanup(row);if not row.cleanupReady then confirmed=false end end
        end
        for _,row in pairs(children)do
            if teams[row.parent.team] and not row.retired then
                if not row.parent.cleanupReady or not cleanup(row,true) then confirmed=false end
            end
        end
        self.state=confirmed and 'stopped' or 'cleanup_pending'
        return confirmed
    end
    function self:releaseActor(actor)
        local parent=parentOf(actor);if not parent then return true end
        parent.stopping=true;parent.busy=false
        local confirmed=prepareCleanup(parent);parent.cleanupReady=confirmed
        if confirmed then for _,row in pairs(children)do if row.parent==parent and not row.retired and not cleanup(row,true) then confirmed=false end end end
        return confirmed
    end
    function self:status()
        local p,c,h,b,s=0,0,0,0,0
        for _,row in pairs(parents)do p=p+1;if row.busy then b=b+1 end end
        for _,row in pairs(children)do if not row.retired then c=c+1 end end
        for _ in pairs(hooks)do h=h+1 end
        for _ in pairs(storyLinks)do s=s+1 end
        return {supported=supported(),skip_supported=supported() and type(options.rule)=='function',state=self.state,parents=p,helpers=c,busy=b,hooks=h,failures=self.failures,completed=self.completed,anchors=self.anchors,storyGuards=s}
    end
    function self:silence()
        if thread() then
            if not self:stop(TEAMS) then say('shutdown','卸载前原生阶段/帮手恢复仍未确认，请先遣散梦华随从并清理确认后再重载') end
        elseif next(children) then say('shutdown','非游戏线程卸载不访问阶段对象；清理未确认，请先遣散梦华随从') end
        alive=false;uninstall(true)
    end
    return self
end
return Phase
