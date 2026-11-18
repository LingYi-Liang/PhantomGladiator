"""Strict, revisioned NPC profile storage. Never reads or writes a game save."""
import copy,hashlib,json,math,os,pathlib,re,threading

MAX_BYTES=262144
ROOT=pathlib.Path(__file__).resolve().parent
CATALOG=json.loads((ROOT/'hun-catalog.json').read_text(encoding='utf-8'))
ITEMS={r['id']:r for r in CATALOG['items']}
# Accessory row -> its effect class per refine tier (tier 0 is the unrefined item, tier n the nth refinement).
EFFECTS=json.loads((ROOT/'hun-accessory-effects.json').read_text(encoding='utf-8'))['rows']
VERSION=1
LOADOUT_NAME='hun-loadout.tsv'

def integer(value,low,high,label):
    if type(value)is not int or not low<=value<=high:raise ValueError(label+'数值无效')
    return value

def exact(value,keys,label):
    if not isinstance(value,dict)or set(value)!=set(keys):raise ValueError(label+'字段不完整或包含未知字段')

def number(value,low,high,label):
    if type(value)not in (int,float)or not math.isfinite(value)or not low<=value<=high:raise ValueError(label+'数值无效')
    return value

def clean_name(value):
    if not isinstance(value,str)or not 1<=len(value.strip())<=60 or any(ord(c)<32 for c in value):raise ValueError('方案名称需要1～60个可见字符')
    return value.strip()

def default_profile():
    return {'schema':VERSION,'name':'满配魂','items':{key:{'enabled':True,'level':'max','soul':row['soul_option'],'weight':1.0}for key,row in ITEMS.items()},
        'growth':'native_max','attributes':{},'ai_parameters':{},
        'ai':{'deflect_chance':1.0,'red_dodge_chance':1.0,'counter_chance':1.0,'late_weapon_bias':True,
              'repeat_policy':'soft','combo_limit':0},
        'resources':{'medicine_count':'native_max','consume_medicine':True,'consume_skill_resources':True,'cooldown_scale':1.0,'rebirth':'native'},
        'survival':{'grab':'native','execution':'native','lethal':'native'},
        'phases':[{'id':'heimoshang_survival','name':'黑魔伤保命','enabled':True,'health_below':0.25,
                   'weapon_id':next(k for k,r in ITEMS.items()if r['kind']=='main_weapon'and r['row']=='黑魔伤'),
                   'action':'native_combat_art','priority':100,'once':True}],
        'mode':'blue','count':1,'experimental':{'accessory_effects':True}}

def upgrade(profile):
    # Profiles saved before the trial switches existed load with every trial off.
    if isinstance(profile,dict)and'experimental'not in profile:return {**profile,'experimental':{'accessory_effects':False}}
    return profile

def loadout_text(revision,profile,positive=(),non_negative=()):
    """The saved profile in the form the game side reads (hun_loadout.lua): only what it can apply."""
    lines=['HunLoadoutV1\t%d'%revision,'count\t%d'%profile['count'], 'kit\t1']
    def cell(value):
        if type(value) is bool:
            return 'on' if value else 'off'
        return str(value)
    def append(kind,*values):
        lines.append('\t'.join([kind,*(cell(v) for v in values)]))
    # Keep catalog order stable for variants with the same native id. A missing row is disabled.
    ranks={}
    for key,row in ITEMS.items():
        kind=row['kind']
        if kind=='accessory':continue
        ranks[kind]=ranks.get(kind,0)+1
        choice=profile['items'][key]
        if choice['enabled']:
            path=(choice['soul'] and row['soul_config']) or row['normal_config']
            append({'main_weapon':'weapon','shadow_armament':'shadow','resource_armament':'variant'}[kind],
                   key,row['native_id'],path,choice['level'],choice['soul'],choice['weight'],ranks[kind],row['name'])
    for group in ('ai','resources','survival'):
        for field,value in profile[group].items():
            append(group,field,value)
    for field,value in profile['ai_parameters'].items():
        append('param',field,value)
    for phase in profile['phases']:
        if phase['enabled']:
            append('phase',phase['id'],phase['health_below'],phase['weapon_id'],phase['priority'],phase['once'])
    for field in sorted(profile['attributes']):
        value=float(profile['attributes'][field])
        if (field in positive and value<=0)or(field in non_negative and value<0):continue
        lines.append('attr\t%s\t%s'%(field,format(value,'.10g')))
    lines.append('accessories\t'+('on'if profile['experimental']['accessory_effects']else'off'))
    seen=set()
    for key,row in ITEMS.items():
        choice=profile['items'][key]
        if row['kind']!='accessory'or not choice['enabled']:continue
        tiers=EFFECTS[row['row']]
        tier=tiers[-1]if choice['level']=='max'else tiers[min(choice['level'],len(tiers)-1)]
        if tier['effect']in seen:continue
        seen.add(tier['effect'])
        lines.append('ge\t%s\t%d\t%s'%(tier['effect'],tier['level'],re.sub(r'[\x00-\x1f\x7f]',' ',row['name'])[:40]))
    return '\n'.join(lines)+'\n'

