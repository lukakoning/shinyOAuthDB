cloud_sql_scope <- "https://www.googleapis.com/auth/sqlservice.login"

cloud_sql_test_helper <- function(authorization, ...) {
  args <- utils::modifyList(
    list(
      authorization = authorization,
      host = "cloudsql.example.org",
      dbname = "reporting",
      user = "analyst@example.org"
    ),
    list(...),
    keep.null = TRUE
  )
  do.call(oauth_db_cloud_sql_postgres, args)
}

test_that("Cloud SQL sign-in requests Google identity and database login", {
  client <- oauth_db_cloud_sql_client("app", "http://localhost:8100", "secret")
  expect_s3_class(client, "shinyOAuth::OAuthClient")
  expect_identical(
    client@provider@auth_url,
    "https://accounts.google.com/o/oauth2/v2/auth"
  )
  expect_setequal(client@scopes, c("openid", "email", cloud_sql_scope))
  expect_false(
    "https://www.googleapis.com/auth/sqlservice.admin" %in% client@scopes
  )
  expect_identical(client@token_targets, list())
  provider <- shinyOAuth::oauth_provider_google(name = "custom-google")
  custom <- oauth_db_cloud_sql_client(
    "app",
    "http://localhost:8100",
    "secret",
    provider = provider,
    scopes = c("openid", cloud_sql_scope),
    required_scopes = cloud_sql_scope,
    label = "Reporting database"
  )
  expect_identical(custom@provider, provider)
  expect_setequal(custom@scopes, c("openid", cloud_sql_scope))
  expect_identical(custom@required_scopes, cloud_sql_scope)
  expect_identical(custom@label, "Reporting database")
})

test_that("Cloud SQL rejects configuration overrides before acquiring a token", {
  for (name in c(
    "password",
    "user",
    "drv",
    "DSN",
    "service",
    "serv",
    "sslmode",
    "ssl-mode",
    "require_auth",
    "gssencmode",
    "passfile",
    "channel_binding",
    "options"
  )) {
    if (name == "user") {
      next
    }
    expect_error(
      do.call(
        cloud_sql_test_helper,
        c(
          list(function() stop("Must not acquire authorization")),
          stats::setNames(list("sensitive-fixture"), name)
        )
      ),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  invalid <- list(
    list(host = "https://cloudsql.example.org"),
    list(host = "first.example,second.example"),
    list(host = "cloudsql.example/db"),
    list(dbname = "host=other.example password=secret"),
    list(dbname = "postgresql://user@other.example/db"),
    list(hostaddr = "host=secret"),
    list(port = NULL),
    list(port = NA_real_),
    list(port = Inf),
    list(port = c(5432, 5433)),
    list(port = 0),
    list(port = 65536),
    list(port = 5432.5),
    list(port = TRUE),
    list(port = "5432"),
    list(user = ""),
    list(user = "reader\nsecret")
  )
  for (args in invalid) {
    error <- expect_error(
      do.call(cloud_sql_test_helper, c(list(NULL), args)),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_false(grepl("secret", conditionMessage(error), fixed = TRUE))
  }
  expect_error(
    cloud_sql_test_helper(NULL, sslcert = "certificate.pem"),
    "both the client certificate"
  )
})

test_that("Cloud SQL PostgreSQL supplies only visitor credentials with verified TLS", {
  skip_if_not_installed("RPostgres")
  captured <- NULL
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      captured <<- list(...)
      "native"
    },
    .package = "DBI"
  )
  withr::local_envvar(c(
    PGSERVICE = NA,
    PGSERVICEFILE = NA,
    PGPASSWORD = "ambient-password",
    GOOGLE_APPLICATION_CREDENTIALS = "ambient-credentials.json"
  ))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = cloud_sql_scope)
    con <- cloud_sql_test_helper(
      auth$connection,
      hostaddr = "192.0.2.1",
      port = 6543L,
      sslrootcert = "ca.pem",
      sslcert = "client.pem",
      sslkey = "client.key",
      connect_timeout = 12,
      bigint = "character"
    )
    expect_null(captured)
    expect_identical(con(), "native")
    expect_identical(
      captured,
      list(
        user = "analyst@example.org",
        password = "fixture-A",
        sslmode = "verify-full",
        gssencmode = "disable",
        require_auth = "password",
        host = "cloudsql.example.org",
        dbname = "reporting",
        port = 6543L,
        hostaddr = "192.0.2.1",
        sslrootcert = "ca.pem",
        sslcert = "client.pem",
        sslkey = "client.key",
        connect_timeout = 12,
        bigint = "character"
      )
    )
  })
})

