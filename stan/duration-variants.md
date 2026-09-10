# Duration term variants

Options for the Duration term in the DCE utility function, per `claude/dce-design.md` §3. `U = PHM×Vac + [Duration term] + Inc + Mor + Econ`.

| Option | Formulation | Captures | Trade-offs |
|---|---|---|---|
| A. Independent linear covariate | `Dur`, ordinal (3/6/9 months), own coefficient | Constant per-month cost | Simplest; doesn't capture fatigue |
| B. Nonlinear duration-only term | `Dur²` (convex, fatigue) or `log(Dur)` (concave, habituation) | Whether time-cost accelerates or plateaus | Same curve regardless of measure severity |
| C. PHM×Duration interaction | `PHM×Dur` | Burden = severity × time | Still linear in Dur |
| G. Severity-weighted fatigue | `PHM×Dur²` | Fatigue that accrues while a measure is in force and accelerates over time | Needs finer Duration levels than 3/6/9 to pin down curvature |
| D. Vac×Duration discounting | `Vac / (1 + k·Dur)` or `Vac × exp(-k·Dur)` | Time-preference: a distant vaccine is worth less now | `k` can't be jointly estimated in a linear-in-parameters model |
| E. Duration×Econ interaction | `Dur×Econ` | Economic damage compounds over time | Competes with C/G/D for where Duration's effect lives |
| F. Random discount/fatigue rate | Person-specific random effect on D or G's rate | Individual heterogeneity in fatigue/discounting | Most demanding on sample size and estimation |

Recommendation in `dce-design.md`: start with A, then move to G; treat D/F as follow-on extensions; E is lower priority.

## What's implemented in `stan/`

`dce_model_optionA.stan` and `dce_model_optionB.stan` diverge from the A/B pair above per a later, explicit correction from the user overriding `dce-design.md`'s framing:

- **Option A here = categorical Duration** — dummy-coded (reference 3 months; dummies for 6, 9), not the ordinal/linear coding described in the table's row A.
- **Option B here = continuous Duration** — a single coefficient on raw months, not the `Dur²`/`log(Dur)` fatigue transform described in the table's row B.

Every other attribute (PHM×Vaccine, Econ, Infection, Mortality, Education) is dummy-coded categorical in both files, and PHM×Vaccine is a single joined 6-category factor (not the monotonic ordinal product in `dce-design.md` §2) — also per that later correction. Sex and Age group are added as respondent-level covariates, interacted with the PHM×Vaccine factor only.

## Files in `stan/`

All seven Duration variants are now implemented, sharing the same PHM×Vaccine 6-category dummy factor (+ Sex/Age-group interactions), Econ/Infection/Mortality/Education dummies, and no alternative-specific constant. Only the Duration-related terms differ:

| File | Variant | Duration term |
|---|---|---|
| `dce_model_optionA.stan` | A (categorical form used in this project) | Dummy-coded 3/6/9 months |
| `dce_model_optionB.stan` | A (linear form from the table above) | Single continuous coefficient on raw months |
| `dce_model_durB_convex.stan` | B (fatigue) | `Dur²` |
| `dce_model_durB_concave.stan` | B (habituation) | `log(1+Dur)` |
| `dce_model_durC.stan` | C | `PHM_sev × Dur` (adds a `PHM_sev` ordinal 0/1/2, kept separate from the PHM×Vaccine dummies) |
| `dce_model_durG.stan` | G | `PHM_sev × Dur²` |
| `dce_model_durD.stan` | D | `Vac_notavail × exp(-k·Dur/12)`, k fixed at 0.03/year (Dur in months; not jointly estimable in a linear-in-parameters model) |
| `dce_model_durE.stan` | E | `Econ_lvl × Dur` (adds an `Econ_lvl` ordinal 0/1/2, kept separate from the Econ dummies) |
| `dce_model_durF.stan` | F | Random per-respondent slope on G's `PHM_sev × Dur²` term (non-centred hierarchical parameterisation; needs a respondent id, `resp`, and count, `R`, in the data) |

C/D/E/F/G *add* their interaction term alongside the existing main-effect dummies rather than replacing them, per each variant's description in the table above.

None of these have been compiled (no `stanc`/`cmdstan` available in this sandbox) - treat the Stan syntax as unverified until run locally, especially F's hierarchical block, which is the most likely to need tuning (e.g. `adapt_delta`) if it doesn't sample cleanly out of the box.
