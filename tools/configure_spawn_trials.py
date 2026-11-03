"""Build bounded trial permissions from the panel's validated native-codex evidence.

Run offline against a captured catalogue response; publish the reviewed outputs only
after tests. This is permission to try, never a successful native-spawn claim.
"""
import argparse
import json
import re
from pathlib import Path

SWORD = '/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue.BP_Monster_MaleThug_Sword_Blue_C'
VESSEL = '/PBZCombatAsset/ActorData/Mobs/023_Vessel_Child/BP_Monster_Vessel_Child.BP_Monster_Vessel_Child_C'
FLAME = '/PBZCombatAsset/ActorData/Mobs/005_ModDog/BP_Monster_FlameDog.BP_Monster_FlameDog_C'


def build(catalog, old_policy):
    selected = {}
    for unit in catalog['units']:
        path = unit['class_path']
        if path in {SWORD, VESSEL, FLAME}:
            continue
        if not (unit.get('codex_entry_kind') == 'primary' and unit.get('inheritance_verified') is True
                and unit.get('resolved_unit_kind') == 'npc' and unit.get('native_parent') == '/Script/ProjectPBZ.PBZCharacter_NPC'
                and unit.get('browse_type') in ('普通敌人', 'BOSS') and not unit.get('is_special')):
            continue
        package, name = path.rsplit('.', 1)
        if (not re.fullmatch(r'/[\w/.-]+', path, flags=re.ASCII) or '..' in path or '//' in path
                or package.rsplit('/', 1)[-1] + '_C' != name or name.lower().endswith('_base_c') or len(path) > 512):
            raise ValueError('invalid concrete class path')
        if path in selected:
            raise ValueError('duplicate class path')
        selected[path] = 'boss' if unit['browse_type'] == 'BOSS' else 'mob'
    if not 0 < len(selected) <= 256:
        raise ValueError('unexpected trial count')
    policy = {'schema_version': 1, 'policy': 'Native codex primary enemies: one per request, two owned actors total. Trial permission is not spawn or combat validation.',
              'units': {p: old_policy['units'][p] for p in (SWORD, VESSEL)}}
    baseline = policy['units'][SWORD]
    baseline['combat_validated'] = True
    baseline['evidence'] = [{'source': 'docs/REVERSE_ENGINEERING.md ordinary-NPC baseline',
                             'supports': 'Another NPC killed the first Sword_Blue without player attacks; logs show HP decrease and death.'}]
    baseline['scope'] = 'Observed spawn, damage, hit reaction and NPC mutual death for this exact class; one per request, two owned actors total; long-term stability unverified.'
    for path in sorted(selected):
        policy['units'][path] = {'class_path': path, 'allow_spawn': True, 'validation_status': 'controlled_test',
                                 'max_count': 1, 'max_live': 2, 'evidence': ['native_codex_primary']}
        previous = old_policy['units'].get(path, {})
        if previous.get('spawn_observed') is True:
            for key in ('spawn_observed', 'combat_validated', 'evidence', 'scope'):
                if key in previous:
                    policy['units'][path][key] = previous[key]
    encoded = json.dumps(policy, ensure_ascii=False, separators=(',', ':')) + '\n'
    if len(encoded.encode('utf-8')) > 65536:
        raise ValueError('policy exceeds existing backend size limit')
    manifest = 'PhantomGladiatorSpawnTrialsV1\n' + ''.join(path + '\t' + selected[path] + '\n' for path in sorted(selected))
    return encoded, manifest, {'trials': len(selected), 'mobs': sum(v == 'mob' for v in selected.values()),
                               'bosses': sum(v == 'boss' for v in selected.values()), 'policy_bytes': len(encoded.encode('utf-8'))}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--catalog-json', type=Path, required=True)
    parser.add_argument('--old-policy', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    policy, manifest, report = build(json.loads(args.catalog_json.read_text(encoding='utf-8')), json.loads(args.old_policy.read_text(encoding='utf-8')))
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'unit_validation.json').write_text(policy, encoding='utf-8')
    (args.output / 'spawn-trials.tsv').write_text(manifest, encoding='utf-8')
    (args.output / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))
