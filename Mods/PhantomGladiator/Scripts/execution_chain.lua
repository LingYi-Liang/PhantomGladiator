-- Only open a managed NPC's native continuous-execution window when another usable enemy is nearby.
-- Keep the game's target selection/QTE for eligible candidates; never change the player's own result.
local U=require('ue_observe')
local Chain={}
local CLASS='/PBZCombatAsset/Prototypes/Actions/GAA_ContinuousExecution.GAA_ContinuousExecution_C'
Chain.path=CLASS..':K2_CanActivateAction'
local STANDARD='Targeting.Handler.ContinuousExecution.Execution'
-- Read from that handler's current cooked defaults, not the ordinary execution prompt's health threshold.
local BLOCKED={'CharacterState.HitReact.State.Dead','CharacterState.HitReact.State.Executing','CharacterState.Dead',
    'CharacterState.CanNotBeExecuted','CharacterType.GiantEnemy','CharacterType.Animal','CharacterType.AI.Boss','Driver.Driving'}
local function call(object,method,...)
    if not U.valid(object) then return nil end
    local args,n={...},select('#',...)
    local ok,value=pcall(function()return object[method](object,table.unpack(args,1,n))end)
    if ok then return U.unwrap(value) end
    return nil
end
local function tag(value)
    local n=U.struct(value,'TagName')
    if type(n)=='string' then return n end
    local ok,s=pcall(function()return n:ToString()end)
    return ok and s or nil
end
local function short(object)
    local n=call(object,'GetFName');local ok,s=pcall(function()return n:ToString()end)
    return ok and s or '?'
end
local function weak(v)
    v=U.unwrap(v)
    if U.valid(v) and U.key(v) then return v end
    local ok,object=pcall(function()return v:Get()end)
    return ok and U.valid(object) and object or nil
end
local function position(actor)
    local v=call(actor,'K2_GetActorLocation')
    local x,y,z=U.struct(v,'X'),U.struct(v,'Y'),U.struct(v,'Z')
    if type(x)=='number' and type(y)=='number' and type(z)=='number' then return {X=x,Y=y,Z=z} end
end

