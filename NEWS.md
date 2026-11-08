# shinyOAuthDB 0.0.0.9000

* Check CrateDB row-count limits before numeric conversion so counts above
  `2^53` cannot round into the supported range.

* Reject malformed BigQuery and ClickHouse dates, including invalid calendar
  dates and trailing text, while preserving nulls and typed empty results.

* Use the published relay port in generated local PostgreSQL and StarRocks
  apps, independent of argument line breaks in the Docker app templates.

* Convert CrateDB query results to data frames once, while retaining cell
  validation for raw results and execution counts.

* Reject malformed BigQuery Boolean, floating-point and timestamp results,
  including nested values, instead of silently introducing missing data.
  Preserve SQL NULLs and valid floating-point NaN and infinity values.

* Return the complete CrateDB SQL endpoint from services-mode demos so
  `demo$url` can be passed directly to `oauth_db_cratedb_api()`.

* Prevent libcurl from replaying PostgREST, OpenSearch, ClickHouse and CrateDB
  writes after a reused connection drops its response. Apply the existing
  libSQL protection through the shared HTTP transport.

* Reject Snowflake ODBC protocol overrides before acquiring a token or opening
  a native connection, preserving the driver's HTTPS default.

* Require token-based password authentication over verified TLS for Azure
  PostgreSQL. Disable GSS encryption and reject native authentication/TLS
  overrides. This helper now requires RPostgres linked to libpq 16 or later.

* Reject incomplete BigQuery dataset listings when the API reports unreachable
  locations, including on later result pages.

* Restore services-mode OAuth options and revoke its PostgREST HTTP exception
  when stopping through `oauth_db_demo(action = "stop")`. Retained handles
  recognize the shutdown, and failed Docker cleanup remains retryable.

* Launch the documented apps with `runApp(..., launch.browser = FALSE)`
  and explain that OAuth sign-in needs a regular browser. Keep the README's
  follow-up links in a short Learn more section.

* Add `oauth_db_demo(action = "services")` to start Docker infrastructure
  and return settings for an app running in the current R session. The
  README example now starts PostgreSQL and PostgREST itself, works without
  a native database driver, and stops its services when Shiny stops.

* Keep the README app focused on sign-in and a PostgreSQL query. Ship that
  minimal example in the package with Docker run instructions. Runnable
  demos keep their styled UI.

* Use `alice` / `alice` and `bob` / `bob` for demo sign-in, with explicit
  username/password tables. Remove "Your" from cloud demo titles and keep
  sign-in guidance in sync with completed queries and warehouse selection.

* Give all local and cloud demos a responsive bslib layout, with sign-in
  controls, visible example queries/requests and platform-specific connection
  details. Local R and cloud apps require bslib 0.9.0 or later.

* Clarify each local demo's purpose, demo accounts and expected data access.
  Show editing and restart commands in the console, and let users retry a
  failed write check without losing the Shiny session.

* Keep cloud drafts in a persistent directory per platform. Back to setup
  now offers a settings menu without discarding the client registration.
  Cloud apps explain their identity query and guide sign-in and query errors.

* Add a ClickHouse Cloud demo for a qualifying JWT service with Entra role
  mapping, an early readiness check and HTTPS SQL requests.

* Add a Redshift cloud demo using Entra JWTs and IAM Identity Center, with
  a readiness check and explicit resource/scope guidance.

* Add an Azure PostgreSQL cloud demo with Entra user/group-role mapping,
  a trusted CA bundle and RPostgres connections.

* Add an Azure SQL cloud demo with Entra database-principal and networking
  guidance, and separate local Shiny and database ports.

* Add a Snowflake cloud demo with custom integration instructions, matching
  OAuth/SQL roles and explicit warehouse selection.

* Add a BigQuery cloud demo with Web OAuth registration guidance, query
  project/location settings and a maximum bytes billed limit.

* Add a guided Fabric cloud demo with Entra registration help, editable SQL
  app files and an explicit query button. Cloud drafts are now isolated by
  platform and use platform-specific secret environment variables.

