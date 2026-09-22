# CLAUDE.md — building the outbreak-response simulation model

This folder (`Outputs4Sims/`) is the self-contained handoff package from the
`HPRU_DCE100Days` discrete choice experiment (DCE) project to the simulation
project. Everything a simulation needs — the fitted utility parameters, the
population to simulate, and the attribute definitions the utility function
is built on — is here. Nothing outside this folder should be required.

**Task for this project: build an agent-based (or population-average) Monte
Carlo simulation model that uses the fitted DCE utility function to
determine how a simulated population responds to public health measures
during an outbreak.** This document specifies the model and the data
contract; it does not implement the simulation.

---

## 1. What's in this folder

```
Outputs4Sims/
  CLAUDE.md                        <- this file
  duration-variants.md             <- full detail on the 9 Duration model variants
  Population/
    syn_pop_2000_augmented.csv     <- 2,000-person synthetic population to simulate
  Attributes/
    attributes.json                <- attribute levels/coding used in the DCE design
  Dur_a/Pars/Pars_s001.json        <- fitted parameters, Duration variant A
  Dur_b/Pars/Pars_s001.json        <- fitted parameters, Duration variant B
  Dur_b_convex/Pars/Pars_s001.json
  Dur_b_concave/Pars/Pars_s001.json
  Dur_c/Pars/Pars_s001.json
  Dur_d/Pars/Pars_s001.json
  Dur_e/Pars/Pars_s001.json
  Dur_f/Pars/Pars_s001.json
  Dur_g/Pars/Pars_s001.json
```

Each `{Model}/` folder is one fitted specification of the DCE utility
function, differing only in how the Duration term is modelled (Section 4).
Build the simulation so the model variant is a configuration choice, not a
hard-coded assumption — the simulation should be able to run against any of
the nine `{Model}` folders unchanged.

---

## 2. Population (`Population/syn_pop_2000_augmented.csv`)

2,000 synthetic individuals, one row each, columns:

| Column | Values | Notes |
|---|---|---|
| `Age` | integer, 18+ | |
| `Sex` | `Male`, `Female` | |
| `Religion` | categorical | not used by the utility function below |
| `MaritalStatus` | categorical | not used by the utility function below |
| `LivingWithChildren` | `Yes`, `No` | not used by the utility function below |
| `CovidExperience` | categorical | not used by the utility function below |

Only `Age` and `Sex` enter the fitted utility function (as the age-group and
sex covariates in Section 3). The other columns are carried over from the
population-generation step and may be used by the simulation for purposes
outside the utility function (e.g. stratified reporting), but are not part
of the utility calculation itself.

Age groups used by the utility function: **18–34** (reference), **35–54**,
**55+**.

---

## 3. The utility function

Every fitted model shares the same structure:

```
Utility = f(PHM x Vaccine) + f(Duration) + Econ + Infection + Mortality + Education
```

`f(PHM x Vaccine)`, `Econ`, `Infection`, `Mortality` and `Education` are
identical across all nine models; only `f(Duration)` differs (Section 4).
This is a **conditional logit / discrete choice utility**: given two
alternatives A and B (e.g. two different policy packages), the probability
a simulated individual chooses A is:

```
P(choose A) = 1 / (1 + exp(-(Utility_A - Utility_B)))
```

There is no alternative-specific constant — only the utility *difference*
between whatever options are being compared matters. A single option's
utility is only meaningful relative to another option (or to the reference
levels, all coded zero, which functions as an implicit baseline option).

### 3.1 PHM x Vaccine term (shared by all models)

Public health measures (PHM: Basic / Reduced social contact / Lockdown) and
vaccine availability (Available / Not available) are combined into one
6-category factor, dummy-coded against the reference **Basic measures +
Vaccine available** (coded 0). The other five categories each have their
own coefficient, further modified by the individual's sex and age group:

```
f(PHM x Vaccine) =
    b_phmvac_<category>
  + b_phmvac_<category>_male      x [Sex == Male]
  + b_phmvac_<category>_age3554   x [Age in 35-54]
  + b_phmvac_<category>_age55p    x [Age >= 55]
```

where `<category>` is one of: `basic_notavail`, `rsc_avail`, `rsc_notavail`,
`lockdown_avail`, `lockdown_notavail`. (Reference: Basic + Available scores
zero on this whole term.) Sex/age enter ONLY as modifiers of this term —
never as a stand-alone additive effect — because a plain individual-level
effect cancels out of the utility difference between two policy options
that both apply to the same person.

### 3.2 Econ, Infection, Mortality, Education terms (shared by all models)

Each is dummy-coded against a reference level:

| Attribute | Reference (coded 0) | Other levels |
|---|---|---|
| Econ (businesses closed) | 0% | `b_econ20` (20%), `b_econ40` (40%) |
| Infection (12-month family risk) | 25% | `b_inc50` (50%), `b_inc90` (90%) |
| Mortality (deaths/day) | 50 | `b_mor100` (100), `b_mor150` (150) |
| Education (children falling behind, of 25) | 5 | `b_edu10` (10) |

### 3.3 Duration term — model-specific

See Section 4 and `duration-variants.md`. This is the only part of the
utility function that differs between the nine `{Model}` folders.

---

## 4. Duration model variants

