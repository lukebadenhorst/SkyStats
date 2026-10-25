# Methodology

This document explains how SkyStats gets its data, how it prepares it, and how each of the three methods works. It is meant for the marker and for anyone in the group who has to explain a result. The code for every step is named so you can check it.

The three methods come from the STAT3037A course notes:

| Tab | Course chapter | Question |
|---|---|---|
| Autocorrelation | Ch 4, spatial autocorrelation | Where does air traffic concentrate? |
| Point Patterns | Ch 7, quadrat test for complete spatial randomness | How concentrated is it? |
| Spatial Regression | Ch 6, spatial lag regression | Why do some countries see more of it? |

For what the results mean in aviation, see `docs/real_world_applications.md`.

## 1. Data

### Aircraft positions

The app calls the OpenSky Network REST API (`GET /states/all` with `extended=1`). One call returns a state vector for every aircraft OpenSky can see worldwide, usually around 10,000 rows. Each row has the aircraft's ICAO 24-bit address, callsign, country of registration, longitude, latitude, barometric and geometric altitude, whether it is on the ground, speed, heading and emitter category.

The app signs in with OAuth2 client credentials read from `OPENSKY_CLIENT_ID` and `OPENSKY_CLIENT_SECRET` in `.Renviron`. That file is never committed. See `R/data_api.R`.

### Caching and the sample snapshot

All users of one running app share a single in-memory cache that expires after 10 minutes, so the app makes at most one API call per 10 minutes however many people have it open. A call costs 4 of the 4,000 daily credits on a free account.

When the app cannot get live data it falls back in this order:

1. The last good live snapshot, if there is one (the badge shows "Cache").
2. The bundled sample snapshot in `data/sample/states_sample.rds` (the badge shows "Sample").

The app uses the sample when there are no credentials, when OpenSky returns an error, or when it hits the rate limit (HTTP 429). After a 429 the app stops polling for as long as OpenSky's `X-Rate-Limit-Retry-After-Seconds` header asks, or 10 minutes if the header is missing.

OpenSky drops connections from shinyapps.io servers, so the hosted app always runs on the sample. Run the app locally with credentials to see live data. `docs/shiny_deployment.md` has the details.

### Reference tables

| Table | Source | Used for |
|---|---|---|
| `data/lookups/airlines.rds` | OpenFlights `airlines.dat` | Airline names in the filter and popups |
| `data/lookups/airports.rds` | OurAirports, large and medium airports | The airport point set and the airport-count covariate |
| `spData::world` | Natural Earth, via the `spData` package | Country polygons, population, GDP per capita and area for the regression |

`data-raw/build_lookups.R` rebuilds the first two.

## 2. Preparing the data

`prep_states()` in `R/data_prep.R` cleans each snapshot before any tab sees it.

- Rows with no longitude or latitude are dropped.
- Callsigns are trimmed, and empty ones become missing.
- The airline code is the first three letters of the callsign when they are followed by a digit (`SAA312` gives `SAA`). Callsigns that are registrations, such as `ZSABC`, get no airline.
- Altitude is the barometric altitude, or the geometric altitude when the barometric one is missing. It is then put in a band: on ground, below 3,000 m, 3,000 to 9,000 m, above 9,000 m, or unknown.
- Each aircraft gets one category from a set of rules checked in order: military or government (US military address range ADF7C8 to AFFFFF, known military callsigns, or "air force", "navy" and similar in the airline name), cargo, business jet, passenger airline (any other airline code), private or general aviation (a callsign with no airline code), and unknown.

The sidebar filters (airline, category, altitude band, airborne only) then apply to every tab. The airport point set ignores the airline, category and altitude filters, because airports have none of those attributes.

## 3. Regions and projections

The methods run on one region at a time. Each region is a longitude/latitude box with its own equal-area projection, so that a hexagon or quadrat covers the same ground area wherever it sits in the region. This matters because both the hex counts and the quadrat test compare counts across cells and assume the cells are the same size.

| Region | Projection | Methods |
|---|---|---|
| Europe | EPSG:3035 (LAEA Europe) | All three |
| North America | ESRI:102008 (North America Albers equal area) | Autocorrelation, Point Patterns |
| Southern Africa | ESRI:102022 (Africa Albers equal area) | Autocorrelation, Point Patterns |
| East Asia | ESRI:102025 (Asia North Albers equal area) | Autocorrelation, Point Patterns |
| World | None (stays in longitude/latitude) | Spatial Regression |

