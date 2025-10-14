#!/usr/bin/env Rscript
# ==============================================================================
# 06_plots.R
# Purpose: Generate model vs market comparison plots + edge analysis
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(tidyr)
  library(purrr)
  library(pROC)
})

start_time <- Sys.time()

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)
eval_dir <- "artifacts/20251014_161044/eval"
out_dir <- "artifacts/20251014_161044/plots"

for (i in seq_along(args)) {
  if (args[i] == "--eval_dir" && i < length(args)) eval_dir <- args[i + 1]
  if (args[i] == "--out" && i < length(args)) out_dir <- args[i + 1]
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cat(sprintf("Eval directory: %s\n", eval_dir))
cat(sprintf("Output directory: %s\n", out_dir))

# Load evaluation results
overall <- read_csv(file.path(eval_dir, "overall.csv"), show_col_types = FALSE)
by_season <- read_csv(file.path(eval_dir, "by_season.csv"), show_col_types = FALSE)
by_season_week <- read_csv(file.path(eval_dir, "by_season_week.csv"), show_col_types = FALSE)

# Load test data with predictions
games <- read_csv("data/raw/games_20251013_202758.csv", show_col_types = FALSE)
context <- read_csv("data/processed/context_20251014_161031.csv", show_col_types = FALSE)

data <- games %>%
  inner_join(context, by = "game_id") %>%
  filter(season > 2022 | (season == 2022 & week > 20))

# Re-generate predictions (same as validation)
source("R/utils/market.R")
suppressPackageStartupMessages(library(xgboost))

train_data <- games %>%
  inner_join(context, by = "game_id") %>%
  filter(season < 2023 | (season == 2022 & week <= 20))

market_model <- fit_market_baseline(train_data, method = "isotonic")
data$market_prob <- market_prob(data$spread_close, market_model)

xgb_model <- xgb.load("artifacts/20251014_161044/xgb/model.xgb")
feature_cols <- c("home", "spread_close", "total_close", "week", "rest_home_capped",
                 "rest_away_capped", "first_game_home", "first_game_away",
                 "prev_margin_home", "prev_margin_away", "elo_diff")
test_matrix <- xgb.DMatrix(data = as.matrix(data[, feature_cols]))
data$model_prob <- predict(xgb_model, test_matrix)
data$edge <- data$model_prob - data$market_prob

cat(sprintf("\n=== Test Data: %d games ===\n", nrow(data)))

# Plot 1: Model vs Market scatter
p1 <- ggplot(data, aes(x = market_prob, y = model_prob, color = factor(season))) +
  geom_point(alpha = 0.5, size = 2) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray30") +
  labs(title = "Model vs Market Predictions",
       x = "Market P(home_win)", y = "Model P(home_win)", color = "Season") +
  theme_minimal() + coord_fixed()
ggsave(file.path(out_dir, "model_vs_market_prob_scatter.png"), p1, width = 8, height = 6)

# Plot 2: Edge distribution by season
p2 <- ggplot(data, aes(x = factor(season), y = edge)) +
  geom_violin(fill = "steelblue", alpha = 0.6) +
  geom_boxplot(width = 0.2, outlier.alpha = 0.3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  labs(title = "Model Edge Over Market (by Season)",
       x = "Season", y = "Δp = P(model) - P(market)") +
  theme_minimal()
ggsave(file.path(out_dir, "model_prob_minus_market_by_season.png"), p2, width = 8, height = 5)

# Plot 3: Log loss by season
by_season_long <- by_season %>%
  select(season, model_logloss, market_logloss) %>%
  pivot_longer(cols = c(model_logloss, market_logloss), names_to = "source", values_to = "logloss")

p3 <- ggplot(by_season_long, aes(x = factor(season), y = logloss, fill = source)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("model_logloss" = "steelblue", "market_logloss" = "coral"),
                   labels = c("Model", "Market")) +
  labs(title = "Log Loss by Season", x = "Season", y = "Log Loss", fill = "Source") +
  theme_minimal()
ggsave(file.path(out_dir, "logloss_by_season_bar.png"), p3, width = 8, height = 5)

# Plot 4: Calibration slope by season
p4 <- ggplot(by_season, aes(x = factor(season))) +
  geom_col(aes(y = model_calib_slope), fill = "steelblue", alpha = 0.7) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "red") +
  geom_hline(yintercept = c(0.8, 1.2), linetype = "dotted", color = "gray50") +
  labs(title = "Calibration Slope by Season (Model)",
       x = "Season", y = "Calibration Slope (ideal = 1.0)") +
  theme_minimal()
ggsave(file.path(out_dir, "calibration_slope_by_season.png"), p4, width = 8, height = 5)

# Edge analysis
cat("\n=== Edge Analysis ===\n")
data <- data %>% mutate(abs_edge = abs(edge))

# Decile bins
data$edge_decile <- cut(data$abs_edge, breaks = quantile(data$abs_edge, probs = seq(0, 1, 0.1)),
                        include.lowest = TRUE, labels = paste0("D", 1:10))

edge_bins <- data %>%
  group_by(edge_decile) %>%
  summarise(
    n = n(),
    mean_abs_edge = mean(abs_edge),
    accuracy = mean(home_win == (model_prob > 0.5)),
    model_logloss = -mean(home_win * log(model_prob + 1e-15) + (1 - home_win) * log(1 - model_prob + 1e-15)),
    market_logloss = -mean(home_win * log(market_prob + 1e-15) + (1 - home_win) * log(1 - market_prob + 1e-15)),
    logloss_delta = market_logloss - model_logloss,
    .groups = "drop"
  )

write_csv(edge_bins, file.path(out_dir, "edge_bins_outcomes.csv"))
print(edge_bins)

# Plot edge bins
p5 <- edge_bins %>%
  ggplot(aes(x = edge_decile, y = logloss_delta)) +
  geom_col(fill = "steelblue") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  labs(title = "Model Gain Over Market by Edge Decile",
       x = "Edge Decile (|Δp|)", y = "Log Loss Gain (market - model)") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(out_dir, "edge_bins_outcomes.png"), p5, width = 8, height = 5)

