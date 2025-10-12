# ==============================================================================
# features.R
# Purpose: Feature engineering helpers
# ==============================================================================

#' Compute rest days between games for a team
#'
#' @param games Data frame with game_id, date, team columns sorted by date
#' @return Vector of rest days (NA for first game)
compute_rest_days <- function(games) {
  # TODO: Group by team, compute days since previous game
  # TODO: Return vector matching row order

  return(rep(NA_integer_, nrow(games)))
}

#' Compute previous game margin for a team
#'
#' @param games Data frame with game_id, date, team, margin columns sorted by date
#' @return Vector of previous margins (NA for first game)
compute_prev_margin <- function(games) {
  # TODO: Group by team, lag margin by 1 game
  # TODO: Return vector matching row order

  return(rep(NA_real_, nrow(games)))
}

#' Initialize Elo ratings for teams
#'
#' @param teams Character vector of team names
#' @param seed Seed method ("five38", "equal", or named vector)
#' @return Named vector of initial Elo ratings
init_elo <- function(teams, seed = "equal") {
  # TODO: Implement seeding strategies
  # TODO: "equal" = all 1500
  # TODO: "five38" = load from reference if available
  # TODO: named vector = use provided values

  elos <- setNames(rep(1500, length(teams)), teams)
  return(elos)
}

#' Update Elo ratings after a game
#'
#' @param elo_home Current home team Elo
#' @param elo_away Current away team Elo
#' @param home_win 1 if home won, 0 if away won
#' @param k K-factor (default 20)
#' @param hfa Home field advantage (default 65)
#' @return List with updated elo_home and elo_away
update_elo <- function(elo_home, elo_away, home_win, k = 20, hfa = 65) {
  # TODO: Compute expected win probability with HFA
  # TODO: Update ratings based on outcome
  # TODO: Return list(elo_home_new, elo_away_new)

  return(list(elo_home = elo_home, elo_away = elo_away))
}

#' Compute rolling Elo ratings across games
#'
#' @param games Data frame with game_id, home_team, away_team, home_win, sorted by date
#' @param init_elos Named vector of initial Elos
#' @return Data frame with game_id, elo_home, elo_away, elo_diff
compute_elo_ratings <- function(games, init_elos) {
  # TODO: Initialize Elo tracker
  # TODO: Loop through games in order
  # TODO: Record pre-game Elos
  # TODO: Update Elos after each game
  # TODO: Return data frame with game_id, elo_home, elo_away, elo_diff

  return(data.frame(
    game_id = games$game_id,
    elo_home = NA_real_,
    elo_away = NA_real_,
    elo_diff = NA_real_
  ))
}
