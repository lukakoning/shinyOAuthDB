test_that("malformed permission evidence cannot acquire a token or open a connection", {
  invalid <- list(NULL, logical(), NA, 1, "TRUE", c(TRUE, FALSE))
  for (permissions in invalid) {
    odb_test_domain(function(session) {
      acquired <- opened <- 0L
      grant <- list(
        id = "permission-contract",
        has_scopes = function(scopes, target = NULL) permissions,
        access_token = function(...) {
          acquired <<- acquired + 1L
          "fixture-token"
        }
      )
      con <- oauth_db_connect(
        grant,
        required_scopes = "read",
        connect = function(token) {
          opened <<- opened + 1L
          new.env()
        }
      )
      expect_error(con(), class = "shinyOAuthDB_invalid_authorization")
      session$flushReact()
      expect_error(con(), class = "shinyOAuthDB_invalid_authorization")
      expect_identical(acquired, 0L)
      expect_identical(opened, 0L)
    })
  }
  odb_test_domain(function(session) {
    allowed <- shiny::reactiveVal(FALSE)
    acquired <- opened <- 0L
    grant <- list(
      id = "valid-permissions",
      has_scopes = function(scopes, target = NULL) allowed(),
      access_token = function(...) {
        acquired <<- acquired + 1L
        "fixture-token"
      }
    )
    con <- oauth_db_connect(
      grant,
      required_scopes = "read",
      connect = function(token) {
        opened <<- opened + 1L
        expect_identical(token, "fixture-token")
        new.env()
      }
    )
    expect_error(con(), class = "shiny.silent.error")
    expect_identical(acquired, 0L)
    expect_identical(opened, 0L)
    allowed(TRUE)
    session$flushReact()
    expect_type(con(), "environment")
    expect_identical(acquired, 1L)
    expect_identical(opened, 1L)
  })
})

test_that("unexpected expiry validation failures remain errors rather than permission evidence", {
  errors <- list(
    errorCondition(
      "fixture provider failure",
      class = "fixture_provider_error"
    ),
    structure(
      list(
        message = "Unsupported token target",
        call = NULL,
        context = list(reason = "unsupported_target")
      ),
      class = c("shinyOAuth_access_error", "error", "condition")
    )
  )
  for (problem in errors) {
    odb_test_domain(function(session) {
      opened <- 0L
      grant <- list(
        id = "expiry-validation",
        has_scopes = function(scopes, target = NULL) TRUE,
        summary = function() list(status = "expired"),
        access_token = function(...) stop(problem)
      )
      con <- oauth_db_connect(
        grant,
        required_scopes = "read",
        connect = function(token) {
          opened <<- opened + 1L
          new.env()
        }
      )
      for (attempt in 1:2) {
        failure <- tryCatch(con(), error = identity)
        expect_identical(class(failure), class(problem))
        expect_identical(conditionMessage(failure), conditionMessage(problem))
        expect_identical(failure$context, problem$context)
        session$flushReact()
      }
      expect_identical(opened, 0L)
    })
  }
})

test_that("authorization identities and protocol methods are validated before use", {
  invalid_ids <- list(
    NULL,
    character(),
    "",
    NA_character_,
    NA,
    1L,
    TRUE,
    c("A", "B")
  )
  invalid_grants <- lapply(invalid_ids, function(id) {
    list(
      id = id,
      has_scopes = function(...) stop("Must not check permissions"),
      access_token = function(...) stop("Must not acquire a token")
    )
  })
  for (method in c("has_scopes", "access_token")) {
    for (invalid in list(NULL, "method", TRUE)) {
      grant <- list(
        id = "valid-id",
        has_scopes = function(...) TRUE,
        access_token = function(...) "fixture-token"
      )
      grant[method] <- list(invalid)
      invalid_grants[[length(invalid_grants) + 1L]] <- grant
    }
  }
  for (grant in invalid_grants) {
    odb_test_domain(function(session) {
      opened <- 0L
      factories <- list(function(auth) oauth_db_token(auth), function(auth) {
        oauth_db_connect(auth, connect = function(token) {
          opened <<- opened + 1L
          token
        })
      })
      for (factory in factories) {
        static_error <- tryCatch(factory(grant), error = identity)
        expect_s3_class(static_error, "shinyOAuthDB_invalid_authorization")
        selected <- shiny::reactiveVal(grant)
        accessor <- factory(selected)
        reactive_error <- tryCatch(accessor(), error = identity)
        expect_s3_class(reactive_error, "shinyOAuthDB_invalid_authorization")
        session$flushReact()
        expect_error(accessor(), class = "shinyOAuthDB_invalid_authorization")
      }
      expect_identical(opened, 0L)
    })
  }
  odb_test_domain(function(session) {
    for (id in c("0", "valid-id")) {
      grant <- list(
        id = id,
        has_scopes = function(...) TRUE,
        access_token = function(...) "fixture-token"
      )
      expect_identical(oauth_db_token(grant)(), "fixture-token")
      expect_identical(
        oauth_db_connect(grant, connect = function(token) token)(),
        "fixture-token"
      )
    }
  })
})

test_that("an invalid selected authorization closes SQL access and recovers after correction", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    selected <- shiny::reactiveVal(auth$connection)
    opened <- 0L
    con <- oauth_db_connect(selected, connect = function(token) {
      opened <<- opened + 1L
      native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      DBI::dbWriteTable(native, "identity", data.frame(token = token))
      native
    })
    first <- con()
    selected(list(
      id = "",
      has_scopes = function(...) TRUE,
      access_token = function(...) "invalid-grant-token"
    ))
    session$flushReact()
    expect_false(DBI::dbIsValid(first))
    expect_error(con(), class = "shinyOAuthDB_invalid_authorization")
    expect_identical(opened, 1L)
    auth$token(auth$make_token("corrected-token"))
    selected(auth$connection)
    session$flushReact()
    replacement <- con()
    expect_identical(
      DBI::dbReadTable(replacement, "identity")$token,
      "corrected-token"
    )
    expect_false(identical(first, replacement))
    expect_identical(con(), replacement)
    expect_identical(opened, 2L)
  })
})
