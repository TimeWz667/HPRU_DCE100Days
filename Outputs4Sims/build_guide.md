# Build guide — outbreak-response simulation model

Standalone specification for building the simulation. Nothing outside this
`Outputs4Sims/` folder is required — every path below is relative to this
folder. This document specifies the model and the data contract; it does
not implement the simulation. For how the parameter files were produced,
the nine underlying Duration models, and why these three were selected,
see `README.md`.

**Task: build an agent-based (or population-average) Monte Carlo
simulation that uses the fitted DCE utility function to determine how a
simulated population responds to public health measures during an
outbreak, across three named scenarios.**

---

## 1. Folder contents and paths

```
./CLAUDE.md            <- pointer to this file and README.md
./build_guide.md       <- this file
./README.md            <- extraction method, underlying models, selection reasons
./duration-variants.md <- full detail on all 9 Duration model variants
./Scenario_1/Pars_s001.csv   <- parameters, one row per respondent
./Scenario_2/Pars_s001.csv
./Scenario_3/Pars_s001.csv
```

Only the three `./Scenario_{n}/Pars_s001.csv` files and the tables in
this document are needed to build and run the simulation. Use relative
paths from wherever this folder is placed:

```
./Scenario_1/Pars_s001.csv
./Scenario_2/Pars_s001.csv
./Scenario_3/Pars_s001.csv
```

Confirm the file exists at that relative path before loading it — each
`Scenario_{n}/` folder must contain a `Pars_s001.csv` file directly inside
it. If a future replication is added, it will appear alongside as
`Scenario_{n}/Pars_s002.csv` etc. — treat the set of available `s*`
files as discoverable, not fixed at one.

Each `Scenario_{n}/` is one fitted specification of the DCE utility
function, differing only in how the Duration term is modelled (Section 4).
Build the simulation so the scenario is a configuration choice (e.g. a
folder path passed in), not a hard-coded assumption.

---

## 2. Parameter file columns (`Pars_s001.csv`)

One row per simulated individual (2,000 rows), combining that individual's
demographic covariates with one parameter set already assigned to them:

| Column group | Columns |
|---|---|
| Individual info | `respondent_id`, `Age`, `Sex`, `Religion`, `MaritalStatus`, `LivingWithChildren`, `CovidExperience`, `assigned_block`, `ideology_id`, `ideology_name`, `sampling_seed` |
| Draw provenance | `draw_id` |
| Parameters | coefficient columns, e.g. `b_phmvac_basic_notavail` ... `b_dur6`, `b_dur9` (`Scenario_1`); ... `b_vacdisc` (`Scenario_2`); ... `b_phmsev_dur2`, `sigma_u` (`Scenario_3`) |

Only `Age` and `Sex` from the individual-info columns enter the utility
function (Section 3). The rest are available for stratified reporting but
play no part in the utility calculation as fitted. `draw_id` is
provenance only (which of the original 2,000 posterior draws this row's
parameters came from) and is not itself a model input.

Compute two derived covariates from each row before using Section 3:

```
male     = 1 if Sex == "Male" else 0
age3554  = 1 if 35 <= Age <= 54 else 0
age55p   = 1 if Age >= 55 else 0
```

(Age group reference: 18–34.)

---

## 3. The utility function

Every scenario shares the same structure:

```
Utility = f(PHM x Vaccine) + f(Duration) + Econ + Infection + Mortality + Education
```

`f(PHM x Vaccine)`, `Econ`, `Infection`, `Mortality` and `Education` are
identical across all three scenarios; only `f(Duration)` differs
(Section 4). This is a **conditional logit / discrete choice utility**:
given two alternatives A and B (e.g. two different policy packages), the
probability a simulated individual chooses A is:

```
P(choose A) = 1 / (1 + exp(-(Utility_A - Utility_B)))
```

There is no alternative-specific constant — only the utility *difference*
between whatever options are being compared matters. A single option's
utility is only meaningful relative to another option (or to the reference
levels, all coded zero, which functions as an implicit baseline option).

### 3.1 PHM x Vaccine term (shared by all scenarios)

Public health measures (PHM) and vaccine availability are combined into
one 6-category factor, dummy-coded against the reference **Basic measures
+ Vaccine available** (coded 0). The other five categories each have their
own coefficient, further modified by the individual's sex and age group:

