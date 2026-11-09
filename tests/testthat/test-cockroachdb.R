cockroachdb_test_args <- function(...) {
  c(
    list(host = "sql.example.org", dbname = "reporting", user = "alice"),
    list(...)
  )
}

test_that("CockroachDB rejects ambiguous endpoints and credential overrides before login", {
  invalid <- list(
    list(host = "host,other"),
    list(host = "/tmp"),
    list(host = "@socket"),
    list(host = "postgresql://host/db"),
    list(host = "host\nother"),
    list(host = "host=other"),
    list(dbname = "host=other dbname=reporting"),
    list(dbname = "postgresql://other/reporting"),
    list(user = "alice\nbob"),
    list(port = 0),
    list(port = 65536),
    list(port = NA_real_),
    list(port = 26257.5),
    list(port = "26257"),
    list(connect_timeout = 1),
    list(connect_timeout = Inf),
    list(connect_timeout = 2.5),
    list(connect_timeout = 1e50),
    list(sslrootcert = NA_character_),
    list(password = "secret"),
    list(token = "secret"),
    list(service = "ambient"),
    list(ser = "ambient"),
    list(options = "--crdb:jwt_auth_enabled=false"),
    list(sslmode = "disable"),
    list(sslcert = "client.pem"),
    list(hostaddr = "192.0.2.1"),
    list(require_auth = "none"),
    list(passfile = "ambient"),
    list(drv = "other"),
    list(SSLMode = "disable")
  )
  auth <- function() stop("must not acquire credentials")
  for (replacement in invalid) {
    args <- utils::modifyList(cockroachdb_test_args(), replacement)
    error <- expect_error(
      do.call(oauth_db_cockroachdb, c(list(auth), args)),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_false(grepl("secret", conditionMessage(error), fixed = TRUE))
  }
  expect_error(
    do.call(
      oauth_db_cockroachdb,
      c(list(auth), cockroachdb_test_args(), list(42))
    ),
    "unique names"
  )
})

test_that("CockroachDB requires a driver that can enforce password authentication", {
  skip_if_not_installed("RPostgres")
  local_mocked_bindings(
    dbGetInfo = function(...) list(client.version = package_version("15.0")),
    .package = "DBI"
  )
  expect_error(
    do.call(
      oauth_db_cockroachdb,
      c(list(function() stop("no token")), cockroachdb_test_args())
    ),
    "libpq 16",
    class = "shinyOAuthDB_missing_dependency"
  )
})

test_that("CockroachDB sends only the visitor JWT over verified TLS", {
  skip_if_not_installed("RPostgres")
  args <- NULL
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      args <<- list(...)
      "native"
    },
    .package = "DBI"
  )
  withr::local_envvar(c(
    PGSERVICE = NA,
    PGSERVICEFILE = NA,
    PGOPTIONS = "--crdb:jwt_auth_enabled=false",
    PGPASSWORD = "ambient"
  ))
  jwt <- "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJhbGljZSJ9.c2ln"
  settings <- list(
    host = "sql.example.org",
    dbname = "reporting",
    user = function() "alice",
    port = 26257L,
    sslrootcert = "root.crt",
    connect_timeout = 5L,
    options = list(bigint = "character", application_name = "shiny")
  )
  expect_identical(
    do.call(.odb_backend_cockroachdb, c(list(function() jwt), settings)),
    "native"
  )
  expect_identical(args$password, jwt)
  expect_identical(args$user, "alice")
  expect_identical(args$port, 26257L)
  expect_identical(args$sslmode, "verify-full")
  expect_identical(args$sslrootcert, "root.crt")
  expect_identical(args$require_auth, "password")
  expect_identical(args$gssencmode, "disable")
  expect_identical(args$options, "--crdb:jwt_auth_enabled=true")
  expect_identical(args$bigint, "character")
  expect_identical(args$application_name, "shiny")
  settings$sslrootcert <- NULL
  do.call(
    .odb_backend_cockroachdb,
    c(list(function() jwt), settings, list(sslrootcert = NULL))
  )
  expect_false("sslrootcert" %in% names(args))
  for (value in c("opaque-token", "Bearer a.b.c", "a.b.", "a.b.c\n")) {
    args <- NULL
    expect_error(
      do.call(
        .odb_backend_cockroachdb,
        c(list(function() value), settings, list(sslrootcert = NULL))
      ),
      class = "shinyOAuthDB_invalid_credential"
    )
    expect_null(args)
  }
  for (variable in c("PGSERVICE", "PGSERVICEFILE")) {
    withr::with_envvar(stats::setNames("ambient", variable), {
      expect_error(
        do.call(
          .odb_backend_cockroachdb,
          c(
            list(function() stop("no token")),
            settings,
            list(sslrootcert = NULL)
          )
        ),
        "Unset PGSERVICE",
        fixed = TRUE
      )
    })
  }
})

