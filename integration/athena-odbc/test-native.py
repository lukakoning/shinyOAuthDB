"""Run the native R/ODBC constructor against a local, rejecting STS service."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs
import os
import ssl
import subprocess
import sys
import tempfile
import threading


records = []


class STSHandler(BaseHTTPRequestHandler):
    def handle(self):
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            # Native TLS probes may close before sending an HTTP request.
            pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        records.append((parse_qs(body.decode()), dict(self.headers)))
        response = (
            b'<ErrorResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">'
            b"<Error><Type>Sender</Type><Code>InvalidIdentityToken</Code>"
            b"<Message>Fixture rejects token</Message></Error>"
            b"<RequestId>athena-fixture</RequestId></ErrorResponse>"
        )
        self.send_response(400)
        self.send_header("Content-Type", "text/xml")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, *_args):
        pass


def main():
    with tempfile.TemporaryDirectory(prefix="athena-native-") as tmp:
        directory = Path(tmp)
        key, cert = directory / "key.pem", directory / "cert.pem"
        subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-keyout", str(key), "-out", str(cert), "-days", "1",
             "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost"],
            check=True, capture_output=True,
        )
        server = ThreadingHTTPServer(("127.0.0.1", 0), STSHandler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        environment = dict(
            os.environ,
            ATHENA_PROBE_CERT=str(cert),
            ATHENA_PROBE_PORT=str(server.server_port),
            AWS_ACCESS_KEY_ID="unrelated-host-key",
            AWS_SECRET_ACCESS_KEY="unrelated-host-secret",
            AWS_SESSION_TOKEN="unrelated-host-session",
            AWS_EC2_METADATA_DISABLED="true",
            NO_PROXY="localhost,127.0.0.1",
        )
        try:
            subprocess.run(
                ["Rscript", "--vanilla", "/probe/test-native.R"],
                env=environment, check=True, timeout=90,
            )
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=5)

        # Two rejecting exchanges, no retry and no HTTP request after the
        # mismatched TLS hostname. The fixture never returns AWS credentials.
        assert len(records) == 2, f"Expected 2 STS requests, got {len(records)}"
        subjects = [body["WebIdentityToken"][0].split(".")[1] for body, _ in records]
        assert subjects == ["alice", "bob"]
        for body, headers in records:
            assert body["Action"] == ["AssumeRoleWithWebIdentity"]
            assert body["RoleArn"] == ["arn:aws:iam::123456789012:role/AthenaApplication"]
            assert not any(name.lower() == "authorization" for name in headers)
            assert body["RoleSessionName"][0].startswith("shinyOAuthDB-")
        assert records[0][0]["RoleSessionName"] != records[1][0]["RoleSessionName"]
        assert not (Path.home() / ".athena-odbc").exists()
        print("Native visitor-token routing, host-credential isolation and TLS checks passed.")


if __name__ == "__main__":
    main()
    subprocess.run([sys.executable, "/probe/test-success.py"], check=True)
