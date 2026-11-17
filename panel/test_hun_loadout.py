"""The game-facing copy of the Hun profile: what it carries, when it is rewritten, and old profiles."""
import copy, importlib.util, json, pathlib, tempfile, unittest

ROOT = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('hun', ROOT / 'hun_profiles.py')
hun = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hun)
FIELDS = ('Health_Max', 'Attack', 'Shachi', 'Level')


class LoadoutTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.file = pathlib.Path(self.tmp.name) / 'hun-profile.json'
        self.loadout = self.file.with_name('hun-loadout.tsv')
        self.store = hun.Store(self.file, FIELDS, {}, positive=('Health_Max', 'Attack'), non_negative=('Shachi',))

    def tearDown(self):
        self.tmp.cleanup()

    def rows(self):
        text = self.loadout.read_text(encoding='utf-8')
        self.assertTrue(text.endswith('\n') and '\r' not in text)
        return [line.split('\t') for line in text.splitlines()]

    def test_defaults_are_exported_before_anything_is_saved(self):
        rows = self.rows()
        self.assertEqual(rows[0], ['HunLoadoutV1', '0'])
        self.assertEqual(rows[1], ['count', '1'])
        self.assertIn(['accessories', 'off'], rows)
        self.assertFalse([r for r in rows if r[0] == 'attr'])
        effects = [r for r in rows if r[0] == 'ge']
        self.assertEqual(len(effects), 73, 'every accessory is on by default and each has its own effect class')
        self.assertEqual(len({r[1] for r in effects}), 73)

    def test_a_save_rewrites_the_copy_with_count_attributes_and_the_trial_switch(self):
        profile = self.store.snapshot()['profile']
        profile['count'] = 7
        profile['attributes'] = {'Health_Max': 123456.5, 'Attack': 0, 'Shachi': -1, 'Level': -3}
        profile['experimental']['accessory_effects'] = True
        self.assertEqual(self.store.save({'revision': 0, 'profile': profile})['revision'], 1)
        rows = self.rows()
        self.assertEqual(rows[0], ['HunLoadoutV1', '1'])
        self.assertIn(['count', '7'], rows)
        self.assertIn(['accessories', 'on'], rows)
        self.assertEqual(sorted(r[1:] for r in rows if r[0] == 'attr'), [['Health_Max', '123456.5'], ['Level', '-3']],
                         'values the game would refuse (zero attack, negative Sha-Chi) are left out')

    def test_refine_level_picks_the_tier_and_disabled_accessories_are_left_out(self):
        accessories = [(key, row) for key, row in hun.ITEMS.items() if row['kind'] == 'accessory']
        two_tier = next((key, row) for key, row in accessories if row['level_max'] == 2)
        profile = self.store.snapshot()['profile']
        for key, _ in accessories:
            profile['items'][key]['enabled'] = False
        key, row = two_tier
        tiers = hun.EFFECTS[row['row']]
        self.assertEqual(len(tiers), 3)
        for level, expected in (('max', tiers[2]), (1, tiers[1]), (2, tiers[2])):
            profile['items'][key] = {**profile['items'][key], 'enabled': True, 'level': level}
            saved = self.store.save({'revision': self.store.snapshot()['revision'], 'profile': copy.deepcopy(profile)})
            effects = [r for r in self.rows() if r[0] == 'ge']
            self.assertEqual(effects, [['ge', expected['effect'], str(expected['level']), row['name']]], level)
            self.assertEqual(self.rows()[0][1], str(saved['revision']))

    def test_a_profile_saved_before_the_trial_switch_loads_with_it_off(self):
        old = hun.default_profile()
        del old['experimental']
        self.file.write_text(json.dumps({'revision': 4, 'profile': old}, ensure_ascii=False), encoding='utf-8')
        store = hun.Store(self.file, FIELDS, {})
        snapshot = store.snapshot()
        self.assertEqual((snapshot['error'], snapshot['revision']), ('', 4))
        self.assertEqual(snapshot['profile']['experimental'], {'accessory_effects': False})
        self.assertEqual(self.rows()[0], ['HunLoadoutV1', '4'])
        package = json.dumps({'format': 'PhantomGladiatorHunProfile', 'version': 1, 'profile': old}, ensure_ascii=False)
        self.assertEqual(store.import_text(4, package)['profile']['experimental'], {'accessory_effects': False})
        bad = hun.default_profile()
        bad['experimental'] = {'accessory_effects': 'yes'}
        with self.assertRaises(ValueError):
            store.save({'revision': 5, 'profile': bad})

    def test_a_damaged_profile_does_not_replace_the_copy(self):
        before = self.loadout.read_text(encoding='utf-8')
        self.file.write_text('corrupt', encoding='utf-8')
        store = hun.Store(self.file, FIELDS, {})
        self.assertTrue(store.snapshot()['error'])
        self.assertEqual(self.loadout.read_text(encoding='utf-8'), before)

    def test_effect_table_matches_the_catalog(self):
        rows = {row['row']: row for row in hun.ITEMS.values() if row['kind'] == 'accessory'}
        self.assertEqual(set(rows), set(hun.EFFECTS))
        for name, tiers in hun.EFFECTS.items():
            self.assertEqual(len(tiers), rows[name]['level_max'] + 1, name)
            for tier in tiers:
                self.assertRegex(tier['effect'], r'^/PBZCombatAsset/Prototypes/GameplayEffects/Accessories/[\w/]+\.GE_\w+_C$')
                self.assertIn(tier['level'], range(0, 101))


if __name__ == '__main__':
    unittest.main()
