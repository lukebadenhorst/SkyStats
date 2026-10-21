# Project state

**As of 21 Oct 2026.** Due 26 Oct 2026. Update this file whenever a task is merged.

The app works end to end: the Live Map and all three method tabs run in both live and sample mode, and the About page and README describe the finished app. What is left is the Home page (Task 11, on hold), the bug bash (Task 13), and the stretch goals. 204 tests pass on `main`.

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
| 11 | Home (landing) page | **On hold** (design to be agreed) | |
| 12 | About page, sidebar text, README | Done | #11 |
| 13 | Bug bash | **Not started** | |
| S1–S5 | Stretch goals | Not started (only after Task 13) | |

The step-by-step checkboxes are in `docs/plan.md`.

## What the app does now

- **Tabs:** Live Map, Autocorrelation, Point Patterns, Spatial Regression, About. The Airports & Routes skeleton was removed in Task 12 because stretch S1 is not built; it is in git history if S1 is done.
- **Filters** in the sidebar apply to every tab. Airport points (Point Patterns) ignore the airline, category and altitude filters.
- **Regions:** Autocorrelation and Point Patterns need one of the four regions (World has no equal-area projection). Regression runs in Europe and World only.
- Every method runs only on **Run analysis**. A problem the user can fix shows as a yellow message, never a raw R error.

## What is left

### Task 11: Home page (on hold)

The plan has the structure (hero, shortcut cards, `home_server(on_select)`); the text and look are for the group to design. Things to know before starting:

- The plan's test lists "Airports & Routes" among the app's tabs. That tab no longer exists, so drop it from `app_tabs` in the test.
- `docs/ideas.md`, idea 1, has a draft "How this app works" accordion with six panels of text. It is meant to be the introduction to the class presentation, so check it on a projector (1280 × 720, browser zoom 125–150%).
- Still open: whether the filter sidebar should be hidden on Home.

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
- Each task goes on its own branch with a PR into `main`.
- Rebuild the airline and airport lookups: `Rscript data-raw/build_lookups.R` (needs internet, no API credits).
