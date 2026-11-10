# Supabase

Supabase provides a PostgreSQL database with a web API for its tables,
views and functions. A Shiny app can use this Data API to read data with
each visitor’s account, without a PostgreSQL driver.

[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md)
sends the visitor’s access token with requests. PostgreSQL grants and
row-level security policies determine which records they can read or
change. The first example uses a table of notes where each person can
read only their own rows.

## Configure Supabase sign-in

For people with accounts in your Supabase project, enable the project’s
[OAuth 2.1
server](https://supabase.com/docs/guides/auth/oauth-server/getting-started).
This feature is currently in beta. It requires an existing sign-in and
consent page in your Supabase application; the Shiny app redirects to
it.

In **Authentication \> OAuth Server**, enable the server, configure its
authorization path and register a client with the exact Shiny redirect
URI, `http://localhost:8100` for this example. A deployed app needs its
own HTTPS redirect URI. For a confidential client, select
`client_secret_basic` and save its secret. Public clients registered
with authentication method `none` can omit the secret. Both use PKCE.

Configure an asymmetric signing key, such as ES256 or RS256. The default
client requests `openid` and validates signed ID tokens through OIDC
discovery and JWKS. Supabase’s legacy HS256 signing setup cannot issue
these OIDC ID tokens. See the [signing key
guide](https://supabase.com/docs/guides/auth/signing-keys).

Save these values in your app’s `.Renviron`:

``` text
OAUTHDB_SUPABASE_URL=https://your-project.supabase.co
OAUTHDB_SUPABASE_KEY=sb_publishable_your-project-key
OAUTHDB_CLIENT_ID=your-oauth-client-id
OAUTHDB_CLIENT_SECRET=your-oauth-client-secret
```

Use the project base URL, without `/rest/v1` or `/auth/v1`. Get the
publishable key from the project’s API keys settings. It identifies your
application and is separate from the OAuth client ID and secret. For a
public client, leave `OAUTHDB_CLIENT_SECRET` empty. Restart R after
editing `.Renviron` and keep the file out of Git.

Use a publishable key or legacy `anon` key. The visitor’s access token
provides their identity; the project key identifies the application.
Server secret keys and `service_role` keys aren’t accepted. See
[Supabase API
keys](https://supabase.com/docs/guides/getting-started/api-keys).

## Prepare a table with user permissions

Run this example in the Supabase SQL editor, or use an existing table
with the grants and RLS policies your app needs:

``` sql
create table public.oauthdb_notes (
  id bigint generated always as identity primary key,
  owner_id uuid not null references auth.users(id),
  note text not null
);

alter table public.oauthdb_notes enable row level security;
revoke all on public.oauthdb_notes from anon, authenticated;
grant select on public.oauthdb_notes to authenticated;

create policy "Visitors read their own notes"
  on public.oauthdb_notes for select to authenticated
  using ((select auth.uid()) = owner_id);
```

Add rows in the SQL editor using the UUIDs of two existing project users
as `owner_id`. Sign in as each user to verify that they see only their
own rows. An empty result can mean that RLS allows no matching rows.

Supabase OAuth scopes such as `openid`, `profile` and `email` control
identity information, not table access. Apply grants and RLS to exposed
tables. You can also restrict a policy to your app with
`auth.jwt() ->> 'client_id'`. See [OAuth tokens and
RLS](https://supabase.com/docs/guides/auth/oauth-server/token-security).

## A complete Shiny app

Save this as `example.R`, then run `source("example.R")`:

After signing in, click **Load rows**. The app starts its workers once
and stops them at shutdown.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

project_url <- Sys.getenv("OAUTHDB_SUPABASE_URL")

client <- oauth_db_supabase_client(
  url = project_url,
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
  auth <- oauth_module_server(
    "auth",
    client,
    auto_redirect = FALSE,
    async = TRUE
  )

  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  supabase <- oauth_db_supabase_api(
    auth$connection,
    url = project_url,
    api_key = Sys.getenv("OAUTHDB_SUPABASE_KEY")
  )

  query_task <- oauth_db_task(supabase, method = "select")

  observeEvent(input$load, {
    query_task$invoke("oauthdb_notes", order = "id.asc", limit = 20L)
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

# Open the app in your regular browser at its registered redirect URI.
```

shinyOAuth handles sign-in and token renewal. Supabase supplies refresh
tokens without an `offline_access` scope. The Data API helper waits for
sign-in, then uses the visitor’s current access token.

## Use an existing third-party identity provider

A project configured to trust a [third-party
provider](https://supabase.com/docs/guides/auth/third-party/overview)
can use that provider’s authorization directly. Register the Shiny app
with the provider and configure the JWT claims required by your Supabase
integration. A provider enabled only as a Supabase social-login option
does not establish direct Data API trust for that provider’s tokens.

Replace the app’s client with your existing shinyOAuth client, or pass
`provider` and `scopes` explicitly:

``` r

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_SUPABASE_ISSUER")
)

client <- oauth_db_supabase_client(
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  provider = provider,
  scopes = c("openid", "profile", "email")
)
```

The Data API client stays the same. Native Supabase Auth uses UUID
subjects with `auth.uid()`; external providers may use other subject
formats, so write their policies against the appropriate verified JWT
claims.

## Functions, schemas and writes

Use `schema = "reporting"` to select another schema exposed by the Data
API. The signed-in user’s role still needs schema and object privileges.

``` r

# Call an existing database function with the visitor's permissions.
total <- supabase$rpc("note_total", list(category = "work"))

# A write requires grants and an RLS policy permitting updates.
response <- supabase$request(
  "oauthdb_notes",
  method = "PATCH",
  query = list(id = "eq.42"),
  body = list(note = "Reviewed"),
  prefer = "return=representation",
  raw = TRUE
)
```

`select()` returns one page; use `limit`, `offset` and a deterministic
order to fetch more. The [PostgREST
guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.md)
covers filters, embedded resources, counts and result types. The project
must expose a function before `rpc()` can call it; this client does not
execute arbitrary SQL.

Reads can refresh and retry once after HTTP 401; writes and POST
function calls don’t retry automatically. Results are discarded after
sign-out or account changes. See
[`?oauth_db_supabase_api`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md)
for request options.
