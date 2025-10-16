#!/usr/bin/env Rscript
# ==============================================================================
# 00_run_all.R
# Purpose: One-shot orchestration script for full model pipeline
# ==============================================================================

suppressPackageStartupMessages({
  library(yaml)
})

cat("==============================================\n")
cat("  NFL Meta-Model Pipeline Runner\n")
cat("==============================================\n\n")

pipeline_start <- Sys.time()

# ==============================================================================
# Load Configuration
# ==============================================================================
config_file <- "config/default.yml"
if (!file.exists(config_file)) {
  stop(sprintf("ERROR: Config file not found: %s", config_file))
}

config <- read_yaml(config_file)
cat(sprintf("✓ Loaded config: %s\n", config_file))
cat(sprintf("  Seasons: %s\n", paste(config$data$seasons, collapse = ", ")))
cat(sprintf("  Seed: %d\n", config$model$seed))
cat(sprintf("  Edge thresholds: %s\n\n", paste(config$edge$thresholds, collapse = ", ")))

# ==============================================================================
# Step 1: Ingest
# ==============================================================================
cat("[1/6] Running ingest...\n")
step_start <- Sys.time()

ingest_status <- tryCatch({
  source("R/01_ingest.R", local = TRUE)
  0
}, error = function(e) {
  cat(sprintf("  ERROR: %s\n", e$message))
  1
})

if (ingest_status != 0) stop("Ingest failed. Halting pipeline.")

step_elapsed <- difftime(Sys.time(), step_start, units = "secs")
cat(sprintf("  Completed in %.1f sec\n\n", step_elapsed))

# ==============================================================================
# Step 2: Features
# ==============================================================================
cat("[2/6] Running feature engineering...\n")
step_start <- Sys.time()

features_status <- tryCatch({
  source("R/02_features.R", local = TRUE)
  0
}, error = function(e) {
  cat(sprintf("  ERROR: %s\n", e$message))
  1
})

if (features_status != 0) stop("Feature engineering failed. Halting pipeline.")

step_elapsed <- difftime(Sys.time(), step_start, units = "secs")
cat(sprintf("  Completed in %.1f sec\n\n", step_elapsed))

# ==============================================================================
# Step 3: XGBoost Fit (with OOF export)
# ==============================================================================
cat("[3/6] Running XGBoost training...\n")
step_start <- Sys.time()

xgb_status <- tryCatch({
  source("R/04_xgb_fit.R", local = TRUE)
  0
}, error = function(e) {
  cat(sprintf("  ERROR: %s\n", e$message))
  1
})

if (xgb_status != 0) stop("XGBoost training failed. Halting pipeline.")

step_elapsed <- difftime(Sys.time(), step_start, units = "secs")
cat(sprintf("  Completed in %.1f sec\n\n", step_elapsed))

# ==============================================================================
# Step 4: Edge Labels
# ==============================================================================
cat("[4/6] Running edge label generation...\n")
step_start <- Sys.time()

edge_status <- tryCatch({
  source("R/20_edge_labels.R", local = TRUE)
  0
}, error = function(e) {
  cat(sprintf("  ERROR: %s\n", e$message))
  1
})

if (edge_status != 0) stop("Edge label generation failed. Halting pipeline.")

step_elapsed <- difftime(Sys.time(), step_start, units = "secs")
cat(sprintf("  Completed in %.1f sec\n\n", step_elapsed))

# ==============================================================================
# Step 5: Edge Plots
# ==============================================================================
cat("[5/6] Running edge plot generation...\n")
step_start <- Sys.time()

plots_status <- tryCatch({
  source("R/23_edge_plots.R", local = TRUE)
  0
}, error = function(e) {
  cat(sprintf("  ERROR: %s\n", e$message))
  1
})

if (plots_status != 0) stop("Edge plots failed. Halting pipeline.")

step_elapsed <- difftime(Sys.time(), step_start, units = "secs")
cat(sprintf("  Completed in %.1f sec\n\n", step_elapsed))

# ==============================================================================
# Step 6: Weekly Brief
# ==============================================================================
cat("[6/6] Running weekly brief generation...\n")
step_start <- Sys.time()

brief_status <- tryCatch({
  source("R/90_weekly_brief.R", local = TRUE)
  0
}, error = function(e) {
  cat(sprintf("  ERROR: %s\n", e$message))
  1
})

if (brief_status != 0) stop("Weekly brief failed. Halting pipeline.")

step_elapsed <- difftime(Sys.time(), step_start, units = "secs")
cat(sprintf("  Completed in %.1f sec\n\n", step_elapsed))

# ==============================================================================
# Summary
# ==============================================================================
pipeline_elapsed <- difftime(Sys.time(), pipeline_start, units = "mins")

cat("==============================================\n")
cat("  Pipeline Complete!\n")
cat("==============================================\n\n")
cat(sprintf("Total elapsed: %.2f minutes\n", pipeline_elapsed))
cat(sprintf("Timestamp: %s UTC\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")))
cat("\nOutputs:\n")
cat(sprintf("  - Raw data: %s/\n", config$data$raw_dir))
cat(sprintf("  - Processed data: %s/\n", config$data$processed_dir))
cat(sprintf("  - Artifacts: %s/<timestamp>/\n", config$output$artifacts_dir))
cat(sprintf("  - Reports: %s/weekly_brief_<timestamp>.md\n", config$output$reports_dir))
cat("\nNext steps:\n")
cat("  - Review reports/weekly_brief_*.md\n")
cat("  - Check artifacts/*/plots_small/ for diagnostic plots\n")
cat("  - Validate edge analysis and calibration metrics\n\n")
