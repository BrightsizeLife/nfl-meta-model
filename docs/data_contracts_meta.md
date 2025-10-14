# Meta-Model Data Contracts

## Overview

Multi-model system for NFL prediction with specialized components:
- **Win models**: P(home_win) from various sources
- **Edge models**: Market inefficiency detection (residuals + flags)
- **Points models**: Offensive/defensive scoring predictions
- **Reconcile**: Combine components for final predictions

---

## odds_books.csv

**Purpose**: Multi-source odds/probabilities (one row per game per book)

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| game_id | character | Unique game identifier | "2024_05_KC_BUF" |
| book_id | character | Sportsbook/model identifier | "pinnacle", "fanduel", "market_proxy" |
| collected_at | datetime | Timestamp of odds collection | "2024-10-12 18:30:00" |
| prob_home | numeric | Implied P(home_win) after de-vig | 0.55 |
| prob_away | numeric | Implied P(away_win) after de-vig | 0.45 |
| spread_line | numeric | Spread (home perspective) | -3.5 |
| total_line | numeric | Over/under total | 47.5 |
| de_vig_method | character | De-vigging method used | "multiplicative", "shin", "power" |
| odds_type | character | Odds format source | "american", "decimal", "implied" |

**Rules**:
- `prob_home + prob_away` should equal 1.0 (post de-vig)
- `book_id = "market_proxy"` for v0 baseline (isotonic from spread_close)
- One row per game-book pair; multiple books → multiple rows
- Collected before kickoff only

**v0 Implementation** (current):
- Single book: `book_id = "market_proxy"`
- `prob_home = market_prob(spread_close)` from isotonic regression
- `prob_away = 1 - prob_home`

**v1+ Roadmap**:
- Ingest from The Odds API (Pinnacle, FanDuel, DraftKings, etc.)
- Track line movement over time (multiple `collected_at` per game-book)
- Compare de-vig methods (multiplicative vs Shin vs power)

---

## edges.csv

**Purpose**: Market inefficiency targets derived from model vs book residuals

| Column | Type | Description | Range/Example |
|--------|------|-------------|---------------|
| game_id | character | Unique game identifier | "2024_05_KC_BUF" |
| book_id | character | Book used for baseline | "market_proxy" |
| home_win | integer | Actual outcome | 0 or 1 |
| prob_book | numeric | Book's P(home_win) | 0.55 |
| prob_model | numeric | Model's P(home_win) (out-of-fold if available) | 0.62 |
| residual | numeric | r = home_win - prob_book | -0.55 to +0.45 |
| direction | integer | sign(residual): -1, 0, +1 | -1 (book overestimated) |
| off_flag_003 | integer | \|residual\| > 0.03 | 0 or 1 |
| off_flag_005 | integer | \|residual\| > 0.05 | 0 or 1 |
| off_flag_007 | integer | \|residual\| > 0.07 | 0 or 1 |
| delta_prob | numeric | prob_model - prob_book | -0.3 to +0.3 |
| delta_logit | numeric | qlogis(prob_model) - qlogis(prob_book) (optional) | -2 to +2 |
| abs_edge | numeric | \|delta_prob\| | 0 to 0.3 |

**Interpretation**:
- **residual > 0**: Book underestimated home team (home won or came closer than expected)
- **residual < 0**: Book overestimated home team
- **off_flag_τ = 1**: Book's probability was off by more than τ threshold
- **delta_prob**: Model's disagreement with book (edge signal)

**Use Cases**:
1. **Regression target**: Predict `residual` to correct book probabilities
2. **Classification target**: Predict `off_flag_005` to flag unreliable book lines
3. **Edge detection**: Use `abs_edge` to rank games by model confidence
4. **Lift analysis**: Measure model improvement vs book in high-`abs_edge` games

**Notes**:
- Use out-of-fold `prob_model` to avoid overfitting (if available)
- v0: Uses test-set predictions from XGBoost v1.2
- Future: Track per-book residuals when multi-source odds added

---

## Model-Specific Outputs

### Win Models (`models/win/`, `artifacts/win/`)

**Purpose**: P(home_win) predictions

**Inputs**: `context.csv` + `games.csv` (features: spread, elo, rest, margins, etc.)

**Outputs**:
- `predictions.csv`: game_id, prob_home, prob_away
- `metrics.csv`: log_loss, brier, roc_auc, calibration_slope
- `cv_results.csv`: per-fold metrics
- Plots: calibration.png, roc.png, feature_importance.png

### Edge Models (`models/edge/`, `artifacts/edge/`)

**Purpose**: Market inefficiency detection

**Regression** (`21_edge_reg_fit.R`):
- Target: `residual`
- Metrics: RMSE, MAE, R²
- Slices: per-season, per-week, per-book

**Classification** (`22_edge_cls_fit.R`):
- Target: `off_flag_005` (or 003/007)
- Metrics: PR-AUC, ROC-AUC, precision@K
- Output: threshold table, lift curves

### Points Models (`models/points_off/`, `models/points_def/`)

**Purpose**: Scoring predictions for spread/total synthesis

**Inputs**: Team-level features (offense/defense stats, pace, etc.)

**Targets**:
- `points_off`: Points scored by focal team
- `points_def`: Points allowed by focal team

**Approaches**:
- Poisson/Negative Binomial GLM
- XGBoost regression
- Ensemble

**Outputs**:
- `predictions.csv`: game_id, team, predicted_points, prediction_interval
- `metrics.csv`: RMSE, MAE, coverage (90% PI)

### Reconcile (`models/reconcile/`)

**Purpose**: Combine win, edge, and points models for final predictions

**Approach** (v2+):
- Use points models to synthesize spread/total
- Adjust win probabilities by edge model corrections
- Ensemble multiple win models with learned weights
- Output: unified prediction with uncertainty

---

## Versioning

- **v0** (current): Single book (market_proxy), XGBoost win model, edge targets computed
- **v1**: Multi-book odds ingestion, edge regression/classification, points model scaffolds
- **v2**: Full meta-model ensemble, hierarchical calibration per book, reconcile module
- **v3**: Bayesian uncertainty (BART), conformal prediction intervals

---

## Data Quality Checks

### odds_books.csv
- `prob_home + prob_away = 1.0` (tolerance ±0.01)
- `collected_at < kickoff_time`
- No missing book_id or game_id

### edges.csv
- `residual ∈ [-1, +1]` (by definition)
- `off_flag_τ` consistent with `|residual| > τ`
- `prob_book` and `prob_model` both in [0, 1]
- Join 1:1 with games.csv on game_id (for single-book v0)

---

## References

- **De-vigging**: [Pinnacle's guide](https://www.pinnacle.com/en/betting-articles/betting-strategy/removing-the-vig)
- **Shin method**: Shin, H. S. (1991). "Prices of state contingent claims with insider traders"
- **Market efficiency**: Efficient Market Hypothesis applied to sports betting
