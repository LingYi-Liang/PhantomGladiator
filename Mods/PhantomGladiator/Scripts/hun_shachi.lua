-- Shadow armaments on an owned Hun NPC. Shared configs are only read; the instance's two
-- ShaChi slots hold transient copies. Activation uses a spec granted on this actor's ASC.
local U = require('ue_observe')
local Vitals = require('hun_vitals')
local Data = require('hun_shachi_data')
local Charge = require('hun_shadow_charge')
local Shachi = {}
local SLOT = 'Weapon.Slot.ShaChi'
local MAP = 'Weapon Attack Multipliers'
local NORMALIZED = MAP .. ' Normalized'
local ACTIVE_TAG = 'Ability.Action.Hun.ShachiAbility'
local STACK_UTIL = '/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
local serial = 0
local catalog = {}
for _, item in ipairs(Data.items) do catalog[item.id] = item end
local variants={}
for _,item in ipairs(Data.variants) do variants[item.id]=item end

local function call(object, method, ...)
    if not U.valid(object) then return false end
    local args, count = {...}, select('#', ...)
    local ok, value = pcall(function() return object[method](object, table.unpack(args, 1, count)) end)
    return ok, U.unwrap(value)
end

local function tagName(tag)
    local name = U.struct(tag, 'TagName')
    if type(name) == 'string' then return name end
    local ok, text = pcall(function() return name:ToString() end)
    return ok and text or nil
end

local function near(a, b)
    return type(a)=='number' and type(b)=='number' and math.abs(a-b)<=0.0001*math.max(1,math.abs(b))
end

local function damageMap(object, field)
    local map = U.field(object,field)
    local values = {}
    local ok = pcall(function()
        map:ForEach(function(key,value)
            local name = tagName(U.unwrap(key))
            local number = U.unwrap(value)
            assert(type(name)=='string' and type(number)=='number')
            values[name] = number
        end)
    end)
    return ok and values or nil
end

local function matches(values, expected, scale)
    if not values or not expected then return false end
    for key, value in pairs(values) do
        if not expected[key] or not near(value, expected[key]*scale) then return false end
    end
    for key in pairs(expected) do if values[key]==nil then return false end end
    return true
end

local function objectPath(object)
    local ok, name = call(object, 'GetFullName')
    return ok and type(name)=='string' and name:match('^%S+ (/.+)$') or nil
end

local function granted(asc)
    local specs = U.array(U.struct(U.field(asc,'ActivatableAbilities'),'Items'))
    local ascKey=U.key(asc)
    if not ascKey or not specs or #specs>1024 then return {} end
    local out = {}
    for index,spec in ipairs(specs) do
        local path = objectPath(U.struct(spec,'Ability'))
        if path then
            local id=U.struct(U.struct(spec,'Handle'),'Handle')
            if type(id)=='number' and id>0 then
                out[path:gsub('%.Default__','.')]={id=id, active=U.struct(spec,'ActiveCount'), spec=spec,index=index,ascKey=ascKey,abilityKey=U.key(U.struct(spec,'Ability'))}
            end
        end
    end
    return out
end

local function ownedComponent(actor, field)
    local component=U.field(actor,field)
    local ok,owner=call(component,'GetOwner')
    if ok and U.key(owner) and U.key(owner)==U.key(actor) then return component end
end

-- GAS can move or regrant specs. Cache an array position, never a pointer into that array.
local function activeSpec(asc,cast)
    if cast.ascKey then
        local key=U.key(asc)
        if not key then return nil,false end
        if key~=cast.ascKey then return nil,true end
    end
    local items=U.struct(U.field(asc,'ActivatableAbilities'),'Items')
    local function match(row)
        if U.struct(U.struct(row,'Handle'),'Handle')==cast.handle and U.key(U.struct(row,'Ability'))==cast.abilityKey then
            return {id=cast.handle,active=U.struct(row,'ActiveCount'),spec=row}
        end
    end
    local ok,row=pcall(function()
        if cast.index and cast.index<=#items then return U.unwrap(items[cast.index]) end
    end)
    local found=ok and match(row)
    if found then return found,true end
    local list=U.array(items)
    if not list or #list>1024 then return nil,false end
    for i,spec in ipairs(list) do
        found=match(spec)
        if found then cast.index=i;return found,true end
    end
    return nil,true
end

local function slotConfig(wc, tag, index)
    local result={}
    local ok = call(wc,'GetSlotWeapon',tag,index,result)
    if not ok then return nil,false end
    local value=U.unwrap(result.WeaponConfig)
    if U.valid(value) then return value,true end
    local inner=U.struct(value,'ObjectPointer')
    if U.valid(inner) then return inner,true end
    if value~=nil then
        local got, object = pcall(function() return value:GetObject() end)
        if got then return U.valid(object) and object or nil,true end
        -- An opaque non-null interface cannot be treated as a confirmed empty slot.
        local probed,live=pcall(function()return value:IsValid()end)
        return nil,probed and live==false
    end
    return nil,true
end

