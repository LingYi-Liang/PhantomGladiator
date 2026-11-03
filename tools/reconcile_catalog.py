"""Reconcile a completed, read-only registry inventory with codex/spawn evidence.

Never loads assets, executes game commands, or edits spawn permissions. Native
inheritance is read from the local header dump; those headers are not copied.
"""
from __future__ import annotations
import argparse,csv,collections,io,json,os,re,shutil,subprocess
from datetime import datetime,timezone
from pathlib import Path

CATALOG=('id','name','category','class_path','loaded','spawnable','reason')
ROOTS={'/Script/ProjectPBZ.PBZCharacter_NPC':'npc','/Script/ProjectPBZ.PBZCharacter_Player':'player',
       '/Script/Engine.Character':'character','/Script/Engine.Pawn':'pawn'}
CLASS_PATH=re.compile(r'/[^\s\x00-\x1f\x7f\'":]+\.[^./\s\x00-\x1f\x7f\'":]+$')

def object_path(raw):
    if not isinstance(raw,str):return None
    raw=raw.strip()
    quoted=re.fullmatch(r"[^'\"]*(['\"])(/[^'\"]+)\1",raw)
    if quoted:raw=quoted.group(2)
    return raw if CLASS_PATH.fullmatch(raw) and '..' not in raw else None

def rows(path):
    if not path.exists():return []
    with path.open(encoding='utf-8-sig',newline='') as f:
        result=list(csv.DictReader(f,delimiter='\t'))
    if any(None in row or any(v is None for v in row.values()) for row in result):raise ValueError(f'incomplete/malformed TSV: {path.name}')
    return result

def native_edges(root):
    cmd=['rg','--with-filename','--line-number','--no-heading',r'^class ([AU][A-Za-z0-9_]+) : public ([AU][A-Za-z0-9_]+)',str(root),'-g','*.hpp']
    result=subprocess.run(cmd,capture_output=True,encoding='utf-8',check=False)
    if result.returncode not in (0,1):raise RuntimeError(result.stderr)
    cpp=collections.defaultdict(set);decl=[]
    for line in result.stdout.splitlines():
        found=re.match(r'(.+\.hpp):(\d+):class ([AU]\w+) : public ([AU]\w+)',line)
        if not found:continue
        filename,number,child,parent=found.groups()
        if child.endswith('_C'):continue # individual Blueprint SDK files are not Script modules
        module=Path(filename).stem
        path=f'/Script/{module}.{child[1:]}'
        cpp[child].add(path);decl.append((path,parent,f'{module}.hpp:{number}'))
    edges={};sources={}
    for path,parent,source in decl:
        choices=cpp.get(parent,set())
        if len(choices)==1:edges[path]=next(iter(choices));sources[path]=source
    return edges,sources

def build_classes(index):
    classes={};conflicts=set()
    for asset in index:
        generated=object_path(asset.get('generated_class',''))
        if not generated and asset['asset_type'] in ('/Script/Engine.BlueprintGeneratedClass','/Script/CoreUObject.Class'):
            generated=object_path(asset['asset_path'])
        if not generated:continue
        record={'class_path':generated,'parent':object_path(asset.get('parent_class','')),
                'native_parent':object_path(asset.get('native_parent','')),'asset':asset}
        old=classes.get(generated)
        if old:
            for key in ('parent','native_parent'):
                if old[key] and record[key] and old[key]!=record[key]:conflicts.add(generated)
                if not record[key]:record[key]=old[key]
        classes[generated]=record
    return classes,conflicts

def resolve_kind(path,classes,native):
    stack=[(path,[])];seen=set();matches={}
    while stack and len(seen)<256:
        current,chain=stack.pop()
        if current in seen:continue
        seen.add(current);chain=chain+[current]
        if current in ROOTS:
            matches[ROOTS[current]]=chain;continue
        record=classes.get(current)
        if record:
            for parent in (record['parent'],record['native_parent']):
                if parent:stack.append((parent,chain))
        elif current in native:stack.append((native[current],chain))
    # NPC/player are more specific than Character/Pawn; never infer rank from name.
    if 'npc' in matches and 'player' in matches:return None,[], 'conflicting_unit_roots'
    for kind in ('npc','player','character','pawn'):
        if kind in matches:return kind,matches[kind],None
    return None,[], 'no_confirmed_unit_root'

