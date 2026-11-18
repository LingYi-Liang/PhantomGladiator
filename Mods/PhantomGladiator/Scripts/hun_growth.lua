-- BP_RenewalPlayer.GetCombatLevel returns 1 for the original actor config's base values.
-- CT_Talent_Increase{Health,Shachi,Attack} have their final keys at 30. Accessories are applied after spawn.
local Growth={}
local attributes={
    {'Health_Max',850,510}, {'Shachi_Max',400,240}, {'Attack',100,60},
    {'ShachiAttack',100,60}, {'Infliction_Max',1000,0},
}
function Growth.values(overrides)
    -- Player base charge is 100 per bar and one bar. Both permanent IncreaseUltimateCharge effects add one bar.
    local out={UltimateCharge_Max=100,UltimateChargeCount_Max=3,UltimateChargeCount=3,Shachi_Min=0}
    for _,row in ipairs(attributes) do
        local field,base,bonus=table.unpack(row)
        out[field]=base+bonus
        out[field..'_Lv1']=base
    end
    for field,value in pairs(overrides or {})do out[field]=value end
    if not (overrides and overrides.UltimateChargeCount) then out.UltimateChargeCount=out.UltimateChargeCount_Max end
    return out
end
return Growth
