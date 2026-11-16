"""Local audio lifecycle checks with bounded fake children; no game or speakers."""
import importlib.util,io,json,pathlib,subprocess,tempfile,threading,time,unittest,wave
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('local_audio',ROOT/'panel/local_audio.py')
audio=importlib.util.module_from_spec(spec);spec.loader.exec_module(audio)

class Process:
    def __init__(self):self.stdin=io.BytesIO();self.stdout=io.BytesIO();self.stderr=None;self.dead=False
    def poll(self):return 0 if self.dead else None
    def wait(self,timeout=None):return 0

class Child:
    def __init__(self,args,**kw):self.process=Process();self.args=args;self.closed=False
    def close(self):self.closed=True;self.process.dead=True

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.temp.name)
        (self.root/'runtime').mkdir();(self.root/'tools').mkdir()
        self.clock=10.;self.game_reads=0;self.children=[]
        def child(args,**kw):c=Child(args,**kw);self.children.append(c);return c
        self.service=audio.LocalAudio(self.root/'runtime',self.root/'data',self.root/'tools',{'BOSS':'Boss'},self.game,child=child,clock=lambda:self.clock,wall=lambda:1000)
        self.values={'battle_music_mode':'LOCAL','battle_local_client':self.service.client,'battle_local_token':'request-1','battle_local_unit':'BOSS','battle_local_ready':'false'}
        self.ready=True;self.age=0
    def tearDown(self):self.service.close();self.temp.cleanup()
    def game(self):
        self.game_reads+=1;return {'ready':self.ready,'age_seconds':self.age,'game_session':'session-1','values':self.values}
    def mapped(self):
        asset='a'*32;(self.service.root/(asset+'.wav')).write_bytes(b'test fixture')
        self.service._update(lambda m,v:({'BOSS':{'asset':asset,'name':'test.wav','seconds':1}},v))
    def test_empty_feature_has_zero_poll_or_child_cost(self):
        for _ in range(2000):self.service.tick()
        self.assertEqual(self.game_reads,0);self.assertEqual(self.children,[])
    def test_prepared_player_must_wait_for_game_permission(self):
        self.mapped();self.service.tick();self.assertEqual(len(self.children),1)
        self.assertNotIn(b'PLAY',self.children[0].process.stdin.getvalue())
        self.service.ack_state='ready';self.values['battle_local_ready']='true';self.clock+=1;self.service.tick()
        self.assertIn(b'PLAY 50',self.children[0].process.stdin.getvalue())
        for _ in range(100):self.service.tick()
        self.assertEqual(len(self.children),1)
    def test_opening_is_bounded_even_when_worker_repeats_opening_acks(self):
        self.mapped();self.service.tick();self.clock+=3;self.service.ack_at=self.clock;self.service.tick()
        self.assertTrue(self.children[0].closed);self.assertIn('BOSS',self.service.failed)
        for _ in range(100):self.service.tick()
        self.assertEqual(len(self.children),1)
    def test_stale_game_or_wrong_client_stops_playback(self):
        self.mapped();self.service.tick();self.age=3;self.service.tick();self.assertTrue(self.children[0].closed)
        self.age=0;self.values['battle_local_client']='other';self.service.tick();self.assertEqual(len(self.children),1)
    def test_stalled_playback_cannot_keep_native_music_silent(self):
        self.mapped();self.service.tick();self.service.ack_state='playing';self.values['battle_local_ready']='true';self.service.tick()
        self.clock+=4;self.service.ack_at=self.clock;self.service.tick();self.assertTrue(self.children[0].closed)
    def test_volume_validation_and_persistence(self):
        for n in (-1,101,True,'50'):
            with self.assertRaises(ValueError):self.service.configure({'action':'volume','volume':n})
        self.service.configure({'action':'volume','volume':25})
        again=audio.LocalAudio(self.root/'runtime',self.root/'data',self.root/'tools',{'BOSS':'Boss'},self.game)
        self.assertEqual(again.volume,25);again.close()
    def test_slow_configuration_io_does_not_hold_status_lock(self):
        entered=threading.Event();finish=threading.Event();original=audio.atomic
        def slow(*args,**kw):entered.set();finish.wait(1);return original(*args,**kw)
        audio.atomic=slow
        task=threading.Thread(target=lambda:self.service.configure({'action':'volume','volume':20}));task.start()
        try:
            self.assertTrue(entered.wait(1));start=time.monotonic();self.service.snapshot();self.service.tick()
            self.assertLess(time.monotonic()-start,.1)
        finally:finish.set();task.join(2);audio.atomic=original
    def test_import_timeout_preserves_previous_mapping_and_kills_child(self):
        self.mapped();old=dict(self.service.mapping);source=self.root/'bad.mp3';source.write_bytes(b'not audio')
        class Timed(Child):
            def __init__(s,*a,**kw):super().__init__(*a,**kw);self.children.append(s)
            def timeout(s,timeout=None):raise subprocess.TimeoutExpired('decode',timeout)
        def timed(args,**kw):c=Timed(args,**kw);c.process.wait=c.timeout;return c
        self.service.child=timed;self.service.configure({'action':'import','boss':'BOSS','path':str(source)})
        until=time.monotonic()+2
        while self.service.importing and time.monotonic()<until:time.sleep(.01)
        self.assertIsNone(self.service.importing);self.assertEqual(self.service.mapping,old);self.assertTrue(self.children[-1].closed)
    def test_unc_path_and_unknown_boss_are_rejected_without_spawn(self):
        with self.assertRaises(ValueError):self.service.configure({'action':'import','boss':'unknown','path':'x'})
        self.service.configure({'action':'import','boss':'BOSS','path':r'\\server\share\music.mp3'})
        until=time.monotonic()+1
        while self.service.importing and time.monotonic()<until:time.sleep(.01)
        self.assertEqual(self.children,[]);self.assertEqual(self.service.mapping,{})

if __name__=='__main__':unittest.main()
