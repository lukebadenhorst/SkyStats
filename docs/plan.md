# Flights Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the three skeleton method tabs (Autocorrelation, Point Patterns, Spatial Regression) into working analyses, so a marker can run each one on the bundled sample and get correct results with a plain-English interpretation.

**Architecture:** Each method is a pure `R/stats_*.R` file (no Shiny, tested against the course-notes examples) plus a Shiny module `R/mod_*.R` that collects inputs, calls the stats function on **Run analysis** and renders the result. Shared helpers come first (Tasks 1–3), then the three methods can be built in parallel by different people.

**Tech Stack:** R 4.6, shiny + bslib, leaflet, sf, spdep, spatialreg, spatstat.geom / spatstat.explore, spData, testthat.

**Spec:** `docs/design.md`. Read it with this plan. Where they differ, this plan wins; the differences are listed under "Scope for 26 Oct".

**Progress:** the checkboxes below show what is done. `STATE.md` in the project root summarises the current state, what is left and what changed while building.

---

## Scope for 26 Oct

Six days are left, so the plan builds the three methods first. Everything else is a stretch goal.

**Must have (Tasks 1–13):** the three method tabs working in sample and live mode, a Home page with shortcuts to each tab (design later), the About page, the README, a clean bug bash.

**Stretch, only once Task 13 passes (S1–S5 at the end):** Airports & Routes tab, aircraft manufacturer/type filter, Freeze snapshot and source selector, `renv`, hosting.

**Differences from the spec, decided while writing this plan:**

| Spec says | Plan does | Why |
|---|---|---|
| Data files are Parquet (§2.3, §2.4) | `.rds`, as the existing code already does | No `arrow` dependency; files are small |
| Regression allowed in Southern Africa / East Asia with ≥ 15 countries (§2.7) | Regression only in **Europe** and **World** | Checked with `spData::world`: Southern Africa has 10 countries, East Asia 8, North America 11. Europe has 44 (39 complete), World 177 |
| Response: departures yesterday *or* aircraft now (§3.6) | Aircraft over each country now only | Departures need `/flights/all`, which is stretch S1 |
| Residual Moran via `lm.morantest` (§3.6) | `moran.test(residuals(ols), listw)` | That is what the Ch 6 notes do |
| Ch 6 test reproduces the notes' numbers (§6) | Test pins numbers from the 23 complete countries in `merge(world, worldbank_df)` | The notes' example ended up with 4 countries after its own join, which can't be reproduced from shipped data |
| `R/interpret.R` (§4) | Each `run_*()` returns its own `interpretation`; shared wording helpers live in `R/stats_common.R` | Keeps each method in one file per owner |
| Patch `-99` ISO codes (§2.6) | Not needed | In spData 2.3.5 only Northern Cyprus and Somaliland lack `iso_a2` |
| Permutation inference for every statistic (§3.4) | Analytic only for Global G | spdep has no `globalG.mc` |
| Quadrat test over the region window (§3.5) | Over `quadrat_window()`, the largest rectangle inside the region | A grid over the curved projected region has tiny clipped edge tiles. They fail the expected-count check (North America at 6 × 6, East Asia above 2 × 2) and make the VTMR report clustering for random points, because the notes' VTMR assumes equal quadrats. Found while building Task 6 |

## Global Constraints

- R ≥ 4.4. Packages: `shiny`, `bslib`, `bsicons`, `leaflet`, `cachem`, `DT`, `httr2`, `dplyr`, `jsonlite`, `sf`, `spdep`, `spatialreg`, `spatstat.geom`, `spatstat.explore`, `spatstat.data` (tests only), `spData`, `testthat`. Add no others (in particular not `lwgeom`, `arrow`, `mapgl`, `tmap`, `ggplot2`).
- Files in `R/` that do not start with `mod_` are pure: no Shiny calls, and every package function is called as `pkg::fn()`.
- Each `stats_*` function takes an `sf` object (or a `ppp` for quadrats) plus parameter values and returns a named list.
- A problem the user can fix (too few points, World selected, and so on) is raised with `stop_user()`. The module shows its message in a yellow alert; the user never sees a raw R error.
- Minimum data (spec §5), checked before each analysis:
  - Quadrat: ≥ 30 points, and every quadrat has an expected count ≥ 5.
  - Autocorrelation: ≥ 30 hexes, and the values are not all equal.
  - Regression: ≥ 15 countries with complete data, and n > number of coefficients + 2.
- Spatial weights always use `zero.policy = TRUE`. The number of units with no neighbours is reported.
- Global tests use `alternative = "greater"`, as in the notes. Permutations are capped at 999.
- Results are computed only when **Run analysis** is clicked (`bindEvent(input$run)`).
- Analyses run in the region's equal-area CRS from `R/regions.R`. Maps are shown in EPSG:4326 on `providers$Esri.WorldGrayCanvas`.
- The app must run from a fresh clone with no OpenSky credentials (sample mode).
- Run all tests from the R console in the project folder: `testthat::test_dir("tests/testthat")`. One file: `testthat::test_file("tests/testthat/test-<name>.R")`.

## Review Focus

1. **Filters leave almost nothing** (one airline in Southern Africa, every category unticked): each tab must show the minimum-data message, not an R error. Pinned by `run_safely()` tests in Task 1 and the "too few" tests in Tasks 4, 6 and 9.
2. **World selected on the Autocorrelation or Point Patterns tab**: show "World has no equal-area projection…". Pinned in Task 2.
3. **Namibia's ISO code is the string `"NA"`**: read naively, it becomes missing and Namibia gets no airports. Pinned in Task 8.
4. **A point on a hex edge counted twice, or a point outside the window**: hex totals must equal the number of points. Pinned in Task 4 (`hex_counts`) and Task 6 (`as_ppp`).
5. **Island countries with no queen neighbours** (Iceland and Cyprus in Europe): the regression must still run and report the isolates. Pinned in Task 9.

---

## How to split the work tomorrow

```
Task 1 → Task 2 → Task 3          (together, first; everyone needs these)
   ├── Person A: Task 4 → Task 5  Autocorrelation
   ├── Person B: Task 6 → Task 7  Point Patterns
   ├── Person C: Task 8 → Task 9 → Task 10   Regression (largest)
   └── Person D (or whoever is free): Task 11   Home page (needs no other task)
Task 12 → Task 13                 (together, at the end)
```

Each person works on their own branch (`git switch -c autocorr`, and so on) and merges into `main` when their tests pass. The only shared files the parallel tasks touch are `app.R` (one line each in `server`) and `R/mod_placeholders.R` (each deletes its own placeholder function), so merges should be small.

---

