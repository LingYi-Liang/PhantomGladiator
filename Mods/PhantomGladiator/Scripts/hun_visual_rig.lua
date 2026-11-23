-- A replacement skin is presentation only. Keep the NPC's own animated mesh as the driver.
local U=require('ue_observe')
local Rig={}
local BONES={'pelvis','head','hand_l','hand_r','foot_l','foot_r'}
local function weak(value)
    local kind=U.kind(value)
    if kind=='WeakObjectPtr' or kind=='FWeakObjectPtr' or kind=='TWeakObjectPtr' then
        local ok,v=pcall(function()return value:Get()end);return ok and U.valid(v) and v or nil
    end
    return U.valid(value) and value or nil
end
function Rig.leader(comp)return weak(U.field(comp,'LeaderPoseComponent'))end

function Rig.new(o)
    local self={}
    local call=o.call
    local function visible(c)
        local flag=U.field(c,'bVisible')
        if type(flag)=='boolean' then return flag end
        local _,result=call(c,'IsVisible');return result
    end
    local function setVisible(c,on)
        local ok=call(c,'SetVisibility',on,false)
        return ok and visible(c)==on
    end
    local function actorMesh(r,mesh)
        local _,owner=call(mesh,'GetOwner')
        return r.still and r.still() and U.key(mesh)~=nil and U.key(U.field(r.actor,'Mesh'))==U.key(mesh) and U.key(owner)==U.key(r.actor)
    end
    local function parentBone(comp,bone)
        local _,name=call(comp,'GetParentBone',o.fname(bone))
        if type(name)=='string' then return name:lower() end
        local ok,s=pcall(function()return name:ToString()end)
        return ok and type(s)=='string' and s:lower() or nil
    end
    local function matchingBones(a,b,measure)
        local head,pelvis
        local checked={}
        for _,name in ipairs(BONES)do
            local bone=o.fname(name)
            local _,ia=call(a,'GetBoneIndex',bone);local _,ib=call(b,'GetBoneIndex',bone)
            if type(ia)~='number' or ia<0 or type(ib)~='number' or ib<0 then return false end
            if measure then
                local pa=o.position(a,bone);local pb=o.position(b,bone)
                local gap=o.distance(pa,pb)
                if not gap or not (gap<=3) then return false end
                if name=='head' then head=pb elseif name=='pelvis' then pelvis=pb end
            else
                -- The leader maps bones by name. Matching endpoints on unrelated parent chains
                -- is insufficient; verify the body chains once before creating the visual mesh.
                local node=name
                for depth=1,64 do
                    if node=='none' or checked[node] then break end
                    local parent=parentBone(a,node)
                    if not parent or parent~=parentBone(b,node) or parent==node or depth==64 then return false end
                    checked[node]=true;node=parent
                end
            end
        end
        return not measure or (o.distance(head,pelvis) or 0)>5
    end
    function self:bind(component,driver)
        local ownerOK,owner=call(component,'GetOwner');local _,bodyOwner=call(driver,'GetOwner')
        if not ownerOK or not U.key(owner) or U.key(owner)~=U.key(bodyOwner) then return false end
        local previous=U.key(Rig.leader(component))
        if previous and previous~=U.key(driver) and previous~=U.key(Rig.leader(driver)) then return false end
        local ok=call(component,'SetLeaderPoseComponent',driver,true,false)
        local actual=U.key(Rig.leader(component))
        return ok and actual~=nil and (actual==U.key(driver) or actual==U.key(Rig.leader(driver)))
    end
    local function partsVisible(group,on)
        if not group then return true end
        for _,p in ipairs(group.parts)do
            if not o.owns(p) or not setVisible(p.comp,on) then return false end
        end
        return true
    end
    function self:discard(r,slot)
        local group=r[slot]
        if group then
            for _,p in ipairs(group.parts)do if o.owns(p) then setVisible(p.comp,false) end end
            local _,done=o.destroy(group)
            if done then r[slot]=nil end
            return done
        end
        return true
    end
    function self:stage(r,mesh,outfit,signature)
        if not actorMesh(r,mesh) or not matchingBones(outfit.bodySource,mesh,false) then return false end
        if not self:discard(r,'pendingRig') then return false end
        local group={actor=r.actor,name=r.name,parts={},signature=signature,driver=mesh,asset=outfit.body}
        r.pendingRig=group
        local function build()
            local root=o.newBody(group,mesh,outfit)
            if not root or not self:bind(root,mesh) then return false end
            group.root=root
            if outfit.head then
                local head=o.addMesh(group,root,outfit.head,r.still)
                if not head then return false end
                group.head=o.find(group,outfit.head.name)
                group.headAsset=outfit.head.object
                group.gap=o.headGap(outfit.head.source,outfit.bodySource) or 0
            end
            for _,spec in ipairs(outfit.parts)do if not o.addMesh(group,root,spec,r.still) then return false end end
            for _,spec in ipairs(outfit.cloth)do if not o.addCloth(group,root,spec,r.still) then return false end end
            for _,part in ipairs(group.parts)do
                if not o.owns(part) then return false end
                call(part.comp,'SetCollisionEnabled',0)
                local _,collision=call(part.comp,'GetCollisionEnabled')
                if collision~=0 then return false end
            end
            return partsVisible(group,false)
        end
        local ok,ready=pcall(build)
        if not ok or not ready then self:discard(r,'pendingRig');return false end
        return true
    end
    local function baseline(r,mesh,on)
        if not actorMesh(r,mesh) then return false end
        if on then
            local old=r.rigBaseline
            if not old then return true end
            local restored=true
            local _,asset=call(mesh,'GetSkeletalMeshAsset')
            if old.mesh==U.key(mesh) and old.asset==U.key(asset) then
                for _,p in ipairs(old.parts)do
                    if o.owns(p) and not setVisible(p.comp,true) then restored=false end
                end
            end
            if old.mesh==U.key(mesh) then
                if old.visible and not setVisible(mesh,true) then restored=false end
                if U.field(mesh,'VisibilityBasedAnimTickOption')==0 then mesh.VisibilityBasedAnimTickOption=old.tick end
            end
            if restored then r.rigBaseline=nil end
            return restored
        end
        if r.rigBaseline then return true end
        local wasVisible=visible(mesh)
        local tick=U.field(mesh,'VisibilityBasedAnimTickOption')
        if wasVisible~=true or type(tick)~='number' then return false end
        local _,asset=call(mesh,'GetSkeletalMeshAsset')
        local old={mesh=U.key(mesh),asset=U.key(asset),visible=wasVisible,tick=tick,parts={}}
        r.rigBaseline=old
        mesh.VisibilityBasedAnimTickOption=0
        if U.field(mesh,'VisibilityBasedAnimTickOption')~=0 or not setVisible(mesh,false) then return false end
        for _,p in ipairs(r.parts or {})do
            if not p.gone and o.owns(p) then
                if visible(p.comp) then
                    old.parts[#old.parts+1]=p
                    if not setVisible(p.comp,false) then return false end
                end
            end
        end
        return true
    end
    function self:aligned(group,repair)
        if not group or not group.root or not group.parts[1] or not o.owns(group.parts[1]) or
            U.key(U.field(group.actor,'Mesh'))~=U.key(group.driver) or
            U.key(weak(U.field(group.root,'LeaderPoseComponent')))~=U.key(group.driver) then return false end
        local _,asset=call(group.root,'GetSkeletalMeshAsset')
        if U.key(asset)~=U.key(group.asset) then return false end
        if not matchingBones(group.root,group.driver,true) then return false end
        if not group.head then return true end
        if not o.owns(group.head) then return false end
        local _,headAsset=call(group.head.comp,'GetSkeletalMeshAsset')
        if U.key(headAsset)~=U.key(group.headAsset) then return false end
        local gap=o.headGap(group.head.comp,group.root)
        if gap~=nil and math.abs(gap-group.gap)<=1 then group.headBad=0;return true end
        group.headBad=(group.headBad or 0)+1
        if repair and gap and group.headBad>=2 and not group.headRebound then
            local _,a=call(group.head.comp,'GetSkeletalMeshAsset');local _,b=call(group.root,'GetSkeletalMeshAsset')
            if U.key(U.field(a,'Skeleton')) and U.key(U.field(a,'Skeleton'))==U.key(U.field(b,'Skeleton')) then
                group.headRebound=self:bind(group.head.comp,group.root)
            end
        end
        return false
    end
    function self:driverReady(r,mesh)
        local held=r.rigBaseline
        local _,asset=call(mesh,'GetSkeletalMeshAsset')
        if not held or not actorMesh(r,mesh) or held.mesh~=U.key(mesh) or held.asset~=U.key(asset) then return false end
        local tick=U.field(mesh,'VisibilityBasedAnimTickOption')
        if tick~=0 then
            if type(tick)~='number' then return false end
            held.tick=tick;mesh.VisibilityBasedAnimTickOption=0
            if U.field(mesh,'VisibilityBasedAnimTickOption')~=0 then return false end
        end
        return visible(mesh)==false or setVisible(mesh,false)
    end
    function self:commit(r,mesh)
        local group=r.pendingRig
        if not group or U.key(group.driver)~=U.key(mesh) or not actorMesh(r,mesh) or not self:aligned(group,true) then return false end
        if not self:discard(r,'retiredRig') then return false end
        if not partsVisible(group,true) or not baseline(r,mesh,false) then
            partsVisible(group,false)
            if not r.activeRig then baseline(r,mesh,true) end
            return false
        end
        r.retiredRig,r.activeRig,r.pendingRig=r.activeRig,group,nil
        self:discard(r,'retiredRig')
        return true
    end
    function self:restore(r,mesh)
        local pending=self:discard(r,'pendingRig')
        local retired=self:discard(r,'retiredRig')
        if r.rigBaseline and not baseline(r,mesh,true) then return false end
        return self:discard(r,'activeRig') and pending and retired
    end
    function self:death(r,on)
        for _,p in ipairs(r.activeRig and r.activeRig.parts or {})do
            if o.owns(p) then
                if on and visible(p.comp)==true then p.hiddenOnDeath=setVisible(p.comp,false)
                elseif not on and p.hiddenOnDeath then
                    p.hiddenOnDeath=nil
                    if visible(p.comp)==false then setVisible(p.comp,true) end
                end
            end
        end
    end
    return self
end
return Rig
