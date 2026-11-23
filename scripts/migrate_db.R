source("R/config.R")
source("R/db.R")
run_migrations <- function() {
  db_pool <- get_db_pool()
  on.exit(pool::poolClose(db_pool), add = TRUE)
  con <- pool::poolCheckout(db_pool)
  on.exit(pool::poolReturn(con), add = TRUE, after = FALSE)
  files <- sort(list.files("scripts/migrations", pattern = "[.]sql$", full.names = TRUE))
  DBI::dbWithTransaction(con, {
    DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP)")
    DBI::dbGetQuery(con, "SELECT pg_advisory_xact_lock(72319381)")
    applied <- DBI::dbGetQuery(con, "SELECT name FROM schema_migrations")$name
    for (file in files) {
      if (basename(file) %in% applied) next
      DBI::dbExecute(con, paste(readLines(file, warn = FALSE), collapse = "\n"), immediate = TRUE)
      DBI::dbExecute(con, "INSERT INTO schema_migrations(name) VALUES ($1)", params = list(basename(file)))
      cat("Applied", basename(file), "\n")
    }
    runtime_role <- Sys.getenv("DB_RUNTIME_ROLE", "")
    if (nzchar(runtime_role)) {
      role <- DBI::dbQuoteIdentifier(con, runtime_role)
      DBI::dbExecute(con, paste("GRANT SELECT,INSERT ON TABLE import_registry TO", role))
    }
  })
}
run_migrations()
