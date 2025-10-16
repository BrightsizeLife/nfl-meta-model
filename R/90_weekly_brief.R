#!/usr/bin/env Rscript
# ==============================================================================
# 90_weekly_brief.R
# Purpose: Generate single-page weekly model brief with metrics + plots
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(jsonlite)
})

start_time <- Sys.time()

# ==============================================================================
# Locate most recent artifacts
# ==============================================================================
# Find most recent XGBoost artifacts
xgb_dirs <- list.dirs("artifacts", recursive = FALSE, full.names = TRUE)
xgb_dirs <- xgb_dirs[grepl("[0-9]{8}_[0-9]{6}", basename(xgb_dirs))]
xgb_dirs <- xgb_dirs[sapply(xgb_dirs, function(d) dir.exists(file.path(d, "xgb")))]

if (length(xgb_dirs) == 0) {
  stop("ERROR: No XGBoost artifacts found in artifacts/*/xgb/")
}

xgb_artifact_dir <- xgb_dirs[length(xgb_dirs)]
xgb_timestamp <- basename(xgb_artifact_dir)
xgb_dir <- file.path(xgb_artifact_dir, "xgb")

cat(sprintf("Using XGBoost artifacts: %s\n", xgb_dir))

# Find most recent edge artifacts (may be different timestamp)
edge_dirs <- list.dirs("artifacts", recursive = FALSE, full.names = TRUE)
edge_dirs <- edge_dirs[grepl("[0-9]{8}_[0-9]{6}", basename(edge_dirs))]
edge_dirs <- edge_dirs[sapply(edge_dirs, function(d) dir.exists(file.path(d, "edge")))]

if (length(edge_dirs) > 0) {
  edge_artifact_dir <- edge_dirs[length(edge_dirs)]
  edge_timestamp <- basename(edge_artifact_dir)
  cat(sprintf("Using Edge artifacts: %s\n", file.path(edge_artifact_dir, "edge")))
} else {
  edge_artifact_dir <- NULL
  edge_timestamp <- NULL
}

# Use XGBoost timestamp for report
timestamp <- xgb_timestamp

results <- fromJSON(file.path(xgb_dir, "results.json"))
calibration_summary <- read_csv(file.path(xgb_dir, "calibration_summary.csv"), show_col_types = FALSE)
feature_importance <- read_csv(file.path(xgb_dir, "feature_importance.csv"), show_col_types = FALSE)

# ==============================================================================
# Load edge analysis
# ==============================================================================
edge_summary_files <- list.files("data/processed",
                                  pattern = "^edges_summary_threshold_.*\\.csv$",
                                  full.names = TRUE)
if (length(edge_summary_files) == 0) {
  warning("No edge summary found; skipping edge section")
  edge_summary <- NULL
} else {
  edge_summary <- read_csv(edge_summary_files[length(edge_summary_files)], show_col_types = FALSE)
}

edges_file <- list.files("data/processed", pattern = "^edges_[0-9]{8}_[0-9]{6}\\.csv$", full.names = TRUE)
if (length(edges_file) > 0) {
  edges <- read_csv(edges_file[length(edges_file)], show_col_types = FALSE)

  # 10-bin lift table
  edge_lift <- edges %>%
    mutate(edge_decile = ntile(abs_edge, 10)) %>%
    group_by(edge_decile) %>%
    summarise(
      n = n(),
      mean_abs_edge = mean(abs_edge),
      mean_loss_delta = mean(loss_delta),
      .groups = "drop"
    )
} else {
  edges <- NULL
  edge_lift <- NULL
}

# ==============================================================================
# Generate Markdown Report
# ==============================================================================
report_file <- file.path("reports", sprintf("weekly_brief_%s.md", timestamp))
dir.create("reports", showWarnings = FALSE, recursive = TRUE)

md <- c(
  sprintf("# Weekly Model Brief — %s\n", timestamp),
  sprintf("**Generated:** %s UTC\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")),
  sprintf("**XGBoost Artifacts:** `%s/`\n", xgb_artifact_dir),
  "",
  "---",
  "",
  "## Overall Performance",
  "",
  sprintf("- **Test Log Loss:** %.4f", results$test_logloss),
  sprintf("- **Test Brier Score:** %.4f", results$test_brier),
  sprintf("- **Test AUC-ROC:** %.4f", results$test_auc),
  sprintf("- **Calibration Slope:** %.3f (ideal: 1.0)", calibration_summary$slope),
  sprintf("- **Calibration Intercept:** %.3f (ideal: 0.0)", calibration_summary$intercept),
  "",
  "### Feature Importance (Top 5)",
  "",
  "| Feature | Gain |",
  "|---------|------|"
)

top_features <- feature_importance %>%
  arrange(desc(Gain)) %>%
  head(5)

