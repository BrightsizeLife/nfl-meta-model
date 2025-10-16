# Live Odds Manual Entry Guide

## Overview

For weekend scoring (v0), we manually enter live odds from sportsbooks into a CSV file. The system will compute implied probabilities and edges against our model.

## CSV Schema

**Required columns:**
- `game_id` (string): NFL game identifier (format: `YYYY_WW_AWAY_HOME`, e.g., `2024_10_KC_BUF`)
- `kickoff_et` (datetime): Kickoff time in ET timezone (format: `YYYY-MM-DD HH:MM`, e.g., `2024-11-10 16:25`)
- `book` (string): Sportsbook name (lowercase, underscore-separated)

**Odds columns** (provide at least one):
- `moneyline_home` (integer): Home team moneyline (American odds, e.g., `-150`)
- `moneyline_away` (integer): Away team moneyline (e.g., `+130`)
- `spread_home` (numeric): Home team spread (negative = favored, e.g., `-3.5`)
- `total` (numeric): Over/under total points (optional, e.g., `47.5`)

**Notes:**
- Moneyline is preferred over spread for probability calculation (more accurate)
- If both are provided, moneyline takes precedence (configurable in `config/default.yml`)
- `total` is informational only (not currently used for edge calculation)

## File Naming

Save manual odds files as: `data/live/odds_YYYYMMDD_HHMMSS.csv`

Example: `data/live/odds_20241110_143000.csv`

The scoring pipeline will automatically use the most recent odds file.

## Sportsbook Names

**Preferred books** (in order of preference, per `config/default.yml`):
1. `draftkings`
2. `fanduel`
3. `betmgm`
4. `caesars`
5. `bet365`
6. `espn_bet`

Other books can be used, but the system prioritizes these when multiple books have odds for the same game.

## Example CSV

```csv
game_id,kickoff_et,book,moneyline_home,moneyline_away,spread_home,total
2024_10_KC_BUF,2024-11-10 16:25,draftkings,-140,+120,-2.5,47.5
2024_10_KC_BUF,2024-11-10 16:25,fanduel,-135,+115,-2.5,48.0
2024_10_DET_HOU,2024-11-10 13:00,draftkings,+165,-195,+4.0,49.5
2024_10_PHI_DAL,2024-11-10 20:20,betmgm,-220,+180,-5.5,45.0
```

## Workflow

1. **Collect odds** from sportsbooks (manually or via screenshot)
2. **Create CSV** in `data/live/` following the schema above
3. **Run scoring pipeline**:
   ```bash
   Rscript R/95_weekend_run.R
   ```
4. **Review output** in `reports/weekend_picks_<timestamp>.md`

## Probability Calculation

### From Moneyline (preferred)

We use the **Additive method** for de-vigging:

```
If ML_home = -140, ML_away = +120:
  - Raw prob_home = 140 / (140 + 100) = 0.583
  - Raw prob_away = 100 / (100 + 120) = 0.455
  - Vig = 0.583 + 0.455 - 1.0 = 0.038
  - De-vigged: prob_home = 0.583 - 0.038/2 = 0.564
  - De-vigged: prob_away = 0.455 - 0.038/2 = 0.436
```

### From Spread (fallback)

We use the **isotonic regression** mapping trained on historical spread → outcome data:

```
If spread_home = -3.5:
  - Apply isotonic model: spread -> prob_home
  - Typical result: prob_home ≈ 0.63
```

## Data Quality Checks

The system will validate:
- ✅ `game_id` format matches schedule
- ✅ At least one of `moneyline_*` or `spread_home` is present
- ✅ Moneyline odds are valid American format (negative or positive integers)
- ✅ Spread is numeric
- ✅ No duplicate `game_id` + `book` combinations
- ⚠️ Warning if odds are stale (>24 hours old)

## Troubleshooting

**Error: "No odds CSV found"**
- Ensure file is in `data/live/` with name matching `odds_*.csv`

**Error: "No upcoming games found"**
- Check that `nflreadr` has schedule data for current week
- Verify today's date is before kickoff

**Warning: "Multiple books for same game"**
- System will auto-select based on `books_preference` order
- Check `reports/weekend_picks_*.md` for which book was used

**Error: "Missing moneyline and spread"**
- At least one must be provided per row
- Add either `moneyline_home`/`moneyline_away` OR `spread_home`

## Future Enhancements

- **Automated odds fetch** via APIs (requires paid subscriptions)
- **Multi-book aggregation** with best odds per side
- **Line movement tracking** over time
- **Kelly criterion** sizing recommendations
- **Historical odds archive** for backtesting
