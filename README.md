# Global Flights: Spatial Statistics Dashboard

An R Shiny dashboard of global air traffic for STAT3037A Introduction to Spatial Statistics (Wits). It shows live aircraft positions from the [OpenSky Network](https://opensky-network.org) and runs three spatial statistics methods from the course on them.

**Status:** the Live Map and the three method tabs (Autocorrelation, Point Patterns, Spatial Regression) work in both live and sample mode. A Home page is still to come. See `docs/design.md` for the design and `docs/plan.md` for the implementation plan.

## Run it

1. Install R (4.4 or later) and the packages:

   ```r
   install.packages(c(
     "shiny", "bslib", "bsicons", "leaflet", "cachem", "DT",
     "httr2", "dplyr", "jsonlite", "testthat",
     "sf", "spdep", "spatialreg", "spatstat", "spData"
   ))
   ```

   `spatstat` installs its sub-packages; the app uses `spatstat.geom` and `spatstat.explore`, and the tests also use `spatstat.data` and `spatstat.random`.

2. From the project folder, run:

   ```r
   shiny::runApp()
   ```

   In Positron or RStudio you can also open `app.R` and press **Run App**.

No API credentials are needed. Without them the app uses the bundled sample snapshot in `data/sample/`, and the header badge says so.

## Using the method tabs

Pick a region and set the filters in the sidebar first: they apply to every tab. On each method tab, choose the parameters on the left and click **Run analysis**. Nothing is computed until you do. The results show a plain-English interpretation at your chosen α, the test tables, and a map. If the filters leave too little data, a yellow message says what to change.

- **Autocorrelation (Ch 4):** counts aircraft in hexagons over the region and tests whether neighbouring hexes have similar counts (Moran's I, Geary's C or Global G), then maps the LISA clusters. Choose the hex size, the spatial weights and analytic or permutation inference. Needs a region other than World.
- **Point Patterns (Ch 7):** tests airborne aircraft or airports for complete spatial randomness with the chi-squared quadrat test and the variance-to-mean ratio. Choose the number of quadrats across and down. Needs a region other than World.
- **Spatial Regression (Ch 6):** models aircraft over each country from population, GDP per capita, area and airport count, through OLS, residual Moran's I, the LM tests and a spatial lag model. Choose the covariates and the weights. Europe and World only, since the other regions have fewer than 15 countries.

## Live data (optional)

1. Create a free account at <https://opensky-network.org>, then create an API client on your account page to get a client ID and secret.
2. Add them to your user `.Renviron` (run `usethis::edit_r_environ()` or edit the file by hand):

   ```
   OPENSKY_CLIENT_ID=your-client-id
   OPENSKY_CLIENT_SECRET=your-client-secret
   ```

3. Restart R. The badge now reads **Live, updated hh:mm UTC**.

Never commit `.Renviron` or paste credentials into the code.

The app calls `/states/all` at most once every 10 minutes, shared across all sessions (4 API credits per call, out of 4,000 per day). **Refresh data** forces a new call, but not more than once a minute. If the API fails, the app keeps showing the last good live data, or falls back to the sample.

To recapture the sample snapshot (costs 4 credits):

```sh
Rscript data-raw/capture_sample.R
```

Airline names come from the [OpenFlights](https://openflights.org/data) airline list, plus a few newer airlines added by hand. Airports are the large and medium airports from [OurAirports](https://ourairports.com/data/). To rebuild both lookups (needs internet, no credits):

```sh
Rscript data-raw/build_lookups.R
```

## Tests

```r
testthat::test_dir("tests/testthat")
```

The tests use a small JSON fixture, the bundled sample and the course-notes examples (`spatstat.data::bei` and `spData::worldbank_df`). They make no network calls.

## Layout

Files in `R/` that start with `stats_` (and the other non-`mod_` files) are pure R with no Shiny, so they can be tested on their own. Each tab is one Shiny module, `R/mod_*.R`.

| Path | What it holds |
|---|---|
| `app.R` | Page layout, global sidebar, wiring of the modules |
| `R/data_api.R` | OpenSky fetch, parsing, shared 10-minute cache, sample fallback |
| `R/data_prep.R` | Cleaning, airline codes and names, categories, altitude bands, filters |
| `R/lookups.R` | Loads the airline and airport lookups in `data/lookups/`; the hand-listed codes for categories |
| `R/regions.R` | Analysis regions with bboxes and equal-area CRSs |
| `R/stats_common.R` | Shared helpers: user-facing errors, p-value and decision wording |
| `R/stats_weights.R` | Spatial weights (queen, k nearest neighbours, distance band, inverse distance) |
| `R/stats_autocorr.R` | Hex counts, global tests and LISA (Ch 4) |
| `R/stats_quadrat.R` | Quadrat window, quadrat test and VTMR (Ch 7) |
| `R/stats_regression.R` | Country units, model formula and the regression workflow (Ch 6) |
| `R/mod_common.R` | Shared layout for the method tabs |
| `R/mod_live.R` | Live Map tab |
| `R/mod_autocorr.R` | Autocorrelation tab |
| `R/mod_quadrat.R` | Point Patterns tab |
| `R/mod_regression.R` | Spatial Regression tab |
| `R/mod_about.R` | About tab |
| `data-raw/capture_sample.R` | Captures the bundled sample snapshot |
| `data-raw/build_lookups.R` | Builds the airline and airport lookups |
| `data/sample/` | The sample snapshot |
| `data/lookups/` | Airline names by ICAO code; OurAirports large and medium airports |
| `tests/testthat/` | Unit tests and fixtures |

Data courtesy of The OpenSky Network.
