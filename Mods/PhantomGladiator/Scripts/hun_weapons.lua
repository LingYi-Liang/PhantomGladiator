-- Experimental weapons of the owned Hun body (BP_Monster_Hun), scheduled by hun_body.lua on the same records.
-- Only that instance's weapons component, ability system and attribute set are written; weapon configs and ability
-- classes are shared assets and only referenced. Each low-confidence native call is preceded by a "即将" line and read
-- back; a step that does not read back is undone (the body goes back to its own weapon, slot 0) and read back again.
-- Change Weapon (BPL_PBZCombatUtils) = SetCurrentWeapon -> (true) SetArmed -> StartChangeWeaponCooldown ->
-- ModifyCharacterAttributeValue(Shachi, Override, Shachi_Max) (weapon-switch/BPL_PBZCombatUtils, Change Weapon [180-614]).
-- The light-attack chains come from hun_weapon_combos.lua (exported from the decoded input maps).
local U=require('ue_observe')
local Vitals=require('hun_vitals')
local Rotation=require('hun_weapon_rotation')
local Weapons={}
-- Switches of the weapon steps (this file is the only place they live).
Weapons.STEPS={
    enabled=true,          -- the whole weapon step (3-1 … 3-8)
    restart=true,          -- precondition: CharacterWeaponsComponent:OnRestarted(body) when its fields read empty
    slot=true,             -- 3-1 SetSlotWeapon into Weapon.Slot.Main index 1
    -- slotWeapons optionally selects the fixed three-weapon diagnostic used by beta-19.
    switch=true,           -- 3-2 switch on break or Shachi < 20 % with the cooldown done
    forceSwitchAt=false,      -- 3-2 seconds after the battle starts for one forced switch; false = off
    utilsFirst=true,       -- 3-2 the game's Change Weapon first, the four steps in Lua when it does not read back
    combo=true,            -- 3-3 Lua pushes the light-attack chain while a slot-1 weapon is current
    probe=true,            -- 3-4 / 3-5 read-only: locomotion layers, hit-react config, weapon tags
    grab=true,             -- 3-6 the slot-1 weapon's grab (DualHook GEx / ZhanMa C) by spec handle
    victimGrab=true,      -- 3-8 a broken body asks its opponent for a grab
}
local PLAYER='/PBZCombatAsset/ActorData/Players/Hun/'
Weapons.LIST={
    Tang={label='唐刀',config=PLAYER..'Weapon/Tang/Weapon_Hun_Tang.Weapon_Hun_Tang',prefix='GA_Hun_Tang_',
        tags={'Weapon.Type.TangBlade.Default','Weapon.Type.Global.SingleHanded'}},
    DualHook={label='别离残钩',config=PLAYER..'Weapon/DualHook/Weapon_Hun_DualHook.Weapon_Hun_DualHook',prefix='GA_Hun_DualHook_',
        tags={'Weapon.Type.DualHook','Weapon.Type.Global.DualHanded'},
        grab=PLAYER..'Abilities/DualHook/Default/GA_Hun_DualHook_GEx.GA_Hun_DualHook_GEx_C'},
    ZhanMa={label='斩马刀',config=PLAYER..'Weapon/ZhanMaBlade/Weapon_Hun_ZhanMaBlade.Weapon_Hun_ZhanMaBlade',prefix='GA_Hun_ZhanMa_',
        tags={'Weapon.Type.ZhanMaBlade','Weapon.Type.Global.TwoHanded'},
        grab=PLAYER..'Abilities/ZhanMaBlade/GA_Hun_ZhanMa_C.GA_Hun_ZhanMa_C_C',grabNeeds='CharacterType.Humanoid'},
}
Weapons.PATHS={
    utils='/PBZCombatAsset/Prototypes/BPL_PBZCombatUtils.Default__BPL_PBZCombatUtils_C',
    utilsClass='/PBZCombatAsset/Prototypes/BPL_PBZCombatUtils.BPL_PBZCombatUtils_C',
    light='/PBZInput/InputActions/IA_AttackL_Press.IA_AttackL_Press',
    heavy='/PBZInput/InputActions/IA_AttackH_Press.IA_AttackH_Press',
}
local MAIN='Weapon.Slot.Main'
local OWN=0                -- the body's own weapon (绝影) in the main slot
local NEW=1                -- the slot this module fills
local LOOP_MS=200          -- the fight loop period; also the combo rate limit
local COOLDOWN=15          -- Change Weapon Cooldown of every player weapon config (weapon-switch/config-summary.txt)
local LOW_SHACHI=0.2
local RANGE=400            -- cm: an opponent this close counts as in attack range
local GRAB_RANGE=500
local VICTIM_RANGE=600
local GRAB_EVERY=8         -- seconds between two grab attempts of one body
local GRAB_MAX=6           -- grab attempts per body
local COMBO_GIVE_UP=15     -- combo attempts in a row without a start before the body goes back to its own weapon
local FIRST_MOVE_WAIT=3   -- give a newly equipped weapon a turn, even when its native switch cooldown is zero
local STAT_EVERY=5         -- seconds between two combo statistics lines of one weapon
local MAX_STAT_LINES=40    -- combo statistics lines in a load
local MAX_SPECS=512
local RECHECK_AFTER=1      -- seconds after a switch for its second readback
local GRAB_READS={0.4,1.5} -- seconds after a grab for the target's grab-state readback
local BUSY={'CharacterState.Dead','Ability.Action.Execution','Ability.Executed','CharacterState.HitReact.State.Executing',
    'CharacterState.Hitreact.Phase.Act','CharacterState.Hitreact.State.Frozen','CharacterState.Unselectable.Force.Perform','Ability.Action.Hun.HeiMoShang.Reborn'}
Weapons.LIMIT=2
local LABELS={slot='装武器',switch='换武器',combo='新武器出招',grab='魂用投技',victim='请对手出投技'}

local function call(o,m,...)
    if not U.valid(o)then return false end
    local a,n={...},select('#',...);local ok,value=pcall(function()return o[m](o,table.unpack(a,1,n))end)
    return ok,U.unwrap(value)
end
local function name(o)local ok,n=call(o,'GetFullName');return ok and type(n)=='string'and n or nil end
local function short(o)
    if not U.valid(o)then return'无'end
    local n=name(o);return n and(n:match('[%.:]([^%.:]+)$')or n)or'?'
end
local function path(o)local n=name(o);return n and n:match('^%S+ (/.+)$')end
-- An ability spec holds the class default object: Default__GA_X_C reads as GA_X_C.
local function abilityName(o)return(short(o):gsub('^Default__',''))end
local function weak(value)
    value=U.unwrap(value)
    if U.valid(value)then return value end
    local ok,object=pcall(function()return value:Get()end)
    return ok and U.valid(object)and object or nil
end
-- The UObject behind a TScriptInterface value as UE4SS hands it over (object, {ObjectPointer=…} or :GetObject()).
local function iface(value)
    value=U.unwrap(value)
    if U.valid(value)then return value end
    local p=U.struct(value,'ObjectPointer');if U.valid(p)then return p end
    local ok,object=pcall(function()return value:GetObject()end)
    return ok and U.valid(object)and object or nil
end
local function currentWeapon(w)return w.selected or w.active or Weapons.LIST[w.weapon] end
local function num(v)return type(v)=='number'and v==v and string.format('%.3g',v)or tostring(v)end
local function text(v)
    v=U.unwrap(v)
    if type(v)=='string'then return v end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string'and s or nil
end

-- Depending on the binding the getter returns an array, an FRuntimeWeaponSlotData, or no Lua value.
-- RuntimeWeaponData is the component's reflected TMap and contains the same per-slot Weapons array.
function Weapons.mainSlotCount(wc,tag)
    local function size(array)
        array=U.unwrap(array)
        if U.kind(array)=='TArray' then
            local ok,n=pcall(function()return array:GetArrayNum()end)
            if ok and type(n)=='number' and n>=0 then return n end
        end
        local list=U.array(array)
        return list and #list or nil
    end
    local _,value=call(wc,'GetSlotWeapons',tag)
    local count=size(U.struct(value,'Weapons')) or size(value)
    if count~=nil then return count,'GetSlotWeapons' end
    local map=U.field(wc,'RuntimeWeaponData')
    local ok=pcall(function()map:ForEach(function(key,row)
        if text(U.struct(key,'TagName'))==MAIN then count=size(U.struct(row,'Weapons')) end
    end)end)
    if ok and count~=nil then return count,'RuntimeWeaponData' end
    return nil,'逐槽核对'
end

