// DCE conditional-logit model - Duration variant D: Vac x Duration
// discounting (time preference): a "discounted vaccine benefit" regressor
// `vac_notavail x exp(-k x Dur/12)`, where vac_notavail is 1 when the
// alternative's vaccine is NOT available soon, Dur is in months, and k is a
// FIXED annual discount rate of 0.03/year (converted to a monthly rate by
// dividing Dur by 12) - roughly a 0.75% discount by month 3, 1.5% by month
// 6, 2.2% by month 9. The longer a measure must be endured before any
// vaccine benefit theoretically arrives, the less that eventual vaccine is
// worth now - a genuine time-preference story, distinct from fatigue. k
// must be fixed a priori: mlogit/bernoulli_logit is linear-in-parameters,
// so k cannot be jointly estimated without a grid search or nonlinear MLE
// (per claude/dce-design.md section 3's note on this option). To try a
// different discount rate, edit the `k` constant in transformed data and
// refit; comparing LOO across a few fixed k values is a reasonable
// alternative to jointly estimating it.
//
// This ADDS the Vac-discounting term on top of the existing PHM x Vaccine
// 6-category dummy factor and its Sex/Age interactions (kept as the main
// vaccine-availability effect; this term captures the EXTRA duration-
// dependent erosion of that effect) - it does not replace them. Everything
// else is identical to dce_model_optionA.stan / dce_model_optionB.stan.

data {
  int<lower=1> N;  // number of choice observations (respondent x set)

  // PHM x Vaccine, 6 categories, dummy-coded (1/0) against the reference
  // "Basic measures + Available".
  vector<lower=0, upper=1>[N] phmvac_basic_notavail_a;
  vector<lower=0, upper=1>[N] phmvac_basic_notavail_b;
  vector<lower=0, upper=1>[N] phmvac_rsc_avail_a;
  vector<lower=0, upper=1>[N] phmvac_rsc_avail_b;
  vector<lower=0, upper=1>[N] phmvac_rsc_notavail_a;
  vector<lower=0, upper=1>[N] phmvac_rsc_notavail_b;
  vector<lower=0, upper=1>[N] phmvac_lockdown_avail_a;
  vector<lower=0, upper=1>[N] phmvac_lockdown_avail_b;
  vector<lower=0, upper=1>[N] phmvac_lockdown_notavail_a;
  vector<lower=0, upper=1>[N] phmvac_lockdown_notavail_b;

  // Duration, CONTINUOUS (raw months: 3/6/9)
  vector<lower=0>[N] dur_a;
  vector<lower=0>[N] dur_b;


  // Econ (share of businesses closed), dummy-coded against 0%
  vector<lower=0, upper=1>[N] econ20_a;
  vector<lower=0, upper=1>[N] econ20_b;
  vector<lower=0, upper=1>[N] econ40_a;
  vector<lower=0, upper=1>[N] econ40_b;

  // Infection, dummy-coded against 25%
  vector<lower=0, upper=1>[N] inc50_a;
  vector<lower=0, upper=1>[N] inc50_b;
  vector<lower=0, upper=1>[N] inc90_a;
  vector<lower=0, upper=1>[N] inc90_b;

  // Mortality, dummy-coded against 50 deaths/day
  vector<lower=0, upper=1>[N] mor100_a;
  vector<lower=0, upper=1>[N] mor100_b;
  vector<lower=0, upper=1>[N] mor150_a;
  vector<lower=0, upper=1>[N] mor150_b;

  // Education, dummy-coded against 5 falling behind
  vector<lower=0, upper=1>[N] edu10_a;
  vector<lower=0, upper=1>[N] edu10_b;

  // Vaccine NOT available soon (1) vs available (0), independent of the PHM
  // x Vaccine dummy factor above - used only to build the discounting
  // interaction below.
  vector<lower=0, upper=1>[N] vac_notavail_a;
  vector<lower=0, upper=1>[N] vac_notavail_b;


  // Respondent-level covariates (used only as PHM x Vaccine interaction
  // modifiers - a plain additive Sex/Age effect cancels out of the utility
  // difference between two unlabelled alternatives).
  vector<lower=0, upper=1>[N] male;         // 1 = Male, 0 = Female (reference)
  vector<lower=0, upper=1>[N] age_35_54;    // 1 = respondent aged 35-54
  vector<lower=0, upper=1>[N] age_55plus;   // 1 = respondent aged 55+
                                             // (reference age group = 18-34)

  array[N] int<lower=0, upper=1> y;  // 1 if alt A (alt1) chosen, 0 if alt B (alt2)
}

