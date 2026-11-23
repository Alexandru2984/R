source("../../R/db.R")
source("../../R/auth.R")
source("../../R/audit.R")
source("../../R/import.R")
source("../../R/detection_rules.R")
source("../../R/scoring.R")
source("../../R/analytics.R")
source("../../R/comparison.R")

test_that("PostgreSQL imports are atomic, deduplicated and accurately summarized", {
  skip_if(!nzchar(Sys.getenv("TEST_DB_NAME")), "Set TEST_DB_NAME to an isolated test database")
  con <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("TEST_DB_NAME"),
    host = Sys.getenv("TEST_DB_HOST", ""), user = Sys.getenv("TEST_DB_USER", Sys.info()[["user"]]),
    password = Sys.getenv("TEST_DB_PASSWORD", ""))
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  schema <- paste0("rtraffic_test_", Sys.getpid(), "_", sample.int(1e8, 1))
  DBI::dbExecute(con, paste("CREATE SCHEMA", schema))
  on.exit(DBI::dbExecute(con, paste("DROP SCHEMA", schema, "CASCADE")), add = TRUE, after = FALSE)
  DBI::dbExecute(con, paste("SET search_path TO", schema))
  for (file in c("../../scripts/init_db.sql", sort(list.files("../../scripts/migrations", pattern = "[.]sql$", full.names = TRUE)))) {
    DBI::dbExecute(con, paste(readLines(file), collapse = "\n"), immediate = TRUE)
  }
  row <- data.frame(ip_address = "192.0.2.1", timestamp = as.POSIXct("2026-11-22 12:00:00", tz = "UTC"),
    method = "GET", path = "/", protocol = "HTTP/1.1", status_code = 200L, response_size = 12,
    referrer = "-", user_agent = "Mozilla", bot_score = 0, classification = "likely_human")
  prepared <- list(data = row, rejected = 0L, hash = paste(rep("a", 64), collapse = ""), type = "nginx")
  first <- import_requests(con, prepared, "sample.log")
  expect_equal(first$accepted, 1L)
  events <- DBI::dbGetQuery(con, "SELECT * FROM admin_audit_events")
  expect_equal(events$action, "import_completed")
  expect_equal(events$accepted_rows, 1L)
  expect_error(import_requests(con, prepared, "renamed.log"), "already been imported")
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM requests")$n, 1)
  prepared$hash <- paste(rep("b", 64), collapse = "")
  prepared$rejected <- -1L
  expect_error(import_requests(con, prepared, "failure.log"), "check constraint")
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM requests")$n, 1)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM imported_log_files")$n, 1)
  prepared$rejected <- 0L
  prepared$data <- rbind(row, transform(row, path = "/.env", bot_score = 8, classification = "scanner"))
  import_requests(con, prepared, "next.log")
  summary <- DBI::dbGetQuery(con, "SELECT * FROM ip_summary")
  expect_equal(summary$total_requests, 3L)
  expect_equal(summary$unique_paths, 2L)
  expect_equal(summary$classification, "scanner")
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM import_registry")$n, 2)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM admin_audit_events")$n, 2)
  read_pool <- pool::dbPool(RPostgres::Postgres(), dbname = Sys.getenv("TEST_DB_NAME"),
    host = Sys.getenv("TEST_DB_HOST", ""), user = Sys.getenv("TEST_DB_USER", Sys.info()[["user"]]),
    password = Sys.getenv("TEST_DB_PASSWORD", ""), options = paste0("-c search_path=", schema, " -c timezone=UTC"))
  on.exit(pool::poolClose(read_pool), add = TRUE, after = FALSE)
  f <- normalize_filters(c("2026-11-22", "2026-11-22"), today = as.Date("2026-11-23"))
  s <- load_traffic_snapshot(read_pool, f, compare = TRUE)
  expect_equal(nrow(s$data), 3L)
  expect_equal(s$comparison$metrics$total, 0L)
  expect_equal(query_db(read_pool, "SHOW transaction_read_only")$transaction_read_only, "off")
  prepared$hash <- paste(rep("c", 64), collapse = "")
  expect_error(import_requests(con, prepared, "audit-failure.log", actor = "bad\nactor"), "Invalid audit actor")
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM requests")$n, 3)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM import_registry")$n, 2)
})
