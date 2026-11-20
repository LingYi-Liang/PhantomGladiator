-- Skill 06 keeps its attached Niagara component on the summoned actor. A cancelled
-- gameplay task can miss the SpawnPillar tag's removal, leaving the effect active.
local U=require('ue_observe')
local Pillar={}
local BOSS='/PBZCombatAsset/ActorData/Mobs/067_MoTian/BP_Monster_MoTian.BP_Monster_MoTian_C'
local SYSTEM='NiagaraSystem /PBZVFXPack/VFX/BattleFX/MoYuan/NS_MoYuan_Pillar_001_Main.NS_MoYuan_Pillar_001_Main'
local function read(obj,method)
    if not U.valid(obj) then return nil end
    local ok,v=pcall(function()return obj[method](obj)end)
    if ok then return U.unwrap(v) end
end
local function attached(actor,comp)
    local mesh=U.key(U.field(actor,'Mesh'))
    return mesh and U.key(read(comp,'GetAttachParent'))==mesh and read(U.field(comp,'Asset'),'GetFullName')==SYSTEM
end
local function skillEnded(actor)
    local specs=U.struct(U.field(U.field(actor,'AbilitySystemComponent'),'ActivatableAbilities'),'Items')
    local found=false
    for _,row in ipairs(U.array(specs) or {}) do
        if U.className(U.struct(row,'Ability'))=='GA_MoTian_Skill_06_C' then
            if U.struct(row,'ActiveCount')~=0 then return false end
            found=true
        end
    end
    return found
end
function Pillar.new(log)
    local pending={}
    local self={}
    function self:tick(members)
        local nextPending={}
        for _,member in ipairs(members)do
            local actor=member.actor
            if member.class_path==BOSS and U.valid(actor) then
                local comp=U.field(actor,'Pillar')
                if U.valid(comp) and read(comp,'IsActive')==true and attached(actor,comp) and skillEnded(actor) then
                    local key,id=U.key(actor),U.key(comp)
                    if key and id then
                        local r=pending[key]
                        if not r or r.id~=id then r={id=id,tries=0}
                        elseif r.tries<2 then
                            r.tries=r.tries+1
                            read(actor,'DespawnPillar')
                            log('[MoYuanPillar] 技能已结束，清理残留火柱 实例='..key..' 组件='..id..' 活动读回='..tostring(read(comp,'IsActive')))
                        end
                        nextPending[key]=r
                    end
                end
            end
        end
        pending=nextPending
    end
    return self
end
return Pillar
