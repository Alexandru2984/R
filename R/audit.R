# The audit trail deliberately excludes passwords, client IPs, raw logs and session tokens.
ADMIN_AUDIT_ACTIONS <- c("login_success", "logout", "session_expired", "import_completed")

record_admin_event <- function(con, action, actor = "admin", file_id = NULL, accepted = NULL, rejected = NULL) {
  if (!scalar_text(action, 40L) || !action %in% ADMIN_AUDIT_ACTIONS) stop("Invalid audit action.", call. = FALSE)
  if (!scalar_text(actor, 128L) || !nzchar(actor) || grepl("[[:cntrl:]]", actor)) stop("Invalid audit actor.", call. = FALSE)
  count <- function(value) {
    if (is.null(value)) return(NA_integer_)
    if (!is.numeric(value) || length(value) != 1L || is.na(value) || !is.finite(value) ||
        value < 0 || value > .Machine$integer.max || value != floor(value)) stop("Invalid audit count.", call. = FALSE)
    as.integer(value)
  }
  execute_connection(con, "INSERT INTO admin_audit_events (action,actor,file_id,accepted_rows,rejected_rows) VALUES ($1,$2,$3,$4,$5)",
    list(action, actor, count(file_id), count(accepted), count(rejected)))
}

read_admin_events <- function(db_pool) {
  query_db(db_pool, "SELECT occurred_at AS time_utc,action,actor,file_id,accepted_rows,rejected_rows FROM admin_audit_events ORDER BY occurred_at DESC,id DESC LIMIT 200")
}
