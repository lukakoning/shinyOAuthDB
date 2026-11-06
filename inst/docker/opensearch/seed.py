"""Seed the node using its private administrative client certificate."""
import json
import ssl
import time
import urllib.error
import urllib.request

context = ssl.create_default_context(cafile='/fixtures/tls/ca-cert.pem')
context.load_cert_chain('/state/admin.pem', '/state/admin-key.pem')


def request(path, method='GET', body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request('https://localhost:9200/' + path, data=data, method=method,
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, context=context, timeout=10) as response:
        return json.load(response)


for attempt in range(180):
    try:
        request('')
        break
    except (urllib.error.URLError, TimeoutError):
        time.sleep(1)
else:
    raise RuntimeError('OpenSearch did not initialize')

request('orders', 'PUT', {'mappings': {'properties': {
    'id': {'type': 'integer'}, 'owner': {'type': 'keyword'}, 'marker': {'type': 'keyword'}}}})
for user in ['alice', 'bob']:
    for row in [1, 2]:
        request(f'orders/_doc/{user}-{row}?refresh=true', 'PUT', {
            'id': row, 'owner': user, 'marker': f'{user}-visible-{row}'})
print('OpenSearch document permissions and sample data are ready.')
