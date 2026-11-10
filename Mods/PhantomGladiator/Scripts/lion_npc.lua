-- Separate physical poles for NPC opponents. Only poles created here may be removed.
local U=require('ue_observe')
local LionNPC={}
local BOSS='/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_LionDancer_P2.BP_Monster_LionDancer_P2_C'
local POLE='/Game/RenewalContent/Actors/SpecialMove/Volume/BP_LionDancing_Pole_Base.BP_LionDancing_Pole_Base_C'
local ON_POLE='CharacterState.AbilityState.LionDancer.OnPole'
local PROTECTED={'CharacterState.Unselectable.Force.Perform','CharacterState.Stand.Invulnerable.Unselectable'}
local BUSY={'Ability.Action','CharacterState.InLevelSequence','CharacterState.Stand.Break',
    'CharacterState.Hitreact.State.Lying','AI.DisableCombatAI'}
local POLE_TOP=500.126801 -- the native wood mesh's local upper bound
local RETRY,SETTLE=5,0.4

local function call(object,method,...)
    if not U.valid(object) then return false end
    local ok,value=pcall(function(target,key,...)return target[key](target,...)end,object,method,...)
    return ok,U.unwrap(value)
end
local function same(a,b)
    local key=U.key(a)
    return key~=nil and key==U.key(b)
end
local function vector(value)
    local x,y,z=U.struct(value,'X'),U.struct(value,'Y'),U.struct(value,'Z')
    if type(x)=='number' and type(y)=='number' and type(z)=='number' then return {X=x,Y=y,Z=z} end
end
local function rotationOf(actor)
    local ok,value=call(actor,'K2_GetActorRotation')
    if not ok then return nil end
    local pitch,yaw,roll=U.struct(value,'Pitch'),U.struct(value,'Yaw'),U.struct(value,'Roll')
    if type(pitch)=='number' and type(yaw)=='number' and type(roll)=='number' then
        return {Pitch=pitch,Yaw=yaw,Roll=roll}
    end
end
local function distance2(a,b)
    return (a.X-b.X)^2+(a.Y-b.Y)^2
end
local function contains(list,actor)
    for _,value in ipairs(U.array(list) or {})do if same(value,actor) then return true end end
    return false
end

