# Getting started

With shinyOAuthDB, people sign in to your app and query a database with
their own permissions. You can use DBI, dbplyr, or the platform’s R
package to read the data.

## Try an app on your computer

Install the package, then start Docker with Linux containers and run:

``` r

shinyOAuthDB::oauth_db_demo()
```

The package starts PostgreSQL, Keycloak sign-in and a small Shiny app
with demo accounts. Open `http://localhost:18100` when ready. See [Local
Docker
demos](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.md)
for the passwords, other databases, editing the app and cleanup. No
repository clone or cloud account is needed.

To run an editable app in local R with its database in Docker, try
`shinyOAuthDB::oauth_db_demo("postgrest", app = "local")`. The [local
app
guide](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html#run-and-edit-shiny-in-local-r)
lists the required R packages and explains how to edit and reload the
app.

For your own data, choose a guide below. Each starts with the database’s
purpose, the settings you need and a complete app, then explains the
server and advanced configuration.

## Choose your source

| Source | What you can do |
|----|----|
| [Self-hosted PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.md) | Try the Docker/Keycloak demo or connect your own PostgreSQL 18 server |
| [PostgREST](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.md) | Read PostgreSQL tables and call functions over HTTP |
| [StarRocks](https://lukakoning.github.io/shinyOAuthDB/articles/starrocks.md) | Query with JWT authentication and MySQL Connector/ODBC |
| [ClickHouse](https://lukakoning.github.io/shinyOAuthDB/articles/clickhouse.md) | Run SQL over HTTPS with a visitor token |
| [CrateDB](https://lukakoning.github.io/shinyOAuthDB/articles/cratedb.md) | Run SQL over HTTPS with JWT authentication and database user privileges |
| [DuckDB](https://lukakoning.github.io/shinyOAuthDB/articles/duckdb.md) | Query a remote Quack server with OAuth access tokens |
| [libSQL and Turso](https://lukakoning.github.io/shinyOAuthDB/articles/libsql.md) | Run SQLite SQL over HTTPS with compatible user tokens |
| [OpenSearch](https://lukakoning.github.io/shinyOAuthDB/articles/opensearch.md) | Search indexes, run aggregations and query the SQL plugin |
| [Azure SQL and SQL Server](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.md) | Query with DBI or dbplyr |
| [Microsoft Fabric](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.md) | Query SQL endpoints, read OneLake tables, and call fabricQueryR functions |
| [Databricks](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.md) | Query SQL warehouses and call brickster functions |
| [Snowflake](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.md) | Query with a user’s Snowflake account and role |
| [Google BigQuery](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.md) | Run GoogleSQL and get data frames |
| [Amazon Redshift](https://lukakoning.github.io/shinyOAuthDB/articles/redshift.md) | Query Redshift with DBI |
| [Trino and Starburst Enterprise](https://lukakoning.github.io/shinyOAuthDB/articles/trino.md) | Query a self-hosted Trino or Starburst Enterprise cluster with RTrino and DBI |
| [Azure PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.md) | Query with RPostgres and DBI |

## Install shinyOAuthDB

``` r

install.packages("remotes")
remotes::install_github("lukakoning/shinyOAuthDB")
```

This also installs shinyOAuth. Your source may need another R package or
a database driver; its guide lists those requirements.

For locally browsable guides, add `build_vignettes = TRUE` to the GitHub
installation call. The Docker demos supply their own R environment and
database drivers.

## Run your first app

Start with the guide for your data source. You’ll register an OAuth
application, which gives your Shiny app a client ID and client secret.
The registration also records the redirect URI: the address where the
browser returns after sign-in. The examples use `http://localhost:8100`.

Use [OAuth
setup](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.md)
for the registration steps and terminology. Save the credentials in a
local `.Renviron` file as shown in the guide and restart R. Copy the
example into `app.R`, replace the connection settings, and run
`shiny::runApp(port = 8100)` from that directory.

The people signing in need access to the data. OAuth consent lets the
app act on their behalf; their database permissions determine what they
can read.

## How it fits into Shiny

Create the sign-in `client` outside `server()`. Inside `server()`,
[`oauth_module_server()`](https://lukakoning.github.io/shinyOAuth/reference/oauth_module_server.html)
handles each visitor’s login. Pass its `auth$connection` function to a
database helper or API client.

A DBI helper returns a function such as `con`. In a render or reactive
expression, call `connection <- con()` before using DBI or dbplyr. The
helper reuses that visitor’s connection. When their authorization or
Shiny session ends, it stops returning the connection and calls the
driver’s cleanup method. A saved Databricks connection can retain its
token; call `con()` before each operation rather than keeping the native
handle.

API clients either offer query methods, such as BigQuery’s `$query()`,
or call functions from the platform’s R package through `$call()`.

For an existing login, several accounts, or query results saved between
button clicks, see [Authentication and
sessions](https://lukakoning.github.io/shinyOAuthDB/articles/authorization.md).
