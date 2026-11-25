package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Gaze=require('selfie_gaze')
local function point(x,y,z)return {X=x,Y=y,Z=z}end
local function fixture()
    local h={objects={},serial=0,logs={}}
    local function object(path,fields)
        h.serial=h.serial+1
        local o=fields or {}
        o.id,o.path,o.valid=h.serial,path,true
        function o:IsValid()return self.valid end
        function o:GetFullName()assert(self.valid);return 'Object '..self.path end
        function o:GetAddress()assert(self.valid);return self.id end
        h.objects[path]=o
        return o
    end
    h.object=object
    local world=object('/Test.World')
    function world:GetOuter()return nil end
    h.world=world
    local componentClass=object('/Script/Engine.SkeletalMeshComponent')
    h.lens=object('/Test.World:Camera',{position=point(100,0,80)})
    local function subject(label,player,prefix)
        local actor=object('/Test.World:'..label)
        local mesh=object(actor.path..'.Mesh',{PrimaryComponentTick={bTickEvenWhenPaused=false}})
        local anim=object(mesh.path..'.Anim',{
            AnimGraphNode_LookAt={BoneToModify={BoneName='head'},LookAt_Axis={Axis=point(1,0,0),bInLocalSpace=true},InterpolationTime=.5},
            bUseMultiThreadedAnimationUpdate=true,
        })
        local flag,location,weight,enabled='bEnableLookAt','NPCLookAtLocation','NPCLookAtAlpha','bEnableNPCLookat'
        if player then flag,location,weight,enabled='bInteractiveLookAt','LookAtLocation','LookAtAlpha','bLookAt' end
        actor[flag]=false
        actor.Mesh=mesh
        local original=point(4,5,6)
        anim[location],anim[weight],anim[enabled]=original,.15,false
        function actor:GetOuter()return world end
        function mesh:GetOwner()return actor end
        function mesh:GetPostProcessInstance()if player then return anim end end
        function mesh:GetAnimInstance()if not player then return anim end end
        function mesh:DoesSocketExist(bone)return bone=='head' end
        function mesh:SetTickableWhenPaused(value)if not self.rejectTick then self.PrimaryComponentTick.bTickEvenWhenPaused=value end end
        function mesh:GetSocketTransform(bone,space)
            assert(bone=='head' and space==0)
            return {Translation=point(0,0,80),Rotation={X=0,Y=0,Z=0,W=1}}
        end
        local getter=player and 'GetLookAtLocation' or 'GetNPCLookAtLocation'
        local getterAlpha=player and 'GetLookAtAlpha' or 'GetNPCLookAtAlpha'
        anim[getter]=function(_,target)assert(target==h.lens and target.valid);return target.position end
        anim[getterAlpha]=function(_,p)assert(p.X==h.lens.position.X);return .9 end
        local face=object(actor.path..'.Face',{weights={}})
        local asset=object(actor.path..'.Head',{MorphTargets={}})
        for _,dir in ipairs({'Left','Right','Up','Down'})do
            for _,side in ipairs({'L','R'})do
                local name=prefix..'eye_look'..dir..'_'..side
                local m=object(asset.path..':'..name)
                function m:GetFName()return name end
                asset.MorphTargets[#asset.MorphTargets+1]=m
                face.weights[name]=dir=='Left' and .2 or 0
            end
        end
        mesh.asset=object(mesh.path..'.Body',{MorphTargets={}})
        function mesh:GetSkeletalMeshAsset()return self.asset end
        function face:GetOwner()return actor end
        function face:GetSkeletalMeshAsset()return self.asset end
        function face:GetMorphTarget(n)return assert(self.weights[n]) end
        function face:SetMorphTarget(n,v,drop)assert(self.weights[n] and drop);self.weights[n]=v end
        face.asset=asset
        function actor:K2_GetComponentsByClass(c)assert(c==componentClass);return {mesh,face} end
        return {actor=actor,mesh=mesh,anim=anim,face=face,prefix=prefix,flag=flag,location=location,weight=weight,original=original}
    end
    h.player=subject('Hero',true,'')
    h.companion=subject('Follower',false,'head_lod0_mesh__')
    local shared={}
    function shared:SetSharedVariable(k,v)assert(type(v)=='string');self[k]=v end
    function shared:GetSharedVariable(k)return self[k] end
    -- UE4SS exposes FName as a callable Lua table.
    local fname=setmetatable({}, {__call=function(_,s)return s end})
    function h:new()
        return Gaze.new({shared=shared,world=function()return h.world end,find=function(p)return h.objects[p] end,
            fname=fname,log=function(s)h.logs[#h.logs+1]=s end})
    end
    h.gaze=h:new()
    function h:arm()self.gaze:start(h.player.actor,h.companion.actor,h.lens)end
    local function assertRestored(s)
        assert(not s.actor[s.flag] and not s.actor.LookAtTarget)
        assert(not s.mesh.PrimaryComponentTick.bTickEvenWhenPaused and s.anim.bUseMultiThreadedAnimationUpdate)
        assert(s.anim.AnimGraphNode_LookAt.InterpolationTime==.5)
        assert(s.anim[s.location].X==s.original.X and s.anim[s.weight]==.15)
        assert(s.face.weights[s.prefix..'eye_lookLeft_L']==.2 and s.face.weights[s.prefix..'eye_lookRight_R']==0)
    end
    function h:restored()assertRestored(self.player);assertRestored(self.companion)end
    return h
end

do
    local h=fixture();h:arm()
    for _,s in ipairs({h.player,h.companion})do
        assert(s.actor[s.flag] and s.actor.LookAtTarget==h.lens)
        assert(s.mesh.PrimaryComponentTick.bTickEvenWhenPaused and s.anim.AnimGraphNode_LookAt.InterpolationTime==0)
        assert(s.anim.bUseMultiThreadedAnimationUpdate==false)
    end
    h.lens.position=point(100,35,91)
    h.gaze:update(h.lens.position,1)
    for _,s in ipairs({h.player,h.companion})do
        assert(s.anim[s.location].Y==35 and s.anim[s.weight]==.9)
        assert(s.face.weights[s.prefix..'eye_lookRight_L']>.3 and s.face.weights[s.prefix..'eye_lookUp_R']>0)
        assert(s.face.weights[s.prefix..'eye_lookLeft_R']==0)
    end
    h.lens.position=point(100,-20,68)
    h.gaze:update(h.lens.position,1.01)
    assert(h.player.anim.LookAtLocation.Y==35,'bounded sampling when camera moves')
    h.gaze:update(h.lens.position,1.1)
    assert(h.player.anim.LookAtLocation.Y==-20 and h.companion.anim.NPCLookAtLocation.Z==68)
    assert(h.player.face.weights.eye_lookRight_R==0 and h.player.face.weights.eye_lookDown_L>0)
    assert(h.gaze:stop() and not h.gaze:pending());h:restored()
end
do
    local h=fixture();h.companion.mesh.rejectTick=true;h:arm()
    assert(h.player.actor.bInteractiveLookAt and not h.companion.actor.bEnableLookAt)
    assert(h.companion.actor.LookAtTarget==nil and h.companion.anim.AnimGraphNode_LookAt.InterpolationTime==.5)
    assert(h.gaze:stop());h:restored()
end
do
    local h=fixture();h:arm();h.lens.position=point(100,35,91);h.gaze:update(h.lens.position,1)
    h.lens.valid=false
    local reloaded=h:new()
    assert(reloaded:pending() and reloaded:stop(),'restores exact objects even if the camera was removed first')
    h:restored()
end
do
    local h=fixture()
    h.player.actor.bInteractiveLookAt=true
    h.player.actor.LookAtTarget=h.companion.actor
    h:arm()
    assert(h.player.actor.LookAtTarget==h.companion.actor and not h.player.mesh.PrimaryComponentTick.bTickEvenWhenPaused)
    assert(h.gaze:stop())
    assert(h.player.actor.bInteractiveLookAt and h.player.actor.LookAtTarget==h.companion.actor)
end
do
    local h=fixture();h:arm()
    h.lens.position=point(100,35,91);h.gaze:update(h.lens.position,1)
    h.player.face.weights.eye_lookRight_L=.44
    assert(h.gaze:stop())
    assert(h.player.face.weights.eye_lookRight_L==.44,'do not undo a new value owned by another feature')
end
do
    local h=fixture()
    local bound=h.gaze:start(h.player.actor,h.companion.actor,h.lens,{true,false})
    assert(bound[1] and not bound[2] and h.player.actor.LookAtTarget==h.lens and h.companion.actor.LookAtTarget==nil)
    assert(h.gaze:stop());h:restored()
end
do
    local h=fixture()
    local original=h.companion.actor
    h.player.actor.LookAtTarget=original
    local bound=h.gaze:start(h.player.actor,nil,h.lens,{true,false})
    assert(bound[1] and h.player.actor.LookAtTarget==h.lens,'an inactive native target should not block deliberate photography gaze')
    h.lens.valid=false
    assert(h:new():stop() and h.player.actor.LookAtTarget==original and not h.player.actor.bInteractiveLookAt)
end
do
    local h=fixture()
    local actor=h.player.actor
    local primary=h.object(actor.path..'.Primary')
    function primary:GetOwner()return actor end
    function primary:GetPostProcessInstance()return nil end
    actor.Mesh=primary
    function h.player.anim:GetOwningComponent()return h.player.mesh end
    local bound=h.gaze:start(actor,nil,h.lens,{true,false})
    assert(bound[1] and h.player.mesh.PrimaryComponentTick.bTickEvenWhenPaused,
        'only a correctly owned working post-process rig can substitute for the primary mesh')
    assert(h.gaze:stop())
    h:restored()
end
do
    local h=fixture()
    local actor=h.player.actor
    local bound=h.gaze:start(actor,nil,h.lens,{false,false},{3,1})
    assert(not bound[1] and actor.LookAtTarget==nil and not actor.bInteractiveLookAt)
    h.gaze:update(h.lens.position,1)
    assert(h.player.face.weights.eye_lookLeft_L==.64 and h.player.face.weights.eye_lookRight_R==0)
    assert(h:new():stop())
    h:restored()
end
print('selfie_gaze: PASS native rig selection, independent eye controls and original-target recovery')
