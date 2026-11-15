"""Release notes accept maintained languages while retaining historical translations."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='pg-release-languages-') as directory:
    work = pathlib.Path(directory)
    for relative in ('panel/prototype/changelog.js', 'release/safe/latest.json', 'release/safe/versions.json'):
        target = work / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    before = (work / 'panel/prototype/changelog.js').read_text(encoding='utf-8')
    notes = work / 'notes.json'
    notes.write_text(json.dumps({'zh': ['中文更新'], 'en': ['English update']}), encoding='utf-8')
    subprocess.run([sys.executable, '-I', str(ROOT / 'tools/release/changelog.py'), str(work), '999.0.0', '2026-11-16T00:00:00+08:00', str(notes)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, '-I', str(ROOT / 'tools/release/manifest.py'), str(work), '999.0.0', 'a' * 64, '123'], check=True, stdout=subprocess.DEVNULL)
    manifest = json.loads((work / 'release/safe/latest.json').read_text(encoding='utf-8'))
    assert set(manifest['notes']) == {'zh', 'en'}
    versions = json.loads((work / 'release/safe/versions.json').read_text(encoding='utf-8'))['versions']
    assert versions[0]['version'] == '999.0.0'
    assert any(set(entry['notes']) == {'zh', 'en', 'ja', 'fr', 'de', 'es'} for entry in versions[1:])
    assert '"version": "0.40.14"' in before
    notes.write_text(json.dumps({'zh': ['中文更新']}), encoding='utf-8')
    rejected = subprocess.run([sys.executable, '-I', str(ROOT / 'tools/release/changelog.py'), str(work), '999.0.1', '2026-11-16T00:00:00+08:00', str(notes)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert rejected.returncode != 0, 'English notes are required'
print('release_languages: PASS (Chinese/English required, old six-language history preserved)')
