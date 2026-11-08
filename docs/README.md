# Documentation for contributors

The [package website](https://lukakoning.github.io/shinyOAuthDB/) contains
the user documentation. Start with the [README](../README.md) for a local
PostgreSQL app or choose a source guide below. This directory holds
contributor notes; pkgdown builds separately into `_site/`.

| Source | Guide |
| --- | --- |
| Self-hosted PostgreSQL | [Native OAuth and Docker playground](../vignettes/postgres.Rmd) |
| Azure SQL and SQL Server | [DBI and dbplyr queries](../vignettes/azure-sql.Rmd) |
| Microsoft Fabric | [SQL, platform functions, and Lakehouse objects](../vignettes/fabric.Rmd) |
| Databricks | [SQL warehouses and brickster](../vignettes/databricks.Rmd) |
| Snowflake | [Snowflake sign-in and DBI](../vignettes/snowflake.Rmd) |
| Google BigQuery | [GoogleSQL queries](../vignettes/bigquery.Rmd) |
| Amazon Redshift | [Redshift queries with DBI](../vignettes/redshift.Rmd) |
| Trino and Starburst Enterprise | [RTrino and DBI queries](../vignettes/trino.Rmd) |
| Azure PostgreSQL | [RPostgres connections](../vignettes/azure-postgres.Rmd) |
| Oracle Database | [OAuth access tokens and Oracle ODBC](../vignettes/oracle.Rmd) |
| SAP HANA and HANA Cloud | [JWT access tokens and SAP HANA ODBC](../vignettes/hana.Rmd) |
| Oracle REST Data Services | [JWT-protected HTTP resources](../vignettes/oracle-ords.Rmd) |
| PostgREST | [PostgreSQL tables and functions over HTTP](../vignettes/postgrest.Rmd) |
| Supabase | [Data API queries and Supabase OAuth sign-in](../vignettes/supabase.Rmd) |
| StarRocks | [JWT authentication and DBI queries](../vignettes/starrocks.Rmd) |
| ClickHouse | [HTTPS SQL queries with JWT](../vignettes/clickhouse.Rmd) |
| DuckDB | [Remote Quack servers and OAuth](../vignettes/duckdb.Rmd) |
| libSQL and Turso | [Remote SQLite SQL and compatible tokens](../vignettes/libsql.Rmd) |
| CrateDB | [JWT-authenticated HTTP SQL](../vignettes/cratedb.Rmd) |
| OpenSearch | [Search, SQL and user permissions](../vignettes/opensearch.Rmd) |

[Getting started](../vignettes/getting-started.Rmd) explains the package,
walks through the README app, and covers OAuth settings, sessions and demos.
The source guides above cover each database's setup and query methods.
The [playground](../playground/README.md) contains runnable scripts.

For existing apps and package development:

- [Migration from earlier development versions](migration.md)
- [Development and checks](development.md)
- [Validation record](validation.md)
- [Snowflake backend decision](snowflake-backends.md)
- [Backend research notes](backend-candidates.md)
- [Supabase backend decision](supabase-backend.md)
- [Oracle backend decision](oracle-backend.md)
- [SAP HANA backend decision](hana-backend.md)
- [Guided cloud demos: implementation notes](cloud-demos.md)