function LionNPC.new(options)
    local self={seats={},sources={}}
    local find=options.find or StaticFindObject
    local load=options.load or LoadAsset
    local name=options.fname or FName
    local combat=options.combat
    local retryAt,waiting,failedFor={},{},{}
    local currentWorld,poleClass
    local function say(text)options.log('[LionNPC] '..text)end
    local function gone(actor)
        return not U.valid(actor) or options.isDestroying(actor)==true
    end
    local function alive(actor)
        if gone(actor) then return false end
        local hp=options.hp(actor)
        return type(hp)=='number' and hp>0
    end
    local function location(actor)
        return not gone(actor) and vector(options.location(actor)) or nil
    end
    local function tag(actor,text)
        local ok,value=call(U.field(actor,'AbilitySystemComponent'),'GetGameplayTagCount',{TagName=name(text)})
        return ok and type(value)=='number' and value or nil
    end
    local function clearTags(actor,tags)
        for _,text in ipairs(tags)do if tag(actor,text)~=0 then return false end end
        return true
    end
    local function idle(actor)
        if gone(actor) or (options.busy and options.busy(actor)) or not clearTags(actor,BUSY) then return false end
        local montage=U.field(U.field(actor,'AbilitySystemComponent'),'LocalAnimMontageInfo')
        local ability=U.struct(montage,'AnimatingAbility')
        if U.kind(ability)=='FWeakObjectPtr' then
            local ok,value=pcall(function()return ability:Get()end)
            if not ok then return false end
            ability=U.unwrap(value)
        end
        return not U.valid(ability) or U.field(ability,'bIsActive')==false
    end
    local function wait(actor,why)
        local key=U.key(actor)
        if key and waiting[key]~=why then
            waiting[key]=why
            say('等待上桩 actor='..key..' 读回='..why)
        end
        return nil
    end
    local function shape(actor)
        local capsule=U.field(actor,'CapsuleComponent')
        local okRadius,radius=call(capsule,'GetScaledCapsuleRadius')
        local okHalf,half=call(capsule,'GetScaledCapsuleHalfHeight')
        local movement=U.field(actor,'CharacterMovement')
        local mode=tonumber((U.field(movement,'MovementMode')))
        if not okRadius or not okHalf or type(radius)~='number' or type(half)~='number'
            or radius<=0 or half<radius or not U.valid(movement) then return nil end
        if mode~=0 and mode~=1 and mode~=2 and mode~=5 then return nil end
        return {capsule=capsule,radius=radius,half=half,movement=movement,mode=mode}
    end
    local function sourceAnchor(source)
        local at=location(source.actor)
        if not at then return nil end
        local best,closest
        for _,pole in ipairs(U.array(U.field(source.area,'ActivatedPoles')) or {})do
            local owned=false
            for _,seat in pairs(self.seats)do
                if same(pole,seat.pole) or same(pole,seat.previousPole)
                    or (seat.nextPole and same(pole,seat.nextPole.pole)) then owned=true;break end
            end
            if not owned and not gone(pole) and same(U.field(pole,'Area'),source.area)
                and U.field(pole,'Occupied')==true and U.field(pole,'Activated')==true then
                local ok,point=call(U.field(pole,'StandPoint'),'K2_GetComponentLocation')
                point=ok and vector(point) or nil
                local d=point and distance2(point,at)
                if d and (not closest or d<closest) then best,closest=point,d end
            end
        end
        return closest and closest<600^2 and best or nil
    end
    local function chooseSpot(actor,carrier,source,body,anchor)
        local at=location(carrier)
        local bossBody=shape(source.actor)
        if not at or not bossBody then return nil end
        local gap=body.radius+bossBody.radius+45
        local range=options.range(actor)
        local reach=type(range)=='number' and math.max(gap,math.min(range*0.65,1000)) or gap+80
        local angle=math.atan(at.Y-anchor.Y,at.X-anchor.X)
        for _,degrees in ipairs({0,45,-45,90,-90,135,-135,180})do
            local radians=angle+math.rad(degrees)
            local candidate={X=anchor.X+math.cos(radians)*reach,Y=anchor.Y+math.sin(radians)*reach,Z=anchor.Z}
            local free=true
            for _,seat in pairs(self.seats)do
                local minimum=(body.radius+seat.body.radius+75)^2
                if (seat.top and distance2(candidate,seat.top)<minimum)
                    or (seat.nextPole and distance2(candidate,seat.nextPole.top)<minimum) then free=false;break end
            end
            if free then return candidate end
        end
    end
    local function classOfPole()
        if U.valid(poleClass) then return poleClass end
        local ok,value=pcall(find,POLE)
        if not ok or not U.valid(value) then
            ok,value=pcall(load,POLE)
            if not ok or not U.valid(value) then ok,value=pcall(find,POLE) end
        end
        local named,full=call(value,'GetFullName')
        if named and full=='BlueprintGeneratedClass '..POLE then poleClass=value;return value end
    end
    local function write(object,field,value)
        if not U.valid(object) then return false end
        local ok=pcall(function()object[field]=value end)
        return ok and U.field(object,field)==value
    end
    local function restoreFields(seat)
        local body=seat.body
        local restored=true
        for _,flag in ipairs({'bCanWalkOffLedges','bCanWalkOffLedgesWhenCrouching'})do
            if seat[flag]~=nil and U.valid(body.movement) then
                local value=U.field(body.movement,flag)
                if value==false then restored=write(body.movement,flag,seat[flag]) and restored
                elseif value~=true then restored=false end
            end
        end
        if seat.oldResponse~=nil and U.valid(body.capsule) then
            local ok,response=call(body.capsule,'GetCollisionResponseToChannel',seat.poleChannel)
            if not ok or not tonumber(response) then restored=false
            elseif tonumber(response)==2 then
                call(body.capsule,'SetCollisionResponseToChannel',seat.poleChannel,seat.oldResponse)
                local read,after=call(body.capsule,'GetCollisionResponseToChannel',seat.poleChannel)
                restored=read and tonumber(after)==seat.oldResponse and restored
            end
        end
        if seat.changedMode and U.valid(body.movement) then
            local mode=tonumber((U.field(body.movement,'MovementMode')))
            if mode==1 or (seat.hopAt and mode==3) then
                call(body.movement,'SetMovementMode',body.mode,0)
                restored=tonumber((U.field(body.movement,'MovementMode')))==body.mode and restored
            elseif not mode then restored=false end
        end
        if seat.hopMode==5 and U.valid(body.movement) then
            local mode=tonumber((U.field(body.movement,'MovementMode')))
            if mode==1 or mode==3 then
                call(body.movement,'SetMovementMode',5,0)
                restored=tonumber((U.field(body.movement,'MovementMode')))==5 and restored
            elseif not mode then restored=false end
        end
        return restored
    end
    local function teleport(actor,destination,rotation)
        local ok,result=call(actor,'K2_TeleportTo',destination,rotation)
        local after=location(actor)
        return ok and result==true and after and distance2(after,destination)<=25^2 and math.abs(after.Z-destination.Z)<=25
    end
    local function removePole(seat,pole)
        if gone(pole) or not U.inWorld(pole,seat.world) then return true end
        if not gone(seat.area) and U.inWorld(seat.area,seat.world) then
            if not call(seat.area,'UnregisterPole',pole) then return false end
            if contains(U.field(seat.area,'ActivatedPoles'),pole) or contains(U.field(seat.area,'DeactivatedPoles'),pole) then return false end
        end
        call(pole,'K2_DestroyActor')
        return gone(pole)
    end
    local function release(seat,why)
        -- A map transition invalidates the whole old world. Never call its actors again.
        if not same(currentWorld,seat.world) then return true end
        local carrierHere=U.inWorld(seat.carrier,seat.world)
        local returned=false
        if seat.moved and carrierHere and alive(seat.carrier) then
            local at=location(seat.carrier)
            local body=seat.body
            local ground=at and options.ground(seat.world,at.X,at.Y,at.Z-body.half,0)
            local dest=type(ground)=='number' and {X=at.X,Y=at.Y,Z=ground+body.half+3} or seat.original
            local rotation=rotationOf(seat.carrier) or seat.rotation
            if not teleport(seat.carrier,dest,rotation)
                and (dest==seat.original or not teleport(seat.carrier,seat.original,rotation)) then
                if combat then combat:release(seat) end
                wait(seat.actor,'下桩位置尚未读回')
                return false
            end
            seat.moved=false
            returned=true
        end
        if carrierHere and not gone(seat.carrier) and not restoreFields(seat) then return false end
        if combat and not combat:release(seat) then return false end
        if seat.nextPole and not removePole(seat,seat.nextPole.pole) then return false end
        if seat.previousPole and not removePole(seat,seat.previousPole) then return false end
        if not removePole(seat,seat.pole) then return false end
        say('下桩与独立桩清理 actor='..seat.key..' 原因='..why..' 返地读回='..tostring(returned)..' 属性/桩移除读回=true')
        return true
    end
    local function spawnPole(seat,top,now)
        local cls,statics=classOfPole(),options.statics()
        if not U.valid(cls) or not U.valid(statics) or not U.valid(seat.carrier) or not U.valid(currentWorld) then return nil end
        local body,carrier=seat.body,seat.carrier
        local scale=math.max(1,(body.radius+25)/40)
        local transform={Translation={X=top.X,Y=top.Y,Z=top.Z-POLE_TOP},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=scale,Y=scale,Z=1}}
        local began,pole=call(statics,'BeginDeferredActorSpawnFromClass',currentWorld,cls,transform,1,carrier,1)
        if not began or gone(pole) then return nil end
        local platform={pole=pole,top=top,createdAt=now}
        local configured=write(pole,'Occupied',true) and write(pole,'PlayerCanJump',false) and write(pole,'CanCreateLink',false)
        local finished=configured and U.valid(cls) and U.valid(currentWorld)
            and call(statics,'FinishSpawningActor',pole,transform,1)
        local mesh=U.field(pole,'SM_WoodPost_001')
        local okType,pawnType=call(body.capsule,'GetCollisionObjectType')
        local poleTypeRead,poleType=call(mesh,'GetCollisionObjectType')
        if finished and same(U.field(pole,'Owner'),carrier) and U.inWorld(pole,currentWorld)
            and okType and poleTypeRead and tonumber(pawnType) and tonumber(poleType) then
            platform.mesh=mesh
            platform.poleChannel=tonumber(poleType)
            platform.pawnChannel=tonumber(pawnType)
            platform.readyToCheck=call(mesh,'SetCollisionResponseToChannel',platform.pawnChannel,2)
                and call(mesh,'SetGenerateOverlapEvents',true) and call(pole,'SetActorEnableCollision',true)
                and call(mesh,'SetCollisionEnabled',1)
        end
        say('准备独立桩 actor='..seat.key..' 体型半径='..body.radius..' 移动模式='..body.mode
            ..' 生成所有者读回='..tostring(same(U.field(pole,'Owner'),carrier))..' 碰撞准备调用='..tostring(platform.readyToCheck==true))
        return platform
    end
    local function validatePole(seat,platform)
        if not platform.readyToCheck or gone(seat.area) or gone(platform.pole) then return false end
        local pole=platform.pole
        local _,overlap=call(pole,'IsOverlappingActor',seat.area)
        if overlap==true and not contains(U.field(seat.area,'ActivatedPoles'),pole) then
            call(seat.area,'ReceiveActorBeginOverlap',pole)
        end
        local ok,point=call(U.field(pole,'StandPoint'),'K2_GetComponentLocation')
        local top=ok and vector(point) or nil
        local _,poleResponse=call(platform.mesh,'GetCollisionResponseToChannel',platform.pawnChannel)
        local _,collisionMode=call(platform.mesh,'GetCollisionEnabled')
        local registered=same(U.field(pole,'Area'),seat.area) and contains(U.field(seat.area,'ActivatedPoles'),pole)
        if not top or not registered or tonumber(poleResponse)~=2 or tonumber(collisionMode)~=1
            or U.field(pole,'Activated')~=true or U.field(pole,'Occupied')~=true then return false end
        platform.top=top
        return true
    end
    local function create(actor,carrier,source,now)
        local key=U.key(carrier)
        if not key or not alive(carrier) or not U.inWorld(carrier,currentWorld) then return end
        if not U.npcPath(actor) or not U.npcPath(carrier) then return wait(actor,'未读到原生NPC身份') end
        local body=shape(carrier)
        local anchor=sourceAnchor(source)
        if not body or not anchor or not idle(actor) or not idle(carrier) then return wait(actor,'动作、移动模式或原版占用桩未就绪') end
        local top=chooseSpot(actor,carrier,source,body,anchor)
        local original=location(carrier)
        local rotation=rotationOf(carrier)
        if not top or not original or not rotation then return wait(actor,'落点未读回') end
        local seat={actor=actor,carrier=carrier,key=key,source=source,area=source.area,world=currentWorld,
            body=body,original=original,rotation=rotation}
        local platform=spawnPole(seat,top,now)
        if not platform then return wait(actor,'独立桩生成未读回') end
        for field,value in pairs(platform)do seat[field]=value end
        self.seats[key]=seat
        seat.failed=not seat.readyToCheck
    end
    local function board(seat,now)
        if now-seat.createdAt<SETTLE then return end
        local actor,body=seat.carrier,seat.body
        if not idle(seat.actor) or not idle(actor) or tonumber((U.field(body.movement,'MovementMode')))~=body.mode then
            if now-seat.createdAt>3 then seat.failed=true end
            return
        end
        if not validatePole(seat,seat) then
            seat.failed=true
            return wait(seat.actor,'桩高度、登记或双向碰撞未读回')
        end
        local read,old=call(body.capsule,'GetCollisionResponseToChannel',seat.poleChannel)
        if not read or not tonumber(old) then seat.failed=true;return end
        if tonumber(old)~=2 then
            seat.oldResponse=tonumber(old)
            call(body.capsule,'SetCollisionResponseToChannel',seat.poleChannel,2)
            local _,response=call(body.capsule,'GetCollisionResponseToChannel',seat.poleChannel)
            if tonumber(response)~=2 then seat.failed=true;return end
        end
        if body.mode==1 or body.mode==2 then
            for _,flag in ipairs({'bCanWalkOffLedges','bCanWalkOffLedgesWhenCrouching'})do
                local before=U.field(body.movement,flag)
                if type(before)~='boolean' then seat.failed=true;return end
                seat[flag]=before
                if not write(body.movement,flag,false) then seat.failed=true;return end
            end
        end
        if body.mode==2 then
            seat.changedMode=true
            call(body.movement,'SetMovementMode',1,0)
            if tonumber((U.field(body.movement,'MovementMode')))~=1 then seat.failed=true;return end
        end
        local top=seat.top
        local dest={X=top.X,Y=top.Y,Z=top.Z+body.half+3}
        seat.moved=true -- retain rollback even if a teleport changes location but returns failure
        local moved=teleport(actor,dest,rotationOf(actor) or seat.rotation)
        seat.boardedAt=now
        seat.failed=not moved
        say('上桩定位 actor='..seat.key..' 原版桩登记=true 双向碰撞=2 位置读回='..tostring(moved))
    end
    local function verifySeat(seat,now)
        local mode=tonumber((U.field(seat.body.movement,'MovementMode')))
        local ok,base=call(seat.body.movement,'GetMovementBase')
        local supported=ok and (same(base,seat.mesh) or same(U.field(base,'Owner'),seat.pole))
        local at=location(seat.carrier)
        local inPlace=at and distance2(at,seat.top)<(seat.body.radius+35)^2
            and math.abs(at.Z-seat.top.Z-seat.body.half)<40
        local stationary=(seat.body.mode==0 or seat.body.mode==5) and mode==seat.body.mode and inPlace
        if supported or stationary then
            if not seat.confirmed then
                seat.confirmed=true
                say('NPC上桩确认 actor='..seat.key..' 物理基底='..tostring(supported)..' 原移动模式='..seat.body.mode..' 当前='..tostring(mode))
            end
            if not seat.source.resumed and now>=(seat.source.resumeAt or 0) then
                seat.source.resumeAt=now+1
                local library=options.library()
                if U.valid(library) and U.valid(seat.area) and alive(seat.carrier) then
                    local resumed,count=call(library,'ResumeLionDancerPoleClusterActions',seat.area,seat.carrier)
                    if resumed and type(count)=='number' then
                        seat.source.resumed=count>0
                        if seat.source.resumeRead~=count then
                            seat.source.resumeRead=count
                            say('用已上桩NPC继续原版桩群 actor='..seat.key..' 读回排入数量='..count)
                        end
                    end
                end
            end
            return true
        elseif now-seat.boardedAt>2 then
            -- After verified native movement off the pole, keep the new location.
            if seat.confirmed and not inPlace then seat.moved=false end
            seat.failed=true
            wait(seat.actor,'脚下支撑未读回或已离开')
        end
    end
    local function skipHop(seat,why,now)
        if removePole(seat,seat.nextPole.pole) then
            seat.nextPole=nil
            if not combat:endHop(seat,now) then seat.failed=true end
        else seat.failed=true end
        say('取消跨桩 actor='..seat.key..' 读回='..why)
    end
    local function hop(seat,now)
        local nextPole,body=seat.nextPole,seat.body
        if not combat:held(seat) then seat.failed=true;return end
        if seat.hopAt then
            local _,base=call(body.movement,'GetMovementBase')
            if same(base,nextPole.mesh) then
                seat.previousPole=seat.pole
                seat.pole,seat.mesh,seat.top=nextPole.pole,nextPole.mesh,nextPole.top
                seat.nextPole,seat.hopAt=nil,nil
                call(body.movement,'StopMovementImmediately')
                if seat.hopMode==5 then
                    call(body.movement,'SetMovementMode',5,0)
                    if tonumber((U.field(body.movement,'MovementMode')))~=5 then seat.failed=true;return end
                end
                seat.hopMode=nil
                if removePole(seat,seat.previousPole) then seat.previousPole=nil end
                if not combat:endHop(seat,now) then seat.failed=true end
                say('跨桩落脚 actor='..seat.key..' 新桩物理基底读回=true')
            elseif now-seat.hopAt>1.6 then
                seat.failed=true
                wait(seat.actor,'跨桩落脚未读回')
            end
            return
        end
        if now-nextPole.createdAt<SETTLE then return end
        if not idle(seat.actor) or not idle(seat.carrier) then
            if now-nextPole.createdAt>3 then skipHop(seat,'仍在受击或技能中',now) end
            return
        end
        local at=location(seat.carrier)
        local mode=tonumber((U.field(body.movement,'MovementMode')))
        local _,gravity=call(body.movement,'GetGravityZ')
        if not at or (mode~=1 and mode~=5) or type(gravity)~='number' or gravity>=-1
            or nextPole.poleChannel~=seat.poleChannel or not validatePole(seat,nextPole) then
            skipHop(seat,'移动、重力或目标桩未读回',now);return
        end
        local top=nextPole.top
        local dx,dy,dz=top.X-at.X,top.Y-at.Y,top.Z+body.half+3-at.Z
        if dx*dx+dy*dy>1300^2 or math.abs(dz)>300 then skipHop(seat,'目标桩超出跳跃范围',now);return end
        if not combat:beginHop(seat) then seat.failed=true;return end
        local seconds=0.8
        seat.hopMode=mode
        seat.hopAt=now
        local launched=call(seat.carrier,'LaunchCharacter',{X=dx/seconds,Y=dy/seconds,Z=dz/seconds-gravity*seconds/2},true,true)
        say('跨桩起跳 actor='..seat.key..' 目标桩读回=true 原生起跳调用='..tostring(launched))
        if not launched then seat.failed=true end
    end
    local function fight(seat,now)
        if not combat then return end
        if not seat.combat and not combat:arm(seat,now) then seat.failed=true;return end
        if seat.previousPole and removePole(seat,seat.previousPole) then seat.previousPole=nil end
        local ok,wantsHop=combat:tick(seat,now,idle(seat.actor) and idle(seat.carrier))
        if not ok then seat.failed=true;return end
        if wantsHop and not seat.previousPole and seat.body.mode~=0 then
            local anchor=sourceAnchor(seat.source)
            local top=anchor and chooseSpot(seat.actor,seat.carrier,seat.source,seat.body,anchor)
            if top and distance2(top,seat.top)<=1300^2 then seat.nextPole=spawnPole(seat,top,now) end
        end
    end

    function self:stop(why)
        local complete=true
        for key,seat in pairs(self.seats)do
            if release(seat,why or '停止') then self.seats[key]=nil else complete=false end
        end
        if complete then self.sources={};retryAt={};waiting={};failedFor={} end
        return complete
    end
    function self:releaseActor(actor)
        local complete=true
        for key,seat in pairs(self.seats)do
            if same(actor,seat.actor) or same(actor,seat.carrier) or same(actor,seat.source.actor) then
                -- The caller will destroy this carrier immediately after the owned state is restored.
                if same(actor,seat.carrier) then seat.moved=false end
                if release(seat,'角色清理') then self.seats[key]=nil else complete=false end
            end
        end
        return complete
    end
    function self:holds(actor)
        for _,seat in pairs(self.seats)do
            if seat.moved and (same(actor,seat.carrier) or same(actor,seat.actor)) then return true end
        end
        return false
    end
    function self:count()
        local n=0
        for _ in pairs(self.seats)do n=n+1 end
        return n
    end
    function self:tick(members,status)
        local world=options.world()
        if not U.valid(world) then return end
        if currentWorld and not same(world,currentWorld) then
            self.seats={};self.sources={};retryAt={};waiting={};failedFor={}
        end
        currentWorld=world
        if not status or not status.battle_active then self:stop('对战结束');return end
        local now=options.now()
        if type(now)~='number' then return end
        local hasBoss=false
        for _,entry in ipairs(members or {})do
            if entry.class_path==BOSS then hasBoss=true;break end
        end
        if not hasBoss then self:stop('没有烈焰参战');return end
        local active,roster={},{}
        for _,entry in ipairs(members or {})do
            local actor=entry.actor
            local key=U.key(actor)
            if key and alive(actor) and U.inWorld(actor,world) and (entry.team=='blue' or entry.team=='red')
                and not entry.stand and not entry.reserve and not entry.aid then
                roster[key]=entry
                if entry.class_path==BOSS and (tag(actor,ON_POLE) or 0)>0 then
                    local source=self.sources[key] or {actor=actor}
                    if gone(source.area) then source.area=options.area(actor,world) end
                    if not gone(source.area) and U.inWorld(source.area,world) then
                        source.team=entry.team
                        self.sources[key]=source
                        active[key]=source
                    end
                end
            end
        end
        self.sources=active
        for key,seat in pairs(self.seats)do
            local owner=roster[U.key(seat.actor)]
            local target=owner and options.opponent(seat.actor)
            local carrier=owner and options.carrier(seat.actor)
            if not active[U.key(seat.source.actor)] or not owner or not same(carrier,seat.carrier)
                or not same(target,seat.source.actor) or not clearTags(seat.source.actor,PROTECTED)
                or gone(seat.pole) or U.field(seat.pole,'Activated')~=true or not alive(seat.carrier) or seat.failed then
                if release(seat,'阶段、目标或支撑变化') then
                    local actorKey=U.key(seat.actor) or key
                    self.seats[key]=nil;retryAt[actorKey]=now+RETRY
                    if seat.failed then failedFor[actorKey]=seat.source end
                end
            elseif seat.nextPole then hop(seat,now)
            elseif seat.boardedAt then
                if verifySeat(seat,now) then fight(seat,now) end
            else board(seat,now) end
        end
        if not next(active) then return end
        -- At most one new native actor per support tick, including multi-opponent battles.
        for key,entry in pairs(roster)do
            if entry.class_path~=BOSS and (not retryAt[key] or now>=retryAt[key]) then
                local target=options.opponent(entry.actor)
                local source=active[U.key(target)]
                if source and source~=failedFor[key] and source.team~=entry.team and clearTags(source.actor,PROTECTED) then
                    local carrier=options.carrier(entry.actor)
                    if U.valid(carrier) and not self.seats[U.key(carrier)] then
                        retryAt[key]=now+RETRY
                        create(entry.actor,carrier,source,now)
                        break
                    end
                end
            end
        end
    end
    return self
end

return LionNPC
