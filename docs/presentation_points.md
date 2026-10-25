# Presentation points (10 minutes)

The short version of `presentation_script.md`, for cue cards. Values in [brackets] come off the screen on the day. *Italics* are the driver's clicks.

## Person 1: Introduction and Live Map (2.5 min)

*Home page.*

- SkyStats runs spatial statistics on the aircraft in the air right now.
- Data: OpenSky. Planes broadcast ADS-B and volunteer receivers pick it up. Airlines come from the callsign, airports from OurAirports, countries from spData.
- *Point at the badge.* New snapshot every 10 minutes, shared by all users, which keeps us inside the free limit. With no connection it uses a saved snapshot.
- Before a test runs, the app cleans, filters, crops and projects the data. Each region has its own equal-area projection.
- Empty sky can mean no receivers. Coverage is thin over Africa and the oceans.

*Open Live Map.*

- About [number] aircraft right now.
- *Cargo filter, then back.* Filter by airline, category and altitude.
- *Click a plane.* Callsign, airline, altitude, speed.
- *Choose Europe.* Each analysis runs on one region. Hand over to autocorrelation.

## Person 2: Spatial Autocorrelation (2.5 min)

*Autocorrelation tab, Europe.*

- Question: where does traffic concentrate?
- Hex grid over Europe, aircraft counted per hex.
- Neighbours: queen contiguity (touching hexes). k nearest and distance bands are also in the settings.
- Moran's I = [value], p = [value]. Positive means busy hexes sit next to busy hexes.
- Geary's C and Global G agree. Global G says the clusters are of high values (hot spots).
- *LISA layer.* Red is high-high, along the main city corridors. Dark blue is low-low, over sea and remote areas. Orange is high-low, a lone hub or a holding pattern.
- *Real-world uses.* Air traffic control uses this to size airspace sectors.
- Caveat: receivers are clustered too, so some low-low areas just have no receivers.

## Person 3: Point Patterns (1.5 min)

*Point Patterns tab.*

- Question: how clustered is it?
- Equal squares (quadrats) over the region. Count the points in each and compare with complete spatial randomness.
- [6 × 6] grid, chi-squared p = [value], so we reject CSR. Expected, since planes fly between cities.
- VTMR = [value]. Above 1 is clustered, below 1 regular, about 1 random.
- *Move the nx slider.* VTMR changes with grid size: the modifiable areal unit problem.
- *Real-world uses.* On airports, planners want a spread (VTMR below 1). Empty quadrats matter for twin-engine aircraft that must stay near an airport.
- Hand over to regression.

## Person 4: Spatial Regression (2.5 min)

*Regression tab.*

- Question: why do some countries have more aircraft over them?
- Aircraft per country, modelled on population and GDP per capita. Area and airports are optional.
- Step 1, OLS: R² = [value], [population] is the strongest predictor.
- Step 2, Moran's I on the residuals = [value], p = [value]. Neighbouring countries are wrong in the same direction, so OLS coefficients are biased.
- Step 3, LM tests: robust lag is [significant], so use a lag model.
- Step 4, spatial lag model: ρ = [value]. A country's traffic depends on its neighbours'. Overflights, for example Kazakhstan and Sudan, and the fees they charge.
- *Step 5, residual map.* Positive: transit corridors and hubs. Negative: connectivity gaps, which the Single African Air Transport Market aims to close.
- Hand back to Person 3.

## Person 3: Wrap-up (1 min)

*Home page.*

- Autocorrelation showed where, quadrats showed how clustered, regression showed why, including spillover from neighbours.
- Limits: one snapshot in time; coverage follows the receivers; results shift with region, hex size and grid.
- Thank you, questions.
