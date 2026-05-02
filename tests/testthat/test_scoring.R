# tests/testthat/test_scoring.R
source("../../R/detection_rules.R")
source("../../R/scoring.R")

test_that("Requests are scored correctly", {
  df <- data.frame(
    user_agent = c("Mozilla/5.0", "curl/7.68.0", "Googlebot/2.1", NA),
    path = c("/", "/about", "/.env", "/wp-admin"),
    stringsAsFactors = FALSE
  )
  
  res <- score_requests(df)
  
  expect_equal(res$classification[1], "likely_human")
  expect_equal(res$classification[2], "known_bot")
  expect_equal(res$classification[3], "scanner") # Googlebot + /.env => scanner (path rule takes precedence in classification logic)
  expect_equal(res$classification[4], "scanner") # NA ua + /wp-admin => scanner
})
