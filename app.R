library(shiny)
library(bslib)
library(DT)
library(plotly)
library(dplyr)
for (module in c("config", "db", "auth", "validation", "parser_nginx", "parser_cloudflare",
                 "detection_rules", "scoring", "summaries", "import", "analytics", "demo", "ui_components")) {
  source(paste0("R/", module, ".R"))
}
options(shiny.sanitize.errors = TRUE, shiny.maxRequestSize = MAX_IMPORT_BYTES, shiny.autoreload = FALSE)

# One lazy pool per R process. Anonymous sessions never initialize it.
shared_pool <- NULL
process_pool <- function() {
  if (is.null(shared_pool)) shared_pool <<- get_db_pool()
  shared_pool
}
onStop(function() { if (!is.null(shared_pool)) pool::poolClose(shared_pool) })
auth_limiter <- new_auth_limiter()
auth_global_limiter <- new_auth_limiter()
demo_cache <- NULL
public_demo <- function() {
  if (is.null(demo_cache) || difftime(Sys.time(), demo_cache$created, units = "secs") > 60) {
    demo_cache <<- list(data = generate_demo_data(), created = Sys.time())
  }
  demo_cache$data
}

server <- function(input, output, session) {
  logged_in <- reactiveVal(FALSE)
  started <- NULL
  active <- NULL
  last_login <- as.POSIXct(0, origin = "1970-01-01")
  last_refresh <- as.POSIXct(0, origin = "1970-01-01")
  refresh <- reactiveVal(0L)
  prepared_upload <- reactiveVal(NULL)
  upload_message <- reactiveVal("Preview a log file before importing it.")
  auth_key <- auth_client_key(session$request)
  admin_now <- function() isTRUE(logged_in()) && admin_session_valid(started, active)
  touch <- function() { if (admin_now()) active <<- Sys.time() }
  refresh_data <- function() {
    if (difftime(Sys.time(), last_refresh, units = "secs") >= 2) {
      last_refresh <<- Sys.time()
      refresh(isolate(refresh()) + 1L)
    }
  }
  logout <- function(message = "Signed out. Synthetic demo restored.") {
    logged_in(FALSE)
    started <<- NULL
    active <<- NULL
    prepared_upload(NULL)
    upload_message("Preview a log file before importing it.")
    removeModal()
    nav_select("main_nav", "Dashboard")
    showNotification(message, type = "message")
  }
  observe({
    invalidateLater(30000, session)
    if (logged_in() && !admin_now()) logout("Your admin session expired. Sign in again.")
  })
  observeEvent(input$activity, touch(), ignoreInit = TRUE)
  observe({
    if (logged_in()) nav_show("main_nav", "Logs & Import") else nav_hide("main_nav", "Logs & Import")
  })
  output$auth_button_ui <- renderUI({
    if (logged_in()) actionButton("btn_logout", "Sign out", class = "btn-outline-light btn-sm", icon = icon("right-from-bracket"))
    else actionButton("btn_login_modal", "Admin sign in", class = "btn-outline-light btn-sm", icon = icon("lock"))
  })
  output$demo_banner <- renderUI({
    tags$div(class = if (logged_in()) "source-banner source-live" else "source-banner",
      tags$span(class = "source-label", if (logged_in()) "PRIVATE WORKSPACE" else "INTERACTIVE DEMO"),
      tags$span(if (logged_in()) "Production logs · visible to your admin session only." else "Explore synthetic traffic. Production logs stay private."))
  })
  observeEvent(input$btn_login_modal, {
    showModal(modalDialog(title = "Admin workspace", size = "s", easyClose = TRUE,
      tags$p("Sign in to inspect production traffic and import logs."),
      textInput("auth_user", "Username"), passwordInput("auth_pass", "Password"),
      tags$p(class = "text-muted", "Sessions expire after 30 minutes of inactivity or 8 hours."),
      footer = tagList(modalButton("Cancel"), actionButton("btn_login_submit", "Sign in", class = "btn-primary"))))
  })
  observeEvent(input$btn_login_submit, {
    now <- Sys.time()
    if (difftime(now, last_login, units = "secs") < 1) return()
    last_login <<- now
    updateTextInput(session, "auth_pass", value = "")
    if (auth_locked(auth_limiter, auth_key) || auth_locked(auth_global_limiter, "all")) {
      showNotification("Too many attempts. Try again later.", type = "error")
      return()
    }
    record_auth_failure(auth_global_limiter, "all", max_failures = 120L)
    if (verify_admin_credentials(input$auth_user, input$auth_pass, Sys.getenv("APP_USERNAME", ""), Sys.getenv("APP_PASSWORD_HASH", ""))) {
      clear_auth_failures(auth_limiter, auth_key)
      started <<- now
      active <<- now
      logged_in(TRUE)
      removeModal()
      showNotification("Signed in. Your private workspace is ready.", type = "message")
    } else {
      locked <- record_auth_failure(auth_limiter, auth_key)
      showNotification(if (locked) "Too many attempts. Try again later." else "Invalid credentials.", type = "error")
    }
  })
  observeEvent(input$btn_logout, logout())
  observeEvent(input$refresh, { touch(); refresh_data() })
  observe({
    invalidateLater(60000, session)
    if (isTRUE(input$auto_refresh)) refresh_data()
  })
  observeEvent(input$date_preset, {
    days <- switch(input$date_preset, "today" = 0, "week" = 6, "month" = 30, NULL)
    if (!is.null(days)) updateDateRangeInput(session, "date_filter", start = utc_today() - days, end = utc_today())
  })
  observeEvent(input$reset_filters, {
    updateDateRangeInput(session, "date_filter", start = utc_today() - 6, end = utc_today())
    for (id in c("class_filter", "status_filter", "method_filter")) updateSelectInput(session, id, selected = "All")
    updateTextInput(session, "ip_filter", value = "")
    updateTextInput(session, "path_filter", value = "")
  })
  observeEvent(input$show_threats, updateSelectInput(session, "class_filter", selected = "scanner"))
  filters <- reactive({
    normalize_filters(input$date_filter, if (is.null(input$class_filter)) "All" else input$class_filter,
      if (is.null(input$status_filter)) "All" else input$status_filter, input$ip_filter, input$path_filter,
      if (is.null(input$method_filter)) "All" else input$method_filter)
  })
  stable_filters <- debounce(filters, 500)
  snapshot <- reactive({
    refresh()
    live <- logged_in()
    tryCatch({
      f <- stable_filters()
      if (live) {
        req(admin_now())
        query <- request_query(f)
        data <- query_db(process_pool(), query$sql, query$params)
      } else data <- filter_demo(public_demo(), f)
      finish_snapshot(data, f, if (live) "Live production" else "Synthetic demo")
    }, error = function(e) {
      # Do not log attacker-controlled SQL parameters, raw log contents or secrets.
      message("Traffic snapshot unavailable [", class(e)[1], "]")
      list(error = if (inherits(e, "simpleError") && grepl("Choose a date|Invalid filter|Enter one valid|Search text", conditionMessage(e)))
        conditionMessage(e) else "Traffic data is unavailable. Try refreshing shortly.", source = if (live) "Live production" else "Synthetic demo")
    })
  })
  data_view <- reactive({
    s <- snapshot()
    validate(need(is.null(s$error), s$error))
    if (s$source == "Live production") req(admin_now())
    s$data
  })
  metrics <- reactive(traffic_metrics(data_view()))
  output$total_req <- renderText(format(metrics()$total, big.mark = ","))
  output$unique_ips <- renderText(format(metrics()$ips, big.mark = ","))
  output$sus_bots <- renderText(format(metrics()$flagged, big.mark = ","))
  output$sus_404 <- renderText(sprintf("%.1f%%", metrics()$error_rate))
  output$bandwidth <- renderText(sprintf("%.1f MiB", metrics()$bandwidth))
  output$coverage <- renderUI({
    s <- snapshot()
    if (!is.null(s$error)) return(tags$div(class = "data-notice notice-error", role = "alert", s$error))
    tags$div(class = "data-notice", role = "status",
      tags$span(sprintf("%s · %s – %s UTC", s$source, s$filters$start, s$filters$end)),
      tags$span(paste(if (s$capped) "Latest 20,000 requests before classification filter ·" else "Complete matching window ·",
        format(s$updated, "%H:%M:%S", tz = "UTC"), "UTC")))
  })
  table_widget <- function(data, selection = "none", page = 10L) {
    datatable(data, rownames = FALSE, escape = TRUE, selection = selection,
      options = list(pageLength = page, lengthMenu = c(5, 10, 25, 50), scrollX = TRUE,
        autoWidth = TRUE, order = list(), language = list(emptyTable = "No matching requests. Try a wider date range or reset the filters.")))
  }
  output$table_top_paths <- renderDT({
    data <- data_view() |> count(path, name = "Requests", sort = TRUE) |> head(20) |> rename(Path = path)
    table_widget(data, page = 5L)
  }, server = FALSE)
  ip_rows <- reactive(ip_investigation(data_view()))
  output$table_top_ips <- renderDT(table_widget(head(ip_rows(), 1000), selection = "single", page = 5L), server = FALSE)
  recent_rows <- reactive({
    d <- head(data_view(), 1000)
    data.frame(Time_UTC = format(d$timestamp, "%Y-%m-%d %H:%M:%S", tz = "UTC"), IP = d$ip_address,
      Method = d$method, Path = d$path, Status = d$status_code, Signal = unname(CLASS_LABELS[d$classification]),
      Score = d$bot_score, Reason = d$reason, check.names = FALSE)
  })
  output$table_recent_reqs <- renderDT(table_widget(recent_rows(), selection = "single"), server = FALSE)
  observeEvent(input$table_top_ips_rows_selected, {
    index <- input$table_top_ips_rows_selected
    if (length(index) != 1L || !is.numeric(index) || is.na(index) || index < 1 || index > min(nrow(ip_rows()), 1000L)) return()
    ip <- ip_rows()$IP[index]
    d <- data_view(); d <- d[d$ip_address == ip, , drop = FALSE]
    showModal(modalDialog(title = paste("Investigate", ip), size = "l", easyClose = TRUE,
      tags$p(sprintf("%d requests · %d paths · %d HTTP errors · highest score %.0f", nrow(d), length(unique(d$path)), sum(d$status_code >= 400), max(d$bot_score))),
      tags$p("These signals describe the current filtered snapshot. User-agent identity is unverified."),
      tags$ul(lapply(unique(d$reason), tags$li)),
      tags$h5("Most requested paths"), tags$ul(lapply(head(names(sort(table(d$path), decreasing = TRUE)), 8), tags$li)),
      actionButton("filter_selected_ip", "Filter this IP", class = "btn-primary"), footer = modalButton("Close")))
  })
  observeEvent(input$filter_selected_ip, {
    index <- input$table_top_ips_rows_selected
    if (length(index) == 1L && is.numeric(index) && !is.na(index) && index >= 1 && index <= min(nrow(ip_rows()), 1000L)) {
      updateTextInput(session, "ip_filter", value = ip_rows()$IP[index])
      removeModal()
    }
  })
  observeEvent(input$table_recent_reqs_rows_selected, {
    index <- input$table_recent_reqs_rows_selected
    d <- head(data_view(), 1000)
    if (length(index) != 1L || !is.numeric(index) || is.na(index) || index < 1 || index > nrow(d)) return()
    row <- d[index, ]
    showModal(modalDialog(title = "Request details", size = "l", easyClose = TRUE,
      tags$dl(tags$dt("Path"), tags$dd(tags$code(row$path)), tags$dt("IP / user agent"),
        tags$dd(paste(row$ip_address, row$user_agent, sep = " · ")), tags$dt("Signal explanation"), tags$dd(row$reason),
        tags$dt("Response"), tags$dd(paste(row$status_code, "·", row$response_size, "bytes"))), footer = modalButton("Close")))
  })
  chart_style <- function(chart) {
    chart |> layout(paper_bgcolor = "transparent", plot_bgcolor = "transparent", font = list(color = "#b9c6dc", family = "system-ui"),
      xaxis = list(title = "", gridcolor = "#263248"), yaxis = list(title = "Requests", gridcolor = "#263248", rangemode = "tozero"),
      margin = list(l = 48, r = 20, t = 15, b = 50), legend = list(orientation = "h", x = 0, y = -0.2)) |>
      config(displaylogo = FALSE, displayModeBar = FALSE, responsive = TRUE)
  }
  output$chart_time <- renderPlotly({
    d <- data_view()
    validate(need(nrow(d), "No traffic in this window. Reset filters to explore the demo."))
    bucket <- if (identical(input$time_bucket, "day")) "days" else "hours"
    d$time <- as.POSIXct(cut(d$timestamp, breaks = bucket), tz = "UTC")
    counts <- d |> count(time, classification, name = "Requests")
    plot_ly(counts, x = ~time, y = ~Requests, color = ~classification, colors = CLASS_COLORS,
      type = "scatter", mode = "lines", line = list(width = 2), hoverinfo = "x+y+name") |> chart_style()
  })
  output$chart_classes <- renderPlotly({
    d <- data_view() |> count(classification, name = "Requests")
    validate(need(nrow(d), "No matching traffic."))
    plot_ly(d, labels = ~unname(CLASS_LABELS[classification]), values = ~Requests, type = "pie", hole = .65,
      marker = list(colors = unname(CLASS_COLORS[d$classification])), textinfo = "percent", hoverinfo = "label+value+percent") |>
      chart_style() |> layout(showlegend = TRUE)
  })
  output$chart_status <- renderPlotly({
    d <- data_view() |> count(status_code, name = "Requests")
    validate(need(nrow(d), "No matching traffic."))
    plot_ly(d, x = ~as.character(status_code), y = ~Requests, type = "bar", marker = list(color = "#67a9ff"), hoverinfo = "x+y") |> chart_style()
  })
  output$insights <- renderUI({
    d <- data_view(); m <- traffic_metrics(d)
    if (!nrow(d)) return(tags$p("No matching traffic. Reset your filters or import a log file in the admin workspace."))
    top <- names(sort(table(d$path), decreasing = TRUE))[1]
    tags$div(class = "insight-list",
      tags$p(tags$strong(sprintf("%.1f%% flagged", 100 * m$flagged / m$total)), " by configured request rules. Review evidence before taking action."),
      tags$p(tags$strong(sprintf("%d bot / tool claims", m$bots)), "; user agents can be spoofed."),
      tags$p(tags$strong("Busiest path: "), tags$code(top)),
      tags$p(sprintf("%.1f MiB response volume. Figures describe this filtered snapshot.", m$bandwidth)))
  })
  download_snapshot <- function() {
    s <- snapshot()
    req(is.null(s$error))
    if (s$source == "Live production") req(admin_now())
    s
  }
  output$export_csv <- downloadHandler(filename = function() paste0("traffic-", if (admin_now()) "private-" else "demo-", utc_today(), ".csv"),
    contentType = "text/csv; charset=utf-8", content = function(file) {
      s <- download_snapshot(); d <- s$data
      d$timestamp <- format(d$timestamp, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      d$source <- s$source
      d$coverage <- if (s$capped) "Latest 20,000 before classification filter" else "Complete matching window"
      write.csv(spreadsheet_safe(d), file, row.names = FALSE, na = "", fileEncoding = "UTF-8")
    })
  output$export_report <- downloadHandler(filename = function() paste0("traffic-report-", utc_today(), ".txt"),
    contentType = "text/plain; charset=utf-8", content = function(file) writeLines(traffic_report(download_snapshot()), file, useBytes = TRUE))
  observeEvent(list(input$log_upload, input$log_type), {
    prepared_upload(NULL)
    if (!admin_now() || is.null(input$log_upload)) return()
    info <- input$log_upload
    tryCatch({
      req(is.data.frame(info), nrow(info) == 1L, scalar_text(info$name, 255L))
      prepared <- prepare_import(info$datapath, input$log_type, uploaded = TRUE)
      prepared$filename <- info$name
      prepared_upload(prepared)
      upload_message(sprintf("Preview ready: %d accepted, %d rejected. Review before importing.", nrow(prepared$data), prepared$rejected))
      touch()
    }, error = function(e) {
      message("Upload rejected [", class(e)[1], "]")
      upload_message("Cannot preview this file. Use Nginx combined logs or Cloudflare CSV, up to 10 MiB and 50,000 rows.")
    })
  }, ignoreNULL = FALSE)
  output$upload_status <- renderText(upload_message())
  output$import_preview <- renderDT({
    if (!admin_now() || is.null(prepared_upload())) return(table_widget(data.frame()))
    d <- head(prepared_upload()$data, 20)
    table_widget(d[, c("ip_address", "method", "path", "status_code", "classification")], page = 5L)
  }, server = FALSE)
  observeEvent(input$btn_process, {
    req(admin_now(), prepared_upload())
    touch()
    tryCatch({
      prepared <- prepared_upload()
      con <- pool::poolCheckout(process_pool())
      result <- tryCatch(import_requests(con, prepared, prepared$filename), finally = pool::poolReturn(con))
      prepared_upload(NULL)
      upload_message(sprintf("Imported %d requests. %d malformed rows were skipped.", result$accepted, result$rejected))
      refresh(isolate(refresh()) + 1L)
    }, error = function(e) {
      message("Import failed [", class(e)[1], "]")
      upload_message("Import failed. This file may already be imported, or storage is unavailable. No partial import was saved.")
    })
  })
  output$import_history <- renderDT({
    refresh()
    if (!admin_now()) return(table_widget(data.frame()))
    history <- tryCatch(query_db(process_pool(), "SELECT f.filename,f.file_type,f.imported_at,r.accepted_rows,r.rejected_rows FROM imported_log_files f LEFT JOIN import_registry r ON r.file_id=f.id ORDER BY f.imported_at DESC,f.id DESC LIMIT 100"), error = function(e) NULL)
    validate(need(!is.null(history), "Import history is unavailable."))
    table_widget(history)
  }, server = FALSE)
}

shinyApp(ui, server)
