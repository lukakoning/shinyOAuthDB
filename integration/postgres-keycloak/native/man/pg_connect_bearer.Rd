\name{pg_connect_bearer}
\alias{pg_connect_bearer}
\title{Open an integration DBI connection with an existing bearer token}
\usage{
pg_connect_bearer(token, issuer, scope, host, port, dbname, user,
  sslmode = "verify-full", sslrootcert = NULL, connect_timeout = 5L)
}
\arguments{
\item{token}{Already acquired raw bearer token, without its Bearer prefix.}
\item{issuer}{Exact HTTPS issuer identifier configured on the PostgreSQL server.}
\item{scope}{Distinct OAuth scopes separated by single spaces.}
\item{host, port, dbname, user}{Explicit TCP target, database and database role.}
\item{sslmode}{Must be \code{"verify-full"}.}
\item{sslrootcert}{Database TLS CA certificate path, or NULL for libpq defaults.}
\item{connect_timeout}{Whole connection timeout in seconds, at least two.}
}
\value{An ordinary RPostgres PqConnection, managed through DBI.}
\description{
Linux/libpq 18 integration fixture that supplies an explicit existing token
through a temporary native libpq hook while RPostgres opens the connection.
It does not acquire or refresh tokens or validate JWT claims. The server
validator validates the token and authorizes the database role.
}
\details{
Use only in the disposable image with libpq built without its device flow and
without the optional libpq-oauth module. Reconnects and cloning are unsupported:
discard a broken connection and acquire a fresh credential for a new opening.
Only single-threaded synchronous connection opening is supported. The hook is
restored on normal return and R error/interrupt unwind. This package is not a
production dependency of shinyOAuthDB.
}
