starrocks_fixture_driver <- "/usr/lib/x86_64-linux-gnu/odbc/libmyodbc9w.so"
starrocks_fixture_plugins <- "/usr/lib/x86_64-linux-gnu/mysql/libmyodbc9/plugin"

starrocks_fixture_admin <- function() {
  DBI::dbConnect(odbc::odbc(), driver = starrocks_fixture_driver,
    SERVER = "localhost", PORT = 9030L, UID = "root", PWD = "",
    SSLMODE = "VERIFY_IDENTITY", SSLCA = "/fixtures/tls/ca-cert.pem")
}


local({
    con <- starrocks_fixture_admin()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    deadline <- Sys.time() + 60
    repeat {
      backends <- DBI::dbGetQuery(con, "SHOW BACKENDS")
      if (nrow(backends) && any(tolower(as.character(backends$Alive)) == "true")) break
      if (Sys.time() > deadline) stop("StarRocks backend readiness failed.", call. = FALSE)
      Sys.sleep(0.5)
    }
    DBI::dbExecute(con, "CREATE DATABASE reporting")
    DBI::dbExecute(con, paste("CREATE TABLE reporting.base_rows (id INT, owner_name VARCHAR(20), marker VARCHAR(50))",
      "DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 1 PROPERTIES ('replication_num'='1')"))
    DBI::dbExecute(con, paste("INSERT INTO reporting.base_rows VALUES",
      "(1,'alice','alice-visible-1'),(2,'alice','alice-visible-2'),",
      "(3,'bob','bob-visible-1'),(4,'bob','bob-visible-2')"))
    principal <- "split_part(regexp_replace(current_user(), '[^a-z_@]', ''), '@', 1)"
    DBI::dbExecute(con, paste("CREATE VIEW reporting.visible_rows AS SELECT id,", principal,
      "AS database_user, marker FROM reporting.base_rows WHERE owner_name =", principal))
    for (user in c("alice", "bob")) {
      properties <- jsonlite::toJSON(list(
        jwks_url = "http://localhost:18080/realms/shinyoauthdb/protocol/openid-connect/certs",
        principal_field = "preferred_username", required_issuer = "https://localhost:18443/realms/shinyoauthdb",
        required_audience = "local-fixture"), auto_unbox = TRUE)
      DBI::dbExecute(con, paste0("CREATE USER ", user, " IDENTIFIED WITH authentication_jwt AS '", properties, "'"))
      DBI::dbExecute(con, paste0("GRANT SELECT ON VIEW reporting.visible_rows TO USER ", user))
      DBI::dbExecute(con, paste0("CREATE TABLE reporting.", user,
        "_only (marker VARCHAR(50)) DUPLICATE KEY(marker) DISTRIBUTED BY HASH(marker) BUCKETS 1 PROPERTIES ('replication_num'='1')"))
      DBI::dbExecute(con, paste0("INSERT INTO reporting.", user, "_only VALUES ('", user, "-private')"))
      DBI::dbExecute(con, paste0("GRANT SELECT ON reporting.", user, "_only TO USER ", user))
    }

})
