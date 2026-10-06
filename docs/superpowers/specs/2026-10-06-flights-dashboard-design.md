# Global Flights Spatial Statistics Dashboard: Design Spec

- **Date:** 2026-10-06
- **Course:** STAT3037A Introduction to Spatial Statistics (Wits), group assignment, 25% of class mark
- **Due:** 26 October 2026
- **Inputs:** `context/instructions.md` (assignment brief), `context/course_notes.md` (lecture notes), `plan/flight-dashboard-plan.md` (earlier draft plan; this spec supersedes it where they differ)

---

## 1. Goal and success criteria

Build an R Shiny dashboard about global air traffic, delivered as a GitHub repository, that:

1. Displays spatial statistics on an underlying spatial dataset held on the back-end.
2. Lets the user choose parameters and **run three spatial statistics methods covered in the course**.
3. Is polished, clean and user-friendly.
4. Runs straight from a fresh clone (`shiny::runApp()`), with no API credentials needed.

Success means a marker can clone the repo, open the app, run each of the three methods in at least one region, and get correct results with a plain-English interpretation, whether or not the OpenSky API is reachable.

### Decisions made during brainstorming

| Decision | Choice |
|---|---|
| Data source | OpenSky REST API called by the app, plus a bundled sample dataset as fallback. No scheduled collector. |
| Three methods | Ch 4 spatial autocorrelation, Ch 7 quadrat/CSR test, Ch 6 spatial lag regression |
| Spatial scope | Global data; the user picks a region per analysis, each region with its own projected CRS |
| Live map | Included. It costs little because it reads the same cached snapshot as the analyses. |
| Delivery | GitHub repo; hosting (shinyapps.io / Posit Connect Cloud) optional |
| Team split | Not yet decided; the architecture is modular so any split works |

### Out of scope

- Time-series or multi-day position analysis. The API only serves positions from the last hour.
- Gravity models, Ripley's K, Getis-Ord Gi\*, kriging. These are not in the course notes, so they are not counted as methods. Routes appear only as descriptive views.
- User accounts, persistence of user settings, mobile-specific layouts beyond bslib defaults.

---

## 2. Data layer

### 2.1 Sources

| Data | Source | Refresh | Cost (credits) |
|---|---|---|---|
| Aircraft positions (state vectors) | OpenSky `GET /states/all` (global, `extended=1` for category) | Every 10 min, shared across sessions | 4 per call → ≤ 576/day |
| Flights with estimated dep/arr airports | OpenSky `GET /flights/all`, yesterday, 12 × 2 h windows | Once per UTC day, cached to disk | ≤ 360/day |
| Airports | OurAirports `airports.csv` (ident, type, lat, lon, iso_country) | Build once, committed | none |
| Airlines | OpenFlights `airlines.dat` (ICAO code → name, country) | Build once, committed | none |
| Aircraft type / manufacturer | OpenSky aircraft database CSV, trimmed to `icao24`, `manufacturername`, `model`, `typecode` | Build once, committed | none |
| Country polygons + covariates | `spData::world` (pop, gdpPercap, area_km2, iso_a2), the same data as the course's Ch 6 example | Package data | none |

The free standard account gives 4,000 credits/day per endpoint bucket. The budget above leaves a large margin.

### 2.2 Authentication

- OAuth2 client credentials only, using `httr2::req_oauth_client_credentials()`. The token URL is in `plan/flight-dashboard-plan.md` §3.
- Credentials are read from `OPENSKY_CLIENT_ID` / `OPENSKY_CLIENT_SECRET` in `.Renviron`. That file is git-ignored and never committed. When hosted, they are set as platform secrets.
- If the credentials are missing, the app runs in sample mode without error.

### 2.3 Bundled sample dataset (`data/sample/`)

- `states_sample.parquet`: one global `/states/all` snapshot (~10k rows).
- `flights_sample.parquet`: one full day of `/flights/all`.
- `sample_meta.json`: capture timestamps.
- This is the dataset on the back-end. It is used when there are no credentials, on API failure or 429, and by the test suite.
- Target size is under 10 MB in total. It is captured with `data-raw/capture_sample.R`.

