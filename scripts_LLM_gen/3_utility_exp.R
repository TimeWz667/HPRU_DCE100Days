library(tidyverse)
library(jsonlite)

# ---------------------------------------------------------------------------
# 1. Load Option A's fitted parameters (2000 posterior draws) and write them
#    out as JSON alongside the CSV.
# ---------------------------------------------------------------------------
params <- read_csv(here::here("out", "durA_2000.csv"))

write_json(params, here::here("out", "durA_2000.json"), dataframe = "rows", digits = 8)

# ---------------------------------------------------------------------------
# 2. Utility function
# ---------------------------------------------------------------------------
# Rebuilds the linear predictor from dce_model_optionA.stan for ONE profile
# (one alternative), given a parameter draw (one row of `params`) and a
# situation. Because the fitted model has no alternative-specific constant,
# the difference of this function evaluated at two profiles reproduces the
# model's estimated utility difference exactly; the function's own level is
# only meaningful relative to another profile.
#
# Situation inputs:
#   phm       : "Basic", "RSC" (reduced social contact), or "Lockdown"
#   vaccine   : "Available" or "Not available"
#   duration  : 3, 6, or 9 (months)
#   econ      : 0, 20, or 40 (% businesses closed)
#   infection : 25, 50, or 90 (%)
#   mortality : 50, 100, or 150 (deaths/day)
#   education : 5 or 10 (children falling behind, of 25)
#   sex       : "Male" or "Female"
#   age       : integer years (bucketed into 18-34 / 35-54 / 55+)
#
# Reference levels (all dummies 0): Basic + Available, 3 months, 0% closed,
# 25% infection, 50 deaths/day, 5 falling behind, Female, 18-34.

situation_dummies <- function(phm, vaccine, duration, econ, infection, mortality, education, sex, age) {
  phmvac <- case_when(
    phm == "Basic"    & vaccine == "Available"     ~ "basic_avail",
    phm == "Basic"    & vaccine != "Available"     ~ "basic_notavail",
    phm == "RSC"      & vaccine == "Available"     ~ "rsc_avail",
    phm == "RSC"      & vaccine != "Available"     ~ "rsc_notavail",
    phm == "Lockdown" & vaccine == "Available"     ~ "lockdown_avail",
    phm == "Lockdown" & vaccine != "Available"     ~ "lockdown_notavail",
    TRUE ~ NA_character_
  )
  if (is.na(phmvac)) stop("Unrecognised phm/vaccine combination: ", phm, " / ", vaccine)

  male       <- as.integer(sex == "Male")
  age_3554   <- as.integer(age >= 35 & age <= 54)
  age_55p    <- as.integer(age >= 55)

  list(
    phmvac_basic_notavail    = as.integer(phmvac == "basic_notavail"),
    phmvac_rsc_avail         = as.integer(phmvac == "rsc_avail"),
    phmvac_rsc_notavail      = as.integer(phmvac == "rsc_notavail"),
    phmvac_lockdown_avail    = as.integer(phmvac == "lockdown_avail"),
    phmvac_lockdown_notavail = as.integer(phmvac == "lockdown_notavail"),
    male = male, age_3554 = age_3554, age_55p = age_55p,
    dur6  = as.integer(duration == 6),
    dur9  = as.integer(duration == 9),
    econ20 = as.integer(econ == 20),
    econ40 = as.integer(econ == 40),
    inc50 = as.integer(infection == 50),
    inc90 = as.integer(infection == 90),
    mor100 = as.integer(mortality == 100),
    mor150 = as.integer(mortality == 150),
    edu10 = as.integer(education == 10)
  )
}

