test_that("Databricks clients expose serializable worker configuration", {
  skip_if_not_installed("brickster", "0.2.14")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_databricks_api(auth$connection, "workspace.example")
    spec <- .odb_task_source(api)
    expect_length(spec$plans, 1L)
    expect_silent(.odb_task_plain(spec$worker$args))
    expect_identical(unserialize(serialize(spec$worker, NULL)), spec$worker)
  })
})
