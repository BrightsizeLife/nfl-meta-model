#!/usr/bin/env Rscript
# ==============================================================================
# 06_score.R
# Purpose: Score upcoming games with trained model
# ==============================================================================
# Inputs:  --model (artifacts/<timestamp>/xgb), --in (data/processed)
# Outputs: data/processed/predictions_<timestamp>.csv
#
# Workflow:
#   - Load trained model
#   - Load features for upcoming games (current week)
#   - Generate predictions (prob_home, prob_away)
#   - Write predictions CSV
#
# Output Schema:
#   game_id, date, home_team, away_team, prob_home, prob_away, predicted_at
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(xgboost)
  library(lubridate)
  library(jsonlite)
})

# TODO: Parse command-line arguments (model path, in path)
# TODO: Load trained XGBoost model
# TODO: Identify upcoming games (current week, no results yet)
# TODO: Load features for upcoming games
# TODO: Generate predictions
# TODO: Format output with game_id, teams, probabilities, timestamp
# TODO: Write predictions_<timestamp>.csv
# TODO: Print summary: games scored, avg prob_home, elapsed time

cat("06_score.R stub loaded. Ready for implementation.\n")
