test_that("the offline playground exercises connection reuse and A/B isolation", {
  skip_if_not_installed("RSQLite")
  app <- playground_load_example("example-offline.R")$app
  shiny::testServer(app, {
    session$setInputs(select_a = 1L, value = 7L)
    session$setInputs(run_sync = 1L)
    rows_a <- sync_result()
    expect_identical(rows_a$user, c("A", "A"))
    expect_identical(rows_a$requested_value, c(7L, 7L))
    connection_a <- db$connection()
    session$setInputs(value = 8L, run_sync = 2L)
    expect_identical(db$connection(), connection_a)
    expect_identical(sync_result()$requested_value, c(8L, 8L))

    # The same browser replaces its authorization. A's native connection must
    # be retired, and A's already-fetched rows must disappear before B queries.
    session$setInputs(select_b = 1L)
    expect_false(DBI::dbIsValid(connection_a))
    expect_error(sync_result(), class = "shiny.silent.error")
    session$setInputs(run_sync = 3L)
    expect_identical(sync_result()$user, c("B", "B"))
    expect_false(identical(db$connection(), connection_a))

    connection_b <- db$connection()
    session$setInputs(logout = 1L)
    expect_false(DBI::dbIsValid(connection_b))
    expect_error(sync_result(), class = "shiny.silent.error")
    expect_identical(db$status()$status, "waiting_for_authorization")
  })
})

test_that("the offline playground validates bound browser values", {
  skip_if_not_installed("RSQLite")
  app <- playground_load_example("example-offline.R")$app
  shiny::testServer(app, {
    session$setInputs(select_a = 1L, value = -1L, run_sync = 1L)
    expect_error(sync_result(), class = "shiny.silent.error")
    session$setInputs(value = 1.25, run_sync = 2L)
    expect_error(sync_result(), class = "shiny.silent.error")
    session$setInputs(value = 17L, run_sync = 3L)
    expect_identical(sync_result()$requested_value, c(17L, 17L))
  })
})

test_that("separate playground sessions cannot reuse another user's rows", {
  skip_if_not_installed("RSQLite")
  app <- playground_load_example("example-offline.R")$app
  first_connection <- NULL
  shiny::testServer(app, {
    session$setInputs(select_a = 1L, value = 5L, run_sync = 1L)
    expect_identical(sync_result()$user, c("A", "A"))
    first_connection <<- db$connection()
  })
  expect_false(DBI::dbIsValid(first_connection))
  shiny::testServer(app, {
    expect_error(sync_result(), class = "shiny.silent.error")
    session$setInputs(select_b = 1L, value = 9L, run_sync = 1L)
    expect_identical(sync_result()$user, c("B", "B"))
    expect_false(identical(db$connection(), first_connection))
  })
})

test_that("each named playground and live runner is valid R", {
  root <- testthat::test_path("..", "..")
  if (!dir.exists(file.path(root, "playground"))) {
    skip("Source-checkout script smoke; playground scripts are not installed package assets.")
  }
  paths <- list.files(file.path(root, "playground"), pattern = "\\.R$", full.names = TRUE)
  expect_gte(length(paths), 13L)
  for (path in paths) expect_error(parse(path), NA, info = basename(path))
  paths <- list.files(file.path(root, "tests", "integration"), pattern = "\\.R$", full.names = TRUE)
  for (path in paths) expect_error(parse(path), NA, info = basename(path))
})

test_that("live transport tests require an explicit opt-in before configuration", {
  runner <- testthat::test_path("..", "integration", "live-transport.R")
  if (!file.exists(runner)) skip("Live runner requires a source checkout.")
  sys.source(runner, envir = environment())
  withr::local_envvar(c(OAUTHDB_LIVE_TESTS = "false", OAUTHDB_CLIENT_ID = NA_character_))
  expect_error(run_live_transport(list()), "disabled")
})
