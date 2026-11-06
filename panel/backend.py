"""Local PhantomGladiator panel bridge. Python 3.11+, standard library only.

The server never calls a game API. It serializes validated commands to Runtime/
inbox.tsv and waits for the game's matching ack.tsv. No ACK means no success.
"""
from __future__ import annotations

import argparse
import csv
import io
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import secrets
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit, parse_qs

_labels_spec = importlib.util.spec_from_file_location("phantom_catalog_labels", Path(__file__).with_name("catalog_labels.py"))
_labels_module = importlib.util.module_from_spec(_labels_spec)
_labels_spec.loader.exec_module(_labels_module)
decorate_row = _labels_module.decorate_row
_taxonomy_spec = importlib.util.spec_from_file_location('phantom_catalog_taxonomy', Path(__file__).with_name('catalog_taxonomy.py'))
_taxonomy_module = importlib.util.module_from_spec(_taxonomy_spec)
_taxonomy_spec.loader.exec_module(_taxonomy_module)

DEFAULT_RUNTIME = Path(r"C:\Program Files (x86)\Steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PhantomGladiator\Runtime")
ACTIONS = {"spawn", "set_unit_rule", "toggle_track", "track_pick", "track_next", "set_camera_track", "set_ai_params", "set_boss_combos", "select_unit", "start", "stop", "clear_neutral", "recall_companions", "toggle_time_stop", "set_free_camera", "refresh_catalog", "configure_keys", "configure_unit_key", "toggle_spectator", "toggle_stat_match", "toggle_camera", "exit_camera", "cycle_team", "set_spawn_difficulty", "dismiss_companions", "set_fun_feature", "set_team_immortal", "set_clock_hud", "set_execution_camera", "set_companion_executions", "set_stat_mode", "set_companion_stats", "set_spawn_level"}
# Teams a unit can be summoned to; companion units follow the player (companion.lua).
TEAMS = ("blue", "red", "neutral", "companion")
# FOLLOW keeps the game difficulty; the others are the game's own four levels (spawn_difficulty.lua).
SPAWN_DIFFICULTIES = ("FOLLOW", "EASY", "NORMAL", "HARD", "NIGHTMARE")
# Where a summon's level comes from (home_levels.lua): its home (default), the map enemies near the player, or one
# level for all; UNIT picks one unit's level. Levels are whole numbers up to SPAWN_LEVEL_MAX.
SPAWN_LEVEL_MODES = ("HOME", "HERE", "CUSTOM", "UNIT")
SPAWN_LEVEL_MAX = 60
# native: where the game itself puts the unit (native_levels.lua); area/extra/prologue: the areas of the codex home
# map, for units no spawner places; picked: a level the player picked that is none of those.
HOME_LEVEL_SOURCES = {"native", "area", "extra", "prologue", "picked"}
HOME_LEVEL_HEADER = "unit\tlevel\tsource\tmap\tpart\tdefault\tpicked\tcount"
UNIT_SHORT_ID = re.compile(r"[A-Za-z0-9_]{1,128}")
# Rules set on a unit's card (unit_rules.lua).
UNIT_RULES = {"lock": ("execute", "kill"), "phantom": ("off", "keep")}
# Player-only fun features (fun_features.lua): infinite Shachi, auto perfect deflect, auto red-light dodge.
FUN_FEATURES = ("SHACHI", "DEFLECT", "DODGE")
# Teams whose units can be kept from going down (immortal_teams.lua); no-team units are the player's to beat.
IMMORTAL_TEAMS = ("blue", "red", "companion")
# Units per summon (arena_controller.lua MAX_BATCH): only guards against a mistyped number freezing the game.
MAX_SPAWN_COUNT = 100
# Every attribute of the game's attribute set (character_stats.lua Stats.allFields, CharacterBasics.hpp order):
# what a unit's spawn values can be set to.
STAT_FIELDS = (
    "Level", "Health", "Health_Max", "Health_Max_Lv1", "Shield", "Shield_Max", "Infliction_Max",
    "Infliction_Max_Lv1", "Attack", "Attack_Lv1", "Amplification_Physical", "DealtVulnerabilityMultiplier_Physical",
    "DealtReductionMultiplier_Physical", "Resistance_Physical", "TakenAdditiveMultiplier_Physical",
    "TakenVulnerabilityMultiplier_Physical", "TakenReductionMultiplier_Physical", "Amplification_PhysicalSharp",
    "DealtVulnerabilityMultiplier_PhysicalSharp", "DealtReductionMultiplier_PhysicalSharp",
    "Resistance_PhysicalSharp", "TakenAdditiveMultiplier_PhysicalSharp",
    "TakenVulnerabilityMultiplier_PhysicalSharp", "TakenReductionMultiplier_PhysicalSharp",
    "Amplification_PhysicalBlunt", "DealtVulnerabilityMultiplier_PhysicalBlunt",
    "DealtReductionMultiplier_PhysicalBlunt", "Resistance_PhysicalBlunt", "TakenAdditiveMultiplier_PhysicalBlunt",
    "TakenVulnerabilityMultiplier_PhysicalBlunt", "TakenReductionMultiplier_PhysicalBlunt", "Resistance_Poise",
    "TakenAdditiveMultiplier_Poise", "TakenVulnerabilityMultiplier_Poise", "TakenReductionMultiplier_Poise",
    "Amplification_Elemental", "DealtVulnerabilityMultiplier_Elemental", "DealtReductionMultiplier_Elemental",
    "Resistance_Elemental", "TakenAdditiveMultiplier_Elemental", "TakenVulnerabilityMultiplier_Elemental",
    "TakenReductionMultiplier_Elemental", "Amplification_Fire", "DealtVulnerabilityMultiplier_Fire",
    "DealtReductionMultiplier_Fire", "Resistance_Fire", "TakenAdditiveMultiplier_Fire",
    "TakenVulnerabilityMultiplier_Fire", "TakenReductionMultiplier_Fire", "Amplification_Toxin",
    "DealtVulnerabilityMultiplier_Toxin", "DealtReductionMultiplier_Toxin", "Resistance_Toxin",
    "TakenAdditiveMultiplier_Toxin", "TakenVulnerabilityMultiplier_Toxin", "TakenReductionMultiplier_Toxin",
    "Amplification_Ice", "DealtVulnerabilityMultiplier_Ice", "DealtReductionMultiplier_Ice", "Resistance_Ice",
    "TakenAdditiveMultiplier_Ice", "TakenVulnerabilityMultiplier_Ice", "TakenReductionMultiplier_Ice",
    "Amplification_Aqua", "DealtVulnerabilityMultiplier_Aqua", "DealtReductionMultiplier_Aqua", "Resistance_Aqua",
    "TakenAdditiveMultiplier_Aqua", "TakenVulnerabilityMultiplier_Aqua", "TakenReductionMultiplier_Aqua",
    "Amplification_Lightning", "DealtVulnerabilityMultiplier_Lightning", "DealtReductionMultiplier_Lightning",
    "Resistance_Lightning", "TakenAdditiveMultiplier_Lightning", "TakenVulnerabilityMultiplier_Lightning",
    "TakenReductionMultiplier_Lightning", "Amplification_Blood", "DealtVulnerabilityMultiplier_Blood",
    "DealtReductionMultiplier_Blood", "Resistance_Blood", "TakenAdditiveMultiplier_Blood",
    "TakenVulnerabilityMultiplier_Blood", "TakenReductionMultiplier_Blood", "Amplification_Chaos",
    "DealtVulnerabilityMultiplier_Chaos", "DealtReductionMultiplier_Chaos", "Resistance_Chaos",
    "TakenAdditiveMultiplier_Chaos", "TakenVulnerabilityMultiplier_Chaos", "TakenReductionMultiplier_Chaos",
    "Resistance_BreakDamageAdditionalMultiplier", "TakenAdditiveMultiplier_BreakDamage",
    "TakenVulnerabilityMultiplier_BreakDamage", "TakenReductionMultiplier_BreakDamage", "Shachi", "Shachi_Min",
    "Shachi_Max", "Shachi_Max_Lv1", "ShachiRegen", "ShachiRegenCooldown", "BreakDurationAdditionalMultiplier",
    "ShachiAttack", "ShachiAttack_Lv1", "Amplification_ImpactShachi", "DealtVulnerabilityMultiplier_ImpactShachi",
    "DealtReductionMultiplier_ImpactShachi", "Resistance_ImpactShachi", "TakenAdditiveMultiplier_ImpactShachi",
    "TakenVulnerabilityMultiplier_ImpactShachi", "TakenReductionMultiplier_ImpactShachi",
    "Amplification_ReflectShachi", "DealtVulnerabilityMultiplier_ReflectShachi",
    "DealtReductionMultiplier_ReflectShachi", "Resistance_ReflectShachi", "TakenAdditiveMultiplier_ReflectShachi",
    "TakenVulnerabilityMultiplier_ReflectShachi", "TakenReductionMultiplier_ReflectShachi",
    "Amplification_DefenceShachi", "DealtVulnerabilityMultiplier_DefenceShachi",
    "DealtReductionMultiplier_DefenceShachi", "Resistance_DefenceShachi", "TakenAdditiveMultiplier_DefenceShachi",
    "TakenVulnerabilityMultiplier_DefenceShachi", "TakenReductionMultiplier_DefenceShachi",
    "Resistance_ShachiWeaponHealth", "Resistance_ShachiWeaponShachi", "Resistance_ShachiWeaponStrength",
    "Resistance_ShachiWeaponRanged", "Resistance_ShachiWeaponMagic", "Resistance_ShachiWeaponMartial",
    "Resistance_ShachiWeaponSummon", "HeavyAttack_ShachiCostReduction", "UltimateCharge", "UltimateCharge_Max",
    "UltimateChargeCount", "UltimateChargeCount_Max", "UltimateChargeAdditiveRate",
    "UltimateChargeGainRateMultiplier", "SpiritShadow", "SpiritShadow_Max", "Ignite_Accumulation",
    "Poison_Accumulation", "Frost_Accumulation", "Thunder_Accumulation", "Electrified_Accumulation",
    "Bleed_Accumulation", "BloodBurst_Accumulation", "Water_Accumulation", "Amplification_ElementalAccumulation",
    "DealtVulnerabilityMultiplier_ElementalAccumulation", "DealtReductionMultiplier_ElementalAccumulation",
    "Resistance_ElementalAccumulation", "TakenAdditiveMultiplier_ElementalAccumulation",
    "TakenVulnerabilityMultiplier_ElementalAccumulation", "TakenReductionMultiplier_ElementalAccumulation",
    "Amplification_Ignite", "DealtVulnerabilityMultiplier_IgniteAccumulation",
    "DealtReductionMultiplier_IgniteAccumulation", "Resistance_IgniteAccumulation",
    "TakenAdditiveMultiplier_IgniteAccumulation", "TakenVulnerabilityMultiplier_IgniteAccumulation",
    "TakenReductionMultiplier_IgniteAccumulation", "Amplification_Poison",
    "DealtVulnerabilityMultiplier_PoisonAccumulation", "DealtReductionMultiplier_PoisonAccumulation",
    "Resistance_PoisonAccumulation", "TakenAdditiveMultiplier_PoisonAccumulation",
    "TakenVulnerabilityMultiplier_PoisonAccumulation", "TakenReductionMultiplier_PoisonAccumulation",
    "Amplification_Frost", "DealtVulnerabilityMultiplier_FrostAccumulation",
    "DealtReductionMultiplier_FrostAccumulation", "Resistance_FrostAccumulation",
    "TakenAdditiveMultiplier_FrostAccumulation", "TakenVulnerabilityMultiplier_FrostAccumulation",
    "TakenReductionMultiplier_FrostAccumulation", "Resistance_FrostDuration", "TakenAdditiveMultiplier_FrostDuration",
    "TakenVulnerabilityMultiplier_FrostDuration", "TakenReductionMultiplier_FrostDuration", "Amplification_Electrified",
    "DealtVulnerabilityMultiplier_ElectrifiedAccumulation", "DealtReductionMultiplier_ElectrifiedAccumulation",
    "Resistance_ElectrifiedAccumulation", "TakenAdditiveMultiplier_ElectrifiedAccumulation",
    "TakenVulnerabilityMultiplier_ElectrifiedAccumulation", "TakenReductionMultiplier_ElectrifiedAccumulation",
    "Amplification_Bleed", "DealtVulnerabilityMultiplier_BleedAccumulation",
    "DealtReductionMultiplier_BleedAccumulation", "Resistance_BleedAccumulation",
    "TakenAdditiveMultiplier_BleedAccumulation", "TakenVulnerabilityMultiplier_BleedAccumulation",
    "TakenReductionMultiplier_BleedAccumulation", "Amplification_BloodBurst",
    "DealtVulnerabilityMultiplier_BloodBurstAccumulation", "DealtReductionMultiplier_BloodBurstAccumulation",
    "Resistance_BloodBurstAccumulation", "TakenAdditiveMultiplier_BloodBurstAccumulation",
    "TakenVulnerabilityMultiplier_BloodBurstAccumulation", "TakenReductionMultiplier_BloodBurstAccumulation",
    "Amplification_Water", "DealtVulnerabilityMultiplier_WaterAccumulation",
    "DealtReductionMultiplier_WaterAccumulation", "Resistance_WaterAccumulation",
    "TakenAdditiveMultiplier_WaterAccumulation", "TakenVulnerabilityMultiplier_WaterAccumulation",
    "TakenReductionMultiplier_WaterAccumulation", "StatusInflictionDecrementRate",
    "ExecutionExecutorNormalHealthThreshold", "ExecutionExecutorBreakHealthThreshold",
    "ExecutionTargetNormalHealthThreshold", "ExecutionTargetBreakHealthThreshold", "MindDustAdditiveMultiplier",
    "Health_Min", "WalkSpeed", "JogSpeed", "SprintSpeed", "CrouchSpeed", "FinalWalkSpeed", "Awakening",
    "Awakening_Max", "PowerScore", "XP", "Coin", "Corrosion",
)
STAT_MODES = {"game": "GAME", "match": "MATCH", "custom": "CUSTOM"}
# The arena's set and the companions' own, with their files; companions never copy a first unit (stat_match.lua).
STAT_SETS = {"set_stat_mode": {"modes": ("game", "match", "custom"), "request": "stat-custom-request.tsv"},
             "set_companion_stats": {"modes": ("game", "custom"), "request": "companion-stats-request.tsv"}}
