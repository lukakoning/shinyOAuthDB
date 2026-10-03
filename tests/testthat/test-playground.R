test_that("the offline app reads through native connections and follows A/B selection", {
  skip_if_not_installed("RSQLite")
  app <- playground_load_example("example-offline.R")
  saved <- NULL
  shiny::testServer(app$server, {
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(select_a = 1L)
    expect_match(output$rows, ">\\s*A\\s*<")
    con_a <- con()
    expect_identical(con(), con_a)

    session$setInputs(select_b = 1L)
    expect_false(DBI::dbIsValid(con_a))
    expect_match(output$rows, ">\\s*B\\s*<")
    expect_false(grepl(">\\s*A\\s*<", output$rows))
    con_b <- con()
    session$setInputs(logout = 1L)
    expect_false(DBI::dbIsValid(con_b))
    expect_error(output$rows, class = "shiny.silent.error")

    session$setInputs(select_a = 2L)
    expect_match(output$rows, ">\\s*A\\s*<")
    saved <<- con()
  })
  expect_false(DBI::dbIsValid(saved))
})

test_that("separate offline sessions cannot reuse another user's connection", {
  skip_if_not_installed("RSQLite")
  app <- playground_load_example("example-offline.R")
  first_connection <- NULL
  shiny::testServer(app$server, {
    session$setInputs(select_a = 1L)
    expect_match(output$rows, ">\\s*A\\s*<")
    first_connection <<- con()
  })
  expect_false(DBI::dbIsValid(first_connection))
  shiny::testServer(app$server, {
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(select_b = 1L)
    expect_match(output$rows, ">\\s*B\\s*<")
    expect_false(identical(con(), first_connection))
  })
})

test_that("all complete playground examples parse", {
  root <- testthat::test_path("..", "..", "playground")
  if (!dir.exists(root)) skip("Playground examples require a source checkout.")
  paths <- list.files(root, pattern = "\\.R$", full.names = TRUE)
  for (path in paths) expect_error(parse(path), NA, info = basename(path))
})
