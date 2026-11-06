source("integration/contracts.R")
fixture_repository <- normalizePath(".", mustWork = TRUE)

fixture_check_refresh_rejection <- function() {
  fixture <- fixture_setup()
  on.exit(fixture$close(), add = TRUE)
  browser <- fixture$new_browser()
  fixture_login(browser, "alice", fixture$config)
  before <- fixture_wait(browser, function(x) !is.null(x$result))
  fixture_wait(browser, function(x) isTRUE(fixture_value(browser,
    "!document.documentElement.classList.contains('shiny-busy')")))
  fixture_value(browser, "Shiny.setInputValue('fail_refresh', 1, {priority:'event'}); true")
  failed <- fixture_wait(browser, function(x) isTRUE(x$refresh_failed) && !is.null(x$held_usable))
  testthat::expect_false(failed$authorized)
  testthat::expect_false(failed$held_usable)
  testthat::expect_null(failed$result)
  testthat::expect_identical(failed$calls, before$calls)
  if (fixture_backend$dbi) testthat::expect_false(failed$held_valid)
  fixture_login(browser, "bob", fixture$config)
  recovered <- fixture_wait(browser, function(x) !is.null(x$result))
  testthat::expect_false(identical(recovered$authorization_id, before$authorization_id))
  testthat::expect_identical(vapply(recovered$result, `[[`, "", "marker"), paste0("bob-visible-", 1:2))
}

fixture_check_natural_expiry <- function() {
  config <- fixture_config("shiny-short-lived")
  config$retain_expired <- TRUE
  fixture <- fixture_setup(config)
  on.exit(fixture$close(), add = TRUE)
  browser <- fixture$new_browser()
  fixture_login(browser, "alice", fixture$config)
  before <- fixture_wait(browser, function(x) !is.null(x$result))
  testthat::expect_false(before$read_credential_rotated)
  wait <- before$original_expiry + 1 - as.numeric(Sys.time())
  if (wait > 0) Sys.sleep(wait)
  fixture_click(browser, "load")
  after <- fixture_wait(browser, function(x) x$calls > before$calls)
  testthat::expect_null(after$error)
  testthat::expect_identical(after$authorization_id, before$authorization_id)
  testthat::expect_true(after$read_credential_rotated)
  testthat::expect_identical(after$calls, before$calls + 1L)
  if (fixture_backend$dbi) testthat::expect_identical(after$openings, before$openings)
  testthat::expect_identical(vapply(after$result, `[[`, "", "marker"), paste0("alice-visible-", 1:2))
}

fixture_config <- function(client_id = "shiny-db") {
  list(backend = Sys.getenv("OAUTHDB_FIXTURE"), client_id = client_id,
    issuer = "https://localhost:18443/realms/shinyoauthdb",
    origin = "http://localhost:18100", ca = "/fixtures/tls/ca-cert.pem", server = "localhost", port = 18444L,
    ended = tempfile("oauthdb-session-ended-"))
}

fixture_value <- function(browser, script) {
  result <- browser$Runtime$evaluate(script, returnByValue = TRUE)
  if (!is.null(result$exceptionDetails)) stop("Fixture JavaScript failed.", call. = FALSE)
  result$result$value
}

fixture_snapshot <- function(browser) {
  fixture_value(browser, "(() => { try { return JSON.parse(document.querySelector('#snapshot').textContent); } catch (_) { return {}; } })()")
}

fixture_wait <- function(browser, predicate, timeout = 30) {
  deadline <- Sys.time() + timeout
  repeat {
    value <- tryCatch(fixture_snapshot(browser), error = function(e) list())
    if (isTRUE(predicate(value))) return(value)
    if (Sys.time() > deadline) {
      page <- tryCatch(fixture_value(browser,
        "({origin:location.origin,path:location.pathname,text:document.body.innerText.slice(0,1200)})"),
        error = function(e) list())
      stop("Local browser test timed out. Sanitized snapshot: ",
        jsonlite::toJSON(value, auto_unbox = TRUE, null = "null"),
        "; page: ", jsonlite::toJSON(page, auto_unbox = TRUE), call. = FALSE)
    }
    Sys.sleep(0.1)
  }
}

