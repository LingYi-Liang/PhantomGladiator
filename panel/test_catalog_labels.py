"""Offline label tests. No game access, asset loads or spawn-policy changes."""
import copy
import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("catalog_labels", Path(__file__).with_name("catalog_labels.py"))
labels = importlib.util.module_from_spec(spec)
spec.loader.exec_module(labels)


def row(name, parent="/Script/ProjectPBZ.PBZCharacter_NPC", **extra):
    value = {"id": "/Game/Combat/" + name + "." + name + "_C", "class_path": "/Game/Combat/" + name + "." + name + "_C",
             "name": name, "spawnable": "1", "reason": "native_parent=/Script/CoreUObject.Class'" + parent + "'"}
    value.update(extra)
    return value


class CatalogLabelTests(unittest.TestCase):
    def test_working_translation_keeps_internal_identifier(self):
        result = labels.decorate_row(row("BP_Monster_MaleThug_TwinAxe"))
        self.assertIn("男性匪徒", result["display_name"])
        self.assertIn("双斧", result["display_name"])
        self.assertIn("BP_Monster_MaleThug_TwinAxe", result["display_name"])
        self.assertEqual(result["name_source"], "working_translation")
        self.assertEqual(result["category"], "普通怪物（级别待核）")

    def test_boss_elite_name_and_hp_never_establish_rank(self):
        for name in ("BP_Monster_MBoss", "BP_Monster_Dog_Elite", "BP_Monster_Normal"):
            result = labels.decorate_row(row(name, hp=999999, category="BOSS"))
            self.assertEqual(result["category"], "普通怪物（级别待核）")

    def test_exact_verified_codex_evidence_can_supply_official_name_and_boss(self):
        value = row("BP_Monster_Example")
        result = labels.decorate_row(value, {"class_path": value["class_path"], "source": "FCodexEnemyRow",
                                            "verified": True, "zh_name": "测试图鉴原名", "is_boss": True, "enemy_type": 5})
        self.assertEqual(result["display_name"], "测试图鉴原名")
        self.assertEqual(result["category"], "BOSS")
        self.assertEqual(result["name_source"], "game_codex")
        self.assertEqual(result["species_label"], "人偶类")

    def test_wrong_class_or_unverified_evidence_cannot_rename_or_rank(self):
        value = row("BP_Monster_Example")
        for evidence in ({"class_path": "/Other", "source": "FCodexEnemyRow", "verified": True},
                         {"class_path": value["class_path"], "source": "FCodexEnemyRow", "verified": False}):
            evidence.update(zh_name="不能使用的名字", is_boss=True)
            result = labels.decorate_row(value, evidence)
            self.assertNotEqual(result["display_name"], evidence["zh_name"])
            self.assertEqual(result["category"], "普通怪物（级别待核）")

    def test_non_boss_is_not_minion_and_species_is_not_rank(self):
        value = row("BP_Monster_Example")
        result = labels.decorate_row(value, {"class_path": value["class_path"], "source": "FCodexEnemyRow",
                                            "verified": True, "is_boss": False, "enemy_type": 4, "role": "minion"})
        self.assertEqual(result["category"], "普通怪物（级别待核）")
        self.assertIn("non_boss_verified", result["traits"])

    def test_minion_needs_an_independent_verified_role_field(self):
        value = row("BP_Monster_Example")
        evidence = {"class_path": value["class_path"], "source": "game_character_data", "verified": True, "role": "minion"}
        self.assertEqual(labels.decorate_row(value, evidence)["category"], "普通怪物（级别待核）")
        evidence["role_source_field"] = "explicit_fixture_role_field"
        self.assertEqual(labels.decorate_row(value, evidence)["category"], "小兵")

    def test_explicit_special_modes_are_quarantined_labels(self):
        for name in ("BP_Monster_Hun_Summon_Double", "BP_Monster_QiShu_Bing_Phantom",
                     "BP_Monster_Danghui_StuntDouble", "BP_Monster_JingYe_HumanoidTest",
                     "BP_Monster_LengTu_Preview", "BP_Monster_ZhengDaoRenShi_Execute",
                     "BP_Monster_Foo_NPCHelper", "BP_Monster_Foo_Stand", "BP_Monster_Foo_Unused"):
            result = labels.decorate_row(row(name))
            self.assertEqual(result["category"], "特殊实体", name)
            self.assertIn("quarantine_review", result["traits"])

    def test_npc_parent_alone_does_not_make_story_npc_a_combat_unit(self):
        result = labels.decorate_row(row("BP_NPC_Ending_JingYe"))
        self.assertEqual(result["category"], "特殊实体")
        self.assertIn("story_variant", result["traits"])

    def test_non_npc_assets_and_base_templates_stay_special(self):
        self.assertEqual(labels.decorate_row(row("BP_Monster_Sword", "/Script/PBZCombatAsset.WeaponActorBase"))["category"], "特殊实体")
        self.assertIn("base_template", labels.decorate_row(row("BP_Monster_EMei_Base_Sacrifice"))["traits"])
        self.assertIn("base_template", labels.decorate_row(row("BP_RenewalNPC"))["traits"])

    def test_unknown_proper_names_are_not_invented_as_official_chinese(self):
        result = labels.decorate_row(row("BP_Monster_GuWanYue"))
        self.assertIn("GuWanYue", result["display_name"])
        self.assertEqual(result["name_source"], "working_translation_partial")
        self.assertIn("official_name_unavailable", result["traits"])

    def test_special_variant_is_not_promoted_by_boss_evidence(self):
        value = row("BP_Monster_Example_Summon")
        result = labels.decorate_row(value, {"class_path": value["class_path"], "source": "FCodexEnemyRow", "verified": True, "is_boss": True})
        self.assertEqual(result["category"], "特殊实体")

    def test_does_not_modify_input_or_return_spawn_safety(self):
        value = row("BP_Monster_Dog", spawnable="0")
        before = copy.deepcopy(value)
        result = labels.decorate_row(value)
        self.assertEqual(value, before)
        self.assertNotIn("spawnable", result)
        self.assertNotIn("safe", result)

    def test_current_codex_tsv_schema_and_string_booleans(self):
        value = row("BP_Monster_Example")
        evidence = {"class_path": value["class_path"], "source": "game_codex",
                    "zh_name": "测试图鉴名称", "is_boss": "true", "enemy_type": "5"}
        result = labels.decorate_row(value, evidence)
        self.assertEqual(result["display_name"], evidence["zh_name"])
        self.assertEqual(result["name_source"], "game_codex")
        self.assertEqual(result["category"], "BOSS")
        self.assertEqual(result["species_label"], "人偶类")
        evidence["is_boss"] = "false"
        self.assertEqual(labels.decorate_row(value, evidence)["category"], "普通怪物（级别待核）")

    def test_codex_name_missing_does_not_claim_official_localization(self):
        value = row("BP_Monster_Dog")
        result = labels.decorate_row(value, {"class_path": value["class_path"], "source": "game_codex",
                                            "zh_name": "", "is_boss": "1", "enemy_type": "1"})
        self.assertEqual(result["name_source"], "working_translation")
        self.assertEqual(result["category"], "BOSS")

    def test_direct_native_boss_base_is_boss_without_granting_spawn_permission(self):
        value = row("BP_Monster_Example_Base", spawnable="0")
        before = copy.deepcopy(value)
        evidence = {"class_path": value["class_path"], "source": "game_codex",
                    "source_detail": "native_codex:FCodexEnemyRow;use_replacement_entry=false;EnemyClass",
                    "zh_name": "原生图鉴名称", "is_boss": "1"}
        result = labels.decorate_row(value, evidence)
        self.assertEqual(result["category"], "BOSS")
        self.assertEqual(result["category_source"], "native_codex_direct_enemy")
        self.assertIn("base_template", result["traits"])
        self.assertIn("基型命名待核，不代表不是敌人", result["trait_labels"])
        self.assertEqual(value, before)
        self.assertNotIn("spawnable", result)

    def test_direct_native_nonboss_base_is_an_enemy_not_automatically_minion(self):
        value = row("BP_Monster_Example_Base", spawnable="0")
        result = labels.decorate_row(value, {
            "class_path": value["class_path"], "source": "game_codex",
            "source_detail": "native_codex:FCodexEnemyRow;EnemyClass", "is_boss": "0",
        })
        self.assertEqual(result["category"], "普通怪物（级别待核）")
        self.assertIn("base_template", result["traits"])
        self.assertIn("non_boss_verified", result["traits"])
        self.assertNotIn("spawnable", result)

    def test_real_direct_ending_and_tutorial_bosses_keep_category_and_variant_traits(self):
        cases = (
            ("BP_Monster_ZuoShang_Ending", "组织冥主：左殇（银发）", "story_variant"),
            ("BP_Monster_ZuoShang_Young_Tutorial", "少年左殇", "test_variant"),
        )
        for name, chinese, trait in cases:
            value = row(name, spawnable="0")
            result = labels.decorate_row(value, {
                "class_path": value["class_path"], "source": "game_codex",
                "source_detail": "native_codex:FCodexEnemyRow;use_replacement_entry=false;EnemyClass",
                "zh_name": chinese, "is_boss": "1",
            })
            self.assertEqual(result["category"], "BOSS", name)
            self.assertEqual(result["display_name"], chinese)
            self.assertIn(trait, result["traits"])
            self.assertIn("boss_verified", result["traits"])
            self.assertEqual(result["category_special"], "特殊BOSS变体（初始化待验证）")
            self.assertNotIn("spawnable", result)

    def test_alias_boss_evidence_does_not_erase_special_variant_category(self):
        value = row("BP_Monster_Example_Phantom")
        result = labels.decorate_row(value, {
            "class_path": value["class_path"], "source": "game_codex",
            "source_detail": "native_codex:FCodexEnemyRow;AliasEnemyClasses;canonical=/Game/Boss.Boss_C",
            "is_boss": "1",
        })
        self.assertEqual(result["category"], "特殊实体")
        self.assertIn("boss_verified", result["traits"])
        self.assertIn("clone_variant", result["traits"])
        self.assertEqual(result["category_special"], "特殊BOSS变体（初始化待验证）")

    def test_bare_or_unmatched_provenance_cannot_override_a_base_name(self):
        value = row("BP_Monster_Example_Base")
        for detail in ("game_codex", "untrusted;EnemyClass",
                       "native_codex:FCodexEnemyRow;AliasEnemyClasses;canonical=UNKNOWN"):
            result = labels.decorate_row(value, {
                "class_path": value["class_path"], "source": "game_codex",
                "source_detail": detail, "is_boss": "1",
            })
            self.assertEqual(result["category"], "特殊实体", detail)
        result = labels.decorate_row(value, {
            "class_path": "/Other/Boss.Boss_C", "source": "game_codex",
            "source_detail": "native_codex:FCodexEnemyRow;EnemyClass", "is_boss": "1",
        })
        self.assertEqual(result["category"], "特殊实体")

    def test_exact_parent_suffix_uses_chinese_family_as_working_translation_only(self):
        value = row("BP_Monster_Dog_Summon", spawnable="0")
        parent = "/Game/Combat/BP_Monster_Dog.BP_Monster_Dog_C"
        value["reason"] += ";parent=/Script/Engine.BlueprintGeneratedClass'" + parent + "'"
        evidence = {"class_path": parent, "source": "game_codex", "zh_name": "狂犬", "is_boss": "1"}
        before = copy.deepcopy(value)
        result = labels.decorate_row(value, parent_evidence=evidence)
        self.assertEqual(result["display_name"], "狂犬·召唤变体〔BP_Monster_Dog_Summon〕")
        self.assertEqual(result["name_source"], "derived_working_translation")
        self.assertEqual(result["name_source_label"], "参考图鉴父类的工作译名")
        self.assertEqual(result["category"], "特殊实体")
        self.assertNotIn("boss_verified", result["traits"])
        self.assertIn("official_name_unavailable", result["traits"])
        self.assertEqual(value, before)
        self.assertNotIn("spawnable", result)

    def test_parent_name_with_different_internal_stem_only_adds_a_reference(self):
        value = row("BP_Monster_FlameDog")
        parent = "/Game/Combat/BP_Monster_Dog.BP_Monster_Dog_C"
        value["reason"] += ";parent='" + parent + "'"
        result = labels.decorate_row(value, parent_evidence={
            "class_path": parent, "source": "game_codex", "zh_name": "狂犬", "is_boss": "1",
        })
        self.assertTrue(result["display_name"].startswith("火焰犬〔BP_Monster_FlameDog〕"))
        self.assertIn("参考父类族名：狂犬", result["display_name"])
        self.assertEqual(result["category"], "普通怪物（级别待核）")
        self.assertNotIn("boss_verified", result["traits"])

    def test_direct_child_name_always_precedes_a_parent_reference(self):
        value = row("BP_Monster_Dog_Summon")
        parent = "/Game/Combat/BP_Monster_Dog.BP_Monster_Dog_C"
        value["reason"] += ";parent='" + parent + "'"
        result = labels.decorate_row(value,
            {"class_path": value["class_path"], "source": "game_codex", "zh_name": "子类图鉴原名", "is_boss": "0"},
            {"class_path": parent, "source": "game_codex", "zh_name": "狂犬", "is_boss": "1"})
        self.assertEqual(result["display_name"], "子类图鉴原名")
        self.assertEqual(result["name_source"], "game_codex")
        self.assertNotIn("parent_codex_name_reference", result["traits"])

    def test_parent_reference_requires_exact_unambiguous_original_parent_metadata(self):
        parent = "/Game/Combat/BP_Monster_Dog.BP_Monster_Dog_C"
        evidence = {"class_path": parent, "source": "game_codex", "zh_name": "狂犬", "is_boss": "1"}
        reasons = (
            "native_parent='" + parent + "'",
            "parent='" + parent + "Extra'",
            "parent='" + parent + "';parent='" + parent + "'",
            "parent='/Wrong/Dog.Dog_C'",
            "parent=prefix " + parent,
            "parent='/Game/../Combat/BP_Monster_Dog.BP_Monster_Dog_C'",
        )
        for reason in reasons:
            value = row("BP_Monster_Dog_Summon", reason=reason, parent_class_path=parent)
            self.assertNotEqual(labels.decorate_row(value, parent_evidence=evidence)["name_source"],
                                "derived_working_translation", reason)
        value = row("BP_Monster_Dog_Summon", reason="parent='" + parent + "'")
        self.assertNotEqual(labels.decorate_row(value, parent_evidence=dict(evidence, source="untrusted"))["name_source"],
                            "derived_working_translation")

    def test_clear_descriptive_tokens_are_working_translations(self):
        for token, chinese in (("Teaching", "教学变体"), ("Trap", "陷阱变体"), ("Respawn", "重生变体"),
                               ("Bomb", "爆弹"), ("Eagle", "鹰"), ("Hoe", "锄"), ("TwinHoe", "双锄")):
            result = labels.decorate_row(row("BP_Monster_Dog_" + token))
            self.assertIn(chinese, result["display_name"])
            self.assertEqual(result["name_source"], "working_translation")

    def test_only_exact_hun_proxy_path_is_a_special_character_model(self):
        value = row("BP_Monster_Hun", id=labels.HUN_PROXY_CLASS, class_path=labels.HUN_PROXY_CLASS)
        result = labels.decorate_row(value)
        self.assertEqual(result["category"], "特殊实体")
        self.assertIn("special_character_model", result["traits"])
        self.assertIn("用途待核", result["display_name"])
        self.assertEqual(result["name_source"], "working_translation")
        self.assertNotIn("无血", " ".join(result["trait_labels"]))
        other = labels.decorate_row(row("BP_Monster_Hun"))
        self.assertNotIn("special_character_model", other["traits"])


if __name__ == "__main__":
    unittest.main()
