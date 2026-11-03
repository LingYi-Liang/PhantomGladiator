"""Presentation-only taxonomy. Never grants spawning or inherits map membership."""
import re

LOCATION_FIELDS = ('class_path', 'own_map_id', 'map_name', 'chapter_id', 'chapter_name', 'chapter_order',
                   'map_order', 'level_name', 'display_order', 'canonical_class_path', 'map_status', 'source')
VESSEL_CHILD = '/PBZCombatAsset/ActorData/Mobs/023_Vessel_Child/BP_Monster_Vessel_Child.BP_Monster_Vessel_Child_C'


def identity(evidence):
    if not evidence or evidence.get('source') != 'game_codex':
        return 'candidate', None
    source = evidence.get('source_detail', '')
    if source.endswith(';EnemyClass'):
        return 'primary', evidence['class_path']
    match = re.search(r';AliasEnemyClasses;canonical=(/[^;\s]+)$', source)
    if match:
        return 'alias', match.group(1)
    return 'candidate', None


def decorate(unit, evidence=None, location=None):
    kind, canonical = identity(evidence)
    traits = set(unit.get('traits', []))
    boss = evidence.get('is_boss') in ('1', 'true', True) if evidence else None
    nonboss = evidence.get('is_boss') in ('0', 'false', False) if evidence else False
    basis = '名称或继承线索，尚未核实用途'
    if unit['class_path'] == VESSEL_CHILD:
        category, basis = '特殊机制', '实测：机灵鬼自带穿透／无敌，不用于普通互伤基准'
    elif boss:
        category, basis = 'BOSS', '游戏图鉴 bIsBoss=true'
    elif kind in ('primary', 'alias') and nonboss:
        category, basis = '普通敌人', '游戏图鉴 bIsBoss=false；尚未细分小兵与精英'
    elif traits & {'base_template', 'test_variant', 'unused_variant'}:
        category = '模板／测试'
    elif traits & {'summon_variant', 'clone_variant'}:
        category = '召唤／分身'
    elif 'story_variant' in traits:
        category = '剧情／NPC候选'
    elif traits & {'helper_variant', 'proxy_variant', 'display_variant', 'execution_variant', 'special_character_model'}:
        category = '特殊／辅助'
    elif 'npc_parent_metadata' in traits and unit.get('internal_name', '').startswith('BP_Monster_'):
        category = '敌人变体候选'
    else:
        category = '待分类'
    result = {'codex_entry_kind': kind, 'canonical_class_path': canonical,
              'browse_type': category, 'browse_type_basis': basis,
              'map_id': None, 'map_name': None, 'chapter_id': None, 'chapter_name': None,
              'chapter_order': None, 'map_order': None, 'codex_order': None,
              'level_name': None, 'map_status': 'unknown', 'map_source': None}
    if location:
        result.update(map_id=location['own_map_id'] or None, map_name=location['map_name'] or None,
                      chapter_id=location['chapter_id'] or None, chapter_name=location['chapter_name'] or None,
                      chapter_order=location['chapter_order'], map_order=location['map_order'],
                      codex_order=location['display_order'], level_name=location['level_name'] or None,
                      map_status=location['map_status'], map_source='游戏图鉴 OwnMapID → 地图表 → 章节表')
    return result
