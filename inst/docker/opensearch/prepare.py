"""Prepare native OpenSearch Security for Keycloak-issued access tokens."""
import base64
import datetime
import json
from pathlib import Path
import sys
sys.path.insert(0, '/demo/python')
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from support import ISSUER, keycloak

out = Path('/state')
(out / 'security').mkdir(exist_ok=True)
key = next(k for k in keycloak('/protocol/openid-connect/certs')['keys']
           if k.get('alg') == 'RS256' and k.get('use') == 'sig')


def number(value):
    return int.from_bytes(base64.urlsafe_b64decode(value + '=='), 'big')


public_key = rsa.RSAPublicNumbers(number(key['e']), number(key['n'])).public_key()
public_pem = public_key.public_bytes(serialization.Encoding.PEM,
                                    serialization.PublicFormat.SubjectPublicKeyInfo).decode()
ca = x509.load_pem_x509_certificate(Path('/fixtures/tls/ca-cert.pem').read_bytes())
ca_key = serialization.load_pem_private_key(Path('/fixtures/tls/ca-key.pem').read_bytes(), password=None)
admin_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
now = datetime.datetime.now(datetime.timezone.utc)
admin = (x509.CertificateBuilder()
    .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'demo-admin')]))
    .issuer_name(ca.subject).public_key(admin_key.public_key()).serial_number(x509.random_serial_number())
    .not_valid_before(now - datetime.timedelta(days=1)).not_valid_after(now + datetime.timedelta(days=2))
    .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
    .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.CLIENT_AUTH]), critical=False)
    .sign(ca_key, hashes.SHA256()))
(out / 'admin.pem').write_bytes(admin.public_bytes(serialization.Encoding.PEM))
(out / 'admin-key.pem').write_bytes(admin_key.private_bytes(serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
(out / 'admin-key.pem').chmod(0o600)
node_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
node = (x509.CertificateBuilder()
    .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'opensearch-demo')]))
    .issuer_name(ca.subject).public_key(node_key.public_key()).serial_number(x509.random_serial_number())
    .not_valid_before(now - datetime.timedelta(days=1)).not_valid_after(now + datetime.timedelta(days=2))
    .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]), critical=False)
    .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
    .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.CLIENT_AUTH,
        x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]), critical=False).sign(ca_key, hashes.SHA256()))
(out / 'node.pem').write_bytes(node.public_bytes(serialization.Encoding.PEM))
(out / 'node-key.pem').write_bytes(node_key.private_bytes(serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))


def security(name, kind, content):
    (out / 'security' / name).write_text(json.dumps({'_meta': {'type': kind, 'config_version': 2}, **content}))


security('config.yml', 'config', {'config': {'dynamic': {'authc': {'jwt_auth_domain': {
    'http_enabled': True, 'transport_enabled': False, 'order': 0,
    'http_authenticator': {'type': 'jwt', 'challenge': False, 'config': {
        'signing_key': public_pem, 'jwt_header': 'Authorization', 'jwt_url_parameter': None,
        'subject_key': 'preferred_username', 'required_audience': 'opensearch-demo',
        'required_issuer': ISSUER, 'jwt_clock_skew_tolerance_seconds': 0}},
    'authentication_backend': {'type': 'noop'}}}}}})
security('roles.yml', 'roles', {'orders_reader': {
    'cluster_permissions': ['cluster:monitor/main'], 'index_permissions': [{
        'index_patterns': ['orders'], 'allowed_actions': ['indices:data/read/*'],
        'dls': '{"term":{"owner":"${user.name}"}}', 'fls': ['id', 'marker', 'owner']}]}})
security('roles_mapping.yml', 'rolesmapping', {'orders_reader': {'users': ['alice', 'bob']}})
for filename, kind in [('internal_users.yml', 'internalusers'), ('action_groups.yml', 'actiongroups'),
                       ('tenants.yml', 'tenants'), ('nodes_dn.yml', 'nodesdn')]:
    security(filename, kind, {})
security('allowlist.yml', 'allowlist', {'config': {'enabled': False, 'requests': {}}})
config = {'cluster.name': 'shinyOAuthDB-demo', 'node.name': 'opensearch', 'network.host': '127.0.0.1',
    'discovery.type': 'single-node', 'node.store.allow_mmap': False,
    'plugins.security.ssl.transport.pemcert_filepath': 'node.pem',
    'plugins.security.ssl.transport.pemkey_filepath': 'node-key.pem',
    'plugins.security.ssl.transport.pemtrustedcas_filepath': 'demo/ca-cert.pem',
    'plugins.security.ssl.transport.enforce_hostname_verification': False,
    'plugins.security.ssl.http.enabled': True,
    'plugins.security.ssl.http.pemcert_filepath': 'node.pem',
    'plugins.security.ssl.http.pemkey_filepath': 'node-key.pem',
    'plugins.security.ssl.http.pemtrustedcas_filepath': 'demo/ca-cert.pem',
    'plugins.security.ssl.http.clientauth_mode': 'OPTIONAL',
    'plugins.security.authcz.admin_dn': ['CN=demo-admin'],
    'plugins.security.nodes_dn': ['CN=opensearch-demo'],
    'plugins.security.allow_default_init_securityindex': True,
    'plugins.security.cache.ttl_minutes': 0}
(out / 'opensearch.yml').write_text(json.dumps(config))
print('Prepared OpenSearch TLS and Keycloak signing-key configuration.')
