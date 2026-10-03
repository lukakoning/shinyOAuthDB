# Proposed R API

Historical API exploration. Implementation now exists; use [the implemented contract](implementation.md), the [README](../README.md), and function help for the selected API. Callback-based task proposals below were superseded by direct native function tasks.

These APIs are a design proposal, not implemented functions. Existing functions are qualified with their package names. Examples illustrate the intended user experience; they require the future package and the adapter release gates in [migration-plan.md](migration-plan.md).

## 1. A small common surface

| Proposed function | Purpose |
|---|---|
| `oauth_db_azure_sql()`, `oauth_db_sql_server()` | Describe an Azure SQL or explicitly Entra-enabled SQL Server source |
| `oauth_db_azure_postgres()` | Describe an Entra-enabled Azure PostgreSQL Flexible Server source |
| `oauth_db_fabric_sql()`, `oauth_db_fabric()` | Describe Fabric SQL or one Fabric API service |
| `oauth_db_databricks()` | Describe one Databricks workspace / SQL warehouse with a named auth mode |
| `oauth_db_snowflake()` | Describe a Snowflake account/warehouse with explicit OAuth user/role setup |
| `oauth_db_capabilities(source)` | Inspect supported operations and dependency/prerequisite status |
| `oauth_db_auth_plan(sources, profiles)` | Produce static groups and target/scope declarations from explicitly associated provider/registration profiles |
| `oauth_db_microsoft_client(sources, ...)` | Optional convenience for one compatible Microsoft registration; returns a `shinyOAuth` client |
| `oauth_db_session(source, authorization, ...)` | Bind a source to the current session's reactive OAuthConnection selection |
| `oauth_db_query(db, sql, params, ...)` | Execute SQL through the existing native engine with managed acquisition/cleanup |
| `oauth_db_with_connection(db, fun, ...)` | Run a synchronous callback with a native DBI connection |
| `oauth_db_with_client(db, fun, ...)` | Run a synchronous callback with a service-specific credential/client context |
| `oauth_db_task(db, operation, ...)` | Create a guarded nonblocking task using the same lifecycle |
| `oauth_db_sql_operation()`, `oauth_db_native_operation(package, fun)` | Explicit worker operation descriptors |

Keep all public names under `oauth_db_` to reduce collisions with DBI and existing clients. Source constructors contain non-secret configuration. A session handle supplies `$status()`, `$close()`, and optional `$diagnose_identity()`; a task supplies `$invoke(...)`, `$status()`, `$result()`, and `$cancel()`. These are R6 runtime methods, not DBI methods.

`oauth_db_query()` and scoped callbacks are synchronous. The task helper is the nonblocking choice. There is no `async = TRUE` flag that silently changes a query's return type from data to promise.

## 2. Azure SQL in a Shiny app

This example includes an existing `shinyOAuth` module, the proposed source/session layer, and a SQL task. Application registration, delegated SQL permission consent, network access, a provisioned user/group, and database grants must already exist.

```r
library(shiny)

# Proposed shinyOAuthDB functions; no credentials in this source descriptor.
sales_source <- shinyOAuthDB::oauth_db_azure_sql(
  server = "example.database.windows.net",
  database = "Sales",
  target = "sql",
  driver = "ODBC Driver 18 for SQL Server"
)

# Proposed helper: derives the explicit delegated SQL profile and checks
# static profile compatibility. Registration and consent are prerequisites.
client <- shinyOAuthDB::oauth_db_microsoft_client(
  sources = list(sales = sales_source),
  tenant_id = Sys.getenv("ENTRA_TENANT_ID"),
  client_id = Sys.getenv("ENTRA_CLIENT_ID"),
  client_secret = Sys.getenv("ENTRA_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTH_REDIRECT_URI")
)

# Existing worker setup; size belongs to deployment configuration.
mirai::daemons(2)
shiny::onStop(function() mirai::daemons(0))

ui <- shinyOAuth::oauth_ui(
  fluidPage(
    numericInput("year", "Year", value = 2026, min = 2000, max = 2100),
    actionButton("load", "Load my sales"),
    textOutput("load_status"),
    tableOutput("sales")
  ),
  id = "auth", client = client
)

server <- function(input, output, session) {
  auth <- shinyOAuth::oauth_module_server(
    "auth", client, async = TRUE, refresh_proactively = TRUE
  )

  db <- shinyOAuthDB::oauth_db_session(
    sales_source,
    authorization = reactive(auth$connection()),
    session = session,
    connection_policy = "operation"
  )

  sales <- shinyOAuthDB::oauth_db_task(
    db,
    operation = shinyOAuthDB::oauth_db_sql_operation(effect = "read"),
    executor = "mirai",
    pending = "latest",
    credential_budget = 120
  )

  observeEvent(input$load, {
    sales$invoke(
      sql = "SELECT sale_date, amount FROM dbo.Sales WHERE sale_year = ?",
      params = list(as.integer(input$year))
    )
  })

  output$load_status <- renderText(sales$status())
  output$sales <- renderTable(sales$result())
}

shinyApp(ui, server, uiPattern = ".*")
```

