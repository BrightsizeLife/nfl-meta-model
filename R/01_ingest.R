#!/usr/bin/env Rscript
# ==============================================================================
# 01_ingest.R
# Purpose: Load NFL schedules/results + closing spread/total from nflreadr
# ==============================================================================
# Inputs:  --seasons (e.g., 2018:2024), --out (e.g., data/raw), --dryrun
# Outputs: data/raw/games_<timestamp>.csv + sidecar JSON (schema_hash, row_count)
#
# Stage Gate Tests:
#   - Header hash matches schema contract
#   - Row-type histogram stable across seasons
#   - NA audit by column
#   - No duplicates by game_id
#
# Data Contract (games.csv):
#   Keys: game_id (string), season (int), week (int)
#   Entities: date, kickoff_et (datetime), home_team, away_team, home_score, away_score
#   Outcomes: home_win (0/1)
#   Market: spread_close (home favored +/-), total_close
# ==============================================================================

suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(readr)
  library(lubridate)
  library(jsonlite)
  library(digest)
})

# TODO: Parse command-line arguments (seasons, out path, dryrun flag)
# TODO: Load schedules via nflreadr::load_schedules() for specified seasons
# TODO: Normalize columns to match Data Contract above
# TODO: Compute home_win from home_score vs away_score
# TODO: Extract spread_close and total_close (check nflreadr column names)
# TODO: Generate timestamp in YYYYmmdd_HHMMSS format (UTC)
# TODO: Write CSV to data/raw/games_<timestamp>.csv
# TODO: Compute schema hash (digest::sha1 of column names + types)
# TODO: Write sidecar JSON with schema_hash, row_count, created_at
# TODO: Print summary: rows written, distinct game_ids, NA counts, elapsed time

cat("01_ingest.R stub loaded. Ready for implementation.\n")
