-- The Hun body's own footwork may not end a move this mod started on it.
-- AIConfig_Hun lists AITask_CancelAbilities("Ability.Action") under PreMoveToExecuteTasks. BTTask_BaseMoveToTask and
-- BTTask_MoveAwayFromTarget run that list before every move: an NPC has no locomotion driver, so the abilities' own
-- CancelAbilityOnMoveInput never fires for it and the game needs another way to walk out of a recovery. The weapon
-- chains, shadow weapons and guards of this mod run beside the behaviour tree, so each step of it ended them in the
-- middle of the swing. With a short circling time the body restarted the first swing several times a second.
-- ExecuteTask_Internal is called by blueprint and cancels synchronously. For that one call the running action is made
-- uncancellable; hits, stuns, executions, the native attacks and death cancel it at any other time as before. A step
-- refused this way is granted through the ability's own Move Cancel Ability once its Cancel phase has nothing to chain.
--
-- The other interruption is the body's native attack pool (AbilityPool_Hun_JueYing). Its conditions read the body's own
-- tags (CheckTargetTags is off), and every weapon's light A carries the tag the pool's AA waits for: in a player's log
-- GA_Hun_Double_AAAA began 0.31 s into the soft sword's AAA, whose strike phase lasts until 0.80 s, and ended it through
-- CancelAbilitiesWithTag. While a move of the mod runs, the pool's nine abilities of this body are on cooldown: the
-- game's own check in BP_AbilityBase (Cooldown Data, Cooldown Mark Time, both per instance) refuses them. Short
-- cooldowns are renewed only while the action runs. Read-back failures retain the original values for another try.
local U=require('ue_observe')
local Vitals=require('hun_vitals')
local Guard={HOOK='/Script/SGameAI.SGameAITask:ExecuteTask_Internal',UTILS='/Script/SGameUtils.Default__AbilityUtils'}
local CANCEL={AITask_CancelAbilities_C=true,SGameAITask_CancelAbility=true}
-- AbilityPool_Hun_JueYing: the attacks the body's own AI starts. It may walk out of those as it always could.
local NATIVE={}
for _,s in ipairs({'A','AA','AAA','AAAA','AAAAA','B','BB','BBB','BBBB'})do NATIVE['GA_Hun_Double_'..s..'_C']=true end
local EXECUTING={'Ability.Action.Execution','Ability.Executed','CharacterState.HitReact.State.Executing'}
local COMBO,FINISH='CharacterState.Action.Phase.Combo','CharacterState.Action.Phase.Cancel'
local CHAINING=.45      -- s: the weapon loop pressed or looked for a chain this recently
local LONGEST=12        -- s: one action is not kept longer than this
local OWN_PUSH=6        -- s: a GA_Hun_Double_* the weapon loop pressed counts as the mod's
local LINES=10          -- log lines of kept actions in a load
local COOLDOWN='Cooldown_2_C711E94E40D3CE24089AD884023A69F9'
local LEGACY_COOLDOWN=1e6
local GATE_SECONDS=2
local RENEW_SECONDS=1
local NO_COOLDOWN,NO_MARK=0,-10000 -- what all nine classes ship with
local NEAR=1e-3
local RECOVERY='PhantomGladiator.hun_action_recovery.v1'
local MAX_RECOVERY=2*1024*1024
local RESTORE_LOOKUPS=4
local MISSING_LOOKUPS=3 -- transient objects can disappear on a hot reload

local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function near(a,b)return finite(a) and finite(b) and math.abs(a-b)<NEAR end

local function call(o,m,...)
    if not U.valid(o)then return false end
    local args=table.pack(...)
    local ok,value=pcall(function()return o[m](o,table.unpack(args,1,args.n))end)
    return ok,U.unwrap(value)
end
local function fullName(v)
    local ok,name=call(v,'GetFullName')
    return ok and type(name)=='string' and name or nil
end
local function text(v)
    v=U.unwrap(v)
    if type(v)=='string'then return v end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string'and s or nil
end

