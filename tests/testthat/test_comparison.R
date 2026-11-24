for (module in c("auth", "detection_rules", "scoring", "analytics", "demo")) source(paste0("../../R/", module, ".R"))
source("../../R/comparison.R")

test_that("previous periods preserve filters and have equal inclusive UTC lengths", {
  current <- normalize_filters(c(as.Date("2026-11-17"), as.Date("2026-11-23")), ip = "192.0.2.1", path = "/api", today = as.Date("2026-11-23"))
  previous <- previous_period_filters(current)
  expect_equal(previous$start, as.Date("2026-11-10"))
  expect_equal(previous$end, current$start - 1)
  expect_identical(previous[c("ip", "path", "status", "method", "classification")], current[c("ip", "path", "status", "method", "classification")])
})

test_that("comparison avoids infinite percentages and rates for empty periods", {
  expect_equal(relative_change(10, 0), "New activity; no baseline")
  expect_equal(relative_change(0, 0), "No change")
  expect_equal(relative_change(15, 10), "+50.0%")
  expect_equal(relative_change(0, 10), "-100.0%")
  empty <- traffic_metrics(generate_demo_data(10L)[0, ])
  current <- traffic_metrics(generate_demo_data(20L))
  rows <- comparison_rows(current, empty)
  expect_equal(rows$Change[rows$Metric == "HTTP error rate"], "Insufficient requests")
  expect_false(any(grepl("Inf|NaN", unlist(rows))))
})

test_that("activity map keeps counts and UTC weekday/hour boundaries", {
  d <- data.frame(timestamp = as.POSIXct(c("2026-11-22 23:59:59", "2026-11-23 00:00:00", "2026-11-23 00:01:00"), tz = "UTC"))
  map <- traffic_heatmap(d)
  expect_equal(dim(map), c(7L, 24L))
  expect_equal(sum(map), 3)
  expect_equal(map["Sun", "23:00"], 1)
  expect_equal(map["Mon", "00:00"], 2)
})

test_that("untrusted country/method labels are classified without becoming chart markup", {
  d <- data.frame(country = c("ro", NA, "<svg>", "US"), method = c("GET", "POST", "<svg>", NA))
  countries <- country_distribution(d)
  expect_equal(sum(countries$Requests), 4)
  expect_equal(countries$Requests[countries[[1]] == "Unknown"], 2)
  expect_false(any(grepl("svg", method_distribution(d)$Method)))
})


test_that("empty request windows retain typed country/method table columns", {
  data <- generate_demo_data(5L)[0, ]
  expect_equal(nrow(country_distribution(data)), 0L)
  expect_identical(names(country_distribution(data)), c("Reported country", "Requests"))
  expect_equal(nrow(method_distribution(data)), 0L)
  expect_identical(names(method_distribution(data)), c("Method", "Requests"))
})
