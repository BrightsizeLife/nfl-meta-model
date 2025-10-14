#!/usr/bin/env Rscript
# ==============================================================================
# edge.R
# Purpose: Edge/residual utilities for market inefficiency analysis
# ==============================================================================

#' Create off-target flag from residual
#'
#' @param r Residual (home_win - prob_book)
#' @param tau Threshold for flagging
#' @return Binary flag (1 if |r| > tau, else 0)
#'
#' @examples
#' make_off_flag(c(-0.1, 0.03, 0.06), tau = 0.05)
make_off_flag <- function(r, tau) {
  as.integer(abs(r) > tau)
}

#' Compute log loss
#'
#' @param y True binary outcomes (0 or 1)
#' @param p Predicted probabilities [0, 1]
#' @return Scalar log loss
logloss <- function(y, p) {
  eps <- 1e-15
  p <- pmax(pmin(p, 1 - eps), eps)
  -mean(y * log(p) + (1 - y) * log(1 - p))
}

#' Compute gain vs market (log loss improvement)
#'
#' @param y True binary outcomes
#' @param p_book Book probabilities
#' @param p_model Model probabilities
#' @return Scalar gain (positive = model better)
gain_vs_market <- function(y, p_book, p_model) {
  logloss(y, p_book) - logloss(y, p_model)
}

#' Bin observations by absolute edge and compute lift
#'
#' @param abs_edge Absolute difference |p_model - p_book|
#' @param y True outcomes
#' @param p_model Model probabilities
#' @param p_book Book probabilities
#' @param n_bins Number of bins (default 10)
#' @return Data frame with bin, n, mean_abs_edge, lift, model_logloss, book_logloss
#'
#' @examples
#' edge_lift_by_bin(abs_edge, home_win, p_model, p_book, n_bins = 10)
edge_lift_by_bin <- function(abs_edge, y, p_model, p_book, n_bins = 10) {
  suppressPackageStartupMessages(library(dplyr))

  df <- data.frame(
    abs_edge = abs_edge,
    y = y,
    p_model = p_model,
    p_book = p_book
  )

  df$bin <- cut(df$abs_edge,
               breaks = quantile(df$abs_edge, probs = seq(0, 1, length.out = n_bins + 1)),
               include.lowest = TRUE,
               labels = paste0("D", 1:n_bins))

  df %>%
    group_by(bin) %>%
    summarise(
      n = n(),
      mean_abs_edge = mean(abs_edge),
      model_logloss = logloss(y, p_model),
      book_logloss = logloss(y, p_book),
      lift = book_logloss - model_logloss,
      .groups = "drop"
    )
}

#' Compute precision and recall at threshold
#'
#' @param y True binary outcomes
#' @param score Predicted scores (probabilities or edge flags)
#' @param threshold Decision threshold
#' @return List with precision, recall, f1
precision_recall_at_threshold <- function(y, score, threshold) {
  pred <- as.integer(score >= threshold)
  tp <- sum(pred == 1 & y == 1)
  fp <- sum(pred == 1 & y == 0)
  fn <- sum(pred == 0 & y == 1)

  precision <- ifelse(tp + fp == 0, 0, tp / (tp + fp))
  recall <- ifelse(tp + fn == 0, 0, tp / (tp + fn))
  f1 <- ifelse(precision + recall == 0, 0, 2 * precision * recall / (precision + recall))

  list(precision = precision, recall = recall, f1 = f1)
}

#' Compute cumulative gain curve (sorted by descending abs_edge)
#'
#' @param abs_edge Absolute edge values
#' @param y True outcomes
#' @param p_model Model probabilities
#' @param p_book Book probabilities
#' @return Data frame with game_rank, abs_edge, gain, cumulative_gain
cumulative_gain_curve <- function(abs_edge, y, p_model, p_book) {
  df <- data.frame(
    abs_edge = abs_edge,
    y = y,
    p_model = p_model,
    p_book = p_book
  ) %>%
    arrange(desc(abs_edge)) %>%
    mutate(
      model_loss = logloss_single(y, p_model),
      book_loss = logloss_single(y, p_book),
      gain = book_loss - model_loss,
      cumulative_gain = cumsum(gain),
      game_rank = row_number()
    )

  return(df)
}

# Helper: single-observation log loss
logloss_single <- function(y, p) {
  eps <- 1e-15
  p <- pmax(pmin(p, 1 - eps), eps)
  -(y * log(p) + (1 - y) * log(1 - p))
}
