"""Generate disposable TLS certificates and signed database tokens."""

import base64
import datetime
import ipaddress
import json
import pathlib
import secrets
import sys
import time

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def main():
    destination = pathlib.Path(sys.argv[1])
    destination.mkdir(parents=True, exist_ok=True)
    now = datetime.datetime.now(datetime.timezone.utc)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "SingleStore fixture CA")])
    ca = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=5))
        .not_valid_after(now + datetime.timedelta(days=1))
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )
    server_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    server_cert = (
        x509.CertificateBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "fixture.invalid")]))
        .issuer_name(name)
        .public_key(server_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=5))
        .not_valid_after(now + datetime.timedelta(days=1))
        .add_extension(
            x509.SubjectAlternativeName([
                x509.IPAddress(ipaddress.ip_address("127.0.0.1")),
            ]),
            critical=False,
        )
        .sign(key, hashes.SHA256())
    )
    for filename, certificate in [("ca.pem", ca), ("server.pem", server_cert)]:
        (destination / filename).write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    wrong_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    wrong_ca = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(wrong_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=5))
        .not_valid_after(now + datetime.timedelta(days=1))
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .sign(wrong_key, hashes.SHA256())
    )
    (destination / "wrong-ca.pem").write_bytes(wrong_ca.public_bytes(serialization.Encoding.PEM))
    (destination / "server.key").write_bytes(server_key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption(),
    ))
    jwt_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    numbers = jwt_key.public_key().public_numbers()
    (destination / "jwks.json").write_text(json.dumps({"keys": [{
        "kty": "RSA", "alg": "RS256", "kid": "fixture",
        "n": b64(numbers.n.to_bytes((numbers.n.bit_length() + 7) // 8, "big")),
        "e": b64(numbers.e.to_bytes((numbers.e.bit_length() + 7) // 8, "big")),
        "aud": "shinyOAuthDB-fixture",
    }]}), encoding="utf-8")

    def token(user, *, expired=False, audience="shinyOAuthDB-fixture", signing_key=jwt_key):
        issued = int(time.time()) - (7200 if expired else 0)
        header = b64(json.dumps({"alg": "RS256", "kid": "fixture"}).encode())
        payload = b64(json.dumps({
            "iss": "https://fixture.example.org", "sub": user, "aud": audience,
            "iat": issued, "exp": issued + 3600, "jti": secrets.token_hex(12),
        }).encode())
        message = f"{header}.{payload}".encode("ascii")
        signature = signing_key.sign(message, padding.PKCS1v15(), hashes.SHA256())
        return f"{header}.{payload}.{b64(signature)}"

    tokens = {
        "alice": token("alice"), "bob": token("bob"), "renewed": token("alice"),
        "expired": token("alice", expired=True),
        "wrong_audience": token("alice", audience="another-database"),
        "wrong_signature": token("alice", signing_key=rsa.generate_private_key(
            public_exponent=65537, key_size=2048,
        )),
    }
    (destination / "tokens.json").write_text(json.dumps(tokens), encoding="utf-8")


if __name__ == "__main__":
    main()
