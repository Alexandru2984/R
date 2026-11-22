# Explicit, bounded imports. Intentionally no default scan of unrelated VPS logs.
source("R/config.R")
source("R/db.R")
for (module in c("validation", "parser_nginx", "parser_cloudflare", "detection_rules", "scoring", "import")) source(paste0("R/", module, ".R"))
run_import <- function() {
  paths <- commandArgs(trailingOnly = TRUE)
  if (!length(paths)) stop("Usage: Rscript scripts/import_local_nginx.R /path/to/access.log", call. = FALSE)
  db_pool <- get_db_pool()
  on.exit(pool::poolClose(db_pool), add = TRUE)
  con <- pool::poolCheckout(db_pool)
  on.exit(pool::poolReturn(con), add = TRUE, after = FALSE)
  for (path in paths) {
    result <- import_requests(con, prepare_import(path, "nginx"), basename(path))
    cat(sprintf("Imported %d rows; rejected %d.\n", result$accepted, result$rejected))
  }
}
run_import()
