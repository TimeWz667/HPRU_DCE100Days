library(tidyverse)
library(cmdstanr)
library(loo)

# ---------------------------------------------------------------------------
# 1. Inputs
# ---------------------------------------------------------------------------
# Design file (as fielded - alt-level rows, one per Block/Set/Alt)
design <- read_csv(here::here("Surveys", "full_surveys_prepilot_nocross.csv"))

# Respondent choices for one simulation run (swap for any s001..s010 run, or
# the earlier N=100/N=2000 pilot outputs)


ans <- read_csv(here::here("Results", "simulated_respondents_ans_s002.csv"))
info <- read_csv(here::here("Results", "simulated_respondents_info_s002.csv")) %>%
  transmute(
    respondent_id,
    male       = as.integer(Sex == "Male"),
    age_35_54  = as.integer(Age >= 35 & Age <= 54),
    age_55plus = as.integer(Age >= 55)
    # reference age group = 18-34 (male = age_35_54 = age_55plus = 0)
  )

# ---------------------------------------------------------------------------
# 2. Recode the design to the dummy/categorical scheme shared by every
#    stan/dce_model_*.stan file:
#      - PHM x Vaccine joined into ONE 6-category factor, dummy-coded
#        against the reference "Basic measures + Available".
#      - Duration: dummy-coded (3/6/9) for Option A; continuous (raw
#        months) for every other variant (Option B, B_convex, B_concave,
#        C, D, E, F, G).
#      - Econ/Infection/Mortality/Education: each dummy-coded against its
#        reference level.
#    Plus the extra ordinal/binary regressors some variants need ALONGSIDE
#    the dummies above (never replacing them - see stan/duration-
#    variants.md): PHM severity (0/1/2, for C/F/G), Vaccine-not-available
#    (0/1, for D), and Econ level (0/1/2, for E).
# ---------------------------------------------------------------------------
design_coded <- design %>%
  transmute(
    Block, Set, Alt,
    phmvac = case_when(
      PHSM == "Basic measures" & VACCINE == "Available"          ~ "basic_avail",   # reference
      PHSM == "Basic measures" & VACCINE != "Available"          ~ "basic_notavail",
      PHSM == "Reduced social contact" & VACCINE == "Available"  ~ "rsc_avail",
      PHSM == "Reduced social contact" & VACCINE != "Available"  ~ "rsc_notavail",
      PHSM == "Lockdown" & VACCINE == "Available"                ~ "lockdown_avail",
      PHSM == "Lockdown" & VACCINE != "Available"                ~ "lockdown_notavail"
    ),
    phm_sev = case_when(
      PHSM == "Basic measures"         ~ 0,
      PHSM == "Reduced social contact" ~ 1,
      PHSM == "Lockdown"               ~ 2
    ),
    vac_notavail = as.integer(VACCINE != "Available"),
    dur  = DURATION_C,       # raw months (3/6/9) - dummy-coded for A, continuous elsewhere
    econ_lvl = FINANACES_C,
    econ = case_when(FINANACES_C == 0 ~ "econ0", FINANACES_C == 1 ~ "econ20", FINANACES_C == 2 ~ "econ40"),
    inc  = case_when(INFECTION_C == 25 ~ "inc25", INFECTION_C == 50 ~ "inc50", INFECTION_C == 90 ~ "inc90"),
    mor  = case_when(DEATH_C == 50 ~ "mor50", DEATH_C == 100 ~ "mor100", DEATH_C == 150 ~ "mor150"),
    edu  = case_when(EDUCATION_C == 5 ~ "edu5", EDUCATION_C == 10 ~ "edu10")
  ) %>%
  mutate(
    phmvac_basic_notavail   = as.integer(phmvac == "basic_notavail"),
    phmvac_rsc_avail        = as.integer(phmvac == "rsc_avail"),
    phmvac_rsc_notavail     = as.integer(phmvac == "rsc_notavail"),
    phmvac_lockdown_avail   = as.integer(phmvac == "lockdown_avail"),
    phmvac_lockdown_notavail = as.integer(phmvac == "lockdown_notavail"),
    dur6  = as.integer(dur == 6),
    dur9  = as.integer(dur == 9),
    econ20 = as.integer(econ == "econ20"),
    econ40 = as.integer(econ == "econ40"),
    inc50 = as.integer(inc == "inc50"),
    inc90 = as.integer(inc == "inc90"),
    mor100 = as.integer(mor == "mor100"),
    mor150 = as.integer(mor == "mor150"),
    edu10 = as.integer(edu == "edu10")
  ) %>%
  select(Block, Set, Alt, dur, phm_sev, vac_notavail, econ_lvl,
         phmvac_basic_notavail, phmvac_rsc_avail, phmvac_rsc_notavail,
         phmvac_lockdown_avail, phmvac_lockdown_notavail,
         dur6, dur9, econ20, econ40, inc50, inc90, mor100, mor150, edu10)

