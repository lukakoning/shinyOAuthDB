# Run the real SingleStore driver against disposable JWT users over verified TLS.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
inside <- identical(Sys.getenv("OAUTHDB_SINGLESTORE_IN_CONTAINER"), "1")
if (inside) {
  library <- tempfile("singlestore-r-library-")
  dir.create(library)
  .libPaths(c(library, .libPaths()))
  status <- system2(
    file.path(R.home("bin"), "R"),
    c(
      "CMD",
      "INSTALL",
      paste0("--library=", library),
      "/package.tar.gz"
    )
  )
  if (status != 0L) {
    stop("Could not install the package under test.")
  }
  library(shinyOAuthDB)
} else {
  pkgload::load_all(quiet = TRUE)
}
source("tests/testthat/helper-authorization.R")
library(testthat)

check_singlestore <- function() {
  if (!inside) {
    docker <- function(args) {
      result <- processx::run("docker", args, error_on_status = FALSE)
      if (result$status != 0L) {
        stop(result$stdout, result$stderr, call. = FALSE)
      }
      result$stdout
    }
    parent <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
    fixture <- tempfile("shinyOAuthDB-singlestore-", tmpdir = parent)
    dir.create(fixture)
    fixture <- normalizePath(fixture, winslash = "/", mustWork = TRUE)
    stopifnot(identical(dirname(fixture), parent))
    on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
    python <- Sys.getenv("OAUTHDB_SINGLESTORE_PYTHON", "python3")
    processx::run(python, c("integration/singlestore-jwt/prepare.py", fixture))
    file.copy(
      file.path("integration/singlestore-jwt", c("start.sh", "init.sql")),
      fixture
    )
    container <- paste0(
      "shinyoauthdb-singlestore-",
      Sys.getpid(),
      "-",
      sample.int(1e6, 1L)
    )
    image <- paste0(
      "ghcr.io/singlestore-labs/singlestoredb-dev@sha256:",
      "2f181587a74b63a83e7dbd46b02e9dce031b8cacf1f5651bff297b2d8c87df37"
    )
    docker(c(
      "run",
      "--detach",
      "--name",
      container,
      "--cpus=4",
      "--memory=6g",
      "--publish",
      "127.0.0.1::3306",
      "--mount",
      paste0("type=bind,source=", fixture, ",target=/fixture,readonly"),
      "--env",
      "ROOT_PASSWORD=singlestore-fixture-only",
      "--env",
      "INIT_SQL=/fixture/init.sql",
      "--env",
      "SINGLESTORE_SET_GLOBAL_JWKS_ENDPOINT=http://127.0.0.1:18082/jwks.json",
      "--env",
      "SINGLESTORE_SET_GLOBAL_JWKS_USERNAME_FIELD=sub",
      "--entrypoint",
      "bash",
      image,
      "/fixture/start.sh"
    ))
    on.exit(
      try(docker(c("rm", "--force", "--volumes", container)), silent = TRUE),
      add = TRUE,
      after = FALSE
    )
    ready <- FALSE
    for (attempt in seq_len(180L)) {
      probe <- processx::run(
        "docker",
        c("exec", container, "test", "-f", "/server/.ready"),
        error_on_status = FALSE
      )
      if (probe$status == 0L) {
        ready <- TRUE
        break
      }
      Sys.sleep(0.5)
    }
    if (!ready) {
      stop("SingleStore fixture did not start.\n", docker(c("logs", container)))
    }
    runner <- "shinyoauthdb-singlestore-runner:1"
    docker(c("build", "--tag", runner, "integration/singlestore-jwt"))
    archive <- pkgbuild::build(
      Sys.getenv("OAUTHDB_SINGLESTORE_SOURCE", "."),
      dest_path = fixture,
      vignettes = FALSE,
      manual = FALSE
    )
    root <- normalizePath(".", winslash = "/", mustWork = TRUE)
    output <- docker(c(
      "run",
      "--rm",
      paste0("--network=container:", container),
      "--mount",
      paste0("type=bind,source=", fixture, ",target=/fixture,readonly"),
      "--mount",
      paste0(
        "type=bind,source=",
        root,
        ",target=/workspace/shinyOAuthDB,readonly"
      ),
      "--mount",
      paste0("type=bind,source=", archive, ",target=/package.tar.gz,readonly"),
      "--env",
      "OAUTHDB_SINGLESTORE_IN_CONTAINER=1",
      runner,
      "Rscript",
      "tools/check-singlestore.R"
    ))
    cat(output)
    return(invisible(NULL))
  }
  fixture <- "/fixture"
  port <- 3306L
  driver <- list.files(
    "/opt/singlestore-driver",
    "libssodbcw[.]so$",
    recursive = TRUE,
    full.names = TRUE
  )
  stopifnot(length(driver) == 1L)
  tokens <- jsonlite::read_json(file.path(fixture, "tokens.json"))
  admin_sql <- function(sql) {
    DBI::dbExecute(admin, sql)
  }
  admin <- DBI::dbConnect(
    odbc::odbc(),
    driver = driver,
    SERVER = "127.0.0.1",
    PORT = port,
    UID = "root",
    PWD = "singlestore-fixture-only",
    SSLCA = file.path(fixture, "ca.pem"),
    SSLVERIFY = 1L,
    BROWSER_SSO = 0L,
    USE_MYCNF = 0L,
    AUTO_RECONNECT = 0L
  )
  on.exit(DBI::dbDisconnect(admin), add = TRUE)
  make <- function(auth, ..., server = "127.0.0.1", ca = "ca.pem") {
    oauth_db_singlestore(
      auth,
      server,
      "oauth_fixture",
      ssl_ca = file.path(fixture, ca),
      driver = driver,
      port = port,
      ...
    )
  }
  test_that("SingleStore JWT users retain separate database grants and native SQL results", {
    odb_test_domain(function(session) {
      a <- odb_test_authorization(session)
      b <- odb_test_authorization(session, id = "B")
      a$token(a$make_token(tokens$alice))
      b$token(b$make_token(tokens$bob))
      selected <- shiny::reactiveVal(a$connection)
      con <- make(selected)
      first <- con()
      expect_match(
        DBI::dbGetQuery(first, "SELECT CURRENT_USER() AS u")$u,
        "^alice@"
      )
      expect_identical(
        DBI::dbGetQuery(
          first,
          "SELECT label FROM alice_rows WHERE id = ?",
          params = list(1L)
        )$label,
        "alice-visible"
      )
      expect_identical(
        dplyr::collect(dplyr::filter(
          dplyr::tbl(first, "alice_rows"),
          id == 1L
        ))$label,
        "alice-visible"
      )
      expect_identical(
        nrow(dplyr::collect(dplyr::filter(
          dplyr::tbl(first, "alice_rows"),
          id < 0L
        ))),
        0L
      )
      expect_error(DBI::dbGetQuery(first, "SELECT * FROM bob_rows"))
      expect_error(DBI::dbExecute(
        first,
        "INSERT INTO alice_rows VALUES (3, 'forbidden')"
      ))
      selected(b$connection)
      second <- con()
      expect_false(DBI::dbIsValid(first))
      expect_match(
        DBI::dbGetQuery(second, "SELECT CURRENT_USER() AS u")$u,
        "^bob@"
      )
      expect_identical(
        DBI::dbGetQuery(second, "SELECT label FROM bob_rows")$label,
        "bob-visible"
      )
      expect_error(DBI::dbGetQuery(second, "SELECT * FROM alice_rows"))
      selected(NULL)
      expect_error(con(), class = "shiny.silent.error")
      expect_false(DBI::dbIsValid(second))
    })
  })
  test_that("SingleStore reconnects with a renewed token without replaying completed queries", {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      auth$token(auth$make_token(tokens$alice))
      con <- make(auth$connection)
      queries <- 0L
      result <- shiny::reactive({
        connection <- con()
        queries <<- queries + 1L
        DBI::dbGetQuery(connection, "SELECT label FROM alice_rows")
      })
      expect_identical(result()$label, "alice-visible")
      connection <- con()
      id <- DBI::dbGetQuery(connection, "SELECT CONNECTION_ID() AS id")$id
      auth$token(auth$make_token(tokens$renewed))
      session$flushReact()
      expect_identical(queries, 1L)
      admin_sql(paste("KILL CONNECTION", id))
      renewed <- con()
      expect_false(identical(connection, renewed))
      expect_identical(
        DBI::dbGetQuery(renewed, "SELECT label FROM alice_rows")$label,
        "alice-visible"
      )
      expect_identical(queries, 1L)
      session$close()
      expect_false(DBI::dbIsValid(renewed))
    })
  })
  test_that("SingleStore refuses expired, foreign and mismatched JWT credentials", {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      for (name in c("expired", "wrong_signature", "wrong_audience")) {
        auth$token(auth$make_token(tokens[[name]]))
        con <- make(auth$connection)
        expect_error(con())
      }
      auth$token(auth$make_token(tokens$alice))
      mismatched <- make(auth$connection, user = "bob")
      expect_error(mismatched())
    })
  })
  test_that("SingleStore requires a trusted TLS chain and the correct server hostname", {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      auth$token(auth$make_token(tokens$alice))
      untrusted <- make(auth$connection, ca = "wrong-ca.pem")
      expect_error(untrusted())
      wrong_host <- make(auth$connection, server = "localhost")
      expect_error(wrong_host())
    })
  })
}

check_singlestore()
