-- Observe native execution transitions between this mod's opponents and complete only the two audited
-- grab-counter QTEs while their native action/task is live. No health-floor substitute for a grab counter.
local U=require('ue_observe')
local O={}
local Windows=require('arena_counter_windows')
O.bladePath=Windows.BLADE_GRAB..':OnTick_7E5A1E344065E15ADAE3BEB56AAD8275'
O.jadePath=Windows.JADE_GRAB_BASE..':K2_ActivateAbility'
O.jadeAfterPath='/PBZDeflectSystem/Abilities/BP_Hun_PerfectDodge_ExecutionBase.BP_Hun_PerfectDodge_ExecutionBase_C:Do Dodge After Deflect'
O.evadePath='/PBZDeflectSystem/Abilities/BP_PlayerDodge_Base.BP_PlayerDodge_Base_C:OnEvadeDamage'
O.executionPath='/Script/SGameExecution.ExecutionComponent:PlayExactExecution'
local QTE_CLASS='/PBZCombatAsset/Prototypes/Actions/GAA_MultiClickQTE.GAA_MultiClickQTE_C'
O.qtePath=QTE_CLASS..':Received_ActionBegin'
local SUCCESS='OnSuccess_07EF313E4694428175E13880AB103147'
local EVENTS={['GameplayEvent.QTE.LionDancer.Succeed']=true,['GameplayEvent.QTE.HookMan.Succeed']=true}
local function call(object,method,...)
    if not U.valid(object) then return nil end
    local args,n={...},select('#',...)
    local ok,v=pcall(function()return object[method](object,table.unpack(args,1,n))end)
    if ok then return U.unwrap(v) end
    return nil
end
local function weak(v)
    v=U.unwrap(v)
    if U.valid(v) and U.key(v) then return v end
    local ok,o=pcall(function()return v:Get()end)
    return ok and U.valid(o) and o or nil
end
local function tag(v)
    local n=U.struct(v,'TagName');if type(n)=='string' then return n end
    local ok,s=pcall(function()return n:ToString()end);return ok and s or nil
end
local function short(object)
    local n=call(object,'GetFName');local ok,s=pcall(function()return n:ToString()end);return ok and s or '?'
