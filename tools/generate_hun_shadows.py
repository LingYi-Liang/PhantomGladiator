"""Export runtime references and numbers from an already-decoded local armament table."""
import json
from pathlib import Path

HERE = None
def load(name):
    return json.loads(next(HERE.glob(name + '-*.json')).read_text(encoding='utf-8'))

def literal(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int,float)):
        return format(value,'.7g')
    if isinstance(value, dict):
        return '{'+', '.join(k+'='+literal(v) for k,v in value.items())+'}'
    return '{'+', '.join(map(literal,value))+'}'

def source(item):
    path = item[1]
    return path+'.'+path.rsplit('/',1)[-1]+'_C'

def config(path):
    props = load(path.split('.')[-1])['objects'][0]['properties']
    actions = {}
    fallback = []
    default_actions = []
    for grant in props.get('Equip Abilities',[]):
        cls=source(grant)
        stem=grant[1].rsplit('/',1)[-1]
        if not list(HERE.glob(stem+'-*.json')): continue
        data=load(stem)
        default=next((x['properties'] for x in data['objects'] if x['name'].startswith('Default__')), {})
        timelines={x['name']:x['properties'].get('SequenceLength',0) for x in data['objects'] if x['class']=='LGATimeline'}
        timeout=timelines.get('Main') or max(timelines.values(),default=8)
        if stem=='GA_HorseCart_Charge': timeout=max(timeout,default.get('Duration_Lv3',0),default.get('DefaultDuration',0))
        tags=default.get('AbilityTags',['Ability.Action.Hun.ShachiAbility.Default'])
        row=dict(cls=cls, duration=max(1,timeout), cost=default.get('Bullet Instant Cost',0),
                 ongoing=default.get('Bullet Constant Cost',0),radius=default.get('Focus Radius',450))
        for fn in data['functions']:
            if fn['name']=='To Release' or (fn['name'].startswith('OnRelease_') and 'TimeHeld' in str(fn['statements'][:1])):
                row['release']=fn['name']
                break
        for tag in tags: actions[tag]=row
        common='Ability.Action.Hun.ShachiAbility.Default'
        if common in default.get('AbilityTags',[]):
            default_actions.append(dict(row,tag=common,priority=-5,needs=[],excludes=[]))
        if len(props.get('Equip Abilities',[]))==1: fallback.append(dict(row,tag=tags[0],priority=-5,needs=[],excludes=[]))
    moves=[]
    for key,binding in props.get('Weapon Combos',[]):
        if key[1].split('/')[-1]!='IA_ShachiAbility': continue
        for group in load(binding[1].rsplit('/',1)[-1])['objects'][0]['properties']['Bindings']:
            for ent in group.get('NormalData',{}).get('Actions',[])+group.get('NormalData',{}).get('Combos',[]):
                tag=ent.get('TriggerTag',{}).get('TagName')
                if tag in actions:
                    row=dict(actions[tag],tag=tag,priority=group.get('ActionPriority',-5),
                             needs=ent.get('RequiredTags',[]),excludes=ent.get('IgnoredTags',[]))
                    if row not in moves:moves.append(row)
    if not moves: moves=fallback
    # Special input maps add counters/combos. An explicit default spec also has the base armament input.
    for row in default_actions:
        if not any(m['cls']==row['cls'] for m in moves):
            moves.append(row)
    if not moves: raise ValueError('no usable actions '+path)
    return moves

def effects(row):
    result=[]
    def add(effects, minimum=1,soul=False):
        for e in effects:
            path=e.get('SoftClassPtr','')
            if not path:continue
            rule=dict(path=path,level=e.get('GELevel',1),minimum=minimum,soul=soul,slot=bool(e.get('bApplyOnCurrentEquipOnly',0)))
            # A higher tier may change GELevel, retain the thresholds for that case.
            if not any({k:v for k,v in r.items() if k!='minimum'}=={k:v for k,v in rule.items() if k!='minimum'} for r in result):
                result.append(rule)
    add([row['DefaultGEData']])
    add([row['DefaultSnapSoulGEData']],soul=True)
    add(row['ShaChiWeaponSnapSoulData']['GameplayEffectDatas'],soul=True)
    for level,tier in enumerate(row['ShaChiWeaponUpLevelData'],2):
        add(tier.get('GEDatas',[])+tier.get('PersistentGEDatas',[]),level)
        add(tier.get('SnapSoulGEDatas',[]),level,True)
    return result

