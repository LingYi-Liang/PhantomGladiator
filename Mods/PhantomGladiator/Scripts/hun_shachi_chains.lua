-- The original InitChain type-checks the player class before making three chains.
-- Recreate its component graph only on the NPC that is equipping a chain armament.
local U=require('ue_observe')
local M={}
local chainClass='/PBZCombatAsset/Prototypes/Gameplay/Chain/BP_ChainComponent.BP_ChainComponent_C'
local whipClass='/PBZCombatAsset/Prototypes/Gameplay/Whip/BP_WhipComponent.BP_WhipComponent_C'
local sidesFX='/PBZVFXPack/VFX/BattleFX/HookMan/Assets/NS_HookMan_ChainFinal_001.NS_HookMan_ChainFinal_001'
local middleFX='/PBZVFXPack/VFX/BattleFX/HookMan/NS_HookMan_Chain_201_ActorSpace.NS_HookMan_Chain_201_ActorSpace'
local identity={Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}
local function vector(x)return {X=x,Y=0,Z=0}end
local function call(o,m,...)
    if not U.valid(o) then return false end
    local a,n={...},select('#',...)
    local ok,v=pcall(function()return o[m](o,table.unpack(a,1,n))end)
    return ok,U.unwrap(v)
end
local function owns(comp,actor)
    local ok,owner=call(comp,'GetOwner')
    return ok and U.key(owner)~=nil and U.key(owner)==U.key(actor)
end
local function name(v)
    if type(v)=='string' then return v end
    local ok,s=pcall(function()return v:ToString()end);return ok and s or nil
end
function M.new(o)
    local self={}
    local function add(r,cls)
        local asset=o.asset(cls)
        if not U.valid(asset) or not o.current(r) then return end
        o.say(r,'即将新建锁链部件 '..cls:match('[^%.]+$'))
        local ok,c=call(r.actor,'AddComponentByClass',asset,false,identity,false)
        if not ok or not owns(c,r.actor) then return end
        r.shadowChain.parts[#r.shadowChain.parts+1]=c
        return c
    end
    function self:cleanup(r)
        local state=r.shadowChain
        if not state then return end
        for i=#state.parts,1,-1 do
            local c=state.parts[i]
            if o.current(r) and owns(c,r.actor) then
                o.say(r,'即将销毁锁链部件 '..tostring(U.key(c)))
                call(c,'K2_DestroyComponent',c)
                local _,gone=call(c,'IsBeingDestroyed')
                if U.valid(c) and gone~=true then o.say(r,'锁链部件销毁未读回') end
            end
        end
        r.shadowChain=nil
    end
    function self:select(r,path)
        local needs=path:find('/ShachiHook/',1,true) or path:find('/HuoLiuXing/',1,true) or path:find('/XueDiZi/',1,true)
        if not needs then self:cleanup(r);return true end
        if r.shadowChain then return r.shadowChain.ready end
        if r.shadowChainFailed or not o.current(r) then return false end
        local mesh=U.field(r.actor,'Mesh')
        if not owns(mesh,r.actor) then return false end
        r.shadowChain={parts={}}
        local function fail()
            self:cleanup(r);r.shadowChainFailed=true
            o.say(r,'锁链部件未读回，已撤回本实例的附加部件')
            return false
        end
        local fname=o.fname
        for _,side in ipairs({'R','L','M'}) do
            local spline=add(r,'/Script/Engine.SplineComponent')
            local fx=add(r,'/Script/Niagara.NiagaraComponent')
            local chain=add(r,chainClass)
            local asset=o.asset(side=='M' and middleFX or sidesFX)
            if not (spline and fx and chain and U.valid(asset)) then return fail() end
            o.say(r,'即将设置锁链特效及骨骼 '..side)
            call(fx,'SetCastShadow',true)
            call(fx,'SetAsset',asset,true)
            if U.key(U.field(fx,'Asset'))~=U.key(asset) then return fail() end
            if side~='R' then
                local left=side=='L'
                if not call(chain,'SetParameter',not left,fname(left and 'hand_l' or 'hand_r'),fname(left and 'weapon_l' or 'weapon_r'),
                    vector(0),fname('hand_r'),fname('hand_l'),vector(-5),vector(5),fname(left and 'None' or 'lowerarm_l')) then return fail() end
            end
            call(chain,'ConstructFunc',mesh,spline,fx,nil,false)
            if U.key(U.field(chain,'Mesh'))~=U.key(mesh) or U.key(U.field(chain,'Spline'))~=U.key(spline)
                or U.key(U.field(chain,'Niagara'))~=U.key(fx) then return fail() end
            if side=='M' then
                local lib=o.asset('/Script/Niagara.Default__NiagaraDIRigidMeshCollisionFunctionLibrary')
                if not call(lib,'SetSourceActors',fx,fname('Rig'),{r.actor}) then return fail() end
            end
        end
        -- These are the two BP_Renewal_Hun component-template overrides used by the native
        -- whip actions. Keep the NPC component defaults for all remaining simulation parameters.
        for _,side in ipairs({'R','L'}) do
            local lower=side:lower()
            local whip=add(r,whipClass)
            if not whip then return fail() end
            local fields={WhipRoot='hand_'..lower,WhipEnd='weapon_'..lower,VB_WhipEnd='ik_weapon_'..lower,
                EnableIKCurveName='EnableWeaponIK_'..side,IKTargetSnapToGroundCurveName='IKTargetSnapToGround_'..side,
                LockIKTargetCurveName='LockIKTarget_'..side}
            for field,value in pairs(fields) do
                if not o.current(r) or not owns(whip,r.actor) then return fail() end
                local ok=pcall(function()whip[field]=fname(value)end)
                if not ok or name(U.field(whip,field))~=value then return fail() end
            end
            local index=side=='R' and 0 or 1
            if not pcall(function()whip['Whip Index']=index end) or U.field(whip,'Whip Index')~=index then return fail() end
        end
        r.shadowChain.ready=true
        o.say(r,'锁链3套、左右鞭组件读回 部件='..#r.shadowChain.parts)
        return true
    end
    return self
end
return M
