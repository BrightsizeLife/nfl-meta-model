#!/usr/bin/env Rscript
# ==============================================================================
# 04_xgb_fit.R
# Purpose: Fit XGBoost model with rolling weekly CV
# ==============================================================================
# Inputs:  --in (data/processed), --cv (weekly/expanding), --seed
# Outputs: artifacts/<timestamp>/xgb/ (model, params, CV results, SHAP, plots)
#
# Stage Gate Tests:
#   - Rolling weekly CV completed
#   - Log loss & Brier computed overall + by context slices
#   - No feature with >20% missing post-imputation
#   - Calibration slope ∈ [0.8, 1.2] or flagged
#
# Model Spec:
#   Target: home_win (0/1)
#   Predictors: home, spread_close, total_close, week, rest_*, prev_margin_*,
#               elo_diff, wind_mph, temp_f, precip_mm
#   CV: Rolling by week within season
#   Tuning: Randomized search (max_depth, eta, min_child_weight, subsample,
#           colsample_bytree, lambda)
#   Diagnostics: SHAP summary, partial dependence (top 5), reliability curve,
#                calibration slope/intercept
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(xgboost)
  library(rsample)
  library(yardstick)
  library(ggplot2)
  library(pROC)
  library(jsonlite)
})

# TODO: Parse command-line arguments (in path, cv method, seed)
# TODO: Read games.csv and context.csv; join on game_id
# TODO: Create rolling weekly CV folds
# TODO: Define hyperparameter search grid
# TODO: Run randomized search with cross-validation
# TODO: Fit final model on all training data with best params
# TODO: Compute SHAP values for feature importance
# TODO: Generate partial dependence plots for top 5 features
# TODO: Compute reliability curve (10 bins)
# TODO: Compute calibration slope and intercept
# TODO: Save model object, params, CV results, SHAP CSV, plots
# TODO: Print summary: best params, CV metrics, top features, elapsed time

cat("04_xgb_fit.R stub loaded. Ready for implementation.\n")
