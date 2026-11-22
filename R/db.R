# R/db.R
library(DBI)
library(RPostgres)
library(pool)

# Create a connection pool to PostgreSQL
get_db_pool <- function() {
  cfg <- get_config()
  pool::dbPool(
    drv = RPostgres::Postgres(),
    dbname = cfg$db_name,
    host = cfg$db_host,
    port = cfg$db_port,
    user = cfg$db_user,
    password = cfg$db_password,
    minSize = 0, maxSize = 5, idleTimeout = 60,
    options = "-c statement_timeout=10000 -c lock_timeout=5000 -c timezone=UTC",
    bigint = "numeric"
  )
}

# Query wrapper to return data.table or data.frame
query_db <- function(pool, query, params = list()) {
  con <- poolCheckout(pool)
  on.exit(poolReturn(con), add = TRUE)
  query_connection(con, query, params)
}

execute_db <- function(pool, query, params = list()) {
  con <- poolCheckout(pool)
  on.exit(poolReturn(con), add = TRUE)
  execute_connection(con, query, params)
}

# Always clear a prepared result, including when dbBind rejects a value.
query_connection <- function(con, query, params = list()) {
  result <- DBI::dbSendQuery(con, query)
  on.exit(DBI::dbClearResult(result), add = TRUE)
  if (length(params)) DBI::dbBind(result, params)
  DBI::dbFetch(result)
}

execute_connection <- function(con, query, params = list()) {
  result <- DBI::dbSendStatement(con, query)
  on.exit(DBI::dbClearResult(result), add = TRUE)
  if (length(params)) DBI::dbBind(result, params)
  DBI::dbGetRowsAffected(result)
}
