# R/parser_nginx.R
library(stringr)

parse_nginx_log <- function(filepath) {
  lines <- readLines(filepath, warn = FALSE)

  # Nginx combined log format regex
  # Example: 127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 "http://www.example.com/start.html" "Mozilla/4.0 (compatible; MSIE 5.5; Windows NT 5.0)"
  pattern <- "^(\\S+) \\S+ \\S+ \\[([^]]+)\\] \"([^\"]+)\" (\\d{3}) (\\d+|-) \"([^\"]*)\" \"([^\"]*)\""

  matches <- str_match(lines, pattern)

  valid_idx <- !is.na(matches[, 1])

  valid_data <- NULL
  if (any(valid_idx)) {
    req_parts <- str_split_fixed(matches[valid_idx, 4], " ", 3)
    method <- req_parts[, 1]
    path <- req_parts[, 2]
    protocol <- req_parts[, 3]

    timestamp_str <- matches[valid_idx, 3]
    # Nginx timestamps look like: 10/Oct/2000:13:55:36 -0700
    # Parse to POSIXct
    Sys.setlocale("LC_TIME", "C")
    parsed_time <- as.POSIXct(timestamp_str, format="%d/%b/%Y:%H:%M:%S %z")

    resp_size <- matches[valid_idx, 6]
    resp_size[resp_size == "-"] <- "0"

    valid_data <- data.frame(
      ip_address = matches[valid_idx, 2],
      timestamp = parsed_time,
      method = method,
      path = path,
      protocol = protocol,
      status_code = as.integer(matches[valid_idx, 5]),
      response_size = as.numeric(resp_size),
      referrer = matches[valid_idx, 7],
      user_agent = matches[valid_idx, 8],
      stringsAsFactors = FALSE
    )
  }

  invalid_lines <- lines[!valid_idx]

  list(
    valid = valid_data,
    invalid = invalid_lines
  )
}
