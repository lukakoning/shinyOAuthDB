# Run in the integration image against the freshly installed shinyOAuthDB.
library(shinyOAuthDB)

fail <- function(expr, pattern = NULL) {
  condition <- tryCatch(
    {
      force(expr)

      NULL
    },
    error = identity
  )
  stopifnot(inherits(condition, "error"))
  if (!is.null(pattern)) {
    stopifnot(grepl(pattern, conditionMessage(condition), fixed = TRUE))
  }

  invisible(condition)
}

ns <- asNamespace("shinyOAuthDB")
pg_bearer_runtime <- get(".odb_postgres_runtime", ns)
pg_connect_bearer <- get(".odb_postgres_connect_bearer", ns)

with_hook <- function(callback, expected = metadata) {
  .Call(
    get("C_pg_with_bearer", ns),
    "synthetic-test-bearer",
    expected,
    callback
  )
}

probe <- function(
  expected = metadata,
  discovery = discovery_url,
  scope = "postgresql",
  second = FALSE
) {
  .Call(get("C_pg_bearer_probe", ns), expected, discovery, scope, second)
}

metadata <- c(
  "https://localhost:18443/realms/shinyoauthdb",
  "postgresql",
  "127.0.0.1",
  "1",
  "fixture",
  "alice",
  "shinyOAuthDB-external-bearer-only"
)
discovery_url <- paste0(metadata[[1L]], "/.well-known/openid-configuration")

restored <- function() {
  runtime <- pg_bearer_runtime()

  stopifnot(
    runtime$same_libpq,
    runtime$default_hook,
    !runtime$active,
    runtime$libpq_version >= 180000L,
    runtime$libpq_version < 190000L
  )
}

restored()
local({
  stage <- tempfile("native-hook-fixture-")
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  source <- file.path("integration", "postgres-keycloak", "native", "tests")
  build <- function(name, libpq = FALSE) {
    stopifnot(file.copy(file.path(source, paste0(name, ".c")), stage))
    flags <- if (libpq) c(
      PKG_CPPFLAGS = trimws(processx::run("pkg-config", c("--cflags", "libpq"))$stdout),
      PKG_LIBS = trimws(processx::run("pkg-config", c("--libs", "libpq"))$stdout)) else character()
    result <- processx::run(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", paste0(name, ".c")),
      wd = stage, env = c("current", flags), error_on_status = FALSE)
    if (result$status != 0L) stop("Native fixture compilation failed: ", result$stderr, call. = FALSE)
    normalizePath(file.path(stage, paste0(name, .Platform$dynlib.ext)))
  }
  foreign_path <- build("foreign-hook", libpq = TRUE)
  mismatch_path <- build("mismatched-runtime")
  foreign <- dyn.load(foreign_path, local = TRUE)
  on.exit(dyn.unload(foreign_path), add = TRUE, after = FALSE)
  setter <- getNativeSymbolInfo("fixture_foreign_hook", PACKAGE = foreign)
  current <- getNativeSymbolInfo("fixture_foreign_current", PACKAGE = foreign)
  local({
    stopifnot(isTRUE(.Call(setter, TRUE)))
    on.exit(.Call(setter, FALSE), add = TRUE)
    callback_ran <- FALSE
    fail(with_hook(function() { callback_ran <<- TRUE }), "Another libpq OAuth hook")
    fail(pg_bearer_runtime(), "Another libpq OAuth hook")
    stopifnot(!callback_ran, isTRUE(.Call(current)))
  })
  restored()
  mismatch <- dyn.load(mismatch_path, local = TRUE)
  on.exit(dyn.unload(mismatch_path), add = TRUE, after = FALSE)
  fail(.Call(get("C_pg_bearer_runtime", ns), mismatch_path), "same shared libpq hook")
  fail(.Call(get("C_pg_bearer_runtime", ns), file.path(stage, "not-loaded.so")), "not already loaded")
  restored()
})
stopifnot(identical(with_hook(function() 17L), 17L))
restored()
fail(
  with_hook(function() stop("intentional callback failure")),
  "intentional callback failure"
)
restored()
fail(with_hook(function() with_hook(function() NULL)), "Nested bearer-hook")
restored()
interrupted <- tryCatch(
  with_hook(function() stop(structure(list(message = "test interrupt", call = NULL),
    class = c("interrupt", "condition")))),
  interrupt = identity
)
stopifnot(inherits(interrupted, "interrupt"))
restored()

# A supplied token is usable only by the configured connection, issuer and
# requested scopes, and can be consumed only once in an opening scope.
stopifnot(with_hook(function() probe()) == 1L)
restored()
fail(
  with_hook(function() {
    stopifnot(probe() == 1L)

    stop("intentional failure after bearer delivery")
  }),
  "intentional failure after bearer delivery"
)
restored()
stopifnot(with_hook(function() probe()) == 1L)
restored()
stopifnot(
  with_hook(function() {
    probe(
      discovery = "https://different.invalid/.well-known/openid-configuration"
    )
  }) <
    0L
)
restored()
stopifnot(with_hook(function() probe(scope = "other-scope")) < 0L)
restored()
stopifnot(with_hook(function() probe(
  discovery = "https://localhost:18443/.well-known/oauth-authorization-server/realms/shinyoauthdb"
)) == 1L)
restored()
other_user <- metadata
other_user[[6L]] <- "bob"
stopifnot(with_hook(function() probe(expected = other_user)) < 0L)
restored()
stopifnot(with_hook(function() probe(second = TRUE)) == 1L)
restored()

for (issuer in c("https://localhost:18443/", "https://localhost:18443/realms/shinyoauthdb/")) {
  expected <- metadata
  expected[[1L]] <- issuer
  discovery <- paste0(issuer, "/.well-known/openid-configuration")
  stopifnot(with_hook(function() probe(expected, discovery), expected) == 1L)
  restored()

  different <- expected
  different[[1L]] <- sub("/$", "", issuer)
  stopifnot(with_hook(function() probe(different, discovery), expected) < 0L)
  restored()
}

# Validation must not mutate/install the native hook on malformed arguments.
args <- list(
  token = "synthetic-test-bearer",
  issuer = metadata[[1L]],
  scope = "postgresql",
  host = "127.0.0.1",
  port = 1L,
  dbname = "fixture",
  user = "alice",
  connect_timeout = 2L
)
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
bad$options <- list(sslmode = "require")
fail(do.call(pg_connect_bearer, bad), "cannot be overridden")
restored()

# Exercise RPostgres's real error/unwind path against an unavailable TCP port.
# No bearer reaches a server, no provider request/device prompt is possible.
fail(do.call(pg_connect_bearer, args))
restored()
cat(
  "shinyOAuthDB: native restoration, connection isolation and validation checks passed.\n"
)
