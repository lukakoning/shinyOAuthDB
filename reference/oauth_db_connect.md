# Connect another database package to a user's sign-in

Use a database package that accepts access tokens with a visitor's Shiny
sign-in. This is the general helper for drivers without a dedicated
shinyOAuthDB function. It supplies the user's token when opening the
connection and keeps that connection in their Shiny session.

## Usage

``` r
oauth_db_connect(
  authorization,
  connect = DBI::dbConnect,
  ...,
  token_arg = "token",
  target = NULL,
  required_scopes = character(),
  disconnect = NULL,
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- connect:

  Function that opens the connection, such as
  [`DBI::dbConnect`](https://dbi.r-dbi.org/reference/dbConnect.html).

- ...:

  Named arguments for `connect`, excluding the token argument.

- token_arg:

  Name of the argument that receives the user's access token.

- target:

  Name of the service token to use in your shinyOAuth client. Named
  targets let one sign-in obtain tokens for different services. `NULL`
  uses the client's default token.

- required_scopes:

  Additional OAuth permissions to check before use. Request them on the
  shinyOAuth client first; this check doesn't request consent or grant
  database privileges.

- disconnect:

  Function to close the connection. By default, DBI connections use
  [`DBI::dbDisconnect()`](https://dbi.r-dbi.org/reference/dbDisconnect.html);
  other objects have no cleanup.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A reactive function, usually named `con`. Call `connection <- con()`
inside a render or reactive expression to get the database connection.
Before sign-in, it waits quietly like
[`shiny::req()`](https://rdrr.io/pkg/shiny/man/req.html).

## Details

Create the helper inside `server()` so each visitor has their own
connection. Call `con()` before each operation; it checks the current
authorization and reuses a valid connection. Sign-out, account changes,
loss of required permissions and session end trigger cleanup.

A connection you save separately may keep copied credentials, depending
on the driver. Obtain it through `con()` each time. A valid DBI
connection can stay open through token renewal; a broken one reopens on
the next call.

If token refresh is running, reactive outputs wait until it finishes. A
button-triggered query may need another click. `min_valid_for` checks
the token's remaining lifetime at the start; it doesn't guarantee
validity throughout a long query.

For functions that accept a token on every request, use
[`oauth_db_token()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_token.md)
or the source's API client.

## See also

[`oauth_db_token()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_token.md).
For saved results and connection lifetime, see
[`vignette("getting-started", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# Inside server(); client configured for Azure PostgreSQL:
con <- oauth_db_connect(
  auth$connection,
  connect = DBI::dbConnect,
  drv = RPostgres::Postgres(),
  token_arg = "password",
  target = "postgres",
  host = "example.postgres.database.azure.com",
  dbname = "reporting",
  user = "reporting-readers",
  sslmode = "verify-full"
)
} # }
```
