# These tests run only in the explicit Docker integration runner. Missing
# infrastructure is a failure; there are no optional skips or token fixtures.

testthat::test_that("browser PKCE users receive their PostgreSQL grants and lifecycle", {
  fixture <- postgres_browser_setup()
  on.exit(fixture$close(), add = TRUE)
  browser_a <- fixture$new_browser()
  browser_b <- fixture$new_browser()
  testthat::expect_true(postgres_browser_value(browser_a, "document.querySelector('#load').disabled"))
  testthat::expect_true(postgres_browser_value(browser_a, "document.querySelector('#refresh').disabled"))
  testthat::expect_identical(postgres_browser_value(browser_a,
    "document.querySelector('#snapshot').getBoundingClientRect().height"), 0L)
  browser_a$Page$bringToFront()
  postgres_browser_value(browser_a, "document.querySelector('summary').focus()")
  testthat::expect_identical(postgres_browser_value(browser_a, "document.activeElement.tagName"), "SUMMARY")
  browser_a$Input$dispatchKeyEvent(type = "keyDown", key = " ", code = "Space", windowsVirtualKeyCode = 32L)
  browser_a$Input$dispatchKeyEvent(type = "keyUp", key = " ", code = "Space", windowsVirtualKeyCode = 32L)
  testthat::expect_true(postgres_browser_value(browser_a, "document.querySelector('details').open"))
  browser_a$Input$dispatchKeyEvent(type = "keyDown", key = " ", code = "Space", windowsVirtualKeyCode = 32L)
  browser_a$Input$dispatchKeyEvent(type = "keyUp", key = " ", code = "Space", windowsVirtualKeyCode = 32L)
  testthat::expect_false(postgres_browser_value(browser_a, "document.querySelector('details').open"))
  testthat::expect_identical(postgres_browser_value(browser_a, "document.documentElement.lang"), "en")
  login_a <- postgres_browser_login(browser_a, "alice", fixture$config)
  login_b <- postgres_browser_login(browser_b, "bob", fixture$config)
  for (login in list(login_a, login_b)) {
    testthat::expect_identical(login$metadata$response_type, "code")
    testthat::expect_identical(login$metadata$pkce_method, "S256")
    testthat::expect_true(login$metadata$has_s256_challenge)
    testthat::expect_true(login$snapshot$authorized)
  }

  testthat::expect_false(identical(
    login_a$snapshot$authorization_id,
    login_b$snapshot$authorization_id
  ))

  # Ordinary Shiny reactivity performs the initial read after authorization.
  a <- postgres_browser_wait(browser_a, function(value) {
    !is.null(value$result) || !is.null(value$error)
  })
  b <- postgres_browser_wait(browser_b, function(value) {
    !is.null(value$result) || !is.null(value$error)
  })

  testthat::expect_null(a$error)
  testthat::expect_null(b$error)
  testthat::expect_identical(a$result$database_user, "alice")
  testthat::expect_identical(b$result$database_user, "bob")
  testthat::expect_identical(
    unlist(a$result$markers),
    c("alice-visible-1", "alice-visible-2")
  )
  testthat::expect_identical(
    unlist(b$result$markers),
    c("bob-visible-1", "bob-visible-2")
  )
  testthat::expect_false(identical(a$result$backend_pid, b$result$backend_pid))
  alice_table <- postgres_browser_value(browser_a, "document.querySelector('#rows').textContent")
  bob_table <- postgres_browser_value(browser_b, "document.querySelector('#rows').textContent")
  testthat::expect_match(alice_table, "alice-visible-1", fixed = TRUE)
  testthat::expect_false(grepl("bob-visible", alice_table, fixed = TRUE))
  testthat::expect_match(bob_table, "bob-visible-1", fixed = TRUE)
  testthat::expect_false(grepl("alice-visible", bob_table, fixed = TRUE))
  testthat::expect_match(postgres_browser_value(browser_a,
    "document.querySelector('#session_status').textContent"), "alice", fixed = TRUE)
  testthat::expect_match(postgres_browser_value(browser_a,
    "document.querySelector('#action_status').textContent"), "Loaded 2 rows", fixed = TRUE)

  for (entry in list(
    list(browser = browser_a, before = a),
    list(browser = browser_b, before = b)
  )) {
    postgres_browser_click(entry$browser, "request_other_role")
    denied <- postgres_browser_wait(entry$browser, function(value) {
      value$role_probe_attempts >= 1
    })

    testthat::expect_true(denied$other_role_denied)
    testthat::expect_identical(
      denied$authorization_id,
      entry$before$authorization_id
    )
    testthat::expect_identical(denied$result, entry$before$result)
    testthat::expect_identical(
      denied$query_attempts,
      entry$before$query_attempts
    )
    testthat::expect_identical(
      denied$connect_attempts,
      entry$before$connect_attempts
    )
    testthat::expect_true(denied$hook_restored)
    testthat::expect_match(postgres_browser_value(entry$browser,
      "document.querySelector('#role_status').textContent"), "other role was rejected", fixed = TRUE)

    postgres_browser_click(entry$browser, "probe_table_grants")
    grants <- postgres_browser_wait(entry$browser, function(value) {
      value$grant_probe_attempts >= 1
    })

    testthat::expect_true(grants$own_table_allowed)
    testthat::expect_true(grants$other_table_denied)
    testthat::expect_identical(grants$result, entry$before$result)
    testthat::expect_identical(
      grants$connect_attempts,
      entry$before$connect_attempts
    )
  }

  postgres_browser_click(browser_a, "probe_table_grants")
  postgres_browser_wait(browser_a, function(value) value$grant_probe_attempts >= 2L)
  testthat::expect_match(postgres_browser_value(browser_a,
    "document.querySelector('#action_status').textContent"), "Table access checked", fixed = TRUE)
  postgres_browser_click(browser_a, "probe_native_scope")
  postgres_browser_wait(browser_a, function(value) value$native_scope_probe_attempts >= 1L)
  testthat::expect_match(postgres_browser_value(browser_a,
    "document.querySelector('#scope_status').textContent"), "accepted", fixed = TRUE)
  writeBin(jsonlite::base64_dec(browser_a$Page$captureScreenshot(captureBeyondViewport = TRUE)$data),
    "/results/playground-desktop.png")

  postgres_browser_click(browser_a, "load")
  reused <- postgres_browser_wait(browser_a, function(value) {
    isTRUE(value$query_attempts > a$query_attempts)
  })

  testthat::expect_identical(reused$result$backend_pid, a$result$backend_pid)
  testthat::expect_identical(reused$successful_connections, 1L)

  refresh_click <- postgres_browser_click(browser_a, "refresh")
  testthat::expect_match(refresh_click$message, "Refreshing your token", fixed = TRUE)
  testthat::expect_true(refresh_click$disabled)
  refreshed <- postgres_browser_wait(browser_a, function(value) {
    value$refreshes >= 1 || !is.null(value$error)
  })

  testthat::expect_null(refreshed$error)
  testthat::expect_true(refreshed$credential_rotated)
  testthat::expect_false(refreshed$refreshing)
  testthat::expect_match(postgres_browser_value(browser_a,
    "document.querySelector('#action_status').textContent"), "Token refreshed", fixed = TRUE)
  testthat::expect_identical(
    refreshed$authorization_id,
    reused$authorization_id
  )
  testthat::expect_identical(refreshed$result$markers, reused$result$markers)

  postgres_browser_click(browser_a, "load")
  reused_after_refresh <- postgres_browser_wait(browser_a, function(value) {
    isTRUE(value$query_attempts > refreshed$query_attempts)
  })

  testthat::expect_null(reused_after_refresh$error)
  testthat::expect_identical(reused_after_refresh$result$database_user, "alice")
  testthat::expect_identical(reused_after_refresh$successful_connections, 1L)
  testthat::expect_identical(
    reused_after_refresh$result$backend_pid,
    reused$result$backend_pid
  )

  postgres_browser_click(browser_a, "logout")
  logged_out <- postgres_browser_wait(browser_a, function(value) {
    !isTRUE(value$authorized)
  })

  testthat::expect_null(logged_out$result)
  testthat::expect_true(postgres_browser_value(browser_a, "document.querySelector('#load').disabled"))
  testthat::expect_false(logged_out$held_provider_usable)
  testthat::expect_false(logged_out$held_connection_valid)
  testthat::expect_true(postgres_browser_snapshot(browser_b)$authorized)

  switched_login <- postgres_browser_login(browser_a, "bob", fixture$config)

  testthat::expect_true(switched_login$snapshot$authorized)
  testthat::expect_identical(switched_login$snapshot$result$database_user, "bob")
  testthat::expect_false(identical(
    switched_login$snapshot$authorization_id,
    reused_after_refresh$authorization_id
  ))

  postgres_browser_click(browser_a, "load")
  switched <- postgres_browser_wait(browser_a, function(value) {
    !is.null(value$result) || !is.null(value$error)
  })

  testthat::expect_null(switched$error)
  testthat::expect_identical(switched$result$database_user, "bob")
  testthat::expect_identical(
    unlist(switched$result$markers),
    c("bob-visible-1", "bob-visible-2")
  )

  postgres_browser_click(browser_b, "reset_backend")
  reset <- postgres_browser_wait(browser_b, function(value) {
    value$reset_count >= 1 || !is.null(value$error)
  })

  testthat::expect_null(reset$error)

  before <- reset$query_attempts
  postgres_browser_click(browser_b, "load")
  failed <- postgres_browser_wait(browser_b, function(value) {
    value$query_attempts > before && !is.null(value$error)
  })

  testthat::expect_identical(failed$error, "database_operation_failed")
  testthat::expect_null(failed$result)
  testthat::expect_identical(failed$authorization_id, reset$authorization_id)
  testthat::expect_identical(failed$connect_attempts, reset$connect_attempts)
  testthat::expect_true(failed$authorized)

  postgres_browser_click(browser_b, "retry_native")
  native_failed <- postgres_browser_wait(browser_b, function(value) {
    value$held_query_failures >= 2
  })

  testthat::expect_identical(native_failed$error, "held_native_query_failed")
  testthat::expect_identical(
    native_failed$authorization_id,
    reset$authorization_id
  )
  testthat::expect_identical(
    native_failed$connect_attempts,
    reset$connect_attempts
  )
  testthat::expect_true(native_failed$hook_restored)

  # The public helper can replace a broken handle with the current user's token.
  postgres_browser_click(browser_b, "load")
  recovered <- postgres_browser_wait(browser_b, function(value) {
    is.null(value$error) && !is.null(value$result) &&
      value$query_attempts > native_failed$query_attempts
  })
  testthat::expect_identical(recovered$result$database_user, "bob")
  testthat::expect_identical(unlist(recovered$result$markers),
    c("bob-visible-1", "bob-visible-2"))
  testthat::expect_false(identical(recovered$result$backend_pid, reset$result$backend_pid))
  testthat::expect_identical(recovered$successful_connections, 2L)
  testthat::expect_true(recovered$hook_restored)
  browser_b$Emulation$setDeviceMetricsOverride(width = 375L, height = 812L,
    deviceScaleFactor = 1, mobile = TRUE)
  testthat::expect_true(postgres_browser_value(browser_b,
    "document.documentElement.scrollWidth <= window.innerWidth"))
  writeBin(jsonlite::base64_dec(browser_b$Page$captureScreenshot(captureBeyondViewport = TRUE)$data),
    "/results/playground-mobile.png")
  testthat::expect_identical(postgres_browser_value(browser_a, "window.pgErrors.length"), 0L)
  testthat::expect_identical(postgres_browser_value(browser_b, "window.pgErrors.length"), 0L)
})

