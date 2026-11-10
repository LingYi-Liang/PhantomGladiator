-- Scoped NPC control for a verified pole seat. The original projectile owns damage and hit reactions.
local U=require('ue_observe')
local Combat={}
local AI='/Script/SGameAI.Default__SGameAIFunctionLibrary'
local MESH='/Script/Engine.SkeletalMeshComponent'
local HEAD='/HuaShira/Characters/Monster/DaTouWaWa/HouHouHou/HouHouHou_Head.HouHouHou_Head'
local FIRE='/PBZCombatAsset/ActorData/Players/Hun/Abilities/LionHeadHouHouHou/BulletData_Hun_LionDanceHead_FireBall.BulletData_Hun_LionDanceHead_FireBall'
local BULLET_PACKAGE='/PBZCombatAsset/ActorData/Mobs/LionDancer/BP_Bullet_LionDancer_FlameBall_Small'
local BULLET=BULLET_PACKAGE..'.BP_Bullet_LionDancer_FlameBall_Small_C'
local POSE_DIR='/HuaShira/Characters/EliteBoss/LionDancer_P2/Hun_Anim/B/'
local SHOOT=POSE_DIR..'Hun_LionHead_B_Attack_R.Hun_LionHead_B_Attack_R'
local HOP=POSE_DIR..'Hun_LionHead_B_Battle_Walk_Fwd_R.Hun_LionHead_B_Battle_Walk_Fwd_R'
local LAUNCH_FRAME,SHOT_END=0.990279,2.766667
local PAUSE_REASON='PhantomGladiator lion pole'

local function call(object,method,...)
    if not U.valid(object) then return false end
    local ok,value=pcall(function(target,key,...)return target[key](target,...)end,object,method,...)
    return ok,U.unwrap(value)
end
local function same(a,b)
    local key=U.key(a)
    return key~=nil and key==U.key(b)
end
local function transform(at,pitch,yaw)
    local cp,sp,cy,sy=math.cos(pitch/2),math.sin(pitch/2),math.cos(yaw/2),math.sin(yaw/2)
    return {Translation=at,Rotation={X=sp*sy,Y=-sp*cy,Z=cp*sy,W=cp*cy},Scale3D={X=1,Y=1,Z=1}}
end

