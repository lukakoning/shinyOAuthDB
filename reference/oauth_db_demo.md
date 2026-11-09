# Run a local database OAuth demo

Try a Shiny app where visitors sign in and query a database with their
own permissions. The package supplies a local database, Keycloak
sign-in, demo accounts and sample data through Docker. You can run the
app in Docker or local R without a cloud account or source checkout.

## Usage

``` r
oauth_db_demo(
  database = c("postgres", "postgrest", "trino", "starrocks", "duckdb", "libsql",
    "cratedb", "opensearch"),
  action = c("start", "stop", "files", "services"),
  path = NULL,
  launch_browser = interactive(),
  build = TRUE,
  app = c("docker", "local")
)
```

## Arguments

- database:

  Demo to run: `"postgres"` (the default), `"postgrest"`, `"trino"`,
  `"starrocks"`, `"duckdb"` (Quack), `"libsql"`, `"cratedb"`, or
  `"opensearch"`.

- action:

  `"start"` runs the demo until you stop it or interrupt R. `"stop"`
  removes its containers and data, including after a forced exit.
  `"files"` copies the configuration without starting Docker.
  `"services"` starts only the Docker services and returns settings for
  an app you run in the current R session; `app` is ignored in this
  mode.

- path:

  Directory for the demo files. Defaults to a database-specific
  directory in R's user cache. Existing demo files are kept so you can
  edit the app or configuration. An unrelated nonempty directory is
  refused.

- launch_browser:

  Open the app in your browser once it is ready. Services-only mode
  leaves browser launch to your app.

- build:

  Build Docker images before starting. Set to `FALSE` to reuse images
  from a previous successful build.

- app:

  Where to run the Shiny app: `"docker"` (the default) supplies its R
  environment and drivers, or `"local"` uses your installed R packages.
  Local mode creates an editable app under `local-app/<database>/` in
  `path`.

## Value

Invisibly, the directory containing the demo configuration. With
`action = "services"`, an environment containing `provider` (a
configured shinyOAuth provider), `url` (the local data endpoint),
`host`, `port`, `ca_bundle` (for HTTPS endpoints), `path` and a
[`stop()`](https://rdrr.io/r/base/stop.html) function instead.

## Details

Install and start Docker with Linux containers and Compose v2, then run
`oauth_db_demo()`. The first build needs internet access, several
minutes and a few GB of disk space.

Open `http://localhost:18100` in a regular browser. Sign in as `alice`
with password `alice`, or `bob` with password `bob`. Your browser may
ask you to accept Keycloak's local test certificate at
`https://localhost:18443`.

Run one demo at a time because they share ports. Click **Stop demo** or
interrupt R to remove the containers and sample data. Copied files and
cached images stay for later runs. After a forced exit, use
`action = "stop"` with the same database, `app` mode and `path`.

The accounts and passwords are public demo settings. For your own
deployment, follow the source's setup guide.

## Run and edit the app locally

Use `app = "local"` to run Shiny with your installed R packages while
Docker runs the database and sign-in service. Install callr and bslib
0.9.0 or later, plus the source's R client and database driver.
PostgREST works without a database driver and is a useful first option.

Trino needs RTrino. StarRocks needs odbc and MySQL Connector/ODBC with
its OpenID Connect plugin. DuckDB needs a matching client (1.5.4 for the
demo) and its Quack extensions. Native PostgreSQL needs Linux with
RPostgres and shinyOAuthDB linked to the same libpq 18.

Use `action = "files"` to copy the app, then edit
`local-app/<database>/app.R`. Start with the same `path`, save your
edits and reload the browser. Existing files are preserved; use a new
empty path for fresh templates.

Local mode needs Compose 2.24.4 or later. It trusts the demo certificate
only in the app process, leaving your certificate store unchanged.
StarRocks needs about 4 GB of Docker memory and amd64 support;
OpenSearch needs about 2 GB for its database container.

## Run your own app with Docker services

Use `action = "services"` to start the database and sign-in service,
then return to R without starting Shiny. This needs Compose 2.24.4 or
later. Pass the returned `provider` to `shinyOAuth::oauth_client()` and
`url` to the data helper. The PostgREST example works without a database
driver; native clients still need their usual drivers.

Keep the returned handle, such as `demo`, while your app runs. Register
`demo$stop` with
[`shiny::onStop()`](https://rdrr.io/pkg/shiny/man/onStop.html) or call
`demo$stop()` when finished. It removes containers and sample data and
restores local-development options. Reuse the handle until you stop it.

Browser sign-in uses HTTPS. Services-only PostgREST uses HTTP on
`127.0.0.1:19444`, allowed only while the demo is active. Other
endpoints use HTTPS; the handle's `ca_bundle` supplies their local
certificate.

## See also

[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md).

## Examples

``` r
if (FALSE) { # \dontrun{
oauth_db_demo()
oauth_db_demo("postgrest")
oauth_db_demo("trino")
oauth_db_demo("starrocks")
oauth_db_demo("duckdb")
oauth_db_demo("libsql")
oauth_db_demo("cratedb")
oauth_db_demo("opensearch")
oauth_db_demo(action = "stop")
path <- oauth_db_demo(action = "files")
# Edit a local R app backed by PostgreSQL and PostgREST in Docker:
path <- oauth_db_demo("postgrest", app = "local", action = "files")
file.edit(file.path(path, "local-app", "postgrest", "app.R"))
oauth_db_demo("postgrest", app = "local", path = path)
# Run your own app against PostgreSQL through PostgREST:
demo <- oauth_db_demo("postgrest", action = "services")
demo$provider
demo$url
demo$stop()
} # }
```
