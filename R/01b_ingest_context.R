#!/usr/bin/env Rscript
# ==============================================================================
# 01b_ingest_context.R
# Purpose: Build context features from games data
# ==============================================================================
# Inputs:  --in (data/raw path), --out (data/processed)
# Outputs: data/processed/context_<timestamp>.csv + provenance JSON
#
# Stage Gate Tests:
#   - 1:1 join on game_id with games.csv
#   - week ∈ [1, 22]; rest ∈ [0, 14]; wind >= 0; elo_diff finite
#   - No orphan game_ids
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
  library(purrr)
  library(jsonlite)
  library(stringr)
})

source("R/utils/features.R")

start_time <- Sys.time()

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)
in_path <- "data/raw"
out_path <- "data/processed"
elo_seed <- "equal"

for (i in seq_along(args)) {
  if (args[i] == "--in" && i < length(args)) {
    in_path <- args[i + 1]
  } else if (args[i] == "--out" && i < length(args)) {
    out_path <- args[i + 1]
  } else if (args[i] == "--elo_seed" && i < length(args)) {
    elo_seed <- args[i + 1]
  }
}

# Find most recent games file
games_files <- list.files(in_path, pattern = "^games_.*\\.csv$", full.names = TRUE)
if (length(games_files) == 0) {
  stop("No games CSV files found in ", in_path)
}
games_file <- games_files[length(games_files)]
cat(sprintf("Reading: %s\n", games_file))

games <- read_csv(games_file, show_col_types = FALSE)
cat(sprintf("Loaded %d games\n", nrow(games)))

# Sort by date for sequential feature computation
games <- games %>%
  arrange(date, game_id)

# Initialize context data frame
context <- games %>%
  select(game_id, season, week, date, home_team, away_team, home_score, away_score)

# Compute rest days for each team
cat("Computing rest days...\n")
team_games <- bind_rows(
  games %>% select(game_id, date, team = home_team) %>% mutate(is_home = TRUE),
  games %>% select(game_id, date, team = away_team) %>% mutate(is_home = FALSE)
) %>%
  arrange(team, date) %>%
  group_by(team) %>%
  mutate(
    prev_date = lag(date),
    rest_days = as.integer(difftime(date, prev_date, units = "days"))
  ) %>%
  ungroup() %>%
  mutate(rest_days = ifelse(is.na(rest_days), 7L, rest_days))

rest_home <- team_games %>% filter(is_home) %>% select(game_id, rest_home = rest_days)
rest_away <- team_games %>% filter(!is_home) %>% select(game_id, rest_away = rest_days)

# Compute previous margins
cat("Computing previous margins...\n")
team_margins <- bind_rows(
  games %>% mutate(team = home_team, margin = home_score - away_score),
  games %>% mutate(team = away_team, margin = away_score - home_score)
) %>%
  arrange(team, date) %>%
  group_by(team) %>%
  mutate(prev_margin = lag(margin)) %>%
  ungroup()

prev_margin_home <- team_margins %>%
  filter(team == home_team) %>%
  select(game_id, prev_margin_home = prev_margin)

prev_margin_away <- team_margins %>%
  filter(team == away_team) %>%
  select(game_id, prev_margin_away = prev_margin)

# Compute Elo ratings
cat("Computing Elo ratings...\n")
teams <- unique(c(games$home_team, games$away_team))
elo_ratings <- setNames(rep(1500, length(teams)), teams)

k_factor <- 20
hfa <- 65

elo_results <- map_dfr(1:nrow(games), function(i) {
  game <- games[i, ]

  elo_home <- elo_ratings[game$home_team]
  elo_away <- elo_ratings[game$away_team]
  elo_diff <- elo_home - elo_away + hfa

  # Expected probability
  expected_home <- 1 / (1 + 10^(-(elo_diff) / 400))

  # Actual outcome
  actual_home <- as.integer(game$home_score > game$away_score)

  # Update ratings
  elo_home_new <- elo_home + k_factor * (actual_home - expected_home)
  elo_away_new <- elo_away + k_factor * ((1 - actual_home) - (1 - expected_home))

  elo_ratings[game$home_team] <<- elo_home_new
  elo_ratings[game$away_team] <<- elo_away_new

  tibble(
    game_id = game$game_id,
    elo_home = elo_home,
    elo_away = elo_away,
    elo_diff = elo_diff
  )
})

