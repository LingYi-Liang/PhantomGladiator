-- Timing decisions for an owned Hun NPC. Frames and activated abilities belong to its own ASC.
local U = require('ue_observe')
local Vitals = require('hun_vitals')
local Defense = {}
local PASSIVES = {'BP_PlayerDeflectPassive', 'BP_PerfectDodgePassive'}
local COST = {
    CostOfTime_6_1918214C431B290CEA5A4A9CAEAA8C4A = 20,
    CostOfTimeStartDelay_10_D32DE2BC437394BD04342497EDBEB139 = 0.3,
    CostOfTimeEndDelay_11_85354FFE4DC3D6FB650ED1A8F9425022 = 0.3,
}
local BASE_DEFENSE = {'GA_Hun_Double_Stance','GA_Hun_Double_HoldDeflect','GA_Hun_Double_PerfectDodge','GA_Hun_AdvancedDash_Double'}
local PURE_DASH = {
    GA_Hun_AdvancedDash_Double_C=true, GA_Hun_AdvancedDash_Tang_C=true,
    GA_Hun_AdvancedDash_Long_C=true, GA_Hun_AdvancedDash_Unarmed_C=true,
}
local DASH_RESULT='/PBZDeflectSystem/Abilities/BP_PlayerDodge_Base.BP_PlayerDodge_Base_C:OnEvadeDamage'
local NPC_WEAPON = '/PBZCombatAsset/ActorData/Mobs/000_Hun/Weapon/Weapon_Hun_JueYing.Weapon_Hun_JueYing'
local BUSY = {'CharacterState.Stand.Break','CharacterState.Dead','Ability.Action.Execution', 'Ability.Executed', 'CharacterState.HitReact.State.Executing',
    'CharacterState.Hitreact.State.Dead', 'Ability.Action.Hun.HeiMoShang.Reborn',
    'CharacterState.Hitreact.Phase.Act','CharacterState.Hitreact.State.Frozen','CharacterState.Unselectable.Force.Perform'}

local function call(obj, method, ...)
    if not U.valid(obj) then return false end
    local args = table.pack(...)
    local ok, result = pcall(function() return obj[method](obj, table.unpack(args, 1, args.n)) end)
    return ok, U.unwrap(result)
end

local function iface(value)
    if U.valid(value) then return value end
    local obj = U.struct(value, 'ObjectPointer')
    if U.valid(obj) then return obj end
    local ok, interface = pcall(function() return value:GetObject() end)
    if ok and U.valid(interface) then return interface end
end

local function owned(instance, actor)
    local ok, avatar = call(instance, 'GetAvatarActorFromActorInfo')
    return ok and U.key(actor) ~= nil and U.key(avatar) == U.key(actor)
end

local function specOf(asc, class)
    local specs = U.array(U.struct(U.field(asc, 'ActivatableAbilities'), 'Items'))
    if not specs then return nil, false end
    for _, spec in ipairs(specs) do
        if U.className(U.struct(spec, 'Ability')) == class then return spec, true end
    end
    return nil, true
end

local function tagName(value)
    local name = U.struct(value, 'TagName')
    if type(name) == 'string' then return name end
    local ok, text = pcall(function() return name:ToString() end)
    return ok and text or ''
end

local function weak(value)
    if U.valid(value) then return value end
    local ok, object = pcall(function() return value:Get() end)
    return ok and U.valid(object) and object or nil
end

-- The three lead times follow the light/normal/knockback pre-hit measurements.
function Defense.window(frame)
    local kind, strength = frame.kind, frame.strength or ''
    if frame.dodge or kind == 0 or kind == 3 then return 'dodge', 0.10 end
    if strength:find('Light', 1, true) then return 'deflect', 0.06 end
    if strength:find('Knock', 1, true) then return 'deflect', 0.13 end
    return 'deflect', 0.09
end

