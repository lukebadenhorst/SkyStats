# Map-first redesign: design

**Date:** 22 Oct 2026. **Due:** 26 Oct 2026 (the app is presented to the class).
**Mockups:** `.superpowers/brainstorm/525-1792702796/content/` (local only): `planefinder-light.html` (layout), `results-panel.html` (a method tab), `home-tour.html` (Home page and tour), `setup-box.html` (the first-visit setup box). All four were approved. Open them in a browser; they are throwaway HTML and JavaScript, not code to copy.

## Why

The app works: all three methods, the Live Map and the About page are done (see `STATE.md`). It looks like a standard bslib dashboard, though: a sidebar, value boxes and a stack of cards, with a small map inside a card on each tab. The group will present it on a projector, and Luke wants it to look impressive, with clean and elegant styling and animations.

The model is **Plane Finder** (https://planefinder.net/), but with a **light map**. What Luke liked about it: the map fills the screen, aircraft are drawn as plane icons pointing the way they fly, and the controls float on top of the map in rounded panels instead of sitting in a fixed sidebar.

The core idea: **one full-screen map for the whole app**. Each tab changes what is drawn on that map, and the numbers and tables float beside it.

## Goals

1. A full-screen light map behind everything, shared by every tab.
2. Floating rounded panels for the tab bar, the filters, each method's settings and the results.
3. Aircraft drawn as plane icons rotated to their heading, gliding between data refreshes.
4. Each method tab draws its result on the shared map (LISA hexes, quadrat grid, regression residuals).
5. Results shown as a short summary card that expands to show everything.
6. Methods re-run by themselves when a setting changes, with a loading state; no Run button.
7. A Home page with a step-through "How this app works" tour that opens the class presentation, where the map acts out each step.
8. Smooth, calm animation throughout: fades, slides, numbers counting up, layers fading in.

## Non-goals

- **Not React.** The brief says the dashboard "must be designed on RShiny". It stays a Shiny app, styled with bslib, CSS and a small amount of JavaScript.
- **No change to the statistics.** The `stats_*.R` functions and their tests stay as they are. Only the UI and the module servers' wiring change.
- No new methods, data sources or filters.
- The final wording of the Home tour. Luke said the text needs rework; that is a later job. Use the mockup text (from `docs/ideas.md`, idea 1) as placeholder.
- A phone layout. It should not break on a narrow screen, but it is designed for a laptop and a projector.

## Anti-goals (a failure even if it works)

- **The "AI look".** Luke rejected a pastel version for looking AI-made. Avoid purple/indigo-and-teal gradients, blurred colour blobs, emoji used as icons, and everything being a soft rounded bubble. The approved look is neutral: white panels, near-black text and controls, a light grey map, and one blue accent (see "Look" below).
- Animation that delays results or makes the app feel slow. Motion supports the content; it never makes the user wait.
- Motion that distracts during the presentation (constant bouncing, looping attention-grabbers).
- Breaking a working app close to the deadline. The work happens on a branch, and `main` keeps working until the redesign is ready.

## Constraints

- R Shiny, bslib (Bootstrap 5), leaflet. Packages already installed are listed in `CLAUDE.md`; avoid adding new ones unless there is a clear need.
- Basemap: Esri World Light Gray Canvas (`providers$Esri.WorldGrayCanvas`). CARTO tiles need an API key.
- External scripts or fonts only from a CDN with a pinned version, or bundled in `www/`. The app is hosted on shinyapps.io later (`docs/shiny_deployment.md`).
- **Projector:** everything must fit and be readable at 1280 × 720 with the browser zoomed to 125–150%.
- **Performance:** a live snapshot can hold around 10,000 aircraft worldwide. The plane layer must stay smooth at that size (see "Planes").
- The existing tests (204) must keep passing, apart from the module tests whose trigger changes from the Run button to auto-run; update those to the new trigger.
- Luke is the only person editing the app while this is built, so rewriting `app.R` and every `mod_*.R` file at once is fine. Still keep each tab's code in its own `mod_*.R` file.
- No time cutoff: Luke said not to worry about time, so build the whole design rather than a reduced version.

## What was decided, as decided

These came from Luke during the design conversation.

- **Style:** Plane Finder's layout with a light map (the `planefinder-light.html` mockup was approved).
- **Method results on the map:** when a method tab is used, the full-screen map updates to show its result.
- **Results:** a few headline results, with an option to expand and see everything (the `results-panel.html` mockup was approved).
- **Auto-run:** Luke asked what would look best. Claude recommended auto-run with a short pause and a loading state, and Luke went with it (he then moved on without objecting).
- **Home page:** part of this redesign, as a step-through tour (the `home-tour.html` mockup was approved). The tour text is reworked later.
- **First visit to a method tab:** a box in the centre of the screen lets the user choose the starting settings, and explains each one in simple words. Later visits to that tab reuse the most recent settings.
- **Scope and people:** no time cutoff (build all of it); Luke is the only one editing the app for now.

## Design

### Layout

- The shared Leaflet map fills the window, behind everything (`position: fixed; inset: 0`).
- **Top bar** (floating panels, left to right): the app name with a plane icon; the tab bar (Home, Live Map, Autocorrelation, Point Patterns, Spatial Regression, About) with a dark highlight that slides to the active tab; on the right, the data badge (live, cached or sample, with the time; a pulsing green dot when live), the Refresh button and the dark mode switch.
- **Left column** (floating panels, about 230–260 px wide): the shared filters (region, airline, category, altitude band, airborne only), as folding panels. On a method tab, that method's settings panel appears below the filters, with a chapter tag (Ch 4, Ch 6, Ch 7). On the Live Map it is absent.
- **Right column:** the results card (see below). On the Live Map it shows the aircraft count, the percentage airborne and the top origin countries.
- **Bottom right:** zoom buttons and the map legend for the current layer.
- Panels: white at about 94% opacity with a light blur, a 1 px border at 10% black, 12 px corners, and a soft two-layer shadow. If the left column is taller than the window, it scrolls on its own.

### Look

- Colours: near-black `#1c2430` for text, the active tab and primary buttons; grey `#5b6573` and `#8a94a3` for secondary text; one accent blue `#1d6fd8` for focus, selected chips and small tags; green `#16a34a` only for the live dot. Map layers keep their existing meaningful colours (LISA classes, residuals, quadrat counts).
- Font: Inter (as in the mockups and Plane Finder), with tabular numbers for statistics.
- Controls follow the mockups: chips for multi-choice filters, segmented controls for two- or three-way choices, slim range sliders, and plain selects.
- The navy theme colours `#1d3557` / `#457b9d` are replaced by the neutral palette above.

### One shared map

- `app.R` owns the single `leafletOutput("map")`. Each module draws into its own layer group (or pane) on that map through a Leaflet proxy, and never re-renders the map. This is what allows layers to fade instead of the map flashing.
- The app tells every module which tab is active. A module's layer is visible only while its tab is active. Switching tabs fades the old layer out and the new one in (CSS opacity transitions on the layer panes), and the map glides (`flyToBounds`) to the selected region's extent.
- Changing a setting redraws only that tab's layer: the old layer dims while R works, then the new one fades in.
- Hex and polygon popups or tooltips keep the details they have now (counts, local I, p-value, residuals).

### Planes (Live Map)

- Each aircraft is a small plane icon rotated to its heading (`true_track`). Coloured by the existing altitude palette. *(Claude's call: the mockups used one colour, but the altitude filter and legend already exist, so colour carries information.)*
- **Glide:** between the 10-minute refreshes, each plane moves forward along its heading at its reported speed (`velocity`), so the map stays alive. Aircraft on the ground do not move. When a new snapshot arrives, planes move to their new positions.
- **Performance:** about 10,000 icons as separate DOM markers will be too slow. Draw the planes on a canvas layer instead (a small custom JavaScript layer in `www/`, fed from R with `session$sendCustomMessage`, or an equivalent approach), with hit-testing for hover and click.
- Hover shows a small dark tooltip (callsign, altitude, speed). Click opens the existing aircraft popup.
- On first load, planes fade in over about a second.

### Method tabs

Each method tab has three parts: a map layer, a settings panel on the left, and a results card on the right.

| Tab | Map layer | Headline in the short card |
|---|---|---|
| Autocorrelation (Ch 4) | Hex grid coloured by LISA cluster | The chosen global statistic (Moran's I, Geary's C or Global G), a badge (clustered / dispersed / no evidence), z, p, the number of hexes and significant hexes |
| Point Patterns (Ch 7) | Quadrat grid with the count in each cell (and the points, as now) | χ² statistic and p, VTMR, a badge (clustered / random / regular) |
| Spatial Regression (Ch 6) | Countries coloured by residuals (OLS or lag, as the existing radio buttons choose) | The model the LM tests point to, ρ, the AIC comparison, residual Moran's I before and after |

**The results card:**

- **Short version** (about 270 px wide): a small label, the headline number counting up to its value, a coloured badge, a 2×2 grid of supporting numbers, the plain-English interpretation (cut to two or three lines; the full text appears in the expanded view), the legend for the map layer, and a **Show all results** button.
- **Expanded version** (about 640 px wide, or whatever fits): everything the tab shows today, in the same order: the full interpretation, the test tables, the plots (Moran scatterplot, quadrat histogram) and the regression steps 1–5. It widens with an animation; the button becomes **Show less**.
- If a run fails with a message the user can act on, the card shows the existing yellow message instead of results.

**First visit: the setup box.**

- The first time a method tab is opened in a visit, a box appears in the centre of the screen, over the map (blurred and dimmed behind it, like the About panel). The map has no method layer yet, and the settings panel and results card are hidden.
- The box has the method's name and chapter, one sentence on what the method asks (for example "Do busy areas sit next to other busy areas?"), and every setting the tab has. Under each setting is one or two lines in simple words saying what it does and what changing it means. For example, hex size: "How big each hexagon is. Smaller hexes show more detail but hold fewer aircraft each." Write these from the course notes, in plain language; Luke will review the wording, as with the tour text.
- **Region is in the box.** It lists only the regions that method accepts (no World for Autocorrelation and Point Patterns; only Europe and World for Regression). It is preselected to the current region if the method accepts it, otherwise Europe. Choosing a region here changes the shared region filter, so it applies to the other tabs too. *(Claude's call: this is how the box answers the "World" problem; there is no automatic switch.)*
- Settings that only apply to some choices appear and disappear as they do now (for example, k only for k-nearest neighbours).
- A button (**Run analysis**) closes the box with an animation, runs the method, and shows the settings panel on the left and the results card on the right, filled in with the same values chosen in the box.
- **Later visits** to that tab skip the box and show the last result, with the most recent settings. "Most recent" means within one visit to the app (one browser session); a page reload starts fresh. *(Claude's call.)*
- A small "Settings guide" link in the settings panel reopens the box, so a presenter can show the explanations again. *(Claude's call.)*

**Auto-run:**

- After the setup box, there is no Run button. A method re-runs by itself whenever a setting, the filters, the region or the data change.
- Wait until the inputs have been still for about 600 ms before running (debounce), so dragging a slider does not start several runs.
- Loading state while R works: the current layer dims, and a thin progress line runs along the top of the results card. When the result arrives, the layer fades in and the numbers count up.
- Do not run methods for tabs that are not active. Keep the last result for each tab, so switching back is instant if nothing changed.
- Region rules stay as they are (World is refused for autocorrelation and point patterns; regression only runs in Europe and World). If the user later picks a region the method refuses, using the shared filter, the results card shows the existing yellow message, the method layer fades out, and the message offers the accepted regions as one-click buttons. *(Claude's call.)*

### Live Map tab

- The plane layer, the shared filters on the left, and a stats card on the right (aircraft in view, percentage airborne with a thin bar, top origin countries).
- The aircraft table (currently a "Table" tab beside the map) moves into the expanded version of the Live Map card. *(Claude's call.)*

### Home page and tour

- The app opens on Home. The planes glide behind a soft white haze (a radial gradient overlay). In the centre: the title, one or two sentences with a live aircraft count that counts up, two buttons (**How this app works**, **Open the live map**) and four shortcut cards (Live Map and the three methods), which fade up one after another and lift on hover.
- **How this app works** starts a six-step tour. The haze lifts and a card in the bottom-left shows the step number, one headline, two or three short points, dot progress, and Back/Next buttons. The arrow keys also move between steps (useful with a presentation clicker), and Escape ends the tour.
- Each step drives the map:
  1. Data: a wide view of all the planes.
  2. Updates: a highlight ring around the data badge.
  3. Pipeline: Fetch › Clean › Filter › Project › Analyse light up one by one in the card.
  4. Methods: a real LISA hex layer over Europe. When the tour starts, run the autocorrelation once in the background on Europe with the tab's default settings (the one exception to "do not run methods for tabs that are not active"), and cache it so step 4 shows real data. If it is not ready in time, the step shows without the layer. *(Claude's call: fake hexes would be out of place in a statistics presentation.)*
  5. Regions: the map flies from region to region, outlining each region with its projection code.
  6. Caveats: the map flies to an area with thin receiver coverage (Africa).
- The last step's button reads **Start exploring** and returns to the Home view.
- The step text is a placeholder for now (from `docs/ideas.md`, idea 1). Keep it in one easy-to-edit place, such as a list in `R/mod_home.R`.
- This replaces Task 11 in `docs/plan.md` (the hero, the shortcut cards and the `home_sections` idea carry over; the accordion becomes the tour).

### About page

- Shown as a large centred panel over the map, which is blurred and dimmed behind it. The content stays as it is. *(Claude's call.)*

### Dark mode

- Keep the existing switch. In dark mode the panels turn dark grey (Plane Finder style), the text turns light, and the map uses the existing inverted-tiles trick. Planes keep their altitude colours, brightened where needed to show on the dark map (the existing palette already uses indigo instead of navy for this reason). *(Claude's call.)*
- The app opens in light mode (clearer on a projector).

### Animation guidelines

- Entrances: panels fade and slide in by about 8–12 px, staggered by about 80–100 ms, over 0.5–0.7 s, with an ease-out curve (`cubic-bezier(.2,.7,.2,1)` in the mockups).
- Numbers count up over about 1.1–1.6 s.
- Hover: panels and cards lift by 3–4 px with a deeper shadow.
- Respect `prefers-reduced-motion`: turn off the glide and the entrances, and keep the fades short.

## Order of work

Build all of it, in this order, so each step leaves the app working. There is no time cutoff.

1. Layout shell: the full-screen shared map, floating top bar and tab bar, left filter panels, the light look.
2. Method tabs on the shared map: each module draws its layer on the shared map, with the short and expanded results card.
3. The first-visit setup box, then auto-run with debounce and the loading state.
4. Planes: rotated icons on a canvas layer, then the glide.
5. Home page and tour.
6. About page, dark mode, and the remaining animation polish.

After that, the bug bash (Task 13 in `docs/plan.md`) runs on the redesigned app.

## Left to the builder

- How modules get access to the shared map (passing the parent session, a proxy function, or similar) and how the active tab is passed to them.
- How tabs are switched under the hood (for example `navset_hidden` plus a custom tab bar calling `nav_select`).
- How layer fades are done (custom Leaflet panes with CSS transitions, or JavaScript).
- The canvas plane layer's implementation.
- Where the CSS and JavaScript live (for example `www/app.css` and `www/app.js`), and how much bslib theming versus hand-written CSS to use.
- Exact panel widths, so everything fits at 1280 × 720 and 150% zoom.
- How the badge wording (clustered, random and so on) is derived from each method's existing result.
