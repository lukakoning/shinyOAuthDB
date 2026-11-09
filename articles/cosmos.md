# Azure Cosmos DB for NoSQL

Read Cosmos DB documents in a Shiny app using each visitor’s Microsoft
Entra account and Cosmos DB data permissions.
[`oauth_db_cosmos_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cosmos_api.md)
runs NoSQL queries over HTTPS, collects result pages and returns data
frames. You can also read one document or fetch one result page at a
time.

This guide covers **Azure Cosmos DB for NoSQL**. MongoDB, Cassandra,
Gremlin and Table endpoints use other protocols. Cosmos DB in Microsoft
Fabric hasn’t been validated with this backend.

## Prepare the account and sign-in

You need an existing Cosmos DB for NoSQL account, database and
container. Copy the account’s **URI** from the Azure portal, such as
`https://example.documents.azure.com`. Supply database and container IDs
separately; don’t use an account key or connection string.

Register a **Web** application in Microsoft Entra with your Shiny app’s
exact redirect URI. The example uses `http://localhost:8100`. Use the
registration’s tenant ID, application ID and server-side client secret.
The shared [registration
guide](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#register-your-app)
explains those settings and production redirect URIs.

[`oauth_db_cosmos_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cosmos_client.md)
requests `openid`, `profile`, `offline_access` and
`https://cosmos.azure.com/.default`. Cosmos DB doesn’t expose a
delegated permission in the app-registration permission picker; don’t
invent a `user_impersonation` permission. Your tenant and application
registration must allow obtaining a user access token for this resource.
Validate that combination before deploying: the offline checks do not
establish tenant consent or live browser sign-in.

Assign each visitor a Cosmos DB **data-plane** role, such as **Cosmos DB
Built-in Data Reader**, scoped to the required database or container.
Subscription Reader, Contributor and account-management roles alone
don’t grant document access. Follow Microsoft’s [data-plane RBAC
guide](https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-connect-role-based-access-control)
to create the assignments. The app doesn’t create databases, containers,
role assignments or users.

Set these values in your environment or `.Renviron`, then restart R:

``` text
OAUTHDB_TENANT_ID=your-tenant-id
OAUTHDB_CLIENT_ID=your-application-id
OAUTHDB_CLIENT_SECRET=your-client-secret
OAUTHDB_COSMOS_URL=https://example.documents.azure.com
OAUTHDB_DATABASE=reporting
OAUTHDB_COSMOS_CONTAINER=orders
```

Install shinyOAuthDB using the [installation
instructions](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#install).
Install `jsonlite` too. This backend doesn’t need ODBC, Python, Azure
CLI or an Azure SDK.

## Build an app

This example reads up to 20 documents with `id`, `country` and `total`
fields. Change the query and partition key to match your container. Save
it as `app.R` and run it in R:

``` r

pkgs <- c("shiny", "shinyOAuth", "shinyOAuthDB", "mirai", "jsonlite")
for (pkg in pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
}

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_cosmos_client(
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)

ui <- oauth_ui(
  fluidPage(
    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),
    actionButton("load", "Load rows"),
    tableOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE, async = TRUE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  cosmos <- oauth_db_cosmos_api(
    auth$connection,
    url = Sys.getenv(
      "OAUTHDB_COSMOS_URL",
      "https://example.documents.azure.com"
    ),
    database = Sys.getenv("OAUTHDB_DATABASE"),
    container = Sys.getenv("OAUTHDB_COSMOS_CONTAINER", "orders")
  )
  query_task <- oauth_db_task(cosmos)
  observeEvent(input$load, {
    query_task$invoke(
      "SELECT TOP 20 c.id, c.total FROM c WHERE c.country = @country",
      parameters = list(country = "NL"),
      partition_key = "NL"
    )
  })
  output$rows <- renderTable(query_task$result())
}

runApp(
  shinyApp(ui, server, onStart = function() {
    mirai::daemons(2)
    onStop(function() mirai::daemons(0))
  }),
  port = 8100,
  launch.browser = FALSE
)
# Open http://localhost:8100 in your regular browser.
```

Create the API client inside `server()` and pass `auth$connection`
without parentheses. Sign in and click **Load rows** to fetch in a
background worker. Cosmos DB checks the visitor’s token and applies
their data-plane roles. The output clears on sign-out or account
replacement; click **Load rows** again to fetch for the new account.

## Queries and documents

Use `@name` placeholders in SQL and a named list without `@` in
`parameters`. Values are sent separately from the query:

``` r

cosmos$query(
  "SELECT c.id, c.total FROM c WHERE c.total >= @minimum",
  parameters = list(minimum = 100),
  partition_key = "NL"
)

document <- cosmos$read("order-123", partition_key = "NL")
document$total
```

Objects become data-frame columns. Nested objects, arrays and mixed
types stay in list columns. Missing and null fields become `NA` in
scalar columns. Large JSON integers stay as strings. For exact decimal
identifiers or money, store and project strings; Cosmos DB’s JSON
numbers don’t supply arbitrary decimal precision.

`SELECT VALUE` can return scalars, arrays or objects. Scalar or mixed
results use a `value` list column. Empty queries return a data frame
with no field schema. To retain native JSON lists and distinguish
missing fields from explicit nulls, use `raw = TRUE` or `$query_page()`.

## Partition keys and access rules

Omitting `partition_key` enables a cross-partition query. Supply a
scalar to target one logical partition. For a hierarchical partition
key, pass the components in their configured order, such as
`list("NL", "Retail")`. Use `list(NULL)` for a JSON null partition key.
Point reads require a key.

The client uses the REST gateway and doesn’t implement the vendor SDK’s
query-plan distribution and result merging. Some cross-partition
aggregates or ordered queries need an SDK; use a partition-specific
query where possible. Unsupported queries return an error from the
service.

**A partition key or SQL filter is a query choice, not an access rule.**
Cosmos DB RBAC controls access to databases and containers, not
individual documents selected by your SQL filter. Give visitors access
only to the containers they are allowed to read.

## Result pages, usage and failures

`$query()` collects every result page within one `timeout`, including
empty pages that carry a continuation token. A page uses a current
access token but stays bound to the account that started the operation.
It stops if that authorization is replaced or revoked. The client
carries Cosmos DB session tokens between pages of the operation.

Use `raw = TRUE` to inspect the total request charge, measured in
request units, alongside the collected documents. Queries can incur
charges even if fetching a later page fails. For larger results, fetch
one page at a time:

``` r

first <- cosmos$query_page(
  "SELECT c.id, c.total FROM c",
  partition_key = "NL"
)
first$documents
first$request_charge

if (!is.null(first$continuation)) {
  second <- cosmos$query_page(
    "SELECT c.id, c.total FROM c",
    partition_key = "NL",
    continuation = first$continuation,
    session_token = first$session_token
  )
}
```

Reuse a continuation only with the same query, parameters, partition and
account. Clear saved pages and continuation tokens on sign-out or
account replacement. The [shared session
guide](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#sessions-saved-results-and-extra-permissions)
covers saved results and background fetching.

Each read can refresh and retry once after HTTP 401. HTTP 403,
throttling (429), redirects and other failures stop the operation. There
is no automatic retry for throttling, and no fallback to a key, managed
identity or the hosting machine’s account. Errors omit service response
bodies and credentials.

The sign-in helper uses the separate `cosmos` token target and the
documented `.default` consent scope. An existing shinyOAuth
authorization can be used with `target = NULL` or another named target
if it obtains a token accepted by the account. For another Azure cloud,
supply the proper `resource` and Microsoft provider explicitly; the
preset defaults to Azure public cloud.

## Validation boundary

Offline tests exercise real shinyOAuth authorization references and HTTP
request construction with synthetic tokens. They cover pagination,
partition keys, JSON values, current tokens, account changes, sign-out,
timeouts and sanitized failures. They don’t validate live Entra consent,
Cosmos DB RBAC or a cloud account. The [backend
notes](https://github.com/lukakoning/shinyOAuthDB/blob/main/docs/cosmos-backend.md)
record the implementation decision and remaining live checks.
