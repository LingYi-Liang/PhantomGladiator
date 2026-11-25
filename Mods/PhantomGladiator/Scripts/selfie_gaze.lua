-- Only the two photographed actors can acquire gaze overrides. Undo is tied to the
-- exact world and instance identities and contains no UObject references across reloads.
local U=require('ue_observe')
local Face=require('photo_face')
local Gaze={}
local JOURNAL='PhantomGladiator.selfie.gaze.v1'
local PATHS={
    player={enable='bInteractiveLookAt',position='LookAtLocation',alpha='LookAtAlpha',blend='bLookAt',
        getter='GetLookAtLocation',weight='GetLookAtAlpha'},
    npc={enable='bEnableLookAt',position='NPCLookAtLocation',alpha='NPCLookAtAlpha',blend='bEnableNPCLookat',
        getter='GetNPCLookAtLocation',weight='GetNPCLookAtAlpha'},
}
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<1e8 end
local function clamp(v,lo,hi)return math.min(hi,math.max(lo,v))end
local function call(obj,method,...)
    if not U.valid(obj) then return end
    local ok,v=pcall(function(...)return obj[method](obj,...)end,...)
    if ok then return U.unwrap(v) end
end
local function key(o)return U.key(o)end
local function name(o)
    local n=call(o,'GetFullName')
    return type(n)=='string' and not n:find('%c') and n:match('^%S+ (/.+)$') or nil
end
local function enumName(v)
    if type(v)=='string' then return v end
    if v==nil then return end
    local ok,t=pcall(function()return v:ToString()end)
    if ok and type(t)=='string' then return t end
end
local function vector(v)
    local x,y,z=U.struct(v,'X'),U.struct(v,'Y'),U.struct(v,'Z')
    if finite(x) and finite(y) and finite(z) then return {X=x,Y=y,Z=z} end
end
local function nearly(a,b)
    return a and b and math.abs(a.X-b.X)+math.abs(a.Y-b.Y)+math.abs(a.Z-b.Z)<.05
end
local function put(obj,field,value)
    if not U.valid(obj) then return false end
    return pcall(function()obj[field]=value end)
end
local function setInterpolation(anim,value)
    if not U.valid(anim) then return false end
    local node=U.field(anim,'AnimGraphNode_LookAt')
    if not finite(U.struct(node,'InterpolationTime')) then return false end
    local ok=pcall(function()node.InterpolationTime=value end)
    return ok and U.struct(U.field(anim,'AnimGraphNode_LookAt'),'InterpolationTime')==value
end
local function ticksWhenPaused(mesh)
    return U.struct(U.field(mesh,'PrimaryComponentTick'),'bTickEvenWhenPaused')
end
local function setTick(mesh,value)
    call(mesh,'SetTickableWhenPaused',value)
    return ticksWhenPaused(mesh)==value
end

local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function cross(a,b)return {X=a.Y*b.Z-a.Z*b.Y,Y=a.Z*b.X-a.X*b.Z,Z=a.X*b.Y-a.Y*b.X}end
local function unit(v)
    local n=math.sqrt(dot(v,v))
    if n<.001 then return end
    return {X=v.X/n,Y=v.Y/n,Z=v.Z/n}
end
local function forward(transform,axis)
    local q=U.struct(transform,'Rotation')
    local xyz=vector(q);local w=U.struct(q,'W')
    if not xyz or not finite(w) or math.abs(dot(xyz,xyz)+w*w-1)>.02 then return end
    local a=cross(xyz,axis);local b=cross(xyz,a)
    return unit({X=axis.X+2*(w*a.X+b.X),Y=axis.Y+2*(w*a.Y+b.Y),Z=axis.Z+2*(w*a.Z+b.Z)})
end
local function eyeWeights(head,origin,target)
    local right=unit(cross({X=0,Y=0,Z=1},head))
    local to=unit({X=target.X-origin.X,Y=target.Y-origin.Y,Z=target.Z-origin.Z})
    if not right or not to then return end
    local f=dot(head,to)
    if f<=0 then return {Left=0,Right=0,Down=0,Up=0} end
    local v=cross(head,right)
    local yaw=math.deg(math.atan(dot(right,to),f))
    local pitch=math.deg(math.atan(dot(v,to),f))
    return {Left=clamp(-yaw/22,0,.75),Right=clamp(yaw/22,0,.75),Down=clamp(-pitch/16,0,.75),Up=clamp(pitch/16,0,.75)}
end
Gaze.eyeWeights=eyeWeights

