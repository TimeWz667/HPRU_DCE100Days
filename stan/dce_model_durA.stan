// DCE conditional-logit model, Duration Option A: Duration CATEGORICAL.
//
// Revises the earlier version of this model per the user's corrections:
//   - PHM and Vaccine are joined into a single combined categorical factor
//     with 3 x 2 = 6 categories (no monotonic PHM*Vac ordinal product any
//     more), dummy-coded against a reference category.
//   - Duration (3/6/9 months) is dummy-coded categorical here in Option A
//     (Option B, in dce_model_optionB.stan, instead treats it as continuous
//     - that contrast is now the entire difference between the two files).
//   - Every other attribute (Econ/Finances, Infection, Mortality,
//     Education) is categorical, dummy-coded against a reference level.
//   - Sex and Age group are added as respondent-level covariates,
//     interacted with the PHM x Vaccine factor only (they cannot enter as
//     plain additive terms: the choice is between two unlabelled
//     alternatives with no alt.cte, so any effect that is the same for
//     both alternatives cancels out of the utility difference U_A - U_B;
//     it can only show up as a modifier of an attribute effect).
//
// Reference (omitted) categories, all coded 0 when an alternative is AT
// that level:
//   PHM x Vaccine : Basic measures + Vaccine available
//   Duration      : 3 months
//   Econ          : 0% of businesses closed
//   Infection     : 25%
//   Mortality     : 50 deaths/day
//   Education     : 5 (of 25) children falling behind
//   Sex           : Female
//   Age group     : 18-34
//
// No alternative-specific constant - the idefix design was built with
// alt.cte = c(0, 0) (Scripts/1_choiceset_design_pilot.R), so utility
// differences alone drive the binary logit: P(choose A) = inv_logit(U_A - U_B).

data {
  int<lower=1> N;  // number of choice observations (respondent x set)

  // PHM x Vaccine, 6 categories, dummy-coded (1/0) against the reference
  // "Basic measures + Available" - one pair of 0/1 vectors per non-reference
  // category, for each alternative.
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

  // Duration, dummy-coded against 3 months
  vector<lower=0, upper=1>[N] dur6_a;
  vector<lower=0, upper=1>[N] dur6_b;
  vector<lower=0, upper=1>[N] dur9_a;
  vector<lower=0, upper=1>[N] dur9_b;

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

  // Respondent-level covariates (one value per observation, same for both
  // alternatives - used only as PHM x Vaccine interaction modifiers below).
  vector<lower=0, upper=1>[N] male;         // 1 = Male, 0 = Female (reference)
  vector<lower=0, upper=1>[N] age_35_54;    // 1 = respondent aged 35-54
  vector<lower=0, upper=1>[N] age_55plus;   // 1 = respondent aged 55+
                                             // (reference age group = 18-34,
                                             // i.e. male = age_35_54 = age_55plus = 0)

  array[N] int<lower=0, upper=1> y;  // 1 if alt A (alt1) chosen, 0 if alt B (alt2)
}

transformed data {
  vector[N] d_phmvac_basic_notavail   = phmvac_basic_notavail_a   - phmvac_basic_notavail_b;
  vector[N] d_phmvac_rsc_avail        = phmvac_rsc_avail_a        - phmvac_rsc_avail_b;
  vector[N] d_phmvac_rsc_notavail     = phmvac_rsc_notavail_a     - phmvac_rsc_notavail_b;
  vector[N] d_phmvac_lockdown_avail   = phmvac_lockdown_avail_a   - phmvac_lockdown_avail_b;
  vector[N] d_phmvac_lockdown_notavail = phmvac_lockdown_notavail_a - phmvac_lockdown_notavail_b;

  // PHM x Vaccine dummies interacted with Sex/Age-group, so each PHM x
  // Vaccine effect can differ by respondent covariate.
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

  vector[N] d_dur6  = dur6_a  - dur6_b;
  vector[N] d_dur9  = dur9_a  - dur9_b;

  vector[N] d_econ20 = econ20_a - econ20_b;
  vector[N] d_econ40 = econ40_a - econ40_b;

  vector[N] d_inc50 = inc50_a - inc50_b;
  vector[N] d_inc90 = inc90_a - inc90_b;

  vector[N] d_mor100 = mor100_a - mor100_b;
  vector[N] d_mor150 = mor150_a - mor150_b;

  vector[N] d_edu10 = edu10_a - edu10_b;
}

parameters {
  // PHM x Vaccine main effects (reference respondent: Female, age 18-34)
  real b_phmvac_basic_notavail;
  real b_phmvac_rsc_avail;
  real b_phmvac_rsc_notavail;
  real b_phmvac_lockdown_avail;
  real b_phmvac_lockdown_notavail;

  // PHM x Vaccine x Male interactions
  real b_phmvac_basic_notavail_male;
  real b_phmvac_rsc_avail_male;
  real b_phmvac_rsc_notavail_male;
  real b_phmvac_lockdown_avail_male;
  real b_phmvac_lockdown_notavail_male;

  // PHM x Vaccine x Age 35-54 interactions
  real b_phmvac_basic_notavail_age3554;
  real b_phmvac_rsc_avail_age3554;
  real b_phmvac_rsc_notavail_age3554;
  real b_phmvac_lockdown_avail_age3554;
  real b_phmvac_lockdown_notavail_age3554;

  // PHM x Vaccine x Age 55+ interactions
  real b_phmvac_basic_notavail_age55p;
  real b_phmvac_rsc_avail_age55p;
  real b_phmvac_rsc_notavail_age55p;
  real b_phmvac_lockdown_avail_age55p;
  real b_phmvac_lockdown_notavail_age55p;

  real b_dur6;
  real b_dur9;

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
  mu =  b_phmvac_basic_notavail    * d_phmvac_basic_notavail +
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
        b_dur6  * d_dur6 +
        b_dur9  * d_dur9 +
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

  b_dur6  ~ normal(0, 2);
  b_dur9  ~ normal(0, 2);
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
  vector[N] log_lik;  // for LOO/WAIC comparison against Option B
  for (n in 1:N) {
    log_lik[n] = bernoulli_logit_lpmf(y[n] | mu[n]);
  }
}
