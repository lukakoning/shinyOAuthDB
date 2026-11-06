"""Use Keycloak's Ed25519 access tokens directly with the real libSQL server."""
import base64
import http.client
import json
from pathlib import Path
import socket
import subprocess
import sys
import time
sys.path.insert(0, '/demo/python')
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from support import Proxy, keycloak, service_token, serve

token = service_token('libsql-admin', 'demo-libsql-admin-secret')
header = json.loads(base64.urlsafe_b64decode(token.split('.')[0] + '=='))
keys = keycloak('/protocol/openid-connect/certs')['keys']
key = next(k for k in keys if k['kid'] == header['kid'])
if key['kty'] != 'OKP' or key['crv'] != 'Ed25519':
    raise RuntimeError('libSQL requires an Ed25519 signing key')
public = Ed25519PublicKey.from_public_bytes(base64.urlsafe_b64decode(key['x'] + '=='))
Path('/tmp/libsql-public.pem').write_bytes(public.public_bytes(
    serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
process = subprocess.Popen(['/usr/local/bin/sqld', '--db-path', '/tmp/demo.sqld',
    '--http-listen-addr', '127.0.0.1:13000', '--auth-jwt-key-file', '/tmp/libsql-public.pem',
    '--no-welcome', '--disable-metrics'])
for attempt in range(120):
    if process.poll() is not None:
        raise RuntimeError('libSQL exited before readiness')
    try:
        with socket.create_connection(('127.0.0.1', 13000), timeout=1):
            break
    except OSError:
        time.sleep(0.25)
else:
    raise RuntimeError('libSQL did not listen')

statements = ['CREATE TABLE visible_rows (id INTEGER PRIMARY KEY, marker TEXT)',
              "INSERT INTO visible_rows VALUES (1, 'shared-visible-1'), (2, 'shared-visible-2')"]
requests = [{'type': 'execute', 'stmt': {'sql': sql, 'want_rows': False}} for sql in statements]
requests.append({'type': 'close'})
connection = http.client.HTTPConnection('127.0.0.1', 13000, timeout=20)
connection.request('POST', '/v2/pipeline', json.dumps({'requests': requests}),
                   {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
response = connection.getresponse()
result = json.loads(response.read())
connection.close()
if response.status != 200 or any(r['type'] != 'ok' for r in result['results']):
    raise RuntimeError('Could not seed the libSQL database')


class LibsqlProxy(Proxy):
    def do_GET(self):
        self.json({'ready': process.poll() is None}, 200 if process.poll() is None else 503)

    def do_POST(self):
        self.forward(13000)


print('libSQL with Keycloak Ed25519 validation is ready.')
serve(LibsqlProxy, 18444)
