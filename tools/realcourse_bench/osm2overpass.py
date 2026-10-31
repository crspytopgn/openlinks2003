# Converts an OSM API map.json download into an Overpass "out geom" answer (dev testing only).
import json, sys
d = json.load(open(sys.argv[1]))
nodes = {e['id']: e for e in d['elements'] if e['type'] == 'node'}
ways = {e['id']: e for e in d['elements'] if e['type'] == 'way'}
out = []
def geom(w):
    return [{'lat': nodes[n]['lat'], 'lon': nodes[n]['lon']} for n in w['nodes'] if n in nodes]
for e in d['elements']:
    t = e.get('tags', {})
    if not t: continue
    if e['type'] == 'node': out.append({'type': 'node', 'lat': e['lat'], 'lon': e['lon'], 'tags': t})
    elif e['type'] == 'way': out.append({'type': 'way', 'tags': t, 'geometry': geom(e)})
    elif e['type'] == 'relation':
        ms = [{'type': 'way', 'role': m['role'], 'geometry': geom(ways[m['ref']])} for m in e['members'] if m['type'] == 'way' and m['ref'] in ways]
        out.append({'type': 'relation', 'tags': t, 'members': ms})
json.dump({'elements': out}, open(sys.argv[2], 'w'))
print(len(out))
