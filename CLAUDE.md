# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

HPRU discrete choice experiment (DCE) for the "100 Days Mission" (public-health response to outbreaks). It is an R / Stan project, not a package: there is no build, lint, or test suite. Scripts are run interactively (RStudio project `HPRU_DCE100Days.Rproj`) or via `Rscript`, and resolve paths with `here::here()` from the project root. Study stage is tracked in `README.md` (think-aloud rounds done; pilot of 100 cases next).

## Pipeline

1. **Attribute definitions** — `def/attributes*.json` (`attributes.json` original; `_chd` and `_old` are the child/older-adult pilot variants). Each attribute has `name`, `name_short`, and `levels` (`value`, `text`). Icons for levels live in `Icons/Attr_<Attr>_<level>.png`.
2. **Choice-set design** (`Scripts/`, numbered by stage) — uses `idefix` (Bayesian efficient designs, `Profiles()`, dummy vs. continuous coding) driven by the JSON attribute files:
   - `1_1_choiceset_design_pilot.R`, `2_1_choiceset_design_chd_pilot.R`, `2_2_choiceset_design_old_pilot.R` write blocks (`.rdata`) and survey CSVs to `Surveys/` (including `*_nocross` variants without attribute cross-restrictions).
   - `1_2_choiceset_analysis_pilot.R`, `1_3_fit_dce_stan_models (pseudo data).R`, `0_dev.R` — analysis / scratch.
3. **Simulated respondents** (`scripts_LLM_gen/`, run in numeric order): synthetic population from ONS data in `Data/external/` → `Data/Sims/syn_pop_2000*.csv` and `ideology.json`; LLM-roleplayed answers land in `Results/simulated_respondents_{ans,info}_sNNN.csv` (10 replications); then Stan model fitting, utility/scenario plots, direction checks, and parameter extraction. See `scripts_LLM_gen/README.md` for the rationale (demography is sampled statistically, never LLM-generated; respondents answer independently, in character, with no utility function given; everything seeded).
4. **Stan models** — `stan/dce_model_dur*.stan` are variants of the Duration-attribute specification (A, B, B concave/convex, …). Compiled `.exe` files are present locally; posterior draws go to `out/Dur_*_2000.csv`, figures to `out/figures/`.
5. **Handoff to simulation** — `Outputs4Sims/` is a self-contained package (parameter files for three scenarios plus `build_guide.md`). It has its own `CLAUDE.md`; follow that when working in that folder. Scenario_1/2/3 correspond to model variants Dur_a/Dur_d/Dur_f.

## Conventions

- Scripts are numbered `<stage>_<step>_name.R`; keep that scheme for new scripts.
- Designs and results are seeded and versioned (`sNNN` suffix for replications); regenerate rather than hand-edit `Surveys/`, `Results/`, `out/`.
- Tidyverse style with the `%>%` pipe; `jsonlite::read_json` for attribute definitions.
