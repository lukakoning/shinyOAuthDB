# Athena ODBC transport fixture

This checks the real Amazon Athena ODBC 2.5.0.0 driver through R odbc
against local HTTPS AWS protocol fixtures. It doesn't contact AWS or run billed
queries. The driver download is pinned by SHA-256 in the Dockerfile.

From the repository root, build the image:

```sh
docker build -t shinyoauthdb-athena-native:2.5.0.0 integration/athena-odbc
```

Run it with the source mounted at `/src` and this fixture at `/probe`.
In PowerShell:

```powershell
docker run --rm --network none `
  --mount "type=bind,source=$PWD,target=/src,readonly" `
  --mount "type=bind,source=$PWD/integration/athena-odbc,target=/probe,readonly" `
  shinyoauthdb-athena-native:2.5.0.0 python3 /probe/test-native.py
```

The production ODBC constructor sends two different visitor tokens to
`AssumeRoleWithWebIdentity`, despite unrelated host AWS credentials. The
fixture rejects each token, checks that the native call fails without
retrying or switching credentials, and verifies distinct role session
names. A wrong TLS hostname must fail before the server receives an HTTP
request. Errors must not retain token text, and no file cache may appear.

The runner then starts `test-success.py`, which supplies synthetic STS,
Identity Center and Athena responses to the actual driver. It opens
connections for Alice, Bob and a renewed Alice token in one R process,
keeps all three open and runs six SQL queries through DBI. The fixture
checks separate credential exchanges, current-token use and results tied
to the correct synthetic credentials, including queries on older handles
after another visitor connects. Workgroup checks must run for each new
connection, and no file credential cache may appear.

The success fixture maps the SDK's Identity Center endpoint to localhost
in the disposable container's `/etc/hosts` and listens on port 443. It
requires the image's default root user; it doesn't modify the host's DNS,
trust store or credentials. Both fixtures inject local endpoints into the
internal constructor; the public helper rejects endpoint overrides.

The emulator doesn't validate JWT signatures or AWS permissions. Its
credentials are synthetic and can't access AWS. Live Identity Center
exchange, Lake Formation grants, S3 results and real AWS error behavior
still need deployment checks. See the
[acceptance checklist](../../docs/athena-backend.md#acceptance-boundary).
