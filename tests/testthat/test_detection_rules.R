# tests/testthat/test_detection_rules.R
source("../../R/detection_rules.R")

test_that("Bot detection works for known bots", {
  expect_true(is_known_bot("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"))
  expect_true(is_known_bot("curl/7.68.0"))
  expect_false(is_known_bot("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"))
  expect_false(is_known_bot(""))
  expect_false(is_known_bot(NA))
})

test_that("Suspicious path detection works", {
  expect_true(is_suspicious_path("/.env"))
  expect_true(is_suspicious_path("/wp-admin/login.php"))
  expect_true(is_suspicious_path("/static/../../etc/passwd"))
  expect_true(is_suspicious_path("/search?q=<script>alert(1)</script>"))
  expect_true(is_suspicious_path("/login?u=admin' UNION SELECT 1,2--"))
  
  expect_false(is_suspicious_path("/about"))
  expect_false(is_suspicious_path("/"))
  expect_false(is_suspicious_path("/assets/css/style.css"))
})
