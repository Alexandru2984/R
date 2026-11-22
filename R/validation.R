MAX_IMPORT_BYTES <- 10 * 1024^2
MAX_IMPORT_ROWS <- 50000L
MAX_LINE_BYTES <- 32768L

check_import_file <- function(path, uploaded = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) stop("Select a valid file.", call. = FALSE)
  info <- file.info(path)
  if (isTRUE(info$isdir) || nzchar(Sys.readlink(path))) stop("A regular file is required.", call. = FALSE)
  if (is.na(info$size) || info$size <= 0 || info$size > MAX_IMPORT_BYTES) stop("The file must be between 1 byte and 10 MiB.", call. = FALSE)
  if (uploaded) {
    root <- paste0(normalizePath(tempdir(), winslash = "/", mustWork = TRUE), "/")
    if (!startsWith(normalizePath(path, winslash = "/", mustWork = TRUE), root)) stop("Invalid upload location.", call. = FALSE)
  }
  invisible(path)
}

valid_ip <- function(ip) {
  ipv4 <- function(x) {
    if (!grepl("^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$", x)) return(FALSE)
    parts <- strsplit(x, ".", fixed = TRUE)[[1]]
    all(nchar(parts) <= 3L & suppressWarnings(as.integer(parts)) <= 255L)
  }
  vapply(as.character(ip), function(x) {
    if (is.na(x) || !nzchar(x) || nchar(x, type = "bytes") > 45L) return(FALSE)
    if (!grepl(":", x, fixed = TRUE)) return(ipv4(x))
    if (!grepl("^[0-9a-fA-F:.]+$", x) || grepl(":::", x, fixed = TRUE)) return(FALSE)
    if (grepl(".", x, fixed = TRUE)) {
      tail <- sub("^.*:", "", x)
      if (!ipv4(tail)) return(FALSE)
      x <- paste0(substr(x, 1, nchar(x) - nchar(tail)), "0:0")
    }
    count <- sum(gregexpr("::", x, fixed = TRUE)[[1]] > 0)
    if (count > 1L || (count == 0L && (startsWith(x, ":") || endsWith(x, ":")))) return(FALSE)
    parts <- strsplit(x, ":", fixed = TRUE)[[1]]
    parts <- parts[nzchar(parts)]
    all(nchar(parts) <= 4L) && if (count == 1L) length(parts) < 8L else length(parts) == 8L
  }, logical(1), USE.NAMES = FALSE)
}

validate_requests <- function(df) {
  if (is.null(df) || !nrow(df)) return(logical(0))
  ok <- valid_ip(df$ip_address) & !is.na(df$timestamp) &
    !is.na(df$status_code) & df$status_code >= 100L & df$status_code <= 599L &
    !is.na(df$response_size) & is.finite(df$response_size) & df$response_size >= 0 & df$response_size <= 2^53 &
    !is.na(df$method) & grepl("^[A-Z]{1,10}$", df$method) &
    !is.na(df$path) & nzchar(df$path) & nchar(df$path, type = "bytes") <= 4096L &
    !is.na(df$protocol) & grepl("^HTTP/[0-9.]{1,8}$", df$protocol)
  for (key in intersect(c("path", "user_agent", "referrer", "country"), names(df))) {
    limit <- switch(key, country = 10L, user_agent = 2048L, 4096L)
    value <- df[[key]]
    ok <- ok & (is.na(value) | (nchar(value, type = "bytes") <= limit & !grepl("[[:cntrl:]]", value)))
  }
  ok[is.na(ok)] <- FALSE
  ok
}

read_log_lines <- function(path) {
  check_import_file(path)
  lines <- readLines(path, n = MAX_IMPORT_ROWS + 1L, warn = FALSE, encoding = "UTF-8")
  if (length(lines) > MAX_IMPORT_ROWS) stop("Maximum 50,000 log rows per file.", call. = FALSE)
  if (any(nchar(lines, type = "bytes") > MAX_LINE_BYTES)) stop("A log line exceeds 32 KiB.", call. = FALSE)
  lines
}
