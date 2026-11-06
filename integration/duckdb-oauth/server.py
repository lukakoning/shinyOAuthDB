import base64
import datetime
import http.client
import json
import ssl
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import duckdb
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

out = Path('/out')
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
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
provider = ThreadingHTTPServer(('127.0.0.1', 19497), Jwks)
threading.Thread(target=provider.serve_forever, daemon=True).start()
def jwt(subject, scope='quack:read', audience='shinyOAuthDB-fixture'):
    header = b64(json.dumps({'alg': 'RS256', 'kid': 'fixture'}).encode())
    claims = b64(json.dumps({'iss': 'https://fixture.invalid', 'aud': audience, 'sub': subject,
                           'iat': int(time.time()), 'exp': int(time.time()) + 3600, 'scope': scope}).encode())
    data = (header + '.' + claims).encode()
    return data.decode() + '.' + b64(key.sign(data, padding.PKCS1v15(), hashes.SHA256()))
tokens = {'a': jwt('alice'), 'b': jwt('bob'), 'denied': jwt('alice', scope='other'),
          'audience': jwt('alice', audience='wrong-api')}
(out / 'tokens.json').write_text(json.dumps(tokens))
con = duckdb.connect()
for ext in ['quack', 'httpfs']:
    con.execute('INSTALL ' + ext)
    con.execute('LOAD ' + ext)
con.execute('INSTALL quack_oauth FROM community')
con.execute('LOAD quack_oauth')
con.execute('SET quack_oauth_telemetry_enabled = false')
con.execute("CREATE SECRET rs (TYPE quack_oauth_server, issuer 'https://fixture.invalid', audience 'shinyOAuthDB-fixture', jwks_uri 'http://127.0.0.1:19497/jwks')")
con.execute("SET quack_oauth_server_secret_name = 'rs'")
con.execute('SET quack_oauth_trust_plaintext = true')
con.execute("SET quack_authentication_function = 'quack_oauth_check_token'")
con.execute("SET quack_authorization_function = 'quack_oauth_check_authorization'")
con.execute('CREATE TABLE orders AS SELECT 42 AS id')
print(con.execute("CALL quack_serve('quack:0.0.0.0:19495', allow_other_hostname = true, disable_ssl = true, token='unused-fixture')").fetchall())

tls_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
now = datetime.datetime.now(datetime.timezone.utc)
cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(tls_key.public_key())
        .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=2))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]), critical=False)
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .sign(tls_key, hashes.SHA256()))
(out / 'fixture-ca.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
Path('/key.pem').write_bytes(tls_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
class Proxy(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        conn = http.client.HTTPConnection('127.0.0.1', 19495)
        conn.request('POST', self.path, body, {'Content-Type': self.headers.get('Content-Type', 'application/duckdb')})
        response = conn.getresponse()
        payload = response.read()
        self.send_response(response.status)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
        conn.close()
    def log_message(self, *args):
        pass
proxy = ThreadingHTTPServer(('0.0.0.0', 19496), Proxy)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(str(out / 'fixture-ca.pem'), '/key.pem')
proxy.socket = context.wrap_socket(proxy.socket, server_side=True)
threading.Thread(target=proxy.serve_forever, daemon=True).start()
(out / 'ready').write_text('ready')
print('OAuth and TLS fixture ready')
while True:
    time.sleep(1)
