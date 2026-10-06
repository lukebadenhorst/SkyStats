# Reference tables committed under data/lookups/ (built by
# data-raw/build_lookups.R). Pure functions, no Shiny.

airlines_path <- file.path("data", "lookups", "airlines.rds")

# Columns: icao, name, country. An empty table if the file is missing, so the
# app still runs and the picker falls back to bare codes.
load_airlines <- function(path = airlines_path) {
  if (!file.exists(path)) {
    return(data.frame(icao = character(), name = character(), country = character()))
  }
  readRDS(path)
}

airline_name <- function(code, airlines) {
  unname(airlines$name[match(code, airlines$icao)])
}

# ---- Flight category rules (used by flight_category()) ---------------------
# Hand-listed ICAO codes that the airline-name patterns below miss.

# Air Mobility Command (Reach), US Navy, Priority Air Transport (US Army),
# Canadian Forces, French and Italian air forces.
military_codes <- c("RCH", "CNV", "PAT", "CFC", "CTM", "IAM")
military_name_pattern <- "air force|navy|army|militar|armed forces|air corps"

# FedEx, UPS, DHL group, Atlas, Kalitta, ABX, ATN, Amerijet, Martinair,
# TNT/ASL Belgium, West Atlantic.
cargo_codes <- c(
  "FDX", "UPS", "DHK", "BCS", "DHX", "DAE", "GTI", "CKS",
  "ABX", "ATN", "AJT", "MPH", "TAY", "SWN"
)
cargo_name_pattern <- "cargo|freight"

# NetJets, Flexjet, VistaJet, XOJET, Executive Jet Management, Wheels Up.
bizjet_codes <- c("EJA", "NJE", "LXJ", "VJT", "XOJ", "EJM", "WUP")
