# Context Features Overview

This document describes all features used in the NFL meta-model, their definitions, typical ranges, modeling rationale, and leakage checks.

---

## Target Variable

### `home_win`
- **Definition**: Binary indicator (1 = home team won, 0 = away team won)
- **Units**: Boolean (0 or 1)
- **Typical Range**: ~55% home wins historically (varies by season)
- **Why It Matters**: Primary prediction target for win probability models
- **Leakage Notes**: ✅ No leakage risk (outcome variable)

---

## Market Features

### `spread_close`
- **Definition**: Closing point spread from sportsbooks (negative = home favored)
- **Units**: Points (e.g., -7.0 means home team favored by 7 points)
- **Typical Range**: [-14, +14] (95% of games); extremes can reach ±20
- **Why It Matters**: Market consensus on expected margin; strong predictor of win probability
- **Leakage Notes**: ⚠️ Must use *closing* spread (pre-game); avoid "current" live spreads
- **Sanity Check**:
  - Home underdogs (positive spread) should be <50% of games
  - Check for unrealistic values (|spread| > 30)
  - Verify spread == 0 is rare (<5% of games)

### `total_close`
- **Definition**: Closing over/under total points (both teams combined)
- **Units**: Points (e.g., 48.5 means market expects ~49 total points)
- **Typical Range**: [38, 54] (95% of games); weather/style can push extremes
- **Why It Matters**: Proxy for game pace, offensive strength, and scoring environment
- **Leakage Notes**: ⚠️ Must use *closing* total (pre-game); avoid in-game totals
- **Sanity Check**:
  - Check for totals < 30 or > 65 (investigate outliers)
  - Verify correlation with weather (low totals in bad weather)

---

## Temporal Features

### `season`
- **Definition**: NFL season year (e.g., 2023 for 2023-24 season)
- **Units**: Year (integer)
- **Typical Range**: [2018, 2024] in current dataset
- **Why It Matters**: Controls for rule changes, league trends, roster evolution
- **Leakage Notes**: ✅ No leakage (known pre-game)
- **Sanity Check**: All games in same season should have same year

### `week`
- **Definition**: Week number within season (1-22, includes playoffs)
- **Units**: Integer week number
- **Typical Range**: [1, 18] regular season; [19, 22] playoffs
- **Why It Matters**: Captures seasonality, playoff intensity, roster health changes
- **Leakage Notes**: ✅ No leakage (known pre-game)
- **Sanity Check**: Week should be ∈ [1, 22]; playoff weeks (>18) are rare

---

## Rest & Schedule Features

### `rest_home`
- **Definition**: Days of rest for home team since last game
- **Units**: Days (integer)
- **Typical Range**: [3, 10] (short week to bye week); 180+ for season opener
- **Why It Matters**: Rest advantage correlates with injury recovery and performance
- **Leakage Notes**: ✅ No leakage (known from schedule)
- **Sanity Check**:
  - Most games have 6-8 days rest (standard week)
  - Short weeks (Thu games) have ~3-4 days
  - Bye weeks give 13-14 days
  - Check for negative values (data error)

### `rest_away`
- **Definition**: Days of rest for away team since last game
- **Units**: Days (integer)
- **Typical Range**: [3, 10]; 180+ for season opener
- **Why It Matters**: Combined with `rest_home`, models rest advantage/disadvantage
- **Leakage Notes**: ✅ No leakage (known from schedule)
- **Sanity Check**: Same as `rest_home`

---

## Performance Features

### `prev_margin_home`
- **Definition**: Home team's point margin in previous game (positive = won by X)
- **Units**: Points (can be negative for losses)
- **Typical Range**: [-30, +30] (95% of games); blowouts can exceed ±40
- **Why It Matters**: Momentum proxy; recent performance indicator
- **Leakage Notes**: ⚠️ Must use *previous* game only (not current game outcome!)
- **Sanity Check**:
  - Check for games where prev_margin is NA (season openers OK)
  - Verify extreme values (|margin| > 50) are rare

