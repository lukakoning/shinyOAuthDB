"""Generate disposable TLS, JWT and native OpenSearch Security configuration."""
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
(out / 'security').mkdir(exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc)
ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'OpenSearch fixture CA')])
ca = (x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name)
      .public_key(ca_key.public_key()).serial_number(x509.random_serial_number())
      .not_valid_before(now - datetime.timedelta(days=1)).not_valid_after(now + datetime.timedelta(days=2))
      .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
      .sign(ca_key, hashes.SHA256()))
(out / 'ca.pem').write_bytes(ca.public_bytes(serialization.Encoding.PEM))

def certificate(stem, cn, names):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    builder = (x509.CertificateBuilder()
               .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)]))
               .issuer_name(ca_name).public_key(key.public_key()).serial_number(x509.random_serial_number())
               .not_valid_before(now - datetime.timedelta(days=1)).not_valid_after(now + datetime.timedelta(days=2))
               .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
               .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH,
                                                   x509.oid.ExtendedKeyUsageOID.CLIENT_AUTH]), critical=False))
    if names:
        builder = builder.add_extension(x509.SubjectAlternativeName([x509.DNSName(n) for n in names]), critical=False)
    cert = builder.sign(ca_key, hashes.SHA256())
    (out / (stem + '.pem')).write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    (out / (stem + '-key.pem')).write_bytes(key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))

certificate('node', 'opensearch-fixture', ['localhost', 'opensearch'])
certificate('admin', 'fixture-admin', [])
jwt_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
public_key = jwt_key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()

def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=').decode()

def token(subject, roles=('readers',), audience='shinyoauthdb-opensearch', issuer='https://fixture.invalid', lifetime=3600):
    header = b64(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode())
    claims = b64(json.dumps({'iss': issuer, 'aud': audience, 'sub': subject, 'roles': roles,
                            'scope': 'search.read', 'iat': int(time.time()), 'exp': int(time.time()) + lifetime}).encode())
    data = (header + '.' + claims).encode()
    return data.decode() + '.' + b64(jwt_key.sign(data, padding.PKCS1v15(), hashes.SHA256()))

(out / 'tokens.json').write_text(json.dumps({
    'alice': token('alice'), 'bob': token('bob'), 'writer': token('writer', ['writers']),
    'denied': token('outsider', []), 'audience': token('alice', audience='wrong-api'),
    'issuer': token('alice', issuer='https://wrong.invalid'), 'expired': token('alice', lifetime=-3600)}))

def security(name, kind, content):
    (out / 'security' / name).write_text(json.dumps({'_meta': {'type': kind, 'config_version': 2}, **content}))

security('config.yml', 'config', {'config': {'dynamic': {'authc': {'jwt_auth_domain': {
    'http_enabled': True, 'transport_enabled': False, 'order': 0,
    'http_authenticator': {'type': 'jwt', 'challenge': False, 'config': {
        'signing_key': public_key, 'jwt_header': 'Authorization', 'jwt_url_parameter': None,
        'subject_key': 'sub', 'roles_key': 'roles', 'required_audience': 'shinyoauthdb-opensearch',
        'required_issuer': 'https://fixture.invalid', 'jwt_clock_skew_tolerance_seconds': 0}},
    'authentication_backend': {'type': 'noop'}}}}}})
security('roles.yml', 'roles', {
    'orders_reader': {'cluster_permissions': ['cluster:monitor/main', 'cluster:admin/opensearch/sql*'],
        'index_permissions': [{'index_patterns': ['orders'],
            'allowed_actions': ['indices:data/read/*', 'indices:admin/mappings/get', 'indices:admin/get',
                                'indices:admin/aliases/get', 'indices:admin/resolve/index', 'indices:monitor/settings/get'],
            'dls': '{"term":{"owner":"${user.name}"}}', 'fls': ['owner', 'country', 'total', 'big_id']}]},
    'orders_writer': {'cluster_permissions': ['indices:data/write/bulk'], 'index_permissions': [
        {'index_patterns': ['orders'], 'allowed_actions': ['indices:*']}]}})
security('roles_mapping.yml', 'rolesmapping', {
    'orders_reader': {'backend_roles': ['readers']}, 'orders_writer': {'backend_roles': ['writers']}})
for filename, kind in [('internal_users.yml', 'internalusers'), ('action_groups.yml', 'actiongroups'),
                       ('tenants.yml', 'tenants'), ('nodes_dn.yml', 'nodesdn')]:
    security(filename, kind, {})
security('allowlist.yml', 'allowlist', {'config': {'enabled': False, 'requests': {}}})
config = {'cluster.name': 'shinyOAuthDB-opensearch', 'node.name': 'opensearch', 'network.host': '0.0.0.0',
          'discovery.type': 'single-node', 'node.store.allow_mmap': False,
          'plugins.security.ssl.transport.pemcert_filepath': 'fixture/node.pem',
          'plugins.security.ssl.transport.pemkey_filepath': 'fixture/node-key.pem',
          'plugins.security.ssl.transport.pemtrustedcas_filepath': 'fixture/ca.pem',
          'plugins.security.ssl.transport.enforce_hostname_verification': False,
          'plugins.security.ssl.http.enabled': True,
          'plugins.security.ssl.http.pemcert_filepath': 'fixture/node.pem',
          'plugins.security.ssl.http.pemkey_filepath': 'fixture/node-key.pem',
          'plugins.security.ssl.http.pemtrustedcas_filepath': 'fixture/ca.pem',
          'plugins.security.ssl.http.clientauth_mode': 'OPTIONAL',
          'plugins.security.authcz.admin_dn': ['CN=fixture-admin'],
          'plugins.security.nodes_dn': ['CN=opensearch-fixture'],
          'plugins.security.allow_default_init_securityindex': True,
          'plugins.security.cache.ttl_minutes': 0}
(out / 'opensearch.yml').write_text(json.dumps(config))
print('Generated OpenSearch fixture certificates, JWTs and roles.')
