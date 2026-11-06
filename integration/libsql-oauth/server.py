import base64
import datetime
import http.client
import json
import socket
import ssl
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ed25519, rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

out = Path('/out')
key = ed25519.Ed25519PrivateKey.generate()
public_path = Path('/jwt-public.pem')
public_path.write_bytes(key.public_key().public_bytes(
    serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=').decode()


def jwt(subject, permission='ro', namespace='default', lifetime=3600, signer=key, **extra):
    header = b64(json.dumps({'alg': 'EdDSA', 'typ': 'JWT'}).encode())
    claims = {'iss': 'https://fixture.invalid', 'sub': subject, 'id': namespace,
              'a': permission, 'iat': int(time.time()), 'exp': int(time.time()) + lifetime,
              'scope': 'sqlite.read'}
    claims.update(extra)
    data = (header + '.' + b64(json.dumps(claims).encode())).encode()
    return data.decode() + '.' + b64(signer.sign(data))


tokens = {'a': jwt('alice'), 'rotated': jwt('alice', rotation=1),
          'b': jwt('bob', permission='rw'), 'expired': jwt('alice', lifetime=-3600),
          'wrong_key': jwt('alice', signer=ed25519.Ed25519PrivateKey.generate()),
          'other_namespace': jwt('alice', namespace='other'),
          'audience': jwt('alice', aud='fixture-api')}
(out / 'tokens.json').write_text(json.dumps(tokens))
process = subprocess.Popen(['/usr/local/bin/sqld', '--db-path', '/tmp/fixture.sqld',
                            '--http-listen-addr', '127.0.0.1:8080',
                            '--auth-jwt-key-file', str(public_path), '--no-welcome', '--disable-metrics'])
for attempt in range(180):
    if process.poll() is not None:
        raise RuntimeError('libSQL exited before readiness')
    try:
        with socket.create_connection(('127.0.0.1', 8080), timeout=1):
            break
    except OSError:
        time.sleep(0.25)
else:
    raise RuntimeError('libSQL failed to listen')

seed = {'baton': None, 'requests': [
    {'type': 'execute', 'stmt': {'sql': 'CREATE TABLE orders(id INTEGER, country TEXT, amount REAL, payload BLOB)', 'want_rows': False}},
    {'type': 'execute', 'stmt': {'sql': "INSERT INTO orders VALUES (9223372036854775807, 'NL', 1.25, x'00ff')", 'want_rows': False}},
    {'type': 'execute', 'stmt': {'sql': 'CREATE TABLE events(id INTEGER PRIMARY KEY, value TEXT)', 'want_rows': False}},
    {'type': 'close'}]}
connection = http.client.HTTPConnection('127.0.0.1', 8080)
connection.request('POST', '/v2/pipeline', json.dumps(seed),
                   {'Authorization': 'Bearer ' + tokens['b'], 'Content-Type': 'application/json'})
response = connection.getresponse()
body = json.loads(response.read())
assert response.status == 200 and all(x['type'] == 'ok' for x in body['results']), body
connection.close()

tls_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'libSQL fixture CA')])
name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
now = datetime.datetime.now(datetime.timezone.utc)
ca = (x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name).public_key(ca_key.public_key())
      .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=1))
      .not_valid_after(now + datetime.timedelta(days=2))
      .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
      .add_extension(x509.KeyUsage(True, False, False, False, False, True, True, None, None), critical=True)
      .sign(ca_key, hashes.SHA256()))
cert = (x509.CertificateBuilder().subject_name(name).issuer_name(ca_name).public_key(tls_key.public_key())
        .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=2))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
        .sign(ca_key, hashes.SHA256()))
(out / 'fixture-ca.pem').write_bytes(ca.public_bytes(serialization.Encoding.PEM))
Path('/tls-cert.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM)
                                 + ca.public_bytes(serialization.Encoding.PEM))
Path('/tls-key.pem').write_bytes(tls_key.private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))


class Proxy(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_POST(self):
        payload = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if self.path == '/redirect/v2/pipeline':
            self.send_response(302)
            self.send_header('Location', 'https://untrusted.invalid/v2/pipeline')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        connection = http.client.HTTPConnection('127.0.0.1', 8080)
        connection.request('POST', '/v2/pipeline', payload, {
            'Authorization': self.headers.get('Authorization', ''), 'Content-Type': 'application/json'})
        response = connection.getresponse()
        body = response.read()
        connection.close()
        if self.path == '/drop/v2/pipeline':
            self.close_connection = True
            self.connection.shutdown(socket.SHUT_RDWR)
            return
        if self.path == '/delay/v2/pipeline':
            time.sleep(2)
        self.send_response(response.status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *args):
        pass


proxy = ThreadingHTTPServer(('0.0.0.0', 19498), Proxy)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/tls-cert.pem', '/tls-key.pem')
proxy.socket = context.wrap_socket(proxy.socket, server_side=True)
(out / 'ready').write_text('ready')
print('libSQL JWT and TLS fixture ready')
proxy.serve_forever()
