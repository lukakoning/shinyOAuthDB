# Elasticsearch

Use
[`oauth_db_elasticsearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_elasticsearch_api.md)
to search documents or run SQL and ES\|QL with each Shiny visitor’s
access token. Elasticsearch checks the token and applies that user’s
roles, including document and field restrictions. The client uses HTTPS
and needs `jsonlite`, without a database driver.

This guide uses an external identity provider and an Elasticsearch JWT
realm configured for access tokens. It supports self-managed
Elasticsearch and Elastic Cloud Hosted deployments with that realm
enabled. Check your subscription for JWT realm availability. Elastic
Cloud Serverless does not support authentication realms, so this setup
does not apply to Serverless.

## Configure the deployment

Ask your Elasticsearch administrator to configure a JWT realm accepting
the access tokens issued to your app. The `access_token` realm type
requires Elasticsearch 8.7 or later. Configure the issuer, audience,
signing keys, allowed subjects and claims used for the username and
groups.

For example, a realm named `visitors` in `elasticsearch.yml` could
contain:

``` yaml
xpack.security.authc.realms.jwt.visitors:
  order: 0
  token_type: access_token
  client_authentication.type: shared_secret
  allowed_issuer: "https://login.example.org/realms/reporting"
  allowed_audiences: ["elasticsearch-reporting"]
  allowed_subjects: ["alice-subject", "bob-subject"]
  allowed_signature_algorithms: ["RS256"]
  pkc_jwkset_path: "https://login.example.org/realms/reporting/protocol/openid-connect/certs"
  claims.principal: sub
  claims.groups: groups
```

Replace the subjects with the provider’s actual `sub` values, or
configure appropriate `allowed_subject_patterns`. The provider must
issue JWT access tokens containing `iss`, `aud`, `sub`, `iat` and `exp`;
opaque tokens won’t work with this realm. Configure the audience for the
data service, and keep ID tokens separate from access tokens.

Store the application’s realm shared secret in the Elasticsearch
keystore:

``` sh
bin/elasticsearch-keystore add xpack.security.authc.realms.jwt.visitors.client_authentication.shared_secret
```

For Elastic Cloud Hosted, use the deployment’s configuration and secure
settings controls. The Shiny app needs the same realm shared secret.
This secret authenticates the application and is separate from the
secret used by shinyOAuth for the OAuth client registration.

Create Elasticsearch roles and role mappings for your users. For
example, an administrator could grant a provider group named `analysts`
read access:

``` json
PUT /_security/role/orders_reader
{
  "indices": [{
    "names": ["orders"],
    "privileges": ["read", "view_index_metadata"]
  }]
}

PUT /_security/role_mapping/reporting_analysts
{
  "enabled": true,
  "roles": ["orders_reader"],
  "rules": {"all": [
    {"field": {"realm.name": "visitors"}},
    {"field": {"groups": "analysts"}}
  ]}
}
```

Add document and field restrictions to those roles when users should see
different records or fields. OAuth scopes requested by the app do not
grant Elasticsearch index privileges. Configuring Kibana’s OIDC login
also does not configure this JWT realm for API requests.

See Elastic’s [JWT realm
guide](https://www.elastic.co/docs/deploy-manage/users-roles/cluster-or-deployment-auth/jwt)
and [Serverless authentication
limitations](https://www.elastic.co/docs/deploy-manage/deploy/elastic-cloud/serverless-faq).

## Register your app and save its settings

Register a Shiny web application with the identity provider trusted by
the realm. Use `http://localhost:8100` as its redirect URI for this
example. The provider must issue access tokens for the configured
Elasticsearch audience and include the user or group claims needed by
your role mappings.

Save these settings in `.Renviron` and restart R:

| Setting | Value |
|----|----|
| `OAUTHDB_ELASTICSEARCH_URL` | Deployment HTTPS URL, without `/_search` or `/_sql` |
| `OAUTHDB_ELASTICSEARCH_ISSUER` | Identity provider issuer URL |
| `OAUTHDB_ELASTICSEARCH_REALM_SECRET` | Shared secret configured for the JWT realm |
| `OAUTHDB_CLIENT_ID`, `OAUTHDB_CLIENT_SECRET` | OAuth registration’s ID and secret |

The example requests `search.read`, a scope your provider must define or
replace. Configure the token audience with your provider’s settings. If
it needs an authorization parameter such as Auth0’s `audience`, pass it
through the provider’s `extra_auth_params`; an arbitrary scope name
won’t set it. See [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#register-your-app)
for registration and token settings.

## A complete app

Replace `orders` and the requested scope with those used by your
deployment. The realm’s user role must permit reading the index.

After signing in, click **Load rows**. The app starts its workers once
and stops them at shutdown.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_ELASTICSEARCH_ISSUER")
)

client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("openid", "profile", "search.read")
)

