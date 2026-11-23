# All writes for an import share a checked-out connection and one transaction.
prepare_import <- function(path, type, uploaded = FALSE) {
  check_import_file(path, uploaded)
  if (!is.character(type) || length(type) != 1L || is.na(type) || !type %in% c("nginx", "cloudflare")) stop("Choose Nginx or Cloudflare.", call. = FALSE)
  parsed <- if (type == "nginx") parse_nginx_log(path) else parse_cloudflare_csv(path)
  if (is.null(parsed$valid) || !nrow(parsed$valid)) stop("No valid requests found.", call. = FALSE)
  list(data = score_requests(parsed$valid), rejected = length(parsed$invalid),
       hash = digest::digest(file = path, algo = "sha256"), type = type)
}

import_requests <- function(con, prepared, filename, actor = "admin") {
  stopifnot(is.character(filename), length(filename) == 1L, !is.na(filename))
  filename <- substr(basename(gsub("\\\\", "/", filename)), 1, 200)
  DBI::dbWithTransaction(con, {
    # Serializes imports, so affected-IP summaries remain correct across sessions.
    query_connection(con, "SELECT pg_advisory_xact_lock(72319381)")
    duplicate <- query_connection(con, "SELECT file_id FROM import_registry WHERE content_hash = $1", params = list(prepared$hash))
    if (nrow(duplicate)) stop("This exact file has already been imported.", call. = FALSE)
    meta <- query_connection(con, "INSERT INTO imported_log_files (filename, file_type) VALUES ($1, $2) RETURNING id", params = list(filename, prepared$type))
    data <- prepared$data
    # Reasons are computed for the explorer, not stored in the legacy schema.
    data <- data[, setdiff(names(data), "reason"), drop = FALSE]
    data$file_id <- meta$id[1]
    DBI::dbAppendTable(con, "requests", data)
    execute_connection(con, "INSERT INTO import_registry (content_hash, file_id, accepted_rows, rejected_rows) VALUES ($1,$2,$3,$4)",
                   params = list(prepared$hash, meta$id[1], nrow(data), prepared$rejected))
    # Recompute from all requests for affected IPs; never add incompatible per-file counts.
    execute_connection(con, "INSERT INTO ip_summary
      (ip_address,total_requests,unique_paths,error_404_count,risk_score,classification,last_seen)
      SELECT r.ip_address,COUNT(*),COUNT(DISTINCT r.path),COUNT(*) FILTER (WHERE r.status_code=404),
        LEAST(999.99,MAX(r.bot_score)),
        CASE WHEN bool_or(r.classification='scanner') THEN 'scanner'
             WHEN bool_or(r.classification='suspicious') THEN 'suspicious'
             WHEN bool_or(r.classification='known_bot') THEN 'known_bot' ELSE 'likely_human' END, MAX(r.timestamp)
      FROM requests r WHERE r.ip_address IN (SELECT ip_address FROM requests WHERE file_id=$1)
      GROUP BY r.ip_address ON CONFLICT (ip_address) DO UPDATE SET
        total_requests=EXCLUDED.total_requests,unique_paths=EXCLUDED.unique_paths,
        error_404_count=EXCLUDED.error_404_count,risk_score=EXCLUDED.risk_score,
        classification=EXCLUDED.classification,last_seen=EXCLUDED.last_seen", params = list(meta$id[1]))
    record_admin_event(con, "import_completed", actor, meta$id[1], nrow(data), prepared$rejected)
    list(file_id = meta$id[1], accepted = nrow(data), rejected = prepared$rejected)
  })
}
