# Headline summaries of each method's result, for the results panel's
# summary card. Pure: no Shiny. Each takes the `value` of a successful run
# and returns list(label, value, digits, badge, tone, mini, text).

autocorr_summary <- function(res, statistic, alpha) {
  global <- res$global
  cluster <- res$lisa$cluster
  reject <- global$p_value < alpha

  label <- if (startsWith(global$statistic, "Global")) {
    global$statistic
  } else {
    paste("Global", global$statistic)
  }

  badge <- if (!reject) {
    "No clear pattern"
  } else if (statistic == "globalg") {
    "Hot spots"
  } else {
    "Clustered"
  }

  meaning <- if (!reject) {
    "Neighbouring hexes are no more alike than chance would give."
  } else if (statistic == "globalg") {
    "The busiest hexes sit together in hot spots."
  } else {
    "Busy hexes sit next to other busy hexes, so air traffic is clustered."
  }

  list(
    label = label,
    value = global$observed,
    digits = if (statistic == "globalg") 4L else 3L,
    badge = badge,
    tone = if (reject) "hot" else "neutral",
    mini = c(
      "z-score" = sprintf("%.2f", global$z),
      "p-value" = format_p(global$p_value),
      "Hexes" = as.character(nrow(res$lisa)),
      "Significant" = as.character(sum(cluster != "Not significant"))
    ),
    text = paste0(
      meaning, " LISA finds ", sum(cluster == "High-High"), " High-High and ",
      sum(cluster == "Low-Low"), " Low-Low hexes."
    )
  )
}

# Badge rule as quadrat_text(): not significant is Random, else a VTMR below
# 1 is Regular and above 1 is Clustered.
quadrat_summary <- function(res, alpha) {
  chisq <- res$chisq
  vtmr <- res$vtmr

  pattern <- if (vtmr$p_value >= alpha) {
    "Random"
  } else if (vtmr$vtmr < 1) {
    "Regular"
  } else {
    "Clustered"
  }

  list(
    label = "Variance-to-mean ratio",
    value = vtmr$vtmr,
    digits = 2L,
    badge = pattern,
    tone = c(Random = "neutral", Regular = "cool", Clustered = "hot")[[pattern]],
    mini = c(
      "χ²" = sprintf("%.1f", chisq$statistic),
      "χ² p-value" = format_p(chisq$p_value),
      "VTMR p-value" = format_p(vtmr$p_value),
      "Quadrats" = as.character(vtmr$m)
    ),
    text = c(
      Random = "The points are spread about as evenly as chance would give (consistent with CSR).",
      Regular = "The points are more evenly spaced than chance would give.",
      Clustered = "The points bunch together more than chance would give."
    )[[pattern]]
  )
}

# Only the OLS residual Moran's I is shown: run_regression() does not return
# the Moran's I of the lag residuals.
regression_summary <- function(res) {
  rec <- res$recommendation
  aic <- function(model) res$aic$aic[res$aic$model == model]

  list(
    label = "Spatial lag ρ",
    value = res$rho,
    digits = 3L,
    badge = c(
      "OLS" = "OLS is enough",
      "Spatial lag" = "Spatial lag model",
      "Spatial error" = "Spatial error model"
    )[[rec]],
    tone = if (rec == "OLS") "neutral" else "info",
    mini = c(
      "ρ p-value" = format_p(res$rho_p_value),
      "Residual Moran's I" = sprintf("%.3f", res$resid_moran$observed),
      "AIC (OLS)" = sprintf("%.2f", aic("OLS")),
      "AIC (lag)" = sprintf("%.2f", aic("Spatial lag"))
    ),
    text = c(
      "OLS" = "The OLS residuals show no spatial pattern, so plain OLS is enough.",
      "Spatial lag" = "A country's traffic depends on its neighbours' traffic, so the LM tests point to the spatial lag model.",
      "Spatial error" = "The LM tests point to a spatial error model. The lag model is shown for comparison."
    )[[rec]]
  )
}
