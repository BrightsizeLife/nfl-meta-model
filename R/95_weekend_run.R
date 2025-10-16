#!/usr/bin/env Rscript
# ==============================================================================
# 95_weekend_run.R
# Purpose: One-shot runner for weekend live scoring workflow
# ==============================================================================

suppressPackageStartupMessages({
  library(yaml)
})

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)

# Default options
threshold <- NULL
books <- NULL
dryrun <- FALSE

# Parse args
i <- 1
while (i <= length(args)) {
  if (args[i] == "--threshold" && i < length(args)) {
    threshold <- as.numeric(args[i + 1])
    i <- i + 2
  } else if (args[i] == "--books" && i < length(args)) {
    books <- strsplit(args[i + 1], ",")[[1]]
    i <- i + 2
  } else if (args[i] == "--dryrun") {
    dryrun <- TRUE
    i <- i + 1
  } else {
    cat(sprintf("Unknown argument: %s\n", args[i]))
    i <- i + 1
  }
}

cat("==============================================\n")
cat("  Weekend Live Scoring Pipeline\n")
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

# Override config with command line args
if (!is.null(threshold)) {
  config$edge$edge_threshold <- threshold
}
if (!is.null(books)) {
  config$live$books_preference <- books
}

cat(sprintf("✓ Loaded config: %s\n", config_file))
cat(sprintf("  Edge threshold: %.2f\n", config$edge$edge_threshold))
cat(sprintf("  Preferred books: %s\n", paste(config$live$books_preference, collapse = ", ")))

if (dryrun) {
  cat("\n⚠️  DRY RUN MODE: No files will be written.\n")
}

cat("\n")

# ==============================================================================
# Step 1: Score upcoming games
# ==============================================================================
cat("[1/3] Scoring upcoming games...\n")
step_start <- Sys.time()

if (!dryrun) {
  score_status <- tryCatch({
    source("R/60_score_upcoming.R", local = TRUE)
    0
  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n", e$message))
    1
  })

  if (score_status != 0) {
    cat("\n❌ Scoring failed. Check:\n")
    cat("  - Is the current NFL season active?\n")
    cat("  - Are there upcoming games in the schedule?\n")
    cat("  - Run `Rscript R/01_ingest.R` if historical data is missing.\n")
    stop("Scoring failed. Halting pipeline.")
  }
} else {
  cat("  [SKIPPED - dry run]\n")
}

step_elapsed <- difftime(Sys.time(), step_start, units = "secs")
cat(sprintf("  Completed in %.1f sec\n\n", step_elapsed))

# ==============================================================================
# Step 2: Manual odds entry check
# ==============================================================================
cat("[2/3] Checking for manual odds CSV...\n")

odds_files <- list.files("data/live", pattern = "^odds_.*\\.csv$", full.names = TRUE)
if (length(odds_files) == 0) {
  cat("\n⚠️  No odds CSV found in data/live/\n\n")
  cat("NEXT STEPS:\n")
  cat("1. Manually collect odds from sportsbooks\n")
  cat("2. Create CSV file: data/live/odds_<timestamp>.csv\n")
  cat("3. Follow schema in docs/odds_live_manual.md\n")
  cat("4. Re-run this script after creating the odds file\n\n")
  cat("Example:\n")
  cat("  game_id,kickoff_et,book,moneyline_home,moneyline_away,spread_home,total\n")
  cat("  2024_10_KC_BUF,2024-11-10 16:25,draftkings,-140,+120,-2.5,47.5\n\n")
  stop("Manual odds file required. Halting pipeline.")
}

odds_file <- odds_files[length(odds_files)]
cat(sprintf("  ✓ Found: %s\n\n", basename(odds_file)))

# ==============================================================================
# Step 3: Join odds and compute edges
# ==============================================================================
cat("[3/4] Joining odds with predictions...\n")
step_start <- Sys.time()

if (!dryrun) {
  join_status <- tryCatch({
    source("R/61_join_live_odds.R", local = TRUE)
    0
  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n", e$message))
    1
  })

  if (join_status != 0) stop("Odds join failed. Halting pipeline.")
} else {
  cat("  [SKIPPED - dry run]\n")
}

step_elapsed <- difftime(Sys.time(), step_start, units = "secs")
cat(sprintf("  Completed in %.1f sec\n\n", step_elapsed))

# ==============================================================================
# Step 4: Generate weekend report
# ==============================================================================
cat("[4/4] Generating weekend picks report...\n")
step_start <- Sys.time()

if (!dryrun) {
  report_status <- tryCatch({
    source("R/95_weekend_report.R", local = TRUE)
    0
  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n", e$message))
    1
  })

  if (report_status != 0) stop("Report generation failed. Halting pipeline.")
} else {
  cat("  [SKIPPED - dry run]\n")
}

step_elapsed <- difftime(Sys.time(), step_start, units = "secs")
cat(sprintf("  Completed in %.1f sec\n\n", step_elapsed))

# ==============================================================================
# Summary
# ==============================================================================
pipeline_elapsed <- difftime(Sys.time(), pipeline_start, units = "secs")

cat("==============================================\n")
cat("  Pipeline Complete!\n")
cat("==============================================\n\n")
cat(sprintf("Total elapsed: %.1f seconds\n", pipeline_elapsed))
cat(sprintf("Timestamp: %s UTC\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")))

if (!dryrun) {
  cat("\nOutputs:\n")
  cat(sprintf("  - Upcoming predictions: data/live/upcoming_*.csv\n"))
  cat(sprintf("  - Edges: data/live/edges_upcoming_*.csv\n"))
  cat(sprintf("  - Report: reports/weekend_picks_*.md\n"))
  cat(sprintf("  - Plots: artifacts/*/live/plots_small/\n"))
  cat("\nNext steps:\n")
  cat("  - Review reports/weekend_picks_*.md for flagged picks\n")
  cat("  - Check edge distribution and model vs book scatter plots\n")
  cat("  - Validate picks before placing any bets\n\n")
} else {
  cat("\n(Dry run mode - no files written)\n\n")
}
