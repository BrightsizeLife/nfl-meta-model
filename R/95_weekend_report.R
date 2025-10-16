#!/usr/bin/env Rscript
# ==============================================================================
# 95_weekend_report.R
# Purpose: Generate weekend picks report with edges and visualizations
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(yaml)
})

start_time <- Sys.time()

cat("=== Generating Weekend Picks Report ===\n\n")

# ==============================================================================
# Load configuration
# ==============================================================================
config <- read_yaml("config/default.yml")
edge_threshold <- config$edge$edge_threshold

# ==============================================================================
# Load edges
# ==============================================================================
edges_files <- list.files("data/live", pattern = "^edges_upcoming_.*\\.csv$", full.names = TRUE)
if (length(edges_files) == 0) {
  stop("ERROR: No edges CSV found. Run R/61_join_live_odds.R first.")
}

edges_file <- edges_files[length(edges_files)]
cat(sprintf("Loading: %s\n", basename(edges_file)))

edges <- read_csv(edges_file, show_col_types = FALSE)

# Extract timestamp
timestamp_match <- regmatches(basename(edges_file), regexpr("[0-9]{8}_[0-9]{6}", basename(edges_file)))
if (length(timestamp_match) == 0) {
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
} else {
  timestamp <- timestamp_match
}

cat(sprintf("  %d games loaded\n", nrow(edges)))
cat(sprintf("  Flagged (threshold=%.2f): %d\n\n", edge_threshold, sum(edges$flag)))

# ==============================================================================
# Create plots
# ==============================================================================
cat("Generating plots...\n")

plots_dir <- file.path("artifacts", timestamp, "live", "plots")
plots_small_dir <- file.path("artifacts", timestamp, "live", "plots_small")
dir.create(plots_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(plots_small_dir, recursive = TRUE, showWarnings = FALSE)

# Plot 1: Edge histogram
p1 <- ggplot(edges, aes(x = edge)) +
  geom_histogram(bins = 20, fill = "steelblue", alpha = 0.8) +
  geom_vline(xintercept = c(-edge_threshold, edge_threshold),
             linetype = "dashed", color = "red") +
  labs(
    title = "Edge Distribution",
    subtitle = sprintf("Threshold = ±%.2f | n = %d games", edge_threshold, nrow(edges)),
    x = "Edge (P_model - P_book)",
    y = "Count"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(plots_dir, "edge_histogram.png"), p1, width = 8, height = 5, dpi = 150)
ggsave(file.path(plots_small_dir, "edge_histogram.png"), p1, width = 8, height = 5, dpi = 100)

# Plot 2: Model vs Book probability scatter
p2 <- ggplot(edges, aes(x = p_book, y = p_model)) +
  geom_point(aes(color = flag), size = 3, alpha = 0.7) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray40") +
  scale_color_manual(values = c("FALSE" = "gray60", "TRUE" = "red"),
                     labels = c("FALSE" = sprintf("Not flagged (|edge| ≤ %.2f)", edge_threshold),
                               "TRUE" = sprintf("Flagged (|edge| > %.2f)", edge_threshold))) +
  labs(
    title = "Model vs Book Probabilities",
    subtitle = sprintf("n = %d games | Red = flagged picks", nrow(edges)),
    x = "Book Probability (de-vigged)",
    y = "Model Probability",
    color = "Status"
  ) +
  coord_fixed() +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave(file.path(plots_dir, "model_vs_book_scatter.png"), p2, width = 7, height = 7, dpi = 150)
ggsave(file.path(plots_small_dir, "model_vs_book_scatter.png"), p2, width = 7, height = 7, dpi = 100)

cat(sprintf("✓ Plots saved to: %s\n", plots_small_dir))

# ==============================================================================
# Generate markdown report
# ==============================================================================
cat("\nGenerating report...\n")

report_file <- file.path("reports", sprintf("weekend_picks_%s.md", timestamp))

# Summary stats
n_flagged <- sum(edges$flag)
pct_flagged <- 100 * mean(edges$flag)
mean_edge <- mean(edges$abs_edge)

# Flagged picks table
flagged_picks <- edges %>%
  filter(flag) %>%
  arrange(desc(abs_edge)) %>%
  select(game_id, kickoff_et, home_team, away_team, week, book, p_book, p_model, edge, side)

md <- c(
  sprintf("# Weekend Picks Report — %s\n", timestamp),
  sprintf("**Generated:** %s UTC\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")),
  sprintf("**Edge Threshold:** %.2f\n", edge_threshold),
  "",
  "---",
  "",
  "## Summary",
  "",
  sprintf("- **Total Games:** %d", nrow(edges)),
  sprintf("- **Flagged Picks:** %d (%.1f%%)", n_flagged, pct_flagged),
  sprintf("- **Mean |Edge|:** %.3f", mean_edge),
  sprintf("- **Edge Range:** [%.3f, %.3f]", min(edges$edge), max(edges$edge)),
  "",
  "### Picks by Book",
  ""
)

