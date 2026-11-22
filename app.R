# app.R
library(shiny)
library(bslib)
library(DT)
library(plotly)
library(dplyr)

# Source modules
source("R/config.R")
source("R/db.R")
source("R/auth.R")
source("R/ui_components.R")
for (module in c("validation", "parser_nginx", "parser_cloudflare", "detection_rules", "scoring", "summaries", "import")) source(paste0("R/", module, ".R"))
options(shiny.sanitize.errors = TRUE, shiny.maxRequestSize = MAX_IMPORT_BYTES)

# Initialize pool
pool <- NULL
auth_limiter <- new_auth_limiter()
process_pool <- function() {
  if (is.null(pool)) pool <<- get_db_pool()
  pool
}
onStop(function() { if (!is.null(pool)) pool::poolClose(pool) })

server <- function(input, output, session) {
  
  # Reactive values
  rv <- reactiveValues(refresh_trigger = 0)
  is_logged_in <- reactiveVal(FALSE)
  auth_key <- auth_client_key(session$request)
  auth_started <- NULL
  auth_active <- NULL
  observe({
    invalidateLater(30000, session)
    if (is_logged_in() && !admin_session_valid(auth_started, auth_active)) is_logged_in(FALSE)
  })
  observeEvent(input$refresh, { if (is_logged_in()) auth_active <<- Sys.time() })
  
  observeEvent(input$refresh, {
    rv$refresh_trigger <- rv$refresh_trigger + 1
  })
  
  # Hide import tab by default if not logged in
  observe({
    if (!is_logged_in()) {
      nav_hide("main_nav", "Logs & Import")
    } else {
      nav_show("main_nav", "Logs & Import")
    }
  })
  
  # Auth UI - Login / Logout button
  output$auth_button_ui <- renderUI({
    if (is_logged_in()) {
      actionButton("btn_logout", "Logout", class = "btn-outline-danger btn-sm mt-2", icon = icon("sign-out-alt"))
    } else {
      actionButton("btn_login_modal", "Admin Login", class = "btn-outline-info btn-sm mt-2", icon = icon("lock"))
    }
  })
  
  # Demo Banner
  output$demo_banner <- renderUI({
    if (!is_logged_in()) {
      tags$div(class = "alert alert-warning text-center mx-3 mt-3 mb-0", 
               style="border-radius:10px; font-weight:bold; background-color: rgba(239, 68, 68, 0.15); border-color: rgba(239, 68, 68, 0.3); color: #f8fafc;",
               icon("eye-slash"), " PUBLIC DEMO MODE - Showing randomized mock data. Please login to view live production logs."
      )
    }
  })
  
  # Login Modal
  observeEvent(input$btn_login_modal, {
    showModal(modalDialog(
      title = "Admin Authentication",
      textInput("auth_user", "Username"),
      passwordInput("auth_pass", "Password"),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("btn_login_submit", "Login", class = "btn-primary")
      )
    ))
  })
  
  # Login submit
  observeEvent(input$btn_login_submit, {
    if (auth_locked(auth_limiter, auth_key)) {
      updateTextInput(session, "auth_pass", value = "")
      showNotification("Too many attempts. Try again later.", type = "error")
      return()
    }

    valid_user <- Sys.getenv("APP_USERNAME", "")
    valid_hash <- Sys.getenv("APP_PASSWORD_HASH", "")

    if (verify_admin_credentials(input$auth_user, input$auth_pass, valid_user, valid_hash)) {
      clear_auth_failures(auth_limiter, auth_key)
      auth_started <<- Sys.time()
      auth_active <<- Sys.time()
      is_logged_in(TRUE)
      updateTextInput(session, "auth_pass", value = "")
      removeModal()
      showNotification("Logged in successfully. Live production data loaded.", type = "message")
      rv$refresh_trigger <- rv$refresh_trigger + 1
    } else {
      locked <- record_auth_failure(auth_limiter, auth_key)
      updateTextInput(session, "auth_pass", value = "")
      message <- if (locked) "Too many attempts. Try again later." else "Invalid credentials"
      showNotification(message, type = "error")
    }
  })
  
  # Logout
  observeEvent(input$btn_logout, {
    is_logged_in(FALSE)
    showNotification("Logged out. Mock data loaded.", type = "warning")
    rv$refresh_trigger <- rv$refresh_trigger + 1
  })
  
  # Reactive tables depending on auth state
  tbl_req <- reactive({ if(is_logged_in()) "requests" else "mock_requests" })
  tbl_ip <- reactive({ if(is_logged_in()) "ip_summary" else "mock_ip_summary" })
  
  # Helper for dynamic where clauses
  where_data <- reactive({
    rv$refresh_trigger # Depend on refresh button
    
    date_f <- input$date_filter
    class_f <- input$class_filter
    
    build_w <- function(prefix = "", is_ip_table = FALSE) {
      where_parts <- c()
      params <- list()
      time_col <- if (is_ip_table) "last_seen" else "timestamp"
      
      if (isTruthy(date_f[1])) {
        param_idx <- length(params) + 1
        where_parts <- c(where_parts, sprintf("%s%s >= $%d", prefix, time_col, param_idx))
        params <- c(params, as.character(date_f[1]))
      }
      if (isTruthy(date_f[2])) {
        param_idx <- length(params) + 1
        where_parts <- c(where_parts, sprintf("%s%s < $%d", prefix, time_col, param_idx))
        params <- c(params, as.character(date_f[2] + 1))
      }
      if (isTruthy(class_f) && class_f != "All") {
        param_idx <- length(params) + 1
        where_parts <- c(where_parts, sprintf("%sclassification = $%d", prefix, param_idx))
        params <- c(params, class_f)
      }
      
      clause <- if (length(where_parts) > 0) paste("WHERE", paste(where_parts, collapse = " AND ")) else ""
      list(clause = clause, params = params)
    }
    
    list(
      req = build_w(is_ip_table = FALSE),
      ip = build_w(is_ip_table = TRUE)
    )
  })
  
  # Value Boxes
  output$total_req <- renderText({
    w <- where_data()$req
    res <- tryCatch({
      query_db(process_pool(), paste("SELECT COUNT(*) as n FROM", tbl_req(), w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  output$unique_ips <- renderText({
    w <- where_data()$req
    res <- tryCatch({
      query_db(process_pool(), paste("SELECT COUNT(DISTINCT ip_address) as n FROM", tbl_req(), w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  output$sus_bots <- renderText({
    w <- where_data()$req
    bot_cond <- "classification IN ('known_bot', 'scanner', 'suspicious')"
    w$clause <- if (w$clause == "") paste("WHERE", bot_cond) else paste(w$clause, "AND", bot_cond)
    res <- tryCatch({
      query_db(process_pool(), paste("SELECT COUNT(*) as n FROM", tbl_req(), w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  output$sus_404 <- renderText({
    w <- where_data()$req
    cond_404 <- "status_code = 404"
    w$clause <- if (w$clause == "") paste("WHERE", cond_404) else paste(w$clause, "AND", cond_404)
    res <- tryCatch({
      query_db(process_pool(), paste("SELECT COUNT(*) as n FROM", tbl_req(), w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  # Handle upload
  observeEvent(input$btn_process, {
    req(is_logged_in())
    req(input$log_upload)
    output$upload_status <- renderText("Processing...")
    
    req(admin_session_valid(auth_started, auth_active))
    auth_active <<- Sys.time()
    tryCatch({
      prepared <- prepare_import(input$log_upload$datapath, input$log_type, uploaded = TRUE)
      con <- pool::poolCheckout(process_pool())
      result <- tryCatch(import_requests(con, prepared, input$log_upload$name),
                         finally = pool::poolReturn(con))
      status <- sprintf("Imported %d requests; rejected %d rows.", result$accepted, result$rejected)
      output$upload_status <- renderText(status)
      rv$refresh_trigger <- rv$refresh_trigger + 1
    }, error = function(e) {
      message("Import failed: ", conditionMessage(e))
      output$upload_status <- renderText("Import failed. Check file format, size and whether it was already imported.")
    })
  })

  # DT outputs
  output$table_top_paths <- renderDT({
    w <- where_data()$req
    res <- tryCatch({
      query_db(process_pool(), paste("SELECT path, COUNT(*) as count FROM", tbl_req(), w$clause, "GROUP BY path ORDER BY count DESC LIMIT 10"), w$params)
    }, error = function(e) data.frame(path=character(0), count=integer(0)))
    datatable(res, options = list(pageLength = 5))
  })
  
  output$table_top_ips <- renderDT({
    w <- where_data()$ip
    res <- tryCatch({
      query_db(process_pool(), paste("SELECT ip_address, total_requests, risk_score, classification FROM", tbl_ip(), w$clause, "ORDER BY risk_score DESC LIMIT 10"), w$params)
    }, error = function(e) data.frame(ip=character(0)))
    datatable(res, options = list(pageLength = 5))
  })
  
  output$table_recent_reqs <- renderDT({
    w <- where_data()$req
    res <- tryCatch({
      query_db(process_pool(), paste("SELECT timestamp, ip_address, method, path, status_code, classification FROM", tbl_req(), w$clause, "ORDER BY timestamp DESC LIMIT 50"), w$params)
    }, error = function(e) data.frame())
    datatable(res, options = list(pageLength = 10))
  })
  
  # Plotly Chart
  output$chart_time <- renderPlotly({
    w <- where_data()$req
    res <- tryCatch({
      query_db(process_pool(), paste("SELECT date_trunc('hour', timestamp) as time_bucket, COUNT(*) as count FROM", tbl_req(), w$clause, "GROUP BY time_bucket ORDER BY time_bucket"), w$params)
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
