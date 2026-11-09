"""Emulate successful AWS protocol responses, without validating real identity."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs
import base64
import json
import os
import ssl
import subprocess
import tempfile
import threading
import time


def jwt(claims):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    return encode({"alg": "RS256"}) + "." + encode(claims) + ".c2lnbmF0dXJl"


def claims(token):
    payload = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))


class AWSHandler(BaseHTTPRequestHandler):
    credentials = {}
    queries = {}
    exchanges = []
    workgroups = []

    def handle(self):
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass

    def reply(self, body, content_type="application/x-amz-json-1.1"):
        data = json.dumps(body).encode() if isinstance(body, dict) else body.encode()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def role_credentials(self, action, grant, prefix):
        access_key = prefix + str(len(self.credentials))
        self.credentials[access_key] = grant
        self.reply(
            f'<{action}Response xmlns="https://sts.amazonaws.com/doc/2011-06-15/">'
            f"<{action}Result><Credentials><AccessKeyId>{access_key}</AccessKeyId>"
            f"<SecretAccessKey>fixture-secret</SecretAccessKey>"
            f"<SessionToken>fixture-session-{grant}</SessionToken>"
            f"<Expiration>2030-01-01T00:00:00Z</Expiration></Credentials>"
            f"<AssumedRoleUser><AssumedRoleId>fixture:{grant}</AssumedRoleId>"
            f"<Arn>arn:aws:sts::123456789012:assumed-role/Fixture/{grant}</Arn>"
            f"</AssumedRoleUser></{action}Result>"
            f"<ResponseMetadata><RequestId>fixture</RequestId></ResponseMetadata>"
            f"</{action}Response>",
            "text/xml",
        )

    def do_POST(self):
        data = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if "json" in self.headers.get("Content-Type", ""):
            body = json.loads(data)
        else:
            body = {name: value[0] for name, value in parse_qs(data.decode()).items()}
        authorization = self.headers.get("Authorization", "")
        access_key = authorization.split("Credential=")[-1].split("/")[0]
        grant = self.credentials.get(access_key)
        action = body.get("Action", self.headers.get("X-Amz-Target", self.path))
        if action == "AssumeRoleWithWebIdentity":
            assert not authorization
            assert body["RoleArn"] == "arn:aws:iam::123456789012:role/AthenaApplication"
            grant = claims(body["WebIdentityToken"])["jti"]
            self.exchanges.append((grant, body["RoleSessionName"]))
            self.role_credentials(action, grant, "APP")
            return
        assert grant is not None, "The client must use the synthetic exchanged credentials"
        if self.path.startswith("/token"):
            assert claims(body["assertion"])["jti"] == grant
            self.reply({
                "accessToken": "access-" + grant,
                "idToken": jwt({"sts:identity_context": grant, "exp": int(time.time()) + 3600}),
                "expiresIn": 3600,
                "tokenType": "Bearer",
            }, "application/json")
        elif action == "AssumeRole":
            assert body["ProvidedContexts.member.1.ContextAssertion"] == grant
            assert body["RoleArn"] == "arn:aws:iam::123456789012:role/AthenaAccess"
            self.role_credentials(action, grant, "ACCESS")
        elif action.endswith("GetWorkGroup"):
            self.workgroups.append(grant)
            self.reply({"WorkGroup": {
                "Name": "reporting", "State": "ENABLED",
                "Configuration": {
                    "EngineVersion": {
                        "SelectedEngineVersion": "Athena engine version 3",
                        "EffectiveEngineVersion": "Athena engine version 3",
                    },
                    "ResultConfiguration": {"OutputLocation": "s3://query-results/reporting/"},
                },
            }})
        elif action.endswith("StartQueryExecution"):
            query_id = "fixture-query-" + str(len(self.queries))
            self.queries[query_id] = grant
            self.reply({"QueryExecutionId": query_id})
        elif action.endswith("GetQueryExecution"):
            assert self.queries[body["QueryExecutionId"]] == grant
            self.reply({"QueryExecution": {
                "QueryExecutionId": body["QueryExecutionId"],
                "Query": "SELECT fixture_user", "StatementType": "DML",
                "SubstatementType": "SELECT", "Status": {"State": "SUCCEEDED"},
                "ResultConfiguration": {"OutputLocation": "s3://query-results/reporting/result.csv"},
            }})
        elif action.endswith("GetQueryResults"):
            assert self.queries[body["QueryExecutionId"]] == grant
            self.reply({"ResultSet": {
                "ResultSetMetadata": {"ColumnInfo": [{
                    "Name": "who", "Type": "varchar", "Precision": 255,
                    "Scale": 0, "Nullable": "UNKNOWN", "CaseSensitive": True,
                }]},
                "Rows": [{"Data": [{"VarCharValue": value}]} for value in ("who", grant)],
            }})
        else:
            self.send_error(400, "Unexpected API operation")

    def log_message(self, *_args):
        pass


def main():
    hosts = ("oidc.eu-west-1.amazonaws.com", "oidc.us-east-1.amazonaws.com")
    # This runs only inside the disposable, network-isolated fixture container.
    with Path("/etc/hosts").open("a") as handle:
        handle.write("\n127.0.0.1 " + " ".join(hosts) + "\n")
    with tempfile.TemporaryDirectory(prefix="athena-success-") as tmp:
        directory = Path(tmp)
        key, cert = directory / "key.pem", directory / "cert.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(key), "-out", str(cert), "-days", "1", "-subj", "/CN=localhost",
            "-addext", "subjectAltName=" + ",".join("DNS:" + host for host in ("localhost", *hosts)),
        ], check=True, capture_output=True)
        server = ThreadingHTTPServer(("127.0.0.1", 443), AWSHandler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        grants = ["alice-1", "bob-1", "alice-2"]
        for grant in grants:
            (directory / (grant + ".token")).write_text(jwt({
                "iss": "https://fixture.example", "aud": "athena-fixture",
                "sub": grant.split("-")[0], "jti": grant, "exp": int(time.time()) + 3600,
            }))
        environment = dict(
            os.environ, ATHENA_PROBE_CERT=str(cert), ATHENA_PROBE_DIR=tmp,
            AWS_ACCESS_KEY_ID="unrelated-host-key", AWS_SECRET_ACCESS_KEY="unrelated-host-secret",
            AWS_SESSION_TOKEN="unrelated-host-session", AWS_EC2_METADATA_DISABLED="true",
            NO_PROXY=",".join(("localhost", "127.0.0.1", *hosts)),
        )
        try:
            subprocess.run(["Rscript", "--vanilla", "/probe/test-success.R"],
                           env=environment, check=True, timeout=90)
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=5)
        assert [grant for grant, _ in AWSHandler.exchanges] == grants
        assert len({name for _, name in AWSHandler.exchanges}) == 3
        assert AWSHandler.workgroups == grants
        assert len(AWSHandler.queries) == 6
        assert not (Path.home() / ".athena-odbc").exists()
        print("Synthetic exchanges, renewed-token isolation and interleaved SQL queries passed.")


if __name__ == "__main__":
    main()
