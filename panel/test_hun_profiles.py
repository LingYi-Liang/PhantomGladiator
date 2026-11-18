import copy,importlib.util,json,pathlib,tempfile,unittest,unittest.mock
ROOT=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('hun',ROOT/'hun_profiles.py');hun=importlib.util.module_from_spec(spec);spec.loader.exec_module(hun)
class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.file=pathlib.Path(self.tmp.name)/'hun-profile.json'
        self.store=hun.Store(self.file,('Health_Max','Attack'),{'进攻概率':'float','计数':'int','开关':'bool'})
    def tearDown(self):self.tmp.cleanup()
    def test_full_defaults_preserve_all_variants_and_native_rules(self):
        p=self.store.snapshot()['profile'];self.assertEqual(len(p['items']),151);self.assertTrue(all(r['enabled']for r in p['items'].values()))
        self.assertEqual(p['resources']['medicine_count'],'native_max');self.assertEqual(p['resources']['cooldown_scale'],1)
        self.assertEqual(p['phases'][0]['health_below'],.25);self.assertEqual(p['ai']['repeat_policy'],'soft')
        ids=[r['id']for r in hun.CATALOG['items']if r['native_id']=='HuoLiuXing'];self.assertEqual(len(ids),2);self.assertNotEqual(*ids)
    def test_round_trip_and_existing_snapshot_immutability(self):
        before=self.store.immutable_snapshot(0);p=copy.deepcopy(before['profile']);p['name']='新方案';p['attributes']={'Attack':99};p['count']=100
        saved=self.store.save({'revision':0,'profile':p});self.assertEqual(saved['revision'],1)
        self.assertEqual(before['profile']['name'],'满配魂');self.assertNotEqual(before['sha256'],self.store.immutable_snapshot(1)['sha256'])
        again=hun.Store(self.file,('Health_Max','Attack'),{'进攻概率':'float','计数':'int','开关':'bool'})
        self.assertEqual(again.snapshot()['profile'],p)
    def test_stale_revision_does_not_overwrite(self):
        p=self.store.snapshot()['profile'];self.store.save({'revision':0,'profile':p})
        with self.assertRaises(ValueError):self.store.save({'revision':0,'profile':p})
        with self.assertRaises(ValueError):self.store.immutable_snapshot(0)
    def test_no_arbitrary_assets_functions_or_unknown_fields(self):
        for mutate in (lambda p:p.update(path='/Game/Other'),lambda p:p['items'].update({'raw_path':{}}),lambda p:p['attributes'].update({'script':'print(1)'})):
            p=self.store.snapshot()['profile'];mutate(p)
            with self.assertRaises(ValueError):self.store.save({'revision':0,'profile':p})
        self.assertFalse(self.file.exists())
    def test_nonfinite_and_invalid_probability_or_counts_rejected(self):
        for field,value in (('deflect_chance',float('nan')),('red_dodge_chance',float('inf')),('counter_chance',1.1),('combo_limit',True)):
            p=self.store.snapshot()['profile'];p['ai'][field]=value
            with self.assertRaises(ValueError):self.store.save({'revision':0,'profile':p})
        for count in (0,101,True,1.5):
            p=self.store.snapshot()['profile'];p['count']=count
            with self.assertRaises(ValueError):self.store.save({'revision':0,'profile':p})
    def test_explicit_accessory_level_and_no_fake_soul(self):
        p=self.store.snapshot()['profile'];key=next(k for k,r in hun.ITEMS.items()if r['kind']=='accessory'and r['refine_max']==2)
        p['items'][key]['level']=2;self.store.save({'revision':0,'profile':p})
        p['items'][key]['level']=3
        with self.assertRaises(ValueError):self.store.save({'revision':1,'profile':p})
        p['items'][key]['level']=2;p['items'][key]['soul']=True
        with self.assertRaises(ValueError):self.store.save({'revision':1,'profile':p})
    def test_weapon_level_uses_per_variant_native_bound(self):
        p=self.store.snapshot()['profile'];key=next(k for k,r in hun.ITEMS.items()if r['kind']=='main_weapon'and r['level_max']==60)
        p['items'][key]['level']=60;self.store.save({'revision':0,'profile':p})
        for value in (0,61,True,1.5):
            changed=copy.deepcopy(p);changed['items'][key]['level']=value
            with self.assertRaises(ValueError):self.store.save({'revision':1,'profile':changed})
        special=next(k for k,r in hun.ITEMS.items()if r['kind']=='main_weapon'and r['level_max']==10)
        p['items'][special]['level']=11
        with self.assertRaises(ValueError):self.store.save({'revision':1,'profile':p})
    def test_failed_atomic_save_preserves_previous_profile(self):
        p=self.store.snapshot()['profile'];self.store.save({'revision':0,'profile':p});old=self.file.read_bytes();p['name']='拒绝写入'
        with unittest.mock.patch.object(hun.os,'replace',side_effect=OSError('locked')):
            with self.assertRaises(OSError):self.store.save({'revision':1,'profile':p})
        self.assertEqual(self.file.read_bytes(),old);self.assertEqual(self.store.snapshot()['profile']['name'],'满配魂')
    def test_locked_game_copy_does_not_publish_a_new_profile_on_disk_or_after_restart(self):
        for has_previous in (False,True):
            with self.subTest(has_previous=has_previous),tempfile.TemporaryDirectory() as directory:
                path=pathlib.Path(directory)/'profile.json'
                store=hun.Store(path)
                old=store.snapshot()['profile']
                if has_previous:store.save({'revision':0,'profile':old})
                revision=store.snapshot()['revision']
                previous_json=path.read_bytes() if path.exists() else None
                previous_game=store.loadout_path.read_bytes()
                changed=copy.deepcopy(old);changed['count']=7
                replace=hun.os.replace
                def locked(source,destination):
                    if destination==store.loadout_path:raise PermissionError('game copy is locked')
                    return replace(source,destination)
                with unittest.mock.patch.object(hun.os,'replace',side_effect=locked):
                    with self.assertRaises(OSError):store.save({'revision':revision,'profile':changed})
                self.assertEqual(path.read_bytes() if path.exists() else None,previous_json)
                self.assertEqual(store.loadout_path.read_bytes(),previous_game)
                self.assertEqual(store.immutable_snapshot(revision)['profile'],old)
                recovered=hun.Store(path)
                self.assertEqual(recovered.snapshot()['revision'],revision)
                self.assertEqual(recovered.loadout_path.read_bytes(),previous_game)
                self.assertEqual(store.save({'revision':revision,'profile':changed})['revision'],revision+1)
                self.assertIn(b'count\t7\n',store.loadout_path.read_bytes())
    def test_game_readback_failure_restores_both_files(self):
        old=self.store.snapshot()['profile']
        self.store.save({'revision':0,'profile':old})
        mirror=self.store.loadout_path;previous=mirror.read_bytes()
        record=self.file.read_bytes()
        changed=copy.deepcopy(old);changed['count']=9
        read_bytes=pathlib.Path.read_bytes
        fail=True
        def readback(path):
            nonlocal fail
            value=read_bytes(path)
            if path==mirror and value.startswith(b'HunLoadoutV1\t2\n') and fail:
                fail=False
                raise OSError('readback temporarily unavailable')
            return value
        with unittest.mock.patch.object(pathlib.Path,'read_bytes',readback):
            with self.assertRaises(OSError):self.store.save({'revision':1,'profile':changed})
        self.assertFalse(fail)
        self.assertEqual(self.file.read_bytes(),record)
        self.assertEqual(mirror.read_bytes(),previous)
        self.assertEqual(self.store.immutable_snapshot(1)['profile'],old)
    def test_incomplete_rollback_blocks_summon_until_the_persisted_record_is_recovered(self):
        old=self.store.snapshot()['profile']
        self.store.save({'revision':0,'profile':old})
        changed=copy.deepcopy(old);changed['count']=8
        replace=hun.os.replace
        published=False
        def lock_after_publish(source,destination):
            nonlocal published
            if published:raise PermissionError('sharing violation')
            replace(source,destination)
            published=True
        with unittest.mock.patch.object(hun.os,'replace',side_effect=lock_after_publish):
            with self.assertRaises(OSError):self.store.save({'revision':1,'profile':changed})
            self.assertTrue(self.store.snapshot()['error'])
            with self.assertRaises(ValueError):self.store.immutable_snapshot(1)
        self.assertEqual(self.store.save({'revision':1,'profile':changed})['revision'],2)
        recovered=hun.Store(self.file)
        self.assertEqual(recovered.immutable_snapshot(2)['profile'],changed)
        self.assertIn(b'count\t8\n',recovered.loadout_path.read_bytes())
    def test_import_limits_duplicate_keys_and_corrupt_file(self):
        for raw in ('{"a":1,"a":2}','{"x":NaN}',' '*(hun.MAX_BYTES+1)):
            with self.assertRaises(ValueError):hun.decode(raw)
        self.file.write_text('corrupt',encoding='utf-8');store=hun.Store(self.file)
        self.assertTrue(store.snapshot()['error']);self.assertEqual(self.file.read_text(),'corrupt')
if __name__=='__main__':unittest.main()
