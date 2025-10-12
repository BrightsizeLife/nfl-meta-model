# Project North Star
- **Outcome:** A reproducible NFL meta-model that learns when market (and other model) probabilities are miscalibrated conditional on context, and produces weekly calibrated win probabilities + monitoring.
- **Guardrails:** Privacy-safe (public data only), cost cap (free sources first), fast iteration until "first useful," then slow down to small, reviewable batches. Tools: **R** (primary), bash. No paid APIs in v1.

---

## Quick Start (for CC)
1) **Create repo scaffolding** (see layout). Use LF line endings.
2) Add R project metadata, `renv` lock, and `DESCRIPTION` with packages.
3) Implement minimal ingest: `nflreadr::load_schedules()` for results + closing spread/total; save timestamped CSV to `data/raw/`.
4) Implement features: week/home/rest/prev_margin/elo_diff/weather(wind, temp, precip) → `data/processed/`.
5) Fit **XGBoost** baseline (`R/xgb_fit.R`) with rolling weekly CV; save artifacts under `artifacts/<timestamp>/`.
6) Produce `reports/model_compare_<timestamp>.md` (log loss, Brier, calibration).
7) Wire a Tuesday retrain script + monitoring checklist.

---

## Repo Layout & Naming
```
/ (repo root)
  ├─ R/
  │   ├─ 01_ingest.R           # schedules/results + spread/total
  │   ├─ 02_features.R         # rest, prev margins, elo diff, weather
  │   ├─ 03_eda.R              # structure checks, histograms, slices
  │   ├─ 04_xgb_fit.R          # model train + CV (rolling by week)
  │   ├─ 05_validate.R         # test metrics + calibration curves
  │   ├─ 06_score.R            # score upcoming games (if any)
  │   └─ 07_monitor.R          # drift + calibration monitoring
  ├─ R/utils/
  │   ├─ io.R                  # timestamped write/read helpers
  │   ├─ odds.R                # (placeholder for ML odds later)
  │   ├─ features.R            # feature builders
  │   └─ eval.R                # metrics, reliability bins
  ├─ data/
  │   ├─ raw/                  # append-only CSV/Parquet (YYYYmmdd_HHMMSS)
  │   └─ processed/            # derived features (timestamped)
  ├─ artifacts/                # models, CV folds, plots (timestamped)
  ├─ reports/                  # EDA/model markdown
  ├─ renv.lock                 # R dependency lockfile
  ├─ DESCRIPTION               # R package metadata
  ├─ README.md                 # short overview + how to run
  └─ .Rprofile                 # renv::activate(), options
```
**Artifact timestamp format:** `YYYYmmdd_HHMMSS` (UTC). **Never overwrite**; write new snapshots.

---

## Data Contracts (tidy & explicit)
**games.csv** (one row per game)
- Keys: `game_id` (string; stable), `season` (int), `week` (int)
- Entities: `date`, `kickoff_et` (datetime), `home_team`, `away_team`, `home_score`, `away_score`
- Outcomes: `home_win` (0/1)
- Market (v1): `spread_close` (home favored +/−), `total_close`

**context.csv** (one row per game)
- `game_id`
- Structure: `home`, `rest_home`, `rest_away`, `prev_margin_home`, `prev_margin_away`,
  `elo_home`, `elo_away`, `elo_diff`, `wind_mph`, `temp_f`, `precip_mm`

**predictions.csv** (future v2+; one row per game per source)
- `game_id`, `source`, `market`, `collected_at`, `prob_home`, `prob_away`, `de_vig_method`

**Rules**
- `data/raw/` is append-only. Include `schema_hash` and `row_count` in a sidecar JSON per file.
- `data/processed/` is derived; record source paths in a sidecar JSON (`provenance`).
- On drift (schema/levels): snapshot example rows to `artifacts/<ts>/schema_drift/`.

---

## Stage Gates & "Done" Criteria
**Ingest**
- _Done when_: Schedules + results + spread/total loaded for chosen seasons; `games.csv` has ≥ 5 seasons; schema hash saved.
- Tests: header hash matches, row-type histogram stable, NA audit; duplicates by `game_id` == 0.

**Clean/Features**
- _Done when_: `context.csv` built and fully joinable to `games.csv` (1:1); date parsing success > 99.5%.
- Tests: week in [1, 22]; rest days ∈ [0,14]; winds ≥ 0; elo_diff finite; join cardinality check.

**EDA**
- _Done when_: Histograms + pairplots saved; leakage checks (no post-game info in features).

**Model (XGBoost v1)**
- _Done when_: Rolling weekly CV completed; artifacts (params, feature importances, SHAP) saved; calibration curve plotted.
- Tests: log loss & Brier computed overall + by context slices; no feature with >20% missing post-imputation.