def atomic(path,content):
    temporary=path.with_name(path.name+'.audit-tmp')
    with temporary.open('w',encoding='utf-8',newline='') as f:f.write(content);f.flush();os.fsync(f.fileno())
    os.replace(temporary,path)

def tsv(fields,records):
    out=io.StringIO();writer=csv.DictWriter(out,fieldnames=fields,delimiter='\t',lineterminator='\n',extrasaction='ignore')
    writer.writeheader();writer.writerows(records);return out.getvalue()

def reconcile(runtime,headers,publish=False):
    manifest=dict(line.rstrip('\n').split('\t',1) for line in (runtime/'asset-index-status.tsv').read_text(encoding='utf-8-sig').splitlines() if '\t' in line)
    if manifest.get('complete')!='true' or manifest.get('scope')!='current_mounted_on_disk_registry':
        raise ValueError('inventory has not completed its independent count verification; catalog not replaced')
    index=rows(runtime/'asset-index.tsv')
    unique={row['asset_path'] for row in index}
    expected=int(manifest['expected_assets']);final=int(manifest['final_asset_count'])
    if len(index)!=len(unique) or len(unique)!=expected or expected!=final:raise ValueError('inventory count mismatch')
    old=rows(runtime/'catalog.tsv');old_by_id={r['id']:r for r in old}
    baseline=rows(runtime/'catalog.before-inventory.tsv') or old
    baseline_ids={r['id'] for r in baseline}
    classes,conflicts=build_classes(index);native,native_sources=native_edges(headers)
    codex={r['class_path']:r for r in rows(runtime/'codex.tsv')}
    current_configs=rows(runtime/'spawn-config.tsv')
    history=rows(runtime/'spawn-config-history.tsv')
    configs=list({tuple(sorted(r.items())):r for r in history+current_configs}.values())
    references=rows(runtime/'asset-references.tsv')
    table_rows=rows(runtime/'native-table-catalog.tsv')
    attribute_paths={r['asset_path'] for r in table_rows if r['schema']=='attributes' and r['asset_path']}
    sequence_links={r['related_class']:r['asset_path'] for r in table_rows if r['schema']=='sequence' and r['related_class']}
    configured=collections.defaultdict(list);observed=collections.defaultdict(list)
    for item in configs:
        path=object_path(item.get('class_path',''))
        if not path:continue
        if item['evidence_kind']=='configured_spawn':configured[path].append(item)
        elif item['evidence_kind']=='loaded_actor_observation':observed[path].append(item)
    refs=collections.defaultdict(set)
    for item in references:refs[item['package']].add(item['referenced_by'])
    evidence=[];added=[];merged=dict(old_by_id);kinds=collections.Counter();unresolved=0
    for path,record in sorted(classes.items()):
        kind,chain,problem=resolve_kind(path,classes,native)
        if path in conflicts:kind=None;problem='conflicting_asset_metadata'
        if not kind:
            if path in old_by_id:unresolved+=1
            continue
        kinds[kind]+=1
        asset=record['asset'];package=asset['package_name']
        source='asset_registry_and_header_inheritance'
        fields={'id':path,'name':path.rsplit('.',1)[-1],'category':{'npc':'NPC','player':'玩家角色','character':'角色','pawn':'Pawn实体'}[kind],
                'class_path':path,'loaded':'unknown','spawnable':'1' if kind=='npc' else '0',
                'reason':';'.join(['registry_generated_class_tag','inheritance_resolved='+kind,'asset='+asset['asset_path'],
                    'asset_type='+asset['asset_type'],'package='+package,'package_path='+asset['package_path'],
                    'parent='+str(record['parent'] or 'unknown'),'native_parent='+str(record['native_parent'] or 'unknown'),
                    'scope=current_mounted_registry;spawn_compatibility_unverified'])}
        if path not in baseline_ids:added.append({'class_path':path,'kind':kind,'package':package})
        merged[path]=fields
        configured_rows=configured.get(path,[])
        configured_maps=sorted({v['map_id'] for v in configured_rows if v['map_id']})
        map_refs=sorted(p for p in refs[package] if '/Maps/' in p or '/__ExternalActors__/' in p or '/__ExternalObjects__/' in p)
        evidence.append({'class_path':path,'unit_kind':kind,'native_parent':record['native_parent'],'inheritance_chain':chain,
            'source':source,'in_codex':path in codex,'configured_maps':configured_maps,
            'configured_spawner_count':len(configured_rows),'loaded_observations':len(observed.get(path,[])),
            'map_package_references':map_refs,'map_reference_scope':'package_reference_not_spawn_proof',
            'has_attribute_entry':path in attribute_paths or asset['asset_path'] in attribute_paths,
            'sequence_gameplay_class':sequence_links.get(path),
            'purpose_hint':'cinematic' if '/ActorForSeqs/' in path or any('/ActorForSeqs/' in p for p in chain) else None})
    missing_configured=sorted(set(configured)-set(classes))
    report={'schema_version':1,'created_utc':datetime.now(timezone.utc).isoformat(),
        'asset_scope':'current_mounted_on_disk_registry','asset_count':len(index),'independent_count':expected,
        'paths_verified':int(manifest['paths_done']),'large_directories':int(manifest.get('large_paths','0')),
        'inventory_verified':True,'physical_encrypted_container_coverage':'UNKNOWN','all_maps_spawn_coverage':'NOT_COMPLETE',
        'previous_catalog_rows':len(baseline),'merged_catalog_rows':len(merged),'strong_unit_classes':dict(kinds),
        'added':added,'metadata_conflicts':sorted(conflicts),'old_candidates_without_confirmed_unit_root':unresolved,
        'codex_paths':len(codex),'configured_spawn_records':sum(map(len,configured.values())),
        'configured_unit_classes':len(configured),'configured_maps':sorted({m['map_id'] for v in configured.values() for m in v if m['map_id']}),
        'configured_classes_missing_registry_class_record':missing_configured,
        'reference_edges_read':len(references),'published':bool(publish)}
    report['native_table_rows']=dict(collections.Counter(r['schema'] for r in table_rows))
    report['attribute_paths_resolved']=len(attribute_paths)
    report['spawn_snapshot_scope']='loaded_world_samples;not_all_map_cells'
    atomic(runtime/'inventory-report.json',json.dumps(report,ensure_ascii=False,indent=2))
    atomic(runtime/'unit-evidence.json',json.dumps({'schema_version':1,'scope':'current_mounted_registry','units':evidence},ensure_ascii=False,indent=2))
    if publish:
        backup=runtime/'catalog.before-inventory.tsv'
        if not backup.exists():shutil.copy2(runtime/'catalog.tsv',backup)
        atomic(runtime/'catalog.tsv',tsv(CATALOG,[merged[k] for k in sorted(merged)]))
        if configs:atomic(runtime/'spawn-config-history.tsv',tsv(tuple(configs[0]),configs))
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--runtime',type=Path,required=True);parser.add_argument('--headers',type=Path,required=True);parser.add_argument('--publish',action='store_true')
    args=parser.parse_args();report=reconcile(args.runtime.resolve(),args.headers.resolve(),args.publish)
    print(json.dumps({k:report[k] for k in ('asset_count','paths_verified','previous_catalog_rows','merged_catalog_rows','strong_unit_classes','configured_unit_classes','configured_maps','reference_edges_read','published')},ensure_ascii=False,indent=2))
    print('New candidates:',len(report['added']))