# The game's named AI parameters the panel can change, with their types (ai_params.lua, prototype/ai-params.js).
AI_PARAMS = {
    "近距离进攻概率": "float", "中距离进攻概率": "float", "远距离进攻概率": "float", "目标在受击状态进攻概率": "float", "咋呼概率": "float",
    "重新规划-进攻欲望": "float", "重新规划-起攻权重": "float", "重新规划-摸奖权重": "float", "重新规划-牵制权重": "float", "重新规划-打差合概率": "float",
    "事件反应-打差合概率": "float", "事件反应-反蓄力动作概率": "float", "autocombo权重": "float", "非autocombo权重": "float",
    "重新规划-全部攻击距离不满足时保底起攻": "bool", "进攻-起攻最大距离": "float", "进攻-摸奖最小距离": "float", "进攻-摸奖最大距离": "float",
    "进攻-牵制最小距离": "float", "重新规划-差合最小距离": "float", "重新规划-差合最大距离": "float", "尝试远程攻击的距离": "float",
    "格挡后-反击距离": "float", "立回-退出立回距离": "float", "立回-近距离分界线": "float", "立回-远距离分界线": "float", "立回-超远距离分界线": "float",
    "立回-近距离二人转权重": "float", "立回-近距离远离权重": "float", "立回-近距离闪避权重": "float", "立回-中距离二人转权重": "float",
    "立回-中距离靠近权重": "float", "立回-中距离远离权重": "float", "立回-中距离闪避权重": "float", "立回-远距离二人转权重": "float",
    "立回-远距离靠近权重": "float", "立回-近距离二人转最小持续时间": "float", "立回-近距离二人转最大持续时间": "float", "立回-中距离二人转最小持续时间": "float",
    "立回-中距离二人转最大持续时间": "float", "立回-远距离二人转最小持续时间": "float", "立回-远距离二人转最大持续时间": "float", "玩家开始近战攻击-格挡权重": "float",
    "玩家开始近战攻击-闪避权重": "float", "玩家开始近战攻击-无行为权重": "float", "玩家开始近战攻击-针对动作权重": "float", "玩家开始近战攻击-格挡距离": "float",
    "玩家开始近战攻击-闪避距离": "float", "远程攻击发射-格挡权重": "float", "远程攻击发射-闪避权重": "float", "远程攻击发射-无行为权重": "float",
    "远程攻击发射-针对动作权重": "float", "玩家靠近-抢招权重": "float", "玩家靠近-闪避后撤权重": "float", "玩家靠近-无行为权重": "float",
    "受击-转格挡概率": "float", "受击-允许转格挡计数": "int", "受击-正面脱离计数": "int", "受击-背面脱离计数": "int", "重新规划-不进攻时闪避概率": "float",
    "重新规划-不进攻时闪避最大距离": "float", "玩家开始远程攻击-反制概率": "float", "闪避敌人近战攻击的距离": "float", "减帧时允许格挡": "bool",
    "无视子弹开始事件": "bool",
}
STAT_POSITIVE = {"Health", "Health_Max", "Shachi_Max", "Attack"}
STAT_NON_NEGATIVE = {"Shachi", "ShachiAttack"}
LEGACY_BINDING_NAMES = ("spawn", "start", "stop", "refresh_catalog")
# The eight of FunctionKeysV2 (function_keybinds.lua); a save may lack the ones added later, which stay unbound.
V2_BINDING_NAMES = LEGACY_BINDING_NAMES + ("toggle_camera", "exit_camera", "cycle_team", "toggle_spectator")
BINDING_NAMES = V2_BINDING_NAMES + ("recall_companions", "toggle_time_stop", "toggle_track", "track_pick", "track_next")
BINDING_LABELS = dict(zip(BINDING_NAMES, ("召唤所选单位", "开始交战", "停止并清理", "刷新单位目录", "自由观战（无仇恨＋隐身＋无敌锁血）", "退出自由观战并恢复", "切换召唤队伍", "单独切换无仇恨", "召回随从到身边", "时停（游戏暂停，自由视角照常移动）", "镜头跟踪开关", "镜头锁定屏幕中央的单位", "镜头跟踪下一个单位")))
# Function key schemas the mod reports (status.tsv function_keys_schema): 2 had eight keys, 3 ten, 4 has thirteen and takes
# configure_keys in 19 columns. Keys are shown for all; saving needs 4, the mod this app installs.
FUNCTION_KEY_SCHEMAS = ("2", "3", "4")
# 镜头跟踪 (camera_track.lua).
TRACK_FRAMINGS = ("side", "shoulder", "orbit")
TRACK_RESUME_MAX = 10
TRACK_TARGET = re.compile(r"[0-9]{1,24}")
CATALOG_FIELDS = ("id", "name", "category", "class_path", "loaded", "spawnable", "reason")
CODEX_FIELDS = ("class_path", "zh_name", "is_boss", "enemy_type", "source")
# From v0.37.5 the mod adds the name in the game's current language and that language (codex_catalog_export.lua).
CODEX_FIELDS_NAMED = CODEX_FIELDS + ("name", "name_lang")
LANGUAGE_CODE = re.compile(r"[A-Za-z0-9-]{0,16}")
LABEL_FIELDS = ("display_name", "internal_name", "category", "category_source", "category_special", "name_source", "name_source_label",
                "traits", "trait_labels", "family_id", "untranslated_tokens", "species_label")
CODEX_ENEMY_TYPES = {"None": "unknown", "Animal": "1", "GuaiMian": "2", "DragonModified": "3", "HumanMaster": "4", "Puppet": "5"}
COMMAND_FIELDS = ("id", "action", "unit_id", "team", "count", "key_spawn", "key_start", "key_stop", "key_refresh_catalog", "schema_version")
MAX_UNIT_ID_BYTES = 512
MAX_INBOX_BYTES = 2048
READY_ACTIONS = {"spawn", "start", "toggle_spectator"}
# A summon, start or no-aggro switch waits this long for the game to stand in a map, then fails: the queue is
# first in first out, and before v0.38.1 one such wait held back every command behind it, the app's unit selection
# too (a player's summon key kept giving the unit selected long before).
READY_WAIT_SECONDS = 60
# A command the game has not answered after this long is reported, with the way to clear the queue.
SLOW_ACK_SECONDS = 20
TERMINAL_STATES = ("succeeded", "failed", "uncertain")
CLEARED_PENDING = "已手动清理，未投递，游戏没有执行"
CLEARED_INFLIGHT = "uncertain: 已手动清理；这条已交给游戏，是否执行过未确认，不会重发"
READY_TIMEOUT = "游戏%d秒内一直没进入可操作的地图，这条没有执行；进地图后再点一次" % READY_WAIT_SECONDS
# The free camera's speed (cm/s), turn (% of the raw mouse) and smoothing (%), as free_camera.lua takes them.
FREE_CAMERA_LIMITS = {"speed": (100, 5000), "turn": (20, 300), "smooth": (0, 100)}
MAX_GAME_JOURNAL_BYTES = 4 * 2097152
# Content types for the app's own files. Not mimetypes.guess_type: on Windows it reads the registry, where
# other software often registers .js as text/plain, and under nosniff the browser then refuses every
# script and the window stays empty (reported by players on v0.35.1).
STATIC_TYPES = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                ".svg": "image/svg+xml", ".png": "image/png", ".ico": "image/x-icon", ".woff2": "font/woff2"}
DEFAULT_VALIDATION = Path(__file__).with_name("unit_validation.json")
NPC_NATIVE_PARENT = "/Script/ProjectPBZ.PBZCharacter_NPC"
NON_UNIT_NATIVE_PARENTS = {
    "/Script/SGameCombatSystem.SGameGameplayAbility",
    "/Script/PBZCombatAsset.WeaponActorBase",
    "/Script/PBZCombatAsset.WeaponActorBase_NoSkeletalMesh",
    "/Script/PBZCombatAsset.PBZ_ProjectileBullet",
    "/Script/SGameCombatSystem.BulletEventBase",
    "/Script/Engine.Actor",
    "/Script/Engine.ActorComponent",
}
ALLOWED_KEYS = {f"F{i}" for i in range(1,25) if i!=10} | {
    "NUM_" + name for name in ("ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE")
}


class ValidationError(ValueError):
    pass

def parse_binding(value):
    if value is None or value in ('', 'UNBOUND'):
        return {'key_code': 0, 'modifiers': 0}
    if isinstance(value, str):
        match=re.fullmatch(r'VK_(\d+)_MOD_(\d+)',value)
        digits=('ZERO','ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE')
        if match: vk,mods=map(int,match.groups())
        elif re.fullmatch(r'F(?:[1-9]|1\d|2[0-4])',value):vk,mods=111+int(value[1:]),0
        elif value.startswith('NUM_') and value[4:] in digits:vk,mods=96+digits.index(value[4:]),0
        elif re.fullmatch('[A-Z0-9]',value):vk,mods=ord(value),0
        else:raise ValidationError('不支持的按键名称：'+value[:32])
    elif isinstance(value,dict) and set(value)=={'key_code','modifiers'}:
        vk,mods=value['key_code'],value['modifiers']
    else:raise ValidationError('快捷键格式无效')
    special={8,9,13,19,20,32,33,34,35,36,37,38,39,40,45,46,144,145,186,187,188,189,190,191,192,219,220,221,222}
    if type(vk) is not int or type(mods) is not int or not 0<=mods<=7 or not (vk==0 or vk in special or 48<=vk<=57 or 65<=vk<=90 or 96<=vk<=135):
        raise ValidationError('无效的按键或组合键')
    return {'key_code':vk,'modifiers':mods if vk else 0}

