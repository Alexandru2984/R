# app.R
library(shiny)
library(bslib)
library(DT)
library(plotly)
library(dplyr)

# Source modules
source("R/config.R")
source("R/db.R")
source("R/ui_components.R")

# Initialize pool
pool <- NULL

server <- function(input, output, session) {
  
  # Connect to DB
  pool <<- get_db_pool()
  onStop(function() {
    if (!is.null(pool)) poolClose(pool)
  })
  
  # Reactive values
  rv <- reactiveValues(refresh_trigger = 0)
  
  observeEvent(input$refresh, {
    rv$refresh_trigger <- rv$refresh_trigger + 1
  })
  
  # Load basic stats
  observe({
    rv$refresh_trigger
    
    # Very basic queries for value boxes
    res <- tryCatch({
      query_db(pool, "SELECT COUNT(*) as n FROM requests")
    }, error = function(e) data.frame(n=0))
    output$total_req <- renderText({ if(nrow(res)>0) res$n[1] else 0 })
    
    res_ips <- tryCatch({
      query_db(pool, "SELECT COUNT(DISTINCT ip_address) as n FROM requests")
    }, error = function(e) data.frame(n=0))
    output$unique_ips <- renderText({ if(nrow(res_ips)>0) res_ips$n[1] else 0 })
    
    res_bots <- tryCatch({
      query_db(pool, "SELECT COUNT(*) as n FROM requests WHERE classification IN ('known_bot', 'scanner', 'suspicious')")
    }, error = function(e) data.frame(n=0))
    output$sus_bots <- renderText({ if(nrow(res_bots)>0) res_bots$n[1] else 0 })
    
    res_404 <- tryCatch({
      query_db(pool, "SELECT COUNT(*) as n FROM requests WHERE status_code = 404")
    }, error = function(e) data.frame(n=0))
    output$sus_404 <- renderText({ if(nrow(res_404)>0) res_404$n[1] else 0 })
  })
  
  # Handle upload
  observeEvent(input$btn_process, {
    req(input$log_upload)
    output$upload_status <- renderText("Processing...")
    
    file_path <- input$log_upload$datapath
    file_type <- input$log_type
    
    tryCatch({
      source("R/parser_nginx.R")
      source("R/parser_cloudflare.R")
      source("R/scoring.R")
      source("R/summaries.R")
      
      if (file_type == "nginx") {
        parsed <- parse_nginx_log(file_path)
      } else {
        parsed <- parse_cloudflare_csv(file_path)
      }
      
      if (!is.null(parsed$valid) && nrow(parsed$valid) > 0) {
        # Score
        scored_data <- score_requests(parsed$valid)
        
        # Insert file record
        res <- dbSendQuery(pool, "INSERT INTO imported_log_files (filename, file_type) VALUES ($1, $2) RETURNING id")
        dbBind(res, list(input$log_upload$name, file_type))
        file_id <- dbFetch(res)$id[1]
        dbClearResult(res)
        
        # Insert requests
        scored_data$file_id <- file_id
        dbAppendTable(pool, "requests", scored_data)
        
        # Update summaries
        ip_sums <- aggregate_ips(scored_data)
        if (!is.null(ip_sums)) {
          for (i in 1:nrow(ip_sums)) {
            row <- ip_sums[i, ]
            # UPSERT
            q <- "INSERT INTO ip_summary (ip_address, total_requests, unique_paths, error_404_count, risk_score, classification, last_seen) 
                  VALUES ($1, $2, $3, $4, $5, $6, $7)
                  ON CONFLICT (ip_address) DO UPDATE SET 
                  total_requests = ip_summary.total_requests + EXCLUDED.total_requests,
                  unique_paths = EXCLUDED.unique_paths,
                  error_404_count = ip_summary.error_404_count + EXCLUDED.error_404_count,
                  risk_score = GREATEST(ip_summary.risk_score, EXCLUDED.risk_score),
                  classification = EXCLUDED.classification,
                  last_seen = GREATEST(ip_summary.last_seen, EXCLUDED.last_seen)"
            execute_db(pool, q, list(
              row$ip_address, row$total_requests, row$unique_paths, row$error_404_count, 
              row$risk_score, row$classification, row$last_seen
            ))
          }
        }
        
        output$upload_status <- renderText(sprintf("Success! Inserted %d requests.", nrow(scored_data)))
        rv$refresh_trigger <- rv$refresh_trigger + 1
      } else {
        output$upload_status <- renderText("No valid data found in file.")
      }
    }, error = function(e) {
      output$upload_status <- renderText(paste("Error processing file:", e$message))
    })
  })
  
  # Simple DT outputs
  output$table_top_paths <- renderDT({
    rv$refresh_trigger
    res <- tryCatch({
      query_db(pool, "SELECT path, COUNT(*) as count FROM requests GROUP BY path ORDER BY count DESC LIMIT 10")
    }, error = function(e) data.frame(path=character(0), count=integer(0)))
    datatable(res, options = list(pageLength = 5))
  })
  
  output$table_top_ips <- renderDT({
    rv$refresh_trigger
    res <- tryCatch({
      query_db(pool, "SELECT ip_address, total_requests, risk_score, classification FROM ip_summary ORDER BY risk_score DESC LIMIT 10")
    }, error = function(e) data.frame(ip=character(0)))
    datatable(res, options = list(pageLength = 5))
  })
  
  output$table_recent_reqs <- renderDT({
    rv$refresh_trigger
    res <- tryCatch({
      query_db(pool, "SELECT timestamp, ip_address, method, path, status_code, classification FROM requests ORDER BY timestamp DESC LIMIT 50")
    }, error = function(e) data.frame())
    datatable(res, options = list(pageLength = 10))
  })
  
  # Plotly dummy
  output$chart_time <- renderPlotly({
    rv$refresh_trigger
    res <- tryCatch({
      query_db(pool, "SELECT date_trunc('hour', timestamp) as time_bucket, COUNT(*) as count FROM requests GROUP BY time_bucket ORDER BY time_bucket")
    }, error = function(e) data.frame(time_bucket=Sys.time(), count=0))
    
    if (nrow(res) > 0) {
      plot_ly(res, x = ~time_bucket, y = ~count, type = 'scatter', mode = 'lines+markers',
              line = list(color = '#06b6d4', width = 3),
              marker = list(color = '#8b5cf6', size = 8)) %>%
        layout(
          title = "",
          xaxis = list(title = "", gridcolor = 'rgba(255,255,255,0.05)', color = '#94a3b8'), 
          yaxis = list(title = "Requests", gridcolor = 'rgba(255,255,255,0.05)', color = '#94a3b8'),
          plot_bgcolor = 'transparent',
          paper_bgcolor = 'transparent',
          margin = list(l=40, r=20, t=20, b=40)
        )
    } else {
      plot_ly() %>% layout(
        title = list(text = "No data", font = list(color = '#94a3b8')),
        plot_bgcolor = 'transparent',
        paper_bgcolor = 'transparent'
      )
    }
  })
}

shinyApp(ui, server)