function Weapons.new(o)
    local self={off={},streak={},skipped={},bodies=0,statLines=0,announced={}}
    local steps=o.steps or Weapons.STEPS
    local find=o.find or StaticFindObject
    local load=o.load or LoadAsset
    local fname=o.fname or FName
    local clock=o.clock or os.clock
    local combos=o.combos or require('hun_weapon_combos')
    local loops,alive={},true
    local function say(s)(o.log or function()end)('[HunWeapon] '..s)end
    local Timer=require('hun_combat_timer')
    local register,cancel=o.loop or LoopInGameThreadWithDelay,o.cancel or CancelDelayedAction
    local normal=Timer.new(LOOP_MS,register,cancel,clock,say)
    local staggered=Timer.new(math.floor(LOOP_MS/4),register,cancel,clock,say)
    local activeTimer,roster,slice,bodyCount=nil,nil,0,0
    local bucketSizes={0,0,0,0}
    local function once(key,line)if not self.announced[key]then self.announced[key]=true;say(line)end end
    local function object(p)
        local ok,found=pcall(find,p)
        if ok and U.valid(found)then return found end
        local loaded,value=pcall(load,p)
        if loaded and U.valid(value)then return value end
        ok,found=pcall(find,p)
        if ok and U.valid(found)then return found end
    end
    local function slotTag()return {TagName=fname(MAIN)}end
    local function tagCount(actor,tagName)
        local got,count=call(U.field(actor,'AbilitySystemComponent'),'GetGameplayTagCount',{TagName=fname(tagName)})
        return got and type(count)=='number'and count or nil
    end
    local function stat(actor,field)
        local stats=o.stats and o.stats()
        if not stats then return nil end
        local ok,value=pcall(stats.read,stats,actor,field)
        return ok and type(value)=='table'and value.current or nil
    end
    local function still(r)return o.current==nil or o.current(r)end
    local function index(wc,pending)
        local got,i=call(wc,'GetCurrentWeaponIndex',slotTag(),pending==true)
        return got and type(i)=='number'and i or nil
    end
    local function slotCount(wc)
        return Weapons.mainSlotCount(wc,slotTag())
    end
    local function slotData(wc,i)
        local out={}
        if not call(wc,'GetSlotWeapon',slotTag(),i,out)then return nil end
        return out
    end
    local function slotConfig(wc,i)local out=slotData(wc,i);return out and iface(out.WeaponConfig)end
    local function slotActors(wc,i)
        local out=slotData(wc,i)
        local list={}
        for _,a in ipairs(out and U.array(out.WeaponActors)or{})do if U.valid(a)then list[#list+1]=a end end
        return list
    end
    local function cooldown(wc)
        local got,v=call(wc,'GetCurrentChangeWeaponCooldown',slotTag())
        return got and type(v)=='number'and v or nil
    end
    -- Granted ability specs: count, how many of a name prefix, how many of the body's own double blades.
    local function specs(actor)
        local list=U.array(U.struct(U.field(U.field(actor,'AbilitySystemComponent'),'ActivatableAbilities'),'Items'))
        return list and #list<=MAX_SPECS and list or nil
    end
    local function specSummary(actor,prefix)
        local list=specs(actor)
        if not list then return {count=nil,mine=0,double=0}end
        local mine,double=0,0
        for _,spec in ipairs(list)do
            local n=abilityName(U.struct(spec,'Ability'))
            if prefix and n:sub(1,#prefix)==prefix then mine=mine+1 end
            if n:sub(1,14)=='GA_Hun_Double_'then double=double+1 end
        end
        return {count=#list,mine=mine,double=double}
    end
    local function specText(s)return tostring(s.count)..'（本武器 '..s.mine..'，双刀 '..s.double..'）'end
    -- The spec of one ability class (by path), with its handle and ActiveCount.
    local function specOf(actor,classPath,wantedHandle)
        for _,spec in ipairs(specs(actor)or{})do
            local handle=wantedHandle and U.struct(U.struct(spec,'Handle'),'Handle')
            local ability=U.struct(spec,'Ability')
            if (not wantedHandle or wantedHandle==handle) and U.valid(ability)then
                local p=path(ability)
                if p==classPath or(p and p:gsub('%.Default__','.')==classPath)then
                    return {handle=handle or U.struct(U.struct(spec,'Handle'),'Handle'),active=U.struct(spec,'ActiveCount'),name=abilityName(ability),ability=ability}
                end
            end
        end
    end
    local function owned(actor,list,r)
        local key=U.key(r.actor)
        if not key then return end
        for _,a in ipairs(list)do
            local _,owner=call(a,'GetOwner')
            if U.key(owner)==key then
                local k=U.key(a)
                local fullName=name(a)
                if k and fullName then r.wep.spawned[k]={actor=a,name=fullName} end
            end
        end
    end
    local function attachText(list)
        local parts={}
        for _,a in ipairs(list)do
            local _,parent=call(a,'GetAttachParentActor')
            local _,socket=call(a,'GetAttachParentSocketName')
            parts[#parts+1]=short(a)..'@'..short(parent)..':'..tostring(text(socket)or'?')
        end
        return table.concat(parts,',')
    end
    local function record(step,passed)
        if passed then self.streak[step]=0
        else
            self.streak[step]=(self.streak[step]or 0)+1
            if self.streak[step]>=Weapons.LIMIT and not self.off[step]then
                self.off[step]=true
                say('已停用 '..LABELS[step]..'：连续 '..self.streak[step]..' 只魂失败，下次 Restart All Mods 恢复')
            end
        end
    end
    local function usable(step,r)
        if steps[step]==false or not steps.enabled then return false end
        if self.off[step]then
            if not self.skipped[step]then self.skipped[step]=true;say(LABELS[step]..' 本次加载已停用，之后的魂都跳过（实例='..r.name..'）')end
            return false
        end
        return true
    end

    ---- Precondition: the ability input component and the weapons component reach the ability system.
    local function precheck(r)
        local actor=r.actor
        local aic=U.field(actor,'Ability Input Component')
        local wc=U.field(actor,'Character Weapons Component')
        local function state()
            return U.valid(U.field(aic,'AbilitySystem')),weak(U.field(wc,'AbilitySystem'))~=nil,weak(U.field(wc,'AbilityInput'))~=nil
        end
        local a,b,c=state()
        say('前提 读回 实例='..r.name..' AbilityInputComponent有效='..tostring(U.valid(aic))..' 其AbilitySystem有效='..tostring(a)
            ..' 武器组件有效='..tostring(U.valid(wc))..' 其AbilitySystem有效='..tostring(b)..' 其AbilityInput有效='..tostring(c))
        if a and b and c then return aic,wc end
        if steps.restart and U.valid(wc)and still(r)then
            say('即将 武器组件 OnRestarted(魂) 实例='..r.name..'（前提字段为空，原生在这里填字段）')
            local called=call(wc,'OnRestarted',actor)
            a,b,c=state()
            say('OnRestarted 读回 实例='..r.name..' 调用='..tostring(called==true)..' AbilityInputComponent.AbilitySystem有效='..tostring(a)
                ..' 武器组件.AbilitySystem有效='..tostring(b)..' 武器组件.AbilityInput有效='..tostring(c))
            if a and b and c then return aic,wc end
        end
        local why={}
        if not a then why[#why+1]='AbilityInputComponent.AbilitySystem 无效'end
        if not b then why[#why+1]='武器组件.AbilitySystem 无效'end
        if not c then why[#why+1]='武器组件.AbilityInput 无效'end
        say('跳过整个武器步骤 实例='..r.name..' 原因='..table.concat(why,'、'))
        return nil
    end

    ---- 3-1: a player weapon config into Weapon.Slot.Main index 1.
    local function slotStep(r,wc,weapon)
        local cfg=object(weapon.config)
        if not cfg then say('装武器 实例='..r.name..'；'..weapon.label..'配置没载入，不装');return false end
        local before=slotCount(wc)
        if before==nil then say('装武器 实例='..r.name..'；读不到主槽，不装');return false end
        if before>NEW then
            local present=slotConfig(wc,NEW)
            say('装武器 实例='..r.name..'；主槽已有 '..before..' 把（序号'..NEW..'='..short(present)..'），不覆盖')
            return U.key(present)==U.key(cfg)
        end
        local actor=r.actor
        local specBefore=specSummary(actor,weapon.prefix)
        local bindings=U.array(U.field(U.field(actor,'Ability Input Component'),'InputBindings'))
        local bindingsBefore=bindings and #bindings or nil
        local attempts={}
        local order=self.ifaceMode=='pointer'and{'pointer','direct'}or{'direct','pointer'}
        local count,mode=before,nil
        for _,how in ipairs(order)do
            if not still(r)then attempts[#attempts+1]=how..'：实例已变化，不写';break end
            local value=how=='direct'and cfg or{ObjectPointer=cfg}
            say('即将 装武器 实例='..r.name..' 武器组件:SetSlotWeapon(Main,'..NEW..','..short(cfg)..') 传参='..(how=='direct'and'直接传对象'or'{ObjectPointer=配置}'))
            local called,err=call(wc,'SetSlotWeapon',slotTag(),NEW,value)
            count=slotCount(wc)
            attempts[#attempts+1]=(how=='direct'and'直接传对象'or'{ObjectPointer}')..' 调用='..tostring(called==true)..(called and''or'（'..tostring(err)..'）')
                ..' 槽数'..tostring(before)..'→'..tostring(count)
            if count and count>before then mode=how;break end
        end
        local got=slotConfig(wc,NEW)
        local actors=slotActors(wc,NEW)
        owned(actor,actors,r)
        local specAfter=specSummary(actor,weapon.prefix)
        bindings=U.array(U.field(U.field(actor,'Ability Input Component'),'InputBindings'))
        local verified=mode~=nil and U.key(got)==U.key(cfg)
        say('装武器 读回 实例='..r.name..' '..weapon.label..' '..table.concat(attempts,'；')..' 序号'..NEW..'配置='..short(got)
            ..' 技能数 '..specText(specBefore)..'→'..specText(specAfter)..' InputBindings '..tostring(bindingsBefore)..'→'..tostring(bindings and #bindings)
            ..' 武器Actor=['..attachText(actors)..'] verified='..tostring(verified))
        if verified then self.ifaceMode=mode;r.wep.cfg=cfg;return true end
        if count and count>before and still(r)then
            say('即将 清槽 实例='..r.name..' SetSlotWeapon(Main,'..NEW..',nil)')
            local cleared=call(wc,'SetSlotWeapon',slotTag(),NEW,nil)
            say('清槽 读回 实例='..r.name..' 调用='..tostring(cleared==true)..' 槽数='..tostring(slotCount(wc)))
        end
        self:cleanup(r,'装武器没读回')
        return false
    end

    ---- 3-4 / 3-5 read-only probes.
    local function probe(r,when)
        if not steps.probe then return end
        local actor=r.actor
        local mesh=U.field(actor,'Mesh')
        local _,graph=call(mesh,'GetLinkedAnimGraphInstanceByTag',fname('MMGraph'))
        local linked={}
        for _,item in ipairs(U.array(U.field(mesh,'LinkedInstances'))or{})do linked[#linked+1]=tostring(U.className(item))end
        say('走跑层（只读）实例='..r.name..'（'..when..'） MMGraph='..(U.valid(graph)and tostring(U.className(graph))or'无')
            ..' MMGraph.CharacterMovement有效='..tostring(U.valid(U.field(graph,'CharacterMovement')))..' 链接实例=['..table.concat(linked,'|')..']')
        local hit=U.field(actor,'Hitreact Component')
        local weapon=currentWeapon(r.wep)
        local counts={}
        for _,t in ipairs({'CharacterState.Armed','Weapon.Type.Global.DualHanded'})do counts[#counts+1]=t..'='..tostring(tagCount(actor,t))end
        for _,t in ipairs(weapon and weapon.tags or{})do counts[#counts+1]=t..'='..tostring(tagCount(actor,t))end
        say('受击表（只读）实例='..r.name..'（'..when..'） HitreactComponent有效='..tostring(U.valid(hit))..' ActorConfig='..short(iface(U.field(hit,'ActorConfig')))
            ..' HitreactStatesConfig='..short(U.field(hit,'HitreactStatesConfig'))..' 武器标签：'..table.concat(counts,' '))
    end

    ---- 3-2: switch the main slot, the game's function first, else the four steps; failure goes back to slot 0.
    local function utils()
        local cdo=object(Weapons.PATHS.utils)
        if cdo then return cdo end
        pcall(load,Weapons.PATHS.utilsClass)
        local ok,found=pcall(find,Weapons.PATHS.utils)
        return ok and U.valid(found)and found or nil
    end
    local function back(r,wc,why)
        if not still(r)then say('切回绝影 实例='..r.name..'；实例已变化，不写');return end
        say('即将 切回绝影 实例='..r.name..' SetCurrentWeapon(Main,'..OWN..') 原因='..why)
        local called=call(wc,'SetCurrentWeapon',slotTag(),OWN)
        local now=index(wc,true)
        say('切回绝影 读回 实例='..r.name..' 调用='..tostring(called==true)..' 序号='..tostring(now)..' 已切回='..tostring(now==OWN))
        r.wep.idx=now or r.wep.idx
    end
    local function switchTo(r,target,why)
        local w=r.wep;local actor=r.actor;local wc=w.wc
        local weapon=currentWeapon(w)
        local from=index(wc,false)
        local shachi,max=stat(actor,'Shachi'),stat(actor,'Shachi_Max')
        local specBefore=specSummary(actor,weapon.prefix)
        local cdBefore=cooldown(wc)
        local via,steps4
        if steps.utilsFirst and not self.utilsBroken then
            local cdo=utils()
            if cdo then
                say('即将 换武器 实例='..r.name..' BPL_PBZCombatUtils:Change Weapon(魂,Main,'..target..',Armed=true) 原因='..why)
                local called,err=call(cdo,'Change Weapon',actor,slotTag(),target,true,actor)
                local now=index(wc,true)
                if called and now==target then via='原版 Change Weapon'
                else
                    say('原版 Change Weapon 读回 实例='..r.name..' 调用='..tostring(called==true)..(called and''or'（'..tostring(err)..'）')..' 序号='..tostring(now)..'，改用 Lua 四步')
                    if not called then self.utilsBroken=true end
                end
            else
                once('noUtils','找不到 BPL_PBZCombatUtils 默认对象，换武器用 Lua 四步')
            end
        end
        if not via then
            if not still(r)then say('换武器 实例='..r.name..'；实例已变化，不写');return false end
            local parts={}
            say('即将 换武器 四步 1/4 实例='..r.name..' SetCurrentWeapon(Main,'..target..') 原因='..why)
            local s1=call(wc,'SetCurrentWeapon',slotTag(),target)
            local i1=index(wc,true)
            parts[#parts+1]='SetCurrentWeapon 调用='..tostring(s1==true)..' 序号='..tostring(i1)
            local ok=s1==true and i1==target
            if ok then
                local s2=call(wc,'SetArmed',slotTag(),true)
                local _,armed=call(wc,'IsArmed',slotTag())
                parts[#parts+1]='SetArmed 调用='..tostring(s2==true)..' 读回='..tostring(armed)
                ok=s2==true and armed~=false
            end
            if ok then
                local s3=call(wc,'StartChangeWeaponCooldown',slotTag(),target)
                parts[#parts+1]='StartChangeWeaponCooldown 调用='..tostring(s3==true)..' 冷却='..num(cooldown(wc))
                ok=s3==true
            end
            if ok then
                local stats=o.stats and o.stats()
                local wrote=false
                if stats and type(max)=='number'then wrote=pcall(stats.writeBase,stats,actor,'Shachi',max)end
                local after=stat(actor,'Shachi')
                local full=type(after)=='number'and type(max)=='number'and math.abs(after-max)<=math.max(1e-3,math.abs(max)*1e-4)
                parts[#parts+1]='杀气 Override 写入='..tostring(wrote)..' '..num(shachi)..'→'..num(after)..'（上限 '..num(max)..'）'
                ok=wrote and full
            end
            steps4=table.concat(parts,'；')
            if not ok then
                say('换武器 四步 读回 实例='..r.name..' '..steps4..' verified=false')
                if not w.rotation and target~=OWN then back(r,wc,'四步没读回')end
                return false
            end
            via='Lua 四步'
        end
        w.idx=target;w.lastSwitch=clock();w.switches=(w.switches or 0)+1;w.recheckAt=clock()+RECHECK_AFTER
        w.tagMap=nil;w.comboFails=0
        local actors=slotActors(wc,target)
        if w.rotation or target==NEW then owned(actor,actors,r)end
        local oldActors=slotActors(wc,from or OWN)
        local after=stat(actor,'Shachi')
        local specAfter=specSummary(actor,weapon.prefix)
        say('换武器 读回 实例='..r.name..' 方式='..via..(steps4 and('（'..steps4..'）')or'')..' 序号 '..tostring(from)..'→'..tostring(index(wc,false))
            ..'（含待定 '..tostring(index(wc,true))..'） 新武器Actor=['..attachText(actors)..'] 原武器Actor=['..attachText(oldActors)..']'
            ..' 技能数 '..specText(specBefore)..'→'..specText(specAfter)..' 杀气 '..num(shachi)..'→'..num(after)..'（上限 '..num(max)..'）'
            ..' 原生冷却 '..num(cdBefore)..'→'..num(cooldown(wc))..'（Lua 冷却 '..COOLDOWN..' 秒） 原因='..why..' verified=true')
        pcall(probe,r,'换到序号'..target..'后')
        return true
    end

    ---- 3-3: one light-attack push from the current weapon's chain.
    local function tagMap(r,list)
        if r.wep.tagMap then return r.wep.tagMap end
        -- Several specs can carry one tag (the body's own GA_Hun_Double_* and the slotted weapon's); the current
        -- weapon's prefix wins.
        local map={}
        local prefix=currentWeapon(r.wep).prefix
        local exact={}
        if r.wep.rotation then
            local cfg=r.wep.currentConfig
            for i,cls in ipairs(U.array(U.field(cfg,'Equip Abilities')) or {})do
                local key=path(cls)
                if key then exact[key:lower()]={class=cls,rank=i} end
            end
        end
        for index,spec in ipairs(list or specs(r.actor) or {})do
            local ability=U.struct(spec,'Ability')
            local n_=abilityName(ability)
            local abilityPath=(path(ability) or ''):gsub('%.Default__','.')
            local equipped=exact[abilityPath:lower()]
            local rank=equipped and equipped.rank
            local mine=rank~=nil or (not r.wep.rotation and n_:sub(1,#prefix)==prefix)
            local container=U.field(ability,'AbilityTags')
            for _,t in ipairs(U.array(U.struct(container,'GameplayTags'))or{})do
                local n=text(U.struct(t,'TagName'))
                if n and(not map[n]or mine and (not map[n].mine or rank and rank<(map[n].rank or math.huge)))then
                    map[n]={handle=U.struct(U.struct(spec,'Handle'),'Handle'),name=n_,mine=mine,rank=rank,cls=abilityPath,
                        class=equipped and equipped.class,index=index,abilityKey=U.key(ability)}
                end
            end
        end
        r.wep.tagMap=map
        return map
    end
    local function matches(actor,entry,cache)
        local function count(t)if cache[t]==nil then cache[t]=tagCount(actor,t) or false end;return cache[t]end
        for _,t in ipairs(entry.req)do local n=count(t);if not n or n<=0 then return false end end
        for _,t in ipairs(entry.ign)do if count(t)~=0 then return false end end
        return true
    end
    local function nextTag(r,chain,cache,performing,resolve)
        local function first(rows,kind)
            for _,entry in ipairs(rows) do
                if (kind~='连段' or entry.tag~=r.wep.skipTag) and matches(r.actor,entry,cache) then
                    if not resolve then return entry.tag,kind end
                    local granted,active=resolve(entry.tag)
                    if granted then return entry.tag,kind,granted,active end
                end
            end
        end
        local tag,kind,granted,active=first(chain.combos,'连段')
        if tag or performing then return tag,kind,granted,active end
        return first(chain.actions,'起手')
    end
    local function montage(actor)
        local _,instance=call(U.field(actor,'Mesh'),'GetAnimInstance')
        local _,m=call(instance,'GetCurrentActiveMontage')
        return short(m)
    end
    local function comboStats(r,weapon,s,force)
        local t=clock()
        if self.statLines>=MAX_STAT_LINES then return end
        if not force and t-(s.lastLine or-math.huge)<STAT_EVERY then return end
        if s.lineTries==s.tries and not force then return end
        s.lastLine=t;s.lineTries=s.tries;self.statLines=self.statLines+1
        say('出招统计 实例='..r.name..' '..weapon.label..' 尝试='..s.tries..' 成功='..s.ok..'（按标签 '..s.byTag..'，按句柄 '..s.byHandle..'，原生输入接招 '..(s.byInput or 0)..'）'
            ..' 对手掉血='..s.hits..' 最近招='..tostring(s.lastTag)..' 最近蒙太奇='..tostring(s.lastMontage)
            ..(self.statLines>=MAX_STAT_LINES and'（本次加载统计行已到上限）'or''))
    end
    local function matchesTarget(actor,target)
        if not o.nativeTarget then return true end
        local key=U.key(target)
        if not key then return false end
        local ok,actual=pcall(o.nativeTarget,actor)
        return ok and U.key(actual)==key
    end
    local function comboActive(actor,entry)
        local items=U.struct(U.field(U.field(actor,'AbilitySystemComponent'),'ActivatableAbilities'),'Items')
        local ok,row=pcall(function()return U.unwrap(items[entry.index])end)
        if ok and U.struct(U.struct(row,'Handle'),'Handle')==entry.handle and U.key(U.struct(row,'Ability'))==entry.abilityKey then
            return U.struct(row,'ActiveCount')
        end
        local spec=specOf(actor,entry.cls,entry.handle)
        if spec and U.key(spec.ability)==entry.abilityKey then return spec.active end
    end
    local function combo(r,target,performing,canChain)
        if performing and not canChain then return end
        local w=r.wep;local actor=r.actor
        local weapon=currentWeapon(w)
        local heavy=w.rotation and (tagCount(target,'CharacterState.Stand.Break') or 0)>0
        local aic=U.field(actor,'Ability Input Component')
        local list,map,missing,positions
        local function resolve(tag)
            if not list then list=specs(actor) or {};map=tagMap(r,list) end
            local entry=map[tag]
            if entry and entry.mine and entry.abilityKey and type(entry.handle)=='number' and entry.handle>0 then
                local row=list[entry.index]
                if U.struct(U.struct(row,'Handle'),'Handle')~=entry.handle then
                    -- GAS can reorder the array without changing the grant. Build the index
                    -- only on that path; never retain a row across native calls.
                    if not positions then
                        positions={}
                        for i,live in ipairs(list) do
                            local handle=U.struct(U.struct(live,'Handle'),'Handle')
                            if type(handle)=='number' then positions[handle]=i end
                        end
                    end
                    entry.index=positions[entry.handle];row=list[entry.index]
                end
                if row and U.key(U.struct(row,'Ability'))==entry.abilityKey then
                    return entry,U.struct(row,'ActiveCount')
                end
            end
            missing=missing or tag
        end
        local counts={}
        local function selectInput(useHeavy)
            local priority=useHeavy and 2 or 1
            local got,gate=call(aic,'CanActivateExternalActionAbility',priority)
            if (w.rotation and (not got or gate~=true)) or gate==false then return end
            local chain=w.rotation and Rotation.chain(weapon,useHeavy) or combos[w.weapon]
            if not chain then return end
            local tag,kind,entry,active=nextTag(r,chain,counts,performing,w.rotation and resolve)
            if not tag then return end
            if entry and active~=0 then return tag,kind,entry,active end
            local input=object(useHeavy and Weapons.PATHS.heavy or Weapons.PATHS.light)
            if input then return tag,kind,entry,active,priority,input end
        end
        once('canActivate','即将 只读 AbilityInputComponent:CanActivateExternalActionAbility（本次加载第一次）')
        local tag,kind,exact,active,priority,ia=selectInput(heavy)
        if not tag and heavy then tag,kind,exact,active,priority,ia=selectInput(false) end
        if missing and clock()>=(w.nextMapRead or 0) then
            w.tagMap=nil;w.nextMapRead=clock()+1
            once('missing-combo:'..weapon.config..missing,'当前武器跳过未授予的连段 '..weapon.label..' '..missing)
        end
        if not tag or not ia or (exact and (active~=0 or comboActive(actor,exact)~=0)) then return end
        if not still(r) or not matchesTarget(actor,target) then return end
        w.stats[w.weapon]=w.stats[w.weapon]or{tries=0,ok=0,byTag=0,byHandle=0,hits=0}
        local s=w.stats[w.weapon]
        s.tries=s.tries+1;s.lastTag=tag
        if exact then once('exactCombo','即将按本武器授予的具体技能句柄出招 '..exact.name)
        else once(heavy and 'heavyByTag' or 'byTag','即将 AbilityInputComponent:TryActivateExternalActionAbilityByTag(标签,'..(heavy and 'IA_AttackH_Press' or 'IA_AttackL_Press')..','..priority..')（本次加载第一次，之后不再逐次写）')end
        local before=tagCount(actor,tag)or 0
        local called,result
        if exact and performing then
            if not U.valid(exact.class) then return end
            called,result=call(aic,'TryActivateExternalActionAbilityByClass',exact.class,ia,priority)
        elseif exact then
            called,result=call(U.field(actor,'AbilitySystemComponent'),'TryActivateAbility',{Handle=exact.handle},false)
        else
            called,result=call(aic,'TryActivateExternalActionAbilityByTag',{TagName=fname(tag)},ia,priority)
        end
        local after=tagCount(actor,tag)or 0
        local started=after>before or(result==true and after>0)
        local how='标签'
        if exact then
            local count=comboActive(actor,exact)
            started=called and result~=false and type(count)=='number' and count>0
            how=performing and '原生输入' or '句柄'
            s.lastClass=exact.name
        elseif not started then
            local spec=tagMap(r)[tag]
            if spec and spec.mine and type(spec.handle)=='number'then
                once('byHandle','即将 AbilitySystemComponent:TryActivateAbility(句柄)（出招备选，本次加载第一次）')
                local asc=U.field(actor,'AbilitySystemComponent')
                local ok2,res2=call(asc,'TryActivateAbility',{Handle=spec.handle},false)
                local again=tagCount(actor,tag)or 0
                started=again>before or(ok2 and res2==true)
                how='句柄'
            end
        end
        if started then
            w.firstMoveUntil=nil
            w.chainCount=(w.chainCount or 0)+1
            s.ok=s.ok+1
            if how=='标签' then s.byTag=s.byTag+1
            elseif how=='原生输入' then s.byInput=(s.byInput or 0)+1
            else s.byHandle=s.byHandle+1 end
            s.lastMontage=montage(actor);w.comboFails=0;w.skipTag=nil
            if target and #w.pending<4 then w.pending[#w.pending+1]={weapon=w.weapon,target=target,hp=o.hp and select(2,pcall(o.hp,target)),at=clock()}end
        elseif not (exact and performing) then
            w.comboFails=(w.comboFails or 0)+1;w.skipTag=kind=='连段'and tag or nil
        end
        if not w.comboFirst then
            w.comboFirst=true
            say('出招 第一次 实例='..r.name..' '..weapon.label..' 标签='..tag..'（'..kind..'） 调用='..tostring(called==true)..' 技能类='..tostring(s.lastClass)..' 返回='..tostring(result)
                ..' 标签计数 '..before..'→'..after..' 方式='..how..' 启动='..tostring(started)..' 蒙太奇='..montage(actor))
        end
        if started and not w.comboRecorded then w.comboRecorded=true;record('combo',true)end
        comboStats(r,weapon,s,false)
        if (w.comboFails or 0)>=COMBO_GIVE_UP then
            say('新武器出招不通 实例='..r.name..' '..weapon.label..' 连续 '..w.comboFails..' 次没启动，切回绝影（原生招式池恢复有效）')
            comboStats(r,weapon,s,true)
            if not w.comboRecorded then w.comboRecorded=true;if not w.rotation then record('combo',false) end end
            if w.rotation then
                w.rotation.failures[w.currentId]=2
                w.retrySwitch=true
                w.comboOff=true
                say('本局剔除武器 '..weapon.label..'；下一次换武器重新选取')
            else
                w.comboOff=true
                back(r,w.wc,'新武器出招不通')
            end
        end
    end
    local function settleHits(r)
        local w=r.wep;local t=clock();local keep={}
        for _,p in ipairs(w.pending)do
            if t-p.at>=0.8 then
                if U.valid(p.target)and type(p.hp)=='number'and o.hp then
                    local ok,hp=pcall(o.hp,p.target)
                    if ok and type(hp)=='number'and hp<p.hp then local s=w.stats[p.weapon];if s then s.hits=s.hits+1 end end
                end
            else keep[#keep+1]=p end
        end
        w.pending=keep
    end

    ---- 3-6: the slot-1 weapon's grab by spec handle.
    local function grabState(actor)
        return 'Ability.Executed='..tostring(tagCount(actor,'Ability.Executed'))..' Executing='..tostring(tagCount(actor,'CharacterState.HitReact.State.Executing'))
            ..' 蒙太奇='..montage(actor)
    end
    local activateArt
    local function grab(r,target)
        local w=r.wep;local actor=r.actor
        local weapon=currentWeapon(w)
        w.grabAt=clock();w.grabs=(w.grabs or 0)+1
        local spec=specOf(actor,weapon.grab)
        if not spec then
            say('魂用投技 实例='..r.name..' '..weapon.label..'；技能 '..weapon.grab:match('([^%.]+)$')..' 没授予（spec 不在）')
            if not w.grabRecorded then w.grabRecorded=true;if not w.rotation then record('grab',false) end end
            return
        end
        if spec.active~=0 or type(spec.handle)~='number'then return end
        if not still(r)then return end
        if weapon.grabNeeds and (tagCount(target,weapon.grabNeeds) or 0)==0 then return end
        local needs=weapon.grabNeeds and(' 目标 '..weapon.grabNeeds..'='..tostring(tagCount(target,weapon.grabNeeds)))or''
        local asc=U.field(actor,'AbilitySystemComponent')
        say('即将 魂用投技 实例='..r.name..' '..spec.name..' AbilitySystemComponent:TryActivateAbility(句柄='..spec.handle..') 目标='..short(target)..needs)
        local called,result
        if w.rotation and weapon.grab==weapon.art then called=true;result=activateArt(r,weapon,spec,target)
        else called,result=call(asc,'TryActivateAbility',{Handle=spec.handle},false) end
        local after=specOf(actor,weapon.grab)
        local started=called and after~=nil and type(after.active)=='number'and after.active>0
        say('魂用投技 读回 实例='..r.name..' '..spec.name..' 调用='..tostring(called==true)..' 返回='..tostring(result)..' ActiveCount '..tostring(spec.active)
            ..'→'..tostring(after and after.active)..' 启动='..tostring(started)..' 目标 '..grabState(target))
        if not w.grabRecorded then w.grabRecorded=true;if not w.rotation then record('grab',started) end end
        if started then
            w.firstMoveUntil=nil
            for _,d in ipairs(GRAB_READS)do w.grabReads[#w.grabReads+1]={target=target,at=clock()+d,label='+'..d..'s'}end
        end
    end
    local function grabReads(r)
        local w=r.wep;local t=clock();local keep={}
        for _,g in ipairs(w.grabReads)do
            if t>=g.at then
                if U.valid(g.target)then say('魂用投技 目标读回 实例='..r.name..' '..g.label..' 目标='..short(g.target)..' '..grabState(g.target))end
            else keep[#keep+1]=g end
        end
        w.grabReads=keep
    end

    ---- 3-8: a broken body asks its opponent for a grab (off by default).
    local function victim(r,target)
        local w=r.wep
        local _,playerControlled=call(target,'IsPlayerControlled')
        if playerControlled==true or (name(target) or ''):find('BP_Renewal_Hun_C',1,true) then return end
        if o.qteFamily and o.qteFamily(target)then
            once('victimQTE'..tostring(U.key(target)),'请对手出投技 实例='..r.name..' 对手='..short(target)..' 是 QTE 族，按 QTE 闸不请')
            return
        end
        local chosen
        for _,spec in ipairs(specs(target)or{})do
            local ability=U.struct(spec,'Ability')
            local n=abilityName(ability)
            if n:lower():find('_gex')and U.struct(spec,'ActiveCount')==0 then
                chosen={handle=U.struct(U.struct(spec,'Handle'),'Handle'),name=n,cls=path(ability)};break
            end
        end
        w.victimAsked=true
        if not chosen or type(chosen.handle)~='number'then say('请对手出投技 实例='..r.name..' 对手='..short(target)..'；没有空闲的 GEx 技能');return end
        local asc=U.field(target,'AbilitySystemComponent')
        say('即将 请对手出投技 实例='..r.name..' 对手='..short(target)..' '..chosen.name..' TryActivateAbility(句柄='..chosen.handle..')')
        local called,result=call(asc,'TryActivateAbility',{Handle=chosen.handle},false)
        local after=chosen.cls and specOf(target,chosen.cls)
        local started=called and after~=nil and type(after.active)=='number'and after.active>0
        say('请对手出投技 读回 实例='..r.name..' '..chosen.name..' 调用='..tostring(called==true)..' 返回='..tostring(result)..' ActiveCount 0→'
            ..tostring(after and after.active)..' 启动='..tostring(started)..' 魂 '..grabState(r.actor))
        record('victim',started)
    end

    ---- The fight loop of one body, every LOOP_MS.
    local function nearest(r,range)
        local best,bestD
        local native
        if o.nativeTarget then
            local ok,target=pcall(o.nativeTarget,r.actor)
            native=ok and U.key(target)
            if not native then return nil end
        end
        local _,me=call(r.actor,'K2_GetActorLocation')
        local mx,my,mz=U.struct(me,'X'),U.struct(me,'Y'),U.struct(me,'Z')
        if type(mx)~='number' or type(my)~='number' or (mz~=nil and type(mz)~='number') then return nil end
        for _,a in ipairs(o.opponents and o.opponents(r)or{})do
            if U.valid(a) and (not native or U.key(a)==native) then
                local alive=true
                if o.hp then local ok,hp=pcall(o.hp,a);alive=ok and type(hp)=='number' and hp>0 and hp<math.huge end
                local _,at=call(a,'K2_GetActorLocation')
                local x,y,z=U.struct(at,'X'),U.struct(at,'Y'),U.struct(at,'Z')
                if alive and type(x)=='number' and type(y)=='number' and (z==nil or type(z)=='number') then
                    local d=math.sqrt((x-mx)^2+(y-my)^2+((z or 0)-(mz or 0))^2)
                    if d<=range and(not bestD or d<bestD)then best,bestD=a,d end
                end
            end
        end
        return best,bestD
    end
    local function setInactive(r,idx,cfg)
        local w=r.wep
        if not still(r) or index(w.wc,false)==idx then return false end
        if U.key(slotConfig(w.wc,idx))==U.key(cfg) then return true end
        local forms=self.ifaceMode=='pointer' and {'pointer','direct'} or {'direct','pointer'}
        for _,form in ipairs(forms) do
            if not still(r) or index(w.wc,false)==idx then return false end
            say('即将 填非当前武器槽 实例='..r.name..' 槽='..idx..' 配置='..short(cfg)..' 传参='..form)
            local value=form=='direct' and cfg or {ObjectPointer=cfg}
            call(w.wc,'SetSlotWeapon',slotTag(),idx,value)
            local actual=slotConfig(w.wc,idx)
            say('填槽 读回 实例='..r.name..' 槽='..idx..' 配置='..short(actual))
            if U.key(actual)==U.key(cfg) then
                self.ifaceMode=form
                owned(r.actor,slotActors(w.wc,idx),r)
                return true
            end
        end
        return false
    end
    local function failedPick(r,item,t,why)
        local s=r.wep.rotation
        s.failures[item.id]=(s.failures[item.id] or 0)+1
        s.retryAt=t+2
        say('换武器失败 实例='..r.name..' 武器='..item.label..' 原因='..why..
            ' 失败数='..s.failures[item.id]..(s.failures[item.id]>=2 and ' 本局剔除' or ''))
    end
    local POWER_HOOK='/PBZCombatAsset/Prototypes/Config/PBZ_MainWeaponConfig.PBZ_MainWeaponConfig_C:GetWeaponPowerMultiplier'
    local powerRecords={}
    local function ensurePowerHook()
        if self.powerHook then return end
        local register=o.register or RegisterHook
        if type(register)~='function' then return end
        local ok,pre,post=pcall(register,POWER_HOOK,function(config,avatar)
            if not alive then return end
            local actor=U.unwrap(avatar)
            local key=U.key(actor)
            local rec=key and powerRecords[key]
            if not rec or not still(rec) then return nil end
            local w=rec.wep
            if not w.active or U.key(U.unwrap(config))~=U.key(w.currentConfig) then return nil end
            return w.active.multipliers[w.active.level]
        end)
        if ok and type(pre)=='number' and type(post)=='number' then self.powerHook={pre,post}
        else once('powerHook','魂专属武器倍率回调未安装：'..tostring(pre)) end
    end
    -- The NPC template installs its movement graph as a linked layer, also when it has no MMGraph tag.
    local function alignHitReactions(r)
        local w,actor=r.wep,r.actor
        if w.hitConfigTried then return end
        w.hitConfigTried=true
        local hit=U.field(actor,'Hitreact Component')
        local _,hitOwner=call(hit,'GetOwner')
        local original=iface(U.field(hit,'ActorConfig'))
        local _,class=call(original,'GetClass')
        local construct=o.construct or StaticConstructObject
        local combined=object(PLAYER..'Hit_Hun_Combined.Hit_Hun_Combined')
        if not U.valid(original) or not combined or not U.valid(class) or type(construct)~='function' or
            U.key(hitOwner)~=U.key(actor) or not still(r) then return end
        say('即将 建立魂私有受击配置 '..r.name)
        local made,copy=pcall(construct,class,hit,fname('PG_HunHit_'..self.bodies),0x40,0,false,false,original)
        local _,outer=call(copy,'GetOuter')
        local _,copyClass=call(copy,'GetClass')
        if not made or not U.valid(copy) or U.key(copy)==U.key(original) or U.key(outer)~=U.key(hit)
            or U.key(copyClass)~=U.key(class) then return end
        local field='Hitreat Anim Set'
        local prior=U.field(copy,field)
        if not U.valid(prior) then return end
        say('即将 替换魂私有受击动作集 '..r.name)
        local wrote=pcall(function()copy[field]=combined end)
        if not wrote or U.key(U.field(copy,field))~=U.key(combined) then return end
        local function assign(obj)
            local ok=pcall(function()hit.ActorConfig=obj end)
            if not ok or U.key(iface(U.field(hit,'ActorConfig')))~=U.key(obj) then
                pcall(function()hit.ActorConfig={ObjectPointer=obj} end)
            end
            return U.key(iface(U.field(hit,'ActorConfig')))==U.key(obj)
        end
        say('即将 在魂受击组件挂入私有副本 '..r.name)
        if assign(copy) then
            w.hitCopy=copy;w.hitComponent=hit;w.restoreHit=function()return assign(original) end
            say('武器受击集 读回='..short(combined))
        else say('即将 还原魂受击接口 '..r.name);say('还原受击接口 读回='..tostring(assign(original))) end
    end
    local function scaleCooldown(r)
        local w=r.wep
        local scale=w.rotation.resources.cooldown_scale or 1
        local cd=cooldown(w.wc)
        if type(cd)=='number' and cd>0 then
            if scale<1 then
                say('即将 在魂武器组件缩短换武器冷却 原值='..num(cd)..' 倍率='..num(scale))
                call(w.wc,'ReduceChangeWeaponCooldown',cd*(1-scale))
                say('缩短换武器冷却 读回='..num(cooldown(w.wc)))
            end
            -- Honor a native reset or accessory reduction. An extended policy adds only the requested excess time.
            w.extraWait=scale>1 and cd*scale or 0
        else
            w.extraWait=COOLDOWN*scale
        end
    end
    local function afterSwitch(r,item,idx,cfg,now)
        local w=r.wep
        w.active,w.weapon,w.currentId,w.idx=item,item.id,item.id,idx
        w.firstMoveUntil=now+FIRST_MOVE_WAIT
        w.tagMap=nil;w.skipTag=nil;w.comboOff=false;w.comboFails=0;w.chainCount=0
        w.retrySwitch=false
        Rotation.chosen(w.rotation,item)
        scaleCooldown(r)
        Rotation.effects(w.rotation,item,U.field(r.actor,'AbilitySystemComponent'),{object=object,call=call,say=say})
        powerRecords[U.key(r.actor)]=r
        ensurePowerHook()
        local got,power=call(cfg,'GetWeaponPowerMultiplier',r.actor)
        say('武器生效读回 实例='..r.name..' 武器='..item.label..' 等级='..item.level..
            ' 铸魂='..tostring(item.soul)..' 本局次数='..w.rotation.picks[item.id]..
            ' 权重来源='..(item.grantGroup or (item.temporary and '临时武器' or '目录序估计'))..
            ' 方案攻击倍率='..item.multipliers[item.level]..' 原生读取倍率='..tostring(got and power))
        if Vitals.actionState(r.actor) then w.pendingHitConfig=item.id
        else w.pendingHitConfig=nil;alignHitReactions(r) end
    end
    local CONTROLLER='/Script/Engine.GameplayStatics:GetPlayerController'
    local activeArt,probeActor,probeCount
    local function prepareControllerGuard(r)
        if not self.controllerHook then
            local register=o.register or RegisterHook
            local created,empty=pcall(o.createInvalid or CreateInvalidObject)
            if not created or empty==nil or U.valid(empty) or type(register)~='function' then return false end
            local ok,pre,post=pcall(register,CONTROLLER,function(_,context,playerIndex)
                if not alive or (not activeArt and not probeActor) then return end
                local ctx=U.unwrap(context)
                if U.unwrap(playerIndex)~=0 then return end
                if probeActor and U.key(ctx)==U.key(probeActor) then probeCount=probeCount+1;return empty end
                if not activeArt or not U.valid(ctx) then return end
                local _,class=call(ctx,'GetClass')
                if path(class)~=activeArt.class then return end
                local _,owner=call(ctx,'GetAvatarActorFromActorInfo')
                if U.key(owner)==U.key(activeArt.actor) then return empty end
            end)
            if not ok or type(pre)~='number' or type(post)~='number' then return false end
            self.controllerHook={pre,post}
        end
        if self.guardVerified then return true end
        probeActor,probeCount=r.actor,0
        local statics=object('/Script/Engine.Default__GameplayStatics')
        local ok,result=call(statics,'GetPlayerController',probeActor,0)
        probeActor=nil
        self.guardVerified=ok and not U.valid(result) and probeCount==1
        say('魂战技手柄隔离 自检='..tostring(self.guardVerified))
        return self.guardVerified
    end
    activateArt=function(r,item,spec,target)
        if not matchesTarget(r.actor,target) or not still(r) then return false end
        -- BP_CombatArt_Base uses the controller of local player zero for haptic feedback on success.
        -- Its charge debit is synchronous and takes GetUltimateChargeCost from UltimateChargeCount.
        if not prepareControllerGuard(r) then once('noArtGuard','魂战技跳过：无法确认玩家手柄隔离');return false end
        local cost=U.field(spec.ability,'Ultimate Charge Cost')
        if type(cost)~='number' or cost<0 then return false end
        cost=math.max(1,cost)
        r.wep.artCosts=r.wep.artCosts or {}
        r.wep.artCosts[item.id]=cost
        local before=stat(r.actor,'UltimateChargeCount')
        if type(before)~='number' then return false end
        local free=r.wep.rotation.resources.consume_skill_resources==false
        local stats=o.stats and o.stats()
        local borrowed=0
        if before<cost then
            if not free or not stats then return false end
            local cap=stat(r.actor,'UltimateChargeCount_Max')
            if type(cap)~='number' or cap<cost then return false end
            say('即将 给魂垫付本次战技缺少的绝技格 '..num(cost-before))
            local ok,wrote=pcall(stats.writeBase,stats,r.actor,'UltimateChargeCount',cost)
            local read=stat(r.actor,'UltimateChargeCount')
            if type(read)=='number' then borrowed=math.max(0,read-before) end
            if not ok or wrote==false or read~=cost then
                if borrowed>0 then pcall(stats.writeBase,stats,r.actor,'UltimateChargeCount',before) end
                return false
            end
        end
        activeArt={actor=r.actor,class=item.art}
        local called,result=call(U.field(r.actor,'AbilitySystemComponent'),'TryActivateAbility',{Handle=spec.handle},false)
        activeArt=nil
        if not still(r) then return false end
        local after=specOf(r.actor,item.art,spec.handle)
        local balance=stat(r.actor,'UltimateChargeCount')
        local active=after and after.handle==spec.handle and after.active or nil
        local paid=type(balance)=='number' and math.abs(before+borrowed-balance-cost)<0.0001
        -- An accepted instant ability can finish or lose its spec before TryActivateAbility returns.
        local confirmed=paid and called and (result==true or (result~=false and type(active)=='number' and active>0))
        if free and stats and type(balance)=='number' then
            local refund=confirmed and cost or 0
            local correction=refund-borrowed
            if correction~=0 then
                local adjusted=math.max(0,balance+correction)
                say('即将 结算魂本次战技增减的绝技格 目标='..num(adjusted))
                pcall(stats.writeBase,stats,r.actor,'UltimateChargeCount',adjusted)
                say('本次战技绝技格 读回='..num(stat(r.actor,'UltimateChargeCount')))
            end
        end
        if confirmed then r.wep.firstMoveUntil=nil end
        return confirmed,active
    end
    local function phaseArt(r,t,target)
        local w,intent=r.wep,r.intent
        if not intent or not intent.phaseId or intent.performedPhase==intent.phaseId or
            not w.active or w.currentId~=intent.weapon_id or t<(w.phaseRetryAt and w.phaseRetryAt[intent.weapon_id] or 0) then return false end
        local item=w.active
        w.phaseRetryAt=w.phaseRetryAt or {}
        w.phaseRetryAt[item.id]=t+1
        if not item.art then
            once('missingArt'..item.id,'阶段战技：武器 '..item.label..' 没有识别到原生战技')
            return false
        end
        local spec=specOf(r.actor,item.art)
        if not spec or type(spec.handle)~='number' or spec.active~=0 then return false end
        say('即将 阶段战技 实例='..r.name..' 阶段='..intent.phaseId..' '..spec.name)
        local confirmed,active=activateArt(r,item,spec,target)
        if confirmed then
            intent.performedPhase=intent.phaseId
            intent.busyUntil=math.max(intent.busyUntil or 0,t+0.35)
            say('阶段战技 读回 实例='..r.name..' 阶段='..intent.phaseId..' 已确认扣费 ActiveCount='..tostring(active))
            return true
        end
        return false
    end
    local drawTag='CharacterState.Talent.EnableDrawAttack'
    local switchTag='Ability.Action.Hun.Weapon.Switch.Normal'
    local function releaseDrawTag(r)
        local w=r.wep
        if not w.drawTag or not still(r) then return end
        local lib=w.drawTag
        w.drawTag=nil
        say('即将 还原魂拔刀许可 '..r.name)
        call(lib,'RemoveLooseGameplayTag',r.actor,{TagName=fname(drawTag)},false)
        say('拔刀许可 读回='..tostring(tagCount(r.actor,drawTag)))
    end
    local function tryDraw(r,item,cfg,idx,from,why,t)
        local w=r.wep
        if not w.active then return false end
        local input=object('/PBZInput/InputActions/IA_ChangeWeapon.IA_ChangeWeapon')
        local aic=U.field(r.actor,'Ability Input Component')
        if not input or not U.valid(aic) then return false end
        local enabled=tagCount(r.actor,drawTag)
        if enabled==0 then
            local lib=object('/Script/SGameUtils.Default__AbilityUtils')
            if not lib then return false end
            say('即将 启用魂拔刀许可 '..r.name)
            if not call(lib,'AddLooseGameplayTag',r.actor,{TagName=fname(drawTag)},false) then return false end
            w.drawTag=lib
            enabled=tagCount(r.actor,drawTag)
        end
        if not enabled or enabled<1 then releaseDrawTag(r);return false end
        say('即将 魂拔刀换武器 '..r.name..' 目标='..item.label)
        local called,ret=call(aic,'ForceActivateExternalActionAbilityByTag',{TagName=fname(switchTag)},input,1)
        local active=(tagCount(r.actor,switchTag) or 0)>0
        local committed=index(w.wc,false)==idx
        say('拔刀换武器 读回='..tostring(committed)..' 招式启动='..tostring(active)..' 返回='..tostring(ret))
        if not called or not (active or committed) then releaseDrawTag(r);return false end
        w.draw={item=item,cfg=cfg,idx=idx,from=from,why=why,expires=t+2}
        return true
    end
    local function settleDraw(r,t)
        local w=r.wep
        local d=w.draw
        if not d then return false end
        local idx=index(w.wc,false)
        if idx==d.idx and U.key(slotConfig(w.wc,idx))==U.key(d.cfg) then
            w.draw=nil;releaseDrawTag(r)
            w.currentConfig=d.cfg;w.lastSwitch=t;w.switches=(w.switches or 0)+1;w.recheckAt=t+RECHECK_AFTER
            local shachi,max=stat(r.actor,'Shachi'),stat(r.actor,'Shachi_Max')
            say('拔刀换武器已切换 实例='..r.name..' 原因='..d.why..' 杀气='..num(shachi)..'/'..num(max))
            afterSwitch(r,d.item,idx,d.cfg,t)
        elseif t>=d.expires then
            w.draw=nil;releaseDrawTag(r)
            -- Re-enter normal selection after a missed notify. The next direct switch
            -- must pass the target, action and slot checks again.
            w.directAfterDraw=idx==d.from
            w.rotation.retryAt=t+1
        end
        return true
    end
    local function weaponAsset(r,item)
        local shared=object(item.config)
        if not shared or not item.temporary then return shared end
        local w=r.wep
        w.tempConfigs=w.tempConfigs or {}
        if U.valid(w.tempConfigs[item.id]) then return w.tempConfigs[item.id] end
        local _,class=call(shared,'GetClass')
        local construct=o.construct or StaticConstructObject
        if not U.valid(class) or type(construct)~='function' or not still(r) then return nil end
        say('即将 建立魂私有临时武器配置 '..item.label)
        local made,copy=pcall(construct,class,r.actor,fname('PG_Temp_'..item.id),0x40,0,false,false,shared)
        local _,outer=call(copy,'GetOuter')
        local _,cls=call(copy,'GetClass')
        if not made or not U.valid(copy) or U.key(copy)==U.key(shared) or U.key(outer)~=U.key(r.actor)
            or U.key(cls)~=U.key(class) then return nil end
        -- GA_TempWeaponPassive is the player's temporary-slot lifetime/force-switch policy.
        -- The NPC owns and cleans its two slots; only its private copy's array may be cleared.
        local key='Equip Passive Abilities'
        local a,b=U.field(copy,key),U.field(shared,key)
        local before=U.array(b)
        if not before or #before~=1 then return nil end
        local name_=name(before[1]) or ''
        if not name_:find('GA_TempWeaponPassive',1,true) then return nil end
        local ownArrays=false
        if type(a)=='table' and type(b)=='table' and U.kind(a)=='table' and U.kind(b)=='table' then
            ownArrays=a~=b
        elseif U.kind(a)=='TArray' and U.kind(b)=='TArray' then
            local ok,x,y=pcall(function()return a:GetArrayDataAddress(),b:GetArrayDataAddress()end)
            ownArrays=ok and type(x)=='number' and type(y)=='number' and x~=0 and y~=0 and x~=y
        end
        if not ownArrays then return nil end
        say('即将 在魂私有临时武器配置移除玩家临时槽被动 '..item.label)
        local ok=pcall(function()
            if U.kind(a)=='TArray' then a:Empty() else copy[key]={} end
        end)
        local remaining,unchanged=U.array(U.field(copy,key)),U.array(U.field(shared,key))
        if not ok or not remaining or #remaining~=0 or not unchanged or #unchanged~=#before then return nil end
        w.tempConfigs[item.id]=copy
        say('临时武器副本 读回 '..item.label..' 副本被动=0 原配置被动='..#unchanged)
        return copy
    end
    local function settleSwitch(r,t)
        local w=r.wep
        if settleDraw(r,t) then return true end
        if w.pendingSwitch then
            local pending=w.pendingSwitch
            if index(w.wc,false)==pending.idx and U.key(slotConfig(w.wc,pending.idx))==U.key(pending.cfg) then
                w.pendingSwitch=nil;w.currentConfig=pending.cfg
                afterSwitch(r,pending.item,pending.idx,pending.cfg,t)
            elseif t>=pending.expires then
                w.pendingSwitch=nil;failedPick(r,pending.item,t,'原生待切换序号未生效')
            end
            return true
        end
        return false
    end
    local function advanceRotation(r,t,target,performing)
        local w=r.wep
        local s=w.rotation
        local current=index(w.wc,false)
        if current~=0 and current~=1 or index(w.wc,true)~=current then return true end
        if w.active and (current~=w.idx or U.key(slotConfig(w.wc,current))~=U.key(w.currentConfig)) then
            -- A game ability can change the current slot independently. Reconcile before touching either slot.
            w.active=nil;w.currentId=nil;s.currentId=nil;w.weapon=nil
            Rotation.effects(s,nil,U.field(r.actor,'AbilitySystemComponent'),{object=object,call=call,say=say})
        end
        if performing then return false end
        if (tagCount(r.actor,switchTag) or 0)>0 then return true end
        if t<s.retryAt or not usable('switch',r) then return false end
        if w.pendingHitConfig then
            if w.active and w.pendingHitConfig==w.active.id then alignHitReactions(r) end
            w.pendingHitConfig=nil
        end
        if phaseArt(r,t,target) then return true end
        local phase=r.intent and r.intent.weapon_id
        if not phase and not w.comboOff and t<(w.firstMoveUntil or 0) then return false end
        local cd=cooldown(w.wc)
        local fallback=w.extraWait or 0
        if w.lastSwitch and t-w.lastSwitch<math.max(0.2,fallback) or cd and cd>0 then return false end
        if phase==w.currentId and phase~=nil then return false end
        local item=Rotation.pick(s,phase,o.random)
        if not item then
            if w.comboOff and w.active and w.original then
                local inactive=1-current
                if setInactive(r,inactive,w.original) then
                    say('即将 恢复原生绝影招式池 '..r.name)
                    call(w.wc,'SetCurrentWeapon',slotTag(),inactive)
                    if index(w.wc,false)==inactive and U.key(slotConfig(w.wc,inactive))==U.key(w.original) then
                        w.active=nil;w.currentId=nil;s.currentId=nil;w.weapon=nil;w.idx=inactive
                        Rotation.effects(s,nil,U.field(r.actor,'AbilitySystemComponent'),{object=object,call=call,say=say})
                    end
                end
                s.retryAt=t+2
            end
            return false
        end
        if item.id==w.currentId then return false end
        local cfg=weaponAsset(r,item)
        if not cfg then failedPick(r,item,t,'无法加载或隔离临时配置');return true end
        local inactive=1-current
        local previous=slotConfig(w.wc,inactive)
        local swapped=setInactive(r,inactive,cfg)
        local broken=(tagCount(r.actor,'CharacterState.Stand.Break') or 0)>0
        local shachi,max=stat(r.actor,'Shachi'),stat(r.actor,'Shachi_Max')
        local low=type(shachi)=='number' and type(max)=='number' and max>0 and shachi/max<LOW_SHACHI
        local why=phase==item.id and '阶段优先' or broken and '破防' or low and '杀气<20%' or '权重轮换'
        w.selected=item
        local direct=w.directAfterDraw
        w.directAfterDraw=nil
        if swapped and not direct and target and tryDraw(r,item,cfg,inactive,current,why,t) then w.selected=nil;return true end
        local success=swapped and switchTo(r,inactive,why)
        w.selected=nil
        local actual=index(w.wc,true)
        if success and actual==inactive and U.key(slotConfig(w.wc,inactive))==U.key(cfg) then
            if index(w.wc,false)==inactive then
                w.currentConfig=cfg;afterSwitch(r,item,inactive,cfg,t)
            else
                w.pendingSwitch={item=item,idx=inactive,cfg=cfg,expires=t+2}
            end
            return true
        end
        if still(r) then
            if index(w.wc,true)~=current then
                say('即将 还原魂当前武器 槽='..current)
                call(w.wc,'SetCurrentWeapon',slotTag(),current)
                say('还原魂当前槽 读回='..tostring(index(w.wc,true)))
            end
            if index(w.wc,false)==current and index(w.wc,true)==current then
                if previous then setInactive(r,inactive,previous)
                elseif slotConfig(w.wc,inactive) then
                    say('即将 还原空武器槽 槽='..inactive)
                    call(w.wc,'SetSlotWeapon',slotTag(),inactive,nil)
                    say('还原空槽 读回='..short(slotConfig(w.wc,inactive)))
                end
            end
        end
        failedPick(r,item,t,swapped and '切换未读回' or '非当前槽未写入')
        return true
    end
    local function fight(r,t)
        local w=r.wep;local actor=r.actor
        if type(t)~='number' then return end
        local fighting=not r.dead and o.battle and o.battle(r)
        if not fighting then w.fightStart=nil end
        if not fighting and not (w.draw or w.pendingSwitch) then return end
        if r.dead then releaseDrawTag(r);w.draw=nil;w.pendingSwitch=nil;return end
        if o.hp then local ok,hp=pcall(o.hp,actor);if not ok or type(hp)~='number' or hp<=0 then return end end
        if (w.draw or w.pendingSwitch) and settleSwitch(r,t) then return end
        if not fighting then return end
        w.fightStart=w.fightStart or t
        if w.recheckAt and t>=w.recheckAt then
            w.recheckAt=nil
            say('换武器 复读 实例='..r.name..' 序号='..tostring(index(w.wc,false))..' 新武器Actor=['..attachText(slotActors(w.wc,w.idx or OWN))..']'
                ..' 原生冷却='..num(cooldown(w.wc))..' 杀气='..num(stat(actor,'Shachi'))..'/'..num(stat(actor,'Shachi_Max')))
        end
        if #w.pending>0 then settleHits(r)end
        if #w.grabReads>0 then grabReads(r)end
        -- Nothing is pushed or switched while the body executes, is executed or grabbed (arena_executions holds its AI).
        for _,t_ in ipairs(BUSY)do if(tagCount(actor,t_)or 0)>0 then return end end
        if r.loadout and r.loadout.kit and (tagCount(actor,'CharacterState.Stand.Break') or 0)>0 then return end
        if r.intent and (r.intent.busy or (r.intent.busyUntil or 0)>t) then return end
        local target,dist=nearest(r,math.max(RANGE,GRAB_RANGE,VICTIM_RANGE))
        if o.pairProtected and o.pairProtected(r,target) then return end
        if not matchesTarget(actor,target) then return end
        local performing,canChain=Vitals.actionState(actor,fname)
        if w.rotation and advanceRotation(r,t,target,performing) then return end
        -- 3-2
        if not performing and not w.rotation and w.slotted and usable('switch',r)and not w.switchOff then
            local target,why
            if steps.forceSwitchAt and not w.forced and w.idx==OWN and t-w.fightStart>=steps.forceSwitchAt then
                target,why=NEW,'开战'..steps.forceSwitchAt..'秒强制（验证用）';w.forced=true
            elseif t-(w.lastSwitch or-math.huge)>=COOLDOWN then
                local cd=cooldown(w.wc)
                if not cd or cd<=0 then
                    local broken=(tagCount(actor,'CharacterState.Stand.Break')or 0)>0
                    local shachi,max=stat(actor,'Shachi'),stat(actor,'Shachi_Max')
                    local low=type(shachi)=='number'and type(max)=='number'and max>0 and shachi/max<LOW_SHACHI
                    if broken or low then target,why=(w.idx==OWN and NEW or OWN),broken and'破防'or'杀气<20%'end
                end
            end
            if target then
                local ok,passed=pcall(switchTo,r,target,why)
                if not ok then say('换武器 中断：实例='..r.name..' 原因='..tostring(passed));passed=false;pcall(back,r,w.wc,'中断')end
                if not w.switchRecorded then w.switchRecorded=true;record('switch',passed==true)end
                if passed~=true then w.switchOff=true end
                return
            end
        end
        -- 3-8
        if steps.victimGrab and usable('victim',r) and not (r.loadout and r.loadout.survival and r.loadout.survival.grab=='immune') then
            local weakTag=(tagCount(actor,'CharacterState.CanWeakExecute.Weak')or 0)>0
            if not weakTag then w.victimAsked=false
            elseif not performing and not w.victimAsked and target and matchesTarget(target,actor)
                and not Vitals.actionState(target) then victim(r,target)return end
        end
        if w.rotation and not w.active or not w.rotation and w.idx~=NEW then return end
        local weapon=currentWeapon(w)
        if not performing and w.rotation and weapon and not weapon.temporary and weapon.art and weapon.grab~=weapon.art and
            target and dist<=RANGE and not (r.intent and r.intent.phaseId) and t>=(w.combatArtAt or 0)
            and t>=(w.phaseRetryAt and w.phaseRetryAt[weapon.id] or 0) then
            w.combatArtAt=t+4
            local broken=(tagCount(target,'CharacterState.Stand.Break') or 0)>0
            local charge,max=stat(actor,'UltimateChargeCount'),stat(actor,'UltimateChargeCount_Max')
            local spec=specOf(actor,weapon.art)
            local full=type(charge)=='number' and type(max)=='number' and max>0 and charge>=max
            if (broken or full) and spec and spec.active==0 and type(spec.handle)=='number' and activateArt(r,weapon,spec,target) then
                say('魂释放原生战技 '..weapon.label..' '..spec.name..' 原因='..(broken and '敌方破防' or '绝技格已满'))
                return
            end
        end
        if not performing and weapon and weapon.temporary and weapon.art and target and dist<=RANGE
            and (tagCount(target,'CharacterState.Stand.Break') or 0)>0 and t>=(w.tempArtAt or 0) then
            w.tempArtAt=t+8
            local spec=specOf(actor,weapon.art)
            if spec and type(spec.handle)=='number' and spec.active==0 then
                say('即将 魂临时武器终结技 '..weapon.label..' '..spec.name)
                call(U.field(actor,'AbilitySystemComponent'),'TryActivateAbility',{Handle=spec.handle},false)
                local after=specOf(actor,weapon.art)
                say('临时武器终结技 读回 ActiveCount='..tostring(after and after.active))
                if after and type(after.active)=='number' and after.active>0 then w.firstMoveUntil=nil;return end
            end
        end
        -- 3-6
        if not performing and weapon and weapon.grab and usable('grab',r)and target and dist<=GRAB_RANGE and(w.grabs or 0)<GRAB_MAX and t-(w.grabAt or-math.huge)>=GRAB_EVERY then
            grab(r,target);return
        end
        -- 3-3
        local limit=w.rotation and w.rotation.ai.combo_limit or 0
        if limit>0 and (w.chainCount or 0)>=limit then
            if t-(w.comboAt or t)<0.9 then return end
            w.chainCount=0;w.skipTag=nil
        end
        if usable('combo',r)and not w.comboOff and target and dist<=RANGE and t-(w.comboAt or-math.huge)>=LOOP_MS/1000-0.01 then
            w.comboAt=t
            combo(r,target,performing,canChain)
        end
    end
    local function stopLoop(r)
        local entry=loops[r]
        if not entry then return end
        loops[r]=nil
        r.weaponTimerPending=nil;roster=nil
        bodyCount=bodyCount-1
        bucketSizes[entry.bucket]=bucketSizes[entry.bucket]-1
        if bodyCount==0 then normal:stop();staggered:stop();activeTimer=nil;slice=0
        elseif alive and bodyCount==3 and activeTimer==staggered then
            self:retryTimer(next(loops))
        end
        return true
    end
    function self:stop(r,why)
        if not stopLoop(r) then return end
        if r.wep and r.wep.drawTag then releaseDrawTag(r) end
        for k,record in pairs(powerRecords) do if record==r then powerRecords[k]=nil end end
        local w=r.wep
        if w and w.rotation then
            local s=w.rotation
            if still(r) then
                Rotation.effects(s,nil,U.field(r.actor,'AbilitySystemComponent'),{object=object,call=call,say=say},true)
                if w.hitCopy and U.key(iface(U.field(w.hitComponent,'ActorConfig')))==U.key(w.hitCopy) then
                    say('即将 撤销魂私有受击配置');say('受击接口还原 读回='..tostring(w.restoreHit()))
                end
                local current=index(w.wc,false)
                if w.active and (current==0 or current==1) and current==index(w.wc,true) then
                    -- Restore the exact spawn loadout only if the currently selected weapon still belongs to this module.
                    if U.key(slotConfig(w.wc,current))==U.key(w.currentConfig) then
                        local dest=w.originalIdx
                        if current==dest and U.key(slotConfig(w.wc,current))~=U.key(w.original) then
                            if setInactive(r,1-current,w.original) then
                                say('即将 切到魂原生武器以还原两个主槽')
                                call(w.wc,'SetCurrentWeapon',slotTag(),1-current)
                            end
                        end
                        if U.key(slotConfig(w.wc,dest))==U.key(w.original) or setInactive(r,dest,w.original) then
                            say('即将 还原魂出生时主槽='..dest)
                            call(w.wc,'SetCurrentWeapon',slotTag(),dest)
                            if index(w.wc,false)==dest and index(w.wc,true)==dest then
                                if w.originalOther then setInactive(r,1-dest,w.originalOther)
                                else
                                    say('即将 清空魂出生时的空槽')
                                    call(w.wc,'SetSlotWeapon',slotTag(),1-dest,nil)
                                end
                                say('出生主槽还原 读回='..short(slotConfig(w.wc,dest))..' 另一槽='..short(slotConfig(w.wc,1-dest)))
                                for i=0,1 do
                                    for _,a in ipairs(slotActors(w.wc,i)) do local key=U.key(a);if key then w.spawned[key]=nil end end
                                end
                            end
                        end
                    end
                end
            end
            for _,weapon in ipairs(s.pool) do
                local counters=w.stats[weapon.id]
                if counters then comboStats(r,weapon,counters,true) end
            end
        elseif w then
            for name_,counters in pairs(w.stats) do
                local weapon=Weapons.LIST[name_];if weapon then comboStats(r,weapon,counters,true) end
            end
        end
        say('武器循环结束 实例='..r.name..' 原因='..tostring(why))
    end
    local function runWeapon(r,t)
        if not still(r) then self:stop(r,'实例离场或已变化');return end
        fight(r,t)
    end
    local function tickWeapons(timer,bucket)
        if not alive or timer~=activeTimer then return end
        if not roster then
            roster={{},{},{},{}}
            for _,entry in pairs(loops) do
                local group=roster[entry.bucket]
                group[#group+1]=entry
            end
        end
        -- Keep this pass stable when a native call summons or removes another fighter.
        local snapshot,t,wall=roster,clock(),os.clock()
        for i=bucket or 1,bucket or 4 do
            for _,entry in ipairs(snapshot[i]) do
                local r=entry.record
                if loops[r]==entry and (not entry.timer or entry.timer==timer or wall-entry.lastTick>=.19) then
                    entry.timer,entry.lastTick=timer,wall
                    local ok,why=pcall(runWeapon,r,t)
                    if not ok then
                        say('武器循环中断 实例='..r.name..' 原因='..tostring(why))
                        self:stop(r,'中断')
                    end
                end
            end
        end
    end
    local function tickSmall()tickWeapons(normal) end
    local function tickGroup()
        slice=slice%4+1
        tickWeapons(staggered,slice)
    end
    function self:retryTimer(r)
        if not alive or not loops[r] then return end
        local split=bodyCount>=8 or (activeTimer==staggered and bodyCount>3)
        local wanted=split and staggered or normal
        if wanted~=activeTimer and wanted:ensure(split and tickGroup or tickSmall) then
            local previous=activeTimer
            activeTimer=wanted
            if previous then previous:stop() end
        end
        r.weaponTimerPending=activeTimer~=wanted
    end
    local function start(r)
        if not alive or loops[r] then return end
        local bucket=1
        for i=2,4 do if bucketSizes[i]<bucketSizes[bucket] then bucket=i end end
        bucketSizes[bucket]=bucketSizes[bucket]+1;bodyCount=bodyCount+1
        loops[r]={record=r,bucket=bucket};roster=nil
        self:retryTimer(r)
    end

    -- The second support cycle after birth: precondition, 3-1, probes; then the fight loop.
    function self:equip(r)
        if not steps.enabled or r.wep then return end
        self.bodies=self.bodies+1
        if not steps.slotWeapons then
            if not still(r) then return end
            local rotation=Rotation.new(r)
            if #rotation.pool==0 then return end
            r.weaponInitPending=true
            r.wep={rotation=rotation,spawned={},stats={},pending={},grabReads={},idx=OWN}
            local aic,wc=precheck(r)
            if not aic then r.wep.skipped=true;return end
            local idx=index(wc,false)
            local count,via=slotCount(wc)
            if (idx~=0 and idx~=1) or (count~=nil and (count<=idx or count>2)) then
                say('武器池未接入：主槽序号='..tostring(idx)..' 数量='..tostring(count)..' 来源='..via..' 实例='..r.name);return
            end
            local original=slotConfig(wc,idx)
            if not original then say('武器池未接入：读不到魂原装配置 实例='..r.name);return end
            -- In this build GetSlotWeapon's out parameter also works when the bulk getter is opaque.
            -- Only write the other of slots 0/1, after capturing its prior contents.
            local other
            if count~=nil and 1-idx>=count then other={} else other=slotData(wc,1-idx) end
            local otherValue=other and U.unwrap(other.WeaponConfig)
            local otherConfig=iface(otherValue)
            local knownEmpty=other and otherValue==nil
            if otherValue~=nil and not otherConfig then
                local ok,inner=pcall(function()return otherValue:GetObject()end)
                local readable,valid=pcall(function()return otherValue:IsValid()end)
                knownEmpty=(ok and not U.valid(inner)) or (readable and valid==false)
            end
            if not otherConfig and not knownEmpty then
                say('武器池未接入：备用槽未读回 实例='..r.name);return
            end
            r.wep.wc,r.wep.idx,r.wep.original=wc,idx,original
            r.wep.originalIdx=idx;r.wep.originalOther=otherConfig
            r.wep.slotted=true
            r.weaponInitPending=false
            say('武器池 实例='..r.name..' 启用='..#rotation.pool..' 主槽='..idx..' 数量='..tostring(count)..' 来源='..via..' 原武器='..short(original))
            start(r)
            return
        end
        local list=steps.slotWeapons or{'Tang'}
        local choice=list[(self.bodies-1)%#list+1]
        local weapon=Weapons.LIST[choice]
        r.wep={weapon=choice,spawned={},stats={},pending={},grabReads={},idx=OWN}
        if not weapon then say('武器 实例='..r.name..'；未知武器 '..tostring(choice));return end
        if not still(r)then return end
        local aic,wc=precheck(r)
        if not aic then r.wep.skipped=true;return end
        r.wep.wc=wc
        local i=index(wc,false)
        say('武器 实例='..r.name..' 本次加载第'..self.bodies..'只魂 序号'..NEW..'装'..weapon.label..'；主槽武器数='..tostring(slotCount(wc))..' 当前序号='..tostring(i)
            ..' 原生冷却='..num(cooldown(wc))..' 杀气='..num(stat(r.actor,'Shachi'))..'/'..num(stat(r.actor,'Shachi_Max')))
        r.wep.idx=i or OWN
        pcall(probe,r,'装武器前')
        if not usable('slot',r)then return end
        local ok,passed=pcall(slotStep,r,wc,weapon)
        if not ok then say('装武器 中断：实例='..r.name..' 原因='..tostring(passed));passed=false end
        record('slot',passed==true)
        r.wep.slotted=passed==true
        if r.wep.slotted then start(r)end
    end
    -- Weapon actors this module registered: still the body's, or left without an owner, are destroyed and read back.
    function self:cleanup(r,why)
        local w=r.wep
        if not w then return end
        local key=U.key(r.actor)
        local texts={}
        for k,entry in pairs(w.spawned)do
            local a=entry.actor
            if not U.valid(a)then texts[#texts+1]='?=已无效';w.spawned[k]=nil
            elseif U.key(a)~=k or name(a)~=entry.name then texts[#texts+1]='武器实例已更换，不动';w.spawned[k]=nil
            else
                local read,owner=call(a,'GetOwner')
                local mine=key~=nil and U.valid(owner)and U.key(owner)==key
                local orphan=read and not U.valid(owner)
                local _,destroying=call(a,'IsActorBeingDestroyed')
                if destroying==true then texts[#texts+1]=short(a)..'=销毁中';w.spawned[k]=nil
                elseif read and (mine or orphan) then
                    say('即将 销毁武器 Actor 实例='..r.name..' '..short(a)..'（'..(mine and'仍属魂'or'无主')..'）')
                    local called=call(a,'K2_DestroyActor')
                    local _,after=call(a,'IsActorBeingDestroyed')
                    local gone=not U.valid(a)or after==true
                    texts[#texts+1]=short(a)..'=调用'..tostring(called==true)..'/'..(gone and'已销毁'or'未确认')
                    if gone then w.spawned[k]=nil end
                elseif not read then
                    texts[#texts+1]=short(a)..'=归属未读回，不动'
                else
                    texts[#texts+1]=short(a)..'=已归别处（'..short(owner)..'），不动';w.spawned[k]=nil
                end
            end
        end
        if #texts>0 then say('清理武器 Actor 实例='..r.name..' 原因='..tostring(why)..' '..table.concat(texts,' '))end
    end
    function self:silence(restore)
        alive=false;activeArt,probeActor=nil,nil
        for r in pairs(loops) do
            if restore==false then stopLoop(r) else self:stop(r,'Mod 卸载') end
        end
        powerRecords={}
        if self.controllerHook then
            pcall(o.unregister or UnregisterHook,CONTROLLER,self.controllerHook[1],self.controllerHook[2])
            self.controllerHook=nil;self.guardVerified=false
        end
        if self.powerHook then
            pcall(o.unregister or UnregisterHook,POWER_HOOK,self.powerHook[1],self.powerHook[2])
            self.powerHook=nil
        end
    end
    return self
end
return Weapons