function Chain.new(options)
    local log=options.log or function()end
    local find=options.staticFind or StaticFindObject
    local load=options.loadAsset or LoadAsset
    local register=options.registerHook or RegisterHook
    local unregister=options.unregisterHook or UnregisterHook
    local name=options.fname or FName
    local findAll=options.findAll or FindAllOf
    local self={}
    local record,hook,uncertain=nil,nil,false
    local verifying=false
    local generation,lines=0,0
    local function say(text)if lines<40 then lines=lines+1;log('[ExecutionChain] '..text)end end
    local function has(actor,text)
        local count=call(U.field(actor,'AbilitySystemComponent'),'GetGameplayTagCount',{TagName=name(text)})
        return type(count)=='number' and count>0 or false
    end
    local function ranges(action)
        local handlerTag=U.field(action,'TargetingHandlerTag')
        local component=U.field(record.executor,'Targeting Component')
        local handler=handlerTag and call(component,'GetTargetHandler',handlerTag)
        local out={}
        for _,p in ipairs(U.array(U.field(handler,'ParamsList')) or {}) do
            local max=U.struct(p,'MaxDistance');local min=U.struct(p,'MinDistance');local z=U.struct(p,'MaxZDiff')
            if type(max)=='number' and max>0 then out[#out+1]={min=type(min)=='number' and min or 0,max=max,z=type(z)=='number' and z or math.huge} end
        end
        if #out==0 and tag(handlerTag)==STANDARD then out={{min=0,max=1600,z=400}} end
        return out,tag(handlerTag)==STANDARD
    end
    local function available(action)
        local members=options.members() or {}
        local mine
        for _,m in ipairs(members) do if U.key(m.actor)==record.key then mine=m.team;break end end
        if mine~='blue' and mine~='red' then return false,'执行方已不在参赛队伍' end
        local from=position(record.executor)
        if not from then return false,'执行方位置不可读' end
        local bounds,standard=ranges(action)
        local rejected={}
        for _,m in ipairs(members) do
            local candidate=m.actor
            local key=U.key(candidate)
            if key and key~=record.key and key~=record.targetKey and (m.team=='blue' or m.team=='red') and m.team~=mine
                and not (options.isImmortal and options.isImmortal(m.team)) and call(candidate,'IsActorBeingDestroyed')~=true then
                local hp=options.health(candidate)
                local at=type(hp)=='number' and hp>0 and position(candidate)
                if at then
                    local dx,dy,dz=at.X-from.X,at.Y-from.Y,at.Z-from.Z
                    local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
                    local near=#bounds==0 -- Unknown handlers retain their own distance/filter decisions.
                    for _,b in ipairs(bounds) do if distance>=b.min and distance<=b.max and math.abs(dz)<=b.z then near=true;break end end
                    local blocked=false
                    if standard then
                        for _,t in ipairs(BLOCKED) do if has(candidate,t) then blocked=true;break end end
                        if has(candidate,'CharacterState.Unselectable') and not has(candidate,'CharacterState.Unselectable.KeepLock') then blocked=true end
                    end
                    -- A chain action supplies its own follow-up ability. Its handler does not require the
                    -- candidate's ordinary TargetExecutionAnims table; leave final compatibility to the game.
                    if near and not blocked then
                        return true,string.format('候选=%s HP=%.2f 距离=%.1fm；保留原生角度/路径/选目标判断',short(candidate),hp,distance/100)
                    end
                    if #rejected<4 then rejected[#rejected+1]=string.format('%s HP=%.2f 距离=%.1fm 范围=%s 标签排除=%s',short(candidate),hp,distance/100,tostring(near),tostring(blocked)) end
                elseif #rejected<4 then
                    rejected[#rejected+1]=short(candidate)..' HP='..tostring(hp)..' 位置='..tostring(at~=nil)
                end
            end
        end
        return false,'可连携敌人=0；'..(#rejected>0 and table.concat(rejected,'；') or '无其他存活敌方候选（自己、当前目标、同队及销毁对象不计）')
    end
    local function capture(r,action)
        local key=U.key(action)
        if not key then return nil end
        local entry=r.actions[key]
        if not entry then entry={action=action,tasks={},readbacks=0};r.actions[key]=entry end
        local task=U.field(action,'QTE Task');local tk=U.key(task)
        if tk then
            local ext=U.field(task,'ExtensionObj')
            local owned=entry.tasks[tk] or {task=task}
            if U.valid(ext) then owned.extension=ext end
            entry.tasks[tk]=owned
            if U.field(ext,'bFinished')~=true then entry.started=true end
        end
        if U.field(action,'ExecutionEnabled')==true then entry.started=true end
        return entry
    end
    local function invoke(object,method)
        if not U.valid(object) then return false end
        return pcall(function()object[method](object)end)
    end
    local function handleValid(extension)
        local handle=U.field(extension,'Handle')
        local okWorld,world=pcall(options.getWorld or function()return nil end)
        if not okWorld or not U.valid(world) or handle==nil then return nil end
        local okLib,lib=pcall(find,'/Script/Engine.Default__SubsystemBlueprintLibrary')
        local okClass,cls=pcall(find,'/Script/UIExtension.UIExtensionSubsystem')
        if okLib and okClass and U.valid(cls) then
            local subsystem=call(lib,'GetWorldSubsystem',world,cls)
            -- The handle library's "IsValid" collides with UE4SS UObject:IsValid. Use the unambiguous API.
            return call(subsystem,'IsValidHandle',handle)
        end
        return nil
    end
    local function cleanup(r)
        if not r then return end
        local seen={}
        for _,entry in pairs(r.actions) do
            capture(r,entry.action)
            for key,owned in pairs(entry.tasks) do
                if not seen[key] and not owned.cleaned then
                    seen[key]=true
                    local task,ext=owned.task,owned.extension
                    local before=U.field(ext,'bFinished')
                    local ended=invoke(task,'EndTask')
                    local deactivated=invoke(ext,'Deactivate')
                    owned.cleaned=U.field(ext,'bFinished')==true and handleValid(ext)~=true
                    log('[ExecutionChain] 清理本次QTE task='..short(task)..' EndTask='..tostring(ended)
                        ..' Deactivate='..tostring(deactivated)..' finished='..tostring(before)..'→'..tostring(U.field(ext,'bFinished'))
                        ..' UI句柄仍有效='..tostring(handleValid(ext)))
                end
            end
        end
    end
    local function install()
        if uncertain or type(register)~='function' or type(unregister)~='function' then say('连携检查未安装：接口不可用或旧注册状态不明');return false end
        if hook then return true end
        local ok,fn=pcall(find,Chain.path)
        if not ok or not U.valid(fn) then
            pcall(load,CLASS)
            ok,fn=pcall(find,Chain.path)
        end
        if not ok or not U.valid(fn) then say('连携检查未安装：函数尚未加载');return false end
        generation=generation+1
        local token=generation
        local callback=function(context)
            if token~=generation or not record then return nil end
            local action=U.unwrap(context)
            local avatar=call(action,'GetAvatarActor')
            if not U.valid(record.executor) or U.key(avatar)~=record.key then return nil end
            local player=options.getPlayer and options.getPlayer()
            if U.valid(player) and U.key(player)==record.key then return nil end
            local ability=call(action,'GetAbility')
            if U.key(call(ability,'GetClass'))~=record.classKey then return nil end
            local entry=capture(record,action)
            if not entry then return nil end
            record.checks=record.checks+1
            if entry.started then
                if not entry.saidStarted then entry.saidStarted=true;say('连携窗口已经开始，保留原生结束/清理流程') end
                record.pending=action
                return nil
            end
            local checked,yes,detail=pcall(available,action)
            if not checked then say('连携候选读回失败，保留原生判断：'..tostring(yes));return nil end
            if not verifying then
                if entry.lastDecision~=yes then
                    say((yes and '允许原生连携窗口：' or '阻止空连携窗口：')..detail)
                    entry.lastDecision=yes
                end
                record.pending=action
            end
            if not yes then return false end
            return nil -- A plausible target exists; never force a native rejection into true.
        end
        local registered,pre,post=pcall(register,Chain.path,callback)
        if registered and type(pre)=='number' and type(post)=='number' then
            hook={pre=pre,post=post}
            say('安装蓝图激活检查 读回ID='..pre..'/'..post..'；仅限本次NPC、技能实例类型')
            return true
        end
        generation=generation+1;uncertain=registered
        say('连携检查注册未确认：'..tostring(pre));return false
    end
    function self:begin(executor,target,abilityClass)
        record=nil;lines=0
        local key,classKey=U.key(executor),U.key(abilityClass)
        if not key or not classKey or not install() then return false end
        record={executor=executor,key=key,targetKey=U.key(target),classKey=classKey,actions={},checks=0}
        return true
    end
    function self:tick()
        if record and record.pending then
            local action=record.pending;record.pending=nil
            local entry=capture(record,action)
            if entry and entry.readbacks<3 then
                -- This blueprint predicate is a pure "return true" before our gate. Read its effective return
                -- on the later support tick, never recursively from its own callback.
                verifying=true
                local actual=call(action,'K2_CanActivateAction')
                verifying=false
                entry.readbacks=entry.readbacks+1
                say('后续读回 CanActivate='..tostring(actual)..' ExecutionEnabled='..tostring(U.field(action,'ExecutionEnabled'))
                    ..' QTE任务有效='..tostring(U.valid(U.field(action,'QTE Task'))))
            end
        end
        if record then
            for _,entry in pairs(record.actions) do
                local action=entry.action
                if not entry.requested and U.valid(action) and U.field(action,'ExecutionEnabled')==true
                    and U.key(call(action,'GetAvatarActor'))==record.key then
                    local ability=call(action,'GetAbility')
                    local selected=weak(U.field(action,'SelectedTarget'))
                    local targetKey=U.key(selected)
                    local mine,theirs
                    for _,m in ipairs(options.members() or {})do
                        if U.key(m.actor)==record.key then mine=m.team end
                        if targetKey and U.key(m.actor)==targetKey then theirs=m.team end
                    end
                    local hp=targetKey and options.health(selected)
                    local player=options.getPlayer and options.getPlayer()
                    if U.key(call(ability,'GetClass'))==record.classKey and targetKey~=record.key and targetKey~=record.targetKey
                        and (mine=='blue' or mine=='red') and (theirs=='blue' or theirs=='red') and mine~=theirs
                        and type(hp)=='number' and hp>0 and not (options.isImmortal and options.isImmortal(theirs))
                        and not (U.valid(player) and U.key(player)==targetKey) and call(selected,'IsActorBeingDestroyed')~=true
                        and not has(selected,'CharacterState.Dead') and not has(selected,'CharacterState.HitReact.State.Dead') then
                        entry.requested=true
                        local ok,err=pcall(function()action:ManualCallExecutionInput()end)
                        say('NPC代按连携 原生选中='..short(selected)..' HP='..hp..' 调用='..tostring(ok)
                            ..(ok and '；等待原生下一段处决读回' or ' '..tostring(err)))
                    end
                end
            end
        end
    end
    function self:stop(reason)
        local prior=record
        record=nil;generation=generation+1
        cleanup(prior)
        if prior then log('[ExecutionChain] 本轮检查次数='..prior.checks..' 结束='..tostring(reason)) end
        if hook then
            local ok,err=pcall(unregister,Chain.path,hook.pre,hook.post)
            say('移除连携检查 '..tostring(reason)..' 调用='..tostring(ok)..(ok and '' or ' '..tostring(err)))
            if ok then hook=nil else uncertain=true end
        end
    end
    function self:closeTasks()cleanup(record)end
    function self:silence()
        record=nil;generation=generation+1
        -- UE4SS removes its Lua hooks during unload, as for the existing combat probe.
    end
    local audited=false
    function self:auditExisting()
        if audited then return end
        audited=true
        -- Snapshot the already lingering icon. Only a natively finished extension with a still-valid UI
        -- registration is retired; no active/unreadable QTE is ended by this startup sweep.
        for _,kind in ipairs({'AbilityTask_RegisterQTE','RegisterQTEExtensionObj'}) do
            local ok,objects=pcall(findAll,kind)
            local count=0
            for _,object in ipairs(ok and U.array(objects) or {}) do
                if U.valid(object) and not short(object):match('^Default__') and count<12 then
                    count=count+1
                    local ext=kind=='RegisterQTEExtensionObj' and object or U.field(object,'ExtensionObj')
                    log('[ExecutionQTEAudit] kind='..kind..' object='..short(object)..' outer='..short(call(object,'GetOuter'))
                        ..' input='..short(U.field(ext,'InputAction'))..' finished='..tostring(U.field(ext,'bFinished'))
                        ..' UI句柄有效='..tostring(handleValid(ext))..' time='..tostring(U.field(object,'CurrentTime'))..'/'..tostring(U.field(object,'TotalTime')))
                    if U.field(ext,'bFinished')==true and handleValid(ext)==true then
                        local ok=invoke(ext,'Deactivate')
                        log('[ExecutionQTEAudit] 撤销已结束的遗留UI '..short(ext)..' 调用='..tostring(ok)..' UI句柄仍有效='..tostring(handleValid(ext)))
                    end
                end
            end
            log('[ExecutionQTEAudit] kind='..kind..' sampled='..count..' scan='..tostring(ok))
        end
    end
    return self
end
return Chain
