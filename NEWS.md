# shinyOAuthDB 0.0.0.9000

* Add `oauth_db_libsql_api()` for SQL queries and statements against libSQL
  and compatible Turso HTTPS endpoints. Supports bound parameters, exact
  64-bit integers, blobs and mixed SQLite types. Each operation uses a fresh
  stream and connection; SQL is never retried after a lost response or 401.
  Includes a real libSQL/JWT/TLS fixture and provider compatibility guidance.
* Add `oauth_db_cratedb_api()` for CrateDB's JWT-authenticated HTTPS SQL
  interface, positional parameters and exact BIGINT/NUMERIC results. Tokens
  are renewed before requests, and SQL submissions are never replayed.
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
