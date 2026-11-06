# libSQL JWT and HTTPS fixture

With Docker running and the R test dependencies installed, run from the
repository root:

```sh
Rscript --vanilla tools/check-libsql-oauth.R
```

The fixture runs the published libSQL server 0.24.33 image, pinned by
digest, behind a Python TLS proxy. Only the proxy is published on loopback;
the libSQL listener stays inside the container. No cloud account or
production credentials are needed.

The fixture creates an Ed25519 signing key and database-specific JWTs with
`id = "default"`, explicit `a` permissions, and expiry timestamps. The real
server checks signatures, expiry, namespace restrictions and read/write
permissions. Tokens use a fixture issuer; this test does not exercise a
browser OAuth flow, a production identity provider, or Turso Cloud JWKS.

The runner exercises the public `oauth_db_libsql_api()` helper using
synthetic Shiny authorization references. It checks bound parameters,
64-bit integer limits, blobs, nulls, empty results, token rotation and
account selection. Rejected tokens and read-only writes must fail.

The TLS proxy generates a temporary CA and server certificate valid for
`localhost`. Checks require that CA to be trusted and reject an untrusted
chain and a mismatched hostname. On Windows the runner selects curl's
OpenSSL backend when none was explicitly selected, so its temporary CA
bundle can be used without modifying the Windows certificate store.

The proxy also commits an insert and then drops its response, or delays
the response beyond the client's timeout. The runner checks the real
database afterward: exactly one insert may have occurred. Persistent HTTP
connections are available on the proxy to catch transport-level replays.
Redirects must fail without following the Location header.

The runner removes its container and temporary token/certificate directory
on exit. The Docker image is retained. Set `OAUTHDB_LIBSQL_TEST_PORT` to
choose a port instead of allowing the runner to select a free one.
The initial build needs network access to fetch the server image and
Python dependencies.

See the [libSQL guide](../../vignettes/libsql.Rmd) for the different token
requirements of self-hosted libSQL and Turso Cloud. The tested self-hosted
server has no general OIDC/JWKS discovery configuration and rejects an
`aud` claim without an accepted-audience configuration.
