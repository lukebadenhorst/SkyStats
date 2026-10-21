# Build the lookup tables committed under data/lookups/.
# Run from the project root: Rscript data-raw/build_lookups.R
# Needs internet access. No OpenSky credits are used.

source(file.path("R", "lookups.R"))

# OpenFlights airlines: ICAO code -> airline name and country.
airlines_url <- "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airlines.dat"

raw <- utils::read.csv(
  airlines_url,
  header = FALSE,
  na.strings = c("\\N", ""),
  encoding = "UTF-8",
  stringsAsFactors = FALSE,
  col.names = c("id", "name", "alias", "iata", "icao", "callsign", "country", "active")
)

raw <- raw[!is.na(raw$icao) & grepl("^[A-Z]{3}$", raw$icao), , drop = FALSE]

# Several defunct airlines share an ICAO code with a current one, so keep the
# active row where there is one, then the first listed.
raw <- raw[order(raw$icao, raw$active != "Y", raw$id), , drop = FALSE]
raw <- raw[!duplicated(raw$icao), , drop = FALSE]

airlines <- data.frame(
  icao = raw$icao,
  name = trimws(raw$name),
  country = raw$country,
  row.names = NULL
)

# OpenFlights stopped updating around 2017. Fill in common codes it lacks
# (the most frequent unnamed codes in the Oct 2026 sample snapshot).
extra <- data.frame(
  icao = c(
    "EDV", "EJU", "WMT", "NSZ", "NJE", "MXY", "BEL", "NOZ",
    "ITY", "TKJ", "EFW", "EZS", "WUK", "AKJ", "RUK", "MBU",
    "WUP", "CNV"
  ),
  name = c(
    "Endeavor Air", "easyJet Europe", "Wizz Air Malta", "Norwegian Air Sweden",
    "NetJets Europe", "Breeze Airways", "Brussels Airlines", "Norwegian Air Norway",
    "ITA Airways", "AJet", "BA Euroflyer", "easyJet Switzerland",
    "Wizz Air UK", "Akasa Air", "Ryanair UK", "Marabu Airlines",
    "Wheels Up", "United States Navy"
  ),
  country = c(
    "United States", "Austria", "Malta", "Sweden",
    "Portugal", "United States", "Belgium", "Norway",
    "Italy", "Turkey", "United Kingdom", "Switzerland",
    "United Kingdom", "India", "United Kingdom", "Estonia",
    "United States", "United States"
  )
)
airlines <- rbind(airlines, extra[!extra$icao %in% airlines$icao, ])
airlines <- airlines[order(airlines$icao), ]
rownames(airlines) <- NULL

dir.create(dirname(airlines_path), recursive = TRUE, showWarnings = FALSE)
saveRDS(airlines, airlines_path, compress = "xz")

message(
  "Saved ",
  nrow(airlines),
  " airlines to ",
  airlines_path,
  " (",
  round(file.size(airlines_path) / 1024),
  " KB)"
)

# OurAirports: large and medium airports with their location and country.
# na.strings = "" only: the default would turn Namibia's ISO code "NA" into a
# missing value.
airports_url <- "https://davidmegginson.github.io/ourairports-data/airports.csv"

raw <- utils::read.csv(
  airports_url,
  na.strings = "",
  encoding = "UTF-8",
  stringsAsFactors = FALSE
)
raw <- raw[raw$type %in% c("large_airport", "medium_airport"), , drop = FALSE]

airports <- data.frame(
  ident = raw$ident,
  type = raw$type,
  name = raw$name,
  latitude = raw$latitude_deg,
  longitude = raw$longitude_deg,
  iso_country = raw$iso_country,
  row.names = NULL
)
airports <- airports[!is.na(airports$latitude) & !is.na(airports$longitude), ]
airports <- airports[order(airports$ident), ]
rownames(airports) <- NULL

saveRDS(airports, airports_path, compress = "xz")

message(
  "Saved ",
  nrow(airports),
  " airports to ",
  airports_path,
  " (",
  round(file.size(airports_path) / 1024),
  " KB)"
)
