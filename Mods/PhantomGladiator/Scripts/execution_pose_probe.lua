-- Temporary, read-only evidence for the two bodies drifting apart during an execution.
-- Sample on the existing support tick and at stage boundaries; no extra timer, hook, movement or asset writes.
local U=require('ue_observe')
local Probe={}
local function call(object,method,...)
    if not U.valid(object) then return nil end
    local args,n={...},select('#',...)
    local ok,value=pcall(function()return object[method](object,table.unpack(args,1,n))end)
    return ok and U.unwrap(value) or nil
end
local function num(v)return type(v)=='number' and v==v and math.abs(v)<1e12 end
local function scalar(v)return num(v) and string.format('%.3f',v) or tostring(v)end
local function vector(v)
    local x,y,z=U.struct(v,'X'),U.struct(v,'Y'),U.struct(v,'Z')
    return num(x) and num(y) and num(z) and {X=x,Y=y,Z=z} or nil
end
local function xyz(v)return v and string.format('%.1f,%.1f,%.1f',v.X,v.Y,v.Z) or '?'end
local function delta(a,b)return a and b and {X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z} or nil end
local function short(object)
    if not U.valid(object) then return '?' end
    local value=call(object,'GetFName')
    local ok,s=pcall(function()return value:ToString()end)
    return ok and type(s)=='string' and s or '?'
end

function Probe.new(options)
    local log=options.log or function()end
    local name=options.fname or FName
    local now=options.now
    local find=options.staticFind or StaticFindObject
    local self,run,runs={},nil,0
    local function bone(mesh,boneName)
        local id=call(mesh,'GetBoneIndex',name(boneName))
        if not num(id) or id<0 then return nil,nil end
        return vector(call(mesh,'GetSocketLocation',name(boneName))),U.struct(call(mesh,'GetSocketRotation',name(boneName)),'Yaw')
    end
    local function mesh(mesh)
        if not U.valid(mesh) then return 'mesh=invalid' end
        local at=vector(call(mesh,'K2_GetComponentLocation'))
        local root,yaw=bone(mesh,'root')
        local pelvis=bone(mesh,'pelvis')
        local anim=call(mesh,'GetAnimInstance')
        local montage=call(anim,'GetCurrentActiveMontage')
        local time=U.valid(montage) and call(anim,'Montage_GetPosition',montage) or nil
        local data=U.field(mesh,'AnimationData')
        local clip=U.struct(data,'AnimToPlay')
        return string.format('mesh=%s scale=%s root=%s root-mesh=%s rootYaw=%s pelvis=%s mode=%s tickPose=%s montage=%s@%s clip=%s@%s rootMotion=%s clipRoot=%s forceLock=%s',
            xyz(at),xyz(vector(call(mesh,'K2_GetComponentScale'))),xyz(root),xyz(delta(root,at)),scalar(yaw),xyz(pelvis),
            tostring(U.field(mesh,'AnimationMode')),tostring(U.field(mesh,'bFollowerShouldTickPose')),short(montage),scalar(time),short(clip),scalar(call(mesh,'GetPosition')),
            tostring(U.field(anim,'RootMotionMode')),tostring(U.field(clip,'bEnableRootMotion')),tostring(U.field(clip,'bForceRootLock')))
    end
    local function warping(actor)
        local ok,cls=pcall(find,'/Script/MotionWarping.MotionWarpingComponent')
        local component=ok and U.valid(cls) and call(actor,'GetComponentByClass',cls) or nil
        if not U.valid(component) then return 'warp=unreadable' end
        local targets,mods={},{}
        for _,target in ipairs(U.array(U.field(component,'WarpTargets')) or {}) do
            local n=U.struct(target,'Name');local got,s=pcall(function()return n:ToString()end)
            if got and s=='Execution' then
                targets[#targets+1]=xyz(vector(U.struct(target,'Location')))..'/'..scalar(U.struct(U.struct(target,'Rotation'),'Yaw'))
                    ..'/follow='..tostring(U.struct(target,'bFollowComponent'))
            end
        end
        for _,modifier in ipairs(U.array(U.field(component,'Modifiers')) or {}) do
            if U.valid(modifier) and #mods<8 then
                mods[#mods+1]=short(modifier)..':'..tostring(U.field(modifier,'State'))..'@'..scalar(U.field(modifier,'CurrentPosition'))
            end
        end
        -- WarpTargets.Location is the stored value, not a claim that a followed component has been resolved.
        return 'warpStored='..table.concat(targets,';')..' modifiers='..table.concat(mods,';')
    end
    local function actor(actor)
        if not U.valid(actor) then return 'actor=invalid' end
        local capsule=U.field(actor,'CapsuleComponent')
        return string.format('actor=%s pos=%s yaw=%s velocity=%s capsule=%s/%s collision=%s {%s} {%s}',short(actor),
            xyz(vector(call(actor,'K2_GetActorLocation'))),scalar(U.struct(call(actor,'K2_GetActorRotation'),'Yaw')),
            xyz(vector(call(actor,'GetVelocity'))),scalar(call(capsule,'GetScaledCapsuleRadius')),
            scalar(call(capsule,'GetScaledCapsuleHalfHeight')),tostring(call(capsule,'GetCollisionEnabled')),
            mesh(U.field(actor,'Mesh')),warping(actor))
    end
    function self:sample(event)
        if not run or run.samples>=80 then return end
        run.samples=run.samples+1
        local ok,line=pcall(function()
            return string.format('[ExecutionPose] run=%d sample=%d t=%.3f event=%s executor[%s] target[%s] borrowed[%s]',
                runs,run.samples,now()-run.started,tostring(event),actor(run.executor),actor(run.target),mesh(run.body))
        end)
        if ok then log(line) else log('[ExecutionPose] 只读采样失败='..tostring(line)) end
    end
    function self:begin(executor,target,body)
        run=nil
        if runs>=3 then return end
        runs=runs+1;run={executor=executor,target=target,body=body,started=now(),samples=0}
        log('[ExecutionPose] 只读检查开始：每次最多80条、此次加载最多3次处决；不写位置、旋转、动画或碰撞')
        self:sample('begin')
    end
    function self:stop(reason)
        self:sample('stop:'..tostring(reason))
        run=nil
    end
    return self
end
return Probe
