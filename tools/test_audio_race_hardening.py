"""Deterministic cancellation/readback/close races. No native audio or game access."""
import importlib.util,io,pathlib,sys,tempfile,threading,unittest,wave
ROOT=pathlib.Path(__file__).resolve().parents[1]
folder=pathlib.Path(sys.argv.pop(1))if len(sys.argv)>1 and pathlib.Path(sys.argv[1]).is_dir()else ROOT/'panel'
spec=importlib.util.spec_from_file_location('audio_race',folder/'local_audio.py')
audio=importlib.util.module_from_spec(spec);spec.loader.exec_module(audio)
class Process:
    def __init__(self):self.stdin=io.BytesIO();self.stdout=io.BytesIO();self.stderr=None;self.dead=False;self.waits=0
    def poll(self):return 0 if self.dead else None
    def kill(self):self.dead=True
    def wait(self,timeout=None):self.waits+=1;return 0
class Child:
    def __init__(self,args,**kw):self.args=args;self.process=Process();self.closed=False
    def close(self):self.closed=True;self.process.dead=True
class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.temp.name);(self.root/'runtime').mkdir();self.children=[]
        self.service=audio.LocalAudio(self.root/'runtime',self.root/'data',self.root/'tools',{'BOSS':'Boss'},self.game,child=self.child)
        self.source=self.root/'source.wav'
        with wave.open(str(self.source),'wb')as w:w.setnchannels(2);w.setsampwidth(2);w.setframerate(44100);w.writeframes(bytes(100*4))
        self.values={'battle_music_mode':'LOCAL','battle_local_client':self.service.client,'battle_local_token':'request-1','battle_local_unit':'BOSS','battle_local_ready':'false'}
        self.ready=True;self.callback=None
    def tearDown(self):self.service.close();self.temp.cleanup()
    def game(self):return {'ready':self.ready,'age_seconds':0,'game_session':'session-1','values':self.values}
    def child(self,args,**kw):
        c=Child(args,**kw);self.children.append(c)
        if self.callback:self.callback()
        return c
    def task(self,cancel=False):
        task={'id':'a'*32,'boss':'BOSS','cancel':cancel,'started':0};self.service.importing=task;return task
    def mapped(self):
        asset='b'*32;(self.service.root/(asset+'.wav')).write_bytes(b'fixture')
        self.service._update(lambda m,v:({'BOSS':{'asset':asset,'name':'test.wav','seconds':1}},v))
    def test_cancelled_import_never_launches_a_decoder(self):
        self.service._import(self.task(True),str(self.source));self.assertEqual(len(self.children),0)
    def test_cancel_during_spawn_closes_without_waiting_for_decode(self):
        task=self.task();self.callback=lambda:task.update(cancel=True)
        self.service._import(task,str(self.source))
        self.assertEqual(self.children[0].process.waits,0);self.assertTrue(self.children[0].closed)
    def test_close_during_spawn_closes_without_waiting_for_decode(self):
        task=self.task();self.callback=self.service.close
        self.service._import(task,str(self.source))
        self.assertEqual(self.children[0].process.waits,0);self.assertTrue(self.children[0].closed)
    def test_late_player_creation_after_close_is_not_published(self):
        self.mapped();self.callback=self.service.close;self.service.tick()
        self.assertIsNone(self.service.player);self.assertTrue(self.children[0].closed)
    def test_mapping_removed_while_player_opens_cannot_get_permission(self):
        self.mapped();self.callback=lambda:self.service.configure({'action':'remove','boss':'BOSS'})
        self.service.tick();self.assertIsNone(self.service.player);self.assertTrue(self.children[0].closed)
    def test_world_session_lost_while_player_opens_cannot_get_permission(self):
        self.mapped();self.callback=lambda:setattr(self,'ready',False)
        self.service.tick();self.assertIsNone(self.service.player);self.assertTrue(self.children[0].closed)
    def test_old_ack_cannot_restore_ready_after_stop(self):
        s=self.service;p=Child([]);p.process.stdout=io.BytesIO(b'{"state":"ready","position":0}\n');s.player=p;s.ack_state='opening'
        entered,release,stopped=threading.Event(),threading.Event(),threading.Event();original=audio.json.loads
        class Ack(dict):
            gated=False
            def __getitem__(self,key):
                if key=='state'and not self.gated:self.gated=True;entered.set();release.wait(2)
                return super().__getitem__(key)
        audio.json.loads=lambda text:Ack(original(text))
        receiver=threading.Thread(target=s._listen,args=(p,));receiver.start()
        stopper=threading.Thread(target=lambda:(s._stop(),stopped.set()))
        try:
            self.assertTrue(entered.wait(1));stopper.start();stopped.wait(.1)
        finally:
            release.set();receiver.join(2);stopper.join(2);audio.json.loads=original
        self.assertFalse(receiver.is_alive()or stopper.is_alive());self.assertIsNone(s.player);self.assertEqual(s.ack_state,'')
    def test_concurrent_child_close_releases_handle_once(self):
        c=audio._process.Child.__new__(audio._process.Child);entered,release=threading.Event(),threading.Event();calls=[]
        class Kernel:
            def CloseHandle(self,handle):calls.append(handle);entered.set();release.wait(2)
        c.k=Kernel();c.job=123;c.process=Process();c._close_lock=threading.Lock();c._closed=False
        one=threading.Thread(target=c.close);two=threading.Thread(target=c.close);one.start();self.assertTrue(entered.wait(1));two.start()
        two.join(.1);release.set();one.join(2);two.join(2)
        self.assertEqual(calls,[123]);self.assertEqual(c.process.waits,1)
if __name__=='__main__':unittest.main()