local EYE_NAMES={}
for _,dir in ipairs({'Left','Right','Up','Down'})do
    for _,side in ipairs({'L','R'})do EYE_NAMES[#EYE_NAMES+1]={direction=dir,side=side,tail='eye_look'..dir..'_'..side} end
end

function Gaze.new(o)
    local self={}
    local find=o.find or StaticFindObject
    local fname=o.fname or FName
    local share=o.shared or ModRef
    local rows,failures={},{}
    local active,sampleAt,lastLens,settleUntil=false,0,nil,0
    local say=o.log or function()end
    local function save()
        if not share then return true end
        local lines={}
        for _,r in ipairs(rows)do
            local base={r.world,r.mode,r.actorPath,r.actorKey,r.cameraKey,r.meshPath,r.meshKey,r.animPath,r.animKey,
                r.tick and 1 or 0,r.thread and 1 or 0,r.interpolation,r.beforeAt.X,r.beforeAt.Y,r.beforeAt.Z,r.beforeAlpha,r.beforeBlend and 1 or 0,
                r.facePath or '-',r.faceKey or '-',r.faceAssetKey or '-',r.prefix or '-',r.originalTargetPath or '-',r.originalTargetKey or '-',r.eyesOnly and 1 or 0}
            for _,v in ipairs(r.morphs or {})do base[#base+1]=v.before end
            lines[#lines+1]=table.concat(base,'\t')
        end
        local serialized=table.concat(lines,'\n')
        local ok,read=pcall(function()share:SetSharedVariable(JOURNAL,serialized);return share:GetSharedVariable(JOURNAL)end)
        return ok and read==serialized
    end
    if share then
        local ok,text=pcall(function()return share:GetSharedVariable(JOURNAL)end)
        if ok and type(text)=='string' and #text<=12000 then
            for line in text:gmatch('[^\n]+')do
                local t={}
                for v in (line..'\t'):gmatch('(.-)\t')do t[#t+1]=v end
                local extra=(#t==24 or #t==32) and 3 or (#t==23 or #t==31) and 2 or 0
                if (#t==21+extra or #t==29+extra) and #rows<2 and PATHS[t[2]] and t[3]:sub(1,1)=='/' and t[6]:sub(1,1)=='/' and t[8]:sub(1,1)=='/' then
                    local okNumbers=true
                    for i=10,17 do if not finite(tonumber(t[i])) then okNumbers=false end end
                    local morphs
                    if #t==29+extra then
                        morphs={}
                        for i,n in ipairs(EYE_NAMES)do
                            local before=tonumber(t[21+extra+i])
                            if not finite(before) then okNumbers=false;break end
                            local prefix=t[21]=='-' and '' or t[21]
                            morphs[i]={text=prefix..n.tail,before=before,direction=n.direction}
                        end
                    end
                    if okNumbers then
                        rows[#rows+1]={world=t[1],mode=t[2],actorPath=t[3],actorKey=t[4],cameraKey=t[5],meshPath=t[6],meshKey=t[7],
                            animPath=t[8],animKey=t[9],tick=t[10]=='1',thread=t[11]=='1',interpolation=tonumber(t[12]),
                            beforeAt={X=tonumber(t[13]),Y=tonumber(t[14]),Z=tonumber(t[15])},beforeAlpha=tonumber(t[16]),beforeBlend=t[17]=='1',
                            facePath=t[18],faceKey=t[19],faceAssetKey=t[20],prefix=t[21]=='-' and '' or t[21],morphs=morphs,
                            originalTargetPath=extra>=2 and t[22] or nil,originalTargetKey=extra>=2 and t[23] or nil,
                            eyesOnly=extra==3 and t[24]=='1'}
                    end
                end
            end
        end
    end
    local function resolve(obj,path,id)
        if key(obj)==id and name(obj)==path then return obj end
        if type(find)~='function' or not path or not id or path=='-' then return end
        local ok,found=pcall(find,path)
        if ok and key(found)==id and name(found)==path then return found end
    end
    local function setMorph(face,n,v)
        call(face,'SetMorphTarget',n,v,true)
        local now=call(face,'GetMorphTarget',n)
        return finite(now) and math.abs(now-v)<.005
    end
    local function restore(r,world)
        if r.world~=key(world) then return true end
        local a=resolve(r.actor,r.actorPath,r.actorKey)
        if not a or not U.inWorld(a,world) then return true end
        local d=PATHS[r.mode]
        local target,read=U.field(a,'LookAtTarget')
        local owned=not r.eyesOnly and read and (not U.valid(target) or key(target)==r.cameraKey)
        local done=r.eyesOnly or read
        if owned then
            if U.field(a,d.enable)==true then done=put(a,d.enable,false) and U.field(a,d.enable)==false and done end
            local original=resolve(r.originalTarget,r.originalTargetPath,r.originalTargetKey)
            if original and not U.inWorld(original,world) then original=nil end
            if target~=nil or original then
                done=put(a,'LookAtTarget',original) and key(U.field(a,'LookAtTarget'))==key(original) and done
            end
        end
        local mesh=resolve(r.mesh,r.meshPath,r.meshKey)
        local anim=resolve(r.anim,r.animPath,r.animKey)
        if mesh and key(call(mesh,'GetOwner'))~=r.actorKey then mesh,anim=nil,nil end
        if mesh and not r.eyesOnly then
            if not r.tick and ticksWhenPaused(mesh)==true then done=setTick(mesh,false) and done end
        end
        if anim and not r.eyesOnly then
            local at=vector(U.field(anim,d.position))
            if owned and (not r.lastAt or nearly(at,r.lastAt)) then
                done=put(anim,d.position,r.beforeAt) and put(anim,d.alpha,r.beforeAlpha)
                    and put(anim,d.blend,r.beforeBlend) and done
            end
            if U.struct(U.field(anim,'AnimGraphNode_LookAt'),'InterpolationTime')==0 and r.interpolation~=0 then
                done=setInterpolation(anim,r.interpolation) and done
            end
            if r.thread and U.field(anim,'bUseMultiThreadedAnimationUpdate')==false then
                done=put(anim,'bUseMultiThreadedAnimationUpdate',true) and U.field(anim,'bUseMultiThreadedAnimationUpdate')==true and done
            end
        end
        local face=resolve(r.face,r.facePath,r.faceKey)
        if face and key(call(face,'GetOwner'))==r.actorKey and key(call(face,'GetSkeletalMeshAsset'))==r.faceAssetKey then
            for _,v in ipairs(r.morphs or {})do
                local n=v.name or fname(v.text)
                local current=call(face,'GetMorphTarget',n)
                if finite(current) and (v.last==nil or math.abs(current-v.last)<.005)
                    and math.abs(current-v.before)>.005 then
                    done=setMorph(face,n,v.before) and done
                end
            end
        end
        say('[SelfieGaze] 恢复 '..r.actorPath..' 读回='..tostring(done))
        return done
    end
    function self:stop()
        active=false
        if #rows==0 then return true end
        local w=o.world()
        if not key(w) then return false end
        local unresolved={}
        for _,r in ipairs(rows)do
            if not restore(r,w) then unresolved[#unresolved+1]=r end
        end
        rows=unresolved
        return save() and #rows==0
    end
    function self:pending()return #rows>0 end

    local function faceOf(actor)
        return Face.find(actor,find,function(c,asset,available)
            for _,prefix in ipairs({'','head_lod0_mesh__'})do
                local morphs={}
                for _,item in ipairs(EYE_NAMES)do
                    local label=prefix..item.tail
                    if not available[label] then break end
                    local n=fname(label);local weight=call(c,'GetMorphTarget',n)
                    if not finite(weight) then break end
                    morphs[#morphs+1]={text=label,name=n,direction=item.direction,side=item.side,before=weight,last=weight}
                end
                if #morphs==#EYE_NAMES then
                    local eyes={}
                    for _,side in ipairs({'L','R'})do
                        for _,bone in ipairs({'FACIAL_'..side..'_Eye','eye_'..side:lower()})do
                            local id=fname(bone)
                            if call(c,'DoesSocketExist',id)==true then eyes[side]=id;break end
                        end
                    end
                    return c,asset,prefix,morphs,eyes
                end
            end
        end)
    end
    local function driver(actor,mesh,mode,additional)
        if not U.valid(mesh) or key(call(mesh,'GetOwner'))~=key(actor) then return nil,'角色网格未读回' end
        local anim=call(mesh,mode=='player' and 'GetPostProcessInstance' or 'GetAnimInstance')
        local meshPath,animPath=name(mesh),name(anim)
        if not meshPath or not animPath then return nil,'动画实例未就绪' end
        if additional and key(call(anim,'GetOwningComponent'))~=key(mesh) then return nil,'后处理网格归属未确认' end
        local node=U.field(anim,'AnimGraphNode_LookAt')
        local bone=enumName(U.struct(U.struct(node,'BoneToModify'),'BoneName'))
        local orient=U.struct(node,'LookAt_Axis')
        local dir=vector(U.struct(orient,'Axis'))
        if not bone or bone:lower()~='head' or not dir or U.struct(orient,'bInLocalSpace')~=true
            or call(mesh,'DoesSocketExist',fname(bone))~=true then
            return nil,'转头节点未匹配 '..tostring(U.className(anim) or '?')..' head='..tostring(bone)
        end
        local d=PATHS[mode]
        local pause,thread=ticksWhenPaused(mesh),U.field(anim,'bUseMultiThreadedAnimationUpdate')
        local interpolation=U.struct(node,'InterpolationTime')
        local at,alpha,blend=vector(U.field(anim,d.position)),U.field(anim,d.alpha),U.field(anim,d.blend)
        if type(pause)~='boolean' or type(thread)~='boolean' or not finite(interpolation)
            or not at or not finite(alpha) or type(blend)~='boolean' then
            return nil,'转头参数未读回 '..tostring(U.className(anim) or '?')
        end
        return {mesh=mesh,meshKey=key(mesh),meshPath=meshPath,anim=anim,animKey=key(anim),animPath=animPath,
            tick=pause,thread=thread,interpolation=interpolation,beforeAt=at,beforeAlpha=alpha,beforeBlend=blend,bone=fname(bone),axis=dir}
    end
    local function bind(actor,camera,asPlayer,eyesOnly,eyeMode)
        local mode=asPlayer and 'player' or 'npc'
        local d=PATHS[mode]
        local world=o.world()
        local actorPath=name(actor)
        local target,read=U.field(actor,'LookAtTarget')
        local enabled=U.field(actor,d.enable)
        if not actorPath or not eyesOnly and (not read or type(enabled)~='boolean') then return false,'角色注视输入未读回' end
        if not eyesOnly and enabled then return false,'原版注视正在进行' end
        local previousPath,previousKey
        if not eyesOnly and U.valid(target) then
            previousPath,previousKey=name(target),key(target)
            if not previousPath or not previousKey or not U.inWorld(target,world) then return false,'原版注视目标无法安全记录' end
        end
        local mesh=U.field(actor,'Mesh')
        local r,why=driver(actor,mesh,mode,false)
        if not r and asPlayer and type(find)=='function' then
            local cls=find('/Script/Engine.SkeletalMeshComponent')
            if U.valid(cls) then
                for _,other in ipairs(U.array(call(actor,'K2_GetComponentsByClass',cls)) or {})do
                    if key(other)~=key(mesh) then
                        r=driver(actor,other,mode,true)
                        if r then break end
                    end
                end
            end
        end
        if not r then return false,why end
        local face,asset,prefix,morphs,eyes=faceOf(actor)
        if eyesOnly and not morphs then return false,'该脸部模型没有可用眼神' end
        r.eyesOnly,r.eyeMode=eyesOnly,eyeMode
        r.mode,r.world,r.actor,r.actorKey,r.actorPath=mode,key(world),actor,key(actor),actorPath
        r.camera,r.cameraKey=camera,key(camera)
        r.face,r.facePath,r.faceKey,r.faceAssetKey=face,name(face),key(face),key(asset)
        r.prefix,r.morphs,r.eyes=prefix,morphs,eyes
        r.originalTarget,r.originalTargetPath,r.originalTargetKey=target,previousPath,previousKey
        if not r.world or not r.cameraKey or (face and not r.facePath) then return false,'注视恢复信息未读回' end
        rows[#rows+1]=r
        if not save() then rows[#rows]=nil;return false,'注视恢复记录未保存' end
        if eyesOnly then
            r.bound=true;say('[SelfieGaze] 独立眼神绑定 '..actorPath)
            return true
        end
        local anim,mesh=r.anim,r.mesh
        local ok=put(anim,'bUseMultiThreadedAnimationUpdate',false) and U.field(anim,'bUseMultiThreadedAnimationUpdate')==false
            and setInterpolation(anim,0) and put(actor,'LookAtTarget',camera)
            and key(U.field(actor,'LookAtTarget'))==r.cameraKey and put(actor,d.enable,true) and U.field(actor,d.enable)==true
            and setTick(mesh,true)
        say('[SelfieGaze] 绑定 '..mode..' '..actorPath..' 头部输入读回='..tostring(ok)..' 眼部形变='..tostring(morphs~=nil))
        if ok then r.bound=true end
        return ok,not ok and '注视输入写入未读回' or nil
    end
    local function bindWanted(role,actor,camera,wanted,eyeMode)
        if not wanted and eyeMode<=1 then return false end
        local ok,why=bind(actor,camera,role=='主角',not wanted,eyeMode)
        if ok then failures[role]=nil
        else
            local reason=tostring(why or '未知')
            if failures[role]~=reason then say('[SelfieGaze] '..role..'注视未绑定：'..reason);failures[role]=reason end
        end
        return wanted and ok==true
    end
    function self:start(player,companion,camera,wanted,eyes)
        if #rows~=0 or fname==nil then return {false,false} end
        active,sampleAt,lastLens,settleUntil=true,0,nil,0
        wanted=wanted or {true,true}
        eyes=eyes or {1,1}
        local playerBound=bindWanted('主角',player,camera,wanted[1],eyes[1])
        local companionBound=bindWanted('随从',companion,camera,wanted[2],eyes[2])
        for _,r in ipairs(rows)do
            if not r.bound then
                local restored=restore(r,o.world())
                r.rolledBack=restored
            end
        end
        local pending={}
        for _,r in ipairs(rows)do if not r.rolledBack then pending[#pending+1]=r end end
        rows=pending;save()
        return {playerBound,companionBound}
    end
    function self:update(lens,now)
        if not active or #rows==0 or not finite(now) or now<sampleAt then return end
        if not nearly(lastLens,lens) then lastLens,settleUntil=lens,now+.35 end
        if now>=settleUntil then return end
        sampleAt=now+1/30
        local worldID=key(o.world())
        for _,r in ipairs(rows)do
            if r.bound and r.world==worldID and U.valid(r.anim) and U.valid(r.mesh)
                and (r.eyesOnly or key(U.field(r.actor,'LookAtTarget'))==r.cameraKey) then
                local d=PATHS[r.mode]
                local moved=not r.lens or not nearly(r.lens,lens)
                if moved and r.eyesOnly then
                    r.lens=lens;r.sampleUntil=now+.2
                elseif moved then
                    local at=vector(call(r.anim,d.getter,r.camera))
                    if at then
                        local alpha=call(r.anim,d.weight,at)
                        if finite(alpha) then
                            local value=clamp(alpha,0,1)
                            if put(r.anim,d.position,at) and nearly(vector(U.field(r.anim,d.position)),at) then
                                r.lastAt=at
                                if put(r.anim,d.alpha,value) and put(r.anim,d.blend,value>0) then
                                    r.lens=lens
                                    r.sampleUntil=now+.20
                                end
                            end
                        end
                    end
                end
                if moved or now<(r.sampleUntil or 0) then
                    local head=call(r.mesh,'GetSocketTransform',r.bone,0)
                    local origin=vector(U.struct(head,'Translation'))
                    local aim=forward(head,r.axis)
                    local axisEye=({[3]='Left',[4]='Right',[5]='Up',[6]='Down'})[r.eyeMode]
                    local fixed=r.eyeMode>=2 and r.eyeMode<=6
                    local wanted=fixed and {Left=0,Right=0,Up=0,Down=0} or aim and origin and eyeWeights(aim,origin,lens)
                    if axisEye then wanted[axisEye]=.64 end
                    if wanted and r.face and key(call(r.face,'GetSkeletalMeshAsset'))==r.faceAssetKey then
                        local byEye={}
                        for side,socket in pairs(not fixed and r.eyes or {})do
                            local eye=vector(call(r.face,'GetSocketLocation',socket))
                            if eye then byEye[side]=eyeWeights(aim,eye,lens) end
                        end
                        local verified=0
                        for _,v in ipairs(r.morphs)do
                            local weight=(byEye[v.side] or wanted)[v.direction]
                            if math.abs(weight-v.last)>.012 and setMorph(r.face,v.name,weight) then v.last=weight end
                            if math.abs(weight-v.last)<.015 then verified=verified+1 end
                        end
                        if not r.eyeLogged and verified==#r.morphs then
                            r.eyeLogged=true;say('[SelfieGaze] 眼部形变权重读回 '..r.actorPath..' '..verified..'/'..#r.morphs)
                        end
                    end
                    if origin and aim and r.lastAt and not moved and (r.headChecks or 0)<4
                        and (not r.lastHeadCheck or not nearly(r.lastHeadCheck,lens)) then
                        local toward=unit({X=lens.X-origin.X,Y=lens.Y-origin.Y,Z=lens.Z-origin.Z})
                        local error=toward and math.deg(math.acos(clamp(dot(aim,toward),-1,1)))
                        if error then
                            r.headChecks=(r.headChecks or 0)+1
                            r.lastHeadCheck=lens
                            say(string.format('[SelfieGaze] %s 头部方向与镜头夹角 %.1f°（骨骼读回）',r.actorPath,error))
                        end
                    end
                end
            end
        end
    end
    return self
end
return Gaze
