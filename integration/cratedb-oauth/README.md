# CrateDB JWT and TLS fixture

From the repository root, with Docker running and the R test dependencies
installed, run:

```sh
Rscript --vanilla tools/check-cratedb-oauth.R
```

On Windows the runner builds the repository's Linux R test image and runs
the checks in Docker, so private CA verification uses the same TLS backend
as CI. Other platforms run the R client on the host.

The runner starts CrateDB 6.4.3 with its native JWT authentication, a
temporary RSA/JWKS issuer and a TLS proxy. Only the proxy is published, on
loopback. An internal administrative rule creates the fixture data and
users; the proxy requires a bearer token and forwards it to CrateDB.
Alice can read and write orders and read an additional private table.
Bob can only read orders. All signing keys, access tokens and certificates
are generated for the run; no production credentials are needed.

The public API helper is tested against real user mapping and grants,
positional parameters, exact BIGINT/NUMERIC results, token rotation,
incorrect signatures, wrong audiences, expired credentials, private CA
trust and hostname verification. A proxy fault drops a response after a
write reaches the engine; a subsequent query confirms it ran exactly once.
Another fault checks the client's timeout. Synthetic Shiny authorization
references supply the signed tokens; browser sign-in is not exercised.

The runner removes its containers, network, temporary credentials and data.
The built image is retained. Set `OAUTHDB_CRATEDB_TEST_PORT` to choose a
specific loopback port instead of an available random port. CrateDB's heap
is set to 512 MB. The internal issuer uses HTTP for this disposable fixture;
production identity-provider and database endpoints should use HTTPS.
