# Point Patterns tab (Ch 7): the quadrat test for complete spatial
# randomness, on airborne aircraft or airports, drawn on the shared map.
# The statistics are in R/stats_quadrat.R.
#
# Three parts, all with module id "quadrat" (the method name):
#   quadrat_settings_ui()  the settings panel, which is also the setup box
#   quadrat_results_ui()   the results card
#   quadrat_server()       runs the method and draws the map layer
# quadrat_server() takes from app.R:
#   aircraft  reactive: prepped + filtered state vectors
#   region_id reactive: the selected region
#   airports  data.frame with longitude, latitude and type (not reactive)
#   active    reactive: TRUE while the tab is open
#
# The test runs over quadrat_window(), a rectangle inside the region, so
# every quadrat has the same area (see R/stats_quadrat.R).

quadrat_settings_ui <- function(id) {
  ns <- NS(id)
  settings_panel(
    ns,
    "quadrat",
    "Point Patterns",
    "Ch 7",
    question = "Are the points spread at random?",
    intro = "We lay a grid of equal squares (quadrats) over the region, count the points in each, and compare the counts with what pure chance would give.",
    fields = tagList(
      setting(
        segmented_input(
          ns("points"),
          "Point set",
          c("Airborne aircraft" = "aircraft", "Airports" = "airports")
        ),
        "Which points to test: the aircraft currently in the air, or the airports on the ground."
      ),
      conditionalPanel(
        "input.points == 'airports'",
        ns = ns,
        setting(
          checkboxGroupInput(
            ns("airport_types"),
            "Airport types",
            c("Large" = "large_airport", "Medium" = "medium_airport"),
            selected = c("large_airport", "medium_airport")
          ),
          "Airline, category and altitude filters don't apply to airports."
        )
      ),
      setting(
        sliderInput(ns("nx"), "Quadrats across (nx)", min = 2, max = 15, value = 6),
        "How many squares the grid has from west to east. More squares show finer detail, but each holds fewer points."
      ),
      setting(
        sliderInput(ns("ny"), "Quadrats down (ny)", min = 2, max = 15, value = 6),
        "How many squares the grid has from north to south. The test needs about 5 points per square on average, so a fine grid needs plenty of points."
      ),
      setting(
        alpha_input(ns),
        "How strong the evidence must be before we call a pattern real. 0.05 means we accept a 5% chance of seeing a pattern that is really just chance."
      )
    )
  )
}

# The full results: the interpretation, both tests, the setup note and the
# histogram.
quadrat_results_ui <- function(id) {
  ns <- NS(id)
  results_card(
    ns,
    full = div(
      class = "results-grid",
      div(class = "results-section span-all", h5("Interpretation"), uiOutput(ns("interpretation"))),
      div(class = "results-section", h5("Chi-squared quadrat test"), tableOutput(ns("chisq"))),
      div(class = "results-section", h5("Variance-to-mean ratio (VTMR)"), tableOutput(ns("vtmr"))),
      div(class = "results-section span-all", uiOutput(ns("setup"))),
      div(
        class = "results-section span-all",
        h5("Quadrat counts against the Poisson expectation"),
        plotOutput(ns("hist"), height = "260px")
      )
    )
  )
}

