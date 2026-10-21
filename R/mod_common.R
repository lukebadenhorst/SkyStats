# Shared UI pieces for the method tabs (Autocorrelation, Point Patterns,
# Spatial Regression).

# Layout for a method tab: parameters and the Run button on the left, the
# method summary and the results on the right.
# controls: function(ns) returning the input controls.
# results: a tagList of outputs (build their ids with NS(id)).
method_tab_ui <- function(id, chapter, summary, controls, results) {
  ns <- NS(id)
  layout_columns(
    col_widths = c(4, 8),
    card(
      card_header("Parameters"),
      controls(ns),
      actionButton(ns("run"), "Run analysis", icon = icon("play"), class = "btn-primary w-100")
    ),
    layout_columns(
      col_widths = 12,
      fill = FALSE,
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span("Method"),
          span(class = "badge text-bg-info", chapter)
        ),
        summary
      ),
      results
    )
  )
}

alpha_input <- function(ns) {
  selectInput(ns("alpha"), "Significance level (alpha)", c(0.10, 0.05, 0.01), selected = 0.05)
}

# Yellow alert with the message of a failed run_safely() result, or NULL if
# it succeeded.
result_alert <- function(res) {
  if (isTRUE(res$ok)) {
    return(NULL)
  }
  div(class = "alert alert-warning", res$message)
}