function Guard.new(o)
    local self={alive=true,kept=0,granted=0,gated=0}
    local bodies,byController,open,restoring={},{},{},{}
    local shared=o.shared or ModRef
    local retryRestoreAt,restoreLines=0,0
    local hook,retryAt,retryDelay
    local action,lines={},0
    local fname=o.fname or FName
    local wall=o.wall or os.clock
    local find=o.find or StaticFindObject
    local function say(s)(o.log or function()end)('[HunGuard] '..s)end
    local function tag(actor,name)
        local ok,count=call(U.field(actor,'AbilitySystemComponent'),'GetGameplayTagCount',{TagName=fname(name)})
        return ok and type(count)=='number' and count or 0
    end
    -- Only abilities the task would cancel: their own asset tags contain Ability.Action.
    local function isAction(class,ability)
        if action[class]~=nil then return action[class] end
        local list=U.array(U.struct(U.field(ability,'AbilityTags'),'GameplayTags'))
        if not list then return false end
        local yes=false
        for _,t in ipairs(list)do
            local name=text(U.struct(t,'TagName'))
            if name=='Ability.Action' or name and name:sub(1,15)=='Ability.Action.' then yes=true;break end
        end
        action[class]=yes
        return yes
    end
    local function pushed(r,class,now)
        local push=r.wep and r.wep.push
        return push~=nil and push.class==class and now-push.at<OWN_PUSH
    end
    -- The instances of this body's active actions that are not the native AI's own.
    local function running(r,now)
        local list={}
        local items=U.array(U.struct(U.field(U.field(r.actor,'AbilitySystemComponent'),'ActivatableAbilities'),'Items'))
        local key=U.key(r.actor)
        for _,spec in ipairs(items or {})do
            if (U.struct(spec,'ActiveCount') or 0)>0 then
                local ability=U.struct(spec,'Ability')
                local class=U.className(ability)
                if class and (not NATIVE[class] or pushed(r,class,now)) and isAction(class,ability) then
                    for _,field in ipairs({'NonReplicatedInstances','ReplicatedInstances'})do
                        for _,instance in ipairs(U.array(U.struct(spec,field)) or {})do
                            local ok,avatar=call(instance,'GetAvatarActorFromActorInfo')
                            if ok and key and U.key(avatar)==key then list[#list+1]={object=instance,key=U.key(instance),class=class} end
                        end
                    end
                end
            end
        end
        return list
    end
    local function chaining(r,now)
        local w=r.wep
        return w~=nil and w.comboWall~=nil and not w.comboOff and now-w.comboWall<=CHAINING
    end
    local function cooldownOf(instance)
        local value,mark=U.struct(U.field(instance,'Cooldown Data'),COOLDOWN),U.field(instance,'Cooldown Mark Time')
        if finite(value) and finite(mark) then return value,mark end
    end
    local function setDuration(instance,value)
        local data=U.field(instance,'Cooldown Data')
        local wrote=pcall(function()data[COOLDOWN]=value end)
        return wrote and near(cooldownOf(instance),value)
    end
    local function setMark(instance,value)
        if not U.valid(instance) then return false end
        local wrote=pcall(function()instance['Cooldown Mark Time']=value end)
        return wrote and near(U.field(instance,'Cooldown Mark Time'),value)
    end
    local function worldKey()
        if not o.world then return nil end
        local ok,world=pcall(o.world)
        return ok and U.key(world) or nil
    end
    local function ownerOf(actor)
        return {key=U.key(actor),name=fullName(actor),world=worldKey()}
    end
    local function receipt(kind,item,owner)
        item.kind,item.owner,item.name=kind,owner,fullName(item.object)
    end
    local function restoreKey(item)return item.kind..':'..item.key end
    local function wroteMark(item,mark)return near(mark,item.written) or near(mark,item.pendingMark) end
    local function safeField(v)return type(v)=='string' and v~='' and not v:find('%c') end
    -- UE4SS may unload Lua off the game thread. The next load gets plain identities and values, never wrappers.
    local function saveRecovery()
        local rows,seen={},{}
        local function add(item)
            local k=restoreKey(item);local owner=item.owner
            if seen[k] or not (safeField(owner.world) and safeField(owner.key) and safeField(owner.name)
                and safeField(item.key) and safeField(item.name) and item.name:match('^%S+ /')) then return end
            seen[k]=true
            rows[#rows+1]=table.concat({item.kind,owner.world,owner.key,item.key,owner.name,item.name,
                tostring(item.value or 0),tostring(item.mark or 0),tostring(item.written or 0),item.legacy and '1' or '0',
                tostring(item.pendingMark or '-')},'\t')
        end
        for _,item in pairs(restoring)do add(item) end
        for _,entry in ipairs(open)do for _,item in ipairs(entry.list)do add(item) end end
        for _,b in pairs(bodies)do if b.gate then for _,item in ipairs(b.gate.list)do add(item) end end end
        if #rows>0 and shared then
            local data=table.concat(rows,'\n')
            local ok,verified=pcall(function()
                shared:SetSharedVariable(RECOVERY,data)
                return shared:GetSharedVariable(RECOVERY)==data
            end)
            say('跨重载状态登记='..#rows..' 读回='..tostring(ok and verified==true))
        end
    end
    if shared then
        local ok,saved=pcall(function()return shared:GetSharedVariable(RECOVERY)end)
        if ok and type(saved)=='string' and #saved>0 and #saved<=MAX_RECOVERY then
            for row in saved:gmatch('[^\n]+')do
                -- A prior beta saved the same record without a pending mark field.
                local kind,world,owner,key,avatar,name,value,mark,written,legacy,tail=row:match(
                    '^(%a+)\t(%d+)\t(%d+)\t(%d+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([01])(.*)$')
                local pendingMark=tail and tail:match('^\t([^\t]+)$')
                value,mark,written=tonumber(value),tonumber(mark),tonumber(written)
                if (kind=='cancel' or kind=='cooldown') and safeField(avatar) and safeField(name)
                    and name:match('^%S+ /') and finite(value) and finite(mark) and finite(written)
                    and (tail=='' or pendingMark) then
                    pendingMark=tonumber(pendingMark)
                    local item={kind=kind,key=key,name=name,owner={key=owner,name=avatar,world=world},value=value,
                        mark=mark,written=written,pendingMark=finite(pendingMark) and pendingMark or nil,legacy=legacy=='1'}
                    restoring[restoreKey(item)]=item
                end
            end
            pcall(function()shared:SetSharedVariable(RECOVERY,'')end)
        end
    end
    local function restoreValue(item,currentWorld)
        local expected=item.owner
        if expected.world and currentWorld and expected.world~=currentWorld then return true end
        if expected.world and not currentWorld then return false end
        local object=item.object
        if not object then
            local path=item.name:match('^%S+ (/.+)$')
            local ok,found=pcall(find,path)
            if not ok or not U.valid(found) then
                item.misses=(item.misses or 0)+1
                return item.misses>=MISSING_LOOKUPS,'missing'
            end
            item.misses=nil
            object=found
        end
        if U.key(object)~=item.key then return true end
        if item.name then
            local name=fullName(object)
            if not name then return false end
            if name~=item.name then return true end
        end
        local ok,avatar=call(object,'GetAvatarActorFromActorInfo')
        local avatarKey=ok and U.key(avatar)
        if not avatarKey then return false end
        if avatarKey~=expected.key then return true end
        if expected.name then
            local name=fullName(avatar)
            if not name then return false end
            if name~=expected.name then return true end
        end
        item.object=object
        if item.kind=='cancel' then
            local cancellable=U.field(object,'bIsCancelable')
            if cancellable==true then return true end
            if cancellable~=false then return false end
            call(object,'SetCanBeCanceled',true)
            return U.field(object,'bIsCancelable')==true
        end
        local value,mark=cooldownOf(object)
        if not value then return false end
        local ours=near(value,GATE_SECONDS) or item.legacy and near(value,LEGACY_COOLDOWN)
        if ours and not near(value,item.value) and not setDuration(object,item.value) then return false end
        if wroteMark(item,mark) and not near(mark,item.mark) and not setMark(object,item.mark) then return false end
        return true
    end
    local function restore(item,currentWorld)
        local key=restoreKey(item)
        local done,reason=restoreValue(item,currentWorld)
        if done then
            restoring[key]=nil
            if reason=='missing' and restoreLines<LINES then
                restoreLines=restoreLines+1
                say('重载后技能对象未找到，停止恢复查询 '..tostring(item.name))
            end
            return reason
        end
        restoring[key]=item
        item.delay=math.min(8,(item.delay or .25)*2)
        item.retryAt=wall()+item.delay
        if item.delay==.5 and restoreLines<LINES then
            restoreLines=restoreLines+1
            say('动作状态待恢复 '..tostring(item.name)..' 类型='..item.kind)
        end
        return reason
    end
    -- The classes the weapon in hand grants itself (黑伤双刃 and the player's 绝影 carry some of the nine).
    local function granted(r)
        local set={}
        for _,class in ipairs(U.array(U.field(r.wep and r.wep.currentConfig,'Equip Abilities')) or {})do
            local name=fullName(class)
            name=name and name:match('([^%.:/]+)$')
            if name then set[name]=true end
        end
        return set
    end
    local function openGate(b)
        local gate=b.gate
        if not gate then return end
        b.gate=nil
        local world=worldKey()
        for _,item in ipairs(gate.list)do restore(item,world) end
    end
    local function closeGate(r,b)
        local now=o.now and o.now()
        if not finite(now) or now<0 or not o.current(r) then return end
        local own,list=granted(r),{}
        local owner=ownerOf(r.actor)
        local items=U.array(U.struct(U.field(U.field(r.actor,'AbilitySystemComponent'),'ActivatableAbilities'),'Items'))
        for _,spec in ipairs(items or {})do
            local class=U.className(U.struct(spec,'Ability'))
            if class and NATIVE[class] and not own[class] then
                for _,field in ipairs({'NonReplicatedInstances','ReplicatedInstances'})do
                    for _,instance in ipairs(U.array(U.struct(spec,field)) or {})do
                        local ok,avatar=call(instance,'GetAvatarActorFromActorInfo')
                        local value,mark=cooldownOf(instance)
                        local key=U.key(instance)
                        if ok and owner.key and U.key(avatar)==owner.key and value and key and not restoring['cooldown:'..key] then
                            local legacy=near(value,LEGACY_COOLDOWN)
                            if legacy then value,mark=NO_COOLDOWN,NO_MARK end
                            local item={object=instance,key=key,value=value,mark=mark,written=now,legacy=legacy}
                            receipt('cooldown',item,owner)
                            if setMark(instance,now) and setDuration(instance,GATE_SECONDS) then
                                item.legacy=nil
                                list[#list+1]=item
                            else restore(item,owner.world) end
                        end
                    end
                end
            end
        end
        if #list==0 then return end
        b.gate={list=list,renewAt=now+RENEW_SECONDS}
        self.gated=self.gated+1
        if not self.gateLogged then
            self.gateLogged=true
            say('出招期间原版连招暂不可用 实例='..tostring(r.name)..' 技能数='..#list..'（本次加载第一次）')
        end
    end
    local function renewGate(b)
        local gate=b.gate
        if not gate then return end
        local now=o.now and o.now()
        if not finite(now) or now<gate.renewAt then return end
        gate.renewAt=now+RENEW_SECONDS
        for _,item in ipairs(gate.list)do
            if U.key(item.object)==item.key then
                local value,mark=cooldownOf(item.object)
                if near(value,GATE_SECONDS) and wroteMark(item,mark) then
                    -- The setter can take effect even when its immediate readback is unavailable.
                    item.written=mark
                    item.pendingMark=now
                    if setMark(item.object,now) then item.written=now;item.pendingMark=nil end
                end
            end
        end
    end
    local function hold(r,b,held)
        if r.dead or not o.current(r) then return end
        local busy,window=Vitals.actionState(r.actor,fname)
        if not busy then b.since,b.refused=nil,nil;return end
        local now=wall()
        if window and (Vitals.phase(r.actor,fname)~=COMBO or not chaining(r,now)) then return end
        for _,name in ipairs(EXECUTING)do if tag(r.actor,name)>0 then return end end
        b.since=b.since or now
        local push=r.wep and r.wep.push
        if now-math.max(b.since,push and push.at or b.since)>LONGEST then return end
        local list=running(r,now)
        local last
        local owner
        for _,item in ipairs(list)do
            if item.key and not restoring['cancel:'..item.key] and U.field(item.object,'bIsCancelable')==true then
                owner=owner or ownerOf(r.actor)
                receipt('cancel',item,owner)
                call(item.object,'SetCanBeCanceled',false)
                local result=U.field(item.object,'bIsCancelable')
                if result~=true then held[#held+1]=item end
                if result==false then last=item end
            end
        end
        if not last then return end
        b.refused=last
        b.kept=(b.kept or 0)+1;self.kept=self.kept+1
        if lines<LINES then
            lines=lines+1
            say('立回移动不打断出招 实例='..tostring(r.name)..' 招='..last.class..' 阶段='..tostring(Vitals.phase(r.actor,fname))..' 本只第'..b.kept..'次')
        end
    end
    local function release(entry)
        if #entry.list==0 then return end
        local world=worldKey()
        for _,item in ipairs(entry.list)do restore(item,world) end
    end
    local function gameThread()
        local thread=o.inGameThread or IsInGameThread
        if type(thread)~='function' then return true end
        local ok,yes=pcall(thread)
        return ok and yes==true
    end
    -- The followed controller among the arguments; false: another object's call; nil: none can be read. Not by place:
    -- a post-hook may get a return value before the arguments.
    local function controllerOf(...)
        local other
        for i=1,select('#',...)do
            local key=U.key(U.unwrap((select(i,...))))
            if key and byController[key] then return key end
            if key then other=false end
        end
        return other
    end
    local function before(context,...)
        if not self.alive or next(byController)==nil then return end
        local key=controllerOf(...)
        local r=key and byController[key]
        local b=r and bodies[r]
        if not b or not gameThread() then return end
        local task=U.unwrap(context)
        if not CANCEL[U.className(task)] then return end
        local entry={controller=key,task=U.key(task),record=r,list={}}
        open[#open+1]=entry
        hold(r,b,entry.list)
    end
    local function after(context,...)
        local top=open[#open]
        if not top or not gameThread() or U.key(U.unwrap(context))~=top.task then return end
        local key=controllerOf(...)
        if key==false or key and key~=top.controller then return end
        open[#open]=nil
        release(top)
    end
    local function install()
        if hook or not next(bodies) then return end
        local register=o.register or RegisterHook
        local now=wall()
        if type(register)~='function' or (retryAt and now<retryAt and retryAt-now<=60) then return end
        local ok,pre,post=pcall(register,Guard.HOOK,
            function(...)pcall(before,...)end,function(...)pcall(after,...)end)
        if ok and type(pre)=='number' and type(post)=='number' then
            hook={pre,post};retryAt,retryDelay=nil,nil
            say('挂钩注册读回 ExecuteTask_Internal pre='..pre..' post='..post)
        else
            retryDelay=math.min(60,(retryDelay or 1.5)*2);retryAt=now+retryDelay
            say('挂钩未确认 ExecuteTask_Internal：'..tostring(pre)..'；'..retryDelay..' 秒后再试')
        end
    end
    local function uninstall()
        if not hook then return end
        local ok,result=pcall(o.unregister or UnregisterHook,Guard.HOOK,hook[1],hook[2])
        if ok and result~=false then hook=nil end
    end
    function self:tick()
        if not self.alive or not next(restoring) or not gameThread() then return end
        local now=wall()
        if now<retryRestoreAt then return end
        retryRestoreAt=now+.25
        local world=worldKey()
        local lookups=0
        local missing=false
        for _,item in pairs(restoring)do
            if not item.retryAt or now>=item.retryAt then
                if item.object then restore(item,world)
                elseif lookups<RESTORE_LOOKUPS and not missing then
                    lookups=lookups+1
                    -- A missing UObject lookup can be slow. Leave the rest for a later tick.
                    missing=restore(item,world)=='missing'
                end
            end
        end
    end
    -- Every support cycle for a living body whose kit runs. A post-hook that never came is made up for here.
    function self:follow(r)
        if not self.alive then return end
        while #open>0 do release(table.remove(open)) end
        local b=bodies[r]
        if not b then b={};bodies[r]=b end
        local key=U.key(U.field(r.actor,'Controller'))
        if key~=b.controller then
            if b.controller and byController[b.controller]==r then byController[b.controller]=nil end
            b.controller=key
        end
        if key then byController[key]=r end
        install()
        if b.gate then self:observe(r) end
    end
    -- The mod has just started a move on this body.
    function self:pressed(r)
        local b=bodies[r]
        if not self.alive or not b then return end
        local now=wall()
        b.pressedAt,b.since,b.refused=now,now,nil
        if not b.gate then closeGate(r,b) else renewGate(b) end
    end
    -- The move of the mod is over: nothing runs, its recovery is free, or it has run for too long.
    function self:observe(r,busy,window)
        local b=bodies[r]
        if not b then return end
        if r.dead or not o.current(r) then openGate(b);return end
        if busy==nil then busy,window=Vitals.actionState(r.actor,fname) end
        local age=wall()-(b.pressedAt or 0)
        -- A press reads as busy only once its montage runs: the first moment is not its end.
        if age>=0 and age<.15 then return end
        if not busy then b.since,b.refused=nil,nil end
        if not busy or window and Vitals.phase(r.actor,fname)==FINISH or age>LONGEST or age<0 then
            openGate(b)
        elseif b.gate then renewGate(b) end
    end
    function self:stop(r)
        local b=bodies[r]
        if not b then return end
        for i=#open,1,-1 do
            if open[i].record==r then release(table.remove(open,i)) end
        end
        openGate(b)
        bodies[r]=nil
        if b.controller and byController[b.controller]==r then byController[b.controller]=nil end
        if (b.kept or 0)>0 then
            say('出招保护统计 实例='..tostring(r.name)..' 保留='..b.kept..' 收招后放行移动='..(b.granted or 0))
        end
        if not next(bodies) then uninstall() end
    end
    -- The weapon loop, once per pass: it pressed something new, or it found nothing to press.
    function self:settle(r,chained)
        local b=bodies[r]
        if not chained then self:observe(r) end
        local wanted=b and b.refused
        if not wanted then return end
        if chained then b.refused=nil;return end
        if not o.current(r) then b.refused=nil;return end
        local busy,window=Vitals.actionState(r.actor,fname)
        if not busy then b.refused,b.since=nil,nil;return end
        if not window or Vitals.phase(r.actor,fname)~=FINISH then return end
        b.refused=nil
        local ok,avatar=call(wanted.object,'GetAvatarActorFromActorInfo')
        if not ok or U.key(wanted.object)~=wanted.key or U.key(avatar)~=U.key(r.actor) then return end
        local read,active=call(find(Guard.UTILS),'IsAbilityActive',wanted.object)
        if not read or active~=true then return end
        if call(wanted.object,'Move Cancel Ability') then b.granted=(b.granted or 0)+1;self.granted=self.granted+1 end
    end
    function self:status()return {kept=self.kept,granted=self.granted,gated=self.gated,hooked=hook~=nil}end
    function self:silence(onGameThread)
        self.alive=false
        -- Off the game thread nothing native may be touched; an action's own end resets its cancellability.
        if onGameThread==true then
            while #open>0 do release(table.remove(open)) end
            for r,b in pairs(bodies)do openGate(b) end
            uninstall()
        end
        saveRecovery()
        open,bodies,byController,restoring={},{},{},{}
    end
    return self
end
return Guard
