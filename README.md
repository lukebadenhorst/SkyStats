# Global Flights: Spatial Statistics Dashboard

An R Shiny dashboard of global air traffic for STAT3037A Introduction to Spatial Statistics (Wits). It shows live aircraft positions from the [OpenSky Network](https://opensky-network.org) and will let the user run three spatial statistics methods from the course on them.

**Status: demo.** The Live Map works end to end. The method tabs (Autocorrelation, Point Patterns, Spatial Regression) and Airports & Routes show their planned controls and outputs but cannot run yet. See `docs/design.md` for the full design.

## Run it

1. Install R (4.4 or later) and the packages:

   ```r
   install.packages(c(
     "shiny", "bslib", "bsicons", "leaflet", "cachem", "DT",
     "httr2", "dplyr", "jsonlite", "testthat",
     "sf", "spdep", "spatialreg", "spatstat", "spData"
   ))
   ```

2. From the project folder, run:

   ```r
   shiny::runApp()
   ```

   In Positron or RStudio you can also open `app.R` and press **Run App**.

No API credentials are needed. Without them the app uses the bundled sample snapshot in `data/sample/`, and the header badge says so.

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

Airline names come from the [OpenFlights](https://openflights.org/data) airline list, plus a few newer airlines added by hand. To rebuild the lookup (no credits needed):

```sh
Rscript data-raw/build_lookups.R
```

## Tests

```r
testthat::test_dir("tests/testthat")
```

The tests use a small JSON fixture and the bundled sample. They make no network calls.

## Layout

| Path | What it holds |
|---|---|
| `app.R` | Page layout, global sidebar, wiring of the modules |
| `R/data_api.R` | OpenSky fetch, parsing, shared 10-minute cache, sample fallback |
| `R/data_prep.R` | Cleaning, airline codes and names, categories, altitude bands, filters |
| `R/lookups.R` | Loads the lookup tables in `data/lookups/`; the hand-listed codes for categories |
| `R/regions.R` | Analysis regions with bboxes and equal-area CRSs |
| `R/mod_live.R` | Live Map tab |
| `R/mod_placeholders.R` | Skeleton method tabs and About |
| `data-raw/capture_sample.R` | Captures the bundled sample snapshot |
| `data-raw/build_lookups.R` | Builds the airline name lookup |
| `data/sample/` | The sample snapshot |
| `data/lookups/` | Airline names by ICAO code |
| `tests/testthat/` | Unit tests and fixtures |

Data courtesy of The OpenSky Network.
