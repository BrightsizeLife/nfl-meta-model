#!/usr/bin/env Rscript
# ==============================================================================
# 02_features.R
# Purpose: Build context.csv with game-level features from games.csv
# ==============================================================================
# Inputs:  --in (data/raw path), --out (data/processed), --elo_seed (e.g., five38)
# Outputs: data/processed/context_<timestamp>.csv + provenance JSON
#
# Stage Gate Tests:
#   - context.csv fully joinable to games.csv (1:1 on game_id)
#   - week ∈ [1, 22]; rest_days ∈ [0, 14]; winds ≥ 0; elo_diff finite
#   - Date parsing success > 99.5%
#   - Join cardinality check (no orphans)
#
# Data Contract (context.csv):
#   game_id
#   Structure: home, rest_home, rest_away, prev_margin_home, prev_margin_away
#   Elo: elo_home, elo_away, elo_diff
#   Weather: wind_mph, temp_f, precip_mm
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
  library(purrr)
  library(jsonlite)
})

# TODO: Parse command-line arguments (in path, out path, elo seed)
# TODO: Read latest games.csv from data/raw
# TODO: Compute home flag (1 if home, 0 if away - but structure is one row per game)
# TODO: Compute rest_home and rest_away (days since previous game per team)
# TODO: Compute prev_margin_home and prev_margin_away (last game margin)
# TODO: Initialize and update Elo ratings by team (seeded from elo_seed option)
# TODO: Fetch weather data via meteostat for stadium location at kickoff (wind, temp, precip)
# TODO: Validate ranges and joins
# TODO: Write context_<timestamp>.csv + provenance JSON (source path, row counts)
# TODO: Print summary: rows, joins, NA counts, elapsed time

cat("02_features.R stub loaded. Ready for implementation.\n")
