import base64
import datetime
import http.client
import json
import ssl
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

out = Path('/out')
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
issuer = 'http://fixture:8080/jwks'

def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=').decode()

def number(value):
    return b64(value.to_bytes((value.bit_length() + 7) // 8, 'big'))

public = key.public_key().public_numbers()
jwks = {'keys': [{'kty': 'RSA', 'kid': 'fixture', 'use': 'sig', 'alg': 'RS256', 'n': number(public.n), 'e': number(public.e)}]}

class Jwks(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps(jwks).encode())
    def log_message(self, *args):
        pass

provider = ThreadingHTTPServer(('0.0.0.0', 8080), Jwks)
threading.Thread(target=provider.serve_forever, daemon=True).start()

def token(user, audience='shinyOAuthDB-cratedb', lifetime=3600):
    header = b64(json.dumps({'alg': 'RS256', 'kid': 'fixture'}).encode())
    claims = b64(json.dumps({'iss': issuer, 'aud': audience, 'username': user, 'sub': user,
                           'iat': int(time.time()) - 10, 'exp': int(time.time()) + lifetime}).encode())
    data = (header + '.' + claims).encode()
    return data.decode() + '.' + b64(key.sign(data, padding.PKCS1v15(), hashes.SHA256()))

(out / 'tokens.json').write_text(json.dumps({'a': token('alice'), 'b': token('bob'),
    'rotated': token('alice', lifetime=3500), 'audience': token('alice', audience='wrong-api'),
    'expired': token('alice', lifetime=-3600)}))

def admin(sql):
    req = urllib.request.Request('http://engine:4200/_sql', json.dumps({'stmt': sql}).encode(),
        {'Content-Type': 'application/json', 'Authorization': 'Basic ' + b64(b'crate:')})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(error.read().decode()) from None

for attempt in range(180):
    try:
        admin('SELECT 1')
        break
    except Exception:
        time.sleep(1)
else:
    raise RuntimeError('CrateDB did not start')

admin('CREATE TABLE doc.orders (id BIGINT PRIMARY KEY, amount NUMERIC(38,9), flag BOOLEAN, tags ARRAY(BIGINT), counter INTEGER) CLUSTERED INTO 1 SHARDS WITH (number_of_replicas=0)')
admin("INSERT INTO doc.orders (id, amount, flag, tags) VALUES ('9007199254740993'::bigint, '123456789012345678.123456789'::numeric, true, ['9007199254740993'::bigint])")
admin('CREATE TABLE doc.alice_only (id INTEGER) CLUSTERED INTO 1 SHARDS WITH (number_of_replicas=0)')
admin('REFRESH TABLE doc.orders')
for user in ['alice', 'bob']:
    admin(f'''CREATE USER {user} WITH (jwt = {{"iss" = '{issuer}', "username" = '{user}', "aud" = 'shinyOAuthDB-cratedb'}})''')
    admin(f'GRANT DQL ON TABLE doc.orders TO {user}')
admin('GRANT DML ON TABLE doc.orders TO alice')
admin('GRANT DQL ON TABLE doc.alice_only TO alice')

tls_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
now = datetime.datetime.now(datetime.timezone.utc)
ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'CrateDB fixture CA')])
ca_cert = (x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name).public_key(ca_key.public_key())
        .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=2))
        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
        .add_extension(x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()), critical=False)
        .sign(ca_key, hashes.SHA256()))
cert = (x509.CertificateBuilder().subject_name(name).issuer_name(ca_name).public_key(tls_key.public_key())
        .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=2))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
        .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()), critical=False)
        .sign(ca_key, hashes.SHA256()))
(out / 'fixture-ca.pem').write_bytes(ca_cert.public_bytes(serialization.Encoding.PEM))
Path('/server.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
Path('/key.pem').write_bytes(tls_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))

class Proxy(BaseHTTPRequestHandler):
    def do_POST(self):
        authorization = self.headers.get('Authorization', '')
        if not authorization.startswith('Bearer '):
            self.send_error(401)
            return
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        conn = http.client.HTTPConnection('engine', 4200)
        headers = {'Content-Type': 'application/json', 'Authorization': authorization}
        if self.headers.get('Default-Schema'):
            headers['Default-Schema'] = self.headers['Default-Schema']
        conn.request('POST', self.path, body, headers)
        response = conn.getresponse()
        payload = response.read()
        sql = json.loads(body)['stmt']
        if 'fixture-drop' in sql:
            conn.close()
            self.close_connection = True
            return
        if 'fixture-delay' in sql:
            time.sleep(2)
        self.send_response(response.status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
        except (BrokenPipeError, ssl.SSLError):
            pass
        conn.close()
    def log_message(self, *args):
        pass

proxy = ThreadingHTTPServer(('0.0.0.0', 8443), Proxy)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/server.pem', '/key.pem')
proxy.socket = context.wrap_socket(proxy.socket, server_side=True)
(out / 'ready').write_text('ready')
print('CrateDB JWT and TLS fixture ready')
proxy.serve_forever()
