testthat::test_that("real browser users receive only their server-enforced rows", {
  fixture <- fixture_setup()
  on.exit(fixture$close(), add = TRUE)
  a <- fixture$new_browser()
  b <- fixture$new_browser()
  before <- fixture_snapshot(a)
  testthat::expect_false(before$authorized)
  testthat::expect_null(before$result)
  testthat::expect_identical(before$calls, 0L)
  for (entry in list(
    list(browser = a, user = "alice"),
    list(browser = b, user = "bob")
  )) {
    login <- fixture_login(entry$browser, entry$user, fixture$config)
    testthat::expect_identical(login$metadata$response_type, "code")
    testthat::expect_identical(login$metadata$pkce_method, "S256")
    testthat::expect_true(login$metadata$challenge_valid)
    snapshot <- fixture_wait(entry$browser, function(x) {
      !is.null(x$result) || !is.null(x$error)
    })
    testthat::expect_null(snapshot$error)
    testthat::expect_identical(
      vapply(snapshot$result, `[[`, "", "database_user"),
      rep(entry$user, 2L)
    )
    testthat::expect_identical(
      vapply(snapshot$result, `[[`, "", "marker"),
      paste0(entry$user, "-visible-", 1:2)
    )
    fixture_click(entry$browser, "probe")
    check <- fixture_wait(entry$browser, function(x) !is.null(x$denied))
    testthat::expect_true(integration_require_checks(
      check$denied,
      integration_check_names(fixture$config$backend, "denied"),
      "Permission checks"
    ))
    fixture_click(entry$browser, "tamper")
    check <- fixture_wait(entry$browser, function(x) {
      !is.null(x$tampered_denied)
    })
    testthat::expect_true(check$tampered_denied)
    fixture_click(entry$browser, "tls")
    check <- fixture_wait(entry$browser, function(x) !is.null(x$tls_checks))
    testthat::expect_true(integration_require_checks(
      check$tls_checks,
      integration_check_names(fixture$config$backend, "tls"),
      "TLS checks"
    ))
    fixture_click(entry$browser, "data")
    check <- fixture_wait(entry$browser, function(x) !is.null(x$data_checks))
    testthat::expect_null(check$data_error)
    testthat::expect_true(integration_require_checks(
      check$data_checks,
      integration_check_names(fixture$config$backend, "data"),
      "Data checks"
    ))
  }
  initial <- fixture_snapshot(a)
  testthat::expect_false(identical(
    initial$authorization_id,
    fixture_snapshot(b)$authorization_id
  ))
  fixture_click(a, "load")
  reused <- fixture_wait(a, function(x) x$calls > initial$calls)
  testthat::expect_identical(reused$openings, initial$openings)
  fixture_click(a, "refresh")
  refreshed <- fixture_wait(a, function(x) x$refreshes == 1L)
  testthat::expect_true(refreshed$rotated)
  testthat::expect_identical(refreshed$calls, reused$calls)
  fixture_click(a, "load")
  refreshed_read <- fixture_wait(a, function(x) x$calls > reused$calls)
  testthat::expect_null(refreshed_read$error)
  testthat::expect_identical(refreshed_read$openings, reused$openings)
  testthat::expect_identical(refreshed_read$result, reused$result)
  if (fixture_backend$dbi) {
    fixture_click(a, "break_connection")
    fixture_wait(a, function(x) isTRUE(x$broken))
    fixture_click(a, "load")
    recovered <- fixture_wait(a, function(x) x$calls > refreshed_read$calls)
    testthat::expect_null(recovered$error)
    testthat::expect_identical(recovered$openings, refreshed_read$openings + 1L)
    testthat::expect_identical(recovered$result, refreshed_read$result)
  }

  fixture_login(a, "bob", fixture$config)
  replacement <- fixture_wait(a, function(x) {
    !identical(x$authorization_id, initial$authorization_id) &&
      !is.null(x$result) &&
      identical(x$result[[1L]]$database_user, "bob")
  })
  testthat::expect_identical(
    vapply(replacement$result, `[[`, "", "marker"),
    paste0("bob-visible-", 1:2)
  )
  testthat::expect_identical(
    vapply(replacement$result, `[[`, "", "database_user"),
    rep("bob", 2L)
  )
  testthat::expect_true(fixture_snapshot(b)$authorized)

  fixture_click(a, "logout")
  logged_out <- fixture_wait(a, function(x) !isTRUE(x$authorized))
  testthat::expect_null(logged_out$result)
  if (fixture_backend$dbi) {
    testthat::expect_false(logged_out$held_valid)
  }
  testthat::expect_true(fixture_snapshot(b)$authorized)
  fixture_login(a, "bob", fixture$config)
  switched <- fixture_wait(a, function(x) !is.null(x$result))
  testthat::expect_false(identical(
    switched$authorization_id,
    initial$authorization_id
  ))
  testthat::expect_identical(
    vapply(switched$result, `[[`, "", "marker"),
    paste0("bob-visible-", 1:2)
  )

  ending_id <- fixture_snapshot(b)$authorization_id
  unlink(fixture$config$ended)
  fixture_click(b, "end")
  deadline <- Sys.time() + 15
  ended <- NULL
  repeat {
    ended <- if (file.exists(fixture$config$ended)) {
      tryCatch(
        jsonlite::read_json(fixture$config$ended, simplifyVector = TRUE),
        error = function(e) NULL
      )
    } else {
      NULL
    }
    if (identical(ended$authorization_id, ending_id) || Sys.time() > deadline) {
      break
    }
    Sys.sleep(0.1)
  }
  testthat::expect_true(file.exists(fixture$config$ended))
  testthat::expect_identical(ended$authorization_id, ending_id)
  testthat::expect_false(ended$accessor_usable)
  if (fixture_backend$dbi) testthat::expect_false(ended$native_valid)
})