local function display(object)
    local rows=U.array(U.field(object,'Display Data'))
    if not rows or #rows==0 then return end
    local values,signature={},{}
    for _,row in ipairs(rows) do
        local entry={}
        local cls=U.struct(row,'WeaponClass')
        if not U.key(cls) then return end
        entry.WeaponClass=cls
        signature[#signature+1]=U.key(cls)
        for _,field in ipairs({'UnarmedSocket','ArmedSocket','ScabbardSocket'}) do
            local socket=U.struct(row,field)
            local read,value=pcall(function()return type(socket)=='string' and socket or socket:ToString() end)
            if not read or type(value)~='string' then return end
            entry[field]=socket;signature[#signature+1]=value
        end
        local sheath=U.struct(row,'ScabbardMesh')
        if U.valid(sheath) then entry.ScabbardMesh=sheath end
        signature[#signature+1]=U.key(sheath) or '-'
        values[#values+1]=entry
    end
    return values,table.concat(signature,'|')
end

local function optionsFor(loadout)
    local rows={}
    local function add(row,choice)
        local activePath=(choice.soul and row.soul~='') and row.soul or row.normal
        local level=row.donor and 1 or (choice.level=='max' and 60 or tonumber(choice.level))
        if (choice.path and choice.path~=activePath) or not level or level<1 or level>60 then return end
        local weight=tonumber(choice.weight) or 1
        if weight>0 then
            rows[#rows+1]={id=row.id,meta=row,level=level,soul=choice.soul==true,path=activePath,weight=weight}
        end
    end
    if loadout and loadout.shadows then
        for _,choice in ipairs(loadout.shadows) do
            local row=catalog[choice.id]
            if row then add(row,choice) end
        end
    else
        for _,row in ipairs(Data.items) do add(row,{level=60,soul=true}) end
    end
    for _,entry in ipairs(loadout and loadout.variants or {}) do
        local row=variants[entry.id]
        if row then add(row,entry) end
    end
    return rows
end

function Shachi.new(o)
    local self={}
    local find,load=o.find or StaticFindObject,o.load or LoadAsset
    local fname=o.fname or FName
    local construct=o.construct or StaticConstructObject
    local clock=o.clock or os.clock
    local random=o.random or math.random
    local assets={}
    local function say(r,line)
        if o.log then o.log('[HunShadow] '..tostring(r.name or U.key(r.actor))..' '..line) end
    end
    local function current(r)
        return U.valid(r.actor) and o.current and o.current(r)
    end
    local function asset(path)
        if U.valid(assets[path]) then return assets[path] end
        for _,get in ipairs({find,load,find}) do
            local ok,obj=pcall(get,path)
            if ok and U.valid(obj) then assets[path]=obj;return obj end
        end
    end
    local summons=require('hun_shachi_summons').new({current=current,say=say,asset=asset,register=o.registerHook,unregister=o.unregisterHook})
    local chains=require('hun_shachi_chains').new({current=current,say=say,asset=asset,fname=fname})
    local charge=Charge.new({current=current,say=say,asset=asset,call=call})
    local function attr(r,field)
        local stats=o.stats and o.stats()
        if not stats then return nil end
        local ok,value=pcall(stats.read,stats,r.actor,field)
        if ok and type(value)=='table' and type(value.current)=='number' and math.abs(value.current)<math.huge then return value.current end
    end
    local function write(r,field,value)
        if not current(r) then return false end
        local stats=o.stats and o.stats()
        if not stats then return false end
        local before=attr(r,field)
        if before==nil then return false end
        if near(before,value) then return true end
        say(r,'即将写 '..field..'='..value)
        local called,ok=pcall(stats.writeBase,stats,r.actor,field,value)
        local after=attr(r,field)
        say(r,field..' '..before..'→'..tostring(after))
        return called and ok and near(after,value)
    end
    local function tag(name) return {TagName=fname(name)} end
    local function count(asc,name)
        local ok,value=call(asc,'GetGameplayTagCount',tag(name))
        return ok and type(value)=='number' and value or nil
    end
    function self:equip(r)
        if not current(r) or r.shadowState then return end
        local loadout=r.loadout or {}
        local state={choices=optionsFor(r.loadout),slots={},copies={},effects={},untilAt={},attempts={},
                     uncertainEffects={},nextAt=0,resources=loadout.resources or {},ai=loadout.ai or {}}
        r.shadowState=state
        if #state.choices==0 then return end
        local attributes=loadout.attributes or {}
        -- An explicit override wins. Retain a larger cap contributed by gear/talents.
        local cap=attr(r,'SpiritShadow_Max')
        if cap then
            local wanted=attributes.SpiritShadow_Max or math.max(cap,4)
            if write(r,'SpiritShadow_Max',wanted) then
                write(r,'SpiritShadow',math.min(wanted,attributes.SpiritShadow or wanted))
            end
        end
        write(r,'ShachiRegen',attributes.ShachiRegen or 0.0833)
        write(r,'ShachiRegenCooldown',attributes.ShachiRegenCooldown or 1.0)
        say(r,'影之武装候选='..#state.choices..' 暗源='..tostring(attr(r,'SpiritShadow'))..'/'..tostring(attr(r,'SpiritShadow_Max')))
    end

    -- Native GetWeaponPowerMultiplier looks up the backpack. A private config is absent from that
    -- index. Confirm its actual native multiplier and compensate once in both of its damage maps.
    local function privateConfig(r,choice)
        local state=r.shadowState
        local cached=state.copies[choice.id]
        if U.valid(cached) then return cached end
        -- An interaction variant supplies appearance and its own parsed damage weights.
        -- The template is ALWAYS its combat counterpart. Blocker and story abilities never enter a slot.
        local source=asset(choice.meta.donor or choice.path)
        local form=choice.meta.donor and asset(choice.path) or source
        if not U.valid(form) then return end
        local valid,class=call(source,'GetClass')
        if not valid or not U.valid(class) or type(construct)~='function' or not current(r) then return end
        serial=serial+1
        say(r,'即将复制武装 '..choice.meta.label..' 等级='..choice.level)
        local made,copy=pcall(construct,class,r.actor,fname('PG_Hun_Shadow_'..serial),0x40,0,false,false,source)
        if not made or not U.key(copy) or U.key(copy)==U.key(source) then return end
        local _,outer=call(copy,'GetOuter')
        local _,actualClass=call(copy,'GetClass')
        if U.key(outer)~=U.key(r.actor) or U.key(actualClass)~=U.key(class) then return end
        local beforeA,beforeB=damageMap(source,MAP),damageMap(source,NORMALIZED)
        if not beforeA or not beforeB then return end
        local values=(choice.soul and next(beforeB) and beforeB) or beforeA
        if choice.meta.donor then
            values=damageMap(form,MAP)
            local skin,skinKey=display(form)
            local _,sourceKey=display(source)
            if not skinKey or not sourceKey then return end
            if skinKey~=sourceKey then
                if not pcall(function()copy['Display Data']=skin end) then return end
            end
            local _,copiedKey=display(copy)
            local _,originalKey=display(source)
            if copiedKey~=skinKey or originalKey~=sourceKey then return end
        end
        local ok,power=call(copy,'GetWeaponPowerMultiplier',r.actor)
        if not ok or type(power)~='number' or not (power>0 and power<1000) or not values or not next(values) then return end
        local scale=(1+(choice.level-1)/10)/power
        for _,field in ipairs({MAP,NORMALIZED}) do
            if not current(r) then return end
            local map=U.field(copy,field)
            local prior=damageMap(copy,field)
            if not prior then return end
            -- A normalized map can legitimately be empty on an evolved config (e.g. the puppet bell).
            -- Leave that optional channel empty; scale only the authored combat channel in the private copy.
            local desired=(field==NORMALIZED and not next(beforeB)) and beforeB or values
            local changed=pcall(function()
                for name in pairs(prior) do if desired[name]==nil then map:Remove(tag(name)) end end
                for name,amount in pairs(desired) do map:Add(tag(name),amount*scale) end
            end)
            if not changed or not matches(damageMap(copy,field),desired,scale) then return end
        end
        if not matches(damageMap(source,MAP),beforeA,1) or not matches(damageMap(source,NORMALIZED),beforeB,1) then return end
        if choice.meta.normal:find('Weapon_ThunderSpear',1,true) then
            -- This native passive reads a game-instance achievement subsystem. It provides no
            -- combat move. Exclude it from the private config before its equip passives are granted.
            local field='Equip Passive Abilities'
            local grantedClasses=U.array(U.field(copy,field))
            local safe={}
            for _,cls in ipairs(grantedClasses or {}) do
                local path=objectPath(cls)
                if not path then return end
                if not path:find('GA_ThunderSpear_ParalyzeAchievement',1,true) then safe[#safe+1]=cls end
            end
            if not grantedClasses or #safe==#grantedClasses then return end
            if not pcall(function() copy[field]=safe end) then return end
            local check=U.array(U.field(copy,field))
            if not check or #check~=#safe then return end
            for i,cls in ipairs(check) do if U.key(cls)~=U.key(safe[i]) then return end end
        end
        state.copies[choice.id]=copy
        say(r,'武装私有副本读回 '..choice.meta.label..' 倍率='..string.format('%.3f',power*scale))
        return copy
    end

    local function effectStack(handle)
        local lib=asset(STACK_UTIL)
        local ok,n=call(lib,'GetActiveGameplayEffectStackCount',handle)
        return ok and type(n)=='number' and n or nil
    end
    local function applyEffects(r,asc,choice)
        local state=r.shadowState
        local wanted={}
        for _,rule in ipairs(choice.meta.effects) do
            if rule.minimum<=choice.level and (not rule.soul or choice.soul) then
                local prior=wanted[rule.path]
                if not prior or rule.level>prior.level then wanted[rule.path]=rule end
            end
        end
        for path,entry in pairs(state.effects) do
            local nextRule=wanted[path]
            if entry.slot and (not nextRule or nextRule.level~=entry.level) then
                if not current(r) then return false end
                say(r,'即将撤下武装效果 '..path:match('[^/]+$'))
                call(asc,'RemoveActiveGameplayEffect',entry.handle,-1)
                if effectStack(entry.handle)~=0 then return false end
                state.effects[path]=nil
            end
        end
        for path,rule in pairs(wanted) do
            if not state.effects[path] and not state.uncertainEffects[path] then
                local cls=asset(path)
                if U.valid(cls) and current(r) then
                    local read,n=call(asc,'GetGameplayEffectCount',cls,nil,false)
                    -- Never take ownership of an effect that was already present.
                    if read and n==0 then
                        say(r,'即将应用武装效果 '..path:match('[^/]+$'))
                        local ok,result=call(asc,'BP_ApplyGameplayEffectToSelf',cls,rule.level,{})
                        local id=ok and U.struct(result,'Handle')
                        if type(id)=='number' and id>0 then
                            local handle={Handle=id,bPassedFiltersAndWasExecuted=true}
                            state.effects[path]={slot=rule.slot,handle=handle,level=rule.level}
                            say(r,'武装效果读回 栈='..tostring(effectStack(handle)))
                        else
                            -- A native write without an identifiable handle may already have run
                            -- (instant effects have no durable stack). Do not retry it on each cast.
                            state.uncertainEffects[path]=true
                            say(r,'武装效果缺少可读句柄，本实例不重复施加 '..path:match('[^/]+$'))
                        end
                    end
                end
            end
        end
        return true
    end

    local function setSlot(r,wc,index,value,prior)
        local slot=tag(SLOT)
        if not current(r) then return false end
        local before,ok=slotConfig(wc,slot,index)
        if not ok or U.key(before)~=U.key(prior) then return false end
        for attempt=1,(value and 2 or 1) do
            say(r,'即将写影武槽 '..index..' ('..attempt..')')
            local called,err=call(wc,'SetSlotWeapon',slot,index,attempt==2 and {ObjectPointer=value} or value)
            local after,read=slotConfig(wc,slot,index)
            if read and U.key(after)==U.key(value) then return true end
            if not read or U.key(after)~=U.key(prior) or not current(r) then return false end
            -- Retry the interface wrapper only after a concrete argument-marshalling error.
            -- A successful but unreadable native write may still be pending.
            local reason=tostring(err):lower()
            if called or not (reason:find('interface',1,true) or reason:find('objectpointer',1,true)
                or reason:find('convert',1,true) or reason:find('expected',1,true)) then return false end
        end
        return false
    end
    local function equipChoice(r,wc,asc,choice,now)
        local s=r.shadowState
        local ok,index=call(wc,'GetCurrentWeaponIndex',tag(SLOT),false)
        if not ok or type(index)~='number' or index < -1 or index>1 then return false end
        local slot=tag(SLOT)
        local entry=s.slots[index]
        if entry and entry.id==choice.id then
            local seen=slotConfig(wc,slot,index)
            return U.key(seen)~=nil and U.key(seen)==U.key(entry.copy) and applyEffects(r,asc,choice)
        end
        local scale=s.resources.cooldown_scale or 1
        if now<(s.switchedAt or -100)+0.35*scale then return false end
        local copy=privateConfig(r,choice)
        if not copy then return false end
        local other=index==0 and 1 or 0
        local saved=s.slots[other]
        local prev,read=slotConfig(wc,slot,other)
        if not read or (saved and U.key(prev)~=U.key(saved.copy)) then return false end
        local armed,restoreRules=summons:arm(r,choice,Data.summons[choice.path])
        if not armed then return false end
        local previousSlot=s.slots[other]
        s.slots[other]={id=choice.id,copy=copy,original=previousSlot and previousSlot.original or prev}
        if previousSlot then s.slots[other].original=previousSlot.original end
        if not setSlot(r,wc,other,copy,prev) then
            if restoreRules then restoreRules() end
            local actual,readable=slotConfig(wc,slot,other)
            if readable and U.key(actual)==U.key(prev) then s.slots[other]=previousSlot else s.disabled=true end
            return false
        end
        if s.originalIndex==nil then s.originalIndex=index end
        local function rollback()
            if restoreRules then restoreRules() end
            if not current(r) then return end
            if index>=0 then call(wc,'SetCurrentWeapon',slot,index) end
            local restored=setSlot(r,wc,other,prev,copy)
            local gotIndex,nowIndex=call(wc,'GetCurrentWeaponIndex',slot,false)
            if restored and index==-1 and gotIndex and nowIndex~=-1 then
                call(wc,'SetCurrentWeapon',slot,-1)
                gotIndex,nowIndex=call(wc,'GetCurrentWeaponIndex',slot,false)
            end
            say(r,'换装失败还原槽 '..other..'='..tostring(restored)..' 当前='..tostring(nowIndex))
            if restored then s.slots[other]=previousSlot end
            if not restored or not gotIndex or nowIndex~=index then s.disabled=true end
        end
        say(r,'即将启用影武槽 '..other..' '..choice.meta.label)
        call(wc,'SetCurrentWeapon',slot,other)
        local got,active=call(wc,'GetCurrentWeaponIndex',slot,false)
        local after=slotConfig(wc,slot,other)
        if not got or active~=other or U.key(after)~=U.key(copy) then rollback();return false end
        local specs=granted(asc)
        local has=false
        for _,move in ipairs(Data.moves[choice.path]) do if specs[move.cls] then has=true;break end end
        if not has then rollback();return false end
        chains:select(r,choice.path)
        s.switchedAt=now
        say(r,'已读回槽及授予技能 '..choice.meta.label..' 槽='..other)
        return applyEffects(r,asc,choice)
    end

    -- Evaluate the same static cost adjustments as BP_ShachiAbility_Base. Only the NPC's own ASC is read.
    local function usableMove(choice,move,available,hasTag,beforeEquip)
        local cost=move.cost
        local kind=Data.kinds[choice.path]
        if kind=='Ranged' and hasTag('CharacterState.Accessory.RangedWeapon') then cost=0
        elseif kind=='Magic' and hasTag('CharacterState.Accessory.MagicWeapon') then cost=math.max(0,cost-1)
        elseif kind=='Strength' and hasTag('CharacterState.Accessory.PowerWeapon') then cost=cost+1 end
        if available+0.001<cost or (move.ongoing>0 and available<=0) then return false end
        for _,needed in ipairs(move.needs)do
            if not (beforeEquip and needed:match('^CharacterState%.WeaponUpgrade%.')) and not hasTag(needed) then return false end
        end
        for _,excluded in ipairs(move.excludes)do
            if not (beforeEquip and excluded:match('^CharacterState%.WeaponUpgrade%.')) and hasTag(excluded)~=false then return false end
        end
        return true,cost
    end
    local function readTags(asc)
        local tags={}
        return function(name)
            if tags[name]==nil then
                local n=count(asc,name)
                if type(n)~='number' then return nil end
                tags[name]=n>0
            end
            return tags[name]
        end
    end
    local function reserveCharge(s,ctx,now,available)
        return s.resources.consume_skill_resources~=false and available<=math.max(1,(s.cap or 5)/2) and not ctx.opening and not ctx.targetBroken and (ctx.hpRatio or 1)>.25
            and now<(s.lastPaidAt or -math.huge)+20
    end
    local function followup(move)
        for _,need in ipairs(move.needs) do
            if need:match('^Ability%.Action%.Hun%.') or need=='Ability.Action.Stance' or need=='Ability.Action.HoldDeflect'
                or need=='CharacterState.Deflect.Stance' or need=='CharacterState.AbilityState.Stance.HoldingStanceKey'
                or need:match('^CharacterState%.AbilityState%..*CanCombo') or need:match('^CharacterState%.AbilityState%..*PerfectDodge') then return true end
        end
        return false
    end
    local function choose(s,ctx,now,available,hasTag,aic,equipped)
        local pool,total={},0
        local preserve=reserveCharge(s,ctx,now,available)
        local gates={}
        for _,choice in ipairs(s.choices) do
            local usable,favour,ranged=false,false,false
            if (not equipped or equipped==choice.id) and (s.untilAt[choice.id] or 0)<=now then
                for _,move in ipairs(Data.moves[choice.path]) do
                    local ok,cost=usableMove(choice,move,available,hasTag,true)
                    if ok and (not equipped or followup(move)) and not (preserve and cost>0) then
                        if gates[move.priority]==nil then
                            local read,allow=call(aic,'CanActivateExternalActionAbility',move.priority)
                            gates[move.priority]=read and allow==true
                        end
                        if gates[move.priority] then
                            usable=true
                            local p=Charge.profile(move)
                            if p and p.ranged then ranged=true end
                            if p and p.kind~='channel' and Charge.opportunity(p,move,ctx) then favour=true end
                        end
                    end
                end
            end
            if usable then
                local kind=choice.meta.category
                local far=ctx.distance>650
                local distant=ranged or kind==1 or kind==4 or kind==3
                local factor=far and (distant and 1 or 0) or (distant and 0.65 or 1)
                if ctx.targetBroken or ctx.opening then factor=factor*((kind==0 or kind==2) and 1.8 or 1) end
                if favour then factor=factor*2 end
                if s.ai.repeat_policy~='none' and s.last==choice.id then factor=factor*0.22 end
                local w=choice.weight*factor
                if w>0 then total=total+w;pool[#pool+1]={choice=choice,upper=total} end
            end
        end
        if total==0 then return end
        local pick=random()*total
        for _,entry in ipairs(pool) do if pick<=entry.upper then return entry.choice end end
        return pool[#pool].choice
    end
    local function chooseMove(choice,asc,available,preserve,aic,ctx,continuation,moves)
        local specs=granted(asc)
        local hasTag=readTags(asc)
        local best,bestSpec,bestProfile,bestScore,bestCost
        for _,move in ipairs(moves or Data.moves[choice.path]) do
            local spec=specs[move.cls]
            if spec and spec.active==0 and (not continuation or followup(move)) then
                local ok,cost=usableMove(choice,move,available,hasTag,false)
                if ok and not (preserve and cost>0) and (not moves or cost==0) then
                    local read,allowed=call(aic,'CanActivateExternalActionAbility',move.priority)
                    if read and allowed==true then
                        local p=Charge.profile(move)
                        local hold=Charge.opportunity(p,move,ctx) and (not p.upgrade or hasTag(p.upgrade))
                        local score=hold and p.kind~='channel' and 2 or 0
                        -- Retain native follow-ups and counters during their short eligibility window.
                        if followup(move) then score=score+3 end
                        if not bestScore or score>bestScore then
                            best,bestSpec,bestProfile,bestScore,bestCost=move,spec,hold and p or nil,score,cost
                        end
                    end
                end
            end
        end
        return best,bestSpec,bestProfile,bestCost
    end

    local function ownedInstances(r,spec,fn)
        for _,field in ipairs({'NonReplicatedInstances','ReplicatedInstances'}) do
            for _,instance in ipairs(U.array(U.struct(spec.spec,field)) or {}) do
                local _,avatar=call(instance,'GetAvatarActorFromActorInfo')
                if current(r) and U.key(avatar)==U.key(r.actor) then fn(instance) end
            end
        end
    end

    local function retireCast(r,asc,action)
        if not asc then return false end
        local spec,read=activeSpec(asc,action)
        if not read then return false end
        if not spec or spec.active==0 then return true end
        if type(spec.active)~='number' or action.retireAttempted then return false end
        action.retireAttempted=true
        say(r,'即将结束该魂未收招的影武 '..action.move.tag)
        ownedInstances(r,spec,function(instance)call(instance,'K2_CancelAbility')end)
        spec,read=activeSpec(asc,action)
        say(r,'影武中止读回 活动数='..tostring(spec and spec.active))
        return read and (not spec or spec.active==0)
    end
    local function livingTarget(target)
        if not U.valid(target) then return false end
        if o.hp then
            local ok,hp=pcall(o.hp,target)
            return ok and type(hp)=='number' and hp>0 and hp<math.huge
        end
        return true
    end
    local function matchesTarget(r,target)
        local key=U.key(target)
        if not key or not livingTarget(target) then return false end
        if o.nativeTarget then
            local ok,selected=pcall(o.nativeTarget,r.actor)
            return ok and U.key(selected)==key
        elseif o.aiOf then
            local ok,ai=pcall(o.aiOf,r.actor)
            local _,selected=call(ok and U.field(ai,'BlackboardComponent'),'GetValueAsObject',fname('TargetActor'))
            return U.key(selected)==key
        end
        return true
    end
    local function clearSight(r,target,distance)
        if distance<=650 then return true end
        local _,controller=call(r.actor,'GetController')
        if not U.valid(controller) then controller=U.field(r.actor,'Controller') end
        local _,pawn=call(controller,'K2_GetPawn')
        if U.key(pawn)~=U.key(r.actor) then return false end
        local ok,clear=call(controller,'LineOfSightTo',target,{X=0,Y=0,Z=0},false)
        return ok and clear==true
    end
    local function castRecord(choice,move,spec,now,resource,target,duration)
        local _,name=call(target,'GetFullName')
        return {choice=choice,move=move,handle=spec.id,started=now,deadline=now+duration+1,
            before=resource,lastResource=resource,index=spec.index,ascKey=spec.ascKey,abilityKey=spec.abilityKey,target=U.key(target),targetName=name}
    end
    -- Free casts may need ammunition for the native activation check. Return only
    -- that advance and the cost observed on this cast. A one-shot cannot refund later hits.
    local function applyCorrection(r,p,target)
        p.writing=true
        local ok=write(r,'SpiritShadow',target)
        p.writing=false
        return ok
    end
    local function settleFree(r,s,asc,value,closing)
        local p=s.payment
        if not p then return value end
        if closing then p.closing=true end
        if p.writing or not current(r) or not U.valid(asc) then return nil end
        if p.asc~=U.key(asc) then s.payment=nil;return value end
        value=value or attr(r,'SpiritShadow')
        if type(value)~='number' then return nil end
        if p.funding then
            local original=p.last-p.advance
            if value<original or value>p.last then
                say(r,'垫付期间暗源另有变化，保留新的读回 '..value)
                s.payment=nil
                return value
            end
            -- No native cast was sent. Undo only the part of the advance that actually landed.
            p.advance=value-original;p.last=value;p.remaining=0;p.funding=false
        end
        if p.pending then
            -- Retry the same absolute write only while its original value is still present.
            if near(value,p.pending.from) then
                if not applyCorrection(r,p,p.pending.to) then return nil end
                value=p.pending.to
            elseif not near(value,p.pending.to) then
                say(r,'结算期间暗源已变化，保留新的读回 '..value)
                p.last=value
            end
            p.pending=nil
        end
        local loss=math.max(0,p.last-value)
        local refund=math.min(loss,p.remaining)
        local repay=(p.closing or (not p.channel and loss>0)) and p.advance or 0
        local wanted=math.max(0,value+refund-repay)
        if wanted>value then
            local cap=attr(r,'SpiritShadow_Max')
            if type(cap)~='number' then return nil end
            wanted=math.min(math.max(cap,value),wanted)
        end
        p.remaining=p.remaining-refund;p.advance=p.advance-repay;p.last=wanted
        if not near(wanted,value) then
            p.pending={from=value,to=wanted}
            if not applyCorrection(r,p,wanted) then return nil end
            p.pending=nil
        end
        if p.closing and p.advance>0 then return settleFree(r,s,asc,wanted,true) end
        if p.closing or (p.remaining==0 and p.advance==0) then s.payment=nil end
        return wanted
    end
    local function inputFollowup(aic,move)
        local class=asset(move.cls)
        local input=asset('/PBZInput/InputActions/IA_ShachiAbility.IA_ShachiAbility')
        if not input or objectPath(class)~=move.cls then return false,false end
        return call(aic,'TryActivateExternalActionAbilityByClass',class,input,move.priority)
    end
    local function continueCast(r,s,asc,now,ctx)
        local cast=s.running
        if cast.followTried or cast.pendingUntil or cast.cancelled or cast.hold or cast.move.release or cast.move.ongoing>0
            or ctx.busy or ctx.pairProtected or ctx.allowAction==false or ctx.allowShadow==false or cast.target~=U.key(ctx.target) then return end
        -- Only offer a free follow-up explicitly naming this live predecessor.
        if not cast.followups then
            cast.followups={}
            for _,move in ipairs(Data.moves[cast.choice.path]) do
                if move.cls~=cast.move.cls and move.cost==0 and move.ongoing==0 and not move.release then
                    for _,needed in ipairs(move.needs) do
                        if needed==cast.move.tag then cast.followups[#cast.followups+1]=move;break end
                    end
                end
            end
        end
        if #cast.followups==0 or now<(cast.nextWindowRead or 0) then return end
        cast.nextWindowRead=now+.10
        local _,window=Vitals.actionState(r.actor,fname)
        if not window or not matchesTarget(r,ctx.target) then return end
        local wc=ownedComponent(r.actor,'Character Weapons Component')
        local _,idx=call(wc,'GetCurrentWeaponIndex',tag(SLOT),false)
        local slot=s.slots[idx]
        if not slot or slot.id~=cast.choice.id or U.key(slotConfig(wc,tag(SLOT),idx))~=U.key(slot.copy) then return end
        local aic=ownedComponent(r.actor,'Ability Input Component')
        local spirit=attr(r,'SpiritShadow')
        if type(spirit)~='number' or type(ctx.distance)~='number' then return end
        local move,spec=chooseMove(cast.choice,asc,spirit,false,aic,ctx,true,cast.followups)
        if not move or not (ctx.distance>=0 and ctx.distance<=move.radius) or not clearSight(r,ctx.target,ctx.distance) then return end
        cast.followTried=true
        local nextCast=castRecord(cast.choice,move,spec,now,spirit,ctx.target,move.duration)
        say(r,'即将 原生影武接段 '..cast.move.tag..' → '..move.tag)
        local sent,result=inputFollowup(aic,move)
        local read=activeSpec(asc,nextCast)
        local active=read and type(read.active)=='number' and read.active>0
        say(r,'影武接段读回 返回='..tostring(result)..' 活动数='..tostring(read and read.active))
        if active then s.running=nextCast
        elseif sent and result==true then cast.queued=nextCast end
    end
    local function observe(r,s,asc,now,ctx)
        local cast=s.running
        if not cast then return false end
        if cast.queued then
            local nextCast=cast.queued
            local read=activeSpec(asc,nextCast)
            if read and type(read.active)=='number' and read.active>0 then
                say(r,'影武接段延后读回 活动数='..read.active)
                s.running=nextCast;cast=nextCast
            elseif now<nextCast.started+.45 then return true
            else cast.queued=nil end
        end
        local spec,readable=activeSpec(asc,cast)
        if not readable then
            if now<cast.deadline then return true end
            charge:finish(r,cast.hold)
            s.running=nil;s.quarantine=cast
            return false
        end
        local after=attr(r,'SpiritShadow')
        local debitObserved=type(after)=='number' and after<cast.lastResource
        if debitObserved then s.lastPaidAt=now end
        if s.payment then after=settleFree(r,s,asc,after,s.payment.cast~=cast) end
        if r.shadowState~=s or s.running~=cast then return false end
        if after then cast.lastResource=after end
        local protected=false
        if ctx.pairProtected and cast.target==U.key(ctx.target) and livingTarget(ctx.target) then
            local read,name=call(ctx.target,'GetFullName')
            protected=read and type(name)=='string' and cast.targetName==name
        end
        local lost=cast.hold and (not cast.released or cast.awaitWindow) and (cast.target~=U.key(ctx.target)
            or (not protected and (not matchesTarget(r,ctx.target) or type(ctx.distance)~='number'
                or not (ctx.distance>=0 and ctx.distance<=3000) or not clearSight(r,ctx.target,ctx.distance))))
        if cast.pendingUntil then
            if (spec and spec.id==cast.handle and type(spec.active)=='number' and spec.active>0) or debitObserved then
                cast.pendingUntil=nil
            elseif now<cast.pendingUntil and not lost then return true
            else
                -- The request may have been accepted even though neither debit nor activity was
                -- observable. Never issue that same cast again on the strength of a missing readback.
                charge:finish(r,cast.hold)
                s.untilAt[cast.choice.id]=math.huge;s.running=nil
                say(r,'影武启动未能读回，已暂停本实例的 '..cast.choice.meta.label)
                return false
            end
        end
        if not spec or spec.id~=cast.handle or spec.active==0 then
            charge:finish(r,cast.hold)
            say(r,'影武结束 '..cast.choice.meta.label..' 暗源 '..cast.before..'→'..tostring(after)..' 活动数='..tostring(spec and spec.active))
            s.running=nil
            return false
        end
        if cast.cancelledAt and now>=cast.cancelledAt+.5 then
            charge:finish(r,cast.hold)
            s.running=nil;s.quarantine=cast
            say(r,'原生影武仍活动，暂缓新的影武并交还战斗决策 '..cast.choice.meta.label)
            return false
        end
        if cast.hold and not lost and not protected and now<cast.deadline and not cast.cancelled then
            local hasTag=readTags(asc)
            ownedInstances(r,spec,function(instance)charge:observe(r,cast,instance,ctx,now,hasTag) end)
        elseif not cast.hold and not protected and not cast.released and cast.move.release and now<cast.deadline then
            ownedInstances(r,spec,function(instance)charge:tap(r,cast,instance,now) end)
        end
        if (lost or now>=cast.deadline or (cast.hold and not cast.released and now>cast.started+cast.profile.limit+.5)) and not cast.cancelled then
            cast.cancelled=true;cast.cancelledAt=now
            ownedInstances(r,spec,function(instance)
                say(r,'即将取消影武 '..cast.choice.meta.label..(lost and ' 目标丢失' or ' 等待超时'))
                call(instance,'K2_CancelAbility')
            end)
            charge:finish(r,cast.hold)
            local read=activeSpec(asc,cast)
            say(r,'影武取消读回 活动数='..tostring(read and read.active))
        end
        return true
    end
    local function observeResources(r,s,now)
        if now<(s.sampleAt or 0) then return end
        s.sampleAt=now+1
        if not s.initialRead then
            local cap=attr(r,'SpiritShadow_Max')
            s.cap=cap
            local amount=attr(r,'SpiritShadow')
            local attributes=r.loadout and r.loadout.attributes or {}
            -- Accessories can raise the cap after the base resource pass. Fill exactly once,
            -- before the first fight action, while respecting explicit initial overrides.
            if cap and amount and not s.running and not s.last and attributes.SpiritShadow==nil and amount<cap then
                write(r,'SpiritShadow',cap)
            end
            say(r,'资源下一拍 暗源='..tostring(attr(r,'SpiritShadow'))..'/'..tostring(cap)..' 杀气回复='
                ..tostring(attr(r,'ShachiRegen'))..' 延迟='..tostring(attr(r,'ShachiRegenCooldown')))
            s.initialRead=true
        end
        local value=attr(r,'Shachi')
        if value and s.lastShachi and value~=s.lastShachi and (s.sampleLines or 0)<8 then
            say(r,'杀气采样 '..s.lastShachi..'→'..value)
            s.sampleLines=(s.sampleLines or 0)+1
        end
        s.lastShachi=value
    end

    function self:tick(r,ctx)
        if not current(r) then return false end
        if r.dead then self:interrupt(r);return false end
        if r.shadowSubmitting then return true end
        if not r.shadowState then self:equip(r) end
        local s=r.shadowState
        if not s or s.disabled or #s.choices==0 then return false end
        local now=ctx.now or clock()
        local asc=ownedComponent(r.actor,'AbilitySystemComponent')
        if not asc then return false end
        if s.running and s.running.starting then return true end
        observeResources(r,s,now)
        if observe(r,s,asc,now,ctx) then
            continueCast(r,s,asc,now,ctx)
            return true
        end
        if r.shadowState~=s or r.dead then return false end
        if s.payment then
            settleFree(r,s,asc,nil,true)
            if s.payment then return false end
        end
        if s.quarantine then
            if now<(s.checkQuarantineAt or 0) then return false end
            s.checkQuarantineAt=now+1
            local queued=s.quarantine.queued
            if queued then
                if not retireCast(r,asc,queued) or (not queued.retireAttempted and now<queued.started+.45) then return false end
                s.quarantine.queued=nil
            end
            local old,readable=activeSpec(asc,s.quarantine)
            if not readable or (old and old.active~=0) then return false end
            s.quarantine=nil;s.checkQuarantineAt=nil
        end
        if now<s.nextAt or ctx.busy or ctx.allowAction==false or ctx.allowShadow==false or not U.valid(ctx.target)
            or U.key(ctx.target)==U.key(r.actor) or type(ctx.distance)~='number'
            or not (ctx.distance>=0 and ctx.distance<=3000) then return false end
        local performing,canChain=Vitals.actionState(r.actor,fname)
        s.nextAt=now+(performing and .15 or 1)
        if performing and not canChain then return false end
        local wc=ownedComponent(r.actor,'Character Weapons Component')
        if not wc or count(asc,ACTIVE_TAG)~=0 then return false end
        local equipped
        if performing then
            local _,idx=call(wc,'GetCurrentWeaponIndex',tag(SLOT),false)
            local entry=s.slots[idx]
            if not entry then return false end
            equipped=entry.id
        end
        local available=attr(r,'SpiritShadow')
        if type(available)~='number' then return false end
        if not matchesTarget(r,ctx.target) or not clearSight(r,ctx.target,ctx.distance) then return false end
        local free=s.resources.consume_skill_resources==false
        local budget=free and math.max(available,attr(r,'SpiritShadow_Max') or available) or available
        local aic=ownedComponent(r.actor,'Ability Input Component')
        local choice=choose(s,ctx,now,budget,readTags(asc),aic,equipped)
        if not choice then
            if available<=0 and not s.emptyReported then
                say(r,'暗源已耗尽，等待原生免费招式窗口或资源恢复')
                s.emptyReported=true
            end
            return false
        end
        if available>0 then s.emptyReported=nil end
        if not equipChoice(r,wc,asc,choice,now) then
            local failures=(s.attempts[choice.id] or 0)+1
            s.attempts[choice.id]=failures;s.untilAt[choice.id]=now+math.min(120,5*failures)
            say(r,'影武槽、配置或技能读回失败 '..choice.meta.label)
            return false
        end
        -- Equipping can run passives and change either the balance or the target.
        available=attr(r,'SpiritShadow')
        if type(available)~='number' or not current(r) or not matchesTarget(r,ctx.target) then return false end
        budget=free and math.max(available,attr(r,'SpiritShadow_Max') or available) or available
        local move,spec,profile,cost=chooseMove(choice,asc,budget,reserveCharge(s,ctx,now,available),aic,ctx,performing)
        if not move then s.untilAt[choice.id]=now+2;return false end
        local cast=castRecord(choice,move,spec,now,available,ctx.target,move.duration)
        local funded=available
        cast.starting=true;s.running=cast
        if free then
            funded=move.ongoing>0 and budget or math.max(available,cost)
            s.payment={cast=cast,asc=U.key(asc),advance=funded-available,last=funded,
                channel=move.ongoing>0,remaining=move.ongoing>0 and math.huge or cost,funding=funded>available}
            if funded>available and not write(r,'SpiritShadow',funded) then
                if s.running==cast then s.running=nil;settleFree(r,s,asc,nil,true) end
                return false
            end
            if s.running~=cast or not current(r) then return false end
            s.payment.funding=false
        end
        cast.lastResource=funded
        -- The ability checks its owner's input during activation. Establish it before the request.
        local hold=profile and charge:begin(r,asc)
        if r.shadowState~=s or s.running~=cast or not current(r) then charge:finish(r,hold);return false end
        cast.hold,cast.profile=hold,profile
        local ready=activeSpec(asc,cast)
        if not ready or ready.active~=0 or not matchesTarget(r,ctx.target)
            or U.key(ownedComponent(r.actor,'AbilitySystemComponent'))~=cast.ascKey then
            s.running=nil;charge:finish(r,hold)
            settleFree(r,s,ownedComponent(r.actor,'AbilitySystemComponent'),nil,true)
            return false
        end
        local priorSuccess=hold and profile.success and (count(asc,profile.success) or 0)>0
        if profile and not hold and not s.inputUnavailable then
            say(r,'未读回魂的独立长按，本次使用原生点按')
            s.inputUnavailable=true
        end
        say(r,'即将使用 '..choice.meta.label..' '..move.tag..' 暗源='..available)
        local ok,response
        r.shadowSubmitting=cast
        if performing then ok,response=inputFollowup(aic,move)
        else ok,response=call(asc,'TryActivateAbility',{Handle=spec.id},false) end
        r.shadowSubmitting=nil
        if r.shadowState~=s or s.running~=cast or not current(r) then
            if current(r) then
                local live=ownedComponent(r.actor,'AbilitySystemComponent')
                if U.key(live)==cast.ascKey and not retireCast(r,live,cast) and r.shadowState==s then
                    s.quarantine=cast;s.checkQuarantineAt=nil
                end
                if s.payment and s.payment.cast==cast then settleFree(r,s,live,nil,true) end
            end
            return false
        end
        cast.starting=nil
        local read=activeSpec(asc,cast)
        local after=attr(r,'SpiritShadow')
        local active=read and read.id==spec.id and type(read.active)=='number' and read.active>0
        say(r,'影武启动读回 返回='..tostring(response)..' 活动数='..tostring(read and read.active)..' 暗源='..tostring(after))
        local debited=type(after)=='number' and after<funded
        if debited then s.lastPaidAt=now end
        if not active and not debited and (not ok or response==false) then
            charge:finish(r,hold)
            s.running=nil;settleFree(r,s,asc,after,true)
            s.untilAt[choice.id]=now+2;return false
        end
        local duration=hold and math.max(move.duration,profile.limit+profile.tail) or move.duration
        cast.deadline=now+duration+1;cast.priorSuccess=priorSuccess
        cast.opening=ctx.opening or ctx.targetBroken
        if not active and not debited then s.running.pendingUntil=now+1 end
        s.last=choice.id;s.nextAt=now+math.max(0.35,(s.resources.cooldown_scale or 1)*2.0)
        observe(r,s,asc,now,ctx)
        if not s.running and s.payment then settleFree(r,s,asc,nil,true) end
        return true
    end
    function self:silence()
        summons:silence();assets={}
    end
    -- A dead body stops receiving brain ticks but may return with the same
    -- equipment. Retire its own transient inputs before suspending the brain.
    function self:interrupt(r)
        local s=r.shadowState
        local cast=s and s.running
        if not s or (not cast and not s.payment) then return end
        local asc=current(r) and ownedComponent(r.actor,'AbilitySystemComponent')
        s.running=nil
        if s.payment and not r.shadowSubmitting then settleFree(r,s,asc,nil,true) end
        if not cast then return end
        local retired=retireCast(r,asc,cast)
        local queued=cast.queued
        if queued and retireCast(r,asc,queued) and queued.retireAttempted then cast.queued=nil end
        charge:finish(r,cast.hold)
        if not retired or cast.queued then s.quarantine=cast;s.checkQuarantineAt=nil end
    end
    function self:cleanup(r)
        local s=r.shadowState
        if not s then return end
        if current(r) and s.quarantine then
            local asc=ownedComponent(r.actor,'AbilitySystemComponent')
            retireCast(r,asc,s.quarantine)
            if s.quarantine.queued then retireCast(r,asc,s.quarantine.queued) end
        end
        if r.shadowSubmitting then self:interrupt(r)
        elseif current(r) and s.running then
            local asc=ownedComponent(r.actor,'AbilitySystemComponent')
            if asc then
                local queued=s.running.queued
                if queued then
                    s.running.queued=nil
                    retireCast(r,asc,queued)
                end
                s.running.pendingUntil=nil
                observe(r,s,asc,s.running.deadline+1,{})
            end
        end
        if s.running then charge:finish(r,s.running.hold) end
        if s.payment and not r.shadowSubmitting and current(r) then settleFree(r,s,ownedComponent(r.actor,'AbilitySystemComponent'),nil,true) end
        charge:cleanup(r)
        summons:cleanup(r)
        chains:cleanup(r)
        if current(r) then
            local wc=ownedComponent(r.actor,'Character Weapons Component')
            local asc=ownedComponent(r.actor,'AbilitySystemComponent')
            if wc then
                local slotTag=tag(SLOT)
                local which,index=call(wc,'GetCurrentWeaponIndex',slotTag,false)
                local entry=which and s.slots[index]
                local ownActive=entry and U.key(slotConfig(wc,slotTag,index))==U.key(entry.copy)
                local initial=s.originalIndex
                local original=initial and s.slots[initial]
                local ready=true
                if original then ready=setSlot(r,wc,initial,original.original,original.copy) end
                if ownActive and ready and initial and initial>=0 then
                    call(wc,'SetCurrentWeapon',slotTag,initial)
                end
                for i,slot in pairs(s.slots) do
                    if i~=initial then setSlot(r,wc,i,slot.original,slot.copy) end
                end
                if ownActive and initial==-1 then call(wc,'SetCurrentWeapon',slotTag,-1) end
                if ownActive then
                    local _,restored=call(wc,'GetCurrentWeaponIndex',slotTag,false)
                    say(r,'清理影武槽 当前='..tostring(restored)..' 原始='..tostring(initial))
                end
            end
            for _,entry in pairs(s.effects) do
                call(asc,'RemoveActiveGameplayEffect',entry.handle,-1)
                say(r,'清理影武效果 栈='..tostring(effectStack(entry.handle)))
            end
        end
        r.shadowState=nil
    end
    return self
end
return Shachi
