#!/usr/bin/env Rscript
# ==============================================================================
# edge.R
# Purpose: Edge/residual utilities for market inefficiency analysis
# ==============================================================================

#' Create off-target flag from edge
#'
#' @param edge Edge value (p_model - p_book)
#' @param tau Threshold for flagging
#' @return Binary flag (1 if |edge| > tau, else 0)
make_off_flag <- function(edge, tau) {
  as.integer(abs(edge) > tau)
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
