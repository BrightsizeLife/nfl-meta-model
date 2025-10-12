#!/usr/bin/env Rscript
# ==============================================================================
# 03_eda.R
# Purpose: Exploratory data analysis - structure checks, histograms, slices
# ==============================================================================
# Inputs:  --in (data/processed path)
# Outputs: reports/eda_<timestamp>.md, artifacts/<timestamp>/eda/ (plots)
#
# Stage Gate Tests:
#   - Histograms + pairplots saved
#   - Leakage checks: no post-game info in features
#   - Distribution summaries by season/week
#
# Checks:
#   - Target balance (home_win)
#   - Feature correlations
#   - Missing value patterns
#   - Outlier detection
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(purrr)
})

# TODO: Parse command-line arguments (in path)
# TODO: Read games.csv and context.csv
# TODO: Join on game_id
# TODO: Generate target balance histogram
# TODO: Generate feature correlation matrix
# TODO: Generate univariate distributions for key features
# TODO: Check for leakage (features computed only from pre-game data)
# TODO: Save plots to artifacts/<timestamp>/eda/
# TODO: Generate markdown report with summary stats
# TODO: Print summary: plots created, leakage flags, elapsed time

cat("03_eda.R stub loaded. Ready for implementation.\n")