book_counts <- edges %>%
  count(book) %>%
  arrange(desc(n))

for (i in 1:nrow(book_counts)) {
  md <- c(md, sprintf("- **%s:** %d games", book_counts$book[i], book_counts$n[i]))
}

md <- c(md, "", "---", "")

# Flagged picks section
if (n_flagged > 0) {
  md <- c(md,
    "## Flagged Picks",
    "",
    sprintf("**%d games with |edge| > %.2f**\n", n_flagged, edge_threshold),
    "| Game | Kickoff (ET) | Week | Book | P(Book) | P(Model) | Edge | Side |",
    "|------|-------------|------|------|---------|----------|------|------|"
  )

  for (i in 1:nrow(flagged_picks)) {
    game_label <- sprintf("%s @ %s", flagged_picks$away_team[i], flagged_picks$home_team[i])
    md <- c(md, sprintf("| %s | %s | %d | %s | %.3f | %.3f | %+.3f | %s |",
                        game_label,
                        flagged_picks$kickoff_et[i],
                        flagged_picks$week[i],
                        flagged_picks$book[i],
                        flagged_picks$p_book[i],
                        flagged_picks$p_model[i],
                        flagged_picks$edge[i],
                        flagged_picks$side[i]))
  }

  md <- c(md, "")
} else {
  md <- c(md,
    "## Flagged Picks",
    "",
    sprintf("**No games with |edge| > %.2f**\n", edge_threshold),
    "Consider lowering the threshold or reviewing model calibration.",
    ""
  )
}

md <- c(md, "---", "")

# All games table
md <- c(md,
  "## All Games",
  "",
  "| Game | Kickoff (ET) | Week | Book | P(Book) | P(Model) | Edge | Flagged |",
  "|------|-------------|------|------|---------|----------|------|---------|"
)

edges_sorted <- edges %>% arrange(desc(abs_edge))

for (i in 1:nrow(edges_sorted)) {
  game_label <- sprintf("%s @ %s", edges_sorted$away_team[i], edges_sorted$home_team[i])
  flag_emoji <- ifelse(edges_sorted$flag[i], "🚩", "")
  md <- c(md, sprintf("| %s | %s | %d | %s | %.3f | %.3f | %+.3f | %s |",
                      game_label,
                      edges_sorted$kickoff_et[i],
                      edges_sorted$week[i],
                      edges_sorted$book[i],
                      edges_sorted$p_book[i],
                      edges_sorted$p_model[i],
                      edges_sorted$edge[i],
                      flag_emoji))
}

md <- c(md, "", "---", "")

# Plots section
md <- c(md,
  "## Visualizations",
  "",
  "### Edge Distribution",
  sprintf("![Edge Histogram](../artifacts/%s/live/plots_small/edge_histogram.png)", timestamp),
  "",
  "### Model vs Book Probabilities",
  sprintf("![Scatter](../artifacts/%s/live/plots_small/model_vs_book_scatter.png)", timestamp),
  "",
  "---",
  "",
  "## Data Sources",
  "",
  sprintf("- **Predictions:** `data/live/upcoming_%s.csv`", timestamp),
  sprintf("- **Odds:** `data/live/odds_*.csv` (manual entry)"),
  sprintf("- **Edges:** `data/live/edges_upcoming_%s.csv`", timestamp),
  sprintf("- **Model:** XGBoost baseline from `artifacts/*/xgb/model.xgb`"),
  ""
)

writeLines(md, report_file)

elapsed <- difftime(Sys.time(), start_time, units = "secs")

cat(sprintf("\n=== Weekend Report Generated ===\n"))
cat(sprintf("  Report: %s\n", report_file))
cat(sprintf("  Flagged picks: %d\n", n_flagged))
cat(sprintf("  Plots: %s\n", plots_small_dir))
cat(sprintf("  Elapsed: %.1f sec\n", elapsed))
