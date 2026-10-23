# Shared UI pieces: the floating panels used on every tab, and the pieces for
# the method tabs (Autocorrelation, Point Patterns, Spatial Regression).

# A rounded panel floating over the shared map (styled in www/app.css).
float_panel <- function(..., class = NULL, id = NULL) {
  div(id = id, class = paste(c("float-panel", class), collapse = " "), ...)
}

# A floating panel whose body folds away when its header is clicked. The
# folding happens in the browser (www/app.js). tag: optional small label in
# the header, such as a chapter ("Ch 4").
fold_panel <- function(title, ..., open = TRUE, tag = NULL) {
  float_panel(
    class = c("fold-panel", if (!open) "closed"),
    div(
      class = "fold-head",
      role = "button",
      tabindex = "0",
      `aria-expanded` = if (open) "true" else "false",
      span(class = "fold-title", title),
      if (!is.null(tag)) span(class = "fold-tag", tag),
      span(class = "fold-chevron", bsicons::bs_icon("chevron-down"))
    ),
    # fold-body animates its height; fold-inner clips; fold-content pads.
    div(class = "fold-body", div(class = "fold-inner", div(class = "fold-content", ...)))
  )
}

alpha_input <- function(ns) {
  segmented_input(ns("alpha"), "Significance level (alpha)", c("0.10" = "0.1", "0.05" = "0.05", "0.01" = "0.01"), selected = "0.05")
}

