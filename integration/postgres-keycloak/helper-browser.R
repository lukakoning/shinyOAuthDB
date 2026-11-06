# Browser orchestration adapted from shinyOAuth's local Keycloak wrapper tests.
# Only fixture metadata and expected granted rows cross the browser boundary.

postgres_browser_config <- function(client_id = "shiny-db") {
  list(
    client_id = client_id,
    issuer = Sys.getenv(
      "OAUTHDB_TEST_ISSUER",
      "https://localhost:18443/realms/shinyoauthdb"
    ),
    origin = sub(
      "/$",
      "",
      Sys.getenv("OAUTHDB_TEST_APP_ORIGIN", "http://localhost:18100")
    ),
    pg_host = Sys.getenv("OAUTHDB_TEST_PG_HOST", "localhost"),
    pg_port = as.integer(Sys.getenv("OAUTHDB_TEST_PG_PORT", "5432")),
    pg_dbname = Sys.getenv("OAUTHDB_TEST_PG_DBNAME", "oauthdb_fixture"),
    ca_file = Sys.getenv(
      "OAUTHDB_TEST_PG_CA",
      Sys.getenv("OAUTHDB_TEST_CA", "/fixtures/tls/ca-cert.pem")
    ),
    admin_password = Sys.getenv(
      "OAUTHDB_TEST_PG_ADMIN_PASSWORD",
      "fixture-superuser-password"
    )
  )
}

