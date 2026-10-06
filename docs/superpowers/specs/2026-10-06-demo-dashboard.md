# Demo Dashboard (first deliverable): Design

- **Date:** 2026-10-06
- **Status:** approved and built on 2026-10-06 (branch `demo-dashboard`).
- **Goal:** a showcase app for the group, finished in one day. Live flights work end to end; the other features appear as skeleton tabs.
- **Parent spec:** `2026-10-06-flights-dashboard-design.md`. The demo is the first slice of it.

## Live Map tab (working)

- Live global aircraft from OpenSky `/states/all`, polled every 10 min through one process-level `cachem` cache shared across sessions. A **Refresh** button forces an update.
- `leaflet` with `preferCanvas = TRUE`. Each aircraft is a circle marker coloured by altitude.
- The popup shows callsign, airline code (callsign prefix), origin country, altitude, speed and heading.
- KPI cards: aircraft count, % airborne, top 5 origin countries.
- Working sidebar filters: region (zooms and crops, from `R/regions.R`), airline code, altitude band, airborne only.
- Data-source badge: `Live, updated hh:mm UTC` or `Sample snapshot`.
- Sample fallback: one snapshot captured by `data-raw/capture_sample.R` into `data/sample/states_sample.rds`. It is used when credentials are missing or the API fails.

## Skeleton tabs (UI only)

- Covers Airports & Routes, Autocorrelation (Ch 4), Point Patterns (Ch 7), Spatial Regression (Ch 6), and About.
- Each shows its real parameter controls from the parent spec, with Run disabled.
- Each has a card describing the method and its course chapter, plus an "Owner: TBD" line for splitting the work.
- About lists the data sources and limitations.

## Deviations from the parent spec (demo only)

- `leaflet` instead of `mapgl`, because it is lower risk. Revisit if 10k markers are slow.
- `.rds` instead of Parquet for the sample, so `arrow` isn't needed yet.

## Files

`app.R`, `R/data_api.R`, `R/regions.R`, `R/mod_live.R`, `R/mod_placeholders.R`, `data-raw/capture_sample.R`, `data/sample/`, `tests/testthat/` (state parsing and fallback), `README.md`.

## Packages to install

`shiny`, `bslib`, `bsicons`, `leaflet`, `cachem`, `DT`, `testthat`, into the user library. `httr2`, `dplyr`, `purrr` and `jsonlite` are already installed.