ui <- oauth_ui(
  fluidPage(
    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),

    actionButton("load", "Load rows"),
    verbatimTextOutput("rows")
  ),

  id = "auth",
  client = client
)

fetch_rows <- function(database) {
  database$database(
    "orders",
    body = list(size = 20L, query = list(term = list(country = "NL")))
  )$hits
}

server <- function(input, output, session) {
  auth <- oauth_module_server(
    "auth",
    client,
    auto_redirect = FALSE,
    async = TRUE
  )

  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  search <- oauth_db_elasticsearch_api(
    auth$connection,
    url = Sys.getenv("OAUTHDB_ELASTICSEARCH_URL"),
    client_secret = Sys.getenv("OAUTHDB_ELASTICSEARCH_REALM_SECRET"),
    required_scopes = "search.read"
  )

  query_task <- oauth_db_task(search, method = fetch_rows)

  observeEvent(input$load, {
    query_task$invoke()
  })

  output$rows <- renderPrint(query_task$result())
}

runApp(
  shinyApp(ui, server, uiPattern = ".*", onStart = function() {
    mirai::daemons(2)

    onStop(function() mirai::daemons(0))
  }),
  port = 8100,
  launch.browser = FALSE
)

# Open the app in your regular browser at its registered redirect URI.
```

Open `http://localhost:8100` in your regular browser. For a private CA,
pass its PEM bundle through `ca_bundle` when creating the API client.

## SQL, ES\|QL and pagination

SQL and ES\|QL return their native column metadata and rows as lists.
Large JSON integers remain strings and multivalued fields remain nested
lists. Bind parameter values separately from the query:

``` r

sql <- search$sql(
  "SELECT country, total FROM orders WHERE country = ?",
  parameters = list("NL")
)

sql$columns
sql$rows

esql <- search$esql(
  "FROM orders | WHERE country == ? | KEEP country, total | LIMIT 20",
  parameters = list("NL")
)

esql$values
```

ES\|QL and its parameter syntax depend on the server version. The
integration check uses Elasticsearch 9.2.0. For named ES\|QL parameters
or other native options, use `$request()` with the server’s JSON body
format.

The client returns one page per call. Fetch search pages explicitly
using `search_after` and a stable sort. For SQL, use the returned
cursor:

``` r

if (!is.null(sql$cursor)) {
  page <- search$request(
    "_sql",
    method = "POST",
    body = list(cursor = sql$cursor)
  )

  if (!is.null(page$cursor)) {
    search$request(
      c("_sql", "close"),
      method = "POST",
      body = list(cursor = page$cursor)
    )
  }
}
```

SQL column metadata appears on the first page only. Keep cursors and
point-in-time identifiers with the authorization that created them;
consume or close them before changing accounts and discard saved
identifiers after sign-out. There is no automatic pagination or cursor
cleanup.

Each call gets a current token. The client discards responses if the
user signs out, switches accounts or loses required scopes during a
request. GET and HEAD can refresh and retry once after a 401. POST
searches, SQL, ES\|QL and writes never retry automatically, including
after a 401 or a lost response. Submitted work may continue on the
server after a client timeout.

Search timeouts, failed shards and partial query results raise errors.
Use `raw = TRUE` to inspect the HTTP response, or `$request()` when you
need to handle native response metadata yourself. The client supports
JSON APIs; bulk NDJSON requests need a different client.
