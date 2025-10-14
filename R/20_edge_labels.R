#!/usr/bin/env Rscript
# ==============================================================================
# 20_edge_labels.R
# Purpose: Compute edge targets (residuals + flags) from model vs market
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(xgboost)
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

# Load XGBoost model and get predictions
xgb_model <- xgb.load("artifacts/20251014_161044/xgb/model.xgb")
feature_cols <- c("home", "spread_close", "total_close", "week", "rest_home_capped",
                 "rest_away_capped", "first_game_home", "first_game_away",
                 "prev_margin_home", "prev_margin_away", "elo_diff")

X <- as.matrix(data[, feature_cols])
data$prob_model <- predict(xgb_model, xgb.DMatrix(data = X))

# Compute edge targets
edges <- data %>%
  select(game_id, season, week, home_win, prob_book, prob_model) %>%
  mutate(
    book_id = "market_proxy",
    residual = home_win - prob_book,
    direction = sign(residual),
    off_flag_003 = make_off_flag(residual, 0.03),
    off_flag_005 = make_off_flag(residual, 0.05),
    off_flag_007 = make_off_flag(residual, 0.07),
    delta_prob = prob_model - prob_book,
    delta_logit = qlogis(prob_model) - qlogis(prob_book),
    abs_edge = abs(delta_prob)
  )

# Write edges
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
out_file <- sprintf("data/processed/edges_%s.csv", timestamp)
write_csv(edges, out_file)

# Summary stats
summary_stats <- edges %>%
  group_by(season) %>%
  summarise(
    n = n(),
    mean_residual = mean(residual),
    sd_residual = sd(residual),
    pct_off_003 = mean(off_flag_003),
    pct_off_005 = mean(off_flag_005),
    pct_off_007 = mean(off_flag_007),
    mean_abs_edge = mean(abs_edge),
    .groups = "drop"
  )

write_csv(summary_stats, sprintf("data/processed/edges_summary_%s.csv", timestamp))

cat("\n=== Edge Summary ===\n")
print(summary_stats)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
cat(sprintf("\n✓ Edges computed: %d rows\n", nrow(edges)))
cat(sprintf("  Output: %s\n", out_file))
cat(sprintf("  Overall: %.1f%% off by >0.05\n", 100 * mean(edges$off_flag_005)))
cat(sprintf("  Elapsed: %.2f seconds\n", elapsed))
