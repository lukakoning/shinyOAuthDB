# shinyOAuthDB 0.0.0.9000

* Add Trino DBI connections through RTrino, using per-request user tokens
  and a username callback for the selected authorization.
* Add Redshift DBI connections using externally supplied user tokens through
  the AWS ODBC driver, with explicit token mode and verified TLS.
* Add a per-user BigQuery REST client with Google sign-in, named parameters,
  result paging, and token renewal through shinyOAuth.
* Require shinyOAuth 0.7.0 and use its released client and token interfaces.
* Connect Azure SQL, Fabric SQL, Databricks SQL, Snowflake, and Azure
  PostgreSQL to the signed-in user's authorization. Helpers return functions
  that provide DBI connections and handle reuse and cleanup.
* Add `oauth_db_fabric_api()` and `oauth_db_databricks_api()` for authenticated
  calls to fabricQueryR and brickster. Fabric resource objects retain a token
  callback for their workload methods.
* Keep OAuth client configuration optional: use the Microsoft, Databricks, or
  Snowflake presets, or supply an existing shinyOAuth client.
* Replace the earlier source and operation API with ordinary Shiny code and
  native database functions. See the [migration notes](docs/migration.md).
* Organize vignettes by source, each with sign-in setup and a complete app.
  Keep SQL and API examples for Fabric and Databricks in their source guides,
  with separate guides for getting started and advanced session behaviour.
