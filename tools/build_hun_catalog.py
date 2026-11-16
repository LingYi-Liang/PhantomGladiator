"""Build a metadata-only Hun equipment list from a locally audited inventory.

The input stays local; output contains names, identifiers and configuration references,
never game binaries, meshes or decoded ability implementations.
"""
import argparse,hashlib,json,pathlib

def build(source):
    if source.get('build')!='26367565':raise ValueError('inventory build is not supported')
    items=[]
    for row in source['items']:
        kind=row['kind'];key=kind+'|'+row['table']+'|'+row['row']
        items.append({'id':kind+'_'+hashlib.sha256(key.encode()).hexdigest()[:16],
            'kind':kind,'name':row['row'],'native_id':row.get('item_id')or'',
            'source':'item_table','table':row['table'],'row':row['row'],
            'normal_config':row.get('base_config')or'','soul_config':row.get('snap_soul_config')or'',
            'upgrade_records':row.get('upgrade_records')or 0,'refine_max':row.get('max_refine_level'),
            'level_max':row.get('max_refine_level')if kind=='accessory'else min(60,(row.get('upgrade_records')or 0)+1),
            'soul_option':kind!='accessory'and bool(row.get('has_snap_soul_data')),
            'progression_rank':None,'availability':'not_audited','runtime':'not_validated'})
    for row in source.get('unmapped_player_configs',[]):
        path=row['asset'];kind='resource_weapon'if'MainWeaponConfig'in row['class']else'resource_armament'
        items.append({'id':kind+'_'+hashlib.sha256(path.encode()).hexdigest()[:16],'kind':kind,
            'name':path.rsplit('.',1)[-1],'native_id':'','source':'resource_only','table':'','row':'',
            'normal_config':path,'soul_config':'','upgrade_records':0,'refine_max':None,
            'level_max':None,
            'soul_option':False,'progression_rank':None,'availability':'not_audited','runtime':'not_validated'})
    assert len({r['id']for r in items})==len(items)
    assert len([r for r in items if r['kind']=='main_weapon'])==33
    assert len([r for r in items if r['kind']=='shadow_armament'])==28
    assert len([r for r in items if r['kind']=='accessory'])==73
    return {'schema':1,'build':'26367565','items':items}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('inventory',type=pathlib.Path);parser.add_argument('--out',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parents[1]/'panel/hun-catalog.json')
    args=parser.parse_args();data=build(json.loads(args.inventory.read_text(encoding='utf-8')))
    args.out.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('Hun metadata:',len(data['items']),'variant-preserving entries; runtime compatibility remains unverified')
