TRAFFIC_CLASSES <- c("likely_human", "known_bot", "scanner", "suspicious", "unknown")
CLASS_LABELS <- c(likely_human = "Likely human", known_bot = "Bot / tool claim", scanner = "Scanner signals", suspicious = "Suspicious", unknown = "Unknown")
CLASS_COLORS <- c(likely_human = "#4dd5ac", known_bot = "#67a9ff", scanner = "#ff7186", suspicious = "#f2c66d", unknown = "#a6b4cb")
SNAPSHOT_LIMIT <- 20000L
utc_today <- function() as.Date(Sys.time(), tz = "UTC")

normalize_filters <- function(dates = NULL, classification = "All", status = "All", ip = "", path = "", method = "All", today = utc_today()) {
  if (is.null(dates)) dates <- c(today - 6, today)
  parsed <- tryCatch(as.Date(as.character(dates), format = "%Y-%m-%d"), error = function(e) as.Date(NA))
  if (length(parsed) != 2L || anyNA(parsed) || parsed[1] > parsed[2] || parsed[2] > today || as.numeric(parsed[2] - parsed[1]) > 30) {
    stop("Choose a date range of up to 31 days, ending today or earlier.", call. = FALSE)
  }
  choice <- function(value, choices) {
    if (!scalar_text(value, 30L) || !value %in% choices) stop("Invalid filter selection.", call. = FALSE)
    value
  }
  search <- function(value, limit) {
    if (is.null(value)) return("")
    if (!scalar_text(value, limit) || grepl("[[:cntrl:]]", value)) stop("Search text is too long or contains control characters.", call. = FALSE)
    trimws(value)
  }
  ip <- search(ip, 45L)
  if (nzchar(ip) && !valid_ip(ip)) stop("Enter one valid IPv4 or IPv6 address.", call. = FALSE)
  list(start = parsed[1], end = parsed[2],
       classification = choice(classification, c("All", TRAFFIC_CLASSES)),
       status = choice(status, c("All", "2xx", "3xx", "4xx", "5xx", "404")),
       ip = ip, path = search(path, 160L),
       method = choice(method, c("All", "GET", "POST", "HEAD", "PUT", "PATCH", "DELETE", "OPTIONS")))
}

request_query <- function(filters) {
  clauses <- c("timestamp >= $1::date", "timestamp < ($2::date + INTERVAL '1 day')")
  params <- list(as.character(filters$start), as.character(filters$end))
  add <- function(sql, value) {
    params[[length(params) + 1L]] <<- value
    clauses <<- c(clauses, sprintf(sql, length(params)))
  }
  if (nzchar(filters$ip)) add("ip_address = $%d", filters$ip)
  if (nzchar(filters$path)) add("strpos(lower(path), lower($%d)) > 0", filters$path)
  if (filters$method != "All") add("method = $%d", filters$method)
  if (filters$status == "404") add("status_code = $%d::integer", 404L)
  else if (filters$status != "All") add("status_code / 100 = $%d::integer", as.integer(substr(filters$status, 1, 1)))
  list(sql = paste("SELECT timestamp,ip_address,method,path,protocol,status_code,response_size,referrer,user_agent,country FROM requests WHERE",
                   paste(clauses, collapse = " AND "), "ORDER BY timestamp DESC, id DESC LIMIT 20001"), params = params)
}

filter_demo <- function(data, filters) {
  keep <- data$timestamp >= as.POSIXct(filters$start, tz = "UTC") & data$timestamp < as.POSIXct(filters$end + 1, tz = "UTC")
  if (nzchar(filters$ip)) keep <- keep & data$ip_address == filters$ip
  if (nzchar(filters$path)) keep <- keep & grepl(tolower(filters$path), tolower(data$path), fixed = TRUE)
  if (filters$method != "All") keep <- keep & data$method == filters$method
  if (filters$status == "404") keep <- keep & data$status_code == 404L
  else if (filters$status != "All") keep <- keep & data$status_code %/% 100L == as.integer(substr(filters$status, 1, 1))
  data[keep, , drop = FALSE]
}