utility <- function(theta, phm, vaccine, duration, econ, infection, mortality, education, sex, age) {
  d <- situation_dummies(phm, vaccine, duration, econ, infection, mortality, education, sex, age)

  theta$b_phmvac_basic_notavail    * d$phmvac_basic_notavail +
    theta$b_phmvac_rsc_avail         * d$phmvac_rsc_avail +
    theta$b_phmvac_rsc_notavail      * d$phmvac_rsc_notavail +
    theta$b_phmvac_lockdown_avail    * d$phmvac_lockdown_avail +
    theta$b_phmvac_lockdown_notavail * d$phmvac_lockdown_notavail +
    theta$b_phmvac_basic_notavail_male    * d$phmvac_basic_notavail    * d$male +
    theta$b_phmvac_rsc_avail_male         * d$phmvac_rsc_avail         * d$male +
    theta$b_phmvac_rsc_notavail_male      * d$phmvac_rsc_notavail      * d$male +
    theta$b_phmvac_lockdown_avail_male    * d$phmvac_lockdown_avail    * d$male +
    theta$b_phmvac_lockdown_notavail_male * d$phmvac_lockdown_notavail * d$male +
    theta$b_phmvac_basic_notavail_age3554    * d$phmvac_basic_notavail    * d$age_3554 +
    theta$b_phmvac_rsc_avail_age3554         * d$phmvac_rsc_avail         * d$age_3554 +
    theta$b_phmvac_rsc_notavail_age3554      * d$phmvac_rsc_notavail      * d$age_3554 +
    theta$b_phmvac_lockdown_avail_age3554    * d$phmvac_lockdown_avail    * d$age_3554 +
    theta$b_phmvac_lockdown_notavail_age3554 * d$phmvac_lockdown_notavail * d$age_3554 +
    theta$b_phmvac_basic_notavail_age55p    * d$phmvac_basic_notavail    * d$age_55p +
    theta$b_phmvac_rsc_avail_age55p         * d$phmvac_rsc_avail         * d$age_55p +
    theta$b_phmvac_rsc_notavail_age55p      * d$phmvac_rsc_notavail      * d$age_55p +
    theta$b_phmvac_lockdown_avail_age55p    * d$phmvac_lockdown_avail    * d$age_55p +
    theta$b_phmvac_lockdown_notavail_age55p * d$phmvac_lockdown_notavail * d$age_55p +
    theta$b_dur6  * d$dur6 +
    theta$b_dur9  * d$dur9 +
    theta$b_econ20 * d$econ20 +
    theta$b_econ40 * d$econ40 +
    theta$b_inc50 * d$inc50 +
    theta$b_inc90 * d$inc90 +
    theta$b_mor100 * d$mor100 +
    theta$b_mor150 * d$mor150 +
    theta$b_edu10 * d$edu10
}

# ---------------------------------------------------------------------------
# 3. Monte Carlo experiment
# ---------------------------------------------------------------------------
# One draw: sample a parameter set at random from the 2000 posterior draws,
# compute utility for the given situation with vaccine available vs. not
# available (all other attributes held fixed), and return both utilities
# and their difference.
mc_draw <- function(phm, duration, econ, infection, mortality, education, sex, age) {
  theta <- params[sample.int(nrow(params), 1), ]

  u_avail <- utility(theta, phm, "Available", duration, econ, infection, mortality, education, sex, age)
  u_notavail <- utility(theta, phm, "Not available", duration, econ, infection, mortality, education, sex, age)

  tibble(u_avail = u_avail, u_notavail = u_notavail, u_diff = u_avail - u_notavail)
}

# Runs n_draws independent Monte Carlo draws for one situation (age/sex plus
# the non-vaccine attributes) and summarises the vaccine-availability effect.
run_mc_experiment <- function(phm, duration, econ, infection, mortality, education,
                               sex, age, n_draws = 2000, seed = 20260910) {
  set.seed(seed)
  draws <- map_dfr(seq_len(n_draws), ~ mc_draw(phm, duration, econ, infection, mortality, education, sex, age))

  summary <- draws %>%
    summarise(
      phm = phm, duration = duration, econ = econ, infection = infection,
      mortality = mortality, education = education, sex = sex, age = age,
      n_draws = n(),
      mean_u_avail = mean(u_avail),
      mean_u_notavail = mean(u_notavail),
      mean_u_diff = mean(u_diff),
      sd_u_diff = sd(u_diff),
      p_prefers_avail = mean(u_diff > 0),  # share of draws where "available" raises utility
      ci_lo = quantile(u_diff, 0.025),
      ci_hi = quantile(u_diff, 0.975)
    )

  list(draws = draws, summary = summary)
}

# ---------------------------------------------------------------------------
# 4. Example experiment - edit the situation below, or loop run_mc_experiment
#    over a grid of situations for a fuller sweep.
# ---------------------------------------------------------------------------
example <- run_mc_experiment(
  phm = "Lockdown", duration = 6, econ = 20, infection = 50, mortality = 100,
  education = 10, sex = "Female", age = 60, n_draws = 2000
)

print(example$summary)

write_csv(example$draws, here::here("out", "utility_exp_example_draws.csv"))
write_csv(example$summary, here::here("out", "utility_exp_example_summary.csv"))