# Radio buttons drawn as a segmented control (class "seg", www/app.css), for
# a few short text choices.
segmented_input <- function(inputId, label, choices, selected = NULL) {
  tagAppendAttributes(radioButtons(inputId, label, choices, selected = selected, inline = TRUE), class = "seg")
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

# ---- Method tabs: settings panel, setup box, results card ------------------
#
# A method tab is a settings panel in the left column, a results card on the
# right and a layer in the method's own pane of the shared map. On the first
# visit the settings panel opens as the "setup box" in the centre of the
# screen (www/app.js and www/app.css switch it with the class .setup-mode).
# method_runner() runs the method, after the box's Run analysis button and
# then by itself whenever its inputs settle.

# One settings row: the input, then a plain-words help line that shows only
# in the setup box.
setting <- function(input, help) {
  div(class = "setting", input, p(class = "setting-help", help))
}

# The regions a method accepts, as selectInput() choices.
method_region_choices <- function(method) {
  choices <- region_choices()
  choices[choices %in% method_regions(method)]
}

# The method's settings panel, which doubles as the setup box. ns: the
# module's NS(); method: "autocorr", "quadrat" or "regression"; title: the
# method's short name ("Autocorrelation"); chapter: "Ch 4"; question and
# intro: the box's heading and sentence; fields: a tagList of setting() rows.
# .setup-only parts show only in the box, .panel-only parts only in the
# left column.
settings_panel <- function(ns, method, title, chapter, question, intro, fields) {
  region_help <- if (method == "regression") {
    "Regression compares countries, so it needs at least 15 of them. Only Europe and the whole World have enough."
  } else {
    "Each region gets its own map projection that keeps areas fair. World is not offered because no single projection can do that for the whole globe."
  }
  float_panel(
    id = ns("settings"),
    class = "settings-panel",
    div(
      class = "panel-head panel-only",
      span(class = "panel-title", paste(title, "settings")),
      span(class = "fold-tag", chapter)
    ),
    div(
      class = "setup-head setup-only",
      span(class = "fold-tag", paste(chapter, title, sep = " · ")),
      h3(question),
      p(intro)
    ),
    div(
      class = "settings-body",
      div(
        class = "setup-only",
        # A native select: a selectize dropdown would be clipped by the box's
        # scrolling body.
        setting(
          selectInput(ns("setup_region"), "Region", choices = method_region_choices(method), selectize = FALSE),
          region_help
        )
      ),
      fields,
      tags$a(class = "guide-link panel-only", href = "#", role = "button", "Settings guide ›")
    ),
    div(
      class = "setup-foot setup-only",
      span(class = "setup-note", "You can change these any time."),
      actionButton(ns("setup_run"), "Run analysis", class = "btn-run")
    )
  )
}

# The method's results card: the short summary (output "short"), the Show
# all results button and the full results. Expanding happens in the browser
# (the .btn-more handler in www/app.js). The busy progress line finds the
# card by its id, "<method>-card", so the module id must be the method name.
results_card <- function(ns, full) {
  float_panel(
    id = ns("card"),
    class = "results-card",
    uiOutput(ns("short")),
    actionButton(ns("more"), "Show all results", class = "btn-more"),
    div(class = "results-full", div(class = "results-full-inner", full))
  )
}

# The short card's content from a summary list (R/summaries.R): the label,
# the big number (counted up by www/app.js), the badge, the 2 x 2 grid of
# supporting numbers, the interpretation and the map legend.
summary_ui <- function(s, legend = NULL) {
  tagList(
    div(class = "card-label", s$label),
    div(
      class = "summary-head",
      span(
        class = "big-number",
        # formatC rather than format(): format() turns small values such as
        # 0.0003 into "3e-04".
        span(class = "count-up", `data-digits` = s$digits, formatC(s$value, format = "f", digits = s$digits))
      ),
      span(class = paste("badge-pill", paste0("tone-", s$tone)), s$badge)
    ),
    div(
      class = "mini-grid",
      lapply(names(s$mini), function(name) {
        div(span(class = "mini-label", name), span(class = "mini-value", s$mini[[name]]))
      })
    ),
    p(class = "summary-text", s$text),
    legend
  )
}

# Small colour swatches with labels, for the map layer. For a continuous
# scale, pass the binned colours and their labels.
legend_ui <- function(colours, labels, title = NULL) {
  div(
    class = "card-legend",
    if (!is.null(title)) div(class = "card-legend-title", title),
    div(
      class = "card-legend-items",
      lapply(seq_along(colours), function(i) {
        span(
          class = "card-legend-item",
          tags$i(class = "card-legend-swatch", style = paste0("background:", colours[[i]])),
          labels[[i]]
        )
      })
    )
  )
}

# NULL for a successful run. Otherwise the yellow alert with the message and,
# when the region was refused, one button per accepted region (www/app.js
# sends the pick as input$region_pick; app.R sets the region filter).
region_alert <- function(res, method) {
  if (isTRUE(res$ok)) {
    return(NULL)
  }
  accepted <- method_region_choices(method)
  div(
    class = "alert alert-warning region-alert",
    p(res$message),
    if (isTRUE(res$region_refused)) {
      div(
        class = "region-btns",
        lapply(seq_along(accepted), function(i) {
          tags$button(type = "button", class = "region-btn", `data-region` = accepted[[i]], names(accepted)[i])
        })
      )
    }
  )
}

# Runs a method tab. Returns a reactive with a run_safely() result (ok, then
# value or message) plus region_refused (TRUE when the region is one the
# method does not accept).
#   method     "autocorr", "quadrat" or "regression" (also the map pane)
#   active     reactive: TRUE while the tab is open
#   region_id  reactive: the shared region filter
#   params     reactive list of the method's own inputs, plus any data that
#              should re-run it (such as the filtered aircraft)
#   compute    function(p, region) returning a run_safely() result; it runs
#              isolated, so it must take its data from p, not read reactives
# Nothing runs until the setup box's Run analysis button; after that the
# method re-runs once its inputs have been still for 600 ms. The result is a
# lazy reactive: modules read it only in observers and outputs that start
# with req(active()), so an inactive tab never runs and keeps its last
# result.
method_runner <- function(input, session, method, active, region_id, params, compute) {
  done <- reactiveVal(FALSE)
  last_ok <- TRUE

  setup_box <- function(open) {
    session$sendCustomMessage("setup", list(id = session$ns("settings"), open = open))
  }

  # Opening the tab: the setup box until it has run, else the last layer.
  # Leaving it: close the box and hide the layer.
  observeEvent(active(), {
    if (active()) {
      if (done()) {
        set_pane(session, method, if (last_ok) "shown" else "hidden")
      } else {
        setup_box(TRUE)
      }
    } else {
      setup_box(FALSE)
      set_pane(session, method, "hidden")
    }
  })

  # The box's region follows the shared filter (or Europe when the method
  # refuses it), so reopening the box from "Settings guide" and pressing Run
  # keeps the current region.
  observeEvent(list(active(), region_id()), {
    if (active()) {
      updateSelectInput(session, "setup_region", selected = default_method_region(region_id(), method))
    }
  })

  observeEvent(input$setup_run, {
    # The box's region sets the shared filter, so it applies to every tab.
    updateSelectInput(session$rootScope(), "region", selected = input$setup_region)
    done(TRUE)
    setup_box(FALSE)
  })

  trigger <- debounce(reactive(list(done = done(), params = params(), region = region_id())), 600)

  reactive({
    # Everything comes from the debounced trigger, so a burst of changes
    # runs the method once, with the newest values.
    t <- trigger()
    req(t$done)
    set_pane(session, method, "busy")
    # Isolated: a reactive that compute() reads directly would re-run the
    # method at once, skipping the debounce.
    res <- isolate(compute(t$params, t$region))
    res$region_refused <- !(t$region %in% method_regions(method))
    last_ok <<- isTRUE(res$ok)
    set_pane(session, method, if (last_ok) "shown" else "hidden")
    res
  })
}
