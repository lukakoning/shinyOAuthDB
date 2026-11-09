# Query Trino as the signed-in user

Query data through Trino or Starburst Enterprise with each visitor's
account and cluster permissions. The RTrino connection supports DBI and
dbplyr. A catalog selects the data source; a schema selects a group of
tables within it.

## Usage

``` r
oauth_db_trino(
  authorization,
  host,
  catalog,
  schema,
  user,
  ...,
  port = NULL,
  ca_bundle = NULL,
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

  Cluster hostname or HTTPS origin.

- catalog, schema:

  Default Trino catalog and schema.

- user:

  Trino username, or a function returning it for the selected account.
  Use a reactive function when the username can change.

- ...:

  RTrino connection options, such as `timeout`, `bigint`,
  `query_max_run_time`, or `extra.headers`.

- port:

  HTTPS port. `NULL` uses the port in `host`, or `443`.

- ca_bundle:

  Optional CA certificate bundle path for RTrino.

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

Install RTrino 0.1.0 or later. Create the helper inside `server()` and
call `con()` inside a render or reactive expression before querying.

## Sign-in settings

Configure a shinyOAuth client for the cluster's trusted provider and
audience. Set `user` to match the cluster's identity mapping; the server
checks that the visitor can use that username.

## Connection lifetime

RTrino gets a current token for each request, including result pages.
Token renewal preserves the connection. Account or username changes
replace it; sign-out and session end close it.

## See also

[`vignette("trino", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/trino.md)
has sign-in setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_trino(
  auth$connection,
  host = "https://trino.example.org",
  catalog = "lakehouse",
  schema = "reporting",
  user = function() shiny::req(auth$token@userinfo$email)
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT * FROM Orders LIMIT 20")
})
} # }
```
