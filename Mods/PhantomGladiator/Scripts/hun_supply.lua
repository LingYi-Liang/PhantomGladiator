-- Health flasks and native death handling for individual summoned Hun records.
local U = require('ue_observe')
local Supply = {}
local ROOT = '/PBZCombatAsset/Prototypes/GameplayEffects/'
local HEAL = ROOT..'Medicine/GE_Medicine_Medicine_01.GE_Medicine_Medicine_01_C'
local HIT_COOLDOWN = ROOT..'GE_MedicineInHit_Cooldown.GE_MedicineInHit_Cooldown_C'
local PAYLOAD = ROOT..'Medicine/BP_MedicinePreActivatePayload.BP_MedicinePreActivatePayload_C'
local ANIM = '/PBZCombatAsset/ActorData/Players/Hun/Montage/Item/AM_Hun_Medicine_'
local STATS = '/Script/Engine.Default__GameplayStatics'
local EVENTS = '/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
local COOLDOWN = 'CharacterState.AbilityState.HeiMoShang.RebornCooldown'
local REBORN = 'Ability.Action.Hun.HeiMoShang.Reborn'
local IMMORTAL = 'CharacterState.Immortal.HeiMoShang'
local NATIVE_COOLDOWN = '/Script/PBZCombatAsset.GE_HeiMoShang_RebornCooldown'
local REBORN_PASSIVE = 'GA_HeiMoShang_RebornPassive'
local BLOCK = {'Ability.Action.Execution','Ability.Executed','CharacterState.HitReact.State.Executing',
    'CharacterState.Hitreact.Phase.Act','CharacterState.Hitreact.State.Frozen',
    'CharacterState.Hitreact.State.Dead','CharacterState.Dead', IMMORTAL, REBORN}
-- Use_Common's GameplayEvent.UseItem starts at 0.241148 seconds. Its ordinary action ends at 1.3496.
local SIP = 0.2411484718
local END = 1.3496
local VARIANTS = {
    {'Weapon.Type.TangBlade','TangBlade'}, {'Weapon.Type.LongBlade','LongBlade'},
    {'Weapon.Type.DoubleBlade','DoubleBlade'}, {'Weapon.Type.SnakeDual','SnakeDual'},
    {'Weapon.Type.Unarmed','Unarmed'}
}

local function call(obj, method, ...)
    if not U.valid(obj) then return false end
    local args=table.pack(...)
    local ok,res=pcall(function() return obj[method](obj,table.unpack(args,1,args.n)) end)
    return ok,U.unwrap(res)
end

