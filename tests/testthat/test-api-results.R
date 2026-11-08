api_result_fixture <- function(session, backend) {
  skip_if_not_installed(
    if (backend == "fabric") "fabricQueryR" else "brickster",
    if (backend == "fabric") "1.0.1" else "0.2.14"
  )
  auth <- if (backend == "fabric") {
    odb_test_fabric_authorization(session, services = "fabric")
  } else {
    odb_test_authorization(session)
  }
  replacement <- if (backend == "fabric") {
    odb_test_fabric_authorization(session, id = "B", services = "fabric")
  } else {
    odb_test_authorization(session, "B")
  }
  selected <- shiny::reactiveVal(auth$connection)
  api <- if (backend == "fabric") {
    oauth_db_fabric_api(selected, targets = c(fabric = "fabric"))
  } else {
    oauth_db_databricks_api(
      selected,
      "workspace.example",
      required_scopes = "read"
    )
  }
  list(
    call = api$call,
    credential = function(token) {
      if (is.function(token)) {
        token("https://api.fabric.microsoft.com/.default")
      } else {
        token
      }
    },
    change = function(transition) {
      switch(
        transition,
        replace = selected(replacement$connection),
        logout = selected(NULL),
        session_end = session$close(),
        rotate = if (backend == "fabric") {
          tokens <- auth$tokens()
          tokens$fabric <- auth$make_token("fabric", "rotated")
          auth$tokens(tokens)
        } else {
          auth$token(auth$make_token("rotated"))
        },
        permissions = if (backend == "fabric") {
          tokens <- auth$tokens()
          tokens$fabric <- auth$make_token(
            "fabric",
            "denied",
            scopes = character()
          )
          auth$tokens(tokens)
        } else {
          auth$token(auth$make_token("denied", "write"))
        }
      )
    }
  )
}

test_that("native API calls discard results when authorization changes during execution", {
  for (backend in c("fabric", "databricks")) {
    for (transition in c("replace", "logout", "permissions", "session_end")) {
      odb_test_domain(function(session) {
        fixture <- api_result_fixture(session, backend)
        expect_error(
          fixture$call(function(token, ...) {
            value <- fixture$credential(token)
            fixture$change(transition)
            value
          }),
          class = "shinyOAuthDB_authorization_unavailable",
          info = paste(backend, transition)
        )
      })
    }
  }
})

test_that("native API result checks preserve token rotation, visibility and native failures", {
  for (backend in c("fabric", "databricks")) {
    odb_test_domain(function(session) {
      fixture <- api_result_fixture(session, backend)
      first <- fixture$call(function(token, ...) fixture$credential(token))
      result <- withVisible(fixture$call(function(token, ...) {
        value <- fixture$credential(token)
        fixture$change("rotate")
        invisible(value)
      }))
      expect_identical(result, list(value = first, visible = FALSE))
      failure <- errorCondition("native failure", class = "native_api_failure")
      error <- tryCatch(
        fixture$call(function(token, ...) stop(failure)),
        error = identity
      )
      expect_identical(error, failure)
    })
  }
})

test_that("Fabric discards results after an optional operation permission is lost", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  resource <- "https://api.fabric.microsoft.com"
  base <- paste0(resource, "/Workspace.Read.All")
  operation <- paste0(resource, "/Item.Read.All")
  client <- oauth_db_microsoft_client(
    client_id = "test",
    redirect_uri = "http://localhost:8100",
    provider = shinyOAuth::oauth_provider_microsoft(
      tenant = "organizations",
      userinfo_required = FALSE
    ),
    token_targets = list(
      fabric = list(
        resource = resource,
        scopes = c(base, operation),
        required_scopes = base
      )
    )
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(
      session,
      client = client,
      target = "fabric",
      resource = resource,
      scopes = c("Workspace.Read.All", "Item.Read.All")
    )
    api <- oauth_db_fabric_api(auth$connection, targets = c(fabric = "fabric"))
    expect_error(
      api$call(function(token) {
        value <- token(operation)
        auth$token(auth$make_token("limited", base))
        value
      }),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
})

api_result_await <- function(promise) {
  result <- new.env(parent = emptyenv())
  result$done <- FALSE
  promise$then(
    onFulfilled = function(value, .visible) {
      result$value <- value
      result$visible <- .visible
      result$done <- TRUE
      NULL
    },
    onRejected = function(error) {
      result$error <- error
      result$done <- TRUE
      NULL
    }
  )
  deadline <- proc.time()[["elapsed"]] + 5
  while (!result$done && proc.time()[["elapsed"]] < deadline) {
    later::run_now(0.01)
  }
  expect_true(result$done)
  as.list(result)
}

test_that("native API promises check authorization when their values resolve", {
  for (backend in c("fabric", "databricks")) {
    for (transition in c(
      "replace",
      "logout",
      "permissions",
      "session_end",
      "rotate"
    )) {
      resolve <- pending <- NULL
      odb_test_domain(function(session) {
        fixture <- api_result_fixture(session, backend)
        pending <<- fixture$call(function(token, ...) {
          value <- fixture$credential(token)
          promises::promise(function(complete, reject) {
            resolve <<- function() complete(invisible(value))
          })
        })
        fixture$change(transition)
        resolve()
        result <- api_result_await(pending)
        if (transition == "rotate") {
          expect_null(result$error)
          expect_false(result$visible)
          expect_identical(
            result$value,
            if (backend == "fabric") "A-fabric" else "fixture-A"
          )
        } else {
          expect_s3_class(
            result$error,
            "shinyOAuthDB_authorization_unavailable"
          )
          expect_null(result$value)
        }
      })
    }
  }
})

test_that("native API promise rejections keep their original failure", {
  for (backend in c("fabric", "databricks")) {
    odb_test_domain(function(session) {
      fixture <- api_result_fixture(session, backend)
      failure <- errorCondition("native failure", class = "native_api_failure")
      pending <- fixture$call(function(token, ...) {
        promises::promise_reject(failure)
      })
      expect_identical(api_result_await(pending)$error, failure)
    })
  }
})

test_that("API promise guards retain their owning session outside the original reactive context", {
  for (backend in c("fabric", "databricks")) {
    session <- shiny::MockShinySession$new()
    tryCatch(
      {
        pending <- shiny::withReactiveDomain(
          session,
          shiny::isolate({
            fixture <- api_result_fixture(session, backend)
            fixture$call(function(token, ...) {
              promises::promise_resolve(fixture$credential(token))
            })
          })
        )
        result <- api_result_await(pending)
        expect_null(result$error)
        expect_identical(
          result$value,
          if (backend == "fabric") "A-fabric" else "fixture-A"
        )
      },
      finally = session$close()
    )
  }
})

test_that("native API results close rejected DBI connections", {
  skip_if_not_installed("RSQLite")
  for (backend in c("fabric", "databricks")) {
    for (async in c(FALSE, TRUE)) {
      odb_test_domain(function(session) {
        fixture <- api_result_fixture(session, backend)
        connection <- NULL
        native <- function(token, ...) {
          fixture$credential(token)
          connection <<- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
          fixture$change("replace")
          if (async) promises::promise_resolve(connection) else connection
        }
        if (async) {
          result <- api_result_await(fixture$call(native))
          expect_s3_class(
            result$error,
            "shinyOAuthDB_authorization_unavailable"
          )
        } else {
          expect_error(
            fixture$call(native),
            class = "shinyOAuthDB_authorization_unavailable"
          )
        }
        expect_false(DBI::dbIsValid(connection))
      })
    }
  }
})
