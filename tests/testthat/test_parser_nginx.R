# tests/testthat/test_parser_nginx.R
source("../../R/parser_nginx.R")

test_that("Nginx parser handles valid lines", {
  # Create a temp file
  tmp <- tempfile()
  writeLines(c(
    '127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 "http://www.example.com/start.html" "Mozilla/4.0 (compatible; MSIE 5.5; Windows NT 5.0)"'
  ), tmp)
  
  res <- parse_nginx_log(tmp)
  
  expect_equal(nrow(res$valid), 1)
  expect_equal(res$valid$ip_address[1], "127.0.0.1")
  expect_equal(res$valid$method[1], "GET")
  expect_equal(res$valid$path[1], "/apache_pb.gif")
  expect_equal(res$valid$status_code[1], 200)
  expect_equal(res$valid$response_size[1], 2326)
  expect_equal(res$valid$user_agent[1], "Mozilla/4.0 (compatible; MSIE 5.5; Windows NT 5.0)")
  
  unlink(tmp)
})

test_that("Nginx parser identifies invalid lines", {
  tmp <- tempfile()
  writeLines(c(
    '127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET / HTTP/1.0" 200 2326 "-" "-"',
    'this is a completely malformed line'
  ), tmp)
  
  res <- parse_nginx_log(tmp)
  
  expect_equal(nrow(res$valid), 1)
  expect_equal(length(res$invalid), 1)
  expect_equal(res$invalid[1], 'this is a completely malformed line')
  
  unlink(tmp)
})