finish_snapshot <- function(data, filters, source) {
  capped <- nrow(data) > SNAPSHOT_LIMIT
  data <- head(data, SNAPSHOT_LIMIT)
  data <- score_requests(data)
  if (filters$classification != "All") data <- data[data$classification == filters$classification, , drop = FALSE]
  pairs <- unique(data[, c("path", "user_agent"), drop = FALSE])
  reasons <- vapply(seq_len(nrow(pairs)), function(i) request_reason(pairs$path[i], pairs$user_agent[i]), character(1))
  keys <- paste(pairs$path, pairs$user_agent, sep = "\r")
  data$reason <- reasons[match(paste(data$path, data$user_agent, sep = "\r"), keys)]
  list(data = data, capped = capped, source = source, filters = filters, updated = Sys.time(), error = NULL)
}

traffic_metrics <- function(data) {
  n <- nrow(data)
  list(total = n, ips = length(unique(data$ip_address)),
       flagged = sum(data$classification %in% c("scanner", "suspicious")),
       bots = sum(data$classification == "known_bot"),
       errors = sum(data$status_code >= 400, na.rm = TRUE),
       error_rate = if (n) 100 * mean(data$status_code >= 400, na.rm = TRUE) else 0,
       bandwidth = sum(data$response_size, na.rm = TRUE) / 1024^2)
}

ip_investigation <- function(data) {
  if (!nrow(data)) return(data.frame(IP = character(), Requests = integer(), Paths = integer(), Errors = integer(), Risk = numeric(), Signals = character()))
  data |>
    dplyr::group_by(ip_address) |>
    dplyr::summarise(Requests = dplyr::n(), Paths = dplyr::n_distinct(path), Errors = sum(status_code >= 400),
      Risk = max(bot_score), Signals = CLASS_LABELS[[classification[which.max(bot_score)]]], .groups = "drop") |>
    dplyr::arrange(dplyr::desc(Risk), dplyr::desc(Requests)) |>
    dplyr::rename(IP = ip_address) |>
    as.data.frame()
}

spreadsheet_safe <- function(data) {
  for (key in names(data)) {
    if (is.character(data[[key]])) {
      risky <- grepl("^[[:space:]]*[=+@-]", data[[key]]) | grepl("^[\t\r\n]", data[[key]])
      risky[is.na(risky)] <- FALSE
      data[[key]][risky] <- paste0("'", data[[key]][risky])
    }
  }
  data
}

traffic_report <- function(snapshot) {
  m <- traffic_metrics(snapshot$data)
  f <- snapshot$filters
  report <- c("TRAFFIC INTELLIGENCE REPORT", paste("Source:", snapshot$source),
    paste("Generated UTC:", format(snapshot$updated, tz = "UTC", usetz = TRUE)),
    paste("Window UTC:", f$start, "through", f$end),
    paste("Filters:", paste(names(f), vapply(f, as.character, character(1)), sep = "=", collapse = "; ")),
    paste("Requests:", m$total), paste("Unique IPs:", m$ips), paste("Flagged requests:", m$flagged),
    paste("Bot/tool claims:", m$bots), sprintf("HTTP error rate: %.1f%%", m$error_rate),
    sprintf("Response body volume: %.2f MiB", m$bandwidth),
    paste("Coverage:", if (snapshot$capped) "latest 20,000 matching requests before classification filter" else "all requests matching source/date/search filters"),
    "Classifications are heuristic signals. User agents and source IPs do not verify identity.",
    "Live exports contain potentially sensitive log data. Store and share with care.")
  if (!is.null(snapshot$comparison)) {
    ref <- snapshot$comparison
    rows <- comparison_rows(m, ref$metrics)
    report <- c(report, "", sprintf("PREVIOUS PERIOD: %s through %s UTC", ref$filters$start, ref$filters$end),
      paste("Previous coverage:", if (ref$capped) "Latest 20,000 before classification filter" else "Complete matching window"),
      apply(rows, 1, function(row) paste(row, collapse = " | ")))
  }
  report
}
