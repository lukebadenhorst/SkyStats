# Global Flights Dashboard: R Shiny Spatial Statistics Group Project

Context and plan for building this project with Claude Code. Rename to `CLAUDE.md` in the repo root, or reference it from there, so Claude Code loads it automatically.

> API facts below were checked against the OpenSky docs on 29 Sept 2026. Re-check https://openskynetwork.github.io/opensky-api/rest.html if anything fails.

---

## 1. Project brief

- **Course:** Spatial statistics (Wits, BSc Geospatial Science, 3rd year). This is a group project.
- **Deliverable:** An R Shiny app/dashboard of flights around the world.
- **Required features:**
  - Live flights map
  - Airport hotspot analysis
  - Busiest flight routes
  - **Three distinct types of spatial analysis** (must be spatial *statistics*, not just maps)
  - Filters: airline, aircraft type/manufacturer, etc.

---

## 2. Core design decision: separate live data from analysis data

- **Live layer.** The map tab polls the OpenSky API every 1–2 minutes. It's for visuals only.
- **Archive layer.** A scheduled collection script saves snapshots to disk (Parquet/DuckDB). **All spatial statistics run on this fixed archive**, so results are reproducible and defensible in the report.
- **Start the collector as early as possible.** Position history can't be backfilled (see §3).

---

## 3. Data sources and API constraints

### Sources

| Need | Source | Notes |
|---|---|---|
| Live aircraft positions | OpenSky `GET /states/all` | Free; supports a bounding box via `lamin`, `lomin`, `lamax`, `lomax` |
| Flights (dep → arr airport) | OpenSky `GET /flights/all` | Airports are *estimated* (`estDepartureAirport`, `estArrivalAirport`) |
| Aircraft type / manufacturer | OpenSky aircraft database CSV | Join on `icao24` |
| Airline name | First 3 chars of callsign = ICAO airline code → OpenFlights `airlines.dat` | e.g. `SAA`, `BAW`, `UAE` |
| Airports | OurAirports CSV | Coordinates, type, country, ICAO code |

### Authentication (important)

- OpenSky **only accepts the OAuth2 client credentials flow**. Basic auth with username/password no longer works, so older tutorials will fail.
- Create an API client on your OpenSky account page to get `client_id` and `client_secret`.
- Token URL: `https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token`
- Tokens expire after 30 minutes, so refresh them automatically. `httr2::req_oauth_client_credentials()` does this.
- Store credentials in `.Renviron` as `OPENSKY_CLIENT_ID` and `OPENSKY_CLIENT_SECRET`. **Never commit them.** Add `.Renviron` to `.gitignore`.
- Each group member should create their own free account.

### Time limits

| Data | How far back |
|---|---|
| State vectors, anonymous | Current snapshot only (`time` ignored), 10 s resolution |
| State vectors, authenticated | **Max 1 hour in the past** (older returns 400), 5 s resolution |
| `/flights/all` | Historical, but **each request ≤ 2 hours** of interval |
| `/flights/aircraft`, `/flights/arrival` | Batch-processed nightly, so only the previous day or earlier is complete |
| `/tracks` | Per aircraft, up to 30 days back, **experimental** |
| Full history | Trino interface; requires applying for researcher access |

**Conclusions:**
- Yesterday's flights and routes can be pulled: 12 × 2-hour `/flights/all` requests.
- 24 hours of aircraft positions **cannot** be downloaded after the fact. Collect them ourselves going forward.

### API credits (daily quotas, separate buckets for `/states/*`, `/flights/*`, `/tracks/*`)

| Tier | Credits |
|---|---|
| Anonymous | 400 / day |
| Standard user | 4,000 / day |
| Active feeder | 8,000 / day |

`/states/all` cost by bounding-box area (lat range × lon range in sq°):

| Area | Credits |
|---|---|
| ≤ 25 sq° | 1 |
| 25–100 | 2 |
| 100–400 | 3 |
| > 400 or global | 4 |

`/flights/*` cost: 4 credits (live / < 24 h), 30 credits (1–2 calendar-day partitions), more for longer ranges.

**Budgets:**
- Global snapshot every 15 min ≈ 96 × 4 = **384 credits/day**
- Global snapshot every 5 min ≈ 288 × 4 = **~1,150 credits/day**
- Yesterday's flights: 12 requests × ≤ 30 = **≤ 360 credits**

When credits run out, the API returns `429`; read the `X-Rate-Limit-Retry-After-Seconds` header. `X-Rate-Limit-Remaining` shows the remaining balance.

### `/states/all` response schema (`states` is a 2D array; index → field)

```
0 icao24          1 callsign        2 origin_country   3 time_position
4 last_contact    5 longitude       6 latitude         7 baro_altitude (m)
8 on_ground       9 velocity (m/s) 10 true_track (deg) 11 vertical_rate (m/s)
12 sensors       13 geo_altitude   14 squawk          15 spi
16 position_source (0 ADS-B, 1 ASTERIX, 2 MLAT, 3 FLARM)
17 category (only with extended=1; e.g. 4 Large, 6 Heavy, 8 Rotorcraft)
```

Callsigns are padded to 8 chars, so `trimws()` them. Lat/lon can be null, so drop those rows.

### Known data-quality issues (cover these in the report's limitations section)

- **Coverage bias.** OpenSky relies on volunteer receivers. Coverage is excellent over Europe and North America and sparse over much of Africa and the oceans. Global hotspots partly reflect receiver density, not traffic. Either analyse well-covered regions or discuss this explicitly.
- Departure/arrival airports are estimates and are often missing.
- Private and general-aviation aircraft have no airline prefix, and some `icao24` codes aren't in the aircraft DB. Label these **"Unknown"**; don't drop them silently.

### R client options

