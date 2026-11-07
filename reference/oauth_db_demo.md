# Run a local database OAuth demo

Start a database and Keycloak sign-in using Docker, with a small Shiny
app running either in Docker or in a local R process. The installed
package includes the configuration, accounts and sample data; no source
checkout or cloud account is needed.

## Usage

``` r
oauth_db_demo(
  database = c("postgres", "postgrest", "trino", "starrocks", "duckdb", "libsql",
    "cratedb", "opensearch"),
  action = c("start", "stop", "files"),
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

- path:

  Directory for the demo files. Defaults to a database-specific
  directory in R's user cache. Existing demo files are kept so you can
  edit the app or configuration. An unrelated nonempty directory is
  refused.

- launch_browser:

  Open the app in your browser once it is ready.

- build:

  Build Docker images before starting. Set to `FALSE` to reuse images
  from a previous successful build.

- app:

  Where to run the Shiny app: `"docker"` (the default) supplies its R
  environment and drivers, or `"local"` uses your installed R packages.
  Local mode creates an editable app under `local-app/<database>/` in
  `path`.

## Value

Invisibly, the directory containing the demo configuration.

## Details

Install and start Docker with Linux containers and Docker Compose v2.
The first build downloads images, R packages and pinned package sources
from GitHub. PostgreSQL also compiles its native OAuth runtime. Allow
several minutes and a few GB of disk space. StarRocks uses amd64 images
and needs about 4 GB of Docker memory; other architectures need
emulation. DuckDB installs a matching R client and Quack extensions; the
client compiles from source if a Linux binary isn't available.
OpenSearch needs about 2 GB of Docker memory for its database container.

Open `http://localhost:18100` and sign in as `alice` with password
`alice`, or `bob` with password `bob`. Keycloak uses a generated test
certificate at `https://localhost:18443`; your browser may ask you to
accept it for this local demo.

Run one demo at a time: they share the same loopback ports. All accounts
are public demo accounts. Containers bind browser ports to loopback
only. Clicking **Stop demo**, or interrupting the foreground R call,
removes the demo's containers and volumes. The copied files and cached
images stay. A separate R session can use `action = "stop"` after a
forced exit.

To edit an example, first use `action = "files"`, edit the returned
directory, then call with the same `path`. `app.R` in the selected
database's subdirectory is the Shiny app. Stop the demo before
rebuilding.

## Run and edit the app locally

Use `app = "local"` to keep the database and sign-in services in Docker
while running Shiny in a separate R process on your computer. This uses
your R library and watches the copied `local-app/<database>/app.R` for
changes. Save the file and reload the browser to try your edits.
Existing app files are preserved. Local and Docker modes have separate
default cache directories.

Local mode requires callr and bslib 0.9.0 or later. Trino also needs
RTrino; StarRocks needs odbc and MySQL Connector/ODBC with its OpenID
Connect plugin; DuckDB needs a client matching the demo server (DuckDB
1.5.4) and installs its matching Quack/httpfs extensions. PostgreSQL's
native client requires Linux and shinyOAuthDB/RPostgres built against
the same shared libpq 18. Use the PostgREST demo for local editing on
Windows or macOS without a database driver.

The launcher copies the demo's public CA certificate and trusts it only
inside the local app process. It does not change your certificate store
or the parent R session's TLS settings. Local mode requires Compose
2.24.4 or later and publishes its database endpoint on loopback port
19444.

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
} # }
```
