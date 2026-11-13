# shinyOAuthDB 0.0.0.9000

* Require promises 1.4.0 or later so nested task callbacks retain their Shiny
  session. The local minimum-version suite now includes background task tests.

* Add `oauth_db_task()` for background database and API operations with mirai.
  Acquire credentials asynchronously in the owning Shiny session, open and
  close a separate worker connection, and hide results when authorization
  changes. Complete examples use background fetching and install missing
  dependencies before loading packages.

* Add `oauth_db_neo4j_api()` for Cypher queries with each visitor's access
  token and Neo4j database roles. Includes parameter binding, graph results,
  update counters, session isolation and a complete Shiny setup guide.

* Add Azure Cosmos DB for NoSQL with `oauth_db_cosmos_client()` and
  `oauth_db_cosmos_api()`. Queries and point reads use each visitor's Entra
  token and data-plane permissions, with partition keys, continuation pages,
  token renewal and session isolation. Includes a complete setup guide;
  live tenant consent and Cosmos DB authentication remain unvalidated.

* Add `oauth_db_mongodb()` for MongoDB workforce OIDC using the official
  PyMongo driver through reticulate. Includes per-visitor clients, verified
  TLS, token replacement, queries, aggregations and database commands, with
  Extended JSON results and a complete Shiny setup guide.

* Add `oauth_db_dremio()` for Flight SQL DBI connections through adbi and
  Apache Arrow's ADBC driver using each visitor's OAuth access token.
  Require verified TLS and reopen connections after token renewal. Include
  a complete Shiny guide and native Flight SQL transport checks; live
  Dremio Enterprise and Cloud compatibility remains unverified.

* Add Google Cloud SQL IAM database authentication for PostgreSQL,
  with a Google sign-in preset, per-visitor DBI connections, verified TLS,
  current credentials on reconnection, and a setup guide.

* Add `oauth_db_cockroachdb()` for self-hosted and cloud CockroachDB clusters
  configured for JWT SQL authentication. Includes verified TLS, per-user DBI
  connections, credential rotation and a complete Shiny setup guide.

* Add `oauth_db_azure_mysql()` for Azure Database for MySQL Flexible Server
  through MariaDB Connector/ODBC and each visitor's Entra access token.
  Includes the Microsoft `mysql` sign-in preset, verified TLS, connection
  replacement after token renewal, and a complete Shiny setup guide.
  Local protocol checks cover the real driver; live Azure remains unverified.

* Add `oauth_db_singlestore()` for SingleStore and Helios SQL connections
  using visitor JWT access tokens through SingleStore ODBC. Require verified
  TLS and reconnect with current credentials through the session helper.
  Includes a complete setup guide and a real database integration check.

* Add `oauth_db_elasticsearch_api()` for per-visitor searches, SQL and ES|QL
  using external JWT access tokens and optional realm client authentication.
  Includes a setup guide, native JSON requests, and a real Elasticsearch JWT,
  document/field permissions and TLS integration check.

* Keep bearer tokens out of the stored calls in native ODBC connection errors,
  while preserving the driver's error class and message.

* Reopen Azure PostgreSQL connections on the next access after token changes,
  avoiding repeated reconnect failures with an obsolete password. Token
  renewal does not replay completed reactive queries.

* Add `oauth_db_hana()` for SAP HANA and HANA Cloud SQL connections using
  visitor JWT access tokens through SAP HANA ODBC. Require JWT authentication
  and verified TLS, and obtain current tokens when reopening connections.
  Includes a complete Shiny setup guide; live SAP compatibility remains unverified.

* Add Salesforce user sign-in, CRM SOQL queries and Data Cloud (Data 360)
  SQL queries through Query Connect API. Includes object discovery, bound
  SQL parameters, polling, pagination and a complete Shiny setup guide.
  Registrations must issue JWT-based access tokens for named users.

* Add `oauth_db_supabase_api()` for Supabase tables, views and functions using
  project publishable keys and each visitor's access token. Add
  `oauth_db_supabase_client()` for the project's OAuth server, with a setup
  guide covering native sign-in, third-party providers and row-level security.

* Generalize `oauth_db_oracle()` to database-trusted OAuth JWTs, including
  configured OCI IAM OAuth and Keycloak direct-logon integrations. Add
  `authorization_model = "end_user"` to verify Oracle Deep Data Security
  token context and reopen sessions when renewed tokens carry new claims.
  Oracle operation scopes are now checked literally for every provider.

* Add `oauth_db_oracle_ords_api()` for protected ORDS collections and JSON
  resources with per-visitor OAuth tokens. Preserve native pages, enforce
  session isolation and retry only safe reads. Add generic OIDC and
  provider-specific setup guides.

* Install the checkout's source archive in Docker demo browser checks and
  verify its hash in the running app container before testing sign-in.

* Decode Turso's null-valued floating-point results as `NaN`, preserving SQL
  NULL values and rejecting malformed float cells in ordinary and raw results.

* Allow Azure PostgreSQL to share a Microsoft sign-in client with other
  services by requesting its explicit delegated scope in mixed-service clients.

* Add `oauth_db_oracle()` for Oracle Database configured for Microsoft Entra
  authentication. Connections use Oracle ODBC, verified TCPS and each visitor's
  access token. Temporary token files are removed after connection opening;
  the helper requires Oracle to confirm token authentication. Includes a
  setup guide for self-hosted and hosted databases.

* Document ODBC as the Fabric backend for dbplyr's SQL Server translations,
  and explain ADBC driver setup, result lifetime and numeric conversion.

* Apply ODBC connection-string validation only to Fabric's ODBC backend,
  allowing literal ADBC driver paths. Reject URI overrides for either backend.

* Reopen Fabric ADBC connections with a current token on access after token
  renewal, without replaying completed reactive queries. ODBC connections
  continue to reuse valid database sessions across ordinary token renewal.

* Close ADBC connections and their outstanding DBI or Arrow results when the
  authorization changes, permissions are lost, or the Shiny session ends.

* Return CrateDB's internal byte columns as numbers, including nulls and empty
  results, and reject values outside the signed byte range in scalar and array
  responses.

* Decode libSQL REAL values as doubles regardless of JSON number notation,
  while retaining exact integer cells and large affected-row counts.

* Retain the selected Microsoft resource's default consent scopes when using
  `token_targets = list()`. Multiple resources need named targets or explicit
  scopes instead of silently requesting only sign-in permissions.

* Refuse to restart an active services-mode demo at the same database and path,
  preventing competing handles from stopping its containers or restoring its
  OAuth options prematurely.

* Parse API responses and HTTP error diagnostics as literal JSON so response
  bodies cannot trigger local-file reads or additional HTTP requests.

* Refresh the Docker demo runtime to include the current transport protections,
  corrected local app ports, strict date decoding and exact row-count checks.

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
