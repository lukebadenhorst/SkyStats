# Project state

**As of 24 Oct 2026.** Due 26 Oct 2026. Update this file whenever a task is merged.

The app works end to end: the Live Map and all three method tabs run in both live and sample mode, and the About page and README describe the finished app. On branch `map-redesign` the whole app has been rebuilt map-first (Plane Finder style, see "Map-first redesign" below), with a Home page and presentation tour that replace Task 11. It waits for the final review and Luke's visual check before it is merged into `main`. What is left after that is the bug bash (Task 13) and the stretch goals. 330 tests pass on `map-redesign`.

## Progress

| Task | What | Status | PR |
|---|---|---|---|
| 1 | Shared helpers and test setup | Done | #1 |
| 2 | Region geometry | Done | #2 |
| 3 | Spatial weights | Done | #3 |
| 4 | Autocorrelation statistics (Ch 4) | Done | #4 |
| 5 | Autocorrelation tab | Done | #5 |
| 6 | Quadrat statistics (Ch 7) | Done | #6 |
| 7 | Point Patterns tab | Done | #7 |
| 8 | Airport lookup | Done | #8 |
| 9 | Regression statistics (Ch 6) | Done | #9 |
| 10 | Spatial Regression tab | Done | #10 |
| 11 | Home (landing) page | Done: replaced by the redesign's Home page and tour (branch `map-redesign`) | |
| 12 | About page, sidebar text, README | Done | #11 |
| 13 | Bug bash | **Not started** | |
| S1–S5 | Stretch goals | Not started (only after Task 13) | |

The step-by-step checkboxes are in `docs/plan.md`.

## What the app does now

On branch `map-redesign` (spec `docs/superpowers/specs/2026-10-22-map-first-redesign-design.md`, plan `docs/superpowers/plans/2026-10-22-map-first-redesign.md`, Tasks 1-9 built):

- **One full-screen map** behind everything. Every tab draws on it: the planes on Home and the Live Map, the LISA hexes, the quadrats and the residual map on the method tabs. Panels float on top of it.
- **Top bar:** the app name, the tab bar (Home, Live Map, Autocorrelation, Point Patterns, Spatial Regression, About) with a highlight that slides to the active tab, the data badge (live, cached or sample), Refresh and the dark mode switch. The app opens on Home, in light mode.
- **Left column:** the shared filters (region, airline, category, altitude band, airborne only) in a folding panel; on a method tab, that method's settings panel sits below them. The filters fold when a method tab opens. The Airports & Routes skeleton was removed in Task 12 because stretch S1 is not built; it is in git history if S1 is done.
- **Right column:** a results card. The short version has the headline number, a badge, four supporting numbers, two or three lines of interpretation and the map legend; **Show all results** widens it to everything the old tabs showed (tables, plots, regression steps 1-5).
- **Method tabs:** the first visit opens a setup box in the middle of the screen that explains each setting and the region; nothing runs until **Run analysis**. After that, changing a setting re-runs the method by itself after a 600 ms pause, with a progress line on the card. A problem the user can fix shows as a yellow message, never a raw R error.
- **Planes:** about 13,000 plane icons drawn on a canvas, coloured by altitude, that glide along their heading between refreshes (for at most 15 minutes). Hover shows the callsign, a click opens the details.
- **Home:** a hero with the aircraft count, shortcut cards to each tab, and **How this app works**, a six-step tour for the class presentation (arrow keys and a clicker work, Escape ends it).
- **Dark mode:** dark grey panels, light text, light primary buttons, the map tiles inverted and brighter plane and legend colours. Flipping it never re-runs a method. **Reduced motion** (the operating system setting) turns off the glide, the slides and the count-ups, and map moves jump instead of flying.
- **Regions:** Autocorrelation and Point Patterns need one of the four regions (World has no equal-area projection). Regression runs in Europe and World only.
- Filters apply to every tab. Airport points (Point Patterns) ignore the airline, category and altitude filters.

**Drafts for Luke to reword:** the tour text (`R/mod_home.R`) and the one-line help under each setting in the setup boxes (`R/mod_autocorr.R`, `R/mod_quadrat.R`, `R/mod_regression.R`; the region's help line is in `R/mod_common.R`).

## What is left

### Map-first redesign: before merging

The final review of the whole branch, and Luke's own look at the app (light and dark, on a projector at 1280 × 720 and 125-150% zoom). Then reword the draft tour text and setting help lines.

### Task 13: Bug bash

All six steps in `docs/plan.md` are open: the region × method matrix in sample mode, extreme filters, timing (Europe, 50 km hexes, 999 permutations, under 15 s), the matrix in live mode, a fresh clone on another laptop, then tag `v1.0`.

Checked by hand so far (not the full matrix): each method tab in Europe; Spatial Regression in World and North America (refused with the yellow message); Point Patterns with airports in Europe.

### Stretch goals

S1 Airports & Routes, S2 manufacturer/type filter, S3 freeze snapshot, S4 `renv`, S5 hosting. See the end of `docs/plan.md`.

## Changes made while building

Recorded in `docs/plan.md` where they affect an interface; listed here so the group knows.

- **Quadrat test window (Task 6):** the test runs over `quadrat_window()`, the largest rectangle inside the region, not the curved region outline. Clipped edge quadrats failed the expected-count check and made the VTMR report clustering for random points. Points outside the rectangle are left out, and the About page says so.
- **Airports (Task 8):** read with `na.strings = ""` so Namibia's ISO code `"NA"` survives. 5,280 large and medium airports, 111 KB.
- **Regression tests (Task 9):** two fixes to the plan's test code: `sf::st_as_sf()` around `merge()` (without it, `merge()` returns a plain data frame when `sf` isn't loaded yet), and `which()` because Northern Cyprus has no ISO code.
- **Regression output (Task 9):** the lag model table uses the same columns as the OLS table (`term`, `estimate`, `std_error`, `statistic`, `p_value`). "Complete data" also drops rows where a log gives `-Inf`.

## Things to mention in the presentation or write-up

- `spData::world` has no population or GDP for France and Norway (and no GDP for Syria), so a Europe regression with those covariates uses 40 of the 44 countries. They show grey on the residual map.
- On the sample, the LM tests often recommend a **spatial error** model, but the app only fits the lag model (step 4 of the course workflow). The tab says this when it happens.
- With queen weights, island countries have no neighbours (3 in Europe, 16 in the World). The tab suggests K nearest neighbours. `spdep` prints "no neighbours" and "sub-graphs" warnings to the R console in that case; they are expected.
- Regression covers aircraft over each country **now**. "Flights departing yesterday" needs stretch S1.

## Working on it

- Run the app: `shiny::runApp()`. Without OpenSky credentials it uses the bundled sample (the badge says so).
- Run the tests: `testthat::test_dir("tests/testthat")`.
- Each task goes on its own branch with a PR into `main`. The redesign is one branch, `map-redesign`.
- Rebuild the airline and airport lookups: `Rscript data-raw/build_lookups.R` (needs internet, no API credits).
