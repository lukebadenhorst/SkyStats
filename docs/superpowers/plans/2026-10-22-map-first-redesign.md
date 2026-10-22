# Map-first Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the Shiny flights dashboard into a Plane Finder-style app: one full-screen light map shared by every tab, floating panels, plane icons, method results drawn on the map, a first-visit setup box, auto-run, and a Home page with a presentation tour.

**Architecture:** `app.R` owns one `leafletOutput("map")` filling the window. Each tab draws into its own Leaflet pane through a proxy on the root session, and JavaScript fades panes in and out. Two hidden navsets switch together: one in the left column for each method's settings panel, and one for the right-hand content (results cards, Home, About). A shared server helper, `method_runner()`, gives every method tab the same setup box, debounced auto-run and loading state. The planes are a custom canvas layer in `www/planes.js`.

**Tech Stack:** R 4.6.1, shiny, bslib (Bootstrap 5), leaflet (R package's bundled Leaflet 1.x), sf, testthat; plain JavaScript and CSS in `www/`.

**Spec:** `docs/superpowers/specs/2026-10-22-map-first-redesign-design.md`. Mockups (local only, open in a browser): `.superpowers/brainstorm/525-1792702796/content/` `planefinder-light.html`, `results-panel.html`, `setup-box.html`, `home-tour.html`. Copy their look and timings, not their code.

## Global Constraints

- It stays a Shiny app: "must be designed on RShiny". No React.
- Do not change any `R/stats_*.R` file, `R/regions.R`, `R/data_*.R` or `R/lookups.R`. Their tests must pass unchanged.
- Basemap: `providers$Esri.WorldGrayCanvas` (CARTO needs an API key).
- External scripts or fonts only from a CDN with a pinned version (Google Fonts allowed), or bundled in `www/`. Inter via `bslib::font_google("Inter", local = FALSE)`, falling back to `system-ui`.
- Colours: text and primary controls `#1c2430`; secondary text `#5b6573`, `#8a94a3`; accent `#1d6fd8`; live dot `#16a34a`. Map layers keep their existing colours (`lisa_colours`, viridis quadrat counts, RdBu residuals, `altitude_colours`).
- Panels: white at 94% opacity, `backdrop-filter: blur(6px)`, `1px solid rgba(28,36,48,.10)`, 12 px corners, shadow `0 1px 4px rgba(0,0,0,.06), 0 4px 14px rgba(0,0,0,.08)`.
- Motion: entrances fade and slide 8–12 px over 0.5–0.7 s with `cubic-bezier(.2,.7,.2,1)`, staggered 80–100 ms; numbers count up over 1.1–1.6 s; hover lifts 3–4 px. Under `prefers-reduced-motion: reduce`, no glide, no entrance slides, fades at most 150 ms.
- Avoid the "AI look": no purple/indigo-teal gradients, blurred colour blobs, or emoji as icons.
- Must fit and read at 1280 × 720 with browser zoom 125–150%.
- Auto-run debounce: 600 ms.
- The app opens on Home, in light mode.
- R tests: `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe" -e 'testthat::test_dir("tests/testthat")'`.
- Run the app (sample mode, from Bash): `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe" -e 'shiny::runApp(port = 4388, launch.browser = FALSE)'` in the background, then open http://127.0.0.1:4388. For live data prefix `R_ENVIRON_USER="C:/Users/lukeb/OneDrive/Documents/.Renviron"`. Never print or commit the credentials.
- Work on branch `map-redesign`. End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Glide on old data:** in sample mode the snapshot is days old. Planes must glide from the moment the data reached the browser, not from the snapshot time, and stop extrapolating after 15 minutes. Otherwise they fly off the map. (Task 7, manual check.)
2. **Nothing left after filtering** (every category unticked, or an airline with no aircraft in the region): the planes vanish, the Live Map card shows "-", method tabs show their yellow message, and the console shows no JavaScript errors. (Tasks 2, 4, 7.)
3. **Rapid changes:** dragging a slider or changing the region several times quickly runs the method once, and only the newest result is drawn. (Task 3 test.)
4. **Leaving a tab with the setup box open:** the box closes. Coming back before pressing Run reopens it. Coming back after Run shows the last result without re-running. (Task 3 test, plus a manual check.)
5. **Dark mode flipped on a method tab:** panels, plots, planes and legends all switch, and the map layer is not redrawn or re-run. (Task 9, manual check.)

---

## File map

| File | Responsibility |
|---|---|
| `R/app_tabs.R` (new) | The tab list and which regions each method accepts. Pure. |
| `R/summaries.R` (new) | Headline numbers, badge and short text for each method's result. Pure. |
| `R/map_shared.R` (new) | The shared map, its panes, the proxy on the root session, pane messages, flying to a region. |
| `R/mod_common.R` | Panel builders, results card, settings panel and setup box, region alert, and `method_runner()`. Keeps `alpha_input()`, `plot_palette()`, `use_plot_theme()`, `result_alert()`. Drops `method_tab_ui()`. |
| `R/mod_live.R` | Live Map stats card and expanded table; sends plane data. |
| `R/mod_autocorr.R`, `R/mod_quadrat.R`, `R/mod_regression.R` | Each split into `*_settings_ui()`, `*_results_ui()` and `*_server()`. They draw into their own pane. |
| `R/mod_home.R` (new) | Home hero, shortcut cards, tour steps, tour LISA. |
| `R/mod_about.R` | Same content, wrapped in a centred panel. |
| `app.R` | Theme, layout shell, tab switching, shared filters, map, data badge. |
| `www/app.css` (new) | All styling, animation and dark mode. |
| `www/app.js` (new) | Tab bar, folding panels, count-up, results expand, setup mode, busy state, map pane messages, region buttons. |
| `www/planes.js` (new) | The canvas plane layer. |
| `www/tour.js` (new) | The Home tour. |

---

### Task 1: Tab list, method regions and result summaries

**Files:**
- Create: `R/app_tabs.R`, `R/summaries.R`, `tests/testthat/test-app_tabs.R`, `tests/testthat/test-summaries.R`

**Interfaces:**
- Produces:
  - `app_tabs`: data.frame with columns `id`, `label`, `icon` (a bsicons name), `kind` (`"page"` or `"method"`). Rows in order: `home` "Home" `house` page; `live` "Live Map" `map` page; `autocorr` "Autocorrelation" `grid-3x3` method; `quadrat` "Point Patterns" `dot` method; `regression` "Spatial Regression" `graph-up` method; `about` "About" `info-circle` page.
  - `method_regions(method)` → character vector of region ids. `"autocorr"` and `"quadrat"`: the regions with a CRS (`regions$id[!is.na(regions$crs)]`). `"regression"`: `regions$id[regions$allow_regression]`. Any other value: `stop()`.
  - `default_method_region(current, method)` → `current` if it is in `method_regions(method)`, else `"europe"`.
  - `autocorr_summary(res, statistic, alpha)`, `quadrat_summary(res, alpha)`, `regression_summary(res)`. Each takes the `value` of a successful run (the list returned by `run_autocorr()`, by `run_quadrat()` plus the module's extras, or by `run_regression()`) and returns `list(label, value, digits, badge, tone, mini, text)`: `label` chr, `value` numeric, `digits` integer, `badge` chr, `tone` one of `"hot"`, `"cool"`, `"neutral"`, `"info"`, `mini` a named character vector of length 4, `text` chr (one or two sentences).

- [ ] **Step 1: Write the failing tests**

`tests/testthat/test-app_tabs.R`:

```r
test_that("the tab list has the six tabs in order", {
  expect_equal(app_tabs$id, c("home", "live", "autocorr", "quadrat", "regression", "about"))
  expect_equal(app_tabs$kind[app_tabs$id == "autocorr"], "method")
})

test_that("each method offers only the regions it accepts", {
  expect_equal(method_regions("autocorr"), c("europe", "north_america", "southern_africa", "east_asia"))
  expect_equal(method_regions("quadrat"), method_regions("autocorr"))
  expect_equal(method_regions("regression"), c("world", "europe"))
  expect_error(method_regions("live"))
})

test_that("the default region keeps an accepted region and falls back to Europe", {
  expect_equal(default_method_region("east_asia", "autocorr"), "east_asia")
  expect_equal(default_method_region("world", "autocorr"), "europe")
  expect_equal(default_method_region("world", "regression"), "world")
  expect_equal(default_method_region("north_america", "regression"), "europe")
})
```

`tests/testthat/test-summaries.R` builds small fake results by hand (no spatial work):

```r
lisa <- data.frame(cluster = factor(c("High-High", "Low-Low", "Not significant", "High-High")))
moran <- list(global = data.frame(statistic = "Moran's I", observed = 0.421, expectation = -0.005,
                                  variance = 0.001, z = 8.14, p_value = 1e-6), lisa = lisa)

test_that("autocorrelation summary: significant Moran's I reads as clustered", {
  s <- autocorr_summary(moran, "moran", 0.05)
  expect_equal(s$label, "Global Moran's I")
  expect_equal(s$value, 0.421)
  expect_equal(s$digits, 3L)
  expect_equal(s$badge, "Clustered")
  expect_equal(s$tone, "hot")
  expect_equal(unname(s$mini), c("8.14", "< 0.001", "4", "3"))
  expect_equal(names(s$mini), c("z-score", "p-value", "Hexes", "Significant"))
  expect_match(s$text, "2 High-High and 1 Low-Low")
})

test_that("autocorrelation summary: Global G and a non-significant result", {
  g <- moran
  g$global$statistic <- "Global G"
  expect_equal(autocorr_summary(g, "globalg", 0.05)$badge, "Hot spots")
  expect_equal(autocorr_summary(g, "globalg", 0.05)$label, "Global G")
  expect_equal(autocorr_summary(g, "globalg", 0.05)$digits, 4L)
  ns <- moran
  ns$global$p_value <- 0.4
  expect_equal(autocorr_summary(ns, "moran", 0.05)$badge, "No clear pattern")
  expect_equal(autocorr_summary(ns, "moran", 0.05)$tone, "neutral")
})

quad <- function(vtmr, p) list(
  chisq = data.frame(statistic = 120.5, df = 35, p_value = 0.001),
  vtmr = data.frame(m = 36, mean = 10, variance = 10 * vtmr, vtmr = vtmr, statistic = 35 * vtmr, df = 35, p_value = p)
)

test_that("quadrat summary reads the VTMR", {
  expect_equal(quadrat_summary(quad(3.4, 0.001), 0.05)$badge, "Clustered")
  expect_equal(quadrat_summary(quad(0.4, 0.001), 0.05)$badge, "Regular")
  expect_equal(quadrat_summary(quad(0.4, 0.001), 0.05)$tone, "cool")
  expect_equal(quadrat_summary(quad(1.1, 0.6), 0.05)$badge, "Random")
  s <- quadrat_summary(quad(3.4, 0.001), 0.05)
  expect_equal(s$label, "Variance-to-mean ratio")
  expect_equal(s$value, 3.4)
  expect_equal(names(s$mini), c("χ²", "χ² p-value", "VTMR p-value", "Quadrats"))
  expect_equal(unname(s$mini[4]), "36")
})

reg <- function(rec) list(
  recommendation = rec, rho = 0.312, rho_p_value = 0.004,
  resid_moran = data.frame(observed = 0.214, expectation = -0.03, variance = 0.01, z = 2.4, p_value = 0.008),
  aic = data.frame(model = c("OLS", "Spatial lag"), aic = c(101.23, 95.4))
)

test_that("regression summary shows rho and the recommended model", {
  s <- regression_summary(reg("Spatial lag"))
  expect_equal(s$label, "Spatial lag ρ")
  expect_equal(s$value, 0.312)
  expect_equal(s$badge, "Spatial lag model")
  expect_equal(s$tone, "info")
  expect_equal(unname(s$mini), c("0.004", "0.214", "101.23", "95.40"))
  expect_equal(names(s$mini), c("ρ p-value", "Residual Moran's I", "AIC (OLS)", "AIC (lag)"))
  expect_equal(regression_summary(reg("OLS"))$badge, "OLS is enough")
  expect_equal(regression_summary(reg("OLS"))$tone, "neutral")
  expect_equal(regression_summary(reg("Spatial error"))$badge, "Spatial error model")
})
```

- [ ] **Step 2: Run the tests and check they fail**

Run: `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe" -e 'testthat::test_dir("tests/testthat", filter = "app_tabs|summaries")'`
Expected: FAIL, `object 'app_tabs' not found`.

- [ ] **Step 3: Implement `R/app_tabs.R` and `R/summaries.R`**

Wording for `text` (copy exactly; a two-sentence string where shown):
- autocorr, significant, Moran or Geary: `"Busy hexes sit next to other busy hexes, so air traffic is clustered."`; Global G: `"The busiest hexes sit together in hot spots."`; not significant: `"Neighbouring hexes are no more alike than chance would give."`. Then always append `" LISA finds <n HH> High-High and <n LL> Low-Low hexes."`
- autocorr `label`: the statistic name, prefixed with `"Global "` unless it already starts with `"Global"`. `digits` 4 for Global G, else 3. `mini`: z with `%.2f`, `format_p()`, `nrow(lisa)`, count of clusters other than "Not significant".
- quadrat: Random `"The points are spread about as evenly as chance would give (consistent with CSR)."`, Regular `"The points are more evenly spaced than chance would give."`, Clustered `"The points bunch together more than chance would give."`. Badge rule as `quadrat_text()`: `vtmr$p_value >= alpha` Random/neutral; else `vtmr < 1` Regular/cool; else Clustered/hot. `digits` 2. `mini`: χ² `%.1f`, `format_p(chisq$p_value)`, `format_p(vtmr$p_value)`, `m`.
- regression: OLS `"The OLS residuals show no spatial pattern, so plain OLS is enough."`, lag `"A country's traffic depends on its neighbours' traffic, so the LM tests point to the spatial lag model."`, error `"The LM tests point to a spatial error model. The lag model is shown for comparison."`. Badges: OLS `"OLS is enough"`/neutral; lag `"Spatial lag model"`/info; error `"Spatial error model"`/info. `digits` 3. `mini`: `format_p(rho_p_value)`, residual Moran's I `%.3f`, both AICs `%.2f`.

The spec's regression headline also lists "residual Moran's I before and after". "After" (Moran's I of the lag residuals) is not returned by `run_regression()`, and the stats files are frozen, so the card shows the OLS residual Moran's I only.

- [ ] **Step 4: Run the full test suite**

Run the R tests command. Expected: all pass (204 old + the new ones).

- [ ] **Step 5: Commit**

```bash
git add R/app_tabs.R R/summaries.R tests/testthat/test-app_tabs.R tests/testthat/test-summaries.R
git commit -m "Add the tab list, method regions and result summaries"
```

---

### Task 2: Layout shell, shared map and Live Map card

After this task the app has the new look and layout. The method tabs still use their old card layout and their own maps, shown inside a temporary scrolling panel, so everything keeps working.

**Files:**
- Create: `R/map_shared.R`, `www/app.css`, `www/app.js`
- Modify: `app.R`, `R/mod_live.R`, `R/mod_about.R`, `R/mod_common.R`

**Interfaces:**
- Consumes: `app_tabs` (Task 1).
- Produces:
  - `map_panes`: named integer vector of pane z-indexes: `autocorr = 410L, quadrat = 411L, regression = 412L, tour = 413L, planes = 450L`.
  - `shared_map()` → a leaflet widget: `Esri.WorldGrayCanvas` tiles, `leafletOptions(zoomControl = FALSE, worldCopyJump = TRUE, zoomSnap = 0.25, zoomDelta = 0.5)`, a zoom control at bottom right (`htmlwidgets::onRender` adding `L.control.zoom({position: "bottomright"})`), one `addMapPane()` per `map_panes` entry, and the view `setView(10, 25, 2)`.
  - `shared_map_proxy(session)` → `leaflet::leafletProxy("map", session = session$rootScope())`. Works from inside any module.
  - `set_pane(session, pane, state)`: sends the custom message `"map-pane"` with `list(pane = pane, state = state)`; `state` is `"shown"`, `"hidden"` or `"busy"`.
  - `fly_to_region(proxy, region_id)`: World → `flyTo(proxy, 10, 25, 2)`; any other region → `flyToBounds()` on its bbox.
  - `float_panel(..., class = NULL, id = NULL)`: a `div` with class `float-panel` plus `class`.
  - `fold_panel(title, ..., open = TRUE, tag = NULL)`: a `float_panel` with a clickable header (title, optional small tag, chevron) and a body that folds. Folding is client-side (`app.js`).
  - Tab switching: buttons and cards with `data-tab="<id>"` anywhere on the page switch tabs. `app.js` sends `Shiny.setInputValue("tab_click", id, {priority: "event"})`; the server calls `nav_select("tab", id)` and `nav_select("settings_nav", id)`, then sends `"tab-changed"` with `list(tab = id)`. `app.js` moves the tab bar highlight and sets `body` classes `tab-<id>`.
  - App-level reactive `active_tab()` in `app.R` (the current tab id), passed to modules in later tasks as `active = reactive(active_tab() == "<id>")`.
  - `mod_live_server(id, aircraft)` (drops `region_id`; flying to the region moves to `app.R`).

- [ ] **Step 1: Write `R/map_shared.R`**

Add a test `tests/testthat/test-map_shared.R`: `expect_equal(names(map_panes), c("autocorr", "quadrat", "regression", "tour", "planes"))`, and `shared_map()` returns an object of class `"leaflet"`. Run it, see it fail, implement, see it pass. (`R/map_shared.R` is sourced by the test helper because its name does not start with `mod_`. The helper does not attach leaflet, so use `leaflet::` prefixes in this file.)

- [ ] **Step 2: Rewrite `app.R` as the shell**

- `page(theme = theme, ...)` (not `page_navbar`), with `tags$head()` linking `app.css` and `app.js`.
- The theme: `bs_theme(version = 5, primary = "#1c2430", base_font = font_google("Inter", local = FALSE), "border-radius" = "8px")`. Move the existing dark-mode Leaflet rules into `app.css`.
- `div(id = "map-wrap", leafletOutput("map", height = "100%"))` fixed full-window behind everything; `output$map <- renderLeaflet(shared_map())`.
- Top bar `div(class = "top-bar")`: brand panel (plane icon + "Global Flights"); tab bar panel with one `tags$button(class = "tab-btn", "data-tab" = id, label)` per `app_tabs` row plus a `span(class = "tab-slider")`; on the right, `uiOutput("source_badge")` restyled as a panel (pulsing green dot when live), the Refresh button (icon-only, tooltip "Refresh data"), and `input_dark_mode(id = "dark_mode", mode = "light")`.
- Left column `div(class = "left-col")`: `fold_panel("Filters", ...)` holding the existing filter inputs with the same ids, then `navset_hidden(id = "settings_nav", ...)` with one `nav_panel_hidden(value = id)` per tab (empty for now).
- Content `navset_hidden(id = "tab", selected = "home", ...)`: `home` a placeholder `float_panel(class = "center-panel", h1("Global Flights"))` (Task 8 replaces it); `live` `mod_live_ui("live")`; `autocorr`, `quadrat`, `regression` each the old UI inside `float_panel(class = "legacy-panel", ...)`; `about` `about_ui("about")`.
- Checkbox filters render as chips: wrap them in `div(class = "chips", ...)`. CSS styles the Bootstrap `.form-check` markup with `:has(input:checked)`; no custom inputs.
- Server: keep the snapshot, refresh, warning, `states`, airline picker and `aircraft` code. Add `active_tab <- reactiveVal("home")` and `observeEvent(input$tab_click, ...)` as in Interfaces, which also sets `active_tab()`. Add an observer on `active_tab()` that calls `set_pane(session, "planes", "shown")` on Home and Live Map and `"hidden"` elsewhere, and adds or removes the altitude legend the same way. Add one observer that calls `fly_to_region(shared_map_proxy(session), input$region)` when the region changes or a method tab opens. Replace the badge `span`s with the new badge markup (classes `badge-live`, `badge-cache`, `badge-sample`; keep the same wording).

- [ ] **Step 3: Live Map card and temporary planes**

- `mod_live_ui(id)` returns `float_panel(class = "results-card", ...)`: "Aircraft in view" (`textOutput(ns("n_aircraft"))` with class `count-up`), "Airborne" (percentage plus a thin bar whose width the server sets through a `uiOutput`), "Top origin countries" (the existing list); a **Show all aircraft** button; and a full section holding the existing `DT::DTOutput(ns("table"))`.
- `mod_live_server()` keeps its outputs, drops `renderLeaflet` and the region observer, and draws the aircraft with the existing `addCircleMarkers()` call on `shared_map_proxy(session)`, with `options = pathOptions(pane = "planes")` and `group = "aircraft"`. Task 7 replaces these with plane icons. The altitude legend (`addLegend(..., layerId = "altitude-legend")`, bottom right) is added and removed by the `app.R` tab observer.
- Legends: the spec puts "the map legend for the current layer" at the bottom right, and also puts the legend in each method's short card. To avoid showing it twice, only the Live Map's altitude legend sits at the bottom right; method legends live in the results card (Tasks 4–6).

- [ ] **Step 4: About page**

Wrap the existing `about_ui()` cards in `float_panel(class = "center-panel about-panel", ...)`, scrollable. `body.tab-about #map-wrap` gets `filter: blur(3px)` and a dim overlay.

- [ ] **Step 5: Write `www/app.css` and `www/app.js` for the shell**

Copy the look from `planefinder-light.html`: top bar, tab bar with the sliding dark highlight, badge with the pulsing dot, folding panels, chips, slim range sliders, select styling, the results card and its expand animation (`grid-template-rows` 0fr → 1fr; the card widens from 270 px to `min(640px, 100vw - 300px)`), entrance animations for panels shown by a tab switch (CSS animation on `.tab-pane.active .float-panel`), and the count-up (`app.js` watches elements with class `count-up` through Shiny's `shiny:value` event and animates from the old to the new number, keeping `data-digits` decimal places and any `%` suffix). The left column and the results card each scroll on their own when taller than the window. No ancestor of the left column may have a `transform` or `filter` (Task 3's setup box uses `position: fixed` inside it).

- [ ] **Step 6: Run the tests and the app**

Run the R tests command. Expected: all pass. The module tests for the method tabs still pass because their servers are unchanged.

Start the app (sample mode) and check in Chrome at 1280 × 720 and at 150% zoom:
- The map fills the window; the panels float; the tabs switch with the sliding highlight; the badge reads "Sample snapshot".
- Live Map: the dots show; the card counts up; "Show all aircraft" expands to the table and collapses again.
- Untick every category: the dots disappear, the count shows 0 and "Airborne" shows "-". The browser console has no errors. *(Review Focus 2.)*
- The three method tabs still run with their old layout inside the scrolling panel. About shows over the blurred map.

- [ ] **Step 7: Commit**

```bash
git add app.R R/map_shared.R R/mod_live.R R/mod_about.R R/mod_common.R www/app.css www/app.js tests/testthat/test-map_shared.R
git commit -m "Build the map-first layout shell and the Live Map card"
```

---

### Task 3: Settings panel, setup box, results card and the method runner

**Files:**
- Modify: `R/mod_common.R`, `www/app.css`, `www/app.js`, `app.R`
- Test: `tests/testthat/test-mod_common.R`

**Interfaces:**
- Consumes: `method_regions()`, `default_method_region()` (Task 1); `float_panel()`, `shared_map_proxy()`, `set_pane()`, `fly_to_region()` (Task 2).
- Produces (all in `R/mod_common.R`):
  - `setting(input, help)`: one settings row: the input, then `p(class = "setting-help", help)`. The help line shows only in setup mode.
  - `settings_panel(ns, method, title, chapter, question, intro, fields)`: `float_panel(id = ns("settings"), class = "settings-panel", ...)` containing:
    - setup-only parts: the chapter tag and title, `h3(question)`, `p(intro)`, a region row `setting(selectInput(ns("setup_region"), "Region", choices = region_choices()[region_choices() %in% method_regions(method)]), "<help>")`, and the button `actionButton(ns("setup_run"), "Run analysis", class = "btn-run")`;
    - always: the `fields` (a tagList of `setting()` rows);
    - panel-only: the header "<title> settings" with the chapter tag, and a link `tags$a(class = "guide-link", "Settings guide ›")`.
    Region help text: `"Each region gets its own map projection that keeps areas fair. World is not offered because no single projection can do that for the whole globe."` For regression use: `"Regression compares countries, so it needs at least 15 of them. Only Europe and the whole World have enough."`
  - `results_card(ns, full)`: `float_panel(id = ns("card"), class = "results-card", uiOutput(ns("short")), actionButton(ns("more"), "Show all results", class = "btn-more"), div(class = "results-full", full))`. Expanding is client-side.
  - `summary_ui(s, legend = NULL)`: renders a summary list from Task 1: the small label, the big number (`span(class = "count-up", "data-digits" = s$digits, format(round(s$value, s$digits), nsmall = s$digits))`), a badge `span(class = paste("badge-pill", paste0("tone-", s$tone)), s$badge)`, a 2 × 2 grid from `s$mini`, `p(s$text)`, and `legend`.
  - `legend_ui(colours, labels, title = NULL)`: small colour swatches with labels. For continuous scales, pass the binned colours and their labels.
  - `region_alert(res, method)`: `NULL` when `res$ok`. Otherwise the yellow alert with `res$message`. When `isTRUE(res$region_refused)`, it adds one button per accepted region: `tags$button(class = "region-btn", "data-region" = id, label)`. `app.js` sends `Shiny.setInputValue("region_pick", id, {priority: "event"})`, and `app.R` calls `updateSelectInput(session, "region", selected = id)`.
  - `method_runner(input, session, method, active, region_id, params, compute)` → a reactive returning a `run_safely()`-style list (`ok`, `value` or `message`) plus `region_refused` (logical). Arguments: `method` (`"autocorr"`, `"quadrat"` or `"regression"`), `active` (reactive logical), `region_id` (reactive), `params` (reactive list of the method's own inputs), `compute` (`function(p, region)` returning a `run_safely()` result).

Behaviour of `method_runner()`:
1. `done <- reactiveVal(FALSE)`.
2. When `active()` becomes TRUE: if `!done()`, update `setup_region` to `default_method_region(region_id(), method)` and send the custom message `"setup"` with `list(id = session$ns("settings"), open = TRUE)`. When `active()` becomes FALSE, send `"setup"` with `open = FALSE`.
3. `observeEvent(input$setup_run)`: `updateSelectInput(session$rootScope(), "region", selected = input$setup_region)`, `done(TRUE)`, send `"setup"` with `open = FALSE`.
4. `trigger <- debounce(reactive(list(done(), params(), region_id())), 600)`.
5. The returned reactive: `req(done())`, reads `trigger()`, sends `set_pane(session, method, "busy")`, runs `compute(params(), region_id())`, sets `region_refused <- !(region_id() %in% method_regions(method))`, then sends `set_pane()` `"shown"` if `ok`, else `"hidden"`. It is a plain lazy `reactive()`, so it computes only when an active observer reads it, and keeps its last value while nothing it depends on changes.
6. Panes: when `active()` becomes FALSE, `set_pane(session, method, "hidden")`. When it becomes TRUE and `done()`, `"shown"`.

Each module reads the result only inside observers and outputs that start with `req(active())`. That is what keeps inactive tabs from running.

- [ ] **Step 1: Write the failing tests** (append to `tests/testthat/test-mod_common.R`)

A test module wraps the runner, counts calls to `compute`, and reads the result only while active:

```r
runner_test_server <- function(id, active, region, calls) {
  moduleServer(id, function(input, output, session) {
    res <- method_runner(
      input, session, "autocorr", active, region,
      params = reactive(list(n = input$n)),
      compute = function(p, region) { calls(calls() + 1); run_safely(p$n * 2) }
    )
    observe({ req(active()); res() })
    session$userData$res <- res
  })
}

test_that("the runner waits for the setup box, then debounces changes", {
  calls <- reactiveVal(0)
  testServer(runner_test_server, args = list(active = reactive(TRUE), region = reactive("europe"), calls = calls), {
    session$setInputs(n = 1)
    session$elapse(1000)
    expect_equal(calls(), 0)              # no run before Run analysis
    session$setInputs(setup_region = "europe", setup_run = 1)
    session$elapse(700)
    expect_equal(calls(), 1)
    expect_equal(session$userData$res()$value, 2)
    session$setInputs(n = 2); session$elapse(200)
    session$setInputs(n = 3); session$elapse(200)
    session$setInputs(n = 4); session$elapse(700)
    expect_equal(calls(), 2)              # one run for the burst (Review Focus 3)
    expect_equal(session$userData$res()$value, 8)
  })
})

test_that("an inactive tab does not run, and a refused region is flagged", {
  calls <- reactiveVal(0)
  active <- reactiveVal(TRUE)
  region <- reactiveVal("world")
  testServer(runner_test_server, args = list(active = active, region = region, calls = calls), {
    session$setInputs(n = 1, setup_region = "europe", setup_run = 1)
    session$elapse(700)
    expect_true(session$userData$res()$region_refused)   # region() is still "world" in the mock
    n_before <- calls()
    active(FALSE)
    session$setInputs(n = 5); session$elapse(700)
    expect_equal(calls(), n_before)       # nothing ran while inactive (Review Focus 4)
  })
})
```

If `session$rootScope()` or `leafletProxy()` cannot be used inside `testServer`, guard those calls in the runner with a small helper that does nothing when the session is a `MockShinySession`, and say so in a comment.

- [ ] **Step 2: Run them and check they fail**

Run: `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe" -e 'testthat::test_dir("tests/testthat", filter = "mod_common")'`. Expected: FAIL, `could not find function "method_runner"`.

- [ ] **Step 3: Implement the R pieces** listed under Interfaces, and the `region_pick` observer in `app.R`.

- [ ] **Step 4: Implement setup mode, busy state and panes in `www/app.css` and `www/app.js`**

- `"setup"` message: toggle class `setup-mode` on the element with that id, and `setup-open` on `body`. In setup mode the settings panel is `position: fixed`, centred, 600 px wide (max `100vw - 32px`), `max-height: calc(100vh - 90px)` with an inner scroll, and shows `.setup-only` parts and `.setting-help`. Outside setup mode those are hidden and `.panel-only` parts show. `body.setup-open` blurs `#map-wrap` (`blur(3px) saturate(.8)`) and shows a dim overlay. Opening and closing animate as in `setup-box.html`. Escape and clicking the overlay close the box only when the tab has already run (`app.js` tracks this per panel; it is set when the panel's Run button is clicked).
- `.guide-link` click: open setup mode again, client-side only.
- Results card: `.btn-more` toggles class `expanded` on its card and swaps its label between "Show all results" and "Show less". On the Live Map card the labels are "Show all aircraft" and "Show less".
- `"map-pane"` message: find the map with `HTMLWidgets.find("#map").getMap()`, get the pane with `map.getPane(pane)`, and set a class: `pane-hidden` (opacity 0, `pointer-events: none`), `pane-busy` (opacity .35), or none. The pane transition is `opacity .6s`.
- Busy also shows a thin animated progress line along the top of the method's results card. Find the card by the pane name: `#<method>-card`.

- [ ] **Step 5: Run the full test suite.** Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add R/mod_common.R app.R www/app.css www/app.js tests/testthat/test-mod_common.R
git commit -m "Add the settings panel, setup box, results card and method runner"
```

---

### Task 4: Autocorrelation tab on the shared map

**Files:**
- Modify: `R/mod_autocorr.R`, `app.R`, `tests/testthat/test-mod_autocorr.R`

**Interfaces:**
- Consumes: `settings_panel()`, `setting()`, `results_card()`, `summary_ui()`, `legend_ui()`, `region_alert()`, `method_runner()` (Task 3); `autocorr_summary()` (Task 1); `shared_map_proxy()` (Task 2).
- Produces:
  - `autocorr_settings_ui(id)`: `settings_panel(ns, "autocorr", "Autocorrelation", "Ch 4", question = "Do busy areas sit next to other busy areas?", intro = "We cover the region in hexagons, count the aircraft in each, and test whether neighbouring hexes have similar counts.", fields = ...)`. The fields are the existing inputs with the same ids and conditions, each wrapped in `setting()`, with help lines in plain words. Use `setup-box.html` as the first draft; Luke rewords them later. Short text choices become segmented controls through CSS (class `seg` on the radio group).
  - `autocorr_results_ui(id)`: `results_card(ns, full = ...)` where `full` holds, in order, the full interpretation, the global test table and setup note, the Moran scatterplot, and the strongest clusters table. The card's id comes out as `"autocorr-card"` (`ns("card")` with module id `"autocorr"`), which is what Task 3's busy state looks for. Module ids must therefore equal the method names.
  - `autocorr_server(id, aircraft, region_id, active)`; inside, `result <- method_runner(...)` (same name as before, so the tests can read `result()`).

- [ ] **Step 1: Update the tests first** in `tests/testthat/test-mod_autocorr.R`: pass `active = reactive(TRUE)`, replace `run = 1` with `setup_region = "europe", setup_run = 1` followed by `session$elapse(700)`, and replace the second run with changing the region then `session$elapse(700)`. Keep every existing expectation. Add one assertion: `expect_true(result()$region_refused)` after switching to World.

- [ ] **Step 2: Run them and check they fail.** Expected: FAIL (unused argument `active`).

- [ ] **Step 3: Rewrite the module.**
- `compute` holds the body of today's `run_safely({...})` block, reading inputs from `p` and the region from the `region` argument. Drop `withProgress()` and `bindEvent(input$run)`.
- `output$short`: `req(active())`. If the result is not ok, `region_alert(res, "autocorr")`. Otherwise `summary_ui(autocorr_summary(value, input$statistic, as.numeric(input$alpha)), legend_ui(lisa_colours, names(lisa_colours)))`.
- Keep the other outputs (`interpretation`, `global`, `setup`, `scatter`, `top`), each reading the ok result after `req(active())`.
- Replace `output$map` with an observer: `req(active())`, read the result, then `shared_map_proxy(session) |> clearGroup("autocorr")`. If ok, add the same polygons and popups with `options = pathOptions(pane = "autocorr")` and `group = "autocorr"`. No `addLegend()`: the legend is in the card.
- In `app.R`: `autocorr_settings_ui("autocorr")` goes in the `settings_nav` panel `autocorr`; `autocorr_results_ui("autocorr")` replaces the legacy panel; the server call passes `active = reactive(active_tab() == "autocorr")`.

- [ ] **Step 4: Run the full test suite.** Expected: all pass.

- [ ] **Step 5: Check in the app** (sample mode, 1280 × 720):
- First visit: the setup box opens over the blurred map, with Region preselected to Europe (the filter is on World). Press Run: the box closes, the map flies to Europe, the hexes fade in, and the card counts up with the right badge.
- Drag the hex-size slider: one re-run, during which the layer dims and the progress line shows.
- Switch to Live Map and back: no box, the same result straight away, and the R console shows no re-run.
- Open the tab, then switch away before pressing Run, then return: the box reopens. *(Review Focus 4.)*
- Set the region filter to World on this tab: the yellow message shows with four region buttons, and the layer fades out. A button switches the region and the result comes back.
- "Settings guide ›" reopens the box with the current values.

- [ ] **Step 6: Commit**

```bash
git add R/mod_autocorr.R app.R tests/testthat/test-mod_autocorr.R
git commit -m "Move the Autocorrelation tab onto the shared map"
```

---

### Task 5: Point Patterns tab on the shared map

Same pattern as Task 4.

**Files:** Modify `R/mod_quadrat.R`, `app.R`, `tests/testthat/test-mod_quadrat.R`

**Interfaces:**
- Produces: `quadrat_settings_ui(id)` (question `"Are the points spread at random?"`; intro `"We lay a grid of equal squares (quadrats) over the region, count the points in each, and compare the counts with what pure chance would give."`), `quadrat_results_ui(id)` (card id `"quadrat-card"`; `full` = full interpretation, χ² table, VTMR table, the setup note, the histogram), `quadrat_server(id, aircraft, region_id, airports, active)`.
- Layer: the quadrat tiles, the study-rectangle outline, the points and the count labels, all with `pane = "quadrat"` and `group = "quadrat"`. Labels use `addLabelOnlyMarkers(..., options = markerOptions(pane = "quadrat"))`. Legend in the card: `legend_ui()` with five viridis colours, labelled from the minimum to the maximum count.
- Card: `summary_ui(quadrat_summary(value, as.numeric(input$alpha)), legend)`.

- [ ] **Step 1: Update `tests/testthat/test-mod_quadrat.R`** the same way as Task 4, Step 1 (`active`, `setup_run`, `session$elapse(700)`). Keep all expectations. `poisson_bins` tests are unchanged.
- [ ] **Step 2: Run them and check they fail.**
- [ ] **Step 3: Rewrite the module and wire it in `app.R`.**
- [ ] **Step 4: Run the full test suite.** Expected: all pass.
- [ ] **Step 5: Check in the app:** the setup box; switching between aircraft and airports re-runs once; 15 × 15 quadrats gives the yellow "fewer than 5" message and hides the layer; the count labels fade with the pane.
- [ ] **Step 6: Commit** — `git commit -m "Move the Point Patterns tab onto the shared map"`

---

### Task 6: Spatial Regression tab on the shared map

**Files:** Modify `R/mod_regression.R`, `app.R`, `tests/testthat/test-mod_regression.R`

**Interfaces:**
- Produces: `regression_settings_ui(id)` (question `"What explains how many aircraft are over each country?"`; intro `"We model each country's aircraft count from its population, wealth, size and airports, then check whether neighbouring countries affect each other."`), `regression_results_ui(id)` (card id `"regression-card"`; `full` = interpretation and isolates note, steps 1–4 as today, and the residual radio buttons `resid`), `regression_server(id, aircraft, region_id, airports, active)`.
- Layer: country polygons coloured by the chosen residual, `pane = "regression"`, `group = "regression"`, with the same bins and labels as today. The `resid` radio buttons sit in the expanded card and also show in the short card above the legend. Changing them redraws the layer only; it does not re-run the model, so `resid` is not part of `params`.
- Card: `summary_ui(regression_summary(value), legend)`, with the RdBu bins as the legend.

- [ ] **Step 1: Update `tests/testthat/test-mod_regression.R`** as in Task 4, Step 1. The North America check becomes: change the region, `session$elapse(700)`, then expect the same message and `region_refused` TRUE.
- [ ] **Step 2: Run them and check they fail.**
- [ ] **Step 3: Rewrite the module and wire it in `app.R`.** Delete `method_tab_ui()` from `R/mod_common.R` and the `legacy-panel` CSS, since nothing uses them now.
- [ ] **Step 4: Run the full test suite.** Expected: all pass.
- [ ] **Step 5: Check in the app:** the box offers only Europe and World; switching the residual type changes colours without the progress line; queen weights show the isolates note in the expanded card.
- [ ] **Step 6: Commit** — `git commit -m "Move the Spatial Regression tab onto the shared map"`

---

### Task 7: Plane icons on a canvas layer, with glide

**Files:**
- Create: `www/planes.js`
- Modify: `R/mod_live.R`, `app.R` (script tag), `www/app.css`

**Interfaces:**
- Consumes: the `planes` pane (Task 2); `aircraft_popup()` and `altitude_colours` (`R/mod_live.R`).
- Produces:
  - Custom message `"planes-data"` sent by `mod_live_server()` whenever `aircraft()` changes: `list(lon, lat, hdg, spd, band, ground, callsign, popup, palette = list(light = as.list(altitude_colours), dark = as.list(altitude_colours_dark)))`. `hdg` is `true_track` (degrees, NA allowed), `spd` is `velocity` (m/s, NA allowed), `band` the altitude band label, `ground` the logical `on_ground`, `popup` from `aircraft_popup()`. Send the palette with every message; it is small.
  - `altitude_colours_dark` in `R/mod_live.R`: `c("On ground" = "#c3c8cd", "< 3,000 m" = "#f6b57f", "3,000-9,000 m" = "#4fd1c0", "> 9,000 m" = "#8f91ff", "Unknown" = "#e0e0e0")`.
  - `www/planes.js`: a Leaflet layer (`L.Layer` subclass) drawing on one `<canvas>` inside the `planes` pane, so the pane fades work as for the other layers.

Behaviour:
- Glyph: the plane path from the mockups (`M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5z`, a 24 × 24 viewBox, pointing up) as a `Path2D`, drawn 14 px wide (16 px from zoom 6 up), rotated by `hdg` (0 = north, clockwise), filled with the band colour for the current theme, with a light drop shadow. Aircraft with no heading are drawn pointing north.
- Theme: read `document.documentElement.getAttribute("data-bs-theme")` and watch it with a `MutationObserver`, then redraw with the matching palette.
- **Glide:** remember `t0 = performance.now()` when a message arrives (not the snapshot time). Each frame, for airborne aircraft with a speed and heading, `dt = min((now - t0) / 1000, 900)` seconds; `dlat = spd * dt * cos(h) / 111320`; `dlon = spd * dt * sin(h) / (111320 * cos(lat))`. Aircraft on the ground do not move. Redraw with `requestAnimationFrame`, at most 30 times a second, drawing only aircraft inside the current view (plus a 20 px margin). No glide under `prefers-reduced-motion`.
- New data: replace the arrays, reset `t0`, and fade the canvas in over 0.5 s on the first message only.
- Hover: on `mousemove` over the map, find the nearest drawn plane within 8 px and show a dark tooltip (class `plane-tip`): callsign, then the altitude and speed. Click opens a Leaflet popup with that aircraft's `popup` HTML. Hit-testing is ignored while the `planes` pane is hidden.
- Resize, zoom and pan: reposition and resize the canvas on Leaflet's `move`, `zoom` and `resize` events.

- [ ] **Step 1: Write `www/planes.js`** and load it in `app.R` after `app.js`.
- [ ] **Step 2: Change `mod_live_server()`** to send `"planes-data"` instead of adding circle markers, and delete the `addCircleMarkers()` code.
- [ ] **Step 3: Run the full test suite.** Expected: all pass (nothing here has R tests; `aircraft_popup()` is unchanged).
- [ ] **Step 4: Check in the app, in sample mode and then live:**
  - Planes point the way they fly, coloured by altitude, and glide smoothly. With the full world (~10,000 aircraft) panning and zooming stay smooth. If the frame rate drops below about 30 fps, check in Chrome's performance panel that only in-view planes are drawn.
  - Sample mode: after 2 minutes the planes have moved only a little (seconds of flight, not days). *(Review Focus 1.)*
  - Hover shows the tooltip and click shows the popup. On a method tab the planes are hidden and hovering where they were shows nothing.
  - Untick every category: the canvas is empty and the console has no errors. *(Review Focus 2.)*
- [ ] **Step 5: Commit** — `git commit -m "Draw aircraft as gliding plane icons on a canvas layer"`

---

### Task 8: Home page and tour

**Files:**
- Create: `R/mod_home.R`, `www/tour.js`, `tests/testthat/test-mod_home.R`
- Modify: `app.R`, `www/app.css`

**Interfaces:**
- Consumes: `app_tabs` (Task 1); `shared_map_proxy()`, `set_pane()` (Task 2); `hex_counts()`, `run_autocorr()`, `to_region_sf()`, `region_window()`, `lisa_colours` (existing).
- Produces:
  - `tour_steps`: a list of six lists, each with `title` (chr), `points` (chr vector, 2–3 items) and `action`, one of `"world"`, `"badge"`, `"pipeline"`, `"lisa"`, `"regions"`, `"coverage"`, in that order. Use the text from `home-tour.html` as the placeholder; Luke rewrites it later, so keep it in this one list.
  - `home_ui(id)`: the haze overlay; the hero (`h1("Global Flights")`, a sentence with `textOutput(ns("count"), inline = TRUE)` (class `count-up`) aircraft in the sky, two buttons: `actionButton(ns("tour_start"), "How this app works", class = "btn-dark tour-start")` (`tour.js` listens for clicks on `.tour-start`; the server sees the same click as `input$tour_start`) and `tags$button("data-tab" = "live", "Open the live map")`); four shortcut cards with `data-tab` set to `live`, `autocorr`, `quadrat` and `regression`, each with the chapter tag and a one-line blurb; the tour card; and `tags$script(type = "application/json", id = "tour-data", jsonlite::toJSON(list(steps = tour_steps, regions = <bbox per method region with its label and crs>), auto_unbox = TRUE))`.
  - `home_server(id, aircraft)`: `output$count` is the number of aircraft. On the first `input$tour_start`, it computes a LISA layer for Europe with the Autocorrelation defaults (150 km hexes, log, queen, W, Moran's I, analytic, α = 0.05) from `aircraft()` and draws it into pane `"tour"` (group `"tour"`), with `set_pane(session, "tour", "hidden")` first. On failure it draws nothing.
  - `www/tour.js`: reads `#tour-data` and drives the steps.

Tour behaviour (copy from `home-tour.html`): the start button adds `body.touring` (the haze and hero fade out, the tour card rises in the bottom-left). Next, Back and the arrow keys move between steps; Escape ends the tour. Dots show progress, and the last step's button reads "Start exploring". Actions: `world` flies to `[30, 10]` zoom 2; `badge` adds a highlight ring to the data badge; `pipeline` lights Fetch › Clean › Filter › Project › Analyse one by one, 350 ms apart, inside the card; `lisa` shows pane `tour` and flies to Europe; `regions` cycles through the four method regions every 2.6 s, outlining each with a dashed rectangle and a label "<Region> · <CRS>"; `coverage` flies to `[0, 20]` zoom 3. Leaving a step undoes what it set (the ring, the rectangle and its timer, the `tour` pane). Leaving the Home tab ends the tour.

- [ ] **Step 1: Write the failing test** `tests/testthat/test-mod_home.R`:

```r
library(shiny)
library(bslib)
for (f in c("mod_common.R", "mod_home.R")) source(file.path(root, "R", f))

test_that("the tour has six steps in speaking order", {
  expect_length(tour_steps, 6)
  expect_equal(vapply(tour_steps, `[[`, "", "action"), c("world", "badge", "pipeline", "lisa", "regions", "coverage"))
  for (s in tour_steps) {
    expect_true(nzchar(s$title))
    expect_gte(length(s$points), 2)
  }
})

test_that("the home page links every tab it shows to a real tab", {
  html <- as.character(home_ui("home"))
  targets <- regmatches(html, gregexpr('data-tab="[a-z]+"', html))[[1]]
  expect_true(all(sub('data-tab="([a-z]+)"', "\\1", targets) %in% app_tabs$id))
  expect_match(html, 'id="tour-data"')
})
```

- [ ] **Step 2: Run it and check it fails.**
- [ ] **Step 3: Implement `R/mod_home.R`, `www/tour.js` and the CSS; put `home_ui("home")` in the `home` panel and call `home_server("home", aircraft)` in `app.R`.** The planes pane is shown on Home as on the Live Map.
- [ ] **Step 4: Run the full test suite.** Expected: all pass.
- [ ] **Step 5: Check in the app** at 1280 × 720 and 150% zoom: the hero and cards fit without scrolling; the count counts up; the cards switch tabs; the whole tour works with the arrow keys; step 4 shows real hexes (or nothing if the run failed); Escape and leaving Home clean up.
- [ ] **Step 6: Commit** — `git commit -m "Add the Home page and the presentation tour"`

---

### Task 9: Dark mode, reduced motion, projector check and docs

**Files:**
- Modify: `www/app.css`, `www/app.js`, `STATE.md`, `docs/plan.md`, `README.md` (screenshots or wording only if they describe the old layout)

- [ ] **Step 1: Dark mode.** Under `[data-bs-theme="dark"]`: panels `#2b2f36` at 94% opacity with a `rgba(255,255,255,.08)` border, text `#e6e8eb`, secondary text `#9aa3ad`, the active tab and primary buttons light (`#e6e8eb` background, `#1c2430` text), chips and segmented controls darkened, and the haze dark. The map keeps the existing tile inversion. Plots already follow the theme through `use_plot_theme()`.
- [ ] **Step 2: Reduced motion.** Add the `@media (prefers-reduced-motion: reduce)` rules from Global Constraints, and have `app.js` skip count-ups (it writes the final number straight away).
- [ ] **Step 3: Check the whole app** in Chrome at 1280 × 720, at 100% and 150% zoom, in light and dark mode, and in sample and live mode:
  - Flip dark mode on a method tab: panels, plots, planes and legends switch, and no re-run happens (no progress line, nothing in the R console). *(Review Focus 5.)*
  - With reduced motion turned on in the browser's rendering emulation: no glide and no slides.
  - Every panel is readable and nothing overlaps the tab bar; the left column and the expanded card scroll.
- [ ] **Step 4: Run the full test suite.** Expected: all pass.
- [ ] **Step 5: Update the docs.**
  - `STATE.md`: describe the new layout. Mark Task 11 done (replaced by the tour), and note the tour text and setting help lines are drafts for Luke to reword.
  - `docs/plan.md`: under Task 11, note that it was superseded by this plan.
  - Update `CLAUDE.md`'s Status section (it is git-ignored, so not committed).
- [ ] **Step 6: Commit**

```bash
git add www/app.css www/app.js STATE.md docs/plan.md README.md
git commit -m "Finish dark mode and reduced motion, and update the docs"
```
