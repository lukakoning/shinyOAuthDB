"""Provision fixture roles and data over verified HTTPS."""
import base64
import json
import ssl
import time
import urllib.error
import urllib.request

context = ssl.create_default_context(cafile='/out/ca.pem')
authorization = 'Basic ' + base64.b64encode(b'elastic:fixture-admin-password').decode()

def request(path, body=None, method='GET'):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request('https://elasticsearch:9200/' + path, data=data,
                                 headers={'Authorization': authorization,
                                          'Content-Type': 'application/json'}, method=method)
    with urllib.request.urlopen(req, context=context, timeout=15) as response:
        return json.load(response)

for attempt in range(120):
    try:
        request('_cluster/health?wait_for_status=yellow&timeout=5s')
        break
    except (OSError, urllib.error.URLError):
        time.sleep(2)
else:
    raise RuntimeError('Elasticsearch did not become ready')

request('_security/role/orders_reader', {
    'indices': [{'names': ['orders'], 'privileges': ['read', 'view_index_metadata'],
                 'query': {'template': {'source': {'term': {'owner': '{{_user.username}}'}}}},
                 'field_security': {'grant': ['owner', 'country', 'total', 'big_id']}}]}, 'PUT')
request('_security/role/orders_writer', {
    'indices': [{'names': ['orders'], 'privileges': ['all']}]}, 'PUT')
for group, role in [('readers', 'orders_reader'), ('writers', 'orders_writer')]:
    request('_security/role_mapping/' + group, {'enabled': True, 'roles': [role],
            'rules': {'all': [{'field': {'realm.name': 'visitors'}},
                              {'field': {'groups': group}}]}}, 'PUT')
request('orders', {'settings': {'number_of_shards': 1, 'number_of_replicas': 0},
                  'mappings': {'properties': {
                      'owner': {'type': 'keyword'}, 'country': {'type': 'keyword'},
                      'total': {'type': 'integer'}, 'big_id': {'type': 'long'},
                      'secret': {'type': 'keyword'}}}}, 'PUT')
for owner, total in [('alice', 42), ('bob', 17)]:
    request('orders/_doc/' + owner + '?refresh=true', {
        'owner': owner, 'country': 'NL', 'total': total,
        'big_id': 9007199254740993, 'secret': 'private-' + owner}, 'PUT')
request('private-orders/_doc/1?refresh=true', {'secret': 'restricted'}, 'PUT')
print('Seeded Elasticsearch roles and per-user documents.')
