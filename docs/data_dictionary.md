# Data Dictionary

## games.csv

| Column | Type | Description | Range/Example |
|--------|------|-------------|---------------|
| game_id | character | Unique game identifier | "2018_01_ATL_PHI" |
| season | integer | NFL season year | 2018-2024 |
| week | integer | Week number within season | 1-22 (includes playoffs) |
| date | date | Game date | "2018-09-06" |
| kickoff_et | time | Kickoff time (Eastern) | "20:20:00" |
| home_team | character | Home team abbreviation | "PHI" |
| away_team | character | Away team abbreviation | "ATL" |
| home_score | integer | Final home team score | 0-60 |
| away_score | integer | Final away team score | 0-60 |
| home_win | integer | Home team won (1) or lost (0) | 0 or 1 |
| spread_close | numeric | Closing spread (home perspective, negative = favorite) | -14.0 to +14.0 |
| total_close | numeric | Closing over/under total | 35.0 to 60.0 |

## context.csv

**Note**: Season, week, spread_close, and total_close are stored in games.csv and joined during model training to avoid duplication.

| Column | Type | Description | Range/Example |
|--------|------|-------------|---------------|
| game_id | character | Unique game identifier (joins to games.csv) | "2018_01_ATL_PHI" |
| home | integer | Home indicator (always 1) | 1 |
| rest_home | integer | Days since home team's previous game (raw) | 4-260 (includes offseason) |
| rest_home_capped | integer | Rest days capped at 14 for modeling | 4-14 |
| first_game_home | integer | Home team's first game of season (1=yes, 0=no) | 0 or 1 |
| rest_away | integer | Days since away team's previous game (raw) | 4-260 (includes offseason) |
| rest_away_capped | integer | Rest days capped at 14 for modeling | 4-14 |
| first_game_away | integer | Away team's first game of season (1=yes, 0=no) | 0 or 1 |
| prev_margin_home | numeric | Home team's previous game scoring margin (+ = won by) | -40 to +40, NA for first game |
| prev_margin_away | numeric | Away team's previous game scoring margin | -40 to +40, NA for first game |
| elo_home | numeric | Home team's pre-game Elo rating | 1200-1800 |
| elo_away | numeric | Away team's pre-game Elo rating | 1200-1800 |
| elo_diff | numeric | Elo difference (home - away + HFA=65) | -500 to +500 |
| wind_mph | numeric | Wind speed at kickoff (mph) | PLACEHOLDER: all NA |
| temp_f | numeric | Temperature at kickoff (Fahrenheit) | PLACEHOLDER: all NA |
| precip_mm | numeric | Precipitation at kickoff (mm) | PLACEHOLDER: all NA |

## Notes

### Data Quality
- **games.csv**: 1,942 games across 7 seasons (2018-2024)
  - Zero duplicates by game_id
  - 100% date parsing success
  - Zero missing values

- **context.csv**: 1,942 rows (1:1 join with games.csv), now with 16 columns (v1.2)
  - 16 NA in prev_margin_home (teams' first games)
  - 17 NA in prev_margin_away (teams' first games)
  - All weather fields NA (Meteostat integration pending)
  - 96 first games of season flagged
  - Season/week/spread/total joined from games.csv to avoid duplication

### Feature Engineering (v1.1)
- **Rest days capped**: Raw rest days (4-260) capped at 14 for modeling
  - Preserves raw values for analysis
  - Provides capped values for XGBoost training
- **First game flags**: Binary indicators for season openers (96 games total)
  - Captures distinct behavior patterns for season debuts
  - Mitigates extreme rest day values from offseason

### Elo Methodology
- Initial rating: 1500 for all teams
- K-factor: 20
- Home field advantage (HFA): 65 points
- Update formula: Elo_new = Elo_old + K * (actual - expected)
- Expected win prob: 1 / (1 + 10^(-elo_diff/400))

### Data Sources
- **nflreadr** (v4.6.1): NFL schedules, scores, betting lines
- **Elo ratings**: Computed in-house (FiveThirtyEight methodology)
- **Weather**: Meteostat integration deferred to v1.5