def binding_token(value):
    entry=parse_binding(value)
    return f"VK_{entry['key_code']}_MOD_{entry['modifiers']}" if entry['key_code'] else 'UNBOUND'

def binding_system_owner(vk,mods):
    if vk in (121,192):return '游戏控制台'
    if vk in (91,92):return 'Windows系统键'
    if vk==82 and mods&1:return 'UE4SS重载Mod（Ctrl+R）'
    if vk==115 and mods&2:return '关闭窗口（Alt+F4）'
    if vk==9 and mods&2:return '切换窗口（Alt+Tab）'
    if vk==46 and mods&3==3:return 'Windows安全界面（Ctrl+Alt+Delete）'
    return None


def clean_field(value, name, limit=1024):
    if not isinstance(value, str) or not value or len(value) > limit:
        raise ValidationError(f"{name}: expected a nonempty string of at most {limit} characters")
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValidationError(f"{name}: control characters are forbidden")
    return value


def bounded_read(path: Path, limit: int, complete_lines=False):
    try:
        with path.open("rb") as stream:
            data = stream.read(limit + 1)
    except FileNotFoundError:
        return None
    if len(data) > limit:
        raise ValidationError(f"{path.name}: file exceeds {limit} bytes")
    if complete_lines and not data.endswith(b"\n"):
        # A concurrent Lua write can end halfway through a UTF-8 character.
        # Remove the unfinished line before decoding, not after.
        end = data.rfind(b"\n")
        data = data[:end + 1] if end >= 0 else b""
    return data.decode("utf-8-sig")


def atomic_text(path: Path, content: str):
    temporary = path.with_name(path.name + ".panel-tmp")
    with temporary.open("w", encoding="utf-8", newline="") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def tsv_rows(text):
    return csv.reader(io.StringIO(text), delimiter="\t", quoting=csv.QUOTE_NONE)


def native_parent_from_reason(reason):
    """Read only the exact metadata key, including UE's quoted class paths.

    Names, parent=, and package paths are not evidence of the native parent.
    Ambiguous or malformed metadata stays unknown rather than being guessed.
    """
    values = [part.split("=", 1)[1].strip() for part in reason.split(";")
              if part.startswith("native_parent=")]
    if len(values) != 1:
        return None
    value = values[0]
    if re.fullmatch(r"/Script/[A-Za-z0-9_]+\.[A-Za-z0-9_]+", value):
        return value
    wrapped = re.fullmatch(
        r"(?:/Script/[A-Za-z0-9_]+\.[A-Za-z0-9_]+|Class|BlueprintGeneratedClass)?"
        r"(?P<quote>['\"])(?P<path>/Script/[A-Za-z0-9_]+\.[A-Za-z0-9_]+)(?P=quote)", value)
    return wrapped.group("path") if wrapped else None


def trusted_codex_source(source):
    if source == "game_codex":
        return True
    return re.fullmatch(
        r"native_codex:FCodexEnemyRow(?:;replacement=/[^;\s]+)?"
        r"(?:;use_replacement_entry=(?:true|false))?"
        r";(?:EnemyClass|AliasEnemyClasses;canonical=(?:UNKNOWN|/[^;\s]+))", source) is not None


class RuntimeLease:
    """Only one HTTP bridge may dispatch for a runtime, even on different ports."""
    def __init__(self, path):
        self.file = path.open("a+b")
        try:
            self.file.seek(0, os.SEEK_END)
            if self.file.tell() == 0:
                self.file.write(b"0")
                self.file.flush()
            self.file.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            self.file.close()
            raise RuntimeError("已有面板后端使用此 Runtime；请复用该服务或先停止它。") from error

    def close(self):
        self.file.close()  # Releasing the handle releases its OS file lock.


