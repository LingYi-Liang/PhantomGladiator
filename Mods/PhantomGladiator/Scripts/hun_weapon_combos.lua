-- Ground light-attack chains (IA_AttackL_Press, priority 1) of the weapons hun_weapons.lua slots, exported by
-- hun-npc-20261117/weapon-moves/export_combos.py from the decoded input maps. Weapon-specific combos come before
-- the generic AIM_Hun_LightAttack ones, the order the lookup tries them. Air, sprint and jump entries are left out.
return {
    Tang={
        sources={'/PBZCombatAsset/ActorData/Players/Hun/Weapon/Tang/AIM_Tang_LightAttack','/PBZCombatAsset/ActorData/Players/Hun/InputMap/AIM_Hun_LightAttack'},
        actions={
            {tag='Ability.Action.Hun.Light.A.Normal',req={'CharacterState.Space.Ground','CharacterState.Armed'},ign={'CharacterState.Native.Attitude.Sprinting'}}, -- 地面普攻1
            {tag='Ability.Action.Hun.Light.A.Draw',req={'CharacterState.Space.Ground'},ign={'CharacterState.Armed','CharacterState.Native.Attitude.Sprinting'}}, -- 地面普攻1 拔刀
        },
        combos={
            {tag='Ability.Action.Hun.Light.AAAAA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.AAAA'},ign={}}, -- 地面普攻5
            {tag='Ability.Action.Hun.Light.Tang.AAAAAA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.AAAAA','CharacterState.WeaponUpgrade.Tang.Combo_01'},ign={}}, -- 升级地面普攻6
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.A.Normal'},ign={}}, -- 地面普攻2
            {tag='Ability.Action.Hun.Light.AAA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.AA'},ign={}}, -- 地面普攻3
            {tag='Ability.Action.Hun.Light.AAAA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.AAA'},ign={}}, -- 地面普攻4
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.ADash.Normal'},ign={}}, -- 冲刺-地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Weapon.Switch.Normal'},ign={}}, -- 切武器 地面-地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.A.Draw'},ign={}}, -- 拔刀 接 地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.ADash.Draw'},ign={}}, -- 冲刺 拔刀-地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Weapon.Switch.Dash'},ign={}}, -- 切武器 拔刀 - 地面普攻2
            {tag='Ability.Action.Hun.Light.A.Normal',req={'CharacterState.Space.Ground','CharacterState.Armed','Ability.Action.Stance'},ign={}}, -- 拼刀普攻
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','CharacterState.Armed','Ability.Action.Hun.PerfectDodge'},ign={}}, -- 完美闪避 普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'Ability.Action.Hun.SimpleExecution','CharacterState.Space.Ground'},ign={}}, -- 小处决 普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Execution'},ign={}}, -- 处决 普攻2
            {tag='Ability.Action.Hun.Light.A.Normal',req={'CharacterState.Space.Ground','CharacterState.Armed','Ability.Action.HoldDeflect'},ign={}}, -- QTE拼刀 普攻
        },
    },
    DualHook={
        sources={'/PBZCombatAsset/ActorData/Players/Hun/Weapon/DualHook/AIM_DualHook_LightAttack','/PBZCombatAsset/ActorData/Players/Hun/InputMap/AIM_Hun_LightAttack'},
        actions={
            {tag='Ability.Action.Hun.Light.A.Normal',req={'CharacterState.Space.Ground','CharacterState.Armed'},ign={'CharacterState.Native.Attitude.Sprinting'}}, -- 地面普攻1
            {tag='Ability.Action.Hun.Light.A.Draw',req={'CharacterState.Space.Ground'},ign={'CharacterState.Armed','CharacterState.Native.Attitude.Sprinting'}}, -- 地面普攻1 拔刀
        },
        combos={
            {tag='Ability.Action.Hun.Light.AAAAA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.AAAA'},ign={}}, -- 地面普攻5
            {tag='Ability.Action.Hun.Light.AAAAAA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.AAAAA'},ign={}}, -- 地面普攻6
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','CharacterState.AbilityState.DualHook.DB.Light'},ign={'CharacterState.AbilityState.Stance.HoldingStanceKey'}}, -- DB.L -> AA
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','CharacterState.AbilityState.DualHook.DB.Heavy'},ign={'CharacterState.AbilityState.Stance.HoldingStanceKey'}}, -- DB.H -> AA
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.DualHook.Pursure'},ign={}}, -- APursure -> AA
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.A.Normal'},ign={}}, -- 地面普攻2
            {tag='Ability.Action.Hun.Light.AAA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.AA'},ign={}}, -- 地面普攻3
            {tag='Ability.Action.Hun.Light.AAAA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.AAA'},ign={}}, -- 地面普攻4
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.ADash.Normal'},ign={}}, -- 冲刺-地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Weapon.Switch.Normal'},ign={}}, -- 切武器 地面-地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.A.Draw'},ign={}}, -- 拔刀 接 地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.ADash.Draw'},ign={}}, -- 冲刺 拔刀-地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Weapon.Switch.Dash'},ign={}}, -- 切武器 拔刀 - 地面普攻2
            {tag='Ability.Action.Hun.Light.A.Normal',req={'CharacterState.Space.Ground','CharacterState.Armed','Ability.Action.Stance'},ign={}}, -- 拼刀普攻
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','CharacterState.Armed','Ability.Action.Hun.PerfectDodge'},ign={}}, -- 完美闪避 普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'Ability.Action.Hun.SimpleExecution','CharacterState.Space.Ground'},ign={}}, -- 小处决 普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Execution'},ign={}}, -- 处决 普攻2
            {tag='Ability.Action.Hun.Light.A.Normal',req={'CharacterState.Space.Ground','CharacterState.Armed','Ability.Action.HoldDeflect'},ign={}}, -- QTE拼刀 普攻
        },
    },
    ZhanMa={
        sources={'/PBZCombatAsset/ActorData/Players/Hun/Weapon/ZhanMaBlade/AIM_ZhanMa_LightAttack','/PBZCombatAsset/ActorData/Players/Hun/InputMap/AIM_Hun_LightAttack'},
        actions={
            {tag='Ability.Action.Hun.Light.A.Normal',req={'CharacterState.Space.Ground','CharacterState.Armed'},ign={'CharacterState.Native.Attitude.Sprinting'}}, -- 地面普攻1
            {tag='Ability.Action.Hun.Light.A.Draw',req={'CharacterState.Space.Ground'},ign={'CharacterState.Armed','CharacterState.Native.Attitude.Sprinting'}}, -- 地面普攻1 拔刀
        },
        combos={
            {tag='Ability.Action.Hun.Light.ZhanMa.SA',req={'Ability.Action.Hun.Heavy','CharacterState.Space.Ground'},ign={}}, -- SA
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.A.Normal'},ign={}}, -- 地面普攻2
            {tag='Ability.Action.Hun.Light.AAA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.AA'},ign={}}, -- 地面普攻3
            {tag='Ability.Action.Hun.Light.AAAA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.AAA'},ign={}}, -- 地面普攻4
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.ADash.Normal'},ign={}}, -- 冲刺-地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Weapon.Switch.Normal'},ign={}}, -- 切武器 地面-地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.A.Draw'},ign={}}, -- 拔刀 接 地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Light.ADash.Draw'},ign={}}, -- 冲刺 拔刀-地面普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Hun.Weapon.Switch.Dash'},ign={}}, -- 切武器 拔刀 - 地面普攻2
            {tag='Ability.Action.Hun.Light.A.Normal',req={'CharacterState.Space.Ground','CharacterState.Armed','Ability.Action.Stance'},ign={}}, -- 拼刀普攻
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','CharacterState.Armed','Ability.Action.Hun.PerfectDodge'},ign={}}, -- 完美闪避 普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'Ability.Action.Hun.SimpleExecution','CharacterState.Space.Ground'},ign={}}, -- 小处决 普攻2
            {tag='Ability.Action.Hun.Light.AA',req={'CharacterState.Space.Ground','Ability.Action.Execution'},ign={}}, -- 处决 普攻2
            {tag='Ability.Action.Hun.Light.A.Normal',req={'CharacterState.Space.Ground','CharacterState.Armed','Ability.Action.HoldDeflect'},ign={}}, -- QTE拼刀 普攻
        },
    },
}
