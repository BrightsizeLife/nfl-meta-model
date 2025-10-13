# ADR-20251012-initial-scope

**Status:** Accepted

**Date:** 2025-10-12

**Deciders:** Derek Debellis

## Context

We need to build a reproducible NFL meta-model that learns when market and model probabilities are miscalibrated conditional on context. The goal is to produce weekly calibrated win probabilities with monitoring.

Key constraints:
- Privacy-safe: Public data only
- Cost cap: Free sources first, no paid APIs in v1
- Fast iteration: Get to "first useful" quickly
- Tools: R (primary), bash
- Target: Production-ready weekly predictions by end of season

Trade-offs to consider:
1. **Model complexity vs. interpretability**: More complex models may perform better but are harder to debug and explain
2. **Data sources**: Free public data vs. paid premium sources
3. **Feature engineering**: Manual domain knowledge vs. automated feature discovery
4. **Uncertainty quantification**: Point estimates vs. full posterior distributions

## Decision

### Phase 1 (Current): XGBoost Baseline
- **Model**: XGBoost for binary classification (home_win)
- **Features** (v1):
  - Game structure: home/away, week, rest days
  - Historical: previous game margins, Elo ratings
  - Market: closing spread and total
  - Weather: wind, temperature, precipitation (placeholder for now)
- **Data sources**:
  - nflreadr for schedules, scores, betting lines
  - Elo ratings computed in-house (FiveThirtyEight methodology)
  - Meteostat for weather (future integration)
- **Validation**: Rolling weekly cross-validation within seasons
- **Metrics**: Log loss (primary), Brier score, calibration slope/intercept
- **Deployment**: Weekly retrain script, monitoring dashboard

### Phase 2 (Roadmap): Meta-Model
- Add multiple probability sources (sportsbooks, other models)
- Implement de-vig methods for odds conversion
- Build hierarchical meta-model with `(1|source)` random effects
- Learn context-dependent calibration adjustments

### Phase 3 (Roadmap): Uncertainty & Refinement
- Add BART (Bayesian Additive Regression Trees) for uncertainty quantification
- Compare XGBoost point estimates vs. BART posterior distributions
- Identify overconfident predictions
- Refine with conformal prediction intervals

## Consequences

### Positive
- **Fast iteration**: XGBoost is fast to train and well-supported in R
- **Interpretability**: SHAP values and partial dependence plots
- **No API costs**: All data sources are free in v1
- **Reproducibility**: Timestamped artifacts, version control, documented pipeline
- **Incremental value**: Can deliver useful predictions while building toward full meta-model

### Negative
- **Limited uncertainty**: XGBoost gives point estimates only (mitigated in Phase 3)
- **Manual feature engineering**: Requires domain knowledge and experimentation
- **Weather data gap**: Meteostat integration deferred, using placeholders
- **No odds aggregation**: Deferring multi-source meta-model to v2

### Neutral
- **R ecosystem**: Strong statistical libraries but fewer production deployment options than Python
- **Data quality**: nflreadr is excellent but limited to public data
- **Elo ratings**: Simple to implement but may underperform more sophisticated power rankings

## Alternatives Considered

### Alternative 1: Start with Logistic Regression
**Pros**: Simple, fast, fully interpretable
**Cons**: Limited capacity to learn complex interactions
**Rejected**: XGBoost offers better performance with manageable complexity

### Alternative 2: Deep Learning (Neural Networks)
**Pros**: Can learn complex patterns automatically
**Cons**: Harder to interpret, requires more data, prone to overfitting on small datasets
**Rejected**: NFL dataset size (~1800 games over 7 seasons) better suited to tree-based models

### Alternative 3: BART First
**Pros**: Full posterior uncertainty from the start
**Cons**: Slower to train, less familiar to most users, harder to debug
**Rejected**: Defer to Phase 3 after establishing baseline

### Alternative 4: Skip XGBoost, Build Meta-Model Directly
**Pros**: Addresses final goal immediately
**Cons**: Requires multiple data sources upfront, slower iteration, harder to debug
**Rejected**: Build incrementally to ensure each component works

## Next Steps

1. **Complete v1 implementation** (current batch):
   - ✅ Ingest results and context features
   - ✅ EDA to validate data quality
   - ⏳ Train XGBoost baseline model
   - ⏳ Validate on held-out weeks
   - ⏳ Set up monitoring

2. **Validate approach** (next 2-4 weeks):
   - Run full pipeline on 2018-2024 data
   - Assess calibration and Brier scores
   - Compare to market spread as baseline
   - Iterate on features if needed

3. **Add weather data** (v1.5):
   - Integrate Meteostat API
   - Test impact on model performance
   - Document any stadium-specific adjustments

4. **Build toward meta-model** (v2, 2-3 months):
   - Research historical odds data sources
   - Implement de-vig methods in R/utils/odds.R
   - Collect multiple probability sources per game
   - Build hierarchical model with source-specific calibration

5. **Add uncertainty quantification** (v3, 3-4 months):
   - Implement BART in parallel with XGBoost
   - Compare posterior distributions to XGBoost point estimates
   - Identify systematic overconfidence
   - Add conformal prediction intervals

## References

- FiveThirtyEight NFL Elo methodology: https://fivethirtyeight.com/methodology/how-our-nfl-predictions-work/
- nflreadr documentation: https://nflreadr.nflverse.com/
- XGBoost R package: https://xgboost.readthedocs.io/
- BART: Chipman, George, McCulloch (2010) "BART: Bayesian Additive Regression Trees"
