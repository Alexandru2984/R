source("../../R/auth.R")

test_that("credential verification uses the configured password hash", {
  password_hash <- sodium::password_store("correct horse battery staple")

  expect_true(verify_admin_credentials("admin", "correct horse battery staple", "admin", password_hash))
  expect_false(verify_admin_credentials("other", "correct horse battery staple", "admin", password_hash))
  expect_false(verify_admin_credentials("admin", "wrong", "admin", password_hash))
  expect_false(verify_admin_credentials("admin", "correct horse battery staple", "", password_hash))
  expect_false(verify_admin_credentials("admin", "correct horse battery staple", "admin", ""))
})

test_that("failed attempts lock and successful authentication can clear state", {
  limiter <- new_auth_limiter()
  key <- "192.0.2.1"
  now <- as.POSIXct("2026-10-07 12:00:00", tz = "UTC")

  for (attempt in seq_len(AUTH_MAX_FAILURES - 1L)) {
    expect_false(record_auth_failure(limiter, key, now + attempt))
  }

  expect_true(record_auth_failure(limiter, key, now + AUTH_MAX_FAILURES))
  expect_true(auth_locked(limiter, key, now + AUTH_MAX_FAILURES + 1L))

  clear_auth_failures(limiter, key)
  expect_false(auth_locked(limiter, key, now + AUTH_MAX_FAILURES + 1L))
})

test_that("failure windows expire before counting new attempts", {
  limiter <- new_auth_limiter()
  key <- "198.51.100.2"
  now <- as.POSIXct("2026-10-07 12:00:00", tz = "UTC")

  expect_false(record_auth_failure(limiter, key, now))
  expect_false(record_auth_failure(limiter, key, now + AUTH_WINDOW_SECONDS + 1))
  expect_equal(limiter[[key]]$count, 1L)
})
