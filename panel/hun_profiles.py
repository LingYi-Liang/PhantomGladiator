"""Strict, revisioned NPC profile storage. Never reads or writes a game save."""
import copy,hashlib,json,math,os,pathlib,re,threading

MAX_BYTES=262144
ROOT=pathlib.Path(__file__).resolve().parent
CATALOG=json.loads((ROOT/'hun-catalog.json').read_text(encoding='utf-8'))
ITEMS={r['id']:r for r in CATALOG['items']}
VERSION=1

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
                   'weapon_id':next(k for k,r in ITEMS.items()if r['kind']=='main_weapon'and r['name']=='黑魔伤'),
                   'action':'native_combat_art','priority':100,'once':True}],
        'mode':'blue','count':1}

def validate(profile,stat_fields,ai_fields):
    expected=default_profile();exact(profile,expected,'角色方案')
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

class Store:
    def __init__(self,path,stat_fields=(),ai_fields=None):
        self.path=pathlib.Path(path);self.stat_fields=stat_fields;self.ai_fields=ai_fields or {};self.lock=threading.Lock()
        self.profile=default_profile();self.revision=0;self.error=''
        try:
            if self.path.exists():
                if self.path.is_symlink()or self.path.stat().st_size>MAX_BYTES:raise ValueError('方案文件路径或大小无效')
                payload=decode(self.path.read_text(encoding='utf-8'))
                exact(payload,('revision','profile'),'保存记录');integer(payload['revision'],1,2147483646,'版本')
                self.profile=validate(payload['profile'],self.stat_fields,self.ai_fields);self.revision=payload['revision']
        except (OSError,UnicodeError,ValueError,TypeError)as err:self.error=str(err)

    def snapshot(self):
        with self.lock:return {'revision':self.revision,'profile':copy.deepcopy(self.profile),'error':self.error}

    def save(self,request):
        exact(request,('revision','profile'),'保存请求')
        integer(request['revision'],0,2147483645,'版本')
        profile=validate(request['profile'],self.stat_fields,self.ai_fields)
        with self.lock:
            if request['revision']!=self.revision:raise ValueError('方案已在另一处更新，请重新载入后再保存')
            revision=self.revision+1;content=json.dumps({'revision':revision,'profile':profile},ensure_ascii=False,allow_nan=False)
            if len(content.encode('utf-8'))>MAX_BYTES:raise ValueError('方案过大')
            tmp=self.path.with_name(self.path.name+'.tmp')
            if self.path.is_symlink()or tmp.is_symlink():raise ValueError('方案路径无效')
            with tmp.open('w',encoding='utf-8',newline='\n')as f:f.write(content);f.flush();os.fsync(f.fileno())
            os.replace(tmp,self.path)
            if self.path.read_text(encoding='utf-8')!=content:raise OSError('方案保存未读回确认')
            self.profile,self.revision,self.error=profile,revision,''
        return self.snapshot()

    def immutable_snapshot(self,revision):
        with self.lock:
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
