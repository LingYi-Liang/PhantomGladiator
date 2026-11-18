-- Profile weapons belong to one captured NPC. Assets in the catalog are only looked up.
local data=require('hun_weapon_catalog')
local Rotation={}
local byId={}
for rank,row in ipairs(data.rows) do byId[row.id]=row;row.rank=rank end

local function pool(profile)
    local out={}
    local entries={}
    for _,entry in ipairs(profile and profile.weapons or data.rows) do entries[#entries+1]=entry end
    for _,entry in ipairs(profile and profile.variants or {}) do
        local variant=data.variants[entry.id]
        if variant and not variant.poleOnly then entries[#entries+1]=entry end
    end
    for _,entry in ipairs(entries) do
        local row=byId[entry.id] or data.variants[entry.id]
        if row then
            local path=entry.path
            if entry==row and row.soul and row.soulPath~='' then path=row.soulPath end
            local cfg=(path==row.path or path==row.soulPath) and data.configs[path]
            local weight=entry.weight or 1
            if cfg and weight>0 then
                local level=type(entry.level)=='number' and entry.level or #row.multipliers
                local item={id=row.id,native_id=row.native_id,label=row.label,config=path,weight=weight,
                    level=math.max(1,math.min(level,#row.multipliers)),rank=row.rank,soul=entry.soul==true,
                    effects=row.effects,multipliers=row.multipliers,temporary=row.temporary,grantGroup=row.grantGroup,
                    progression=row.grantStage and (row.grantStage-1)/12 or (row.rank-1)/math.max(1,#data.rows-1)}
                for k,v in pairs(cfg) do item[k]=v end
                out[#out+1]=item
            end
        end
    end
    return out
end

function Rotation.allowsPoleHead(profile)
    if not profile or profile.variants==nil then return true end
    for _,entry in ipairs(profile.variants) do
        local variant=data.variants[entry.id]
        if variant and variant.poleOnly and entry.path==variant.path and (entry.weight or 1)>0 then return true end
    end
    return false
end

function Rotation.new(r)
    local profile=r.loadout or {}
    return {pool=pool(profile),ai=profile.ai or {},resources=profile.resources or {},activeEffects={},
        failures={},history={},picks={},retryAt=0}
end

function Rotation.pick(s,phase,random)
    local weights,total={},0
    for i,item in ipairs(s.pool) do
        if (s.failures[item.id] or 0)<2 then
            if item.id==phase then return item end
            if item.id~=s.currentId then
                local weight=item.weight
                -- For a multi-stage map we use the earliest member of its native map group.
                if s.ai.late_weapon_bias~=false then weight=weight*(1+2*item.progression) end
                if s.ai.repeat_policy~='none' then
                    for age,id in ipairs(s.history) do if id==item.id then weight=weight*age/(age+2) end end
                end
                weights[i]=weight
                total=total+weight
            end
        end
    end
    if total<=0 then return nil end
    local draw=(random or math.random)()*total
    local last
    for i,item in ipairs(s.pool) do
        if weights[i] then
            last=item
            draw=draw-weights[i]
            if draw<0 then return item end
        end
    end
    return last
end

function Rotation.chosen(s,item)
    s.currentId=item.id
    s.picks[item.id]=(s.picks[item.id] or 0)+1
    table.insert(s.history,1,item.id)
    if #s.history>3 then table.remove(s.history) end
end

-- Build the order from the weapon's own input map followed by the game's shared map.
local chains={}
function Rotation.chain(item,heavy)
    local name=heavy and item.heavyChain or item.chain
    if not name then return nil end
    if chains[name] then return chains[name] end
    local own=data.chains[name]
    local common=heavy and data.chains.AIM_Hun_HeavyAttack or data.chains.AIM_Hun_LightAttack
    local out={actions={},combos={}}
    for _,kind in ipairs({'actions','combos'}) do
        for _,v in ipairs(own[kind]) do table.insert(out[kind],v) end
        if own~=common then for _,v in ipairs(common[kind]) do table.insert(out[kind],v) end end
    end
    chains[name]=out
    return out
end

-- Record handles for effects actually added by this module. Never remove someone else's effect of the same class.
function Rotation.effects(s,item,asc,api,removeAll)
    local wanted={}
    if item then
        for _,e in ipairs(item.effects) do
            if item.level>=e[2] and (not e[5] or item.soul) then wanted[e[1]]=e end
        end
    end
    for path,record in pairs(s.activeEffects) do
        if (removeAll or record.equipped) and not wanted[path] then
            api.say('即将 移除魂当前武器效果 '..path)
            local ok,result=api.call(asc,'RemoveActiveGameplayEffect',record.handle,-1)
            local got,count=api.call(asc,'GetGameplayEffectCount',record.cls,nil,true)
            api.say('移除武器效果 读回 '..path..' 数量='..tostring(count))
            if ok and result~=false or got and count==0 then s.activeEffects[path]=nil end
        end
    end
    -- Apply in the order of the source table: base, upgrades, then snap-soul effects.
    for _,e in ipairs(item and item.effects or {}) do
        local path=e[1]
        if wanted[path]==e and not s.activeEffects[path] then
            local cls=api.object(path)
            local read,count
            if cls then read,count=api.call(asc,'GetGameplayEffectCount',cls,nil,true) end
            if cls and read and count==0 then
                api.say('即将 施加魂武器效果 '..item.label..' '..path..' 等级='..e[3])
                local sent,handle=api.call(asc,'BP_ApplyGameplayEffectToSelf',cls,e[3],{})
                local got,after=api.call(asc,'GetGameplayEffectCount',cls,nil,true)
                api.say('武器效果 读回 '..path..' 数量='..tostring(after))
                if sent and got and type(after)=='number' and after>0 and handle~=nil then
                    s.activeEffects[path]={cls=cls,handle=handle,equipped=e[4]}
                end
            end
        end
    end
end

return Rotation
