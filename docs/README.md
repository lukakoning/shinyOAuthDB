# Documentation

Choose your source in [Getting started](../vignettes/getting-started.Rmd).
Each guide includes sign-in setup, a complete Shiny app, and further examples:

| Source | Guide |
| --- | --- |
| Azure SQL and SQL Server | [Entra sign-in, DBI, and dbplyr](../vignettes/azure-sql.Rmd) |
| Microsoft Fabric | [SQL, platform functions, and resource objects](../vignettes/fabric.Rmd) |
| Databricks | [SQL warehouses and brickster](../vignettes/databricks.Rmd) |
| Snowflake | [OAuth roles and DBI](../vignettes/snowflake.Rmd) |
| Google BigQuery | [Google sign-in and GoogleSQL](../vignettes/bigquery.Rmd) |
| Amazon Redshift | [Delegated tokens and ODBC](../vignettes/redshift.Rmd) |
| Trino and Starburst Enterprise | [OIDC sign-in and RTrino](../vignettes/trino.Rmd) |
| Azure PostgreSQL | [Entra sign-in and RPostgres](../vignettes/azure-postgres.Rmd) |

[Authentication and sessions](../vignettes/authorization.Rmd) covers existing
logins, multiple accounts, and cached results. Runnable scripts are in the
[playground](../playground/README.md).

For existing apps and package development:

- [Migration from earlier development versions](migration.md)
- [Development and checks](development.md)
- [Validation record](validation.md)
- [Snowflake backend decision: why skiLift is deferred](snowflake-backends.md)
- [Additional OAuth backends](backend-candidates.md)
