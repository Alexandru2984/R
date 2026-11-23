MAX_SAVED_VIEWS <- 10L

make_saved_view <- function(name, filters, source, compare = FALSE, time_bucket = "hour") {
  if (!scalar_text(name, 160L)) stop("Use a view name of 1–40 characters.", call. = FALSE)
  name <- trimws(name)
  if (!nzchar(name) || nchar(name) > 40L || grepl("[[:cntrl:]]", name)) stop("Use a view name of 1–40 characters without control characters.", call. = FALSE)
  if (!scalar_text(source, 30L) || !source %in% c("Synthetic demo", "Live production")) stop("Invalid view source.", call. = FALSE)
  filters <- normalize_filters(c(filters$start, filters$end), filters$classification, filters$status, filters$ip, filters$path, filters$method)
  if (!scalar_text(time_bucket, 10L) || !time_bucket %in% c("hour", "day")) stop("Invalid time grouping.", call. = FALSE)
  list(name = name, filters = filters, source = source, compare = isTRUE(compare), time_bucket = time_bucket)
}

store_saved_view <- function(views, view, key) {
  existing <- which(vapply(views, function(x) identical(x$name, view$name), logical(1)))
  if (length(existing)) key <- names(views)[existing[1]]
  else if (length(views) >= MAX_SAVED_VIEWS) stop("The session can hold up to 10 saved views. Delete one first.", call. = FALSE)
  views[[key]] <- view
  list(views = views, selected = key)
}

evaluate_rule_sample <- function(path, user_agent) {
  if (!scalar_text(path, 4096L) || !nzchar(path) || !scalar_text(user_agent, 2048L) ||
      grepl("[[:cntrl:]]", path) || grepl("[[:cntrl:]]", user_agent)) stop("Use a path up to 4 KiB and a user agent up to 2 KiB, without control characters.", call. = FALSE)
  missing_ua <- !nzchar(trimws(user_agent)) || user_agent == "-"
  matched <- c(is_suspicious_path(path), is_known_bot(user_agent), missing_ua)
  points <- c(8, 5, 2) * matched
  scored <- score_requests(data.frame(path = path, user_agent = user_agent, stringsAsFactors = FALSE))
  list(classification = scored$classification[1], score = scored$bot_score[1], reason = request_reason(path, user_agent),
    signals = data.frame(Signal = c("Sensitive endpoint / traversal / injection", "Bot or tool user-agent claim", "Missing user agent"),
      Matched = ifelse(matched, "Yes", "No"), Points = points, stringsAsFactors = FALSE))
}

LAB_EXAMPLES <- list(
  sensitive = list(path = "/.env", ua = "curl/8.0"),
  login = list(path = "/login", ua = "Mozilla/5.0"),
  traversal = list(path = "/static/%252e%252e/etc/passwd", ua = "Mozilla/5.0"),
  bot = list(path = "/", ua = "python-requests/2.32"),
  empty = list(path = "/", ua = "")
)
