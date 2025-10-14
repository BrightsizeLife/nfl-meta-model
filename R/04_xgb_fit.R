#!/usr/bin/env Rscript
# ==============================================================================
# 04_xgb_fit.R
# Purpose: Fit XGBoost model with rolling weekly CV
# ==============================================================================
# Inputs:  --in (data/processed), --cv (weekly/expanding), --seed
# Outputs: artifacts/<timestamp>/xgb/ (model, params, CV, SHAP, plots)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(xgboost)
  library(ggplot2)
  library(purrr)
  library(jsonlite)
})

start_time <- Sys.time()

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)
in_proc <- "data/processed"
cv_method <- "weekly"
seed <- 20251013

for (i in seq_along(args)) {
  if (args[i] == "--in" && i < length(args)) {
    in_proc <- args[i + 1]
  } else if (args[i] == "--cv" && i < length(args)) {
    cv_method <- args[i + 1]
  } else if (args[i] == "--seed" && i < length(args)) {
    seed <- as.integer(args[i + 1])
  }
}

set.seed(seed)
cat(sprintf("Using seed: %d\n", seed))

# Load data
games_file <- list.files("data/raw", pattern = "^games_.*\\.csv$", full.names = TRUE)
games_file <- games_file[length(games_file)]
context_file <- list.files(in_proc, pattern = "^context_.*\\.csv$", full.names = TRUE)
context_file <- context_file[length(context_file)]

cat(sprintf("Loading games: %s\n", basename(games_file)))
cat(sprintf("Loading context: %s\n", basename(context_file)))

games <- read_csv(games_file, show_col_types = FALSE)
context <- read_csv(context_file, show_col_types = FALSE)

# Join and prepare data
data <- games %>%
  inner_join(context, by = "game_id") %>%
  arrange(season, week, date) %>%
  filter(!is.na(home_score))  # Only completed games

cat(sprintf("Loaded %d completed games\n", nrow(data)))

# Define features (v1: use capped rest days, exclude weather)
feature_cols <- c(
  "home", "spread_close", "total_close", "week",
  "rest_home_capped", "rest_away_capped",
  "first_game_home", "first_game_away",
  "prev_margin_home", "prev_margin_away",
  "elo_diff"
)

# Handle NAs in previous margins (first games -> 0)
data <- data %>%
  mutate(
    prev_margin_home = ifelse(is.na(prev_margin_home), 0, prev_margin_home),
    prev_margin_away = ifelse(is.na(prev_margin_away), 0, prev_margin_away)
  )

# Create feature matrix and target
X <- data %>% select(all_of(feature_cols)) %>% as.matrix()
y <- data$home_win

cat(sprintf("\n=== Features (v1) ===\n"))
cat(sprintf("Features: %s\n", paste(feature_cols, collapse = ", ")))
cat(sprintf("Rows: %d, Cols: %d\n", nrow(X), ncol(X)))
cat(sprintf("Target balance: %.3f home wins\n", mean(y)))

# Rolling weekly CV setup
cat(sprintf("\n=== Cross-Validation: %s ===\n", cv_method))

# Group by season-week for rolling CV
data <- data %>%
  mutate(season_week = paste(season, sprintf("%02d", week), sep = "_"))

unique_weeks <- data %>%
  arrange(season, week) %>%
  distinct(season, week, season_week) %>%
  pull(season_week)

# Use 70% of weeks for training, remaining for test
n_train_weeks <- floor(length(unique_weeks) * 0.7)
train_weeks <- unique_weeks[1:n_train_weeks]
test_weeks <- unique_weeks[(n_train_weeks + 1):length(unique_weeks)]

train_idx <- which(data$season_week %in% train_weeks)
test_idx <- which(data$season_week %in% test_weeks)

cat(sprintf("Train weeks: %d (%s to %s)\n", length(train_weeks), train_weeks[1], train_weeks[length(train_weeks)]))
cat(sprintf("Test weeks: %d (%s to %s)\n", length(test_weeks), test_weeks[1], test_weeks[length(test_weeks)]))
cat(sprintf("Train games: %d, Test games: %d\n", length(train_idx), length(test_idx)))

