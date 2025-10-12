#!/usr/bin/env Rscript
# ==============================================================================
# 05_validate.R
# Purpose: Compute test metrics + calibration curves on held-out weeks
# ==============================================================================
# Inputs:  --in (artifacts/<timestamp>/xgb), --report (reports path)
# Outputs: reports/model_compare_<timestamp>.md
#
# Stage Gate Tests:
#   - Held-out week(s) metrics reported
#   - Calibration slope ∈ [0.8, 1.2] or flagged
#   - Log loss and Brier computed
#
# Metrics:
#   - Overall: log loss, Brier score, AUC
#   - By context slices: season, week, spread bucket, elo diff bucket
#   - Calibration: slope, intercept, reliability diagram
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(xgboost)
  library(yardstick)
  library(ggplot2)
  library(pROC)
  library(jsonlite)
})

# TODO: Parse command-line arguments (in path, report path)
# TODO: Load saved model object and test data
# TODO: Generate predictions on held-out weeks
# TODO: Compute overall metrics (log loss, Brier, AUC)
# TODO: Compute metrics by context slices
# TODO: Compute calibration slope and intercept
# TODO: Generate reliability diagram
# TODO: Write markdown report with metrics tables and plots
# TODO: Print summary: test metrics, calibration assessment, elapsed time

cat("05_validate.R stub loaded. Ready for implementation.\n")
