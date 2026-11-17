-- Experimental weapons of the owned Hun body (BP_Monster_Hun), scheduled by hun_body.lua on the same records.
-- Only that instance's weapons component, ability system and attribute set are written; weapon configs and ability
-- classes are shared assets and only referenced. Each low-confidence native call is preceded by a "即将" line and read
-- back; a step that does not read back is undone (the body goes back to its own weapon, slot 0) and read back again.
-- Change Weapon (BPL_PBZCombatUtils) = SetCurrentWeapon -> (true) SetArmed -> StartChangeWeaponCooldown ->
-- ModifyCharacterAttributeValue(Shachi, Override, Shachi_Max) (weapon-switch/BPL_PBZCombatUtils, Change Weapon [180-614]).
-- The light-attack chains come from hun_weapon_combos.lua (exported from the decoded input maps).
local U=require('ue_observe')
local Weapons={}
-- Switches of the weapon steps (this file is the only place they live).
Weapons.STEPS={
    enabled=true,          -- the whole weapon step (3-1 … 3-8)
    restart=true,          -- precondition: CharacterWeaponsComponent:OnRestarted(body) when its fields read empty
    slot=true,             -- 3-1 SetSlotWeapon into Weapon.Slot.Main index 1
    slotWeapons={'Tang','DualHook','ZhanMa'}, -- the weapon for slot 1, by body of the load in turn
    switch=true,           -- 3-2 switch on break or Shachi < 20 % with the cooldown done
    forceSwitchAt=10,      -- 3-2 seconds after the battle starts for one forced switch; false = off
    utilsFirst=true,       -- 3-2 the game's Change Weapon first, the four steps in Lua when it does not read back
    combo=true,            -- 3-3 Lua pushes the light-attack chain while a slot-1 weapon is current
    probe=true,            -- 3-4 / 3-5 read-only: locomotion layers, hit-react config, weapon tags
    grab=true,             -- 3-6 the slot-1 weapon's grab (DualHook GEx / ZhanMa C) by spec handle
    victimGrab=false,      -- 3-8 a broken body asks its opponent for a grab
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
    locomotion=PLAYER..'Animation/ABP_Hun_Locomotion.ABP_Hun_Locomotion_C',
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
local STAT_EVERY=5         -- seconds between two combo statistics lines of one weapon
local MAX_STAT_LINES=40    -- combo statistics lines in a load
local MAX_SPECS=512
local RECHECK_AFTER=1      -- seconds after a switch for its second readback
local GRAB_READS={0.4,1.5} -- seconds after a grab for the target's grab-state readback
local BUSY={'Ability.Action.Execution','Ability.Executed','CharacterState.HitReact.State.Executing'}
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
local function num(v)return type(v)=='number'and v==v and string.format('%.3g',v)or tostring(v)end
local function text(v)
    v=U.unwrap(v)
    if type(v)=='string'then return v end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string'and s or nil
end

function Weapons.new(o)
    local self={off={},streak={},skipped={},bodies=0,statLines=0,announced={}}
    local steps=o.steps or Weapons.STEPS
    local find=o.find or StaticFindObject
    local load=o.load or LoadAsset
    local fname=o.fname or FName
    local clock=o.clock or os.clock
    local combos=o.combos or require('hun_weapon_combos')
    local loops={}
    local function say(s)(o.log or function()end)('[HunWeapon] '..s)end
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
        local _,slots=call(wc,'GetSlotWeapons',slotTag())
        local list=U.array(slots)
        return list and #list or nil
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
    local function specOf(actor,classPath)
        for _,spec in ipairs(specs(actor)or{})do
            local ability=U.struct(spec,'Ability')
            if U.valid(ability)then
                local p=path(ability)
                if p==classPath or(p and p:gsub('%.Default__','.')==classPath)then
                    local handle=U.struct(U.struct(spec,'Handle'),'Handle')
                    return {handle=handle,active=U.struct(spec,'ActiveCount'),name=abilityName(ability)}
                end
            end
        end
    end
    local function owned(actor,list,r)
        local key=U.key(r.actor)
        for _,a in ipairs(list)do
            local _,owner=call(a,'GetOwner')
            if U.key(owner)==key then
                local k=U.key(a)
                r.wep.spawned[k]=r.wep.spawned[k]or a
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
        local loco=object(Weapons.PATHS.locomotion)
        local _,locoLayer=call(mesh,'GetLinkedAnimLayerInstanceByClass',loco)
        say('走跑层（只读）实例='..r.name..'（'..when..'） MMGraph='..(U.valid(graph)and tostring(U.className(graph))or'无')
            ..' MMGraph.CharacterMovement有效='..tostring(U.valid(U.field(graph,'CharacterMovement')))..' 链接实例=['..table.concat(linked,'|')..']'
            ..' ABP_Hun_Locomotion已链接='..tostring(U.valid(locoLayer)))
        local hit=U.field(actor,'Hitreact Component')
        local weapon=Weapons.LIST[r.wep.weapon]
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
        local weapon=Weapons.LIST[w.weapon]
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
                if target~=OWN then back(r,wc,'四步没读回')end
                return false
            end
            via='Lua 四步'
        end
        w.idx=target;w.lastSwitch=clock();w.switches=(w.switches or 0)+1;w.recheckAt=clock()+RECHECK_AFTER
        w.tagMap=nil;w.comboFails=0
        local actors=slotActors(wc,target)
        if target==NEW then owned(actor,actors,r)end
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
    local function tagMap(r)
        if r.wep.tagMap then return r.wep.tagMap end
        -- Several specs can carry one tag (the body's own GA_Hun_Double_* and the slotted weapon's); the current
        -- weapon's prefix wins.
        local map={}
        local prefix=Weapons.LIST[r.wep.weapon].prefix
        for _,spec in ipairs(specs(r.actor)or{})do
            local ability=U.struct(spec,'Ability')
            local n_=abilityName(ability)
            local mine=n_:sub(1,#prefix)==prefix
            local container=U.field(ability,'AbilityTags')
            for _,t in ipairs(U.array(U.struct(container,'GameplayTags'))or{})do
                local n=text(U.struct(t,'TagName'))
                if n and(not map[n]or mine and not map[n].mine)then
                    map[n]={handle=U.struct(U.struct(spec,'Handle'),'Handle'),name=n_,mine=mine}
                end
            end
        end
        r.wep.tagMap=map
        return map
    end
    local function matches(actor,entry,cache)
        local function count(t)if cache[t]==nil then cache[t]=tagCount(actor,t)or 0 end;return cache[t]end
        for _,t in ipairs(entry.req)do if count(t)<=0 then return false end end
        for _,t in ipairs(entry.ign)do if count(t)>0 then return false end end
        return true
    end
    local function nextTag(r,chain)
        local cache={}
        local skip=r.wep.skipTag
        for _,entry in ipairs(chain.combos)do if entry.tag~=skip and matches(r.actor,entry,cache)then return entry.tag,'连段'end end
        for _,entry in ipairs(chain.actions)do if matches(r.actor,entry,cache)then return entry.tag,'起手'end end
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
        say('出招统计 实例='..r.name..' '..weapon.label..' 尝试='..s.tries..' 成功='..s.ok..'（按标签 '..s.byTag..'，按句柄 '..s.byHandle..'）'
            ..' 对手掉血='..s.hits..' 最近招='..tostring(s.lastTag)..' 最近蒙太奇='..tostring(s.lastMontage)
            ..(self.statLines>=MAX_STAT_LINES and'（本次加载统计行已到上限）'or''))
    end
    local function combo(r,target)
        local w=r.wep;local actor=r.actor
        local weapon=Weapons.LIST[w.weapon]
        local chain=combos[w.weapon]
        if not chain then once('nochain'..w.weapon,'出招 '..weapon.label..' 没有连段表，不推招');return end
        local aic=U.field(actor,'Ability Input Component')
        once('canActivate','即将 只读 AbilityInputComponent:CanActivateExternalActionAbility(1)（本次加载第一次）')
        local gotGate,gate=call(aic,'CanActivateExternalActionAbility',1)
        if gotGate and gate==false then return end
        local tag,kind=nextTag(r,chain)
        if not tag then return end
        local ia=object(Weapons.PATHS.light)
        w.stats[w.weapon]=w.stats[w.weapon]or{tries=0,ok=0,byTag=0,byHandle=0,hits=0}
        local s=w.stats[w.weapon]
        s.tries=s.tries+1;s.lastTag=tag
        once('byTag','即将 AbilityInputComponent:TryActivateExternalActionAbilityByTag(标签,IA_AttackL_Press,1)（本次加载第一次，之后不再逐次写）')
        local before=tagCount(actor,tag)or 0
        local called,result=call(aic,'TryActivateExternalActionAbilityByTag',{TagName=fname(tag)},ia,1)
        local after=tagCount(actor,tag)or 0
        local started=after>before or(result==true and after>0)
        local how='标签'
        if not started then
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
            s.ok=s.ok+1;if how=='标签'then s.byTag=s.byTag+1 else s.byHandle=s.byHandle+1 end
            s.lastMontage=montage(actor);w.comboFails=0;w.skipTag=nil
            if target and #w.pending<4 then w.pending[#w.pending+1]={target=target,hp=o.hp and select(2,pcall(o.hp,target)),at=clock()}end
        else
            w.comboFails=(w.comboFails or 0)+1;w.skipTag=kind=='连段'and tag or nil
        end
        if not w.comboFirst then
            w.comboFirst=true
            say('出招 第一次 实例='..r.name..' '..weapon.label..' 标签='..tag..'（'..kind..'） ByTag调用='..tostring(called==true)..' 返回='..tostring(result)
                ..' 标签计数 '..before..'→'..after..' 方式='..how..' 启动='..tostring(started)..' 蒙太奇='..montage(actor))
        end
        if started and not w.comboRecorded then w.comboRecorded=true;record('combo',true)end
        comboStats(r,weapon,s,false)
        if w.comboFails>=COMBO_GIVE_UP then
            say('新武器出招不通 实例='..r.name..' '..weapon.label..' 连续 '..w.comboFails..' 次没启动，切回绝影（原生招式池恢复有效）')
            comboStats(r,weapon,s,true)
            if not w.comboRecorded then w.comboRecorded=true;record('combo',false)end
            w.comboOff=true
            back(r,w.wc,'新武器出招不通')
        end
    end
    local function settleHits(r)
        local w=r.wep;local t=clock();local keep={}
        for _,p in ipairs(w.pending)do
            if t-p.at>=0.8 then
                if U.valid(p.target)and type(p.hp)=='number'and o.hp then
                    local ok,hp=pcall(o.hp,p.target)
                    if ok and type(hp)=='number'and hp<p.hp then local s=w.stats[w.weapon];if s then s.hits=s.hits+1 end end
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
    local function grab(r,target)
        local w=r.wep;local actor=r.actor
        local weapon=Weapons.LIST[w.weapon]
        w.grabAt=clock();w.grabs=(w.grabs or 0)+1
        local spec=specOf(actor,weapon.grab)
        if not spec then
            say('魂用投技 实例='..r.name..' '..weapon.label..'；技能 '..weapon.grab:match('([^%.]+)$')..' 没授予（spec 不在）')
            if not w.grabRecorded then w.grabRecorded=true;record('grab',false)end
            return
        end
        if spec.active~=0 or type(spec.handle)~='number'then return end
        if not still(r)then return end
        local needs=weapon.grabNeeds and(' 目标 '..weapon.grabNeeds..'='..tostring(tagCount(target,weapon.grabNeeds)))or''
        local asc=U.field(actor,'AbilitySystemComponent')
        say('即将 魂用投技 实例='..r.name..' '..spec.name..' AbilitySystemComponent:TryActivateAbility(句柄='..spec.handle..') 目标='..short(target)..needs)
        local called,result=call(asc,'TryActivateAbility',{Handle=spec.handle},false)
        local after=specOf(actor,weapon.grab)
        local started=called and after~=nil and type(after.active)=='number'and after.active>0
        say('魂用投技 读回 实例='..r.name..' '..spec.name..' 调用='..tostring(called==true)..' 返回='..tostring(result)..' ActiveCount '..tostring(spec.active)
            ..'→'..tostring(after and after.active)..' 启动='..tostring(started)..' 目标 '..grabState(target))
        if not w.grabRecorded then w.grabRecorded=true;record('grab',started)end
        if started then for _,d in ipairs(GRAB_READS)do w.grabReads[#w.grabReads+1]={target=target,at=clock()+d,label='+'..d..'s'}end end
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
        local _,me=call(r.actor,'K2_GetActorLocation')
        local mx,my,mz=U.struct(me,'X'),U.struct(me,'Y'),U.struct(me,'Z')
        if type(mx)~='number'then return nil end
        for _,a in ipairs(o.opponents and o.opponents(r)or{})do
            if U.valid(a)then
                local alive=true
                if o.hp then local ok,hp=pcall(o.hp,a);alive=not ok or type(hp)~='number'or hp>0 end
                local _,at=call(a,'K2_GetActorLocation')
                local x,y,z=U.struct(at,'X'),U.struct(at,'Y'),U.struct(at,'Z')
                if alive and type(x)=='number'then
                    local d=math.sqrt((x-mx)^2+(y-my)^2+((z or 0)-(mz or 0))^2)
                    if d<=range and(not bestD or d<bestD)then best,bestD=a,d end
                end
            end
        end
        return best,bestD
    end
    local function fight(r)
        local w=r.wep;local actor=r.actor;local t=clock()
        if not(o.battle and o.battle())then w.fightStart=nil;return end
        if o.hp then local ok,hp=pcall(o.hp,actor);if ok and type(hp)=='number'and hp<=0 then return end end
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
        -- 3-2
        if w.slotted and usable('switch',r)and not w.switchOff then
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
        local target,dist=nearest(r,math.max(RANGE,GRAB_RANGE,VICTIM_RANGE))
        -- 3-8
        if steps.victimGrab and usable('victim',r)then
            local weakTag=(tagCount(actor,'CharacterState.CanWeakExecute.Weak')or 0)>0
            if not weakTag then w.victimAsked=false
            elseif not w.victimAsked and target then victim(r,target)return end
        end
        if w.idx~=NEW then return end
        local weapon=Weapons.LIST[w.weapon]
        -- 3-6
        if weapon.grab and usable('grab',r)and target and dist<=GRAB_RANGE and(w.grabs or 0)<GRAB_MAX and t-(w.grabAt or-math.huge)>=GRAB_EVERY then
            grab(r,target);return
        end
        -- 3-3
        if usable('combo',r)and not w.comboOff and target and dist<=RANGE and t-(w.comboAt or-math.huge)>=LOOP_MS/1000-0.01 then
            w.comboAt=t
            combo(r,target)
        end
    end
    function self:stop(r,why)
        local entry=loops[r]
        if not entry then return end
        loops[r]=nil
        if entry.handle then pcall(o.cancel or CancelDelayedAction,entry.handle)end
        local w=r.wep
        if w then for name_,s in pairs(w.stats)do local weapon=Weapons.LIST[name_];if weapon then comboStats(r,weapon,s,true)end end end
        say('武器循环结束 实例='..r.name..' 原因='..tostring(why))
    end
    local function start(r)
        local loop=o.loop or LoopInGameThreadWithDelay
        if type(loop)~='function'then say('武器循环没启动 实例='..r.name..'：没有循环函数');return end
        local entry={}
        loops[r]=entry
        local ok,handle=pcall(loop,LOOP_MS,function()
            if loops[r]~=entry then return end
            if not still(r)then self:stop(r,'实例离场或已变化');return end
            local ran,why=pcall(fight,r)
            if not ran then say('武器循环中断 实例='..r.name..' 原因='..tostring(why));self:stop(r,'中断')end
        end)
        if not ok or handle==nil or handle==false then loops[r]=nil;say('武器循环没登记 实例='..r.name..' '..tostring(handle));return end
        entry.handle=handle
    end

    -- The second support cycle after birth: precondition, 3-1, probes; then the fight loop.
    function self:equip(r)
        if not steps.enabled or r.wep then return end
        self.bodies=self.bodies+1
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
        for k,a in pairs(w.spawned)do
            if not U.valid(a)then texts[#texts+1]='?=已无效';w.spawned[k]=nil
            else
                local _,owner=call(a,'GetOwner')
                local mine=U.valid(owner)and U.key(owner)==key
                local orphan=not U.valid(owner)
                local _,destroying=call(a,'IsActorBeingDestroyed')
                if destroying==true then texts[#texts+1]=short(a)..'=销毁中';w.spawned[k]=nil
                elseif mine or orphan then
                    say('即将 销毁武器 Actor 实例='..r.name..' '..short(a)..'（'..(mine and'仍属魂'or'无主')..'）')
                    local called=call(a,'K2_DestroyActor')
                    local _,after=call(a,'IsActorBeingDestroyed')
                    local gone=not U.valid(a)or after==true
                    texts[#texts+1]=short(a)..'=调用'..tostring(called==true)..'/'..(gone and'已销毁'or'未确认')
                    if gone then w.spawned[k]=nil end
                else
                    texts[#texts+1]=short(a)..'=已归别处（'..short(owner)..'），不动';w.spawned[k]=nil
                end
            end
        end
        if #texts>0 then say('清理武器 Actor 实例='..r.name..' 原因='..tostring(why)..' '..table.concat(texts,' '))end
    end
    function self:silence()for r in pairs(loops)do self:stop(r,'Mod 卸载')end end
    return self
end
return Weapons