def validate(profile,stat_fields,ai_fields):
    profile=upgrade(profile)
    expected=default_profile();exact(profile,expected,'角色方案')
    exact(profile['experimental'],expected['experimental'],'试验功能')
    if type(profile['experimental']['accessory_effects'])is not bool:raise ValueError('试验开关无效')
    if type(profile['schema'])is not int or profile['schema']!=VERSION:raise ValueError('不支持的方案版本')
    display_name=clean_name(profile['name'])
    if profile['growth']!='native_max':raise ValueError('不支持的基础成长模式')
    exact(profile['items'],ITEMS,'装备目录')
    for key,value in profile['items'].items():
        exact(value,('enabled','level','soul','weight'),'装备')
        row=ITEMS[key]
        if type(value['enabled'])is not bool or type(value['soul'])is not bool:raise ValueError('装备开关无效')
        if value['soul']and not row['soul_option']:raise ValueError('此条目没有已识别的铸魂配置')
        if value['level']!='max':
            # Player weapon levels use base level 1, level-2 upgrade indices and a native cap of 60.
            limit=row.get('level_max')
            if limit is None:raise ValueError('该条目的等级边界尚未核验，目前可保存最高有效等级')
            integer(value['level'],1,limit,'装备等级')
        number(value['weight'],0,1000,'装备权重')
    for field,allowed in [('attributes',set(stat_fields)),('ai_parameters',set(ai_fields))]:
        values=profile[field]
        if not isinstance(values,dict)or len(values)>len(allowed):raise ValueError('自定义属性过多')
        for key,value in values.items():
            if key not in allowed:raise ValueError('未知属性：'+str(key))
            number(value,-1e9,1e9,'自定义属性')
            if field=='ai_parameters'and ai_fields[key]in ('int','bool'):
                integer(value,0,1 if ai_fields[key]=='bool'else 1000000,'AI参数')
    exact(profile['ai'],expected['ai'],'AI策略')
    for field in ('deflect_chance','red_dodge_chance','counter_chance'):number(profile['ai'][field],0,1,'AI概率')
    if type(profile['ai']['late_weapon_bias'])is not bool or profile['ai']['repeat_policy']not in ('soft','none'):raise ValueError('AI策略无效')
    integer(profile['ai']['combo_limit'],0,100,'连招长度')
    exact(profile['resources'],expected['resources'],'资源规则')
    resources=profile['resources']
    if resources['medicine_count']!='native_max':integer(resources['medicine_count'],0,10000,'血药数量')
    for key in ('consume_medicine','consume_skill_resources'):
        if type(resources[key])is not bool:raise ValueError('资源开关无效')
    number(resources['cooldown_scale'],0,10,'冷却倍率')
    if resources['rebirth']!='native':raise ValueError('重生机制目前仅支持原版')
    exact(profile['survival'],expected['survival'],'生存规则')
    if any(x not in ('native','immune')for x in profile['survival'].values()):raise ValueError('生存规则无效')
    phases=profile['phases']
    if not isinstance(phases,list)or len(phases)>16:raise ValueError('阶段数量应为0～16')
    ids=set()
    for phase in phases:
        exact(phase,expected['phases'][0],'阶段')
        if not isinstance(phase['id'],str)or not re.fullmatch('[a-zA-Z0-9_-]{1,64}',phase['id'])or phase['id']in ids:raise ValueError('阶段编号无效或重复')
        ids.add(phase['id']);clean_name(phase['name'])
        for key in ('enabled','once'):
            if type(phase[key])is not bool:raise ValueError('阶段开关无效')
        number(phase['health_below'],.01,1,'阶段血线');integer(phase['priority'],0,1000,'阶段优先级')
        if not isinstance(phase['weapon_id'],str)or phase['weapon_id']not in ITEMS or ITEMS[phase['weapon_id']]['kind']!='main_weapon':raise ValueError('阶段武器无效')
        if phase['action']!='native_combat_art':raise ValueError('未知阶段动作')
    if profile['mode']not in ('blue','red','neutral','companion'):raise ValueError('阵营无效')
    integer(profile['count'],1,100,'召唤数量')
    out=copy.deepcopy(profile);out['name']=display_name;return out

def decode(text):
    if not isinstance(text,str)or len(text.encode('utf-8'))>MAX_BYTES:raise ValueError('方案文件超过256 KiB')
    def pairs(items):
        out={}
        for key,value in items:
            if key in out:raise ValueError('方案含重复字段')
            out[key]=value
        return out
    try:return json.loads(text,object_pairs_hook=pairs,parse_constant=lambda value:(_ for _ in ()).throw(ValueError('非有限数字')))
    except RecursionError:raise ValueError('方案嵌套过深')

def _stage(path,data):
    tmp=path.with_name(path.name+'.tmp')
    if path.is_symlink() or tmp.is_symlink():raise OSError('方案路径无效')
    with tmp.open('wb') as output:
        output.write(data)
        output.flush()
        os.fsync(output.fileno())
    return tmp

