# Dev only: fetch a course's OSM data from the OSM API (Overpass is down) as an Overpass answer.
import json, sys, time, urllib.request, urllib.parse, subprocess
slug, q = sys.argv[1], sys.argv[2]
UA = {'User-Agent': 'openlinks2003-dev-bench (github.com/crspytopgn/openlinks2003)'}
def get(u):
    return urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=120).read()
r = json.loads(get('https://nominatim.openstreetmap.org/search?format=jsonv2&limit=10&q=' + urllib.parse.quote(q)))
r = [p for p in r if p.get('type') == 'golf_course'] or r
if not r: print('no result'); sys.exit(1)
s, n, w, e = map(float, r[0]['boundingbox'])
pad = 0.004
s, n, w, e = s - pad, n + pad, w - pad * 1.6, e + pad * 1.6
json.dump([r[0]], open(f'/tmp/bench/{slug}_nom.json', 'w'))
raw = get(f'https://api.openstreetmap.org/api/0.6/map.json?bbox={w},{s},{e},{n}')
open(f'/tmp/bench/{slug}_map.json', 'wb').write(raw)
subprocess.run(['python3', __import__('os').path.join(__import__('os').path.dirname(__import__('os').path.abspath(__file__)), 'osm2overpass.py'), f'/tmp/bench/{slug}_map.json', f'/tmp/bench/{slug}_op.json'], check=True)
print(r[0]['display_name'])