end
function O.new(options)
    local log=options.log or function()end
    local find=options.staticFind or StaticFindObject
    local load=options.loadAsset or LoadAsset
    local register=options.registerHook or RegisterHook
    local unregister=options.unregisterHook or UnregisterHook
    local defer=options.defer or function(fn)return ExecuteInGameThreadWithDelay(1,fn)end
    local cancel=options.cancel or CancelDelayedAction
    local self={alive=true}
    local hooks,queued,loaded={}, {}, {}
    local generation,lines=0,0
    local function say(s)if lines<60 then lines=lines+1;log('[ExecutionOpportunity] '..s)end end
    local function opponents(a,b)
        if not U.valid(a) or not U.valid(b) or U.key(a)==U.key(b) then return false end
        local player=options.getPlayer and options.getPlayer()
        if U.valid(player) and (U.key(a)==U.key(player) or U.key(b)==U.key(player)) then return false end
        local ta,tb
        for _,m in ipairs(options.members() or {})do
            if U.key(m.actor)==U.key(a) then ta=m.team end
            if U.key(m.actor)==U.key(b) then tb=m.team end
        end
        return (ta=='blue' or ta=='red') and (tb=='blue' or tb=='red') and ta~=tb
    end
    local function schedule(fn)
        local token=generation
        local handle
        local ok,result=pcall(defer,function()
            if handle then queued[handle]=nil end
            if not self.alive or token~=generation or options.inGameThread and not options.inGameThread() then return end
            local worked,err=pcall(fn)
            if not worked then say('原生机会处理失败：'..tostring(err)) end
        end)
        if ok and result then handle=result;queued[handle]=true
        else say('原生机会延后处理未登记：'..tostring(result)) end
    end
    local function execution(context,animData,target,startTime)
        if not self.alive or options.internal() or not options.available() then return end
        local component=U.unwrap(context)
        local executor=call(component,'GetOwner')
        target=U.unwrap(target);animData=U.unwrap(animData)
        local execution=U.struct(animData,'ExecutionAbility');local executed=U.struct(animData,'ExecutedAbility')
        if not opponents(executor,target) or not U.valid(execution) or not U.valid(executed) then return end
        local ability=short(execution)
        if options.grabReadback and lines<60 and (ability:lower():find('^ga_greatblademan_ca_01_gex') or ability:find('^GA_YuDing_GEx_01')) then
            say('原生抓取启动 招式='..ability..' 双方='..short(executor)..'/'..short(target)..' '..options.grabReadback(executor,target))
        end
        if not options.data(ability) then return end
        if not options.available(executor,target) then say('另一对处决表现仍在进行，未重复接管原生调用');return end
        local t=U.unwrap(startTime)
        local info={executor=executor,target=target,execution=execution,executed=executed,start=type(t)=='number' and t or 0}
        say('读到原生处决 '..short(executor)..' → '..short(target)..' / '..short(execution))
        schedule(function()if opponents(executor,target) then options.adopt(info)end end)
    end
    local function qte(context)
        if not self.alive or not options.available() then return end
        local action=U.unwrap(context)
        if not U.valid(action) or not EVENTS[tag(U.field(action,'Success Event'))] then return end
        local ability=call(action,'GetAbility')
        local info=U.field(ability,'Execution Info')
        local attacker,target=weak(U.struct(info,'Executor')),weak(U.struct(info,'Target'))
        if not opponents(attacker,target) or not options.available(target,attacker) then return end
        local task=U.field(action,'Async Task')
        if not U.valid(task) or U.field(action,'Triggered')~=false then return end
        say('原生反制QTE窗口 '..tostring(tag(U.field(action,'Success Event')))..'；双方='..short(attacker)..'/'..short(target))
        schedule(function()
            if not opponents(attacker,target) or not options.available(target,attacker) or not U.valid(action) or not U.valid(task) or U.field(action,'Triggered')~=false then return end
            local ext=U.field(task,'ExtensionObj')
            if U.field(ext,'bFinished')==true then return end
            local ok,err=pcall(function()action[SUCCESS](action)end)
            local triggered=U.field(action,'Triggered')
            say('NPC完成原生反制 回调='..tostring(ok)..' Triggered读回='..tostring(triggered)..(ok and '' or ' '..tostring(err)))
            if ok and triggered==true then
                local ended,cleared=false,false
                if U.valid(task) then ended=pcall(function()task:EndTask()end)end
                if U.valid(ext) then cleared=pcall(function()ext:Deactivate()end)end
                say('反制提示收尾 EndTask调用='..tostring(ended)..' task仍有效='..tostring(U.valid(task))
                    ..' Deactivate调用='..tostring(cleared)..' finished='..tostring(U.field(ext,'bFinished')))
            end
        end)
    end
    local windows=options.counterWindows
    local function bladeTick(context)
        if self.alive and windows.blade and not options.internal() then windows:bladeTick(U.unwrap(context)) end
    end
    local function jadeCast(context)
        if self.alive and windows.jade and not options.internal() then windows:jadeCast(U.unwrap(context)) end
    end
    local function jadeAfter(context)
        if not self.alive or not windows.jade or options.internal() then return end
        local ability=U.unwrap(context)
        schedule(function()
            local event=windows:jadePair(ability)
            if event and options.available(event.executor,event.target) then
                say('玉鼎精准闪避双方已启动 '..short(event.executor)..' → '..short(event.target))
                options.adopt(event)
            end
        end)
    end
    local function onEvade(context,source,_,perfect)
        if self.alive and windows.jade and U.unwrap(perfect)==true and not options.internal() then
            local actor=call(U.unwrap(context),'GetAvatarActorFromActorInfo')
            windows:jadeResult(actor,U.unwrap(source))
        end
    end
    function self:tick(members,foes)
        local fighting=self.alive and options.fighting()
        if windows then windows:sync(members or {},fighting,foes) end
        if not self.alive or not (fighting or windows and windows.blade) or type(register)~='function' or type(unregister)~='function' then return end
        local entries=fighting and {{path=O.executionPath,native=true,callback=execution},{path=O.qtePath,callback=qte,asset=QTE_CLASS}} or {}
        if windows and windows.blade then entries[#entries+1]={path=O.bladePath,callback=bladeTick} end
        if windows and windows.jade then
            entries[#entries+1]={path=O.jadePath,callback=jadeCast}
            entries[#entries+1]={path=O.evadePath,callback=onEvade}
            entries[#entries+1]={path=O.jadeAfterPath,callback=jadeAfter}
        end
        for _,entry in ipairs(entries)do
            local prior=hooks[entry.path]
            if prior and not prior.lease.enabled and not prior.uncertain and not prior.failed then
                if pcall(unregister,entry.path,prior.pre,prior.post) then hooks[entry.path]=nil end
            end
            if not hooks[entry.path] then
                local ok,fn=pcall(find,entry.path)
                if (not ok or not U.valid(fn)) and entry.asset and not loaded[entry.path] then
                    loaded[entry.path]=true;pcall(load,entry.asset);ok,fn=pcall(find,entry.path)
                end
                if ok and U.valid(fn) then
                    local lease={enabled=true}
                    local fnCallback=entry.callback
                    local callback=function(...)
                        if lease.enabled and (not options.inGameThread or options.inGameThread()) then return fnCallback(...) end
                    end
                    local installed,pre,post
                    if entry.native then installed,pre,post=pcall(register,entry.path,function()end,callback)
                    else installed,pre,post=pcall(register,entry.path,callback)end
                    if installed and type(pre)=='number' and type(post)=='number' then
                        hooks[entry.path]={pre=pre,post=post,lease=lease};say('安装 '..entry.path..' 读回ID='..pre..'/'..post)
                    else
                        lease.enabled=false
                        hooks[entry.path]={lease=lease,uncertain=installed,failed=not installed}
                        say('安装未确认 '..entry.path..' '..tostring(pre))
                    end
                end
            end
        end
    end
    function self:stop(reason)
        if windows then windows:clear() end
        generation=generation+1
        for handle in pairs(queued)do pcall(cancel,handle)end;queued={}
        for path,ids in pairs(hooks)do
            ids.lease.enabled=false
            if ids.failed then hooks[path]=nil
            elseif not ids.uncertain then
                local ok=pcall(unregister,path,ids.pre,ids.post);say('移除 '..path..' 调用='..tostring(ok)..' '..tostring(reason))
                if ok then hooks[path]=nil end
            end
        end
    end
    function self:silence()
        if windows then windows:clear() end
        self.alive=false;generation=generation+1
        for _,slot in pairs(hooks)do slot.lease.enabled=false end
        for handle in pairs(queued)do pcall(cancel,handle)end;queued={}
    end
    return self
end
return O