function Combat.new(options)
    local self={}
    local find=options.find or StaticFindObject
    local load=options.load or LoadAsset
    local name=options.fname or FName
    local function say(text)options.log('[LionPoleCombat] '..text)end
    local function live(actor,world)
        return U.inWorld(actor,world) and not options.isDestroying(actor)
    end
    local function object(path)
        local ok,value=pcall(find,path)
        if not ok or not U.valid(value) then ok,value=pcall(load,path) end
        if not ok or not U.valid(value) then ok,value=pcall(find,path) end
        return ok and U.valid(value) and value or nil
    end
    local function brainOf(actor)
        return U.field(U.field(actor,'Controller'),'BrainComponent')
    end
    local function paused(brain)
        local ok,value=call(brain,'IsPaused')
        if ok and type(value)=='boolean' then return value end
    end
    local function matches(bullet,seat,control)
        return live(bullet,seat.world) and same(U.field(bullet,'BulletOwnerAvatar'),seat.actor)
            and same(U.field(bullet,'BulletData'),control.data)
    end
    local function stopPose(control)
        if not control.pose then return true end
        if not control.pose:stop() then return false end
        control.pose=nil
        return true
    end
    function self:release(seat)
        local control=seat.combat
        if not control then return true end
        local restored=stopPose(control)
        if matches(control.bullet,seat,control) then
            local state=U.field(control.bullet,'BulletStatus')
            if state==1 or state==2 then call(control.bullet,'Deactivate',0.0) end
            if matches(control.bullet,seat,control) and U.field(control.bullet,'BulletStatus')~=3 then restored=false end
        end
        if U.valid(control.head) then
            local _,destroying=call(control.head,'IsBeingDestroyed')
            if destroying~=true then call(control.head,'K2_DestroyComponent',control.head) end
            local _,after=call(control.head,'IsBeingDestroyed')
            restored=(not U.valid(control.head) or after==true) and restored
        end
        for _,record in ipairs(control.brains)do
            if record.changed and live(record.actor,seat.world) and same(brainOf(record.actor),record.brain) then
                if paused(record.brain)==true then call(control.ai,'ResumeLogic',record.brain,PAUSE_REASON) end
                if paused(record.brain)~=false then restored=false else record.changed=false end
            end
        end
        if restored then seat.combat=nil end
        say('退出狮头模式 actor='..seat.key..' 动画、狮头及AI恢复读回='..tostring(restored))
        return restored
    end
    local function createHead(seat,control,headAsset,meshClass)
        local mesh=U.field(seat.actor,'Mesh')
        local root=U.field(seat.actor,'RootComponent')
        if not U.valid(root) then return false end
        local _,hand=call(mesh,'DoesSocketExist',name('weapon_r_Socket'))
        local _,headBone=call(mesh,'DoesSocketExist',name('head'))
        local parent,socket=root,'None'
        if hand==true then parent,socket=mesh,'weapon_r_Socket'
        elseif headBone==true then parent,socket=mesh,'head' end
        local ok,head=call(seat.actor,'AddComponentByClass',meshClass,true,transform({X=0,Y=0,Z=0},0,0),false)
        if not ok or not U.valid(head) then return false end
        control.head=head
        if not U.valid(parent) or not U.valid(headAsset) then return false end
        call(head,'SetCollisionEnabled',0)
        call(head,'SetSkeletalMeshAsset',headAsset)
        local attached,result=call(head,'K2_AttachToComponent',parent,name(socket),2,2,2,false)
        if socket=='None' then call(head,'K2_SetRelativeLocation',{X=0,Y=0,Z=seat.body.half*0.75},false,{},false) end
        local _,asset=call(head,'GetSkeletalMeshAsset')
        return attached and result==true and same(asset,headAsset) and same(U.field(head,'AttachParent'),parent)
    end
    function self:arm(seat,now)
        local data,headAsset,meshClass,ai=object(FIRE),object(HEAD),object(MESH),object(AI)
        local _,class=call(data,'GetBulletClass')
        local _,full=call(class,'GetFullName')
        if full~='BlueprintGeneratedClass '..BULLET or not U.valid(headAsset) or not U.valid(meshClass) or not U.valid(ai) then
            say('原版火焰弹或狮头资源未读回 actor='..seat.key)
            return false
        end
        local actors={seat.actor}
        if not same(seat.actor,seat.carrier) then actors[#actors+1]=seat.carrier end
        local control={brains={},data=data,class=class,ai=ai,nextAt=now,shots=0}
        for _,actor in ipairs(actors)do
            local brain=brainOf(actor)
            if not live(actor,seat.world) or paused(brain)~=false then return false end
            control.brains[#control.brains+1]={brain=brain,actor=actor}
        end
        seat.combat=control
        if not createHead(seat,control,headAsset,meshClass) then return false end
        for _,record in ipairs(control.brains)do
            if not U.valid(record.brain) or not U.valid(ai) then return false end
            record.changed=true
            local ok=call(ai,'PauseLogic',record.brain,PAUSE_REASON)
            local read=paused(record.brain)
            say('上桩改用狮头 actor='..seat.key..' 暂停原招调用='..tostring(ok)..' 读回='..tostring(read))
            if not ok or read~=true then return false end
        end
        return true
    end
    function self:held(seat)
        local control=seat.combat
        if not control or not U.valid(control.head) then return false end
        for _,record in ipairs(control.brains)do
            if not live(record.actor,seat.world) or not same(brainOf(record.actor),record.brain) or paused(record.brain)~=true then
                return false
            end
        end
        return true
    end
    local function aim(seat)
        local target=seat.source.actor
        local from=options.location(seat.actor)
        local there=options.location(target)
        if not from or not there then return nil end
        local dx,dy=there.X-from.X,there.Y-from.Y
        local distance=math.sqrt(dx*dx+dy*dy)
        if distance<seat.body.radius+65 or distance>4200 then return nil end
        local yaw=math.atan(dy,dx)
        local muzzle={X=from.X+math.cos(yaw)*(seat.body.radius+45),Y=from.Y+math.sin(yaw)*(seat.body.radius+45),Z=from.Z+math.min(120,seat.body.half*0.45)}
        local pitch=math.atan(there.Z-muzzle.Z,distance-seat.body.radius-45)
        return transform(muzzle,pitch,yaw),yaw
    end
    local function launch(seat,control)
        local target=seat.source.actor
        if not live(target,seat.world) or not U.valid(control.data) or not U.valid(control.class) then return false end
        if matches(control.bullet,seat,control) and U.field(control.bullet,'BulletStatus')==2 then return true end
        local shot=aim(seat)
        local component=U.field(target,'CapsuleComponent')
        if not shot or not U.valid(component) then return false end
        local ok,bullet=call(control.data,'CreateBullet',shot,seat.actor)
        if not ok or not live(bullet,seat.world) then
            say('火焰弹创建未读回 actor='..seat.key)
            return false
        end
        local _,class=call(bullet,'GetClass')
        if not same(class,control.class) then return false end
        local initialized=U.valid(seat.actor) and U.valid(control.data) and call(bullet,'Initialize',nil,seat.actor,nil,control.data,false)
        local owner=matches(bullet,seat,control)
        if not initialized or not owner or U.field(bullet,'BulletStatus')~=1 then
            local state=U.field(bullet,'BulletStatus')
            if state==0 then call(bullet,'K2_DestroyActor')
            elseif owner and (state==1 or state==2) then call(bullet,'Deactivate',0.0) end
            say('火焰弹初始化 actor='..seat.key..' 所有者/资源读回='..tostring(owner))
            return false
        end
        control.bullet=bullet
        call(bullet,'K2_DetachFromActor',1,1,1)
        local aimed=U.valid(component) and call(bullet,'InitializePreSelectedTarget',{Component=component,SocketName=name('None')})
        local assigned=same(U.struct(U.field(bullet,'CurrentTarget'),'Component'),component)
        local placed=call(bullet,'SetBulletTransform',shot)
        local started=aimed and assigned and placed and call(bullet,'Start')
        local state=U.field(bullet,'BulletStatus')
        local targetRead=U.valid(component) and same(U.struct(U.field(bullet,'CurrentTarget'),'Component'),component)
        say('原版火焰弹 actor='..seat.key..' 归属读回='..tostring(owner)..' 目标读回='..tostring(targetRead)..' 启动状态='..tostring(state))
        if not started or state~=2 or not targetRead then call(bullet,'Deactivate',0.0);return false end
        control.shots=control.shots+1
        return true
    end
    local function pose(seat,clip)
        if not options.pose or not same(seat.actor,seat.carrier) then return nil end
        return options.pose(seat.actor,clip)
    end
    function self:beginHop(seat)
        local control=seat.combat
        if not control or not stopPose(control) then return false end
        control.pose=pose(seat,HOP)
        return true
    end
    function self:endHop(seat,now)
        local control=seat.combat
        if not control or not stopPose(control) then return false end
        control.nextAt=now+0.25
        return true
    end
    function self:tick(seat,now,canAct)
        local control=seat.combat
        if not control then return false end
        if not self:held(seat) then return false end
        if control.started and not control.fired then
            local hp=options.hp(seat.actor)
            if not canAct or type(hp)~='number' or hp<control.hp then
                control.started=nil
                control.nextAt=now+0.5
                return stopPose(control)
            end
            local at=now-control.started
            if control.pose then at=control.pose:position() end
            if type(at)~='number' then return false end
            if at>=LAUNCH_FRAME then
                if not launch(seat,control) then return false end
                control.fired=true
            end
            return true
        end
        if control.started and now-control.started>=SHOT_END then
            control.started=nil;control.fired=false
            if not stopPose(control) then return false end
            if control.shots>(control.hoppedAfter or 0) then
                control.hoppedAfter=control.shots
                return true,true
            end
        end
        if not control.started and now>=control.nextAt and canAct then
            local _,yaw=aim(seat)
            local hp=options.hp(seat.actor)
            if yaw and type(hp)=='number' and hp>0 then
                call(seat.carrier,'K2_SetActorRotation',{Pitch=0,Yaw=math.deg(yaw),Roll=0},false)
                control.pose=pose(seat,SHOOT)
                control.started=now;control.hp=hp;control.fired=false
            end
        end
        return true
    end
    return self
end

return Combat
