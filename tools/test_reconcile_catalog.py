import importlib.util,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('reconcile',Path(__file__).with_name('reconcile_catalog.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class CatalogReconcileTests(unittest.TestCase):
    def test_exact_export_paths_and_inheritance_not_names(self):
        self.assertEqual(m.object_path("Class'/Script/ProjectPBZ.PBZCharacter_NPC'"),'/Script/ProjectPBZ.PBZCharacter_NPC')
        self.assertIsNone(m.object_path('/Game/X.X_C:Subobject'))
        classes={'/Game/Odd.Odd_C':{'parent':None,'native_parent':'/Script/Custom.NativeNPC'},
                 '/Game/BP_Monster_Fake.BP_Monster_Fake_C':{'parent':None,'native_parent':'/Script/Engine.Actor'}}
        kind,chain,err=m.resolve_kind('/Game/Odd.Odd_C',classes,{'/Script/Custom.NativeNPC':'/Script/ProjectPBZ.PBZCharacter_NPC'})
        self.assertEqual(kind,'npc');self.assertEqual(chain[-1],'/Script/ProjectPBZ.PBZCharacter_NPC')
        self.assertIsNone(m.resolve_kind('/Game/BP_Monster_Fake.BP_Monster_Fake_C',classes,{})[0])
    def test_native_header_modules_and_blueprint_sdk_are_distinct(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'Engine.hpp').write_text('class APawn : public AActor\nclass ACharacter : public APawn\n',encoding='utf-8')
            (root/'ProjectPBZ.hpp').write_text('class APBZCharacter_NPC : public ACharacter\nclass ACustomNPC : public APBZCharacter_NPC\n',encoding='utf-8')
            (root/'BP_Fake.hpp').write_text('class ABP_Fake_C : public ACustomNPC\n',encoding='utf-8')
            edges,sources=m.native_edges(root)
            self.assertEqual(edges['/Script/ProjectPBZ.CustomNPC'],'/Script/ProjectPBZ.PBZCharacter_NPC')
            self.assertNotIn('/Script/BP_Fake.BP_Fake_C',edges)
    def test_cycles_and_conflicts_do_not_create_unit_proof(self):
        classes={'a':{'parent':'b','native_parent':None},'b':{'parent':'a','native_parent':None}}
        self.assertIsNone(m.resolve_kind('a',classes,{})[0])
        classes={'a':{'parent':'/Script/ProjectPBZ.PBZCharacter_NPC','native_parent':'/Script/ProjectPBZ.PBZCharacter_Player'}}
        self.assertEqual(m.resolve_kind('a',classes,{})[2],'conflicting_unit_roots')
    def test_incomplete_manifest_cannot_replace_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            rt=Path(directory);original='existing catalog'
            (rt/'catalog.tsv').write_text(original,encoding='utf-8')
            (rt/'asset-index-status.tsv').write_text('scope\tcurrent_mounted_on_disk_registry\ncomplete\tfalse\n',encoding='utf-8')
            with self.assertRaises(ValueError):m.reconcile(rt,rt,True)
            self.assertEqual((rt/'catalog.tsv').read_text(),original)

if __name__=='__main__':unittest.main()
