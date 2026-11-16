"""Real loopback profile/probe transport; uses temporary Runtime and never loads the game."""
import http.client,importlib.util,json,pathlib,tempfile,threading,time,unittest
ROOT=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('backend',ROOT/'backend.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name);self.bridge=b.Bridge(self.root/'Runtime')
        self.server=b.PanelServer(self.bridge,ROOT/'prototype',0);self.worker=threading.Thread(target=lambda:self.server.serve_forever(poll_interval=.01),daemon=True);self.worker.start()
    def tearDown(self):
        self.server.shutdown();self.worker.join(2);self.server.server_close();self.bridge.close();self.tmp.cleanup()
    def request(self,method,path,body=None,token=True):
        c=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=3)
        headers={'Content-Type':'application/json'}
        if token:headers['X-CSRF-Token']=self.server.csrf_token
        c.request(method,path,None if body is None else json.dumps(body,ensure_ascii=False).encode(),headers)
        r=c.getresponse();status=r.status;data=json.loads(r.read());c.close();return status,data
    def ready(self,**extra):
        values={'schema_version':'1','heartbeat_unix':str(time.time()),'game_session':'fixture','game_ready':'true','hun_body_probe_supported':'true',**extra}
        (self.bridge.runtime/'status.tsv').write_text(''.join(k+'\t'+v+'\n'for k,v in values.items()),encoding='utf-8')
    def test_profile_load_save_import_and_revision(self):
        status,data=self.request('GET','/api/hun');self.assertEqual(status,200);self.assertEqual(len(data['catalog']['items']),151)
        profile=data['profile'];profile['name']='独立方案';profile['count']=100
        status,saved=self.request('POST','/api/hun-profile',{'revision':0,'profile':profile});self.assertEqual(status,200);self.assertEqual(saved['revision'],1)
        status,_=self.request('POST','/api/hun-profile',{'revision':0,'profile':profile});self.assertEqual(status,400)
        text=json.dumps({'format':'PhantomGladiatorHunProfile','version':1,'profile':profile},ensure_ascii=False)
        status,saved=self.request('POST','/api/hun-profile',{'revision':1,'import_text':text});self.assertEqual(status,200);self.assertEqual(saved['revision'],2)
    def test_import_rejects_duplicate_keys_without_overwrite(self):
        status,_=self.request('POST','/api/hun-profile',{'revision':0,'import_text':'{"format":"bad","format":"PhantomGladiatorHunProfile","version":1,"profile":{}}'})
        self.assertEqual(status,400);self.assertFalse((self.bridge.runtime/'hun-profile.json').exists())
    def test_probe_is_capability_guarded_and_has_no_arbitrary_class(self):
        request={'action':'hun_body_probe','team':'blue','count':100,'profile_revision':0}
        status,_=self.request('POST','/api/command',request);self.assertEqual(status,400)
        self.ready();status,_=self.request('POST','/api/command',{**request,'unit_id':'/Game/Other'});self.assertEqual(status,400)
        status,data=self.request('POST','/api/command',request);self.assertEqual(status,202)
        self.bridge.tick();self.assertTrue((self.bridge.runtime/'inbox.tsv').exists(),(self.bridge.transport_error,self.bridge._command(data['id'])))
        wire=(self.bridge.runtime/'inbox.tsv').read_text();self.assertIn('\thun_body_probe\t\tblue\t100\t0\t',wire)
        self.assertFalse((self.bridge.runtime/'hun-profile.json').exists(),'probe cannot mutate saved equipment')
    def test_stop_cancels_pending_probes_and_queue_mode_refuses_them(self):
        self.ready();request={'action':'hun_body_probe','team':'blue','count':1,'profile_revision':0}
        status,job=self.request('POST','/api/command',request);self.assertEqual(status,202)
        status,_=self.request('POST','/api/command',{'action':'stop'});self.assertEqual(status,202)
        self.assertEqual(self.bridge._command(job['id'])['status'],'failed')
        self.ready(summon_queue_enabled='true');status,_=self.request('POST','/api/command',request);self.assertEqual(status,400)
    def test_csrf_and_corrupt_profile_do_not_write(self):
        profile=b._hun_module.default_profile()
        status,_=self.request('POST','/api/hun-profile',{},False);self.assertEqual(status,403)
        profile['items']['/Game/Injected']={};status,_=self.request('POST','/api/hun-profile',{'revision':0,'profile':profile});self.assertEqual(status,400)
        self.assertFalse((self.bridge.runtime/'hun-profile.json').exists())
    def test_changed_profile_before_delivery_fails_without_blocking_queue(self):
        self.ready();_,job=self.request('POST','/api/command',{'action':'hun_body_probe','team':'blue','count':1,'profile_revision':0})
        self.bridge.hun_profiles.save({'revision':0,'profile':b._hun_module.default_profile()})
        self.bridge.tick();self.assertEqual(self.bridge._command(job['id'])['status'],'failed')
        self.assertFalse((self.bridge.runtime/'inbox.tsv').exists())
    def test_bad_optional_profile_path_keeps_regular_status_available(self):
        runtime=self.root/'OtherRuntime';runtime.mkdir();outside=self.root/'outside-profile.json';outside.write_text('untouched')
        try:(runtime/'hun-profile.json').symlink_to(outside)
        except OSError as error:self.skipTest('symlink privilege unavailable: '+str(error))
        bridge=b.Bridge(runtime)
        try:
            self.assertIsNone(bridge.hun_profiles);self.assertTrue(bridge.hun_profile_error)
            self.assertFalse(bridge.status()['game']['online']);self.assertEqual(outside.read_text(),'untouched')
        finally:bridge.close()
if __name__=='__main__':unittest.main()