testthat::test_that("the playground switches accounts, cancels refresh and stops cleanly", {
  config <- postgres_browser_config()
  config$playground <- TRUE
  fixture <- postgres_browser_setup(config)
  on.exit(fixture$close(), add = TRUE)
  browser <- fixture$new_browser()
  first <- postgres_browser_login(browser, "alice", config)
  switched <- postgres_browser_login(browser, "bob", config)
  testthat::expect_identical(switched$snapshot$result$database_user, "bob")
  testthat::expect_false(identical(first$snapshot$authorization_id, switched$snapshot$authorization_id))
  postgres_browser_value(browser, paste0(
    "document.querySelector('#refresh').click();",
    "document.querySelector('#logout').click();"
  ))
  signed_out <- postgres_browser_wait(browser, function(value) !isTRUE(value$authorized))
  testthat::expect_null(signed_out$result)
  testthat::expect_false(signed_out$refreshing)
  testthat::expect_match(postgres_browser_value(browser,
    "document.querySelector('#action_status').textContent"), "Signed out", fixed = TRUE)
  testthat::expect_identical(postgres_browser_value(browser, "window.pgErrors.length"), 0L)
  postgres_browser_click(browser, "stop_playground")
  fixture$process$wait(timeout = 10000)
  testthat::expect_false(fixture$process$is_alive())
  testthat::expect_identical(fixture$process$get_exit_status(), 0L)
})

