"""Seed the disposable node using its generated admin client certificate."""
import json
import ssl
import time
import urllib.error
import urllib.request

context = ssl.create_default_context(cafile='/out/ca.pem')
context.load_cert_chain('/out/admin.pem', '/out/admin-key.pem')

def request(path, method='GET', body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request('https://opensearch:9200/' + path, data=data, method=method,
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, context=context, timeout=10) as response:
        return json.load(response)

last_error = None
for attempt in range(180):
    try:
        request('')
        break
    except (urllib.error.URLError, TimeoutError) as error:
        last_error = error
        time.sleep(1)
else:
    raise RuntimeError('OpenSearch did not initialize: ' + str(last_error))

request('orders', 'PUT', {'mappings': {'properties': {
    'owner': {'type': 'keyword'}, 'country': {'type': 'keyword'}, 'total': {'type': 'integer'},
    'secret': {'type': 'keyword'}, 'big_id': {'type': 'long'}}}})
for owner in ['alice', 'bob']:
    request('orders/_doc/' + owner + '?refresh=true', 'PUT', {
        'owner': owner, 'country': 'NL', 'total': 42, 'secret': 'PRIVATE-FIELD', 'big_id': 9007199254740993})
request('private-orders/_doc/1?refresh=true', 'PUT', {'owner': 'alice', 'private': 'FORBIDDEN-INDEX'})
print('OpenSearch Security initialized and fixture data seeded.')
