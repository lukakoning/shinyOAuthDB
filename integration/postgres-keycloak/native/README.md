# Integration-only PostgreSQL bearer hook

This is an **integration-only Linux helper package**, installed in the disposable
PostgreSQL + Keycloak test image. It supplies an existing bearer token to libpq
18 while RPostgres remains responsible for connecting and all DBI operations.
It implements no OAuth acquisition, refresh, JWT validation, SQL transport or
database authorization policy, and is not a production dependency of shinyOAuthDB.

The harness calls:

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

on.exit(DBI::dbDisconnect(con), add = TRUE)
DBI::dbGetQuery(con, "SELECT current_user")
```

The returned object is a normal `RPostgres::PqConnection`. Each opening supplies
one explicit token for the expected connection target and user. The validator
checks token issuer, audience, scopes and identity; this helper does not infer
those claims from a JWT or turn an ID token into a database access token.

The C entry point wraps RPostgres's synchronous `dbConnect()` callback with
`R_UnwindProtect()`. It restores libpq's previous hook and erases its temporary
native token copy on successful return, errors and interrupts. It refuses a
preexisting custom OAuth hook, nested scopes, unexpected discovery URLs/scopes,
another connection or consumption of the token twice. The callback never invokes
R from libpq's authentication hook. The only process-wide hook exists during this
single-threaded opening; concurrent libpq connection openings in that R process
are unsupported. Background workers must each run in a separate process.

The helper enforces verified database TLS and `require_auth = "oauth"`, sets the
database role and target explicitly, supplies a nonsecret password sentinel and
uses `/dev/null` as the password file. It never reads a token from an environment
variable or file, installs an OAuth provider or prints a token. The input R string
is still managed by R; the helper cannot promise to erase caller-held R copies.

**Reconnects and connection cloning are unsupported.** RPostgres may call
`PQreset()` after a broken connection. libpq clears the bearer after successful
authentication, and this helper has already removed its token hook. The fixture
therefore builds libpq 18 without its builtin device flow (`--without-libcurl`)
and does not install the optional `libpq-oauth` module. It also disables Keycloak
device authorization for its application clients. Reconnect must fail, after
which the harness discards the DBI object and opens a new connection with a fresh
session credential. `require_auth = "oauth"` prevents password, trust or other
authentication fallback, but by itself does not prevent another OAuth login.
Do not reuse this helper in a runtime which installs a default/custom OAuth flow.
The live integration tests must verify a forced disconnect followed by denial.

PostgreSQL 18's current source requires a nonempty `oauth_client_id` before calling
the custom hook, even for an already acquired token, and `PQconnectdbParams()`
ignores empty values. The helper consequently uses the fixed sentinel
`pgBearerHook-external-bearer-only`. It makes no authorization-server request
with that ID. This fixture pins major version 18; it does not implement the
PostgreSQL 19 development V2 hook.

Build inside the isolated Linux image, after installing libpq 18 headers/shared
library, pkg-config and the RPostgres build dependencies:

```sh
# Configure the fixture's PostgreSQL/libpq source without a builtin login flow.
# ... ./configure --without-libcurl ...
Rscript -e 'install.packages("RPostgres", type = "source")'
cp -R /fixtures/native /tmp/pgBearerHook-source
R CMD INSTALL /tmp/pgBearerHook-source
Rscript /fixtures/native/tests/regression.R
```

Both packages must link the **same shared libpq instance**, not merely the same
major version. `pg_bearer_runtime()` verifies that the already-loaded RPostgres
shared object resolves the same `PQgetAuthDataHook` symbol as this package, and
reports only version and hook-state booleans. Its native regression tests cover
normal/error unwind restoration, nesting denial, connection/issuer/scope
isolation, one-use token delivery, malformed input and a real RPostgres connection
failure. Provider-backed login, database RLS and forced reconnect denial belong
to the surrounding integration harness.

The underlying interfaces and constraints are documented in
[PostgreSQL's libpq OAuth API](https://www.postgresql.org/docs/18/libpq-oauth.html),
[libpq connection parameters](https://www.postgresql.org/docs/18/libpq-connect.html),
[PostgreSQL 18 OAuth implementation](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/interfaces/libpq/fe-auth-oauth.c),
[RPostgres's connection constructor](https://github.com/r-dbi/RPostgres/blob/main/src/DbConnection.cpp)
and [R's unwind API](https://stat.ethz.ch/R-manual/R-devel/doc/manual/R-exts.html#Condition-handling-and-unwinding).
