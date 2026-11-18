package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Shachi=require('hun_shachi')
local Data=require('hun_shachi_data')
local id=0
local function object(path)
    id=id+1
    local key=id
    return {IsValid=function()return true end, GetAddress=function()return key end,
            GetFullName=function()return 'Object '..path end}
end
local function map(value)
    local m={v={a=value}}
    function m:ForEach(fn) for name,n in pairs(self.v) do fn({TagName=name},n) end end
    function m:Add(k,v) self.v[k.TagName]=v end
    function m:Remove(k) self.v[k.TagName]=nil end
    return m
end
local function fixture(item,soul)
    if soul==nil then soul=true end
    item=item or Data.items[1]
    local h={owner=true,casts=0,cancels=0,now=0,logs={},sets=0,refused=false,nativePower=1,grants=true}
    local a,enemy=object('body'),object('enemy')
    local wc,asc=object('weapons'),object('abilities')
    local aic=object('inputs')
    a['Character Weapons Component']=wc;a['AbilitySystemComponent']=asc;a['Ability Input Component']=aic
    wc.GetOwner=function() return a end;asc.GetOwner=wc.GetOwner;aic.GetOwner=wc.GetOwner
    function aic:CanActivateExternalActionAbility()return not h.busy end
    local attrs={SpiritShadow_Max=0,SpiritShadow=0,ShachiRegen=0,ShachiRegenCooldown=2}
    local stats={}
    function stats:read(actor,f) assert(actor==a);return {current=attrs[f]} end
    function stats:writeBase(actor,f,v) assert(actor==a);attrs[f]=v;return true end
    local cls=object('class')
    local cache, counts={},{}
    local modelA,modelB=object('combatModel'),object('variantModel')
    local path=soul and item.soul~='' and item.soul or item.normal
    local function find(p)
        if not cache[p] then
            local v=object(p);cache[p]=v
            function v:GetClass()return cls end
            if p==path or p==item.donor then
                v['Weapon Attack Multipliers']=map(2);v['Weapon Attack Multipliers Normalized']=map(3)
                v['Display Data']={{WeaponClass=(item.displayDiff and p==path) and modelB or modelA,ArmedSocket='weapon_r',UnarmedSocket='weapon_r',ScabbardSocket='None'}}
                v['Equip Passive Abilities']={object('/Abilities/Combat_C'),object('/Abilities/GA_ThunderSpear_ParalyzeAchievement_C')}
            end
            function v:GetActiveGameplayEffectStackCount(handle)return counts[handle.Handle] or 0 end
        end
        return cache[p]
    end
    local function construct(c,outer,name,flags,_,__,___,src)
        assert(c==cls and outer==a and flags==0x40)
        if h.badCopy then return src end
        h.templatePath=src:GetFullName():match('^Object (.*)$')
        local v=object(name)
        v['Display Data']={table.unpack(src['Display Data'])}
        v.GetClass=src.GetClass
        function v:GetOuter()return a end
        function v:GetWeaponPowerMultiplier(actor)assert(actor==a);return h.nativePower end
        for _,k in ipairs({'Weapon Attack Multipliers','Weapon Attack Multipliers Normalized'})do v[k]=map(src[k].v.a) end
        v['Equip Passive Abilities']={table.unpack(src['Equip Passive Abilities'])}
        return v
    end
    local rows={}
    asc.ActivatableAbilities={Items=rows}
    local function grants()
        for i=#rows,1,-1 do rows[i]=nil end
        if not h.grants then return end
        local used={}
        for _,move in ipairs(Data.moves[path]) do
            if not used[move.cls] then
                local inst=object('instance')
                local spec={Ability=object(move.cls:gsub('%.','.Default__')),Handle={Handle=#rows+1},ActiveCount=0,NonReplicatedInstances={inst}}
                function inst:GetAvatarActorFromActorInfo()return h.foreignAvatar and enemy or a end
                function inst:K2_CancelAbility()h.cancels=h.cancels+1;spec.ActiveCount=0 end
                rows[#rows+1]=spec;used[move.cls]=true
            end
        end
    end
    wc.slots={};wc.active=-1
    function wc:GetSlotWeapon(slot,i,out)assert(slot.TagName=='Weapon.Slot.ShaChi');out.WeaponConfig=self.slots[i] end
    function wc:SetSlotWeapon(slot,i,value)assert(slot.TagName=='Weapon.Slot.ShaChi');h.sets=h.sets+1;self.slots[i]=value end
    function wc:GetCurrentWeaponIndex()return self.active end
    function wc:SetCurrentWeapon(slot,i)if not h.refused then self.active=i;grants() end end
    function asc:GetGameplayTagCount(tag)if h.tags then return h.tags[tag.TagName] or 0 end;return tag.TagName=='CharacterState.Space.Ground' and 1 or 0 end
    function asc:GetGameplayEffectCount(effect)return 0 end
    function asc:BP_ApplyGameplayEffectToSelf(effect,level)
        assert(level>=0);local k=effect:GetAddress();counts[k]=1
        return {Handle=k}
    end
    function asc:RemoveActiveGameplayEffect(handle)counts[handle.Handle]=0 end
    function asc:TryActivateAbility(handle)
        if h.refuseAction then return false end
        assert(rows[handle.Handle].ActiveCount==0)
        h.casts=h.casts+1
        if not h.instant then rows[handle.Handle].ActiveCount=1 end
        attrs.SpiritShadow=math.max(0,attrs.SpiritShadow-1)
        return true
    end
    h.r={actor=a,name='hun',loadout={shadows={{id=item.id,path=path,weight=1,level=60,soul=soul}},resources={}}}
    h.mod=Shachi.new({current=function(r)return r==h.r and h.owner end,stats=function()return stats end,find=find,load=find,
        nativeTarget=function()return h.targetReadback or enemy end,
        registerHook=function()return 1,2 end,unregisterHook=function()end,
        construct=construct,fname=function(n)return n end,random=function()return 0.1 end,log=function(x)h.logs[#h.logs+1]=x end})
    h.ctx={now=0,target=enemy,distance=200}
    function h:tick(t)self.ctx.now=t;return self.mod:tick(self.r,self.ctx) end
    h.attrs,h.wc,h.asc,h.rows,h.source,h.counts=attrs,wc,asc,rows,find(path),counts
    return h
end
local count=0
local function check(label,fn)
    local ok,e=pcall(fn)
    assert(ok,label..': '..tostring(e))
    count=count+1
end
check('28 independent rows and both configurations have native grants and durations',function()
    local seen={}
    assert(#Data.items==28)
    for _,item in ipairs(Data.items) do
        assert(not seen[item.id]);seen[item.id]=true
        for _,path in ipairs({item.normal,item.soul}) do
            if path~='' then
                assert(#Data.moves[path]>0)
                for _,m in ipairs(Data.moves[path]) do assert(m.duration>=1 and m.cost>=0 and m.cls:sub(-2)=='_C') end
            end
        end
    end
end)
check('native cast, normal shadow cost, isolated level 60 and soul multiplier',function()
    local h=fixture()
    assert(h:tick(0));assert(h.casts==1 and h.attrs.SpiritShadow==3)
    local slot=h.wc.slots[0]
    assert(slot~=h.source and math.abs(slot['Weapon Attack Multipliers'].v.a-3*6.9)<0.00001)
    assert(h.source['Weapon Attack Multipliers Normalized'].v.a==3 and h.source['Weapon Attack Multipliers'].v.a==2)
    assert(h:tick(0.5) and h.casts==1)
    h.mod:cleanup(h.r);assert(h.wc.slots[0]==nil)
    for _,n in pairs(h.counts) do assert(n==0) end
end)
check('explicit unawakened level and native power correction',function()
    local h=fixture()
    h.nativePower=2;h.r.loadout.shadows[1].soul=false;h.r.loadout.shadows[1].level=6
    assert(h:tick(0))
    assert(math.abs(h.wc.slots[0]['Weapon Attack Multipliers Normalized'].v.a-1.5)<0.00001)
end)
check('foreign record, unverified clone and wrong component never receive a write',function()
    local h=fixture();h.owner=false;assert(not h:tick(0) and h.sets==0 and h.attrs.SpiritShadow==0)
    h=fixture();h.badCopy=true;assert(not h:tick(0) and h.sets==0)
    h=fixture();h.wc.GetOwner=function()return h.ctx.target end;assert(not h:tick(0) and h.sets==0)
end)
check('empty/zero-weight loadout and situational guards',function()
    local h=fixture();h.r.loadout.shadows={};assert(not h:tick(0) and h.sets==0)
    h=fixture();h.r.loadout.shadows[1].weight=0;assert(not h:tick(0) and h.sets==0)
    h=fixture();h.ctx.allowShadow=false;assert(not h:tick(0) and h.sets==0)
    h.ctx.allowShadow=true;h.ctx.distance=4000;assert(not h:tick(2) and h.sets==0)
    h.ctx.distance=100;h.ctx.busy=true;assert(not h:tick(4) and h.sets==0)
end)
check('config or grant failure restores the original slot',function()
    for _,k in ipairs({'refused','grants'})do
        local h=fixture();local old=object('original');h.wc.slots[0]=old
        h[k]=k=='refused'
        assert(not h:tick(0) and h.wc.slots[0]==old and h.casts==0)
        local writes=h.sets;assert(not h:tick(1.1) and h.sets==writes)
    end
end)
check('native failed activation, empty owned resource, user-owned custom resources',function()
    local h=fixture();h.r.loadout.attributes={SpiritShadow=2,SpiritShadow_Max=7,ShachiRegen=0.5}
    h.refuseAction=true;assert(not h:tick(0) and h.casts==0 and h.attrs.SpiritShadow==2 and h.attrs.ShachiRegen==0.5)
    h=fixture();h.r.loadout.attributes={SpiritShadow=0};assert(not h:tick(0) and h.casts==0 and h.attrs.SpiritShadow==0)
end)
check('free skill setting refunds its own cast and instant cast',function()
    for _,instant in ipairs({false,true}) do
        local h=fixture();h.r.loadout.resources.consume_skill_resources=false;h.instant=instant
        assert(h:tick(0) and h.attrs.SpiritShadow==4)
    end
end)
check('cancel exact owned spec after its native timeline and never cancel foreign actor',function()
    local h=fixture();assert(h:tick(0));h.ctx.allowShadow=false
    assert(h:tick(1) and h.cancels==0)
    h:tick(80);assert(h.cancels==1);h:tick(81);assert(h.cancels==1)
    h=fixture();h.foreignAvatar=true;assert(h:tick(0));h:tick(80);assert(h.cancels==0)
end)
check('ThunderSpear private copy excludes achievement passive and keeps combat passive',function()
    local item=Data.items[22];local h=fixture(item);assert(h:tick(0))
    assert(#h.wc.slots[0]['Equip Passive Abilities']==1 and #h.source['Equip Passive Abilities']==2)
end)
check('summon blueprint corrections apply only to the owned child and deregister cleanly',function()
    local M=require('hun_shachi_summons')
    local h, callbacks, unloaded, lines = {}, {}, {}, {}
    local world,parent,child,foreign = object('world'),object('parent'),object('minion'),object('foreign')
    local npcClass=object('/Game/NPC.NPC_C')
    local native=object('/Script/ProjectPBZ.PBZCharacter_NPC')
    function native:GetFullName()return 'Class /Script/ProjectPBZ.PBZCharacter_NPC' end
    function npcClass:GetSuperStruct()return native end
    for _,actor in ipairs({parent,child,foreign})do
        function actor:GetClass()return npcClass end
        function actor:GetOuter()return world end
        actor.AbilitySystemComponent=object('asc')
        function actor.AbilitySystemComponent:GetOwner()return actor end
    end
    local passive='/Game/Shadow/GA_Summon.GA_Summon_C'
    local pclass=object(passive)
    local ab=object('cast')
    function ab:GetClass()return pclass end
    function ab:GetAvatarActorFromActorInfo()return h.parent or parent end
    function child:GetGlobalCombatConfig()return {IsValid=function()return true end,GetGlobalMobLevelOffset=function()return 2 end} end
    child.Level=4;child.Owner=parent
    local assets={}
    local function asset(path)if not assets[path] then assets[path]=object(path) end;return assets[path] end
    h.stacks={};h.destroy=false
    local parentAsc,childAsc=parent.AbilitySystemComponent,child.AbilitySystemComponent
    function childAsc:GetGameplayEffectCount(cls,source)assert(source==parentAsc);return h.stacks[cls]or 0 end
    function parentAsc:BP_ApplyGameplayEffectToTarget(cls,dest)assert(dest==childAsc);h.stacks[cls]=1 end
    function childAsc:RemoveActiveGameplayEffectBySourceEffect(cls,source)assert(source==parentAsc);h.stacks[cls]=0 end
    function child:IsActorBeingDestroyed()return h.destroy end
    function child:K2_DestroyActor()h.destroy=true end
    local r={actor=parent,world=tostring(world:GetAddress())}
    local mod=M.new({current=function(v)return v==r end,asset=asset,say=function(_,msg)lines[#lines+1]=msg end,
        register=function(path,cb)callbacks[path]=cb;return 10,20 end,
        unregister=function(path,first,last)assert(first==10 and last==20);unloaded[path]=true end})
    local low,high='/GE/Low','/GE/High'
    local rules={[passive]={{path=low,level=5},{path=high,level=25}}}
    assert(mod:arm(r,{level=15},rules))
    h.stacks[asset(high)]=1
    local prefix='/PBZCombatAsset/ActorData/Players/Hun/Abilities/ShachiAbility/GA_SummonPassive_Hun.GA_SummonPassive_Hun_C:'
    h.parent=foreign;callbacks[prefix..'OnDeferedSpawn'](ab,child);assert(child.Level==4)
    h.parent=parent;callbacks[prefix..'OnDeferedSpawn'](ab,child);assert(child.Level==17)
    callbacks[prefix..'OnSpawnFinish'](ab,child)
    assert(h.stacks[asset(low)]==1 and h.stacks[asset(high)]==0)
    mod:cleanup(r);assert(h.destroy and unloaded[prefix..'OnDeferedSpawn'])
end)

check('all 28 catalog selections activate an owned granted move in a matching scenario',function()
    local runs=0
    for _,item in ipairs(Data.items) do
        for _,soul in ipairs({false,true}) do
            local h=fixture(item,soul)
            local path=soul and item.soul~='' and item.soul or item.normal
            local m=Data.moves[path][1];h.tags={}
            for _,name in ipairs(m.needs) do h.tags[name]=1 end
            assert(h:tick(0) and h.casts==1,item.label..' '..path)
            runs=runs+1
        end
    end
    assert(runs==56)
end)

check('chain components use only the NPC mesh and all parts unwind on failure or switch',function()
    local Chains=require('hun_shachi_chains')
    local r={actor=object('hun')}
    local assets,made={},{}
    local function asset(p) if not assets[p] then local cls=object(p);assets[p]=cls;cls.path=p end;return assets[p] end
    function r.actor:AddComponentByClass(cls)
        local part=object(cls.path);function part:GetOwner()return r.actor end
        function part:SetCastShadow()end
        function part:SetAsset(value)self.Asset=value end
        function part:SetParameter()end
        function part:ConstructFunc(mesh,spline,fx)if not r.bad then self.Mesh,self.Spline,self.Niagara=mesh,spline,fx end end
        function part:K2_DestroyComponent()self.gone=true end
        function part:IsBeingDestroyed()return self.gone==true end
        made[#made+1]=part;return part
    end
    r.actor.Mesh=object('mesh');function r.actor.Mesh:GetOwner()return r.actor end
    local rig=asset('/Script/Niagara.Default__NiagaraDIRigidMeshCollisionFunctionLibrary')
    function rig:SetSourceActors(_,_,actors)assert(actors[1]==r.actor)end
    local chains=Chains.new({asset=asset,current=function(v)return v==r end,say=function()end,fname=function(n)return n end})
    assert(chains:select(r,'/ShachiHook/Weapon') and #made==11)
    assert(chains:select(r,'/HuoLiuXing/Weapon') and #made==11)
    assert(chains:select(r,'/Bow/Weapon'))
    for _,p in ipairs(made) do assert(p.gone) end
    r.bad=true;assert(not chains:select(r,'/ShachiHook/Weapon') and r.shadowChainFailed)
    for _,p in ipairs(made) do assert(p.gone) end
end)

check('13 interaction variants preserve their own identity and borrow only combat grants',function()
    assert(#Data.variants==13)
    for _,item in ipairs(Data.variants) do
        local h=fixture(item,false)
        h.r.loadout.variants=h.r.loadout.shadows
        h.r.loadout.shadows={}
        h.r.loadout.variants[1].level='max'
        local m=Data.moves[item.normal][1]
        h.tags={};for _,name in ipairs(m.needs) do h.tags[name]=1 end
        assert(h:tick(0),item.label)
        local picked=h.r.shadowState.running.choice
        assert(picked.id==item.id and picked.level==1 and not picked.soul)
        assert(h.templatePath==item.donor and not h.templatePath:find('_Interact',1,true))
        local copy=h.wc.slots[0]
        assert(copy['Weapon Attack Multipliers'].v.a==2 and copy['Weapon Attack Multipliers Normalized'].v.a==2)
        assert(copy['Display Data'][1].WeaponClass==h.source['Display Data'][1].WeaponClass)
        assert(h.r.shadowState.running.move.cls:find('/GameplayBlocker/',1,true)==nil)
    end
end)
check('one uncertain acknowledgement cannot cause a second charge or effect',function()
    local h=fixture()
    local requests=0
    function h.asc:TryActivateAbility()requests=requests+1;return true end
    local effects=0
    function h.asc:BP_ApplyGameplayEffectToSelf()effects=effects+1;return nil end
    assert(h:tick(0) and requests==1 and effects>0)
    local n=effects
    assert(h:tick(.5) and requests==1)
    assert(not h:tick(2) and not h:tick(4) and requests==1 and effects==n)
    local delayed=fixture()
    local first=true
    function delayed.asc:TryActivateAbility()if first then first=false;return true end;error('double debit') end
    delayed.r.loadout.resources.consume_skill_resources=false
    assert(delayed:tick(0))
    delayed.attrs.SpiritShadow=3
    assert(not delayed:tick(.5) and delayed.attrs.SpiritShadow==4)
    assert(not delayed.r.shadowState.untilAt[Data.items[1].id])
end)
check('malformed distance, mismatched native target and blocked sight all suppress casts',function()
    local h=fixture()
    for _,dist in ipairs({-1,0/0,math.huge}) do h.ctx.distance=dist;assert(not h:tick(0) and h.sets==0) end
    h.ctx.distance=1;h.ctx.target=h.r.actor;assert(not h:tick(0) and h.sets==0)
    h=fixture(Data.items[2]);h.ctx.distance=900
    local ai=object('ctrl')
    function h.r.actor:GetController()return ai end
    function ai:K2_GetPawn()return h.r.actor end
    function ai:LineOfSightTo()return false end
    assert(not h:tick(0) and h.sets==0)
    h=fixture();h.targetReadback=h.r.actor
    assert(not h:tick(0) and h.sets==0)
end)
check('late failed switch, stale slot and late cleanup preserve owned boundaries',function()
    local h=fixture();local original=object('native slot');h.wc.slots[0]=original;h.grants=false
    assert(not h:tick(0) and h.wc.active==-1 and h.wc.slots[0]==original)
    h=fixture();assert(h:tick(0));local foreign=object('external replacement');h.wc.slots[0]=foreign
    h.mod:cleanup(h.r);assert(h.wc.slots[0]==foreign)
    h=fixture();assert(h:tick(0));local before=h.sets;h.owner=false
    h.mod:cleanup(h.r);assert(h.sets==before and h.r.shadowState==nil)
end)
check('release enters only the local cast receiver while its exact hold task is alive',function()
    local h=fixture();assert(h:tick(0));local run=h.r.shadowState.running
    assert(run.move.release=='To Release')
    local inst=h.rows[run.handle].NonReplicatedInstances[1]
    local t=object('wait');local cls=object('taskclass')
    function t:GetClass()return cls end
    function cls:GetFName()return {ToString=function()return 'AbilityTask_WaitSInputRelease' end} end
    t.Input=object('/PBZInput/InputActions/IA_ShachiAbility_Hold.IA_ShachiAbility_Hold')
    t.Ability=object('another ability')
    inst.ActiveTasks={t};local releases=0;inst['To Release']=function()releases=releases+1 end
    assert(h:tick(.75) and releases==0)
    t.Ability=inst;assert(h:tick(.8) and releases==1)
    assert(h:tick(.9) and releases==1)
end)

print('hun_shachi: '..count..' checks passed')