### `prev_margin_away`
- **Definition**: Away team's point margin in previous game
- **Units**: Points (can be negative for losses)
- **Typical Range**: [-30, +30]; extremes can exceed ±40
- **Why It Matters**: Momentum proxy for away team
- **Leakage Notes**: ⚠️ Must use *previous* game only
- **Sanity Check**: Same as `prev_margin_home`

---

## Strength-of-Team Features

### `elo_home`
- **Definition**: Elo rating for home team (seeded from external source, e.g., 538)
- **Units**: Elo points (dimensionless rating)
- **Typical Range**: [1300, 1700] (average ~1500); elite teams can reach 1750+
- **Why It Matters**: Quantifies team strength; updates after each game based on performance
- **Leakage Notes**: ⚠️ Must use *pre-game* Elo (not post-game updated Elo!)
- **Sanity Check**:
  - Average Elo across league should be ~1500 (by design)
  - Check for unrealistic values (<1000 or >2000)
  - Verify Elo updates monotonically within season (teams improve/decline)

### `elo_away`
- **Definition**: Elo rating for away team (pre-game)
- **Units**: Elo points
- **Typical Range**: [1300, 1700]; average ~1500
- **Why It Matters**: Away team strength for matchup modeling
- **Leakage Notes**: ⚠️ Must use *pre-game* Elo
- **Sanity Check**: Same as `elo_home`

### `elo_diff`
- **Definition**: Home Elo minus Away Elo (positive = home team stronger)
- **Units**: Elo points (difference)
- **Typical Range**: [-400, +400] (95% of games); extremes indicate mismatches
- **Why It Matters**: Direct measure of team strength differential; highly predictive
- **Leakage Notes**: ✅ No leakage if `elo_home` and `elo_away` are pre-game
- **Sanity Check**:
  - elo_diff should equal elo_home - elo_away exactly
  - Most games have |elo_diff| < 200 (competitive matchups)

---

## Weather Features

### `wind_mph`
- **Definition**: Wind speed at kickoff location (from weather API)
- **Units**: Miles per hour (mph)
- **Typical Range**: [0, 25] (95% of games); severe weather can exceed 30 mph
- **Why It Matters**: High winds reduce passing efficiency, affect kicking accuracy
- **Leakage Notes**: ⚠️ Use forecast or game-time weather (not post-game corrected data)
- **Sanity Check**:
  - Wind should be ≥ 0 (never negative)
  - Check for missing data (indoor stadiums should have wind ~ 0)
  - Extreme winds (>35 mph) are rare; investigate outliers

### `temp_f`
- **Definition**: Temperature at kickoff in Fahrenheit
- **Units**: Degrees Fahrenheit (°F)
- **Typical Range**: [20, 85] (95% of games); cold-weather games can drop <10°F
- **Why It Matters**: Cold weather affects ball handling, player performance, scoring
- **Leakage Notes**: ⚠️ Use forecast or game-time temp (not post-game)
- **Sanity Check**:
  - Temp should be realistic for season/location (-10°F to 100°F)
  - Indoor stadiums should have consistent ~70°F
  - Summer preseason can exceed 90°F

### `precip_mm`
- **Definition**: Precipitation at kickoff (rain/snow) in millimeters
- **Units**: Millimeters (mm)
- **Typical Range**: [0, 5] (95% of games); heavy rain/snow can exceed 10 mm
- **Why It Matters**: Precipitation reduces offensive efficiency, favors run-heavy teams
- **Leakage Notes**: ⚠️ Use forecast or game-time precip
- **Sanity Check**:
  - Precip should be ≥ 0 (never negative)
  - Most games have precip = 0 (dry conditions)
  - Indoor stadiums should always have precip = 0

---

## Structural Feature

