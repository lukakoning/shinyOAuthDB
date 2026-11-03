# Native PostgreSQL OAuth regression tests

The bearer-token adapter lives in shinyOAuthDB's `src/postgres.c` and
`R/backend__postgres.R`. This directory contains the native regression checks
run against the freshly installed package inside the
[PostgreSQL/Keycloak environment](../README.md).

The checks verify that the scoped libpq hook restores its previous state
after success, failure and nested calls. They also reject a mismatched
connection, issuer or scope and repeated token delivery. A real failed
RPostgres connection exercises native cleanup through R's error path.

Use the integration runner to execute them; the normal package tests also
check public helper validation and connection lifetime without Docker.
See the [PostgreSQL guide](../../../vignettes/postgres.Rmd) for build details.
