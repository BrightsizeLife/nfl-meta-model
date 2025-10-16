#!/usr/bin/env Rscript
# ==============================================================================
# 61_join_live_odds.R
# Purpose: Join live odds with model predictions and compute edges
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(yaml)
})

source("R/utils/market.R")

start_time <- Sys.time()

cat("=== Joining Live Odds with Predictions ===\n\n")

# ==============================================================================
# Load configuration
# ==============================================================================
config <- read_yaml("config/default.yml")
edge_threshold <- config$edge$edge_threshold
books_preference <- config$live$books_preference
prefer_ml <- config$live$prefer_moneyline

cat(sprintf("Edge threshold: %.2f\n", edge_threshold))
cat(sprintf("Preferred books: %s\n", paste(books_preference, collapse = ", ")))
cat(sprintf("Prefer moneyline: %s\n\n", prefer_ml))

# ==============================================================================
# Load upcoming predictions
# ==============================================================================
upcoming_files <- list.files("data/live", pattern = "^upcoming_.*\\.csv$", full.names = TRUE)
if (length(upcoming_files) == 0) {
  stop("ERROR: No upcoming predictions found. Run R/60_score_upcoming.R first.")
}

upcoming_file <- upcoming_files[length(upcoming_files)]
cat(sprintf("Loading predictions: %s\n", basename(upcoming_file)))

upcoming <- read_csv(upcoming_file, show_col_types = FALSE)
cat(sprintf("  %d games with predictions\n", nrow(upcoming)))

# ==============================================================================
# Load manual odds
# ==============================================================================
odds_files <- list.files("data/live", pattern = "^odds_.*\\.csv$", full.names = TRUE)
if (length(odds_files) == 0) {
  stop("ERROR: No odds CSV found. Create data/live/odds_<timestamp>.csv manually (see docs/odds_live_manual.md)")
}

odds_file <- odds_files[length(odds_files)]
cat(sprintf("Loading odds: %s\n", basename(odds_file)))

odds <- read_csv(odds_file, show_col_types = FALSE)
cat(sprintf("  %d odds rows\n", nrow(odds)))
cat(sprintf("  Books: %s\n", paste(unique(odds$book), collapse = ", ")))

# Validate odds schema
required_cols <- c("game_id", "book")
if (!all(required_cols %in% names(odds))) {
  stop(sprintf("ERROR: Odds CSV missing required columns: %s",
               paste(setdiff(required_cols, names(odds)), collapse = ", ")))
}

odds_cols <- c("moneyline_home", "moneyline_away", "spread_home")
has_odds <- sapply(odds_cols, function(col) col %in% names(odds))

if (!any(has_odds)) {
  stop("ERROR: Odds CSV must have at least one of: moneyline_home/moneyline_away OR spread_home")
}

# ==============================================================================
# Load market baseline model (for spread conversion)
# ==============================================================================
cat("\nLoading market baseline model...\n")

# Find most recent fitted market model (saved during edge label generation)
# For now, we'll refit from historical data
games_file <- list.files("data/raw", pattern = "^games_.*\\.csv$", full.names = TRUE)
games <- read_csv(games_file[length(games_file)], show_col_types = FALSE)

context_file <- list.files("data/processed", pattern = "^context_.*\\.csv$", full.names = TRUE)
context <- read_csv(context_file[length(context_file)], show_col_types = FALSE)

data <- games %>%
  inner_join(context, by = "game_id") %>%
  filter(!is.na(spread_close), !is.na(home_win))

market_model <- fit_market_baseline(data, method = "isotonic")

# ==============================================================================
# Compute p_book for each odds row
# ==============================================================================
cat("\nComputing book probabilities...\n")

odds_with_prob <- odds %>%
  rowwise() %>%
  mutate(
    prob_result = list(choose_p_book(cur_data(), market_model, prefer_ml)),
    p_book = prob_result$p_book,
    prob_source = prob_result$source
  ) %>%
  ungroup() %>%
  select(-prob_result)

# Filter out rows without valid probabilities
odds_valid <- odds_with_prob %>%
  filter(!is.na(p_book))

cat(sprintf("✓ Computed probabilities for %d odds rows\n", nrow(odds_valid)))
cat(sprintf("  Sources: %s\n", paste(table(odds_valid$prob_source), collapse = ", ")))

# ==============================================================================
# Deduplicate: select best book per game
# ==============================================================================
cat("\nDeduplicating odds by book preference...\n")

# Add book priority based on config
odds_ranked <- odds_valid %>%
  mutate(
    book_rank = match(book, books_preference),
    book_rank = ifelse(is.na(book_rank), 999, book_rank)  # Unknown books last
  ) %>%
  arrange(game_id, book_rank) %>%
  group_by(game_id) %>%
  slice(1) %>%  # Take first (highest priority book)
  ungroup()

cat(sprintf("✓ Deduped to %d games (one book per game)\n", nrow(odds_ranked)))

# ==============================================================================
# Join with predictions and compute edges
# ==============================================================================
cat("\nJoining odds with predictions...\n")

edges_upcoming <- upcoming %>%
  inner_join(odds_ranked %>% select(game_id, book, p_book, prob_source),
             by = "game_id") %>%
  mutate(
    edge = p_model - p_book,
    abs_edge = abs(edge),
    side = ifelse(edge > 0, "HOME", "AWAY"),
    flag = abs_edge > edge_threshold
  )

if (nrow(edges_upcoming) == 0) {
  stop("ERROR: No games matched between predictions and odds. Check game_id format.")
}

cat(sprintf("✓ Joined %d games\n", nrow(edges_upcoming)))
cat(sprintf("  Flagged (|edge| > %.2f): %d (%.1f%%)\n",
           edge_threshold,
           sum(edges_upcoming$flag),
           100 * mean(edges_upcoming$flag)))

# ==============================================================================
# Output
# ==============================================================================
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
out_file <- file.path("data/live", sprintf("edges_upcoming_%s.csv", timestamp))

write_csv(edges_upcoming, out_file)

elapsed <- difftime(Sys.time(), start_time, units = "secs")

cat(sprintf("\n=== Edges Computed ===\n"))
cat(sprintf("  Output: %s\n", out_file))
cat(sprintf("  Rows: %d\n", nrow(edges_upcoming)))
cat(sprintf("  Flagged games: %d\n", sum(edges_upcoming$flag)))
cat(sprintf("  Mean |edge|: %.3f\n", mean(edges_upcoming$abs_edge)))
cat(sprintf("  Edge range: [%.3f, %.3f]\n", min(edges_upcoming$edge), max(edges_upcoming$edge)))
cat(sprintf("  Elapsed: %.1f sec\n", elapsed))