### `home`
- **Definition**: Binary indicator (1 = home team, 0 = away team)
- **Units**: Boolean (0 or 1)
- **Typical Range**: Exactly 50% of observations are home=1 (by design, one per game)
- **Why It Matters**: Encodes home-field advantage (crowd, travel, familiarity)
- **Leakage Notes**: ✅ No leakage (structural feature)
- **Sanity Check**: Exactly one home=1 per game; check for duplicates

---

## Derived Features (Model Outputs)

### `prob_book`
- **Definition**: Market-implied win probability from `spread_close` (via isotonic regression)
- **Units**: Probability [0, 1]
- **Typical Range**: [0.10, 0.90] (95% of games); toss-ups near 0.50
- **Why It Matters**: Baseline for edge analysis; measures market's win expectation
- **Leakage Notes**: ✅ No leakage if derived from pre-game spread
- **Sanity Check**:
  - All values must be ∈ [0, 1]
  - Negative spreads (home favored) → prob_book > 0.50
  - Check calibration: prob_book vs actual outcomes should align

### `p_model_oof`
- **Definition**: Out-of-fold win probability from XGBoost model (temporal split)
- **Units**: Probability [0, 1]
- **Typical Range**: [0.10, 0.90] (95% of games)
- **Why It Matters**: Model's unbiased prediction for edge computation
- **Leakage Notes**: ✅ No leakage if generated from test set only (never trained on)
- **Sanity Check**:
  - All values must be ∈ [0, 1]
  - Should be available only for test set (not full dataset)
  - Check calibration: p_model_oof vs actual outcomes

### `edge`
- **Definition**: Model's disagreement with market: `p_model_oof - prob_book`
- **Units**: Probability difference (can be negative)
- **Typical Range**: [-0.30, +0.30] (95% of games); extremes indicate strong disagreement
- **Why It Matters**: Flags games where model sees value vs market
- **Leakage Notes**: ✅ No leakage if both `p_model_oof` and `prob_book` are clean
- **Sanity Check**:
  - Mean edge should be near 0 (model not systematically biased vs market)
  - Check |edge| > 0.50 for data errors
  - Positive edge → model more bullish on home team than market

---

## Sanity-Check Checklist (Quick Reference)

Run these checks after each data update:

1. **Cardinality**: `game_id` is unique; `home=1` appears exactly once per game
2. **Date Logic**: `week` ∈ [1, 22]; `season` matches date year
3. **Market Bounds**: `spread_close` ∈ [-30, +30]; `total_close` ∈ [30, 70]
4. **Rest Logic**: `rest_home`, `rest_away` ∈ [0, 14] (exclude season openers)
5. **Elo Consistency**: Mean `elo_home`, `elo_away` ≈ 1500; `elo_diff = elo_home - elo_away`
6. **Weather Realism**: `wind_mph` ≥ 0; `temp_f` ∈ [-10, 100]; `precip_mm` ≥ 0
7. **Probability Bounds**: `prob_book`, `p_model_oof` ∈ [0, 1]
8. **Edge Sanity**: Mean `edge` ≈ 0; |edge| < 0.50 for 99%+ of games
9. **Missing Data**: Flag features with >5% NA; investigate systematic missingness
10. **Leakage Audit**: Confirm no post-game data (scores, updated Elos, live spreads) leaked into features

---

## Feature Engineering Notes

- **Feature Interactions**: Consider `elo_diff × spread_close` to detect market inefficiencies
- **Polynomial Terms**: Quadratic `spread_close^2` may capture non-linear edges
- **Categorical Encoding**: `week` can be one-hot encoded for playoff games (weeks 19-22)
- **Lag Features**: `prev_margin_*` can be extended to 2-3 game rolling averages
- **Travel Distance**: (Future) Calculate great-circle distance for away team travel fatigue

---

## Version History

- **v0.3.0-edge-oof** (2025-10-14): Added `p_model_oof`, `edge`, corrected edge definition
- **v0.2.0** (2025-10-14): Added XGBoost baseline with all features
- **v0.1.0** (2025-10-13): Initial feature set with market, Elo, and weather
