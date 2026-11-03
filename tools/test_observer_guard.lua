package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Guard=require('observer_guard')
local function fixture()
    local h={objects={},record={},saves=0,logs={},removed={}};local serial=0
    local function object(path,fields)
        serial=serial+1;local o=fields or {};o.id=serial;o.alive=true;o.path=path
        function o:IsValid()return self.alive end
        function o:GetAddress()assert(self.alive);return self.id end
        function o:GetFullName()assert(self.alive);return 'Object '..self.path end
        h.objects[path]=o;return o
    end
    local function weak(o)return {type=function()return 'TWeakObjectPtr' end,Get=function()return o end}end
    h.world=object('/Test.World')
    h.pawn=object('/Test.World.Player',{bHidden=false,bCanBeDamaged=true})
    function h.pawn:GetOuter()return h.world end
    function h.pawn:SetActorHiddenInGame(value)assert(self.alive);self.bHidden=value end
    h.pawn.AttributeSetBase=object('/Test.World.Player.Stats',{Health={BaseValue=345,CurrentValue=345},Health_Min={BaseValue=0,CurrentValue=0}})
    h.weapon=object('/Test.World.Weapon',{bHidden=false})
    function h.weapon:GetOuter()return h.world end
    function h.weapon:GetAttachParentActor()return h.pawn end
    function h.weapon:SetActorHiddenInGame(value)assert(self.alive);self.bHidden=value end
    function h.pawn:GetAttachedActors(out,reset,recursive)assert(reset and recursive);return {h.weapon}end
    h.camera=object('/Test.World.Camera')
    h.component=object('/Test.World.Camera.Component')
    function h.component:GetOwner()return h.camera end
    h.camera.CameraComponent=h.component
    h.pc=object('/Test.World.PC')
    function h.pc:SetAudioListenerOverride(component,position,rotation)
        assert(component==h.component and position.X==0 and rotation.Yaw==0)
        h.override=component
    end
    function h.pc:ClearAudioListenerOverride()h.override=nil end
    h.listener=object('/Test.World.Listener')
    function h.listener:GetOwner()return h.pc end
    h.oldProbe=object('/Test.World.Player.Probe')
    h.probe=object('/Test.World.Camera.Probe')
    function h.probe:GetOwner()return h.camera end
    h.sound=object('/Test.World.Sound',{bUsePlayerAsDistanceProbe=true,CurrentListenerComponent=weak(h.listener),CurrentDistanceProbeComponent=weak(h.oldProbe)})
    function h.sound:GetOuter()return h.world end
    function h.sound:PBZGetOrCreateOwnedAkComponent(component,name)assert(component==h.component and name=='None');return h.probe end
    function h.sound:PBZSetDistanceProbe(listener,probe)
        assert(listener==h.pc and probe:IsValid())
        if h.rejectProbe and probe==h.probe then return end
        self.CurrentDistanceProbeComponent=weak(probe)
    end
    local subClass=object('/Script/ProjectPBZ.PBZSoundFXSubsystem')
    local subLib=object('/Script/Engine.Default__SubsystemBlueprintLibrary')
    function subLib:GetWorldSubsystem(world,cls)assert(world==h.world and cls==subClass);return h.sound end
    local lockPath='/PBZCombatAsset/Prototypes/GameplayEffects/GE_LockHealth.GE_LockHealth_C'
    h.cls=object(lockPath);h.cdo=object('/Test.LockCDO',{DurationPolicy=1,Modifiers={}})
    function h.cls:IsAnyClass()return true end
    function h.cls:GetCDO()return h.cdo end
    function h.cdo:GetClass()return h.cls end
    h.asc=object('/Test.World.Player.ASC',{ActiveGameplayEffects={GameplayEffects_Internal={}}})
    function h.asc:GetOwner()return h.pawn end
    function h.asc:GetGameplayEffectCount(cls,filter,check)
        assert(self.alive and h.pawn.alive and cls==h.cls and filter==nil and check)
        local count=0;for _,entry in ipairs(self.ActiveGameplayEffects.GameplayEffects_Internal)do if entry.kind=='lock' then count=count+1 end end
        return count
    end
    function h.asc:MakeEffectContext()return {}end
    function h.asc:GetActiveEffects(query)
        assert(type(query)=='table');local out={}
        for _,entry in ipairs(self.ActiveGameplayEffects.GameplayEffects_Internal)do out[#out+1]=entry.Handle end
        return out
    end
    local abilities=object('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
    function abilities:GetActiveGameplayEffectStackCount(handle)
        for _,entry in ipairs(h.asc.ActiveGameplayEffects.GameplayEffects_Internal)do if entry.Handle.Handle==handle.Handle then return 1 end end
        return 0
    end
    function h:updateAttributes()
        local minimum=self.pawn.AttributeSetBase.Health_Min
        local floor,lock=false,false
        for _,entry in ipairs(self.asc.ActiveGameplayEffects.GameplayEffects_Internal)do
            floor=floor or entry.kind=='floor';lock=lock or entry.kind=='lock'
        end
        minimum.CurrentValue=floor and 345 or (lock and 1 or minimum.BaseValue)
        local health=self.pawn.AttributeSetBase.Health;health.CurrentValue=math.max(health.BaseValue,minimum.CurrentValue)
    end
    function h:addEffect(id,kind)
        self.asc.ActiveGameplayEffects.GameplayEffects_Internal[#self.asc.ActiveGameplayEffects.GameplayEffects_Internal+1]={Spec={Def=self.cdo},Handle={Handle=id},kind=kind or 'lock'}
        self:updateAttributes()
    end
    function h.asc:BP_ApplyGameplayEffectToSelf(cls,level,context)
        assert(self.alive and h.record.guard_lock_intent=='1' and h.saves>0 and cls==h.cls and level==1)
        h:addEffect(42);if h.opaqueHandle then return {}end
        return {Handle=42,bPassedFiltersAndWasExecuted=true}
    end
    function h.asc:RemoveActiveGameplayEffect(handle,stacks)
        assert(self.alive and h.pawn.alive and stacks==-1)
        h.removed[#h.removed+1]=handle.Handle
        if h.rejectRemoval then return end
        local kept={};for _,effect in ipairs(self.ActiveGameplayEffects.GameplayEffects_Internal)do
            if effect.Handle.Handle~=handle.Handle then kept[#kept+1]=effect end
        end
        self.ActiveGameplayEffects.GameplayEffects_Internal=kept
        h:updateAttributes()
    end
    h.pawn.AbilitySystemComponent=h.asc
    h.spectator={enabled=false}
    function h.spectator:status()return {enabled_requested=self.enabled,player_can_be_hatred_readback=not self.enabled,pending_flags=0,pending_relations=0}end
    function h.spectator:on()self.enabled=true end
    function h.spectator:off()self.enabled=false end
    h.recordObjects={pawn=h.pawn}
    h.context={record=h.record,pawn=h.pawn,pc=h.pc,camera=h.camera,world=h.world,
        remember=function(name,obj)h.recordObjects[name]=obj;h.record[name]=obj.path;h.record[name..'_key']=tostring(obj.id)end,
        resolve=function(name)local obj=h.recordObjects[name];return obj and obj.alive and obj or nil end,
        save=function()h.saves=h.saves+1 end}
    local attributes={}
    function attributes:read(actor,field)
        assert(actor==h.pawn and actor.alive);local data=actor.AttributeSetBase[field]
        return data and {base=data.BaseValue,current=data.CurrentValue}
    end
    function attributes:writeBase(actor,field,value)
        assert(actor==h.pawn and actor.alive)
        if field=='Health_Min' and value==345 and h.rejectFloor then
            actor.AttributeSetBase[field].BaseValue=170;h:updateAttributes();return false,'fixture partial write'
        end
        if field=='Health_Min' and value==0 and h.rejectFloorRestore then return false,'fixture restore failure' end
        actor.AttributeSetBase[field].BaseValue=value;h:updateAttributes();return true
    end
    h.options={attributes=attributes,getSpectator=function()return h.spectator end,log=function(line)h.logs[#h.logs+1]=line end}
    StaticFindObject=function(path)return h.objects[path]end
    FName=function(name)return name end
    h.guard=Guard.new(h.options);return h
end
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
test('entry changes owned flags, health minimum and distance probe; exit restores without healing',function()
    local h=fixture();h.guard:enter(h.context)
    assert(h.pawn.bHidden and h.weapon.bHidden and not h.pawn.bCanBeDamaged and h.spectator.enabled)
    assert(h.override==h.component and h.sound.CurrentDistanceProbeComponent:Get()==h.probe and not h.sound.bUsePlayerAsDistanceProbe)
    assert(h.pawn.AttributeSetBase.Health.CurrentValue==345)
    assert(h.guard:stop(h.context))
    assert(not h.pawn.bHidden and not h.weapon.bHidden and h.pawn.bCanBeDamaged and not h.spectator.enabled)
    assert(h.sound.CurrentDistanceProbeComponent:Get()==h.oldProbe and h.sound.bUsePlayerAsDistanceProbe and not h.override)
    assert(#h.removed==0 and h.pawn.AttributeSetBase.Health_Min.CurrentValue==0 and h.pawn.AttributeSetBase.Health.CurrentValue==345)
end)
test('prior F8, hidden equipment, invulnerability and native lock are preserved',function()
    local h=fixture();h.spectator.enabled=true;h.weapon.bHidden=true;h.pawn.bCanBeDamaged=false;h:addEffect(99)
    h.guard:enter(h.context);assert(h.guard:stop(h.context))
    assert(h.spectator.enabled and h.weapon.bHidden and not h.pawn.bCanBeDamaged)
    assert(#h.removed==0 and h.asc:GetGameplayEffectCount(h.cls,nil,true)==1)
end)
test('partial audio entry failure can roll back all prior protection changes',function()
    local h=fixture();h.rejectProbe=true
    assert(not pcall(function()h.guard:enter(h.context)end))
    assert(h.guard:stop(h.context))
    assert(not h.pawn.bHidden and h.pawn.bCanBeDamaged and not h.spectator.enabled)
    assert(h.asc:GetGameplayEffectCount(h.cls,nil,true)==0 and h.sound.bUsePlayerAsDistanceProbe)
end)
test('safely rolled-back floor failure does not prevent camera protection from entering',function()
    local h=fixture();h.rejectFloor=true;h.guard:enter(h.context)
    assert(not h.guard:status().health_verified and h.pawn.bHidden and h.override==h.component)
    assert(h.pawn.AttributeSetBase.Health_Min.BaseValue==0 and h.record.guard_floor_direct=='0')
    assert(h.guard:stop(h.context))
end)
test('restoration failure retains the snapshot for retry',function()
    local h=fixture();h.guard:enter(h.context);h.rejectFloorRestore=true
    assert(not h.guard:stop(h.context) and h.record.guard_floor_direct=='1')
    h.rejectFloorRestore=false;assert(h.guard:stop(h.context))
    assert(h.pawn.AttributeSetBase.Health_Min.CurrentValue==0)
end)
test('a new guard restores journaled state after hot reload',function()
    local h=fixture();h.guard:enter(h.context)
    local reloaded=Guard.new(h.options);assert(reloaded:stop(h.context))
    assert(not h.pawn.bHidden and h.pawn.bCanBeDamaged and not h.override)
end)
test('invalid original pawn does not dereference its still-valid ASC',function()
    local h=fixture();h.guard:enter(h.context);h.pawn.alive=false
    assert(h.guard:stop(h.context) and #h.removed==0)
end)
test('native minimum holds current HP and release does not expose accumulated base damage',function()
    local h=fixture();h.guard:enter(h.context)
    assert(h.pawn.AttributeSetBase.Health_Min.CurrentValue==345)
    h.pawn.AttributeSetBase.Health.BaseValue=200;h:updateAttributes()
    assert(h.pawn.AttributeSetBase.Health.CurrentValue==345)
    assert(h.guard:stop(h.context) and h.pawn.AttributeSetBase.Health.CurrentValue==345)
    assert(h.pawn.AttributeSetBase.Health_Min.CurrentValue==0)
end)
test('unknown floor rollback still fails entry until its state is restored',function()
    local h=fixture();h.rejectFloor=true;h.rejectFloorRestore=true
    assert(not pcall(function()h.guard:enter(h.context)end))
    assert(not h.guard:stop(h.context))
    h.rejectFloorRestore=false
    assert(h.guard:stop(h.context) and h.asc:GetGameplayEffectCount(h.cls,nil,true)==0)
    assert(h.pawn.bCanBeDamaged and not h.spectator.enabled and not h.pawn.bHidden)
end)
test('legacy journals remove only the exact previously owned effect handle',function()
    local h=fixture();h.guard:enter(h.context);h:addEffect(42);h:addEffect(99)
    h.context.remember('guard_lock_class',h.cls);h.record.guard_lock_handle='42'
    assert(h.guard:stop(h.context) and #h.removed==1 and h.removed[1]==42)
    assert(h.asc:GetGameplayEffectCount(h.cls,nil,true)==1)
end)
print('observer_guard: PASS ('..passed..' lifecycle/ownership regressions; native effectiveness requires game testing)')
