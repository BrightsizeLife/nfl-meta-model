# NFL Meta-Model

A reproducible NFL meta-model that learns when market and model probabilities are miscalibrated conditional on context, producing weekly calibrated win probabilities with monitoring.

## Overview

This project implements an XGBoost-based model to predict NFL game outcomes, focusing on:
- Calibrated win probabilities that correct market inefficiencies
- Rolling weekly cross-validation for robust evaluation
- Feature engineering from game schedules, historical data, Elo ratings, and weather
- Comprehensive monitoring for model drift and calibration

## Quick Start

### Prerequisites
- R >= 4.0.0
- renv package for dependency management

### Setup
```bash
# Clone the repository (or create it)
# cd meta-model

# Install renv and restore dependencies
R -e "install.packages('renv')"
R -e "renv::restore()"
```

### Run the Pipeline

```bash
# 1. Ingest NFL schedules and results (2018-2024)
Rscript R/01_ingest.R --seasons 2018:2024 --out data/raw --dryrun=false

# 2. Build features (rest days, Elo, weather)
Rscript R/02_features.R --in data/raw --out data/processed --elo_seed five38

# 3. Exploratory data analysis
Rscript R/03_eda.R --in data/processed

# 4. Train XGBoost model with rolling weekly CV
Rscript R/04_xgb_fit.R --in data/processed --cv weekly --seed 20251012

# 5. Validate on held-out weeks
Rscript R/05_validate.R --in artifacts/20251012_120001/xgb --report reports/model_compare_20251012.md

# 6. Score upcoming games (if any)
Rscript R/06_score.R --model artifacts/20251012_120001/xgb --in data/processed

# 7. Monitor for drift and calibration
Rscript R/07_monitor.R --in artifacts/latest/xgb --window 4
```

## Project Structure

```
meta-model/
├── R/                      # Main analysis scripts (01-07)
├── R/utils/                # Helper functions
│   ├── io.R                # Timestamped I/O
│   ├── features.R          # Feature engineering
│   ├── eval.R              # Metrics and calibration
│   └── odds.R              # Odds conversion (future)
├── data/
│   ├── raw/                # Raw NFL data (append-only)
│   └── processed/          # Derived features
├── artifacts/              # Models, plots, CV results
├── reports/                # EDA and validation reports
├── CLAUDE.md               # Detailed project specification
└── README.md               # This file
```

## Data Sources

- **nflreadr**: NFL schedules, scores, and betting lines (public, free)
- **meteostat**: Weather data for stadium locations (public, free)
- Elo ratings seeded from FiveThirtyEight methodology

## Model Features (v1)

- Game structure: home/away, week, rest days
- Historical performance: previous game margins, Elo ratings
- Market data: closing spread and total
- Weather: wind speed, temperature, precipitation

## Evaluation Metrics

- **Log Loss**: Primary metric for probability calibration
- **Brier Score**: Mean squared error of probabilities
- **Calibration**: Slope/intercept from logistic regression, reliability curves
- **AUC**: Area under ROC curve

## Roadmap

- **v1**: XGBoost baseline with public data
- **v2**: Add multiple sportsbook odds, de-vig methods
- **v3**: Hierarchical meta-model with `(1|source)` encodings
- **v4**: BART for uncertainty quantification

## Development Guidelines

See [CLAUDE.md](CLAUDE.md) for detailed specifications including:
- Data contracts and schema validation
- Stage gates and acceptance criteria
- Risk policy and rollback procedures
- Git workflow and branch conventions

## License

MIT

## Contributing

This is a personal research project. For questions or suggestions, please open an issue.
