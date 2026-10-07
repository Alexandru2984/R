source("../../R/config.R")

test_that("required_env rejects missing and empty values", {
  original <- Sys.getenv("R_TRAFFIC_TEST_REQUIRED", unset = NA_character_)
  on.exit({
    if (is.na(original)) Sys.unsetenv("R_TRAFFIC_TEST_REQUIRED") else Sys.setenv(R_TRAFFIC_TEST_REQUIRED = original)
  })

  Sys.unsetenv("R_TRAFFIC_TEST_REQUIRED")
  expect_error(required_env("R_TRAFFIC_TEST_REQUIRED"), "is missing")

  Sys.setenv(R_TRAFFIC_TEST_REQUIRED = "")
  expect_error(required_env("R_TRAFFIC_TEST_REQUIRED"), "is missing")

  Sys.setenv(R_TRAFFIC_TEST_REQUIRED = "configured")
  expect_identical(required_env("R_TRAFFIC_TEST_REQUIRED"), "configured")
})