### Task 1: Shared helpers and test setup

**Files:**
- Create: `R/stats_common.R`, `R/mod_common.R`, `tests/testthat/test-stats_common.R`
- Modify: `tests/testthat/helper-source.R` (source every `R/*.R` file whose name does not start with `mod_`, instead of the fixed list)
- Modify: `R/mod_placeholders.R` (move `method_tab_ui()` and `alpha_input()` out to `R/mod_common.R`)
- Modify: `README.md` (add `sf`, `spdep`, `spatialreg`, `spatstat`, `spData` to the `install.packages()` call)

**Interfaces:**
- Produces (`R/stats_common.R`):
  - `stop_user(...)`: signals an error of class `c("user_error", "error", "condition")` whose message is `paste0(...)`.
  - `run_safely(expr)` → `list(ok = TRUE, value = <result>)`, or `list(ok = FALSE, message = <chr>)`. A `user_error` keeps its message unchanged; any other error becomes `"The analysis failed: <message>"`.
  - `format_p(p)` → `"< 0.001"` when p < 0.001, else `sprintf("%.3f", p)`.
  - `decision_text(p, alpha)` → `"p = 0.006 < α = 0.05, so we reject H0."` or `"p = 0.400 ≥ α = 0.05, so we do not reject H0."`. Write α as `α` and ≥ as `≥` in the source.
- Produces (`R/mod_common.R`):
  - `method_tab_ui(id, chapter, summary, controls, results)`: the existing layout, but with an **enabled** Run button (`actionButton(ns("run"), "Run analysis", ...)`), without the "Owner" line and "Coming soon" note, and with `results` (a tagList) in place of the "Planned outputs" card.
  - `alpha_input(ns)`: unchanged.
  - `result_alert(res)`: `NULL` when `res$ok`, else `div(class = "alert alert-warning", res$message)`.
  - Keep the old `disabled_run_button()` and the placeholder layout in `R/mod_placeholders.R` (rename it `placeholder_tab_ui()`) so the tabs not yet built still render.

- [x] **Step 1: Write the failing tests** in `tests/testthat/test-stats_common.R`

```r
test_that("stop_user signals a user_error", {
  expect_error(stop_user("Too few points: ", 3), "Too few points: 3", class = "user_error")
})

test_that("run_safely returns the value or a message", {
  expect_equal(run_safely(1 + 1), list(ok = TRUE, value = 2))
  expect_equal(run_safely(stop_user("Pick a region.")), list(ok = FALSE, message = "Pick a region."))
  expect_equal(run_safely(stop("boom"))$message, "The analysis failed: boom")
})

test_that("p-values and decisions are worded consistently", {
  expect_equal(format_p(0.0004), "< 0.001")
  expect_equal(format_p(0.00588), "0.006")
  expect_equal(decision_text(0.00588, 0.05), "p = 0.006 < α = 0.05, so we reject H0.")
  expect_equal(decision_text(0.4, 0.05), "p = 0.400 ≥ α = 0.05, so we do not reject H0.")
  expect_equal(decision_text(0.0001, 0.05), "p < 0.001 < α = 0.05, so we reject H0.")
})
```

- [x] **Step 2: Update `helper-source.R`, then run the tests and check they fail**

Run: `testthat::test_file("tests/testthat/test-stats_common.R")`
Expected: FAIL, `could not find function "stop_user"`.

- [x] **Step 3: Implement `R/stats_common.R` and `R/mod_common.R`, and edit `R/mod_placeholders.R`**

- [x] **Step 4: Run all tests and start the app**

Run: `testthat::test_dir("tests/testthat")`. Expected: all pass (60 old + the new ones).
Run: `shiny::runApp()`. Expected: the app opens and every tab still renders.

- [x] **Step 5: Commit**

```bash
git add R/stats_common.R R/mod_common.R R/mod_placeholders.R tests/testthat/ README.md
git commit -m "Add shared helpers for the method tabs"
```

---

### Task 2: Region geometry

**Files:**
- Modify: `R/regions.R`
- Test: `tests/testthat/test-regions.R` (new)

**Interfaces:**
- Consumes: `stop_user()` (Task 1); the existing `regions`, `get_region()` and `crop_to_region()`.
- Produces:
  - `regions$allow_regression` becomes logical: `TRUE` for `world` and `europe`, `FALSE` for the rest.
  - `region_polygon(region_id, n = 60)` → `sfc` POLYGON in EPSG:4326: the region's bbox with `n` points along each edge. Build the ring by hand with `seq()`, because `sf::st_segmentize()` needs `lwgeom`. Densifying keeps the edges curved after projection.
  - `region_crs(region_id)` → CRS string. For `world` it calls `stop_user("World has no equal-area projection. Pick a region to run this method.")`.
  - `region_window(region_id)` → `sf::st_transform(region_polygon(region_id), region_crs(region_id))`.
  - `to_region_sf(df, region_id)` → `sf` POINTs in the region CRS, built from the `longitude`/`latitude` columns after `crop_to_region()`. All other columns are kept, and zero rows is allowed.

- [x] **Step 1: Write the failing tests**

```r
test_that("region_polygon follows the bbox with dense edges", {
  p <- region_polygon("europe")
  expect_equal(as.numeric(sf::st_bbox(p)), c(-25, 34, 45, 72))
  expect_gte(nrow(sf::st_coordinates(p)), 4 * 60)
})

test_that("region_window is in the region's equal-area CRS", {
  w <- region_window("europe")
  expect_equal(sf::st_crs(w), sf::st_crs("EPSG:3035"))
  area_km2 <- as.numeric(sf::st_area(w)) / 1e6
  expect_gt(area_km2, 19e6)
  expect_lt(area_km2, 20e6)
})

test_that("World has no window", {
  expect_error(region_window("world"), "World has no equal-area projection", class = "user_error")
})

test_that("to_region_sf crops and projects", {
  df <- data.frame(longitude = c(10, 100, 2), latitude = c(50, 10, 48), id = 1:3)
  pts <- to_region_sf(df, "europe")
  expect_equal(pts$id, c(1L, 3L))
  expect_equal(sf::st_crs(pts), sf::st_crs("EPSG:3035"))
  expect_equal(nrow(to_region_sf(df[0, ], "europe")), 0)
})

test_that("regression is allowed only in Europe and World", {
  expect_equal(regions$id[regions$allow_regression], c("world", "europe"))
})
```

- [x] **Step 2: Run to check they fail**

Run: `testthat::test_file("tests/testthat/test-regions.R")`. Expected: FAIL, `could not find function "region_polygon"`.

- [x] **Step 3: Implement the four functions and change `allow_regression`**

