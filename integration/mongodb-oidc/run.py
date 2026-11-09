"""Run real MongoDB Enterprise OIDC checks with disposable TLS and JWT keys."""

import argparse
import base64
import datetime
import json
import os
import pathlib
import subprocess
import sys
import time
import uuid

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def integer(value):
    return b64(value.to_bytes((value.bit_length() + 7) // 8, "big"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rscript", required=True)
    parser.add_argument("--root", required=True)
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve()
    name = "oauthdb-mongo-" + uuid.uuid4().hex[:10]
    output = root / ".validation" / "mongodb-oidc" / name
    output.mkdir(parents=True)
    now = datetime.datetime.now(datetime.timezone.utc)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "shinyOAuthDB MongoDB test CA")])
    ca = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
          .public_key(key.public_key()).serial_number(x509.random_serial_number())
          .not_valid_before(now - datetime.timedelta(minutes=5))
          .not_valid_after(now + datetime.timedelta(days=1))
          .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
          .sign(key, hashes.SHA256()))
    (output / "ca.pem").write_bytes(ca.public_bytes(serialization.Encoding.PEM))
    tls_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    certificate = (x509.CertificateBuilder()
                   .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "mongo")]))
                   .issuer_name(subject).public_key(tls_key.public_key())
                   .serial_number(x509.random_serial_number())
                   .not_valid_before(now - datetime.timedelta(minutes=5))
                   .not_valid_after(now + datetime.timedelta(days=1))
                   .add_extension(x509.SubjectAlternativeName([
                       x509.DNSName("mongo"), x509.DNSName("issuer"), x509.DNSName("localhost"),
                   ]), critical=False).sign(key, hashes.SHA256()))
    (output / "server.pem").write_bytes(
        tls_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                              serialization.NoEncryption()) + certificate.public_bytes(serialization.Encoding.PEM))
    jwt_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public = jwt_key.public_key().public_numbers()
    issuer = "https://issuer:8443"
    (output / "jwks.json").write_text(json.dumps({"keys": [{
        "kty": "RSA", "kid": "fixture", "use": "sig", "alg": "RS256",
        "n": integer(public.n), "e": integer(public.e),
    }]}))
    (output / "discovery.json").write_text(json.dumps({
        "issuer": issuer, "jwks_uri": issuer + "/jwks",
        "authorization_endpoint": issuer + "/authorize", "token_endpoint": issuer + "/token",
        "response_types_supported": ["code"], "subject_types_supported": ["public"],
        "id_token_signing_alg_values_supported": ["RS256"],
    }))

    def token(subject="alice", audience="shiny-db", lifetime=3600, signing_key=jwt_key, token_issuer=issuer):
        issued = int(time.time())
        head = b64(json.dumps({"alg": "RS256", "kid": "fixture"}).encode())
        body = b64(json.dumps({"iss": token_issuer, "sub": subject, "aud": audience,
                               "iat": issued - 4000 if lifetime < 0 else issued,
                               "exp": issued + lifetime}).encode())
        message = (head + "." + body).encode()
        return message.decode() + "." + b64(signing_key.sign(message, padding.PKCS1v15(), hashes.SHA256()))

    providers = json.dumps([{
        "issuer": issuer, "audience": "shiny-db", "authNamePrefix": "shiny",
        "clientId": "shiny-db", "useAuthorizationClaim": False,
    }])
    (output / "mongod.yml").write_text(
        "net:\n  bindIpAll: true\n  tls:\n    mode: requireTLS\n"
        "    certificateKeyFile: /fixture/server.pem\n    CAFile: /fixture/ca.pem\n"
        "    allowConnectionsWithoutCertificates: true\n"
        "security:\n  authorization: enabled\n"
        "setParameter:\n  authenticationMechanisms: MONGODB-OIDC,SCRAM-SHA-256\n"
        "  oidcIdentityProviders: '" + providers + "'\n"
    )
    (output / "seed.js").write_text('''
const admin = db.getSiblingDB("admin");
admin.createUser({user:"bootstrap",pwd:"fixture-bootstrap",roles:["root"]});
admin.auth("bootstrap", "fixture-bootstrap");
const reports = db.getSiblingDB("reporting");
for (const user of ["alice", "bob"]) {
  reports.createRole({role:user+"_reader",privileges:[
    {resource:{db:"reporting",collection:user+"_orders"},
     actions:user === "bob" ? ["find","insert","update","remove"] : ["find"]},
    {resource:{db:"reporting",collection:user+"_pages"},actions:["find"]}
  ],roles:[]});
  db.getSiblingDB("$external").createUser({user:"shiny/"+user,
    roles:[{role:user+"_reader",db:"reporting"}]});
  reports.getCollection(user+"_orders").insertMany([
    {country:"NL",total:NumberLong("9007199254740993"),owner:user},
    {country:"BE",total:NumberLong("2"),owner:user}
  ]);
  reports.getCollection(user+"_pages").insertMany(Array.from({length:250}, (_,i) => ({n:i})));
}
''')
    mongo = name + "-db"
    idp = name + "-idp"
    created = []
    network_created = False
    try:
        run("docker", "network", "create", name)
        network_created = True
        run("docker", "run", "-d", "--name", idp, "--network", name,
            "--network-alias", "issuer", "-v", str(output) + ":/fixture:ro",
            "-v", str(root / "integration/mongodb-oidc/issuer.py") + ":/issuer.py:ro",
            "python:3.12-slim", "python", "/issuer.py")
        created.append(idp)
        image = os.environ.get("OAUTHDB_MONGODB_TEST_IMAGE", "mongodb/mongodb-enterprise-server:8.0.16-ubuntu2204")
        run("docker", "run", "-d", "--name", mongo, "--network", name,
            "--network-alias", "mongo", "-p", "127.0.0.1::27017",
            "-v", str(output) + ":/fixture:ro", "--user", "0", "--entrypoint", "/bin/sh",
            image, "-c", "cp /fixture/ca.pem /usr/local/share/ca-certificates/fixture.crt && "
            "update-ca-certificates >/dev/null && exec mongod --config /fixture/mongod.yml")
        created.append(mongo)
        shell = ["docker", "exec", mongo, "mongosh", "--quiet", "--host", "localhost",
                 "--tls", "--tlsCAFile", "/fixture/ca.pem"]
        deadline = time.monotonic() + 90
        while True:
            try:
                run(*shell, "--eval", "db.runCommand({ping:1})")
                break
            except subprocess.CalledProcessError:
                if time.monotonic() > deadline:
                    raise RuntimeError("MongoDB fixture did not become ready") from None
                time.sleep(1)
        run(*shell, "/fixture/seed.js")
        port = run("docker", "port", mongo, "27017/tcp").rsplit(":", 1)[1]
        config = {"url": "mongodb://localhost:" + port, "db": "reporting", "issuer": issuer,
                  "ca": str(output / "ca.pem"), "alice": token(), "renewed": token(lifetime=7200),
                  "bob": token(subject="bob"), "expired": token(lifetime=-100),
                  "audience": token(audience="wrong"), "issuer_token": token(token_issuer="https://wrong.invalid"),
                  "signature": token(signing_key=rsa.generate_private_key(public_exponent=65537, key_size=2048))}
        (output / "config.json").write_text(json.dumps(config))
        environment = dict(os.environ, OAUTHDB_MONGODB_FIXTURE=str(output / "config.json"),
                           OAUTHDB_MONGODB_ROOT=str(root), RETICULATE_PYTHON=sys.executable)
        check = subprocess.run([args.rscript, "--vanilla", str(root / "integration/mongodb-oidc/test-native.R")],
                               env=environment, capture_output=True, text=True)
        (output / "native.log").write_text(check.stdout + check.stderr)
        print(check.stdout, end="")
        if check.returncode:
            print(check.stderr, file=sys.stderr)
            raise RuntimeError("MongoDB native R checks failed")
        print("MongoDB native OIDC fixture passed; logs:", output)
    finally:
        for container in created:
            logs = subprocess.run(["docker", "logs", container], capture_output=True, text=True)
            (output / (container + ".log")).write_text(logs.stdout + logs.stderr)
            subprocess.run(["docker", "rm", "-f", container], capture_output=True)
        if network_created:
            subprocess.run(["docker", "network", "rm", name], capture_output=True)


if __name__ == "__main__":
    main()
