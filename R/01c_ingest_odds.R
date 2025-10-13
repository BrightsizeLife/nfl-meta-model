#!/usr/bin/env Rscript
# ==============================================================================
# 01c_ingest_odds.R
# Purpose: Ingest moneyline odds from multiple sportsbooks (v2+ roadmap)
# ==============================================================================
# Inputs:  --in (data/raw games), --sources (comma-separated bookmakers)
# Outputs: data/raw/odds_<timestamp>.csv + sidecar JSON
#
# Data Contract (odds.csv):
#   game_id (string)
#   source (string) - bookmaker identifier
#   market (string) - "moneyline", "spread", "total"
#   collected_at (datetime)
#   home_odds (numeric) - American odds format
#   away_odds (numeric)
#   home_prob_implied (numeric) - with vig
#   away_prob_implied (numeric)
#   de_vig_method (string) - "multiplicative", "additive", "power", "shin"
#   home_prob_devig (numeric) - after removing vig
#   away_prob_devig (numeric)
#
# Sources (future integration):
#   - The Odds API (free tier: 500 requests/month)
#   - Historical data: kaggle, sportsbook review
#   - Archive: pinnacle closing lines (if available)
#
# Stage Gate Tests:
#   - Multiple sources per game_id
#   - No orphan game_ids (all join to games.csv)
#   - Implied probs sum > 1.0 (sanity check for vig)
#   - De-vigged probs sum to 1.0 ± 0.001
#
# ==============================================================================

cat("01c_ingest_odds.R - STUB ONLY\n")
cat("\nThis script is a placeholder for future odds ingestion.\n")
cat("Implementation deferred to v2+.\n\n")

cat("Planned schema:\n")
cat("  - game_id: links to games.csv\n")
cat("  - source: bookmaker (pinnacle, draftkings, fanduel, etc.)\n")
cat("  - market: moneyline, spread, total\n")
cat("  - collected_at: timestamp of odds collection\n")
cat("  - home_odds, away_odds: American odds format\n")
cat("  - home_prob_implied, away_prob_implied: with vig\n")
cat("  - de_vig_method: method used\n")
cat("  - home_prob_devig, away_prob_devig: after removing vig\n\n")

cat("Planned sources:\n")
cat("  - The Odds API (free tier)\n")
cat("  - Historical archives (Kaggle, sportsbook review)\n")
cat("  - Pinnacle closing lines (if available)\n\n")

cat("Next steps:\n")
cat("  1. Research historical odds data availability\n")
cat("  2. Implement R/utils/odds.R helpers\n")
cat("  3. Add API key management\n")
cat("  4. Implement de-vig methods\n")
cat("  5. Test with sample data\n")
