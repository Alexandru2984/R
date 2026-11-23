previous_period_filters <- function(filters) {
  days <- as.integer(filters$end - filters$start) + 1L
  filters$start <- filters$start - days
  filters$end <- filters$end - days
  filters
}

comparison_reference <- function(snapshot) {
  list(metrics = traffic_metrics(snapshot$data), filters = snapshot$filters,
       capped = snapshot$capped, updated = snapshot$updated)
}

load_traffic_snapshot <- function(db_pool, filters, compare = FALSE) {
  con <- pool::poolCheckout(db_pool)
  on.exit(pool::poolReturn(con), add = TRUE)
  DBI::dbWithTransaction(con, {
    execute_connection(con, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
    query <- request_query(filters)
    current <- finish_snapshot(query_connection(con, query$sql, query$params), filters, "Live production")
    if (compare) {
      previous <- previous_period_filters(filters)
      query <- request_query(previous)
      reference <- finish_snapshot(query_connection(con, query$sql, query$params), previous, "Live production")
      current$comparison <- comparison_reference(reference)
    }
    current
  })
}

relative_change <- function(current, previous) {
  if (!is.finite(current) || !is.finite(previous)) return("Unavailable")
  if (previous == 0) return(if (current == 0) "No change" else "New activity; no baseline")
  sprintf("%+.1f%%", 100 * (current - previous) / previous)
}

comparison_rows <- function(current, previous) {
  display_count <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
  rate_change <- if (current$total > 0 && previous$total > 0) sprintf("%+.1f pp", current$error_rate - previous$error_rate) else "Insufficient requests"
  data.frame(Metric = c("Requests", "Unique IPs", "Flagged requests", "HTTP error rate", "Response volume"),
    Current = c(display_count(current$total), display_count(current$ips), display_count(current$flagged),
      if (current$total) sprintf("%.1f%%", current$error_rate) else "No requests", sprintf("%.1f MiB", current$bandwidth)),
    Previous = c(display_count(previous$total), display_count(previous$ips), display_count(previous$flagged),
      if (previous$total) sprintf("%.1f%%", previous$error_rate) else "No requests", sprintf("%.1f MiB", previous$bandwidth)),
    Change = c(relative_change(current$total, previous$total), relative_change(current$ips, previous$ips),
      relative_change(current$flagged, previous$flagged), rate_change, relative_change(current$bandwidth, previous$bandwidth)), stringsAsFactors = FALSE)
}

traffic_heatmap <- function(data) {
  days <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
  weekdays <- as.integer(format(data$timestamp, "%u", tz = "UTC"))
  hours <- as.integer(format(data$timestamp, "%H", tz = "UTC"))
  counts <- table(factor(weekdays, levels = 1:7), factor(hours, levels = 0:23))
  matrix(as.numeric(counts), nrow = 7, dimnames = list(days, sprintf("%02d:00", 0:23)))
}

country_distribution <- function(data) {
  country <- data$country
  known <- !is.na(country) & grepl("^[A-Za-z]{2}$", country)
  labels <- rep("Unknown", nrow(data))
  labels[known] <- toupper(country[known])
  result <- as.data.frame(table(labels), stringsAsFactors = FALSE)
  names(result) <- c("Reported country", "Requests")
  result[order(-result$Requests, result[[1]]), , drop = FALSE]
}

method_distribution <- function(data) {
  method <- data$method
  known <- !is.na(method) & method %in% c("GET", "POST", "HEAD", "PUT", "PATCH", "DELETE", "OPTIONS", "CONNECT", "TRACE")
  method[!known] <- "Other"
  result <- as.data.frame(table(method), stringsAsFactors = FALSE)
  names(result) <- c("Method", "Requests")
  result[order(-result$Requests, result$Method), , drop = FALSE]
}
