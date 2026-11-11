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
local MOTION_WARP='/Script/MotionWarping.MotionWarpingComponent'
local FIRST_START,FIRST_LAND=0.235649,1.044753
local JUMP_START,JUMP_LAND=0.513629,1.249791

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
    local loop=options.loop or LoopInGameThreadWithDelay
    local cancel=options.cancel or CancelDelayedAction
    local pickups={}
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
        if gone(actor) then return false,'角色已离场' end
        if options.busy and options.busy(actor) then return false,'处决或受抓尚未结束' end
        for _,text in ipairs(BUSY)do
            local count=tag(actor,text)
            if count~=0 then return false,text..'='..tostring(count) end
        end
        local montage=U.field(U.field(actor,'AbilitySystemComponent'),'LocalAnimMontageInfo')
        local ability=U.struct(montage,'AnimatingAbility')
        if U.kind(ability)=='FWeakObjectPtr' then
            local ok,value=pcall(function()return ability:Get()end)
            if not ok then return false,'当前动作未读回' end
            ability=U.unwrap(value)
        end
        if U.valid(ability) and U.field(ability,'bIsActive')~=false then return false,'原生招式仍在执行' end
        return true
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
        local body=shape(source.actor)
        if not at or not body then return nil,'烈焰位置或胶囊未读回' end
        local feet=at.Z-body.half
        local best,closest
        local under,underDistance
        for _,pole in ipairs(U.array(U.field(source.area,'ActivatedPoles')) or {})do
            local owned=false
            for _,seat in pairs(self.seats)do
                if same(pole,seat.pole) or (seat.otherPole and same(pole,seat.otherPole.pole))
                    or (seat.nextPole and same(pole,seat.nextPole.pole)) then owned=true;break end
            end
            if not owned and not gone(pole) and same(U.field(pole,'Area'),source.area)
                and U.field(pole,'Activated')==true then
                local ok,point=call(U.field(pole,'StandPoint'),'K2_GetComponentLocation')
                point=ok and vector(point) or nil
                local d=point and distance2(point,at)
                if d and d<600^2 then
                    if U.field(pole,'Occupied')==true and (not closest or d<closest) then best,closest=point,d end
                    local height=math.abs(point.Z-feet)
                    if height<=160 then
                        local distance=d+height^2
                        if not underDistance or distance<underDistance then under,underDistance=point,distance end
                    end
                end
            end
        end
        if best then return best,'原版占用桩' end
        if under then return under,'烈焰脚下的原版桩' end
        return nil,'烈焰身边的桩顶未读回'
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
                    or (seat.otherPole and distance2(candidate,seat.otherPole.top)<minimum)
                    or (seat.blockedTop and same(seat.actor,actor) and distance2(candidate,seat.blockedTop)<minimum)
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
    local function poleWarp(actor)
        local ok,cls=pcall(find,MOTION_WARP)
        if not ok or not U.valid(cls) then return nil end
        local _,component=call(actor,'GetComponentByClass',cls)
        for _,target in ipairs(U.array(U.field(component,'WarpTargets')) or {})do
            local targetName=U.struct(target,'Name')
            local named,text=pcall(function()return targetName:ToString()end)
            if named and text=='Pole' then return vector(U.struct(target,'Location')) end
        end
    end
    local function pickupPole(pickup,body,carrier,now)
        if not pickup or not pickup.planned then return nil end
        local warp=pickup.warp or poleWarp(pickup.actor)
        local at=location(carrier)
        if not warp or not at then return nil end
        local _,pawnChannel=call(body.capsule,'GetCollisionObjectType')
        if type(pawnChannel)~='number' then return nil end
        local chosen,closest
        for _,pole in ipairs(U.array(U.field(pickup.area,'ActivatedPoles')) or {})do
            local key=U.key(pole)
            if key and not pickup.prior[key] and not gone(pole) and U.inWorld(pole,pickup.world)
                and same(U.field(pole,'Area'),pickup.area) and U.field(pole,'Occupied')==false
                and U.field(pole,'Activated')==true then
                local _,value=call(U.field(pole,'StandPoint'),'K2_GetComponentLocation')
                local top=vector(value)
                local gap=top and distance2(top,warp)
                if gap and gap<=80^2 and math.abs(top.Z-warp.Z)<=180 and distance2(top,at)<=1300^2
                    and (not closest or gap<closest) then
                    local mesh=U.field(pole,'SM_WoodPost_001')
                    local _,response=call(mesh,'GetCollisionResponseToChannel',pawnChannel)
                    local _,mode=call(mesh,'GetCollisionEnabled')
                    local _,channel=call(mesh,'GetCollisionObjectType')
                    if tonumber(response)==2 and (tonumber(mode)==1 or tonumber(mode)==3) and type(channel)=='number' then
                        chosen={pole=pole,mesh=mesh,top=top,poleChannel=channel,pawnChannel=pawnChannel,
                            createdAt=now-SETTLE,readyToCheck=true}
                        closest=gap
                    end
                end
            end
        end
        return chosen
    end
    function self:beginPickup(actor,victim,members,status)
        if not combat or not status or not status.battle_active then return false end
        local world=options.world()
        if not U.inWorld(actor,world) then return false end
        local owner,team,sourceTeam,source
        for _,entry in ipairs(members)do
            if same(entry.actor,victim) then owner=entry.summoner end
            if same(entry.actor,actor) then team=entry.team end
        end
        for _,entry in ipairs(members)do
            if entry.class_path==BOSS and same(entry.actor,owner) then source,sourceTeam=entry.actor,entry.team;break end
        end
        if not source or (team~='blue' and team~='red') or (sourceTeam~='blue' and sourceTeam~='red')
            or team==sourceTeam or (tag(source,ON_POLE) or 0)<=0 then return false end
        local area=options.area(source,world)
        local poles=U.array(U.field(area,'ActivatedPoles'))
        if not poles or not U.inWorld(area,world) then return false end
        local key=U.key(actor)
        if not key or pickups[key] then return false end
        local prior={}
        for _,pole in ipairs(poles)do
            local poleKey=U.key(pole)
            if poleKey then prior[poleKey]=true end
        end
        pickups[key]={key=key,actor=actor,source=source,area=area,world=world,prior=prior,
            weapon=combat:captureWeapon(actor,world)}
        return true
    end
    function self:pickupEnded(actor)
        local pickup=pickups[U.key(actor)]
        if pickup then pickup.ended=options.now();pickup.planned=true end
    end
    local function stopFlight(seat)
        local flight=seat.flight
        if flight and flight.handle then
            pcall(cancel,flight.handle)
            flight.handle=nil
        end
    end
    local function ignoredComponents(capsule)
        local ok,items=call(capsule,'CopyArrayOfMoveIgnoreComponents')
        return ok and U.array(items) or nil
    end
    local function ignoreForFlight(flight,component,pending)
        if not U.valid(component) then return false end
        local list=pending or ignoredComponents(flight.capsule)
        if not list then return false end
        if contains(list,component) then return true end
        local key=U.key(component)
        if not key then return false end
        flight.ignored[key]=component
        if not call(flight.capsule,'IgnoreComponentWhenMoving',component,true) then return false end
        if pending then pending[#pending+1]=component;return true end
        return contains(ignoredComponents(flight.capsule),component)
    end
    local function restoreFlightCollision(flight)
        if not flight or not U.valid(flight.capsule) then return true end
        for key,component in pairs(flight.ignored)do
            if U.valid(component) then
                call(flight.capsule,'IgnoreComponentWhenMoving',component,false)
            else flight.ignored[key]=nil end
        end
        local list=ignoredComponents(flight.capsule)
        if list then
            for key,component in pairs(flight.ignored)do
                if not contains(list,component) then flight.ignored[key]=nil end
            end
        end
        return not next(flight.ignored)
    end
    local function hitComponent(hit)
        local component=U.struct(hit,'Component')
        if U.kind(component)=='FWeakObjectPtr' then
            local ok,value=pcall(function()return component:Get()end)
            component=ok and U.unwrap(value) or nil
        end
        return U.valid(component) and component or nil
    end
    local function stageHit(seat,component)
        local ok,owner=call(component,'GetOwner')
        if not ok or not U.inWorld(owner,seat.world) then return false end
        if contains(U.field(seat.area,'ActivatedPoles'),owner) and same(U.field(owner,'Area'),seat.area) then return 'pole' end
        local a,b=U.field(owner,'LinkedPoleA'),U.field(owner,'LinkedPoleB')
        if contains(U.field(seat.area,'ActivatedLinks'),owner) and same(U.field(owner,'Box'),component)
            and same(U.field(a,'Area'),seat.area) and same(U.field(b,'Area'),seat.area) then return 'link' end
        return false
    end
    local function linkCollision(seat,capsule)
        if not seat.linkCollision then seat.linkCollision={capsule=capsule,ignored={}} end
        if same(seat.linkCollision.capsule,capsule) then return seat.linkCollision end
    end
    local function ignoreStageLinks(seat,flight)
        local owned=linkCollision(seat,flight.capsule)
        if not owned then return false end
        local pending=ignoredComponents(flight.capsule)
        if not pending then return false end
        for _,link in ipairs(U.array(U.field(seat.area,'ActivatedLinks')) or {})do
            local a,b=U.field(link,'LinkedPoleA'),U.field(link,'LinkedPoleB')
            if not gone(link) and U.inWorld(link,seat.world) and same(U.field(a,'Area'),seat.area)
                and same(U.field(b,'Area'),seat.area) then
                local box=U.field(link,'Box')
                if U.valid(box) and not ignoreForFlight(owned,box,pending) then return false end
            end
        end
        local after=ignoredComponents(flight.capsule)
        if not after then return false end
        for _,component in pairs(owned.ignored)do if not contains(after,component) then return false end end
        return true
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
        if seat.flight and U.valid(body.movement) and tonumber((U.field(body.movement,'MovementMode')))==5 and body.mode~=5 then
            call(body.movement,'SetMovementMode',body.mode,0)
            restored=tonumber((U.field(body.movement,'MovementMode')))==body.mode and restored
        elseif seat.changedMode and U.valid(body.movement) then
            local mode=tonumber((U.field(body.movement,'MovementMode')))
            if mode==1 or (seat.flight and mode==3) then
                call(body.movement,'SetMovementMode',body.mode,0)
                restored=tonumber((U.field(body.movement,'MovementMode')))==body.mode and restored
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
        if same(pole,seat.borrowedPole) then
            if not same(U.field(pole,'Area'),seat.area) or U.field(pole,'Occupied')==false then return true end
            return write(pole,'Occupied',false)
        end
        if not gone(seat.area) and U.inWorld(seat.area,seat.world) then
            if not call(seat.area,'UnregisterPole',pole) then return false end
            if contains(U.field(seat.area,'ActivatedPoles'),pole) or contains(U.field(seat.area,'DeactivatedPoles'),pole) then return false end
        end
        call(pole,'K2_DestroyActor')
        return gone(pole)
    end
    local function release(seat,why)
        stopFlight(seat)
        -- A map transition invalidates the whole old world. Never call its actors again.
        if not same(currentWorld,seat.world) or not same(options.world(),seat.world) then return true end
        if not restoreFlightCollision(seat.flight) then return false end
        if not restoreFlightCollision(seat.linkCollision) then return false end
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
                wait(seat.actor,'下桩位置尚未读回')
                return false
            end
            seat.moved=false
            returned=true
        end
        if carrierHere and not gone(seat.carrier) and not restoreFields(seat) then return false end
        if seat.pickup and not combat:restoreWeapon(seat.pickup.weapon) then return false end
        if combat and not combat:release(seat) then return false end
        if seat.nextPole and not removePole(seat,seat.nextPole.pole) then return false end
        if seat.otherPole and not removePole(seat,seat.otherPole.pole) then return false end
        if not removePole(seat,seat.pole) then return false end
        if seat.pickup then pickups[seat.pickup.key]=nil end
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
        if not top or not registered or tonumber(poleResponse)~=2 or (tonumber(collisionMode)~=1 and tonumber(collisionMode)~=3)
            or U.field(pole,'Activated')~=true or U.field(pole,'Occupied')~=true then return false end
        platform.top=top
        return true
    end
    local function create(actor,carrier,source,now)
        local key=U.key(carrier)
        if not key or not alive(carrier) or not U.inWorld(carrier,currentWorld) then return end
        if not U.npcPath(actor) or not U.npcPath(carrier) then return wait(actor,'未读到原生NPC身份') end
        local body=shape(carrier)
        if not body then return wait(actor,'载体胶囊或移动模式未读回') end
        local finishing=options.busy and options.busy(actor)
        if not finishing then
            local ready,reason=idle(actor)
            if not ready then return wait(actor,reason) end
            if not same(actor,carrier) then
                ready,reason=idle(carrier)
                if not ready then return wait(actor,'坐骑'..reason) end
            end
        end
        local pickup=pickups[U.key(actor)]
        if pickup and (not same(pickup.source,source.actor) or not same(pickup.area,source.area)) then pickup=nil end
        if pickup and not pickup.planned then return wait(actor,'等待原版狮头桩升起') end
        local platform=pickupPole(pickup,body,carrier,now)
        local anchorRead='处决升起的原版桩'
        local top
        if not platform then
            local anchor
            anchor,anchorRead=sourceAnchor(source)
            if not anchor then return wait(actor,anchorRead) end
            top=chooseSpot(actor,carrier,source,body,anchor)
        end
        local original=location(carrier)
        local rotation=rotationOf(carrier)
        if (not platform and not top) or not original or not rotation then return wait(actor,'落点未读回') end
        local seat={actor=actor,carrier=carrier,key=key,source=source,area=source.area,world=currentWorld,
            body=body,original=original,rotation=rotation,pickup=pickup}
        if platform then
            seat.borrowedPole=platform.pole
            platform.readyToCheck=write(platform.pole,'Occupied',true)
        else platform=spawnPole(seat,top,now) end
        if not platform then return wait(actor,'独立桩生成未读回') end
        for field,value in pairs(platform)do seat[field]=value end
        self.seats[key]=seat
        seat.failed=not seat.readyToCheck
        say('上桩点准备 actor='..key..' 桩顶依据='..anchorRead..' 处决收尾='..tostring(finishing==true))
    end
    function self:pickupReady(actor)
        local pickup=pickups[U.key(actor)]
        if not pickup then return false end
        pickup.planned=true
        pickup.warp=pickup.warp or poleWarp(actor)
        local now=options.now()
        if type(now)~='number' or not same(currentWorld,pickup.world)
            or (tag(actor,'CharacterState.HasTempWeapon.HouHouHouHead') or 0)<=0
            or not clearTags(pickup.source,PROTECTED) or not same(options.opponent(actor),pickup.source) then
            return false
        end
        local carrier=options.carrier(actor)
        local key=U.key(carrier)
        local source=self.sources[U.key(pickup.source)]
        if key and not self.seats[key] and source and same(source.area,pickup.area) then
            create(actor,carrier,source,now)
        end
        local seat=self.seats[key]
        if not seat or seat.pickup~=pickup or seat.failed or now-seat.createdAt<SETTLE then return false end
        return validatePole(seat,seat)
    end
    local beginFlight
    local function board(seat,now)
        if now-seat.createdAt<SETTLE then return end
        local actor=seat.carrier
        local ready,reason=idle(seat.actor)
        if not ready then return wait(seat.actor,reason) end
        if not same(seat.actor,actor) then
            ready,reason=idle(actor)
            if not ready then return wait(seat.actor,'坐骑'..reason) end
        end
        local body=shape(actor)
        local original,rotation=location(actor),rotationOf(actor)
        if not body or not original or not rotation then return wait(seat.actor,'收尾后位置、胶囊或移动模式未读回') end
        if not same(body.capsule,seat.body.capsule) then seat.failed=true;return end
        seat.body,seat.original,seat.rotation=body,original,rotation
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
        if combat and not seat.combat and not combat:arm(seat,now) then seat.failed=true;return end
        if not beginFlight(seat,seat,now,false) then seat.failed=true end
    end
    local function supported(seat,platform)
        local ok,base=call(seat.body.movement,'GetMovementBase')
        local physical=ok and (same(base,platform.mesh) or same(U.field(base,'Owner'),platform.pole))
        local mode=tonumber((U.field(seat.body.movement,'MovementMode')))
        local at=location(seat.carrier)
        local inPlace=at and distance2(at,platform.top)<(seat.body.radius+35)^2
            and math.abs(at.Z-platform.top.Z-seat.body.half)<40
        if not physical and inPlace and (mode==1 or mode==2) then
            local floor={}
            local read=call(seat.body.movement,'K2_FindFloor',at,floor)
            local walkable=U.struct(floor,'bWalkableFloor')
            local distance=U.struct(floor,'FloorDist')
            if read and (walkable==true or walkable==1) and type(distance)=='number' and distance>=0 and distance<=40
                and same(hitComponent(U.struct(floor,'HitResult')),platform.mesh) then
                physical=true
                write(seat.body.movement,'bForceNextFloorCheck',true)
            end
        end
        local stationary=(seat.body.mode==0 or seat.body.mode==5) and mode==seat.body.mode and inPlace
        return physical or stationary,physical,inPlace,mode
    end
    local function verifySeat(seat,now)
        local ready,physical,inPlace,mode=supported(seat,seat)
        if ready then
            seat.lostAt=nil
            if not seat.confirmed then
                seat.confirmed=true
                say('NPC上桩确认 actor='..seat.key..' 物理基底='..tostring(physical)..' 原移动模式='..seat.body.mode..' 当前='..tostring(mode))
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
        end
        seat.lostAt=seat.lostAt or now
        if now-seat.lostAt>1 then
            -- Allow native knockback to land normally. Restore the weapon when leaving.
            if seat.confirmed and not inPlace then seat.moved=false end
            seat.failed=true
            wait(seat.actor,'脚下支撑已离开')
        end
    end

    beginFlight=function(seat,platform,now,returning)
        local actor,movement=seat.carrier,seat.body.movement
        local from,rotation=location(actor),rotationOf(actor)
        if not from or not rotation or not U.valid(movement) or not validatePole(seat,platform)
            or platform.poleChannel~=seat.poleChannel or type(loop)~='function' or type(cancel)~='function' then
            return false
        end
        local top=platform.top
        local to={X=top.X,Y=top.Y,Z=top.Z+seat.body.half+3}
        local dx,dy,dz=to.X-from.X,to.Y-from.Y,to.Z-from.Z
        if dx*dx+dy*dy>1300^2 or math.abs(dz)>850 then return false end
        local first=not seat.confirmed
        if combat and not returning and not combat:beginHop(seat,first) then return false end
        if not restoreFlightCollision(seat.flight) then return false end
        local flight={platform=platform,returning=returning,started=now,first=first,
            capsule=seat.body.capsule,ignored={},additionalIgnores=0}
        seat.flight=flight
        if not ignoreForFlight(flight,seat.mesh) or not ignoreForFlight(flight,platform.mesh)
            or (returning and seat.nextPole and not ignoreForFlight(flight,seat.nextPole.mesh))
            or not ignoreStageLinks(seat,flight) then
            say('跳桩碰撞忽略未读回 actor='..seat.key)
            return false
        end
        local yaw=math.deg(math.atan(dy,dx))
        if dx*dx+dy*dy<1 then yaw=rotation.Yaw end
        local turn=(yaw-rotation.Yaw+180)%360-180
        local lift=math.max(120,math.abs(dz)*0.42+75)
        local clearance=35
        local takeoff,arrival=JUMP_START,JUMP_LAND
        if first then takeoff,arrival=FIRST_START,FIRST_LAND end
        local landMode=seat.body.mode==2 and 1 or seat.body.mode
        call(movement,'StopMovementImmediately')
        call(movement,'SetMovementMode',5,0)
        if tonumber((U.field(movement,'MovementMode')))~=5 then return false end
        seat.moved=true
        local function fail(reason)
            flight.error=reason
            stopFlight(seat)
            if same(options.world(),seat.world) and not restoreFlightCollision(flight) then
                say('跳桩碰撞恢复待重试 actor='..seat.key)
            end
        end
        local function sweep(desired,angle)
            local hit={}
            local called=call(actor,'K2_SetActorLocationAndRotation',desired,angle,true,hit,false)
            local actual=location(actor)
            local reached=called and actual and distance2(actual,desired)<=8^2 and math.abs(actual.Z-desired.Z)<=8
            return reached,actual,hit
        end
        local function move(desired,angle,linksOnly)
            local reached,actual,hit=sweep(desired,angle)
            while not reached and flight.additionalIgnores<4 do
                local component=hitComponent(hit)
                local kind=stageHit(seat,component)
                local owned=kind=='link' and linkCollision(seat,flight.capsule) or flight
                if not kind or (linksOnly and kind~='link') or not owned
                    or contains(ignoredComponents(flight.capsule),component)
                    or not ignoreForFlight(owned,component) then break end
                flight.additionalIgnores=flight.additionalIgnores+1
                say('跳跃暂让场地部件 actor='..seat.key..' 部件='..tostring(U.key(component))..' 忽略读回=true')
                reached,actual,hit=sweep(desired,angle)
            end
            return reached,actual,hit
        end
        local function pointText(point)
            return point and string.format('%.1f,%.1f,%.1f',point.X,point.Y,point.Z) or '未读回'
        end
        local function blocked(progress,hit,desired,actual)
            local component=hitComponent(hit)
            local _,full=call(component,'GetFullName')
            fail(string.format('跳跃位移未到位 %.0f%% 碰撞部件=%s 深度=%s 目标=%s 实际=%s',
                progress*100,tostring(full or '未读回'),tostring(U.struct(hit,'PenetrationDepth')),pointText(desired),pointText(actual)))
        end
        local function land(time)
            call(movement,'StopMovementImmediately')
            if landMode~=5 then call(movement,'SetMovementMode',landMode,0) end
            if tonumber((U.field(movement,'MovementMode')))~=landMode then fail('落脚移动模式未读回');return end
            flight.arrived=time
            stopFlight(seat)
        end
        local function step()
            if self.seats[seat.key]~=seat or seat.flight~=flight or flight.error or flight.arrived then return end
            if not same(options.world(),seat.world) or not alive(actor) or not alive(seat.source.actor)
                or (tag(seat.source.actor,ON_POLE) or 0)<=0 or not clearTags(seat.source.actor,PROTECTED)
                or gone(platform.pole) or U.field(platform.pole,'Activated')~=true
                or not same(U.field(actor,'CharacterMovement'),movement) then fail('角色、场地或桩状态变化');return end
            if tonumber((U.field(movement,'MovementMode')))~=5 then fail('原生动作接管了移动');return end
            local time=options.now()
            if type(time)~='number' then fail('跳跃时钟未读回');return end
            local elapsed=time-flight.started
            if elapsed>3.5 then fail('跳跃动画没有推进');return end
            local angle={Pitch=rotation.Pitch,Yaw=rotation.Yaw+turn*math.min(1,elapsed/takeoff),Roll=rotation.Roll}
            if flight.descending then
                local alpha=math.min(1,(time-flight.descending)/0.13)
                local desired={X=to.X,Y=to.Y,Z=to.Z+clearance*(1-alpha)}
                local reached,actual,hit=move(desired,angle,true)
                if not reached then
                    local onTop=actual and distance2(actual,to)<=8^2 and actual.Z>=to.Z-8
                        and actual.Z<=to.Z+clearance and same(hitComponent(hit),platform.mesh)
                    if onTop then land(time) else blocked(1,hit,desired,actual) end
                elseif alpha>=1 then land(time) end
                return
            end
            local frame=not returning and combat and combat.jumpPosition and combat:jumpPosition(seat)
            if type(frame)~='number' then frame=elapsed end
            local progress=returning and elapsed/0.65 or (frame-takeoff)/(arrival-takeoff)
            progress=math.min(1,math.max(0,progress))
            if progress<=0 then
                call(actor,'K2_SetActorRotation',angle,false)
                return
            end
            local horizontal=progress*progress*(3-2*progress)
            local desired={X=from.X+dx*horizontal,Y=from.Y+dy*horizontal,
                Z=from.Z+(dz+clearance)*progress+4*lift*progress*(1-progress)}
            local reached,actual,hit=move(desired,angle,false)
            if not reached then blocked(progress,hit,desired,actual);return end
            if progress>=1 then
                if not restoreFlightCollision(flight) then fail('落脚前碰撞恢复未读回');return end
                flight.descending=time
                say('到达目标桩正上方 actor='..seat.key..' 桩体碰撞已恢复，横杆避让保持，开始落脚')
            end
        end
        local registered,handle=pcall(loop,16,function()
            local ok,err=pcall(step)
            if not ok then fail('跳跃更新异常 '..tostring(err)) end
        end)
        if not registered or handle==nil or handle==false then return false end
        flight.handle=handle
        local label=returning and '回到上一根桩' or (flight.first and '首次上桩起跳' or '跨桩起跳')
        say(string.format('%s actor=%s 目标桩读回=true 距离=%.0f 高差=%.0f',label,seat.key,math.sqrt(dx*dx+dy*dy),dz))
        return true
    end

    local function finishFlight(seat,now)
        local flight=seat.flight
        local landed=flight.arrived and supported(seat,flight.platform)
        if landed then
            if flight.platform~=seat then
                local old={pole=seat.pole,mesh=seat.mesh,top=seat.top,createdAt=seat.createdAt,
                    poleChannel=seat.poleChannel,pawnChannel=seat.pawnChannel,readyToCheck=seat.readyToCheck}
                for field,value in pairs(flight.platform)do seat[field]=value end
                seat.otherPole=old
            elseif flight.returning and seat.nextPole then
                if not removePole(seat,seat.nextPole.pole) then seat.failed=true;return end
                if seat.otherPole==seat.nextPole then seat.otherPole=nil end
            end
            seat.nextPole,seat.flight=nil,nil
            seat.boardedAt=now
            seat.lostAt=nil
            if combat and not combat:endHop(seat,now) then seat.failed=true;return end
            local label=flight.returning and '已回上一根桩' or (flight.first and '首次落桩' or '跨桩落脚')
            say(label..' actor='..seat.key..' 桩上支撑读回=true')
            return
        end
        if not flight.error and (not flight.arrived or now-flight.arrived<=1.25) then return end
        local reason=flight.error or '到达桩顶后未读到物理基底'
        say('跳桩待恢复 actor='..seat.key..' 读回='..reason)
        if not flight.first and not flight.returning then
            seat.blockedTop=flight.platform.top
            if beginFlight(seat,seat,now,true) then return end
        end
        seat.failed=true
    end

    local function hop(seat,now)
        local platform=seat.nextPole
        if now-platform.createdAt<SETTLE or not idle(seat.actor) or not idle(seat.carrier) then return end
        if combat:held(seat) and beginFlight(seat,platform,now,false) then return end
        if seat.flight then seat.failed=true;return end
        if not removePole(seat,platform.pole) then seat.failed=true;return end
        if seat.otherPole==platform then seat.otherPole=nil end
        seat.nextPole=nil
        if not combat:endHop(seat,now) then seat.failed=true end
        say('取消换桩 actor='..seat.key..' 起跳准备未读回，继续当前桩')
    end

    local function fight(seat,now)
        if not combat then return end
        if not seat.combat and not combat:arm(seat,now) then seat.failed=true;return end
        local ok,wantsHop=combat:tick(seat,now,idle(seat.actor) and idle(seat.carrier))
        if not ok then seat.failed=true;return end
        if not wantsHop then return end
        if seat.otherPole and validatePole(seat,seat.otherPole) then
            seat.nextPole=seat.otherPole
            return
        end
        if seat.otherPole and not removePole(seat,seat.otherPole.pole) then seat.failed=true;return end
        seat.otherPole=nil
        local anchor=sourceAnchor(seat.source)
        local top=anchor and chooseSpot(seat.actor,seat.carrier,seat.source,seat.body,anchor)
        if top and distance2(top,seat.top)<=1300^2 then seat.nextPole=spawnPole(seat,top,now) end
        if not seat.nextPole and not combat:endHop(seat,now) then seat.failed=true end
    end

    function self:stop(why)
        local complete=true
        for key,seat in pairs(self.seats)do
            if release(seat,why or '停止') then self.seats[key]=nil else complete=false end
        end
        for key,pickup in pairs(pickups)do
            if not same(options.world(),pickup.world) or combat:restoreWeapon(pickup.weapon) then pickups[key]=nil
            else complete=false end
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
        local pickup=pickups[U.key(actor)]
        if pickup and same(options.world(),pickup.world) then
            if combat:restoreWeapon(pickup.weapon) then pickups[pickup.key]=nil else complete=false end
        end
        return complete
    end
    function self:silence()
        for _,seat in pairs(self.seats)do stopFlight(seat) end
    end
    function self:holds(actor)
        for _,seat in pairs(self.seats)do
            if seat.moved and (same(actor,seat.carrier) or same(actor,seat.actor)) then return true end
        end
        return false
    end
    function self:keepsMovement(actor,classPath)
        if self:holds(actor) then return true end
        return classPath==BOSS and (tag(actor,ON_POLE) or 0)>0
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
            self:silence()
            pickups={}
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
            elseif seat.flight then finishFlight(seat,now)
            elseif seat.nextPole then hop(seat,now)
            elseif seat.boardedAt then
                if verifySeat(seat,now) then fight(seat,now) end
            else board(seat,now) end
        end
        for key,pickup in pairs(pickups)do
            local carrier=roster[key] and options.carrier(pickup.actor)
            if not self.seats[U.key(carrier)] and pickup.ended and now-pickup.ended>4
                and combat:restoreWeapon(pickup.weapon) then pickups[key]=nil end
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
                        retryAt[key]=now+0.5
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