### 2.4 Lookup tables (`data/lookups/`)

They are built by `data-raw/build_lookups.R` and committed as Parquet:

- `airports.parquet`: large and medium airports, plus small airports with an ICAO code.
- `airlines.parquet`
- `aircraft.parquet`: the trimmed aircraft database. If it is over 25 MB, keep only `icao24` and `manufacturername`/`typecode`.

### 2.5 Fetching and caching (`R/data_api.R`)

- `get_states()`
  - Returns the current snapshot as a tibble.
  - It is memoised in a process-level `cachem::cache_mem(max_age = 600)`, so all sessions share one API call per 10 minutes.
  - The response is parsed by index (schema in the earlier plan, §3).
- `get_flights_yesterday()`
  - It is memoised in `cachem::cache_disk("cache/")`, keyed by UTC date. The `cache/` folder is git-ignored.
  - A 404 on a window means no flights in that window.
- `data_source()` returns which source is in use: `live`, `cache` (stale live data kept after an error), `sample` or `frozen`. The header badge displays it.
- Freezing a snapshot:
  - The **Freeze snapshot** button writes the current states and flights to `data/frozen/<UTC timestamp>/`.
  - A source selector lets the user re-run analyses on a frozen snapshot, so that report figures can be reproduced.

### 2.6 Preparation (`R/data_prep.R`)

- Drop rows with null lat/lon. `trimws()` the callsigns.
- Joins:
  - **Airline:** the first 3 characters of the callsign, matched to the ICAO airline code.
  - **Manufacturer/type:** matched on `icao24`.
  - **Departure country:** `estDepartureAirport` → airport → `iso_country`.
- Rows that don't match a lookup are labelled `"Unknown"` and kept.
- Altitude band derived from `baro_altitude`: on ground, < 3,000 m, 3,000–9,000 m, > 9,000 m.
- Country-code joins to `spData::world` must be checked. Natural Earth sometimes has missing or `-99` `iso_a2` codes (for example France and Norway), so these are patched by name in a small lookup.

### 2.7 Regions (`R/regions.R`)

A single table holds `id`, `label`, the bbox (lon/lat), the projected CRS, and `allow_regression`:

| Region | CRS | Regression allowed |
|---|---|---|
| Europe | EPSG:3035 (LAEA Europe) | yes |
| North America | ESRI:102008 (NA Albers Equal Area) | no (too few countries) |
| Southern Africa | ESRI:102022 (Africa Albers Equal Area) | only if ≥ 15 countries have complete data |
| East Asia | ESRI:102025 (Asia North Albers Equal Area) | only if ≥ 15 countries have complete data |
| World | — | regression only (country level) |

The bboxes avoid the antimeridian.

---

## 3. App structure

### 3.1 Layout

`bslib::page_navbar` with one shared theme, a global sidebar and six tabs.

**Global sidebar:**
- Region
- Airline
- Manufacturer / type
- Origin country (country of aircraft registration)
- Altitude band
- Airborne only
- Data source (Live / Sample / Frozen)

**Header:** a data-source badge, for example `● Live, updated 14:05 UTC` or `Sample snapshot, 6 Oct 2026`.

**Tabs:**
1. **Live Map:** aircraft rotated to their heading (`mapgl`), with a popup showing callsign, airline, type, altitude and speed. KPI cards: aircraft count, % airborne, top airlines in the current filter.
2. **Airports & Routes** (descriptive, not one of the three methods): busiest departure airports and top-N routes from yesterday's flights, drawn as great-circle lines and listed in a table.
3. **Autocorrelation** (Ch 4)
4. **Point Patterns** (Ch 7)
5. **Spatial Regression** (Ch 6)
6. **About & Methods:** data sources, method summaries, and limitations (coverage bias, estimated airports, Unknown labels, single-snapshot analysis).

### 3.2 Data flow

