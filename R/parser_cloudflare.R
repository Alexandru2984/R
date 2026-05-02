# R/parser_cloudflare.R
# Cloudflare style parser

parse_cloudflare_csv <- function(filepath) {
  if (!file.exists(filepath)) return(list(valid = NULL, invalid = c()))

  df <- tryCatch({
    read.csv(filepath, stringsAsFactors = FALSE)
  }, error = function(e) NULL)

  if (is.null(df)) return(list(valid = NULL, invalid = c("Failed to read CSV")))

  # Try to map columns
  cols <- colnames(df)
  col_lower <- tolower(cols)

  get_col <- function(possible_names, default_val = NA) {
    idx <- which(col_lower %in% possible_names)
    if (length(idx) > 0) df[[cols[idx[1]]]] else rep(default_val, nrow(df))
  }

  ip_address <- get_col(c("clientip", "client_ip", "ip", "client.ip"))
  if (all(is.na(ip_address))) {
    return(list(valid = NULL, invalid = c("Could not find IP address column")))
  }

  ts_raw <- get_col(c("timestamp", "time", "date"))
  timestamp <- as.POSIXct(ts_raw, format="%Y-%m-%dT%H:%M:%SZ", tz="UTC")
  if (all(is.na(timestamp))) {
    timestamp <- as.POSIXct(ts_raw) # try auto parsing
  }

  method <- get_col(c("clientrequestmethod", "method", "req_method"))
  path <- get_col(c("clientrequesturi", "uri", "path", "req_path"))
  protocol <- get_col(c("clientrequestprotocol", "protocol", "proto"))
  status_code <- as.integer(get_col(c("edge responsestatus", "status", "status_code")))
  response_size <- as.numeric(get_col(c("edgeresponsebytes", "bytes", "size", "length"), 0))
  referrer <- get_col(c("clientrequestreferer", "referer", "referrer", "http_referer"), "")
  user_agent <- get_col(c("clientrequestuseragent", "user_agent", "ua", "http_user_agent"), "")
  country <- get_col(c("clientcountry", "country", "geo_country"), "")

  valid_data <- data.frame(
    ip_address = ip_address,
    timestamp = timestamp,
    method = method,
    path = path,
    protocol = protocol,
    status_code = status_code,
    response_size = response_size,
    referrer = referrer,
    user_agent = user_agent,
    country = country,
    stringsAsFactors = FALSE
  )

  # Filter completely bad rows
  valid_idx <- !is.na(valid_data$ip_address) & !is.na(valid_data$timestamp)
  invalid_lines <- df[!valid_idx, ]

  list(
    valid = valid_data[valid_idx, ],
    invalid = if(nrow(invalid_lines) > 0) apply(invalid_lines, 1, paste, collapse=",") else c()
  )
}