function Defense.new(o)
    local self, records, assets = {}, {}, {}
    local log = o.log or function() end
    local find, load = o.find or StaticFindObject, o.load or LoadAsset
    local findAll = o.findAll or FindAllOf
    local loop, cancel = o.loop or LoopInGameThreadWithDelay, o.cancel or CancelDelayedAction
    local clock = o.now or o.clock
    local fname = o.fname or FName
    local resultHook,lastWorldTime,pausedAt
    local observing,alive={},true
    local function say(r, message) log('[HunDefense] '..tostring(r.name)..' '..message) end
    local timer=require('hun_combat_timer').new(20,loop,cancel,clock,log)
    local function asset(path)
        if U.valid(assets[path]) then return assets[path] end
        local ok, obj = pcall(find, path)
        if not ok or not U.valid(obj) then ok, obj = pcall(load, path) end
        if ok and U.valid(obj) then assets[path] = obj; return obj end
    end
    local function releaseObserver()
        if resultHook and not next(observing) then
            local ok,ret=pcall(o.unregister or UnregisterHook,DASH_RESULT,resultHook[1],resultHook[2])
            if ok and ret~=false then resultHook=nil end
        end
    end
    local function observeResult()
        if resultHook then return end
        local register=o.register or RegisterHook
        if type(register)~='function' then return end
        local ticket={}
        local function result(context,source,_,perfect)
            if not alive or resultHook~=ticket then return end
            local thread=o.inGameThread or IsInGameThread
            if type(thread)=='function' then local ok,yes=pcall(thread);if not ok or yes~=true then return end end
            local instance=U.unwrap(context)
            local _,actor=call(instance,'GetAvatarActorFromActorInfo')
            local key=U.key(actor)
            local pending=key and observing[key]
            if not pending or not o.current(pending.record) or U.className(instance)~=pending.class then return end
            local now=clock()
            if type(now)~='number' or now>pending.expires or (pending.source and U.key(U.unwrap(source))~=pending.source) then return end
            local outcome=U.unwrap(perfect)
            if type(outcome)~='boolean' then return end
            pending.perfect=outcome
            observing[key]=nil
            say(pending.record,'无反击闪避原生命中回执 handle='..pending.handle..' Perfect='..tostring(outcome))
        end
        local ok,a,b=pcall(register,DASH_RESULT,function(...) pcall(result,...) end)
        if ok and type(a)=='number' and type(b)=='number' then ticket[1],ticket[2]=a,b;resultHook=ticket end
    end
    local function tag(asc, name)
        local ok, count = call(asc, 'GetGameplayTagCount', {TagName=fname(name)})
        return ok and type(count) == 'number' and count or nil
    end
    local function allowed(chance)
        return chance == nil or chance >= 1 or (chance > 0 and (o.random or math.random)() < chance)
    end
    local function hasHandle(asc,class,handle)
        local specs=U.array(U.struct(U.field(asc,'ActivatableAbilities'),'Items'))
        if not specs then return nil end
        for _,spec in ipairs(specs) do
            if U.struct(U.struct(spec,'Handle'),'Handle')==handle then
                return U.className(U.struct(spec,'Ability'))==class
            end
        end
        return false
    end
    local function clearGrant(r, state, class)
        local grant=state.grants[class]
        if not grant then return true end
        if not o.current(r) then return false end
        local asc = U.field(r.actor, 'AbilitySystemComponent')
        if not U.valid(asc) then return false end
        if U.key(asc)~=U.key(grant.asc) then state.grants[class]=nil;return true end
        local present=hasHandle(asc,class,grant.id)
        if present==nil then return false end
        if not present and grant.awaitUntil then
            local t=clock()
            if type(t)~='number' or t<grant.awaitUntil then return false end
        end
        if present then
            say(r, '即将 清理自授被动 '..class)
            call(asc, 'ClearAbility', {Handle=grant.id})
            local left=hasHandle(asc,class,grant.id)
            say(r, '清理读回 '..class..' 消失='..tostring(left==false))
            if left~=false then return false end
        end
        state.grants[class] = nil
        return true
    end
    local function checkBaseWeapon(r,s,now)
        if s.checkWeaponAt and now<s.checkWeaponAt then return end
        s.checkWeaponAt=now+0.5
        local wc=U.field(r.actor,'Character Weapons Component')
        local slot={TagName=fname('Weapon.Slot.Main')}
        local _,index=call(wc,'GetCurrentWeaponIndex',slot,false)
        if type(index)~='number' or index<0 then return end
        local data={}
        if not call(wc,'GetSlotWeapon',slot,index,data) then return end
        local got,path=call(iface(data.WeaponConfig),'GetFullName')
        if not got or type(path)~='string' or not o.current(r) then return end
        local asc=U.field(r.actor,'AbilitySystemComponent')
        local ascKey=U.key(asc)
        if not ascKey then return end
        if path~=s.checkingWeapon or ascKey~=s.weaponAsc then
            s.checkingWeapon,s.weaponAsc=path,ascKey
            s.weaponPath=nil;s.baseRequests={};s.baseRetryAt=nil;s.retryDelay=.5
        end
        if path==s.weaponPath or now<(s.baseRetryAt or 0) then return end
        local original=path:match('^%S+ (.+)$')==NPC_WEAPON
        local complete=true
        for _,base in ipairs(BASE_DEFENSE) do
            local class=base..'_C'
            if original then
                local existing,read=specOf(asc,class)
                if not read then complete=false
                elseif not existing then
                    local cls=not s.baseRequests[class] and asset('/PBZCombatAsset/ActorData/Players/Hun/Abilities/DoubleBalde/'..base..'.'..class)
                    if cls then
                        say(r,'即将 为原生绝影补 '..base)
                        local ok,handle=call(asc,'K2_GiveAbility',cls,1,-1)
                        local spec=specOf(asc,class)
                        local id=U.struct(U.struct(spec,'Handle'),'Handle')
                        local returned=U.struct(handle,'Handle')
                        if ok and handle~=false and (returned==nil or (type(returned)=='number' and returned>0)) then
                            s.baseRequests[class]=true
                            local ownedId=returned or id
                            if type(ownedId)=='number' and ownedId>0 then
                                s.grants[class]={id=ownedId,asc=asc,awaitUntil=ownedId~=id and now+1 or nil}
                            end
                        end
                        say(r,'绝影技能读回 '..base..' handle='..tostring(id))
                        existing=spec
                    end
                    if not existing then complete=false end
                end
            elseif not clearGrant(r,s,class) then complete=false end
        end
        if complete then s.weaponPath=path
        else s.baseRetryAt=now+s.retryDelay;s.retryDelay=math.min(4,s.retryDelay*2) end
    end
    local function passive(r, state, class)
        local asc = U.field(r.actor, 'AbilitySystemComponent')
        local spec, read = specOf(asc, class)
        if not read or not o.current(r) then return end
        if not spec then
            local base = class:sub(1,-3)
            local cls = asset('/PBZDeflectSystem/Abilities/'..base..'.'..class)
            if not cls then return end
            say(r, '即将 授予并激活 '..class)
            local ok, handle = call(asc, 'K2_GiveAbilityAndActivateOnce', cls, 1, -1)
            spec = specOf(asc, class)
            local id = U.struct(U.struct(spec, 'Handle'), 'Handle')
            local returned = U.struct(handle, 'Handle')
            if ok and type(id) == 'number' and id > 0 and (returned == nil or returned == id) then
                state.grants[class] = {id=id,asc=asc}
            end
            say(r, '授予读回 '..class..' handle='..tostring(id)..' active='..tostring(U.struct(spec, 'ActiveCount')))
        end
        if not spec or (U.struct(spec,'ActiveCount') or 0) <= 0 then return end
        for _, key in ipairs({'NonReplicatedInstances','ReplicatedInstances'}) do
            for _, instance in ipairs(U.array(U.struct(spec, key)) or {}) do
                if owned(instance, r.actor) then return instance end
            end
        end
        local ok, instances = pcall(findAll, class)
        for _, instance in ipairs(ok and type(instances)=='table' and instances or {}) do
            if owned(instance, r.actor) then return instance end
        end
    end
    local function setCosts(r, s)
        local instance = s.block
        local cost = U.field(instance, 'Anger Cost Data')
        local original = {}
        for k in pairs(COST) do
            original[k] = U.struct(cost, k)
            if type(original[k]) ~= 'number' then return false end
        end
        s.cost = original
        local spend=not (r.loadout and r.loadout.resources and r.loadout.resources.consume_skill_resources==false)
        local values={}
        for k,value in pairs(COST) do values[k]=value end
        if not spend then values.CostOfTime_6_1918214C431B290CEA5A4A9CAEAA8C4A=0 end
        say(r,'即将 设置独立格挡被动主动耗气='..tostring(spend))
        local ok = pcall(function() for k,value in pairs(values) do cost[k]=value end end)
        local read = U.field(instance, 'Anger Cost Data')
        for k,value in pairs(values) do ok = ok and math.abs((U.struct(read,k) or -999) - value) < 0.001 end
        say(r, '格挡消耗读回一致='..tostring(ok))
        return ok
    end
    local function restoreCosts(r,s)
        if not s.cost or not o.current(r) or not owned(s.block,r.actor) then return end
        local cost=U.field(s.block,'Anger Cost Data')
        local ok=pcall(function() for k,v in pairs(s.cost) do cost[k]=v end end)
        cost=U.field(s.block,'Anger Cost Data')
        for k,v in pairs(s.cost) do ok=ok and U.struct(cost,k)==v end
        say(r,'恢复格挡消耗读回一致='..tostring(ok))
        s.cost=nil
    end
    local function release(r,s)
        if not s.releaseAt then return end
        if r.intent and r.intent.busyUntil==s.releaseAt then r.intent.busyUntil=0 end
        if s.guardSample and o.current(r) then
            say(r,'持防结束 杀气='..tostring(o.stat(r.actor,'Shachi'))..' 起始='..tostring(s.guardSample.start))
        end
        s.guardSample,s.guardCheck=nil,nil
        s.releaseAt,s.holdStarted=nil,nil
        if o.current(r) and owned(s.block,r.actor) then
            say(r, '即将 松开格挡')
            call(s.block, 'On Stance Key Release')
            if U.field(s.block, 'Stance Key Down') == true then
                pcall(function() s.block['Stance Key Down'] = false end)
            end
            say(r, '松开格挡 键读回='..tostring(U.field(s.block, 'Stance Key Down')))
        end
    end
    local function activeInstance(actor,suffix)
        local specs=U.array(U.struct(U.field(U.field(actor,'AbilitySystemComponent'),'ActivatableAbilities'),'Items'))
        for _,spec in ipairs(specs or {}) do
            local name=(U.struct(spec,'ActiveCount') or 0)>0 and U.className(U.struct(spec,'Ability'))
            if name and name:sub(-#suffix)==suffix then
                for _,key in ipairs({'NonReplicatedInstances','ReplicatedInstances'}) do
                    for _,instance in ipairs(U.array(U.struct(spec,key)) or {}) do
                        if owned(instance,actor) then return instance end
                    end
                end
            end
        end
    end
    local function note(r,s, kind, hitTime, now, asc)
        s.pending = {kind=kind, hit=hitTime, expires=hitTime+0.35}
        r.intent = r.intent or {}
        r.intent.busyUntil = math.max(r.intent.busyUntil or 0, now + 0.18)
        if o.guard then o.guard:pressed(r) end
        if kind=='dashOnly' then
            say(r,'无反击闪避启动读回 动作计数='..tostring(tag(asc,'Ability.Action.Hun.Dash')))
        elseif kind=='deflect' then
            say(r, '格挡窗口读回='..tostring(U.field(s.block, 'Perfect Window'))..
                ' 动作计数='..tostring(tag(asc, 'Ability.Action.Stance')))
        else say(r, '闪避启动读回 类型='..kind..' 动作计数='..tostring(tag(asc, 'Ability.Action.Hun.PerfectDodge'))) end
    end
    -- BP_PlayerDodge_Base grants GE_PerfectDash on activation and receives
    -- GameplayEvent.Actor.HitDodge.Target.Perfect. These four primary weapon dash
    -- classes inherit that logic; none plays the PerfectDodge weapon counter.
    local function dodgeOnly(r,s,asc,input,action,frame,now)
        local ready,eligible=call(input,'CanActivateExternalActionAbility',-5)
        if not ready or eligible~=true then return false end
        local specs=U.array(U.struct(U.field(asc,'ActivatableAbilities'),'Items'))
        local wanted
        local wc=U.field(r.actor,'Character Weapons Component')
        local slot={TagName=fname('Weapon.Slot.Main')}
        local _,index=call(wc,'GetCurrentWeaponIndex',slot,false)
        local out={}
        if type(index)=='number' and call(wc,'GetSlotWeapon',slot,index,out) then
            local config=iface(out.WeaponConfig)
            local _,full=call(config,'GetFullName')
            if full and full:match('^%S+ (.+)$')==NPC_WEAPON then wanted='GA_Hun_AdvancedDash_Double_C'
            else
                for _,abilityClass in ipairs(U.array(U.field(config,'Equip Abilities')) or {}) do
                    local _,name=call(abilityClass,'GetFullName')
                    local class=name and name:match('%.([^%.:]+)$')
                    if PURE_DASH[class] then wanted=class;break end
                end
            end
        end
        local candidate,unique
        for _,spec in ipairs(specs or {}) do
            local class=U.className(U.struct(spec,'Ability'))
            if PURE_DASH[class] then
                if class==wanted then candidate=spec;break end
                if unique==nil then unique=spec else unique=false end
            end
        end
        candidate=candidate or (not wanted and unique)
        local handle=U.struct(U.struct(candidate,'Handle'),'Handle')
        if type(handle)~='number' or handle<=0 then return false end
        local cdo=U.struct(candidate,'Ability')
        local class=U.className(cdo)
        local got,abilityClass=call(cdo,'GetClass')
        if not got or not U.valid(abilityClass) then return false end
        local watch={record=r,class=class,handle=frame.handle,source=frame.source,expires=frame.hit+0.35}
        local key=U.key(r.actor)
        observing[key]=watch
        observeResult()
        say(r,'即将 尝试原生无反击完美闪避 '..class..' handle='..frame.handle)
        local ok,activated=call(input,'TryActivateExternalActionAbilityByClass',abilityClass,action,-5)
        if not ok or activated~=true then observing[key]=nil;return false end
        note(r,s,'dashOnly',frame.hit,now,asc)
        s.pending=nil
        s.dashWatch=watch
        return true
    end
    local function attempt(r,s, frame, kind, now)
        local asc = U.field(r.actor, 'AbilitySystemComponent')
        for _, busy in ipairs(BUSY) do if tag(asc,busy) ~= 0 then return end end
        local holding=s.releaseAt and U.field(s.block,'Stance Key Down')==true
        if not holding then
            local performing,canCancel=Vitals.actionState(r.actor,fname)
            local committed=r.supplyBusy or r.shadowState and r.shadowState.running or r.wep and (r.wep.pendingSwitch or r.wep.draw)
            if (performing or committed) and not canCancel then return false end
        end
        local ai = (r.loadout or {}).ai or {}
        if kind=='guard' or kind=='deflect' then
            if not s.canBlock or not owned(s.block,r.actor) then return end
            r.intent=r.intent or {}
            local untilAt=frame.hit+.55
            if U.field(s.block,'Stance Key Down')==true then
                if s.guardCheck then return end
                if s.releaseAt and kind=='deflect' then
                    if call(s.block,'Give Perfect Window') and call(s.block,'Activate Stance Ability',{}) then
                        note(r,s,'deflect',frame.hit,now,asc)
                    end
                    return
                end
                if s.releaseAt and s.holdStarted then
                    s.releaseAt=math.min(s.holdStarted+2,math.max(s.releaseAt,untilAt))
                    r.intent.busyUntil=math.max(r.intent.busyUntil or 0,s.releaseAt)
                end
                return
            end
            local perfect=kind=='deflect'
            -- On Stance Key Down owns the holding tag and native regeneration-inhibition effect.
            -- Native Update Anger handles elapsed time and impacts; never subtract a parallel Lua cost.
            if not call(s.block,'On Stance Key Down') or U.field(s.block,'Stance Key Down')~=true then return end
            s.holdStarted,s.releaseAt=now,perfect and now+.10 or untilAt
            if o.stat and (s.guardSamples or 0)<6 then
                s.guardSamples=(s.guardSamples or 0)+1
                s.guardSample={start=o.stat(r.actor,'Shachi'),at=now+.42}
            end
            if (not perfect or call(s.block,'Give Perfect Window')) and call(s.block,'Activate Stance Ability',{}) then
                if (tag(asc,'Ability.Action.Stance') or 0)>0 then
                    note(r,s,'deflect',frame.hit,now,asc)
                    r.intent.busyUntil=math.max(r.intent.busyUntil or 0,s.releaseAt)
                else
                    s.guardCheck={hit=frame.hit,expires=now+.08}
                    r.intent.busyUntil=math.max(r.intent.busyUntil or 0,s.guardCheck.expires)
                end
                say(r,(perfect and '临击精防' or '普通持防')..' 原生按住至 '..tostring(s.releaseAt))
            else release(r,s) end
        elseif s.canDodge and allowed(ai.red_dodge_chance) then
            release(r,s)
            local input = U.field(r.actor,'Ability Input Component')
            local action = asset('/PBZDeflectSystem/Input/IA_Dodge.IA_Dodge')
            if not U.valid(action) or not U.valid(input) or U.key(U.field(input,'AbilitySystem'))~=U.key(asc) then return end
            if allowed(ai.counter_chance) then
                local ability='Ability.Action.Hun.PerfectDodge'
                -- Its own CanActivate checks either CanDodge OR the nearest valid received frame.
                say(r,'即将 尝试原生闪避反击 handle='..frame.handle)
                local ok,activated=call(input,'TryActivateExternalActionAbilityInterruptLowerByTag',{TagName=fname(ability)},action,-5)
                if ok and activated==true then note(r,s,ability,frame.hit,now,asc);return end
            end
            if not dodgeOnly(r,s,asc,input,action,frame,now) then say(r,'原生无反击闪避未启动') end
        end
    end
    local function update(r,s,now)
        if s.pending or s.releaseAt or s.dashWatch then
            local asc=U.field(r.actor,'AbilitySystemComponent')
            if r.dead or (tag(asc,'CharacterState.Stand.Break') or 0)>0 or (tag(asc,'CharacterState.Dead') or 0)>0 then
                release(r,s);s.pending=nil
                if s.dashWatch and observing[U.key(r.actor) or '']==s.dashWatch then observing[U.key(r.actor)]=nil end
                s.dashWatch=nil;return
            end
        end
        if s.guardCheck then
            local asc=U.field(r.actor,'AbilitySystemComponent')
            if (tag(asc,'Ability.Action.Stance') or 0)>0 then
                note(r,s,'deflect',s.guardCheck.hit,now,asc)
                r.intent.busyUntil=math.max(r.intent.busyUntil or 0,s.releaseAt)
                s.guardCheck=nil
            elseif now>=s.guardCheck.expires then
                release(r,s);return
            end
        end
        if s.releaseAt and now >= s.releaseAt then release(r,s) end
        if r.dead then s.fighting=false;s.nextCombatCheck=now+.25;return end
        if not s.nextCombatCheck or now>=s.nextCombatCheck then
            s.fighting=o.fighting(r)
            s.nextCombatCheck=now+0.25
        end
        if not s.fighting then release(r,s);return end
        if s.guardSample and s.guardSample.at and now>=s.guardSample.at then
            s.guardSample.at=nil
            say(r,'持防中 原生按键='..tostring(U.field(s.block,'Stance Key Down'))..' 杀气='..tostring(o.stat(r.actor,'Shachi'))..' 起始='..tostring(s.guardSample.start))
        end
        checkBaseWeapon(r,s,now)
        local component = U.field(r.actor,'Deflect Component')
        if s.dashWatch then
            if type(s.dashWatch.perfect)=='boolean' then s.dashWatch=nil
            elseif now>=s.dashWatch.expires then
                if observing[U.key(r.actor)]==s.dashWatch then observing[U.key(r.actor)]=nil end
                say(r,'原生无反击闪避未读到本次命中回执')
                s.dashWatch=nil
            end
        end
        if s.pending then
            local p=s.pending
            if now>=p.hit and not p.searched then
                p.searched=true
                p.action=activeInstance(r.actor,p.kind=='deflect' and '_Stance_C' or '_PerfectDodge_C')
            end
            local data
            if p.kind=='deflect' then data=U.field(p.action,'Current Result Data')
            else data=U.field(component,'PerfectDodgeResultData') end
            local resultAt=U.struct(data,'HitGameTime')
            if type(resultAt)=='number' and math.abs(resultAt-p.hit)<0.002 then
                if p.kind=='deflect' then
                    say(r,'本次格挡结果='..tagName(U.struct(data,'DeflectResult'))..' 命中时间='..resultAt)
                else
                    local _,timeline=call(U.field(p.action,'Last Timeline'),'GetFullName')
                    say(r,'本次完美闪避命中时间读回='..resultAt..' 反击资源有效='..tostring(U.valid(U.struct(data,'CounterAbility')))..
                        ' 时间线='..tostring(timeline))
                end
                s.pending=nil
            elseif now>=p.expires then
                say(r,'本次动作未读到匹配的原生命中结果 '..p.kind)
                s.pending=nil
            end
        end
        local map = U.field(component, 'ReceiveFrames')
        if map==nil then return end
        local choice,seen,choiceKind,protected=nil,{},nil,nil
        local ok = pcall(function() map:ForEach(function(key, value)
            local id = tonumber(U.unwrap(key))
            local frame = U.unwrap(value)
            local hit = U.struct(frame, 'HitGameTime')
            if not id or type(hit)~='number' then return end
            seen[id] = true
            if U.struct(frame,'IsHit')==true or hit<now or hit>now+.6 then return end
            local source = weak(U.struct(frame,'SourceAction'))
            local _,attacker=call(source,'GetAvatarActor')
            local sourceKey=U.key(attacker)
            if o.pairProtected then
                protected=protected or {}
                local key=sourceKey or false
                if protected[key]==nil then protected[key]=o.pairProtected(r,attacker)==true end
                if protected[key] then return end
            end
            if r.intent and hit<=now+.35 then r.intent.incomingUntil=math.max(r.intent.incomingUntil or 0,hit+.1) end
            if s.handles[id]==hit then return end
            local data = {source=sourceKey,handle=id,hit=hit,dodge=U.struct(frame,'IsDodge')==true,
                kind=U.field(source,'DeflectBulletType') or U.field(source,'DeflectType'),
                strength=tagName(U.struct(frame,'DeflectStrength'))}
            local kind, lead = Defense.window(data)
            local advance=hit-now
            if kind=='deflect' then
                local plan=s.guardPlans[id]
                if not plan or plan.hit~=hit then
                    plan={hit=hit,perfect=allowed((r.loadout.ai or {}).deflect_chance)}
                    s.guardPlans[id]=plan
                end
                if not plan.perfect then kind,lead='guard',.6 end
            end
            if advance<=lead and (not choice or hit<choice.hit) then choice, choiceKind = data, kind end
        end) end)
        if not ok then return end
        for id in pairs(s.handles) do if not seen[id] then s.handles[id]=nil end end
        for id in pairs(s.guardPlans) do if not seen[id] then s.guardPlans[id]=nil end end
        if choice and (not s.nextAttempt or now>=s.nextAttempt) and o.current(r) then
            s.nextAttempt=now+0.04
            if attempt(r,s,choice,choiceKind,now)~=false then s.handles[choice.handle]=choice.hit end
        end
    end
    function self:stop(r)
        local s = records[r]
        if not s or s.stopping then return end
        s.stopping=true
        release(r,s)
        if s.cost and o.current(r) and owned(s.block,r.actor) then
            restoreCosts(r,s)
        end
        for _, base in ipairs(PASSIVES) do clearGrant(r,s,base..'_C') end
        for _,base in ipairs(BASE_DEFENSE) do clearGrant(r,s,base..'_C') end
        records[r]=nil
        for key,w in pairs(observing) do if w.record==r then observing[key]=nil end end
        if not next(records) then releaseObserver() end
        r.defenseTimerPending=nil
        if not next(records) then timer:stop();lastWorldTime,pausedAt=nil,nil end
    end
    local function tickDefense()
        if not alive then return end
        local now=clock()
        if type(now)~='number' then return end
        if lastWorldTime==now and (pausedAt==now or (o.paused and o.paused())) then
            pausedAt=now
            return
        end
        pausedAt=nil
        lastWorldTime=now
        for body,state in pairs(records) do
            if not state.stopping and (state.releaseAt or (state.fighting and not body.dead) or not state.nextCombatCheck or now>=state.nextCombatCheck) then
                if not U.valid(body.actor) then self:stop(body)
                else
                    local worked,why=pcall(update,body,state,now)
                    if not worked then say(body,'停用防御 '..tostring(why));self:stop(body) end
                end
            end
        end
    end
    function self:retryTimer(r)
        if alive and records[r] then r.defenseTimerPending=not timer:ensure(tickDefense) end
    end
    function self:start(r)
        if not alive or records[r] or not o.current(r) or type(clock)~='function' or type(loop)~='function' then return end
        local s={grants={},handles={},guardPlans={}}
        records[r]=s
        local ai = (r.loadout or {}).ai or {}
        do -- Ordinary guard remains available when perfect parry chance is zero.
            s.block=passive(r,s,PASSIVES[1]..'_C')
            local input=U.field(s.block,'Input System Component')
            local dc=U.field(s.block,'Deflect Component')
            s.canBlock=owned(s.block,r.actor) and U.valid(input) and U.valid(dc)
                and U.key(input)==U.key(U.field(r.actor,'Ability Input Component'))
                and U.key(dc)==U.key(U.field(r.actor,'Deflect Component'))
                and iface(U.field(s.block,'Global Config'))~=nil and setCosts(r,s)
        end
        if ai.red_dodge_chance~=0 then
            if (ai.counter_chance or 1)<1 or (ai.red_dodge_chance or 1)<1 then
                -- ACTNoob's built-in passive can automatically launch a counter on its own.
                -- A configured NPC instead asks its own ASC for each accepted forecast.
                local input=U.field(r.actor,'Ability Input Component')
                local asc=U.field(r.actor,'AbilitySystemComponent')
                s.canDodge=U.valid(asc) and U.key(U.field(input,'AbilitySystem'))==U.key(asc)
                    and U.valid(U.field(r.actor,'Deflect Component'))
            else
                s.dodge=passive(r,s,PASSIVES[2]..'_C')
                s.canDodge=owned(s.dodge,r.actor)
            end
        end
        if not s.canBlock then
            restoreCosts(r,s)
            clearGrant(r,s,PASSIVES[1]..'_C')
        end
        if not s.canDodge then clearGrant(r,s,PASSIVES[2]..'_C') end
        say(r,'防御就绪读回 格挡='..tostring(s.canBlock==true)..' 闪避='..tostring(s.canDodge==true))
        if not s.canBlock and not s.canDodge then self:stop(r);return end
        self:retryTimer(r)
    end
    function self:silence(restore)
        alive=false
        if restore~=false then for r in pairs(records) do self:stop(r) end end
        records,observing,assets={},{},{}
        timer:stop()
        releaseObserver()
    end
    return self
end
return Defense
