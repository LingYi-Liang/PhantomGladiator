-- Resolve expression and gaze channels on the actual visible head mesh.
local U=require('ue_observe')
local N=require('photo_native')
local Face={}
local presets={
    {name='原表情',weights={}},
    {name='凝神',weights={{'brow_down_L',.72},{'brow_down_R',.72}}},
    {name='惊讶',weights={{'eye_widen_L',.62},{'eye_widen_R',.62},{'jaw_open',.32}}},
    {name='闭眼',weights={{'eye_blink_L',.92},{'eye_blink_R',.92}}},
    {name='微笑',weights={{'McornerPull_EcheekRaise_L',.65},{'McornerPull_EcheekRaise_R',.65}}},
    {name='皱鼻',weights={{'nose_wrinkleFull_L',.58},{'nose_wrinkleFull_R',.58}}},
}

function Face.find(actor,find,choose)
    if not U.valid(actor) then return end
    local meshes,seen={},{}
    local function add(mesh)
        local k=U.key(mesh)
        if k and not seen[k] then seen[k]=true;meshes[#meshes+1]=mesh end
    end
    local cls=type(find)=='function' and find('/Script/Engine.SkeletalMeshComponent')
    if U.valid(cls) then
        for _,component in ipairs(U.array(N.call(actor,'K2_GetComponentsByClass',cls)) or {})do add(component) end
    end
    add(U.field(actor,'Mesh'))
    for _,mesh in ipairs(meshes)do
        if N.same(N.call(mesh,'GetOwner'),actor) and U.field(mesh,'bVisible')~=false and U.field(mesh,'bHiddenInGame')~=true then
            local asset=N.call(mesh,'GetSkeletalMeshAsset')
            local targets=U.field(asset,'MorphTargets')
            local count=U.arraySize(targets)
            if count and count>0 and count<=2048 then
                local map={}
                for _,target in ipairs(U.array(targets) or {})do
                    local label=N.textName(N.call(target,'GetFName')) or N.call(target,'GetName')
                    if type(label)=='string' and not label:find('%c') then map[label]=true end
                end
                local v,b,c,d,f=choose(mesh,asset,map)
                if v then return v,b,c,d,f end
            end
        end
    end
end
function Face.expressions(actor,find)
    local options={{name=presets[1].name,weights={}}}
    local target,asset=Face.find(actor,find,function(mesh,meshAsset,map)
        for i=2,#presets do
            local d=presets[i]
            for _,prefix in ipairs({'','head_lod0_mesh__'})do
                local w={}
                for _,item in ipairs(d.weights)do
                    local channel=prefix..item[1]
                    if not map[channel] then break end
                    w[#w+1]={channel,item[2]}
                end
                if #w==#d.weights then
                    options[#options+1]={name=d.name,weights=w}
                    break
                end
            end
        end
        if #options>1 then return mesh,meshAsset end
    end)
    return {mesh=target,asset=U.key(asset),options=options}
end
return Face
