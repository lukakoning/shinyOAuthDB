test_that("custom token attributes never carry provider state into transports or workers", {
  odb_test_domain(function(session) {
    framework <- new.env(parent = emptyenv())
    framework$refresh_token <- "framework-refresh-secret"
    framework$client_secret <- "framework-client-secret"

    custom <- oauth_db_authorization(
      "metadata-grant",
      access_token = function(
        required_scopes,
        min_valid_for,
        force_refresh,
        async,
        target = NULL
      ) {
        token <- structure(
          "only-bearer-token",
          framework = framework,
          callback = function() framework$refresh_token
        )

        if (async) promises::promise_resolve(token) else token
      },

      has_scopes = function(scopes, target = NULL) all(scopes %in% "read")
    )

    db <- oauth_db_session(odb_test_source(), custom)
    token <- db$token_provider()()

    expect_identical(token, "only-bearer-token")
    expect_null(attributes(token))

    capture <- db$.capture()
    value <- NULL
    promises::then(db$.acquire(capture, async = TRUE), function(token) {
      value <<- token
    })

    odb_test_drain(session, until = function() !is.null(value))

    expect_identical(value, "only-bearer-token")
    expect_null(attributes(value))
    expect_silent(.odb_task_check_plain(list(token = value), "worker token"))
  })
})
