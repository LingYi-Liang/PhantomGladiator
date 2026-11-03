"""Read-only Chinese labels for catalog rows, never a spawn-safety decision.

The current registry TSV has internal names, not official localized names.
Fallback names below are explicitly working translations. Unknown proper names
remain visible instead of inventing official Chinese characters.

Optional verified evidence must match the exact generated class path, e.g.:
    {"class_path": path, "source": "game_codex",
     "zh_name": row.Enemy_CH_Hans_Name, "is_boss": row.bIsBoss,
     "enemy_type": row.EnemyType}
FCodexEnemyRow has no minion/elite rank. A false bIsBoss is not a minion proof.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from typing import Any

NPC_PARENT = "/Script/ProjectPBZ.PBZCharacter_NPC"
HUN_PROXY_CLASS = "/PBZCombatAsset/ActorData/Mobs/000_Hun/BP_Monster_Hun.BP_Monster_Hun_C"

# Internal English descriptions translated literally; these are NOT official names.
WORKING_TERMS = {
    'seq':'演出','seqcharacter':'演出角色','previewappearance':'外观预览','player':'玩家','renewalplayer':'玩家通用基型','hun':'魂（工作名）',
    "arrowman": "弓手", "greatblademan": "大刀兵", "heavycrossbowmannew": "重弩兵",
    "heavycrossbowman": "重弩兵", "bombman": "投弹兵", "malethug": "男性匪徒",
    "femalethug": "女性匪徒", "moddog": "改造犬", "dog": "犬", "flamedog": "火焰犬",
    "goldendog": "金色犬", "sickdog": "病犬", "illnesscrow": "病鸦", "vessel": "容器体",
    "femalevessel": "女性容器体", "vesselchild": "幼体容器", "vesselelder": "老年容器体",
    "vesselman": "男性容器体", "vesselwoman": "女性容器体", "vesselvagrant": "流浪容器体",
    "spearman": "长枪兵", "aquakiller": "水中杀手", "horse": "马", "bandit": "匪徒",
    "scavenger": "拾荒者", "hookman": "钩刃兵", "maddoctor": "狂医生",
    "maddocter": "狂医生", "femaledoll": "女性人偶", "maledoll": "男性人偶",
    "goldmaskman": "金面人", "powerman": "力士", "liondancer": "舞狮者",
    "mboss": "首领代号", "mbossvariants": "首领代号变体",
    "sword": "剑", "blade": "刃", "bigblade": "大刃", "bigknife": "大刀",
    "spear": "长枪", "axe": "斧", "twinaxe": "双斧", "twinsword": "双剑",
    "twinblade": "双刃", "bow": "弓", "crossbow": "弩", "shield": "盾",
    "bigshield": "大盾", "club": "棍棒", "gun": "枪械", "cannon": "炮",
    "fist": "拳", "dart": "飞镖", "knife": "刀", "molotov": "燃烧瓶",
    "fishingnet": "渔网", "boneblade": "骨刃", "weaponless": "无武器",
    "noweapon": "无武器", "black": "黑色", "white": "白色", "blue": "蓝色",
    "red": "红色", "yellow": "黄色", "purple": "紫色", "cyan": "青色",
    "golden": "金色", "gold": "金色", "iron": "铁制", "flame": "火焰",
    "ice": "冰", "poison": "毒", "corrupted": "腐化", "normal": "普通变体",
    "elite": "精英命名变体", "man": "男性", "woman": "女性", "child": "幼体",
    "elder": "老年", "giant": "巨型", "vagrant": "流浪者", "young": "年轻形态",
    "old": "年长形态", "half": "半身", "up": "上部", "rider": "骑乘形态",
    "horsecartcombat": "马车战斗变体", "mask": "面具", "throw": "投掷",
    "summon": "召唤变体", "summonself": "自身召唤变体", "double": "替身",
    "stuntdouble": "演出替身", "clone": "复制体", "phantom": "幻影",
    "stand": "站立展示变体", "npc": "交互角色变体", "npchelper": "NPC辅助体",
    "helper": "辅助体", "base": "基础模板", "test": "测试体", "humanoidtest": "人形测试体",
    "dummy": "靶体", "preview": "预览体", "tutorial": "教学变体", "execute": "处决变体",
    "execution": "处决变体", "narrative": "剧情体", "ending": "结局演出体",
    "cinematic": "过场演出体", "cutscene": "过场演出体", "unused": "未使用变体",
    "deprecated": "弃用变体", "proxy": "代理体", "trash": "Trash用途待查变体",
    "broken": "破损形态", "sleeping": "睡眠形态", "dying": "濒死形态",
    "deadpose": "死亡姿势", "withbook": "持书形态", "withabacus": "持算盘形态",
    "whiteflower": "白花形态", "facefog": "遮面雾形态", "for": "专用变体",
    "self": "自身", "new": "新版", "combat": "战斗", "deflectandhit": "格挡受击",
    "onlyhit": "仅受击", "farmer": "农夫", "renewalnpc": "NPC通用基型",
    # Descriptive pinyin / asset-workflow terms are working labels too. Character
    # proper names such as GuWanYue, LengTu and ZuoShang intentionally stay raw.
    "guichai": "鬼差系", "huashan": "华山系", "emei": "峨眉系", "feizei": "飞贼",
    "ranfang": "染坊变体", "yingdi": "营地变体", "xigu": "溪谷变体",
    "jianghurenshi": "江湖人士", "huojinren": "火金人系", "huotongren": "火铜人系",
    "huotieren": "火铁人系", "datouwawa": "大头娃娃", "qiangdun": "枪盾",
    "cunyuan": "村院变体", "yizhan": "驿站变体", "shiyanchang": "试验场变体",
    "tonggun": "铜棍", "jiuhuandao": "九环刀", "douli": "斗笠", "genv": "歌女",
    "qinnv": "琴女", "nvjianke": "女剑客", "nvdizi": "女弟子",
    "cunmin": "村民", "furen": "妇人", "guke": "顾客",
    "zhangmen": "掌门变体", "hunshui": "昏睡变体", "shoushang": "受伤变体",
    "tingxi": "听戏变体", "ninan": "呢喃变体",
    "laoqigai": "老乞丐", "zhengdaorenshi": "正道人士", "bowl": "碗",
    "ga": "技能资产", "subtitles": "字幕", "snake": "蛇", "autoiron": "自动铁化变体",
    "autogolden": "自动金化变体",
    "teaching": "教学变体", "trap": "陷阱变体", "respawn": "重生变体",
    "bomb": "爆弹", "eagle": "鹰", "hoe": "锄", "twinhoe": "双锄",
}

TRAIT_LABELS = {
    "non_npc_asset": "非NPC资产", "npc_parent_unknown": "NPC继承尚无元数据证据",
    "npc_parent_metadata": "注册表标记NPC继承（非战斗验收）",
    "base_template": "基础模板", "summon_variant": "召唤物变体",
    "clone_variant": "分身／替身／幻影", "helper_variant": "辅助实体",
    "display_variant": "展示或固定姿势变体", "story_variant": "剧情／交互实体候选",
    "test_variant": "测试／靶体／预览／教学", "execution_variant": "处决演出变体",
    "unused_variant": "未使用／弃用变体", "proxy_variant": "代理实体",
    "trash_variant": "Trash命名变体，用途待查", "quarantine_review": "建议隔离核验",
    "boss_name_hint": "内部名含Boss，不等于BOSS分类证据",
    "elite_name_hint": "内部名含Elite，不等于精英等级证据",
    "boss_verified": "图鉴数据明确标记BOSS", "non_boss_verified": "图鉴标记非BOSS，级别仍待确认",
    "direct_codex_enemy": "原生图鉴直接绑定该敌人类",
    "minion_role_verified": "游戏角色数据明确标记小兵", "unmatched_evidence": "附加证据未匹配当前类",
    "official_name_unavailable": "尚未取得游戏中文原名", "untranslated_tokens": "部分内部专名保留原文",
    "parent_codex_name_reference": "仅参考父类图鉴名，非当前类官方名称",
    "special_character_model": "主角形象NPC代理／特殊角色模型，用途待核",
}

SPECIAL_PATTERNS = (
    ("base_template", r"(?:^|[_/])base(?:[_/.]|$)|^bp_renewalnpc$"),
    ("summon_variant", r"summon"),
    ("clone_variant", r"(?:^|_)double(?:_|$)|stuntdouble|(?:^|_)(?:clone|phantom)(?:_|$)"),
    ("helper_variant", r"helper"),
    ("display_variant", r"(?:^|_)stand(?:_|$)|deadpose"),
    ("story_variant", r"^bp_npc_|^bp_test_npc_|^bp_npcmonster_|(?:^|_)npc(?:_|$)|narrative|(?:^|[_/])(?:ending|cinematic|cutscene|story)(?:[_/.]|$)"),
    ("test_variant", r"(?:^|[_/])test(?:[_/.]|$)|humanoidtest|dummy|preview|tutorial"),
    ("execution_variant", r"(?:^|_)(?:execute|execution|executed)(?:_|$)"),
    ("unused_variant", r"unused|deprecated|obsolete|notused"),
    ("proxy_variant", r"(?:^|_)proxy(?:_|$)"),
    ("trash_variant", r"(?:^|_)trash(?:_|$)"),
)

ENEMY_TYPES = {1: "动物类", 2: "怪面类", 3: "龙改造类（工作译名）",
               4: "人类高手类（工作译名）", 5: "人偶类"}


def _text(value: Any, limit: int = 1024) -> str:
    return re.sub(r"[\x00-\x1f\x7f]", " ", str(value or ""))[:limit].strip()


def native_parent(row: Mapping[str, Any]) -> str:
    raw = row.get("native_parent") or row.get("nativeParent") or ""
    if not raw:
        match = re.search(r"(?:^|;)native_parent=([^;]*)", _text(row.get("reason"), 8192))
        raw = match.group(1) if match else ""
    matches = re.findall(r"/Script/[A-Za-z0-9_]+\.[A-Za-z0-9_]+", _text(raw))
    return matches[-1] if matches else ""


def parent_class_path(row: Mapping[str, Any]) -> str | None:
    """Parse exactly one full registry ParentClass, never native_parent or a hint."""
    reason = row.get("reason")
    if not isinstance(reason, str):
        return None
    values = re.findall(r"(?:^|;)(?:parent|ParentClass)=([^;]*)", reason)
    if len(values) != 1:
        return None
    raw = values[0].strip()
    if not raw or re.search(r"[\x00-\x1f\x7f]", raw):
        return None
    wrapped = re.fullmatch(
        r"(?:/Script/[A-Za-z0-9_]+\.[A-Za-z0-9_]+|Class|BlueprintGeneratedClass)?"
        r"(?P<quote>['\"])(?P<path>/[A-Za-z0-9_/.\-]+)(?P=quote)", raw)
    path = wrapped.group("path") if wrapped else raw
    if not re.fullmatch(r"/[A-Za-z0-9_/.\-]+\.[A-Za-z0-9_\-]+_C", path):
        return None
    if ".." in path or "//" in path or "/./" in path:
        return None
    return path


def _internal_name(row: Mapping[str, Any]) -> str:
    name = _text(row.get("internal_name"), 256)
    if name:
        return name[:-2] if name.endswith("_C") else name
    path = _text(row.get("class_path") or row.get("id"))
    name = path.rsplit(".", 1)[-1].rsplit("/", 1)[-1] if path else ""
    if not name.endswith("_C"):
        name = _text(row.get("name"), 256)
    return name[:-2] if name.endswith("_C") else name


def _translate_piece(piece: str) -> tuple[str, bool]:
    known = WORKING_TERMS.get(piece.casefold())
    if known:
        return known, True
    if re.fullmatch(r"P[1-9][0-9]*", piece, re.I):
        return "第" + piece[1:] + "阶段", True
    if piece.isdigit():
        return "变体" + piece, True
    # CamelCase fallback translates known parts without inventing proper names.
    parts = re.findall(r"[A-Z]+(?=[A-Z][a-z]|[0-9]|$)|[A-Z]?[a-z]+|[0-9]+|[\u3400-\u9fff]+", piece)
    if len(parts) > 1:
        translated = [WORKING_TERMS.get(part.casefold(), part) for part in parts]
        if any(part.casefold() in WORKING_TERMS for part in parts):
            return "·".join(translated), all(part.casefold() in WORKING_TERMS or part.isdigit() for part in parts)
    return piece, False


def _working_name(internal: str) -> tuple[str, str, list[str]]:
    core = re.sub(r"^BP_(?:Monster_|NPC_|NPCMonster_)?", "", internal, flags=re.I)
    pieces = [piece for piece in core.split("_") if piece]
    labels, unknown = [], []
    for piece in pieces:
        label, translated = _translate_piece(piece)
        labels.append(label)
        if not translated:
            unknown.append(piece)
    label = "·".join(labels) or "未取得名称"
    if not re.search(r"[\u3400-\u9fff]", label):
        label = "未译单位：" + label
    source = "working_translation_partial" if unknown else "working_translation"
    # The exact internal identifier stays visible even when every token was translated.
    return label + "〔" + (internal or "内部名未知") + "〕", source, unknown


def _evidence_bool(value: Any) -> bool | None:
    if type(value) is bool:
        return value
    if isinstance(value, str):
        if value.casefold() in {"1", "true"}:
            return True
        if value.casefold() in {"0", "false"}:
            return False
    return None


def _direct_codex_enemy(evidence: Mapping[str, Any] | None) -> bool:
    """Only the actual exporter EnemyClass provenance outranks a name heuristic."""
    if not evidence or evidence.get("source") != "game_codex":
        return False
    return re.fullmatch(
        r"native_codex:FCodexEnemyRow(?:;replacement=/[^;\s]+)?"
        r"(?:;use_replacement_entry=(?:true|false))?;EnemyClass",
        str(evidence.get("source_detail") or ""),
    ) is not None


def _parent_working_name(row: Mapping[str, Any], internal: str, current: str,
                         parent_evidence: Mapping[str, Any] | None) -> tuple[str, list[str] | None] | None:
    parent_path = parent_class_path(row)
    if (not parent_path or not parent_evidence or parent_evidence.get("source") != "game_codex"
            or parent_evidence.get("verified") is False or parent_evidence.get("class_path") != parent_path):
        return None
    chinese = _text(parent_evidence.get("zh_name"), 128)
    if not chinese or not re.search(r"[\u3400-\u9fff]", chinese):
        return None
    parent_internal = parent_path.rsplit(".", 1)[-1][:-2]
    if internal.startswith(parent_internal + "_"):
        suffix = internal[len(parent_internal) + 1:]
        translated, unknown = [], []
        for piece in (part for part in suffix.split("_") if part):
            label, complete = _translate_piece(piece)
            translated.append(label)
            if not complete:
                unknown.append(piece)
        return chinese + "·" + "·".join(translated) + "〔" + internal + "〕", unknown
    # The class relationship is known, but the name does not express a simple
    # suffix variant. Keep its existing working name; only append the family hint.
    return current + "（参考父类族名：" + chinese + "）", None


def decorate_row(row: Mapping[str, Any], evidence: Mapping[str, Any] | None = None,
                 parent_evidence: Mapping[str, Any] | None = None) -> dict[str, Any]:
    """Return labels only. Never returns, changes or infers a spawnable/safe flag."""
    internal = _internal_name(row)
    path = _text(row.get("class_path") or row.get("id"))
    parent = native_parent(row)
    traits: list[str] = []
    if parent == NPC_PARENT:
        traits.append("npc_parent_metadata")
    elif parent:
        traits.append("non_npc_asset")
    else:
        traits.append("npc_parent_unknown")
    for code, pattern in SPECIAL_PATTERNS:
        if re.search(pattern, internal, re.I) or re.search(pattern, path, re.I):
            traits.append(code)
    if path == HUN_PROXY_CLASS:
        traits.append("special_character_model")
    if "boss" in internal.casefold():
        traits.append("boss_name_hint")
    if "elite" in internal.casefold():
        traits.append("elite_name_hint")
    special = ("non_npc_asset" in traits or "special_character_model" in traits
               or any(code in traits for code, _ in SPECIAL_PATTERNS))
    if special:
        traits.append("quarantine_review")
    if special:
        category, category_source = "特殊实体", "native_parent_or_name_pattern"
    elif parent == NPC_PARENT and internal.startswith("BP_Monster_"):
        category, category_source = "普通怪物（级别待核）", "npc_metadata_and_monster_name"
    else:
        category, category_source = "待分类", "unknown"
    display, name_source, unknown = _working_name(internal)
    if path == HUN_PROXY_CLASS:
        display, name_source, unknown = "主角形象NPC代理（用途待核）〔" + internal + "〕", "working_translation", []
    source = evidence.get("source") if evidence else None
    # game_codex is the read-only codex.tsv exporter contract; legacy explicit
    # evidence objects additionally require verified=True. Reject explicit false.
    trusted_source = bool(evidence and ((source == "game_codex" and evidence.get("verified") is not False)
                                      or (source in {"FCodexEnemyRow", "game_character_data"}
                                          and evidence.get("verified") is True)))
    matched = bool(trusted_source and evidence.get("class_path") == path)
    direct_enemy = matched and _direct_codex_enemy(evidence)
    boss = None
    if evidence and not matched:
        traits.append("unmatched_evidence")
    if matched:
        chinese = _text(evidence.get("zh_name"), 128)
        if chinese and re.search(r"[\u3400-\u9fff]", chinese):
            display, name_source = chinese, "game_codex" if source in {"game_codex", "FCodexEnemyRow"} else "game_character_data"
            unknown = []
        boss = _evidence_bool(evidence.get("is_boss"))
        if boss is True:
            traits.append("boss_verified")
            if not special:
                category, category_source = "BOSS", "verified_game_data"
        elif boss is False:
            traits.append("non_boss_verified")
        # The current Codex row has no such rank field; never derive it from bIsBoss=false.
        if (evidence.get("source") == "game_character_data" and evidence.get("role") == "minion"
                and evidence.get("role_source_field") and boss is not True):
            traits.append("minion_role_verified")
            if not special:
                category, category_source = "小兵", "verified_game_role"
        # A direct native EnemyClass row is stronger category evidence than
        # Base/Ending/Tutorial/etc in its name. Keep every variant/risk trait;
        # this classification override never supplies spawn permission.
        if direct_enemy:
            traits.append("direct_codex_enemy")
            if boss is True:
                category, category_source = "BOSS", "native_codex_direct_enemy"
            elif boss is False:
                category, category_source = "普通怪物（级别待核）", "native_codex_direct_enemy"
    if name_source.startswith("working_translation"):
        derived = _parent_working_name(row, internal, display, parent_evidence)
        if derived:
            display, derived_unknown = derived
            name_source = "derived_working_translation"
            traits.append("parent_codex_name_reference")
            if derived_unknown is not None:
                unknown = derived_unknown
    if name_source.startswith("working_translation") or name_source == "derived_working_translation":
        traits.append("official_name_unavailable")
    if unknown:
        traits.append("untranslated_tokens")
    source_labels = {"game_codex": "游戏图鉴原文", "game_character_data": "游戏角色数据原文",
                     "working_translation": "中文工作译名（非官方）",
                     "working_translation_partial": "中文工作译名，部分专名待核（非官方）",
                     "derived_working_translation": "参考图鉴父类的工作译名"}
    family = re.search(r"/Mobs/([^/]+)/", path)
    family_id = family.group(1) if family else ""
    trait_labels = [TRAIT_LABELS[code] for code in traits]
    if direct_enemy:
        overrides = {
            "base_template": "基型命名待核，不代表不是敌人",
            "story_variant": "终局／剧情命名变体，初始化待验证",
            "test_variant": "教学命名变体，初始化待验证" if "tutorial" in internal.casefold()
                else "测试／展示命名变体，初始化待验证",
        }
        trait_labels = [overrides.get(code, TRAIT_LABELS[code]) for code in traits]
    result = {"display_name": display, "internal_name": internal, "category": category,
              "category_source": category_source, "name_source": name_source,
              "name_source_label": source_labels[name_source], "traits": traits,
              "trait_labels": trait_labels,
              "category_special": ("特殊BOSS变体（初始化待验证）" if matched and boss is True else "特殊实体") if special else "",
              "family_id": family_id, "untranslated_tokens": unknown}
    if matched:
        enemy_type = evidence.get("enemy_type")
        if isinstance(enemy_type, str) and enemy_type.isdigit():
            enemy_type = int(enemy_type)
        if type(enemy_type) is int and enemy_type in ENEMY_TYPES:
            result["species_label"] = ENEMY_TYPES[enemy_type]
    return result


__all__ = ["decorate_row", "native_parent", "parent_class_path"]
