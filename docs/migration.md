# Updating earlier development apps

The current interface uses ordinary Shiny code and native database functions.
Choose your source in [Getting started](../vignettes/getting-started.Rmd).
Earlier development interfaces have no compatibility aliases.

## Changed arguments

| Earlier name | Current name | Where |
| --- | --- | --- |
| `default_token_target` | `token_target_default` | shinyOAuth client settings |
| `scopes` | `required_scopes` | Permission checks on database and token helpers |
| `database` | `dbname` | `oauth_db_azure_postgres()` |

OAuth clients still use `scopes` to request consent. Azure SQL, Fabric SQL,
Databricks SQL, and Azure PostgreSQL helpers rely on the client or target's
permission requirements by default. Use `required_scopes` for an additional
check. Snowflake derives its default role scope from `role`.

## Databricks and Fabric

`oauth_db_databricks()` now always supplies a DBI connection. Pass a `host`
and either `warehouse_id` or `http_path`. For brickster API functions, use
`oauth_db_databricks_api()$call()`; it supplies the host and current token.

For Fabric API calls and resource objects, use `oauth_db_fabric_api()`.
The single-service `oauth_db_fabric()` callback helper remains available.
See the [Fabric](../vignettes/fabric.Rmd) and
[Databricks](../vignettes/databricks.Rmd) guides for examples.

## Former source and operation API

Replace source descriptors and `oauth_db_session()` with a helper such as
`con <- oauth_db_azure_sql(auth$connection, ...)`. Obtain `connection <- con()`
inside a reactive expression, then call DBI or dbplyr.

Queries, stored results, and background work now belong to the app.
The [query-button example](../playground/example-query-button.R) shows how to
run queries on demand and clear stored results when the authorization changes.
