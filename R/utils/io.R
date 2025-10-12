# ==============================================================================
# io.R
# Purpose: Timestamped write/read helpers for reproducible I/O
# ==============================================================================

#' Generate UTC timestamp in YYYYmmdd_HHMMSS format
#'
#' @return Character string timestamp
timestamp_utc <- function() {
  format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
}

#' Write CSV with timestamped filename
#'
#' @param df Data frame to write
#' @param base_path Base directory path
#' @param base_name Base filename (without extension)
#' @param timestamp Optional timestamp (default: generate new)
#' @return Path to written file
write_timestamped_csv <- function(df, base_path, base_name, timestamp = NULL) {
  if (is.null(timestamp)) {
    timestamp <- timestamp_utc()
  }

  filename <- sprintf("%s_%s.csv", base_name, timestamp)
  filepath <- file.path(base_path, filename)

  # TODO: Implement actual write with readr::write_csv
  # TODO: Return filepath

  return(filepath)
}

#' Write sidecar JSON with metadata
#'
#' @param filepath Path to data file
#' @param metadata List of metadata (schema_hash, row_count, etc.)
write_sidecar_json <- function(filepath, metadata) {
  json_path <- sub("\\.csv$", "_meta.json", filepath)

  # TODO: Add created_at timestamp
  # TODO: Write JSON with jsonlite::write_json(pretty = TRUE)

  return(json_path)
}

#' Compute schema hash from data frame
#'
#' @param df Data frame
#' @return SHA1 hash of column names and types
schema_hash <- function(df) {
  schema_str <- paste(names(df), sapply(df, class), collapse = "|")

  # TODO: Use digest::sha1 to compute hash

  return("placeholder_hash")
}

#' Read most recent timestamped file matching pattern
#'
#' @param base_path Base directory path
#' @param pattern File pattern (e.g., "games_*.csv")
#' @return Path to most recent file
read_latest <- function(base_path, pattern) {
  # TODO: List files matching pattern
  # TODO: Sort by timestamp in filename
  # TODO: Return most recent

  return(NULL)
}