test_that("CockroachDB rotates credentials without replaying queries and follows SQL users", {
  skip_if_not_installed("RPostgres")
  skip_if_not_installed("RSQLite")
  opened <- list()
  local_mocked_bindings(.odb_backend_cockroachdb = function(token, user, ...) {
    native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    DBI::dbWriteTable(
      native,
      "identity",
      data.frame(user = user(), credential = token())
    )
    opened[[length(opened) + 1L]] <<- native
    native
  })
  retained <- NULL
  for (target in list(NULL, "database")) {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session, target = target)
      user <- shiny::reactiveVal("alice")
      con <- oauth_db_cockroachdb(
        auth$connection,
        "sql.example.org",
        "reporting",
        user,
        target = target
      )
      runs <- 0L
      rows <- shiny::reactive({
        runs <<- runs + 1L
        connection <- con()
        DBI::dbGetQuery(connection, "SELECT * FROM identity")
      })
      expect_identical(
        rows(),
        data.frame(user = "alice", credential = "fixture-A")
      )
      first <- con()
      expect_identical(con(), first)
      auth$token(auth$make_token("renewed-A"))
      session$flushReact()
      expect_identical(rows()$credential, "fixture-A")
      expect_identical(runs, 1L)
      second <- con()
      expect_false(DBI::dbIsValid(first))
      expect_identical(
        DBI::dbGetQuery(second, "SELECT credential FROM identity")$credential,
        "renewed-A"
      )
      expect_identical(con(), second)
      user("bob")
      third <- con()
      expect_false(DBI::dbIsValid(second))
      expect_identical(
        DBI::dbGetQuery(third, "SELECT user FROM identity")$user,
        "bob"
      )
      DBI::dbDisconnect(third)
      retained <<- con()
      expect_true(DBI::dbIsValid(retained))
      auth$current(FALSE)
      expect_error(con(), class = "shiny.silent.error")
      expect_false(DBI::dbIsValid(retained))
      auth$current(TRUE)
      retained <<- con()
    })
    expect_false(DBI::dbIsValid(retained))
  }
  expect_true(all(vapply(opened, function(x) !DBI::dbIsValid(x), logical(1))))
})

test_that("CockroachDB closes handles on account and permission changes", {
  skip_if_not_installed("RPostgres")
  skip_if_not_installed("RSQLite")
  local_mocked_bindings(.odb_backend_cockroachdb = function(...) {
    DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  })
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, id = "B")
    selected <- shiny::reactiveVal(a$connection)
    role_calls <- 0L
    con <- oauth_db_cockroachdb(
      selected,
      "sql.example.org",
      "reporting",
      function() {
        role_calls <<- role_calls + 1L
        "reader"
      },
      required_scopes = "write"
    )
    first <- con()
    selected(b$connection)
    second <- con()
    expect_false(DBI::dbIsValid(first))
    b$token(b$make_token("reduced-B", permissions = "read"))
    session$flushReact()
    expect_false(DBI::dbIsValid(second))
    role_calls <- 0L
    expect_error(con(), class = "shiny.silent.error")
    expect_identical(role_calls, 0L)
  })
})
