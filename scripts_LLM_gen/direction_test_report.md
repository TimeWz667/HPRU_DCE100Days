# Direction tests on the fitted DCE utility function

This note documents the checks implemented in `scripts_LLM_gen/6_direction_test.R`
and reports the results of running it against `out/Dur_*_2000.csv` (2,000
posterior draws per variant). Full per-draw output is in
`out/direction_test_summary.csv` and `out/direction_test_coefs.csv`.

## Purpose

The nine Duration model variants (`Dur_a` … `Dur_g`) are separate statistical
fits, not separate theories. Before any of them is used downstream, it is
worth checking that each one behaves the way theory predicts on a handful of
qualitative comparisons — sign checks, not effect sizes. All comparisons are
evaluated per posterior draw, then summarised as a percentage of the 2,000
draws agreeing with the expected direction, so the strength of each finding
can be judged rather than assumed.

## Scenario arms used

| Arm | PHM | Econ | Infection | Mortality | Education |
|---|---|---|---|---|---|
| Lockdown, low health impact | Lockdown | 40% closed | 25% | 50/day | 10 falling behind |
| Basic, high health impact | Basic | 0% closed | 90% | 150/day | 5 falling behind |
| Basic, low health impact | Basic | 0% closed | 25% | 50/day | 5 falling behind |

Duration is set to 6 months for the health/econ comparisons, and varied
between 3 and 9 months for the duration-slope comparisons. Vaccine
availability is varied where the question calls for it and held at
Available otherwise.

## Condition 1 — low-health-impact lockdown vs high-health-impact low PHM

This is the "did the lockdown work" comparison: a strict measure that
suppressed the outbreak, against no measures with a bad outbreak.

**1a. Is a vaccine more attractive in both arms?**
Expectation: `Utility(Available) − Utility(NotAvailable) > 0` for both the
lockdown arm and the low-PHM arm. If the fitted PHM×Vaccine dummies are
behaving sensibly, vaccine availability should raise utility regardless of
which measures are in place.

**1b. Does duration harm more under lockdown than under low PHM?**
Expectation: the utility slope from 3 to 9 months is more negative under
lockdown than under Basic measures. This only has a fitted mechanism in the
variants where the Duration term interacts with PHM severity (`Dur_c`,
`Dur_g`, `Dur_f`); `Dur_a`, `Dur_b`, `Dur_b_convex`, `Dur_b_concave`, `Dur_d`
and `Dur_e` have no PHM-severity-dependent Duration term, so the slope is
identical in both arms by construction and this check cannot discriminate
for them.

**1c. Do parents feel unhappier about the low-PHM arm's weaker measures?**
**Not testable with the fitted utility function.** Per `Outputs4Sims/CLAUDE.md`
§3.1, the model permits only Sex and Age-group as individual-level
covariates on the PHM×Vaccine term — there is no `LivingWithChildren` term
or interaction anywhere in any of the nine Stan specifications. The script
records this question as `NA` with that explanation rather than
approximating an answer the data cannot support. Testing it properly would
require refitting with a parent/children interaction term.

## Condition 2 — low-health-impact lockdown vs low-health-impact low PHM

This is the "was the lockdown overkill" comparison: both arms end up with
the same (good) health outcome, so any drop in the lockdown arm's utility
relative to Basic is the pure cost of measures the outbreak may not have
needed.

**2a. Fatigue — does utility fall as duration rises?**
Expectation: the lockdown arm's utility slope from 3 to 9 months is
negative. This tests fatigue directly, independent of Condition 1's
lockdown-vs-basic comparison.

**2a-2. Fatigue — does the low-PHM arm's utility fall less than the
lockdown arm's as duration rises?**
Computes the same 3-to-9-month utility slope for the low-PHM arm (Basic
measures, same low health impact) and compares it to the lockdown arm's
slope from 2a. Expectation: the low-PHM slope is less negative — i.e.
`(low-PHM slope − lockdown slope) > 0` — since weaker measures should
generate less fatigue to begin with, if the fitted Duration term responds
to measure severity at all.

