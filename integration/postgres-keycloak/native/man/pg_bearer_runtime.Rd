\name{pg_bearer_runtime}
\alias{pg_bearer_runtime}
\title{Inspect the integration bearer-hook runtime}
\usage{pg_bearer_runtime()}
\value{A list with \code{libpq_version}, \code{same_libpq},
\code{default_hook} and \code{active}. No credentials are included.}
\description{
Checks that this integration helper and the already-loaded RPostgres library
resolve the same libpq authentication-hook symbol and that libpq's major
version is 18. It makes no database or OAuth request.
}