# Threshold analysis
thresholds <- c(0.03, 0.05, 0.07)
edge_thresholds <- map_dfr(thresholds, function(t) {
  subset <- data %>% filter(abs_edge >= t)
  tibble(
    threshold = t,
    n = nrow(subset),
    pct_games = nrow(subset) / nrow(data),
    mean_abs_edge = mean(subset$abs_edge),
    model_logloss = -mean(subset$home_win * log(subset$model_prob + 1e-15) +
                         (1 - subset$home_win) * log(1 - subset$model_prob + 1e-15)),
    market_logloss = -mean(subset$home_win * log(subset$market_prob + 1e-15) +
                          (1 - subset$home_win) * log(1 - subset$market_prob + 1e-15)),
    logloss_gain = market_logloss - model_logloss
  )
})
write_csv(edge_thresholds, file.path(out_dir, "edge_thresholds.csv"))
cat("\n=== Edge Thresholds ===\n")
print(edge_thresholds)

# Cumulative gain
data_sorted <- data %>% arrange(desc(abs_edge)) %>%
  mutate(
    model_loss = -(home_win * log(model_prob + 1e-15) + (1 - home_win) * log(1 - model_prob + 1e-15)),
    market_loss = -(home_win * log(market_prob + 1e-15) + (1 - home_win) * log(1 - market_prob + 1e-15)),
    gain = market_loss - model_loss,
    cum_gain = cumsum(gain),
    game_rank = row_number()
  )

