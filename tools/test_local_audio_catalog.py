import json,pathlib,re
root=pathlib.Path(__file__).resolve().parents[1]
source=(root/'panel/prototype/units.js').read_text(encoding='utf-8').split('window.PG_UNITS =',1)[1].strip().removesuffix(';')
expected=[{'id':r['id'],'name':r['name']}for r in json.loads(source)if r.get('boss')is True]
actual=json.loads((root/'panel/local-bosses.json').read_text(encoding='utf-8'))
assert actual==expected and actual and len({r['id']for r in actual})==len(actual)
assert all(re.fullmatch('[A-Za-z0-9_]{1,180}',r['id'])for r in actual)
print('PASS local music choices match all '+str(len(actual))+' shipped boss cards; no runtime codex boss-field dependency')