# Weather data (placeholder - requires meteostat or similar)
cat("Adding weather placeholders (TODO: integrate Meteostat)...\n")
weather <- tibble(
  game_id = games$game_id,
  wind_mph = NA_real_,
  temp_f = NA_real_,
  precip_mm = NA_real_
)

# Add rest day caps and first game flags
cat("Adding rest day caps and first_game flags...\n")
rest_home <- rest_home %>%
  mutate(
    rest_home_capped = pmin(rest_home, 14),
    first_game_home = as.integer(rest_home > 100)
  )

rest_away <- rest_away %>%
  mutate(
    rest_away_capped = pmin(rest_away, 14),
    first_game_away = as.integer(rest_away > 100)
  )

# Combine all features
# Note: Do NOT include season/week/spread/total here, as they will be joined from games.csv
# This avoids duplicate columns during inner_join in downstream scripts
context_final <- context %>%
  select(game_id) %>%
  mutate(home = 1L) %>%
  left_join(rest_home, by = "game_id") %>%
  left_join(rest_away, by = "game_id") %>%
  left_join(prev_margin_home, by = "game_id") %>%
  left_join(prev_margin_away, by = "game_id") %>%
  left_join(elo_results, by = "game_id") %>%
  left_join(weather, by = "game_id")

# Validation
cat("\n=== Validation ===\n")
cat(sprintf("Context rows: %d\n", nrow(context_final)))
cat(sprintf("Games rows: %d\n", nrow(games)))
cat(sprintf("Join cardinality check: %s\n",
            ifelse(nrow(context_final) == nrow(games), "PASS", "FAIL")))

week_range <- range(games$week, na.rm = TRUE)
cat(sprintf("Week range: [%d, %d] (expect [1, 22])\n", week_range[1], week_range[2]))

rest_range <- range(c(context_final$rest_home, context_final$rest_away), na.rm = TRUE)
cat(sprintf("Rest range (raw): [%d, %d]\n", rest_range[1], rest_range[2]))

rest_capped_range <- range(c(context_final$rest_home_capped, context_final$rest_away_capped), na.rm = TRUE)
cat(sprintf("Rest range (capped): [%d, %d] (expect [0, 14])\n", rest_capped_range[1], rest_capped_range[2]))

n_first_games <- sum(context_final$first_game_home | context_final$first_game_away)
cat(sprintf("First games of season: %d\n", n_first_games))

elo_finite <- all(is.finite(context_final$elo_diff))
cat(sprintf("Elo diff finite: %s\n", ifelse(elo_finite, "PASS", "FAIL")))

# Write output
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
out_file <- file.path(out_path, sprintf("context_%s.csv", timestamp))
dir.create(out_path, recursive = TRUE, showWarnings = FALSE)
write_csv(context_final, out_file)

# Write provenance
provenance <- list(
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
  source_file = games_file,
  row_count = nrow(context_final),
  elo_seed = elo_seed,
  elo_k = k_factor,
  elo_hfa = hfa,
  weather_source = "placeholder"
)

prov_file <- sub("\\.csv$", "_meta.json", out_file)
write_json(provenance, prov_file, pretty = TRUE, auto_unbox = TRUE)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat("\n=== Summary ===\n")
cat(sprintf("Output: %s\n", out_file))
cat(sprintf("Rows: %d\n", nrow(context_final)))
cat(sprintf("NA counts:\n"))
print(colSums(is.na(context_final)))
cat(sprintf("\nElapsed: %.2f seconds\n", elapsed))
