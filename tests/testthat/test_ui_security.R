library(shiny)
library(bslib)
library(DT)
library(plotly)

source("../../R/ui_components.R")

test_that("the UI has no remote font dependency", {
  rendered <- htmltools::renderTags(ui)
  markup <- paste(c(rendered$head, rendered$html), collapse = "\n")

  expect_false(grepl("fonts[.](googleapis|gstatic)[.]com", markup))
})
