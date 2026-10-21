# Shared helpers for the stats_*.R files. Pure: no Shiny.

# Signal a problem the user can fix (too few points, wrong region, ...).
# run_safely() shows its message as is, without "The analysis failed".
stop_user <- function(...) {
  stop(structure(
    class = c("user_error", "error", "condition"),
    list(message = paste0(...), call = NULL)
  ))
}

# Evaluate expr and return list(ok = TRUE, value = <result>), or
# list(ok = FALSE, message = <chr>) if it fails. The modules show the
# message in an alert, so the user never sees a raw R error.
run_safely <- function(expr) {
  tryCatch(
    list(ok = TRUE, value = expr),
    user_error = function(e) list(ok = FALSE, message = conditionMessage(e)),
    error = function(e) {
      list(ok = FALSE, message = paste0("The analysis failed: ", conditionMessage(e)))
    }
  )
}

# "< 0.001" for very small p-values, else three decimals.
format_p <- function(p) {
  ifelse(p < 0.001, "< 0.001", sprintf("%.3f", p))
}

# One sentence with the test decision at significance level alpha, e.g.
# "p = 0.006 < α = 0.05, so we reject H0."
decision_text <- function(p, alpha) {
  alpha <- as.numeric(alpha)
  p_txt <- if (p < 0.001) "p < 0.001" else paste("p =", format_p(p))
  if (p < alpha) {
    paste0(p_txt, " < α = ", format(alpha), ", so we reject H0.")
  } else {
    paste0(p_txt, " ≥ α = ", format(alpha), ", so we do not reject H0.")
  }
}
