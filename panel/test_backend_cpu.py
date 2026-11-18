"""Measure and guard idle status work without caching command eligibility."""
import collections,importlib.util,json,os,pathlib,sys,tempfile,time,types,unittest,unittest.mock
ROOT=pathlib.Path(__file__).resolve().parents[1]
source=pathlib.Path(sys.argv.pop(1))if len(sys.argv)>1 and pathlib.Path(sys.argv[1]).is_file()else ROOT/'panel/backend.py'
backend=types.ModuleType('backend_cpu');backend.__file__=str(ROOT/'panel/backend.py')
exec(compile(source.read_text(encoding='utf-8-sig'),str(source),'exec'),backend.__dict__)

class Tests(unittest.TestCase):
    def test_idle_dispatcher_keeps_transport_checks_without_parsing_game_status(self):
        with unittest.mock.patch.object(self.bridge,'game_status',wraps=self.bridge.game_status) as read:
            for _ in range(40):self.bridge.tick()
            self.assertEqual(read.call_count,0)
            self.write('inbox.tsv','987654\tstart\n');self.bridge.tick()
            self.assertEqual(self.bridge.transport_code,'orphan_inbox')

    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name)
        self.policy=self.root/'policy.json';self.policy.write_text('{"schema_version":1,"units":{}}',encoding='utf-8')
        self.bridge=backend.Bridge(self.root/'runtime',clock=lambda:100.,validation_path=self.policy)
        self.write('status.tsv','schema_version\t1\nheartbeat_unix\t100\ngame_session\ts1\ngame_ready\ttrue\n')
        self.catalog(1000)
        with self.bridge.db:
            self.bridge.db.executemany("INSERT INTO commands(action,payload,state,created,game_session)VALUES(?,?,?,?,?)",[('start','{"action":"start"}','succeeded',90,'s1')for _ in range(100)])
    def tearDown(self):self.bridge.close();self.tmp.cleanup()
    def write(self,name,text):(self.bridge.runtime/name).write_text(text,encoding='utf-8')
    def catalog(self,n):
        header='\t'.join(backend.CATALOG_FIELDS)+'\n'
        rows=[]
        for i in range(n):
            p=f'/Game/BP_Test{i}.BP_Test{i}_C'
            rows.append('\t'.join((p,'Test '+str(i),'mob',p,'1','unknown',"native_parent=/Script/CoreUObject.Class'/Script/ProjectPBZ.PBZCharacter_NPC'")))
        self.write('catalog.tsv',header+'\n'.join(rows)+'\n')
    def test_status_cpu_and_queries(self):
        self.bridge.status();queries=[];self.bridge.db.set_trace_callback(queries.append)
        read=backend.bounded_read;calls=collections.Counter();decorated=[0];decorate=backend.decorate_row
        def wrapped(path,*args,**kwargs):calls[pathlib.Path(path).name]+=1;return read(path,*args,**kwargs)
        def counted(*args,**kwargs):decorated[0]+=1;return decorate(*args,**kwargs)
        backend.bounded_read=wrapped;backend.decorate_row=counted;start=time.process_time()
        try:
            for _ in range(20):
                result=self.bridge.status((1,2,100))
                assert result['catalog']['total']==1000 and len(result['queue'])==100
                assert [r['id']for r in result['watched_commands']]==[1,2,100]
        finally:backend.bounded_read=read;backend.decorate_row=decorate;self.bridge.db.set_trace_callback(None)
        metric={'status_calls':20,'history_rows':100,'catalog_rows':1000,'cpu_seconds':round(time.process_time()-start,6),
                'sql_statements':len(queries),'catalog_rows_decorated':decorated[0],'reads':dict(calls)}
        print('MEASURE '+json.dumps(metric),flush=True)
        self.assertEqual(decorated[0],0,'unchanged display summary must not rebuild every catalog row')
        self.assertLessEqual(len(queries),100,'status should bulk-read command history')
        self.assertEqual(calls['status.tsv'],20,'one status response should share one fresh game snapshot')
    def test_catalog_changed_deleted_and_partial_immediately_invalidate(self):
        self.assertEqual(self.bridge.status()['catalog']['total'],1000)
        self.catalog(3);self.assertEqual(self.bridge.status()['catalog']['total'],3)
        full=self.bridge.runtime/'catalog.tsv';full.rename(full.with_name('catalog.tsv.partial'))
        self.write('status.tsv','schema_version\t1\nheartbeat_unix\t100\ngame_session\ts1\ngame_ready\ttrue\ncatalog_state\tscanning\ncatalog_started_at\t1\n')
        self.assertTrue(self.bridge.status()['catalog']['partial'])
        full.with_name('catalog.tsv.partial').unlink();self.assertFalse(self.bridge.status()['catalog']['available'])
    def test_policy_change_cannot_be_hidden_from_spawn_validation(self):
        self.bridge.status();p='/Game/BP_Test0.BP_Test0_C'
        with self.assertRaises(backend.ValidationError):self.bridge._validate({'action':'spawn','unit_id':p})
        self.policy.write_text('{"schema_version":1,"units":{},"allow_all_catalog":true}',encoding='utf-8')
        self.assertEqual(self.bridge._validate({'action':'spawn','unit_id':p})['unit_id'],p)
        self.policy.write_text('{"schema_version":1,"units":{}}',encoding='utf-8')
        with self.assertRaises(backend.ValidationError):self.bridge._validate({'action':'spawn','unit_id':p})
    def test_same_size_atomic_replacement_and_malformed_file_are_visible(self):
        self.catalog(1);self.bridge.status();p=self.bridge.runtime/'catalog.tsv';old=p.stat()
        text=p.read_text();tmp=p.with_suffix('.tmp');tmp.write_text(text.replace('Test 0','Test X'));os.utime(tmp,ns=(old.st_atime_ns,old.st_mtime_ns));os.replace(tmp,p)
        with unittest.mock.patch.object(backend,'decorate_row',wraps=backend.decorate_row)as decorate:
            self.bridge.status();self.assertEqual(decorate.call_count,1,'atomic replacement with preserved size/time must invalidate summary')
        self.assertEqual(self.bridge.catalog()['units'][0]['name'],'Test X')
        self.write('catalog.tsv','malformed\n');self.assertFalse(self.bridge.status()['catalog']['available'])
    def test_returned_summary_cannot_mutate_later_responses(self):
        a=self.bridge.status();a['catalog']['errors'].append('poison')
        self.assertNotIn('poison',self.bridge.status()['catalog']['errors'])
    def test_expired_heartbeat_is_not_cached(self):
        self.bridge.status();self.bridge.clock=lambda:200
        self.assertFalse(self.bridge.status()['game']['online'])
    def test_path_escape_is_rejected_even_after_cache_hit(self):
        self.bridge.status();p=self.bridge.runtime/'catalog.tsv';p.unlink();outside=self.root/'outside.tsv';outside.write_text('malformed\n')
        try:p.symlink_to(outside)
        except OSError as e:self.skipTest('symlink privilege unavailable: '+str(e))
        self.assertFalse(self.bridge.status()['catalog']['available'])
    def test_pending_lookup_is_indexed_with_large_terminal_history(self):
        with self.bridge.db:
            self.bridge.db.executemany("INSERT INTO commands(action,payload,state,created,game_session)VALUES(?,?,?,?,?)",[('start','{}','succeeded',90,'s1')for _ in range(10000)])
        start=time.process_time()
        for _ in range(100):self.bridge.tick()
        print('MEASURE idle dispatch 100 ticks / 10100 terminal rows CPU seconds='+str(round(time.process_time()-start,6)),flush=True)
        plan=self.bridge.db.execute("EXPLAIN QUERY PLAN SELECT * FROM commands WHERE state='pending' ORDER BY id LIMIT 1").fetchall()
        self.assertTrue(any('INDEX'in r['detail']for r in plan),[r['detail']for r in plan])
    def test_every_summary_dependency_invalidates(self):
        self.bridge.status()
        for file in ('codex.tsv','codex-locations.tsv','inventory-report.json','unit-evidence.json'):
            with unittest.mock.patch.object(self.bridge,'catalog',wraps=self.bridge.catalog)as catalog:
                self.write(file,'invalid\n');self.bridge.status();self.assertEqual(catalog.call_count,1,file)
                self.bridge.status();self.assertEqual(catalog.call_count,1,file+' unchanged')
    def test_live_key_readback_never_uses_summary_cache(self):
        self.bridge.status()
        self.write('status.tsv','schema_version\t1\nheartbeat_unix\t100\ngame_session\ts2\ngame_ready\ttrue\nkey_spawn\tF8\n')
        result=self.bridge.status();self.assertEqual(result['game']['game_session'],'s2');self.assertEqual(result['keybinds']['spawn'],'F8')
    def test_cache_is_bounded_by_age_even_when_metadata_is_unchanged(self):
        with unittest.mock.patch.object(backend.time,'monotonic',return_value=10):self.bridge.status()
        with unittest.mock.patch.object(backend.time,'monotonic',return_value=16),unittest.mock.patch.object(self.bridge,'catalog',wraps=self.bridge.catalog)as catalog:
            self.bridge.status();self.assertEqual(catalog.call_count,1)
if __name__=='__main__':unittest.main()
