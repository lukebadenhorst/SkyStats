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

# Colours for base-R plots that follow the light/dark theme.
# fg: the plot's text colour as any CSS colour ("#DEE2E6", "rgb(222, 226, 230)");
# NULL or unreadable means light mode. Light text means a dark background.
plot_palette <- function(fg = NULL) {
  hex <- if (is.null(fg)) NA else htmltools::parseCssColors(fg, mustWork = FALSE)
  if (is.na(hex)) {
    hex <- "#000000"
  }
  rgb <- grDevices::col2rgb(hex)[, 1]
  dark <- mean(rgb) > 128
  list(
    dark = dark,
    fg = grDevices::rgb(rgb[1], rgb[2], rgb[3], maxColorValue = 255),
    bar = if (dark) "#457b9d" else "#a8dadc",
    line = if (dark) "#a8dadc" else "#1d3557",
    border = if (dark) "#212529" else "#ffffff"
  )
}

# Call inside renderPlot(..., bg = "transparent"): sets the axis and label
# colours to the page's text colour and returns plot_palette(). Shiny re-sends
# the colour when the dark-mode switch flips, so the plot redraws to match.
use_plot_theme <- function() {
  info <- getCurrentOutputInfo()
  pal <- plot_palette(if (is.function(info$fg)) info$fg())
  par(fg = pal$fg, col.axis = pal$fg, col.lab = pal$fg, col.main = pal$fg)
  pal
}

# Yellow alert with the message of a failed run_safely() result, or NULL if
# it succeeded.
result_alert <- function(res) {
  if (isTRUE(res$ok)) {
    return(NULL)
  }
  div(class = "alert alert-warning", res$message)
}