* Add `oauth_db_cloud_demo("databricks")`, a `cli` console guide that prepares
  an editable local Shiny app, supports public and confidential OAuth app
  registrations, and explains why Free Edition lacks its registration path.
* Add `$warehouses()` to the Databricks API client, with paginated discovery
  using the signed-in visitor's authorization.

* Add `app = "local"` to `oauth_db_demo()`: keep the database and sign-in
  services in Docker and run an editable Shiny app with your local R library.
  The default continues to run the app in Docker.

* Extend `oauth_db_demo()` with DuckDB Quack, libSQL, CrateDB and OpenSearch.
  Each includes browser sign-in, server-validated tokens and sample data;
  the apps also demonstrate database rejection of writes.

* Add `oauth_db_demo()` to launch packaged PostgreSQL, PostgREST, Trino and
  StarRocks Docker demos with sign-in and sample data, without a checkout.
* Keep one PostgreSQL example in the README and add a pkgdown website with
  database guides, OAuth registration instructions and local demo help.

* Add `oauth_db_libsql_api()` for SQL queries and statements against libSQL
  and compatible Turso HTTPS endpoints. Supports bound parameters, exact
  64-bit integers, blobs and mixed SQLite types. Each operation uses a fresh
  stream and connection; SQL is never retried after a lost response or 401.
  Includes a real libSQL/JWT/TLS fixture and provider compatibility guidance.
* Add `oauth_db_cratedb_api()` for CrateDB's JWT-authenticated HTTPS SQL
  interface, positional parameters and exact BIGINT/NUMERIC results. Tokens
  are renewed before requests, and SQL submissions are never replayed.
* Add `oauth_db_opensearch_api()` for Query DSL, aggregations, SQL plugin
  queries and native JSON requests with a visitor's current bearer token.
  Preserves nested results and metadata, rejects incomplete searches, and
  includes a native OpenSearch Security JWT/TLS permission fixture.
* Add `oauth_db_duckdb()` for DBI and dbplyr queries against OAuth-enabled
  DuckDB Quack servers. Connections use TLS by default and are replaced when
  access tokens rotate; sign-out and session end shut down their private
  in-memory DuckDB instances.
* Add `oauth_db_clickhouse_api()` for JWT-authenticated HTTPS queries and
  statements. Supports native typed parameters, exact integers and decimals,
  metadata, and list columns. SQL submissions are never replayed automatically.
* Add `oauth_db_starrocks()` for DBI queries through StarRocks JWT
  authentication and MySQL Connector/ODBC. Temporary token files are removed
  after connection opening; account and username changes replace connections.
* Add `oauth_db_postgrest_api()` for tables, views, functions, and native
  PostgREST requests with each visitor's current token. Reads support filters,
  schema selection, pagination, and a single 401 refresh retry. Writes and
  POST function calls are not replayed automatically.
* Require shinyOAuth 0.7.0 and httr2 1.2.0.
* Add `oauth_db_postgres()` for self-hosted PostgreSQL 18 with native OAuth
  on Linux/libpq 18, a Docker/Keycloak playground, and a separate browser
  integration workflow that exercises database grants and row policies.
* Add connection helpers for Azure SQL, Fabric SQL, Databricks SQL,
  Snowflake, Redshift, Trino, and Azure PostgreSQL. Query with DBI or dbplyr;
  helpers reuse connections and call the driver's cleanup method when the
  authorization or session ends. Retained Databricks handles can keep their
  copied tokens; call the helper before each operation.
* Add `oauth_db_bigquery_client()` for Google sign-in and
  `oauth_db_bigquery_api()` for GoogleSQL queries. The query client returns
  data frames and supports named parameters.
* Add `oauth_db_fabric_api()` and `oauth_db_databricks_api()` to call
  fabricQueryR and brickster functions with the user's credentials.
  Fabric resource objects can use the same sign-in for later methods.
* Add Microsoft, Databricks, and Snowflake sign-in presets. Existing
  shinyOAuth clients can also be used.
* Replace the earlier source and operation API with Shiny reactive code
  and database functions. See the [migration notes](docs/migration.md).
* Add a guide for each source, with sign-in setup and a complete app.