test_that("Cloud SQL PostgreSQL refuses unsupported libpq and ambient service files", {
  skip_if_not_installed("RPostgres")
  opened <- 0L
  local_mocked_bindings(
    dbConnect = function(...) {
      opened <<- opened + 1L
    },
    dbGetInfo = function(...) list(client.version = package_version("15.0")),
    .package = "DBI"
  )
  withr::local_envvar(c(PGSERVICE = NA, PGSERVICEFILE = NA))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = cloud_sql_scope)
    con <- cloud_sql_test_helper(auth$connection)
    expect_error(con(), "libpq 16", class = "shinyOAuthDB_missing_dependency")
    for (variable in c("PGSERVICE", "PGSERVICEFILE")) {
      withr::with_envvar(stats::setNames("ambient-service", variable), {
        expect_error(con(), "Unset PGSERVICE")
      })
    }
  })
  expect_identical(opened, 0L)
})

test_that("Cloud SQL keeps visitors isolated and replaces credentials without replay", {
  skip_if_not_installed("RSQLite")
  opened <- list()
  local_mocked_bindings(.odb_backend_cloud_sql_postgres = function(
    token,
    settings,
    user,
    options
  ) {
    connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    DBI::dbWriteTable(
      connection,
      "identity",
      data.frame(username = user(), credential = token())
    )
    opened[[length(opened) + 1L]] <<- connection
    connection
  })
  for (target in list(NULL, "cloudsql")) {
    odb_test_domain(function(session) {
      a <- odb_test_authorization(
        session,
        scopes = cloud_sql_scope,
        target = target
      )
      b <- odb_test_authorization(
        session,
        id = "B",
        scopes = cloud_sql_scope,
        target = target
      )
      selected <- shiny::reactiveVal(NULL)
      username <- shiny::reactiveVal("alice@example.org")
      con <- cloud_sql_test_helper(
        selected,
        user = username,
        target = target,
        required_scopes = a$scopes
      )
      expect_error(con(), class = "shiny.silent.error")
      selected(a$connection)
      runs <- 0L
      rows <- shiny::reactive({
        runs <<- runs + 1L
        connection <- con()
        DBI::dbGetQuery(connection, "SELECT * FROM identity")
      })
      expect_identical(rows()$credential, "fixture-A")
      first <- con()
      a$token(a$make_token("renewed-A"))
      session$flushReact()
      expect_identical(rows()$credential, "fixture-A")
      expect_identical(runs, 1L)
      second <- con()
      expect_false(DBI::dbIsValid(first))
      expect_identical(
        DBI::dbGetQuery(second, "SELECT * FROM identity")$credential,
        "renewed-A"
      )
      expect_identical(con(), second)
      username("other-role")
      third <- con()
      expect_false(DBI::dbIsValid(second))
      expect_identical(
        DBI::dbGetQuery(third, "SELECT * FROM identity")$username,
        "other-role"
      )
      selected(b$connection)
      fourth <- con()
      expect_false(DBI::dbIsValid(third))
      expect_identical(
        DBI::dbGetQuery(fourth, "SELECT * FROM identity")$credential,
        "fixture-B"
      )
      b$token(b$make_token("denied-B", permissions = character()))
      expect_error(con(), class = "shiny.silent.error")
      expect_false(DBI::dbIsValid(fourth))
      b$token(b$make_token("restored-B"))
      fifth <- con()
      b$current(FALSE)
      session$flushReact()
      expect_false(DBI::dbIsValid(fifth))
      expect_error(con(), class = "shiny.silent.error")
      b$current(TRUE)
      sixth <- con()
      session$close()
      expect_false(DBI::dbIsValid(sixth))
      expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
    })
  }
  expect_true(all(vapply(
    opened,
    function(con) !DBI::dbIsValid(con),
    logical(1)
  )))
})

test_that("Cloud SQL does not open a driver without the login scope", {
  opened <- resolved <- 0L
  local_mocked_bindings(.odb_backend_cloud_sql_postgres = function(...) {
    opened <<- opened + 1L
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = c("openid", "email"))
    con <- cloud_sql_test_helper(auth$connection, user = function() {
      resolved <<- resolved + 1L
      "analyst@example.org"
    })
    expect_error(con(), class = "shiny.silent.error")
    expect_identical(resolved, 0L)
    expect_identical(auth$calls$acquire, 0L)
  })
  expect_identical(opened, 0L)
})