transformed data {
  vector[N] d_phmvac_basic_notavail   = phmvac_basic_notavail_a   - phmvac_basic_notavail_b;
  vector[N] d_phmvac_rsc_avail        = phmvac_rsc_avail_a        - phmvac_rsc_avail_b;
  vector[N] d_phmvac_rsc_notavail     = phmvac_rsc_notavail_a     - phmvac_rsc_notavail_b;
  vector[N] d_phmvac_lockdown_avail   = phmvac_lockdown_avail_a   - phmvac_lockdown_avail_b;
  vector[N] d_phmvac_lockdown_notavail = phmvac_lockdown_notavail_a - phmvac_lockdown_notavail_b;

  vector[N] d_phmvac_basic_notavail_male    = d_phmvac_basic_notavail    .* male;
  vector[N] d_phmvac_rsc_avail_male         = d_phmvac_rsc_avail         .* male;
  vector[N] d_phmvac_rsc_notavail_male      = d_phmvac_rsc_notavail      .* male;
  vector[N] d_phmvac_lockdown_avail_male    = d_phmvac_lockdown_avail    .* male;
  vector[N] d_phmvac_lockdown_notavail_male = d_phmvac_lockdown_notavail .* male;

  vector[N] d_phmvac_basic_notavail_age3554    = d_phmvac_basic_notavail    .* age_35_54;
  vector[N] d_phmvac_rsc_avail_age3554         = d_phmvac_rsc_avail         .* age_35_54;
  vector[N] d_phmvac_rsc_notavail_age3554      = d_phmvac_rsc_notavail      .* age_35_54;
  vector[N] d_phmvac_lockdown_avail_age3554    = d_phmvac_lockdown_avail    .* age_35_54;
  vector[N] d_phmvac_lockdown_notavail_age3554 = d_phmvac_lockdown_notavail .* age_35_54;

  vector[N] d_phmvac_basic_notavail_age55p    = d_phmvac_basic_notavail    .* age_55plus;
  vector[N] d_phmvac_rsc_avail_age55p         = d_phmvac_rsc_avail         .* age_55plus;
  vector[N] d_phmvac_rsc_notavail_age55p      = d_phmvac_rsc_notavail      .* age_55plus;
  vector[N] d_phmvac_lockdown_avail_age55p    = d_phmvac_lockdown_avail    .* age_55plus;
  vector[N] d_phmvac_lockdown_notavail_age55p = d_phmvac_lockdown_notavail .* age_55plus;

  real k = 0.03;  // FIXED discount rate per YEAR (see header) - not estimated; Dur is in months, so divide by 12
  vector[N] d_vacdisc = (vac_notavail_a .* exp(-k * dur_a / 12)) - (vac_notavail_b .* exp(-k * dur_b / 12));


  vector[N] d_econ20 = econ20_a - econ20_b;
  vector[N] d_econ40 = econ40_a - econ40_b;

  vector[N] d_inc50 = inc50_a - inc50_b;
  vector[N] d_inc90 = inc90_a - inc90_b;

  vector[N] d_mor100 = mor100_a - mor100_b;
  vector[N] d_mor150 = mor150_a - mor150_b;

  vector[N] d_edu10 = edu10_a - edu10_b;

}

parameters {
  real b_phmvac_basic_notavail;
  real b_phmvac_rsc_avail;
  real b_phmvac_rsc_notavail;
  real b_phmvac_lockdown_avail;
  real b_phmvac_lockdown_notavail;

  real b_phmvac_basic_notavail_male;
  real b_phmvac_rsc_avail_male;
  real b_phmvac_rsc_notavail_male;
  real b_phmvac_lockdown_avail_male;
  real b_phmvac_lockdown_notavail_male;

  real b_phmvac_basic_notavail_age3554;
  real b_phmvac_rsc_avail_age3554;
  real b_phmvac_rsc_notavail_age3554;
  real b_phmvac_lockdown_avail_age3554;
  real b_phmvac_lockdown_notavail_age3554;

  real b_phmvac_basic_notavail_age55p;
  real b_phmvac_rsc_avail_age55p;
  real b_phmvac_rsc_notavail_age55p;
  real b_phmvac_lockdown_avail_age55p;
  real b_phmvac_lockdown_notavail_age55p;

  real b_vacdisc;


  real b_econ20;
  real b_econ40;

  real b_inc50;
  real b_inc90;

  real b_mor100;
  real b_mor150;

  real b_edu10;
}

