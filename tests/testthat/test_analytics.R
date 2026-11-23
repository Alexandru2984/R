source("../../R/auth.R")
source("../../R/detection_rules.R")
source("../../R/scoring.R")
source("../../R/analytics.R")
source("../../R/demo.R")

test_that("filters reject hostile shapes and bound the date window", {
  today <- as.Date("2026-11-23")
  expect_error(normalize_filters(c(today - 31, today), today = today), "31 days")
  expect_error(normalize_filters(c(today, today + 1), today = today), "date range")
  expect_error(normalize_filters(classification = c("All", "scanner")), "filter")
  expect_error(normalize_filters(ip = "' OR TRUE --"), "valid IPv4")
  f <- normalize_filters(path = "' OR TRUE --%_")
  query <- request_query(f)
  expect_false(grepl("OR TRUE", query$sql, fixed = TRUE))
  expect_true("' OR TRUE --%_" %in% query$params)
})

test_that("demo data is current and uses documentation IP addresses", {
  set.seed(19)
  before <- .Random.seed
  now <- as.POSIXct("2026-11-23 12:00:00", tz = "UTC")
  d <- generate_demo_data(500L, now)
  expect_identical(.Random.seed, before)
  expect_true(all(d$timestamp <= now & d$timestamp > now - 7 * 86400))
  expect_true(all(grepl("^(192[.]0[.]2|198[.]51[.]100|203[.]0[.]113)[.]", d$ip_address)))
  f <- normalize_filters(dates = c(as.Date(now) - 6, as.Date(now)), today = as.Date(now))
  d <- filter_demo(d, f)
  snapshot <- finish_snapshot(d, f, "Synthetic demo")
  expect_equal(traffic_metrics(snapshot$data)$total, nrow(d))
  expect_true(all(nzchar(snapshot$data$reason)))
  expect_true(any(grepl("Synthetic demo", traffic_report(snapshot), fixed = TRUE)))
})

test_that("classification filters and reports use the same snapshot", {
  f <- normalize_filters(classification = "scanner")
  s <- finish_snapshot(generate_demo_data(500L), f, "Synthetic demo")
  expect_true(all(s$data$classification == "scanner"))
  expect_equal(traffic_metrics(s$data)$flagged, nrow(s$data))
  expect_true(any(grepl(paste("Requests:", nrow(s$data)), traffic_report(s), fixed = TRUE)))
})

test_that("CSV exports neutralize spreadsheet formulas including whitespace prefixes", {
  data <- data.frame(path = c("=1+1", " +cmd", "@SUM(A1)", "-cmd", "\tformula", "/safe", NA_character_), status = 200L)
  result <- spreadsheet_safe(data)
  expect_true(all(startsWith(result$path[1:5], "'")))
  expect_identical(result$path[6:7], data$path[6:7])
  expect_identical(result$status, data$status)
})

test_that("an empty database snapshot retains its typed analysis columns", {
  d <- generate_demo_data(10L)
  d <- d[0, setdiff(names(d), c("classification", "bot_score"))]
  s <- finish_snapshot(d, normalize_filters(), "Live production")
  expect_true(all(c("classification", "bot_score", "reason") %in% names(s$data)))
  expect_equal(traffic_metrics(s$data)$error_rate, 0)
  expect_equal(nrow(ip_investigation(s$data)), 0L)
})
