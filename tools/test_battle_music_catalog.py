"""Music metadata stays identical in the backend, Lua and UI; no audio is embedded."""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
data = json.loads((ROOT / 'panel/battle-music.json').read_text(encoding='utf-8'))
tracks = {row['id']: row for row in data['tracks']}
assert len(tracks) == len(data['tracks']) and len(tracks) >= 10
for key, row in tracks.items():
    assert re.fullmatch(r'[A-Z][A-Z0-9_]{0,31}', key)
    assert row['event'].startswith('/Game/Wwise/Events/Mus/') and row['state'].startswith('/Game/Wwise/States/Mus/')
    assert '..' not in row['event'] and '..' not in row['state']
lua = (ROOT / 'Mods/PhantomGladiator/Scripts/battle_music_catalog.lua').read_text(encoding='utf-8')
found = {}
string = r'("(?:[^"\\]|\\.)*")'
for match in re.finditer(r'\[' + string + r'\]=\{label=' + string + r',event=' + string + r',state=' + string + r'\}', lua):
    key, label, event, state = map(json.loads, match.groups())
    found[key] = dict(id=key, label=label, event=event, state=state)
assert found == tracks
units = {json.loads(a): json.loads(b) for a, b in re.findall(r'\[' + string + r'\]=' + string + r',', lua)}
assert units == data['units'] and all(value in tracks for value in units.values())
js = (ROOT / 'panel/prototype/battle-music.js').read_text(encoding='utf-8')
ui = json.loads(re.search(r'window\.PG_MUSIC_TRACKS = (\[.*\]);', js).group(1))
assert ui == [{key: row[key] for key in ('id', 'label')} for row in data['tracks']]
print('battle_music_catalog: PASS (', len(tracks), 'tracks and', len(units), 'unit defaults agree)')
