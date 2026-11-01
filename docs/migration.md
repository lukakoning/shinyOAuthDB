# Migrating earlier development apps

The current API creates session-local accessors for native connections or
credentials. The [README](../README.md) and [simple apps vignette](../vignettes/simple-apps.Rmd)
start with working examples. This page records changes from earlier development
snapshots; compatibility aliases are not provided.

## Argument names

The released shinyOAuth 0.7.0 interface uses `token_target_default`, replacing
the earlier `default_token_target` setting. Update Microsoft client presets
and direct `shinyOAuth::oauth_client()` calls accordingly. The package now
requires 0.7.0; no development dependency checkout is needed.

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

For native API functions, use `api <- oauth_db_databricks_api(auth$connection,
host = host)`, followed by `api$call(brickster::db_sql_query, ...)`. The client
supplies the host and a current token. The generic bearer accessor remains
available for direct token injection.

`oauth_db_databricks()` always creates a DBI accessor. Supply `host` and either
`warehouse_id` or `http_path`. To supply a bearer string to brickster REST,
use `oauth_db_token(auth$connection, required_scopes = "all-apis")`. Entra REST
access uses the configured target and Entra permission scopes instead.

## Fabric API clients

Use `fabric <- oauth_db_fabric_api(auth$connection)` for multiple services and
native resource-object workflows. `$call(fabricQueryR::fabric_workspaces)`
returns upstream R6 workspace objects; `$token_provider()` supplies a callback
for direct native calls. The older `oauth_db_fabric(service = ...)` continues
to return a single-service callback accessor.

## Scope defaults

Azure SQL, Fabric SQL and Databricks DBI helpers now default to no additional
`required_scopes` check. Configure required permissions on the shinyOAuth
client or target, or pass explicit helper requirements to retain a separate
local check. Existing Microsoft `/.default` and Databricks `sql` clients no
longer need a helper override just to omit a duplicated requirement. Snowflake
continues to derive its native OAuth role scope from `role`.

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