testthat::test_that("the real service rejects a valid token for another audience", {
  fixture <- fixture_setup(fixture_config("shiny-wrong-audience"))
  on.exit(fixture$close(), add = TRUE)
  browser <- fixture$new_browser()
  login <- fixture_login(browser, "alice", fixture$config)
  testthat::expect_true(login$snapshot$authorized)
  value <- fixture_wait(browser, function(x) !is.null(x$error))
  testthat::expect_identical(value$error, "backend_operation_failed")
  testthat::expect_null(value$result)
  testthat::expect_true(value$read_attempts >= 1L || fixture_backend$dbi)
  testthat::expect_identical(value$calls, 0L)
})

testthat::test_that("missing operation scope blocks fixture read attempts", {
  fixture <- fixture_setup(fixture_config("shiny-missing-scope"))
  on.exit(fixture$close(), add = TRUE)
  browser <- fixture$new_browser()
  login <- fixture_login(browser, "alice", fixture$config)
  testthat::expect_true(login$snapshot$authorized)
  fixture_click(browser, "load")
  value <- fixture_snapshot(browser)
  testthat::expect_null(value$result)
  testthat::expect_identical(value$calls, 0L)
  if (fixture$config$backend == "postgrest") {
    testthat::expect_identical(value$remote_read_attempts, 0L)
  } else {
    testthat::expect_identical(value$read_attempts, 0L)
  }
})

testthat::test_that("the service rejects an expired browser-issued token independently of local access", {
  fixture <- fixture_setup(fixture_config("shiny-short-lived"))
  on.exit(fixture$close(), add = TRUE)
  browser <- fixture$new_browser()
  fixture_login(browser, "alice", fixture$config)
  initial <- fixture_wait(browser, function(x) {
    !is.null(x$result) || !is.null(x$error)
  })
  testthat::expect_null(initial$error)
  testthat::expect_false(is.null(initial$original_expiry))
  remaining <- initial$original_expiry +
    fixture_backend$expiry_leeway +
    3 -
    as.numeric(Sys.time())
  if (remaining > 0) {
    Sys.sleep(remaining)
  }
  fixture_click(browser, "expired")
  value <- fixture_wait(browser, function(x) !is.null(x$expired_denied))
  testthat::expect_true(value$expired_denied)
  testthat::expect_false(value$authorized)
  testthat::expect_null(value$result)
  testthat::expect_identical(value$calls, initial$calls)
})

testthat::test_that("a real invalid_grant retires local access without replaying SQL", {
  fixture_check_refresh_rejection()
})

testthat::test_that("normal reads renew naturally expired browser credentials", {
  fixture_check_natural_expiry()
})