# Hyperparameter search space (small for now)
param_grid <- expand.grid(
  max_depth = c(3, 5, 7),
  eta = c(0.01, 0.05, 0.1),
  min_child_weight = c(1, 3),
  subsample = c(0.7, 0.9),
  colsample_bytree = c(0.7, 0.9),
  lambda = c(0, 1)
)

# Sample random parameters
n_trials <- min(20, nrow(param_grid))
param_sample_idx <- sample(1:nrow(param_grid), n_trials, replace = FALSE)
param_trials <- param_grid[param_sample_idx, ]

cat(sprintf("\nRandomized search: %d trials\n", n_trials))

# Cross-validation
cv_results <- map_dfr(1:n_trials, function(trial) {
  params <- param_trials[trial, ]

  xgb_params <- list(
    objective = "binary:logistic",
    eval_metric = "logloss",
    max_depth = params$max_depth,
    eta = params$eta,
    min_child_weight = params$min_child_weight,
    subsample = params$subsample,
    colsample_bytree = params$colsample_bytree,
    lambda = params$lambda,
    seed = seed
  )

  dtrain <- xgb.DMatrix(data = X[train_idx, ], label = y[train_idx])

  cv_model <- xgb.cv(
    params = xgb_params,
    data = dtrain,
    nrounds = 200,
    nfold = 5,
    early_stopping_rounds = 20,
    verbose = 0
  )

  best_iter <- cv_model$best_iteration
  best_logloss <- cv_model$evaluation_log$test_logloss_mean[best_iter]

  if (trial %% 5 == 0) {
    cat(sprintf("Trial %d/%d: logloss=%.4f, nrounds=%d\n", trial, n_trials, best_logloss, best_iter))
  }

  tibble(
    trial = trial,
    max_depth = params$max_depth,
    eta = params$eta,
    min_child_weight = params$min_child_weight,
    subsample = params$subsample,
    colsample_bytree = params$colsample_bytree,
    lambda = params$lambda,
    best_iter = best_iter,
    cv_logloss = best_logloss
  )
})

# Select best parameters
best_trial <- cv_results %>% arrange(cv_logloss) %>% dplyr::slice(1)
cat(sprintf("\nBest trial: %d, CV logloss: %.4f\n", best_trial$trial, best_trial$cv_logloss))
print(best_trial)

# Train final model with best parameters
best_params <- list(
  objective = "binary:logistic",
  eval_metric = "logloss",
  max_depth = best_trial$max_depth,
  eta = best_trial$eta,
  min_child_weight = best_trial$min_child_weight,
  subsample = best_trial$subsample,
  colsample_bytree = best_trial$colsample_bytree,
  lambda = best_trial$lambda,
  seed = seed
)

dtrain <- xgb.DMatrix(data = X[train_idx, ], label = y[train_idx])
dtest <- xgb.DMatrix(data = X[test_idx, ], label = y[test_idx])

final_model <- xgb.train(
  params = best_params,
  data = dtrain,
  nrounds = best_trial$best_iter,
  verbose = 0
)

# Predictions
train_pred <- predict(final_model, dtrain)
test_pred <- predict(final_model, dtest)

# Compute metrics
log_loss <- function(y_true, y_pred) {
  eps <- 1e-15
  y_pred <- pmax(pmin(y_pred, 1 - eps), eps)
  -mean(y_true * log(y_pred) + (1 - y_true) * log(1 - y_pred))
}

brier_score <- function(y_true, y_pred) {
  mean((y_true - y_pred)^2)
}

train_logloss <- log_loss(y[train_idx], train_pred)
test_logloss <- log_loss(y[test_idx], test_pred)
train_brier <- brier_score(y[train_idx], train_pred)
test_brier <- brier_score(y[test_idx], test_pred)