The boxes avoid the 180° meridian. The box edges are densified to 60 points each before projection, so they curve the way they should in the projected map (`region_polygon()` in `R/regions.R`).

World has no single equal-area projection that suits the hex and quadrat methods, so those two are not offered there. Regression needs at least 15 countries with complete data. Only Europe and World have that many; the other regions have 8 to 11.

## 4. Spatial weights

Autocorrelation and regression both need to know which units are neighbours. `build_weights()` in `R/stats_weights.R` builds the weights with `spdep`:

| Type | Neighbours of unit i | Available in |
|---|---|---|
| Queen contiguity | Units that share an edge or a corner with i | Both |
| k nearest neighbours | The k units whose centroids are closest to i's | Both |
| Distance band | Every unit whose centroid is within d km of i's | Autocorrelation |
| Inverse distance | As the distance band, weighted by 1/distance | Autocorrelation |

Distances are in km: projected coordinates are divided by 1,000, and World uses great-circle distances.

The weights can be row-standardised (style W: each unit's weights sum to 1) or binary (style B: every neighbour gets weight 1). Units with no neighbours are allowed and counted, and the results card reports how many there are. The app refuses a distance band shorter than the largest nearest-neighbour distance, because that would leave some units with no neighbours at all, and tells the user the smallest band that works.

## 5. Autocorrelation (Ch 4)

Code: `hex_counts()` and `run_autocorr()` in `R/stats_autocorr.R`.

### Building the hex grid

1. The filtered aircraft in the region are projected into the region's CRS.
2. A hexagonal grid covers the region, with hexes the chosen size across (50 to 500 km, default 150 km). Only hexes that touch the region are kept.
3. Each aircraft is counted in one hex. An aircraft on a shared edge goes to the first hex it falls in, so no aircraft is counted twice.
4. The value of each hex is log(count + 1) by default, or the raw count. A few hexes over busy hubs hold far more aircraft than the rest, and the log stops them from dominating the statistics.

The method needs at least 30 hexes and at least two distinct values.

### Global statistics

Write x_i for the value of hex i, x̄ for the mean, n for the number of hexes, w_ij for the weights and S_0 for the sum of all weights. The user picks one of three global statistics.

Moran's I compares each hex with its neighbours, relative to the mean:

$$I = \frac{n}{S_0} \cdot \frac{\sum_i \sum_j w_{ij}(x_i - \bar{x})(x_j - \bar{x})}{\sum_i (x_i - \bar{x})^2}, \qquad E[I] = -\frac{1}{n-1}$$

I above E[I] means neighbouring hexes have similar values (positive autocorrelation).

Geary's C uses the squared differences between neighbours:

$$C = \frac{(n-1)\sum_i \sum_j w_{ij}(x_i - x_j)^2}{2 S_0 \sum_i (x_i - \bar{x})^2}, \qquad E[C] = 1$$

C below 1 means neighbours are alike (positive autocorrelation). C above 1 means they differ.

Getis-Ord Global G asks whether the high values in particular sit together:

$$G = \frac{\sum_i \sum_{j \ne i} w_{ij} x_i x_j}{\sum_i \sum_{j \ne i} x_i x_j}$$

G above E[G] means high values cluster (hot spots). Global G always uses binary weights, so the style switch is hidden for it.

All three tests are one-sided, with H0 of no spatial autocorrelation and the alternative of positive autocorrelation. For Geary's C the app reports z so that a positive z means C below its expectation, the same convention as `spdep::geary.test()`.

### Inference

There are two ways to get the p-value:

- Analytic: the z-score under the normal approximation (`moran.test()`, `geary.test()`, `globalG.test()`).
- Permutation: the values are shuffled across the hexes 99 to 999 times (default 499), and the p-value is the share of shuffles with a statistic at least as extreme as the observed one (`moran.mc()`, `geary.mc()`). The app reports the mean and variance of the shuffled statistics as the expectation and variance. `spdep` has no permutation test for Global G, so it uses the analytic test only.

The test rejects H0 when p is below the chosen α (0.10, 0.05 or 0.01).

### LISA

The app also computes local Moran's I for every hex with `spdep::localmoran()`, using its two-sided test. Each hex whose local p-value is below α is labelled by its quadrant on the Moran scatterplot (its own value against the average of its neighbours, both relative to the mean):

| Cluster | Meaning |
|---|---|
| High-High | A busy hex among busy neighbours |
| Low-Low | A quiet hex among quiet neighbours |
| High-Low | A busy hex among quiet neighbours (an outlier, often a lone hub) |
| Low-High | A quiet hex among busy neighbours |

The other hexes are "Not significant". The map colours the hexes by cluster, and the scatterplot shows each hex's value against its spatial lag.

## 6. Point Patterns (Ch 7)

Code: `quadrat_window()`, `as_ppp()` and `run_quadrat()` in `R/stats_quadrat.R`.

### The point set

The user picks one of two point sets:

- Airborne aircraft: the filtered aircraft that are not on the ground.
- Airports: large airports, medium airports, or both, from OurAirports.

The points are projected into the region's equal-area CRS.

### Why the grid sits on a rectangle

The quadrat test and the VTMR assume every quadrat has the same area. A region projected into an equal-area CRS has curved edges, so a grid laid over the whole region has small clipped tiles at the edges. Those tiles have low expected counts, and in testing they made the VTMR report clustering for points that were random.

To avoid this, `quadrat_window()` finds a large rectangle inside the region. It grows a rectangle from the centre of the region, with the same shape as the region's bounding box, until it no longer fits, and then pushes each side out as far as it will go. A bisection search with 20 steps finds each limit. The grid is laid over this rectangle, so every quadrat has the same area. Points outside the rectangle are left out. The map outlines the rectangle, and the results say what share of the region it covers.

The points become a `spatstat` point pattern in that window (`as_ppp()`).

### Chi-squared quadrat test

The rectangle is split into nx by ny quadrats (2 to 15 each way, default 6 by 6), giving m = nx × ny quadrats. Under H0 of complete spatial randomness (a homogeneous Poisson process), every quadrat has the same expected count E = n/m.

$$\chi^2 = \sum_{k=1}^{m} \frac{(O_k - E)^2}{E}, \qquad \text{df} = m - 1$$

The app runs this two-sided with `spatstat.explore::quadrat.test()`, and the results include a histogram of the quadrat counts. It refuses to run when any quadrat expects fewer than 5 points, the usual condition for the χ² approximation, and asks the user to use fewer quadrats. It also needs at least 30 points.

### Variance-to-mean ratio

The VTMR compares the spread of the quadrat counts with their mean:

$$\text{VTMR} = \frac{s^2}{\bar{x}}, \qquad (m-1)\cdot\text{VTMR} \sim \chi^2_{m-1} \text{ under CSR}$$

For a Poisson process the variance equals the mean, so the VTMR is close to 1. The app tests it two-sided, with p = 2 × min(lower tail, upper tail). If p ≥ α the pattern is called consistent with randomness. Otherwise a VTMR above 1 is called clustered and a VTMR below 1 is called regular.

Aircraft fly between cities, so CSR is almost always rejected for them. For aircraft the size of the VTMR is the useful number: it lets you compare how concentrated traffic is between regions or at different grid sizes.

## 7. Spatial Regression (Ch 6)

Code: `country_units()`, `regression_formula()` and `run_regression()` in `R/stats_regression.R`.

### The units and variables

The units are the countries of `spData::world` whose centroid falls inside the region's box. For each country the app has:

- The response y: the number of filtered aircraft currently over the country (a point-in-polygon count).
- Population, GDP per capita and area from `spData::world`.
- The number of large and medium airports in the country, from OurAirports.

Europe is projected to EPSG:3035. World stays in longitude/latitude.

The default model is

$$\log(1 + y) = \beta_0 + \beta_1 \log(\text{pop}) + \beta_2 \log(\text{GDP per capita}) + \varepsilon$$

and the user can add log(area) and log(1 + airports), or switch off the log of y. Countries with a missing or non-finite value in any model variable are dropped. Some Natural Earth countries have no GDP figure, and log(0) is not finite. At least 15 countries must remain, and there must be more countries than coefficients plus two.

The weights are queen contiguity (shared borders) or k nearest neighbours (default k = 4), always row-standardised. Island countries have no queen neighbours, so k nearest neighbours is the better choice when a region has many of them.

### The four steps

The app follows the workflow from the course notes.

1. Fit OLS with `lm()` and report the coefficients and R².
2. Test the OLS residuals for spatial autocorrelation with Moran's I (`spdep::moran.test()`, one-sided). A significant result means OLS has missed a spatial pattern and its standard errors cannot be trusted.
3. Run the Lagrange multiplier tests with `spdep::lm.RStests()`: LMlag, LMerr and their robust versions RLMlag and RLMerr. The app recommends a model with the course rule:
   - neither LMlag nor LMerr significant: OLS;
   - only one significant: that model;
   - both significant: the model whose robust test has the smaller p-value.
4. Fit the spatial lag model with `spatialreg::lagsarlm()`:

$$y = \rho W y + X\beta + \varepsilon$$

Here Wy is the weighted average of the neighbours' y, and ρ measures how much a country's traffic depends on its neighbours' traffic. The app reports ρ with its likelihood ratio test, the lag model's coefficients, and the AIC of OLS and the lag model. The lower AIC fits better.

The app fits the lag model at step 4 even when the LM tests recommend OLS or the error model, because the lag model is the method this tab demonstrates. The summary then says what the tests recommended, and the AIC shows whether the lag model was worth it. The app does not fit a spatial error model.

The map shows the OLS or lag model residuals for each country. A positive residual means the country has more aircraft over it than its population, wealth and airports predict, which usually marks a transit corridor or a hub.

## 8. How results are shown

Each method tab has the same layout (`R/mod_common.R`):

- The settings panel on the left, with a one-line explanation under each setting.
- A summary card with the headline statistic, a badge (for example "Clustered" or "Spatial lag model"), four smaller figures and one sentence of meaning.
- An expanded view with the full tables, the plain-English interpretation, the setup used, and a "Real-world uses" panel.
- A map layer drawn on the shared map: LISA hexes, quadrat counts or country residuals.

The interpretation text is built from the results by `autocorr_text()`, `quadrat_text()` and `regression_text()`. Each one states H0, gives the statistic, and states the decision at the chosen α.

A method only runs while its tab is open, and it reruns when the settings, the region, the filters or the data change.

## 9. Errors

Every method runs inside `run_safely()` (`R/stats_common.R`), so the user never sees a raw R error. Problems the user can fix, such as too few points, too many quadrats for the data, or a k larger than the number of units, raise a plain message that says what to change. Any other failure shows "The analysis failed" with the R message.

## 10. Testing

The `stats_*.R` files are pure R with no Shiny code, so they can be tested on their own. The tests in `tests/testthat/` check them against the worked examples in the course notes: Moran's I matches Example 4.1, the quadrat test on the `bei` data matches Example 7.1, and the Ch 6 workflow reproduces pinned values. They also check known cases, such as a perfect grid reading as regular and random points reading as random, both in a plain square and in each region's rectangle. The tests use the bundled sample, so they need no credentials.

```bash
"/c/Program Files/R/R-4.6.1/bin/Rscript.exe" -e 'testthat::test_dir("tests/testthat")'
```

## 11. Limitations

- Coverage bias. OpenSky depends on volunteer ground receivers, which are dense in Europe and North America and sparse over Africa, the oceans and remote land. Some Low-Low clusters and empty quadrats are gaps in coverage, and the sky there may not be empty.
- One snapshot. Each run uses a single moment in time. Traffic changes over the day, so a result at 03:00 UTC can differ from one at 15:00 UTC.
- Cell size. Hex size and quadrat grid both change the results, a form of the modifiable areal unit problem. Rerunning with a few sizes shows how stable a result is.
- Multiple testing in LISA. Each hex is tested at α with no correction, so with hundreds of hexes some will be flagged significant by chance.
- What the regression counts. Aircraft over a country include departures, arrivals and overflights, so y is not the same as air travel demand from that country. This is why area matters so much in the model.
- Country data. `spData::world` figures come from one year and some countries lack GDP. Those countries are dropped from the regression.
- Categories. The flight categories come from callsign and address rules, not an official register, so some aircraft are misclassified or labelled unknown.
