#!/usr/bin/env Rscript
# Install required packages

packages <- c("nflreadr", "dplyr", "readr", "lubridate", "jsonlite", "digest",
              "purrr", "stringr", "ggplot2", "tidyr")

for (pkg in packages) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat(sprintf("Installing %s...\n", pkg))
    install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
  }
}

cat("All packages installed.\n")
