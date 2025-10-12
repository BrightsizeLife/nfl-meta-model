#!/usr/bin/env Rscript
# ==============================================================================
# 03_eda.R
# Purpose: Exploratory data analysis - structure checks, summaries, plots
# ==============================================================================
# Inputs:  --in_raw (data/raw), --in_proc (data/processed)
# Outputs: reports/eda_<timestamp>.md, artifacts/<timestamp>/eda/ (plots)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(purrr)
})

start_time <- Sys.time()

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)
in_raw <- "data/raw"
in_proc <- "data/processed"

for (i in seq_along(args)) {
  if (args[i] == "--in_raw" && i < length(args)) {
    in_raw <- args[i + 1]
  } else if (args[i] == "--in_proc" && i < length(args)) {
    in_proc <- args[i + 1]
  }
}

# Find most recent files
games_files <- list.files(in_raw, pattern = "^games_.*\\.csv$", full.names = TRUE)
context_files <- list.files(in_proc, pattern = "^context_.*\\.csv$", full.names = TRUE)

if (length(games_files) == 0) stop("No games CSV found")
if (length(context_files) == 0) stop("No context CSV found")

games_file <- games_files[length(games_files)]
context_file <- context_files[length(context_files)]

cat(sprintf("Reading games: %s\n", games_file))
cat(sprintf("Reading context: %s\n", context_file))

games <- read_csv(games_file, show_col_types = FALSE)
context <- read_csv(context_file, show_col_types = FALSE)

# Create output dirs
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
plot_dir <- file.path("artifacts", timestamp, "eda")
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

# Initialize report
report_lines <- c(
  sprintf("# EDA Report - %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Data Files",
  sprintf("- Games: `%s`", basename(games_file)),
  sprintf("- Context: `%s`", basename(context_file)),
  ""
)

# Schema summary
report_lines <- c(
  report_lines,
  "## Schema Summary",
  "",
  "### games.csv",
  "```",
  capture.output(str(games)),
  "```",
  "",
  "### context.csv",
  "```",
  capture.output(str(context)),
  "```",
  ""
)

# Row counts
report_lines <- c(
  report_lines,
  "## Row Counts",
  sprintf("- Games: %d", nrow(games)),
  sprintf("- Context: %d", nrow(context)),
  sprintf("- Join check (1:1): %s", ifelse(nrow(games) == nrow(context), "PASS", "FAIL")),
  ""
)

# NA audit
games_na <- colSums(is.na(games))
context_na <- colSums(is.na(context))

report_lines <- c(
  report_lines,
  "## Missing Value Audit",
  "",
  "### games.csv",
  "```",
  capture.output(print(games_na[games_na > 0])),
  "```",
  "",
  "### context.csv",
  "```",
  capture.output(print(context_na[context_na > 0])),
  "```",
  ""
)

# Join validation
joined <- games %>%
  inner_join(context, by = "game_id")

report_lines <- c(
  report_lines,
  "## Join Validation",
  sprintf("- Inner join rows: %d", nrow(joined)),
  sprintf("- Orphan games: %d", nrow(games) - nrow(joined)),
  sprintf("- Orphan context: %d", nrow(context) - nrow(joined)),
  ""
)

# Key distributions
report_lines <- c(
  report_lines,
  "## Key Distributions",
  ""
)

# Home win rate
home_win_rate <- mean(games$home_win, na.rm = TRUE)
report_lines <- c(
  report_lines,
  sprintf("- Home win rate: %.3f", home_win_rate),
  ""
)

# Plot 1: Home win distribution by season
p1 <- games %>%
  group_by(season) %>%
  summarize(home_win_rate = mean(home_win, na.rm = TRUE), .groups = "drop") %>%
  ggplot(aes(x = season, y = home_win_rate)) +
  geom_line() +
  geom_point() +
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "red") +
  labs(title = "Home Win Rate by Season", y = "Home Win Rate", x = "Season") +
  theme_minimal()

plot1_file <- file.path(plot_dir, "home_win_by_season.png")
ggsave(plot1_file, p1, width = 8, height = 5)
report_lines <- c(report_lines, sprintf("![Home Win by Season](%s)", plot1_file), "")

# Plot 2: Elo diff distribution
p2 <- context %>%
  ggplot(aes(x = elo_diff)) +
  geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7) +
  labs(title = "Elo Difference Distribution", x = "Elo Diff (Home - Away + HFA)", y = "Count") +
  theme_minimal()

plot2_file <- file.path(plot_dir, "elo_diff_dist.png")
ggsave(plot2_file, p2, width = 8, height = 5)
report_lines <- c(report_lines, sprintf("![Elo Diff Distribution](%s)", plot2_file), "")

# Plot 3: Rest days distribution
p3 <- context %>%
  select(rest_home, rest_away) %>%
  tidyr::pivot_longer(everything(), names_to = "type", values_to = "rest_days") %>%
  ggplot(aes(x = rest_days, fill = type)) +
  geom_histogram(bins = 15, position = "dodge", alpha = 0.7) +
  labs(title = "Rest Days Distribution", x = "Days", y = "Count") +
  theme_minimal()

plot3_file <- file.path(plot_dir, "rest_days_dist.png")
ggsave(plot3_file, p3, width = 8, height = 5)
report_lines <- c(report_lines, sprintf("![Rest Days Distribution](%s)", plot3_file), "")

# Glimpse of data
report_lines <- c(
  report_lines,
  "## Data Glimpse (first 20 rows)",
  "",
  "### games.csv",
  "```",
  capture.output(print(head(games, 20), n = 20)),
  "```",
  "",
  "### context.csv",
  "```",
  capture.output(print(head(context, 20), n = 20)),
  "```",
  ""
)

# Range checks
report_lines <- c(
  report_lines,
  "## Range Validation",
  sprintf("- Week range: [%d, %d]", min(games$week, na.rm = TRUE), max(games$week, na.rm = TRUE)),
  sprintf("- Rest home range: [%d, %d]", min(context$rest_home, na.rm = TRUE), max(context$rest_home, na.rm = TRUE)),
  sprintf("- Rest away range: [%d, %d]", min(context$rest_away, na.rm = TRUE), max(context$rest_away, na.rm = TRUE)),
  sprintf("- Elo diff finite: %s", ifelse(all(is.finite(context$elo_diff)), "PASS", "FAIL")),
  ""
)

# Write report
report_file <- file.path("reports", sprintf("eda_%s.md", timestamp))
dir.create("reports", showWarnings = FALSE)
writeLines(report_lines, report_file)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat("\n=== Summary ===\n")
cat(sprintf("Report: %s\n", report_file))
cat(sprintf("Plots: %s\n", plot_dir))
cat(sprintf("Elapsed: %.2f seconds\n", elapsed))
