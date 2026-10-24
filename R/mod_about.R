# About tab: data sources, the three methods and their R functions, and the
# limitations. Static text, so there is no server function.

about_ui <- function(id) {
  # A large centred panel over the blurred map (www/app.css), scrolling on its own.
  float_panel(
    class = "center-panel about-panel",
    layout_columns(
      col_widths = c(6, 6, 12),
      card(
        card_header("Data sources"),
        tags$ul(
          tags$li(
            inline_strong("OpenSky Network REST API"),
            " (", inline_code("/states/all"), "): live aircraft positions from volunteer ADS-B receivers. ",
            "Fetched at most every 10 minutes and shared by everyone using the app."
          ),
          tags$li(
            inline_strong("Bundled sample snapshot"),
            " (", inline_code("data/sample/states_sample.rds"), "): used when there are no API ",
            "credentials or the API is unavailable, so the app always runs. The badge in the top ",
            "right says which one you are seeing."
          ),
          tags$li(
            inline_strong("OpenFlights airlines"),
            " (", inline_code("data/lookups/airlines.rds"), "): airline names, matched on the first three ",
            "letters of the callsign, plus a few newer airlines added by hand."
          ),
          tags$li(
            inline_strong("OurAirports"),
            " (", inline_code("data/lookups/airports.rds"), "): large and medium airports, used as points ",
            "on the Point Patterns tab and counted per country for the regression."
          ),
          tags$li(
            inline_strong(inline_code("spData::world")),
            ": country outlines, population, GDP per capita and area for the regression ",
            "(the same data as the Ch 6 example in the course notes)."
          )
        ),
        p(
          class = "small text-muted mb-0",
          "Data courtesy of The OpenSky Network, https://opensky-network.org."
        )
      ),
      card(
        card_header("Limitations"),
        tags$ul(
          class = "mb-0",
          tags$li(
            "Each analysis uses a single snapshot, one moment rather than a day of traffic. ",
            "The API only serves the last hour of positions."
          ),
          tags$li(
            "Coverage depends on volunteer receivers, so it is dense over North America and Europe ",
            "and sparse over oceans, Africa and parts of Asia. Empty sky can mean no receivers ",
            "rather than no aircraft."
          ),
          tags$li(
            "Airline codes come from the first three characters of the callsign. Private and military ",
            "flights have no code, and OpenFlights has no name for some newer airlines."
          ),
          tags$li(
            "Categories are inferred from the callsign, airline and transponder address. Military flights ",
            "with tactical callsigns are only caught inside the US military address block, and airlines ",
            "that fly both passengers and freight count as passenger airlines."
          ),
          tags$li("Origin country is the country of aircraft registration, not where the flight departed."),
          tags$li(
            "World has no single equal-area projection, so Autocorrelation and Point Patterns need ",
            "one of the four regions."
          ),
          tags$li(
            "The quadrat test runs over the largest rectangle that fits inside the region, so every quadrat ",
            "has the same area (the VTMR assumes this). Points outside the rectangle are left out."
          ),
          tags$li(
            "Regression needs at least 15 countries, so it only runs for Europe and the World. ",
            inline_code("spData::world"), " has no population or GDP for a few countries (France and Norway ",
            "among them), and those are left out of the model."
          )
        )
      ),
      card(
        card_header("Methods (from the STAT3037A course notes)"),
        layout_column_wrap(
          width = "300px",
          div(
            h6(bs_icon("grid-3x3"), " Autocorrelation (Ch 4)"),
            p(
              class = "small mb-0",
              "Counts aircraft in a hexagonal grid over the region (", inline_code("sf::st_make_grid"),
              "), builds spatial weights (queen contiguity, k nearest neighbours, a distance band or ",
              "inverse distance, with ", inline_code("spdep::nb2listw"), "), and tests for clustering with ",
              "global Moran's I, Geary's C or Global G (", inline_code("spdep::moran.test"), ", ",
              inline_code("geary.test"), ", ", inline_code("globalG.test"), ", or the permutation versions ",
              inline_code("moran.mc"), " and ", inline_code("geary.mc"), "). Local Moran's I (",
              inline_code("spdep::localmoran"), ") maps the High-High and Low-Low clusters and the outliers."
            )
          ),
          div(
            h6(bs_icon("dot"), " Point Patterns (Ch 7)"),
            p(
              class = "small mb-0",
              "Tests airborne aircraft or airports for complete spatial randomness. The points become a ",
              inline_code("spatstat.geom::ppp"), " in the region's equal-area projection, and an nx by ny grid ",
              "of quadrats is tested with the chi-squared quadrat test (",
              inline_code("spatstat.explore::quadrat.test"), "). The variance-to-mean ratio of the counts ",
              "(VTMR: below 1 regular, about 1 random, above 1 clustered) is tested with (m − 1) × VTMR ",
              "on m − 1 degrees of freedom."
            )
          ),
          div(
            h6(bs_icon("graph-up"), " Spatial Regression (Ch 6)"),
            p(
              class = "small mb-0",
              "Models the number of aircraft over each country from population, GDP per capita, area and ",
              "airport count, following the course workflow: OLS (", inline_code("lm"), "), Moran's I of the ",
              "residuals (", inline_code("spdep::moran.test"), "), the LM tests to choose a model (",
              inline_code("spdep::lm.RStests"), "), then a spatial lag model (", inline_code("spatialreg::lagsarlm"),
              ") compared with OLS by AIC."
            )
          )
        ),
        p(
          class = "small text-muted mb-0 mt-3",
          "Every analysis runs in the region's equal-area projection and only when you click ",
          inline_strong("Run analysis"), ". Each tab ends with a plain-English interpretation at your chosen α."
        )
      )
    )
  )
}

# code() and strong() without the space htmltools puts around each child, so
# "(" code ")" renders as "(x)" rather than "( x )". The text around them
# carries its own spaces.
inline_code <- function(x) code(x, .noWS = "outside")
inline_strong <- function(x) strong(x, .noWS = "outside")