postgres_browser_setup <- function(
  config = postgres_browser_config(),
  .env = parent.frame()
) {
  required <- c(
    "shiny",
    "shinyOAuth",
    "shinyOAuthDB",
    "RPostgres",
    "DBI",
    "chromote",
    "callr",
    "curl",
    "jsonlite",
    "httr2",
    "withr"
  )
  missing <- required[
    !vapply(required, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    stop(
      "Missing browser integration dependencies: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  script <- normalizePath(testthat::test_path("fixture-app.R"), mustWork = TRUE)
  existing <- suppressWarnings(try(
    socketConnection(
      host = "127.0.0.1",
      port = as.integer(httr2::url_parse(config$origin)$port),
      blocking = TRUE,
      open = "r+",
      timeout = 1
    ),
    silent = TRUE
  ))

  if (!inherits(existing, "try-error")) {
    close(existing)

    stop("Browser fixture port is already occupied.", call. = FALSE)
  }

  config$stop_file <- tempfile("postgres-browser-stop-")
  process <- callr::r_bg(
    function(script, config) {
      Sys.setenv(CURL_SSL_BACKEND = "openssl", CURL_CA_BUNDLE = config$ca_file)
      source(script, local = TRUE)
      source(file.path(dirname(script), "playground-ui.R"), local = TRUE)

      stop_when_requested <- function() {
        if (file.exists(config$stop_file)) shiny::stopApp()
        else later::later(stop_when_requested, 0.1)
      }
      later::later(stop_when_requested, 0.1)
      postgres_browser_run_app(config)
    },
    args = list(script, config),
    libpath = .libPaths(),
    supervise = TRUE,
    stdout = "|",
    stderr = "|"
  )
  closed <- FALSE
  chrome <- NULL

  close_all <- function() {
    if (closed) {
      return(invisible(NULL))
    }

    closed <<- TRUE
    if (!is.null(chrome)) {
      try(chrome$close(), silent = TRUE)
    }
    if (process$is_alive()) {
      file.create(config$stop_file)
      process$wait(timeout = 10000)
      if (process$is_alive()) {
        process$kill()
        stop("Browser app did not exit normally; native coverage would be incomplete.", call. = FALSE)
      }
      if (!identical(process$get_exit_status(), 0L)) {
        stop("Browser app exited unsuccessfully.", call. = FALSE)
      }
    }
    unlink(config$stop_file)

    invisible(NULL)
  }

  withr::defer(close_all(), envir = .env)
  deadline <- Sys.time() + 30

  repeat {
    ready <- tryCatch(
      curl::curl_fetch_memory(config$origin)$status_code == 200L,
      error = function(e) FALSE
    )

    if (ready) {
      break
    }
    if (!process$is_alive() || Sys.time() > deadline) {
      # Startup precedes every browser login. Retain only the R error condition
      # and its continuation; omit endpoint URLs and all unrelated child logs.
      lines <- process$read_error_lines()
      index <- which(grepl("^Error([ :]| in )", lines))
      diagnostic <- if (length(index)) {
        start <- tail(index, 1L)
        condition_lines <- lines[seq.int(start, min(start + 8L, length(lines)))]
        condition_lines <- condition_lines[
          !grepl("^(Calls:|Execution halted)", condition_lines)
        ]

        paste(condition_lines, collapse = " ")
      } else if (process$is_alive()) {
        "App readiness timed out."
      } else {
        "The app process ended before listening."
      }
      diagnostic <- gsub(
        "https?://[^[:space:]]+",
        "[configured endpoint]",
        diagnostic
      )
      diagnostic <- gsub(
        "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+",
        "[redacted credential]",
        diagnostic
      )
      close_all()

      stop(
        "Shiny browser fixture failed to start: ",
        substr(diagnostic, 1L, 1000L),
        call. = FALSE
      )
    }

    Sys.sleep(0.1)
  }

  chrome <- chromote::Chromote$new()

  new_browser <- function() {
    context <- chrome$Target$createBrowserContext()$browserContextId
    target <- chrome$Target$createTarget(
      "about:blank",
      browserContextId = context
    )$targetId
    browser <- chromote::ChromoteSession$new(parent = chrome, targetId = target)
    browser$Page$enable()
    browser$go_to(config$origin)
    postgres_browser_wait(browser, function(snapshot) isTRUE(snapshot$ready) &&
      isTRUE(postgres_browser_value(browser, "!document.querySelector('#login').disabled")))

    browser
  }

  list(
    origin = config$origin,
    config = config,
    process = process,
    new_browser = new_browser,
    close = close_all
  )
}

postgres_browser_value <- function(browser, script) {
  browser$Runtime$evaluate(script, returnByValue = TRUE)$result$value
}

postgres_browser_snapshot <- function(browser) {
  postgres_browser_value(
    browser,
    paste0(
      "(() => { try { return JSON.parse(",
      "document.querySelector('#snapshot').textContent); } catch (_) { return {}; } })()"
    )
  )
}

postgres_browser_wait <- function(browser, predicate, timeout = 25) {
  deadline <- Sys.time() + timeout

  repeat {
    snapshot <- tryCatch(
      postgres_browser_snapshot(browser),
      error = function(e) list()
    )

    if (isTRUE(predicate(snapshot))) {
      return(snapshot)
    }

    if (Sys.time() > deadline) {
      page <- tryCatch(
        postgres_browser_value(
          browser,
          paste0(
            "(() => ({",
            "origin:location.origin,path:location.pathname,",
            "loginError:(document.querySelector('#input-error') || document.querySelector('.alert-error'))?.textContent || ''",
            "}))()"
          )
        ),
        error = function(e) list()
      )

      stop(
        "Browser integration assertion timed out. Safe fixture snapshot: ",
        jsonlite::toJSON(snapshot, auto_unbox = TRUE, null = "null"),
        "; page: ",
        jsonlite::toJSON(page, auto_unbox = TRUE),
        call. = FALSE
      )
    }

    Sys.sleep(0.1)
  }
}

postgres_browser_click <- function(browser, id) {
  selector <- jsonlite::toJSON(paste0("#", id), auto_unbox = TRUE)
  postgres_browser_wait(browser, function(value) isTRUE(postgres_browser_value(
    browser, paste0("Boolean(document.querySelector(", selector,
      ") && !document.querySelector(", selector, ").disabled)"))))
  clicked <- postgres_browser_value(
    browser,
    paste0("(() => { const button=document.querySelector(", selector,
      "); button.click(); return {message:document.querySelector('#action_status')?.textContent,",
      "disabled:button.disabled}; })()")
  )

  invisible(clicked)
}

postgres_browser_login <- function(
  browser,
  username,
  config = postgres_browser_config()
) {
  if (!username %in% c("alice", "bob")) {
    stop("Choose a predefined fixture user.", call. = FALSE)
  }

  if (isTRUE(postgres_browser_snapshot(browser)$authorized)) {
    cookies <- browser$Network$getCookies(urls = list(paste0(config$issuer, "/")))$cookies
    for (cookie in cookies) if (startsWith(cookie$name, "KEYCLOAK_")) {
      browser$Network$deleteCookies(name = cookie$name, domain = cookie$domain, path = cookie$path)
    }
  }

  postgres_browser_click(browser, "login")
  deadline <- Sys.time() + 25

  repeat {
    url <- tryCatch(
      postgres_browser_value(browser, "location.href"),
      error = function(e) ""
    )

    form <- tryCatch(
      postgres_browser_value(
        browser,
        "Boolean(document.querySelector('#kc-login') && document.querySelector('#username'))"
      ),
      error = function(e) FALSE
    )

    if (isTRUE(form)) {
      break
    }
    restart <- tryCatch(postgres_browser_value(browser,
      "Boolean(document.querySelector('#reset-login') && !document.querySelector('#username'))"),
      error = function(e) FALSE)
    if (isTRUE(restart)) postgres_browser_value(browser, "document.querySelector('#reset-login').click()")
    if (Sys.time() > deadline) {
      page <- postgres_browser_value(browser, paste0(
        "({origin:location.origin,path:location.pathname,",
        "message:document.querySelector('#action_status')?.textContent,",
        "loginDisabled:document.querySelector('#login')?.disabled,",
        "pageText:document.body.innerText.slice(0,600)})"
      ))
      stop("Browser did not reach the fixture login form. Safe state: ",
        jsonlite::toJSON(postgres_browser_snapshot(browser), auto_unbox = TRUE, null = "null"),
        "; page: ", jsonlite::toJSON(page, auto_unbox = TRUE), call. = FALSE)
    }

    Sys.sleep(0.1)
  }

  query <- httr2::url_parse(url)$query
  if (is.character(query)) {
    query <- shiny::parseQueryString(query)
  }

  metadata <- list(
    response_type = query$response_type,
    pkce_method = query$code_challenge_method,
    has_s256_challenge = is.character(query$code_challenge) &&
      length(query$code_challenge) == 1L &&
      grepl("^[A-Za-z0-9_-]{43}$", query$code_challenge),
    client_id = query$client_id
  )

  # Full authorization URLs contain state. They are never printed or returned.
  if (!startsWith(url, sub("/realms/.*$", "/", config$issuer))) {
    stop("Browser reached an unexpected authorization origin.", call. = FALSE)
  }

  user_json <- jsonlite::toJSON(username, auto_unbox = TRUE)
  password_json <- jsonlite::toJSON(
    paste0(username, "-fixture-password"),
    auto_unbox = TRUE
  )
  postgres_browser_value(
    browser,
    paste0(
      "(() => {",
      "const login=document.querySelector('#kc-login');",
      "document.querySelector('#username').value=",
      user_json,
      ";",
      "document.querySelector('#password').value=",
      password_json,
      ";",
      "HTMLFormElement.prototype.submit.call(login.form); return true; })()"
    )
  )

  snapshot <- postgres_browser_wait(browser, function(value) {
    isTRUE(value$authorized) || !is.null(value$auth_error)
  })

  list(metadata = metadata, snapshot = snapshot)
}