**Validate**
- _Done when_: Held-out week(s) metrics reported; calibration slope ∈ [0.8, 1.2] or flagged.

**Monitor**
- _Done when_: Weekly script computes Brier/logloss deltas, PSI on key features; alert file emitted on threshold breaches.

---

## Agentic Work Cycle (must follow)
**Plan → Execute → Summarize → Pause**.
- Batch cap: _early phase_ ≤ 300 LOC; _post-first-signal_ ≤ 150 LOC.
- Always show diffs, elapsed time, warnings, and I/O counts.
- Prefer dry-runs where applicable; print the exact output paths written.

---

## Modeling (v1 focus: XGBoost)
- Target: `home_win` (0/1).
- Predictors (v1): `home`, `spread_close`, `total_close`, `week`, `rest_*`, `prev_margin_*`, `elo_diff`, `wind_mph`, `temp_f`, `precip_mm`.
- CV: rolling by week within season; optionally expanding window across seasons.
- Tuning: randomized search over `max_depth`, `eta`, `min_child_weight`, `subsample`, `colsample_bytree`, `lambda`.
- Diagnostics: SHAP summary, partial dependence for top 5 features, reliability curve (10 bins), calibration slope/intercept.
- Save: model object, params, CV results, SHAP CSV, plots → `artifacts/<ts>/xgb/`.
- (Roadmap) Add **BART** for uncertainty/posteriors comparison once baseline is useful.

---

## Logging (each script)
- Input → output paths; rows in/out; distinct keys; NA summary; elapsed seconds; warnings; seed.
- For modeling: CV folds summary; best params; feature importance top 10; metrics table.

---

## Risk Policy
- **Low:** localized scripts/docs; no schema change. Reviewer: 1.
- **Medium:** I/O paths, schema, or runtime changes; requires stage tests to pass + approval.
- **High:** algorithmic shifts (loss/target), migrations, or new external data; requires design note + dry-run + explicit approval.
- **Rollback:** revert branch; restore last good `artifacts/<ts>`; re-run `05_validate.R`.

---

## Git Workflow
- Branches: `feat/*`, `fix/*`, `docs/*`, `exp/*`.
- Draft PRs early; include context block (goal, risks, metrics expected).
- Tag PRs with `gate:ingest`, `gate:features`, `gate:model`, etc.

---

## Packages (R)
- `nflreadr`, `dplyr`, `data.table`, `readr`, `stringr`, `lubridate`, `purrr`
- `xgboost`, `rsample`, `yardstick`, `ggplot2`, `pROC`
- `meteostat` (R), `sf` (optional for travel later), `jsonlite`, `arrow` (optional Parquet)
- `renv` for dependency lock

---

## CLI Examples
```bash
Rscript R/01_ingest.R --seasons 2018:2024 --out data/raw --dryrun=false
Rscript R/02_features.R --in data/raw --out data/processed --elo_seed five38
Rscript R/04_xgb_fit.R --in data/processed --cv weekly --seed 20251012
Rscript R/05_validate.R --in artifacts/20251012_120001/xgb --report reports/model_compare_20251012.md
Rscript R/07_monitor.R --in artifacts/latest/xgb --window 4
```

---

## Reusable Slash-Prompts for CC
**/ingest (v1)**
- Implement `R/01_ingest.R` that:
  - Loads schedules/results + `spread_line`, `total_line` via `nflreadr` for specified seasons.
  - Normalizes columns to the **Data Contracts** above.
  - Writes CSV to `data/raw/games_<timestamp>.csv` + sidecar JSON with `schema_hash`, `row_count`.

**/features (v1)**
- Implement `R/02_features.R` that builds `context.csv` from `games.csv`:
  - Compute week/home flags, rest days, prev-game margins, elo diff (seeded), and weather via `meteostat` at kickoff.
  - Validate joins and ranges; write timestamped outputs + provenance JSON.

**/xgb (v1)**
- Implement `R/04_xgb_fit.R`:
  - Rolling weekly CV; randomized hyperparam search; log loss + Brier; SHAP + calibration plots.
  - Save artifacts under `artifacts/<timestamp>/xgb/`.

**/validate & /monitor**
- Implement `R/05_validate.R` and `R/07_monitor.R` per **Stage Gates**.

---

## Notes on Uncertainty & Roadmap
- Add **BART** later to measure posterior uncertainty and to audit where XGB is overconfident.
- Add multiple sources (books/models) to transform to a true hierarchical meta-model with `(1|source)` encodings.
- Add moneyline ingestion (paid/free historical) and convert to calibrated probabilities per source.
