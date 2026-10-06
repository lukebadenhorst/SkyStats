# Live Map tab: KPI cards, the aircraft map and a table of the filtered set.
#
# mod_live_server() takes two reactives from app.R:
#   aircraft  prepped + filtered state vectors
#   region_id the selected region, used to zoom the map

altitude_colours <- c(
  "On ground" = "#9aa0a6",
  "< 3,000 m" = "#f4a261",
  "3,000-9,000 m" = "#2a9d8f",
  "> 9,000 m" = "#1d3557",
  "Unknown" = "#d0d0d0"
)
altitude_palette <- leaflet::colorFactor(
  unname(altitude_colours),
  levels = names(altitude_colours)
)

mod_live_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(
      fill = FALSE,
      col_widths = c(3, 3, 6),
      value_box(
        title = "Aircraft in view",
        value = textOutput(ns("n_aircraft")),
        showcase = bs_icon("airplane"),
        theme = "primary"
      ),
      value_box(
        title = "Airborne",
        value = textOutput(ns("pct_airborne")),
        showcase = bs_icon("cloud-arrow-up"),
        theme = "teal"
      ),
      value_box(
        title = "Top origin countries",
        value = textOutput(ns("top_country")),
        uiOutput(ns("top_countries")),
        showcase = bs_icon("globe2"),
        theme = "light"
      )
    ),
    navset_card_tab(
      full_screen = TRUE,
      nav_panel("Map", leafletOutput(ns("map"), height = "100%")),
      nav_panel("Table", DT::DTOutput(ns("table")))
    )
  )
}

mod_live_server <- function(id, aircraft, region_id) {
  moduleServer(id, function(input, output, session) {
    output$n_aircraft <- renderText(comma(nrow(aircraft())))

    output$pct_airborne <- renderText({
      df <- aircraft()
      if (nrow(df) == 0) "-" else sprintf("%.0f%%", 100 * mean(df$airborne))
    })

    countries <- reactive(top_countries(aircraft(), 5))

    output$top_country <- renderText({
      tc <- countries()
      if (length(tc) == 0) "-" else names(tc)[1]
    })

    output$top_countries <- renderUI({
      tc <- countries()
      if (length(tc) == 0) {
        return(NULL)
      }
      p(
        class = "small mb-0",
        paste0(names(tc), " (", comma(as.integer(tc)), ")", collapse = " · ")
      )
    })

    output$map <- renderLeaflet({
      leaflet(options = leafletOptions(
        preferCanvas = TRUE,
        worldCopyJump = TRUE,
        zoomSnap = 0.25,
        zoomDelta = 0.5
      )) |>
        addProviderTiles(providers$Esri.WorldGrayCanvas) |>
        setView(lng = 10, lat = 25, zoom = 2) |>
        addLegend(
          position = "bottomright",
          colors = unname(altitude_colours),
          labels = names(altitude_colours),
          title = "Altitude",
          opacity = 1
        )
    })

    observe({
      df <- aircraft()
      proxy <- leafletProxy("map", data = df) |> clearGroup("aircraft")
      if (nrow(df) == 0) {
        return()
      }
      proxy |>
        addCircleMarkers(
          lng = ~longitude,
          lat = ~latitude,
          radius = 3,
          stroke = FALSE,
          fillOpacity = 0.8,
          fillColor = ~ altitude_palette(as.character(altitude_band)),
          popup = aircraft_popup(df),
          group = "aircraft"
        )
    })

    observe({
      r <- get_region(region_id())
      proxy <- leafletProxy("map")
      if (r$id == "world") {
        setView(proxy, lng = 10, lat = 25, zoom = 2)
      } else {
        fitBounds(proxy, r$lon_min, r$lat_min, r$lon_max, r$lat_max)
      }
    })

    output$table <- DT::renderDT({
      df <- aircraft()
      DT::datatable(
        data.frame(
          Callsign = df$callsign,
          Airline = df$airline_name,
          Code = df$airline_code,
          Category = df$flight_category,
          `Origin country` = df$origin_country,
          `Altitude (m)` = round(df$altitude),
          `Speed (km/h)` = round(df$velocity * 3.6),
          `Heading (deg)` = round(df$true_track),
          Band = df$altitude_band,
          check.names = FALSE
        ),
        rownames = FALSE,
        filter = "top",
        options = list(pageLength = 15, scrollX = TRUE)
      )
    })
  })
}

comma <- function(x) {
  formatC(x, format = "d", big.mark = ",")
}

# "Name (CODE)", just "CODE" when the name is unknown, "n/a" with no code.
airline_label <- function(name, code) {
  esc <- htmltools::htmlEscape
  ifelse(
    is.na(code),
    "n/a",
    ifelse(is.na(name), esc(code), paste0(esc(name), " (", esc(code), ")"))
  )
}

aircraft_popup <- function(df) {
  fmt <- function(x, unit, digits = 0) {
    ifelse(is.na(x), "n/a", paste(comma(round(x, digits)), unit))
  }
  esc <- function(x) htmltools::htmlEscape(ifelse(is.na(x), "n/a", x))
  paste0(
    "<b>", esc(df$callsign), "</b>",
    "<br>Airline: ", airline_label(df$airline_name, df$airline_code),
    "<br>Category: ", esc(as.character(df$flight_category)),
    "<br>Origin country: ", esc(df$origin_country),
    "<br>Altitude: ", ifelse(df$on_ground %in% TRUE, "on ground", fmt(df$altitude, "m")),
    "<br>Speed: ", fmt(df$velocity * 3.6, "km/h"),
    "<br>Heading: ", ifelse(is.na(df$true_track), "n/a", paste0(round(df$true_track), "&deg;"))
  )
}