testthat::test_that("browser-issued wrong audience is denied by PostgreSQL OAuth", {
  fixture <- postgres_browser_setup(postgres_browser_config(
    "shiny-wrong-audience"
  ))
  on.exit(fixture$close(), add = TRUE)
  browser <- fixture$new_browser()
  login <- postgres_browser_login(browser, "alice", fixture$config)

  testthat::expect_true(login$snapshot$authorized)
  testthat::expect_identical(login$metadata$client_id, "shiny-wrong-audience")

  denied <- postgres_browser_wait(browser, function(value) {
    !is.null(value$error)
  })

  testthat::expect_identical(denied$error, "database_operation_failed")
  testthat::expect_identical(denied$connect_attempts, 1L)
  testthat::expect_identical(denied$successful_connections, 0L)
  testthat::expect_null(denied$result)
  testthat::expect_true(denied$hook_restored)
})

testthat::test_that("browser-issued missing scope never reaches PostgreSQL connect", {
  fixture <- postgres_browser_setup(postgres_browser_config(
    "shiny-missing-scope"
  ))
  on.exit(fixture$close(), add = TRUE)
  browser <- fixture$new_browser()
  login <- postgres_browser_login(browser, "alice", fixture$config)

  testthat::expect_true(login$snapshot$authorized)
  testthat::expect_identical(login$metadata$client_id, "shiny-missing-scope")

  testthat::expect_true(postgres_browser_value(browser, "document.querySelector('#load').disabled"))
  denied <- postgres_browser_wait(browser, function(value) {
    identical(value$database_status, "insufficient_scope")
  })

  testthat::expect_null(denied$error)
  testthat::expect_identical(denied$connect_attempts, 0L)
  testthat::expect_identical(denied$successful_connections, 0L)
  testthat::expect_null(denied$result)
  testthat::expect_true(denied$hook_restored)

  postgres_browser_click(browser, "probe_native_scope")
  server_denied <- postgres_browser_wait(browser, function(value) {
    value$native_scope_probe_attempts >= 1
  })

  testthat::expect_true(server_denied$native_scope_denied)
  testthat::expect_identical(server_denied$connect_attempts, 0L)
  testthat::expect_identical(server_denied$successful_connections, 0L)
  testthat::expect_null(server_denied$result)
  testthat::expect_true(server_denied$hook_restored)
})