wide_cols <- c("phmvac_basic_notavail", "phmvac_rsc_avail", "phmvac_rsc_notavail",
               "phmvac_lockdown_avail", "phmvac_lockdown_notavail",
               "dur6", "dur9", "econ20", "econ40", "inc50", "inc90",
               "mor100", "mor150", "edu10", "phm_sev", "vac_notavail", "econ_lvl")

# Wide: one row per Block/Set, columns suffixed _a (alt1) / _b (alt2)
design_wide <- design_coded %>%
  pivot_wider(
    id_cols = c(Block, Set),
    names_from = Alt,
    values_from = c(dur, all_of(wide_cols)),
    names_glue = "{.value}_{if_else(Alt == 'alt1', 'a', 'b')}"
  )

# ---------------------------------------------------------------------------
# 3. Join to respondent choices
# ---------------------------------------------------------------------------
dat <- ans %>%
  rename(Block = block, Set = set) %>%
  left_join(design_wide, by = c("Block", "Set")) %>%
  left_join(info, by = "respondent_id") %>%
  mutate(
    y = if_else(choice == "alt1", 1L, 0L),
    resp = as.integer(factor(respondent_id))  # dense 1..R index for Stan, in case
    # respondent_id itself isn't contiguous
  ) %>% 
  drop_na()

stopifnot(nrow(dat) == nrow(ans))  # every choice should have matched a design row

# ---------------------------------------------------------------------------
# 4. Stan data lists - one per Duration variant in stan/. All share
#    `shared_data` (PHM x Vaccine dummies + Sex/Age interactions, Econ/
#    Infection/Mortality/Education dummies); each variant adds only its own
#    Duration-related fields, per stan/duration-variants.md.
# ---------------------------------------------------------------------------
shared_data <- list(
  N = nrow(dat),
  phmvac_basic_notavail_a = dat$phmvac_basic_notavail_a, phmvac_basic_notavail_b = dat$phmvac_basic_notavail_b,
  phmvac_rsc_avail_a = dat$phmvac_rsc_avail_a,             phmvac_rsc_avail_b = dat$phmvac_rsc_avail_b,
  phmvac_rsc_notavail_a = dat$phmvac_rsc_notavail_a,       phmvac_rsc_notavail_b = dat$phmvac_rsc_notavail_b,
  phmvac_lockdown_avail_a = dat$phmvac_lockdown_avail_a,   phmvac_lockdown_avail_b = dat$phmvac_lockdown_avail_b,
  phmvac_lockdown_notavail_a = dat$phmvac_lockdown_notavail_a, phmvac_lockdown_notavail_b = dat$phmvac_lockdown_notavail_b,
  econ20_a = dat$econ20_a, econ20_b = dat$econ20_b,
  econ40_a = dat$econ40_a, econ40_b = dat$econ40_b,
  inc50_a = dat$inc50_a, inc50_b = dat$inc50_b,
  inc90_a = dat$inc90_a, inc90_b = dat$inc90_b,
  mor100_a = dat$mor100_a, mor100_b = dat$mor100_b,
  mor150_a = dat$mor150_a, mor150_b = dat$mor150_b,
  edu10_a = dat$edu10_a, edu10_b = dat$edu10_b,
  male = dat$male, age_35_54 = dat$age_35_54, age_55plus = dat$age_55plus,
  y = dat$y
)

stan_data_a <- c(shared_data, list(
  dur6_a = dat$dur6_a, dur6_b = dat$dur6_b,
  dur9_a = dat$dur9_a, dur9_b = dat$dur9_b
))


stan_data_b <- c(shared_data, list(
  dur_a = dat$dur_a, dur_b = dat$dur_b
))

stan_data_b_convex <- c(shared_data, list(
  dur_a = dat$dur_a, dur_b = dat$dur_b
))

stan_data_b_concave <- c(shared_data, list(
  dur_a = dat$dur_a, dur_b = dat$dur_b
))

