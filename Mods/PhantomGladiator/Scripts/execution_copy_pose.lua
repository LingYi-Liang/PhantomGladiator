-- MoYuan's separate head/brows already use Hun_CopyPose. Keep their own pose buffers and redirect an
-- attached-parent CopyPose from the now-following main mesh to the real animated source for this execution.
local U=require('ue_observe')
local Copy={}
local function call(object,method,...)
    if not U.valid(object) then return false,nil end
    local args,n={...},select('#',...)
    local ok,result=pcall(function()return object[method](object,table.unpack(args,1,n))end)
    return ok,ok and U.unwrap(result) or nil
end
local function value(object,method,...)
    local ok,result=call(object,method,...)
    if ok then return result end
    return nil
end
local function short(object)
    local n=value(object,'GetFName');local ok,s=pcall(function()return n:ToString()end)
    return ok and s or '?'
end
local function fields(v,names)
    local t={}
    for _,name in ipairs(names) do local n=U.struct(v,name);if type(n)~='number' or n~=n then return nil end;t[name]=n end
    return t
end
local function transform(v)
    local p=fields(U.struct(v,'Translation'),{'X','Y','Z'})
    local q=fields(U.struct(v,'Rotation'),{'X','Y','Z','W'})
    local s=fields(U.struct(v,'Scale3D'),{'X','Y','Z'})
    return p and q and s and {Translation=p,Rotation=q,Scale3D=s} or nil
end
local function sameTransform(a,b)
    if not a or not b then return false end
    for _,field in ipairs({'Translation','Rotation','Scale3D'}) do
        for k,v in pairs(a[field]) do if math.abs(v-b[field][k])>0.001 then return false end end
    end
    return true
end
function Copy.restore(entries,log)
    local all=true
    for _,entry in ipairs(entries or {}) do
        if not entry.restored then
            if not U.valid(entry.comp) then entry.restored=true
            elseif U.valid(entry.parent) and U.valid(entry.animClass) then
                local attached=call(entry.comp,'K2_AttachToComponent',entry.parent,entry.socket,1,1,1,false)
                local placed=call(entry.comp,'K2_SetRelativeTransform',entry.relative,false,{},true)
                local initialized=call(entry.comp,'SetAnimInstanceClass',entry.animClass)
                local parent=value(entry.comp,'GetAttachParent')
                local cls=value(value(entry.comp,'GetAnimInstance'),'GetClass')
                entry.restored=attached and placed and initialized and U.key(parent)==U.key(entry.parent)
                    and U.key(cls)==U.key(entry.animClass) and sameTransform(entry.relative,transform(value(entry.comp,'GetRelativeTransform')))
                log('[ExecutionFace] 恢复 '..short(entry.comp)..' parent='..short(parent)..' class='..short(cls)..' 变换/归属读回='..tostring(entry.restored))
            end
            if not entry.restored then all=false end
        end
    end
    return all
end
function Copy.follow(parts,main,source,log)
    local entries={}
    for _,part in ipairs(parts) do
        if not part.cloth and not part.leader and U.key(part.comp)~=U.key(main) then
            local parent=value(part.comp,'GetAttachParent')
            local instance=value(part.comp,'GetAnimInstance')
            local cls=value(instance,'GetClass')
            local node=U.field(instance,'AnimGraphNode_CopyPoseFromMesh')
            local attachedParent=U.struct(node,'bUseAttachedParent')
            if U.valid(parent) and U.key(parent)==U.key(main) and short(cls)=='Hun_CopyPose_C'
                and (attachedParent==true or attachedParent==1) then
                local relative=transform(value(part.comp,'GetRelativeTransform'))
                local socket=value(part.comp,'GetAttachSocketName')
                if relative and socket~=nil then
                    local entry={comp=part.comp,parent=parent,animClass=cls,relative=relative,socket=socket}
                    entries[#entries+1]=entry
                    local moved=call(part.comp,'K2_AttachToComponent',source,socket,1,1,1,false)
                    local reset=call(part.comp,'SetAnimInstanceClass',cls)
                    local actualParent=value(part.comp,'GetAttachParent')
                    local actualClass=value(value(part.comp,'GetAnimInstance'),'GetClass')
                    local verified=moved and reset and U.key(actualParent)==U.key(source) and U.key(actualClass)==U.key(cls)
                    log('[ExecutionFace] 改接直接动画源 '..short(part.comp)..' 原父='..short(parent)..' 读回父='..short(actualParent)
                        ..' CopyPose类='..short(actualClass)..' verified='..tostring(verified))
                    if not verified then Copy.restore({entry},log) end
                else log('[ExecutionFace] 跳过 '..short(part.comp)..'：无法完整保存原附着变换') end
            end
        end
    end
    return entries
end
function Copy.sample(entries,source,log,name)
    local bone=name('head')
    local sourceIndex=value(source,'GetBoneIndex',bone)
    if type(sourceIndex)~='number' or sourceIndex<0 then return end
    local a=fields(value(source,'GetSocketLocation',bone),{'X','Y','Z'})
    for _,entry in ipairs(entries or {}) do
        local index=value(entry.comp,'GetBoneIndex',bone)
        local b=type(index)=='number' and index>=0 and fields(value(entry.comp,'GetSocketLocation',bone),{'X','Y','Z'}) or nil
        if a and b then
            local d=math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)
            log(string.format('[ExecutionFace] 动态读回 %s head与动画源距离=%.2fcm parent=%s',short(entry.comp),d,short(value(entry.comp,'GetAttachParent'))))
        end
    end
end
return Copy
