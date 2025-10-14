#!/usr/bin/env Rscript
# ==============================================================================
# 05_validate.R
# Purpose: Time-sliced validation comparing model vs market baseline
# ==============================================================================
# Inputs:  --model_dir (artifacts/<ts>/xgb), --out (artifacts/<ts>/eval)
# Outputs: by_season.csv, by_season_week.csv (metrics for model + market)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(xgboost)
  library(purrr)
})

source("R/utils/market.R")
source("R/utils/eval.R")

start_time <- Sys.time()

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)
model_dir <- "artifacts/20251014_000127/xgb"
out_dir <- "artifacts/20251014_000127/eval"

for (i in seq_along(args)) {
  if (args[i] == "--model_dir" && i < length(args)) {
    model_dir <- args[i + 1]
  } else if (args[i] == "--out" && i < length(args)) {
    out_dir <- args[i + 1]
  }
}

cat(sprintf("Model directory: %s\n", model_dir))
cat(sprintf("Output directory: %s\n", out_dir))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Load data
cat("\n=== Loading Data ===\n")
games <- read_csv("data/raw/games_20251013_202758.csv", show_col_types = FALSE)
context <- read_csv("data/processed/context_20251014_043920.csv", show_col_types = FALSE)

data <- context %>%
  left_join(games %>% select(game_id, home_win), by = "game_id")

# Split train/test (same as XGBoost training)
train_data <- data %>% filter(season < 2023 | (season == 2022 & week <= 20))
test_data <- data %>% filter(season > 2022 | (season == 2022 & week > 20))

cat(sprintf("Train: %d games\n", nrow(train_data)))
cat(sprintf("Test:  %d games\n", nrow(test_data)))

# Load XGBoost model
cat("\n=== Loading XGBoost Model ===\n")
model_file <- file.path(model_dir, "model.xgb")
xgb_model <- xgb.load(model_file)
cat(sprintf("✓ Model loaded from %s\n", model_file))

# Prepare features for XGBoost (v1.1)
feature_cols <- c(
  "home", "spread_close", "total_close", "week",
  "rest_home_capped", "rest_away_capped",
  "first_game_home", "first_game_away",
  "prev_margin_home", "prev_margin_away", "elo_diff"
)

test_matrix <- xgb.DMatrix(
  data = as.matrix(test_data[, feature_cols]),
  label = test_data$home_win
)

# Model predictions
test_data$model_prob <- predict(xgb_model, test_matrix)

# Fit and predict with market baseline
cat("\n=== Fitting Market Baseline ===\n")
market_model <- fit_market_baseline(train_data, method = "isotonic")
test_data$market_prob <- market_prob(test_data$spread_close, market_model)

# Compute metrics
logloss <- function(y, p) {
  p <- pmax(pmin(p, 1 - 1e-15), 1e-15)
  -mean(y * log(p) + (1 - y) * log(1 - p))
}

brier <- function(y, p) mean((y - p)^2)

calib_slope <- function(y, p) {
  fit <- glm(y ~ p, family = binomial(link = "logit"))
  coef(fit)[2]
}

calib_intercept <- function(y, p) {
  fit <- glm(y ~ p, family = binomial(link = "logit"))
  coef(fit)[1]
}

# Overall metrics
cat("\n=== Overall Test Metrics ===\n")
overall <- data.frame(
  source = c("model", "market"),
  logloss = c(
    logloss(test_data$home_win, test_data$model_prob),
    logloss(test_data$home_win, test_data$market_prob)
  ),
  brier = c(
    brier(test_data$home_win, test_data$model_prob),
    brier(test_data$home_win, test_data$market_prob)
  ),
  calib_slope = c(
    calib_slope(test_data$home_win, test_data$model_prob),
    calib_slope(test_data$home_win, test_data$market_prob)
  ),
  calib_intercept = c(
    calib_intercept(test_data$home_win, test_data$model_prob),
    calib_intercept(test_data$home_win, test_data$market_prob)
  )
)

print(overall)

# By season
cat("\n=== By Season Metrics ===\n")
by_season <- test_data %>%
  group_by(season) %>%
  summarise(
    n = n(),
    # Model
    model_logloss = logloss(home_win, model_prob),
    model_brier = brier(home_win, model_prob),
    model_calib_slope = calib_slope(home_win, model_prob),
    model_calib_intercept = calib_intercept(home_win, model_prob),
    # Market
    market_logloss = logloss(home_win, market_prob),
    market_brier = brier(home_win, market_prob),
    market_calib_slope = calib_slope(home_win, market_prob),
    market_calib_intercept = calib_intercept(home_win, market_prob),
    .groups = "drop"
  )

print(by_season)

# By season-week
cat("\n=== By Season-Week Metrics (saving to CSV) ===\n")
by_season_week <- test_data %>%
  group_by(season, week) %>%
  summarise(
    n = n(),
    # Model
    model_logloss = logloss(home_win, model_prob),
    model_brier = brier(home_win, model_prob),
    # Market
    market_logloss = logloss(home_win, market_prob),
    market_brier = brier(home_win, market_prob),
    .groups = "drop"
  )

cat(sprintf("Computed %d season-week slices\n", nrow(by_season_week)))

# Save results
write_csv(overall, file.path(out_dir, "overall.csv"))
write_csv(by_season, file.path(out_dir, "by_season.csv"))
write_csv(by_season_week, file.path(out_dir, "by_season_week.csv"))

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat("\n=== Summary ===\n")
cat(sprintf("✓ Validation complete\n"))
cat(sprintf("  Model wins: %d/%d seasons by log loss\n",
           sum(by_season$model_logloss < by_season$market_logloss),
           nrow(by_season)))
cat(sprintf("  Overall delta: %.4f log loss (model - market)\n",
           overall$logloss[1] - overall$logloss[2]))
cat(sprintf("  Outputs: %s/*.csv\n", out_dir))
cat(sprintf("  Elapsed: %.2f seconds\n", elapsed))
