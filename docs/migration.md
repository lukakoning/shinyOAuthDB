# Updating earlier development apps

Update older development apps to use connection helpers and Shiny reactive
expressions. Choose your source in [Getting started](../vignettes/getting-started.Rmd)
for a complete app. The earlier interfaces have no compatibility aliases.

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

`oauth_db_databricks()` returns a function that provides a DBI connection.
Pass `host` and either `warehouse_id` or `http_path`. For brickster API
functions, create `databricks <- oauth_db_databricks_api(...)` and use
`databricks$call()`.

For Fabric API calls and resource objects, use `oauth_db_fabric_api()`.
The single-service `oauth_db_fabric()` callback helper remains available.
See the [Fabric](../vignettes/fabric.Rmd) and
[Databricks](../vignettes/databricks.Rmd) guides for examples.

## Oracle OAuth providers

`oauth_db_oracle()` now accepts tokens from the identity provider configured
in Oracle, including documented OCI IAM OAuth and Keycloak integrations.
Existing Entra global-schema connections retain the default
`authorization_model = "global"`. For Oracle Deep Data Security direct
logon, select `authorization_model = "end_user"`; it requires a matching
server-established token context and replaces the connection on access
after token renewal.

Oracle's `required_scopes` are now literal provider scope names. Keep
Entra `/.default` consent markers in the client or token target and omit
them from the helper's operation checks. ORDS resources use the separate
`oauth_db_oracle_ords_api()` client. See the [Oracle guide](../vignettes/oracle.Rmd)
and [ORDS guide](../vignettes/oracle-ords.Rmd).

## Former source and operation API

Replace source descriptors and `oauth_db_session()` with a helper such as
`con <- oauth_db_azure_sql(auth$connection, ...)`. Obtain `connection <- con()`
inside a reactive expression, then call DBI or dbplyr.

Keep query results and background work in your app. The
[query-button example](../playground/example-query-button.R) runs SQL on
a button click and clears saved results when the authorization changes.
