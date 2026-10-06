# STAT3037A Flights Dashboard

An R Shiny dashboard of global flights for the STAT3037A (Wits, Introduction to Spatial Statistics) group assignment. It is due **26 Oct 2026** and must be delivered as a GitHub repo.

## Key documents

- `context/instructions.md`: the assignment brief (from a lecture slide).
- `context/course_notes.md`: the lecture notes. The three methods must come from these. Not committed (lecturer's material).
- `docs/superpowers/specs/2026-10-06-flights-dashboard-design.md`: **the main design spec.** Read this first.
- `docs/superpowers/specs/2026-10-06-demo-dashboard.md`: the design for today's demo deliverable.
- `plan/flight-dashboard-plan.md`: earlier draft plan, with useful OpenSky API facts. The spec overrides it where they differ.
- `plan/data_test.r`: working OAuth2 test pull of yesterday's flights.

## Decisions (see the spec for details)

- **Data:** the OpenSky REST API, called by the app with a shared 10-min cache, plus a bundled sample snapshot as fallback. No scheduled collector.
- **Three methods:** Ch 4 spatial autocorrelation (Moran's I / Geary's C / Global G + LISA on a hex grid), Ch 7 quadrat/CSR test with VTMR, Ch 6 spatial lag regression (OLS → residual Moran's I → LM tests → `lagsarlm`).
- Not methods (not in the course notes): gravity model, Ripley's K, Gi\*, kriging.
- **Scope:** global data; the user picks a region per analysis, each with its own equal-area CRS.
- **Code:** `stats_*.R` functions are pure (no Shiny) and tested against the course-notes examples. There is one Shiny module per tab.
- **Team split:** not decided yet, so keep the modules independent.

## Environment

- Windows 11. R 4.6.1 is at `C:\Program Files\R\R-4.6.1`. `Rscript` is **not** on the Bash PATH, so call `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe"` (Bash) or `& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe"` (PowerShell).
- The user works in **Positron** (built-in R, Shiny Run App button, Air formatter on save for R).
- OpenSky credentials `OPENSKY_CLIENT_ID` / `OPENSKY_CLIENT_SECRET` are set in `~/.Renviron`. Never print them, copy them into the repo, or commit them.
- Installed R packages that matter here: `httr2`, `dplyr`, `purrr`, `jsonlite`, `languageserver`, `httpgd`. Not yet installed: `shiny`, `bslib`, `bsicons`, `leaflet`, `cachem`, `DT`, `testthat`, `sf`, `spdep`, `spatialreg`, `spatstat.*`, `spData`.

## Status (as of 2026-10-06)

- Git repo initialised on `main`; the spec is committed. No remote yet.
- **Next step:** build the demo dashboard (`docs/superpowers/specs/2026-10-06-demo-dashboard.md`). The design was presented, but the user hasn't explicitly approved it, so confirm before building. The user wants it finished today.
- After the demo: write the full implementation plan for the main spec (superpowers `writing-plans`).
