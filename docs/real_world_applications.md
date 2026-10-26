# Real-world applications

What each analysis in the app means in practice, and who works on the same question with real data. The app's "Real-world uses" panels draw on it.

How each method is computed is in `docs/methodology.md`.

## Framing

The three tabs answer three questions about air traffic:

- **Autocorrelation:** *where* does traffic concentrate?
- **Point Patterns:** *how* concentrated is it?
- **Spatial Regression:** *why* do some countries see more of it, including spillover from their neighbours?

## 1. Autocorrelation tab: aircraft counts per hex cell (Ch 4)

**What it computes:** for the chosen region, the app counts aircraft (or log(count + 1)) in each hexagon. It then tests whether busy hexes sit next to other busy hexes with Moran's I, Geary's C or Global G, and maps LISA clusters (HH, LL, HL, LH).

**Real-world uses:**

- **Airspace sector design.** Air traffic control splits airspace into sectors, each handled by one controller. HH clusters are where traffic is dense, so they need smaller sectors or more controllers. Eurocontrol and air navigation providers such as ATNS in South Africa do this kind of analysis.
- **Telling corridors from hubs.** A significant Moran's I says traffic forms continuous corridors, not isolated spots. Global G adds whether the clustering is of high values (hot) or low values (cold).
- **HL outliers:** a busy hex surrounded by quiet ones. This is typically a single hub in sparse airspace (Johannesburg or Nairobi on the Southern Africa view), or aircraft in a holding pattern.
- **LL clusters and surveillance gaps.** Oceans and remote land show up as LL. In practice this matters for search and rescue, and it is why satellite-based ADS-B tracking was introduced after MH370.

**Caveat:** OpenSky relies on volunteer ground receivers, and these are themselves clustered: dense in Europe, sparse in Africa. Some LL clusters therefore reflect missing coverage rather than empty sky. This is a real problem with spatial data (coverage bias), and naming it strengthens the interpretation.

## 2. Point Patterns tab: quadrat test and VTMR (Ch 7)

**What it computes:** the app takes either airborne aircraft positions or airports (large, medium or both), projects them to the region's equal-area CRS and counts them in an nx × ny grid. It then runs the χ² test for complete spatial randomness (CSR) and reports VTMR, where values above 1 mean clustered and values below 1 mean regular.

**Real-world uses:**

- **Airports: regular or clustered?** A VTMR below 1 would mean airports are spaced out to serve separate catchment areas, which is what transport planners aim for when siting regional airports. A VTMR above 1 means they bunch around cities and coasts. Which one you get is a question about access and equity, for example how far rural populations are from an airport.
- **Diversion airport coverage.** Twin-engine aircraft on long routes must stay within a set flying time of a usable airport (ETOPS rules). Large empty quadrats are exactly the areas that constrain route planning over Africa, oceans and Siberia.
- **Aircraft clustering as a congestion index.** CSR will almost always be rejected for aircraft, because they fly between cities. The useful number is how large VTMR is, and how it compares between regions or with the grid size. A higher VTMR means traffic is more concentrated, which means more congestion risk at those points.

**Caveat:** results depend on the grid size (a version of the modifiable areal unit problem, MAUP). Showing how VTMR changes with nx × ny makes a good point in the write-up.

## 3. Spatial Regression tab: aircraft over each country (Ch 6)

**What it computes:** the response is log(1 + the number of aircraft currently over each country in `spData::world`). The covariates are log population, log GDP per capita, log area and log(1 + airport count). The app runs OLS, then Moran's I on the residuals, then the LM tests, then the spatial lag model (`lagsarlm`).

**Real-world uses:**

- **Air transport demand modelling.** ICAO, IATA and the World Bank model air traffic against population and income in much the same way, to forecast demand and judge whether a country is "under-connected" for its size and wealth.
- **What ρ means here: overflight spillover.** A positive spatial lag coefficient ρ says a country's traffic depends on its neighbours' traffic. Aircraft over Kazakhstan, Turkey or Sudan are often just passing between busier regions, and many of those countries charge overflight fees. Russia's fees for the Trans-Siberian route between Europe and Asia are a well-known example. So ρ roughly measures how much of a country's air traffic is generated next door.
- **The residual map is the most useful policy output:**
  - *Positive residuals:* more traffic than the country's economy and airports predict. These are usually transit corridors or hub states.
  - *Negative residuals:* less traffic than predicted. These are connectivity gaps, which matter in Africa, where the Single African Air Transport Market (SAATM) aims to open up intra-African routes.
- **The OLS → residual Moran's I → LM tests sequence** is the standard check analysts run. If they skip it and use OLS when the residuals are spatially clustered, the coefficient on, say, GDP is biased, because it absorbs spillover from neighbours.

**Caveat:** a single snapshot of aircraft over each country mixes departing, arriving and passing traffic, which is why the area covariate matters so much. Counting departures instead (OpenSky's `/flights/all` endpoint) would separate demand generated in a country from overflights.
