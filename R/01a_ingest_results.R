#!/usr/bin/env Rscript
# ==============================================================================
# 01a_ingest_results.R
# Purpose: Load NFL schedules/results from nflreadr for specified seasons
# ==============================================================================
# Inputs:  --seasons (e.g., "2018:2024"), --out (e.g., "data/raw")
# Outputs: data/raw/games_<timestamp>.csv + sidecar JSON
#
# Stage Gate Tests:
#   - Header hash matches schema contract
#   - No duplicates by game_id
#   - Date parsing success > 99.5%
#   - Row count >= 5 seasons worth of games
# ==============================================================================

suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(readr)
  library(lubridate)
  library(jsonlite)
  library(digest)
})

start_time <- Sys.time()

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)
seasons_arg <- "2018:2024"
out_path <- "data/raw"

for (i in seq_along(args)) {
  if (args[i] == "--seasons" && i < length(args)) {
    seasons_arg <- args[i + 1]
  } else if (args[i] == "--out" && i < length(args)) {
    out_path <- args[i + 1]
  }
}

# Parse seasons
seasons_parts <- strsplit(seasons_arg, ":")[[1]]
if (length(seasons_parts) == 2) {
  seasons <- as.integer(seasons_parts[1]):as.integer(seasons_parts[2])
} else {
  seasons <- as.integer(seasons_parts)
}

cat(sprintf("Loading schedules for seasons: %s\n", paste(seasons, collapse = ", ")))

# Load schedules
schedules <- nflreadr::load_schedules(seasons = seasons)

cat(sprintf("Loaded %d games\n", nrow(schedules)))

# Normalize to data contract
games <- schedules %>%
  select(
    game_id,
    season,
    week,
    gameday,
    gametime,
    home_team,
    away_team,
    home_score,
    away_score,
    spread_line,
    total_line
  ) %>%
  rename(
    date = gameday,
    kickoff_et = gametime
  ) %>%
  mutate(
    home_win = as.integer(home_score > away_score),
    spread_close = spread_line,
    total_close = total_line
  ) %>%
  select(
    game_id, season, week, date, kickoff_et,
    home_team, away_team, home_score, away_score,
    home_win, spread_close, total_close
  )

# Validation
n_duplicates <- games %>% count(game_id) %>% filter(n > 1) %>% nrow()
cat(sprintf("Duplicates by game_id: %d\n", n_duplicates))

n_na_dates <- sum(is.na(games$date))
date_parse_success <- (nrow(games) - n_na_dates) / nrow(games)
cat(sprintf("Date parsing success: %.2f%%\n", date_parse_success * 100))

# Generate timestamp
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")

# Write CSV
out_file <- file.path(out_path, sprintf("games_%s.csv", timestamp))
dir.create(out_path, recursive = TRUE, showWarnings = FALSE)
write_csv(games, out_file)

# Compute schema hash
schema_str <- paste(names(games), sapply(games, function(x) class(x)[1]), collapse = "|")
schema_hash <- digest::sha1(schema_str)

# Write sidecar JSON
sidecar <- list(
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
  row_count = nrow(games),
  schema_hash = schema_hash,
  seasons = seasons,
  n_duplicates = n_duplicates,
  date_parse_success = date_parse_success
)

sidecar_file <- sub("\\.csv$", "_meta.json", out_file)
write_json(sidecar, sidecar_file, pretty = TRUE, auto_unbox = TRUE)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat("\n=== Summary ===\n")
cat(sprintf("Output: %s\n", out_file))
cat(sprintf("Rows: %d\n", nrow(games)))
cat(sprintf("Distinct game_ids: %d\n", n_distinct(games$game_id)))
cat(sprintf("Seasons: %d\n", n_distinct(games$season)))
cat(sprintf("NA counts:\n"))
print(colSums(is.na(games)))
cat(sprintf("\nElapsed: %.2f seconds\n", elapsed))
cat(sprintf("Schema hash: %s\n", schema_hash))
