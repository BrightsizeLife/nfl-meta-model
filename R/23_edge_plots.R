#!/usr/bin/env Rscript
# ==============================================================================
# 23_edge_plots.R
# Purpose: Generate edge analysis plots with corrected definition
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
})

start_time <- Sys.time()

# Load edge data
edges_file <- list.files("data/processed", pattern = "^edges_[0-9]{8}_[0-9]{6}\\.csv$", full.names = TRUE)
if (length(edges_file) == 0) {
  stop("ERROR: No edges CSV found. Run R/20_edge_labels.R first.")
}
edges_file <- edges_file[length(edges_file)]  # Most recent
cat(sprintf("Loading: %s\n", basename(edges_file)))

edges <- read_csv(edges_file, show_col_types = FALSE)

# Extract timestamp from filename
timestamp_match <- regmatches(basename(edges_file), regexpr("[0-9]{8}_[0-9]{6}", basename(edges_file)))
if (length(timestamp_match) == 0) {
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
} else {
  timestamp <- timestamp_match
}

# Create output directory
out_dir <- file.path("artifacts", timestamp, "edge")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

subtitle_text <- "Edge = P(model_oof) - P(book)"

# ==============================================================================
# Plot 1: Edge lift by decile
# ==============================================================================
edges_decile <- edges %>%
  mutate(edge_decile = ntile(abs_edge, 10)) %>%
  group_by(edge_decile) %>%
  summarise(
    n = n(),
    mean_abs_edge = mean(abs_edge),
    mean_loss_delta = mean(loss_delta),
    .groups = "drop"
  )

p1 <- ggplot(edges_decile, aes(x = edge_decile, y = mean_loss_delta)) +
  geom_col(fill = "steelblue", alpha = 0.8) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  labs(
    title = "Edge Lift by Decile",
    subtitle = subtitle_text,
    x = "Edge Decile (1 = lowest |edge|, 10 = highest)",
    y = "Mean Log Loss Delta (book - model)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(out_dir, "edge_lift_by_decile.png"), p1, width = 8, height = 5, dpi = 150)
cat(sprintf("✓ %s\n", file.path(out_dir, "edge_lift_by_decile.png")))

# ==============================================================================
# Plot 2: Cumulative edge gain
# ==============================================================================
edges_sorted <- edges %>%
  arrange(desc(abs_edge)) %>%
  mutate(
    rank = row_number(),
    cumulative_gain = cumsum(loss_delta) / rank
  )

p2 <- ggplot(edges_sorted, aes(x = rank, y = cumulative_gain)) +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  labs(
    title = "Cumulative Edge Gain",
    subtitle = subtitle_text,
    x = "Games Ranked by |Edge| (High to Low)",
    y = "Cumulative Mean Log Loss Gain"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(out_dir, "cumulative_edge_gain.png"), p2, width = 8, height = 5, dpi = 150)
cat(sprintf("✓ %s\n", file.path(out_dir, "cumulative_edge_gain.png")))

# ==============================================================================
# Plot 3: Model vs Market Probability Scatter
# ==============================================================================
p3 <- ggplot(edges, aes(x = prob_book, y = p_model_oof)) +
  geom_point(alpha = 0.3, color = "steelblue") +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
  labs(
    title = "Model vs Market Probabilities",
    subtitle = subtitle_text,
    x = "Book Probability (from spread)",
    y = "Model OOF Probability"
  ) +
  coord_fixed() +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(out_dir, "model_vs_market_prob_scatter.png"), p3, width = 7, height = 7, dpi = 150)
cat(sprintf("✓ %s\n", file.path(out_dir, "model_vs_market_prob_scatter.png")))

# ==============================================================================
# Plot 4: Delta Probability by Season
# ==============================================================================
edges_season <- edges %>%
  group_by(season) %>%
  summarise(
    n = n(),
    mean_edge = mean(edge),
    sd_edge = sd(edge),
    mean_abs_edge = mean(abs_edge),
    .groups = "drop"
  )

p4 <- ggplot(edges_season, aes(x = factor(season), y = mean_abs_edge)) +
  geom_col(fill = "steelblue", alpha = 0.8) +
  geom_errorbar(aes(ymin = pmax(0, mean_abs_edge - sd_edge), ymax = mean_abs_edge + sd_edge),
                width = 0.2, color = "gray30") +
  labs(
    title = "Mean |Edge| by Season",
    subtitle = subtitle_text,
    x = "Season",
    y = "Mean |Edge| (± SD)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(out_dir, "delta_prob_by_season.png"), p4, width = 8, height = 5, dpi = 150)
cat(sprintf("✓ %s\n", file.path(out_dir, "delta_prob_by_season.png")))

# ==============================================================================
# Summary
# ==============================================================================
elapsed <- difftime(Sys.time(), start_time, units = "secs")

cat(sprintf("\n=== Edge Plots Generated ===\n"))
cat(sprintf("  Input: %s (%d rows)\n", basename(edges_file), nrow(edges)))
cat(sprintf("  Output: %s\n", out_dir))
cat(sprintf("  Files: 4 PNG plots\n"))
cat(sprintf("  Elapsed: %.1f sec\n", elapsed))