- [x] **Step 4: Run all tests.** Expected: all pass.

- [x] **Step 5: Commit** (`git commit -m "Add region polygons, windows and projected points"`)

---

### Task 3: Spatial weights

**Files:**
- Create: `R/stats_weights.R`
- Test: `tests/testthat/test-stats_weights.R`

**Interfaces:**
- Consumes: `stop_user()`.
- Produces: `build_weights(units, type = c("queen", "knn", "dist", "idw"), k = 6, d_km = 300, style = c("W", "B"))` → `list(listw, nb, n_isolates, label)`.
  - `queen`: `spdep::poly2nb(units, queen = TRUE)`. If `units` are not polygons, call `stop_user("Queen contiguity needs polygons.")`.
  - The other types use centroid coordinates. When `sf::st_is_longlat(units)`, pass `longlat = TRUE` to spdep (distances in km). When projected, divide the coordinates by 1000 so `d_km` is in km.
  - `knn`: `knn2nb(knearneigh(coords, k, longlat))`.
  - `dist`: first compute `min_d`, the largest nearest-neighbour distance (`max(unlist(nbdists(knn2nb(knearneigh(coords, 1, longlat)), coords, longlat)))`). If `d_km < min_d`, call `stop_user("A distance band of ", d_km, " km leaves some units with no neighbours. Use at least ", ceiling(min_d), " km.")`. Otherwise `dnearneigh(coords, 0, d_km, longlat = longlat)`.
  - `idw`: the same neighbours as `dist`, with `glist = lapply(nbdists(nb, coords, longlat), function(d) 1 / d)`.
  - Always `nb2listw(nb, glist, style = style, zero.policy = TRUE)`.
  - `n_isolates = sum(spdep::card(nb) == 0)`.
  - `label`, for example `"Queen contiguity, style W"`, `"6 nearest neighbours, style W"`, `"Distance band 300 km, style B"`, `"Inverse distance within 300 km, style W"`.

- [x] **Step 1: Write the failing tests**

```r
nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)

test_that("queen weights on nc reproduce the Ch 4 Moran's I", {
  w <- build_weights(nc, "queen", style = "W")
  expect_equal(w$n_isolates, 0)
  m <- spdep::moran.test(nc$SID74, w$listw, alternative = "greater")
  expect_equal(unname(m$estimate[1]), 0.147740529, tolerance = 1e-8)
})

test_that("knn gives exactly k neighbours", {
  w <- build_weights(nc, "knn", k = 4)
  expect_true(all(spdep::card(w$nb) == 4))
})

test_that("a too-short distance band is refused with the minimum", {
  expect_error(build_weights(nc, "dist", d_km = 1), "Use at least 42 km", class = "user_error")
  w <- build_weights(nc, "idw", d_km = 100, style = "W")
  expect_equal(w$n_isolates, 0)
  expect_equal(sum(w$listw$weights[[1]]), 1)
})

test_that("queen on points is refused, and islands are counted", {
  pts <- sf::st_centroid(sf::st_geometry(nc))
  expect_error(build_weights(pts, "queen"), "needs polygons", class = "user_error")
  w <- suppressWarnings(build_weights(spData::world, "queen"))
  expect_gt(w$n_isolates, 0)
})
```

(The nc nearest-neighbour maximum is 41.03 km, so the message says 42.)

- [x] **Step 2: Run to check they fail.** Expected: `could not find function "build_weights"`.
- [x] **Step 3: Implement `build_weights()`.**
- [x] **Step 4: Run all tests.** Expected: all pass.
- [x] **Step 5: Commit** (`git commit -m "Add build_weights for all four weight types"`)

---

### Task 4: Autocorrelation statistics (Ch 4)

**Files:**
- Create: `R/stats_autocorr.R`
- Test: `tests/testthat/test-stats_autocorr.R`

