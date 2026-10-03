# Run by R CMD check, or Rscript /fixtures/native/tests/regression.R in the
# isolated integration image after R CMD INSTALL /fixtures/native.
library(pgBearerHook)

fail <- function(expr, pattern = NULL) {
  condition <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(condition, "error"))
  if (!is.null(pattern)) stopifnot(grepl(pattern, conditionMessage(condition), fixed = TRUE))
  invisible(condition)
}
ns <- asNamespace("pgBearerHook")
with_hook <- function(callback, expected = metadata) {
  .Call(get("C_pg_with_bearer", ns), "synthetic-test-bearer", expected, callback)
}
probe <- function(expected = metadata, discovery = discovery_url,
                  scope = "postgresql", second = FALSE) {
  .Call(get("C_pg_bearer_probe", ns), expected, discovery, scope, second)
}
metadata <- c("https://localhost:18443/realms/shinyoauthdb", "postgresql",
              "127.0.0.1", "1", "fixture", "alice",
              "pgBearerHook-external-bearer-only")
discovery_url <- paste0(metadata[[1L]], "/.well-known/openid-configuration")
restored <- function() {
  runtime <- pg_bearer_runtime()
  stopifnot(runtime$same_libpq, runtime$default_hook, !runtime$active,
            runtime$libpq_version >= 180000L, runtime$libpq_version < 190000L)
}

restored()
stopifnot(identical(with_hook(function() 17L), 17L))
restored()
fail(with_hook(function() stop("intentional callback failure")), "intentional callback failure")
restored()
fail(with_hook(function() with_hook(function() NULL)), "Nested bearer-hook")
restored()

# A supplied token is usable only by the configured connection, issuer and
# requested scopes, and can be consumed only once in an opening scope.
stopifnot(with_hook(function() probe()) == 1L)
restored()
fail(with_hook(function() {
  stopifnot(probe() == 1L)
  stop("intentional failure after bearer delivery")
}), "intentional failure after bearer delivery")
restored()
stopifnot(with_hook(function() probe()) == 1L)
restored()
stopifnot(with_hook(function() probe(discovery = "https://different.invalid/.well-known/openid-configuration")) < 0L)
restored()
stopifnot(with_hook(function() probe(scope = "other-scope")) < 0L)
restored()
other_user <- metadata
other_user[[6L]] <- "bob"
stopifnot(with_hook(function() probe(expected = other_user)) < 0L)
restored()
stopifnot(with_hook(function() probe(second = TRUE)) == 1L)
restored()

# Validation must not mutate/install the native hook on malformed arguments.
args <- list(token = "synthetic-test-bearer", issuer = metadata[[1L]],
             scope = "postgresql", host = "127.0.0.1", port = 1L,
             dbname = "fixture", user = "alice", connect_timeout = 2L)
bad <- args
bad$token <- "Bearer synthetic-test-bearer"
fail(do.call(pg_connect_bearer, bad), "raw bearer token")
restored()
bad <- args
bad$issuer <- "http://localhost:18443/realms/shinyoauthdb"
fail(do.call(pg_connect_bearer, bad), "HTTPS issuer")
restored()
bad <- args
bad$scope <- "postgresql  another"
fail(do.call(pg_connect_bearer, bad), "single spaces")
restored()
bad <- args
bad$sslmode <- "require"
fail(do.call(pg_connect_bearer, bad), "verify-full")
restored()

# Exercise RPostgres's real error/unwind path against an unavailable TCP port.
# No bearer reaches a server, no provider request/device prompt is possible.
fail(do.call(pg_connect_bearer, args))
restored()
cat("pgBearerHook: native restoration, connection isolation and validation checks passed.\n")