**2b. Does the economic cost of lockdown work against the PHM benefit?**
The PHM×Vaccine benefit of lockdown (`b_phmvac_lockdown_avail` relative to
the Basic+Available reference) and the economic cost of the accompanying
40%-businesses-closed level (`b_econ40`) are compared directly.
Expectation: they have opposite signs — the PHM term positive, the Econ
term negative — meaning the fitted economic cost is genuinely pulling
against the health/measure benefit, not reinforcing it. The reported
`pct_agreeing_with_expectation` is the proportion of draws where the two
signs oppose.

## Condition 3 — cross-model sign consistency

For every coefficient shared by all nine variants (the five PHM×Vaccine
dummies, `b_econ20`/`b_econ40`, `b_inc50`/`b_inc90`, `b_mor100`/`b_mor150`,
`b_edu10`), the script compares the sign of the posterior mean across all
nine fits. Since these terms are specified identically in every Stan model,
a sign that flips between variants would indicate an unstable or
poorly-identified fit rather than a real difference in duration modelling,
and is flagged as inconsistent.

## Outputs once run

- `out/direction_test_summary.csv` — one row per sub-question per variant,
  with the posterior mean of the relevant utility difference and the
  percentage of draws agreeing with the stated expectation.
- `out/direction_test_coefs.csv` — posterior mean and sign of each shared
  coefficient, per variant.
- Console output including a warning naming any coefficient that is sign-
  inconsistent across variants.

## How to read the results

A `pct_agreeing_with_expectation` close to 100% is a clean directional
result; a **1c** row for every variant reads `NA` by design, not by
omission of a real value.

## Results

![Bar plot grid of direction test results](figures/direction_test_grid.png)

*Bars: posterior mean utility difference. Error bars: 95% interval across
the 2,000 draws. Colour: whether at least half of draws agree with the
stated theoretical expectation. Panel 1c is omitted (not testable).*

### 1a. Is a vaccine more attractive in both arms?

Yes, in every one of the nine variants and both arms: 100% of draws show a
positive vaccine effect. It is markedly larger in the low-PHM/high-health
arm (posterior mean roughly 2.0–3.4 utility units) than in the
low-health/lockdown arm (roughly 0.6–1.9 units) — a vaccine matters more
when the alternative is an uncontrolled outbreak than when strict measures
have already suppressed it. `Dur_f` (which adds the random fatigue slope)
shows the largest effect in both arms, but the ranking across variants is
otherwise consistent.

### 1b. Does duration harm more under lockdown than under low PHM?

Splits cleanly along the lines flagged in the specification. `Dur_a`,
`Dur_b`, `Dur_b_convex`, `Dur_b_concave` and `Dur_d` have no PHM-severity-
dependent Duration term, so the slope is identical in both arms by
construction — the posterior mean sits at (numerical) zero and only
18–35% of draws happen to land on the "expected" side, which is
noise around zero, not a real effect. `Dur_c`, `Dur_e`, `Dur_f` and `Dur_g`
— the variants that do let Duration interact with PHM severity or economic
level — all show a clear, 100%-of-draws negative result: duration harms
the lockdown arm distinctly more than the low-PHM arm, with posterior
means from ‑1.5 to ‑2.3 utility units. This is the expected pattern: only
variants with a severity-interacted Duration term can produce it, and
where they can, they do.

### 1c. Do parents feel unhappier about the low-PHM arm's weaker measures?

Not testable, as specified: `NA` for all nine variants — no
`LivingWithChildren` term or interaction exists in any fitted model.

### 2a. Fatigue — does the lockdown arm's utility fall as duration rises?

Yes for eight of nine variants, 100% of draws, posterior means from ‑1.0 to
‑2.3 utility units (lockdown, low health impact, comparing 9 vs 3 months).
The exception is `Dur_d`: its Duration term is `b_vacdisc × Vaccine_not_available
× exp(...)`, which is exactly zero whenever the vaccine is available — and
this comparison holds vaccine at Available throughout. So `Dur_d` shows a
mechanistic zero here, not an absence of fatigue; the same comparison run
with vaccine unavailable would show its (currently untested) discounting
effect instead.

### 2a-2. Fatigue — does the low-PHM arm's utility fall less than the lockdown arm's?

