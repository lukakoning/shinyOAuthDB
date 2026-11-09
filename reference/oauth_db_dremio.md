# Query Dremio as the signed-in user

Open a Flight SQL connection with the visitor's current OAuth access
token. The connection uses adbi and Apache Arrow's ADBC Flight SQL
driver, and supports DBI queries and Arrow results.

## Usage

``` r
oauth_db_dremio(
  authorization,
  host,
  ...,
  port = 32010L,
  driver = "flightsql",
  ca_bundle = NULL,
  timeout = 30,
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

  One Flight SQL endpoint hostname or IPv4 address, without a protocol
  or port. Use a Dremio endpoint configured for TLS and bearer
  authentication.

- ...:

  Result option `bigint`, passed to adbi's
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html)
  method. Other native options cannot be supplied.

- port:

  Flight SQL port, default `32010` for self-hosted Dremio.

- driver:

  Installed ADBC driver name, manifest path or shared-library path. The
  default `"flightsql"` selects the driver installed with
  `dbc install flightsql`.

- ca_bundle:

  Optional path to a PEM file containing trusted CA certificates. `NULL`
  uses the driver's system trust roots.

- timeout:

  Positive timeout in seconds for each Flight SQL connection, query,
  fetch or update RPC. This is not a deadline for an entire query.

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
inside a render or reactive expression, then use the connection with
DBI. Before sign-in, it waits quietly.

## Details

Install adbi, adbcdrivermanager 0.25.0 or later, and the ADBC Flight SQL
shared-library driver. The R packages alone do not install that driver.
Configure Dremio Enterprise to accept the provider's external JWT access
tokens and map their identities to Dremio users. An already acquired
Dremio OAuth access token can also be supplied through shinyOAuth.

The helper sends the access token directly as a bearer credential. It
does not exchange external JWTs for Dremio tokens or run the driver's
OAuth flow. A browser login alone does not configure database access.
Dremio Cloud editions and endpoints require separate compatibility
checks; see
[`vignette("dremio", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/dremio.md).

TLS and certificate verification are required. Credentials, native OAuth
settings, headers, URI and TLS settings cannot be overridden in `...`.

Create the helper inside `server()` and call `con()` before each
operation. A changed access token replaces the connection on its next
use, without replaying completed reactive queries. Account changes,
permission loss, sign-out and session end close the connection and
outstanding results. The driver holds a fixed bearer during each DBI
operation; renewing the Shiny token does not update an ongoing query or
fetch. A failed query is not replayed. Reopening loses SQL session
state; a submitted query may continue after the local connection closes.

## See also

[`vignette("dremio", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/dremio.md)
for driver installation, provider settings and a complete Shiny app.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_dremio(auth$connection, host = "dremio.example.org")
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT CURRENT_USER AS database_user")
})
} # }
```