```
get_states() / get_flights_yesterday() / frozen / sample
        │
   snapshot()        reactive: chosen source; live re-polled every 10 min (invalidateLater)
        │
   filtered()        sidebar filters applied
        │
   region_data()     cropped to region bbox, transformed to region CRS (sf)
        │
   modules: mod_live, mod_routes, mod_autocorr, mod_quadrat, mod_regression
```

Each filter applies wherever its field exists. Each method tab lists the filters that affect it. For example, airline filters do not affect the airport point set.

### 3.3 Method tab pattern

Every method tab has:
- A parameter card.
- A **Run analysis** button. Results are computed with `bindEvent()` on the button, not on every input change.
- The outputs: a map, a statistics table and plots.
- An auto-generated plain-English interpretation that states the hypothesis, the test statistic, the p-value and the conclusion at the chosen α.

### 3.4 Method 1: Spatial autocorrelation (Ch 4)

- **Units:** a hexagonal grid over the region (`sf::st_make_grid(square = FALSE)` in the region CRS). The value in each hex is the aircraft count, or log(count + 1).
- **Parameters:**
  - hex size in km
  - weights: queen contiguity, KNN (k), distance band (d), or inverse distance
  - style: W (row-standardised) or B (binary)
  - global statistic: Moran's I, Geary's C or Global G
  - inference: analytic or permutation (nsim ≤ 999)
  - significance level α
- **Outputs:**
  - Global test table: statistic, expectation, variance, z, p.
  - Moran scatterplot.
  - LISA cluster map from `spdep::localmoran()`: HH, LL, HL, LH, or not significant at α.
  - A Local Moran's I table for the top hexes.
- **Packages:** `spdep` (`poly2nb`, `knn2nb`, `dnearneigh`, `nb2listw`, `moran.test`, `moran.mc`, `geary.test`, `globalG.test`, `localmoran`).

### 3.5 Method 2: Point patterns, quadrat test for CSR (Ch 7)

- **Point set:** airborne aircraft positions, or airports (by type: large, medium or both). Both are projected to the region CRS.
- **Window:** the projected region polygon, as a `spatstat.geom::owin`.
- **Parameters:** point set, airport types, and quadrat grid size nx × ny.
- **Outputs:**
  - A quadrat count map with the points overlaid.
  - The χ² test (`spatstat.explore::quadrat.test`): statistic, df, p.
  - VTMR = s² / x̄, interpreted as < 1 regular, ≈ 1 random, > 1 clustered.
  - The test statistic (m − 1) × VTMR compared against χ²(m − 1), as in the notes.
  - A histogram of quadrat counts against the Poisson expectation.

### 3.6 Method 3: Spatial lag regression (Ch 6)

- **Units:** countries in the region (or the World), from `spData::world`.
- **Response:** either flights departing each country yesterday (from `/flights/all` via airport → country), or aircraft present over each country in the current snapshot. log(1 + y) is available.
- **Covariates (checkboxes):** population, GDP per capita, area, airport count.
- **Weights:** queen contiguity, or KNN (k), which handles islands.
- **Outputs, as numbered steps matching the course workflow:**
  1. OLS summary (`lm`).
  2. Moran's I on the OLS residuals (`lm.morantest`).
  3. LM tests: LMerr, LMlag, RLMerr, RLMlag (`spdep::lm.RStests`; `lm.LMtests` is its older name). The app recommends a model from the robust tests.
  4. Spatial lag model (`spatialreg::lagsarlm`): ρ, coefficients, and AIC compared with OLS.
  5. A map of the residuals.

---

## 4. Code layout

```
STAT3037A_dashboard/
├── app.R                    navbar, sidebar, module wiring
├── R/
│   ├── data_api.R           fetch, cache, fallback, freeze
│   ├── data_prep.R          cleaning + joins
│   ├── regions.R            region table
│   ├── stats_autocorr.R     pure functions, no Shiny
│   ├── stats_quadrat.R
│   ├── stats_regression.R
│   ├── interpret.R          plain-English result text
│   ├── mod_live.R, mod_routes.R, mod_autocorr.R,
│   └── mod_quadrat.R, mod_regression.R, mod_about.R
├── data-raw/                build_lookups.R, capture_sample.R
├── data/
│   ├── lookups/             committed
│   ├── sample/              committed
│   └── frozen/              committed only when a frozen snapshot is used in the write-up
├── tests/testthat/
├── context/, plan/, docs/   brief, notes, plans, specs
├── .Renviron                git-ignored
└── README.md                setup, credentials, run instructions
```

