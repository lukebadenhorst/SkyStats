# Capture one global /states/all snapshot as the bundled sample.
# Run from the project root: Rscript data-raw/capture_sample.R
# Needs OPENSKY_CLIENT_ID / OPENSKY_CLIENT_SECRET in ~/.Renviron. Costs 4 credits.

source(file.path("R", "data_api.R"))

if (!opensky_has_credentials()) {
  stop("Set OPENSKY_CLIENT_ID and OPENSKY_CLIENT_SECRET in ~/.Renviron first.")
}

snapshot <- fetch_states_live()
dir.create(dirname(sample_states_path), recursive = TRUE, showWarnings = FALSE)
saveRDS(snapshot, sample_states_path, compress = "xz")

message(
  "Saved ",
  nrow(snapshot$data),
  " aircraft at ",
  format(snapshot$time, "%Y-%m-%d %H:%M UTC"),
  " to ",
  sample_states_path,
  " (",
  round(file.size(sample_states_path) / 1024),
  " KB)"
)
