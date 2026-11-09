# Run from the repository root with Docker and RPostgres linked to libpq >= 16.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-authorization.R")
library(testthat)

check_cockroachdb <- function() {
  docker <- function(args) processx::run("docker", args)$stdout
  image <- "shinyoauthdb-cockroachdb-fixture:25.4.0"
  docker(c("build", "-t", image, "integration/cockroachdb-jwt"))
  directory <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  fixture <- tempfile("cockroachdb-", tmpdir = directory)
  dir.create(fixture)
  fixture <- normalizePath(fixture, winslash = "/", mustWork = TRUE)
  stopifnot(identical(dirname(fixture), directory))
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  container <- paste0(
    "shinyoauthdb-cockroachdb-",
    Sys.getpid(),
    "-",
    sample.int(1e6, 1L)
  )
  docker(c(
    "run",
    "--detach",
    "--name",
    container,
    "--publish",
    "127.0.0.1::26257",
    "--mount",
    paste0("type=bind,source=", fixture, ",target=/out"),
    image
  ))
  on.exit(
    try(docker(c("rm", "--force", "--volumes", container)), silent = TRUE),
    add = TRUE,
    after = FALSE
  )
  sql <- function(statement) {
    docker(c(
      "exec",
      container,
      "/cockroach/cockroach",
      "sql",
      "--certs-dir=/certs",
      "--host=localhost",
      "--execute",
      statement
    ))
  }
  ready <- FALSE
  for (attempt in seq_len(60L)) {
    if (!inherits(try(sql("SELECT 1"), silent = TRUE), "try-error")) {
      ready <- TRUE
      break
    }
    Sys.sleep(0.5)
  }
  if (!ready) {
    logs <- processx::run("docker", c("logs", container))
    cat(logs$stdout, logs$stderr)
    stop("CockroachDB fixture did not start.")
  }
  mapping <- trimws(docker(c("port", container, "26257/tcp")))
  stopifnot(grepl("^127[.]0[.]0[.]1:[0-9]+$", mapping))
  port <- as.integer(sub("^.*:", "", mapping))
  ca <- file.path(fixture, "ca.crt")
  key <- openssl::rsa_keygen()
  base64url <- function(value) {
    chartr("+/", "-_", sub("=+$", "", openssl::base64_encode(value)))
  }
  public <- as.list(key)$pubkey$data
  jwks <- jsonlite::toJSON(
    list(
      keys = list(list(
        kty = "RSA",
        kid = "fixture",
        use = "sig",
        alg = "RS256",
        n = base64url(public$n),
        e = base64url(public$e)
      ))
    ),
    auto_unbox = TRUE
  )
  jwt <- function(
    user = "alice",
    audience = "shiny-cockroachdb",
    issuer = "https://issuer.example.invalid",
    lifetime = 3600,
    signing_key = key
  ) {
    now <- as.numeric(Sys.time())
    header <- base64url(charToRaw('{"alg":"RS256","kid":"fixture"}'))
    payload <- base64url(charToRaw(jsonlite::toJSON(
      list(
        iss = issuer,
        sub = user,
        aud = audience,
        iat = floor(now),
        exp = floor(now) + lifetime,
        jti = base64url(openssl::rand_bytes(8))
      ),
      auto_unbox = TRUE
    )))
    message <- paste(header, payload, sep = ".")
    paste(
      message,
      base64url(openssl::signature_create(
        charToRaw(message),
        openssl::sha256,
        signing_key
      )),
      sep = "."
    )
  }
  setup <- paste0(
    "SET CLUSTER SETTING diagnostics.reporting.enabled = false; ",
    "SET CLUSTER SETTING server.jwt_authentication.enabled = true; ",
    "SET CLUSTER SETTING server.jwt_authentication.issuers.configuration = 'https://issuer.example.invalid'; ",
    "SET CLUSTER SETTING server.jwt_authentication.audience = 'shiny-cockroachdb'; ",
    "SET CLUSTER SETTING server.jwt_authentication.claim = 'sub'; ",
    "SET CLUSTER SETTING server.jwt_authentication.jwks = '",
    jwks,
    "'; ",
    "CREATE DATABASE reporting; CREATE USER alice; CREATE USER bob; ",
    "CREATE TABLE reporting.public.alice_rows (value STRING); ",
    "CREATE TABLE reporting.public.bob_rows (value STRING); ",
    "INSERT INTO reporting.public.alice_rows VALUES ('alice only'); ",
    "INSERT INTO reporting.public.bob_rows VALUES ('bob only'); ",
    "GRANT CONNECT ON DATABASE reporting TO alice, bob; ",
    "GRANT SELECT ON reporting.public.alice_rows TO alice; ",
    "GRANT SELECT ON reporting.public.bob_rows TO bob;"
  )
  for (statement in strsplit(setup, ";", fixed = TRUE)[[1L]]) {
    if (nzchar(trimws(statement))) sql(statement)
  }
  withr::local_envvar(c(PGSERVICE = NA, PGSERVICEFILE = NA))
  connect <- function(value, user = "alice", host = "127.0.0.1") {
    .odb_backend_cockroachdb(
      function() value,
      host,
      "reporting",
      function() user,
      port,
      ca,
      5L,
      list()
    )
  }
  test_that("real CockroachDB verifies JWT identity and SQL grants", {
    alice <- connect(jwt())
    on.exit(DBI::dbDisconnect(alice), add = TRUE)
    bob <- connect(jwt("bob"), "bob")
    on.exit(DBI::dbDisconnect(bob), add = TRUE)
    expect_identical(
      DBI::dbGetQuery(alice, "SELECT current_user AS name")$name,
      "alice"
    )
    expect_identical(
      DBI::dbGetQuery(bob, "SELECT current_user AS name")$name,
      "bob"
    )
    expect_identical(
      DBI::dbGetQuery(alice, "SELECT * FROM alice_rows")$value,
      "alice only"
    )
    expect_identical(
      DBI::dbGetQuery(bob, "SELECT * FROM bob_rows")$value,
      "bob only"
    )
    expect_identical(
      DBI::dbGetQuery(
        alice,
        "SELECT value FROM alice_rows WHERE value = $1",
        params = list("alice only")
      )$value,
      "alice only"
    )
    expect_identical(
      dplyr::collect(dplyr::filter(
        dplyr::tbl(alice, "alice_rows"),
        value == "alice only"
      ))$value,
      "alice only"
    )
    expect_error(
      DBI::dbGetQuery(alice, "SELECT * FROM bob_rows"),
      "privilege|permission"
    )
    expect_error(
      DBI::dbGetQuery(bob, "SELECT * FROM alice_rows"),
      "privilege|permission"
    )
    expect_error(
      DBI::dbExecute(alice, "INSERT INTO alice_rows VALUES ('denied')"),
      "privilege|permission"
    )
    expect_error(connect(jwt(audience = "other")))
    expect_error(connect(jwt(issuer = "https://untrusted.example.invalid")))
    expect_error(connect(jwt(lifetime = -60)))
    expect_error(connect(jwt(signing_key = openssl::rsa_keygen())))
    expect_error(connect(jwt(), "bob"))
    withr::with_envvar(c(PGHOSTADDR = "127.0.0.1"), {
      expect_error(
        connect(jwt(), host = "wrong.example.invalid"),
        "certificate|match|verify"
      )
    })
    fallback <- jwt("password_only", audience = "other")
    sql(paste0("CREATE USER password_only WITH PASSWORD '", fallback, "'"))
    expect_error(connect(fallback, "password_only"))
  })
  retained <- NULL
  test_that("real CockroachDB follows token, user and authorization changes", {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      auth$token(auth$make_token(jwt()))
      role <- shiny::reactiveVal("alice")
      con <- oauth_db_cockroachdb(
        auth$connection,
        "127.0.0.1",
        "reporting",
        role,
        port = port,
        sslrootcert = ca
      )
      first <- con()
      expect_identical(
        DBI::dbGetQuery(first, "SELECT current_user AS name")$name,
        "alice"
      )
      expect_identical(con(), first)
      auth$token(auth$make_token(jwt()))
      second <- con()
      expect_false(DBI::dbIsValid(first))
      expect_identical(
        DBI::dbGetQuery(second, "SELECT current_user AS name")$name,
        "alice"
      )
      DBI::dbDisconnect(second)
      third <- con()
      expect_identical(
        DBI::dbGetQuery(third, "SELECT current_user AS name")$name,
        "alice"
      )
      auth$token(auth$make_token(jwt("bob")))
      role("bob")
      fourth <- con()
      expect_false(DBI::dbIsValid(third))
      expect_identical(
        DBI::dbGetQuery(fourth, "SELECT current_user AS name")$name,
        "bob"
      )
      expect_error(
        DBI::dbGetQuery(fourth, "SELECT * FROM alice_rows"),
        "privilege|permission"
      )
      auth$current(FALSE)
      session$flushReact()
      expect_false(DBI::dbIsValid(fourth))
      expect_error(con(), class = "shiny.silent.error")
      auth$current(TRUE)
      retained <<- con()
    })
    expect_false(DBI::dbIsValid(retained))
  })
  cat(
    "CockroachDB v25.4.0 native JWT checks passed. Browser sign-in and CockroachDB Cloud were not tested.\n"
  )
}

check_cockroachdb()