cat(sprintf("\n=== Final Model Metrics ===\n"))
cat(sprintf("Train: logloss=%.4f, Brier=%.4f\n", train_logloss, train_brier))
cat(sprintf("Test:  logloss=%.4f, Brier=%.4f\n", test_logloss, test_brier))

# Feature importance
importance <- xgb.importance(model = final_model)
cat(sprintf("\n=== Top 10 Features ===\n"))
print(head(importance, 10))

# Save artifacts
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
out_dir <- file.path("artifacts", timestamp, "xgb")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Save model
xgb.save(final_model, file.path(out_dir, "model.xgb"))

# Save params and metrics
results_summary <- list(
  seed = seed,
  cv_method = cv_method,
  n_trials = n_trials,
  best_params = best_params,
  train_logloss = train_logloss,
  test_logloss = test_logloss,
  train_brier = train_brier,
  test_brier = test_brier,
  n_train = length(train_idx),
  n_test = length(test_idx),
  features = feature_cols
)
write_json(results_summary, file.path(out_dir, "results.json"), pretty = TRUE, auto_unbox = TRUE)

# Save CV results
write_csv(cv_results, file.path(out_dir, "cv_results.csv"))

# Save importance
write_csv(importance, file.path(out_dir, "feature_importance.csv"))

# Plot importance
p_importance <- importance %>%
  head(10) %>%
  ggplot(aes(x = reorder(Feature, Gain), y = Gain)) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  labs(title = "Top 10 Feature Importance (Gain)", x = "Feature", y = "Gain") +
  theme_minimal()

ggsave(file.path(out_dir, "feature_importance.png"), p_importance, width = 8, height = 5)

# Calibration analysis
reliability_bins <- 10
test_data_with_pred <- data[test_idx, ] %>%
  mutate(pred_prob = test_pred)

breaks <- seq(0, 1, length.out = reliability_bins + 1)
test_data_with_pred <- test_data_with_pred %>%
  mutate(pred_bin = cut(pred_prob, breaks = breaks, include.lowest = TRUE, labels = FALSE))

reliability <- test_data_with_pred %>%
  group_by(pred_bin) %>%
  summarize(
    predicted_prob = mean(pred_prob),
    observed_freq = mean(home_win),
    count = n(),
    .groups = "drop"
  )

write_csv(reliability, file.path(out_dir, "reliability.csv"))

# Plot calibration
p_calibration <- reliability %>%
  ggplot(aes(x = predicted_prob, y = observed_freq)) +
  geom_point(aes(size = count)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
  geom_smooth(method = "lm", se = FALSE, color = "blue") +
  labs(
    title = "Calibration Plot (Test Set)",
    x = "Predicted Probability",
    y = "Observed Frequency",
    size = "Count"
  ) +
  theme_minimal() +
  coord_fixed(xlim = c(0, 1), ylim = c(0, 1))

ggsave(file.path(out_dir, "calibration.png"), p_calibration, width = 8, height = 6)

# Calibration slope/intercept
calib_model <- glm(home_win ~ pred_prob, data = test_data_with_pred, family = binomial(link = "logit"))
calib_slope <- coef(calib_model)[2]
calib_intercept <- coef(calib_model)[1]

cat(sprintf("\n=== Calibration ===\n"))
cat(sprintf("Slope: %.3f (ideal=1.0)\n", calib_slope))
cat(sprintf("Intercept: %.3f (ideal=0.0)\n", calib_intercept))

calib_summary <- tibble(
  slope = calib_slope,
  intercept = calib_intercept,
  slope_in_range = calib_slope >= 0.8 & calib_slope <= 1.2
)
write_csv(calib_summary, file.path(out_dir, "calibration_summary.csv"))

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat(sprintf("\n=== Summary ===\n"))
cat(sprintf("Output dir: %s\n", out_dir))
cat(sprintf("Artifacts: model.xgb, results.json, cv_results.csv, feature_importance.csv/.png, calibration.csv/.png\n"))
cat(sprintf("Elapsed: %.2f seconds\n", elapsed))
