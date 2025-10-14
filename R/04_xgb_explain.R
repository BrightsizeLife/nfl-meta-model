#!/usr/bin/env Rscript
# ==============================================================================
# 04_xgb_explain.R
# Purpose: SHAP explainability for XGBoost model
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(xgboost)
  library(ggplot2)
})

start_time <- Sys.time()

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)
model_dir <- "artifacts/20251014_161044/xgb"
out_dir <- "artifacts/20251014_161044/shap"

for (i in seq_along(args)) {
  if (args[i] == "--model_dir" && i < length(args)) model_dir <- args[i + 1]
  if (args[i] == "--out" && i < length(args)) out_dir <- args[i + 1]
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cat(sprintf("Model directory: %s\n", model_dir))
cat(sprintf("Output directory: %s\n", out_dir))

# Load data
games <- read_csv("data/raw/games_20251013_202758.csv", show_col_types = FALSE)
context <- read_csv("data/processed/context_20251014_161031.csv", show_col_types = FALSE)

data <- games %>%
  inner_join(context, by = "game_id") %>%
  filter(season > 2022 | (season == 2022 & week > 20))

cat(sprintf("\n=== Test Data: %d games ===\n", nrow(data)))

# Load model
xgb_model <- xgb.load(file.path(model_dir, "model.xgb"))

# Prepare features
feature_cols <- c("home", "spread_close", "total_close", "week", "rest_home_capped",
                 "rest_away_capped", "first_game_home", "first_game_away",
                 "prev_margin_home", "prev_margin_away", "elo_diff")

X_test <- as.matrix(data[, feature_cols])

# Compute SHAP values (using xgboost's built-in predict with predcontrib)
cat("\n=== Computing SHAP Values ===\n")
shap_values <- predict(xgb_model, X_test, predcontrib = TRUE, approxcontrib = FALSE)

# Remove BIAS column (last column)
shap_matrix <- shap_values[, -ncol(shap_values)]
colnames(shap_matrix) <- feature_cols

# Convert to data frame
shap_df <- as.data.frame(shap_matrix)
shap_df$game_id <- data$game_id

# Global importance: mean absolute SHAP
shap_importance <- tibble(
  feature = feature_cols,
  mean_abs_shap = colMeans(abs(shap_matrix))
) %>%
  arrange(desc(mean_abs_shap))

write_csv(shap_importance, file.path(out_dir, "shap_importance.csv"))
cat("\n=== SHAP Feature Importance ===\n")
print(shap_importance)

# SHAP summary plot (global)
shap_long <- shap_df %>%
  select(-game_id) %>%
  tidyr::pivot_longer(everything(), names_to = "feature", values_to = "shap_value")

feature_values <- data %>%
  select(all_of(feature_cols)) %>%
  tidyr::pivot_longer(everything(), names_to = "feature", values_to = "feature_value")

shap_long$feature_value <- feature_values$feature_value

p_summary <- shap_long %>%
  mutate(feature = factor(feature, levels = rev(shap_importance$feature))) %>%
  ggplot(aes(x = shap_value, y = feature, color = feature_value)) +
  geom_jitter(alpha = 0.3, height = 0.2, size = 1) +
  scale_color_gradient(low = "blue", high = "red") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray30") +
  labs(title = "SHAP Summary Plot",
       x = "SHAP Value (impact on model output)",
       y = "Feature",
       color = "Feature Value") +
  theme_minimal()

ggsave(file.path(out_dir, "shap_summary.png"), p_summary, width = 10, height = 6)

# Dependence plots for top 6 features
top_features <- head(shap_importance$feature, 6)

for (feat in top_features) {
  p_dep <- data.frame(
    feature_value = data[[feat]],
    shap_value = shap_matrix[, feat]
  ) %>%
    ggplot(aes(x = feature_value, y = shap_value)) +
    geom_point(alpha = 0.4, color = "steelblue") +
    geom_smooth(method = "loess", se = TRUE, color = "red", size = 0.8) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray30") +
    labs(title = sprintf("SHAP Dependence: %s", feat),
         x = feat,
         y = "SHAP Value") +
    theme_minimal()

  ggsave(file.path(out_dir, sprintf("shap_dependence_%s.png", feat)), p_dep, width = 7, height = 5)
}

# Interaction plots (spread_close x elo_diff, spread_close x week)
cat("\n=== SHAP Interactions ===\n")

# Interaction 1: spread_close x elo_diff
p_int1 <- data.frame(
  spread = data$spread_close,
  elo_diff = data$elo_diff,
  shap_spread = shap_matrix[, "spread_close"]
) %>%
  ggplot(aes(x = spread, y = shap_spread, color = elo_diff)) +
  geom_point(alpha = 0.5, size = 2) +
  scale_color_gradient2(low = "blue", mid = "white", high = "red", midpoint = 0) +
  geom_smooth(method = "loess", se = FALSE, color = "black", size = 0.8) +
  labs(title = "SHAP Interaction: spread_close × elo_diff",
       x = "Spread (close)",
       y = "SHAP(spread_close)",
       color = "Elo Diff") +
  theme_minimal()

ggsave(file.path(out_dir, "shap_interact_spread_elo.png"), p_int1, width = 8, height = 5)

# Interaction 2: spread_close x week
p_int2 <- data.frame(
  spread = data$spread_close,
  week = data$week,
  shap_spread = shap_matrix[, "spread_close"]
) %>%
  ggplot(aes(x = spread, y = shap_spread, color = week)) +
  geom_point(alpha = 0.5, size = 2) +
  scale_color_viridis_c() +
  geom_smooth(method = "loess", se = FALSE, color = "black", size = 0.8) +
  labs(title = "SHAP Interaction: spread_close × week",
       x = "Spread (close)",
       y = "SHAP(spread_close)",
       color = "Week") +
  theme_minimal()

ggsave(file.path(out_dir, "shap_interact_spread_week.png"), p_int2, width = 8, height = 5)

# Save SHAP values
write_csv(bind_cols(data %>% select(game_id, season, week), shap_df %>% select(-game_id)),
         file.path(out_dir, "shap_values.csv"))

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat(sprintf("\n=== Summary ===\n"))
cat(sprintf("✓ SHAP analysis complete\n"))
cat(sprintf("  Top feature: %s (mean |SHAP| = %.4f)\n",
           shap_importance$feature[1], shap_importance$mean_abs_shap[1]))
cat(sprintf("  Outputs: %s/*.png\n", out_dir))
cat(sprintf("  Elapsed: %.2f seconds\n", elapsed))