| Model folder | Duration term | Behavioural interpretation |
|---|---|---|
| `Dur_a` | Dummy-coded 3/6/9 months: `b_dur6`, `b_dur9` (ref. 3 months) | A flat, categorical duration effect |
| `Dur_b` | `b_dur x Duration` (continuous, months) | Constant cost per month |
| `Dur_b_convex` | `b_dur2 x Duration^2` | Fatigue: each extra month hurts more |
| `Dur_b_concave` | `b_logdur x log(1 + Duration)` | Habituation: each extra month hurts less |
| `Dur_c` | `b_phmsev_dur x (PHM_severity x Duration)` | Burden = measure severity x time |
| `Dur_g` | `b_phmsev_dur2 x (PHM_severity x Duration^2)` | Severity-weighted, accelerating fatigue — the recommended substantive model |
| `Dur_d` | `b_vacdisc x (Vaccine_not_available x exp(-0.03 x Duration/12))` | Time preference: a distant vaccine is worth less now (discount rate fixed at 3%/year) |
| `Dur_e` | `b_econ_dur x (Econ_level x Duration)` | Economic damage compounding over time |
| `Dur_f` | `b_phmsev_dur2 x (PHM_severity x Duration^2)`, **plus a random per-individual offset drawn from `Normal(0, sigma_u)`** | Individual heterogeneity in fatigue rate |

`PHM_severity` is an ordinal score independent of the PHM x Vaccine dummies
in Section 3.1: Basic = 0, Reduced social contact = 1, Lockdown = 2.
`Econ_level` is likewise ordinal: 0% = 0, 20% = 1, 40% = 2.
`Vaccine_not_available` is 1 when the vaccine is not available, 0 otherwise.
`Duration` is in months (3, 6 or 9 in the fielded design; the simulation may
extrapolate beyond this range at its own risk — the fitted curves were not
identified outside it).

**`Dur_f` needs an extra decision from this project:** it introduces a
random individual-level fatigue rate, `Normal(0, sigma_u)`, drawn once per
simulated individual (not once per posterior draw) using the fitted
`sigma_u` in that draw's parameter set. Decide and document whether this
draw is fixed for an individual across the whole simulation or redrawn.

---

## 5. Parameter files (`{Model}/Pars/Pars_{id}.json`)

Each `Pars_{id}.json` is a JSON array of parameter sets — one object per
posterior draw from the Bayesian model fit, e.g.:

```json
[
  {"b_phmvac_basic_notavail": -2.355, "b_phmvac_rsc_avail": -1.117, "...": "...", "b_edu10": -0.260},
  {"b_phmvac_basic_notavail": -2.403, "b_phmvac_rsc_avail": -1.253, "...": "...", "b_edu10": -0.211},
  "... 2000 objects total"
]
```

Field names match the coefficient names in Sections 3–4 exactly (and match
that model's Stan specification 1:1 — the Stan model is the authoritative
source if any name is ambiguous).

**How to use these draws:** each simulated individual should be assigned
one parameter set, drawn **at random, independently, with replacement**
from the 2,000 draws in `Pars_s001.json`. This reflects posterior parameter
uncertainty as between-individual heterogeneity in the simulation — it is a
Monte Carlo device, not a claim that real individuals literally have these
exact, discrete parameter values. Do not average the draws into a single
point estimate for use in the simulation; sampling preserves the fitted
uncertainty, a point estimate would understate it.

**The `{id}` suffix (`s001`, `s002`, ...) mirrors the survey-replication
numbering used in `Results/simulated_respondents_ans_s*.csv` upstream.**
Only `s001` exists today, corresponding to the one replication (`s002` in
the upstream survey data, refitted here as the canonical `s001` parameter
set) that has actually been fitted for every model. If further survey
replications are fitted in future, additional files (`Pars_s002.json`,
`Pars_s003.json`, ...) will appear in the same folders — the simulation
should treat the set of available `{id}` values as a discoverable list, not
assume exactly one file is present.

---

## 6. Suggested build checklist

1. Load `Population/syn_pop_2000_augmented.csv`; compute each individual's
   `male` (0/1), `age_3554` (0/1) and `age_55p` (0/1) covariates from `Sex`
   and `Age` as in Section 2.
2. Pick a `{Model}` folder (a run configuration, not a hard-coded choice)
   and load its `Pars/Pars_{id}.json`.
3. For each individual, draw one parameter set at random, with replacement,
   from the loaded array (Section 5).
4. Define the policy scenario(s) to be compared as attribute levels (PHM,
   Vaccine, Duration, Econ, Infection, Mortality, Education) — see
   `Attributes/attributes.json` for the valid levels and their fielded
   text descriptions.
5. Compute each individual's utility for each scenario using Sections 3–4,
   with that individual's own drawn parameter set and covariates.
6. Convert utility differences between scenarios into choice probabilities
   (Section 3), and simulate choices (or track expected/population-average
   behaviour) as the simulation's design requires.
7. Repeat steps 3–6 across many Monte Carlo runs if population-level
   uncertainty intervals are needed, since a single run only realises one
   random pairing of individuals to parameter draws.

---

## 7. Caveats carried over from the fitting stage

- None of the underlying Stan models have been compiled or verified in the
  environment that produced these parameter files; no `stanc`/`cmdstan`
  toolchain was available there. Treat the model specifications, and hence
  these posterior draws, as unverified until independently checked.
- The fitted data underlying every `{Model}` is from **one** simulated
  survey replication, itself generated by an LLM-based approximation (see
  the DCE project's own `scripts_LLM_gen/README.md` for the fidelity
  caveats on that step) rather than real fieldwork. These are synthetic,
  exploratory parameter estimates, not validated behavioural coefficients.
- Duration levels in the fielded design are limited to 3, 6 and 9 months;
  extrapolating any Duration term outside that range is unsupported by the
  data.