def summon_rules(path):
    config_data=load(path.rsplit('.',1)[-1])['objects'][0]['properties']
    rules={}
    for field in ('Owning Passive Abilities','Equip Passive Abilities'):
        for obj in config_data.get(field,[]):
            stem=obj[1].rsplit('/',1)[-1]
            if 'Summon_Passive' not in stem: continue
            doc=load(stem)
            default=next(e['properties'] for e in doc['objects'] if e['name'].startswith('Default__'))
            effects=[dict(level=level,path=source(effect)) for level,effect in default.get('SummonUpgradeEffectTable',[])]
            for fn in doc['functions']:
                if fn['name']!='ApplyEffectOnSummon':continue
                import re
                body=' '.join(l for _,l in fn['statements'])
                found=re.search(r'GreaterEqual_IntInt\(WeaponLevel, (\d+)\)',body)
                for ge in re.findall(r'BP_ApplyGameplayEffectToTarget\(obj\((GE_\w+)\.',body):
                    if not found:raise ValueError(stem)
                    root=path.split('/Weapon_')[0]+'/UpgradeData/'+ge
                    effects.append(dict(level=int(found.group(1)),path=root+'.'+ge+'_C'))
            rules[source(obj)]=effects
    return rules

def run(catalog, table, decoded, output):
    global HERE
    HERE=decoded
    rows=json.loads(table.read_text(encoding='utf-8'))['objects'][0]['rows']
    items=[r for r in json.loads(catalog.read_text(encoding='utf-8'))['items'] if r['kind']=='shadow_armament']
    out=['-- Runtime references from DT_ShaqiWeaponData, the weapon input bindings and their ability timelines.',
         '-- Each table row keeps its identity even when two rows share a native weapon configuration.',
         'local data={items={},moves={},summons={},variants={},kinds={}}']
    configs=set()
    for i in items:
        row=rows[i['row']]
        normal,soul=i['normal_config'],i['soul_config']
        multipliers=[1]+[t['AttackMultipliers'] for t in row['ShaChiWeaponUpLevelData']]
        for idx,val in enumerate(multipliers):
            assert abs(val-(1+idx/10))<1e-5
        meta=dict(id=i['id'],label=i['name'],normal=normal,soul=soul,category=row['ShaChiWeaponType'])
        out.extend(['do','    local item='+literal(meta),'    item.effects={'])
        out.extend('        '+literal(e)+',' for e in effects(row))
        out.extend(['    }','    data.items[#data.items+1]=item','end'])
        for p in (normal,soul):
            if p and p not in configs:
                configs.add(p)
                tags=load(p.split('.')[-1])['objects'][0]['properties']['Weapon Equip Tags']
                kind,=[t.rsplit('.',1)[-1] for t in tags if t.startswith('Weapon.Type.ShaqiWeapon.Category.')]
                out.append('data.kinds['+literal(p)+']='+literal(kind))
                rules=summon_rules(p)
                if rules:
                    out.append('data.summons['+literal(p)+']={')
                    out.extend('    ['+literal(cls)+']='+literal(effects)+',' for cls,effects in rules.items())
                    out.append('}')
                out.append('data.moves['+literal(p)+']={')
                out.extend('    '+literal(m)+',' for m in config(p))
                out.append('}')
    available=json.loads(catalog.read_text(encoding='utf-8'))['items']
    for variant in available:
        if variant['kind']!='resource_armament' or '/ShaqiWeapon/' not in variant['normal_config']:continue
        path=variant['normal_config']
        name=path.rsplit('.',1)[-1]
        assert name.endswith('_Interact')
        donor_name='Weapon_Lute' if name=='Weapon_HanBingPiPa_Interact' else name.removesuffix('_Interact')
        donor=next(x for x in items if x['normal_config'].endswith('.'+donor_name))
        native=load(name)['objects'][0]['properties']
        base=load(donor_name)['objects'][0]['properties']
        assert len(native['Equip Abilities'])==1 and '/GameplayBlocker/' in native['Equip Abilities'][0][1]
        row=dict(id=variant['id'],label=variant['name'],normal=path,soul='',category=rows[donor['row']]['ShaChiWeaponType'],
                 donor=donor['normal_config'],displayDiff=native['Display Data']!=base['Display Data'],effects=[])
        out.append('data.variants[#data.variants+1]='+literal(row))
        out.append('data.moves['+literal(path)+']=data.moves['+literal(donor['normal_config'])+']')
        out.append('data.kinds['+literal(path)+']=data.kinds['+literal(donor['normal_config'])+']')

    output.write_text('\n'.join(out+['return data','']),encoding='utf-8')
if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser()
    for arg in ('catalog','table','decoded','output'):parser.add_argument(arg,type=Path)
    run(**vars(parser.parse_args()))
