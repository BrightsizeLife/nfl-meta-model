#!/usr/bin/env Rscript
# ==============================================================================
# 60_score_upcoming.R
# Purpose: Score upcoming NFL games with trained XGBoost model
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(nflreadr)
  library(lubridate)
  library(xgboost)
})

start_time <- Sys.time()

cat("=== Scoring Upcoming Games ===\n\n")

# ==============================================================================
# Load upcoming schedule
# ==============================================================================
current_year <- year(Sys.Date())
current_date <- Sys.Date()

cat(sprintf("Current date: %s\n", current_date))
cat(sprintf("Loading schedule for %d season...\n", current_year))

schedule <- load_schedules(seasons = current_year)

# Filter to upcoming games (kickoff >= today)
upcoming <- schedule %>%
  filter(gameday >= current_date) %>%
  arrange(gameday, gametime)

if (nrow(upcoming) == 0) {
  stop(sprintf("ERROR: No upcoming games found for season %d. Check if season is active.", current_year))
}

cat(sprintf("✓ Found %d upcoming games\n", nrow(upcoming)))
cat(sprintf("  Date range: %s to %s\n", min(upcoming$gameday), max(upcoming$gameday)))
cat(sprintf("  Weeks: %s\n", paste(unique(upcoming$week), collapse = ", ")))

# ==============================================================================
# Build minimal context features
# ==============================================================================
cat("\nBuilding context features...\n")

# Load historical data for rest/margin/elo calculations
games_file <- list.files("data/raw", pattern = "^games_.*\\.csv$", full.names = TRUE)
if (length(games_file) == 0) {
  stop("ERROR: No historical games CSV found. Run R/01_ingest.R first.")
}
games_hist <- read_csv(games_file[length(games_file)], show_col_types = FALSE)

context_file <- list.files("data/processed", pattern = "^context_.*\\.csv$", full.names = TRUE)
if (length(context_file) == 0) {
  stop("ERROR: No context CSV found. Run R/02_features.R first.")
}
context_hist <- read_csv(context_file[length(context_file)], show_col_types = FALSE)

# Normalize upcoming schedule to match games schema
upcoming_norm <- upcoming %>%
  transmute(
    game_id = game_id,
    season = season,
    week = week,
    date = gameday,
    kickoff_et = paste(gameday, gametime),
    home_team = home_team,
    away_team = away_team,
    home_score = NA_integer_,  # Unknown (future game)
    away_score = NA_integer_,
    home_win = NA_integer_,
    spread_close = spread_line,  # Use current spread as proxy
    total_close = total_line
  )

cat(sprintf("  Upcoming games normalized: %d rows\n", nrow(upcoming_norm)))

# Build context features (without outcomes)
# Note: This is a simplified version; full feature engineering would go in utils
upcoming_context <- upcoming_norm %>%
  mutate(
    home = 1,  # Home indicator
    # Rest days: placeholder (would need previous game dates)
    rest_home = 7,  # Assume standard week
    rest_away = 7,
    # Previous margins: placeholder (would need previous results)
    prev_margin_home = 0,
    prev_margin_away = 0,
    # Elo: placeholder (would need current Elo ratings)
    elo_home = 1500,
    elo_away = 1500,
    elo_diff = elo_home - elo_away,
    # Weather: placeholder (would need forecast API)
    wind_mph = 5,
    temp_f = 60,
    precip_mm = 0
  )

cat(sprintf("✓ Context features built\n"))
cat(sprintf("  Features: home, week, rest_*, prev_margin_*, elo_diff, weather_*\n"))

# ==============================================================================
# Load trained model
# ==============================================================================
cat("\nLoading trained XGBoost model...\n")

xgb_dirs <- list.dirs("artifacts", recursive = FALSE, full.names = TRUE)
xgb_dirs <- xgb_dirs[grepl("[0-9]{8}_[0-9]{6}", basename(xgb_dirs))]
xgb_dirs <- xgb_dirs[sapply(xgb_dirs, function(d) dir.exists(file.path(d, "xgb")))]

if (length(xgb_dirs) == 0) {
  stop("ERROR: No XGBoost artifacts found. Run R/04_xgb_fit.R first.")
}

model_dir <- file.path(xgb_dirs[length(xgb_dirs)], "xgb")
model_file <- file.path(model_dir, "model.xgb")

if (!file.exists(model_file)) {
  stop(sprintf("ERROR: Model file not found: %s", model_file))
}

model <- xgb.load(model_file)
cat(sprintf("✓ Model loaded: %s\n", model_file))

# Get feature names from training
# (In production, this should be saved with model metadata)
feature_names <- c("home", "spread_close", "total_close", "week",
                  "rest_home", "rest_away", "prev_margin_home", "prev_margin_away",
                  "elo_diff", "wind_mph", "temp_f", "precip_mm")

# ==============================================================================
# Score upcoming games
# ==============================================================================
cat("\nScoring games...\n")

# Prepare feature matrix
X_upcoming <- upcoming_context %>%
  select(all_of(feature_names)) %>%
  as.matrix()

# Check for NAs
if (any(is.na(X_upcoming))) {
  warning("NAs detected in features. Filling with defaults.")
  X_upcoming[is.na(X_upcoming)] <- 0
}

# Predict
dmatrix <- xgb.DMatrix(data = X_upcoming)
p_model <- predict(model, dmatrix)

cat(sprintf("✓ Scored %d games\n", length(p_model)))
cat(sprintf("  Prob range: [%.3f, %.3f]\n", min(p_model), max(p_model)))

# ==============================================================================
# Output
# ==============================================================================
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
output <- upcoming_norm %>%
  select(game_id, season, week, home_team, away_team, kickoff_et) %>%
  mutate(p_model = p_model)

out_file <- file.path("data/live", sprintf("upcoming_%s.csv", timestamp))
write_csv(output, out_file)

elapsed <- difftime(Sys.time(), start_time, units = "secs")

cat(sprintf("\n=== Upcoming Games Scored ===\n"))
cat(sprintf("  Output: %s\n", out_file))
cat(sprintf("  Rows: %d\n", nrow(output)))
cat(sprintf("  Distinct games: %d\n", n_distinct(output$game_id)))
cat(sprintf("  Weeks: %s\n", paste(unique(output$week), collapse = ", ")))
cat(sprintf("  Elapsed: %.1f sec\n", elapsed))
