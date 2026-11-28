"""Generate the mod and UI music metadata from the shared catalog; contains no audio."""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
data = json.loads((ROOT / 'panel/battle-music.json').read_text(encoding='utf-8'))
quote = lambda value: json.dumps(value, ensure_ascii=False)
tracks = {track['id']: track for track in data['tracks']}
assert len(tracks) == len(data['tracks']) and all(track in tracks for track in data['units'].values())
lua = ['-- Music asset references only; audio remains in the installed game.', 'return {tracks={']
for key, row in tracks.items():
    lua.append('[' + quote(key) + ']={' + ','.join(name + '=' + quote(row[name]) for name in ('label', 'event', 'state')) + '},')
lua.append('},units={')
lua.extend('[' + quote(unit) + ']=' + quote(track) + ',' for unit, track in sorted(data['units'].items()))
lua.append('}}')
(ROOT / 'Mods/PhantomGladiator/Scripts/battle_music_catalog.lua').write_text('\n'.join(lua) + '\n', encoding='utf-8', newline='\n')
ui = [
    {'id': row['id'], 'label': row['label'], 'group': row['event'].rsplit('/', 1)[-1].split('.', 1)[0]}
    for row in data['tracks']
]
(ROOT / 'panel/prototype/battle-music.js').write_text('"use strict";\nwindow.PG_MUSIC_TRACKS = ' + json.dumps(ui, ensure_ascii=False) + ';\n', encoding='utf-8', newline='\n')
print('Music metadata:', len(tracks), 'tracks;', len(data['units']), 'unit defaults')
source=(ROOT/'panel/prototype/units.js').read_text(encoding='utf-8').split('window.PG_UNITS =',1)[1].strip().removesuffix(';')
bosses=[{'id':row['id'],'name':row['name']}for row in json.loads(source)if row.get('boss')is True]
(ROOT/'panel/local-bosses.json').write_text(json.dumps(bosses,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
print('Local music targets:',len(bosses),'boss cards')