stan_data_c <- c(shared_data, list(
  dur_a = dat$dur_a, dur_b = dat$dur_b,
  phm_sev_a = dat$phm_sev_a, phm_sev_b = dat$phm_sev_b
))

stan_data_g <- c(shared_data, list(
  dur_a = dat$dur_a, dur_b = dat$dur_b,
  phm_sev_a = dat$phm_sev_a, phm_sev_b = dat$phm_sev_b
))

stan_data_d <- c(shared_data, list(
  dur_a = dat$dur_a, dur_b = dat$dur_b,
  vac_notavail_a = dat$vac_notavail_a, vac_notavail_b = dat$vac_notavail_b
))

stan_data_e <- c(shared_data, list(
  dur_a = dat$dur_a, dur_b = dat$dur_b,
  econ_lvl_a = dat$econ_lvl_a, econ_lvl_b = dat$econ_lvl_b
))

stan_data_f <- c(shared_data, list(
  dur_a = dat$dur_a, dur_b = dat$dur_b,
  phm_sev_a = dat$phm_sev_a, phm_sev_b = dat$phm_sev_b,
  R = max(dat$resp), resp = dat$resp
))

# ---------------------------------------------------------------------------
# 5. Compile and fit every Duration variant
# ---------------------------------------------------------------------------
stan_dir <- here::here("stan")

models <- list(
  a         = list(file = "dce_model_durA.stan",     data = stan_data_a),
  b         = list(file = "dce_model_durB.stan",     data = stan_data_b),
  b_convex  = list(file = "dce_model_durB_convex.stan", data = stan_data_b_convex),
  b_concave = list(file = "dce_model_durB_concave.stan",data = stan_data_b_concave),
  c         = list(file = "dce_model_durC.stan",        data = stan_data_c),
  d         = list(file = "dce_model_durD.stan",        data = stan_data_d),
  e         = list(file = "dce_model_durE.stan",        data = stan_data_e),
  f         = list(file = "dce_model_durF.stan",        data = stan_data_f),
  g         = list(file = "dce_model_durG.stan",        data = stan_data_g)
)

fits <- imap(models, function(m, name) {
  mod <- cmdstan_model(file.path(stan_dir, m$file))
  mod$sample(
    data = m$data, chains = 4, parallel_chains = 4,
    iter_warmup = 1000, iter_sampling = 1000, seed = 20260909,
    # variant F's hierarchical random slope is the one most likely to need
    # a higher adapt_delta to avoid divergences
    adapt_delta = if (name == "f") 0.95 else 0.8
  )
})

save(fits, file = here::here("out", "fits.rdata"))


phmvac_covariate_pars <- c(
  outer(c("b_phmvac_basic_notavail", "b_phmvac_rsc_avail", "b_phmvac_rsc_notavail",
          "b_phmvac_lockdown_avail", "b_phmvac_lockdown_notavail"),
        c("", "_male", "_age3554", "_age55p"), paste0)
) %>% as.vector()

shared_pars <- c("b_econ20", "b_econ40", "b_inc50", "b_inc90", "b_mor100", "b_mor150", "b_edu10")

duration_pars <- list(
  a         = c("b_dur6", "b_dur9"),
  b         = "b_dur",
  b_convex  = "b_dur2",
  b_concave = "b_logdur",
  c         = "b_phmsev_dur",
  d         = "b_vacdisc",
  e         = "b_econ_dur",
  f         = c("b_phmsev_dur2", "sigma_u"),
  g         = "b_phmsev_dur2"
)

walk2(fits, names(fits), function(fit, name) {
  cat("\n===", name, "===\n")
  print(fit$summary(variables = c(phmvac_covariate_pars, duration_pars[[name]], shared_pars)))
})

# ---------------------------------------------------------------------------
# 6. Compare all Duration variants via LOO - the substantive question this
#    whole family of models is built to answer (claude/dce-design.md
#    section 3 / stan/duration-variants.md).
# ---------------------------------------------------------------------------
loos <- map(fits, ~ .x$loo(variables = "log_lik"))
loo_compare(loos)


walk2(fits, names(fits), function(fit, name) {
  cat("\n===", name, "===\n")
  fit$summary(variables = c(phmvac_covariate_pars, duration_pars[[name]], shared_pars))
  fit$draws(variables = c(phmvac_covariate_pars, duration_pars[[name]], shared_pars), format = "draws_matrix") %>% 
    as_tibble() %>% 
    sample_n(2000) %>% 
    write_csv(here::here("out", "Dur_" + glue::as_glue(name) + "_2000.csv"))
})