quadrat_server <- function(id, aircraft, region_id, airports, active) {
  moduleServer(id, function(input, output, session) {
    # Only inputs and already-computed data: debounce reads this even while
    # the tab is closed, so nothing heavy goes in here.
    params <- reactive(list(
      aircraft = aircraft(),
      airports = airports,
      points = input$points,
      airport_types = input$airport_types,
      nx = input$nx,
      ny = input$ny,
      alpha = input$alpha
    ))

    result <- method_runner(
      input,
      session,
      "quadrat",
      active,
      region_id,
      params,
      compute = function(p, region) {
        run_safely({
          crs <- region_crs(region)
          df <- if (p$points == "airports") {
            p$airports[p$airports$type %in% p$airport_types, , drop = FALSE]
          } else {
            a <- p$aircraft
            a[a$airborne, , drop = FALSE]
          }
          pts <- to_region_sf(df, region)
          window <- region_window(region)
          rect <- quadrat_window(window)
          X <- as_ppp(pts, rect)
          res <- run_quadrat(X, nx = p$nx, ny = p$ny, alpha = as.numeric(p$alpha), crs = crs)
          res$rect <- rect
          res$points <- sf::st_as_sf(data.frame(x = X$x, y = X$y), coords = c("x", "y"), crs = crs)
          res$n_region <- nrow(pts)
          res$area_share <- as.numeric(sf::st_area(rect) / sf::st_area(window))
          res$point_label <- if (p$points == "airports") "airports" else "airborne aircraft"
          res$nx <- p$nx
          res$ny <- p$ny
          # The card describes the run it shows, not inputs changed since.
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
        return(region_alert(res, "quadrat"))
      }
      value <- res$value
      counts <- value$tiles$count
      # Five steps of the layer's viridis scale, from the fewest to the most.
      steps <- unique(round(seq(min(counts), max(counts), length.out = 5)))
      pal <- leaflet::colorNumeric("viridis", domain = counts)
      summary_ui(
        quadrat_summary(value, value$alpha),
        legend_ui(pal(steps), steps, title = "Points per quadrat")
      )
    })

    output$interpretation <- renderUI(p(class = "mb-0", ok_result()$interpretation))

    output$chisq <- renderTable(
      {
        q <- ok_result()$chisq
        data.frame(
          Quantity = c("χ²", "df", "p-value (two-sided)"),
          Value = c(sprintf("%.2f", q$statistic), q$df, format_p(q$p_value))
        )
      },
      width = "100%"
    )

    output$vtmr <- renderTable(
      {
        v <- ok_result()$vtmr
        data.frame(
          Quantity = c(
            "Quadrats (m)", "Mean count", "Variance", "VTMR",
            "(m − 1) × VTMR", "df", "p-value (two-sided)"
          ),
          Value = c(
            v$m, sprintf("%.2f", v$mean), sprintf("%.2f", v$variance), sprintf("%.3f", v$vtmr),
            sprintf("%.2f", v$statistic), v$df, format_p(v$p_value)
          )
        )
      },
      width = "100%"
    )

    output$setup <- renderUI({
      res <- ok_result()
      bb <- sf::st_bbox(res$rect)
      side_km <- c(bb[["xmax"]] - bb[["xmin"]], bb[["ymax"]] - bb[["ymin"]]) / 1000 / c(res$nx, res$ny)
      p(
        class = "results-note",
        paste0(
          res$nx, " × ", res$ny, " quadrats of about ", round(side_km[1]), " × ", round(side_km[2]),
          " km, over a rectangle (outlined) covering ", round(100 * res$area_share), "% of the region. ",
          nrow(res$points), " of the ", res$n_region, " ", res$point_label,
          " in the region fall inside it; the rest are left out so every quadrat has the same area."
        )
      )
    })

    # The quadrat layer on the shared map. Coming back to the tab with the
    # same result keeps the drawn layer (method_runner shows its pane again).
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
      value <- res$value
      # Add vertices along the straight projected edges so they curve
      # correctly in the web map.
      to_map <- function(g) sf::st_transform(sf::st_segmentize(g, dfMaxLength = 25000), 4326)
      tiles <- to_map(value$tiles)
      rect <- to_map(value$rect)
      centres <- sf::st_transform(sf::st_point_on_surface(sf::st_geometry(value$tiles)), 4326)
      points <- sf::st_transform(value$points, 4326)
      pal <- leaflet::colorNumeric("viridis", domain = tiles$count)
      popup <- paste0(
        "Count: ", tiles$count,
        "<br>Expected under CSR: ", sprintf("%.1f", tiles$expected)
      )

      proxy <- leaflet::clearGroup(shared_map_proxy(session), "quadrat")
      proxy |>
        leaflet::addPolygons(
          data = tiles,
          fillColor = ~ pal(count),
          fillOpacity = 0.6,
          color = "#ffffff",
          weight = 1,
          popup = popup,
          group = "quadrat",
          options = leaflet::pathOptions(pane = "quadrat")
        ) |>
        # The class lets the dark-mode CSS in app.R lighten the outline.
        leaflet::addPolylines(
          data = sf::st_cast(rect, "LINESTRING"),
          color = "#1d3557",
          weight = 2,
          group = "quadrat",
          options = leaflet::pathOptions(pane = "quadrat", className = "study-window")
        ) |>
        leaflet::addCircleMarkers(
          data = points,
          radius = 1.5,
          stroke = FALSE,
          fillColor = "#e63946",
          fillOpacity = 0.6,
          group = "quadrat",
          options = leaflet::pathOptions(pane = "quadrat")
        ) |>
        leaflet::addLabelOnlyMarkers(
          data = centres,
          label = as.character(tiles$count),
          group = "quadrat",
          options = leaflet::markerOptions(pane = "quadrat"),
          # The labels are tooltips, which Leaflet puts in its tooltip pane
          # unless told otherwise; in the quadrat pane they fade with the layer.
          labelOptions = leaflet::labelOptions(
            pane = "quadrat",
            noHide = TRUE,
            direction = "center",
            textOnly = TRUE,
            style = list("font-weight" = "bold", "color" = "#ffffff", "text-shadow" = "0 0 3px #000000")
          )
        )
    })

    output$hist <- renderPlot({
      res <- ok_result()
      counts <- res$tiles$count
      b <- poisson_bins(counts, res$vtmr$mean)
      mids <- utils::head(b$breaks, -1) + diff(b$breaks) / 2
      h <- graphics::hist(counts, breaks = b$breaks, plot = FALSE)
      pal <- use_plot_theme()
      par(mar = c(4.5, 4.5, 1, 1))
      plot(
        h,
        col = pal$bar, border = pal$border, main = NULL,
        xlab = "Points per quadrat", ylab = "Number of quadrats",
        ylim = c(0, max(h$counts, b$expected) * 1.05)
      )
      lines(mids, b$expected, col = pal$line, lwd = 2)
      points(mids, b$expected, pch = 19, col = pal$line)
      legend(
        "topright",
        legend = c("Observed", paste0("Poisson (mean ", sprintf("%.1f", res$vtmr$mean), ")")),
        fill = c(pal$bar, NA), border = c(pal$border, NA),
        col = c(NA, pal$line), lwd = c(NA, 2), pch = c(NA, 19), bty = "n"
      )
    }, bg = "transparent")
  })
}

# Histogram bins for quadrat counts, and how many quadrats a Poisson
# process with this mean would put in each bin (m quadrats in total).
# Bins are whole numbers wide and centred on whole numbers, so each bin's
# expectation is exact: m × P(count falls in the bin). At most 30 bins.
poisson_bins <- function(counts, mean) {
  top <- max(counts)
  width <- max(1, ceiling((top + 1) / 30))
  breaks <- seq(-0.5, by = width, length.out = ceiling((top + 1) / width) + 1)
  expected <- length(counts) * diff(stats::ppois(floor(breaks), mean))
  list(breaks = breaks, expected = expected)
}