for (i in 1:nrow(top_features)) {
  md <- c(md, sprintf("| %s | %.4f |", top_features$Feature[i], top_features$Gain[i]))
}

md <- c(md, "", "---", "")

# ==============================================================================
# Model vs Market
# ==============================================================================
if (!is.null(edge_summary)) {
  md <- c(md,
    "## Model vs Market",
    "",
    sprintf("**Edge Prevalence** (|edge| > τ):"),
    ""
  )

  for (i in 1:nrow(edge_summary)) {
    tau <- edge_summary$threshold[i]
    pct <- edge_summary$pct_flagged[i]
    mean_edge <- edge_summary$mean_edge_flagged[i]
    mean_gain <- edge_summary$mean_loss_delta_flagged[i]
    md <- c(md, sprintf("- τ=%.2f: %.1f%% flagged | mean |edge|=%.3f | gain=+%.3f log loss",
                        tau, pct, mean_edge, mean_gain))
  }

  md <- c(md, "")
}

# ==============================================================================
# Edge Lift Table
# ==============================================================================
if (!is.null(edge_lift)) {
  md <- c(md,
    "### Edge Lift by Decile",
    "",
    "| Decile | n | Mean |Edge| | Mean Gain |",
    "|--------|---|------------|-----------|"
  )

  for (i in 1:nrow(edge_lift)) {
    md <- c(md, sprintf("| %d | %d | %.3f | %+.3f |",
                        edge_lift$edge_decile[i],
                        edge_lift$n[i],
                        edge_lift$mean_abs_edge[i],
                        edge_lift$mean_loss_delta[i]))
  }

  md <- c(md, "")
}

md <- c(md, "---", "")

# ==============================================================================
# Plots
# ==============================================================================
md <- c(md, "## Diagnostic Plots", "")

# XGBoost plots (check for plots_small first, fallback to direct files)
xgb_plots_small <- file.path(xgb_dir, "plots_small")
if (dir.exists(xgb_plots_small)) {
  cal_plot <- file.path("..", xgb_plots_small, "calibration.png")
  fi_plot <- file.path("..", xgb_plots_small, "feature_importance.png")
} else {
  cal_plot <- file.path("..", xgb_dir, "calibration.png")
  fi_plot <- file.path("..", xgb_dir, "feature_importance.png")
}

md <- c(md,
  "### Model Calibration",
  "",
  sprintf("![Calibration](%s)", cal_plot),
  "",
  "### Feature Importance",
  "",
  sprintf("![Feature Importance](%s)", fi_plot),
  ""
)

# Edge plots
if (!is.null(edge_artifact_dir)) {
  edge_plots_small <- file.path(edge_artifact_dir, "edge", "plots_small")
} else {
  edge_plots_small <- NULL
}

if (!is.null(edge_plots_small) && dir.exists(edge_plots_small)) {
  md <- c(md,
    "### Edge Analysis",
    "",
    "#### Edge Lift by Decile",
    sprintf("![Edge Lift](%s)", file.path("..", edge_plots_small, "edge_lift_by_decile.png")),
    "",
    "#### Cumulative Edge Gain",
    sprintf("![Cumulative Gain](%s)", file.path("..", edge_plots_small, "cumulative_edge_gain.png")),
    "",
    "#### Model vs Market Probabilities",
    sprintf("![Model vs Market](%s)", file.path("..", edge_plots_small, "model_vs_market_prob_scatter.png")),
    "",
    "#### Mean |Edge| by Season",
    sprintf("![Edge by Season](%s)", file.path("..", edge_plots_small, "delta_prob_by_season.png")),
    ""
  )
}

# ==============================================================================
# Data Sources
# ==============================================================================
md <- c(md,
  "---",
  "",
  "## Data Sources",
  "",
  sprintf("- **XGBoost model:** `%s/model.xgb`", xgb_dir),
  sprintf("- **Feature importance:** `%s/feature_importance.csv`", xgb_dir),
  sprintf("- **Calibration:** `%s/calibration_summary.csv`", xgb_dir)
)

if (!is.null(edges)) {
  edges_csv <- basename(edges_file[length(edges_file)])
  md <- c(md, sprintf("- **Edge labels:** `data/processed/%s`", edges_csv))
}

md <- c(md,
  "",
  sprintf("**Seed:** %d (from XGBoost training)", results$seed),
  ""
)

# ==============================================================================
# Write Report
# ==============================================================================
writeLines(md, report_file)

elapsed <- difftime(Sys.time(), start_time, units = "secs")

cat(sprintf("\n=== Weekly Brief Generated ===\n"))
cat(sprintf("  Report: %s\n", report_file))
cat(sprintf("  Artifact timestamp: %s\n", timestamp))
cat(sprintf("  Lines: %d\n", length(md)))
cat(sprintf("  Elapsed: %.1f sec\n", elapsed))
