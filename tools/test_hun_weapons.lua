package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Weapons=require('hun_weapons')
local L=Weapons.LIST
local index=0
local function object(label,fields)
    index=index+1;local id=index;local a=fields or {}
    a.label=label;a.valid=true
    function a:IsValid()return self.valid end
    function a:GetFullName()return self.label end
    function a:GetAddress()return id end
    return a
end
local function vec(x,y,z)return {X=x,Y=y,Z=z}end
-- An ASC with tag counts and ability specs; TryActivateAbility starts a spec unless told otherwise.
local function asc(h,owner)
    local a=object('AbilitySystemComponent '..owner)
    a.tags={};a.specs={}
    a.ActivatableAbilities={Items=a.specs}
    function a:GetGameplayTagCount(t)return self.tags[t.TagName]or 0 end
    function a:TryActivateAbility(handle,remote)
        assert(remote==false);h.calls[#h.calls+1]='activate '..owner..' '..handle.Handle
        for _,spec in ipairs(self.specs)do
            if spec.Handle.Handle==handle.Handle and not h.refuseActivate then
                spec.ActiveCount=spec.ActiveCount+1
                local cost=spec.Ability['Ultimate Charge Cost']
                if cost and h.stats.values.UltimateChargeCount and h.stats.values.UltimateChargeCount>=cost then
                    h.stats.values.UltimateChargeCount=h.stats.values.UltimateChargeCount-cost
                end
                for _,t in ipairs(spec.Ability.AbilityTags.GameplayTags)do self.tags[t.TagName]=(self.tags[t.TagName]or 0)+1 end
                return true
            end
        end
        return false
    end
    return a
end
local function spec(a,classPath,handle,tags)
    local cdo=object('BlueprintGeneratedClass '..classPath:gsub('%.([^%.]+)$','.Default__%1'))
    local list={};for _,t in ipairs(tags or{})do list[#list+1]={TagName=t}end
    cdo.AbilityTags={GameplayTags=list}
    if classPath:match('_C1%.') or classPath:match('_C%.') then cdo['Ultimate Charge Cost']=1 end
    a.specs[#a.specs+1]={Ability=cdo,Handle={Handle=handle},ActiveCount=0}
end
local function fixture(opts)
    opts=opts or {}
    if not opts.profile then
        opts.steps=opts.steps or {}
        local legacy={}
        for k,v in pairs(Weapons.STEPS) do legacy[k]=v end
        legacy.slotWeapons={'Tang','DualHook','ZhanMa'};legacy.forceSwitchAt=10;legacy.victimGrab=false
        for k,v in pairs(opts.steps) do legacy[k]=v end
        opts.steps=legacy
    end
    local h={logs={},calls={},t=0,loops={},cancelled={},hp={},battle=true,loaded={}}
    h.cfg={};for name_,w in pairs(L)do h.cfg[name_]=object('PBZ_MainWeaponConfig_C '..w.config)end
    h.light=object('InputAction '..Weapons.PATHS.light)
    h.utils=object('BPL_PBZCombatUtils_C '..Weapons.PATHS.utils)
    function h.utils:ChangeWeaponImpl(actor,slot,i,armed,world)
        assert(slot.TagName=='Weapon.Slot.Main' and armed==true and world==actor)
        h.calls[#h.calls+1]='utils '..i
        if h.utilsError then error('no such function')end
        if h.utilsIgnored then return end
        h.wc.current=i;h.stats.values.Shachi=h.stats.values.Shachi_Max
    end
    h.utils['Change Weapon']=function(self,...)return self:ChangeWeaponImpl(...)end
    h.assets={[Weapons.PATHS.light]=h.light,[Weapons.PATHS.utils]=h.utils}
    for name_,w in pairs(L)do h.assets[w.config]=h.cfg[name_]end
    h.stats={values={Shachi=100,Shachi_Max=400,UltimateChargeCount=2,UltimateChargeCount_Max=3},refuse=false}
    function h.stats:read(actor,field)local v=self.values[field];return v and {current=v,base=v}end
    function h.stats:writeBase(actor,field,value)assert(field=='Shachi' or field=='UltimateChargeCount');if self.refuse then error('refused')end;self.values[field]=value;return true end
    h.enemy=object('BP_Monster_MaleThug_C /Game/Map.Thug_1');h.enemy.at=vec(200,0,0)
    function h.enemy:K2_GetActorLocation()return self.at end
    h.enemy.AbilitySystemComponent=asc(h,'enemy')
    h.hp[h.enemy]=1000
    h.player=object('Player')
    function h:body(o2)
        o2=o2 or {}
        local a=object('BP_Monster_Hun_C /Game/Map.Hun_'..(index+1))
        h.actor=a;a.at=vec(0,0,0)
        function a:K2_GetActorLocation()return self.at end
        a.AbilitySystemComponent=asc(h,'hun')
        spec(a.AbilitySystemComponent,'/Game/GA_Hun_Double_A.GA_Hun_Double_A_C',1,{'Ability.Action.Hun.Light.A.Normal'})
        a.AbilitySystemComponent.tags['CharacterState.Space.Ground']=1
        a.AbilitySystemComponent.tags['CharacterState.Armed']=1
        local aic=object('AbilityInputComponent');a['Ability Input Component']=aic
        aic.AbilitySystem=not o2.noInputASC and a.AbilitySystemComponent or nil;aic.InputBindings={1,2,3}
        function aic:CanActivateExternalActionAbility(p)assert(p==1);return not h.busy end
        function aic:TryActivateExternalActionAbilityByTag(t,ia,p)
            assert(ia==h.light and p==1);h.calls[#h.calls+1]='bytag '..t.TagName;h.tried=(h.tried or 0)+1
            if h.byTagWorks~=false then local tags=a.AbilitySystemComponent.tags;tags[t.TagName]=(tags[t.TagName]or 0)+1;return true end
            return false
        end
        local wc=object('CharacterWeaponsComponent');a['Character Weapons Component']=wc;h.wc=wc
        wc.AbilitySystem=not o2.noWeaponASC and a.AbilitySystemComponent or nil
        wc.AbilityInput={Get=function()return aic end}
        wc.slots={{config=object('Weapon_Hun_JueYing NPC'),actors={}}};wc.current=0;wc.armed=true;wc.cd=0
        function wc:OnRestarted(pawn)assert(pawn==a);h.calls[#h.calls+1]='restarted';if h.restartFills then self.AbilitySystem=a.AbilitySystemComponent;aic.AbilitySystem=a.AbilitySystemComponent end end
        function wc:GetSlotWeapons(slot)assert(slot.TagName=='Weapon.Slot.Main');local out={};for i=1,#self.slots do out[i]={}end;return out end
        function wc:GetSlotWeapon(slot,i,out)local s=self.slots[i+1];if s then out.WeaponConfig=s.config;out.WeaponActors=s.actors end end
        function wc:SetSlotWeapon(slot,i,value)
            h.calls[#h.calls+1]='slot '..(value==nil and'nil'or(value.ObjectPointer and'pointer'or'direct'))
            if value==nil then self.slots[i+1]=nil;return end
            local cfg=value.ObjectPointer or value
            if h.slotTakes and h.slotTakes~=(value.ObjectPointer and'pointer'or'direct')then return end
            local weapon=object('BP_Weapon_Hun_New_'..i);function weapon:GetOwner()return h.weaponOwner or a end
            function weapon:K2_DestroyActor()h.calls[#h.calls+1]='destroy weapon';self.destroying=true end
            function weapon:IsActorBeingDestroyed()return self.destroying==true end
            function weapon:GetAttachParentActor()return a end
            function weapon:GetAttachParentSocketName()return 'weapon_r'end
            self.slots[i+1]={config=h.slotWrongConfig and object('Wrong')or cfg,actors={weapon}}
            h.newWeapon=weapon
            for _,cls in ipairs(o2.grants or{})do spec(a.AbilitySystemComponent,cls[1],cls[2],cls[3])end
        end
        function wc:GetCurrentWeaponIndex(slot,pending)return self.current end
        function wc:SetCurrentWeapon(slot,i)h.calls[#h.calls+1]='current '..i;if not(h.currentIgnored and i~=0)then self.current=i end end
        function wc:SetArmed(slot,v)h.calls[#h.calls+1]='armed';self.armed=v and not h.armedFails end
        function wc:IsArmed(slot)return self.armed end
        function wc:StartChangeWeaponCooldown(slot,i)h.calls[#h.calls+1]='cooldown '..i;self.cd=15 end
        function wc:GetCurrentChangeWeaponCooldown(slot)return self.cd end
        a.Mesh=object('Mesh');function a.Mesh:GetAnimInstance()return nil end
        h.r={actor=a,name='Hun_'..index}
        h.hp[a]=1000
        return h.r
    end
    h.mod=Weapons.new({log=function(s)h.logs[#h.logs+1]=s end,fname=function(s)return s end,clock=function()return h.t end,
        find=function(p)return h.loaded[p]end,load=function(p)local v=h.assets[p];h.loaded[p]=v;return v end,
        loop=function(ms,fn)assert(ms==200);h.loops[#h.loops+1]=fn;return #h.loops end,cancel=function(handle)h.cancelled[handle]=true end,
        stats=function()return h.stats end,hp=function(actor)return h.hp[actor]end,battle=function()return h.battle end,
        opponents=function()return h.opponents or {h.enemy}end,qteFamily=function(actor)return h.qte==actor end,
        construct=opts.construct,
        nativeTarget=opts.nativeTarget and function(actor)return opts.nativeTarget(h,actor)end,
        createInvalid=function()return {IsValid=function()return false end}end,
        register=function(path,callback)
            if path:find('GetPlayerController',1,true) then h.controllerCallback=callback else h.powerCallback=callback end
            return 1,2
        end,
        unregister=function()h.powerCallback=nil end,
        current=function(r)return h.gone~=r end,steps=opts.steps})
    function h:tick(seconds,step)
        step=step or 0.2
        local target=self.t+(seconds or 0)
        repeat for _,fn in ipairs(self.loops)do fn()end;self.t=self.t+step until self.t>target+1e-9
    end
    function h:logged(text)local n=0;for _,line in ipairs(self.logs)do if line:find(text,1,true)then n=n+1 end end;return n end
    function h:count(text)local n=0;for _,c in ipairs(self.calls)do if c==text then n=n+1 end end;return n end
    function h:firstCall(text)for i,c in ipairs(self.calls)do if c==text then return i end end end
    local statics=object('Statics')
    function statics:GetPlayerController(ctx,i)return h.controllerCallback(nil,ctx,i) or h.player end
    h.assets['/Script/Engine.Default__GameplayStatics']=statics
    h:body(opts.body)
    return h
end
local function steps(over)
    local s={forceSwitchAt=10,victimGrab=false}
    for k,v in pairs(over or{})do s[k]=v end
    return s
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end

test('precondition read back, the Tang goes into slot 1 as a direct object, and the fight loop starts',function()
    local h=fixture();h.mod:equip(h.r)
    assert(h:logged('前提 读回 实例='..h.r.name..' AbilityInputComponent有效=true 其AbilitySystem有效=true 武器组件有效=true 其AbilitySystem有效=true 其AbilityInput有效=true')==1)
    assert(h:count('restarted')==0 and h:count('slot direct')==1 and h:count('slot pointer')==0)
    assert(#h.wc.slots==2 and h.wc.slots[2].config==h.cfg.Tang)
    assert(h:logged('即将 装武器 实例='..h.r.name..' 武器组件:SetSlotWeapon(Main,1,')==1)
    assert(h:logged('直接传对象 调用=true 槽数1→2')==1 and h:logged('verified=true')==1 and h:logged('InputBindings 3→3')==1)
    assert(h.r.wep.slotted and #h.loops==1 and h.r.wep.spawned[tostring(h.newWeapon:GetAddress())]==h.newWeapon,'the new weapon actor is registered')
end)
test('an empty precondition field gets OnRestarted and a readback; still empty skips every weapon step',function()
    local h=fixture({body={noWeaponASC=true}});h.restartFills=true;h.mod:equip(h.r)
    assert(h:count('restarted')==1 and h:logged('即将 武器组件 OnRestarted(魂)')==1 and h:logged('OnRestarted 读回')==1 and h.r.wep.slotted)
    h=fixture({body={noInputASC=true}});h.mod:equip(h.r)
    assert(h:count('restarted')==1 and h:logged('跳过整个武器步骤 实例='..h.r.name..' 原因=AbilityInputComponent.AbilitySystem 无效')==1)
    assert(h:count('slot direct')==0 and #h.loops==0 and h.r.wep.skipped)
    h=fixture({body={noWeaponASC=true},steps=steps({restart=false})});h.mod:equip(h.r)
    assert(h:count('restarted')==0 and h:logged('跳过整个武器步骤')==1)
end)
test('SetSlotWeapon: a direct object the slot ignores is tried again as {ObjectPointer=cfg}, both logged, and the way that worked goes first next',function()
    local h=fixture();h.slotTakes='pointer';h.mod:equip(h.r)
    assert(h:count('slot direct')==1 and h:count('slot pointer')==1 and h:firstCall('slot direct')<h:firstCall('slot pointer'))
    assert(h:logged('直接传对象 调用=true 槽数1→1；{ObjectPointer} 调用=true 槽数1→2')==1 and h.r.wep.slotted)
    h.calls={};h:body();h.mod:equip(h.r)
    assert(h.calls[1]=='slot pointer' and h:count('slot direct')==0,'the pointer form is tried first after it worked')
end)
test('a slot that takes neither form fails; two bodies in a row switch the slot step off',function()
    local h=fixture();h.slotTakes='neither';h.mod:equip(h.r)
    assert(not h.r.wep.slotted and #h.loops==0 and h:count('slot nil')==0,'nothing to clear when the slot did not grow')
    h:body();h.mod:equip(h.r)
    assert(h.mod.off.slot and h:logged('已停用 装武器：连续 2 只魂失败')==1)
    h:body();h.mod:equip(h.r);assert(h:logged('装武器 本次加载已停用')==1)
end)
test('a slot that grew with another config is cleared with nil and its weapon actor destroyed',function()
    local h=fixture();h.slotWrongConfig=true;h.mod:equip(h.r)
    assert(not h.r.wep.slotted and h:count('slot nil')==1 and #h.wc.slots==1 and h:logged('清槽 读回 实例='..h.r.name..' 调用=true 槽数=1')==1)
    assert(h.newWeapon.destroying==true and h:logged('即将 销毁武器 Actor')==1)
end)
test('the forced switch 10 s into the battle goes through the game Change Weapon and is read back',function()
    local h=fixture();h.mod:equip(h.r)
    h:tick(9.6);assert(h:count('utils 1')==0,'not before 10 s')
    h:tick(0.6);assert(h:count('utils 1')==1 and h.wc.current==1)
    assert(h:logged('即将 换武器 实例='..h.r.name..' BPL_PBZCombatUtils:Change Weapon(魂,Main,1,Armed=true) 原因=开战10秒强制（验证用）')==1)
    assert(h:logged('方式=原版 Change Weapon 序号 0→1')==1 and h:logged('杀气 100→400（上限 400）')==1)
    assert(h:logged('受击表（只读）实例='..h.r.name..'（换到序号1后）')==1 and h:logged('走跑层（只读）')==2)
    h:tick(1.2);assert(h:logged('换武器 复读 实例='..h.r.name..' 序号=1')==1)
    h:tick(30);assert(h:count('utils 1')==1,'forced once')
end)
test('nothing is switched or pushed while the body executes or is executed',function()
    local h=fixture();h.mod:equip(h.r);local tags=h.actor.AbilitySystemComponent.tags
    tags['Ability.Executed']=1;h:tick(12);assert(h:count('utils 1')==0 and h.tried==nil)
    tags['Ability.Executed']=0;h:tick(0.2);assert(h:count('utils 1')==1)
    tags['Ability.Action.Execution']=1;local tries=h.tried;h:tick(2);assert(h.tried==tries)
end)
test('the battle clock only runs while the battle is active',function()
    local h=fixture();h.mod:equip(h.r);h.battle=false
    h:tick(20);assert(h:count('utils 1')==0)
    h.battle=true;h:tick(9.6);assert(h:count('utils 1')==0);h:tick(0.6);assert(h:count('utils 1')==1)
end)
test('a Change Weapon that cannot be called or does not read back falls to the Lua four steps, in order',function()
    local h=fixture();h.utilsError=true;h.mod:equip(h.r);h:tick(10.2)
    local i1,i2,i3=h:firstCall('current 1'),h:firstCall('armed'),h:firstCall('cooldown 1')
    assert(i1 and i2 and i3 and i1<i2 and i2<i3,'SetCurrentWeapon, then SetArmed, then the cooldown')
    assert(h.wc.current==1 and h.stats.values.Shachi==400 and h:logged('方式=Lua 四步')==1 and h:logged('原版 Change Weapon 读回')==1)
    assert(h.mod.utilsBroken==true)
    h=fixture();h.utilsIgnored=true;h.mod:equip(h.r);h:tick(10.2)
    assert(h:count('utils 1')==1 and h:count('current 1')==1 and h:logged('方式=Lua 四步')==1 and not h.mod.utilsBroken)
end)
test('four steps: any step that does not read back goes back to the own weapon and stops switching that body',function()
    local base=steps({utilsFirst=false})
    local h=fixture({steps=base});h.currentIgnored=true;h.mod:equip(h.r);h:tick(10.2)
    assert(h:count('armed')==0,'SetArmed only after SetCurrentWeapon read back')
    assert(h:logged('SetCurrentWeapon 调用=true 序号=0 verified=false')==1 and h:count('current 0')==1 and h:logged('切回绝影 读回')==1)
    h:tick(40);assert(h:count('current 1')==1,'no more switching on this body')
    h=fixture({steps=base});h.armedFails=true;h.mod:equip(h.r);h:tick(10.2)
    assert(h:logged('SetArmed 调用=true 读回=false verified=false')==1 and h.wc.current==0 and h:count('cooldown 1')==0)
    h=fixture({steps=base});h.stats.refuse=true;h.mod:equip(h.r);h:tick(10.2)
    assert(h:logged('杀气 Override 写入=false')==1 and h.wc.current==0 and h:logged('即将 切回绝影')==1)
    assert(h.mod.streak.switch==1)
end)
test('with the forced switch off, only a break or Shachi under 20 % with the cooldown done switches',function()
    local h=fixture({steps=steps({forceSwitchAt=false})});h.mod:equip(h.r)
    h:tick(20);assert(h:count('utils 1')==0)
    h.actor.AbilitySystemComponent.tags['CharacterState.Stand.Break']=1;h.wc.cd=3
    h:tick(1);assert(h:count('utils 1')==0,'native cooldown still running')
    h.wc.cd=0;h:tick(0.2);assert(h:count('utils 1')==1 and h:logged('原因=破防')>=1)
    h.actor.AbilitySystemComponent.tags['CharacterState.Stand.Break']=0;h.stats.values.Shachi=10;h.wc.cd=0
    h:tick(5);assert(h:count('utils 0')==0,'Lua cooldown of 15 s')
    h:tick(11);assert(h:count('utils 0')==1 and h:logged('原因=杀气<20%')>=1)
end)
test('combo: on the new weapon one push per 0.2 s at most, following the chain, with statistics',function()
    local h=fixture();h.mod:equip(h.r);h:tick(10.2)
    local before=h.tried or 0
    for _ in ipairs({1,2,3})do for _,fn in ipairs(h.loops)do fn()end end
    assert((h.tried or 0)-before<=1,'the same instant gives at most one push')
    local tags=h.actor.AbilitySystemComponent.tags
    tags['Ability.Action.Hun.Light.A.Normal']=1;h.calls={};h.t=h.t+0.2;for _,fn in ipairs(h.loops)do fn()end
    assert(h.calls[#h.calls]=='bytag Ability.Action.Hun.Light.AA','A is followed by AA')
    tags['Ability.Action.Hun.Light.AAAA']=1;h.t=h.t+0.2;for _,fn in ipairs(h.loops)do fn()end
    assert(h.calls[#h.calls]=='bytag Ability.Action.Hun.Light.AAAAA','the Tang chain before the generic one')
    assert(h:logged('出招 第一次 实例='..h.r.name..' 唐刀')==1 and h:logged('即将 AbilityInputComponent:TryActivateExternalActionAbilityByTag')==1)
    h.hp[h.enemy]=900;h:tick(6);assert(h:logged('出招统计 实例='..h.r.name..' 唐刀')>=1 and h.r.wep.stats.Tang.hits>=1)
    assert(h.mod.streak.combo==0)
end)
test('combo: no push out of range, while the input component refuses, or on the own weapon',function()
    local h=fixture();h.mod:equip(h.r);h.enemy.at=vec(2000,0,0);h:tick(12);assert(h.tried==nil)
    h.enemy.at=vec(200,0,0);h.busy=true;h:tick(1);assert(h.tried==nil)
    h.busy=false;h.wc.current=0;h.r.wep.idx=0;h:tick(1);assert(h.tried==nil)
end)
test('combo: the handle is the fallback when the tag call starts nothing; nothing starting 15 times goes back to the own weapon',function()
    local h=fixture({body={grants={{'/Game/GA_Hun_Tang_A.GA_Hun_Tang_A_C',7,{'Ability.Action.Hun.Light.A.Normal'}}}}})
    h.byTagWorks=false;h.mod:equip(h.r);h:tick(10.4)
    assert(h:count('activate hun 7')>=1 and h.r.wep.stats.Tang.byHandle>=1 and h:logged('即将 AbilitySystemComponent:TryActivateAbility(句柄)（出招备选')==1)
    h=fixture();h.byTagWorks=false;h.mod:equip(h.r);h:tick(10.2)
    h:tick(3.2)
    assert(h:logged('新武器出招不通 实例='..h.r.name..' 唐刀 连续 15 次没启动，切回绝影')==1 and h.wc.current==0 and h.r.wep.comboOff)
    assert(h.mod.streak.combo==1)
    local tries=h.tried;h:tick(3);assert(h.tried==tries,'no more pushes')
end)
test('grab: the DualHook body activates its GEx by handle, reads ActiveCount and the target grab state; the switch off does not',function()
    local GEX=L.DualHook.grab
    local h=fixture({body={grants={{GEX,42,{'Ability.Action.Hun.DualHook.GEx'}}}}})
    h.mod.bodies=1 -- the second body of the load takes DualHook
    h.mod:equip(h.r);assert(h.r.wep.weapon=='DualHook')
    h:tick(10.4)
    assert(h:count('activate hun 42')==1 and h:logged('即将 魂用投技 实例='..h.r.name..' GA_Hun_DualHook_GEx_C AbilitySystemComponent:TryActivateAbility(句柄=42)')==1)
    assert(h:logged('ActiveCount 0→1 启动=true')==1 and h.mod.streak.grab==0)
    h.enemy.AbilitySystemComponent.tags['Ability.Executed']=1
    h:tick(1.6);assert(h:logged('魂用投技 目标读回 实例='..h.r.name..' +0.4s')==1 and h:logged('+1.5s 目标=Thug_1 Ability.Executed=1')==1)
    h:tick(30);assert(h:count('activate hun 42')==1,'the spec is still active: no second activation')
    local off=fixture({steps=steps({grab=false}),body={grants={{GEX,42,{}}}}});off.mod.bodies=1;off.mod:equip(off.r);off:tick(12)
    assert(off:count('activate hun 42')==0)
    local missing=fixture();missing.mod.bodies=1;missing.mod:equip(missing.r);missing:tick(10.4)
    assert(missing:logged('魂用投技 实例='..missing.r.name..' 别离残钩；技能 GA_Hun_DualHook_GEx_C 没授予（spec 不在）')==1)
end)
test('victim grab: off by default; on, a broken body asks the opponent once per break, never a QTE family',function()
    local h=fixture();spec(h.enemy.AbilitySystemComponent,'/Game/GA_Thug_CA_01_GEx.GA_Thug_CA_01_GEx_C',9,{})
    h.mod:equip(h.r);h.actor.AbilitySystemComponent.tags['CharacterState.CanWeakExecute.Weak']=1;h:tick(5)
    assert(h:count('activate enemy 9')==0)
    h=fixture({steps=steps({victimGrab=true,forceSwitchAt=false})});spec(h.enemy.AbilitySystemComponent,'/Game/GA_Thug_CA_01_GEx.GA_Thug_CA_01_GEx_C',9,{})
    h.mod:equip(h.r);local tags=h.actor.AbilitySystemComponent.tags;tags['CharacterState.CanWeakExecute.Weak']=1;h:tick(3)
    assert(h:count('activate enemy 9')==1 and h:logged('请对手出投技 读回 实例='..h.r.name..' GA_Thug_CA_01_GEx_C 调用=true 返回=true ActiveCount 0→1 启动=true')==1)
    tags['CharacterState.CanWeakExecute.Weak']=0;h:tick(0.4);h.enemy.AbilitySystemComponent.specs[1].ActiveCount=0
    tags['CharacterState.CanWeakExecute.Weak']=1;h:tick(0.4);assert(h:count('activate enemy 9')==2,'a new break asks again')
    h=fixture({steps=steps({victimGrab=true})});spec(h.enemy.AbilitySystemComponent,'/Game/GA_Thug_CA_01_GEx.GA_Thug_CA_01_GEx_C',9,{})
    h.qte=h.enemy;h.mod:equip(h.r);h.actor.AbilitySystemComponent.tags['CharacterState.CanWeakExecute.Weak']=1;h:tick(3)
    assert(h:count('activate enemy 9')==0 and h:logged('是 QTE 族，按 QTE 闸不请')==1)
end)
test('cleanup destroys registered weapon actors that are still the body\'s and leaves those that moved elsewhere',function()
    local h=fixture();h.mod:equip(h.r);h.mod:cleanup(h.r,'实例离场')
    assert(h.newWeapon.destroying==true and h:logged('清理武器 Actor 实例='..h.r.name..' 原因=实例离场 BP_Weapon_Hun_New_1=调用true/已销毁')==1)
    h=fixture();h.mod:equip(h.r);h.weaponOwner=object('Pool');h.mod:cleanup(h.r,'实例离场')
    assert(h:count('destroy weapon')==0 and h:logged('已归别处（Pool），不动')==1)
    h=fixture();h.mod:equip(h.r);h:tick(10.2);h.mod:cleanup(h.r,'x')
    assert(h:count('destroy weapon')==1,'the body\'s own weapons, slot 0, are never registered')
end)
test('the loop stops on leave, on a changed identity and on unload; the switch off equips nothing',function()
    local h=fixture();h.mod:equip(h.r);h.mod:stop(h.r,'实例离场');assert(h.cancelled[1] and h:logged('武器循环结束 实例='..h.r.name..' 原因=实例离场')==1)
    h:tick(12);assert(h:count('utils 1')==0)
    h=fixture();h.mod:equip(h.r);h.gone=h.r;h:tick(0.2);assert(h.cancelled[1] and h:logged('原因=实例离场或已变化')==1)
    h=fixture();h.mod:equip(h.r);h.mod:silence();assert(h.cancelled[1])
    h=fixture({steps=steps({enabled=false})});h.mod:equip(h.r);assert(#h.calls==0 and #h.logs==0 and #h.loops==0)
end)
test('a native error inside the loop is logged and stops that body\'s loop',function()
    local h=fixture();h.mod:equip(h.r)
    -- Native getters that throw are absorbed by call(); a Lua error in the loop itself stops the loop.
    h.wc.GetCurrentWeaponIndex=function()error('native fixture failure')end
    h.actor.AbilitySystemComponent.GetGameplayTagCount=function()error('native fixture failure')end
    h:tick(0.2);assert(h:logged('武器循环中断')==0,'absorbed')
    h.opponents=setmetatable({},{__index=function()error('fixture loop failure')end})
    h:tick(0.2)
    assert(h:logged('武器循环中断 实例='..h.r.name..' 原因=')==1 and h.cancelled[1] and h:logged('武器循环结束 实例='..h.r.name..' 原因=中断')==1)
end)
test('switch breaker: two bodies in a row whose switch fails switch it off for the load',function()
    local h=fixture({steps=steps({utilsFirst=false})});h.currentIgnored=true
    h.mod:equip(h.r);h:tick(10.2)
    local r1=h.r;h.mod:stop(r1,'x');h.loops={};h:body();h.mod:equip(h.r);h.t=0;h:tick(10.2)
    assert(h.mod.off.switch and h:logged('已停用 换武器：连续 2 只魂失败')==1)
    h.mod:stop(h.r,'x');h.loops={};h:body();h.mod:equip(h.r);h.t=0;h:tick(10.2)
    assert(h:logged('换武器 本次加载已停用')==1)
end)
test('the combo data covers every slot weapon with ground actions and combos',function()
    local data=require('hun_weapon_combos')
    for _,name_ in ipairs({'Tang','DualHook','ZhanMa'})do
        local chain=data[name_];assert(chain and #chain.actions>=2 and #chain.combos>=5,name_)
        for _,e in ipairs(chain.combos)do assert(type(e.tag)=='string' and #e.req>=1)end
    end
end)
local Catalog=require('hun_weapon_catalog')
local Rotation=require('hun_weapon_rotation')
local function item(native,weight,level)
    for _,row in ipairs(Catalog.rows) do
        if row.native_id==native then return {id=row.id,native_id=native,path=row.path,weight=weight or 1,level=level or 1,soul=false} end
    end
    error(native)
end
local function armed(profile,body,construct,nativeTarget)
    local h=fixture({profile=true,body=body,construct=construct,nativeTarget=nativeTarget})
    for p in pairs(Catalog.configs) do
        if not h.assets[p] then h.assets[p]=object('Weapon '..p) end
    end
    h.r.loadout=profile
    h.mod:equip(h.r)
    return h
end

test('the whole catalog has native power tiers, a real input chain and matching weapon execution pairs',function()
    local pairsFor=require('hun_weapon_execution_data').forConfig
    local ids,paths={},{}
    assert(#Catalog.rows==33 and #pairsFor(nil)==0 and #pairsFor('unknown')==0)
    for _,row in ipairs(Catalog.rows) do
        assert(not ids[row.id] and #row.multipliers>=1 and row.multipliers[1]==1);ids[row.id]=true
        for _,p in ipairs({row.path,row.soulPath}) do
            if p~='' and not paths[p] then
                paths[p]=true
                assert(#Rotation.chain(Catalog.configs[p]).actions>0 and #Rotation.chain(Catalog.configs[p],true).actions>0)
                local pairs=pairsFor(p);assert(#pairs>0,p)
                for _,pair in ipairs(pairs) do
                    assert(pair.victim_skeleton and pair.timing.executor>0 and pair.timing.clip_from<pair.timing.clip_to)
                    assert(pair.timing.executed[pair.executed:match('%.([^%.]+)$')]>0)
                    assert(type(pair.executor_required)=='table' and type(pair.target_ignored)=='table')
                end
            end
        end
    end
    local count,records=0,0;for path in pairs(paths) do count=count+1;records=records+#pairsFor(path) end
    assert(count==36 and records==82)
    assert(#Rotation.new({}).pool==33 and #Rotation.new({loadout={weapons={}}}).pool==0)
end)
test('weighted rotation avoids repeats, respects zero weight, phase choices and per-body failure limits',function()
    local a,b,c=item('Tang'),item('DualHook'),item('Jigsaw',0)
    local s=Rotation.new({loadout={weapons={a,b,c},ai={late_weapon_bias=false,repeat_policy='none'}}})
    assert(#s.pool==2 and Rotation.pick(s,nil,function()return 0 end).id==a.id)
    assert(Rotation.pick(s,nil,function()return .55 end).id==b.id)
    s.ai.late_weapon_bias=true
    assert(Rotation.pick(s,nil,function()return .45 end).id==b.id)
    Rotation.chosen(s,s.pool[2])
    assert(Rotation.pick(s,nil).id==a.id and Rotation.pick(s,b.id).id==b.id)
    s.failures[a.id]=2;assert(Rotation.pick(s,nil)==nil)
    assert(Rotation.new({loadout={weapons={a}}}).failures[a.id]==nil)
end)
test('profile rotations rewrite only the opposite slot, obey intent and scope level returns to actor and config',function()
    local a,b=item('Tang',1,15),item('IronBlade',1,2)
    local h=armed({weapons={a,b},resources={cooldown_scale=1}})
    local old=h.wc.SetSlotWeapon
    function h.wc:SetSlotWeapon(tag,i,cfg)assert(i~=self.current,'overwrote an active slot');return old(self,tag,i,cfg) end
    h.r.intent={weapon_id=a.id,busy=true};h:tick(1);assert(not h.r.wep.active)
    h.r.intent.busy=false;h:tick(.2)
    assert(h.r.wep.currentId==a.id and h.wc.current==1 and h.r.wep.active.level==15)
    assert(h.powerCallback(h.assets[a.path],h.actor)==h.r.wep.active.multipliers[15])
    assert(h.powerCallback(h.assets[b.path],h.actor)==nil and h.powerCallback(h.assets[a.path],h.player)==nil)
    h.r.intent.weapon_id=b.id;h:tick(13);assert(h.wc.current==1)
    h:tick(2);assert(h.wc.current==0 and h.r.wep.currentId==b.id and #h.wc.slots==2)
    h.mod:silence();assert(h.powerCallback==nil)
end)
test('phase completion needs the equipped native art spec to activate, matching the exact phase id',function()
    local a=item('HeiMoShang');local art=Catalog.configs[a.path].art
    local h=armed({weapons={a}},{grants={{art,125,{}}}})
    h.r.intent={weapon_id=a.id,phaseId='low_hp'}
    h.refuseActivate=true;h:tick(.6);assert(h.r.wep.currentId==a.id and not h.r.intent.performedPhase)
    h.refuseActivate=false;h:tick(1.2);assert(h.r.intent.performedPhase=='low_hp' and h:count('activate hun 125')>=1)
end)
test('level and soul gated effects apply once and remove only the captured equip-only handle',function()
    local a=item('IronBlade',1,60);a.soul=true
    local s=Rotation.new({loadout={weapons={a}}})
    local active=s.pool[1];local counts,handles={},{}
    local immune='preexisting'
    local ascObj=object('asc')
    function ascObj:GetGameplayEffectCount(cls)return counts[cls] or 0 end
    function ascObj:BP_ApplyGameplayEffectToSelf(cls,level)
        assert(level>=1);counts[cls]=1;handles[#handles+1]=cls;return {id=#handles}
    end
    function ascObj:RemoveActiveGameplayEffect(handle)
        assert(type(handle.id)=='number' and handles[handle.id]~=immune)
        counts[handles[handle.id]]=0;return true
    end
    local api={object=function(p)return p end,say=function()end,call=function(o,k,...)return true,o[k](o,...)end}
    active.effects={{immune,1,1,true,false},{'level',5,1,true,false},{'soul',1,1,true,true},{'persistent',1,1,false,false}}
    counts[immune]=1;active.level=1;active.soul=false
    Rotation.effects(s,active,ascObj,api);assert(#handles==1 and counts.persistent==1)
    active.level=5;active.soul=true
    Rotation.effects(s,active,ascObj,api);Rotation.effects(s,active,ascObj,api)
    assert(#handles==3 and counts.level==1 and counts.soul==1)
    Rotation.effects(s,nil,ascObj,api)
    assert(counts.level==0 and counts.soul==0 and counts.persistent==1 and counts[immune]==1)
end)
test('a failed inactive-slot switch retains the active configuration and retries on a bounded timer',function()
    local a=item('Tang');local h=armed({weapons={a}})
    local original=h.wc.slots[1].config
    h.utilsError=true;h.currentIgnored=true
    h:tick(.3)
    assert(h.wc.current==0 and h.wc.slots[1].config==original and not h.wc.slots[2] and not h.r.wep.active)
    assert(h.r.wep.rotation.failures[a.id]==1)
    h:tick(3);assert(h.r.wep.rotation.failures[a.id]==2)
    local attempts=h:count('slot direct');h:tick(5);assert(h:count('slot direct')==attempts)
end)
test('temp weapons require private storage, and the lion head follows its own pole pickup setting',function()
    local variants,head={},nil
    for _,v in pairs(Catalog.variants) do
        local entry={id=v.id,path=v.path,weight=1,level='max'}
        if v.poleOnly then head=entry else variants[#variants+1]=entry end
    end
    assert(#variants==3 and head and not Rotation.allowsPoleHead({variants=variants}))
    variants[#variants+1]=head;assert(Rotation.allowsPoleHead({variants=variants}))
    assert(#Rotation.new({loadout={weapons={},variants=variants}}).pool==3)
    local sharedClass=object('BlueprintGeneratedClass TempWeaponConfig')
    local passive=object('Class /Script/PBZCombatAsset.GA_TempWeaponPassive')
    local alias=false
    local function construct(cls,outer,label,flags,unused,a,b,original)
        assert(cls==sharedClass and flags==0x40)
        local copy=object(label)
        function copy:GetOuter()return outer end
        function copy:GetClass()return cls end
        copy['Equip Passive Abilities']=alias and original['Equip Passive Abilities'] or {passive}
        return copy
    end
    local v=variants[1]
    local function setup()
        local h=armed({weapons={},variants={v}},nil,construct)
        local source=h.assets[v.path]
        function source:GetClass()return sharedClass end
        source['Equip Passive Abilities']={passive}
        h:tick(.3)
        assert(source['Equip Passive Abilities'][1]==passive)
        return h,source
    end
    local h,source=setup()
    assert(h.r.wep.currentId==v.id and h.r.wep.currentConfig~=source and #h.r.wep.currentConfig['Equip Passive Abilities']==0)
    alias=true;h=setup();assert(not h.r.wep.active and #h.wc.slots==1)
end)
test('an animation notify commits the prepared weapon exactly once without a direct second switch',function()
    local a,b=item('Tang'),item('Double')
    local h=armed({weapons={a,b},resources={cooldown_scale=0}})
    h.r.intent={weapon_id=a.id};h:tick(.3);assert(h.r.wep.currentId==a.id)
    local change='/PBZInput/InputActions/IA_ChangeWeapon.IA_ChangeWeapon'
    h.assets[change]=object('change')
    local tags=h.actor.AbilitySystemComponent.tags
    tags['CharacterState.Talent.EnableDrawAttack']=1
    function h.actor:HasActorBegunPlay()return true end
    local aic=h.actor['Ability Input Component']
    function aic:ForceActivateExternalActionAbilityByTag(tag,action)
        assert(action==h.assets[change])
        tags[tag.TagName]=1
        h.wc.current=0
        return true
    end
    h.r.intent.weapon_id=b.id;h:tick(.6)
    assert(h.r.wep.currentId==b.id and h:count('utils 0')==0 and h.r.wep.switches==2)
end)
test('pending native slot never receives a second slot mutation, and phase state commits on the actual index',function()
    local a=item('Tang');local h=armed({weapons={a}})
    function h.wc:GetCurrentWeaponIndex(slot,pending)return pending and (self.pending or self.current) or self.current end
    h.utils['Change Weapon']=function(_,_,slot,i)h.wc.pending=i;return true end
    h:tick(.6);assert(h.r.wep.pendingSwitch and h.r.wep.currentId==nil and h:count('slot direct')==1)
    h.wc.current=1;h.wc.pending=nil;h:tick(.3)
    assert(h.r.wep.currentId==a.id and not h.r.wep.pendingSwitch and h:count('slot direct')==1)
end)
test('private motion/weapon hit configuration are checked by owner, and stop restores the original loadout',function()
    local a,b=item('Tang'),item('Long')
    local src=object('ActorConfig NPC');local cls=object('ActorConfig class')
    local originalSet=object('OriginalHitSet');src['Hitreat Anim Set']=originalSet
    function src:GetClass()return cls end
    local copied
    local function construct(class,outer,_,_,_,_,_,template)
        assert(template==src and class==cls)
        copied=object('PrivateHit',{['Hitreat Anim Set']=template['Hitreat Anim Set']})
        function copied:GetClass()return class end
        function copied:GetOuter()return outer end
        return copied
    end
    local h=armed({weapons={a,b},resources={cooldown_scale=0}},nil,construct)
    local originalWeapon=h.wc.slots[1].config
    local hit=object('HitComponent',{ActorConfig=src})
    function hit:GetOwner()return h.actor end
    h.actor['Hitreact Component']=hit
    local combined=object('Combined');h.assets['/PBZCombatAsset/ActorData/Players/Hun/Hit_Hun_Combined.Hit_Hun_Combined']=combined
    local mesh=object('mesh')
    local oldClass=object('npcClass');local loco=object('locoClass')
    h.assets[Weapons.PATHS.locomotion]=loco
    local old=object('originalGraph');function old:GetClass()return oldClass end
    local linked=object('linkedGraph',{WeaponType=3});function linked:GetClass()return loco end
    function linked:TryGetPawnOwner()return h.actor end
    local move=object('movement')
    function move:GetOwner()return h.actor end
    function h.actor:GetMovementComponent()return move end
    local instance=object('anim',{graph=old})
    function instance:GetLinkedAnimGraphInstanceByTag()return self.graph end
    function instance:LinkAnimGraphByTag(tag,class)self.graph=class==loco and linked or old end
    function mesh:GetAnimInstance()return instance end
    h.actor.Mesh=mesh
    h.r.intent={weapon_id=a.id}
    h:tick(.2);assert(hit.ActorConfig==copied and copied['Hitreat Anim Set']==combined and src['Hitreat Anim Set']==originalSet)
    assert(instance.graph==linked and linked.CharacterMovement==move and linked.WeaponType==0)
    h.r.intent.weapon_id=b.id;h:tick(.2);assert(linked.WeaponType==2)
    h.mod:stop(h.r,'停止')
    assert(hit.ActorConfig==src and instance.graph==old and h.wc.current==0 and #h.wc.slots==1 and h.wc.slots[1].config==originalWeapon)
end)
test('free combat art settles only its own charge debit and isolates hand feedback from the player',function()
    local a=item('HeiMoShang');local art=Catalog.configs[a.path].art
    local h=armed({weapons={a},resources={consume_skill_resources=false}},{grants={{art,126,{}}}})
    h.stats.values.UltimateChargeCount=0
    local ctx=object('SkillInstance');local cls=object('BlueprintGeneratedClass '..art)
    function ctx:GetClass()return cls end
    function ctx:GetAvatarActorFromActorInfo()return h.actor end
    local other=object('RealPlayerAbility')
    function other:GetClass()return cls end
    function other:GetAvatarActorFromActorInfo()return h.player end
    local asc_=h.actor.AbilitySystemComponent;local original=asc_.TryActivateAbility
    function asc_:TryActivateAbility(handle,remote)
        if handle.Handle==126 then
            local lib=h.assets['/Script/Engine.Default__GameplayStatics']
            assert(lib:GetPlayerController(ctx,0)~=h.player and lib:GetPlayerController(other,0)==h.player)
            assert(h.stats.values.UltimateChargeCount==1)
            h.stats.values.Shachi=h.stats.values.Shachi-30
        end
        return original(self,handle,remote)
    end
    h.r.intent={phaseId='free',weapon_id=a.id}
    h:tick(.6);assert(h.r.intent.performedPhase=='free' and h.stats.values.UltimateChargeCount==0)
    assert(h.stats.values.Shachi==370)
    h.stats.values.UltimateChargeCount=2
    h.r.intent.phaseId='free2';asc_.specs[#asc_.specs].ActiveCount=0
    -- The free policy restores the exact debit while preserving an already funded charge.
    asc_.TryActivateAbility=original
    h:tick(1.6);assert(h.r.intent.performedPhase=='free2' and h.stats.values.UltimateChargeCount==2)
end)
test('a weapon and its opponent must each target the intended actor before a forced grab',function()
    local a=item('Tang')
    local h=armed({weapons={a}},nil,nil,function(f,actor)
        if actor==f.actor then return f.nativeOpponent end
        if actor==f.enemy then return f.enemyVictim end
    end)
    h.nativeOpponent=h.player;h:tick(.3)
    assert(not h.r.wep.active and #h.wc.slots==1)
    h.nativeOpponent=h.enemy;h.enemyVictim=h.player
    h.actor.AbilitySystemComponent.tags['CharacterState.CanWeakExecute.Weak']=1
    spec(h.enemy.AbilitySystemComponent,'/Game/GA_Thug_CA_01_GEx.GA_Thug_CA_01_GEx_C',99,{})
    h:tick(.6);assert(h.r.wep.active and h:count('activate enemy 99')==0)
    h.enemyVictim=h.actor;h:tick(.2);assert(h:count('activate enemy 99')==1)
end)
test('native cooldown is scaled on the owned component and shorter native timers stay usable',function()
    local a,b=item('Tang'),item('Double')
    local h=armed({weapons={a,b},resources={cooldown_scale=.25}})
    local call=h.utils['Change Weapon']
    h.utils['Change Weapon']=function(self,...)local result=call(self,...);h.wc.cd=8;return result end
    function h.wc:ReduceChangeWeaponCooldown(seconds)self.reduction=seconds;self.cd=self.cd-seconds end
    h.r.intent={weapon_id=a.id};h:tick(.2)
    assert(h.wc.reduction==6 and h.wc.cd==2)
    h.r.intent.weapon_id=b.id;h:tick(.3);assert(h.r.wep.currentId==a.id)
    h.wc.cd=0;h:tick(.3);assert(h.r.wep.currentId==b.id)
end)
print('hun weapons: PASS '..n..' precondition/slot/switch/combo/grab/victim/cleanup/breaker checks; native gameplay remains unverified')
