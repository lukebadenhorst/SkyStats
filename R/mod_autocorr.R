# Autocorrelation tab: counts aircraft in a hex grid over the region,
# runs a global test (Moran's I, Geary's C or Global G) and maps the LISA
# clusters on the shared map. The statistics are in R/stats_autocorr.R.
#
# Three parts, all with module id "autocorr" (the method name):
#   autocorr_settings_ui()  the settings panel, which is also the setup box
#   autocorr_results_ui()   the results card
#   autocorr_server()       runs the method and draws the map layer
# autocorr_server() takes three reactives from app.R:
#   aircraft  prepped + filtered state vectors
#   region_id the selected region
#   active    TRUE while the tab is open

lisa_colours <- c(
  "High-High" = "#d7191c",
  "Low-Low" = "#2c7bb6",
  "High-Low" = "#fdae61",
  "Low-High" = "#abd9e9",
  "Not significant" = "#eeeeee"
)

autocorr_settings_ui <- function(id) {
  ns <- NS(id)
  settings_panel(
    ns,
    "autocorr",
    "Autocorrelation",
    question = "Do busy areas sit next to other busy areas?",
    intro = "We cover the region in hexagons, count the aircraft in each, and test whether neighbouring hexes have similar counts.",
    fields = tagList(
      setting(
        sliderInput(ns("hex_km"), "Hex size (km)", min = 50, max = 500, value = 150, step = 25),
        "How wide each hexagon is. Small hexes show more detail but many will be empty; big hexes smooth things out but can hide local hot spots."
      ),
      setting(
        checkboxInput(ns("log"), "Use log(count + 1)", value = TRUE),
        "A few hexes over busy hubs have far more aircraft than the rest. The log scale stops those few from dominating the result."
      ),
      setting(
        selectInput(
          ns("weights"),
          "Spatial weights",
          c(
            "Queen contiguity" = "queen",
            "K nearest neighbours" = "knn",
            "Distance band" = "dist",
            "Inverse distance" = "idw"
          ),
          selectize = FALSE
        ),
        "Who counts as a neighbour. Queen: hexes that touch. K nearest: the k closest hexes, touching or not. Distance band: every hex within a set distance. Inverse distance: the same, but closer hexes count for more."
      ),
      conditionalPanel(
        "input.weights == 'knn'",
        ns = ns,
        setting(
          numericInput(ns("k"), "k", value = 6, min = 1, max = 20),
          "How many of the closest hexes count as neighbours."
        )
      ),
      conditionalPanel(
        "input.weights == 'dist' || input.weights == 'idw'",
        ns = ns,
        setting(
          numericInput(ns("d"), "Distance band d (km)", value = 300, min = 50),
          "Hexes whose centres are closer than this count as neighbours. Too small and some hexes end up with none."
        )
      ),
      setting(
        segmented_input(
          ns("statistic"),
          "Global statistic",
          c("Moran's I" = "moran", "Geary's C" = "geary", "Global G" = "globalg")
        ),
        "Moran's I compares each hex with the average of its neighbours. Geary's C looks at the differences between neighbours instead. Global G asks whether the high counts specifically are bunched together."
      ),
      # Global G needs binary weights, and spdep has no permutation test
      # for it, so those choices are hidden (the server enforces them too).
      conditionalPanel(
        "input.statistic != 'globalg'",
        ns = ns,
        setting(
          segmented_input(ns("style"), "Weights style", c("W (row-standardised)" = "W", "B (binary)" = "B")),
          "W shares a weight of 1 among each hex's neighbours, so a hex with many neighbours does not count for more. B gives every neighbour a weight of 1."
        ),
        setting(
          segmented_input(ns("inference"), "Inference", c("Analytic" = "analytic", "Permutation" = "perm")),
          "How to get the p-value. Analytic uses a formula and is instant. Permutation shuffles the counts around the map many times and checks how unusual the real pattern is: slower, but it makes fewer assumptions."
        ),
        conditionalPanel(
          "input.inference == 'perm'",
          ns = ns,
          setting(
            numericInput(ns("nsim"), "Simulations", value = 499, min = 99, max = 999, step = 100),
            "How many times to shuffle. More shuffles give a steadier p-value but take longer."
          )
        )
      ),
      conditionalPanel(
        "input.statistic == 'globalg'",
        ns = ns,
        p(class = "setting-note", "Global G uses binary weights (style B) and the analytic test.")
      ),
      setting(
        alpha_input(ns),
        "How strong the evidence must be before we call a pattern real. 0.05 means we accept a 5% chance of seeing a pattern that is really just chance."
      )
    )
  )
}

