fixture_file <- Sys.getenv("OAUTHDB_DREMIO_FIXTURE")
stopifnot(nzchar(fixture_file), file.exists(fixture_file))
fixture <- jsonlite::read_json(fixture_file, simplifyVector = TRUE)

connect_fixture <- function(authorization, ...) {
  oauth_db_dremio(
    authorization,
    host = "localhost",
    port = fixture$port,
    driver = fixture$driver,
    ca_bundle = fixture$ca_bundle,
    timeout = 3,
    ...
  )
}

test_that("the native Flight SQL driver carries separate visitors and renewed tokens", {
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, "B")
    alice <- connect_fixture(a$connection)
    bob <- connect_fixture(b$connection)
    expect_identical(
      DBI::dbGetQuery(alice(), "SELECT CURRENT_USER")$database_user,
      "alice"
    )
    expect_identical(
      DBI::dbGetQuery(bob(), "SELECT CURRENT_USER")$database_user,
      "bob"
    )
    expect_equal(
      DBI::dbGetQuery(
        alice(),
        "SELECT ? AS value",
        params = list(parameter = 17L)
      )$value,
      17
    )
    first <- alice()
    result <- DBI::dbSendQueryArrow(first, "SELECT CURRENT_USER")
    expect_true(DBI::dbIsValid(result))
    a$token(a$make_token("renewed-A"))
    second <- alice()
    expect_false(DBI::dbIsValid(first))
    expect_false(DBI::dbIsValid(result))
    expect_identical(
      DBI::dbGetQuery(second, "SELECT CURRENT_USER")$database_user,
      "alice"
    )
    expect_identical(
      DBI::dbGetQuery(bob(), "SELECT CURRENT_USER")$database_user,
      "bob"
    )
    expect_error(
      DBI::dbGetQuery(second, "SELECT denied", immediate = TRUE),
      "permission denied"
    )
    before_logout <- bob()
    b$current(FALSE)
    expect_error(bob(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(before_logout))
    session$close()
    expect_false(DBI::dbIsValid(second))
  })
  requests <- lapply(
    readLines(file.path(dirname(fixture_file), "requests.jsonl")),
    jsonlite::fromJSON
  )
  labels <- vapply(requests, `[[`, "", "credential")
  expect_true(all(
    c("Bearer fixture-A", "Bearer fixture-B", "Bearer renewed-A") %in% labels
  ))
  expect_false("rejected" %in% labels)
})

test_that("the native Flight SQL driver rejects invalid credentials and untrusted TLS", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("invalid-fixture"))
    con <- connect_fixture(auth$connection)
    expect_error(
      DBI::dbGetQuery(con(), "SELECT CURRENT_USER", immediate = TRUE),
      "bearer rejected"
    )
    auth$token(auth$make_token("fixture-A"))
    untrusted <- oauth_db_dremio(
      auth$connection,
      "localhost",
      port = fixture$port,
      driver = fixture$driver,
      timeout = 1
    )
    expect_error(
      DBI::dbGetQuery(untrusted(), "SELECT CURRENT_USER", immediate = TRUE),
      "certificate|tls|TLS|deadline"
    )
    wrong_host <- oauth_db_dremio(
      auth$connection,
      "127.0.0.1",
      port = fixture$port,
      driver = fixture$driver,
      ca_bundle = fixture$ca_bundle,
      timeout = 1
    )
    expect_error(
      DBI::dbGetQuery(wrong_host(), "SELECT CURRENT_USER", immediate = TRUE),
      "certificate|tls|TLS|deadline"
    )
  })
})
