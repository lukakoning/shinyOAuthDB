"""Create disposable certificates and tokens for Elasticsearch's native JWT realm."""
import base64
import datetime
import json
import time
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

out = Path('/out')
now = datetime.datetime.now(datetime.timezone.utc)
ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Elasticsearch fixture CA')])
ca = (x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name)
      .public_key(ca_key.public_key()).serial_number(x509.random_serial_number())
      .not_valid_before(now - datetime.timedelta(days=1))
      .not_valid_after(now + datetime.timedelta(days=2))
      .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
      .sign(ca_key, hashes.SHA256()))
(out / 'ca.pem').write_bytes(ca.public_bytes(serialization.Encoding.PEM))
node_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
node = (x509.CertificateBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'elasticsearch')]))
        .issuer_name(ca_name).public_key(node_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=2))
        .add_extension(x509.SubjectAlternativeName([
            x509.DNSName('localhost'), x509.DNSName('elasticsearch')]), critical=False)
        .add_extension(x509.ExtendedKeyUsage([
            x509.oid.ExtendedKeyUsageOID.SERVER_AUTH,
            x509.oid.ExtendedKeyUsageOID.CLIENT_AUTH]), critical=False)
        .sign(ca_key, hashes.SHA256()))
(out / 'node.pem').write_bytes(node.public_bytes(serialization.Encoding.PEM))
(out / 'node-key.pem').write_bytes(node_key.private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))

def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

jwt_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
numbers = jwt_key.public_key().public_numbers()
(out / 'jwks.json').write_text(json.dumps({'keys': [{
    'kty': 'RSA', 'kid': 'fixture', 'alg': 'RS256', 'use': 'sig',
    'n': b64(numbers.n.to_bytes((numbers.n.bit_length() + 7) // 8, 'big')),
    'e': b64(numbers.e.to_bytes((numbers.e.bit_length() + 7) // 8, 'big'))}]}))

def token(subject, groups=('readers',), issuer='https://fixture.invalid',
          audience='shinyoauthdb-elasticsearch', lifetime=3600):
    header = b64(json.dumps({'alg': 'RS256', 'typ': 'at+jwt', 'kid': 'fixture'}).encode())
    claims = b64(json.dumps({'iss': issuer, 'aud': audience, 'sub': subject,
                            'groups': groups, 'iat': int(time.time()),
                            'exp': int(time.time()) + lifetime}).encode())
    data = (header + '.' + claims).encode()
    return data.decode() + '.' + b64(jwt_key.sign(data, padding.PKCS1v15(), hashes.SHA256()))

(out / 'tokens.json').write_text(json.dumps({
    'alice': token('alice'), 'bob': token('bob'), 'writer': token('writer', ['writers']),
    'denied': token('outsider', []), 'audience': token('alice', audience='wrong-api'),
    'issuer': token('alice', issuer='https://wrong.invalid'),
    'subject': token('unlisted'), 'expired': token('alice', lifetime=-3600)}))

config = {
    'cluster.name': 'shinyOAuthDB-elasticsearch', 'node.name': 'elasticsearch',
    'network.host': '0.0.0.0', 'discovery.type': 'single-node', 'node.store.allow_mmap': False,
    'xpack.license.self_generated.type': 'trial', 'xpack.security.enabled': True,
    'xpack.security.http.ssl.enabled': True,
    'xpack.security.http.ssl.key': 'fixture/node-key.pem',
    'xpack.security.http.ssl.certificate': 'fixture/node.pem',
    'xpack.security.http.ssl.certificate_authorities': ['fixture/ca.pem'],
    'xpack.security.transport.ssl.enabled': True,
    'xpack.security.transport.ssl.verification_mode': 'certificate',
    'xpack.security.transport.ssl.key': 'fixture/node-key.pem',
    'xpack.security.transport.ssl.certificate': 'fixture/node.pem',
    'xpack.security.transport.ssl.certificate_authorities': ['fixture/ca.pem'],
    'xpack.security.authc.realms.jwt.visitors.order': 0,
    'xpack.security.authc.realms.jwt.visitors.token_type': 'access_token',
    'xpack.security.authc.realms.jwt.visitors.client_authentication.type': 'shared_secret',
    'xpack.security.authc.realms.jwt.visitors.allowed_issuer': 'https://fixture.invalid',
    'xpack.security.authc.realms.jwt.visitors.allowed_audiences': ['shinyoauthdb-elasticsearch'],
    'xpack.security.authc.realms.jwt.visitors.allowed_subjects': ['alice', 'bob', 'writer', 'outsider'],
    'xpack.security.authc.realms.jwt.visitors.allowed_signature_algorithms': ['RS256'],
    'xpack.security.authc.realms.jwt.visitors.pkc_jwkset_path': 'fixture/jwks.json',
    'xpack.security.authc.realms.jwt.visitors.claims.principal': 'sub',
    'xpack.security.authc.realms.jwt.visitors.claims.groups': 'groups',
    'xpack.security.authc.realms.native.native1.order': 1}
(out / 'elasticsearch.yml').write_text(json.dumps(config))
print('Generated Elasticsearch fixture certificates and JWTs.')
