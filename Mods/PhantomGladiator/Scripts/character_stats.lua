-- Native attribute adapter. No raw memory writes and no shared data-table edits.
-- CharacterBasics.hpp, ProjectPBZ.hpp and SGameAttributes.hpp are the local schemas.
local U=require('ue_observe')
local Stats={}
Stats.fields={'Attack','ShachiAttack'}
local families={'Physical','PhysicalSharp','PhysicalBlunt','Elemental','Fire','Toxin','Ice','Aqua',
    'Lightning','Blood','Chaos','ImpactShachi','ReflectShachi'}
local prefixes={'Amplification_','DealtVulnerabilityMultiplier_','DealtReductionMultiplier_',
    'Resistance_','TakenAdditiveMultiplier_','TakenVulnerabilityMultiplier_','TakenReductionMultiplier_'}
for _,family in ipairs(families)do for _,prefix in ipairs(prefixes)do Stats.fields[#Stats.fields+1]=prefix..family end end
for _,field in ipairs({'Resistance_Poise','TakenAdditiveMultiplier_Poise','TakenVulnerabilityMultiplier_Poise','TakenReductionMultiplier_Poise',
        'Resistance_BreakDamageAdditionalMultiplier','TakenAdditiveMultiplier_BreakDamage','TakenVulnerabilityMultiplier_BreakDamage','TakenReductionMultiplier_BreakDamage',
        'Resistance_DefenceShachi','TakenAdditiveMultiplier_DefenceShachi','TakenVulnerabilityMultiplier_DefenceShachi','TakenReductionMultiplier_DefenceShachi',
        'Health_Max','Shachi_Max'})do
    Stats.fields[#Stats.fields+1]=field
end
-- Every attribute of UBasicAttributeSet (CharacterBasics.hpp), header order: what custom spawn stats can set.
Stats.allFields={
    'Level','Health','Health_Max','Health_Max_Lv1','Shield','Shield_Max','Infliction_Max','Infliction_Max_Lv1',
    'Attack','Attack_Lv1','Amplification_Physical','DealtVulnerabilityMultiplier_Physical',
    'DealtReductionMultiplier_Physical','Resistance_Physical','TakenAdditiveMultiplier_Physical',
    'TakenVulnerabilityMultiplier_Physical','TakenReductionMultiplier_Physical','Amplification_PhysicalSharp',
    'DealtVulnerabilityMultiplier_PhysicalSharp','DealtReductionMultiplier_PhysicalSharp','Resistance_PhysicalSharp',
    'TakenAdditiveMultiplier_PhysicalSharp','TakenVulnerabilityMultiplier_PhysicalSharp',
    'TakenReductionMultiplier_PhysicalSharp','Amplification_PhysicalBlunt',
    'DealtVulnerabilityMultiplier_PhysicalBlunt','DealtReductionMultiplier_PhysicalBlunt','Resistance_PhysicalBlunt',
    'TakenAdditiveMultiplier_PhysicalBlunt','TakenVulnerabilityMultiplier_PhysicalBlunt',
    'TakenReductionMultiplier_PhysicalBlunt','Resistance_Poise','TakenAdditiveMultiplier_Poise',
    'TakenVulnerabilityMultiplier_Poise','TakenReductionMultiplier_Poise','Amplification_Elemental',
    'DealtVulnerabilityMultiplier_Elemental','DealtReductionMultiplier_Elemental','Resistance_Elemental',
    'TakenAdditiveMultiplier_Elemental','TakenVulnerabilityMultiplier_Elemental','TakenReductionMultiplier_Elemental',
    'Amplification_Fire','DealtVulnerabilityMultiplier_Fire','DealtReductionMultiplier_Fire','Resistance_Fire',
    'TakenAdditiveMultiplier_Fire','TakenVulnerabilityMultiplier_Fire','TakenReductionMultiplier_Fire',
    'Amplification_Toxin','DealtVulnerabilityMultiplier_Toxin','DealtReductionMultiplier_Toxin','Resistance_Toxin',
    'TakenAdditiveMultiplier_Toxin','TakenVulnerabilityMultiplier_Toxin','TakenReductionMultiplier_Toxin',
    'Amplification_Ice','DealtVulnerabilityMultiplier_Ice','DealtReductionMultiplier_Ice','Resistance_Ice',
    'TakenAdditiveMultiplier_Ice','TakenVulnerabilityMultiplier_Ice','TakenReductionMultiplier_Ice',
    'Amplification_Aqua','DealtVulnerabilityMultiplier_Aqua','DealtReductionMultiplier_Aqua','Resistance_Aqua',
    'TakenAdditiveMultiplier_Aqua','TakenVulnerabilityMultiplier_Aqua','TakenReductionMultiplier_Aqua',
    'Amplification_Lightning','DealtVulnerabilityMultiplier_Lightning','DealtReductionMultiplier_Lightning',
    'Resistance_Lightning','TakenAdditiveMultiplier_Lightning','TakenVulnerabilityMultiplier_Lightning',
    'TakenReductionMultiplier_Lightning','Amplification_Blood','DealtVulnerabilityMultiplier_Blood',
    'DealtReductionMultiplier_Blood','Resistance_Blood','TakenAdditiveMultiplier_Blood',
    'TakenVulnerabilityMultiplier_Blood','TakenReductionMultiplier_Blood','Amplification_Chaos',
    'DealtVulnerabilityMultiplier_Chaos','DealtReductionMultiplier_Chaos','Resistance_Chaos',
    'TakenAdditiveMultiplier_Chaos','TakenVulnerabilityMultiplier_Chaos','TakenReductionMultiplier_Chaos',
    'Resistance_BreakDamageAdditionalMultiplier','TakenAdditiveMultiplier_BreakDamage',
    'TakenVulnerabilityMultiplier_BreakDamage','TakenReductionMultiplier_BreakDamage','Shachi','Shachi_Min',
    'Shachi_Max','Shachi_Max_Lv1','ShachiRegen','ShachiRegenCooldown','BreakDurationAdditionalMultiplier',
    'ShachiAttack','ShachiAttack_Lv1','Amplification_ImpactShachi','DealtVulnerabilityMultiplier_ImpactShachi',
    'DealtReductionMultiplier_ImpactShachi','Resistance_ImpactShachi','TakenAdditiveMultiplier_ImpactShachi',
    'TakenVulnerabilityMultiplier_ImpactShachi','TakenReductionMultiplier_ImpactShachi','Amplification_ReflectShachi',
    'DealtVulnerabilityMultiplier_ReflectShachi','DealtReductionMultiplier_ReflectShachi','Resistance_ReflectShachi',
    'TakenAdditiveMultiplier_ReflectShachi','TakenVulnerabilityMultiplier_ReflectShachi',
    'TakenReductionMultiplier_ReflectShachi','Amplification_DefenceShachi',
    'DealtVulnerabilityMultiplier_DefenceShachi','DealtReductionMultiplier_DefenceShachi','Resistance_DefenceShachi',
    'TakenAdditiveMultiplier_DefenceShachi','TakenVulnerabilityMultiplier_DefenceShachi',
    'TakenReductionMultiplier_DefenceShachi','Resistance_ShachiWeaponHealth','Resistance_ShachiWeaponShachi',
    'Resistance_ShachiWeaponStrength','Resistance_ShachiWeaponRanged','Resistance_ShachiWeaponMagic',
    'Resistance_ShachiWeaponMartial','Resistance_ShachiWeaponSummon','HeavyAttack_ShachiCostReduction',
    'UltimateCharge','UltimateCharge_Max','UltimateChargeCount','UltimateChargeCount_Max',
    'UltimateChargeAdditiveRate','UltimateChargeGainRateMultiplier','SpiritShadow','SpiritShadow_Max',
    'Ignite_Accumulation','Poison_Accumulation','Frost_Accumulation','Thunder_Accumulation',
    'Electrified_Accumulation','Bleed_Accumulation','BloodBurst_Accumulation','Water_Accumulation',
    'Amplification_ElementalAccumulation','DealtVulnerabilityMultiplier_ElementalAccumulation',
    'DealtReductionMultiplier_ElementalAccumulation','Resistance_ElementalAccumulation',
    'TakenAdditiveMultiplier_ElementalAccumulation','TakenVulnerabilityMultiplier_ElementalAccumulation',
    'TakenReductionMultiplier_ElementalAccumulation','Amplification_Ignite',
    'DealtVulnerabilityMultiplier_IgniteAccumulation','DealtReductionMultiplier_IgniteAccumulation',
    'Resistance_IgniteAccumulation','TakenAdditiveMultiplier_IgniteAccumulation',
    'TakenVulnerabilityMultiplier_IgniteAccumulation','TakenReductionMultiplier_IgniteAccumulation',
    'Amplification_Poison','DealtVulnerabilityMultiplier_PoisonAccumulation',
    'DealtReductionMultiplier_PoisonAccumulation','Resistance_PoisonAccumulation',
    'TakenAdditiveMultiplier_PoisonAccumulation','TakenVulnerabilityMultiplier_PoisonAccumulation',
    'TakenReductionMultiplier_PoisonAccumulation','Amplification_Frost',
    'DealtVulnerabilityMultiplier_FrostAccumulation','DealtReductionMultiplier_FrostAccumulation',
    'Resistance_FrostAccumulation','TakenAdditiveMultiplier_FrostAccumulation',
    'TakenVulnerabilityMultiplier_FrostAccumulation','TakenReductionMultiplier_FrostAccumulation',
    'Amplification_Electrified','DealtVulnerabilityMultiplier_ElectrifiedAccumulation',
    'DealtReductionMultiplier_ElectrifiedAccumulation','Resistance_ElectrifiedAccumulation',
    'TakenAdditiveMultiplier_ElectrifiedAccumulation','TakenVulnerabilityMultiplier_ElectrifiedAccumulation',
    'TakenReductionMultiplier_ElectrifiedAccumulation','Amplification_Bleed',
    'DealtVulnerabilityMultiplier_BleedAccumulation','DealtReductionMultiplier_BleedAccumulation',
    'Resistance_BleedAccumulation','TakenAdditiveMultiplier_BleedAccumulation',
    'TakenVulnerabilityMultiplier_BleedAccumulation','TakenReductionMultiplier_BleedAccumulation',
    'Amplification_BloodBurst','DealtVulnerabilityMultiplier_BloodBurstAccumulation',
    'DealtReductionMultiplier_BloodBurstAccumulation','Resistance_BloodBurstAccumulation',
    'TakenAdditiveMultiplier_BloodBurstAccumulation','TakenVulnerabilityMultiplier_BloodBurstAccumulation',
    'TakenReductionMultiplier_BloodBurstAccumulation','Amplification_Water',
    'DealtVulnerabilityMultiplier_WaterAccumulation','DealtReductionMultiplier_WaterAccumulation',
    'Resistance_WaterAccumulation','TakenAdditiveMultiplier_WaterAccumulation',
    'TakenVulnerabilityMultiplier_WaterAccumulation','TakenReductionMultiplier_WaterAccumulation',
    'StatusInflictionDecrementRate','ExecutionExecutorNormalHealthThreshold','ExecutionExecutorBreakHealthThreshold',
    'ExecutionTargetNormalHealthThreshold','ExecutionTargetBreakHealthThreshold','MindDustAdditiveMultiplier',
    'Health_Min','WalkSpeed','JogSpeed','SprintSpeed','CrouchSpeed','FinalWalkSpeed','Awakening','Awakening_Max',
    'PowerScore','XP','Coin','Corrosion'}
-- The level-1 values the game works out damage from (v0.37.1, from fight readbacks): a hit takes the share
-- attacker Attack_Lv1 x move multiplier / target Health_Max_Lv1 of the target's Health_Max, so Health_Max and
-- Attack alone change the bar and the numbers shown but not how many hits a unit takes or deals.
Stats.levelOne={Health_Max='Health_Max_Lv1',Shachi_Max='Shachi_Max_Lv1',Attack='Attack_Lv1',ShachiAttack='ShachiAttack_Lv1',
    Infliction_Max='Infliction_Max_Lv1'}
Stats.levelOneFields={'Health_Max_Lv1','Shachi_Max_Lv1','Attack_Lv1','ShachiAttack_Lv1','Infliction_Max_Lv1'}
-- No GE_MA_<field>_1_Override among the game's assets (asset-index.tsv): these are written on the set's own
-- FGameplayAttributeData (base and current) and read back from it; the other 209 go through the native effect.
Stats.direct={}
for _,field in ipairs({'Infliction_Max_Lv1','Amplification_DefenceShachi','DealtVulnerabilityMultiplier_DefenceShachi',
        'DealtReductionMultiplier_DefenceShachi','Resistance_ShachiWeaponHealth','Resistance_ShachiWeaponShachi',
        'Resistance_ShachiWeaponStrength','Resistance_ShachiWeaponRanged','Resistance_ShachiWeaponMagic',
        'Resistance_ShachiWeaponMartial','Resistance_ShachiWeaponSummon','UltimateChargeGainRateMultiplier',
        'ExecutionTargetNormalHealthThreshold','ExecutionTargetBreakHealthThreshold'})do
    Stats.direct[field]=true
end
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<=1e9 end
local function text(value)
    if type(value)=='string' then return value end
    local ok,s=pcall(function()return value:ToString()end)
    return ok and type(s)=='string' and s or nil
end
Stats.finite=finite
function Stats.close(a,b)return finite(a) and finite(b) and math.abs(a-b)<=math.max(1e-6,math.abs(b)*2e-5)end
local function attributeSet(actor)
    if not U.valid(actor) then return nil,'单位已失效' end
    local set=U.field(actor,'AttributeSetBase')
    if not U.valid(set) then return nil,'没有可读取的战斗属性' end
    local key=U.key(actor);local outer=set
    if not key then return nil,'单位标识不可读' end
    for _=1,8 do
        if not U.valid(outer) then break end
        if U.key(outer)==key then return set end
        local ok,parent=pcall(function()return outer:GetOuter()end)
        if not ok then break end
        outer=parent
    end
    return nil,'属性集不属于这个单位，未修改'
end
function Stats.new()
    local self={effects={}}
    -- Every attribute is writable (custom spawn stats); stat matching copies only Stats.fields.
    local allowed={};for _,field in ipairs(Stats.allFields)do allowed[field]=true end
    function self:read(actor,field)
        local set,why=attributeSet(actor);if not set then return nil,why end
        local data,ok=U.field(set,field)
        local base=U.struct(data,'BaseValue');local current=U.struct(data,'CurrentValue')
        if not ok or not finite(base) or not finite(current) then return nil,'属性不可读: '..field end
        return {base=base,current=current}
    end
    function self:snapshot(actor)
        local result={}
        for _,field in ipairs(Stats.fields)do
            local entry,why=self:read(actor,field);if not entry then return nil,why end
            result[field]=entry
        end
        for _,field in ipairs({'Health','Shachi'})do
            local entry,why=self:read(actor,field);if not entry then return nil,why end
            result[field]=entry
        end
        for _,field in ipairs(Stats.levelOneFields)do
            local entry,why=self:read(actor,field);if not entry then return nil,why end
            result[field]=entry
        end
        if result.Health_Max.current<=0 or result.Shachi_Max.current<=0 or result.Attack.current<=0 then
            return nil,'生命/杀气上限或攻击不是有效的正数，不能作为数值对齐对象'
        end
        return result
    end
    local function descriptor(actor,field)
        local set,why=attributeSet(actor);if not set then return nil,nil,why end
        if not allowed[field] then return nil,nil,'属性不在已核对的修改范围' end
        local utils=StaticFindObject('/Script/SGameAttributes.Default__AttributeUtils')
        local abilities=StaticFindObject('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
        local check=StaticFindObject('/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:IsValid')
        if not U.valid(utils) or not U.valid(abilities) or not U.valid(check) then return nil,nil,'原生属性函数库不可用' end
        -- Combat field paths and observer Health_Min were verified in asset-index.tsv.
        -- Preserve the in-place native descriptor instead of reconstructing its
        -- field path from the Lua table returned by MakeAttribute.
        local effect=self.effects[field]
        local assetName='GE_MA_'..field..'_1_Override'
        local effectPath='/PBZCombatAsset/Config/AttributesModifyEffect/'..assetName..'.'..assetName
        if not U.valid(effect) then
            effect=StaticFindObject(effectPath)
            if not U.valid(effect) then local loaded,value=pcall(LoadAsset,effectPath);if loaded then effect=value end end
            if not U.valid(effect) then return nil,nil,'原生属性效果未加载: '..field end
            local named,full=pcall(function()return effect:GetFullName()end)
            if not named or type(full)~='string' or full:match('^%S+ (/.+)$')~=effectPath then return nil,nil,'原生属性效果路径不匹配' end
            self.effects[field]=effect
        end
        local modifiers=U.array(U.field(effect,'Modifiers'))
        if not modifiers or #modifiers~=1 then return nil,nil,'原生属性效果的修饰项不唯一: '..field end
        local attr=U.struct(modifiers[1],'Attribute')
        -- Use the exact UFunction: library:IsValid(attr) would hit the Lua UObject
        -- validity method instead of checking the FGameplayAttribute itself.
        local validCall,validAttribute=pcall(function()return check(abilities,attr)end)
        local actual=text(U.struct(attr,'AttributeName'))
        if not validCall or validAttribute~=true then
            return nil,nil,'属性描述无效: '..field..' kind='..U.kind(attr)..' cached_name='..tostring(actual)
        end
        local named,debugName=pcall(function()return abilities:GetDebugStringFromGameplayAttribute(attr)end)
        debugName=named and text(debugName) or nil
        if not debugName or (debugName~=field and debugName:match('([^.:/ ]+)$')~=field) then
            return nil,nil,'属性名称未确认: '..field..' native='..tostring(debugName)..' cached='..tostring(actual)
        end
        local read,current=pcall(function()return utils:GetCharacterAttributeValue(actor,attr)end)
        local reflected=U.struct(U.field(set,field),'CurrentValue')
        if not read or not Stats.close(current,reflected) then return nil,nil,'属性原生读取与实例字段不一致: '..field end
        return attr,utils
    end
    -- The set's own field, for the attributes without a native effect: in place, else the whole struct.
    local function writeDirect(actor,field,value)
        if not allowed[field] then return false,'属性不在已核对的修改范围' end
        local set,why=attributeSet(actor);if not set then return false,why end
        local data=U.field(set,field)
        if U.kind(data)~='UScriptStruct' and U.kind(data)~='table' then return false,'属性字段不可写: '..field..' kind='..U.kind(data) end
        local ok=pcall(function()data.BaseValue=value;data.CurrentValue=value end)
        local now=ok and self:read(actor,field)
        if now and Stats.close(now.base,value) and Stats.close(now.current,value) then return true end
        if not U.valid(set) then return false,'写入前对象失效' end
        local err;ok,err=pcall(function()set[field]={BaseValue=value,CurrentValue=value}end)
        return ok,not ok and tostring(err) or nil
    end
    function self:via(field)return Stats.direct[field] and 'field' or 'effect' end
    function self:writeBase(actor,field,value)
        if not finite(value) then return false,'非有限属性值' end
        if Stats.direct[field] then return writeDirect(actor,field,value) end
        local attr,utils,why=descriptor(actor,field);if not attr then return false,why end
        if not U.valid(actor) or not U.valid(utils) then return false,'写入前对象失效' end
        -- EGameplayModOp.Override == 3 in this game's dumped enum.
        local ok,err=pcall(function()utils:ModifyCharacterAttributeValue(actor,attr,3,value)end)
        return ok,not ok and tostring(err) or nil
    end
    -- The native getter; the attributes without a native effect have no descriptor, so their field is read.
    function self:nativeValue(actor,field)
        if Stats.direct[field] then local entry,why=self:read(actor,field);return entry and entry.current,why end
        local attr,utils,why=descriptor(actor,field);if not attr then return nil,why end
        if not U.valid(actor) or not U.valid(utils) then return nil,'读回前对象失效' end
        local ok,value=pcall(function()return utils:GetCharacterAttributeValue(actor,attr)end)
        if not ok or not finite(value) then return nil,'原生属性读回失败: '..field end
        return value
    end
    return self
end
return Stats
