# Typed Cloudflare CSV ingestion. Never infer IP/path types from untrusted CSV.
parse_cloudflare_csv <- function(filepath) {
  lines <- read_log_lines(filepath)
  df <- tryCatch(read.csv(text = paste(lines, collapse = "\n"), stringsAsFactors = FALSE,
                         colClasses = "character", check.names = FALSE, na.strings = "", fill = FALSE),
                 error = function(e) stop("Invalid CSV structure.", call. = FALSE))
  if (nrow(df) > MAX_IMPORT_ROWS) stop("Maximum 50,000 CSV rows per file.", call. = FALSE)
  cols <- gsub("[^a-z0-9]", "", tolower(names(df)))
  get_col <- function(aliases, default = "") {
    idx <- match(aliases, cols, nomatch = 0L)
    idx <- idx[idx > 0L]
    if (length(idx)) df[[idx[1]]] else rep(default, nrow(df))
  }
  raw_time <- get_col(c("edgestarttimestamp", "timestamp", "time", "date"))
  timestamp <- suppressWarnings(as.POSIXct(raw_time, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"))
  missing <- is.na(timestamp)
  timestamp[missing] <- suppressWarnings(as.POSIXct(raw_time[missing], format = "%Y-%m-%d %H:%M:%OS", tz = "UTC"))
  numeric_time <- grepl("^[0-9]{10}([0-9]{3}|[0-9]{9})?$", raw_time)
  numeric_time[is.na(numeric_time)] <- FALSE
  if (any(numeric_time)) {
    values <- as.numeric(raw_time[numeric_time])
    scale <- ifelse(nchar(raw_time[numeric_time]) == 19L, 1e9, ifelse(nchar(raw_time[numeric_time]) == 13L, 1e3, 1))
    timestamp[numeric_time] <- as.POSIXct(values / scale, origin = "1970-01-01", tz = "UTC")
  }
  out <- data.frame(
    ip_address = get_col(c("clientip", "ip")), timestamp = timestamp,
    method = get_col(c("clientrequestmethod", "method", "reqmethod"), "GET"),
    path = get_col(c("clientrequesturi", "uri", "path", "reqpath")),
    protocol = get_col(c("clientrequestprotocol", "protocol", "proto"), "HTTP/1.1"),
    status_code = suppressWarnings(as.integer(get_col(c("edgeresponsestatus", "status", "statuscode")))),
    response_size = suppressWarnings(as.numeric(get_col(c("edgeresponsebytes", "bytes", "size", "length"), "0"))),
    referrer = get_col(c("clientrequestreferer", "referer", "referrer", "httpreferer")),
    user_agent = get_col(c("clientrequestuseragent", "useragent", "ua", "httpuseragent")),
    country = get_col(c("clientcountry", "country", "geocountry")), stringsAsFactors = FALSE)
  accepted <- validate_requests(out)
  list(valid = out[accepted, , drop = FALSE], invalid = rep("Invalid CSV row", sum(!accepted)))
}
