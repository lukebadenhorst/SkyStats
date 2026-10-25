# Presentation script (10 minutes)

Four speakers, about 2.5 minutes each. Each part is about 260 spoken words, which leaves time for the clicking. Person 3 speaks twice: Point Patterns, then the wrap-up after Regression. One person drives the laptop throughout. Lines in *italics* are what the driver does; everything else is spoken.

The numbers change with every snapshot, so the script leaves them as [brackets]. Read them off the screen on the day. Before starting, open each method tab once so the results are already loaded.

## Person 1: Introduction and Live Map (2.5 min)

*Home page on screen.*

Hi everyone. Our dashboard is called SkyStats, and it runs spatial statistics on the aircraft that are in the air right now.

The data comes from OpenSky. Every plane broadcasts its position over ADS-B, and a network of volunteer receivers around the world picks those signals up. Each dot you'll see is one of those signals. We match the callsign to an airline, and we take airports from OurAirports and country outlines from spData.

*Point at the badge in the header.*

This badge tells you how fresh the data is. The app downloads a new snapshot every 10 minutes and shares it between everyone using the app, which keeps us inside OpenSky's free daily limit. If there's no connection, it falls back to a saved snapshot, and the badge says so.

Before any test runs, the app cleans the data, applies your filters, crops it to a region and projects it. Each region has its own equal-area projection, so areas and distances can be compared fairly.

Keep in mind that an empty patch of sky can mean there are no receivers there, rather than no planes. Coverage is dense over Europe and North America and thin over Africa and the oceans.

*Click "Open Live Map".*

This is the Live Map. There are about [number] aircraft in the air at the moment.

*Set the category filter to cargo, then back to all.*

You can filter by airline, by category, such as passenger, cargo or business jet, and by altitude.

*Click a plane.*

Clicking a plane shows its callsign, airline, altitude and speed.

*Open the region selector and choose Europe.*

Each analysis runs on one region at a time. My teammates will now take you through the three methods, starting with spatial autocorrelation.

## Person 2: Spatial Autocorrelation (2.5 min)

*Autocorrelation tab, Europe, already run.*

Our first question is where traffic concentrates. To answer it, we put a grid of hexagons over Europe and count the aircraft in each one.

Spatial autocorrelation asks whether busy hexes tend to sit next to other busy hexes. To decide what counts as a neighbour we use spatial weights, here queen contiguity, so hexes that touch are neighbours. You can switch to k nearest neighbours or distance bands in the settings.

*Point at the results card.*

Moran's I is [value], with a p-value of [value]. A positive Moran's I means similar values cluster together, so busy hexes sit next to busy hexes, and quiet next to quiet. Geary's C and Global G agree. Global G also tells us the clustering is of high values, so these are hot spots rather than cold ones.

*Switch the map to the LISA layer.*

The global statistic gives one number for the whole region. LISA breaks it down hex by hex. Red is high-high: busy hexes surrounded by busy ones. These line up with the main corridors between cities such as London, Paris and Frankfurt. Dark blue is low-low, mostly over the sea and remote areas. Orange and light blue are outliers. An orange hex is high-low: a busy spot in quiet airspace, often a single hub or planes in a holding pattern.

*Click "Real-world uses".*

Air traffic control uses this kind of map to design sectors, the pieces of airspace each controller looks after. High-high clusters need smaller sectors or more controllers.

Receivers are clustered too, though, so some of the low-low areas are just places with no receivers.

Next, we measure how concentrated the traffic is.

## Person 3: Point Patterns (1.5 min)

*Point Patterns tab, already run.*

Autocorrelation told us where traffic clusters. The quadrat test tells us how strongly. We lay a grid of equal squares, called quadrats, over the region, count the points in each, and compare those counts with what complete spatial randomness would give.

*Point at the grid on the map.*

Here we're using a [6 by 6] grid. The chi-squared test gives a p-value of [value], so we reject complete spatial randomness. That's what we expected, because planes fly between cities rather than scattering at random.

The more useful number is the variance-to-mean ratio, VTMR. Above 1 means clustered, below 1 means regular, and close to 1 means random. Ours is [value], so the traffic is [strongly] clustered.

*Drag the nx slider up a few steps.*

If I change the grid size, VTMR changes too. This is the modifiable areal unit problem: the answer depends partly on the units you choose.

*Click "Real-world uses".*

You can also run the test on airports. Planners siting regional airports want them spread out, which would give a VTMR below 1. Large empty quadrats matter for twin-engine aircraft on long routes, which must stay within a set flying time of an airport.

Over to [Person 4] for the last method, spatial regression.

## Person 4: Spatial Regression (2.5 min)

*Regression tab, already run.*

The last question is why some countries have more aircraft over them than others. For each country we count the aircraft overhead and model that count using population and GDP per capita. Land area and airport count can be added as well.

The model takes five steps. The first is an ordinary least squares regression. It gives an R-squared of [value], and [population] is the strongest predictor.

OLS assumes each country is independent of its neighbours, so step two tests that. We run Moran's I on the OLS residuals.

*Point at the residual Moran's I.*

It's [value], with a p-value of [value]. The residuals cluster in space, so countries next to each other are wrong in the same direction. OLS breaks its own assumption here, and its coefficients are biased.

Step three is the Lagrange multiplier tests, which tell us whether to model the problem as a spatial lag or a spatial error. Here the robust lag test is [significant], so step four fits a spatial lag model.

*Point at rho.*

Rho, the spatial lag coefficient, is [value]. It means a country's traffic depends partly on its neighbours' traffic. A lot of the planes over Kazakhstan or Sudan are flying between busier regions, and many of those countries charge overflight fees for exactly that traffic.

*Show the residual map.*

Step five is this residual map. Countries with positive residuals get more traffic than their population and economy predict, which usually means a transit corridor or a hub. Negative residuals show countries with less traffic than expected, and in Africa those are the gaps the Single African Air Transport Market is trying to close.

[Person 3] will finish off.

## Person 3: Wrap-up (1 min)

*Go back to the Home page.*

To sum up: autocorrelation showed where the traffic is, the quadrat test showed how clustered it is, and the regression looked at why some countries get more of it, including traffic spilling over from their neighbours.

The app has limits. Each snapshot is one moment, and traffic changes through the day. Coverage depends on where volunteers have put receivers, which is why Africa and the oceans look emptier than they are. The results also shift with the region, the hex size and the grid we choose, so it's worth trying a few settings before drawing conclusions.

That's SkyStats. Thank you, and we're happy to take questions.
