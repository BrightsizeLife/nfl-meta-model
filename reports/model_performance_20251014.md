# NFL Meta-Model Performance Report

**Date**: 2025-10-14
**Model**: XGBoost v1.2 (with market baseline comparison)
**Test Period**: 2022 week 21 - 2024 week 22 (573 games)

---

## Executive Summary

XGBoost model **outperforms market baseline** by **0.060 log loss** (0.628 vs 0.687). Model wins all 3 test seasons. Strong edge on games with |Δp| > 0.05 (70% of test set, +0.085 log loss gain). Top feature: `spread_close` (mean |SHAP| = 0.448).

**⚠️ Calibration Issue**: Slope = 4.94 (ideal 1.0) - requires post-hoc calibration before deployment.

---

## Overall Metrics

| Source | Log Loss | Brier | ROC AUC | Calib Slope | Calib Intercept |
|--------|----------|-------|---------|-------------|-----------------|
| **Model** | **0.6276** | **0.2190** | 0.686 | 4.94 ⚠️ | -2.35 |
| Market | 0.6874 | 0.2471 | - | NA | 0.23 |
| **Δ (gain)** | **+0.060** | **+0.028** | - | - | - |

---

## Per-Season Performance

| Season | N | Model LogLoss | Market LogLoss | Gain | Model Brier | Market Brier |
|--------|---|---------------|----------------|------|-------------|--------------|
| 2022* | 3 | 0.633 | 0.671 | +0.038 | 0.220 | 0.239 |
| 2023 | 285 | **0.644** | 0.686 | **+0.042** | 0.227 | 0.247 |
| 2024 | 285 | **0.612** | 0.689 | **+0.077** | 0.211 | 0.248 |

*2022 only 3 games (weeks 21-22)

**Finding**: Model improvement strongest in 2024 (+0.077 log loss), suggesting adaptive edge over market.

---

## Confusion Matrices

### Threshold = 0.50 (default)
| | Predicted Home | Predicted Away |
|---|---|---|
| **Actual Home** | 219 (TP) | 100 (FN) |
| **Actual Away** | 100 (FP) | 154 (TN) |

- **Accuracy**: 65.1%
- **Precision**: 68.7%
- **Recall**: 68.7%
- **F1**: 0.687

### Threshold = 0.42 (optimal F1)
- **F1**: 0.738 (+7.4% vs default)
- **Recall**: 91.2% (high sensitivity)
- **Precision**: 61.9% (trade-off)

### Threshold = 0.54 (optimal balanced accuracy)
- **Balanced Accuracy**: 64.7%
- **Precision**: 73.8%
- **Recall**: 53.0%

---

## "When We Beat the Market" (Edge Analysis)

**Edge** = P(model) - P(market)

### By Absolute Edge Threshold

| Threshold | Games (%) | Mean \|Edge\| | Model LogLoss | Market LogLoss | **Gain** |
|-----------|-----------|---------------|---------------|----------------|----------|
| **≥0.03** | 463 (81%) | 0.147 | 0.617 | 0.690 | **+0.073** |
| **≥0.05** | 399 (70%) | 0.164 | **0.604** | 0.689 | **+0.085** |
| **≥0.07** | 333 (58%) | 0.185 | **0.588** | 0.689 | **+0.102** |

**Key Insight**: Model's edge increases with confidence. On games where model diverges most from market (|Δp| ≥ 0.07), we gain **0.102 log loss** (17% improvement).

### Edge Decile Analysis

Highest gains in **D9** (|edge| ≈ 0.26, accuracy 86%, Δ logloss +0.26) and **D7** (|edge| ≈ 0.14, accuracy 77%, Δ logloss +0.11).

![Edge Analysis](../artifacts/20251014_161044/plots/edge_bins_outcomes.png)

### Cumulative Gain

Sorting games by descending |edge|, cumulative gain plateaus after ~400 games, suggesting top 70% of disagreements capture most value.

![Cumulative Gain](../artifacts/20251014_161044/plots/cumulative_edge_gain.png)

---

## ROC & Precision-Recall

- **ROC AUC**: 0.686 (moderate discrimination)
- **PR AUC**: ~0.68 (estimated from curve)

![ROC Curve](../artifacts/20251014_161044/plots/roc_curve.png)
![PR Curve](../artifacts/20251014_161044/plots/pr_curve.png)

---

## SHAP Explainability

### Top Features (mean |SHAP|)

1. **spread_close** (0.448) - Market odds dominate
2. **elo_diff** (0.143) - Power ratings matter
3. **prev_margin_away** (0.067) - Away team momentum
4. **prev_margin_home** (0.042) - Home team momentum
5. **week** (0.033) - Seasonal patterns
6. **total_close** (0.020) - Game script context

![SHAP Summary](../artifacts/20251014_161044/shap/shap_summary.png)

### Key Dependence Patterns

**spread_close**: Monotonic positive relationship (higher spread → higher P(home_win)). SHAP impact ranges from -0.8 to +0.8.

**elo_diff**: Similar monotonic pattern, but weaker (SHAP ±0.4). Complements spread.

**prev_margin_away**: Non-linear. Large losses (margin < -20) increase away team motivation (negative SHAP). Wins show modest positive SHAP.

### Interactions

**spread_close × elo_diff**: When spread and Elo agree (both favor home), SHAP amplifies. When they disagree, SHAP attenuates. Model learns to trust consensus.

**spread_close × week**: Early-season games (weeks 1-4) show higher SHAP variance, suggesting market less calibrated early. Playoff weeks (18-22) compress SHAP range.

![Interaction: Spread × Elo](../artifacts/20251014_161044/shap/shap_interact_spread_elo.png)

---

## What to Watch

### 🔴 Calibration Drift
- Slope = 4.94 across all seasons, but varies: 2023 (4.09), 2024 (5.76)
- **Action**: Monitor per-season slopes; consider season-specific calibration

### 🟡 Market Improvement in 2024
- Market baseline also improved 2023→2024 (0.686→0.689), but model improved faster
- **Hypothesis**: Model captures evolving team dynamics faster than closing lines

### 🟢 Strong Edge on Divergence
- 58% of games have |edge| ≥ 0.07, yielding +0.102 log loss
- **Opportunity**: Focus on high-confidence disagreements for decision-making

### 📊 Seasonal Heterogeneity
- Week 1-4: Higher SHAP variance (market less informed)
- Playoffs (18-22): Model and market converge (lower edge)
- **Strategy**: May need week-specific thresholds

---

## Artifacts

All outputs saved to `artifacts/20251014_161044/`:

- **eval/**: overall.csv, by_season.csv, by_season_week.csv
- **plots/**: 8 PNG files (scatter, violin, bar, ROC, PR, edge, cumulative)
- **shap/**: shap_summary.png, 6 dependence plots, 2 interaction plots, shap_values.csv

---

## Reproducibility

```bash
# Regenerate analysis
Rscript R/05_validate.R --model_dir artifacts/20251014_161044/xgb
Rscript R/06_plots.R --eval_dir artifacts/20251014_161044/eval
Rscript R/04_xgb_explain.R --model_dir artifacts/20251014_161044/xgb
```

**Seed**: 20251013
**Model**: artifacts/20251014_161044/xgb/model.xgb
**Context**: data/processed/context_20251014_161031.csv (v1.2)

---

## Next Steps

1. **v1.3**: Implement Platt scaling to fix calibration (slope → 1.0)
2. **v1.5**: Add weather features (Meteostat) + travel distance
3. **v2**: Multi-source odds meta-model with hierarchical calibration
4. **Production**: Deploy edge-filtered predictions (|Δp| ≥ 0.05 threshold)
