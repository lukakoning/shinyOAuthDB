# Query Trino as the signed-in user

Query a self-hosted Trino cluster or Starburst Enterprise using DBI or
dbplyr through RTrino. Users sign in with an identity provider accepted
by the cluster.

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

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

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

  Token target name in the shinyOAuth client. `NULL` uses its default
  token, including for clients without named targets.

- required_scopes:

  Additional permissions to check before use. Request consent and set
  the client's permission requirements in shinyOAuth.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

A reactive function returning an RTrino DBI connection.

## Details

Install RTrino 0.1.0 or later. Create `con` inside `server()` and get
`connection <- con()` inside a render or reactive expression before
querying.

## Sign-in settings

Configure a shinyOAuth client for the cluster's trusted issuer and
audience. The `user` value must match the cluster's principal mapping;
the server checks impersonation permissions.

## Connection lifetime

RTrino gets a current token for each HTTP request, including result
pages. Ordinary token refresh preserves the connection. Account or
username changes replace it; sign-out and session end close it.

A saved authentication callback stays tied to its original
authorization.

## See also

[`vignette("trino", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/trino.md)
has sign-in setup and a complete app.

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md),
[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md),
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md)

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