The SQL uses the visitor's database principal. It does not need an application-side `WHERE owner = <login email>` merely to reproduce database grants. Any additional application filtering remains a separate product requirement. The app uses a query it defines; bound parameter values cannot change its SQL syntax.

`result()` verifies ownership before it exposes data **or raises an error**. It returns a silent unavailable state before completion or after invalidation, suitable for Shiny outputs. Logging out clears its locally stored result, and logging in as another user cannot reveal the previous invocation's result or error.

`credential_budget` requests minimum recorded token validity for dispatch; it is not a promise that every driver supports a 120-second total query timeout. Adapter capabilities expose deadline enforcement. A configured task publication deadline is checked separately, with remote cancellation best effort.

## 3. Reuse an existing login

The configuration helper is optional. Existing applications keep their current login module and client configuration, provided that the client declares the source's target resource/scopes and supports bearer export.

```r
# Inside server(), using the application's existing auth module:
db <- shinyOAuthDB::oauth_db_session(
  sales_source,
  authorization = shiny::reactive(auth$connection())
)

data <- shiny::reactive({
  shinyOAuthDB::oauth_db_query(
    db,
    sql = "SELECT product_id, amount FROM dbo.Sales WHERE sale_year = ?",
    params = list(as.integer(input$year))
  )
})
```

The reactive depends on source arguments and authorization/permission changes. Ordinary token rotation does not itself requery data. A synchronous remote query still blocks the R process; use the task API for lengthy operations.

For an existing retained-authorization manager:

```r
db <- shinyOAuthDB::oauth_db_session(
  sales_source,
  authorization = shiny::reactive(
    auth$connection(input$selected_authorization_id)
  )
)
```

The selected ID must belong to this manager/session. The manager verifies that ownership. A change of selection invalidates this handle's pending/completed outcomes. Never select an arbitrary manager authorization implicitly when more than one is available.

## 4. DBI and dbplyr stay native

```r
totals <- shinyOAuthDB::oauth_db_with_connection(db, function(con) {
  DBI::dbGetQuery(
    con,
    "SELECT product_id, SUM(amount) AS total FROM dbo.Sales GROUP BY product_id"
  )
})

totals <- shinyOAuthDB::oauth_db_with_connection(db, function(con) {
  dplyr::tbl(con, DBI::Id(schema = "dbo", table = "Sales")) |>
    dplyr::group_by(product_id) |>
    dplyr::summarise(total = sum(amount, na.rm = TRUE)) |>
    dplyr::collect()
})
```

The callback receives an `odbc`, `RPostgres`, or `brickster` connection rather than a new proxy driver. It returns materialized data. The package rejects known live/lazy objects and promises in this per-operation callback's return value; it cannot prevent trusted R code from retaining an object elsewhere. For stream/cursor operations, all consumption must remain within the lease, with appropriate cleanup.

Transactions are supported only where the backend capability says so and native reconnect behavior has been validated. A managed transaction uses one scoped connection, never separate task invocations or bridge-level reconnect. Native callbacks retain their driver's limitations, including RPostgres reset behavior discussed in the architecture. brickster's REST-backed DBI currently has no transaction support. A future explicit write helper can use the same lifecycle with no automatic replay or latest-request coalescing.

