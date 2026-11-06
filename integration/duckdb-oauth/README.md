# DuckDB Quack OAuth fixture

From the repository root, with Docker running and the R test dependencies
installed, run:

```sh
Rscript --vanilla tools/check-duckdb-oauth.R
```

The runner builds a Linux DuckDB server matching the R client's engine
version and installs the `quack`, `httpfs` and community `quack_oauth`
extensions. A fixture issuer generates an RSA key and signed access tokens,
then serves its public JWKS within the container. A TLS proxy presents a
temporary certificate valid for `localhost`. The Windows R client can use
this Linux server even when no quack_oauth binary exists for Windows R.

The public helper runs DBI and dbplyr reads through verified TLS. Checks
cover token replacement, denied writes, incorrect signatures and audiences,
missing server scopes, untrusted certificates and hostname mismatch.
Authorization references use the repository's synthetic Shiny fixtures;
this does not exercise browser sign-in or a production identity provider.

The container publishes only its TLS proxy on loopback. Its issuer and
unencrypted Quack listener remain inside the container. The token audience
is `shinyOAuthDB-fixture` and issuer is `https://fixture.invalid`.
All keys, certificates and tokens are generated for the run and removed
afterward, along with the container. The built Docker image is retained.
No production credentials are needed.

The runner chooses a free port. Set `OAUTHDB_DUCKDB_TLS_TEST_PORT` to select
one explicitly. Docker needs network access to fetch Python dependencies
and DuckDB extensions. A missing extension binary fails the run.
