"""Opt-in local boss music, prepared off-thread and played in a bounded child."""
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
import time
import uuid
import wave

_spec=importlib.util.spec_from_file_location('pg_audio_process',Path(__file__).with_name('audio_process.py'))
_process=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_process)
Child=_process.Child
MAX_SOURCE=512<<20
MAX_WAVE=320<<20
MAX_CACHE=1<<30
MAX_SECONDS=1800
ASSET=re.compile(r'^[a-f0-9]{32}$')
UNIT=re.compile(r'^[A-Za-z0-9_]{1,180}$')
TOKEN=re.compile(r'^[A-Za-z0-9_:\-]{1,240}$')


def atomic(path,text,*,durable=True):
    tmp=path.with_name(path.name+'.tmp')
    if path.is_symlink() or tmp.is_symlink():raise ValueError('音频配置路径无效')
    with tmp.open('w',encoding='utf-8',newline='\n')as f:
        f.write(text);f.flush()
        if durable:os.fsync(f.fileno())
    os.replace(tmp,path)


class LocalAudio:
    def __init__(self,runtime,data,tools,bosses,game_status,*,child=Child,clock=time.monotonic,wall=time.time):
        self.runtime=Path(runtime).resolve();self.root=Path(data).resolve()/hashlib.sha256(str(self.runtime).encode()).hexdigest()[:16]
        self.root.mkdir(parents=True,exist_ok=True)
        self.tools=Path(tools);self.bosses=dict(bosses);self.game_status=game_status;self.child=child;self.clock=clock;self.wall=wall
        self.lock=threading.RLock();self.closed=threading.Event();self.client=uuid.uuid4().hex
        self.save_lock=threading.Lock()
        self.supported=self.tools.joinpath('ffmpeg.exe').is_file()and self.tools.joinpath('LocalAudioPlayer.exe').is_file()
        self.mapping={};self.volume=50;self.revision=0;self.message='选择 BOSS 后导入本地音频，切换到本地替换模式后开战播放'
        self.importing=None;self.convert=None;self.player=None;self.token='';self.source='';self.sent_volume=None
        self.ack_state='';self.ack_at=0;self.failed=set();self.next_link=0;self.thread=None
        self.opened_at=0;self.progress_at=0;self.position=-1;self.log_lines=0
        self.link_failures=0;self.link_faulted=False
        self.link=self.runtime/'battle-local-link.tsv';self.settings=self.root/'settings.json'
        try:
            if self.settings.exists():
                if self.settings.is_symlink()or self.settings.stat().st_size>65536:raise ValueError('配置过大')
                cfg=json.loads(self.settings.read_text(encoding='utf-8'))
                if cfg.get('schema')!=1 or type(cfg.get('volume'))is not int or not 0<=cfg['volume']<=100:raise ValueError('配置格式无效')
                for unit,row in cfg.get('mapping',{}).items():
                    if unit not in self.bosses or not isinstance(row,dict)or not ASSET.fullmatch(row.get('asset','')):raise ValueError('配置单位无效')
                    if not isinstance(row.get('name'),str)or len(row['name'])>240 or type(row.get('seconds'))not in (float,int)or not math.isfinite(row['seconds'])or not 0<row['seconds']<=MAX_SECONDS:raise ValueError('配置曲目无效')
                    self.mapping[unit]={'asset':row['asset'],'name':row['name'],'seconds':row['seconds']}
                self.volume=cfg['volume']
        except (OSError,ValueError,TypeError,AttributeError):
            self.mapping={};self.message='本地音频配置读取失败，已停用替换'

    def start(self):
        self.thread=threading.Thread(target=self._loop,name='local-audio-monitor',daemon=True);self.thread.start()

    def snapshot(self):
        with self.lock:
            return {'supported':self.supported,
                    'revision':self.revision,'volume':self.volume,'importing':bool(self.importing),'message':self.message,
                    'mapping':{u:{'name':r['name'],'seconds':r['seconds']}for u,r in self.mapping.items()},
                    'bosses':[{'id':u,'name':n}for u,n in self.bosses.items()]}

    def _update(self,change):
        if not self.save_lock.acquire(blocking=False):raise ValueError('正在保存音频配置，请稍后重试')
        try:
            with self.lock:mapping,volume=change(dict(self.mapping),self.volume)
            text=json.dumps({'schema':1,'volume':volume,'mapping':mapping},ensure_ascii=False)
            atomic(self.settings,text)
            if self.settings.read_text(encoding='utf-8')!=text:raise OSError('音频设置保存未确认')
            with self.lock:
                self.mapping=mapping;self.volume=volume;self.revision+=1;self.failed.clear()
                self.link_failures=0;self.link_faulted=False
        finally:self.save_lock.release()

    def configure(self,request):
        if not isinstance(request,dict):raise ValueError('音频请求无效')
        action=request.get('action')
        if self.closed.is_set():raise ValueError('音频服务已关闭')
        if action=='volume'and set(request)=={'action','volume'}and type(request['volume'])is int and 0<=request['volume']<=100:
            self._update(lambda mapping,volume:(mapping,request['volume']));self.message='本地音乐音量已保存'
        elif action=='remove'and set(request)=={'action','boss'}and request['boss']in self.bosses:
            def remove(mapping,volume):mapping.pop(request['boss'],None);return mapping,volume
            self._update(remove)
            with self.lock:
                if self.importing and self.importing['boss']==request['boss']:self.importing['cancel']=True
            self.message='已移除该 BOSS 的本地音乐'
        elif action=='retry'and set(request)=={'action'}:
            with self.lock:self.failed.clear();self.link_failures=0;self.link_faulted=False
            self.message='已允许本场重新尝试本地音乐'
        elif action=='import'and set(request)=={'action','boss','path'}:
            if request['boss']not in self.bosses or not isinstance(request['path'],str)or len(request['path'])>4096:raise ValueError('BOSS 或文件路径无效')
            with self.lock:
                if self.importing:raise ValueError('正在处理一个音频，请等待完成')
                task={'id':uuid.uuid4().hex,'boss':request['boss'],'cancel':False,'started':self.clock()};self.importing=task
                self.message='正在后台准备音频，完成前继续使用原配置'
                threading.Thread(target=self._import,args=(task,request['path']),name='local-audio-import',daemon=True).start()
        else:raise ValueError('音频请求格式无效')
        return self.snapshot()

    def _import(self,task,source):
        target=self.root/(task['id']+'.wav');guard=None;committed=False
        try:
            if not self._import_active(task):return
            # Remote paths and alternate streams are not opened by the import worker.
            if source.startswith(('\\\\','//'))or '\x00'in source or (os.name=='nt'and (not re.match(r'^[A-Za-z]:[\\/]',source)or ':'in source[2:])):raise ValueError('请选择本地磁盘上的音频文件')
            path=Path(source).resolve(strict=True)
            if not path.is_file()or not 0<path.stat().st_size<=MAX_SOURCE:raise ValueError('音频文件为空或超过 512 MB')
            with self.lock:referenced={r['asset']for r in self.mapping.values()}
            if self.player:referenced.add(getattr(self,'play_asset',''))
            for old in self.root.glob('*.wav'):
                if not self._import_active(task):return
                if old.stem not in referenced and ASSET.fullmatch(old.stem)and not old.is_symlink():
                    try:old.unlink()
                    except OSError:pass
            used=sum(p.stat().st_size for p in self.root.glob('*.wav')if not p.is_symlink())
            if used+MAX_WAVE>MAX_CACHE or shutil.disk_usage(self.root).free<MAX_WAVE+(128<<20):raise ValueError('音频缓存空间不足，请先移除不用的曲目')
            args=[str(self.tools/'ffmpeg.exe'),'-nostdin','-hide_banner','-loglevel','fatal','-max_alloc','67108864',
                  '-threads','1','-filter_threads','1','-protocol_whitelist','file,pipe','-probesize','5000000','-analyzeduration','5000000',
                  '-i',str(path),'-map','0:a:0','-vn','-sn','-dn','-map_metadata','-1','-threads','1','-ac','2','-ar','44100',
                  '-c:a','pcm_s16le','-t',str(MAX_SECONDS+1),'-fs',str(MAX_WAVE),'-y',str(target)]
            if not self._import_active(task):return
            guard=self.child(args,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            with self.lock:
                if not self._import_active(task):return
                self.convert=guard
            try:code=guard.process.wait(timeout=45)
            except subprocess.TimeoutExpired:raise ValueError('音频处理超时，已停止；请尝试较短的文件')
            if code!=0 or not target.is_file()or target.stat().st_size>=MAX_WAVE:raise ValueError('无法解码该音频，已保留原配置')
            with wave.open(str(target),'rb')as wav:
                seconds=wav.getnframes()/wav.getframerate()
                if wav.getnchannels()!=2 or wav.getsampwidth()!=2 or wav.getframerate()!=44100 or not 0<seconds<=MAX_SECONDS:raise ValueError('音频无有效内容或超过 30 分钟')
            def install(mapping,volume):
                if self.closed.is_set()or task['cancel']or self.importing is not task:raise ValueError('音频准备已取消')
                mapping[task['boss']]={'asset':task['id'],'name':path.name[:240],'seconds':round(seconds,3)}
                return mapping,volume
            self._update(install);committed=True;self.message='音频已准备好，保存本地替换模式后开战播放'
            self._log('prepared boss='+task['boss']+' seconds='+str(round(seconds,3)))
        except (OSError,ValueError,wave.Error,EOFError)as error:
            with self.lock:self.message=str(error)
        finally:
            if guard:guard.close()
            with self.lock:
                if self.importing is task:self.importing=None
                if self.convert is guard:self.convert=None
            if not committed:
                try:target.unlink(missing_ok=True)
                except OSError:pass

    def _import_active(self,task):
        with self.lock:return not self.closed.is_set()and not task['cancel']and self.importing is task

    def _stop(self):
        with self.lock:
            player=self.player;self.player=None;self.token='';self.source='';self.sent_volume=None;self.ack_state=''
        if player:player.close()

    def _log(self,text):
        if self.log_lines<40:self.log_lines+=1;print('[LocalAudio] '+text,flush=True)

    def _listen(self,player):
        try:
            while not self.closed.is_set():
                line=player.process.stdout.readline(4097)
                if not line or len(line)>4096:return
                data=json.loads(line)
                if data.get('state')not in ('opening','ready','playing','failed'):return
                position=data.get('position')
                if type(position)not in (float,int)or not math.isfinite(position)or not 0<=position<=MAX_SECONDS+1:return
                with self.lock:
                    if self.player is not player:return
                    changed=self.ack_state!=data['state']
                    self.ack_state=data['state'];self.ack_at=self.clock()
                    if position!=self.position:self.position=position;self.progress_at=self.clock()
                if changed:self._log('player state='+data['state']+' position='+str(position))
        except (OSError,ValueError):pass

    def _send(self,text):
        player=self.player
        if not player or self.closed.is_set():return
        player.process.stdin.write((text+'\n').encode('ascii'));player.process.stdin.flush()

    def tick(self):
        if self.closed.is_set():return
        with self.lock:
            mapping=dict(self.mapping);volume=self.volume;failed=set(self.failed)
        if not mapping and not self.player:return
        game=self.game_status();v=game.get('values',{});session=game.get('game_session')or ''
        available=game.get('ready')and game.get('age_seconds')is not None and 0<=game['age_seconds']<=2.5 and v.get('battle_music_mode')=='LOCAL'
        unit=v.get('battle_local_unit','');token=v.get('battle_local_token','')
        selected=available and v.get('battle_local_client')==self.client and unit in mapping and unit not in failed and TOKEN.fullmatch(token)
        if not selected:self._stop()
        elif token!=self.token:
            self._stop();asset=self.root/(mapping[unit]['asset']+'.wav')
            if asset.is_symlink()or not asset.is_file():self.failed.add(unit);self.message='本地曲目文件已丢失，已跳过';selected=False
            else:
                candidate=None
                try:
                    candidate=self.child([str(self.tools/'LocalAudioPlayer.exe'),str(asset)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,memory=256<<20)
                    fresh=self.game_status();fv=fresh.get('values',{})
                    with self.lock:
                        row=self.mapping.get(unit)
                        current=(not self.closed.is_set()and row and row['asset']==mapping[unit]['asset']and unit not in self.failed
                            and fresh.get('ready')is True and fresh.get('game_session')==session
                            and fresh.get('age_seconds')is not None and 0<=fresh['age_seconds']<=2.5
                            and fv.get('battle_music_mode')=='LOCAL'and fv.get('battle_local_client')==self.client
                            and fv.get('battle_local_token')==token and fv.get('battle_local_unit')==unit)
                        if current:
                            self.player=candidate;self.token,self.source=token,unit;self.ack_at=self.clock();self.ack_state='opening'
                            self.opened_at=self.clock();self.play_asset=row['asset'];self.position=-1;self.progress_at=self.clock();volume=self.volume
                            published=candidate;candidate=None
                    if current:threading.Thread(target=self._listen,args=(published,),name='local-audio-readback',daemon=True).start()
                except OSError:
                    self.failed.add(unit);self.message='独立播放器无法启动，已跳过本场曲目';self._stop();selected=False
                finally:
                    if candidate:candidate.close()
        if self.player:
            if self.player.process.poll()is not None or self.ack_state=='failed'or self.clock()-self.ack_at>2 or (self.ack_state=='opening'and self.clock()-self.opened_at>2)or (self.sent_volume is not None and self.clock()-self.progress_at>3):
                self.failed.add(self.source);self.message='播放器未及时响应，已停止并交还原版';self._stop()
            else:
                self._send('PING')
                if v.get('battle_local_ready')=='true'and self.ack_state in ('ready','playing')and self.sent_volume!=volume:
                    self._send('PLAY '+str(volume));self.sent_volume=volume
                    self.progress_at=self.clock()
                elif v.get('battle_local_ready')!='true'and self.sent_volume is not None:self._stop()
        if available and not self.closed.is_set()and not self.link_faulted and self.clock()>=self.next_link:
            self.next_link=self.clock()+1
            with self.lock:
                ids=','.join(sorted(u for u in self.mapping if u not in self.failed))
                prepared=self.token if self.player and self.ack_state in ('ready','playing')else '-'
            if not TOKEN.fullmatch(session):return
            try:
                atomic(self.link,'LocalMusicLinkV1\t'+str(int(self.wall()))+'\t'+session+'\t'+self.client+'\t'+prepared+'\t'+ids+'\n',durable=False)
                self.link_failures=0
            except (OSError,ValueError)as error:
                self.link_failures=3 if isinstance(error,ValueError)else self.link_failures+1
                self._log('heartbeat write failed: '+type(error).__name__+' attempt='+str(self.link_failures))
                if self.link_failures>=3:
                    with self.lock:self.failed.update(self.mapping);self.link_faulted=True
                    self._stop();self.message='音乐状态连续未同步，已停止本地播放；可手动重试'
                else:self.message='音乐状态暂未同步，稍后自动重试；连续失败会停止本地播放'

    def _loop(self):
        while not self.closed.wait(0.25):
            try:
                with self.lock:
                    if self.importing and self.clock()-self.importing['started']>55:
                        self.importing['cancel']=True;self.message='音频文件读取长时间未响应，已暂停本次导入；其他功能可继续使用'
                self.tick()
            except Exception as error:
                with self.lock:self.failed.update(self.mapping)
                self.message='本地音频状态异常，已暂停替换'
                print('[LocalAudio] monitor disabled: '+type(error).__name__,flush=True)
                try:self._stop()
                except OSError:pass

    def close(self):
        self.closed.set();self._stop()
        with self.lock:
            if self.importing:self.importing['cancel']=True
            converting=self.convert
        if converting:converting.close()
        if self.thread:self.thread.join(timeout=1)
