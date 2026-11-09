"""MySQL clear-password protocol fixture; synthetic credentials, no Azure APIs."""

import asyncio
import hashlib
import json
import logging
from pathlib import Path
import ssl
import subprocess

from mysql_mimic import MysqlServer, Session
from mysql_mimic.auth import (
    AbstractClearPasswordAuthPlugin,
    IdentityProvider,
    NativePasswordAuthPlugin,
    User,
)
from mysql_mimic.errors import MysqlError


OUTPUT = Path("/out")
LONG_TOKEN = "long-" + "x" * 12000
CREDENTIALS = {"alice": {"fixture-A", "renewed-A", LONG_TOKEN}, "bob": {"fixture-B"}}


def audit(**fields):
    with (OUTPUT / "audit.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(fields) + "\n")


class VisitorPassword(AbstractClearPasswordAuthPlugin):
    name = "visitor_password"

    async def check(self, username, password):
        accepted = password in CREDENTIALS.get(username, set())
        audit(
            event="authentication",
            user=username,
            accepted=accepted,
            length=len(password),
            digest=hashlib.sha256(password.encode()).hexdigest(),
        )
        return username if accepted else None


class Visitors(IdentityProvider):
    def get_plugins(self):
        # Azure selects the cleartext plugin after learning the account name.
        return [NativePasswordAuthPlugin(), VisitorPassword()]

    async def get_user(self, username):
        if username in CREDENTIALS:
            return User(name=username, auth_plugin=VisitorPassword.name)
        return None


class VisitorSession(Session):
    async def handle_query(self, sql, attrs):
        # Connector/ODBC enables session tracking during connection setup.
        if sql.strip().lower().startswith("set") and "session_track_" in sql.lower():
            return [], []
        return await super().handle_query(sql, attrs)

    async def init(self, connection):
        await super().init(connection)
        encrypted = connection.stream.writer.get_extra_info("ssl_object") is not None
        audit(event="connection", user=self.username, tls=encrypted)
        if not encrypted:
            raise MysqlError("TLS is required")

    async def query(self, expression, sql, attrs):
        if sql.lower().strip() == "select value from visible_rows":
            return [(f"{self.username}-visible",)], ["value"]
        raise MysqlError("The fixture denies this query")


async def main():
    OUTPUT.mkdir(exist_ok=True)
    tls_dir = Path("/tmp/fixture-tls")
    tls_dir.mkdir()
    ca_key, ca = tls_dir / "ca.key", OUTPUT / "ca.pem"
    key, csr, cert = tls_dir / "server.key", tls_dir / "server.csr", tls_dir / "server.pem"
    extension = tls_dir / "server.ext"
    extension.write_text("subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth\n")
    commands = [
        ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
         "-subj", "/CN=Azure MySQL protocol test CA", "-keyout", str(ca_key), "-out", str(ca)],
        ["req", "-newkey", "rsa:2048", "-nodes", "-sha256", "-subj", "/CN=127.0.0.1",
         "-keyout", str(key), "-out", str(csr)],
        ["x509", "-req", "-in", str(csr), "-CA", str(ca), "-CAkey", str(ca_key),
         "-CAcreateserial", "-days", "1", "-sha256", "-extfile", str(extension), "-out", str(cert)],
    ]
    for arguments in commands:
        subprocess.run(["openssl", *arguments], check=True, capture_output=True)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert, key)
    server = MysqlServer(
        session_factory=VisitorSession, identity_provider=Visitors(), ssl=context
    )
    await server.start_server(host="0.0.0.0", port=3306)
    (OUTPUT / "ready").write_text("ready\n")
    await server.serve_forever()


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING)
    asyncio.run(main())
