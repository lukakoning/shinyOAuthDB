"""Disposable Neo4j certificates, JWT issuer and database seed data."""
import base64
import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import ssl
import sys
import time
import urllib.error
import urllib.request

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

OUT = Path('/out')
ISSUER = 'https://issuer:8443'


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=').decode()


def prepare():
    now = datetime.datetime.now(datetime.timezone.utc)
    ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Neo4j fixture CA')])
    ca = (x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name)
          .public_key(ca_key.public_key()).serial_number(x509.random_serial_number())
          .not_valid_before(now - datetime.timedelta(days=1))
          .not_valid_after(now + datetime.timedelta(days=2))
          .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
          .sign(ca_key, hashes.SHA256()))
    (OUT / 'ca.pem').write_bytes(ca.public_bytes(serialization.Encoding.PEM))
    node_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    node = (x509.CertificateBuilder().subject_name(x509.Name([
                x509.NameAttribute(NameOID.COMMON_NAME, 'neo4j')]))
            .issuer_name(ca_name).public_key(node_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=2))
            .add_extension(x509.SubjectAlternativeName([
                x509.DNSName(name) for name in ['localhost', 'neo4j', 'issuer']]), critical=False)
            .add_extension(x509.ExtendedKeyUsage([
                x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
            .sign(ca_key, hashes.SHA256()))
    (OUT / 'node.pem').write_bytes(node.public_bytes(serialization.Encoding.PEM))
    (OUT / 'node-key.pem').write_bytes(node_key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public = key.public_key().public_numbers()
    (OUT / 'jwks.json').write_text(json.dumps({'keys': [{
        'kty': 'RSA', 'kid': 'fixture', 'alg': 'RS256', 'use': 'sig',
        'n': b64(public.n.to_bytes((public.n.bit_length() + 7) // 8, 'big')),
        'e': b64(public.e.to_bytes((public.e.bit_length() + 7) // 8, 'big'))}]}))

    def token(subject='alice', groups=None, issuer=ISSUER,
              audience='shinyoauthdb-neo4j', lifetime=3600, signer=key):
        header = b64(json.dumps({'alg': 'RS256', 'typ': 'JWT', 'kid': 'fixture'}).encode())
        claims = b64(json.dumps({'iss': issuer, 'aud': audience, 'sub': subject,
                                'groups': groups if groups is not None else [subject],
                                'iat': int(time.time()) - 5, 'exp': int(time.time()) + lifetime}).encode())
        data = (header + '.' + claims).encode()
        return data.decode() + '.' + b64(signer.sign(data, padding.PKCS1v15(), hashes.SHA256()))

    tokens = {'alice': token(), 'bob': token('bob'), 'renewed': token(lifetime=7200),
              'writer': token('writer', ['writers']), 'audience': token(audience='wrong-api'),
              'issuer': token(issuer='https://wrong.invalid'), 'expired': token(lifetime=-3600),
              'signature': token(signer=rsa.generate_private_key(public_exponent=65537, key_size=2048))}
    (OUT / 'tokens.json').write_text(json.dumps(tokens))
    config = {
        'server.default_listen_address': '0.0.0.0', 'server.http.enabled': 'false',
        'server.https.enabled': 'true', 'server.https.listen_address': ':7473',
        'server.bolt.enabled': 'true', 'server.bolt.listen_address': '127.0.0.1:7687',
        'server.memory.heap.initial_size': '256m',
        'server.memory.heap.max_size': '512m', 'server.memory.pagecache.size': '128m',
        'dbms.ssl.policy.https.enabled': 'true', 'dbms.ssl.policy.https.base_directory': '/fixture',
        'dbms.ssl.policy.https.private_key': 'node-key.pem',
        'dbms.ssl.policy.https.public_certificate': 'node.pem',
        'dbms.ssl.policy.https.client_auth': 'NONE',
        'dbms.security.authentication_providers': 'native,oidc-visitors',
        'dbms.security.authorization_providers': 'native,oidc-visitors',
        'dbms.security.oidc.visitors.issuer': ISSUER,
        'dbms.security.oidc.visitors.jwks_uri': ISSUER + '/jwks.json',
        'dbms.security.oidc.visitors.auth_endpoint': ISSUER + '/authorize',
        'dbms.security.oidc.visitors.token_endpoint': ISSUER + '/token',
        'dbms.security.oidc.visitors.audience': 'shinyoauthdb-neo4j',
        'dbms.security.oidc.visitors.claims.username': 'sub',
        'dbms.security.oidc.visitors.claims.groups': 'groups',
        'dbms.security.oidc.visitors.authorization.group_to_role_mapping':
            'alice=alice_reader;bob=bob_reader;writers=publisher',
    }
    (OUT / 'neo4j.conf').write_text(''.join(f'{key}={value}\n' for key, value in config.items()))
    print('Generated Neo4j fixture certificates and user JWTs.')


def serve():
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != '/jwks.json':
                self.send_error(404)
                return
            data = (OUT / 'jwks.json').read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = HTTPServer(('0.0.0.0', 8443), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(OUT / 'node.pem', OUT / 'node-key.pem')
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


def seed():
    context = ssl.create_default_context(cafile=str(OUT / 'ca.pem'))
    authorization = 'Basic ' + base64.b64encode(b'neo4j:fixture-admin-password').decode()

    def query(statement, database='neo4j'):
        req = urllib.request.Request(f'https://neo4j:7473/db/{database}/query/v2',
                                     data=json.dumps({'statement': statement}).encode(),
                                     headers={'Authorization': authorization,
                                              'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, context=context, timeout=15) as response:
            result = json.load(response)
        if result.get('errors'):
            raise RuntimeError(result['errors'])
        return result

    for attempt in range(90):
        try:
            query('RETURN 1')
            break
        except (OSError, urllib.error.URLError) as error:
            if attempt % 10 == 0:
                print(f'Waiting for Neo4j: {type(error).__name__} '
                      f'{getattr(error, "code", "not ready")}', flush=True)
            time.sleep(2)
    else:
        raise RuntimeError('Neo4j did not become ready')
    for role, label in [('alice_reader', 'AliceData'), ('bob_reader', 'BobData')]:
        query(f'CREATE ROLE {role} IF NOT EXISTS', 'system')
        query(f'GRANT ACCESS ON DATABASE neo4j TO {role}', 'system')
        query(f'GRANT MATCH {{*}} ON GRAPH neo4j NODES {label} TO {role}', 'system')
    query("CREATE (a:AliceData {name:'Alice', id:9007199254740993}), "
          "(b:BobData {name:'Bob'}), (a)-[:KNOWS]->(b)")
    print('Seeded Neo4j roles and graph data.')


{'prepare': prepare, 'serve': serve, 'seed': seed}[sys.argv[1]]()