## 5. Fabric: retain the existing engines

```r
# Outside server(); proposed descriptors:
fabric_sql_source <- shinyOAuthDB::oauth_db_fabric_sql(
  server = "configured-endpoint.datawarehouse.fabric.microsoft.com",
  database = "WarehouseDatabase",
  target = "sql",
  driver = "ODBC Driver 18 for SQL Server"
)

events_source <- shinyOAuthDB::oauth_db_fabric(
  service = "kql",
  cluster = "https://configured-cluster.kusto.fabric.microsoft.com",
  database = "Events",
  target = "kusto"
)

# Inside server():
events_db <- shinyOAuthDB::oauth_db_session(
  events_source, authorization = shiny::reactive(auth$connection())
)

events <- shinyOAuthDB::oauth_db_with_client(events_db, function(client) {
  fabricQueryR::fabric_kql_query(
    cluster = client$config$cluster,
    database = client$config$database,
    query = "Events | take 10",
    token = client$token
  )
})

events_task <- shinyOAuthDB::oauth_db_task(
  events_db,
  operation = shinyOAuthDB::oauth_db_native_operation(
    package = "fabricQueryR", fun = "fabric_kql_query", effect = "read"
  ),
  executor = "mirai"
)
events_task$invoke(query = "Events | take 10")
```

`client` is a short-lived, adapter-specific context: here it has protected native configuration and a Fabric-compatible service credential callback. It is not a replacement Fabric client library. The SQL source opens through `fabricQueryR::fabric_sql_connect()`, preserving its target parsing and conversion behavior; the native Fabric one-shot SQL path may also use `fabric_sql_query()` where its existing query/result semantics fit.

Native operation descriptors resolve a supported exported function by package and name, inject source configuration and the adapter's credential argument, and reject invocation arguments that override credentials, endpoints, role, or protected options. Adapter metadata declares service requirements for each supported operation. The application's explicit effect declaration controls queue policy: only declared reads permit `pending = "latest"`; writes/unknown effects require serial execution and no coalescing. They do not introspect arbitrary functions or classify SQL text to infer permissions/effects, nor support every Fabric function automatically.

The initial compatibility adapter can use exported `fabric_shiny_token_provider()` for synchronous work. **The async example is a target API:** clean fixed-token workers require a public, policy-preserving Fabric credential/materialization seam first. Do not serialize the live callback or reproduce private attribute/profile layouts. The migration plan makes this an explicit release gate.

OneLake, DAX, GraphQL, and discovery use their native Fabric functions similarly. Their scopes, result formats, and applicable item/model/storage policies remain distinct; a generic SQL query method is not imposed on them.

## 6. Databricks: native OAuth or a supported Entra profile

```r
workspace_source <- shinyOAuthDB::oauth_db_databricks(
  host = "https://configured-workspace.azuredatabricks.net",
  warehouse_id = "configured-warehouse-id",
  catalog = "main",
  schema = "reporting",
  auth_mode = "databricks_oauth"
)

# Inside server(), with a Databricks OAuth authorization:
workspace_db <- shinyOAuthDB::oauth_db_session(
  workspace_source,
  authorization = shiny::reactive(databricks_auth$connection())
)

rows <- shinyOAuthDB::oauth_db_query(
  workspace_db, "SELECT * FROM main.reporting.sales LIMIT 10"
)

rows <- shinyOAuthDB::oauth_db_with_client(workspace_db, function(client) {
  brickster::db_sql_query(
    warehouse_id = client$config$warehouse_id,
    statement = "SELECT current_user()",
    host = client$config$host,
    token = client$token
  )
})
```

For the main process, `client$token` is the existing `brickster::db_token_provider()` object capturing this authorization, with exact workspace binding; its callback also checks the captured handle/source/permission epoch. The DBI path uses `brickster::DatabricksSQL()`. A worker constructs its own provider from plain short-lived credential material and a local deadline. It cannot refresh through the live OAuthConnection; a forced-refresh challenge ends the phase with a refresh-unavailable error. Total engine timeout limitations are documented separately.

