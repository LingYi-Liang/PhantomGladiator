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
local LOCK=MOBS..'078_MengHua/GameplayEffects/GE_MengHua_XuKong_LockHealth.GE_MengHua_XuKong_LockHealth_C'
local AI='/Script/SGameAI.Default__SGameAIFunctionLibrary'
local UTILS='/Script/SGameUtils.Default__AbilityUtils'
local ACTIVE='CharacterState.AbilityState.MengHua.XuKong.Active'
local ASSIGN='AI.BlackboardKey.Object.AssignActor1'
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
    warp='/Script/MotionWarping.MotionWarpingComponent:AddOrUpdateWarpTargetFromLocationAndRotation',passive=PASSIVE..':K2_ActivateAbility',skill4Close=SKILL4..':K2_ActivateAbility'}
local PACKAGES={spawn='/SGameAI/Core/AIScript/GA_SummonPassive.GA_SummonPassive_C',exStart=EX,exEnd=EX,edStart=ED,edEnd=ED,
    exInfo='/SGameExecution/GA/GA_ExecutionAbilityBase.GA_ExecutionAbilityBase_C',edInfo='/SGameExecution/GA/GA_ExecutedAbilityBase.GA_ExecutedAbilityBase_C',
    exWindow='/SGameExecution/GA/GA_ExecutionAbilityBase_Grab.GA_ExecutionAbilityBase_Grab_C',
    enterWindow='/MagCombatAbilities/Abilities/BP_ActionAbilityBase_Simple.BP_ActionAbilityBase_Simple_C',enterClose=ENTER,passive=PASSIVE,skill4Close=SKILL4}
