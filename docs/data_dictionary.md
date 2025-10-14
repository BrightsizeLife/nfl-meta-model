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

| Column | Type | Description | Range/Example |
|--------|------|-------------|---------------|
| game_id | character | Unique game identifier (joins to games.csv) | "2018_01_ATL_PHI" |
| home | integer | Home indicator (always 1) | 1 |
| rest_home | integer | Days since home team's previous game | 4-260 (includes offseason) |
| rest_away | integer | Days since away team's previous game | 4-260 (includes offseason) |
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

- **context.csv**: 1,942 rows (1:1 join with games.csv)
  - 16 NA in prev_margin_home (teams' first games)
  - 17 NA in prev_margin_away (teams' first games)
  - All weather fields NA (Meteostat integration pending)

### Known Issues
- **Rest days exceeds expected range**: Found [4, 260] vs expected [0, 14]
  - Cause: Between-season gaps (offseason = ~260 days)
  - Impact: Model should handle or clip to reasonable values
  - Fix: Cap rest days at 14 or add "first_game_of_season" indicator

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
