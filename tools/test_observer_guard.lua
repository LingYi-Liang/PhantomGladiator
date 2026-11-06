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
    h.pawn=object('/Test.World.Player',{bHidden=false,bCanBeDamaged=true,collision=true,at={X=100,Y=200,Z=300},order={}})
    function h.pawn:GetOuter()return h.world end
    -- Spawner volumes as the game has them: inside only while the capsule overlaps, whatever the position. The object type of
    -- the volume is WorldStatic (channel 0), its response to the capsule's Pawn type is Overlap. Leaving despawns the group.
    h.volumeClass=object('/Script/SGameAI.BaseSplineTriggerVolume')
    h.volume=object('/Test.World.Volume')
    h.exits,h.enters=0,0
    h.capsule=object('/Test.World.Player.Capsule',{responses={[0]=2,[1]=2,[2]=2,[19]=2,[21]=2}})
    local function overlapping()return h.pawn.collision and h.capsule.responses[0]>=1 end
    h.wasInside=true
    local function refresh()
        local now=overlapping()
        if h.wasInside and not now then h.exits=h.exits+1 elseif now and not h.wasInside then h.enters=h.enters+1 end
        h.wasInside=now
    end
    function h.capsule:GetCollisionResponseToChannel(channel)
        if h.unreadableChannels then error('fixture unreadable') end
        return self.responses[channel] or 0
    end
    function h.capsule:SetCollisionResponseToChannel(channel,response)
        if h.rejectChannels then error('fixture rejected') end
        self.responses[channel]=response;h.pawn.order[#h.pawn.order+1]='channel'..channel..'='..response
        if h.channelsEndOverlap and response==0 then self.responses[0]=0 end
        refresh()
    end
    h.pawn.CapsuleComponent=h.capsule
    function h.pawn:GetOverlappingActors(out,cls)
        assert(cls==h.volumeClass,'only the trigger volumes are counted')
        if overlapping() then out[1]=h.volume end
        return out
    end
    function h.pawn:GetActorEnableCollision()return self.collision end
    function h.pawn:SetActorEnableCollision(value)
        if h.rejectCollision then error('fixture rejected') end
        self.collision=value;self.order[#self.order+1]='collision='..tostring(value)
        refresh()
    end
    function h.pawn:K2_GetActorLocation()return self.at end
    function h.pawn:K2_GetActorRotation()return {Pitch=0,Yaw=45,Roll=0} end
    function h.pawn:K2_TeleportTo(at,rot)
        assert(rot.Yaw==45);self.at={X=at.X,Y=at.Y,Z=at.Z};self.teleports=(self.teleports or 0)+1
        return true
    end
    h.cmc=object('/Test.World.Player.Move',{MovementMode=1,CustomMovementMode=7,bReceiveSoftPush=true})
    function h.cmc:SetMovementMode(mode,custom)
        h.pawn.order[#h.pawn.order+1]='mode='..mode
        if h.rejectMode then return end
        self.MovementMode,self.CustomMovementMode=mode,custom
    end
    h.pawn.CharacterMovement=h.cmc
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
test('the hidden body stops moving and lets units through, and never leaves the trigger volumes it stands in',function()
    local h=fixture();h.guard:enter(h.context)
    assert(h.cmc.MovementMode==0,'stopped')
    assert(h.capsule.responses[2]==0 and h.capsule.responses[19]==0,'other characters pass through')
    assert(h.capsule.responses[0]==2 and h.capsule.responses[1]==2 and h.capsule.responses[21]==2,'everything else as it was')
    assert(h.cmc.bReceiveSoftPush==false,'soft collision does not push it')
    assert(h.pawn.collision==true,'the actor keeps its collision: switching it off ends every overlap')
    assert(h.exits==0 and h.enters==0,'no volume saw the player leave')
    assert(h.pawn.order[1]=='mode=0' and h.pawn.order[2]=='channel2=0' and h.pawn.order[3]=='channel19=0' and #h.pawn.order==3)
    assert(h.record.guard_body_owned=='1' and h.record.guard_body_mode=='1' and h.record.guard_body_custom=='7')
    assert(h.record.guard_body_channels=='2=2,19=2' and h.record.guard_body_push=='1' and h.record.guard_body_collision=='')
    assert(h.record.guard_body_x=='100' or h.record.guard_body_x=='100.0')
    local text=table.concat(h.logs,'\n')
    assert(text:find('玩家身体 移动模式 1 -> 0 胶囊通道 2=2,19=2 -> 2=0,19=0（调用=true） 被软碰撞推 true -> false 所在触发体 1 -> 1 位置=100,200,300',1,true),text)
    assert(not text:find('离开了触发体',1,true),text)
    h.pawn.order={}
    assert(h.guard:stop(h.context))
    assert(h.pawn.order[1]=='channel2=2' and h.pawn.order[2]=='channel19=2' and h.pawn.order[3]=='mode=1','channels are back before it walks')
    assert(h.capsule.responses[2]==2 and h.capsule.responses[19]==2 and h.cmc.bReceiveSoftPush==true)
    assert(h.pawn.collision==true and h.cmc.MovementMode==1 and h.cmc.CustomMovementMode==7 and h.record.guard_body_owned=='0')
    assert(h.exits==0 and h.enters==0,'no volume saw the player come back either: the groups were never switched')
    text=table.concat(h.logs,'\n')
    assert(text:find('玩家身体恢复 移动模式=1 胶囊通道=2=2,19=2 被软碰撞推=true 所在触发体=1 离进入点=0cm',1,true),text)
    -- Stopped again with nothing owned: left alone.
    h.guard:enter(h.context);h.record.guard_body_owned='0'
    h.pawn.order={};assert(h.guard:stop(h.context) and #h.pawn.order==0)
end)
test('channels already letting units through and a body soft collision already leaves alone come back as they were',function()
    local h=fixture();h.capsule.responses[19]=0;h.capsule.responses[2]=1;h.cmc.bReceiveSoftPush=false;h.cmc.MovementMode=3
    h.guard:enter(h.context)
    assert(h.record.guard_body_channels=='2=1,19=0' and h.record.guard_body_push=='0' and h.cmc.MovementMode==0)
    assert(h.capsule.responses[2]==0 and h.capsule.responses[19]==0)
    assert(h.guard:stop(h.context) and h.capsule.responses[2]==1 and h.capsule.responses[19]==0)
    assert(h.cmc.bReceiveSoftPush==false and h.cmc.MovementMode==3)
    -- A movement component without the soft collision property: nothing written, nothing to put back.
    local g=fixture();g.cmc.bReceiveSoftPush=nil
    g.guard:enter(g.context)
    assert(g.record.guard_body_push=='' and g.capsule.responses[2]==0)
    assert(g.guard:stop(g.context) and g.cmc.bReceiveSoftPush==nil)
end)
test('losing a trigger volume on the way in is said out loud',function()
    local h=fixture();h.channelsEndOverlap=true
    h.guard:enter(h.context)
    assert(h.exits==1)
    local text=table.concat(h.logs,'\n')
    assert(text:find('所在触发体 1 -> 0',1,true) and text:find('玩家身体离开了触发体：1 -> 0',1,true),text)
    -- Nothing to count with: the rest still goes on, and the log shows it was not counted.
    local g=fixture();g.objects['/Script/SGameAI.BaseSplineTriggerVolume']=nil
    g.guard:enter(g.context)
    assert(g.capsule.responses[2]==0 and table.concat(g.logs,'\n'):find('所在触发体 ? -> ?',1,true))
end)
test('a journal from the build that switched the whole collision off still gets it back, before walking',function()
    local h=fixture();h.guard:enter(h.context);assert(h.guard:stop(h.context))
    h.pawn:SetActorEnableCollision(false);h.pawn.order={};h.cmc.MovementMode=0
    assert(h.exits==1)
    local r=h.record
    r.guard_started='1';r.guard_body_owned='1';r.guard_body_collision='1';r.guard_body_channels='';r.guard_body_push='';r.guard_body_mode='1';r.guard_body_custom='7'
    local fresh=Guard.new(h.options)
    assert(fresh:stop(h.context))
    assert(h.pawn.order[1]=='collision=true' and h.pawn.order[2]=='mode=1' and h.pawn.collision==true and h.cmc.MovementMode==1)
    assert(h.enters==1 and r.guard_body_owned=='0')
    -- It was off before that build touched it: off it stays.
    local g=fixture();g.guard:enter(g.context);assert(g.guard:stop(g.context))
    g.pawn:SetActorEnableCollision(false)
    local q=g.record
    q.guard_started='1';q.guard_body_owned='1';q.guard_body_collision='0';q.guard_body_channels='';q.guard_body_push='';q.guard_body_mode='1';q.guard_body_custom='7'
    assert(g.guard:stop(g.context) and g.pawn.collision==false)
end)
test('not being able to stop or read the body leaves it as it was and the camera working',function()
    for _,break_it in ipairs({
        function(h)h.pawn.CharacterMovement=nil end,
        function(h)h.unreadableChannels=true end,
        function(h)h.pawn.CapsuleComponent=nil end,
        function(h)h.pawn.K2_GetActorLocation=function()error('fixture unreadable') end end,
        function(h)h.rejectMode=true end,
    })do
        local h=fixture();break_it(h)
        h.guard:enter(h.context)
        assert(h.pawn.bHidden and h.override==h.component,'the rest of the guard went on')
        assert(h.capsule.responses[2]==2 and h.capsule.responses[19]==2 and h.cmc.MovementMode==1 and h.cmc.bReceiveSoftPush==true,'nothing half done')
        assert(h.record.guard_body_owned~='1')
        assert(table.concat(h.logs,'\n'):find('玩家身体没有改',1,true))
        h.pawn.order={}
        assert(h.guard:stop(h.context) and #h.pawn.order==0,'nothing to put back')
    end
    -- Stopped, but the channels will not change: it is still put back as it was.
    local h=fixture();h.rejectChannels=true
    h.guard:enter(h.context)
    assert(h.cmc.MovementMode==0 and h.capsule.responses[2]==2)
    assert(table.concat(h.logs,'\n'):find('胶囊通道 2=2,19=2 -> 2=2,19=2（调用=false）',1,true))
    h.rejectChannels=false
    assert(h.guard:stop(h.context) and h.cmc.MovementMode==1 and h.capsule.responses[2]==2)
end)
test('a body that something sets moving again is stopped and carried back; a nudge is only logged',function()
    local h=fixture();h.guard:enter(h.context)
    local function ticks(n)for _=1,n do h.guard:tick(h.context) end end
    ticks(30)
    assert(not table.concat(h.logs,'\n'):find('玩家身体被移动',1,true),'still: nothing to say')
    -- Something sets it falling.
    h.cmc.MovementMode=3;h.pawn.at={X=100,Y=200,Z=200}
    ticks(30)
    assert(h.cmc.MovementMode==0 and h.pawn.teleports==1 and h.pawn.at.Z==300)
    local text=table.concat(h.logs,'\n')
    assert(text:find('玩家身体被移动 离进入点=100cm 模式=3 重新停住=true 放回=true',1,true),text)
    -- Moved a little by something else: the log shows it, it is not fought over.
    h.pawn.at={X=130,Y=200,Z=300}
    ticks(30)
    assert(h.pawn.teleports==1 and h.pawn.at.X==130)
    assert(table.concat(h.logs,'\n'):find('玩家身体被移动 离进入点=30cm 模式=0 重新停住=false 放回=false',1,true))
    -- Moving again but close by: stopped, not carried.
    h.cmc.MovementMode=1;h.pawn.at={X=110,Y=200,Z=300}
    ticks(30)
    assert(h.cmc.MovementMode==0 and h.pawn.teleports==1)
    assert(h.guard:stop(h.context))
    assert(table.concat(h.logs,'\n'):find('所在触发体=1 离进入点=10cm',1,true),table.concat(h.logs,'\n'))
end)
test('a restore that does not take is tried again, and a new load of the mod can finish it from the journal',function()
    local h=fixture();h.guard:enter(h.context)
    h.rejectMode=true
    assert(not h.guard:stop(h.context) and h.record.guard_body_owned=='1')
    assert(h.capsule.responses[2]==2 and h.capsule.responses[19]==2 and h.cmc.bReceiveSoftPush==true,'channels and soft push are back already')
    h.rejectMode=false
    -- The journal keeps these fields, and a new guard works from them.
    for _,name in ipairs({'guard_body_owned','guard_body_mode','guard_body_custom','guard_body_collision','guard_body_channels','guard_body_push','guard_body_x','guard_body_y','guard_body_z'})do
        local kept=false
        for _,field in ipairs(Guard.fields)do kept=kept or field==name end
        assert(kept,name)
    end
    local fresh=Guard.new(h.options)
    assert(fresh:stop(h.context) and h.cmc.MovementMode==1 and h.cmc.CustomMovementMode==7 and h.record.guard_body_owned=='0')
    -- The pawn has gone in the meantime: nothing to put back, no waiting on it.
    local g=fixture();g.guard:enter(g.context)
    g.recordObjects.pawn=nil
    g.guard:stop(g.context)
    assert(g.record.guard_body_owned=='0')
end)
test('legacy journals remove only the exact previously owned effect handle',function()
    local h=fixture();h.guard:enter(h.context);h:addEffect(42);h:addEffect(99)
    h.context.remember('guard_lock_class',h.cls);h.record.guard_lock_handle='42'
    assert(h.guard:stop(h.context) and #h.removed==1 and h.removed[1]==42)
    assert(h.asc:GetGameplayEffectCount(h.cls,nil,true)==1)
end)
print('observer_guard: PASS ('..passed..' lifecycle/ownership regressions; native effectiveness requires game testing)')