# The full results, in the order the old tab showed them.
autocorr_results_ui <- function(id) {
  ns <- NS(id)
  results_card(
    ns,
    full = div(
      class = "results-grid",
      div(class = "results-section span-all", h5("Interpretation"), uiOutput(ns("interpretation"))),
      div(class = "results-section", h5("Global test"), tableOutput(ns("global")), uiOutput(ns("setup"))),
      div(class = "results-section", h5("Moran scatterplot"), plotOutput(ns("scatter"), height = "260px")),
      div(
        class = "results-section span-all",
        h5("Strongest local clusters"),
        p(class = "results-note", "The 10 significant hexes with the largest local I."),
        tableOutput(ns("top"))
      )
    ),
    uses = uses_ui(
      c(
        "Airspace sector design" = "Air traffic control splits airspace into sectors, each run by one controller. High-High clusters show where traffic is dense enough to need smaller sectors or more controllers. Eurocontrol and South Africa's ATNS plan sectors this way.",
        "Corridors or hubs" = "A significant Moran's I means busy hexes touch other busy hexes, so traffic runs in continuous corridors. Global G adds whether the clustering is of busy hexes or quiet ones.",
        "Lone hubs (High-Low)" = "A busy hex surrounded by quiet ones is usually a single hub in sparse airspace, such as Johannesburg or Nairobi, or aircraft in a holding pattern.",
        "Gaps in coverage (Low-Low)" = "Oceans and remote land show up as Low-Low. These gaps make search and rescue harder, and they are why satellite ADS-B tracking was brought in after MH370."
      ),
      caveat = "OpenSky's ground receivers are run by volunteers and are thin in Africa, so some Low-Low clusters are missing coverage rather than empty sky."
    )
  )
}