class Bridge:
    def __init__(self, runtime_dir, clock=time.time, validation_path=None):
        self.runtime = Path(runtime_dir).expanduser().resolve()
        self.runtime.mkdir(parents=True, exist_ok=True)
        self.clock = clock
        self.validation_path = Path(validation_path) if validation_path else DEFAULT_VALIDATION
        self.lock = threading.RLock()
        self.disk_lock = threading.Lock()
        self.disk_cache = None
        self.transport_error = None
        database_path = self.runtime / "panel_queue.sqlite3"
        lock_path = self.runtime / "panel.lock"
        if database_path.resolve().parent != self.runtime or lock_path.resolve().parent != self.runtime:
            raise ValidationError("queue database resolves outside the runtime directory")
        self.lease = RuntimeLease(lock_path)
        self.db = sqlite3.connect(database_path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("""CREATE TABLE IF NOT EXISTS commands (
            id INTEGER PRIMARY KEY AUTOINCREMENT, action TEXT NOT NULL,
            payload TEXT NOT NULL, state TEXT NOT NULL, created REAL NOT NULL,
            sent REAL, completed REAL, message TEXT, spawned_count INTEGER, game_session TEXT)""")
        if "game_session" not in {row[1] for row in self.db.execute("PRAGMA table_info(commands)")}:
            self.db.execute("ALTER TABLE commands ADD COLUMN game_session TEXT")
        self.db.execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        self.db.commit()
        self.transport_code = None
        self._number_after_journal()

    def _journal_ids(self):
        """The game's record of the command ids it took (Runtime/command-journal.tsv): id -> last word."""
        try:
            text = bounded_read(self._path("command-journal.tsv"), MAX_GAME_JOURNAL_BYTES)
        except (OSError, UnicodeError, ValueError):
            return None
        ids = {}
        for line in (text or "").splitlines():
            first, _, rest = line.partition("\t")
            if first.isdigit():
                ids[int(first)] = rest.split("\t", 1)[0]
        return ids

    def _number_after_journal(self):
        # A new or emptied queue database numbers from 1 again, while the game still remembers the old ids and
        # answers a repeated id with the stored result of the old command, without running it. New ids go after them.
        ids = self._journal_ids()
        if not ids:
            return
        highest = max(ids)
        row = self.db.execute("SELECT seq FROM sqlite_sequence WHERE name='commands'").fetchone()
        if row is not None and row[0] >= highest:
            return
        with self.db:
            if row is None:
                self.db.execute("INSERT INTO sqlite_sequence(name,seq) VALUES('commands',?)", (highest,))
            else:
                self.db.execute("UPDATE sqlite_sequence SET seq=? WHERE name='commands'", (highest,))

    def close(self):
        with self.lock:
            self.db.close()
            self.lease.close()

    def _path(self, name):
        # All caller-supplied unit IDs stay inside TSV fields, never file paths.
        if name not in {"command-journal.tsv", "codex-icons.tsv", "home-levels.tsv", "stat-custom-request.tsv", "stat-match-settings.tsv", "companion-stats-request.tsv", "companion-stats-settings.tsv", "ai-params-request.tsv", "ai-params-settings.tsv", "catalog.tsv", "catalog.tsv.partial", "codex.tsv", "codex-locations.tsv", "status.tsv", "inbox.tsv", "inbox.session.tsv", "ack.tsv", "inventory-report.json", "unit-evidence.json", "native-table-catalog.tsv", "decrypted-directory.tsv", "decrypted-directory-report.json", "unit-keybinds.tsv", "unit-keybinds-state.tsv", "function-keybinds.tsv", "function-keybinds.tsv.bak", "function-keybinds-state.tsv", "keybinds.tsv"}:
            raise ValidationError("unknown runtime file")
        path = self.runtime / name
        if path.resolve().parent != self.runtime:
            raise ValidationError("runtime file resolves outside the configured directory")
        return path

    def _validation(self):
        text = bounded_read(self.validation_path, 65536)
        if text is None:
            raise ValidationError("unit_validation.json missing; no spawn permission")
        policy = json.loads(text)
        if not isinstance(policy, dict) or policy.get("schema_version") != 1 or not isinstance(policy.get("units"), dict):
            raise ValidationError("unit_validation.json schema is invalid")
        return {path: entry for path, entry in policy["units"].items()
                if isinstance(entry, dict) and entry.get("allow_spawn") is True
                and entry.get("class_path") == path
                and (entry.get("validation_status") == "verified_spawn_observation"
                     or (entry.get("validation_status") == "controlled_test"
                         and entry.get("max_count") == 1 and entry.get("max_live") == 2))
                and isinstance(entry.get("evidence"), list) and entry["evidence"]}

    def _codex_evidence(self):
        """Optional exported game evidence; duplicate paths fail closed for labels."""
        evidence, errors, seen = {}, [], set()
        try:
            text = bounded_read(self._path("codex.tsv"), 8 * 1024 * 1024)
            if text is None:
                return evidence, errors
            rows = tsv_rows(text)
            fields = tuple(next(rows, []))
            if fields not in (CODEX_FIELDS, CODEX_FIELDS_NAMED):
                raise ValidationError("codex.tsv: unsupported header")
            for number, row in enumerate(rows, 2):
                if not row:
                    continue
                path = row[0]
                try:
                    clean_field(path, "class_path", 2048)
                    if path in seen:
                        evidence.pop(path, None)
                        raise ValidationError("duplicate/contradictory class_path; all evidence for this path ignored")
                    seen.add(path)
                    if len(row) != len(fields):
                        raise ValidationError("wrong column count")
                    item = dict(zip(fields, row))
                    if item.get("name"):
                        clean_field(item["name"], "name", 512)
                    if not LANGUAGE_CODE.fullmatch(item.get("name_lang", "")):
                        raise ValidationError("invalid name_lang")
                    if not trusted_codex_source(item["source"]):
                        raise ValidationError("source is not a recognized game codex exporter source")
                    item["source_detail"] = item["source"]
                    item["source"] = "game_codex"
                    if item["zh_name"]:
                        clean_field(item["zh_name"], "zh_name", 512)
                    item["is_boss"] = item["is_boss"].lower()
                    if item["is_boss"] not in {"true", "false", "1", "0", "unknown", ""}:
                        raise ValidationError("invalid is_boss evidence")
                    item["enemy_type"] = CODEX_ENEMY_TYPES.get(item["enemy_type"], item["enemy_type"])
                    if item["enemy_type"] == "UNKNOWN":
                        item["enemy_type"] = "unknown"
                    if item["enemy_type"] not in {"1", "2", "3", "4", "5", "unknown", ""}:
                        raise ValidationError("invalid enemy_type evidence")
                    evidence[path] = item
                except ValidationError as error:
                    evidence.pop(path, None)
                    if len(errors) < 20:
                        errors.append(f"codex.tsv line {number}: {error}")
        except (OSError, UnicodeError, ValueError) as error:
            return {}, [str(error)]
        return evidence, errors

    def _location_evidence(self, codex):
        result, errors, seen = {}, [], set()
        try:
            text = bounded_read(self._path('codex-locations.tsv'), 8 * 1024 * 1024)
            if text is None:
                return result, errors
            rows = tsv_rows(text)
            fields = _taxonomy_module.LOCATION_FIELDS
            if tuple(next(rows, [])) != fields:
                raise ValidationError('codex-locations.tsv: unsupported header')
            for number, values in enumerate(rows, 2):
                if not values:
                    continue
                path = values[0]
                try:
                    if path in seen:
                        result.pop(path, None)
                        raise ValidationError('duplicate class path; affiliation ignored')
                    seen.add(path)
                    if len(values) != len(fields):
                        raise ValidationError('wrong column count')
                    row = dict(zip(fields, values))
                    for key, value in row.items():
                        if value:
                            clean_field(value, key, 2048 if key.endswith('path') else 512)
                    kind, canonical = _taxonomy_module.identity(codex.get(path))
                    if kind == 'candidate' or canonical != row['canonical_class_path']:
                        raise ValidationError('no matching native codex identity/canonical class')
                    if row['source'] != 'native_codex_own_map_v1' or row['map_status'] not in {'assigned', 'unassigned', 'unknown'}:
                        raise ValidationError('unrecognized affiliation source/status')
                    if (row['map_status'] == 'assigned') != bool(row['own_map_id']):
                        raise ValidationError('map status and ID disagree')
                    if not row['own_map_id'] and any(row[k] for k in ('map_name', 'chapter_id', 'chapter_name', 'level_name')):
                        raise ValidationError('map metadata without a map ID')
                    if row['chapter_name'] and not row['chapter_id']:
                        raise ValidationError('chapter name without chapter ID')
                    for key in ('chapter_order', 'map_order', 'display_order'):
                        raw = row[key]
                        if raw and (not raw.isdigit() or int(raw) >= 1000000):
                            raise ValidationError('invalid native display order')
                        row[key] = int(raw) if raw else None
                    result[path] = row
                except ValidationError as error:
                    result.pop(path, None)
                    if len(errors) < 20:
                        errors.append(f'codex-locations.tsv line {number}: {error}')
        except (OSError, UnicodeError, ValueError) as error:
            return {}, [str(error)]
        return result, errors

    def _unit_shortcuts(self, epoch):
        try:
            source=bounded_read(self._path('unit-keybinds.tsv'),2*1024*1024)
            if source is None:return {},[]
            rows=tsv_rows(source);header=next(rows,[])
            if len(header)!=2 or header[0] not in ('UnitKeysV1','UnitKeysV2') or not header[1].isdigit():raise ValidationError('invalid unit key header')
            # V2 rows add the unit's own team and count; empty fields (and V1 rows) follow the current selection.
            columns=5 if header[0]=='UnitKeysV2' else 3
            revision=header[1];result={};seen=set()
            for row in rows:
                if not row:continue
                if len(row)!=columns:raise ValidationError('invalid unit key row')
                unit,key,mask=row[:3];clean_field(unit,'unit key path',512)
                vk,mod=int(key),int(mask)
                team,count=(row[3] or None,int(row[4]) if row[4] else None) if columns==5 else (None,None)
                if team not in (None,)+TEAMS or not (count is None or 1<=count<=MAX_SPAWN_COUNT):raise ValidationError('invalid unit key team or count')
                if not 1<=vk<=255 or not 0<=mod<=7 or unit in result or vk in seen:raise ValidationError('invalid or duplicated unit key')
                seen.add(vk);result[unit]={'key_code':vk,'modifiers':mod,'team':team,'count':count,'active':False,'message':'等待游戏确认'}
            status=bounded_read(self._path('unit-keybinds-state.tsv'),2*1024*1024)
            if status:
                states=tsv_rows(status);meta=next(states,[])
                if meta==['UnitKeyStateV1',revision,epoch] and epoch:
                    for row in states:
                        if len(row)==3 and row[0] in result and row[1] in ('0','1'):
                            result[row[0]]['active']=row[1]=='1';result[row[0]]['message']=row[2]
            return result,[]
        except (OSError,UnicodeError,ValueError,TypeError) as error:return {},[str(error)]

    def disk_directory(self, query='', kind='', offset=0, limit=100):
        if not isinstance(query,str) or len(query)>256 or any(ord(c)<32 for c in query):
            raise ValidationError('invalid directory search')
        if kind not in ('','package','bulk','script','config','other') or not 0<=offset<=2000000 or not 1<=limit<=100:
            raise ValidationError('invalid directory filter/page')
        with self.disk_lock:
            report_path=self._path('decrypted-directory-report.json');index_path=self._path('decrypted-directory.tsv')
            if not report_path.exists() or not index_path.exists():
                return {'available':False,'verified':False,'total':0,'matched':0,'files':[],'directory_only':True}
            stamp=(report_path.stat().st_mtime_ns,index_path.stat().st_mtime_ns,index_path.stat().st_size)
            if self.disk_cache is None or self.disk_cache[0]!=stamp:
                report=json.loads(bounded_read(report_path,1024*1024))
                if report.get('schema_version')!=1 or report.get('verified') is not True or report.get('directory_only') is not True:
                    raise ValidationError('directory verification report unavailable')
                if stamp[2]>256*1024*1024:raise ValidationError('directory index exceeds size limit')
                records=[]
                with index_path.open(encoding='utf-8-sig',newline='') as stream:
                    reader=csv.DictReader(stream,delimiter='\t')
                    expected=('file_path','container','container_type','entry_index','chunk_id','logical_size','virtual_package')
                    if tuple(reader.fieldnames or ())!=expected:raise ValidationError('unsupported directory index schema')
                    for row in reader:
                        if None in row or any(v is None for v in row.values()):raise ValidationError('incomplete directory index')
                        suffix=row['file_path'].rsplit('.',1)[-1].lower()
                        category=('package' if suffix in ('uasset','umap') else 'bulk' if suffix in ('ubulk','uptnl')
                            else 'script' if suffix in ('js','mjs','cjs','ts','lua','jsc') else 'config' if suffix in ('ini','json','csv','xml','toml','yaml') else 'other')
                        records.append({'file_path':row['file_path'],'container':row['container'],'kind':category,
                            'logical_size':int(row['logical_size']) if row['logical_size'].isdigit() else None,
                            'virtual_package':row['virtual_package'],'search':(row['file_path']+' '+row['virtual_package']).casefold()})
                        if len(records)>2000000:raise ValidationError('too many directory records')
                if len(records)!=report.get('files'):raise ValidationError('directory/report count mismatch')
                records.sort(key=lambda r:r['file_path'].casefold())
                self.disk_cache=(stamp,records,report)
            _,records,report=self.disk_cache
            term=query.casefold().strip()
            selected=[r for r in records if (not term or term in r['search']) and (not kind or r['kind']==kind)] if term or kind else records
            return {'available':True,'verified':True,'directory_only':True,'total':len(records),'matched':len(selected),'offset':offset,'limit':limit,
                'registry_crosscheck':report.get('registry_crosscheck'),
                'files':[{k:v for k,v in r.items() if k!='search'} for r in selected[offset:offset+limit]]}

    def catalog(self):
        all_catalog=False
        try:
            policy_settings=json.loads(bounded_read(self.validation_path,65536) or '{}')
            all_catalog=policy_settings.get('allow_all_catalog') is True
        except (OSError,UnicodeError,ValueError,TypeError):
            pass
        final_path = self._path("catalog.tsv")
        partial_path = self._path("catalog.tsv.partial")
        values = self.game_status().get("values", {})
        shortcuts,shortcut_errors=self._unit_shortcuts(values.get('unit_keys_epoch',''))
        use_partial = False
        if partial_path.exists() and (values.get("catalog_state") == "scanning" or not final_path.exists()):
            try:
                partial_time = partial_path.stat().st_mtime
                started = float(values.get("catalog_started_at", "nan"))
                if math.isfinite(started) and started > 0:
                    use_partial = partial_time >= started
                elif final_path.exists():
                    use_partial = partial_time > final_path.stat().st_mtime
            except (FileNotFoundError, ValueError):
                use_partial = False
        text = bounded_read(partial_path if use_partial else final_path, 32 * 1024 * 1024, complete_lines=use_partial)
        if text is None and use_partial:  # Lua may have published it with an atomic rename.
            text = bounded_read(final_path, 32 * 1024 * 1024)
            use_partial = False
        if text is None:
            return {"available": False, "partial": False, "units": [], "errors": [], "total": 0, "excluded_non_units": 0, "codex_errors": []}
        rows = tsv_rows(text)
        header = next(rows, [])
        if tuple(header) != CATALOG_FIELDS:
            raise ValidationError("catalog.tsv: unsupported header")
        items, errors, seen = [], [], set()
        codex, codex_errors = self._codex_evidence()
        locations, location_errors = self._location_evidence(codex)
        audit, unit_proofs, audit_errors = {}, {}, []
        try:
            report_text=bounded_read(self._path('inventory-report.json'),4*1024*1024)
            proof_text=bounded_read(self._path('unit-evidence.json'),16*1024*1024)
            if report_text and proof_text:
                report=json.loads(report_text);proof=json.loads(proof_text)
                if report.get('schema_version')!=1 or report.get('inventory_verified') is not True or proof.get('schema_version')!=1 or proof.get('scope')!='current_mounted_registry':
                    raise ValidationError('unsupported inventory evidence')
                audit={k:report.get(k) for k in ('asset_count','paths_verified','inventory_verified','created_utc','configured_unit_classes','configured_maps','all_maps_spawn_coverage','physical_encrypted_container_coverage')}
                for entry in proof.get('units',[]):
                    if not isinstance(entry,dict):continue
                    path=entry.get('class_path');kind=entry.get('unit_kind');chain=entry.get('inheritance_chain',[])
                    roots={'npc':'/Script/ProjectPBZ.PBZCharacter_NPC','player':'/Script/ProjectPBZ.PBZCharacter_Player','character':'/Script/Engine.Character','pawn':'/Script/Engine.Pawn'}
                    if kind not in roots or not chain or chain[0]!=path or chain[-1]!=roots[kind] or entry.get('source')!='asset_registry_and_header_inheritance':continue
                    if path in unit_proofs:raise ValidationError('duplicate unit inheritance evidence')
                    unit_proofs[path]=entry
        except (OSError,UnicodeError,ValueError,TypeError,KeyError) as error:
            audit,unit_proofs={},{};audit_errors=[str(error)]
        map_names={row['own_map_id']:row['map_name'] for row in locations.values() if row['own_map_id']}
        try:
            validation = self._validation()
        except (OSError, UnicodeError, ValueError) as error:
            validation = {}
            errors.append(str(error))
        excluded_non_units = 0
        for number, row in enumerate(rows, 2):
            if not row:
                continue
            try:
                if len(row) != len(CATALOG_FIELDS):
                    raise ValidationError("wrong column count")
                item = dict(zip(CATALOG_FIELDS, row))
                raw_reason = item["reason"]
                clean_field(item["id"], "id")
                clean_field(item["name"], "name", 512)
                clean_field(item["class_path"], "class_path", 2048)
                for flag in ("loaded", "spawnable"):
                    if item[flag] not in {"0", "1", "unknown"}:
                        raise ValidationError(f"invalid {flag}")
                    item[flag] = {"0": False, "1": True, "unknown": None}[item[flag]]
                if item["id"] in seen:
                    raise ValidationError("duplicate unit id")
                seen.add(item["id"])
                native_parent = native_parent_from_reason(item["reason"])
                if native_parent in NON_UNIT_NATIVE_PARENTS:
                    excluded_non_units += 1
                    continue
                item["native_parent"] = native_parent
                if native_parent != NPC_NATIVE_PARENT:
                    item["spawnable"] = False
                    marker = "native_parent_unknown" if native_parent is None else "npc_identity_unknown"
                    item["reason"] = marker + ";NPC身份未验证；" + item["reason"]
                if item["class_path"].rsplit(".", 1)[-1].endswith("_Base_C"):
                    item["spawnable"] = False
                    item["reason"] = "基类不可召唤；" + item["reason"]
                if item["id"] == item["class_path"] and item["class_path"] in validation:
                    policy_entry = validation[item["class_path"]]
                    item["validation_status"] = policy_entry["validation_status"]
                    controlled = item["validation_status"] == "controlled_test"
                    item["max_count"] = 1 if controlled else MAX_SPAWN_COUNT
                    item["validation_scope"] = ("普通暴徒单只测试；生成和互伤尚未验证，每次1只、场上最多2只" if controlled
                        else "仅该具体路径有生成观察；不表示战斗通过或所有场景安全")
                    if policy_entry.get("battle_excluded_reason"):
                        item["validation_scope"] += "；" + policy_entry["battle_excluded_reason"]
                    item["reason"] = item["validation_scope"] + "；" + item["reason"]
                else:
                    item["spawnable"] = False
                    item["validation_status"] = "unverified"
                    item["validation_scope"] = "未验证，暂不可直接召唤"
                    item["reason"] = item["validation_scope"] + "；" + item["reason"]
                label_input = {**item, "reason": raw_reason, "native_parent": native_parent or "unresolved"}
                parent_path = _labels_module.parent_class_path(label_input)
                item["parent_class_path"] = parent_path or None
                label_input["parent_class_path"] = item["parent_class_path"]
                parent_evidence = codex.get(parent_path)
                labels = decorate_row(label_input, codex.get(item["class_path"]), parent_evidence)
                item["source_detail"] = codex.get(item["class_path"], {}).get("source_detail")
                item["parent_source_detail"] = parent_evidence.get("source_detail") if parent_evidence else None
                item["registry_category"] = item["category"]
                # Display metadata must never overwrite IDs or spawn qualification.
                for field in LABEL_FIELDS:
                    if field in labels:
                        item[field] = labels[field]
                item["is_special"] = item.get("category") == "特殊实体"
                item.update(_taxonomy_module.decorate(item, codex.get(item['class_path']), locations.get(item['class_path'])))
                proof=unit_proofs.get(item['class_path'])
                if proof and proof.get('native_parent')==native_parent:
                    item['resolved_unit_kind']=proof['unit_kind']
                    item['inheritance_verified']=True
                    mids=proof.get('configured_maps',[])
                    if not isinstance(mids,list) or not all(isinstance(m,str) and len(m)<=256 and not any(ord(c)<32 for c in m) for m in mids):mids=[]
                    item['configured_maps']=mids
                    item['configured_map_names']=[map_names.get(m) or m for m in mids]
                    count=proof.get('configured_spawner_count',0)
                    item['configured_spawner_count']=count if type(count) is int and 0<=count<=1000000 else 0
                    item['configuration_basis']='已读取地图刷怪器的Class/随机候选配置；不代表全部地图或已实际刷出'
                    item['purpose_hint']=proof.get('purpose_hint')
                    if item['codex_entry_kind']=='candidate' and item['browse_type'] not in ('模板／测试','召唤／分身'):
                        if proof['unit_kind']=='player':
                            item['browse_type']='玩家角色';item['browse_type_basis']='原生继承链确认玩家角色类；不是战斗NPC验收'
                        elif proof.get('purpose_hint')=='cinematic':
                            item['browse_type']='演出角色候选';item['browse_type_basis']='ActorForSeqs目录/父类与Character继承；演出用途线索'
                        elif proof['unit_kind'] in ('character','pawn'):
                            item['browse_type']='通用角色候选';item['browse_type_basis']='继承链确认角色/Pawn；具体用途与战斗能力未验证'
                if all_catalog and re.fullmatch(r'/[A-Za-z0-9_/.-]+\.[A-Za-z0-9_-]+_C',item['class_path']) and '..' not in item['class_path']:
                    item['spawnable']=True
                    item['max_count']=MAX_SPAWN_COUNT
                    item['validation_status']='experimental_spawn'
                    item['validation_scope']='用户开启全部目录尝试召唤；运行时仍核对Actor类和对象，生成及战斗兼容性未保证'
                    item['reason']=item['validation_scope']+'；'+raw_reason
                item['unit_shortcut']=shortcuts.get(item['id'])
                items.append(item)
            except ValidationError as error:
                if len(errors) < 20:
                    errors.append(f"line {number}: {error}")
        primary = [u for u in items if u['codex_entry_kind'] == 'primary']
        name_counts = {}
        for u in primary:
            name_counts[u.get('display_name')] = name_counts.get(u.get('display_name'), 0) + 1
        for u in items:
            u['same_name_count'] = name_counts.get(u.get('display_name'), 0)
        return {"available": True, "partial": use_partial, "units": items, "errors": errors,
                "total": len(items), "excluded_non_units": excluded_non_units, "codex_errors": codex_errors,
                'location_errors': location_errors, 'primary_count': len(primary),
                'inventory_audit':audit,'inventory_errors':audit_errors,
                'configured_count':sum(u.get('configured_spawner_count',0)>0 for u in items),
                'mapped_count': sum(bool(u['map_id']) for u in primary),
                'spawn_mode':'all_catalog' if all_catalog else 'validated',
                'unit_shortcuts_supported':True,'unit_shortcut_errors':shortcut_errors,
                'location_scope': '图鉴归属，不是全部出现地图或刷怪地点'}

    def game_status(self):
        try:
            text = bounded_read(self._path("status.tsv"), 65536)
            if text is None:
                return {"online": False, "ready": False, "game_session": None, "state": "unavailable", "message": "等待游戏写入状态", "age_seconds": None}
            values = {}
            for row in tsv_rows(text):
                if not row:
                    continue
                if len(row) != 2:
                    raise ValidationError("status.tsv: expected key/value rows")
                values[row[0]] = row[1]
            if values.get("schema_version") != "1":
                raise ValidationError("status.tsv: unsupported schema_version")
            heartbeat = float(values["heartbeat_unix"])
            if not math.isfinite(heartbeat):
                raise ValidationError("status.tsv: heartbeat must be finite")
            age = self.clock() - heartbeat
            connected = 0 <= age <= 15
            session = values.get("game_session") or None
            if session is not None:
                clean_field(session, "game_session", 160)
            ready = connected and session is not None and values.get("game_ready") == "true"
            return {"online": connected, "ready": ready, "game_session": session, "state": values.get("state", "unknown"),
                    "message": values.get("message", ""), "age_seconds": age,
                    "values": values, "status": values}
        except (OSError, UnicodeError, ValueError, KeyError) as error:
            return {"online": False, "ready": False, "game_session": None, "state": "invalid_status", "message": str(error), "age_seconds": None}

    def _validate(self, request):
        if not isinstance(request, dict):
            raise ValidationError("command must be an object")
        action = request.get("action")
        if not isinstance(action, str) or action not in ACTIONS:
            raise ValidationError("unsupported action")
        allowed = {"action"}
        payload = {"action": action}
        if action in {"spawn", "select_unit"}:
            allowed |= {"unit_id", "team", "count"}
            unit_id = clean_field(request.get("unit_id"), "unit_id")
            if len(unit_id.encode("utf-8")) > MAX_UNIT_ID_BYTES:
                raise ValidationError("unit_id: exceeds 512 UTF-8 bytes")
            unit = next((item for item in self.catalog()["units"] if item["id"] == unit_id), None)
            if unit is None:
                raise ValidationError("unit_id is not present in the exported catalog")
            if unit["spawnable"] is False:
                raise ValidationError("unit is marked unavailable for spawning: " + unit["reason"])
            team = request.get("team", "blue")
            if not isinstance(team, str) or team not in TEAMS:
                raise ValidationError("team must be blue, red, neutral or companion")
            count = request.get("count", 1)
            if type(count) is not int or not 1 <= count <= MAX_SPAWN_COUNT:
                raise ValidationError("count must be an integer from 1 to %d" % MAX_SPAWN_COUNT)
            if count > unit.get("max_count", MAX_SPAWN_COUNT):
                raise ValidationError("该单位处于单只测试阶段，数量必须为 1")
            payload.update(unit_id=unit_id, team=team, count=count)
        elif action == 'configure_unit_key':
            allowed|={'unit_id','key_code','modifiers','team','count'}
            unit_id=clean_field(request.get('unit_id'),'unit_id',512)
            if len(unit_id.encode('utf-8'))>MAX_UNIT_ID_BYTES:raise ValidationError('unit_id exceeds byte limit')
            unit=next((u for u in self.catalog()['units'] if u['id']==unit_id),None)
            if unit is None:raise ValidationError('unit is not in the catalogue')
            # Team and count come together: the key then summons this unit there, whatever the panel shows.
            if 'team' in request or 'count' in request:
                team,count=request.get('team'),request.get('count')
                if team not in TEAMS:raise ValidationError('team must be blue, red, neutral or companion')
                if type(count) is not int or not 1<=count<=min(MAX_SPAWN_COUNT,unit.get('max_count',MAX_SPAWN_COUNT)):raise ValidationError('count must be an integer from 1 to %d' % MAX_SPAWN_COUNT)
                payload.update(team=team,count=count)
            vk=request.get('key_code');mods=request.get('modifiers',0)
            if type(vk) is not int or not 0<=vk<=255 or type(mods) is not int or not 0<=mods<=7:raise ValidationError('invalid key or modifiers')
            entry=parse_binding({'key_code':vk,'modifiers':mods})
            blocked=binding_system_owner(vk,mods)
            if blocked:raise ValidationError('该键已被「'+blocked+'」占用')
            if vk:
                for name,binding in self.function_keybinds()['bindings'].items():
                    if binding['key_code']==vk:raise ValidationError('该键已被功能「'+BINDING_LABELS[name]+'」占用')
            payload.update(unit_id=unit_id,key_code=vk,modifiers=mods if vk else 0)
        elif action == 'set_spawn_difficulty':
            allowed.add('difficulty')
            difficulty = request.get('difficulty')
            if difficulty not in SPAWN_DIFFICULTIES:
                raise ValidationError('difficulty must be one of ' + ', '.join(SPAWN_DIFFICULTIES))
            payload['difficulty'] = difficulty
        elif action == 'set_boss_combos':
            allowed |= {'enabled'}
            enabled = request.get('enabled')
            if type(enabled) is not bool:
                raise ValidationError('enabled must be true or false')
            payload.update(enabled=enabled)
        elif action == 'set_fun_feature':
            allowed |= {'feature', 'enabled'}
            feature, enabled = request.get('feature'), request.get('enabled')
            if feature not in FUN_FEATURES:
                raise ValidationError('feature must be one of ' + ', '.join(FUN_FEATURES))
            if type(enabled) is not bool:
                raise ValidationError('enabled must be true or false')
            payload.update(feature=feature, enabled=enabled)
        elif action == 'set_team_immortal':
            allowed |= {'team', 'enabled'}
            team, enabled = request.get('team'), request.get('enabled')
            if team not in IMMORTAL_TEAMS:
                raise ValidationError('team must be one of ' + ', '.join(IMMORTAL_TEAMS))
            if type(enabled) is not bool:
                raise ValidationError('enabled must be true or false')
            payload.update(team=team, enabled=enabled)
        elif action in STAT_SETS:
            allowed |= {'mode', 'values', 'revision'}
            mode = request.get('mode')
            if mode not in STAT_SETS[action]['modes']:
                raise ValidationError('mode must be one of ' + ', '.join(STAT_SETS[action]['modes']))
            payload['mode'] = mode
            if mode == 'custom':
                values = request.get('values')
                if not isinstance(values, dict) or not values:
                    raise ValidationError('custom mode needs at least one value')
                clean = {}
                for field, value in values.items():
                    if field not in STAT_FIELDS:
                        raise ValidationError('unknown attribute: ' + str(field)[:64])
                    if type(value) not in (int, float) or not math.isfinite(value) or abs(value) > 1e9:
                        raise ValidationError(field + ' must be a finite number')
                    if field in STAT_POSITIVE and value <= 0:
                        raise ValidationError(field + ' must be greater than 0')
                    if field in STAT_NON_NEGATIVE and value < 0:
                        raise ValidationError(field + ' must not be negative')
                    clean[field] = value
                payload['values'] = clean
                # A stored payload is validated again right before delivery: keep the revision it was queued under.
                revision = request.get('revision')
                if revision is not None and not (isinstance(revision, str) and re.fullmatch(r'R[0-9A-F]{12}', revision)):
                    raise ValidationError('revision must be R and 12 hex digits')
                payload['revision'] = revision or 'R' + secrets.token_hex(6).upper()
        elif action == 'set_ai_params':
            allowed |= {'values', 'revision'}
            values = request.get('values')
            if not isinstance(values, dict):
                raise ValidationError('values must be an object')
            clean = {}
            for name, value in values.items():
                kind = AI_PARAMS.get(name)
                if kind is None:
                    raise ValidationError('unknown AI parameter: ' + str(name)[:64])
                if type(value) not in (int, float) or not math.isfinite(value) or abs(value) > 1e6:
                    raise ValidationError(name + ' must be a finite number')
                if kind == 'bool' and value not in (0, 1):
                    raise ValidationError(name + ' must be 0 or 1')
                if kind == 'int' and value != int(value):
                    raise ValidationError(name + ' must be a whole number')
                clean[name] = value
            payload['values'] = clean
            revision = request.get('revision')
            if revision is not None and not (isinstance(revision, str) and re.fullmatch(r'R[0-9A-F]{12}', revision)):
                raise ValidationError('revision must be R and 12 hex digits')
            payload['revision'] = revision or 'R' + secrets.token_hex(6).upper()
        elif action == 'set_spawn_level':
            # The stored payload is checked again before delivery, so it uses the request's own fields.
            allowed |= {'level_mode', 'level', 'unit_id'}
            mode, level = request.get('level_mode'), request.get('level')
            if mode not in SPAWN_LEVEL_MODES:
                raise ValidationError('level_mode must be one of ' + ', '.join(SPAWN_LEVEL_MODES))
            if level is not None and (type(level) is not int or not 0 <= level <= SPAWN_LEVEL_MAX):
                raise ValidationError('level must be a whole number from 0 to %d' % SPAWN_LEVEL_MAX)
            if mode == 'CUSTOM' and level is None:
                raise ValidationError('CUSTOM needs a level')
            payload.update(level_mode=mode, level=level if mode in ('CUSTOM', 'UNIT') else None)
            if mode == 'UNIT':
                unit = request.get('unit_id')
                if not (isinstance(unit, str) and UNIT_SHORT_ID.fullmatch(unit)):
                    raise ValidationError('unit_id must be a unit id such as BP_Monster_Name')
                payload['unit_id'] = unit
            elif 'unit_id' in request:
                raise ValidationError('unit_id goes only with UNIT')
        elif action == 'set_free_camera':
            allowed |= set(FREE_CAMERA_LIMITS)
            for field, (low, high) in FREE_CAMERA_LIMITS.items():
                value = request.get(field)
                if type(value) is not int or not low <= value <= high:
                    raise ValidationError('%s must be a whole number from %d to %d' % (field, low, high))
                payload[field] = value
        elif action == 'set_camera_track':
            allowed |= {'framing', 'resume', 'unit_id'}
            framing, resume, target = request.get('framing'), request.get('resume'), request.get('unit_id')
            if framing not in TRACK_FRAMINGS:
                raise ValidationError('framing must be one of ' + ', '.join(TRACK_FRAMINGS))
            if type(resume) is not int or not 0 <= resume <= TRACK_RESUME_MAX:
                raise ValidationError('resume must be a whole number from 0 to %d' % TRACK_RESUME_MAX)
            if target is not None and not (isinstance(target, str) and TRACK_TARGET.fullmatch(target)):
                raise ValidationError('unit_id must be the address of a unit on the field')
            payload.update(framing=framing, resume=resume)
            if target is not None:
                payload['unit_id'] = target
        elif action == 'set_unit_rule':
            allowed |= {'unit_id', 'rule', 'value'}
            unit, rule, value = request.get('unit_id'), request.get('rule'), request.get('value')
            if not (isinstance(unit, str) and UNIT_SHORT_ID.fullmatch(unit)):
                raise ValidationError('unit_id must be a unit id such as BP_Monster_Name')
            if rule not in UNIT_RULES or value not in UNIT_RULES[rule]:
                raise ValidationError('rule and value must be one of the unit rules')
            payload.update(unit_id=unit, rule=rule, value=value)
        elif action in ('set_clock_hud', 'set_execution_camera', 'set_companion_executions'):
            allowed.add('enabled')
            enabled = request.get('enabled')
            if type(enabled) is not bool:
                raise ValidationError('enabled must be true or false')
            payload['enabled'] = enabled
        elif action == "configure_keys":
            allowed.add("bindings")
            bindings = request.get("bindings")
            if not isinstance(bindings, dict) or set(bindings) != set(BINDING_NAMES):
                raise ValidationError("快捷键设置必须包含十三项功能，请刷新面板")
            parsed,seen = {},{}
            game=self.game_status();values=game.get('values',{})
            if values.get('function_keys_schema')!='4':raise ValidationError('游戏端尚未支持新版功能改键（镜头跟踪），请先更新并重载新版Mod')
            units,_=self._unit_shortcuts(values.get('unit_keys_epoch',''))
            for name, value in bindings.items():
                entry=parse_binding(value);vk,mods=entry['key_code'],entry['modifiers']
                blocked=binding_system_owner(vk,mods)
                if blocked:raise ValidationError('该键已被「'+blocked+'」占用')
                if vk:
                    if vk in seen:raise ValidationError('同一主键同时用于「'+BINDING_LABELS[seen[vk]]+'」和「'+BINDING_LABELS[name]+'」')
                    seen[vk]=name
                    owner=next((unit for unit,binding in units.items() if binding['key_code']==vk),None)
                    if owner:
                        row=next((unit for unit in self.catalog()['units'] if unit['id']==owner),{})
                        label=row.get('display_name') or row.get('name') or owner.rsplit('.',1)[-1]
                        raise ValidationError('该键已被单位「'+label+'」占用，请先解除该单位的绑定')
                parsed[name] = entry
            payload["bindings"] = parsed
        if set(request) - allowed:
            raise ValidationError("unknown command fields: " + ", ".join(sorted(set(request) - allowed)))
        return payload

    def enqueue(self, request):
        with self.lock:
            game = self.game_status()
            if not game["online"] or not game.get("game_session"):
                raise ValidationError("未建立当前游戏会话；目录可浏览，指令未提交，请游戏连接后重新请求")
            payload = self._validate(request)
            self._wire({"id": 9223372036854775807, "payload": json.dumps(payload, ensure_ascii=False)})
            if payload["action"] in STAT_SETS and payload["mode"] == "custom":
                # The values travel in a file of their own; the command names the revision to read.
                rows = "".join(f"{field}\t{payload['values'][field]!r}\n" for field in STAT_FIELDS if field in payload["values"])
                atomic_text(self._path(STAT_SETS[payload["action"]]["request"]), f"StatCustomV1\t{payload['revision']}\n{rows}")
            if payload["action"] == "set_ai_params":
                rows = "".join(f"{name}\t{value!r}\n" for name, value in payload["values"].items())
                atomic_text(self._path("ai-params-request.tsv"), f"AIParamsV1\t{payload['revision']}\n{rows}")
            with self.db:
                cursor = self.db.execute("INSERT INTO commands(action,payload,state,created,game_session) VALUES(?,?,?,?,?)",
                    (payload["action"], json.dumps(payload, ensure_ascii=False), "pending", self.clock(), game["game_session"]))
                if payload["action"] == "configure_keys":
                    self.db.execute("INSERT OR REPLACE INTO settings(key,value) VALUES('requested_keys',?)",
                        (json.dumps(payload["bindings"]),))
            return self._command(cursor.lastrowid)

    def _command(self, command_id):
        row = self.db.execute("SELECT * FROM commands WHERE id=?", (command_id,)).fetchone()
        if row is None:
            return None
        result = dict(row)
        result["payload"] = json.loads(result["payload"])
        result["status"] = {"pending": "queued", "inflight": "pending"}.get(result["state"], result["state"])
        return result

    @staticmethod
    def _wire(row):
        payload = json.loads(row["payload"])
        bindings = payload.get("bindings", {})
        if payload['action']=='configure_unit_key':
            bindings={'spawn':'VK_'+str(payload['key_code']) if payload['key_code'] else 'UNBOUND',
                      'start':'MOD_'+str(payload['modifiers'])}
            if 'team' in payload:bindings['stop']='FIXED'
        elif payload['action']=='set_spawn_difficulty':
            bindings={'spawn':payload['difficulty']}
        elif payload['action']=='set_boss_combos':
            bindings={'spawn':'ON' if payload['enabled'] else 'OFF'}
        elif payload['action']=='set_fun_feature':
            bindings={'spawn':payload['feature'],'start':'ON' if payload['enabled'] else 'OFF'}
        elif payload['action'] in STAT_SETS:
            bindings={'spawn':STAT_MODES[payload['mode']],'start':payload.get('revision','')}
        elif payload['action']=='set_ai_params':
            bindings={'spawn':payload['revision']}
        elif payload['action']=='set_spawn_level':
            bindings={'spawn':payload['level_mode'],'start':'' if payload.get('level') is None else str(payload['level'])}
        elif payload['action']=='set_free_camera':
            bindings={'spawn':str(payload['speed']),'start':str(payload['turn']),'stop':str(payload['smooth'])}
        elif payload['action'] in ('set_team_immortal','set_clock_hud','set_execution_camera','set_companion_executions'):
            bindings={'start':'ON' if payload['enabled'] else 'OFF'}
        elif payload['action']=='set_unit_rule':
            bindings={'spawn':payload['rule'].upper(),'start':payload['value'].upper()}
        elif payload['action']=='set_camera_track':
            bindings={'spawn':payload['framing'].upper(),'start':str(payload['resume'])}
        fields = [str(row["id"]), payload["action"], payload.get("unit_id", ""),
                  payload.get("team", "blue"), str(payload.get("count", 1))]
        if payload['action']=='configure_keys':
            fields.extend(binding_token(bindings.get(name)) for name in BINDING_NAMES)
            fields.append('4')
        else:
            fields.extend(bindings.get(name, "") for name in LEGACY_BINDING_NAMES)
            fields.append("1")
        wire = "\t".join(fields) + "\n"
        if len(fields[2].encode("utf-8")) > MAX_UNIT_ID_BYTES or len(wire.encode("utf-8")) > MAX_INBOX_BYTES:
            raise ValidationError("command exceeds Lua inbox limits (unit_id 512 UTF-8 bytes; inbox 2048 bytes)")
        return wire

    def _clear_delivery(self, command_id):
        # Only retire this database command's delivery files, never sweep Runtime. Windows refuses to delete a file
        # that the game (which reads the inbox on every tick until it goes) or a virus scanner holds open; that file
        # is left for _retire_deliveries() to try again. Before v0.38.1 the error left it behind for good, and every
        # later command waited behind an inbox "without an owner", through app, game and PC restarts.
        cleared = True
        for name in ("inbox.tsv", "inbox.session.tsv"):
            path = self._path(name)
            try:
                content = bounded_read(path, 8192)
                if content is not None and content.split("\t", 1)[0] == str(command_id):
                    path.unlink()
            except FileNotFoundError:
                pass
            except (OSError, UnicodeError, ValueError):
                cleared = False
        return cleared

    def _problem(self, code, message):
        self.transport_code, self.transport_error = code, message

    def _retire_deliveries(self):
        """Nothing in flight: the delivery files of a finished command go, an unknown inbox holds the queue."""
        inbox = self._path("inbox.tsv")
        content = bounded_read(inbox, 8192)
        if content is not None:
            first = content.split("\t", 1)[0]
            row = self.db.execute("SELECT state FROM commands WHERE id=?", (int(first),)).fetchone() if first.isdigit() else None
            if row is None or row["state"] not in TERMINAL_STATES:
                self._problem("orphan_inbox", f"Runtime 里有一条不在队列里的指令文件（inbox.tsv，编号 {first[:24]}）；"
                              "为免游戏重复执行，暂停投递。可在操作记录里点「清理排队的指令」")
                return False
            if not self._clear_delivery(first) or inbox.exists():
                self._problem("inbox_locked", "上一条指令的投递文件暂时删不掉（可能被游戏或杀毒软件占用），稍后自动重试")
                return False
        sidecar = self._path("inbox.session.tsv")
        if sidecar.exists():
            # Without an inbox the game runs nothing: the session binding alone is safe to remove.
            try:
                sidecar.unlink()
            except FileNotFoundError:
                pass
            except OSError:
                self._problem("inbox_locked", "上一条指令的会话绑定文件暂时删不掉（可能被占用），稍后自动重试")
                return False
        return True

    def _republish_or_wait(self, current, session):
        # A command in flight without its inbox: only tick() writes that file and it is removed only after the
        # command has finished, so the publication failed (a file in use, a full disk) unless the game read it.
        # The game journals an id before it runs it: no record means it never saw the command, which goes out again.
        ids = self._journal_ids()
        if ids is not None and current["id"] not in ids and session and current["game_session"] == session:
            atomic_text(self._path("inbox.session.tsv"), f"{current['id']}\t{session}\n")
            atomic_text(self._path("inbox.tsv"), self._wire(current))
            self._problem("republished", "上一条指令没投递成功，游戏也没有收到；已重新投递")
            return
        self._problem("waiting_ack", "已投递指令的 inbox 不在；等待同序号 ACK，不自动重放")

    def clear_queue(self):
        """The app's 清理排队的指令: every waiting command is dropped and the delivery files go, whoever they belong to."""
        with self.lock:
            now = self.clock()
            waiting = self.db.execute("SELECT COUNT(*) FROM commands WHERE state='pending'").fetchone()[0]
            sent = self.db.execute("SELECT COUNT(*) FROM commands WHERE state='inflight'").fetchone()[0]
            with self.db:
                self.db.execute("UPDATE commands SET state='failed',completed=?,message=? WHERE state='pending'", (now, CLEARED_PENDING))
                self.db.execute("UPDATE commands SET state='uncertain',completed=?,message=? WHERE state='inflight'", (now, CLEARED_INFLIGHT))
            left = []
            for name in ("inbox.tsv", "inbox.session.tsv"):
                try:
                    self._path(name).unlink()
                except FileNotFoundError:
                    pass
                except OSError:
                    left.append(name)
            self.transport_error = self.transport_code = None
            return {"cleared": waiting, "interrupted": sent, "files_left": left}

    def _expire_stale_sessions(self, session):
        stale = self.db.execute("SELECT * FROM commands WHERE state IN ('pending','inflight') AND (game_session IS NULL OR game_session<>?)", (session,)).fetchall()
        for row in stale:
            state = "uncertain" if row["state"] == "inflight" else "failed"
            message = ("uncertain: 游戏会话已变化，旧投递结果未确认，不重发；请检查游戏后重新请求"
                       if state == "uncertain" else "旧游戏会话的排队指令已取消，未投递；请在当前会话重新请求")
            with self.db:
                self.db.execute("UPDATE commands SET state=?,completed=?,message=? WHERE id=?", (state, self.clock(), message, row["id"]))
            if row["state"] == "inflight":
                self._clear_delivery(row["id"])

    def tick(self):
        with self.lock:
            self.transport_error = self.transport_code = None
            try:
                game = self.game_status()
                session = game.get("game_session") if game["online"] else None
                if session:
                    self._expire_stale_sessions(session)
                current = self.db.execute("SELECT * FROM commands WHERE state='inflight' ORDER BY id LIMIT 1").fetchone()
                inbox = self._path("inbox.tsv")
                if current:
                    ack = bounded_read(self._path("ack.tsv"), 8192)
                    if ack:
                        rows = list(tsv_rows(ack))
                        if len(rows) != 1 or len(rows[0]) != 4:
                            raise ValidationError("ack.tsv: expected one row with four columns")
                        command_id, outcome, message, count = rows[0]
                        if command_id == str(current["id"]):
                            if outcome not in {"ok", "error", "uncertain"}:
                                raise ValidationError("ack.tsv: invalid status")
                            spawned = None if count in {"", "unknown"} else int(count)
                            if spawned is not None and not 0 <= spawned <= MAX_SPAWN_COUNT:
                                raise ValidationError("ack.tsv: invalid spawned_count")
                            if outcome == "ok" and current["action"] == "spawn" and spawned is None:
                                raise ValidationError("ack.tsv: successful spawn requires an observed integer count")
                            state = {"ok": "succeeded", "error": "failed", "uncertain": "uncertain"}[outcome]
                            if "uncertain" in message.lower():
                                state = "uncertain"
                            existing = bounded_read(inbox, 8192)
                            if existing is not None and existing.split("\t", 1)[0] != command_id:
                                raise ValidationError("inbox.tsv belongs to another command; refusing to overwrite")
                            with self.db:
                                self.db.execute("UPDATE commands SET state=?,completed=?,message=?,spawned_count=? WHERE id=?",
                                    (state, self.clock(), message, spawned, current["id"]))
                            self._clear_delivery(current["id"])
                            current = None
                    if current:
                        if not inbox.exists():
                            self._republish_or_wait(current, session)
                        elif self.clock() - (current["sent"] or current["created"]) > SLOW_ACK_SECONDS:
                            values = game.get("values") or {}
                            state = values.get("state")
                            self._problem("slow_game", "游戏%d秒还没回复这条指令%s" % (int(self.clock() - (current["sent"] or current["created"])),
                                "（游戏端：" + str(values.get("message", ""))[:200] + "）" if state == "unknown" else ""))
                        return
                if not self._retire_deliveries():
                    return
                pending = self.db.execute("SELECT * FROM commands WHERE state='pending' ORDER BY id LIMIT 1").fetchone()
                if pending:
                    if not session or pending["game_session"] != session:
                        self._problem("waiting_session", "等待当前游戏会话；未投递排队指令")
                        return
                    if pending["action"] in READY_ACTIONS and not game["ready"]:
                        if self.clock() - pending["created"] > READY_WAIT_SECONDS:
                            with self.db:
                                self.db.execute("UPDATE commands SET state='failed',completed=?,message=? WHERE id=?",
                                    (self.clock(), READY_TIMEOUT, pending["id"]))
                            return
                        self._problem("waiting_ready", "等待游戏进入地图并报告game_ready=true；未投递召唤/开战/观战切换")
                        return
                    try:
                        self._validate(json.loads(pending["payload"]))
                    except ValidationError as error:
                        with self.db:
                            self.db.execute("UPDATE commands SET state='failed',completed=?,message=? WHERE id=?", (self.clock(), "投递前资格检查失败，未执行：" + str(error), pending["id"]))
                        return
                    # Commit before publishing. A crash in this gap leaves a visible
                    # uncertain command instead of replaying a potentially executed action.
                    with self.db:
                        self.db.execute("UPDATE commands SET state='inflight',sent=? WHERE id=?", (self.clock(), pending["id"]))
                    atomic_text(self._path("inbox.session.tsv"), f"{pending['id']}\t{session}\n")
                    atomic_text(inbox, self._wire(pending))
            except (OSError, UnicodeError, ValueError, sqlite3.Error) as error:
                self._problem("error", str(error))

    def function_keybinds(self):
        game=self.game_status();values=game.get('values',{})
        bindings={name:{'key_code':0,'modifiers':0,'active':False,'message':''} for name in BINDING_NAMES}
        revision=0;errors=[]
        def read_keys(name):
            try:
                content=bounded_read(self._path(name),65536)
                return content,content is not None
            except (OSError,UnicodeError,ValueError) as error:
                errors.append(str(error));return None,True
        def parse_saved(source):
            rows=[row for row in tsv_rows(source) if row];header=rows.pop(0) if rows else []
            if len(header)!=2 or header[0]!='FunctionKeysV2' or not header[1].isdigit():raise ValidationError('功能快捷键文件格式无效')
            rev=int(header[1]);parsed={};seen=set()
            if rev>2147483646:raise ValidationError('功能快捷键版本号无效')
            for row in rows:
                if len(row)!=3 or row[0] not in BINDING_NAMES or row[0] in parsed:raise ValidationError('功能快捷键条目无效')
                entry=parse_binding({'key_code':int(row[1]),'modifiers':int(row[2])})
                if binding_system_owner(entry['key_code'],entry['modifiers']):raise ValidationError('功能快捷键占用了系统保留组合')
                if entry['key_code'] and entry['key_code'] in seen:raise ValidationError('功能快捷键存在重复主键')
                if entry['key_code']:seen.add(entry['key_code'])
                parsed[row[0]]=entry
            if not set(V2_BINDING_NAMES)<=set(parsed):raise ValidationError('功能快捷键条目不完整')
            return parsed,rev
        loaded=False;primary_present=False
        for name in ('function-keybinds.tsv','function-keybinds.tsv.bak'):
            source,present=read_keys(name)
            if name=='function-keybinds.tsv':primary_present=present
            if source is not None:
                try:
                    parsed,revision=parse_saved(source)
                    for action,entry in parsed.items():bindings[action].update(entry)
                    loaded=True;break
                except (ValueError,TypeError) as error:errors.append(str(error))
        if not loaded and not primary_present:
            legacy,_=read_keys('keybinds.tsv')
            if legacy:
                try:
                    rows=[row for row in tsv_rows(legacy) if row]
                    if len(rows)!=4 or {r[0] for r in rows if len(r)==2}!=set(LEGACY_BINDING_NAMES):raise ValidationError('旧快捷键文件格式无效')
                    for name,key in rows:bindings[name].update(parse_binding(key))
                except (ValueError,TypeError) as error:errors.append(str(error))
        if not loaded and errors and values.get('function_keys_schema') in FUNCTION_KEY_SCHEMAS:
            try:
                revision=int(values.get('function_keys_revision','0'))
                for name in BINDING_NAMES:
                    if 'key_'+name in values:bindings[name].update(parse_binding(values.get('key_'+name)))
            except (ValueError,TypeError) as error:errors.append(str(error))
        epoch=values.get('function_keys_epoch','')
        confirmed=bool(game['online'] and values.get('function_keys_schema') in FUNCTION_KEY_SCHEMAS and epoch and values.get('function_keys_revision')==str(revision))
        for name,entry in bindings.items():
            entry['active']=bool(confirmed and entry['key_code'] and values.get('key_'+name)==binding_token({'key_code':entry['key_code'],'modifiers':entry['modifiers']}))
            if entry['key_code'] and not entry['active']:entry['message']='等待游戏端确认绑定'
        state,_=read_keys('function-keybinds-state.tsv')
        if state and confirmed:
            rows=list(tsv_rows(state))
            if rows and rows[0]==['FunctionKeyStateV2',str(revision),epoch]:
                for row in rows[1:]:
                    if len(row)==3 and row[0] in bindings and row[2]:bindings[row[0]]['message']=row[2]
        return {'available':bool(game['online'] and game.get('game_session') and values.get('function_keys_schema')=='4' and epoch),
                'bindings':bindings,'revision':revision,'errors':errors}

    # A codex icon's texture name (codex_icons.lua): the only thing an icon URL or index row may carry.
    ICON_NAME = re.compile(r"T_[A-Za-z0-9_]{1,160}")
    UNIT_NAME = re.compile(r"[A-Za-z0-9_]{1,160}")

    def codex_icon_file(self, name):
        """The saved PNG for one icon texture, in Runtime/codex-icons/ or flat in Runtime; None if absent."""
        if not self.ICON_NAME.fullmatch(name or ""):
            return None
        for path in (self.runtime / "codex-icons" / f"{name}.png", self.runtime / f"codex-icon-{name}.png"):
            if path.is_file() and path.resolve().is_relative_to(self.runtime):
                return path
        return None

    def codex_icons(self):
        """Unit id -> icon URL for every icon the mod has saved on this PC (Runtime/codex-icons.tsv)."""
        text = bounded_read(self._path("codex-icons.tsv"), 262144) or ""
        icons = {}
        for line in text.replace("\r\n", "\n").split("\n")[1:]:
            unit, _, file = line.partition("\t")
            leaf = file.rsplit("/", 1)[-1]
            name = leaf[len("codex-icon-"):] if leaf.startswith("codex-icon-") else leaf
            name = name[:-4] if name.endswith(".png") else ""
            if self.UNIT_NAME.fullmatch(unit) and self.codex_icon_file(name):
                icons[unit] = f"/codex-icons/{name}.png"
        return {"icons": icons, "count": len(icons)}

    def unit_names(self):
        """Names in the player's game language by the app's unit id (the class's short name), with chapter and map
        names; empty until a mod that exports them (v0.37.5+) has run. The app keeps its Chinese names until then."""
        codex, _ = self._codex_evidence()
        locations, _ = self._location_evidence(codex)
        units, lang = {}, ""
        for path, item in codex.items():
            name = item.get("name") or ""
            if not name or not item.get("name_lang"):
                continue
            lang = lang or item["name_lang"]
            unit = path.rsplit("/", 1)[-1].split(".", 1)[0]
            place = locations.get(path) or {}
            units[unit] = {"name": name, "map": place.get("map_name") or "", "chapter": place.get("chapter_name") or ""}
        return {"lang": lang, "units": units, "count": len(units)}

    def home_levels(self):
        """Each unit's summon level choices (home_levels.lua, Runtime/home-levels.tsv): every place the game itself
        puts it with how many spawners put it there (native), else the areas of its codex home map, and a level the
        player picked, with the default and the pick marked. Empty until a mod that writes them (v0.37.6+) has run."""
        text = bounded_read(self._path("home-levels.tsv"), 2 * 1024 * 1024)
        units = {}
        lines = (text or "").replace("\r\n", "\n").split("\n")
        if not text or lines[0] != HOME_LEVEL_HEADER:
            return {"units": units, "count": 0}
        for line in lines[1:]:
            cols = line.split("\t")
            if len(cols) != 8 or not UNIT_SHORT_ID.fullmatch(cols[0]) or cols[2] not in HOME_LEVEL_SOURCES:
                continue
            unit, level, source, map_name, part, default, picked, count = cols
            if (not level.isdigit() or int(level) > SPAWN_LEVEL_MAX or len(map_name) > 64 or len(part) > 4
                    or not count.isdigit() or len(count) > 6):
                continue
            entry = units.setdefault(unit, {"options": [], "default": None, "picked": None})
            entry["options"].append({"level": int(level), "source": source, "map": map_name, "part": part,
                                     "count": int(count)})
            if default == "1":
                entry["default"] = len(entry["options"]) - 1
            if picked == "1":
                entry["picked"] = len(entry["options"]) - 1
        return {"units": units, "count": len(units)}

    def ai_params(self):
        """The AI parameter values the mod saved (ai_params.lua, Runtime/ai-params-settings.tsv)."""
        text = (bounded_read(self._path("ai-params-settings.tsv"), 65536) or "").replace("\r\n", "\n")
        values = {}
        for line in text.split("\n")[1:]:
            name, _, raw = line.partition("\t")
            if name not in AI_PARAMS:
                continue
            try:
                number = float(raw)
            except ValueError:
                continue
            if math.isfinite(number):
                values[name] = int(number) if number.is_integer() else number
        return {"values": values, "fields": list(AI_PARAMS)}

    def stat_settings(self, name="stat-match-settings.tsv"):
        """The spawn stat mode and custom values the mod saved (stat_match.lua): the arena's set, or the companions' file."""
        # Lua writes this file in text mode, so on Windows its lines end in CRLF.
        text = (bounded_read(self._path(name), 65536) or "").replace("\r\n", "\n")
        lines = text.split("\n")
        mode, values = "game", {}
        if text == "StatMatchV1\t1\n":
            mode = "match"
        elif lines[0].startswith("StatMatchV2\t"):
            saved = lines[0].split("\t", 1)[1]
            mode = saved if saved in STAT_MODES else "game"
            for line in lines[1:]:
                field, _, raw = line.partition("\t")
                if field not in STAT_FIELDS:
                    continue
                try:
                    number = float(raw)
                except ValueError:
                    continue
                if math.isfinite(number):
                    values[field] = int(number) if number.is_integer() else number
        return {"mode": mode, "values": values, "fields": list(STAT_FIELDS)}

    def keybinds(self):
        with self.lock:
            row = self.db.execute("SELECT value FROM settings WHERE key='requested_keys'").fetchone()
            values = self.game_status().get("values", {})
            return {"requested": json.loads(row[0]) if row else None,
                    "active": {name: values.get("key_" + name) for name in BINDING_NAMES},
                    "message": "提交仅请求保存；实际生效键以游戏状态为准，可能需要 Restart All Mods。"}

    def status(self):
        with self.lock:
            rows = self.db.execute("SELECT id FROM commands ORDER BY id DESC LIMIT 100").fetchall()
            try:
                catalog = self.catalog()
                catalog_summary = {key: catalog.get(key, []) if key == "codex_errors" else catalog[key]
                                   for key in ("available", "partial", "total", "errors", "excluded_non_units", "codex_errors")}
                catalog_summary.update(primary_count=catalog.get('primary_count',0), mapped_count=catalog.get('mapped_count',0),
                                       location_errors=catalog.get('location_errors',[]))
                catalog_summary.update(inventory_audit=catalog.get('inventory_audit',{}),inventory_errors=catalog.get('inventory_errors',[]),configured_count=catalog.get('configured_count',0))
            except (OSError, UnicodeError, ValueError) as error:
                catalog_summary = {"available": False, "total": 0, "errors": [str(error)]}
            keys = self.keybinds()
            return {"schema_version": 1, "stat_match_supported": True, "runtime_dir": str(self.runtime), "game": self.game_status(),
                    "catalog": catalog_summary, "queue": [self._command(row[0]) for row in reversed(rows)],
                    "keybinds": keys["active"], "requested_keybinds": keys["requested"],
                    "function_keys": self.function_keybinds(),"function_keys_supported": True,
                    "allowed_keys": sorted(ALLOWED_KEYS), "transport_error": self.transport_error,
                    "transport_code": self.transport_code}


class PanelServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, bridge, static_dir, port=8765):
        self.bridge = bridge
        self.static_dir = Path(static_dir).resolve()
        self.csrf_token = secrets.token_urlsafe(32)
        super().__init__(("127.0.0.1", port), Handler)
        self.origin = f"http://127.0.0.1:{self.server_port}"
        self.expected_host = f"127.0.0.1:{self.server_port}"


