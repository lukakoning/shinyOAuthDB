# SingleStore JWT and ODBC fixture

From the repository root, with Docker and the R validation dependencies
installed:

```sh
docker build --target runner -t shinyoauthdb-local-runner:1 integration/local
docker build -t shinyoauthdb-starrocks-runner:1 integration/starrocks-keycloak
Rscript --vanilla tools/check-singlestore.R
```

The certificate generator needs Python 3 and `cryptography`. Set
`OAUTHDB_SINGLESTORE_PYTHON` to the interpreter's path if it is not available
as `python3`. Extra R library paths can be supplied to the R script.

The runner starts SingleStore Dev Image 0.2.90 / server 10.9.0, pinned by
digest, with a disposable TLS CA and two JWT database users. A dedicated
loopback JWKS endpoint serves only fixture signing keys. Its nonstandard
`aud` key property restricts the database audience. This is an isolated
self-managed deployment with synthetic tokens; no production credentials
or cloud resources are used.

The client image downloads SingleStore Connector/ODBC 1.2.1 and verifies
the release asset's SHA-256 checksum. It installs the package source
archive under test and runs the public helper inside the server's network
namespace. The SQL endpoint is published only on host loopback. The
server certificate is valid for `127.0.0.1`, allowing the runner to test a
hostname failure by connecting as `localhost`.

Checks cover per-user table grants, bound SQL, dbplyr and empty results,
denied reads and writes, account changes, sign-out, server-terminated
sessions and renewed-token reconnects. Expired tokens, wrong signatures,
wrong audiences, mismatched usernames and untrusted certificates must fail.
Completed reactive queries must not rerun when tokens renew or the helper
reconnects.

The runner removes its server, client and temporary certificates on exit;
Docker images are retained. The initial build needs network access and
the server is limited to four CPUs and 6 GB of memory. This check does not
exercise browser OAuth, a production provider, live JWKS rotation or
SingleStore Helios.
