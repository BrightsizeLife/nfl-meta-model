#!/usr/bin/env Rscript
# ==============================================================================
# 20_edge_labels.R
# Purpose: Compute edge targets (model vs book, not outcome vs book)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

source("R/utils/market.R")
source("R/utils/edge.R")

start_time <- Sys.time()

# Load data
games <- read_csv("data/raw/games_20251013_202758.csv", show_col_types = FALSE)
context <- read_csv("data/processed/context_20251014_161031.csv", show_col_types = FALSE)

data <- games %>%
  inner_join(context, by = "game_id")

# Split train/test
train_data <- data %>% filter(season < 2023 | (season == 2022 & week <= 20))
test_data <- data %>% filter(season > 2022 | (season == 2022 & week > 20))

cat(sprintf("Train: %d games, Test: %d games\n", nrow(train_data), nrow(test_data)))

# Fit market baseline and get probabilities
market_model <- fit_market_baseline(train_data, method = "isotonic")
data$prob_book <- market_prob(data$spread_close, market_model)

# Load OOF predictions
oof_file <- list.files("data/processed", pattern = "^p_model_oof_.*\\.csv$", full.names = TRUE)
if (length(oof_file) == 0) {
  stop("ERROR: No p_model_oof_*.csv found. Run R/04_xgb_fit.R first to generate OOF predictions.")
}
oof_file <- oof_file[length(oof_file)]  # Use most recent
cat(sprintf("Loading OOF predictions: %s\n", basename(oof_file)))

oof_data <- read_csv(oof_file, show_col_types = FALSE)

# Join OOF predictions (only test set has them)
data_with_oof <- data %>%
  left_join(oof_data %>% select(game_id, p_model_oof), by = "game_id") %>%
  filter(!is.na(p_model_oof))  # Only games with OOF predictions

cat(sprintf("Games with OOF predictions: %d\n", nrow(data_with_oof)))
cat(sprintf("Distinct game_ids: %d\n", n_distinct(data_with_oof$game_id)))

# Sanity check: 1:1 join
if (nrow(data_with_oof) != nrow(oof_data)) {
  stop(sprintf("ERROR: Join cardinality mismatch! Expected %d, got %d", nrow(oof_data), nrow(data_with_oof)))
}

# Helper function for single-observation log loss
logloss_single <- function(y, p) {
  eps <- 1e-15
  p <- pmax(pmin(p, 1 - eps), eps)
  -(y * log(p) + (1 - y) * log(1 - p))
}

# Compute edge targets (CORRECTED: model vs book, not outcome vs book)
edges <- data_with_oof %>%
  select(game_id, season, week, home_win, prob_book, p_model_oof) %>%
  mutate(
    book_id = "market_proxy",
    # EDGE = model - book (not outcome - book!)
    edge = p_model_oof - prob_book,
    side = sign(edge),
    # Off-flags based on |edge|
    off_flag_003 = make_off_flag(edge, 0.03),
    off_flag_005 = make_off_flag(edge, 0.05),
    off_flag_007 = make_off_flag(edge, 0.07),
    abs_edge = abs(edge),
    # Evaluation metrics (for comparison only, not used in edge definition)
    loss_book = logloss_single(home_win, prob_book),
    loss_model = logloss_single(home_win, p_model_oof),
    loss_delta = loss_book - loss_model  # Positive = model better
  )

# Write edges
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
out_file <- sprintf("data/processed/edges_%s.csv", timestamp)
write_csv(edges, out_file)

# Summary stats by season
summary_by_season <- edges %>%
  group_by(season) %>%
  summarise(
    n = n(),
    mean_edge = mean(edge),
    sd_edge = sd(edge),
    pct_off_003 = 100 * mean(off_flag_003),
    pct_off_005 = 100 * mean(off_flag_005),
    pct_off_007 = 100 * mean(off_flag_007),
    mean_abs_edge = mean(abs_edge),
    mean_loss_delta = mean(loss_delta),
    .groups = "drop"
  )

write_csv(summary_by_season, sprintf("data/processed/edges_summary_season_%s.csv", timestamp))

# Summary by threshold
summary_by_threshold <- tibble(
  threshold = c(0.03, 0.05, 0.07),
  n_flagged = c(sum(edges$off_flag_003), sum(edges$off_flag_005), sum(edges$off_flag_007)),
  pct_flagged = 100 * n_flagged / nrow(edges),
  mean_edge_flagged = c(
    mean(abs(edges$edge[edges$off_flag_003 == 1])),
    mean(abs(edges$edge[edges$off_flag_005 == 1])),
    mean(abs(edges$edge[edges$off_flag_007 == 1]))
  ),
  mean_loss_delta_flagged = c(
    mean(edges$loss_delta[edges$off_flag_003 == 1]),
    mean(edges$loss_delta[edges$off_flag_005 == 1]),
    mean(edges$loss_delta[edges$off_flag_007 == 1])
  )
)

write_csv(summary_by_threshold, sprintf("data/processed/edges_summary_threshold_%s.csv", timestamp))

cat("\n=== Edge Summary by Season ===\n")
print(summary_by_season)

cat("\n=== Edge Summary by Threshold ===\n")
print(summary_by_threshold)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
cat(sprintf("\n✓ Edges computed: %d rows\n", nrow(edges)))
cat(sprintf("  Output: %s\n", out_file))
cat(sprintf("  Prevalence (τ=0.05): %.1f%%\n", 100 * mean(edges$off_flag_005)))
cat(sprintf("  Mean |edge|: %.3f\n", mean(edges$abs_edge)))
cat(sprintf("  Mean loss_delta: %.4f (positive = model better)\n", mean(edges$loss_delta)))
cat(sprintf("  Elapsed: %.2f seconds\n", elapsed))
