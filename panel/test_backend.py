"""Offline protocol and loopback HTTP tests; never opens the game runtime."""
import mimetypes
import http.client
import importlib.util
import json
import os
import re
from pathlib import Path
import tempfile
import threading
import unittest
import unittest.mock
import sys

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("panel_backend", Path(__file__).with_name("backend.py"))
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)

UNIT = "/PBZCombatAsset/ActorData/Mobs/023_Vessel_Child/BP_Monster_Vessel_Child.BP_Monster_Vessel_Child_C"
NPC_REASON = "native_parent=/Script/CoreUObject.Class'/Script/ProjectPBZ.PBZCharacter_NPC'"
BINDINGS = {"spawn": "F9", "start": "F3", "stop": "F4", "refresh_catalog": "F1",'toggle_camera':'UNBOUND','exit_camera':'UNBOUND','cycle_team':'UNBOUND','toggle_spectator':'UNBOUND','recall_companions':'UNBOUND','toggle_time_stop':'UNBOUND'}


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.policy = self.root / "unit_validation.json"
        fixture_policy=json.loads(backend.DEFAULT_VALIDATION.read_text(encoding='utf-8'))
        fixture_policy['allow_all_catalog']=False
        sword='/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue.BP_Monster_MaleThug_Sword_Blue_C'
        fixture_policy['units']={path:fixture_policy['units'][path] for path in (UNIT,sword)}
        self.policy.write_text(json.dumps(fixture_policy),encoding='utf-8')
        self.bridge = backend.Bridge(self.root / "Runtime", clock=lambda: 100.0, validation_path=self.policy)
        self.game()
        self.write("catalog.tsv", "\t".join(backend.CATALOG_FIELDS) + "\n" +
                   "\t".join((UNIT, "测试单位", "小兵", UNIT, "0", "unknown", "需要加载;" + NPC_REASON)) + "\n")

    def tearDown(self):
        self.bridge.close()
        self.temporary.cleanup()

    def write(self, name, data):
        (self.bridge.runtime / name).write_text(data, encoding="utf-8")

    def spawn(self, **extra):
        return self.bridge.enqueue({"action": "spawn", "unit_id": UNIT, **extra})

    def game(self, session="session-A", ready=True):
        self.write("status.tsv", "schema_version\t1\nheartbeat_unix\t100\n" +
                   (f"game_session\t{session}\n" if session is not None else "") +
                   (f"game_ready\t{str(ready).lower()}\n" if ready is not None else "")+
                   'function_keys_schema\t3\nfunction_keys_epoch\tfixture-keys\nfunction_keys_revision\t0\n')

    def allow_fixture(self, unit_id):
        policy = json.loads(self.policy.read_text(encoding="utf-8"))
        policy["units"][unit_id] = {"class_path": unit_id, "allow_spawn": True,
            "validation_status": "verified_spawn_observation", "evidence": [{"source": "isolated protocol-test fixture only"}]}
        self.policy.write_text(json.dumps(policy, ensure_ascii=False), encoding="utf-8")

    def test_serial_delivery_requires_matching_ack_and_does_not_claim_game_online(self):
        first = self.spawn(count=2)
        second = self.bridge.enqueue({"action": "start"})
        self.bridge.tick()
        original = (self.bridge.runtime / "inbox.tsv").read_text(encoding="utf-8")
        columns = original.rstrip("\n").split("\t")
        self.assertEqual(len(columns), 10)
        self.assertEqual(columns[:5], [str(first["id"]), "spawn", UNIT, "blue", "2"])
        self.assertEqual(columns[-1], "1")
        self.bridge.tick()
        self.assertEqual((self.bridge.runtime / "inbox.tsv").read_text(encoding="utf-8"), original)
        status = self.bridge.status()
        self.assertTrue(status["game"]["online"])
        self.assertEqual(self.bridge._command(first["id"])["status"], "pending")
        self.assertEqual(self.bridge._command(second["id"])["status"], "queued")
        self.write("ack.tsv", "999\tok\tunrelated\t2\n")
        self.bridge.tick()
        self.assertEqual(self.bridge._command(first["id"])["status"], "pending")
        self.write("ack.tsv", f"{first['id']}\tok\t已生成两只\t2\n")
        self.bridge.tick()
        self.assertEqual(self.bridge._command(first["id"])["status"], "succeeded")
        self.assertEqual((self.bridge.runtime / "inbox.tsv").read_text().split("\t")[0], str(second["id"]))
        self.write("ack.tsv", f"{second['id']}\terror\t参赛者不足\t\n")
        self.bridge.tick()
        self.assertEqual(self.bridge._command(second["id"])["status"], "failed")
        self.assertFalse((self.bridge.runtime / "inbox.tsv").exists())

    def test_restart_preserves_inflight_id_and_republishes_only_what_the_game_never_took(self):
        first = self.spawn()
        self.bridge.tick()
        original = (self.bridge.runtime / "inbox.tsv").read_bytes()
        self.bridge.close()
        self.bridge = backend.Bridge(self.root / "Runtime", clock=lambda: 100.0, validation_path=self.policy)
        self.bridge.tick()
        self.assertEqual((self.bridge.runtime / "inbox.tsv").read_bytes(), original)
        # The game journals an id before it runs it: with a record, a missing inbox is never replayed.
        self.write("command-journal.tsv", f"{first['id']}\tstarted\n")
        (self.bridge.runtime / "inbox.tsv").unlink()
        self.bridge.tick()
        self.assertFalse((self.bridge.runtime / "inbox.tsv").exists())
        self.assertEqual(self.bridge._command(first["id"])["status"], "pending")
        self.assertIn("不自动重放", self.bridge.status()["transport_error"])
        # Without one the game never saw it (its publication failed): the same command goes out again.
        (self.bridge.runtime / "command-journal.tsv").unlink()
        self.bridge.tick()
        self.assertEqual((self.bridge.runtime / "inbox.tsv").read_bytes(), original)
        self.assertEqual(self.bridge.status()["transport_code"], "republished")
        self.assertEqual(self.bridge._command(first["id"])["status"], "pending")

    def test_uncertain_ack_is_visible_and_never_becomes_success(self):
        command = self.spawn()
        self.bridge.tick()
        self.write("ack.tsv", f"{command['id']}\tuncertain\t重载发现已开始但未确认\t\n")
        self.bridge.tick()
        self.bridge.tick()
        self.assertEqual(self.bridge._command(command["id"])["status"], "uncertain")
        self.assertFalse((self.bridge.runtime / "inbox.tsv").exists())

    def test_unknown_partial_spawn_count_is_not_fabricated_and_uncertain_message_is_visible(self):
        command = self.spawn()
        self.bridge.tick()
        self.write("ack.tsv", f"{command['id']}\terror\tuncertain: interruption after first spawn\tunknown\n")
        self.bridge.tick()
        result = self.bridge._command(command["id"])
        self.assertEqual(result["status"], "uncertain")
        self.assertIsNone(result["spawned_count"])
        self.assertIsNone(self.bridge.transport_error)
        command = self.spawn()
        self.bridge.tick()
        self.write("ack.tsv", f"{command['id']}\tok\tclaimed success\tunknown\n")
        self.bridge.tick()
        self.assertEqual(self.bridge._command(command["id"])["status"], "pending")
        self.assertIn("observed integer", self.bridge.transport_error)

    def test_select_unit_uses_the_same_validated_fields_without_reporting_a_spawn(self):
        command = self.bridge.enqueue({"action": "select_unit", "unit_id": UNIT, "team": "red", "count": 50})
        self.bridge.tick()
        columns = (self.bridge.runtime / "inbox.tsv").read_text().rstrip("\n").split("\t")
        self.assertEqual(columns[1:5], ["select_unit", UNIT, "red", "50"])
        self.write("ack.tsv", f"{command['id']}\tok\tselection saved\t0\n")
        self.bridge.tick()
        self.assertEqual(self.bridge._command(command["id"])["spawned_count"], 0)
        with self.assertRaises(backend.ValidationError):
            self.bridge.enqueue({"action": "select_unit", "unit_id": "arbitrary/path"})

    def test_second_dispatcher_for_the_same_runtime_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "已有面板后端"):
            backend.Bridge(self.bridge.runtime)
        command = self.spawn()
        self.bridge.tick()
        self.assertEqual(self.bridge._command(command["id"])["status"], "pending")

    def test_unit_id_limits_are_utf8_bytes_and_never_exceed_the_lua_inbox(self):
        for unit_id, expected in (("a" * 512, True), ("a" * 513, False), ("怪" * 170, True), ("怪" * 171, False)):
            with self.subTest(byte_length=len(unit_id.encode("utf-8"))):
                self.write("catalog.tsv", "\t".join(backend.CATALOG_FIELDS) + "\n" +
                           "\t".join((unit_id, "单位", "小兵", unit_id, "0", "1", NPC_REASON)) + "\n")
                request = {"action": "spawn", "unit_id": unit_id}
                if expected:
                    self.allow_fixture(unit_id)
                    result = self.bridge.enqueue(request)
                    wire = self.bridge._wire({"id": result["id"], "payload": json.dumps(result["payload"], ensure_ascii=False)})
                    self.assertLessEqual(len(wire.encode("utf-8")), 2048)
                else:
                    with self.assertRaisesRegex(backend.ValidationError, "512 UTF-8"):
                        self.bridge.enqueue(request)
        with self.assertRaises(backend.ValidationError):
            self.bridge._wire({"id": 1, "payload": json.dumps({"action": "configure_keys", "bindings": {"spawn": "a" * 2050}})})

    def test_non_spawn_wire_fields_satisfy_the_lua_fixed_column_parser(self):
        for action in ("start", "stop", "refresh_catalog", "configure_keys", "toggle_spectator", "toggle_stat_match", "dismiss_companions", "recall_companions", "toggle_time_stop"):
            payload = {"action": action}
            if action == "configure_keys":
                payload["bindings"] = BINDINGS
            command = self.bridge.enqueue(payload)
            wire = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])})
            columns = wire.rstrip("\n").split("\t")
            self.assertEqual(len(columns), 16 if action=='configure_keys' else 10)
            self.assertEqual(columns[3:5], ["blue", "1"])

    def test_companion_team_is_accepted_for_summons_and_unit_keys(self):
        command = self.spawn(team="companion")
        columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
        self.assertEqual(columns[1:5], ["spawn", UNIT, "companion", "1"])
        with self.assertRaises(backend.ValidationError):
            self.spawn(team="pet")

    def test_spawn_difficulty_travels_in_the_spawn_key_column(self):
        for difficulty in backend.SPAWN_DIFFICULTIES:
            command = self.bridge.enqueue({"action": "set_spawn_difficulty", "difficulty": difficulty})
            columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
            self.assertEqual(columns[1:6], ["set_spawn_difficulty", "", "blue", "1", difficulty])
            self.assertEqual(len(columns), 10)
        for bad in ({"action": "set_spawn_difficulty"}, {"action": "set_spawn_difficulty", "difficulty": "hard"},
                    {"action": "set_spawn_difficulty", "difficulty": "HANDICAPPED"},
                    {"action": "set_spawn_difficulty", "difficulty": "HARD", "unit_id": UNIT}):
            with self.subTest(request=bad), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue(bad)

    def test_spawn_level_travels_in_the_spawn_and_start_key_columns(self):
        cases = (({"level_mode": "HOME"}, "", "HOME", ""), ({"level_mode": "HERE"}, "", "HERE", ""),
                 ({"level_mode": "CUSTOM", "level": 12}, "", "CUSTOM", "12"),
                 ({"level_mode": "HOME", "level": 9}, "", "HOME", ""),
                 ({"level_mode": "UNIT", "unit_id": "BP_Monster_Thug", "level": 4}, "BP_Monster_Thug", "UNIT", "4"),
                 ({"level_mode": "UNIT", "unit_id": "BP_Monster_Thug"}, "BP_Monster_Thug", "UNIT", ""))
        for request, unit, mode, level in cases:
            with self.subTest(request=request):
                command = self.bridge.enqueue({"action": "set_spawn_level", **request})
                columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
                self.assertEqual(columns[1:7], ["set_spawn_level", unit, "blue", "1", mode, level])
                self.assertEqual(len(columns), 10)
        for bad in ({"action": "set_spawn_level"}, {"action": "set_spawn_level", "level_mode": "home"},
                    {"action": "set_spawn_level", "level_mode": "CUSTOM"},
                    {"action": "set_spawn_level", "level_mode": "CUSTOM", "level": 61},
                    {"action": "set_spawn_level", "level_mode": "CUSTOM", "level": "12"},
                    {"action": "set_spawn_level", "level_mode": "CUSTOM", "level": True},
                    {"action": "set_spawn_level", "level_mode": "UNIT", "level": 3},
                    {"action": "set_spawn_level", "level_mode": "UNIT", "unit_id": UNIT, "level": 3},
                    {"action": "set_spawn_level", "level_mode": "HOME", "unit_id": "BP_Monster_Thug"},
                    {"action": "set_spawn_level", "level_mode": "HOME", "team": "red"}):
            with self.subTest(request=bad), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue(bad)

    def test_home_levels_lists_each_units_places_with_default_pick_and_count(self):
        self.assertEqual(self.bridge.home_levels(), {"units": {}, "count": 0}, "nothing until the mod has written them")
        self.write("home-levels.tsv", "unit\tlevel\tsource\tmap\tpart\tdefault\tpicked\n"
                   "BP_Monster_Thug\t6\tarea\t血色森林\tC\t1\t0\n")
        self.assertEqual(self.bridge.home_levels()["count"], 0, "the earlier test file without counts is not read")
        self.write("home-levels.tsv", "unit\tlevel\tsource\tmap\tpart\tdefault\tpicked\tcount\n"
                   "BP_Monster_Wanderer\t3\tnative\t悲泣溪谷\tC\t1\t0\t3\n"
                   "BP_Monster_Wanderer\t19\tnative\t梅谷湖\tB\t0\t1\t24\n"
                   "BP_Monster_Thug\t6\tarea\t血色森林\tC\t1\t0\t0\n"
                   "BP_Monster_Thug\t70\tarea\t血色森林\tC\t0\t0\t0\n"
                   "BP_Monster_Thug\t5\tstory\t血色森林\t\t0\t0\t0\n"
                   "BP_Monster_Thug\t5\tarea\t血色森林\tB\t0\t0\tmany\n"
                   "../evil\t5\tarea\tX\t\t0\t0\t0\n"
                   "BP_Monster_Intro\t30\tpicked\t\t\t0\t1\t0\n")
        self.assertEqual(self.bridge.home_levels(), {"count": 3, "units": {
            "BP_Monster_Wanderer": {"default": 0, "picked": 1, "options": [
                {"level": 3, "source": "native", "map": "悲泣溪谷", "part": "C", "count": 3},
                {"level": 19, "source": "native", "map": "梅谷湖", "part": "B", "count": 24}]},
            "BP_Monster_Thug": {"default": 0, "picked": None, "options": [
                {"level": 6, "source": "area", "map": "血色森林", "part": "C", "count": 0}]},
            "BP_Monster_Intro": {"default": None, "picked": 0, "options": [
                {"level": 30, "source": "picked", "map": "", "part": "", "count": 0}]}}})

    def test_fun_feature_travels_in_the_spawn_and_start_key_columns(self):
        for feature in backend.FUN_FEATURES:
            for enabled, token in ((True, "ON"), (False, "OFF")):
                command = self.bridge.enqueue({"action": "set_fun_feature", "feature": feature, "enabled": enabled})
                columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
                self.assertEqual(columns[1:7], ["set_fun_feature", "", "blue", "1", feature, token])
                self.assertEqual(len(columns), 10)
        for bad in ({"action": "set_fun_feature", "feature": "SHACHI"}, {"action": "set_fun_feature", "feature": "shachi", "enabled": True},
                    {"action": "set_fun_feature", "feature": "GOD", "enabled": True},
                    {"action": "set_fun_feature", "feature": "DODGE", "enabled": 1},
                    {"action": "set_fun_feature", "feature": "DODGE", "enabled": True, "unit_id": UNIT}):
            with self.subTest(request=bad), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue(bad)

    def test_stat_mode_carries_custom_values_in_a_file_of_their_own(self):
        command = self.bridge.enqueue({"action": "set_stat_mode", "mode": "custom", "values": {"Attack": 120, "Health_Max": 50000.5}})
        columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
        revision = command["payload"]["revision"]
        self.assertRegex(revision, r"^R[0-9A-F]{12}$")
        self.assertEqual(columns[1:8], ["set_stat_mode", "", "blue", "1", "CUSTOM", revision, ""])
        request = (self.bridge.runtime / "stat-custom-request.tsv").read_text(encoding="utf-8")
        self.assertEqual(request, f"StatCustomV1\t{revision}\nHealth_Max\t50000.5\nAttack\t120\n", "fields in the mod's order")
        # Every attribute of the set can be sent, negative multipliers and resistances included.
        everything = {field: -0.5 for field in backend.STAT_FIELDS if field not in backend.STAT_POSITIVE | backend.STAT_NON_NEGATIVE}
        everything.update({field: 2 for field in backend.STAT_POSITIVE | backend.STAT_NON_NEGATIVE})
        command = self.bridge.enqueue({"action": "set_stat_mode", "mode": "custom", "values": everything})
        rows = (self.bridge.runtime / "stat-custom-request.tsv").read_text(encoding="utf-8").splitlines()[1:]
        self.assertEqual([row.split("\t")[0] for row in rows], list(backend.STAT_FIELDS))
        self.assertEqual((len(rows), len(set(backend.STAT_FIELDS))), (227, 227))
        for mode, token in (("game", "GAME"), ("match", "MATCH")):
            command = self.bridge.enqueue({"action": "set_stat_mode", "mode": mode})
            columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
            self.assertEqual(columns[5:7], [token, ""])
        for bad in ({"action": "set_stat_mode", "mode": "all"}, {"action": "set_stat_mode", "mode": "custom"},
                    {"action": "set_stat_mode", "mode": "custom", "values": {}},
                    {"action": "set_stat_mode", "mode": "custom", "values": {"Bogus": 5}},
                    {"action": "set_stat_mode", "mode": "custom", "values": {"Health": 0}},
                    {"action": "set_stat_mode", "mode": "custom", "values": {"Shachi": -1}},
                    {"action": "set_stat_mode", "mode": "custom", "values": {"Health_Max": 0}},
                    {"action": "set_stat_mode", "mode": "custom", "values": {"ShachiAttack": -1}},
                    {"action": "set_stat_mode", "mode": "custom", "values": {"Attack": "120"}},
                    {"action": "set_stat_mode", "mode": "custom", "values": {"Attack": float("nan")}},
                    {"action": "set_stat_mode", "mode": "custom", "values": {"Attack": 2e9}}):
            with self.subTest(request=bad), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue(bad)

    def test_queued_settings_pass_the_recheck_before_delivery(self):
        # tick() validates a stored payload again right before sending it; whatever enqueue added
        # (the custom revision) has to pass that second look, or the game never sees the command.
        for request in ({"action": "set_stat_mode", "mode": "custom", "values": {"Health_Max": 99999, "Attack": 999}},
                        {"action": "set_stat_mode", "mode": "game"},
                        {"action": "set_team_immortal", "team": "red", "enabled": True},
                        {"action": "set_clock_hud", "enabled": True}):
            with self.subTest(request=request):
                command = self.bridge.enqueue(request)
                self.bridge.tick()
                self.assertEqual(self.bridge._command(command["id"])["status"], "pending")
                columns = (self.bridge.runtime / "inbox.tsv").read_text(encoding="utf-8").rstrip("\n").split("\t")
                self.assertEqual(columns[:2], [str(command["id"]), request["action"]])
                if request.get("mode") == "custom":
                    revision = command["payload"]["revision"]
                    self.assertEqual(columns[5:7], ["CUSTOM", revision])
                    request_file = (self.bridge.runtime / "stat-custom-request.tsv").read_text(encoding="utf-8")
                    self.assertTrue(request_file.startswith(f"StatCustomV1\t{revision}\n"), "the file the mod reads names the same revision")
                self.write("ack.tsv", f"{command['id']}\tok\tfixture\t0\n")
                self.bridge.tick()
                self.assertEqual(self.bridge._command(command["id"])["status"], "succeeded")
        for bad in ("R123", "r0123456789AB", "R0123456789AB\n"):
            with self.subTest(revision=bad), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue({"action": "set_stat_mode", "mode": "custom", "values": {"Attack": 1}, "revision": bad})

    def test_stat_settings_read_what_the_mod_saved(self):
        self.assertEqual(self.bridge.stat_settings()["mode"], "game")
        self.write("stat-match-settings.tsv", "StatMatchV1\t1\n")
        self.assertEqual(self.bridge.stat_settings()["mode"], "match")
        self.write("stat-match-settings.tsv", "StatMatchV2\tcustom\nAttack\t120\nHealth_Max\t50000.5\nShield\t3\nBogus\t1\n")
        settings = self.bridge.stat_settings()
        self.assertEqual((settings["mode"], settings["values"]), ("custom", {"Attack": 120, "Health_Max": 50000.5, "Shield": 3}))
        self.assertEqual(len(settings["fields"]), 227)

    def test_boss_combos_switch_travels_as_on_or_off(self):
        for enabled, token in ((True, "ON"), (False, "OFF")):
            command = self.bridge.enqueue({"action": "set_boss_combos", "enabled": enabled})
            self.assertEqual(command["payload"]["enabled"], enabled)
        with self.assertRaises(backend.ValidationError):
            self.bridge.enqueue({"action": "set_boss_combos", "enabled": 1})

    def test_ai_params_travel_in_a_file_and_come_back(self):
        command = self.bridge.enqueue({"action": "set_ai_params", "values": {"近距离进攻概率": 1, "减帧时允许格挡": 0, "受击-正面脱离计数": 3}})
        revision = command["payload"]["revision"]
        columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
        self.assertEqual(columns[1], "set_ai_params")
        self.assertEqual(columns[5], revision)
        rows = (self.bridge.runtime / "ai-params-request.tsv").read_text(encoding="utf-8").splitlines()
        self.assertEqual(rows[0], "AIParamsV1\t" + revision)
        self.assertIn("近距离进攻概率\t1", rows)
        for bad in ({"Bogus": 1}, {"近距离进攻概率": "x"}, {"近距离进攻概率": float("inf")}, {"减帧时允许格挡": 2}, {"受击-正面脱离计数": 1.5}):
            with self.assertRaises(backend.ValidationError):
                self.bridge.enqueue({"action": "set_ai_params", "values": bad})
        self.bridge.enqueue({"action": "set_ai_params", "values": {}})
        self.write("ai-params-settings.tsv", "AIParamsV1\n近距离进攻概率\t0.5\nBogus\t1\n中距离进攻概率\tx\n")
        settings = self.bridge.ai_params()
        self.assertEqual(settings["values"], {"近距离进攻概率": 0.5})
        self.assertEqual(len(settings["fields"]), 65)

    def test_ai_param_lists_agree(self):
        root = Path(__file__).resolve().parent.parent
        lua = (root / "Mods/PhantomGladiator/Scripts/ai_params.lua").read_text(encoding="utf-8")
        self.assertEqual(dict(re.findall(r"\{'([^']+)','(float|bool|int)'\}", lua)), backend.AI_PARAMS)
        js = (root / "panel/prototype/ai-params.js").read_text(encoding="utf-8")
        rows = json.loads(re.search(r"window\.PG_AI_PARAMS = (\[.*\]);", js, re.S).group(1))
        self.assertEqual({r["name"]: r["kind"] for r in rows}, backend.AI_PARAMS)
        for row in rows:
            self.assertEqual(sorted(row["label"]), ["de", "en", "es", "fr", "ja", "zh"], row["name"])
            self.assertTrue(all(row["label"].values()), row["name"])
            self.assertEqual(sorted(row["tip"]), ["de", "en", "es", "fr", "ja", "zh"], row["name"])
            self.assertTrue(all(row["tip"].values()), row["name"])
            self.assertIn(row["unit"], {"prob", "weight", "cm", "s", "count", "switch"}, row["name"])

    def test_clock_hud_travels_in_the_start_key_column(self):
        for enabled, token in ((True, "ON"), (False, "OFF")):
            command = self.bridge.enqueue({"action": "set_clock_hud", "enabled": enabled})
            columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
            self.assertEqual(columns[1:8], ["set_clock_hud", "", "blue", "1", "", token, ""])
        for bad in ({"action": "set_clock_hud"}, {"action": "set_clock_hud", "enabled": "on"},
                    {"action": "set_clock_hud", "enabled": True, "team": "red"}):
            with self.subTest(request=bad), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue(bad)

    def test_execution_camera_travels_in_the_start_key_column(self):
        for enabled, token in ((True, "ON"), (False, "OFF")):
            command = self.bridge.enqueue({"action": "set_execution_camera", "enabled": enabled})
            columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
            self.assertEqual(columns[1:8], ["set_execution_camera", "", "blue", "1", "", token, ""])
        for bad in ({"action": "set_execution_camera"}, {"action": "set_execution_camera", "enabled": 1},
                    {"action": "set_execution_camera", "enabled": False, "unit_id": "BP_Monster_MoTian"}):
            with self.subTest(request=bad), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue(bad)

    def test_companion_executions_travels_in_the_start_key_column(self):
        for enabled, token in ((True, "ON"), (False, "OFF")):
            command = self.bridge.enqueue({"action": "set_companion_executions", "enabled": enabled})
            columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
            self.assertEqual(columns[1:8], ["set_companion_executions", "", "blue", "1", "", token, ""])
        for bad in ({"action": "set_companion_executions"}, {"action": "set_companion_executions", "enabled": 1},
                    {"action": "set_companion_executions", "enabled": False, "unit_id": "BP_Monster_MoTian"}):
            with self.subTest(request=bad), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue(bad)

    def test_team_immortal_travels_in_the_team_and_start_key_columns(self):
        for team in backend.IMMORTAL_TEAMS:
            for enabled, token in ((True, "ON"), (False, "OFF")):
                command = self.bridge.enqueue({"action": "set_team_immortal", "team": team, "enabled": enabled})
                columns = self.bridge._wire({"id": command["id"], "payload": json.dumps(command["payload"])}).rstrip("\n").split("\t")
                self.assertEqual(columns[1:8], ["set_team_immortal", "", team, "1", "", token, ""])
                self.assertEqual(len(columns), 10)
        for bad in ({"action": "set_team_immortal", "team": "blue"}, {"action": "set_team_immortal", "team": "neutral", "enabled": True},
                    {"action": "set_team_immortal", "team": "BLUE", "enabled": True},
                    {"action": "set_team_immortal", "team": "red", "enabled": "true"},
                    {"action": "set_team_immortal", "team": "red", "enabled": True, "count": 2}):
            with self.subTest(request=bad), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue(bad)

    def test_invalid_ack_keeps_command_pending_and_preserves_inbox(self):
        command = self.spawn()
        self.bridge.tick()
        self.write("ack.tsv", "bad\tack\n")
        self.bridge.tick()
        self.assertEqual(self.bridge._command(command["id"])["status"], "pending")
        self.assertIn("four columns", self.bridge.transport_error)
        self.assertTrue((self.bridge.runtime / "inbox.tsv").exists())

    def test_orphan_inbox_is_not_overwritten(self):
        self.write("inbox.tsv", "123\tspawn\towned elsewhere\n")
        command = self.spawn()
        self.bridge.tick()
        self.assertEqual(self.bridge._command(command["id"])["status"], "queued")
        self.assertEqual(self.bridge.transport_code, "orphan_inbox")
        self.assertIn("不在队列里", self.bridge.transport_error)
        self.assertEqual((self.bridge.runtime / "inbox.tsv").read_text(), "123\tspawn\towned elsewhere\n")

    def test_a_finished_commands_inbox_that_cannot_be_deleted_is_retired_on_a_later_tick(self):
        # The game reads the inbox on every tick until it goes, and Windows refuses to delete an open file. Up to
        # v0.38.0 that left the inbox "without an owner" and every later command waited behind it for good.
        first = self.spawn()
        second = self.bridge.enqueue({"action": "start"})
        self.bridge.tick()
        self.write("ack.tsv", f"{first['id']}\tok\t已生成\t1\n")
        inbox = self.bridge.runtime / "inbox.tsv"
        real_unlink = Path.unlink
        def busy(path, *args, **kwargs):
            if path.name == "inbox.tsv":
                raise PermissionError(32, "being used by another process")
            return real_unlink(path, *args, **kwargs)
        with unittest.mock.patch.object(Path, "unlink", busy):
            self.bridge.tick()
            self.assertEqual(self.bridge._command(first["id"])["status"], "succeeded")
            self.assertTrue(inbox.exists())
            self.assertEqual(self.bridge.transport_code, "inbox_locked")
            self.bridge.tick()
            self.assertEqual(self.bridge._command(second["id"])["status"], "queued")
        self.bridge.tick()
        self.assertEqual(inbox.read_text(encoding="utf-8").split("\t")[0], str(second["id"]))
        self.assertEqual(self.bridge._command(second["id"])["status"], "pending")

    def test_a_session_binding_left_alone_is_removed(self):
        self.write("inbox.session.tsv", "77\tsession-A\n")
        command = self.bridge.enqueue({"action": "start"})
        self.bridge.tick()
        self.assertEqual((self.bridge.runtime / "inbox.session.tsv").read_text(encoding="utf-8"), f"{command['id']}\tsession-A\n")

    def test_a_summon_waiting_for_the_map_times_out_and_lets_the_selection_through(self):
        now = [100.0]
        self.bridge.close()
        self.bridge = backend.Bridge(self.root / "Runtime", clock=lambda: now[0], validation_path=self.policy)
        def status(ready):
            self.write("status.tsv", f"schema_version\t1\nheartbeat_unix\t{now[0]}\ngame_session\tsession-A\ngame_ready\t{str(ready).lower()}\n"
                       "function_keys_schema\t3\nfunction_keys_epoch\tfixture-keys\nfunction_keys_revision\t0\n")
        status(False)
        summon = self.spawn()
        select = self.bridge.enqueue({"action": "select_unit", "unit_id": UNIT})
        self.bridge.tick()
        self.assertEqual(self.bridge.transport_code, "waiting_ready")
        self.assertEqual(self.bridge._command(select["id"])["status"], "queued")
        now[0] += backend.READY_WAIT_SECONDS + 1
        status(False)
        self.bridge.tick()
        failed = self.bridge._command(summon["id"])
        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["message"], backend.READY_TIMEOUT)
        self.bridge.tick()
        self.assertEqual(self.bridge._command(select["id"])["status"], "pending")

    def test_a_new_queue_database_numbers_after_the_ids_the_game_remembers(self):
        runtime = self.root / "Fresh"
        runtime.mkdir()
        (runtime / "command-journal.tsv").write_text("41\tstarted\n41\tdone\tok\told\t1\n7\tstarted\nx\tstarted\n", encoding="utf-8")
        fresh = backend.Bridge(runtime, clock=lambda: 100.0, validation_path=self.policy)
        try:
            (runtime / "status.tsv").write_text((self.bridge.runtime / "status.tsv").read_text(encoding="utf-8"), encoding="utf-8")
            self.assertEqual(fresh.enqueue({"action": "start"})["id"], 42)
        finally:
            fresh.close()
        # A database already past them keeps its own numbers.
        self.write("command-journal.tsv", "3\tstarted\n")
        for _ in range(5):
            last = self.bridge.enqueue({"action": "start"})
        self.bridge.close()
        self.bridge = backend.Bridge(self.root / "Runtime", clock=lambda: 100.0, validation_path=self.policy)
        self.assertEqual(self.bridge.enqueue({"action": "start"})["id"], last["id"] + 1)

    def test_clear_queue_drops_waiting_commands_and_every_delivery_file(self):
        first = self.spawn()
        second = self.bridge.enqueue({"action": "start"})
        self.bridge.tick()
        self.assertEqual(self.bridge.clear_queue(), {"cleared": 1, "interrupted": 1, "files_left": []})
        self.assertEqual(self.bridge._command(first["id"])["status"], "uncertain")
        self.assertEqual(self.bridge._command(second["id"])["status"], "failed")
        self.assertEqual(self.bridge._command(second["id"])["message"], backend.CLEARED_PENDING)
        self.assertFalse((self.bridge.runtime / "inbox.tsv").exists())
        self.assertFalse((self.bridge.runtime / "inbox.session.tsv").exists())
        # An inbox of unknown origin goes too, and the queue carries on.
        self.write("inbox.tsv", "123\tspawn\towned elsewhere\n")
        self.assertEqual(self.bridge.clear_queue(), {"cleared": 0, "interrupted": 0, "files_left": []})
        third = self.bridge.enqueue({"action": "start"})
        self.bridge.tick()
        self.assertEqual((self.bridge.runtime / "inbox.tsv").read_text(encoding="utf-8").split("\t")[0], str(third["id"]))
        # A late answer for a cleared command changes nothing.
        self.write("ack.tsv", f"{first['id']}\tok\t已生成\t1\n")
        self.bridge.tick()
        self.assertEqual(self.bridge._command(first["id"])["status"], "uncertain")
        self.assertEqual(self.bridge._command(third["id"])["status"], "pending")

    def test_command_validation_rejects_code_paths_control_chars_and_counts(self):
        invalid = [
            {"action": "exec", "code": "os.execute(...)"}, {"action": []},
            {"action": "spawn", "unit_id": "../outside"},
            {"action": "spawn", "unit_id": UNIT + "\nstart"},
            {"action": "spawn", "unit_id": UNIT, "team": {}},
            {"action": "spawn", "unit_id": UNIT, "count": True},
            {"action": "spawn", "unit_id": UNIT, "count": 101},
            {"action": "spawn", "unit_id": UNIT, "count": 0},
            {"action": "stop", "path": "C:/anything"},
        ]
        for request in invalid:
            with self.subTest(request=request), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue(request)
        self.assertEqual(self.bridge.status()["queue"], [])
        with self.assertRaises(backend.ValidationError):
            self.bridge._path("../outside")

    def test_keys_are_whitelisted_distinct_and_not_reported_applied_before_game_readback(self):
        requested = {**BINDINGS, "spawn": "NUM_ONE"}
        command = self.bridge.enqueue({"action": "configure_keys", "bindings": requested})
        self.bridge.tick()
        columns = (self.bridge.runtime / "inbox.tsv").read_text().rstrip("\n").split("\t")
        self.assertEqual(columns[5:15], [backend.binding_token(requested[name]) for name in backend.BINDING_NAMES])
        self.assertEqual(columns[-1],'3')
        self.assertEqual(self.bridge.keybinds()["requested"], {name:backend.parse_binding(value) for name,value in requested.items()})
        self.assertEqual(self.bridge.keybinds()["active"]["spawn"], None)
        for key in ("F10", "VK_82_MOD_1", "NUM_NOT_A_KEY"):
            with self.subTest(key=key), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue({"action": "configure_keys", "bindings": {**BINDINGS, "spawn": key}})
        with self.assertRaises(backend.ValidationError):
            self.bridge.enqueue({"action": "configure_keys", "bindings": {**BINDINGS, "spawn": "F3"}})
        self.write("status.tsv", "schema_version\t1\nheartbeat_unix\t100\nstate\tready\nkey_spawn\tF9\n")
        self.assertEqual(self.bridge.keybinds()["active"]["spawn"], "F9")
        self.assertEqual(self.bridge.keybinds()["requested"]["spawn"], {'key_code':97,'modifiers':0})
        self.assertEqual(self.bridge._command(command["id"])["status"], "pending")

    def test_toggle_spectator_uses_ack_but_never_invents_the_game_state(self):
        self.write("status.tsv", "schema_version\t1\nheartbeat_unix\t100\ngame_session\tsession-A\ngame_ready\ttrue\nspectator_enabled\tfalse\n")
        command = self.bridge.enqueue({"action": "toggle_spectator"})
        self.bridge.tick()
        columns = (self.bridge.runtime / "inbox.tsv").read_text().rstrip("\n").split("\t")
        self.assertEqual(columns[:5], [str(command["id"]), "toggle_spectator", "", "blue", "1"])
        self.assertEqual(len(columns), 10)
        self.write("ack.tsv", f"{command['id']}\tok\trequest processed\t0\n")
        self.bridge.tick()
        self.assertEqual(self.bridge._command(command["id"])["status"], "succeeded")
        self.assertEqual(self.bridge.status()["game"]["status"]["spectator_enabled"], "false")
        self.write("status.tsv", "schema_version\t1\nheartbeat_unix\t100\nspectator_enabled\ttrue\n")
        self.assertEqual(self.bridge.status()["game"]["status"]["spectator_enabled"], "true")
        with self.assertRaises(backend.ValidationError):
            self.bridge.enqueue({"action": "toggle_spectator", "unit_id": UNIT})
        self.assertIn("F8", self.bridge.status()["allowed_keys"])

    def test_all_ten_function_defaults_are_empty_and_old_fixed_keys_are_available(self):
        state=self.bridge.function_keybinds()
        self.assertTrue(state['available'])
        self.assertEqual(set(state['bindings']),set(backend.BINDING_NAMES))
        self.assertTrue(all(e['key_code']==0 and not e['active'] for e in state['bindings'].values()))
        empty={name:{'key_code':0,'modifiers':0} for name in backend.BINDING_NAMES}
        job=self.bridge.enqueue({'action':'configure_keys','bindings':empty})
        columns=self.bridge._wire({'id':job['id'],'payload':json.dumps(job['payload'])}).strip().split('\t')
        self.assertEqual(columns[5:15],['UNBOUND']*10)
        for code in (113,117,118,119):
            self.assertEqual(self.bridge.enqueue({'action':'configure_unit_key','unit_id':UNIT,'key_code':code,'modifiers':0})['status'],'queued')

    def test_function_conflicts_name_both_actions_and_the_owning_unit(self):
        empty={name:'UNBOUND' for name in backend.BINDING_NAMES}
        with self.assertRaisesRegex(backend.ValidationError,'自由观战.*退出自由观战'):
            self.bridge.enqueue({'action':'configure_keys','bindings':{**empty,'toggle_camera':'F6','exit_camera':'VK_117_MOD_4'}})
        self.write('unit-keybinds.tsv','UnitKeysV1\t1\n'+UNIT+'\t117\t1\n')
        label=self.bridge.catalog()['units'][0]['display_name']
        with self.assertRaises(backend.ValidationError) as failure:
            self.bridge.enqueue({'action':'configure_keys','bindings':{**empty,'toggle_camera':'F6'}})
        self.assertIn(label,str(failure.exception))

    def test_saved_function_binding_blocks_unit_assignment_and_requires_actual_game_readback(self):
        entries={name:{'key_code':117 if name=='toggle_camera' else 0,'modifiers':0} for name in backend.BINDING_NAMES}
        self.write('function-keybinds.tsv','FunctionKeysV2\t3\n'+''.join(f"{name}\t{e['key_code']}\t0\n" for name,e in entries.items()))
        self.assertFalse(self.bridge.function_keybinds()['bindings']['toggle_camera']['active'])
        with self.assertRaisesRegex(backend.ValidationError,'自由观战'):
            self.bridge.enqueue({'action':'configure_unit_key','unit_id':UNIT,'key_code':117,'modifiers':4})
        self.write('status.tsv','schema_version\t1\nheartbeat_unix\t100\ngame_session\tsession-A\ngame_ready\ttrue\nfunction_keys_schema\t3\nfunction_keys_epoch\tnew-keys\nfunction_keys_revision\t3\nkey_toggle_camera\tVK_117_MOD_0\n')
        self.write('function-keybinds-state.tsv','FunctionKeyStateV2\t3\told-keys\ntoggle_camera\t0\tstale error\n')
        state=self.bridge.function_keybinds()
        self.assertTrue(state['bindings']['toggle_camera']['active'])
        self.assertNotEqual(state['bindings']['toggle_camera']['message'],'stale error')

    def test_legacy_function_saves_preserve_four_keys_and_leave_new_actions_empty(self):
        self.write('keybinds.tsv','spawn\tF9\nstart\tF3\nstop\tF4\nrefresh_catalog\tF1\n')
        entries=self.bridge.function_keybinds()['bindings']
        self.assertEqual(entries['spawn']['key_code'],120)
        for action in ('toggle_camera','exit_camera','cycle_team','toggle_spectator','recall_companions','toggle_time_stop'):
            self.assertEqual(entries[action]['key_code'],0)

    def test_an_eight_key_save_from_before_recall_keeps_its_keys_and_leaves_recall_unbound(self):
        # Written by the mod up to v0.38.1: no recall_companions line. It must not count as incomplete.
        self.write('function-keybinds.tsv','FunctionKeysV2\t4\nspawn\t120\t0\nstart\t114\t0\nstop\t115\t0\nrefresh_catalog\t0\t0\n'
                   'toggle_camera\t117\t0\nexit_camera\t118\t0\ncycle_team\t113\t0\ntoggle_spectator\t119\t0\n')
        state=self.bridge.function_keybinds()
        self.assertEqual(state['errors'],[])
        self.assertEqual(state['revision'],4)
        self.assertEqual(state['bindings']['toggle_camera']['key_code'],117)
        self.assertEqual(state['bindings']['recall_companions']['key_code'],0)
        self.assertEqual(state['bindings']['toggle_time_stop']['key_code'],0)
        # A save missing one of the original eight is still incomplete.
        self.write('function-keybinds.tsv','FunctionKeysV2\t5\nspawn\t120\t0\n')
        self.assertTrue(self.bridge.function_keybinds()['errors'])

    def test_recall_key_is_saved_with_the_others_and_blocks_unit_keys(self):
        job=self.bridge.enqueue({'action':'configure_keys','bindings':{**BINDINGS,'recall_companions':'NUM_FIVE'}})
        columns=self.bridge._wire({'id':job['id'],'payload':json.dumps(job['payload'])}).strip().split('\t')
        self.assertEqual(columns[13],'VK_101_MOD_0')
        self.write('function-keybinds.tsv','FunctionKeysV2\t1\n'+''.join(f"{name}\t{101 if name=='recall_companions' else 0}\t0\n" for name in backend.BINDING_NAMES))
        with self.assertRaisesRegex(backend.ValidationError,'召回随从'):
            self.bridge.enqueue({'action':'configure_unit_key','unit_id':UNIT,'key_code':101,'modifiers':0})
        recall=self.bridge.enqueue({'action':'recall_companions'})
        wire=self.bridge._wire({'id':recall['id'],'payload':json.dumps(recall['payload'])}).strip().split('\t')
        self.assertEqual(wire[1:5],['recall_companions','','blue','1'])

    def test_time_stop_key_and_free_camera_settings_travel_in_the_key_columns(self):
        job=self.bridge.enqueue({'action':'configure_keys','bindings':{**BINDINGS,'toggle_time_stop':'P'}})
        columns=self.bridge._wire({'id':job['id'],'payload':json.dumps(job['payload'])}).strip().split('\t')
        self.assertEqual((len(columns),columns[14],columns[-1]),(16,'VK_80_MOD_0','3'))
        stop=self.bridge.enqueue({'action':'toggle_time_stop'})
        wire=self.bridge._wire({'id':stop['id'],'payload':json.dumps(stop['payload'])}).strip().split('\t')
        self.assertEqual(wire[1:5],['toggle_time_stop','','blue','1'])
        cam=self.bridge.enqueue({'action':'set_free_camera','speed':1500,'turn':150,'smooth':25})
        wire=self.bridge._wire({'id':cam['id'],'payload':json.dumps(cam['payload'])}).strip().split('\t')
        self.assertEqual(wire[1:9],['set_free_camera','','blue','1','1500','150','25',''])
        self.assertEqual(len(wire),10)
        for bad in ({'speed':50,'turn':100,'smooth':40},{'speed':900,'turn':400,'smooth':40},{'speed':900,'turn':100,'smooth':-1},
                    {'speed':900.0,'turn':100,'smooth':40},{'speed':900,'turn':100},{'speed':900,'turn':100,'smooth':40,'fov':90}):
            with self.subTest(bad=bad), self.assertRaises(backend.ValidationError):
                self.bridge.enqueue({'action':'set_free_camera',**bad})

    def test_corrupt_function_file_is_reported_without_breaking_panel_status(self):
        (self.bridge.runtime/'function-keybinds.tsv').write_bytes(b'\xff')
        result=self.bridge.status()
        self.assertTrue(result['game']['online'])
        self.assertTrue(result['function_keys']['errors'])

    def test_old_mod_cannot_receive_new_key_configuration_but_exit_commands_keep_the_v1_envelope(self):
        self.write('status.tsv','schema_version\t1\nheartbeat_unix\t100\ngame_session\tsession-A\ngame_ready\tfalse\n')
        with self.assertRaisesRegex(backend.ValidationError,'重载新版Mod'):
            self.bridge.enqueue({'action':'configure_keys','bindings':BINDINGS})
        # A mod of the eight-key schema shows its keys but takes no nine-key configuration.
        self.write('status.tsv','schema_version\t1\nheartbeat_unix\t100\ngame_session\tsession-A\ngame_ready\tfalse\n'
                   'function_keys_schema\t2\nfunction_keys_epoch\told\nfunction_keys_revision\t0\n')
        self.assertFalse(self.bridge.function_keybinds()['available'])
        with self.assertRaisesRegex(backend.ValidationError,'更新并重载新版Mod'):
            self.bridge.enqueue({'action':'configure_keys','bindings':BINDINGS})
        job=self.bridge.enqueue({'action':'exit_camera'})
        wire=self.bridge._wire({'id':job['id'],'payload':json.dumps(job['payload'])}).strip().split('\t')
        self.assertEqual(len(wire),10);self.assertEqual(wire[-1],'1')

    def test_game_online_requires_recent_valid_heartbeat(self):
        (self.bridge.runtime / "status.tsv").unlink()
        self.assertFalse(self.bridge.game_status()["online"])
        for heartbeat, expected in (("99", True), ("80", False), ("101", False), ("nan", False)):
            self.write("status.tsv", f"schema_version\t1\nheartbeat_unix\t{heartbeat}\nstate\tready\n")
            self.assertEqual(self.bridge.game_status()["online"], expected)

    def test_catalog_is_read_as_data_and_bad_rows_do_not_become_units(self):
        result = self.bridge.catalog()
        self.assertEqual(result["units"][0]["id"], UNIT)
        self.assertFalse(result["units"][0]["loaded"])
        self.assertIsNone(result["units"][0]["spawnable"])
        with (self.bridge.runtime / "catalog.tsv").open("a", encoding="utf-8") as stream:
            stream.write("bad\trow\n")
        self.assertEqual(self.bridge.catalog()["total"], 1)
        self.assertTrue(self.bridge.catalog()["errors"])
        self.write("catalog.tsv", "wrong\theader\n")
        self.assertFalse(self.bridge.status()["catalog"]["available"])

    def test_observed_abilities_weapons_bullets_and_components_are_not_unit_rows(self):
        # Names and native parents were observed in a real registry export.
        # They are regression inputs only; production always reads the game TSV.
        observed = [
            ("GA_HuaShan_RedTroop_BigBro_Subtitles", "/Script/SGameCombatSystem.SGameGameplayAbility", "/PBZCombatAsset/ActorData/Mobs/035_HuaShan/Abilities/RedTroop"),
            ("BP_Weapon_MBoss_Sword", "/Script/PBZCombatAsset.WeaponActorBase", "/PBZCombatAsset/ActorData/Mobs/012_MBoss/Weapon"),
            ("BP_Weapon_MBoss_Guillotine", "/Script/PBZCombatAsset.WeaponActorBase_NoSkeletalMesh", "/PBZCombatAsset/ActorData/Mobs/012_MBoss/Weapon"),
            ("BP_Monster_ChiLian_Snake_Base", "/Script/PBZCombatAsset.PBZ_ProjectileBullet", "/PBZCombatAsset/ActorData/Mobs/063_ChiLian_P1"),
            ("BP_BulletEvent_MBossExecutionBullet", "/Script/SGameCombatSystem.BulletEventBase", "/PBZCombatAsset/ActorData/Mobs/012_MBoss/GameplayEffects"),
            ("BP_Monster_GuiChai_Red_SnapPoint_01", "/Script/Engine.Actor", "/PBZCombatAsset/ActorData/Mobs/069_GuiChai_Red/Setup"),
            ("BP_NPCBehaviorComponent", "/Script/Engine.ActorComponent", "/Game/PBZContent/Blueprint/Character/NPC/Components"),
        ]
        rows = ["\t".join(backend.CATALOG_FIELDS)]
        for name, native, prefix in observed:
            path = f"{prefix}/{name}.{name}_C"
            reason = f"name_candidate;native_parent=/Script/CoreUObject.Class'{native}';registry_coverage_unknown"
            rows.append("\t".join((path, name, "BOSS", path, "1", "1", reason)))
        original = "\n".join(rows) + "\n"
        self.write("catalog.tsv", original)
        result = self.bridge.catalog()
        self.assertEqual(result["total"], 0)
        self.assertEqual(result["excluded_non_units"], 7)
        self.assertEqual(self.bridge.status()["catalog"]["excluded_non_units"], 7)
        self.assertEqual((self.bridge.runtime / "catalog.tsv").read_text(encoding="utf-8"), original)
        for name, _, prefix in observed:
            with self.assertRaises(backend.ValidationError):
                self.bridge.enqueue({"action": "spawn", "unit_id": f"{prefix}/{name}.{name}_C"})

    def test_native_parent_parser_is_exact_and_never_guesses_from_a_monster_name(self):
        self.assertEqual(backend.native_parent_from_reason(NPC_REASON), backend.NPC_NATIVE_PARENT)
        self.assertEqual(backend.native_parent_from_reason("native_parent=/Script/Engine.Actor"), "/Script/Engine.Actor")
        self.assertEqual(backend.native_parent_from_reason('native_parent=Class"/Script/Engine.Actor"'), "/Script/Engine.Actor")
        self.assertIsNone(backend.native_parent_from_reason("parent=/Script/Engine.Actor;name=BP_Monster_Boss"))
        self.assertIsNone(backend.native_parent_from_reason("native_parent=/Script/Engine.ActorSuffix extra"))
        self.assertIsNone(backend.native_parent_from_reason(NPC_REASON + ";native_parent=/Script/Engine.Actor"))
        path = "/Regression/BP_Monster_Boss.BP_Monster_Boss_C"
        for metadata in ("name_candidate", "native_parent=/Script/Custom.ActorComponentSuffix", "native_parent=bad-quoted-path"):
            self.write("catalog.tsv", "\t".join(backend.CATALOG_FIELDS) + "\n" +
                       "\t".join((path, "BP_Monster_Boss", "BOSS", path, "1", "1", metadata)) + "\n")
            result = self.bridge.catalog()
            self.assertEqual(result["total"], 1)
            self.assertEqual(result["excluded_non_units"], 0)
            self.assertFalse(result["units"][0]["spawnable"])
            self.assertIn("unknown", result["units"][0]["reason"])
            with self.assertRaises(backend.ValidationError):
                self.bridge.enqueue({"action": "spawn", "unit_id": path})

    def test_npc_base_is_disabled_and_concrete_child_needs_separate_spawn_validation(self):
        base = "/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Base.BP_Monster_MaleThug_Base_C"
        child = "/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_BigShield.BP_Monster_MaleThug_BigShield_C"
        rows = ["\t".join(backend.CATALOG_FIELDS)]
        for path, name, extra in ((base, "BP_Monster_MaleThug_Base", ""),
                                  (child, "BP_Monster_MaleThug_BigShield", f";parent=/Script/Engine.BlueprintGeneratedClass'{base}'")):
            rows.append("\t".join((path, name, "怪物", path, "0", "1", NPC_REASON + extra)))
        original = "\n".join(rows) + "\n"
        self.write("catalog.tsv", original)
        result = self.bridge.catalog()
        self.assertEqual(result["total"], 2)
        first, second = result["units"]
        self.assertEqual((first["id"], first["name"], first["class_path"]), (base, "BP_Monster_MaleThug_Base", base))
        self.assertFalse(first["spawnable"])
        self.assertIn("基类不可召唤", first["reason"])
        self.assertEqual((second["id"], second["name"], second["class_path"]), (child, "BP_Monster_MaleThug_BigShield", child))
        self.assertFalse(second["spawnable"])
        self.assertEqual(second["validation_status"], "unverified")
        self.assertEqual(result["excluded_non_units"], 0)
        with self.assertRaises(backend.ValidationError):
            self.bridge.enqueue({"action": "spawn", "unit_id": base})
        with self.assertRaises(backend.ValidationError):
            self.bridge.enqueue({"action": "spawn", "unit_id": child})
        self.allow_fixture(child)
        self.assertEqual(self.bridge.enqueue({"action": "spawn", "unit_id": child})["status"], "queued")
        self.assertEqual((self.bridge.runtime / "catalog.tsv").read_text(encoding="utf-8"), original)

    def test_shipped_policy_separates_exact_baseline_and_unverified_native_trials(self):
        policy = json.loads(backend.DEFAULT_VALIDATION.read_text(encoding="utf-8"))
        sword = '/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue.BP_Monster_MaleThug_Sword_Blue_C'
        self.assertEqual(len(policy['units']),177)
        self.assertIn(UNIT,policy['units']);self.assertIn(sword,policy['units'])
        self.assertTrue(policy['units'][sword]['combat_validated'])
        flame='/PBZCombatAsset/ActorData/Mobs/005_ModDog/BP_Monster_FlameDog.BP_Monster_FlameDog_C'
        self.assertNotIn(flame,policy['units'])
        for path,entry in policy['units'].items():
            if path in (UNIT,sword):continue
            self.assertEqual((entry['class_path'],entry['validation_status'],entry['max_count'],entry['max_live']),(path,'controlled_test',1,2))
            self.assertFalse(entry.get('combat_validated',False))
        self.assertFalse(policy["units"][UNIT]["combat_validated"])
        result = self.bridge.catalog()["units"][0]
        self.assertEqual(result["validation_status"], "verified_spawn_observation")
        other = UNIT.replace("BP_Monster_Vessel_Child", "BP_Monster_Vessel_Other")
        with (self.bridge.runtime / "catalog.tsv").open("a", encoding="utf-8") as stream:
            stream.write("\t".join((other, "Other NPC", "怪物", other, "1", "1", NPC_REASON)) + "\n")
        rows = self.bridge.catalog()["units"]
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[1]["validation_status"], "unverified")
        self.assertFalse(rows[1]["spawnable"])
        self.assertIn("未验证，暂不可直接召唤", rows[1]["reason"])
        for action in ("spawn", "select_unit"):
            with self.assertRaises(backend.ValidationError):
                self.bridge.enqueue({"action": action, "unit_id": other})

    def test_controlled_ordinary_baseline_limits_batch(self):
        sword = '/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue.BP_Monster_MaleThug_Sword_Blue_C'
        with (self.bridge.runtime / 'catalog.tsv').open('a', encoding='utf-8') as stream:
            stream.write('\t'.join((sword, 'Sword_Blue', '普通怪物', sword, '0', '1', NPC_REASON)) + '\n')
        unit = next(item for item in self.bridge.catalog()['units'] if item['id'] == sword)
        self.assertEqual(unit['validation_status'], 'controlled_test')
        self.assertEqual(unit['max_count'], 1)
        self.assertIn('每次1只', unit['validation_scope'])
        self.assertTrue(unit['spawnable'])
        for action in ('spawn', 'select_unit'):
            with self.assertRaisesRegex(backend.ValidationError, '数量必须为 1'):
                self.bridge.enqueue({'action': action, 'unit_id': sword, 'count': 2})
            self.assertEqual(self.bridge.enqueue({'action': action, 'unit_id': sword, 'count': 1})['status'], 'queued')
        policy = json.loads(self.policy.read_text(encoding='utf-8'))
        policy['units'][sword]['max_live'] = 24
        self.policy.write_text(json.dumps(policy), encoding='utf-8')
        self.assertFalse(next(item for item in self.bridge.catalog()['units'] if item['id'] == sword)['spawnable'])

    def test_inventory_proof_adds_source_fields_without_unlocking_new_roles(self):
        player='/Game/Cinematic/BP_Seq_Actor.BP_Seq_Actor_C'
        native='/Script/Engine.Character'
        self.write('catalog.tsv','\t'.join(backend.CATALOG_FIELDS)+'\n'+'\t'.join((player,'BP_Seq_Actor','角色',player,'0','0','native_parent='+native))+'\n')
        self.write('inventory-report.json',json.dumps({'schema_version':1,'inventory_verified':True,'asset_count':20}))
        proof={'class_path':player,'unit_kind':'character','native_parent':native,
            'inheritance_chain':[player,native],'source':'asset_registry_and_header_inheritance',
            'configured_maps':['Map_A'],'configured_spawner_count':2,'purpose_hint':'cinematic'}
        self.write('unit-evidence.json',json.dumps({'schema_version':1,'scope':'current_mounted_registry','units':[proof]}))
        result=self.bridge.catalog();unit=result['units'][0]
        self.assertEqual(unit['browse_type'],'演出角色候选')
        self.assertEqual(unit['configured_maps'],['Map_A'])
        self.assertEqual(unit['configured_spawner_count'],2)
        self.assertFalse(unit['spawnable'])
        with self.assertRaises(backend.ValidationError):self.bridge.enqueue({'action':'spawn','unit_id':player})
        proof['inheritance_chain']=[player,'/Script/Engine.Actor']
        self.write('unit-evidence.json',json.dumps({'schema_version':1,'scope':'current_mounted_registry','units':[proof]}))
        self.assertNotIn('inheritance_verified',self.bridge.catalog()['units'][0])

    def test_decrypted_directory_is_paginated_readonly_and_requires_verified_counts(self):
        fields=('file_path','container','container_type','entry_index','chunk_id','logical_size','virtual_package')
        records=[('ProjectPBZ/Content/Test/A.uasset','main.utoc','iostore','0','','123','/Game/Test/A'),
                 ('ProjectPBZ/Content/JavaScript/init.js','main.pak','pak','1','','','')]
        self.write('decrypted-directory.tsv','\t'.join(fields)+'\n'+''.join('\t'.join(r)+'\n' for r in records))
        self.write('decrypted-directory-report.json',json.dumps({'schema_version':1,'verified':True,'directory_only':True,'files':2}))
        result=self.bridge.disk_directory(kind='script',limit=1)
        self.assertEqual(result['total'],2);self.assertEqual(result['matched'],1)
        self.assertTrue(result['files'][0]['file_path'].endswith('init.js'))
        self.assertNotIn('search',result['files'][0]);self.assertNotIn('spawnable',result['files'][0])
        self.assertEqual(len(self.bridge.disk_directory(offset=1,limit=1)['files']),1)
        self.assertEqual(self.bridge.disk_directory(query='missing')['matched'],0)
        self.write('decrypted-directory-report.json',json.dumps({'schema_version':1,'verified':False,'directory_only':True,'files':2}))
        with self.assertRaises(backend.ValidationError):self.bridge.disk_directory()

    def test_explicit_all_catalog_mode_opens_candidates_without_claiming_verified(self):
        actor='/Game/Seq/BP_Cinematic.BP_Cinematic_C'
        self.write('catalog.tsv','\t'.join(backend.CATALOG_FIELDS)+'\n'+
            '\t'.join((actor,'BP_Cinematic','角色',actor,'0','0','native_parent=/Script/Engine.Character'))+'\n')
        self.assertFalse(self.bridge.catalog()['units'][0]['spawnable'])
        policy=json.loads(self.policy.read_text(encoding='utf-8'));policy['allow_all_catalog']=True
        self.policy.write_text(json.dumps(policy),encoding='utf-8')
        unit=self.bridge.catalog()['units'][0]
        self.assertTrue(unit['spawnable']);self.assertEqual(unit['validation_status'],'experimental_spawn')
        self.assertEqual(unit['max_count'],backend.MAX_SPAWN_COUNT)
        self.assertEqual(self.bridge.enqueue({'action':'spawn','unit_id':actor,'count':8})['status'],'queued')
        self.assertEqual(self.bridge.enqueue({'action':'clear_neutral'})['status'],'queued')

    def test_unit_key_wire_and_confirmed_mapping_require_current_game_epoch(self):
        request={'action':'configure_unit_key','unit_id':UNIT,'key_code':81,'modifiers':5}
        job=self.bridge.enqueue(request)
        wire=self.bridge._wire({'id':job['id'],'payload':json.dumps(request)}).strip().split('\t')
        self.assertEqual(wire[5:7],['VK_81','MOD_5']);self.assertEqual(len(wire),10)
        for bad in (121,192):
            with self.assertRaises(backend.ValidationError):self.bridge.enqueue({**request,'key_code':bad})
        with self.assertRaises(backend.ValidationError):self.bridge.enqueue({**request,'modifiers':8})
        clear={**request,'key_code':0,'modifiers':0}
        self.assertIn('\tUNBOUND\tMOD_0\t',self.bridge._wire({'id':9,'payload':json.dumps(clear)}))
        self.write('unit-keybinds.tsv','UnitKeysV1\t2\n'+UNIT+'\t81\t5\n')
        self.write('unit-keybinds-state.tsv','UnitKeyStateV1\t2\tnew-epoch\n'+UNIT+'\t1\t\n')
        bindings,errors=self.bridge._unit_shortcuts('old-epoch')
        self.assertEqual(errors,[]);self.assertFalse(bindings[UNIT]['active'])
        bindings,errors=self.bridge._unit_shortcuts('new-epoch')
        self.assertTrue(bindings[UNIT]['active'])

    def test_unit_key_can_carry_its_own_team_and_count(self):
        request={'action':'configure_unit_key','unit_id':UNIT,'key_code':81,'modifiers':0,'team':'red','count':2}
        job=self.bridge.enqueue(request)
        wire=self.bridge._wire({'id':job['id'],'payload':json.dumps(job['payload'])}).strip().split('\t')
        self.assertEqual(wire[3:8],['red','2','VK_81','MOD_0','FIXED']);self.assertEqual(len(wire),10)
        legacy=self.bridge.enqueue({'action':'configure_unit_key','unit_id':UNIT,'key_code':69,'modifiers':0})
        self.assertEqual(self.bridge._wire({'id':legacy['id'],'payload':json.dumps(legacy['payload'])}).split('\t')[7],'',
                         'a key without a team keeps following the panel selection')
        for bad in ({'team':'green','count':1},{'team':'red','count':101},{'team':'red'},{'count':2}):
            with self.assertRaises(backend.ValidationError):
                self.bridge.enqueue({'action':'configure_unit_key','unit_id':UNIT,'key_code':81,'modifiers':0,**bad})
        self.write('unit-keybinds.tsv','UnitKeysV2\t3\n'+UNIT+'\t81\t0\tneutral\t3\n')
        bindings,errors=self.bridge._unit_shortcuts('')
        self.assertEqual(errors,[]);self.assertEqual((bindings[UNIT]['team'],bindings[UNIT]['count']),('neutral',3))
        self.write('unit-keybinds.tsv','UnitKeysV2\t4\n'+UNIT+'\t81\t0\t\t\n')
        bindings,errors=self.bridge._unit_shortcuts('')
        self.assertEqual(errors,[]);self.assertEqual((bindings[UNIT]['team'],bindings[UNIT]['count']),(None,None))

    def test_missing_codex_uses_explicit_working_translation_and_keeps_identifiers(self):
        result = self.bridge.catalog()
        unit = result["units"][0]
        self.assertEqual(result["codex_errors"], [])
        self.assertTrue(result["available"])
        self.assertEqual((unit["id"], unit["name"], unit["class_path"]), (UNIT, "测试单位", UNIT))
        self.assertIn("容器体", unit["display_name"])
        self.assertEqual(unit["internal_name"], "BP_Monster_Vessel_Child")
        self.assertTrue(unit["name_source"].startswith("working_translation"))
        self.assertIn("非官方", unit["name_source_label"])

    def test_names_in_the_game_language_are_served_by_unit_id_and_older_exports_give_none(self):
        alias=UNIT.replace('Vessel_Child','Vessel_Alias')
        with (self.bridge.runtime/'catalog.tsv').open('a',encoding='utf-8') as f:
            f.write('\t'.join((alias,'Alias','怪物',alias,'0','1',NPC_REASON))+'\n')
        rows=('\t'.join((UNIT,'主图鉴名','0','Puppet','native_codex:FCodexEnemyRow;EnemyClass'))+'\n'+
            '\t'.join((alias,'主图鉴名','0','Puppet','native_codex:FCodexEnemyRow;AliasEnemyClasses;canonical='+UNIT))+'\n')
        self.write('codex.tsv','\t'.join(backend.CODEX_FIELDS)+'\n'+rows)
        self.assertEqual(self.bridge.unit_names(),{'lang':'','units':{},'count':0},'a v0.37.4 export has no names in the game language')
        named=('\t'.join((UNIT,'主图鉴名','0','Puppet','native_codex:FCodexEnemyRow;EnemyClass','Vessel Child','en'))+'\n'+
            '\t'.join((alias,'主图鉴名','0','Puppet','native_codex:FCodexEnemyRow;AliasEnemyClasses;canonical='+UNIT,'Vessel Child','en'))+'\n')
        self.write('codex.tsv','\t'.join(backend.CODEX_FIELDS_NAMED)+'\n'+named)
        header='\t'.join(backend._taxonomy_module.LOCATION_FIELDS)+'\n'
        self.write('codex-locations.tsv',header+'\t'.join((UNIT,'Map_A','Weeping Valley','Chapter_X','Upstream','2','3','Actual_Level','4',UNIT,'assigned','native_codex_own_map_v1'))+'\n')
        self.assertEqual(self.bridge.catalog()['codex_errors'],[],'the seven-column codex is read like the five-column one')
        self.assertEqual(self.bridge.unit_names(),{'lang':'en','count':2,'units':{
            'BP_Monster_Vessel_Child':{'name':'Vessel Child','map':'Weeping Valley','chapter':'Upstream'},
            'BP_Monster_Vessel_Alias':{'name':'Vessel Child','map':'','chapter':''}}})
        self.write('codex.tsv','\t'.join(backend.CODEX_FIELDS_NAMED)+'\n'+named.replace('\ten\n','\ten;rm -rf\n',1))
        self.assertEqual(self.bridge.unit_names()['count'],1,'a row with a malformed language is dropped')

    def test_native_map_chapter_chain_and_official_alias_are_exact_and_do_not_unlock(self):
        alias=UNIT.replace('Vessel_Child','Vessel_Alias')
        with (self.bridge.runtime/'catalog.tsv').open('a',encoding='utf-8') as f:
            f.write('\t'.join((alias,'Alias','怪物',alias,'0','1',NPC_REASON))+'\n')
        self.write('codex.tsv','\t'.join(backend.CODEX_FIELDS)+'\n'+
            '\t'.join((UNIT,'主图鉴名','0','Puppet','native_codex:FCodexEnemyRow;EnemyClass'))+'\n'+
            '\t'.join((alias,'主图鉴名','0','Puppet','native_codex:FCodexEnemyRow;AliasEnemyClasses;canonical='+UNIT))+'\n')
        header='\t'.join(backend._taxonomy_module.LOCATION_FIELDS)+'\n'
        def line(path):
            return '\t'.join((path,'Map_A','原生地图','Chapter_X','原生章节','2','3','Actual_Level','4',UNIT,'assigned','native_codex_own_map_v1'))+'\n'
        self.write('codex-locations.tsv',header+line(UNIT)+line(alias))
        result=self.bridge.catalog();main,variant=result['units']
        self.assertEqual(result['location_errors'],[])
        self.assertEqual(result['primary_count'],1)
        self.assertEqual((main['chapter_name'],main['map_name'],main['codex_order']),('原生章节','原生地图',4))
        self.assertEqual((variant['codex_entry_kind'],variant['canonical_class_path'],variant['map_id']),('alias',UNIT,'Map_A'))
        self.assertFalse(variant['spawnable'],'metadata must never expand spawn permission')
        self.write('codex-locations.tsv',header+line(UNIT)+line(UNIT))
        result=self.bridge.catalog()
        self.assertTrue(result['location_errors'])
        self.assertIsNone(result['units'][0]['map_id'],'duplicate map evidence cannot select one arbitrary location')

    def test_location_without_native_identity_or_wrong_canonical_is_not_used(self):
        fields=backend._taxonomy_module.LOCATION_FIELDS
        values=(UNIT,'Map_A','原生地图','Chapter_X','原生章节','2','3','Actual_Level','4',UNIT,'assigned','native_codex_own_map_v1')
        self.write('codex-locations.tsv','\t'.join(fields)+'\n'+'\t'.join(values)+'\n')
        self.assertIsNone(self.bridge.catalog()['units'][0]['map_id'])
        self.write('codex.tsv','\t'.join(backend.CODEX_FIELDS)+'\n'+
            '\t'.join((UNIT,'主图鉴名','0','Puppet','native_codex:FCodexEnemyRow;EnemyClass'))+'\n')
        for index,bad in ((9,'/Other/Unit.Unit_C'),(11,'path_name_guess'),(5,'NaN'),(10,'guessed')):
            with self.subTest(index=index):
                changed=list(values);changed[index]=bad
                self.write('codex-locations.tsv','\t'.join(fields)+'\n'+'\t'.join(changed)+'\n')
                result=self.bridge.catalog()
                self.assertIsNone(result['units'][0]['map_id'])
                self.assertTrue(result['location_errors'])

    def test_exact_codex_chinese_name_and_boss_evidence_take_precedence(self):
        self.write("codex.tsv", "\t".join(backend.CODEX_FIELDS) + "\n" +
                   "\t".join((UNIT, "图鉴中文名称测试", "true", "5", "game_codex")) + "\n")
        unit = self.bridge.catalog()["units"][0]
        self.assertEqual(unit["display_name"], "图鉴中文名称测试")
        self.assertEqual(unit["name_source"], "game_codex")
        self.assertEqual(unit["name_source_label"], "游戏图鉴原文")
        self.assertEqual(unit["category"], "BOSS")
        self.assertEqual(unit["species_label"], "人偶类")
        self.assertEqual(unit["source_detail"], "game_codex")
        self.assertEqual((unit["id"], unit["name"], unit["class_path"]), (UNIT, "测试单位", UNIT))

    def test_real_native_codex_source_formats_and_exported_enums_are_normalized(self):
        sources = [
            "native_codex:FCodexEnemyRow;EnemyClass",
            "native_codex:FCodexEnemyRow;AliasEnemyClasses;canonical=" + UNIT,
            "native_codex:FCodexEnemyRow;replacement=" + UNIT + ";use_replacement_entry=false;EnemyClass",
            "native_codex:FCodexEnemyRow;use_replacement_entry=true;AliasEnemyClasses;canonical=UNKNOWN",
        ]
        for source in sources:
            with self.subTest(source=source):
                self.write("codex.tsv", "\t".join(backend.CODEX_FIELDS) + "\n" +
                           "\t".join((UNIT, "原生图鉴测试名", "0", "Animal", source)) + "\n")
                result = self.bridge.catalog()
                unit = result["units"][0]
                self.assertEqual(result["codex_errors"], [])
                self.assertEqual(unit["display_name"], "原生图鉴测试名")
                self.assertEqual(unit["source_detail"], source)
                self.assertEqual(unit["species_label"], "动物类")
                self.assertEqual(unit["category"], "普通怪物（级别待核）")
        self.write("codex.tsv", "\t".join(backend.CODEX_FIELDS) + "\n" +
                   "\t".join((UNIT, "原生图鉴测试名", "UNKNOWN", "UNKNOWN", sources[0])) + "\n")
        self.assertEqual(self.bridge.catalog()["codex_errors"], [])

    def test_wrong_path_or_unrecognized_source_never_supplies_an_official_name(self):
        other = UNIT.replace("Vessel_Child", "Vessel_Child_Other")
        for path, source in ((other, "game_codex"), (UNIT, "manual"),
                             (UNIT, "native_codex:FCodexEnemyRowEvil;EnemyClass"),
                             (UNIT, "native_codex:FCodexEnemyRow;EnemyClass;extra=unverified")):
            with self.subTest(path=path, source=source):
                self.write("codex.tsv", "\t".join(backend.CODEX_FIELDS) + "\n" +
                           "\t".join((path, "不得冒用的名称", "1", "1", source)) + "\n")
                unit = self.bridge.catalog()["units"][0]
                self.assertNotEqual(unit["display_name"], "不得冒用的名称")
                self.assertNotEqual(unit["name_source"], "game_codex")

    def test_duplicate_or_conflicting_codex_rows_quarantine_the_whole_path(self):
        first = "\t".join((UNIT, "图鉴名称一", "1", "1", "game_codex"))
        for second in (first, "\t".join((UNIT, "图鉴名称二", "0", "5", "game_codex"))):
            self.write("codex.tsv", "\t".join(backend.CODEX_FIELDS) + "\n" + first + "\n" + second + "\n")
            result = self.bridge.catalog()
            self.assertTrue(result["available"])
            self.assertTrue(result["codex_errors"])
            self.assertNotEqual(result["units"][0]["name_source"], "game_codex")
            self.assertIsNone(result["units"][0]["source_detail"])

    def test_official_labels_and_decorator_fields_cannot_bypass_spawn_validation(self):
        other = UNIT.replace("Vessel_Child", "MaleThug_BigShield")
        self.write("catalog.tsv", "\t".join(backend.CATALOG_FIELDS) + "\n" +
                   "\t".join((other, "BP_Monster_MaleThug_BigShield", "怪物", other, "1", "1", NPC_REASON)) + "\n")
        self.write("codex.tsv", "\t".join(backend.CODEX_FIELDS) + "\n" +
                   "\t".join((other, "有图鉴名称但未做生成测试", "1", "1", "game_codex")) + "\n")
        original = backend.decorate_row
        backend.decorate_row = lambda row, evidence, parent_evidence=None: {**original(row, evidence, parent_evidence), "spawnable": True, "id": UNIT,
            "name": "wrong", "class_path": UNIT, "validation_status": "verified_spawn_observation"}
        try:
            unit = self.bridge.catalog()["units"][0]
            self.assertEqual(unit["display_name"], "有图鉴名称但未做生成测试")
            self.assertEqual((unit["id"], unit["name"], unit["class_path"]), (other, "BP_Monster_MaleThug_BigShield", other))
            self.assertFalse(unit["spawnable"])
            self.assertEqual(unit["validation_status"], "unverified")
            for action in ("spawn", "select_unit"):
                with self.assertRaises(backend.ValidationError):
                    self.bridge.enqueue({"action": action, "unit_id": other})
        finally:
            backend.decorate_row = original

    def test_special_entity_is_decorated_for_browsing_but_stays_locked(self):
        special = UNIT.replace("Vessel_Child", "Vessel_Child_Summon")
        self.write("catalog.tsv", "\t".join(backend.CATALOG_FIELDS) + "\n" +
                   "\t".join((special, "BP_Monster_Vessel_Child_Summon", "怪物", special, "1", "1", NPC_REASON)) + "\n")
        unit = self.bridge.catalog()["units"][0]
        self.assertTrue(unit["is_special"])
        self.assertEqual(unit["category"], "特殊实体")
        self.assertIn("quarantine_review", unit["traits"])
        self.assertFalse(unit["spawnable"])

    def test_exact_parent_codex_labels_are_derived_nonofficial_and_do_not_grant_permissions(self):
        parent = "/Game/Fixture/BP_Monster_Dog.BP_Monster_Dog_C"
        for suffix, category in (("Summon", "特殊实体"), ("Red", "普通怪物（级别待核）")):
            child = f"/Game/Fixture/BP_Monster_Dog_{suffix}.BP_Monster_Dog_{suffix}_C"
            reason = f"parent=/Script/Engine.BlueprintGeneratedClass'{parent}';" + NPC_REASON
            self.write("catalog.tsv", "\t".join(backend.CATALOG_FIELDS) + "\n" +
                       "\t".join((child, f"BP_Monster_Dog_{suffix}", "怪物", child, "0", "1", reason)) + "\n")
            self.write("codex.tsv", "\t".join(backend.CODEX_FIELDS) + "\n" +
                       "\t".join((parent, "父类图鉴名称测试", "1", "Animal", "native_codex:FCodexEnemyRow;EnemyClass")) + "\n")
            unit = self.bridge.catalog()["units"][0]
            self.assertEqual(unit["parent_class_path"], parent)
            self.assertEqual(unit["name_source"], "derived_working_translation")
            self.assertIn("工作译名", unit["name_source_label"])
            self.assertIn("父类图鉴名称测试", unit["display_name"])
            self.assertEqual(unit["category"], category)
            self.assertNotIn("boss_verified", unit["traits"], "a parent BOSS flag must not be inherited")
            self.assertIsNone(unit["source_detail"], "parent provenance must not become child exact evidence")
            self.assertEqual(unit["parent_source_detail"], "native_codex:FCodexEnemyRow;EnemyClass")
            self.assertEqual(unit["validation_status"], "unverified")
            self.assertFalse(unit["spawnable"])
            for action in ("spawn", "select_unit"):
                with self.assertRaises(backend.ValidationError):
                    self.bridge.enqueue({"action": action, "unit_id": child})
            if suffix == "Summon":
                self.assertTrue(unit["is_special"])

    def test_missing_mismatched_or_ambiguous_parent_evidence_keeps_the_previous_working_name(self):
        parent = "/Game/Fixture/BP_Monster_Dog.BP_Monster_Dog_C"
        child = "/Game/Fixture/BP_Monster_Dog_Summon.BP_Monster_Dog_Summon_C"
        for reason, evidence_path in (
            (f"parent={parent};" + NPC_REASON, None),
            (f"parent={parent};" + NPC_REASON, parent.replace("Dog", "Dog_Other")),
            (f"parent={parent};parent={parent};" + NPC_REASON, parent),
            ("parent=BP_Monster_Dog_C;" + NPC_REASON, parent),
            (NPC_REASON, parent),
        ):
            self.write("catalog.tsv", "\t".join(backend.CATALOG_FIELDS) + "\n" +
                       "\t".join((child, "BP_Monster_Dog_Summon", "怪物", child, "0", "1", reason)) + "\n")
            codex = "\t".join(backend.CODEX_FIELDS) + "\n"
            if evidence_path:
                codex += "\t".join((evidence_path, "不得继承的名称", "1", "1", "game_codex")) + "\n"
            self.write("codex.tsv", codex)
            unit = self.bridge.catalog()["units"][0]
            self.assertTrue(unit["name_source"].startswith("working_translation"))
            self.assertNotIn("不得继承的名称", unit["display_name"])
            self.assertFalse(unit["spawnable"])

    def test_exact_child_name_wins_over_parent_derived_label_without_unblocking_spawn(self):
        parent = "/Game/Fixture/BP_Monster_Dog.BP_Monster_Dog_C"
        child = "/Game/Fixture/BP_Monster_Dog_Summon.BP_Monster_Dog_Summon_C"
        self.write("catalog.tsv", "\t".join(backend.CATALOG_FIELDS) + "\n" +
                   "\t".join((child, "BP_Monster_Dog_Summon", "怪物", child, "0", "1", f"ParentClass={parent};" + NPC_REASON)) + "\n")
        self.write("codex.tsv", "\t".join(backend.CODEX_FIELDS) + "\n" +
                   "\t".join((parent, "父类名称", "1", "1", "game_codex")) + "\n" +
                   "\t".join((child, "子类图鉴名称", "0", "1", "game_codex")) + "\n")
        unit = self.bridge.catalog()["units"][0]
        self.assertEqual(unit["display_name"], "子类图鉴名称")
        self.assertEqual(unit["name_source"], "game_codex")
        self.assertEqual(unit["source_detail"], "game_codex")
        self.assertFalse(unit["spawnable"])

    def test_missing_or_revoked_validation_never_grants_metadata_only_spawn_permission(self):
        command = self.spawn()
        self.policy.unlink()
        catalog = self.bridge.catalog()
        self.assertEqual(catalog["total"], 1)
        self.assertFalse(catalog["units"][0]["spawnable"])
        self.bridge.tick()
        self.assertEqual(self.bridge._command(command["id"])["status"], "failed")
        self.assertFalse((self.bridge.runtime / "inbox.tsv").exists())
        self.assertFalse((self.bridge.runtime / "inbox.session.tsv").exists())
        for action in ("spawn", "select_unit"):
            with self.assertRaises(backend.ValidationError):
                self.bridge.enqueue({"action": action, "unit_id": UNIT})

    def test_no_session_rejects_all_new_commands_and_heartbeat_is_not_readiness(self):
        self.game(session=None)
        self.assertTrue(self.bridge.game_status()["online"])
        self.assertFalse(self.bridge.game_status()["ready"])
        for action in backend.ACTIONS:
            request = {"action": action}
            if action in {"spawn", "select_unit"}:
                request["unit_id"] = UNIT
            if action == "configure_keys":
                request["bindings"] = BINDINGS
            with self.subTest(action=action), self.assertRaisesRegex(backend.ValidationError, "当前游戏会话"):
                self.bridge.enqueue(request)
        self.assertEqual(self.bridge.status()["queue"], [])

    def test_sensitive_actions_wait_for_explicit_ready_and_sidecar_precedes_inbox(self):
        for action in ("spawn", "start", "toggle_spectator"):
            with self.subTest(action=action):
                self.game(ready=None)
                request = {"action": action}
                if action == "spawn":
                    request["unit_id"] = UNIT
                command = self.bridge.enqueue(request)
                self.bridge.tick()
                self.assertEqual(self.bridge._command(command["id"])["status"], "queued")
                self.assertFalse((self.bridge.runtime / "inbox.tsv").exists())
                self.game(ready=False)
                self.bridge.tick()
                self.assertFalse((self.bridge.runtime / "inbox.tsv").exists())
                self.game(ready=True)
                writes, original = [], backend.atomic_text
                def tracked(path, content):
                    if path.name == "inbox.tsv":
                        self.assertEqual((self.bridge.runtime / "inbox.session.tsv").read_text(), f"{command['id']}\tsession-A\n")
                    writes.append(path.name)
                    original(path, content)
                backend.atomic_text = tracked
                try:
                    self.bridge.tick()
                finally:
                    backend.atomic_text = original
                self.assertEqual(writes, ["inbox.session.tsv", "inbox.tsv"])
                self.write("ack.tsv", f"{command['id']}\tok\tdone\t1\n")
                self.bridge.tick()
                self.assertFalse((self.bridge.runtime / "inbox.session.tsv").exists())

    def test_new_game_session_expires_inflight_and_queued_commands_without_deleting_history(self):
        inflight = self.spawn()
        queued = self.bridge.enqueue({"action": "start"})
        self.bridge.tick()
        self.game(session="session-B", ready=False)
        self.bridge.tick()
        self.assertEqual(self.bridge._command(inflight["id"])["status"], "uncertain")
        self.assertEqual(self.bridge._command(queued["id"])["status"], "failed")
        self.assertIn("重新请求", self.bridge._command(queued["id"])["message"])
        self.assertEqual(len(self.bridge.status()["queue"]), 2)
        self.assertFalse((self.bridge.runtime / "inbox.tsv").exists())
        self.assertFalse((self.bridge.runtime / "inbox.session.tsv").exists())
        self.game(session="session-B", ready=True)
        self.bridge.tick()
        self.assertFalse((self.bridge.runtime / "inbox.tsv").exists(), "old session must not be replayed after readiness")

    def test_session_expiry_preserves_delivery_files_owned_by_another_id(self):
        command = self.spawn()
        self.bridge.tick()
        self.write("inbox.tsv", "other-id\tstop\t\tblue\t1\t\t\t\t\t1\n")
        self.write("inbox.session.tsv", "other-id\tsession-B\n")
        self.game(session="session-B")
        self.bridge.tick()
        self.assertEqual(self.bridge._command(command["id"])["status"], "uncertain")
        self.assertTrue((self.bridge.runtime / "inbox.tsv").read_text().startswith("other-id\t"))
        self.assertEqual((self.bridge.runtime / "inbox.session.tsv").read_text(), "other-id\tsession-B\n")

    def test_existing_database_is_migrated_and_old_unbound_jobs_are_not_replayed(self):
        directory = self.root / "legacy-runtime"
        directory.mkdir()
        db = backend.sqlite3.connect(directory / "panel_queue.sqlite3")
        db.execute("CREATE TABLE commands(id INTEGER PRIMARY KEY AUTOINCREMENT,action TEXT,payload TEXT,state TEXT,created REAL,sent REAL,completed REAL,message TEXT,spawned_count INTEGER)")
        for command_id, state in ((31, "inflight"), (32, "pending")):
            db.execute("INSERT INTO commands(id,action,payload,state,created) VALUES(?,?,?,?,?)",
                       (command_id, "spawn", json.dumps({"action": "spawn", "unit_id": UNIT}), state, 50))
        db.commit()
        db.close()
        (directory / "status.tsv").write_text("schema_version\t1\nheartbeat_unix\t100\ngame_session\tnew-session\ngame_ready\ttrue\n")
        bridge = backend.Bridge(directory, clock=lambda: 100.0, validation_path=self.policy)
        try:
            bridge.tick()
            self.assertEqual(bridge._command(31)["status"], "uncertain")
            self.assertEqual(bridge._command(32)["status"], "failed")
            self.assertEqual(len(bridge.status()["queue"]), 2)
            self.assertFalse((directory / "inbox.tsv").exists())
        finally:
            bridge.close()

    def test_fresh_partial_catalog_exposes_only_complete_utf8_rows(self):
        header = "\t".join(backend.CATALOG_FIELDS) + "\n"
        row = "\t".join((UNIT, "进行中单位", "小兵", UNIT, "1", "1", "")) + "\n"
        partial = self.bridge.runtime / "catalog.tsv.partial"
        partial.write_bytes((header + row).encode("utf-8") + "unfinished\t怪".encode("utf-8")[:-1])
        os.utime(partial, (101, 101))
        self.write("status.tsv", "schema_version\t1\nheartbeat_unix\t100\ncatalog_state\tscanning\ncatalog_started_at\t100\n")
        result = self.bridge.catalog()
        self.assertTrue(result["partial"])
        self.assertEqual(result["total"], 1)
        self.assertEqual(result["units"][0]["name"], "进行中单位")
        self.assertEqual(result["errors"], [])
        self.assertTrue(self.bridge.status()["catalog"]["partial"])

    def test_previous_scan_partial_does_not_replace_the_published_catalog(self):
        partial = self.bridge.runtime / "catalog.tsv.partial"
        partial.write_text("\t".join(backend.CATALOG_FIELDS) + "\n", encoding="utf-8")
        os.utime(partial, (90, 90))
        self.write("status.tsv", "schema_version\t1\nheartbeat_unix\t100\ncatalog_state\tscanning\ncatalog_started_at\t100\n")
        result = self.bridge.catalog()
        self.assertFalse(result["partial"])
        self.assertEqual(result["total"], 1)

    def test_partial_fallback_requires_scan_freshness_or_a_newer_published_file_comparison(self):
        partial = self.bridge.runtime / "catalog.tsv.partial"
        partial.write_text((self.bridge.runtime / "catalog.tsv").read_text(encoding="utf-8"), encoding="utf-8")
        os.utime(partial, (101, 101))
        os.utime(self.bridge.runtime / "catalog.tsv", (90, 90))
        self.write("status.tsv", "schema_version\t1\nheartbeat_unix\t100\ncatalog_state\tscanning\n")
        self.assertTrue(self.bridge.catalog()["partial"])
        (self.bridge.runtime / "catalog.tsv").unlink()
        self.assertFalse(self.bridge.catalog()["available"], "unattributed old partial must not appear after restart")
        self.write("status.tsv", "schema_version\t1\nheartbeat_unix\t100\ncatalog_state\tscanning\ncatalog_started_at\t100\n")
        self.assertTrue(self.bridge.catalog()["partial"])


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.static = root / "static"
        self.static.mkdir()
        (self.static / "index.html").write_text("<!doctype html><title>local test</title>")
        (root / "outside.html").write_text("must not serve")
        self.bridge = backend.Bridge(root / "Runtime")
        self.server = backend.PanelServer(self.bridge, self.static, 0)
        self.thread = threading.Thread(target=lambda: self.server.serve_forever(poll_interval=0.01), daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.thread.join(timeout=2)
        self.server.server_close()
        self.bridge.close()
        self.temporary.cleanup()

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=2)
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        data = response.read()
        result = response.status, dict(response.getheaders()), data
        connection.close()
        return result

    def test_status_token_and_secure_enqueue_contract(self):
        status, headers, raw = self.request("GET", "/api/status")
        self.assertEqual(status, 200)
        data = json.loads(raw)
        self.assertFalse(data["game"]["online"])
        self.assertIn("csrf_token", data)
        self.assertNotIn("Access-Control-Allow-Origin", headers)
        (self.bridge.runtime / "status.tsv").write_text(
            f"schema_version\t1\nheartbeat_unix\t{backend.time.time()}\ngame_session\thttp-test\ngame_ready\ttrue\nfunction_keys_schema\t3\nfunction_keys_epoch\thttp-keys\nfunction_keys_revision\t0\n", encoding="utf-8")
        write_headers = {"Content-Type": "application/json", "Origin": self.server.origin,
                         "X-CSRF-Token": data["csrf_token"]}
        status, _, raw = self.request("POST", "/api/command", json.dumps({"action": "refresh_catalog"}), write_headers)
        self.assertEqual(status, 202)
        self.assertEqual(json.loads(raw)["status"], "queued")
        self.assertFalse((self.bridge.runtime / "inbox.tsv").exists(), "HTTP acceptance is not dispatch or game execution")
        status, _, raw = self.request("POST", "/api/keybinds", json.dumps(BINDINGS), write_headers)
        self.assertEqual(status, 202)
        self.assertEqual(self.bridge.keybinds()["requested"], {name:backend.parse_binding(value) for name,value in BINDINGS.items()})
        status, _, raw = self.request("POST", "/api/queue/clear", "{}", write_headers)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw), {"cleared": 2, "interrupted": 0, "files_left": []})  # refresh_catalog and the ten keys
        self.assertEqual(self.request("POST", "/api/queue/clear", '{"all":1}', write_headers)[0], 400)
        self.assertEqual(self.request("POST", "/api/queue/clear", "{}", {"Content-Type": "application/json"})[0], 403)

    def test_origin_host_csrf_and_static_traversal_are_rejected(self):
        for headers in ({"Host": "evil.example"}, {"Origin": "https://evil.example"}, {"Origin": "null"}):
            self.assertEqual(self.request("GET", "/api/status", headers=headers)[0], 403)
        self.assertEqual(self.request("POST", "/api/command", '{"action":"stop"}', {"Content-Type": "application/json"})[0], 403)
        self.assertEqual(self.request("GET", "/%2e%2e/outside.html")[0], 403)
        self.assertEqual(self.request("GET", "/backend.py")[0], 403)
        self.assertEqual(self.request("OPTIONS", "/api/command")[0], 403)
        self.assertEqual(self.request("GET", "/")[0], 200)

    def test_static_types_ignore_the_windows_registry(self):
        # Other software often registers .js as text/plain; passed on, the browser refuses every script.
        (self.static / "app.js").write_text("void 0;")
        (self.static / "styles.css").write_text("body{}")
        mimetypes.add_type("text/plain", ".js")
        try:
            status, headers, _ = self.request("GET", "/app.js")
        finally:
            mimetypes.add_type("text/javascript", ".js")
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "text/javascript; charset=utf-8")
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        self.assertEqual(self.request("GET", "/styles.css")[1]["Content-Type"], "text/css; charset=utf-8")
        self.assertEqual(self.request("GET", "/")[1]["Content-Type"], "text/html; charset=utf-8")

    def test_codex_icons_saved_by_the_mod_are_listed_and_served_by_texture_name_only(self):
        runtime = self.bridge.runtime
        runtime.mkdir(exist_ok=True)
        (runtime / "codex-icons").mkdir()
        png = b"\x89PNG\r\n\x1a\nicon"
        (runtime / "codex-icons" / "T_BP_Monster_AHua_GuiTouDao_w.png").write_bytes(png)
        (runtime / "codex-icon-T_BP_Monster_MaleThug_Sword_w.png").write_bytes(png + b"flat")
        (runtime / "codex-icons.tsv").write_text(
            "unit\tfile\n"
            "BP_Monster_AHua_GuiTouDao\tcodex-icons/T_BP_Monster_AHua_GuiTouDao_w.png\n"
            "BP_Monster_AHua_Story\tcodex-icons/T_BP_Monster_AHua_GuiTouDao_w.png\n"
            "BP_Monster_MaleThug_Sword\tcodex-icon-T_BP_Monster_MaleThug_Sword_w.png\n"
            "BP_Missing\tcodex-icons/T_Missing_w.png\n"
            "../evil\tcodex-icons/T_BP_Monster_AHua_GuiTouDao_w.png\n"
            "BP_Traversal\tcodex-icons/../../outside.png\n", encoding="utf-8")
        status, _, raw = self.request("GET", "/api/codex-icons")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw), {"count": 3, "icons": {
            "BP_Monster_AHua_GuiTouDao": "/codex-icons/T_BP_Monster_AHua_GuiTouDao_w.png",
            "BP_Monster_AHua_Story": "/codex-icons/T_BP_Monster_AHua_GuiTouDao_w.png",
            "BP_Monster_MaleThug_Sword": "/codex-icons/T_BP_Monster_MaleThug_Sword_w.png"}})
        status, _, raw = self.request("GET", "/api/home-levels")
        self.assertEqual((status, json.loads(raw)), (200, {"units": {}, "count": 0}), "levels route answers before the game has run")
        status, _, raw = self.request("GET", "/api/unit-names")
        self.assertEqual((status, json.loads(raw)["count"]), (200, 0), "names route answers before the game has run")
        status, headers, raw = self.request("GET", "/codex-icons/T_BP_Monster_AHua_GuiTouDao_w.png")
        self.assertEqual((status, headers["Content-Type"], raw), (200, "image/png", png))
        self.assertEqual(headers["Cache-Control"], "max-age=86400")
        self.assertEqual(self.request("GET", "/codex-icons/T_BP_Monster_MaleThug_Sword_w.png")[2], png + b"flat", "a flat file is served too")
        for path in ("/codex-icons/T_Missing_w.png", "/codex-icons/..%2fcodex-icons.tsv", "/codex-icons/%2e%2e%2foutside.png",
                     "/codex-icons/T_BP_Monster_AHua_GuiTouDao_w.tsv", "/codex-icons/X_BP.png"):
            self.assertEqual(self.request("GET", path)[0], 404, path)
        self.assertEqual(self.request("GET", "/codex-icons/T_BP_Monster_AHua_GuiTouDao_w.png", headers={"Host": "evil.example"})[0], 403)


if __name__ == "__main__":
    unittest.main(verbosity=2)
