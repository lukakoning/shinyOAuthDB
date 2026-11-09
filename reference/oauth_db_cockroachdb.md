# Query CockroachDB as the signed-in user

Read CockroachDB data using each visitor's JWT access token and database
permissions. Works with self-hosted and cloud clusters configured for
cluster SSO using JWTs. Returns an RPostgres connection for DBI or
dbplyr.

## Usage

``` r
oauth_db_cockroachdb(
  authorization,
  host,
  dbname,
  user,
  ...,
  port = 26257L,
  sslrootcert = NULL,
  connect_timeout = 5L,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- host:

  One CockroachDB SQL hostname or IP address.

- dbname:

  Database name, not a connection string or URI.

- user:

  SQL username, or a function deriving it from the selected sign-in. The
  cluster must map the token's principal to that user.

- ...:

  RPostgres result options (`bigint`, `check_interrupts`, `timezone`,
  `timezone_out`), `application_name`, or TCP keepalive options.
  Authentication, connection identity and TLS settings cannot be
  overridden.

- port:

  SQL port, default `26257`.

- sslrootcert:

  CA certificate bundle path, or `NULL` for libpq's configured bundle.

- connect_timeout:

  Connection timeout in whole seconds, at least two.

- target:

  Name of the service token to use in your shinyOAuth client. Named
  targets let one sign-in obtain tokens for different services. `NULL`
  uses the client's default token.

- required_scopes:

  Additional OAuth permissions to check before use. Request them on the
  shinyOAuth client first; this check doesn't request consent or grant
  database privileges.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A reactive function, usually named `con`. Call `connection <- con()`
inside a render or reactive expression, then pass the connection to DBI.
Before sign-in, the function waits quietly.

## Details

Install RPostgres linked to libpq 16 or later. Configure the cluster's
`server.jwt_authentication` settings for your provider's issuer, signing
keys, audience and principal claim. Request a JWT-format access token
intended for the cluster. Opaque access tokens and ID tokens aren't used
by this helper. There is no universal CockroachDB OAuth client preset.

Connections use verified TLS and CockroachDB's JWT-as-password protocol,
with `--crdb:jwt_auth_enabled=true`. The helper requires password
authentication from the server and doesn't use client certificate or
trust authentication. Unset `PGSERVICE` and `PGSERVICEFILE` before use.
This helper doesn't use the newer SASL OAUTHBEARER protocol.

Create the helper inside `server()` and call `con()` before each query.
After token renewal, the next call replaces the connection with current
credentials without replaying completed reactive queries. Account or
username changes, lost permissions, sign-out and session end close it.
Complete a transaction on the connection that started it; get the next
operation's connection through `con()`.

## See also

[`vignette("cockroachdb", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/cockroachdb.md).

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_cockroachdb(
  auth$connection,
  host = "cluster.example.org", dbname = "reporting",
  user = function() {
    reference <- shiny::req(auth$connection())
    identity <- reference$identity(claims = "preferred_username")
    shiny::req(identity$id_token_claims$preferred_username)
  },
  sslrootcert = "path/to/ca.pem"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT current_user")
})
} # }
```