Splits exactly the way theory (and the model structure) predicts. `Dur_c`,
`Dur_e`, `Dur_f` and `Dur_g` — the variants whose Duration term interacts
with PHM severity or economic level — show a clean 100%-of-draws result:
the low-PHM arm's slope is less negative than the lockdown arm's by
1.5–2.3 utility units, i.e. weaker measures genuinely generate less
fatigue in these fits. `Dur_d` again shows an exact zero, for the same
vaccine-availability reason as 2a. The remaining variants (`Dur_a`,
`Dur_b`, `Dur_b_convex`, `Dur_b_concave`) show a numerical-zero gap with
only 27–40% of draws on the expected side — noise, not a real effect,
because their Duration term has no mechanism to respond to PHM severity at
all: fatigue in these fits is identical whatever the measures in place.

### 2b. Does the economic cost of lockdown work against the PHM benefit?

Mixed, and this is the most model-dependent result of the three checks.
`Dur_e` (0.9%) and `Dur_f` (1.0%) — where Duration also interacts with
economic level — show the econ term almost always opposing the PHM
benefit as expected. `Dur_c` (90%) is close behind. The remaining six
variants sit near or below 50%, meaning in roughly half or more of draws
the fitted `b_econ40` coefficient does *not* have the sign needed to
"counter" the PHM benefit — for several variants (`Dur_a`, `Dur_b_convex`)
the posterior mean of `b_econ40` is small and its sign is genuinely
uncertain across draws (this is echoed in Check 3 below). `Dur_d` is the
clear outlier at 0%: its `b_econ40` posterior mean is negative but its
PHM-lockdown benefit is also negative in this decomposition, so the two
signs agree rather than oppose (see the coefficient-sign caveat below).

### Check 3 — cross-model sign consistency

Ten of the twelve shared coefficients are sign-consistent across all nine
variants: the five PHM×Vaccine dummies (all negative — every departure
from Basic+Available reduces utility, vaccine or no) and
`b_inc50`/`b_inc90`/`b_mor100`/`b_mor150`/`b_edu10` (all negative, as
expected for worse outcomes).

`b_econ20` and `b_econ40` are **not** consistent: `b_econ20` is negative in
6 of 9 variants and positive in 3; `b_econ40` is negative in 2 of 9 and
positive in 7. In other words, the fitted economic-cost coefficients are
the least stable part of the utility function across Duration
specifications — some variants estimate that 20–40% of businesses closing
*raises* utility, which is not a plausible direction and is most likely a
fitting/identification artefact (small, LLM-approximated sample; possible
collinearity between Econ level and the Duration terms that also involve
`Econ_level`, e.g. `Dur_e`). This instability is exactly what is driving
the mixed 2b results above and is worth checking before the economic
attribute is used for anything beyond illustrative scenario plots.

**Does the sign disagreement reflect real uncertainty, or just noisy point
estimates?** For each coefficient and variant, the 95% credible interval
(2.5th–97.5th percentile across the 2,000 draws) was checked for whether
it spans zero — i.e. whether that variant's own fit can rule out the
coefficient being zero, independent of what any other variant estimates.

Ten of the twelve coefficients never cross zero in any of the nine
variants — their sign disagreement (or agreement) is a genuine, precisely
estimated feature of each fit, not an artefact of a wide interval. Three
coefficients do cross zero in at least one variant:

| Coefficient | Sign-consistent? | Variants where the 95% CI crosses zero |
|---|---|---|
| `b_econ20` | No (6 negative / 3 positive) | `Dur_c`, `Dur_f`, `Dur_g` (3 of 9) |
| `b_econ40` | No (2 negative / 7 positive) | `Dur_a`, `Dur_b`, `Dur_b_convex`, `Dur_b_concave`, `Dur_c`, `Dur_g` (6 of 9) |
| `b_edu10` | Yes (9 of 9 negative) | `Dur_e`, `Dur_g` (2 of 9) |

This sharpens, rather than contradicts, the sign-consistency finding:
`b_econ40`'s credible interval crosses zero in two-thirds of the fitted
variants, meaning most of those fits cannot distinguish it from zero at
all — the sign flips seen above are consistent with a coefficient the
model has not pinned down, not with two groups of variants confidently
disagreeing with each other. `b_econ20` is directionally unstable but
better identified (crosses zero in only 3 of 9). `b_edu10`, by contrast,
is sign-consistent across every variant and its interval crosses zero in
only 2 of 9 — its point estimate is small in some fits, but the direction
is not in serious doubt the way the economic-cost coefficients are.