transformed parameters {
  vector[N] mu;
  mu =
        b_phmvac_basic_notavail    * d_phmvac_basic_notavail +
        b_phmvac_rsc_avail         * d_phmvac_rsc_avail +
        b_phmvac_rsc_notavail      * d_phmvac_rsc_notavail +
        b_phmvac_lockdown_avail    * d_phmvac_lockdown_avail +
        b_phmvac_lockdown_notavail * d_phmvac_lockdown_notavail +
        b_phmvac_basic_notavail_male    * d_phmvac_basic_notavail_male +
        b_phmvac_rsc_avail_male         * d_phmvac_rsc_avail_male +
        b_phmvac_rsc_notavail_male      * d_phmvac_rsc_notavail_male +
        b_phmvac_lockdown_avail_male    * d_phmvac_lockdown_avail_male +
        b_phmvac_lockdown_notavail_male * d_phmvac_lockdown_notavail_male +
        b_phmvac_basic_notavail_age3554    * d_phmvac_basic_notavail_age3554 +
        b_phmvac_rsc_avail_age3554         * d_phmvac_rsc_avail_age3554 +
        b_phmvac_rsc_notavail_age3554      * d_phmvac_rsc_notavail_age3554 +
        b_phmvac_lockdown_avail_age3554    * d_phmvac_lockdown_avail_age3554 +
        b_phmvac_lockdown_notavail_age3554 * d_phmvac_lockdown_notavail_age3554 +
        b_phmvac_basic_notavail_age55p    * d_phmvac_basic_notavail_age55p +
        b_phmvac_rsc_avail_age55p         * d_phmvac_rsc_avail_age55p +
        b_phmvac_rsc_notavail_age55p      * d_phmvac_rsc_notavail_age55p +
        b_phmvac_lockdown_avail_age55p    * d_phmvac_lockdown_avail_age55p +
        b_phmvac_lockdown_notavail_age55p * d_phmvac_lockdown_notavail_age55p +
        b_vacdisc * d_vacdisc +
        b_econ20 * d_econ20 +
        b_econ40 * d_econ40 +
        b_inc50 * d_inc50 +
        b_inc90 * d_inc90 +
        b_mor100 * d_mor100 +
        b_mor150 * d_mor150 +
        b_edu10 * d_edu10;
}

model {
  b_phmvac_basic_notavail    ~ normal(0, 2);
  b_phmvac_rsc_avail         ~ normal(0, 2);
  b_phmvac_rsc_notavail      ~ normal(0, 2);
  b_phmvac_lockdown_avail    ~ normal(0, 2);
  b_phmvac_lockdown_notavail ~ normal(0, 2);

  b_phmvac_basic_notavail_male    ~ normal(0, 1);
  b_phmvac_rsc_avail_male         ~ normal(0, 1);
  b_phmvac_rsc_notavail_male      ~ normal(0, 1);
  b_phmvac_lockdown_avail_male    ~ normal(0, 1);
  b_phmvac_lockdown_notavail_male ~ normal(0, 1);

  b_phmvac_basic_notavail_age3554    ~ normal(0, 1);
  b_phmvac_rsc_avail_age3554         ~ normal(0, 1);
  b_phmvac_rsc_notavail_age3554      ~ normal(0, 1);
  b_phmvac_lockdown_avail_age3554    ~ normal(0, 1);
  b_phmvac_lockdown_notavail_age3554 ~ normal(0, 1);

  b_phmvac_basic_notavail_age55p    ~ normal(0, 1);
  b_phmvac_rsc_avail_age55p         ~ normal(0, 1);
  b_phmvac_rsc_notavail_age55p      ~ normal(0, 1);
  b_phmvac_lockdown_avail_age55p    ~ normal(0, 1);
  b_phmvac_lockdown_notavail_age55p ~ normal(0, 1);

  b_vacdisc ~ normal(0, 2);

  b_econ20 ~ normal(0, 2);
  b_econ40 ~ normal(0, 2);
  b_inc50 ~ normal(0, 2);
  b_inc90 ~ normal(0, 2);
  b_mor100 ~ normal(0, 2);
  b_mor150 ~ normal(0, 2);
  b_edu10 ~ normal(0, 2);

  y ~ bernoulli_logit(mu);
}

generated quantities {
  vector[N] log_lik;  // for LOO/WAIC model comparison across Duration variants
  for (n in 1:N) {
    log_lik[n] = bernoulli_logit_lpmf(y[n] | mu[n]);
  }
}