autocorr_server <- function(id, aircraft, region_id, active) {
  moduleServer(id, function(input, output, session) {
    # Only inputs and the already-filtered aircraft: debounce reads this
    # even while the tab is closed, so nothing heavy goes in here.
    params <- reactive(list(
      aircraft = aircraft(),
      hex_km = input$hex_km,
      log = input$log,
      weights = input$weights,
      k = input$k,
      d = input$d,
      statistic = input$statistic,
      style = input$style,
      inference = input$inference,
      nsim = input$nsim,
      alpha = input$alpha
    ))

    result <- method_runner(
      input,
      session,
      "autocorr",
      active,
      region_id,
      params,
      compute = function(p, region) {
        if (nrow(p$aircraft) == 0) {
          return(no_aircraft_result())
        }
        globalg <- p$statistic == "globalg"
        run_safely({
          pts <- to_region_sf(p$aircraft, region)
          hexes <- hex_counts(pts, region_window(region), p$hex_km, log = isTRUE(p$log))
          res <- run_autocorr(
            hexes,
            weights = p$weights,
            k = p$k,
            d_km = p$d,
            style = if (globalg) "B" else p$style,
            statistic = p$statistic,
            inference = if (globalg) "analytic" else p$inference,
            nsim = p$nsim,
            alpha = as.numeric(p$alpha)
          )
          res$hex_km <- p$hex_km
          res$value_label <- if (isTRUE(p$log)) "log(count + 1)" else "Aircraft count"
          # The card describes the run it shows, not inputs changed since.
          res$statistic <- p$statistic
          res$alpha <- as.numeric(p$alpha)
          res
        })
      }
    )

    # Every output and the map layer start with req(active()), so a closed
    # tab never runs the method.
    ok_result <- reactive({
      req(active())
      res <- result()
      req(isTRUE(res$ok))
      res$value
    })

    output$short <- renderUI({
      req(active())
      res <- result()
      if (!isTRUE(res$ok)) {
        return(region_alert(res, "autocorr"))
      }
      value <- res$value
      summary_ui(
        autocorr_summary(value, value$statistic, value$alpha),
        legend_ui(lisa_colours, names(lisa_colours))
      )
    })

    output$interpretation <- renderUI(p(class = "mb-0", ok_result()$interpretation))

    output$global <- renderTable(
      {
        g <- ok_result()$global
        data.frame(
          Quantity = c(g$statistic, "Expectation under H0", "Variance", "z", "p-value"),
          Value = c(
            sprintf("%.4f", g$observed),
            sprintf("%.4f", g$expectation),
            formatC(g$variance, format = "g", digits = 3),
            sprintf("%.3f", g$z),
            format_p(g$p_value)
          )
        )
      },
      width = "100%"
    )

    output$setup <- renderUI({
      res <- ok_result()
      isolates <- if (res$n_isolates > 0) {
        paste0(res$n_isolates, " hexes have no neighbours.")
      } else {
        "Every hex has at least one neighbour."
      }
      p(
        class = "results-note",
        paste0(
          nrow(res$lisa), " hexes of ", res$hex_km, " km, value = ", res$value_label, ". ",
          "Weights: ", res$weights_label, ". ", isolates
        )
      )
    })

    output$scatter <- renderPlot({
      res <- ok_result()
      s <- res$scatter
      pal <- use_plot_theme()
      par(mar = c(4.5, 4.5, 1, 1))
      plot(
        s$value, s$lag,
        pch = 21, bg = lisa_colours[as.character(res$lisa$cluster)], col = "#555555",
        xlab = res$value_label, ylab = "Spatially lagged value"
      )
      abline(stats::lm(lag ~ value, data = s), col = pal$line, lwd = 2)
      abline(v = mean(s$value), h = mean(s$lag), lty = 2, col = "#888888")
    }, bg = "transparent")

    # The LISA layer on the shared map. Coming back to the tab with the same
    # result keeps the drawn layer (method_runner shows its pane again).
    drawn <- NULL
    observe({
      req(active())
      res <- result()
      if (identical(res, drawn)) {
        return()
      }
      drawn <<- res
      # A failed run keeps the old layer so method_runner can fade its pane
      # out; the next good run replaces it.
      if (!isTRUE(res$ok)) {
        return()
      }
      proxy <- leaflet::clearGroup(shared_map_proxy(session), "autocorr")
      lisa <- sf::st_transform(res$value$lisa, 4326)
      pal <- leaflet::colorFactor(unname(lisa_colours), levels = names(lisa_colours))
      popup <- paste0(
        "<b>Hex ", lisa$hex_id, "</b>",
        "<br>Aircraft: ", lisa$count,
        "<br>Local I: ", sprintf("%.3f", lisa$Ii),
        "<br>p-value: ", format_p(lisa$p_value),
        "<br>Cluster: ", lisa$cluster
      )
      leaflet::addPolygons(
        proxy,
        data = lisa,
        fillColor = ~ pal(cluster),
        fillOpacity = 0.7,
        color = "#ffffff",
        weight = 0.5,
        popup = popup,
        group = "autocorr",
        options = leaflet::pathOptions(pane = "autocorr")
      )
    })

    output$top <- renderTable(
      {
        lisa <- ok_result()$lisa
        sig <- lisa[lisa$cluster != "Not significant", ]
        sig <- utils::head(sig[order(-sig$Ii), ], 10)
        validate(need(nrow(sig) > 0, "No hex is significant at this alpha."))
        centre <- sf::st_coordinates(sf::st_centroid(sf::st_transform(sf::st_geometry(sig), 4326)))
        data.frame(
          Hex = sig$hex_id,
          `Centre (lat, lon)` = sprintf("%.1f, %.1f", centre[, "Y"], centre[, "X"]),
          Aircraft = sig$count,
          `Local I` = sprintf("%.3f", sig$Ii),
          `p-value` = format_p(sig$p_value),
          Cluster = as.character(sig$cluster),
          check.names = FALSE
        )
      },
      width = "100%"
    )
  })
}