**Interfaces:**
- Consumes: `build_weights()`, `stop_user()`, `format_p()`, `decision_text()`.
- Produces:
  - `hex_counts(points, window, hex_km, log = TRUE)` (`points` is `sf` or `sfc`, in the window's CRS) → `sf` POLYGONs with `hex_id`, `count` (integer) and `value` (`log1p(count)` when `log`, else `count`). The hexes are `sf::st_make_grid(window, cellsize = hex_km * 1000, square = FALSE)`, keeping those that intersect `window`. Each point is counted once, in the first hex `st_intersects(points, hexes)` returns for it.
  - `run_autocorr(units, weights = "queen", k = 6, d_km = 300, style = "W", statistic = c("moran", "geary", "globalg"), inference = c("analytic", "perm"), nsim = 499, alpha = 0.05)` uses `units$value` and returns:
    - `global`: one-row data.frame with `statistic` ("Moran's I", "Geary's C" or "Global G"), `observed`, `expectation`, `variance`, `z`, `p_value`. The analytic tests are `moran.test`, `geary.test` and `globalG.test`. Permutation uses `moran.mc` / `geary.mc` with `nsim = min(nsim, 999)`: then `expectation` and `variance` are the mean and variance of the simulated values, and `z = (observed - expectation) / sqrt(variance)`.
    - `scatter`: data.frame with `value` and `lag = spdep::lag.listw(listw, value, zero.policy = TRUE)`.
    - `lisa`: `units` plus `Ii`, `p_value` and `cluster`, from `spdep::localmoran()`. `cluster` is `attr(., "quadr")$mean`, set to `"Not significant"` where `p_value > alpha`, as a factor with levels `c("High-High", "Low-Low", "High-Low", "Low-High", "Not significant")`.
    - `weights_label`, `n_isolates`.
    - `interpretation`: character. For Moran: `"H0: aircraft counts are spread randomly across the hexes (no spatial autocorrelation). Moran's I = 0.148 (expected -0.010 under H0), z = 2.52. <decision_text>"`, then one sentence saying what that means (I > E[I]: neighbouring hexes have similar counts, so traffic is clustered), then `"LISA finds <n> High-High and <n> Low-Low hexes at α = <alpha>."`. Geary: C < 1 means positive autocorrelation. Global G: G > E[G] means high counts cluster (hot spots).
  - User errors:
    - fewer than 30 units: `"Only <n> hexes in this region. Use smaller hexes (at least 30 are needed)."`
    - all values equal: `"Every hex has the same value, so autocorrelation can't be measured. Change the filters or the hex size."`
    - `globalg` with `perm`: `"Permutation inference isn't available for Global G. Use analytic."`

- [x] **Step 1: Write the failing tests**

```r
nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
nc$value <- nc$SID74

test_that("Moran's I matches Example 4.1", {
  g <- run_autocorr(nc, "queen", style = "W", statistic = "moran")$global
  expect_equal(g$observed, 0.147740529, tolerance = 1e-8)
  expect_equal(g$expectation, -0.010101010, tolerance = 1e-8)
  expect_equal(g$variance, 0.003925567, tolerance = 1e-8)
  expect_equal(g$z, 2.519243, tolerance = 1e-6)
  expect_equal(g$p_value, 0.005880369, tolerance = 1e-8)
})

test_that("Geary's C and Global G match spdep", {
  expect_equal(run_autocorr(nc, statistic = "geary")$global$observed, 0.843876721, tolerance = 1e-8)
  expect_equal(run_autocorr(nc, style = "B", statistic = "globalg")$global$observed, 0.06740078, tolerance = 1e-7)
})

test_that("permutation inference keeps the observed value", {
  set.seed(1)
  g <- run_autocorr(nc, statistic = "moran", inference = "perm", nsim = 499)$global
  expect_equal(g$observed, 0.147740529, tolerance = 1e-8)
  expect_lt(g$p_value, 0.05)
  expect_error(run_autocorr(nc, statistic = "globalg", inference = "perm"), "Global G", class = "user_error")
})

test_that("LISA labels every unit", {
  res <- run_autocorr(nc)
  expect_equal(nrow(res$lisa), 100)
  expect_equal(levels(res$lisa$cluster), c("High-High", "Low-Low", "High-Low", "Low-High", "Not significant"))
  expect_true(all(run_autocorr(nc, alpha = 1e-12)$lisa$cluster == "Not significant"))
  expect_match(res$interpretation, "so we reject H0")
})

test_that("hex_counts counts every point once", {
  win <- sf::st_as_sfc(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 1e5, ymax = 1e5), crs = 3035))
  set.seed(2)
  pts <- sf::st_sample(win, 200)
  hx <- hex_counts(pts, win, hex_km = 10)
  expect_equal(sum(hx$count), 200)
  expect_equal(hx$value, log1p(hx$count))
})

test_that("too few hexes or constant values give a user message", {
  win <- sf::st_as_sfc(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 1e5, ymax = 1e5), crs = 3035))
  big <- hex_counts(sf::st_sample(win, 50), win, hex_km = 50)
  expect_error(run_autocorr(big), "^Only \\d+ hexes", class = "user_error")
  flat <- nc
  flat$value <- 1
  expect_error(run_autocorr(flat), "same value", class = "user_error")
})
```

- [x] **Step 2: Run to check they fail.** Expected: `could not find function "run_autocorr"`.
- [x] **Step 3: Implement `hex_counts()` and `run_autocorr()`.**
- [x] **Step 4: Run all tests.** Expected: all pass.
- [x] **Step 5: Commit** (`git commit -m "Add autocorrelation statistics with LISA"`)

---

### Task 5: Autocorrelation tab

**Files:**
- Create: `R/mod_autocorr.R`, `tests/testthat/test-mod_autocorr.R`
- Modify: `R/mod_placeholders.R` (delete `autocorr_ui`), `app.R` (one line in `server`)

**Interfaces:**
- Consumes: `method_tab_ui()`, `alpha_input()`, `result_alert()`, `run_safely()`, `to_region_sf()`, `region_window()`, `hex_counts()`, `run_autocorr()`.
- Produces: `autocorr_ui(id)` and `autocorr_server(id, aircraft, region_id)`, where `aircraft` is the app's filtered-states reactive and `region_id` is `reactive(input$region)`. Inside the server, `result` is the `bindEvent(reactive(run_safely(...)), input$run)` value; the test reads it.

- [x] **Step 1: Write the failing module test**

```r
library(shiny)
library(bslib)
for (f in c("mod_common.R", "mod_autocorr.R")) source(file.path(root, "R", f))

sample_aircraft <- prep_states(readRDS(sample_path)$data)

test_that("the tab runs Moran's I on the sample in Europe and refuses World", {
  region <- reactiveVal("europe")
  testServer(autocorr_server, args = list(aircraft = reactive(sample_aircraft), region_id = region), {
    session$setInputs(hex_km = 150, log = TRUE, weights = "queen", k = 6, d = 300, style = "W",
                      statistic = "moran", inference = "analytic", nsim = 499, alpha = "0.05", run = 1)
    expect_true(result()$ok)
    expect_equal(result()$value$global$statistic, "Moran's I")
    region("world")
    session$setInputs(run = 2)
    expect_match(result()$message, "World has no equal-area projection")
  })
})
```

- [x] **Step 2: Run to check it fails.** Expected: `could not find function "autocorr_server"`.
- [x] **Step 3: Build the UI**, keeping the existing controls from the placeholder. Wrap the Permutation choice so it is hidden when `input.statistic == 'globalg'`. The `results` area holds:
  - the interpretation and `result_alert()`;
  - the global test table;
  - a LISA leaflet map (hexes transformed to 4326; colours HH `#d7191c`, LL `#2c7bb6`, HL `#fdae61`, LH `#abd9e9`, NS `#eeeeee`);
  - a Moran scatterplot (`renderPlot`: `plot(value, lag)` with the `lm` line and dashed mean lines);
  - a table of the 10 significant hexes with the largest `Ii`.
- [x] **Step 4: Build the server.** The pipeline is `to_region_sf(aircraft(), region_id())` → `hex_counts(pts, region_window(region_id()), input$hex_km, input$log)` → `run_autocorr(...)`, all inside `run_safely()`, with `alpha = as.numeric(input$alpha)`. Show a progress message while it runs.
- [x] **Step 5: Wire it up.** Add `autocorr_server("autocorr", aircraft = aircraft, region_id = reactive(input$region))` to `app.R`, and delete `autocorr_ui` from `R/mod_placeholders.R`.
- [x] **Step 6: Run all tests, then check by hand.** Run `shiny::runApp()` in sample mode, choose Region Europe, keep the defaults and click Run. Expected: a table, map and scatterplot, and an interpretation that mentions Moran's I. With Region World, Run shows the yellow message.
- [x] **Step 7: Commit** (`git commit -m "Build the Autocorrelation tab"`)

---

### Task 6: Quadrat statistics (Ch 7)

**Files:**
- Create: `R/stats_quadrat.R`
- Test: `tests/testthat/test-stats_quadrat.R`

**Interfaces:**
- Consumes: `stop_user()`, `format_p()`, `decision_text()`.
- Produces:
  - `quadrat_window(window)` → `sfc` POLYGON: the largest axis-aligned rectangle (found by search) inside a projected region window, in the same CRS. Every quadrat over it has the same area. It keeps 57–63% of each region's area but most aircraft (95% in Europe, 98% in North America, 67% in East Asia for the sample).
  - `as_ppp(points, window)` (`points` is `sf` or `sfc`) → `spatstat.geom::ppp`, with the window `spatstat.geom::as.owin(window)` (coordinates in metres). Points outside the window are dropped first with `spatstat.geom::inside.owin()`, so `ppp()` never warns.
  - `run_quadrat(X, nx = 6, ny = 6, alpha = 0.05, crs = NA)` → list:
    - `chisq`: data.frame with `statistic`, `df`, `p_value` from `spatstat.explore::quadrat.test(X, nx = nx, ny = ny)`, wrapped in `suppressWarnings()` because the app does its own expected-count check.
    - `vtmr`: data.frame with `m`, `mean`, `variance`, `vtmr`, `statistic`, `df`, `p_value`. The counts are `as.vector(quadratcount(X, nx, ny))` and `m` is how many there are (tiles outside an irregular window are left out). `vtmr = var / mean`, `statistic = (m - 1) * vtmr`, `df = m - 1`, and the p-value is two-sided: `min(1, 2 * min(pchisq(stat, df), pchisq(stat, df, lower.tail = FALSE)))`.
    - `tiles`: `sf` with `count` (from `quadrat.test(...)$observed`, **not** `as.vector(Q)`, which runs down the columns while the tiles run along the rows), `expected` (from `quadrat.test(...)$expected`) and geometry. Build it with `sf::st_as_sfc()` on each tile of `spatstat.geom::tiles(as.tess(Q))`, then set its CRS to `crs`.
    - `interpretation`: `"H0: the points follow complete spatial randomness (a homogeneous Poisson process). χ² = 2681.08 on 35 df. <decision_text>"`, then `"VTMR = 76.60, which suggests a clustered pattern."` (regular when VTMR < 1, clustered when > 1). When the VTMR test is not significant at α, say `"VTMR = 1.04, which is consistent with a random pattern."` instead.
  - User errors:
    - fewer than 30 points: `"Only <n> points in this region. At least 30 are needed; widen the filters."`
    - `min(expected) < 5`: `"Some quadrats expect fewer than 5 points (smallest: <x.x>). Use fewer quadrats."`

- [x] **Step 1: Write the failing tests**

```r
data(bei, package = "spatstat.data")

test_that("the bei example matches Example 7.1", {
  res <- run_quadrat(bei, nx = 6, ny = 6)
  expect_equal(unname(res$chisq$statistic), 2681.077, tolerance = 1e-6)
  expect_equal(unname(res$chisq$df), 35)
  expect_equal(res$vtmr$m, 36)
  expect_equal(res$vtmr$mean, 100.1111, tolerance = 1e-6)
  expect_equal(res$vtmr$vtmr, 76.60219, tolerance = 1e-6)
  expect_equal(res$vtmr$statistic, 35 * res$vtmr$vtmr)
  expect_lt(res$vtmr$p_value, 1e-10)
  expect_equal(sum(res$tiles$count), 3604)
  expect_match(res$interpretation, "clustered")
})

test_that("a perfect grid reads as regular", {
  g <- spatstat.geom::ppp(rep(seq(5, 95, 10), 10), rep(seq(5, 95, 10), each = 10), c(0, 100), c(0, 100))
  res <- run_quadrat(g, nx = 2, ny = 2) # 25 points per quadrat

  expect_equal(res$vtmr$vtmr, 0)
  expect_match(res$interpretation, "regular")
})

test_that("too few points, or too many quadrats, give user messages", {
  set.seed(3)
  few <- spatstat.random::runifpoint(10)
  expect_error(run_quadrat(few), "^Only 10 points", class = "user_error")
  forty <- spatstat.random::runifpoint(40)
  expect_error(run_quadrat(forty, nx = 10, ny = 10), "fewer than 5", class = "user_error")
})

test_that("as_ppp drops points outside the window", {
  win <- sf::st_as_sfc(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 1e5, ymax = 1e5), crs = 3035))
  set.seed(4)
  pts <- c(sf::st_sample(win, 50), sf::st_sfc(sf::st_point(c(2e5, 2e5)), crs = 3035))
  expect_equal(spatstat.geom::npoints(as_ppp(pts, win)), 50)
})
```

(`spatstat.random` is installed with `spatstat`.)

- [x] **Step 2: Run to check they fail.** Expected: `could not find function "run_quadrat"`.
- [x] **Step 3: Implement `as_ppp()` and `run_quadrat()`.**
- [x] **Step 4: Run all tests.** Expected: all pass.
- [x] **Step 5: Commit** (`git commit -m "Add quadrat test and VTMR"`)

---

### Task 7: Point Patterns tab

**Files:**
- Create: `R/mod_quadrat.R`, `tests/testthat/test-mod_quadrat.R`
- Modify: `R/mod_placeholders.R` (delete `quadrat_ui`), `app.R` (one line in `server`)

**Interfaces:**
- Consumes: Task 1 helpers, `to_region_sf()`, `region_window()`, `region_crs()`, `quadrat_window()`, `as_ppp()`, `run_quadrat()`. Build the pattern with `as_ppp(points, quadrat_window(region_window(region)))`, not the region window itself (see the last row of the table under "Scope for 26 Oct"). On the map, draw the rectangle's outline so it is clear which area was tested. `load_airports()` comes from Task 8: until Task 8 is merged, pass an empty data.frame. The airport option then shows "Only 0 points…", which is fine.
- Produces: `quadrat_ui(id)` and `quadrat_server(id, aircraft, region_id, airports)`, where `airports` is a data.frame with `longitude`, `latitude` and `type`. Inside the server, `result` is the `bindEvent`'d `run_safely()` value.

- [x] **Step 1: Write the failing module test** (same pattern as Task 5). Use the sample in Europe with `points = "aircraft"`, `nx = 6`, `ny = 6`, `alpha = "0.05"`, `run = 1`, and expect `result()$ok`. Then set `nx = 15`, `ny = 15` with `points = "airports"` and an `airports` argument of `data.frame(longitude = 10, latitude = 50, type = "large_airport")`, and expect `result()$message` to match `"^Only 1 points"`.
- [x] **Step 2: Run to check it fails.**
- [x] **Step 3: Build the UI and server.**
  - Point set "Airborne aircraft" uses `aircraft()[aircraft()$airborne, ]`. "Airports" uses `airports[airports$type %in% input$airport_types, ]`. Under the airport option, show a note: "Airline, category and altitude filters don't apply to airports."
  - Outputs:
    - the interpretation and `result_alert()`;
    - a χ² table and a VTMR table;
    - a leaflet map of the tiles (transformed to 4326, filled with `colorNumeric("viridis", count)` and labelled with the count) with the points on top;
    - a histogram of the counts (`renderPlot`), with the Poisson expectation `m * dpois(0:max(count), mean)` drawn as points joined by a line.
- [x] **Step 4: Wire it up.** Add `quadrat_server("quadrat", aircraft = aircraft, region_id = reactive(input$region), airports = airports)` to `app.R`. Add `airports <- load_airports()` at the top of `app.R` if Task 8 has landed; otherwise use `airports <- data.frame(longitude = numeric(), latitude = numeric(), type = character())` for now. Delete `quadrat_ui` from the placeholders.
- [x] **Step 5: Run all tests and check by hand** (Europe, defaults, Run). Expected: a map of tiles, two tables, a histogram and the interpretation. Setting nx = ny = 15 in Southern Africa with few aircraft shows the "fewer than 5" message.
- [x] **Step 6: Commit** (`git commit -m "Build the Point Patterns tab"`)

---

### Task 8: Airport lookup

**Files:**
- Modify: `data-raw/build_lookups.R`, `R/lookups.R`
- Create: `data/lookups/airports.rds` (by running the script), `tests/testthat/test-lookups.R`

**Interfaces:**
- Produces:
  - `airports_path <- file.path("data", "lookups", "airports.rds")`.
  - `load_airports(path = airports_path)` → data.frame with `ident`, `type` (`"large_airport"` or `"medium_airport"`), `name`, `latitude`, `longitude` and `iso_country`. If the file is missing, it returns a zero-row data.frame with those columns.
  - In `build_lookups.R`, read `https://davidmegginson.github.io/ourairports-data/airports.csv` with `read.csv(..., na.strings = "")`. **Not** the default, which turns Namibia's `"NA"` into a missing value. Keep only large and medium airports, rename `latitude_deg`/`longitude_deg`, and save with `compress = "xz"`.

- [x] **Step 1: Write the failing tests**

```r
test_that("the airport lookup keeps large and medium airports", {
  a <- load_airports(file.path(root, airports_path))
  expect_gt(nrow(a), 5000)
  expect_setequal(unique(a$type), c("large_airport", "medium_airport"))
  expect_false(anyNA(a$latitude) || anyNA(a$longitude))
})

test_that("Namibia's ISO code survives as the string NA", {
  a <- load_airports(file.path(root, airports_path))
  expect_true("NA" %in% a$iso_country)
})

test_that("a missing airport file gives an empty table", {
  a <- load_airports("nope.rds")
  expect_equal(nrow(a), 0)
  expect_named(a, c("ident", "type", "name", "latitude", "longitude", "iso_country"))
})
```

- [x] **Step 2: Run to check they fail.**
- [x] **Step 3: Implement it.** Then run `Rscript data-raw/build_lookups.R`, or `source("data-raw/build_lookups.R")` in the console. This needs internet but no OpenSky credits.
- [x] **Step 4: Run all tests.** Expected: all pass. The file should be under 1 MB.
- [x] **Step 5: Commit** (`git add data/lookups/airports.rds ...`; `git commit -m "Add the OurAirports lookup"`)

---

### Task 9: Regression statistics (Ch 6)

**Files:**
- Create: `R/stats_regression.R`
- Test: `tests/testthat/test-stats_regression.R`

**Interfaces:**
- Consumes: `build_weights()`, `get_region()`, `region_crs()`, `stop_user()`, `format_p()`, `decision_text()`, `load_airports()` (its columns).
- Produces:
  - `country_units(region_id, aircraft, airports)` → `sf` of `spData::world` countries whose `sf::st_centroid()` (s2 on) falls inside the region bbox. All 177 for `world`. Columns:
    - `iso_a2`, `name_long`, `pop`, `gdpPercap`, `area_km2`;
    - `airports`: rows of `airports` with `iso_country == iso_a2`, 0 when there are none, NA when `iso_a2` is NA;
    - `aircraft`: rows of `aircraft` whose lon/lat fall inside the country, via `st_intersects` in 4326.

    The result is transformed to `region_crs()` except for World, which stays in 4326. If `!get_region(region_id)$allow_regression`, call `stop_user("Regression needs at least 15 countries, so it is only available for Europe and the World.")`.
  - `regression_formula(covariates, log_y = TRUE)` → formula. The left side is `log1p(aircraft)` or `aircraft`. The terms are `pop` → `log(pop)`, `gdpPercap` → `log(gdpPercap)`, `area_km2` → `log(area_km2)` and `airports` → `log1p(airports)`, in the order given. With no covariates, call `stop_user("Pick at least one covariate.")`.
  - `run_regression(units, formula, weights = c("queen", "knn"), k = 4, alpha = 0.05, min_n = 15)` keeps the complete cases of `all.vars(formula)` and builds `build_weights(units_c, weights, k = k, style = "W")`. It returns:
    - `n`, `n_isolates`, `weights_label`;
    - `ols`: data.frame with `term`, `estimate`, `std_error`, `statistic`, `p_value`; plus `r_squared`;
    - `resid_moran`: data.frame with `observed`, `expectation`, `variance`, `z`, `p_value`, from `spdep::moran.test(residuals(ols), listw, zero.policy = TRUE)`;
    - `lm_tests`: data.frame with `test = c("LMlag", "LMerr", "RLMlag", "RLMerr")`, `statistic`, `p_value`, from `spdep::lm.RStests(ols, listw, test = c("LMlag", "LMerr", "RLMlag", "RLMerr"), zero.policy = TRUE)` (the elements come back named `RSlag`, `RSerr`, `adjRSlag`, `adjRSerr`);
    - `recommendation`, one of `"OLS"`, `"Spatial lag"` or `"Spatial error"`. If neither LMlag nor LMerr is significant at α, choose OLS. If exactly one is, choose that model. If both are, choose the one whose robust test has the smaller p-value.
    - `lag`: data.frame from `summary(spatialreg::lagsarlm(formula, data, listw, zero.policy = TRUE))$Coef`, renamed to the same columns as `ols` (`term`, `estimate`, `std_error`, `statistic`, `p_value`) so the tab can show both the same way; plus top-level `rho` and `rho_p_value` (`summary(...)$LR1$p.value`). The lag model is always fitted, because it is step 4 of the course workflow.
    - `aic`: data.frame with `model = c("OLS", "Spatial lag")` and `aic`;
    - `residuals`: `units_c` plus `ols_resid` and `lag_resid`;
    - `interpretation`: one sentence each for steps 2–4. Step 2 is the residual Moran's I plus `decision_text`. Step 3 states the recommendation and why. Step 4 gives ρ, its LR p-value and the AIC comparison, saying "fits better" when the lag model's AIC is lower.
  - User errors:
    - n < min_n: `"Only <n> countries have complete data. At least <min_n> are needed."`
    - n ≤ number of coefficients + 2: `"Too many covariates for <n> countries. Remove one."`
  - Notes from building it:
    - "Complete" also drops rows whose transformed value is not finite (e.g. `log(0)`).
    - `spData::world` has no `pop` or `gdpPercap` for France and Norway (and no `gdpPercap` for Syria), so with those covariates Europe runs on 40 of its 44 countries.
    - The two test fixes below (`sf::st_as_sf()` around `merge()`, and `which()` because Northern Cyprus's `iso_a2` is NA) are in `tests/testthat/test-stats_regression.R`.

- [x] **Step 1: Write the failing tests**

```r
wb <- merge(spData::world, spData::worldbank_df, by = "iso_a2")
f <- unemployment ~ literacy + log(urban_pop)

# Numbers below are from the 23 countries with complete data (Ch 6 workflow,
# KNN k = 2 on great-circle distances). The notes' printout used 4 countries.
test_that("the Ch 6 workflow gives the pinned values", {
  res <- suppressWarnings(run_regression(wb, f, weights = "knn", k = 2))
  expect_equal(res$n, 23)
  expect_equal(res$ols$estimate, c(-5.63978612, 0.13080027, 0.16700095), tolerance = 1e-7)
  expect_equal(res$resid_moran$observed, 0.155019369, tolerance = 1e-7)
  expect_equal(res$lm_tests$test, c("LMlag", "LMerr", "RLMlag", "RLMerr"))
  expect_equal(res$lm_tests$statistic, c(0.21337483, 0.63562008, 3.54754354, 3.96978878), tolerance = 1e-6)
  expect_equal(res$rho, 0.13104414, tolerance = 1e-6)
  expect_equal(res$aic$aic, c(162.0058, 163.7267), tolerance = 1e-4)
  expect_equal(res$recommendation, "OLS")
})

test_that("too few countries give a user message", {
  expect_error(suppressWarnings(run_regression(wb, f, "knn", k = 2, min_n = 30)),
               "^Only 23 countries", class = "user_error")
})

test_that("the formula is built from the covariate choices", {
  expect_equal(deparse(regression_formula(c("pop", "airports"))), "log1p(aircraft) ~ log(pop) + log1p(airports)")
  expect_equal(deparse(regression_formula("area_km2", log_y = FALSE)), "aircraft ~ log(area_km2)")
  expect_error(regression_formula(character()), "at least one", class = "user_error")
})

test_that("country_units counts aircraft and airports per country", {
  ac <- data.frame(longitude = c(2.35, 13.4, 13.5), latitude = c(48.86, 52.5, 52.5))
  ap <- data.frame(iso_country = c("FR", "DE", "NA"))
  u <- country_units("europe", ac, ap)
  expect_equal(nrow(u), 44)
  expect_equal(sf::st_crs(u), sf::st_crs("EPSG:3035"))
  expect_equal(u$aircraft[u$iso_a2 == "FR"], 1)
  expect_equal(u$aircraft[u$iso_a2 == "DE"], 2)
  expect_equal(u$airports[u$iso_a2 == "FR"], 1)
  expect_error(country_units("north_america", ac, ap), "only available for Europe", class = "user_error")
})

test_that("queen weights in Europe run despite the islands", {
  ac <- readRDS(sample_path)$data
  ac <- ac[!is.na(ac$longitude), ]
  u <- country_units("europe", ac, data.frame(iso_country = character()))
  res <- suppressWarnings(run_regression(u, log1p(aircraft) ~ log(pop) + log(gdpPercap), weights = "queen"))
  expect_gte(res$n_isolates, 1)
  expect_true(is.finite(res$rho))
})
```

- [x] **Step 2: Run to check they fail.** Expected: `could not find function "run_regression"`.
- [x] **Step 3: Implement the three functions.**
- [x] **Step 4: Run all tests.** Expected: all pass.
- [x] **Step 5: Commit** (`git commit -m "Add the spatial regression workflow"`)

---

### Task 10: Spatial Regression tab

**Files:**
- Create: `R/mod_regression.R`, `tests/testthat/test-mod_regression.R`
- Modify: `R/mod_placeholders.R` (delete `regression_ui`), `app.R` (one line in `server`, plus `airports <- load_airports()` if Task 7 hasn't added it)

**Interfaces:**
- Consumes: Task 1 helpers, `country_units()`, `regression_formula()`, `run_regression()`.
- Produces: `regression_ui(id)` and `regression_server(id, aircraft, region_id, airports)`. Inside the server, `result` is the `bindEvent`'d `run_safely()` value.

- [x] **Step 1: Write the failing module test** (same pattern as Task 5). On the sample in Europe, set `covariates = c("pop", "gdpPercap")`, `log_y = TRUE`, `weights = "knn"`, `k = 4`, `alpha = "0.05"`, `run = 1`, and expect `result()$ok` and `result()$value$n >= 15`. Then set the region to `"north_america"`, run again, and expect the "only available for Europe" message.
- [x] **Step 2: Run to check it fails.**
- [x] **Step 3: Build the UI and server.** Drop the "Flights departing yesterday" response choice; the response is "Aircraft over the country now" (stretch S1 brings departures back). Show the outputs as five numbered cards matching the course workflow:
  1. the OLS table and R²;
  2. the residual Moran table;
  3. the LM test table, with the recommendation as a badge;
  4. the lag model table, ρ, and the AIC table;
  5. a residual map (leaflet, transformed to 4326, `colorBin("RdBu", reverse = TRUE)`), with a radio to switch between OLS and lag residuals.

  Put the interpretation and `result_alert()` above the cards. If `n_isolates > 0` under queen weights, add a note: "<n> countries have no land neighbours. Try K nearest neighbours."
- [x] **Step 4: Wire it up.** Add `regression_server("regression", aircraft = aircraft, region_id = reactive(input$region), airports = airports)`.
- [x] **Step 5: Run all tests and check by hand** (Europe, then World, in sample mode).
- [x] **Step 6: Commit** (`git commit -m "Build the Spatial Regression tab"`)

---

### Task 11: Home (landing) page

The structure and navigation only. The text and visual design are placeholders, to be designed later by the group. This task depends on no other task, so a fourth person can do it at any point.

**Files:**
- Create: `R/mod_home.R`, `tests/testthat/test-mod_home.R`
- Modify: `app.R`

**Interfaces:**
- Produces:
  - `home_sections`: data.frame with one row per shortcut, columns `key`, `tab`, `icon`, `blurb`. `tab` must equal the `nav_panel` title exactly. Rows:
    - `live`, "Live Map", `map`: "See every aircraft OpenSky is tracking right now."
    - `autocorr`, "Autocorrelation", `grid-3x3`: "Is air traffic clustered? Moran's I, Geary's C, Global G and LISA (Ch 4)."
    - `quadrat`, "Point Patterns", `dot`: "Are aircraft or airports randomly spread? Quadrat test and VTMR (Ch 7)."
    - `regression`, "Spatial Regression", `graph-up`: "What explains traffic per country? OLS to spatial lag model (Ch 6)."
    - `about`, "About", `info-circle`: "Data sources, methods and limitations."

    Add an "Airports & Routes" row only if stretch S1 is done.
  - `home_ui(id)`:
    - a hero section: the title "Global Flights", a 2–3 sentence placeholder on what the app is for (live OpenSky data analysed with three spatial statistics methods from STAT3037A), and the data-source line;
    - a `layout_column_wrap(width = "250px")` of cards, one per `home_sections` row: icon, tab name, blurb, and an `actionButton(ns(paste0("go_", key)), paste("Open", tab))`.
  - `home_server(id, on_select)`: calls `on_select(tab)` each time a shortcut button is clicked. It uses a callback rather than returning a reactive value, so clicking the same shortcut a second time (after coming back to Home) still navigates.

- [ ] **Step 1: Write the failing test**

```r
library(shiny)
library(bslib)
source(file.path(root, "R", "mod_home.R"))

test_that("every shortcut targets its tab, including repeat clicks", {
  picked <- character()
  testServer(home_server, args = list(on_select = function(tab) picked <<- c(picked, tab)), {
    session$setInputs(go_autocorr = 1)
    session$setInputs(go_regression = 1)
    session$setInputs(go_autocorr = 2)
  })
  expect_equal(picked, c("Autocorrelation", "Spatial Regression", "Autocorrelation"))
})

test_that("every shortcut names a real tab", {
  app_tabs <- c("Live Map", "Airports & Routes", "Autocorrelation", "Point Patterns", "Spatial Regression", "About")
  expect_true(all(home_sections$tab %in% app_tabs))
})
```

- [ ] **Step 2: Run to check it fails.** Expected: `could not find function "home_server"`.
- [ ] **Step 3: Implement `R/mod_home.R`.**
- [ ] **Step 4: Wire it into `app.R`.**
  - Give `page_navbar()` the argument `id = "main_nav"`.
  - Add `nav_panel("Home", icon = bs_icon("house"), home_ui("home"))` as the **first** panel, so the app opens on it.
  - In `server`, add `home_server("home", on_select = function(tab) nav_select("main_nav", tab))`.
- [ ] **Step 5: Run all tests and check by hand.** The app opens on Home. Each button jumps to its tab. Going back to Home and clicking the same button again still works.
- [ ] **Step 6: Commit** (`git commit -m "Add a Home page with shortcuts to each tab"`)

**Left for the design pass:** the final copy, the hero image or styling, and whether the filter sidebar should be hidden on Home (`page_navbar`'s sidebar shows on every tab).

---

### Task 12: About page, sidebar text, README

**Files:**
- Create: `R/mod_about.R` (move `about_ui` here from the placeholders and rewrite it)
- Modify: `app.R`, `README.md`; delete `R/mod_placeholders.R` once only `routes_ui` is left in it, and remove the Airports & Routes `nav_panel` unless stretch S1 is done.

- [x] **Step 1: Rewrite the About page.**
  - Data sources: OpenSky, the sample, OpenFlights, OurAirports, `spData::world`.
  - Methods: one paragraph each, naming the chapter and the R functions used.
  - Limitations: the existing ones plus:
    - Quadrats on the region's curved outline have unequal areas. The χ² test allows for this, but VTMR treats them as equal.
    - Regression is limited to Europe and World.
    - Each analysis is a single snapshot.
  - Remove the "About this demo" card.
- [x] **Step 2: Fix the sidebar text.** It becomes "Live data refreshes every 10 minutes. Filters apply to every tab; airport points ignore the airline, category and altitude filters." Also remove "(demo)" from the `app.R` header comment.
- [x] **Step 3: Update the README.** Change the status line (method tabs working), the package list, and the layout table (new `stats_*`, `mod_*` and lookup files). Add one paragraph on how to run each method.
- [x] **Step 4: Run all tests and open every tab.** Expected: all pass, and no tab mentions "demo", "coming soon" or "owner".
- [x] **Step 5: Commit** (`git commit -m "Finish the About page and README"`)

---

### Task 13: Bug bash

No new code unless something breaks; fix anything found with a test first.

- [ ] **Step 1: Run the matrix in sample mode (no credentials).** For each of Europe, North America, Southern Africa, East Asia and World, run each method tab with its defaults. Expected: a result, or one of the yellow messages above. Never a red Shiny error, and nothing in the R console except warnings.
- [ ] **Step 2: Run the extreme filters.** Untick every category; pick one small airline; turn on Airborne only with the "On ground" band only. Expected: messages, not errors.
- [ ] **Step 3: Check the timing.** Europe, 50 km hexes, permutation with 999 simulations. Expected: under 15 s, with the progress message showing.
- [ ] **Step 4: Repeat Step 1 in live mode** (credentials set). Expected: the badge reads Live, and the results differ from the sample.
- [ ] **Step 5: Test from a fresh clone.** Clone into a new folder on another group member's laptop and run `shiny::runApp()`. Expected: it runs with no setup beyond `install.packages()`.
- [ ] **Step 6: Commit the fixes and tag the version** (`git tag v1.0`).

---

## Stretch goals (only after Task 13)

Plan each of these properly before starting.

- **S1. Airports & Routes tab.** Add `get_flights_yesterday()` with a disk cache (spec §2.1, §2.5), `data-raw/capture_flights.R` (about 360 credits, saved to `data/sample/flights_sample.rds`), and `mod_routes.R` with great-circle lines (`sf::st_segmentize` needs `lwgeom`; either install it or interpolate the points by hand). Then add "Flights departing yesterday" back as a regression response.
- **S2. Manufacturer / type filter.** Trim the OpenSky aircraft database to `icao24`, `manufacturername` and `typecode` (spec §2.4), and add a sidebar picker.
- **S3. Freeze snapshot and source selector** (spec §2.5), for reproducible report figures.
- **S4. `renv`** lockfile (spec §4).
- **S5. Hosting** on shinyapps.io. No longer optional: we must hand in the published app as well as the repo. See `docs/shiny_deployment.md` for the plan (deploy by 24 Oct).
