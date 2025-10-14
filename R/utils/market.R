#!/usr/bin/env Rscript
# ==============================================================================
# market.R
# Purpose: Market baseline utilities for NFL game prediction
# ==============================================================================
# Functions:
#   - fit_market_baseline: Learn spread → P(home_win) mapping from training data
#   - market_prob: Predict P(home_win) from spread using fitted baseline
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stats)
})

#' Fit market baseline model
#'
#' Maps closing spread to home win probability using isotonic regression
#' or binning approach. Trains on training data only.
#'
#' @param data Training data with columns: spread_close, home_win
#' @param method One of "isotonic", "binned", "logistic"
#' @param n_bins Number of bins for "binned" method (default 20)
#' @return Market baseline model object (list with method and fitted params)
#'
#' @examples
#' train_data <- data.frame(
#'   spread_close = rnorm(100, 0, 5),
#'   home_win = rbinom(100, 1, 0.5)
#' )
#' market_model <- fit_market_baseline(train_data, method = "isotonic")
fit_market_baseline <- function(data, method = "isotonic", n_bins = 20) {

  if (!all(c("spread_close", "home_win") %in% names(data))) {
    stop("Data must contain 'spread_close' and 'home_win' columns")
  }

  # Remove NA values
  data_clean <- data %>%
    filter(!is.na(spread_close), !is.na(home_win))

  if (nrow(data_clean) == 0) {
    stop("No valid training data after removing NAs")
  }

  cat(sprintf("Fitting market baseline using method: %s\n", method))
  cat(sprintf("Training samples: %d\n", nrow(data_clean)))

  if (method == "isotonic") {
    # Isotonic regression: monotonic mapping from spread to probability
    # Sort by spread (higher spread = more home favored = higher prob)
    data_sorted <- data_clean %>% arrange(spread_close)

    # Fit isotonic regression (monotonically increasing)
    # Note: spread is from home perspective, so positive = home favored
    # We need to negate spread so isotonic constraint works (lower spread = higher prob)
    iso_model <- isoreg(x = -data_sorted$spread_close, y = data_sorted$home_win)

    model <- list(
      method = "isotonic",
      iso_model = iso_model,
      spread_range = range(data_clean$spread_close)
    )

  } else if (method == "binned") {
    # Binned approach: group spreads into bins and compute empirical freq
    data_binned <- data_clean %>%
      mutate(
        spread_bin = cut(spread_close,
                        breaks = n_bins,
                        include.lowest = TRUE)
      ) %>%
      group_by(spread_bin) %>%
      summarise(
        n = n(),
        home_win_rate = mean(home_win),
        spread_mid = mean(spread_close),
        .groups = "drop"
      ) %>%
      filter(n >= 5)  # Require at least 5 games per bin

    if (nrow(data_binned) == 0) {
      stop("No bins with >= 5 games. Try fewer bins.")
    }

    model <- list(
      method = "binned",
      bin_map = data_binned,
      spread_range = range(data_clean$spread_close)
    )

  } else if (method == "logistic") {
    # Logistic regression: parametric fit
    # P(home_win) = logit^-1(β0 + β1 * spread_close)
    glm_model <- glm(home_win ~ spread_close,
                     data = data_clean,
                     family = binomial(link = "logit"))

    model <- list(
      method = "logistic",
      glm_model = glm_model,
      spread_range = range(data_clean$spread_close)
    )

  } else {
    stop(sprintf("Unknown method: %s. Use 'isotonic', 'binned', or 'logistic'", method))
  }

  # Add metadata
  model$n_train <- nrow(data_clean)
  model$spread_mean <- mean(data_clean$spread_close)
  model$spread_sd <- sd(data_clean$spread_close)
  model$home_win_rate <- mean(data_clean$home_win)

  cat(sprintf("✓ Market baseline fitted\n"))
  cat(sprintf("  Spread range: [%.1f, %.1f]\n", model$spread_range[1], model$spread_range[2]))
  cat(sprintf("  Home win rate: %.3f\n", model$home_win_rate))

  return(model)
}


#' Predict home win probability from spread using market baseline
#'
#' @param spread_close Vector of closing spreads (home perspective)
#' @param market_model Market baseline model from fit_market_baseline()
#' @return Vector of home win probabilities
#'
#' @examples
#' spread_new <- c(-7, -3, 0, 3, 7)
#' probs <- market_prob(spread_new, market_model)
market_prob <- function(spread_close, market_model) {

  if (market_model$method == "isotonic") {
    # Use predict on isotonic regression via approx
    # Remember we negated spread during fitting
    iso <- market_model$iso_model

    # Use approx for interpolation (isoreg doesn't have predict method)
    pred_prob <- approx(x = iso$x, y = iso$yf,
                       xout = -spread_close,
                       rule = 2,  # Constant extrapolation
                       ties = mean)$y

    # Clip to [0, 1]
    pred_prob <- pmin(pmax(pred_prob, 0), 1)

  } else if (market_model$method == "binned") {
    # Find nearest bin for each spread
    bin_map <- market_model$bin_map

    pred_prob <- sapply(spread_close, function(s) {
      # Find bin with closest spread_mid
      idx <- which.min(abs(bin_map$spread_mid - s))
      return(bin_map$home_win_rate[idx])
    })

  } else if (market_model$method == "logistic") {
    # Use predict on logistic regression
    pred_df <- data.frame(spread_close = spread_close)
    pred_prob <- predict(market_model$glm_model,
                        newdata = pred_df,
                        type = "response")

  } else {
    stop(sprintf("Unknown market model method: %s", market_model$method))
  }

  # Handle out-of-range spreads by clipping
  out_of_range <- spread_close < market_model$spread_range[1] |
                  spread_close > market_model$spread_range[2]

  if (any(out_of_range)) {
    warning(sprintf("%d spreads out of training range [%.1f, %.1f]",
                   sum(out_of_range),
                   market_model$spread_range[1],
                   market_model$spread_range[2]))
  }

  return(as.numeric(pred_prob))
}


#' Save market baseline model to RDS
#'
#' @param market_model Market baseline model object
#' @param path Output path for RDS file
save_market_model <- function(market_model, path) {
  saveRDS(market_model, path)
  cat(sprintf("✓ Market model saved to: %s\n", path))
}


#' Load market baseline model from RDS
#'
#' @param path Path to RDS file
#' @return Market baseline model object
load_market_model <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Market model file not found: %s", path))
  }

  model <- readRDS(path)
  cat(sprintf("✓ Market model loaded from: %s\n", path))
  cat(sprintf("  Method: %s\n", model$method))
  cat(sprintf("  Training samples: %d\n", model$n_train))

  return(model)
}
