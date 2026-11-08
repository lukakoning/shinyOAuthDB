#' Run a local database OAuth demo
#'
#' Start a database and Keycloak sign-in using Docker, with a small Shiny app
#' running either in Docker or in a local R process.
#' The installed package includes the configuration, accounts and sample data;
#' no source checkout or cloud account is needed.
#'
#' @param database Demo to run: `"postgres"` (the default), `"postgrest"`,
#'   `"trino"`, `"starrocks"`, `"duckdb"` (Quack), `"libsql"`, `"cratedb"`,
#'   or `"opensearch"`.
#' @param action `"start"` runs the demo until you stop it or interrupt R.
#'   `"stop"` removes its containers and data, including after a forced exit.
#'   `"files"` copies the configuration without starting Docker.
#'   `"services"` starts only the Docker services and returns settings for
#'   an app you run in the current R session; `app` is ignored in this mode.
#' @param path Directory for the demo files. Defaults to a database-specific
#'   directory in R's user cache. Existing demo files are kept so you can edit
#'   the app or configuration. An unrelated nonempty directory is refused.
#' @param launch_browser Open the app in your browser once it is ready.
#'   Services-only mode leaves browser launch to your app.
#' @param build Build Docker images before starting. Set to `FALSE` to reuse
#'   images from a previous successful build.
#' @param app Where to run the Shiny app: `"docker"` (the default) supplies
#'   its R environment and drivers, or `"local"` uses your installed R packages.
#'   Local mode creates an editable app under `local-app/<database>/` in `path`.
#' @return Invisibly, the directory containing the demo configuration.
#'   With `action = "services"`, an environment containing `provider` (a
#'   configured shinyOAuth provider), `url` (the local data endpoint),
#'   `host`, `port`, `ca_bundle` (for HTTPS endpoints), `path` and a `stop()`
#'   function instead.
#' @details
#' Install and start Docker with Linux containers and Docker Compose v2.
#' The first build downloads images, R packages and pinned package sources
#' from GitHub. PostgreSQL also compiles its native OAuth runtime. Allow
#' several minutes and a few GB of disk space. StarRocks uses amd64 images
#' and needs about 4 GB of Docker memory; other architectures need emulation.
#' DuckDB installs a matching R client and Quack extensions; the client
#' compiles from source if a Linux binary isn't available.
#' OpenSearch needs about 2 GB of Docker memory for its database container.
#'
#' Open `http://localhost:18100` and sign in as `alice` with password
#' `alice`, or `bob` with password `bob`.
#' Keycloak uses a generated test certificate at `https://localhost:18443`;
#' your browser may ask you to accept it for this local demo.
#'
#' Run one demo at a time: they share the same loopback ports. All accounts
#' are public demo accounts. Containers bind browser ports to loopback only.
#' Clicking **Stop demo**, or interrupting the foreground R call, removes
#' the demo's containers and volumes. The copied files and cached images stay.
#' A separate R session can use `action = "stop"` after a forced exit.
#'
#' To edit an example, first use `action = "files"`, edit the returned
#' directory, then call with the same `path`. `app.R` in the selected
#' database's subdirectory is the Shiny app. Stop the demo before rebuilding.
#' @section Run and edit the app locally:
#' Use `app = "local"` to keep the database and sign-in services in Docker
#' while running Shiny in a separate R process on your computer. This uses
#' your R library and watches the copied `local-app/<database>/app.R` for
#' changes. Save the file and reload the browser to try your edits. Existing
#' app files are preserved. Local and Docker modes have separate default
#' cache directories.
#'
#' Local mode requires callr and bslib 0.9.0 or later. Trino also needs RTrino;
#' StarRocks needs odbc and MySQL Connector/ODBC with its OpenID Connect plugin;
#' DuckDB needs a client matching the demo server (DuckDB 1.5.4) and installs
#' its matching Quack/httpfs extensions. PostgreSQL's native client requires
#' Linux and shinyOAuthDB/RPostgres built against the same shared libpq 18.
#' Use the PostgREST demo for local editing on Windows or macOS without a
#' database driver.
#'
#' The launcher copies the demo's public CA certificate and trusts it only
#' inside the local app process. It does not change your certificate store
#' or the parent R session's TLS settings. Local mode requires Compose 2.24.4
#' or later and publishes its database endpoint on loopback port 19444.
#' @section Run your own app with Docker services:
#' Use `action = "services"` to start the database and sign-in infrastructure
#' without starting Shiny or blocking R. Use the returned `provider` in
#' `shinyOAuth::oauth_client()` and `url` in an API helper.
#' This mode needs Compose 2.24.4 or later but does not install or require
#' local database drivers. Native database clients still need their usual
#' runtime; PostgREST works in local R on Windows, macOS and Linux.
#'
#' Browser sign-in uses HTTPS. The returned provider uses Keycloak's HTTP
#' endpoints on loopback port 18080 for R's token, UserInfo and signing-key
#' requests. It retains the HTTPS issuer and validates signed ID tokens.
#' This avoids changing R's certificate store or curl settings. PostgREST's
#' services-only endpoint uses HTTP on `127.0.0.1:19444`, permitted only while
#' its demo handle is active. Other data endpoints retain HTTPS and supply
#' `ca_bundle` for clients that support custom certificate authorities.
#'
#' During this demo, shinyOAuth's host policy permits loopback hosts and
#' its loopback-only OIDC development option is enabled. `demo$stop()`
#' removes the containers and data and restores these options. Register
#' it with `shiny::onStop()` when your app starts. Services are also stopped
#' when the returned object is garbage collected or R exits. Run one demo
#' at a time, and stop it before starting another.
#' Using `action = "stop"` with the same database and `path` also retires
#' any services handle in the current R process and restores its options.
#' @examples
#' \dontrun{
#' oauth_db_demo()
#' oauth_db_demo("postgrest")
#' oauth_db_demo("trino")
#' oauth_db_demo("starrocks")
#' oauth_db_demo("duckdb")
#' oauth_db_demo("libsql")
#' oauth_db_demo("cratedb")
#' oauth_db_demo("opensearch")
#' oauth_db_demo(action = "stop")
#' path <- oauth_db_demo(action = "files")
#' # Edit a local R app backed by PostgreSQL and PostgREST in Docker:
#' path <- oauth_db_demo("postgrest", app = "local", action = "files")
#' file.edit(file.path(path, "local-app", "postgrest", "app.R"))
#' oauth_db_demo("postgrest", app = "local", path = path)
#' # Run your own app against PostgreSQL through PostgREST:
#' demo <- oauth_db_demo("postgrest", action = "services")
#' demo$provider
#' demo$url
#' demo$stop()
#' }
#' @seealso [oauth_db_postgres()], [oauth_db_postgrest_api()],
#'   [oauth_db_trino()], [oauth_db_starrocks()], [oauth_db_duckdb()],
#'   [oauth_db_libsql_api()], [oauth_db_cratedb_api()], [oauth_db_opensearch_api()].
#' @export
oauth_db_demo <- function(
  database = c(
    "postgres",
    "postgrest",
    "trino",
    "starrocks",
    "duckdb",
    "libsql",
    "cratedb",
    "opensearch"
  ),
  action = c("start", "stop", "files", "services"),
  path = NULL,
  launch_browser = interactive(),
  build = TRUE,
  app = c("docker", "local")
) {
  database <- match.arg(database)
  action <- match.arg(action)
  app <- match.arg(app)
  services <- action == "services"
  if (services) {
    app <- "local"
  }
  if (is.null(path)) {
    path <- file.path(
      tools::R_user_dir("shinyOAuthDB", "cache"),
      "demo",
      paste0(
        database,
        if (services) {
          "-services"
        } else if (app == "local") {
          "-local"
        }
      )
    )
  }
  .odb_string(path, "path")
  for (flag in list(launch_browser = launch_browser, build = build)) {
    if (!is.logical(flag) || length(flag) != 1L || is.na(flag)) {
      stop(
        "launch_browser and build must each be TRUE or FALSE.",
        call. = FALSE
      )
    }
  }
  source <- system.file("docker", package = "shinyOAuthDB", mustWork = TRUE)
  marker <- file.path(path, ".shinyOAuthDB-demo")
  if (action == "stop" && !file.exists(marker)) {
    stop(
      "No demo configuration at this path. Use the path from the launcher.",
      call. = FALSE
    )
  }
  if (!file.exists(marker)) {
    if (
      dir.exists(path) &&
        length(list.files(path, all.files = TRUE, no.. = TRUE))
    ) {
      stop("path must be empty or contain a shinyOAuthDB demo.", call. = FALSE)
    }
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
    files <- list.files(
      source,
      all.files = TRUE,
      no.. = TRUE,
      full.names = TRUE
    )
    if (!all(file.copy(files, path, recursive = TRUE))) {
      stop("Could not copy the demo configuration to path.", call. = FALSE)
    }
    writeLines(as.character(utils::packageVersion("shinyOAuthDB")), marker)
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (app == "local" && action != "stop" && !services) {
    .odb_demo_local_files(path, database)
  }
  if (action == "files") {
    .odb_demo_files_message(database, path, app)
    return(invisible(path))
  }
  if (app == "local" && action == "start") {
    .odb_demo_local_require(database)
  }
  docker <- .odb_demo_docker()
  project <- paste0(
    "shinyoauthdb-demo-",
    database,
    "-",
    substr(openssl::sha256(charToRaw(path)), 1L, 8L)
  )
  compose <- c(
    "compose",
    "--project-name",
    project,
    "--project-directory",
    path,
    "--file",
    file.path(path, "compose.yml"),
    "--file",
    file.path(path, paste0("compose.", database, ".yml"))
  )
  if (app == "local") {
    compose <- c(
      compose,
      "--file",
      file.path(path, "compose.local.yml"),
      "--file",
      file.path(path, database, "compose.local.yml")
    )
  }
  if (services) {
    override <- file.path(path, "compose.services.yml")
    if (!file.exists(override)) {
      stop(
        "These demo files predate services mode. Choose a new empty path.",
        call. = FALSE
      )
    }
    compose <- c(compose, "--file", override)
    backend_override <- file.path(path, database, "compose.services.yml")
    if (file.exists(backend_override)) {
      compose <- c(compose, "--file", backend_override)
    }
  }
  run <- function(args, check = TRUE) {
    .odb_demo_command(docker, c(compose, args), check)
  }
  cleanup <- function() {
    run(c("down", "--volumes", "--remove-orphans"), check = FALSE)
  }
  if (action == "stop") {
    if (cleanup() != 0L) {
      stop(
        "Docker could not stop the demo; see its output above.",
        call. = FALSE
      )
    }
    state <- .odb_demo_services[[.odb_demo_services_key(path, database)]]
    if (!is.null(state)) {
      .odb_demo_services_release(state)
    }
    cli::cli_alert_success(
      "Demo services and sample data removed. Your app files are kept at {.path {path}}.",
      wrap = TRUE
    )
    return(invisible(path))
  }
  run(c("config", "--quiet"))
  title <- .odb_demo_title(database)
  cli::cli_h1("{title} OAuth demo")
  cli::cli_text(
    "The database and local sign-in service run in Docker. {if (services) 'Run your Shiny app in this R session after setup finishes.' else if (app == 'local') 'Shiny runs in your local R installation.' else 'Shiny and its database driver also run in Docker.'}"
  )
  cli::cli_text(
    "Demo files: {.path {path}}. Existing edits are kept; use a new empty {.arg path} for fresh templates."
  )
  if (build) {
    cli::cli_alert_info(
      "The first build downloads dependencies and may take several minutes. Later builds reuse Docker's cache.",
      wrap = TRUE
    )
  }
  cli::cli_text("After a forced exit, clean up with:")
  cli::cli_code(.odb_demo_resume(database, path, app, "stop"))
  keep_services <- FALSE
  on.exit(
    {
      if (!keep_services && cleanup() != 0L) {
        warning(
          "Demo cleanup failed. Use action = 'stop' after Docker is available.",
          call. = FALSE
        )
      } else if (!keep_services) {
        cli::cli_alert_success(
          "Demo services and sample data removed. Your app files are kept."
        )
      }
    },
    add = TRUE
  )
  started <- run(
    c(
      "up",
      "--detach",
      "--wait",
      "--wait-timeout",
      "360",
      if (build) "--build" else "--no-build",
      if (app == "local") "local" else "app"
    ),
    check = FALSE
  )
  if (started != 0L) {
    run(c("logs", "--tail", "50"), check = FALSE)
    stop("Docker could not start the demo; see its logs above.", call. = FALSE)
  }
  if (services) {
    dir.create(file.path(path, "tls"), showWarnings = FALSE)
    if (database != "postgrest") {
      run(c(
        "cp",
        "tls:/fixtures/tls/ca-cert.pem",
        file.path(path, "tls", "ca-cert.pem")
      ))
    }
    settings <- .odb_demo_services_settings(path, cleanup, database)
    keep_services <- TRUE
    cli::cli_h2("Docker services are ready")
    cli::cli_text(
      "Continue with your app in R. Use the returned provider and endpoint; stop the services with {.code demo$stop()} when finished."
    )
    cli::cli_text(
      "Open the app in a regular browser. Embedded RStudio/Positron viewers cannot complete OAuth redirects."
    )
    return(invisible(settings))
  }
  cli::cli_h2(
    if (app == "local") "Starting Shiny in local R" else "Ready to sign in"
  )
  cli::cli_text(
    "Open {.url http://localhost:18100} in a regular browser. Embedded RStudio/Positron viewers cannot complete OAuth redirects. Use the username and password shown in the app's sign-in panel."
  )
  cli::cli_text(
    "Your browser may ask you to allow the local sign-in service's test certificate. Click Stop demo or interrupt R to remove the demo services and sample data."
  )
  if (app == "local") {
    dir.create(file.path(path, "tls"), showWarnings = FALSE)
    run(c(
      "cp",
      "tls:/fixtures/tls/ca-cert.pem",
      file.path(path, "tls", "ca-cert.pem")
    ))
    .odb_demo_local_run(path, database, launch_browser)
  } else {
    if (launch_browser) {
      utils::browseURL("http://localhost:18100")
    }
    run(c("logs", "--follow", "app"))
  }
  invisible(path)
}

.odb_demo_http <- new.env(parent = emptyenv())
.odb_demo_http$active <- 0L

.odb_demo_services <- new.env(parent = emptyenv())

.odb_demo_services_key <- function(path, database) {
  paste(
    database,
    normalizePath(path, winslash = "/", mustWork = TRUE),
    sep = "\r"
  )
}

.odb_demo_services_restore <- function(state) {
  for (name in names(state$previous)) {
    if (identical(getOption(name), state$policy[[name]])) {
      options(state$previous[name])
    }
  }
  invisible(NULL)
}

.odb_demo_services_release <- function(state) {
  if (!state$stopped) {
    state$stopped <- TRUE
    if (state$postgrest) {
      .odb_demo_http$active <- .odb_demo_http$active - 1L
    }
    .odb_demo_services_restore(state)
    if (identical(.odb_demo_services[[state$key]], state)) {
      rm(list = state$key, envir = .odb_demo_services)
    }
  }
  invisible(NULL)
}

.odb_demo_postgrest_url <- function(url) {
  if (identical(url, "http://127.0.0.1:19444") && .odb_demo_http$active > 0L) {
    return(url)
  }
  .odb_http_url(url)
}

.odb_demo_services_settings <- function(path, cleanup, database) {
  # The registry holds state only, so it cannot keep the handle alive and
  # prevent its garbage-collection finalizer from stopping Docker.
  state <- new.env(parent = emptyenv())
  state$key <- .odb_demo_services_key(path, database)
  state$postgrest <- database == "postgrest"
  state$stopped <- FALSE
  state$policy <- list(
    shinyOAuth.allowed_hosts = c("localhost", "127.0.0.1", "::1"),
    shinyOAuth.allow_insecure_oidc_loopback = TRUE
  )
  state$previous <- options(state$policy)
  ready <- FALSE
  on.exit(if (!ready) .odb_demo_services_restore(state), add = TRUE)
  issuer <- "https://localhost:18443/realms/shinyoauthdb"
  backchannel <- "http://localhost:18080/realms/shinyoauthdb/protocol/openid-connect"
  provider <- shinyOAuth::oauth_provider(
    name = "local-demo",
    issuer = issuer,
    auth_url = paste0(issuer, "/protocol/openid-connect/auth"),
    token_url = paste0(backchannel, "/token"),
    userinfo_url = paste0(backchannel, "/userinfo"),
    revocation_url = paste0(backchannel, "/revoke"),
    jwks_uri = paste0(backchannel, "/certs"),
    id_token_validation = TRUE,
    userinfo_required = TRUE,
    use_pkce = TRUE,
    use_nonce = TRUE
  )
  settings <- new.env(parent = emptyenv())
  settings$provider <- provider
  postgrest <- database == "postgrest"
  settings$url <- if (postgrest) {
    "http://127.0.0.1:19444"
  } else {
    "https://localhost:19444"
  }
  settings$host <- "localhost"
  settings$port <- 19444L
  settings$ca_bundle <- if (postgrest) {
    NULL
  } else {
    file.path(path, "tls", "ca-cert.pem")
  }
  settings$path <- path
  if (postgrest) {
    .odb_demo_http$active <- .odb_demo_http$active + 1L
  }
  settings$stop <- function() {
    if (!state$stopped) {
      if (cleanup() != 0L) {
        stop(
          "Docker could not stop the demo. Retry demo$stop() when Docker is available.",
          call. = FALSE
        )
      }
      .odb_demo_services_release(state)
      cli::cli_alert_success("Demo services and sample data removed.")
    }
    invisible(NULL)
  }
  reg.finalizer(settings, .odb_demo_services_finalize, onexit = TRUE)
  .odb_demo_services[[state$key]] <- state
  ready <- TRUE
  settings
}

.odb_demo_services_finalize <- function(settings) {
  try(settings$stop(), silent = TRUE)
}

.odb_demo_title <- function(database) {
  c(
    postgres = "PostgreSQL",
    postgrest = "PostgREST",
    trino = "Trino",
    starrocks = "StarRocks",
    duckdb = "DuckDB Quack",
    libsql = "libSQL",
    cratedb = "CrateDB",
    opensearch = "OpenSearch"
  )[[database]]
}

.odb_demo_resume <- function(database, path, app, action = NULL) {
  paste0(
    "shinyOAuthDB::oauth_db_demo(",
    deparse(database),
    ", app = ",
    deparse(app),
    ", path = ",
    deparse(path),
    if (!is.null(action)) paste0(", action = ", deparse(action)),
    ")"
  )
}

.odb_demo_files_message <- function(database, path, app) {
  file <- if (app == "local") {
    file.path(path, "local-app", database, "app.R")
  } else {
    file.path(path, database, "app.R")
  }
  title <- .odb_demo_title(database)
  cli::cli_alert_success(
    "{title} demo files are ready at {.path {path}}.",
    wrap = TRUE
  )
  cli::cli_text("Edit the app with:")
  cli::cli_code(paste0("file.edit(", deparse(file), ")"))
  cli::cli_text("Then start it with:")
  cli::cli_code(.odb_demo_resume(database, path, app))
}

.odb_demo_local_require <- function(database) {
  .odb_require("bslib", version = "0.9.0")
  .odb_require("callr")
  if (database %in% c("postgrest", "libsql", "cratedb", "opensearch")) {
    .odb_require("jsonlite")
  }
  if (database == "postgres") {
    tryCatch(.odb_postgres_runtime(), error = function(error) {
      stop(
        "The local PostgreSQL app needs Linux and shinyOAuthDB/RPostgres built against shared libpq 18. ",
        "Use oauth_db_demo('postgrest', app = 'local') for a driver-free example, ",
        "or keep app = 'docker'.",
        call. = FALSE
      )
    })
  }
  if (database == "trino") {
    .odb_require("RTrino", version = "0.1.0")
  }
  if (database == "starrocks") {
    .odb_require("odbc", version = "1.4.2")
  }
  if (database == "duckdb") {
    .odb_require("duckdb", version = "1.5.3")
    con <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    version <- DBI::dbGetQuery(
      con,
      "SELECT library_version FROM pragma_version()"
    )$library_version
    if (!identical(version, "v1.5.4")) {
      stop(
        "The local Quack demo needs a DuckDB 1.5.4 client to match its server. ",
        "Use app = 'docker' for the supplied matching client.",
        call. = FALSE
      )
    }
  }
  invisible(NULL)
}

.odb_demo_local_files <- function(path, database) {
  if (!file.exists(file.path(path, "compose.local.yml"))) {
    stop(
      "These demo files predate local app mode. Choose a new empty path to copy the current templates.",
      call. = FALSE
    )
  }
  directory <- file.path(path, "local-app", database)
  if (file.exists(file.path(directory, "app.R"))) {
    return(invisible(directory))
  }
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  ca <- encodeString(file.path(path, "tls", "ca-cert.pem"), quote = '"')
  if (database == "starrocks") {
    driver <- Sys.getenv("OAUTHDB_DEMO_ODBC_DRIVER", "")
    if (!nzchar(driver)) {
      driver <- "/usr/lib/x86_64-linux-gnu/odbc/libmyodbc9w.so"
      if (!file.exists(driver)) {
        drivers <- if (requireNamespace("odbc", quietly = TRUE)) {
          unique(odbc::odbcListDrivers()$name)
        } else {
          character()
        }
        drivers <- grep(
          "^MySQL ODBC [0-9.]+ Unicode Driver$",
          drivers,
          value = TRUE
        )
        if (length(drivers)) {
          versions <- numeric_version(sub(
            "^MySQL ODBC ([0-9.]+) Unicode Driver$",
            "\\1",
            drivers
          ))
          drivers <- drivers[order(versions)]
          drivers <- drivers[sort(versions) >= "9.2"]
        }
        driver <- if (length(drivers)) {
          drivers[[length(drivers)]]
        } else {
          "MySQL ODBC 9.5 Unicode Driver"
        }
      }
    }
  }
  for (name in c("app.R", "prepare.R")) {
    source <- file.path(path, database, name)
    if (!file.exists(source)) {
      next
    }
    code <- readLines(source, warn = FALSE, encoding = "UTF-8")
    code <- gsub('"/fixtures/tls/ca-cert.pem"', ca, code, fixed = TRUE)
    code <- gsub("18444", "19444", code, fixed = TRUE)
    code <- gsub("localhost:9200", "localhost:19444", code, fixed = TRUE)
    code <- gsub("localhost:5432", "localhost:19444", code, fixed = TRUE)
    code <- gsub("localhost:9030", "localhost:19444", code, fixed = TRUE)
    if (database == "postgres") {
      code <- sub(
        'host = "localhost", dbname =',
        'host = "localhost", port = 19444L, dbname =',
        code,
        fixed = TRUE
      )
    }
    if (database == "starrocks") {
      code <- gsub(
        '"/usr/lib/x86_64-linux-gnu/odbc/libmyodbc9w.so"',
        encodeString(driver, quote = '"'),
        code,
        fixed = TRUE
      )
      plugins <- Sys.getenv("OAUTHDB_DEMO_ODBC_PLUGINS", "")
      code <- sub(
        'plugin_dir = "/usr/lib/x86_64-linux-gnu/mysql/libmyodbc9/plugin"',
        paste0(
          "plugin_dir = ",
          if (nzchar(plugins)) encodeString(plugins, quote = '"') else "NULL"
        ),
        code,
        fixed = TRUE
      )
      code <- sub(
        'server = "localhost", database =',
        'server = "localhost", port = 19444L, database =',
        code,
        fixed = TRUE
      )
      code <- gsub("9030L", "19444L", code, fixed = TRUE)
    }
    writeLines(code, file.path(directory, name), useBytes = TRUE)
  }
  invisible(directory)
}

.odb_demo_local_run <- function(path, database, launch_browser) {
  directory <- file.path(path, "local-app", database)
  tls_env <- c(CURL_CA_BUNDLE = file.path(path, "tls", "ca-cert.pem"))
  # R's Windows curl ignores CURL_CA_BUNDLE when using Schannel.
  if (.Platform$OS.type == "windows") {
    tls_env <- c(tls_env, CURL_SSL_BACKEND = "openssl")
  }
  message(
    "Local app: ",
    file.path(directory, "app.R"),
    "\nSave your edits and reload the browser to try them."
  )
  callr::r(
    function(directory, database, launch_browser, tls_env) {
      do.call(Sys.setenv, as.list(tls_env))
      options(
        shinyOAuth.allowed_hosts = c("localhost", "127.0.0.1", "::1"),
        shiny.autoreload = TRUE
      )
      if (database == "duckdb") {
        con <- DBI::dbConnect(duckdb::duckdb())
        tryCatch(
          {
            DBI::dbExecute(con, "INSTALL quack")
            DBI::dbExecute(con, "INSTALL httpfs")
          },
          finally = DBI::dbDisconnect(con, shutdown = TRUE)
        )
      }
      prepare <- file.path(directory, "prepare.R")
      if (file.exists(prepare)) {
        sys.source(prepare, envir = new.env(parent = globalenv()))
      }
      shiny::runApp(
        directory,
        host = "127.0.0.1",
        port = 18100L,
        launch.browser = launch_browser
      )
    },
    args = list(directory, database, launch_browser, tls_env),
    libpath = .libPaths(),
    user_profile = FALSE,
    show = TRUE,
    spinner = FALSE,
    supervise = TRUE,
    cleanup_tree = TRUE,
    windows_hide_window = TRUE
  )
  invisible(NULL)
}

.odb_demo_docker <- function() {
  docker <- Sys.which("docker")
  if (!nzchar(docker)) {
    stop(
      "Install Docker with Linux containers and Compose v2 first.",
      call. = FALSE
    )
  }
  os <- suppressWarnings(system2(
    docker,
    c("info", "--format", shQuote("{{.OSType}}")),
    stdout = TRUE,
    stderr = TRUE
  ))
  if (!is.null(attr(os, "status")) || !"linux" %in% os) {
    stop(
      "Start Docker with Linux containers before running the demo.",
      call. = FALSE
    )
  }
  .odb_demo_command(docker, c("compose", "version"))
  docker
}

.odb_demo_command <- function(docker, args, check = TRUE) {
  status <- system2(docker, vapply(args, shQuote, ""))
  if (check && status != 0L) {
    stop(
      "Docker could not run the demo command; see its output above.",
      call. = FALSE
    )
  }
  invisible(status)
}