fixture_click <- function(browser, id) {
  encoded <- jsonlite::toJSON(id, auto_unbox = TRUE)
  # A snapshot can arrive before the previous reactive flush reports idle.
  fixture_wait(browser, function(x) isTRUE(fixture_value(browser, paste0(
    "(() => { const button=document.getElementById(", encoded, ");",
    "return Boolean(button && !button.disabled && window.Shiny?.shinyapp?.isConnected() && ",
    "window.jQuery && jQuery(button).hasClass('shiny-bound-input') && ",
    "!document.documentElement.classList.contains('shiny-busy')); })()"))))
  clicked <- fixture_value(browser, paste0("(() => { const button=document.getElementById(", encoded, ");",
    "const before=jQuery(button).data('val') || 0; button.click();",
    "return (jQuery(button).data('val') || 0) === before + 1; })()"))
  if (!isTRUE(clicked)) stop("The fixture button did not dispatch its input event.", call. = FALSE)
  invisible(TRUE)
}

fixture_login <- function(browser, username, config) {
  stopifnot(username %in% c("alice", "bob"))
  if (isTRUE(fixture_snapshot(browser)$authorized)) {
    # Keycloak prompt=login reauthenticates its SSO user. Clear only IdP
    # cookies to choose another account, retaining the live Shiny grant.
    cookies <- browser$Network$getCookies(urls = list(paste0(config$issuer, "/")))$cookies
    for (cookie in cookies) if (startsWith(cookie$name, "KEYCLOAK_")) {
      browser$Network$deleteCookies(name = cookie$name, domain = cookie$domain, path = cookie$path)
    }
  }
  fixture_click(browser, "login")
  fixture_wait(browser, function(snapshot) isTRUE(fixture_value(browser,
    "Boolean(document.querySelector('#username') && document.querySelector('#kc-login'))")))
  address <- fixture_value(browser, "location.href")
  stopifnot(startsWith(address, "https://localhost:18443/"))
  query <- httr2::url_parse(address)$query
  metadata <- list(response_type = query$response_type, pkce_method = query$code_challenge_method,
    challenge_valid = isTRUE(grepl("^[A-Za-z0-9_-]{43}$", query$code_challenge)))
  if (isTRUE(fixture_value(browser, "Boolean(document.querySelector('#reset-login'))"))) {
    fixture_value(browser, "document.querySelector('#reset-login').click(); true")
    fixture_wait(browser, function(x) isTRUE(fixture_value(browser,
      "Boolean(document.querySelector('#username') && !document.querySelector('#username').readOnly)")))
  }
  fixture_value(browser, paste0("document.querySelector('#username').value=",
    jsonlite::toJSON(username, auto_unbox = TRUE), ";document.querySelector('#password').value=",
    jsonlite::toJSON(paste0(username, "-fixture-password"), auto_unbox = TRUE),
    ";HTMLFormElement.prototype.submit.call(document.querySelector('#kc-login').form); true"))
  value <- fixture_wait(browser, function(snapshot) isTRUE(snapshot$authorized) || !is.null(snapshot$auth_error))
  list(metadata = metadata, snapshot = value)
}

fixture_setup <- function(config = fixture_config()) {
  root <- fixture_repository
  process <- callr::r_bg(function(root, config) {
    setwd(root)
    source("integration/local/app.R", local = TRUE)
    fixture_run_app(config)
  }, args = list(root, config), libpath = .libPaths(), supervise = TRUE, stdout = "|", stderr = "|")
  chrome <- NULL
  close <- function() {
    if (!is.null(chrome)) try(chrome$close(), silent = TRUE)
    if (process$is_alive()) process$kill()
  }
  ready <- FALSE
  deadline <- Sys.time() + 30
  while (process$is_alive() && Sys.time() < deadline) {
    ready <- tryCatch(curl::curl_fetch_memory(config$origin)$status_code == 200L, error = function(e) FALSE)
    if (ready) break
    Sys.sleep(0.1)
  }
  if (!ready) {
    close()
    # Only startup precedes token acquisition. Redact even these diagnostics.
    detail <- paste(process$read_error_lines(), collapse = " ")
    detail <- gsub("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+", "[redacted]", detail)
    stop("Local fixture did not start: ", substr(detail, 1L, 1500L), call. = FALSE)
  }
  chrome <- chromote::Chromote$new()
  new_browser <- function() {
    context <- chrome$Target$createBrowserContext()$browserContextId
    target <- chrome$Target$createTarget("about:blank", browserContextId = context)$targetId
    browser <- chromote::ChromoteSession$new(parent = chrome, targetId = target)
    browser$Page$enable()
    browser$go_to(config$origin)
    tryCatch(fixture_wait(browser, function(snapshot) isTRUE(snapshot$ready)), error = function(e) {
      detail <- paste(process$read_error_lines(), collapse = " ")
      detail <- gsub("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+", "[redacted]", detail)
      stop(conditionMessage(e), "; app startup: ", substr(detail, 1L, 1800L), call. = FALSE)
    })
    browser
  }
  list(config = config, close = close, new_browser = new_browser)
}