class Handler(BaseHTTPRequestHandler):
    server: PanelServer

    def log_message(self, fmt, *args):
        return

    def _reply(self, status, data, content_type="application/json; charset=utf-8", cache="no-store"):
        if not isinstance(data, bytes):
            data = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", cache)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(data)

    def _trusted(self, write=False):
        hosts = self.headers.get_all("Host", [])
        origins = self.headers.get_all("Origin", [])
        if hosts != [self.server.expected_host] or (origins and origins != [self.server.origin]):
            self._reply(403, {"error": "Host or Origin rejected"})
            return False
        if write and not secrets.compare_digest(self.headers.get("X-CSRF-Token", ""), self.server.csrf_token):
            self._reply(403, {"error": "CSRF token required"})
            return False
        return True

    def do_OPTIONS(self):
        self._reply(403, {"error": "Cross-origin requests are not supported"})

    def do_GET(self):
        if not self._trusted():
            return
        path = unquote(urlsplit(self.path).path)
        try:
            if path == "/api/status":
                result = self.server.bridge.status()
                result.update(csrf_token=self.server.csrf_token, origin=self.server.origin)
            elif path == "/api/catalog":
                result = self.server.bridge.catalog()
            elif path == "/api/keybinds":
                result = self.server.bridge.keybinds()
            elif path == "/api/stat-settings":
                result = self.server.bridge.stat_settings()
            elif path == "/api/companion-stats":
                result = self.server.bridge.stat_settings("companion-stats-settings.tsv")
            elif path == "/api/ai-params":
                result = self.server.bridge.ai_params()
            elif path == "/api/codex-icons":
                result = self.server.bridge.codex_icons()
            elif path == "/api/unit-names":
                result = self.server.bridge.unit_names()
            elif path == "/api/home-levels":
                result = self.server.bridge.home_levels()
            elif path.startswith("/codex-icons/"):
                # A codex bust the mod saved on this PC; never shipped with the app.
                name = path[len("/codex-icons/"):]
                file = self.server.bridge.codex_icon_file(name[:-4]) if name.endswith(".png") else None
                if file is None:
                    self._reply(404, {"error": "icon not found"}); return
                self._reply(200, file.read_bytes(), "image/png", cache="max-age=86400")
                return
            elif path == '/api/disk-directory':
                query=parse_qs(urlsplit(self.path).query)
                result=self.server.bridge.disk_directory(query.get('q',[''])[0],query.get('kind',[''])[0],
                    int(query.get('offset',['0'])[0]),int(query.get('limit',['100'])[0]))
            elif path.startswith("/api/"):
                self._reply(404, {"error": "unknown API"}); return
            else:
                relative = "index.html" if path == "/" else path.lstrip("/")
                target = (self.server.static_dir / relative).resolve()
                if not target.is_relative_to(self.server.static_dir) or target.suffix.lower() not in STATIC_TYPES:
                    self._reply(403, {"error": "static path rejected"}); return
                if not target.is_file():
                    self._reply(404, {"error": "file not found"}); return
                self._reply(200, target.read_bytes(), STATIC_TYPES[target.suffix.lower()])
                return
            self._reply(200, result)
        except (OSError, UnicodeError, ValueError, sqlite3.Error) as error:
            self._reply(503, {"error": str(error)})

    def do_POST(self):
        if not self._trusted(write=True):
            return
        path = urlsplit(self.path).path
        if path not in {"/api/command", "/api/keybinds", "/api/queue/clear"}:
            self._reply(404, {"error": "unknown API"}); return
        try:
            if self.headers.get("Transfer-Encoding") or len(self.headers.get_all("Content-Length", [])) != 1:
                raise ValidationError("one Content-Length is required; streaming bodies are unsupported")
            if self.headers.get("Content-Type", "").split(";", 1)[0].strip() != "application/json":
                raise ValidationError("Content-Type must be application/json")
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 16384:
                raise ValidationError("request body must be 1..16384 bytes")
            self.connection.settimeout(5)
            request = json.loads(self.rfile.read(length).decode("utf-8"))
            if path == "/api/queue/clear":
                if request != {}:
                    raise ValidationError("queue clear takes an empty object")
                self._reply(200, self.server.bridge.clear_queue()); return
            if path == "/api/keybinds":
                request = {"action": "configure_keys", "bindings": request}
            command = self.server.bridge.enqueue(request)
            self._reply(202, {"id": command["id"], "status": "queued", "message": "已排队；等待游戏确认"})
        except (OSError, UnicodeError, ValueError, AttributeError) as error:
            self._reply(400, {"error": str(error)})
        except sqlite3.Error as error:
            self._reply(503, {"error": str(error)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-dir", type=Path, default=DEFAULT_RUNTIME)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--static-dir", type=Path, default=Path(__file__).parent / "static")
    args = parser.parse_args()
    bridge = Bridge(args.runtime_dir)
    try:
        server = PanelServer(bridge, args.static_dir, args.port)
    except OSError:
        bridge.close()
        raise SystemExit(f"127.0.0.1:{args.port} 无法绑定；请检查已有服务或用 --port 指定端口。")
    stopping = threading.Event()

    def dispatch():
        while not stopping.wait(0.25):
            bridge.tick()

    worker = threading.Thread(target=dispatch, name="panel-command-dispatch", daemon=True)
    worker.start()
    print(f"PhantomGladiator panel: {server.origin}")
    print(f"Runtime: {bridge.runtime}")
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        stopping.set()
        worker.join(timeout=2)
        server.server_close()
        bridge.close()


if __name__ == "__main__":
    main()