```
f(PHM x Vaccine) =
    b_phmvac_<category>
  + b_phmvac_<category>_male      x male
  + b_phmvac_<category>_age3554   x age3554
  + b_phmvac_<category>_age55p    x age55p
```

`<category>` is one of: `basic_notavail`, `rsc_avail`, `rsc_notavail`,
`lockdown_avail`, `lockdown_notavail`. Sex/age enter ONLY as modifiers of
this term — never as a stand-alone additive effect — because a plain
individual-level effect cancels out of the utility difference between two
policy options that both apply to the same person.

PHM levels: **Basic measures**, **Reduced social contact**, **Lockdown**.
Vaccine levels: **Available**, **Not available**.

### 3.2 Econ, Infection, Mortality, Education terms (shared by all scenarios)

Each is dummy-coded against a reference level:

| Attribute | Levels (reference first) | Coefficients |
|---|---|---|
| Econ — local businesses closed | 0% (ref), 20%, 40% | `b_econ20`, `b_econ40` |
| Infection — 12-month family risk | 25% (ref), 50%, 90% | `b_inc50`, `b_inc90` |
| Mortality — excess deaths/day | 50 (ref), 100, 150 | `b_mor100`, `b_mor150` |
| Education — children falling behind (of 25) | 5 (ref), 10 | `b_edu10` |

### 3.3 Duration term — scenario-specific

See Section 4. This is the only part of the utility function that differs
between the three scenarios. `Duration` levels in the fielded design are
3, 6 or 9 months; extrapolating outside that range is unsupported by the
underlying data (the fitted curves were not identified outside it).

---

## 4. Duration term — one per scenario

| Scenario | Duration term | Inputs needed |
|---|---|---|
| `Scenario_1` | `b_dur6` if Duration == 6, `b_dur9` if Duration == 9, else 0 (ref. 3 months) | `Duration` |
| `Scenario_2` | `b_vacdisc x vac_notavail x exp(-0.03 x Duration / 12)` | `Duration`, `vac_notavail` (1 if Vaccine == Not available, else 0) |
| `Scenario_3` | `b_phmsev_dur2 x phm_severity x Duration^2`, **plus a random per-individual offset drawn from `Normal(0, sigma_u)`** | `Duration`, `phm_severity` (Basic = 0, Reduced social contact = 1, Lockdown = 2) |

**`Scenario_3` needs one build decision:** the random offset uses that
individual's own `sigma_u` value (already in their row). Decide and
document whether this offset is drawn once per individual and held fixed
for the whole simulation run, or redrawn every time that individual's
utility is evaluated. Either is defensible; just be consistent and record
the choice.

---

## 5. Build checklist

1. Pick a scenario and load `./Scenario_{n}/Pars_s001.csv` — verify
   the file exists at that relative path before proceeding.
2. For each row, compute `male`, `age3554`, `age55p` from `Sex`/`Age`
   (Section 2).
3. Define the policy option(s) to be compared as attribute levels: PHM,
   Vaccine, Duration, Econ, Infection, Mortality, Education (valid levels
   are listed in Sections 3.1–3.3 above — no external file needed).
4. Compute each individual's utility for each option using Sections 3–4,
   with that row's own parameters and covariates.
5. Convert utility differences between options into choice probabilities
   (Section 3), and simulate choices (or track expected/population-average
   behaviour) as the simulation's design requires.
6. A single `Pars_s001.csv` realises one fixed pairing of individuals to
   posterior draws (see `README.md` for why). If population-level
   uncertainty intervals need to account for that pairing itself, a new
   `Pars_s00N.csv` with an independent pairing must be requested from the
   DCE project — this folder does not contain the tooling to regenerate
   one.

---

## 6. Caveats that affect how the model is used

- Duration levels in the fielded design are limited to 3, 6 and 9 months;
  extrapolating any Duration term outside that range is unsupported by
  the data.
- `b_econ20`/`b_econ40` (the economic-cost coefficients) were found to
  flip sign across the wider set of fitted Duration variants during
  testing — treat any conclusion that depends heavily on the economic
  attribute with more caution than the rest of the utility function.
- None of the underlying models have been independently verified. See
  `README.md` for the full caveats on how the parameters were produced.
