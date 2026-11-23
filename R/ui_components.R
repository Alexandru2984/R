library(shiny)
library(bslib)
library(DT)
library(plotly)

cyber_theme <- bs_theme(version = 5, bg = "#0b1423", fg = "#eaf1fc", primary = "#4dd5ac",
  secondary = "#253650", success = "#4dd5ac", info = "#67a9ff", warning = "#f2c66d", danger = "#ff7186",
  base_font = font_collection("system-ui", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "sans-serif"),
  heading_font = font_collection("system-ui", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "sans-serif"),
  code_font = font_collection("ui-monospace", "SFMono-Regular", "Cascadia Code", "Liberation Mono", "monospace"))

analytics_card <- function(title, ..., subtitle = NULL) {
  card(fill = FALSE, card_header(tags$div(class = "card-title-text", title),
                   if (!is.null(subtitle)) tags$div(class = "card-subtitle-text", subtitle)), card_body(..., fillable = FALSE))
}
metric_card <- function(name, output_id, note, class = "") {
  tags$div(class = paste("metric", class), tags$div(class = "metric-name", name),
    tags$div(class = "metric-value", textOutput(output_id, inline = TRUE)), tags$div(class = "metric-note", note))
}

build_ui <- function() {
ui_today <- as.Date(Sys.time(), tz = "UTC")
page_navbar(
  id = "main_nav", title = tags$span(tags$span(class = "brand-mark", "R"), "Traffic Intelligence"),
  window_title = "Traffic Intelligence — Understand your web traffic",
  lang = "en", theme = cyber_theme, fillable = FALSE,
  navbar_options = navbar_options(collapsible = TRUE, theme = "dark", bg = "#0b1423"),
  header = tagList(
    tags$head(
      tags$meta(name = "description", content = "Explore web traffic, inspect bot and scanner signals, and investigate access logs in an interactive demo. Production logs stay in a private admin workspace."),
      tags$link(rel = "canonical", href = "https://r.micutu.com/"),
      tags$meta(property = "og:title", content = "Traffic Intelligence — Understand your web traffic"),
      tags$meta(property = "og:description", content = "Turn access logs into a clearer picture. Explore synthetic traffic and transparent security signals."),
      tags$meta(property = "og:type", content = "website"),
      tags$meta(property = "og:url", content = "https://r.micutu.com/"),
      tags$meta(name = "twitter:card", content = "summary"),
      tags$link(rel = "icon", type = "image/svg+xml", href = "favicon.svg"), tags$link(rel = "stylesheet", href = "dashboard.css"), tags$script(src = "dashboard.js", defer = NA)),
    tags$a(class = "skip-link", href = "#main-content", "Skip to traffic analysis"),
    tags$div(class = "page-shell",
      tags$div(class = "hero",
        tags$div(tags$div(class = "eyebrow", "YOUR TRAFFIC, IN FOCUS"),
          tags$h1("See the signal in every request."),
          tags$p("Understand your visitors, investigate suspicious activity, and turn raw access logs into a clearer picture.")),
        tags$div(class = "hero-actions", downloadButton("export_csv", "Export CSV", class = "btn-outline-light"),
          downloadButton("export_report", "Save report", class = "btn-outline-light"))),
      uiOutput("demo_banner"))),
  nav_panel("Dashboard", value = "Dashboard",
    layout_sidebar(fillable = FALSE,
      sidebar = sidebar(title = "Explore traffic", width = 285, open = list(desktop = "open", mobile = "closed"),
        selectInput("date_preset", "Time window", choices = c("Last 7 days" = "week", "Today" = "today", "Last 31 days" = "month", "Custom dates" = "custom"), selected = "week", selectize = FALSE),
        tags$div(id = "date_filter", class = "traffic-date-range shiny-input-container",
          tags$fieldset(tags$legend("Dates (UTC)"), tags$div(class = "date-fields",
            tags$div(tags$label(`for` = "date_start", "From"), tags$input(id = "date_start", type = "date", class = "form-control", value = as.character(ui_today - 6), max = as.character(ui_today))),
            tags$div(tags$label(`for` = "date_end", "Through"), tags$input(id = "date_end", type = "date", class = "form-control", value = as.character(ui_today), max = as.character(ui_today)))))),
        selectInput("class_filter", "Traffic signal", choices = c("All traffic" = "All", "Likely human" = "likely_human", "Bot / tool claim" = "known_bot", "Scanner signals" = "scanner", "Suspicious" = "suspicious", "Unknown" = "unknown"), selectize = FALSE),
        selectInput("status_filter", "HTTP status", choices = c("All responses" = "All", "Success · 2xx" = "2xx", "Redirect · 3xx" = "3xx", "Client errors · 4xx" = "4xx", "Server errors · 5xx" = "5xx", "Not found · 404" = "404"), selectize = FALSE),
        textInput("ip_filter", "IP address", placeholder = "e.g. 192.0.2.201"),
        textInput("path_filter", "Path contains", placeholder = "e.g. /api · press / to search"),
        selectInput("method_filter", "HTTP method", choices = c("All", "GET", "POST", "HEAD", "PUT", "PATCH", "DELETE", "OPTIONS"), selectize = FALSE),
        tags$hr(),
        tags$div(class = "filter-actions", actionButton("refresh", "Refresh traffic", icon = icon("rotate"), class = "btn-primary w-100"),
          actionButton("reset_filters", "Reset filters", class = "btn-outline-light w-100")),
        uiOutput("source_controls"),
        checkboxInput("compare_period", "Compare previous period", value = FALSE),
        checkboxInput("auto_refresh", "Refresh every minute", value = FALSE),
        tags$p(class = "help-text", "Up to 31 days and the latest 20,000 matching requests. Classification applies within that snapshot.")),
      tags$main(id = "main-content", tabindex = "-1",
        uiOutput("coverage"),
        tags$section(class = "metric-grid", `aria-label` = "Traffic summary",
          metric_card("Requests", "total_req", "In your filtered snapshot"),
          metric_card("Unique IPs", "unique_ips", "Addresses, not verified people"),
          metric_card("Flagged requests", "sus_bots", "Scanner & suspicious signals", "metric-risk"),
          metric_card("HTTP error rate", "sus_404", "Responses with status 4xx / 5xx", "metric-error")),
        uiOutput("comparison_summary"),
        card(card_header(tags$div(class = "chart-toolbar",
          tags$div(tags$div(class = "card-title-text", "Traffic over time"), tags$div(class = "card-subtitle-text", "Request volume by signal · UTC")),
          selectInput("time_bucket", "Group by", choices = c("Hour" = "hour", "Day" = "day"), selectize = FALSE))),
          card_body(plotlyOutput("chart_time", height = "320px"))),
        tags$div(class = "analytics-grid",
          analytics_card("Traffic composition", plotlyOutput("chart_classes", height = "290px"), subtitle = "Signals are heuristic; bot identity is unverified."),
          analytics_card("HTTP responses", plotlyOutput("chart_status", height = "290px"), subtitle = "Find errors, redirects and successful requests.")),
        analytics_card("When traffic arrives", plotlyOutput("chart_activity", height = "300px"), subtitle = "Total requests by UTC weekday and hour across your filtered snapshot. Repeated weekdays are combined."),
        tags$div(class = "analytics-grid",
          analytics_card("Reported countries", DTOutput("table_countries", fill = FALSE), subtitle = "Country codes supplied in the logs; no geolocation is inferred. Missing or invalid values appear as Unknown."),
          analytics_card("Request methods", DTOutput("table_methods", fill = FALSE), subtitle = "HTTP method distribution for the same filtered snapshot.")),
        tags$div(class = "analytics-grid wide-main",
          analytics_card("IPs to investigate", DTOutput("table_top_ips", fill = FALSE), subtitle = "Select an IP for evidence and a focused view. Up to 1,000 addresses."),
          analytics_card("At a glance", uiOutput("insights"), actionButton("show_threats", "Explore scanner signals", class = "btn-outline-light mt-3"))),
        analytics_card("Most requested paths", DTOutput("table_top_paths", fill = FALSE), subtitle = "Your top 20 paths by request count."),
        analytics_card("Request explorer", DTOutput("table_recent_reqs", fill = FALSE), subtitle = "Latest 1,000 requests in this snapshot. Select a row for details; export CSV for the full snapshot."),
        analytics_card("How to read the signals",
          tags$details(class = "policy-note", tags$summary("Scoring, coverage and privacy"),
            tags$p(tags$strong("Transparent rules. "), "Sensitive endpoints, traversal and basic injection probes add 8 points. A bot or tool user-agent claim adds 5. A missing user agent adds 2. Signals can combine; a suspicious path takes precedence."),
            tags$p(tags$strong("Investigation, not automatic blocking. "), "These rules do not prove identity or malicious intent. Normal login and admin routes alone do not count as scanner activity. Review context before acting."),
            tags$p(tags$strong("One consistent snapshot. "), "Charts, metrics and exports use the same filtered requests. Large result sets include only the latest 20,000 requests before classification filtering. Empty hours may appear as gaps."),
            tags$p(tags$strong("Public by design, private by default. "), "The public demo is generated locally from synthetic traffic. Production data requires admin authentication. Live exports may contain IP addresses, URLs and user agents.")))
      )
    )
  ),
  nav_panel("Logs & Import", value = "Logs & Import",
    tags$div(class = "import-intro", tags$h2("Bring your logs into focus"),
      tags$p(class = "text-muted", "Preview, validate, then import. All accepted rows are saved together, and identical files are detected by content.")),
    tags$div(class = "import-grid",
      analytics_card("Upload a log file",
        fileInput("log_upload", "Log file", accept = c(".log", ".txt", ".csv"), buttonLabel = "Choose file", placeholder = "No file selected"),
        radioButtons("log_type", "Format", choices = c("Nginx combined log" = "nginx", "Cloudflare CSV" = "cloudflare")),
        tags$p(class = "help-text", "Maximum 10 MiB and 50,000 lines. The preview shows up to 20 accepted rows. Invalid rows are skipped and counted."),
        textOutput("upload_status"), actionButton("btn_process", "Import validated rows", class = "btn-primary w-100"),
        tags$p(class = "help-text mt-3", "An identical file is imported once. Overlapping files with different contents can still contain duplicate requests.")),
      analytics_card("Preview before saving", DTOutput("import_preview", fill = FALSE), subtitle = "Nothing is saved until you choose Import validated rows.")),
    analytics_card("Import history", DTOutput("import_history", fill = FALSE), subtitle = "Latest 100 imports. Older imports may not include validation counts."),
    analytics_card("Admin audit trail", textOutput("audit_notice"), DTOutput("audit_history", fill = FALSE), subtitle = "Latest 200 authenticated actions. Passwords, client IPs and raw log contents are never included.")
  ),
  nav_spacer(), nav_item(uiOutput("auth_button_ui")),
  footer = tags$footer(class = "site-footer", tags$span("R Traffic Intelligence · built for closer inspection"),
    tags$span("Synthetic public demo · private admin workspace · UTC timestamps"))
)

}
ui <- function(request = NULL) build_ui()