**Interface rule:** each `stats_*` function takes an `sf` object plus parameter values and returns a named list. The list holds the test results as tibbles, the `sf` object for mapping, and any plot data. Modules only collect inputs, call the function and render the result. One person can therefore own each `stats_*` file plus its module without touching the others.

**Main packages:**
- App: `shiny`, `bslib`
- Data: `httr2`, `cachem`, `memoise`, `arrow`, `dplyr`, `sf`
- Statistics: `spdep`, `spatialreg`, `spatstat.geom`, `spatstat.explore`, `spData`
- Maps and tables: `leaflet`, `mapgl`, `DT`
- Tests: `testthat`

Use `renv` to pin the versions.

---

## 5. Error handling and edge cases

### API and data

| Situation | Behaviour |
|---|---|
| No credentials | Sample mode; the badge explains why |
| 401 / 5xx / timeout | Keep the last good cache, otherwise use the sample; one toast per session |
| 429 | Respect `X-Rate-Limit-Retry-After-Seconds`, pause polling, serve the cache |
| `/flights/all` 404 | Treated as an empty window |
| Null lat/lon, padded callsigns | Drop the row / `trimws()` |
| Lookup doesn't match | `"Unknown"` |

### Minimum-data checks

These run before each analysis. If one fails, the user sees a clear message and a suggestion, never an R error.

- **Quadrat:** at least 30 points, and an expected count of at least 5 per quadrat. Otherwise the app suggests a coarser grid.
- **Autocorrelation:** at least 30 hexes, and the values must vary.
- **Regression:** at least 15 complete countries, and n > number of parameters + 2.

### Spatial weights

- Units with no neighbours are counted and reported, and KNN is suggested. `zero.policy = TRUE` is set.
- The distance band's lower limit is the distance that guarantees every unit has at least one neighbour.

### Performance

- The hex grid is cached per region and size, and the neighbour list per weights choice (`bindCache`).
- Permutation tests are capped at 999 simulations, with a progress indicator.

---

## 6. Testing

- **Statistics functions** are checked against examples from the notes:
  - `stats_autocorr` on `spData`'s `nc` SID74: Moran's I matches `moran.test` output from Ch 4.
  - `stats_quadrat` on `spatstat.data::bei`: the χ² and VTMR match the Ch 7 example.
  - `stats_regression` on the world example: OLS and lag-model coefficients match Ch 6.
- **Data layer:** state-vector parsing on a recorded JSON fixture; 404 handling; the source falls back to sample when credentials are absent. No live network calls in the tests.
- **Prep:** the joins produce the expected Unknown counts on the sample.
- **Edge cases:** each minimum-data check returns its message rather than an error.
- **Manual smoke test:** every tab, every region, in sample mode and in live mode.

---

## 7. Suggested schedule (20 days)

| By | Milestone |
|---|---|
| 9 Oct | Repo skeleton, `renv`, OAuth working, `capture_sample.R` run, lookups built, `data_api` + `data_prep` with tests (class test 8 Oct) |
| 13 Oct | All three `stats_*` functions done and tested against the notes' examples |
| 18 Oct | All modules wired into `app.R`; filters and regions working end to end |
| 21 Oct | Live map, routes tab, About page, interpretation text, styling pass |
| 23 Oct | Bug bash in sample mode, README, optional deployment (R assessment on 22 Oct) |
| 26 Oct | Submit |

---

## 8. Open questions to confirm with the lecturer

1. Does data pulled live from an API count as "spatial data set on the back-end", or is the bundled sample dataset what satisfies it? The design works either way.
2. Is there a rubric or a written report beyond the dashboard?
3. Do global Moran's I and Local Moran's I count as one method (as designed here) or two?
