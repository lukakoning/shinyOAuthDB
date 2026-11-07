# Connect another database package to a user's sign-in

Use this when a database driver accepts an OAuth token and has no
dedicated shinyOAuthDB helper. Supply the function that opens its
connection and name the argument that receives the token.

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

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

- connect:

  Function that opens the connection, such as
  [`DBI::dbConnect`](https://dbi.r-dbi.org/reference/dbConnect.html).

- ...:

  Named arguments for `connect`, excluding the token argument.

- token_arg:

  Name of the argument that receives the user's access token.

- target:

  Token target name in the shinyOAuth client. `NULL` uses its default
  token, including for clients without named targets.

- required_scopes:

  Additional permissions to check before use. Request consent and set
  the client's permission requirements in shinyOAuth.

- disconnect:

  Function to close the connection. By default, DBI connections use
  [`DBI::dbDisconnect()`](https://dbi.r-dbi.org/reference/dbDisconnect.html);
  other objects have no cleanup.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

A reactive function such as `con`. Call `connection <- con()` inside a
render or reactive expression to get the connection. Before sign-in, it
waits quietly, like
[`shiny::req()`](https://rdrr.io/pkg/shiny/man/req.html).

## Details

Create the helper inside `server()` and call `con()` before each query.
The helper reuses the connection and calls its cleanup function when the
selected authorization changes, ends, or loses required permissions, or
when the Shiny session ends. Cleanup depends on the driver; a retained
native handle may still contain copied credentials. Call `con()` before
each operation.

A valid DBI connection stays open through token refresh. If the
connection becomes invalid, the next call opens a new one.

This helper supplies the token when opening a connection. For a function
that takes a token on each request, use
[`oauth_db_token()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_token.md)
or a platform API client.

## See also

[`oauth_db_token()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_token.md).
For saved results and connection lifetime, see
[`vignette("authorization", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/authorization.md).

Other advanced connection helpers:
[`oauth_db_fabric()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric.md),
[`oauth_db_token()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_token.md)

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
