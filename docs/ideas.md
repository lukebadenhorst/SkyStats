# Ideas

Ideas for the app that are not yet in `docs/plan.md`. Add new ideas as new sections.

---

## 1. Home page: a "How this app works" section that expands

**Where:** on the Home page (Task 11), below the shortcut cards. It is closed by default, so the page stays clean, and opens when the user clicks it.

**Why:** two jobs.

1. **It is the introduction to our class presentation.** We open the app on the Home page and walk through the panels in order, one click per talking point, before demonstrating the tabs. Showing this inside the app means no separate slides are needed.
2. A marker opening the app later should understand within a minute where the data comes from, how fresh it is, and what each tab does, without having to find the About page.

### How to build it

- Use `bslib::accordion(open = FALSE, ...)` with one `accordion_panel()` per topic below. Each panel opens on its own, so the presenter can open one at a time while talking. This makes the separate panels better than one big panel.
- Panels are in speaking order: data → updates → pipeline → methods → regions → caveats.
- Keep each panel short (3–6 lines). The About page keeps the full detail (sources, method summaries, limitations), and the last panel links to it.
- The "Data right now" line can reuse the header badge's `snapshot()$source` and `snapshot()$time`, so it says live or sample and the time of the snapshot.
- Only `home_ui()` changes. No server logic is needed beyond the existing shortcut buttons, unless the data-source line is made live.

### Draft text for each panel

Placeholder wording for the group to edit. The facts match the current code (`R/data_api.R`, `R/regions.R`) and `docs/plan.md`.

**1. Where the data comes from**

- **Aircraft positions:** the [OpenSky Network](https://opensky-network.org) REST API (`/states/all`). OpenSky collects ADS-B signals from a worldwide network of volunteer receivers. Each row is one aircraft: position, altitude, speed, heading, callsign and category.
- **Airlines:** matched from the first three letters of the callsign to the OpenFlights airline list.
- **Airports:** large and medium airports from OurAirports.
- **Countries:** country polygons, population, GDP per capita and area from `spData::world` (the same data as the Ch 6 example in the course).

**2. How often it updates**

- The app asks OpenSky for a new snapshot at most **once every 10 minutes**. Every user of the app shares that one snapshot, which keeps us well inside OpenSky's free limit of 4,000 credits a day (each call costs 4).
- The **Refresh** button fetches a new snapshot straight away, unless the current one is less than a minute old.
- If OpenSky can't be reached, or we hit the rate limit, the app keeps showing the last good live snapshot. If there is none, or no OpenSky login is set, it uses a **bundled sample snapshot**, so the app always works. The badge in the top right always says which one you're seeing.

**3. From raw data to an analysis**

1. Fetch the snapshot, or use the cached or sample one.
2. Clean it: drop aircraft without a position, and add the airline and category.
3. Apply the sidebar filters.
4. Crop to the chosen region and project it to that region's **equal-area** map projection, so that areas and distances are comparable.
5. Run the method you choose, but only when you click **Run analysis**.

**4. The three methods**

- **Autocorrelation (Ch 4):** counts aircraft in a grid of hexagons and tests whether busy cells sit next to busy cells (Moran's I, Geary's C, Global G). The LISA map shows where the clusters and outliers are.
- **Point Patterns (Ch 7):** splits the region into quadrats and tests whether aircraft or airports are spread at random (complete spatial randomness), clustered, or regular. It uses the χ² test and the variance-to-mean ratio (VTMR).
- **Spatial Regression (Ch 6):** explains the number of aircraft over each country with population, GDP per capita, area and airport count. It follows the course workflow: OLS, then Moran's I on the residuals, then the LM tests, then a spatial lag model if the tests call for one.

Each tab ends with a plain-English interpretation: the hypothesis, the test statistic, the p-value and the conclusion at your chosen α.

**5. Regions and projections**

| Region | Projection | Methods |
|---|---|---|
| Europe | EPSG:3035 (LAEA Europe) | all three |
| North America | ESRI:102008 (Albers) | autocorrelation, point patterns |
| Southern Africa | ESRI:102022 (Albers) | autocorrelation, point patterns |
| East Asia | ESRI:102025 (Albers) | autocorrelation, point patterns |
| World | none (no single equal-area projection works) | regression only |

Regression needs at least 15 countries, so only Europe and World have enough.

**6. Things to keep in mind**

- A snapshot shows one moment, not a day of traffic.
- Coverage is uneven: OpenSky has many receivers in Europe and North America and few over Africa, oceans and remote areas. Empty sky on the map can mean no receivers rather than no aircraft.
- Aircraft that don't match an airline or category are labelled "Unknown" and kept.
- More detail: see the **About** page.

### Making it work as the presentation introduction

- **One headline per panel.** Start each panel with one bold sentence the audience can read while the presenter talks. The bullets underneath are detail for markers reading later, not something to read aloud.
- **A data-flow diagram in panel 3.** Show fetch → clean → filter → crop and project → analyse as boxes and arrows (inline SVG or a PNG in `www/`). An audience follows a picture faster than a numbered list.
- **Readable on a projector.** Check it at 1280 × 720 with the browser zoomed to 125–150%. Panel text should not wrap into long paragraphs.
- **The badge as a live talking point.** In panel 2, point at the header badge ("● Live, updated 14:05 UTC") to show the data is real and current.
- **A plan for bad Wi-Fi.** If the venue's network fails, the app falls back to the sample snapshot by itself and the badge says so. Rehearse once in sample mode (run without the OpenSky credentials) so the demo works either way. For the same results in rehearsal and on the day, the Freeze snapshot stretch goal (S3) would help.
- **Hand-over to the demo.** The last panel ends with the shortcut cards just above it, so the presenter scrolls up and clicks "Open Live Map" to start the tabs.

### Suggested running order for the presentation

Fill in the times once we know how long we have.

| Part | What we show | Who | Time |
|---|---|---|---|
| Introduction | Home page, panels 1–6 | | |
| Live Map | Filters, the region selector, aircraft popups | | |
| Autocorrelation | Run in Europe, explain the LISA map | | |
| Point Patterns | Aircraft vs airports, VTMR | | |
| Spatial Regression | The five steps, the residual map | | |
| Wrap-up | Limitations, real-world uses (`docs/real_world_applications.md`) | | |

With one person per method (as `docs/plan.md` suggests), each person can present the tab they built.

### Open questions for the group

- How long is the presentation, and does everyone have to speak?
- Should panel 4 link to each method tab (reusing the shortcut buttons), or just describe them?
- Add a sentence on real-world uses for each method from `docs/real_world_applications.md`?
