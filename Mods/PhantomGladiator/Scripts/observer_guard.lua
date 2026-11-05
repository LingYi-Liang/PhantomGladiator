-- Owned observation changes; recovery data is stored in the camera journal.
-- Uses the player's native health minimum and SoundFX probe, not health polling writes.
local U=require('ue_observe')
local Stats=require('character_stats')
local Guard={fields={'guard_started','guard_spectator_before','guard_spectator_owned',
    'guard_damage_before','guard_damage_owned','guard_hide_count','guard_lock_handle','guard_lock_intent','guard_effects_before',
    'guard_floor_handle','guard_floor_intent','guard_floor_effects_before','guard_floor_base','guard_floor_current','guard_floor_direct',
    'guard_audio_owned','guard_listener_override','guard_probe_before','guard_hp',
    'guard_body_owned','guard_body_mode','guard_body_custom','guard_body_collision','guard_body_x','guard_body_y','guard_body_z'}}
for _,name in ipairs({'guard_asc','guard_lock_class','guard_sound','guard_listener','guard_old_probe','guard_probe'})do
    Guard.fields[#Guard.fields+1]=name;Guard.fields[#Guard.fields+1]=name..'_key'
end
for i=1,32 do
    for _,suffix in ipairs({'','_key','_before','_owned'})do Guard.fields[#Guard.fields+1]='guard_hidden'..i..suffix end
end
local MOVE_NONE=0
local PUT_BACK=50      -- cm: a body that started moving and got this far is carried back
local BODY_STEP=10     -- cm of drift worth a log line
local BODY_LINES=10
local function same(a,b)local k=U.key(a);return k~=nil and k==U.key(b)end
local function call(obj,name,...)
    if not U.valid(obj) then return false,'invalid '..name end
    local args=table.pack(...)
    return pcall(function()return obj[name](obj,table.unpack(args,1,args.n))end)
end
local function need(obj,name,...)
    local ok,value=call(obj,name,...);assert(ok,name..': '..tostring(value));return value
end
local function owner(obj)
    local value=need(obj,'GetOwner');assert(U.valid(value),'component owner unavailable');return value
end
local function weak(value)
    local kind=U.kind(value)
    if kind=='WeakObjectPtr' or kind=='FWeakObjectPtr' or kind=='TWeakObjectPtr' then
        local ok,obj=pcall(function()return value:Get()end);return ok and U.valid(obj) and obj or nil
    end
    return U.valid(value) and value or nil
end
local function bool(obj,field)local value=U.field(obj,field);assert(type(value)=='boolean','unreadable '..field);return value end
local function put(obj,field,value)
    assert(U.valid(obj),'invalid before '..field);obj[field]=value
    assert(U.field(obj,field)==value,field..' readback mismatch')
end
local function located(actor)
    local read,at=call(actor,'K2_GetActorLocation')
    if not read then return nil end
    local x,y,z=U.struct(at,'X'),U.struct(at,'Y'),U.struct(at,'Z')
    if type(x)=='number' and type(y)=='number' and type(z)=='number' then return {X=x,Y=y,Z=z} end
end
local function where(v)return v and string.format('%.0f,%.0f,%.0f',v.X,v.Y,v.Z) or '?' end
local function homeOf(r)
    local x,y,z=tonumber(r.guard_body_x),tonumber(r.guard_body_y),tonumber(r.guard_body_z)
    return x and y and z and {X=x,Y=y,Z=z} or nil
end
local function gap(a,b)return a and b and math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2) or nil end
local function hp(pawn)
    return U.struct(U.field(U.field(pawn,'AttributeSetBase'),'Health'),'CurrentValue')
end
local function handles(asc)
    -- Handle is not a reflected member of FActiveGameplayEffect in this build.
    -- Use the native query, never guess a field in GameplayEffects_Internal.
    local called,values=call(asc,'GetActiveEffects',{})
    local list=called and U.array(values);if not list or #list>512 then return nil end
    local out={}
    for _,entry in ipairs(list)do
        local id=U.struct(entry,'Handle')
        if type(id)~='number' or id<0 then return nil end
        out[#out+1]=id
    end
    return out
end
local function newHandles(asc,beforeText)
    local before={};for id in (beforeText or ''):gmatch('%d+')do before[tonumber(id)]=true end
    local active=handles(asc);if not active then return nil end
    local added={};for _,id in ipairs(active)do if not before[id] then added[#added+1]=id end end
    return added
end
local function stackCount(id)
    local lib=StaticFindObject('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
    local value=need(lib,'GetActiveGameplayEffectStackCount',{Handle=id,bPassedFiltersAndWasExecuted=true})
    assert(type(value)=='number' and value>=0,'native active-effect stack count unavailable')
    return value
end
function Guard.new(options)
    local self={fields=Guard.fields,ticks=0,healthVerified=false,message='观战保护未开启'};local log=options.log or function()end
    local stats=options.attributes or Stats.new()
    local function remember(c,name,obj)c.remember(name,obj)end
    local function stored(c,name)return c.resolve(name)end
    function self:status()return {health_verified=self.healthVerified,message=self.message}end
    function self:enterHealth(c,health)
        local r,pawn=c.record,c.pawn
        self.healthVerified=false
        local floor,why=stats:read(pawn,'Health_Min')
        if not floor then self.message='锁血未生效：'..tostring(why)..'；镜头仍可使用';log('[Observer] '..self.message);return end
        r.guard_floor_base=tostring(floor.base);r.guard_floor_current=tostring(floor.current)
        r.guard_floor_direct='1';c.save()
        local called,changed,detail=pcall(function()return stats:writeBase(pawn,'Health_Min',health)end)
        local actual=stats:read(pawn,'Health_Min')
        if called and changed and actual and Stats.close(actual.current,health) then
            self.healthVerified=true;self.message='观战保护：生命下限已读回，玩家隐藏，声音跟随镜头'
            log('[Observer] 生命下限操作='..health..' before_base='..floor.base..' before_current='..floor.current
                ..' actual_base='..actual.base..' actual_current='..actual.current..' verified=true')
            return
        end
        local restored=actual and Stats.close(actual.base,floor.base) and Stats.close(actual.current,floor.current)
        if not restored then
            local ok=stats:writeBase(pawn,'Health_Min',floor.base)
            actual=stats:read(pawn,'Health_Min')
            restored=ok and actual and Stats.close(actual.base,floor.base) and Stats.close(actual.current,floor.current)
        end
        assert(restored,'health floor rollback not verified')
        r.guard_floor_direct='0';c.save()
        self.message='锁血未生效，已恢复原值；镜头仍可使用'
        log('[Observer] '..self.message..' detail='..tostring(detail or changed))
    end
    function self:enter(c)
        local r,pawn=c.record,c.pawn
        local spectator=assert(options.getSpectator(),'spectator unavailable')
        local state=spectator:status();assert(type(state.enabled_requested)=='boolean','spectator unreadable')
        local health=hp(pawn);assert(type(health)=='number' and health>0,'player health unavailable')
        local damage=bool(pawn,'bCanBeDamaged')
        local asc=U.field(pawn,'AbilitySystemComponent');assert(U.valid(asc),'player ASC unavailable')
        local owned=owner(asc);assert(same(owned,pawn),'foreign player ASC')
        r.guard_started='1';r.guard_spectator_before=state.enabled_requested and '1' or '0'
        r.guard_damage_before=damage and '1' or '0';r.guard_hp=tostring(health)
        remember(c,'guard_asc',asc);c.save()
        if not state.enabled_requested then
            r.guard_spectator_owned='1';c.save();spectator:on()
        end
        local flag=spectator:status().player_can_be_hatred_readback
        assert(flag==false,'player hatred eligibility not disabled')
        if damage then r.guard_damage_owned='1';c.save();put(pawn,'bCanBeDamaged',false) end
        self:enterHealth(c,health)
        -- Snapshot each attached actor separately; preserve already hidden equipment.
        local out={};local read,attached=call(pawn,'GetAttachedActors',out,true,true)
        attached=read and (U.array(attached) or U.array(out)) or nil
        assert(attached,'attached player models unavailable')
        local targets,seen={pawn},{[U.key(pawn)]=true}
        for _,actor in ipairs(attached)do
            if U.valid(actor) and U.inWorld(actor,c.world) then
                local parent=actor;local ours=false
                for _=1,16 do
                    parent=need(parent,'GetAttachParentActor')
                    if same(parent,pawn) then ours=true;break end
                    if not U.valid(parent) then break end
                end
                local key=U.key(actor)
                if ours and not seen[key] then seen[key]=true;targets[#targets+1]=actor end
            end
        end
        assert(#targets<=32,'too many attached player actors')
        r.guard_hide_count=tostring(#targets)
        for i,actor in ipairs(targets)do
            local name='guard_hidden'..i
            remember(c,name,actor);r[name..'_before']=bool(actor,'bHidden') and '1' or '0'
            r[name..'_owned']='1';c.save()
            need(actor,'SetActorHiddenInGame',true);assert(bool(actor,'bHidden'),'hidden state not verified')
        end
        self:enterBody(c)
        self:enterAudio(c)
        log('[Observer] 已开启：玩家仇恨资格=false can_damage='..tostring(U.field(pawn,'bCanBeDamaged'))
            ..' health_floor_verified='..tostring(self.healthVerified)
            ..' hidden_actors='..#targets..' HP='..health..'；锁血/声音实际效果待实测')
    end
    -- Hidden and unhurt is not gone: the capsule still stops whoever walks into it and whoever hits it can shove it, so the
    -- body gets in the way of the fight and drifts while the camera is elsewhere. Without collision it has no floor and would
    -- fall, so it stops moving first. Failing here costs only this; the camera still works.
    function self:enterBody(c)
        local r,pawn=c.record,c.pawn
        self.bodyAway,self.bodyLines=0,0
        local cmc=U.field(pawn,'CharacterMovement')
        local mode=tonumber((U.field(cmc,'MovementMode')))
        local custom=tonumber((U.field(cmc,'CustomMovementMode')))
        local read,collision=call(pawn,'GetActorEnableCollision')
        local at=located(pawn)
        if not mode or not read or type(collision)~='boolean' or not at then
            log('[Observer] 玩家身体碰撞没有关：读不到 移动模式='..tostring(mode)..' 碰撞='..tostring(collision)..' 位置='..where(at))
            return
        end
        r.guard_body_mode=tostring(mode);r.guard_body_custom=tostring(custom or 0);r.guard_body_collision=collision and '1' or '0'
        r.guard_body_x,r.guard_body_y,r.guard_body_z=tostring(at.X),tostring(at.Y),tostring(at.Z)
        r.guard_body_owned='1';c.save()
        local stopped=call(cmc,'SetMovementMode',MOVE_NONE,0)
        local now=tonumber((U.field(cmc,'MovementMode')))
        if not stopped or now~=MOVE_NONE then
            if now==mode then r.guard_body_owned='0';c.save() end
            log('[Observer] 玩家身体碰撞没有关：移动模式没能停住 调用='..tostring(stopped)..' 读回='..tostring(now))
            return
        end
        local off=call(pawn,'SetActorEnableCollision',false)
        local got,after=call(pawn,'GetActorEnableCollision')
        log(string.format('[Observer] 玩家身体 移动模式 %d -> %s 碰撞 %s -> %s（调用=%s） 位置=%s',mode,tostring(now),tostring(collision),
            got and tostring(after) or '?',tostring(off),where(at)))
    end
    -- Nothing should move it now; if something does, say so. Something that sets it moving again has it falling: with no
    -- collision there is no floor.
    function self:holdBody(c)
        local r,pawn=c.record,c.pawn
        local cmc=U.field(pawn,'CharacterMovement')
        local mode=tonumber((U.field(cmc,'MovementMode')))
        local home,at=homeOf(r),located(pawn)
        local away=gap(at,home)
        local restarted=mode~=nil and mode~=MOVE_NONE
        local put=false
        if restarted then
            call(cmc,'SetMovementMode',MOVE_NONE,0)
            if away and away>PUT_BACK then
                local okRot,rot=call(pawn,'K2_GetActorRotation')
                local moved,result=call(pawn,'K2_TeleportTo',home,okRot and rot or {Pitch=0,Yaw=0,Roll=0})
                put=moved and result~=false
            end
        end
        if (restarted or (away and math.abs(away-(self.bodyAway or 0))>=BODY_STEP)) and (self.bodyLines or 0)<BODY_LINES then
            self.bodyAway,self.bodyLines=away or self.bodyAway,(self.bodyLines or 0)+1
            log(string.format('[Observer] 玩家身体被移动 离进入点=%s 模式=%s 重新停住=%s 放回=%s',away and string.format('%.0fcm',away) or '?',tostring(mode),tostring(restarted),tostring(put)))
        end
    end
    function self:enterAudio(c)
        local r=c.record
        local lib=StaticFindObject('/Script/Engine.Default__SubsystemBlueprintLibrary')
        local cls=StaticFindObject('/Script/ProjectPBZ.PBZSoundFXSubsystem')
        assert(U.valid(cls),'sound subsystem class unavailable')
        local sound=need(lib,'GetWorldSubsystem',c.world,cls)
        assert(U.valid(sound) and U.inWorld(sound,c.world),'world sound subsystem unavailable')
        local listener=weak(U.field(sound,'CurrentListenerComponent'))
        local probe=weak(U.field(sound,'CurrentDistanceProbeComponent'))
        assert(U.valid(listener) and U.valid(probe),'original audio listener/probe unavailable')
        local listenerOwner=owner(listener)
        local before=bool(sound,'bUsePlayerAsDistanceProbe')
        local component=U.field(c.camera,'CameraComponent');assert(U.valid(component),'camera component unavailable')
        local cameraProbe=need(sound,'PBZGetOrCreateOwnedAkComponent',component,FName('None'))
        assert(U.valid(cameraProbe) and same(owner(cameraProbe),c.camera),'camera audio component ownership mismatch')
        remember(c,'guard_sound',sound);remember(c,'guard_listener',listener)
        remember(c,'guard_old_probe',probe);remember(c,'guard_probe',cameraProbe)
        r.guard_probe_before=before and '1' or '0';r.guard_audio_owned='1';c.save()
        put(sound,'bUsePlayerAsDistanceProbe',false)
        need(sound,'PBZSetDistanceProbe',listenerOwner,cameraProbe)
        assert(same(weak(U.field(sound,'CurrentDistanceProbeComponent')),cameraProbe),'audio probe did not follow camera')
        r.guard_listener_override='1';c.save()
        need(c.pc,'SetAudioListenerOverride',component,{X=0,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0})
        log('[Observer] 声音操作=相机Listener+PBZ距离探针；probe读回='..U.key(cameraProbe)
            ..' use_player='..tostring(U.field(sound,'bUsePlayerAsDistanceProbe'))..'；听感需在游戏里确认')
        self.audioSamples=0
    end
    function self:tick(c)
        self.ticks=self.ticks+1;if self.ticks%30~=0 then return end
        local r=c.record
        local spectator=assert(options.getSpectator(),'spectator unavailable')
        if not spectator:status().enabled_requested then spectator:on() end
        assert(bool(c.pawn,'bHidden') and not bool(c.pawn,'bCanBeDamaged'),'player observer flags changed')
        if r.guard_body_owned=='1' then self:holdBody(c) end
        if r.guard_floor_direct=='1' then
            local floor=stats:read(c.pawn,'Health_Min')
            local verified=floor and floor.current+0.01>=tonumber(r.guard_hp) or false
            if self.healthVerified and not verified then
                self.message='生命下限发生变化，锁血待确认；镜头仍可使用';log('[Observer] '..self.message)
            end
            self.healthVerified=verified
        end
        local sound=stored(c,'guard_sound');local probe=stored(c,'guard_probe')
        if U.valid(sound) and U.valid(probe) then
            if bool(sound,'bUsePlayerAsDistanceProbe') or not same(weak(U.field(sound,'CurrentDistanceProbeComponent')),probe) then
                local listenerOwner=owner(stored(c,'guard_listener'))
                put(sound,'bUsePlayerAsDistanceProbe',false);need(sound,'PBZSetDistanceProbe',listenerOwner,probe)
                log('[Observer] 重申相机距离探针；读回='..tostring(same(weak(U.field(sound,'CurrentDistanceProbeComponent')),probe)))
            end
            if (self.audioSamples or 0)<5 then
                self.audioSamples=(self.audioSamples or 0)+1
                for _,field in ipairs({'CurrentListenerComponent','CurrentDistanceProbeComponent','CurrentCharacterSfxListenerComponent'})do
                    local component=weak(U.field(sound,field))
                    local read,position=call(component,'K2_GetComponentLocation')
                    local xyz=read and (tostring(U.struct(position,'X'))..','..tostring(U.struct(position,'Y'))..','..tostring(U.struct(position,'Z'))) or 'unavailable'
                    log('[ObserverAudio] '..field..' object='..tostring(U.key(component))..' location='..xyz)
                end
            end
        end
        local health=hp(c.pawn)
        if self.lastHealth~=health then
            local floor=stats:read(c.pawn,'Health_Min')
            self.lastHealth=health;log('[Observer] 玩家只读 HP='..tostring(health)..' enter_HP='..tostring(r.guard_hp)..' health_min='..tostring(floor and floor.current)
                ..' hidden='..tostring(U.field(c.pawn,'bHidden'))..' can_damage='..tostring(U.field(c.pawn,'bCanBeDamaged')))
        end
    end
    function self:stop(c)
        self.healthVerified=false;self.message='观战保护已退出'
        local r=c.record;if r.guard_started~='1' then return true end
        local pending=false
        local function attempt(name,fn)
            local ok,result=pcall(fn)
            if not ok or result==false then pending=true;log('[Observer] 恢复待确认 '..name..' '..tostring(result)) end
        end
        attempt('audio',function()
            local sound,probe,old,listener=stored(c,'guard_sound'),stored(c,'guard_probe'),stored(c,'guard_old_probe'),stored(c,'guard_listener')
            if not U.valid(c.world) then sound=nil end
            if r.guard_listener_override=='1' and U.valid(c.pc) then need(c.pc,'ClearAudioListenerOverride') end
            r.guard_listener_override='0'
            if r.guard_audio_owned=='1' and U.valid(sound) then
                local current=weak(U.field(sound,'CurrentDistanceProbeComponent'))
                if same(current,probe) then
                    assert(U.valid(old) and U.valid(listener),'original audio objects unavailable')
                    need(sound,'PBZSetDistanceProbe',owner(listener),old)
                    assert(same(weak(U.field(sound,'CurrentDistanceProbeComponent')),old),'original probe not restored')
                end
                put(sound,'bUsePlayerAsDistanceProbe',r.guard_probe_before=='1')
            end
            r.guard_audio_owned='0';c.save()
            log('[Observer] 声音恢复：原距离探针/玩家位置策略已读回；原生Listener覆盖已清除')
        end)
        attempt('health',function()
            local asc,cls=stored(c,'guard_asc'),stored(c,'guard_lock_class')
            if not stored(c,'pawn') then asc=nil end
            local pawn=stored(c,'pawn')
            if r.guard_floor_direct=='1' and pawn then
                local health=assert(stats:read(pawn,'Health'),'health unavailable before restoring floor')
                if health.base<health.current and health.current>0 then
                    assert(stats:writeBase(pawn,'Health',health.current),'health reconciliation failed')
                    assert(Stats.close(assert(stats:read(pawn,'Health')).base,health.current),'health reconciliation not verified')
                end
                local original=assert(tonumber(r.guard_floor_base),'original floor unavailable')
                assert(stats:writeBase(pawn,'Health_Min',original),'health floor restore failed')
                local actual=assert(stats:read(pawn,'Health_Min'),'restored health floor unreadable')
                assert(Stats.close(actual.base,original),'restored health floor not verified')
                log('[Observer] 生命下限恢复 target_base='..original..' actual_base='..actual.base..' actual_current='..actual.current..' HP='..tostring(hp(pawn)))
            end
            r.guard_floor_direct='0';c.save()
            -- Compatibility recovery for the previous effect-based experiments.
            if U.valid(asc) and (r.guard_lock_intent=='1' or (r.guard_lock_handle and r.guard_lock_handle~='')) then
                assert(U.valid(cls),'recorded LockHealth class unavailable')
            end
            if r.guard_floor_intent=='1' and U.valid(asc) then
                local added=newHandles(asc,r.guard_floor_effects_before)
                if added and #added==1 then r.guard_floor_handle=tostring(added[1]);r.guard_floor_intent='0';c.save()
                elseif added and #added==0 then
                    local pawn=stored(c,'pawn');local floor=assert(stats:read(pawn,'Health_Min'),'floor rollback unreadable')
                    local original=assert(tonumber(r.guard_floor_base),'floor snapshot unavailable')
                    if not Stats.close(floor.base,original) then
                        assert(stats:writeBase(pawn,'Health_Min',original),'floor base rollback failed')
                        assert(Stats.close(assert(stats:read(pawn,'Health_Min')).base,original),'floor rollback not verified')
                    end
                    r.guard_floor_intent='0';c.save()
                else return false end
            end
            if r.guard_floor_handle and r.guard_floor_handle~='' and U.valid(asc) then
                local pawn=stored(c,'pawn');local id=assert(tonumber(r.guard_floor_handle),'invalid floor handle')
                local current=assert(stats:read(pawn,'Health'),'health readback unavailable before release')
                -- Some attribute implementations retain a lower base under a
                -- clamped current value. Do not release hidden accumulated damage.
                if current.base<current.current and current.current>0 then
                    assert(stats:writeBase(pawn,'Health',current.current),'health base reconciliation failed')
                    assert(Stats.close(assert(stats:read(pawn,'Health')).base,current.current),'health base reconciliation not verified')
                end
                if stackCount(id)>0 then need(asc,'RemoveActiveGameplayEffect',{Handle=id,bPassedFiltersAndWasExecuted=true},-1)end
                assert(stackCount(id)==0,'owned health floor still active')
                local after=assert(stats:read(pawn,'Health_Min'),'health floor restore readback unavailable')
                log('[Observer] 生命下限恢复 own_handle='..id..' removed=true current='..after.current..' player_HP='..tostring(hp(pawn)))
            end
            r.guard_floor_handle='';r.guard_floor_intent='0';c.save()
            if r.guard_lock_intent=='1' and U.valid(asc) then
                local active=newHandles(asc,r.guard_effects_before)
                local count=need(asc,'GetGameplayEffectCount',cls,nil,true)
                if count==1 and active and #active==1 then r.guard_lock_handle=tostring(active[1]);r.guard_lock_intent='0';c.save()
                elseif count==0 then r.guard_lock_intent='0';c.save()
                else return false end
            end
            if r.guard_lock_handle and r.guard_lock_handle~='' and U.valid(asc) then
                local id=tonumber(r.guard_lock_handle);assert(id and id>=0,'invalid recorded effect handle')
                if stackCount(id)>0 then need(asc,'RemoveActiveGameplayEffect',{Handle=id,bPassedFiltersAndWasExecuted=true},-1) end
                assert(stackCount(id)==0,'owned LockHealth handle still active')
            end
            r.guard_lock_handle='';r.guard_lock_intent='0';c.save()
        end)
        attempt('body',function()
            local pawn=stored(c,'pawn')
            if r.guard_body_owned=='1' and pawn then
                -- Collision first: walking looks for its floor the moment it is set.
                local wanted=r.guard_body_collision~='0'
                need(pawn,'SetActorEnableCollision',wanted)
                local read,now=call(pawn,'GetActorEnableCollision')
                assert(read and now==wanted,'player collision restore not verified')
                local cmc=U.field(pawn,'CharacterMovement');assert(U.valid(cmc),'player movement component unavailable')
                local mode=assert(tonumber(r.guard_body_mode),'player movement mode snapshot unavailable')
                need(cmc,'SetMovementMode',mode,tonumber(r.guard_body_custom) or 0)
                local after=tonumber((U.field(cmc,'MovementMode')))
                assert(after==mode,'player movement mode restore not verified')
                local away=gap(located(pawn),homeOf(r))
                log(string.format('[Observer] 玩家身体恢复 移动模式=%d 碰撞=%s 离进入点=%s',after,tostring(now),away and string.format('%.0fcm',away) or '?'))
            end
            r.guard_body_owned='0';c.save()
        end)
        for i=tonumber(r.guard_hide_count) or 0,1,-1 do
            local name='guard_hidden'..i
            attempt(name,function()
                local actor=stored(c,name)
                if r[name..'_owned']=='1' and actor then
                    local before=r[name..'_before']=='1'
                    need(actor,'SetActorHiddenInGame',before);assert(bool(actor,'bHidden')==before,'visibility restore mismatch')
                end
                r[name..'_owned']='0';c.save()
            end)
        end
        attempt('damage flag',function()
            local pawn=stored(c,'pawn')
            if r.guard_damage_owned=='1' and pawn then put(pawn,'bCanBeDamaged',r.guard_damage_before=='1') end
            r.guard_damage_owned='0';c.save()
        end)
        attempt('spectator',function()
            local spectator=assert(options.getSpectator(),'spectator unavailable')
            if r.guard_spectator_before=='0' then
                spectator:off();local status=spectator:status()
                if status.pending_flags~=0 or status.pending_relations~=0 then return false end
            elseif not spectator:status().enabled_requested then
                spectator:on()
            end
            r.guard_spectator_owned='0';c.save()
        end)
        if not pending then r.guard_started='0';c.save();log('[Observer] 锁血效果、可受伤资格、模型和无仇恨已恢复；只撤销本次持有的效果和状态') end
        return not pending
    end
    return self
end
return Guard
