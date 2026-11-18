-- Timing decisions for an owned Hun NPC. Frames and activated abilities belong to its own ASC.
local U = require('ue_observe')
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
local BUSY = {'Ability.Action.Execution', 'Ability.Executed', 'CharacterState.HitReact.State.Executing',
    'CharacterState.Hitreact.State.Dead', 'Ability.Action.Hun.HeiMoShang.Reborn'}

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
    local timer, resultHook
    local observing={}
    local function say(r, message) log('[HunDefense] '..tostring(r.name)..' '..message) end
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
        local function result(context,source,_,perfect)
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
        if ok and type(a)=='number' and type(b)=='number' then resultHook={a,b} end
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
        local handle = state.grants[class]
        if not handle or not o.current(r) then return end
        local asc = U.field(r.actor, 'AbilitySystemComponent')
        if hasHandle(asc,class,handle) then
            say(r, '即将 清理自授被动 '..class)
            call(asc, 'ClearAbility', {Handle=handle})
            local left=hasHandle(asc,class,handle)
            say(r, '清理读回 '..class..' 消失='..tostring(left==false))
            if left~=false then return end
        end
        state.grants[class] = nil
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
        local _,path=call(iface(data.WeaponConfig),'GetFullName')
        if type(path)~='string' or path==s.weaponPath or not o.current(r) then return end
        s.weaponPath=path
        local original=path:match('^%S+ (.+)$')==NPC_WEAPON
        local asc=U.field(r.actor,'AbilitySystemComponent')
        for _,base in ipairs(BASE_DEFENSE) do
            local class=base..'_C'
            if original then
                local existing,read=specOf(asc,class)
                if read and not existing then
                    local cls=asset('/PBZCombatAsset/ActorData/Players/Hun/Abilities/DoubleBalde/'..base..'.'..class)
                    if cls then
                        say(r,'即将 为原生绝影补 '..base)
                        local ok,handle=call(asc,'K2_GiveAbility',cls,1,-1)
                        local spec=specOf(asc,class)
                        local id=U.struct(U.struct(spec,'Handle'),'Handle')
                        local returned=U.struct(handle,'Handle')
                        if ok and type(id)=='number' and id>0 and (returned==nil or returned==id) then s.grants[class]=id end
                        say(r,'绝影技能读回 '..base..' handle='..tostring(id))
                    end
                end
            else clearGrant(r,s,class) end
        end
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
                state.grants[class] = id
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
        s.releaseAt = nil
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
            local name=U.className(U.struct(spec,'Ability'))
            if name and name:sub(-#suffix)==suffix and (U.struct(spec,'ActiveCount') or 0)>0 then
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
        local ai = (r.loadout or {}).ai or {}
        if kind == 'deflect' then
            if not s.canBlock or not owned(s.block,r.actor) or U.field(s.block,'Stance Key Down')==true or not allowed(ai.deflect_chance) then return end
            say(r, '即将 格挡 handle='..frame.handle)
            s.releaseAt = now + 0.10
            local ok = pcall(function() s.block['Stance Key Down'] = true end)
            if ok and U.field(s.block, 'Stance Key Down')==true and call(s.block,'Give Perfect Window') and
                call(s.block,'Activate Stance Ability',{}) then note(r,s,kind,frame.hit,now,asc)
            else release(r,s) end
        elseif s.canDodge and allowed(ai.red_dodge_chance) then
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
        if s.releaseAt and now >= s.releaseAt then release(r,s) end
        if r.dead or not U.valid(r.actor) then return end
        if not s.nextCombatCheck or now>=s.nextCombatCheck then
            s.fighting=o.fighting(r)
            s.nextCombatCheck=now+0.25
        end
        if not s.fighting then return end
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
        local choice, seen, choiceKind = nil, {}, nil
        local ok = pcall(function() map:ForEach(function(key, value)
            local id = tonumber(U.unwrap(key))
            local frame = U.unwrap(value)
            local hit = U.struct(frame, 'HitGameTime')
            if not id or type(hit)~='number' then return end
            seen[id] = true
            if s.handles[id]==hit or U.struct(frame,'IsHit')==true or hit<now or hit>now+0.13 then return end
            local source = weak(U.struct(frame,'SourceAction'))
            local _,attacker=call(source,'GetAvatarActor')
            local data = {source=U.key(attacker),handle=id,hit=hit,dodge=U.struct(frame,'IsDodge')==true,
                kind=U.field(source,'DeflectBulletType') or U.field(source,'DeflectType'),
                strength=tagName(U.struct(frame,'DeflectStrength'))}
            local kind, lead = Defense.window(data)
            if hit-now<=lead and (not choice or hit<choice.hit) then choice, choiceKind = data, kind end
        end) end)
        if not ok then return end
        for id in pairs(s.handles) do if not seen[id] then s.handles[id]=nil end end
        if choice and not s.releaseAt and (not s.nextAttempt or now>=s.nextAttempt) and o.current(r) then
            s.handles[choice.handle]=choice.hit
            s.nextAttempt=now+0.04
            attempt(r,s,choice,choiceKind,now)
        end
    end
    function self:stop(r)
        local s = records[r]
        if not s then return end
        release(r,s)
        if s.cost and o.current(r) and owned(s.block,r.actor) then
            restoreCosts(r,s)
        end
        for _, base in ipairs(PASSIVES) do clearGrant(r,s,base..'_C') end
        for _,base in ipairs(BASE_DEFENSE) do clearGrant(r,s,base..'_C') end
        records[r]=nil
        for key,w in pairs(observing) do if w.record==r then observing[key]=nil end end
        if not next(records) then releaseObserver() end
        if not next(records) and timer then pcall(cancel,timer);timer=nil end
    end
    function self:start(r)
        if records[r] or not o.current(r) or type(clock)~='function' or type(loop)~='function' then return end
        local s={grants={},handles={}}
        records[r]=s
        local ai = (r.loadout or {}).ai or {}
        if ai.deflect_chance~=0 then
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
        if timer then return end
        local ok,handle=pcall(loop,20,function()
            local now=clock()
            if type(now)~='number' then return end
            for body,state in pairs(records) do
                if not U.valid(body.actor) then self:stop(body)
                else
                    local worked,why=pcall(update,body,state,now)
                    if not worked then say(body,'停用防御 '..tostring(why));self:stop(body) end
                end
            end
        end)
        if ok and handle then timer=handle else self:stop(r) end
    end
    function self:silence()
        for r in pairs(records) do self:stop(r) end
    end
    return self
end
return Defense