- `openSkies` (CRAN, v1.3.0, CC BY-NC 4.0). **Verify that it supports OAuth2** before relying on it.
- Fallback / preferred: call the REST API directly with `httr2` (see §8).

---

## 4. The three spatial analyses

### A. Hotspot analysis: Getis-Ord Gi\* (+ Local Moran's I)
- Aggregate archived aircraft positions to a hexagonal grid. Use `h3jsr` (H3), or `sf::st_make_grid(square = FALSE)` in an equal-area CRS.
- Alternatively, use airport points weighted by departures + arrivals from `/flights/all`.
- `spdep`: neighbours (contiguity for hexes, k-nearest for airports) → `localG()` for Gi\* z-scores, `localmoran()` for LISA clusters (High-High, Low-Low, outliers).
- Report **global Moran's I** first, as the "is there clustering?" test.

### B. Point pattern analysis
- `spatstat` on aircraft positions or airports **within one projected region** (spatstat needs a planar window; don't run it on the globe).
- Kernel density with bandwidth selection (`bw.diggle` / `bw.ppl`), Ripley's K / L-function with simulation envelopes, Clark-Evans nearest-neighbour index.

### C. Route / flow analysis
- Build origin–destination pairs from `/flights/all`, count flights per route, and draw great-circle lines (`sf::st_segmentize` or `geosphere::gcIntermediate`) weighted by volume.
- **Gravity model** to make it statistical: flights_ij ~ size_i × size_j / distance_ij^β, fitted as a Poisson GLM on log terms. Interpret the distance-decay coefficient β.
- Optional: `igraph` degree and betweenness centrality to identify hub airports.

### Alternatives (if the rubric needs different "types")
- Mean centre + standard deviational ellipse per airline. Pairs well with the airline filter.
- Spatial regression (spatial lag model, `spatialreg`) of airport traffic on population/GDP.

> Confirm with the lecturer/rubric whether Gi\* and Local Moran's I count as one type or two.

---

## 5. Filters

One shared reactive filtered dataset drives every tab:
- Airline (callsign prefix join)
- Aircraft type / manufacturer (aircraft DB join)
- Origin country (of registration)
- Altitude band; on ground vs airborne
- Region / bounding box (also reduces API credits on the live tab)
- Time window (archive tabs only)

---

## 6. App structure

### Tabs (`bslib::page_navbar`, or `bs4Dash`)
1. **Live Map.** Aircraft markers rotated by heading; popup with callsign, type, altitude, speed; refresh with `invalidateLater()`.
2. **Hotspots.** Gi\* hex map, LISA cluster map, global Moran's I summary.
3. **Point Patterns.** KDE surface, L-function plot with envelopes, Clark-Evans result.
4. **Routes.** Top-N routes map + table, gravity model output, fitted vs observed plot.
5. **About / Methods.** Data sources and limitations.

### Technical choices
- **Mapping.** A global snapshot can have ~10k aircraft, which is slow with plain `leaflet` markers. Use `leafgl` or `mapgl` (MapLibre).
- **Storage.** Parquet via `arrow`, or DuckDB.
- **Performance.** Precompute heavy statistics (Gi\*, K-function envelopes) in `data-raw/` scripts. Use `bindCache()` on reactives that recompute on filter changes.
- **Shared live cache.** Fetch live data once for all sessions (global `reactivePoll` or a file cache), not once per browser tab.
- **Deployment.** shinyapps.io or Posit Connect Cloud, with secrets set as platform environment variables.

### Folder layout

```
flights-dashboard/
├── app.R
├── R/                 # one Shiny module per tab + helpers (auth, API, joins)
├── data-raw/          # collect_snapshots.R, build_routes.R, build_lookups.R
├── data/              # parquet archive + joined lookup tables
├── .Renviron          # OPENSKY_CLIENT_ID / OPENSKY_CLIENT_SECRET (git-ignored)
└── .gitignore
```

---

## 7. Order of work

1. **Now.** Get OAuth2 working and pull one snapshot into R. **Start the snapshot collector immediately** (Windows Task Scheduler, or GitHub Actions on a cron schedule with secrets).
2. Pull yesterday's flights (§8) and build the lookup joins (airline, aircraft type, airports) plus the shared filtered-data reactive.
3. Split work: one person per analysis tab, plus one on the live map and UI shell. Shiny modules keep merging easy.
4. Integrate, add caching, deploy, write methods and limitations.
5. Optional: apply for OpenSky Trino researcher access if more history is needed.

---

## 8. Starter code: yesterday's flights via `httr2`

```r
library(httr2); library(purrr); library(dplyr)

client <- oauth_client(
  id        = Sys.getenv("OPENSKY_CLIENT_ID"),
  secret    = Sys.getenv("OPENSKY_CLIENT_SECRET"),
  token_url = "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
)

day_start <- as.numeric(as.POSIXct(Sys.Date() - 1, tz = "UTC"))
windows   <- seq(day_start, day_start + 22 * 3600, by = 7200)   # 12 x 2h windows

get_window <- function(begin) {
  resp <- request("https://opensky-network.org/api/flights/all") |>
    req_url_query(begin = begin, end = begin + 7200) |>
    req_oauth_client_credentials(client) |>
    req_error(is_error = \(r) FALSE) |>
    req_perform()
  if (resp_status(resp) == 404) return(NULL)   # 404 = no flights in window
  resp_check_status(resp)
  resp_body_json(resp, simplifyVector = TRUE)
}

flights_yday <- map(windows, get_window, .progress = TRUE) |> list_rbind()

routes <- flights_yday |>
  filter(!is.na(estDepartureAirport), !is.na(estArrivalAirport)) |>
  count(estDepartureAirport, estArrivalAirport, sort = TRUE)
```


