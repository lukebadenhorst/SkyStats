# Point Patterns tab (Ch 7): the quadrat test for complete spatial
# randomness, on airborne aircraft or airports. The statistics are in
# R/stats_quadrat.R.
#
# quadrat_server() takes from app.R:
#   aircraft  reactive: prepped + filtered state vectors
#   region_id reactive: the selected region
#   airports  data.frame with longitude, latitude and type (not reactive)
#
# The test runs over quadrat_window(), a rectangle inside the region, so
# every quadrat has the same area (see R/stats_quadrat.R).

quadrat_ui <- function(id) {
  ns <- NS(id)
  method_tab_ui(
    id,
    chapter = "Ch 7",
    summary = p(
      strong("Quadrat test for complete spatial randomness (CSR)."),
      " Splits a rectangle inside the region into an nx by ny grid of equal quadrats, ",
      "counts the points in each, and tests the counts against a homogeneous Poisson ",
      "process with the chi-squared test and the variance-to-mean ratio ",
      "(VTMR: < 1 regular, about 1 random, > 1 clustered)."
    ),
    controls = function(ns) {
      tagList(
        radioButtons(
          ns("points"),
          "Point set",
          c("Airborne aircraft" = "aircraft", "Airports" = "airports")
        ),
        conditionalPanel(
          "input.points == 'airports'",
          ns = ns,
          checkboxGroupInput(
            ns("airport_types"),
            "Airport types",
            c("Large" = "large_airport", "Medium" = "medium_airport"),
            selected = c("large_airport", "medium_airport")
          ),
          p(class = "small text-muted", "Airline, category and altitude filters don't apply to airports.")
        ),
        sliderInput(ns("nx"), "Quadrats across (nx)", min = 2, max = 15, value = 6),
        sliderInput(ns("ny"), "Quadrats down (ny)", min = 2, max = 15, value = 6),
        alpha_input(ns)
      )
    },
    # As in the Autocorrelation tab, the result cards are fixed and only
    # shown after a successful run, so the leaflet map sizes itself properly.
    results = div(
      uiOutput(ns("status")),
      conditionalPanel(
        "output.ok",
        ns = ns,
        card(card_header("Interpretation"), uiOutput(ns("interpretation"))),
        layout_columns(
          col_widths = c(6, 6),
          card(card_header("Chi-squared quadrat test"), tableOutput(ns("chisq"))),
          card(card_header("Variance-to-mean ratio (VTMR)"), tableOutput(ns("vtmr")))
        ),
        card(
          full_screen = TRUE,
          card_header("Quadrat counts"),
          leaflet::leafletOutput(ns("map"), height = "480px"),
          uiOutput(ns("setup"))
        ),
        card(
          card_header("Quadrat counts against the Poisson expectation"),
          plotOutput(ns("hist"), height = "320px")
        )
      )
    )
  )
}

quadrat_server <- function(id, aircraft, region_id, airports) {
  moduleServer(id, function(input, output, session) {
    result <- reactive({
      withProgress(message = "Running the quadrat test...", {
        run_safely({
          region <- region_id()
          crs <- region_crs(region)
          df <- if (input$points == "airports") {
            airports[airports$type %in% input$airport_types, , drop = FALSE]
          } else {
            a <- aircraft()
            a[a$airborne, , drop = FALSE]
          }
          pts <- to_region_sf(df, region)
          window <- region_window(region)
          rect <- quadrat_window(window)
          X <- as_ppp(pts, rect)
          res <- run_quadrat(X, nx = input$nx, ny = input$ny, alpha = as.numeric(input$alpha), crs = crs)
          res$rect <- rect
          res$points <- sf::st_as_sf(data.frame(x = X$x, y = X$y), coords = c("x", "y"), crs = crs)
          res$n_region <- nrow(pts)
          res$area_share <- as.numeric(sf::st_area(rect) / sf::st_area(window))
          res$point_label <- if (input$points == "airports") "airports" else "airborne aircraft"
          res$nx <- input$nx
          res$ny <- input$ny
          res
        })
      })
    }) |>
      bindEvent(input$run)

    ok_result <- reactive({
      res <- result()
      req(isTRUE(res$ok))
      res$value
    })

    # Drives the conditionalPanel in the UI, so it must update while hidden.
    output$ok <- reactive(isTRUE(result()$ok))
    outputOptions(output, "ok", suspendWhenHidden = FALSE)

    output$status <- renderUI({
      if (is.null(input$run) || input$run == 0) {
        return(card(p(class = "text-muted mb-0", "Choose the parameters and click Run analysis.")))
      }
      result_alert(result())
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
        class = "small text-muted mb-0 mt-2",
        paste0(
          res$nx, " × ", res$ny, " quadrats of about ", round(side_km[1]), " × ", round(side_km[2]),
          " km, over a rectangle (outlined) covering ", round(100 * res$area_share), "% of the region. ",
          nrow(res$points), " of the ", res$n_region, " ", res$point_label,
          " in the region fall inside it; the rest are left out so every quadrat has the same area."
        )
      )
    })

    output$map <- leaflet::renderLeaflet({
      res <- ok_result()
      # Add vertices along the straight projected edges so they curve
      # correctly in the web map.
      to_map <- function(g) sf::st_transform(sf::st_segmentize(g, dfMaxLength = 25000), 4326)
      tiles <- to_map(res$tiles)
      rect <- to_map(res$rect)
      centres <- sf::st_transform(sf::st_point_on_surface(sf::st_geometry(res$tiles)), 4326)
      points <- sf::st_transform(res$points, 4326)
      pal <- leaflet::colorNumeric("viridis", domain = tiles$count)
      popup <- paste0(
        "Count: ", tiles$count,
        "<br>Expected under CSR: ", sprintf("%.1f", tiles$expected)
      )

      leaflet::leaflet() |>
        leaflet::addProviderTiles(leaflet::providers$Esri.WorldGrayCanvas) |>
        leaflet::addPolygons(
          data = tiles,
          fillColor = ~ pal(count),
          fillOpacity = 0.6,
          color = "#ffffff",
          weight = 1,
          popup = popup
        ) |>
        # The class lets the dark-mode CSS in app.R lighten the outline.
        leaflet::addPolylines(
          data = sf::st_cast(rect, "LINESTRING"),
          color = "#1d3557",
          weight = 2,
          options = leaflet::pathOptions(className = "study-window")
        ) |>
        leaflet::addCircleMarkers(
          data = points,
          radius = 1.5,
          stroke = FALSE,
          fillColor = "#e63946",
          fillOpacity = 0.6
        ) |>
        leaflet::addLabelOnlyMarkers(
          data = centres,
          label = as.character(tiles$count),
          labelOptions = leaflet::labelOptions(
            noHide = TRUE,
            direction = "center",
            textOnly = TRUE,
            style = list("font-weight" = "bold", "color" = "#ffffff", "text-shadow" = "0 0 3px #000000")
          )
        ) |>
        leaflet::addLegend(position = "bottomright", pal = pal, values = tiles$count, title = "Count", opacity = 1)
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