`auth_mode = "entra"` is a separate Azure Databricks profile with the correct Databricks Entra resource target. An account/workspace federation profile is another explicit recipe with required policy configuration. No mode accepts the current app login token merely because its issuer is familiar.

## 7. Azure PostgreSQL and Snowflake configuration

```r
pg_source <- shinyOAuthDB::oauth_db_azure_postgres(
  host = "configured-server.postgres.database.azure.com",
  database = "reporting",
  user = "provisioned-entra-group-role",
  target = "postgres",
  sslrootcert = "/deployment/config/postgres-ca.pem"
)

snow_source <- shinyOAuthDB::oauth_db_snowflake(
  server = "configured-account.snowflakecomputing.com",
  database = "ANALYTICS",
  schema = "REPORTING",
  warehouse = "APP_WH",
  role = "APP_READER",
  driver = "SnowflakeDSIIDriver",
  auth_mode = "external_oauth",
  provider_family = "microsoft",
  resource = "api://configured-snowflake-resource",
  scopes = "api://configured-snowflake-resource/session:role:APP_READER",
  target = "snowflake"
)
```

The PostgreSQL `user` is an approved provisioned role. Individual-user mappings can use a trusted runtime resolver over validated identity claims; they cannot trust a browser-supplied email or invent a role from it. A group-role login still uses the individual's accepted Entra token; confirm membership and role semantics in the deployment.

The Snowflake scope string above is illustrative of an application's exposed role scope; the exact scopes, claim mapping, resource, permitted roles, and any scope delimiter must match its configured External OAuth integration. Its provider/profile association is explicit: External OAuth can use Microsoft, Okta, or another configured provider, which cannot be inferred from the scope string. `auth_mode = "snowflake_oauth"` instead uses a separate Snowflake authorization configuration. The adapter supplies `authenticator = "oauth"` and the explicit token, rejects `TOKEN_FILE_PATH`/alternate auth overrides, and returns a native ODBC connection.

When the PostgreSQL source uses a `.default` profile, that consent mode and explicit SQL scopes cannot be automatically mixed in one Microsoft client under the inspected shinyOAuth rules. The transport does not itself mandate `.default`; a compatible explicit delegated profile may be possible. The auth planner should report separate declared registration/authorization groups or request an explicitly reviewed compatible configuration, rather than building an invalid client. It checks declared static compatibility and does not verify the live registration's permissions or consent. Arbitrary merging is not an API convenience.

## 8. Status and lifetime contract

Session `$status()` returns redacted configuration/authorization information, selected target, and connection availability. Its states can include `waiting_for_authorization`, `not_acquired`, `ready`, `acquiring`, `needs_authorization`, `unsupported`, and `closed`. Readiness does not prove remote access. Status can depend on token expiry without forcing a data reload.

Task `$status()` can return `initial`, `queued`, `acquiring`, `running`, `success`, `error`, `cancelled`, or `invalidated`. `$result()` checks correlation and permissions before inspecting the stored value/error; stale errors never escape that guard. `$cancel()` reports local invalidation and remote cancellation support/acknowledgment separately.

`$close()` releases local leases and invalidates tasks; it does not log the user out of unrelated databases or revoke a shared OAuth grant. The existing `shinyOAuth` UI/module owns login, logout, and reauthorization. Session end automatically closes its handles.

Optional `connection_policy = "session"` preserves a native connection only within one session and authorization epoch. It requires tested expiry/native pooling/reconnect behavior. Ordinary connection arguments cannot add alternate credentials. Native-driver limitations are exposed instead of hidden by an automatic fallback.

## 9. Dependency and naming stability

Before implementation, settle final constructor arguments against each native client's public API and keep adapter-specific settings explicit. Core functions should remain small; users should not learn a replacement query language or a parallel configuration system for every driver.

Require `shinyOAuth`, `shiny`, `DBI`, `R6`, and a small condition/validation dependency set in the eventual package. Keep database clients and worker backends optional with actionable per-adapter errors. Exact version floors depend on verified features, not the latest documentation version. The [migration plan](migration-plan.md) records the presently known floors and release gates.