local ORDER={'lookup','player','spawn','exStart','exEnd','edStart','edEnd','exInfo','edInfo','exWindow','enterWindow','enterClose','warp','passive','skill4Close'}
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
    local parents,children,pairRecords,hooks,loads={},{},{},{},{}
    local warpWindows={}
    local internalWarp=false
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
    local function scope(context)
        if not next(children) then return nil end
        local object=U.unwrap(context);local visited={}
        for _=1,5 do
            local key=U.key(object);if not key or visited[key] then return nil end;visited[key]=true
            local row=childOf(object);if row then return row end
            local path=classPath(object) or '';local name=path:match('%.([^%.]+)$') or ''
            local avatar
            if name:match('^GA_') then avatar=call(object,'GetAvatarActorFromActorInfo')
            elseif name:match('^GAA?_') or name:match('^LGAAction') then avatar=call(object,'GetAvatarActor') end
            if U.valid(avatar) then return childOf(avatar) end
            if name:match('^GA_') or name:match('^GAA?_') or name:match('^LGAAction') then return nil end
            -- Non-ability children may be outered to their ability or helper. World/level contexts cannot be one.
            if not path:find('/PBZCombatAsset/ActorData/Mobs/079_XuKong/',1,true) then return nil end
            object=call(object,'GetOuter')
        end
    end
    local function lockCount(parent)
        local asc=U.field(parent,'AbilitySystemComponent');local cls=lookup(LOCK)
        local name=full(cls)
        if not U.valid(asc) or not U.valid(cls) or type(name)~='string' or name:match('^%S+ (/.+)$')~=LOCK or call(cls,'IsAnyClass')~=true then return nil end
        local count=call(asc,'GetGameplayEffectCount',cls,nil,false)
        return type(count)=='number' and count>=0 and count or nil
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
        if same(current,row.actor) then
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
        if U.valid(row.ability) and same(call(row.ability,'GetAvatarActorFromActorInfo'),row.parent.actor) then call(row.ability,'DestroySummons',row.actor) end
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
    local function endParentStage(parent)
        -- Only explicit cleanup uses the original passive's End; running stages keep their normal finish.
        local phase=scopedPassive(parent,PASSIVE,'phasePassive')
        if U.valid(phase) and U.field(phase,'bIsActive')~=false then call(phase,'K2_CancelAbility') end
        local summon=scopedPassive(parent,SUMMON,'summonPassive')
        if U.valid(summon) and U.field(summon,'bIsActive')~=false then call(summon,'K2_CancelAbility') end
        local count=lockCount(parent.actor)
        local confirmed=count==0 and (not U.valid(phase) or U.field(phase,'bIsActive')==false)
            and (not U.valid(summon) or U.field(summon,'bIsActive')==false)
        say('restore','清理时结束本父原生阶段被动；专属锁数量读回='..tostring(count)..' 被动结束确认='..tostring(confirmed))
        if confirmed and U.valid(phase) then parent.nativeStageEnded=true end
        return confirmed
    end
    local function prepareCleanup(parent)
        -- Pair actors must finish/cancel before the summon's passive is allowed to destroy the helper.
        for _,entry in pairs(pairRecords)do
            if entry.child.parent==parent and not entry.ended and U.valid(entry.ability) then call(entry.ability,'K2_CancelAbility') end
        end
        for _,entry in pairs(pairRecords)do
            if entry.child.parent==parent and not entry.ended and U.valid(entry.ability) and U.field(entry.ability,'bIsActive')~=false then return false end
        end
        return parentDead(parent) or endParentStage(parent)
    end
    local callbacks={}
    callbacks.passive=function(context)
        local ability=U.unwrap(context);if classPath(ability)~=PASSIVE then return end
        local parent=parentOf(call(ability,'GetAvatarActorFromActorInfo'));if not parent then return end
        parent.phasePassive={ability=ability,name=full(ability)}
        if parent.stopping then call(ability,'K2_CancelAbility') end
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
        if child.retired or child.quarantine or child.parent.stopping or child.parent.departed then return false end
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
        local row=scope(context);if not row then return end
        local name=full(U.unwrap(cls));local path=type(name)=='string' and name:match('^%S+ (/.+)$')
        if path~=PARENT then return end
        local parent=row.parent
        if not row.seeded then seedAnchor(row,'原生BeginPlay搭档绑定前') end
        local valid=not row.retired and not row.quarantine and not parent.stopping and not parent.departed and parentOf(parent.actor) and not parentDead(parent)
        say('actor-lookup','阶段搭档查找实例隔离；父对象有效读回='..tostring(not not valid))
        return valid and parent.actor or nullActor
    end
    callbacks.player=function(_,context)
        if not alive or not thread() then return end
        local row=scope(context);if not row then return end
        local parent=row.parent
        return not row.retired and not row.quarantine and not parent.stopping and not parent.departed and parentOf(parent.actor) and not parentDead(parent) and parent.actor or nullActor
    end
    callbacks.spawn=function(context,pawn)
        if not alive or not thread() then return end
        local ability,actor=U.unwrap(context),U.unwrap(pawn)
        if classPath(ability)~=SUMMON or classPath(actor)~=CHILD then return end
        local parent=parentOf(call(ability,'GetAvatarActorFromActorInfo'))
        if not parent then return end
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
        parent.summonPassive={ability=ability,name=full(ability)}
        seedAnchor(children[key],'FinishSpawn前')
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
        pairRecords[key]={ability=ability,name=name,child=child,role=role};parent.busy=true
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
    local function uninstall(force)
        if not force and clock()<unhookAt then return end;unhookAt=clock()+1
        for name,ids in pairs(hooks)do
            local ok,value=pcall(unregister,Phase.paths[name],ids[1],ids[2]);if ok and value~=false then hooks[name]=nil end
        end
    end
    function self:syncParents(units)
        local seen={}
        for _,unit in ipairs(units or {})do
            local actor=unit.actor;local key,name=U.key(actor),full(actor)
            if key and type(name)=='string' and TEAMS[unit.team] and not unit.summoner and not unit.aid and not unit.stand and classPath(actor)==PARENT then
                seen[key]=true
                if not parents[key] or parents[key].name~=name then parents[key]={actor=actor,name=name,team=unit.team,busy=false,world=options.world and options.world()} end
                parents[key].departed=false
            end
        end
        for key,row in pairs(parents)do if not seen[key] then row.departed=true;row.busy=false end end
        if next(seen) and ready() and thread() then install() end
    end
    function self:prepare(actor)
        if classPath(actor)~=PARENT then return true end
        if not thread() or not ready() or not parentOf(actor) or not install() then return false,'梦华阶段实例隔离接口未就绪，不能确认原版阶段收尾' end
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
    function self:tick()
        if not alive or not thread() or clock()<nextTick then return end;nextTick=clock()+0.5
        if not next(parents) and not next(children) then uninstall();self.state='idle';return end
        if not ready() then self.state='waiting';return end
        if ready() then install() end
        local pending=0
        for _,parent in pairs(parents)do
            if parent.stopping then parent.cleanupReady=prepareCleanup(parent);if not parent.cleanupReady then pending=pending+1 end end
        end
        for key,row in pairs(children)do
            if row.name~=full(row.actor) or not U.valid(row.actor) then children[key]=nil
            elseif not row.retired then
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
            if not retained then row.busy=false;if not U.valid(row.actor) or row.name~=full(row.actor) then parents[key]=nil end end
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
        if not next(parents) and not next(children) then uninstall() end
        local retained=false;for _,row in pairs(children)do if not row.retired then retained=true;break end end
        self.state=pending>0 and 'pending' or retained and 'stage' or next(parents) and 'ready' or 'idle'
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
        local p,c,h,b=0,0,0,0
        for _,row in pairs(parents)do p=p+1;if row.busy then b=b+1 end end
        for _,row in pairs(children)do if not row.retired then c=c+1 end end
        for _ in pairs(hooks)do h=h+1 end
        return {supported=supported(),state=self.state,parents=p,helpers=c,busy=b,hooks=h,failures=self.failures,completed=self.completed,anchors=self.anchors}
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