function Supply.new(o)
    local self, records, assets = {}, {}, {}
    local find, load = o.find or StaticFindObject, o.load or LoadAsset
    local fname, clock = o.fname or FName, o.now or o.clock
    local function say(r,message) (o.log or function()end)('[HunSupply] '..tostring(r.name)..' '..message) end
    local function object(path)
        if U.valid(assets[path]) then return assets[path] end
        local ok,v=pcall(find,path)
        if not ok or not U.valid(v) then ok,v=pcall(load,path) end
        if ok and U.valid(v) then assets[path]=v;return v end
    end
    local function state(r)
        local s=records[r]
        if s then return s end
        local resources=(r.loadout or {}).resources or {}
        local count=resources.medicine_count
        if count=='native_max' or count==nil then
            count=4
            -- The active talent adds one use per activation. Only mirror an observed spec
            -- to the private supply. Granting the original ability touches the world backpack.
            local asc=U.field(r.actor,'AbilitySystemComponent')
            local specs=U.array(U.struct(U.field(asc,'ActivatableAbilities'),'Items'))
            for _,spec in ipairs(specs or {}) do
                if U.className(U.struct(spec,'Ability'))=='GA_AddMedicineUseTime_C' then
                    local active=U.struct(spec,'ActiveCount')
                    if type(active)=='number' and active>0 then count=count+active end
                end
            end
        end
        s={remaining=count, consume=resources.consume_medicine~=false}
        records[r]=s
        return s
    end
    local function count(asc,key)
        local ok,value=call(asc,'GetGameplayTagCount',{TagName=fname(key)})
        return ok and type(value)=='number' and value or nil
    end
    local function blocked(asc)
        for _,key in ipairs(BLOCK) do if count(asc,key)~=0 then return true end end
        return false
    end
    local function emit(r,tag,optional)
        local value={TagName=fname(tag)}
        local data={EventTag=value,Instigator=r.actor,Target=r.actor,OptionalObject=optional}
        return call(object(EVENTS),'SendGameplayEventToActor',r.actor,value,data)
    end
    local function apply(asc,effect,level)
        local ok,context=call(asc,'MakeEffectContext')
        return call(asc,'BP_ApplyGameplayEffectToSelf',effect,level,ok and context or {})
    end
    local function flaskAnim(asc)
        local variant='Common'
        for _,v in ipairs(VARIANTS) do
            if (count(asc,v[1]) or 0)>0 then variant=v[2];break end
        end
        local function path(name) return ANIM..name..'.AM_Hun_Medicine_'..name end
        return object(path(variant)) or object(path('Common'))
    end
    local function readPosition(anim,montage)
        local played,playing=call(anim,'Montage_IsPlaying',montage)
        local ok,position=call(anim,'Montage_GetPosition',montage)
        if played and playing==true and ok and type(position)=='number' then return position end
    end
    local function advance(r,s,asc,now)
        local d=s.drink
        local pos=readPosition(d.anim,d.montage)
        if blocked(asc) or pos==nil or now-d.start>4 or not o.fighting(r) then
            say(r,'喝药结束或被打断，已服用='..tostring(d.used)..' 余药='..s.remaining)
            s.drink=nil
            return false
        end
        if not d.used and pos>=SIP then
            -- Mark committed before synchronous event listeners can re-enter the arena controller.
            d.used=true
            say(r,'即将 发送服药前事件并施加葫芦效果，动作位置='..pos)
            local payload
            local cls=object(PAYLOAD)
            if cls then
                local made,p=call(object(STATS),'SpawnObject',cls,r.actor)
                if made and U.valid(p) then
                    local wrote=pcall(function() p['Use Count']=1 end)
                    if wrote and U.field(p,'Use Count')==1 then payload=p end
                end
            end
            if payload then
                emit(r,'GameplayEvent.Medicine.PreActivate',payload)
                if not o.current(r) or not U.valid(asc) then return false end
                local use=U.field(payload,'Use Count')
                if use==0 and s.consume then s.remaining=s.remaining+1 end
            end
            local hp=o.stat(r.actor,'Health')
            if type(hp)~='number' or hp<=0 or blocked(asc) then
                s.drink=nil;return false
            end
            local ok=apply(asc,d.heal,6)
            local after=o.stat(r.actor,'Health')
            say(r,'服药读回 HP='..tostring(hp)..'→'..tostring(after)..' 调用='..tostring(ok)..' 余药='..s.remaining)
            if ok and o.current(r) then emit(r,'GameplayEvent.Medicine.PostActive') end
        end
        if pos>=END then s.drink=nil;return false end
        return true
    end
    function self:tick(r,ctx)
        if not o.current(r) or not U.valid(r.actor) then return false end
        local s,now=state(r),clock()
        if type(now)~='number' then return false end
        local asc=U.field(r.actor,'AbilitySystemComponent')
        if s.drink then return advance(r,s,asc,now) end
        local hp=o.stat(r.actor,'Health')
        if type(hp)~='number' or hp<=0 then return false end
        s.death=nil
        if not o.fighting(r) or s.remaining<=0 or now<(s.nextDrink or 0) or (ctx and ctx.busy)
            or (r.intent and now<(r.intent.busyUntil or 0)) then return false end
        if ctx and not ctx.opening and (type(ctx.distance)~='number' or ctx.distance<500) then return false end
        local maxHP=o.stat(r.actor,'Health_Max')
        if type(maxHP)~='number' or maxHP<=0 or hp>maxHP*0.5 or blocked(asc)
            or count(asc,'CharacterState.AbilityState.Medicine.InHitCooldown')~=0 then return false end
        s.nextDrink=now+2
        local heal,cd,montage=object(HEAL),object(HIT_COOLDOWN),flaskAnim(asc)
        local _,anim=call(U.field(r.actor,'Mesh'),'GetAnimInstance')
        if not heal or not cd or not montage or not U.valid(anim) then
            if not s.reportedAssets then say(r,'药品、蒙太奇或动画实例未就绪');s.reportedAssets=true end
            return false
        end
        say(r,'即将 播放服药动作，余药='..s.remaining)
        local ok,duration=call(r.actor,'PlayAnimMontage',montage,1.0,fname('None'))
        local pos=readPosition(anim,montage)
        say(r,'服药动作读回 时长='..tostring(duration)..' 位置='..tostring(pos))
        if not ok or type(duration)~='number' or duration<=0 or not pos or not o.current(r) then return false end
        s.nextDrink=now+math.max(END,duration)
        if s.consume then s.remaining=s.remaining-1 end
        s.drink={start=now,anim=anim,montage=montage,heal=heal,busyUntil=now+END}
        r.intent=r.intent or {}
        r.intent.busyUntil=math.max(r.intent.busyUntil or 0,now+END)
        say(r,'即将 施加喝药受击冷却')
        apply(asc,cd,1)
        say(r,'受击冷却计数='..tostring(count(asc,'CharacterState.AbilityState.Medicine.InHitCooldown')))
        return true
    end

    -- Only the equipped weapon supplies this passive. Never grant rebirth or change death/health tags here.
    local function passive(asc,r)
        local specs=U.array(U.struct(U.field(asc,'ActivatableAbilities'),'Items'))
        for _,spec in ipairs(specs or {}) do
            local class=U.className(U.struct(spec,'Ability'))
            if (class==REBORN_PASSIVE or class==REBORN_PASSIVE..'_C') and (U.struct(spec,'ActiveCount') or 0)>0 then
                for _,key in ipairs({'NonReplicatedInstances','ReplicatedInstances'}) do
                    for _,inst in ipairs(U.array(U.struct(spec,key)) or {}) do
                        local ok,avatar=call(inst,'GetAvatarActorFromActorInfo')
                        if ok and U.key(avatar)==U.key(r.actor) then return true,inst end
                    end
                end
                return true
            end
        end
        return false
    end
    function self:holdsDeath(r)
        if not o.current(r) then return false end
        local asc=U.field(r.actor,'AbilitySystemComponent')
        if not U.valid(asc) then return false end
        local s,now=state(r),clock()
        if type(now)~='number' then return false end
        local hp=o.stat(r.actor,'Health')
        if type(hp)~='number' or hp>0 then s.death=nil;return false end
        local d=s.death
        if d and d.done then return false end
        local active=(count(asc,REBORN) or 0)>0 or (count(asc,IMMORTAL) or 0)>0
        if not d then
            local ok, instance=passive(asc,r)
            if not active and (not ok or count(asc,'CharacterState.Forbid.Resurrect')~=0 or
                count(asc,'CharacterState.Immortal.XuKongHuaShan')~=0 or count(asc,COOLDOWN)~=0 or s.manualSpent) then return false end
            d={start=now,instance=instance};s.death=d
            say(r,'等待原生重生 被动='..tostring(ok)..' 动作='..tostring(active)..' HP='..hp)
        end
        if active then
            if not d.activated then
                say(r,'重生动作读回 冷却='..tostring(count(asc,COOLDOWN))..' 杀气='..tostring(o.stat(r.actor,'Shachi')))
                d.activated=true
            end
            if now-d.start<6 then return true end
        elseif not d.activated and now-d.start<1.5 then
            -- When the passive did not resolve its ability input on this NPC, reproduce the native guard sequence.
            -- A missing state query never permits forced activation.
            if not d.tried and now-d.start>=0.15 and U.valid(d.instance)
                and not U.valid(U.field(d.instance,'AbilityInput')) and not s.manualSpent
                and count(asc,'CharacterState.Forbid.Resurrect')==0 and count(asc,COOLDOWN)==0
                and count(asc,'CharacterState.Immortal.XuKongHuaShan')==0 then
                local comp=U.field(d.instance,'ActorStateComponent')
                local _,pending=call(comp,'InPendingState',{TagName=fname('CharacterState.Dead')})
                local _,vanish=call(comp,'CanActivateNewState',{TagName=fname('CharacterState.Vanish')})
                local input=U.field(r.actor,'Ability Input Component')
                local cd=object(NATIVE_COOLDOWN)
                if pending==true and vanish==true and cd and U.key(U.field(input,'AbilitySystem'))==U.key(asc) then
                    d.tried=true
                    say(r,'即将 请求原生黑魔伤重生技能')
                    local ok,started=call(input,'TryActivateExternalActionAbilityByTag',{TagName=fname(REBORN)},nil,-5)
                    if ok and started==true and o.current(r) then
                        s.manualSpent=true
                        if count(asc,COOLDOWN)==0 then apply(asc,cd,1) end
                        say(r,'重生请求被接受 冷却读回='..tostring(count(asc,COOLDOWN)))
                    end
                end
            end
            return true
        end
        d.done=true
        say(r,'重生等待结束 HP='..hp..' 冷却='..tostring(count(asc,COOLDOWN)))
        return false
    end
    function self:remaining(r) return state(r).remaining end
    function self:stop(r)
        local s=records[r]
        local d=s and s.drink
        if d and o.current(r) and readPosition(d.anim,d.montage) then
            local _,ownerAnim=call(U.field(r.actor,'Mesh'),'GetAnimInstance')
            if U.key(ownerAnim)==U.key(d.anim) then
                say(r,'即将 停止此魂未结束的喝药动作')
                call(d.anim,'Montage_Stop',0.1,d.montage)
                say(r,'喝药停止读回 已停止='..tostring(readPosition(d.anim,d.montage)==nil))
            end
            if r.intent and r.intent.busyUntil==d.busyUntil then r.intent.busyUntil=0 end
        end
        records[r]=nil
    end
    return self
end
return Supply