class Store:
    def __init__(self,path,stat_fields=(),ai_fields=None,positive=(),non_negative=()):
        self.path=pathlib.Path(path);self.stat_fields=stat_fields;self.ai_fields=ai_fields or {};self.lock=threading.Lock()
        self.positive=frozenset(positive);self.non_negative=frozenset(non_negative)
        self.loadout_path=self.path.with_name(LOADOUT_NAME)
        self.profile=default_profile();self.revision=0;self.error=''
        self.resync=False
        self._load()

    def _load(self):
        try:
            if self.path.exists():
                if self.path.is_symlink()or self.path.stat().st_size>MAX_BYTES:raise ValueError('方案文件路径或大小无效')
                payload=decode(self.path.read_text(encoding='utf-8'))
                exact(payload,('revision','profile'),'保存记录');integer(payload['revision'],1,2147483646,'版本')
                profile=validate(payload['profile'],self.stat_fields,self.ai_fields);revision=payload['revision']
            else:profile,revision=default_profile(),0
        except (OSError,UnicodeError,ValueError,TypeError) as err:
            self.error=str(err)
            return
        self.profile,self.revision=profile,revision
        try:self._export(revision,profile)
        except OSError as err:
            self.resync=True
            self.error='魂方案的游戏端副本没写成功：'+str(err)
        else:self.resync,self.error=False,''

    def _export(self,revision,profile):
        content=loadout_text(revision,profile,self.positive,self.non_negative).encode('utf-8')
        try:
            if not self.loadout_path.is_symlink() and self.loadout_path.read_bytes()==content:return
        except OSError:pass
        os.replace(_stage(self.loadout_path,content),self.loadout_path)
        if self.loadout_path.read_bytes()!=content:raise OSError('游戏端副本保存未读回确认')

    def snapshot(self):
        with self.lock:
            if self.resync:self._load()
            return {'revision':self.revision,'profile':copy.deepcopy(self.profile),'error':self.error}

    def save(self,request):
        exact(request,('revision','profile'),'保存请求')
        integer(request['revision'],0,2147483645,'版本')
        profile=validate(request['profile'],self.stat_fields,self.ai_fields)
        with self.lock:
            if self.resync:
                self._load()
                if self.error:raise OSError(self.error)
                if self.revision==request['revision']+1 and self.profile==profile:
                    return {'revision':self.revision,'profile':copy.deepcopy(profile),'error':''}
            if request['revision']!=self.revision:raise ValueError('方案已在另一处更新，请重新载入后再保存')
            revision=self.revision+1
            content=json.dumps({'revision':revision,'profile':profile},ensure_ascii=False,allow_nan=False).encode('utf-8')
            if len(content)>MAX_BYTES:raise ValueError('方案过大')
            mirror=loadout_text(revision,profile,self.positive,self.non_negative).encode('utf-8')
            tmp=_stage(self.path,content)
            game_tmp=_stage(self.loadout_path,mirror)
            previous=self.path.read_bytes() if self.path.exists() else None
            os.replace(tmp,self.path)
            exported=False
            try:
                if self.path.read_bytes()!=content:raise OSError('方案保存未读回确认')
                os.replace(game_tmp,self.loadout_path)
                exported=True
                if self.loadout_path.read_bytes()!=mirror:raise OSError('游戏端副本保存未读回确认')
            except OSError as error:
                # The JSON is authoritative on restart. Restore it before exposing an unconfirmed revision.
                try:
                    if previous is None:self.path.unlink()
                    else:
                        os.replace(_stage(self.path,previous),self.path)
                        if self.path.read_bytes()!=previous:raise OSError('上一版方案未读回确认')
                    if exported:self._export(self.revision,self.profile)
                except OSError as recovery:
                    self.resync=True
                    self.error='方案和游戏副本尚未同步，将在下次读取时重试。'+str(recovery)
                    raise OSError(self.error) from error
                raise
            self.profile,self.revision,self.error=profile,revision,''
            return {'revision':revision,'profile':copy.deepcopy(profile),'error':''}

    def immutable_snapshot(self,revision):
        with self.lock:
            if self.resync:self._load()
            if self.error:raise ValueError('无法确认游戏端方案：'+self.error)
            if revision!=self.revision:raise ValueError('方案已变更，请刷新后重新请求')
            profile=copy.deepcopy(self.profile)
            content=json.dumps(profile,sort_keys=True,ensure_ascii=False,separators=(',',':'))
            return {'revision':revision,'sha256':hashlib.sha256(content.encode()).hexdigest(),'profile':profile}

    def import_text(self,revision,text):
        package=decode(text)
        exact(package,('format','version','profile'),'导入文件')
        if package['format']!='PhantomGladiatorHunProfile'or type(package['version'])is not int or package['version']!=VERSION:
            raise ValueError('不支持的魂方案文件格式')
        return self.save({'revision':revision,'profile':package['profile']})
