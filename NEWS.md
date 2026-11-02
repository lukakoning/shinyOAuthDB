# shinyOAuthDB 0.0.0.9000

* Require shinyOAuth 0.7.0.
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
