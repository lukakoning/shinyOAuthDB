# PostgreSQL token helper for integration tests

Connect the local test app to PostgreSQL with a user's existing OAuth token.
The helper returns an RPostgres DBI connection. PostgreSQL validates the
token and checks database access.

This Linux-only package uses libpq 18 and is installed in the disposable
[PostgreSQL/Keycloak image](../README.md). It isn't a shinyOAuthDB dependency.

## Use in the fixture

```r
con <- pgBearerHook::pg_connect_bearer(
  token = user_access_token,
  issuer = "https://localhost:18443/realms/shinyoauthdb",
  scope = "database.read",
  host = "localhost",
  port = 5432L,
  dbname = "oauthdb_fixture",
  user = "alice",
  sslrootcert = "/fixtures/tls/ca-cert.pem"
)
DBI::dbGetQuery(con, "SELECT current_user")
DBI::dbDisconnect(con)
```

The helper supplies one token during connection opening. shinyOAuth obtains
and refreshes that token; PostgreSQL validates it and enforces database access.

## Build

Build inside the fixture's Linux image with libpq 18 headers, pkg-config,
and the RPostgres build dependencies. Configure libpq with
`--without-libcurl` and leave the optional `libpq-oauth` module uninstalled
so a reconnect cannot start a device login.

```sh
Rscript -e 'install.packages("RPostgres", type = "source")'
cp -R /fixtures/native /tmp/pgBearerHook-source
R CMD INSTALL /tmp/pgBearerHook-source
Rscript /fixtures/native/tests/regression.R
```

Both RPostgres and this package must use the same shared libpq instance.
`pg_bearer_runtime()` checks the loaded hook symbol and reports version and
hook state. Matching major versions alone is insufficient.

## Connection lifetime

The process-wide hook exists only during a synchronous, single-threaded
connection opening. `R_UnwindProtect()` restores the previous hook and erases
the temporary native token copy on return, error, or interrupt. Caller-held
R strings remain managed by R.

The hook rejects nested use, an existing custom hook, unexpected connection
metadata, and repeated token consumption. It enforces verified TLS and
`require_auth = "oauth"`. A fixed client-ID sentinel satisfies libpq 18;
it does not initiate an authorization-server request.

Discard broken connections and open a new one with a current credential.
Resetting or cloning connections is unsupported. RPostgres may call
`PQreset()` after a failure, but the token hook is already gone. The fixture
disables libpq's device login and Keycloak's device and password grants so
that retry fails. Do not install another OAuth flow in this runtime.
Separate workers need separate R processes.

The native regression tests cover cleanup, one-use delivery, metadata
checks, and failed connections. The surrounding browser tests cover login,
database permissions, and reconnect denial.

References: [libpq OAuth hooks](https://www.postgresql.org/docs/18/libpq-oauth.html),
[connection parameters](https://www.postgresql.org/docs/18/libpq-connect.html),
and [RPostgres connections](https://github.com/r-dbi/RPostgres/blob/main/src/DbConnection.cpp).
