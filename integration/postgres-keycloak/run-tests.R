# Opt-in container entrypoint. Installs the mounted source revision into an
# isolated library; neither host R libraries nor an existing database are used.
local({
  if (!identical(Sys.getenv("OAUTHDB_POSTGRES_INTEGRATION"), "1")) {
    stop(
      "Run this opt-in suite through integration/postgres-keycloak/run-integration.ps1 or run-integration.sh.",
      call. = FALSE
    )
  }

  repository <- normalizePath(".", winslash = "/", mustWork = TRUE)
  fixture <- file.path(repository, "integration", "postgres-keycloak")
  authentication <- Sys.getenv(
    "OAUTHDB_SHINYOAUTH_SOURCE",
    "/workspace/shinyOAuth"
  )
  sources <- c(authentication, repository, file.path(fixture, "native"))
  for (path in sources) {
    if (!file.exists(file.path(path, "DESCRIPTION"))) {
      stop(
        "A source checkout is missing; mount shinyOAuth beside shinyOAuthDB.",
        call. = FALSE
      )
    }
  }

  dependencies <- c(
    "DBI",
    "RPostgres",
    "chromote",
    "callr",
    "curl",
    "httr2",
    "jsonlite",
    "testthat",
    "withr"
  )
  missing <- dependencies[
    !vapply(dependencies, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    stop(
      "Missing integration dependencies: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  dependency_libraries <- .libPaths()
  integration_library <- tempfile("shinyOAuthDB-postgres-library-")
  dir.create(integration_library)
  on.exit(unlink(integration_library, recursive = TRUE), add = TRUE)

  # Native compilation writes src/*.o and src/*.so. Keep the bind-mounted
  # checkout read-only and compile an independent writable copy.
  native_stage <- tempfile("shinyOAuthDB-postgres-native-")
  dir.create(native_stage)
  on.exit(unlink(native_stage, recursive = TRUE), add = TRUE)
  if (!file.copy(sources[[3L]], native_stage, recursive = TRUE)) {
    stop("Staging the native fixture for compilation failed.", call. = FALSE)
  }

  sources[[3L]] <- file.path(native_stage, "native")
  .libPaths(c(integration_library, dependency_libraries))
  library_path <- paste(.libPaths(), collapse = .Platform$path.sep)
  Sys.setenv(R_LIBS = library_path, R_LIBS_USER = library_path)
  r_binary <- file.path(R.home("bin"), "R")
  for (path in sources) {
    result <- processx::run(
      r_binary,
      c(
        "CMD",
        "INSTALL",
        "--no-byte-compile",
        paste0("--library=", integration_library),
        path
      ),
      echo = TRUE,
      error_on_status = FALSE
    )

    if (result$status != 0L) {
      stop("Installing an integration source package failed.", call. = FALSE)
    }
  }
  for (package in c("shinyOAuth", "shinyOAuthDB", "pgBearerHook")) {
    resolved <- normalizePath(
      find.package(package),
      winslash = "/",
      mustWork = TRUE
    )
    expected <- normalizePath(
      file.path(integration_library, package),
      winslash = "/",
      mustWork = TRUE
    )
    if (!identical(resolved, expected)) {
      stop(
        "Tests did not resolve the freshly installed source package.",
        call. = FALSE
      )
    }
  }

  ca <- Sys.getenv("OAUTHDB_TEST_PG_CA", "/fixtures/tls/ca-cert.pem")
  if (!file.exists(ca)) {
    stop(
      "The fixture CA is missing; start the Compose TLS service first.",
      call. = FALSE
    )
  }

  issuer <- Sys.getenv(
    "OAUTHDB_TEST_ISSUER",
    "https://localhost:18443/realms/shinyoauthdb"
  )
  discovery <- paste0(issuer, "/.well-known/openid-configuration")
  ready <- FALSE
  deadline <- Sys.time() + 120

  while (!ready && Sys.time() < deadline) {
    ready <- tryCatch(
      {
        response <- httr2::request(discovery) |>
          httr2::req_options(cainfo = ca) |>
          httr2::req_timeout(3) |>
          httr2::req_perform()

        identical(httr2::resp_body_json(response)$issuer, issuer)
      },

      error = function(e) FALSE
    )

    if (!ready) Sys.sleep(1)
  }

  if (!ready) {
    stop("The exact HTTPS Keycloak issuer did not become ready.", call. = FALSE)
  }

  admin <- tryCatch(
    DBI::dbConnect(
      RPostgres::Postgres(),
      host = Sys.getenv("OAUTHDB_TEST_PG_HOST", "localhost"),
      port = as.integer(Sys.getenv("OAUTHDB_TEST_PG_PORT", "5432")),
      dbname = Sys.getenv("OAUTHDB_TEST_PG_DBNAME", "oauthdb_fixture"),
      user = "postgres",
      password = Sys.getenv("OAUTHDB_TEST_PG_ADMIN_PASSWORD"),
      sslmode = "verify-full",
      sslrootcert = ca,
      connect_timeout = 5L
    ),
    error = function(e) {
      stop("The isolated PostgreSQL TLS fixture is unavailable.", call. = FALSE)
    }
  )

  on.exit(if (DBI::dbIsValid(admin)) DBI::dbDisconnect(admin), add = TRUE)
  version <- DBI::dbGetQuery(
    admin,
    "SELECT current_setting('server_version_num')::integer AS version"
  )$version
  if (version < 180000L || version >= 190000L) {
    stop("This pinned fixture requires PostgreSQL 18.", call. = FALSE)
  }

  tryCatch(
    DBI::dbExecute(admin, "LOAD 'pg_oidc_validator'"),
    error = function(e) {
      stop(
        "The PostgreSQL OAuth validator could not be loaded; rebuild the fixture image.",
        call. = FALSE
      )
    }
  )

  DBI::dbDisconnect(admin)

  if ("--playground" %in% commandArgs(trailingOnly = TRUE)) {
    app <- new.env(parent = globalenv())
    sys.source(file.path(fixture, "helper-browser.R"), envir = app)
    sys.source(file.path(fixture, "fixture-app.R"), envir = app)
    config <- app$postgres_browser_config(Sys.getenv(
      "OAUTHDB_TEST_CLIENT_ID",
      "shiny-db"
    ))
    message(
      "PostgreSQL OAuth playground: ",
      config$origin,
      "; users alice / bob, passwords alice-fixture-password / bob-fixture-password."
    )

    app$postgres_browser_run_app(config)
  } else {
    withCallingHandlers(
      sys.source(
        file.path(fixture, "native", "tests", "regression.R"),
        envir = new.env(parent = globalenv())
      ),
      warning = function(w) {
        stop("The native regression emitted a warning.", call. = FALSE)
      }
    )

    browser_results <- testthat::test_dir(
      fixture,
      reporter = "summary",
      stop_on_failure = TRUE,
      load_helpers = TRUE
    )
    counts <- as.data.frame(browser_results)
    message(
      "PostgreSQL/Keycloak integration: ",
      sum(counts$passed),
      " passing assertions; ",
      sum(counts$failed),
      " failures; ",
      sum(counts$error),
      " errors; ",
      sum(counts$warning),
      " warnings; ",
      sum(counts$skipped),
      " skips."
    )

    if (
      any(
        counts$failed > 0 | counts$error | counts$warning > 0 | counts$skipped
      )
    ) {
      stop(
        "Integration requires zero failures, errors, warnings and skips.",
        call. = FALSE
      )
    }
  }
})
