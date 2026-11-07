testthat::test_that("both public Databricks helpers execute real local SQL and rotate copied credentials", {
  fixture <- fixture_setup()
  on.exit(fixture$close(), add = TRUE)
  browser <- fixture$new_browser()
  before <- fixture_snapshot(browser)
  testthat::expect_false(before$authorized)
  testthat::expect_null(before$result)
  login <- fixture_login(browser, "alice", fixture$config)
  testthat::expect_identical(login$metadata$pkce_method, "S256")
  testthat::expect_true(login$metadata$challenge_valid)
  initial <- fixture_wait(browser, function(x) {
    !is.null(x$result) || !is.null(x$error)
  })
  testthat::expect_null(initial$error)
  testthat::expect_identical(
    vapply(initial$result, `[[`, "", "marker"),
    paste0("alice-visible-", 1:2)
  )
  for (row in initial$result) {
    testthat::expect_true(row$dbi_token_current)
    testthat::expect_true(row$api_token_current)
  }
  fixture_click(browser, "data")
  data <- fixture_wait(
    browser,
    function(x) !is.null(x$data_checks),
    timeout = 90
  )
  testthat::expect_null(data$data_error)
  testthat::expect_true(integration_require_checks(
    data$data_checks,
    integration_check_names("minilake", "data"),
    "MiniLake data checks"
  ))
  fixture_click(browser, "load")
  reused <- fixture_wait(browser, function(x) x$calls > data$calls)
  testthat::expect_identical(
    reused$result[[1L]]$generation,
    initial$result[[1L]]$generation
  )
  fixture_click(browser, "refresh")
  refreshed <- fixture_wait(browser, function(x) x$refreshes == 1L)
  testthat::expect_true(refreshed$rotated)
  testthat::expect_identical(refreshed$calls, reused$calls)
  fixture_click(browser, "load")
  current <- fixture_wait(browser, function(x) x$calls > reused$calls)
  testthat::expect_null(current$error)
  testthat::expect_identical(
    current$result[[1L]]$generation,
    reused$result[[1L]]$generation + 1L
  )
  testthat::expect_true(current$result[[1L]]$old_token_replaced)
  testthat::expect_true(current$result[[1L]]$dbi_token_current)
  testthat::expect_true(current$result[[1L]]$api_token_current)
  fixture_login(browser, "bob", fixture$config)
  direct <- fixture_wait(browser, function(x) {
    !identical(x$authorization_id, initial$authorization_id) &&
      !is.null(x$result) &&
      identical(x$result[[1L]]$marker, "bob-visible-1")
  })
  # OAuth navigation creates a new Shiny session, whose connection count starts at one.
  testthat::expect_identical(direct$result[[1L]]$generation, 1L)
  testthat::expect_true(direct$result[[1L]]$dbi_token_current)
  fixture_click(browser, "logout")
  logged_out <- fixture_wait(browser, function(x) !isTRUE(x$authorized))
  testthat::expect_null(logged_out$result)
  fixture_login(browser, "bob", fixture$config)
  switched <- fixture_wait(browser, function(x) !is.null(x$result))
  testthat::expect_false(identical(
    switched$authorization_id,
    initial$authorization_id
  ))
  testthat::expect_identical(
    vapply(switched$result, `[[`, "", "marker"),
    paste0("bob-visible-", 1:2)
  )
  testthat::expect_true(switched$result[[1L]]$dbi_token_current)
  testthat::expect_true(switched$result[[1L]]$api_token_current)
})

testthat::test_that("a real invalid_grant retires local access without replaying SQL", {
  fixture_check_refresh_rejection()
})

testthat::test_that("normal reads renew naturally expired browser credentials", {
  fixture_check_natural_expiry()
})

testthat::test_that("the bridge blocks missing Databricks operation scopes before SQL", {
  fixture <- fixture_setup(fixture_config("shiny-missing-scope"))
  on.exit(fixture$close(), add = TRUE)
  browser <- fixture$new_browser()
  fixture_login(browser, "alice", fixture$config)
  fixture_click(browser, "load")
  value <- fixture_snapshot(browser)
  testthat::expect_null(value$result)
  testthat::expect_identical(value$calls, 0L)
})
