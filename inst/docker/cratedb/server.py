"""Keep Keycloak tokens intact while serving CrateDB's issuer-as-JWKS URL."""
import base64
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
sys.path.insert(0, '/demo/python')
from support import ISSUER, Proxy, serve, service_token


class KeycloakProxy(Proxy):
    def route(self):
        if self.command == 'GET' and self.path == '/realms/shinyoauthdb':
            # CrateDB fetches keys from iss itself rather than OIDC discovery.
            with urllib.request.urlopen('http://localhost:18080/realms/shinyoauthdb/protocol/openid-connect/certs', timeout=10) as response:
                self.json(json.load(response))
        else:
            self.forward(18080, extra_headers={'X-Forwarded-Proto': 'https',
                'X-Forwarded-Host': 'localhost', 'X-Forwarded-Port': '18443'})

    do_GET = do_POST = do_HEAD = do_PUT = do_DELETE = route


serve(KeycloakProxy, 18443, background=True, host='0.0.0.0')


def admin(sql):
    request = urllib.request.Request('http://localhost:4200/_sql',
        json.dumps({'stmt': sql}).encode(), {'Content-Type': 'application/json',
        'Authorization': 'Basic ' + base64.b64encode(b'crate:').decode()})
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)


for attempt in range(180):
    try:
        admin('SELECT 1')
        break
    except (urllib.error.URLError, TimeoutError):
        time.sleep(1)
else:
    raise RuntimeError('CrateDB did not start')

admin('CREATE TABLE doc.visible_rows (id INTEGER PRIMARY KEY, marker TEXT) CLUSTERED INTO 1 SHARDS WITH (number_of_replicas=0)')
admin("INSERT INTO doc.visible_rows VALUES (1, 'shared-visible-1'), (2, 'shared-visible-2')")
admin('REFRESH TABLE doc.visible_rows')
for user in ['alice', 'bob']:
    admin(f'''CREATE USER {user} WITH (jwt = {{"iss" = '{ISSUER}', "username" = '{user}', "aud" = 'cratedb-demo'}})''')
    admin(f'GRANT DQL ON TABLE doc.visible_rows TO {user}')

admin(f'''CREATE USER demo_check WITH (jwt = {{"iss" = '{ISSUER}', "username" = 'service-account-cratedb-probe', "aud" = 'cratedb-demo'}})''')
admin('GRANT DQL ON TABLE doc.visible_rows TO demo_check')
probe = urllib.request.Request('http://localhost:4200/_sql',
    json.dumps({'stmt': 'SELECT marker FROM doc.visible_rows ORDER BY id'}).encode(),
    {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + service_token(
        'cratedb-probe', 'demo-cratedb-probe-secret')})
try:
    with urllib.request.urlopen(probe, timeout=20) as response:
        json.load(response)
except urllib.error.HTTPError as error:
    detail = re.sub(r'eyJ[A-Za-z0-9._-]+', '[redacted token]', error.read().decode())
    raise RuntimeError('CrateDB JWT readiness check failed: ' + detail) from None


class CrateProxy(Proxy):
    def do_GET(self):
        if self.path == '/health':
            self.json({'ready': True})
        else:
            self.json({'error': 'not found'}, 404)

    def do_POST(self):
        if urllib.parse.urlsplit(self.path).path != '/_sql' or not self.headers.get('Authorization', '').startswith('Bearer '):
            self.json({'error': 'bearer access token required'}, 401)
            return
        self.forward(4200)


print('CrateDB JWT users and the Keycloak issuer/JWKS gateway are ready.')
serve(CrateProxy, 18444)
