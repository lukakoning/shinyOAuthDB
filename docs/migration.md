# Migrating earlier development apps

The current API creates session-local accessors for native connections or
credentials. The [README](../README.md) and [simple apps vignette](../vignettes/simple-apps.Rmd)
start with working examples. This page records changes from earlier development
snapshots; compatibility aliases are not provided.

## Argument names

Database helpers now use `required_scopes` for permission checks. Change, for
example, `oauth_db_token(auth$connection, scopes = "all-apis")` to
`oauth_db_token(auth$connection, required_scopes = "all-apis")`. Ordinary OAuth
clients and the optional client presets still use `scopes` for consent.
`scopes` in a connector's `...` is now an ordinary native argument; it is not
intercepted as a legacy bridge setting.

`oauth_db_azure_postgres()` uses native RPostgres `dbname`, replacing `database`.
Its `required_scopes` defaults to `character()`: configure `.default` consent
on the shinyOAuth client, and supply actual permissions for any additional
bridge check. The Microsoft client preset already supplies the consent scope.

## Databricks

`oauth_db_databricks()` always creates a DBI accessor. Supply `host` and either
`warehouse_id` or `http_path`. To supply a bearer string to brickster REST,
use `oauth_db_token(auth$connection, required_scopes = "all-apis")`. Entra REST
access uses the configured target and Entra permission scopes instead.

## Earlier source and operation API

Replace source construction plus `oauth_db_session()` with a backend accessor
such as `con <- oauth_db_azure_sql(auth$connection, ...)`, then call ordinary
database functions with `con()`. Source descriptors, operation mappings,
managed query results, and worker execution were removed. Use ordinary Shiny
code for queries and app-owned result storage.

Earlier architecture and API-draft documents describe that former design.
Shiny integration belongs in this package. The supported fabricQueryR and
brickster interfaces are their native connection and credential APIs; older
experiments with extra hooks or modified dependency checkouts are unnecessary.
