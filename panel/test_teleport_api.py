"""Teleport place list and command over the real loopback API; temporary Runtime, the game is never loaded."""
import http.client,importlib.util,json,pathlib,re,tempfile,threading,time,unittest
ROOT=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('backend',ROOT/'backend.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
LUA=(ROOT.parent/'Mods'/'PhantomGladiator'/'Scripts'/'teleport_places.lua').read_text(encoding='utf-8')
class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name);self.bridge=b.Bridge(self.root/'Runtime')
        self.server=b.PanelServer(self.bridge,ROOT/'prototype',0);self.worker=threading.Thread(target=lambda:self.server.serve_forever(poll_interval=.01),daemon=True);self.worker.start()
    def tearDown(self):
        self.server.shutdown();self.worker.join(2);self.server.server_close();self.bridge.close();self.tmp.cleanup()
    def request(self,method,path,body=None):
        c=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=3)
        c.request(method,path,None if body is None else json.dumps(body,ensure_ascii=False).encode(),{'Content-Type':'application/json','X-CSRF-Token':self.server.csrf_token})
        r=c.getresponse();status=r.status;data=json.loads(r.read());c.close();return status,data
    def ready(self):
        values={'schema_version':'1','heartbeat_unix':str(time.time()),'game_session':'fixture','game_ready':'true'}
        (self.bridge.runtime/'status.tsv').write_text(''.join(k+'\t'+v+'\n'for k,v in values.items()),encoding='utf-8')
    def test_the_app_list_and_the_mod_table_hold_the_same_places(self):
        status,data=self.request('GET','/api/teleport-places');self.assertEqual(status,200)
        places=[p for g in data['groups'] for p in g['places']]
        self.assertGreater(len(places),100)
        mod=dict(re.findall(r'^(T[0-9A-F]{10})=\{world="([A-Za-z0-9_]+)"',LUA,re.M))
        self.assertEqual({p['code'] for p in places},set(mod),'every code the app can send is in the mod table and the reverse')
        for group in data['groups']:
            for place in group['places']:
                self.assertRegex(place['code'],r'^[A-Z0-9_]{1,32}$','a code travels in a key-name column')
                self.assertEqual(mod[place['code']],group['world'])
                self.assertTrue(place['name'] and place['kind'] in ('dev','boss'))
                self.assertTrue(place['en'] and not re.search(r'[㐀-鿿]',place['en']),'an English name for the English interface: '+place['name'])
            self.assertTrue(group['en'] and not re.search(r'[㐀-鿿]',group['en']),group['name'])
        names=[p['name'] for p in places]
        self.assertTrue(any('沐小葵' in n for n in names) and any('左殇' in n for n in names),'the two places that were asked for')
        page=(ROOT/'prototype'/'teleport-page.js').read_text(encoding='utf-8')
        keys=lambda lang:set(re.findall(r'^  "([a-zA-Z.]+)":',page.split('I18N.add("'+lang+'", {',1)[1].split(chr(10)+'});',1)[0].replace(chr(13),''),re.M))
        self.assertTrue(keys('zh') and keys('zh')==keys('en'),'the page says everything in both languages')
    def test_a_place_code_is_all_that_reaches_the_game(self):
        code=next(iter(b.TELEPORT_CODES));self.ready()
        for bad in ({'action':'teleport'},{'action':'teleport','place':'TNOPE00000'},{'action':'teleport','place':7},
                    {'action':'teleport','place':code,'x':1},{'action':'teleport','place':code,'unit_id':'/Game/X'},
                    {'action':'teleport_back','place':code}):
            status,_=self.request('POST','/api/command',bad);self.assertEqual(status,400,bad)
        status,job=self.request('POST','/api/command',{'action':'teleport','place':code});self.assertEqual(status,202)
        self.bridge.tick()
        wire=(self.bridge.runtime/'inbox.tsv').read_text(encoding='utf-8').rstrip('\n').split('\t')
        self.assertEqual(len(wire),10);self.assertEqual((wire[1],wire[2],wire[5],wire[9]),('teleport','',code,'1'))
        self.assertEqual(self.bridge._wire({'id':1,'payload':json.dumps(self.bridge._validate({'action':'teleport_back'}))}).split('\t')[1],'teleport_back')
    def test_a_teleport_key_is_a_code_and_a_chord_and_the_game_state_is_reported(self):
        code=next(iter(b.TELEPORT_CODES))
        for bad in ({'action':'configure_teleport_key','place':'TNOPE00000','key_code':119},{'action':'configure_teleport_key','place':code,'key_code':300},
                    {'action':'configure_teleport_key','place':code,'key_code':119,'modifiers':8},{'action':'configure_teleport_key','place':code,'key_code':121},
                    {'action':'configure_teleport_key','place':code,'key_code':119,'x':1}):
            with self.assertRaises(b.ValidationError,msg=bad):self.bridge._validate(bad)
        def wire(request):return self.bridge._wire({'id':1,'payload':json.dumps(self.bridge._validate(request))}).rstrip('\n').split('\t')
        row=wire({'action':'configure_teleport_key','place':code,'key_code':119,'modifiers':3})
        self.assertEqual((len(row),row[1],row[5],row[6],row[7]),(10,'configure_teleport_key',code,'VK_119','MOD_3'))
        row=wire({'action':'configure_teleport_key','place':'BACK','key_code':0})
        self.assertEqual((row[5],row[6],row[7]),('BACK','UNBOUND','MOD_0'))
        row=wire({'action':'configure_teleport_key','place':code,'key_code':203,'modifiers':2})
        self.assertEqual(row[5:8],[code,'VK_203','MOD_2'])
        status,data=self.request('GET','/api/teleport-places');self.assertEqual(data['keys'],{})
        (self.bridge.runtime/'teleport-keybinds-state.tsv').write_text('TeleportKeyStateV1\t2\ttpkeys-1\nBACK\t120\t1\t1\t\n'+code+'\t119\t0\t0\t该键已被功能「开战」占用\nTNOPE\t65\t0\t1\t\n',encoding='utf-8')
        status,data=self.request('GET','/api/teleport-places')
        self.assertEqual(data['keys'],{'BACK':{'key_code':120,'modifiers':1,'active':True,'message':''},code:{'key_code':119,'modifiers':0,'active':False,'message':'该键已被功能「开战」占用'}})
    def test_teleport_waits_for_the_game_to_be_ready(self):
        code=next(iter(b.TELEPORT_CODES))
        self.assertIn('teleport',b.READY_ACTIONS);self.assertIn('teleport_back',b.READY_ACTIONS)
        status,_=self.request('POST','/api/command',{'action':'teleport','place':code})
        self.bridge.tick();self.assertFalse((self.bridge.runtime/'inbox.tsv').exists(),'held while the game is not ready')
if __name__=='__main__':unittest.main()