p6 <- ggplot(data_sorted, aes(x = game_rank, y = cum_gain)) +
  geom_line(color = "steelblue", size = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  labs(title = "Cumulative Gain Over Market (sorted by |edge|)",
       x = "Games (sorted by descending |edge|)", y = "Cumulative Log Loss Gain") +
  theme_minimal()
ggsave(file.path(out_dir, "cumulative_edge_gain.png"), p6, width = 8, height = 5)

# ROC and PR curves
roc_obj <- roc(data$home_win, data$model_prob, quiet = TRUE)
roc_auc <- auc(roc_obj)

precision_recall <- function(y, p, threshold) {
  pred <- as.integer(p >= threshold)
  tp <- sum(pred == 1 & y == 1)
  fp <- sum(pred == 1 & y == 0)
  fn <- sum(pred == 0 & y == 1)
  precision <- ifelse(tp + fp == 0, 0, tp / (tp + fp))
  recall <- ifelse(tp + fn == 0, 0, tp / (tp + fn))
  c(precision = precision, recall = recall)
}

thresholds_pr <- seq(0, 1, 0.01)
pr_curve <- map_dfr(thresholds_pr, ~as_tibble(t(precision_recall(data$home_win, data$model_prob, .x))))
pr_auc <- sum(diff(pr_curve$recall) * (pr_curve$precision[-1] + pr_curve$precision[-nrow(pr_curve)]) / 2, na.rm = TRUE)

write_csv(tibble(roc_auc = roc_auc, pr_auc = abs(pr_auc)), file.path(out_dir, "auc_metrics.csv"))

# ROC plot
roc_df <- tibble(fpr = 1 - roc_obj$specificities, tpr = roc_obj$sensitivities)
p7 <- ggplot(roc_df, aes(x = fpr, y = tpr)) +
  geom_line(color = "steelblue", size = 1) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
  labs(title = sprintf("ROC Curve (AUC = %.3f)", roc_auc),
       x = "False Positive Rate", y = "True Positive Rate") +
  theme_minimal() + coord_fixed()
ggsave(file.path(out_dir, "roc_curve.png"), p7, width = 6, height = 6)

# PR plot
p8 <- ggplot(pr_curve, aes(x = recall, y = precision)) +
  geom_line(color = "coral", size = 1) +
  labs(title = sprintf("Precision-Recall Curve (AUC ≈ %.3f)", abs(pr_auc)),
       x = "Recall", y = "Precision") +
  theme_minimal()
ggsave(file.path(out_dir, "pr_curve.png"), p8, width = 6, height = 6)

# Confusion matrices
confusion_metrics <- function(y, p, threshold) {
  pred <- as.integer(p >= threshold)
  tp <- sum(pred == 1 & y == 1); fp <- sum(pred == 1 & y == 0)
  tn <- sum(pred == 0 & y == 0); fn <- sum(pred == 0 & y == 1)
  acc <- (tp + tn) / length(y)
  prec <- ifelse(tp + fp == 0, 0, tp / (tp + fp))
  rec <- ifelse(tp + fn == 0, 0, tp / (tp + fn))
  f1 <- ifelse(prec + rec == 0, 0, 2 * prec * rec / (prec + rec))
  bal_acc <- ((tp / (tp + fn)) + (tn / (tn + fp))) / 2
  tibble(threshold = threshold, tp = tp, fp = fp, tn = tn, fn = fn,
         accuracy = acc, precision = prec, recall = rec, f1 = f1, balanced_acc = bal_acc)
}

# Find optimal thresholds
f1_scores <- map_dbl(seq(0.1, 0.9, 0.01), ~confusion_metrics(data$home_win, data$model_prob, .x)$f1)
t_f1 <- seq(0.1, 0.9, 0.01)[which.max(f1_scores)]

bal_scores <- map_dbl(seq(0.1, 0.9, 0.01), ~confusion_metrics(data$home_win, data$model_prob, .x)$balanced_acc)
t_bal <- seq(0.1, 0.9, 0.01)[which.max(bal_scores)]

conf_0.5 <- confusion_metrics(data$home_win, data$model_prob, 0.5)
conf_f1 <- confusion_metrics(data$home_win, data$model_prob, t_f1)
conf_bal <- confusion_metrics(data$home_win, data$model_prob, t_bal)

confusion_all <- bind_rows(conf_0.5, conf_f1, conf_bal)
write_csv(confusion_all, file.path(out_dir, "confusion_matrices.csv"))

cat("\n=== Confusion Matrices ===\n")
print(confusion_all)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
cat(sprintf("\n=== Summary ===\n"))
cat(sprintf("✓ Generated %d plots\n", 8))
cat(sprintf("  Outputs: %s/*.png\n", out_dir))
cat(sprintf("  Elapsed: %.2f seconds\n", elapsed))
