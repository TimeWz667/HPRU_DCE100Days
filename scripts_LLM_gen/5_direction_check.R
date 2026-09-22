# 6_direction_test.R
#
# Directional sanity checks on the fitted DCE utility function, run across
# all nine Duration model variants (out/Dur_*_2000.csv). These are not
# effect-size estimates - they ask, for each posterior draw, whether the
# SIGN of a comparison is what theory would predict, and report the
# proportion of the 2,000 draws agreeing.
#
# Three checks:
#   1. Low health impact + lockdown  vs  high health impact + low PHM
#      1a. Is a vaccine more attractive (higher utility) in BOTH arms?
#      1b. Does duration harm more under lockdown than under low PHM?
#      1c. Do parents dislike the low-PHM arm's weaker measures more?
#          (see note - not directly testable with the fitted model)
#   2. Low health impact + lockdown  vs  low health impact + low PHM
#      2a. Fatigue: does utility of the lockdown arm fall as duration rises?
#      2b. Does the economic cost of lockdown work against (partly cancel)
#          the health/PHM benefit?
#   3. Cross-model consistency: for every shared coefficient (PHMxVaccine,
#      Econ, Infection, Mortality, Education), is the sign of the posterior
#      mean the same across all nine Duration variants?
#
# Inputs:  out/Dur_a_2000.csv ... out/Dur_g_2000.csv (2,000 posterior draws
#          each, written by 2_fit_dce_stan_models.R)
# Outputs: out/direction_test_summary.csv        (checks 1-2, one row per test)
#          out/direction_test_coefs.csv          (check 3, one row per coefficient)
#          out/figures/direction_test_grid.png   (bar plot grid, one panel per scenario question)
#          printed summary to console
#
# This script only reads existing posterior draws - it does not refit
# anything.

library(dplyr)
library(tidyr)
library(purrr)
library(readr)
library(ggplot2)

src_dir <- "out"
out_dir <- "out"

# ---- 1. duration term per variant --------------------------------------
# Each function takes a data frame of draws (`pars`, one row per draw) and
# the scenario's PHM severity (0/1/2), vaccine-not-available flag (0/1),
# econ level (0/1/2) and duration (months), and returns a vector of
# per-draw Duration-term contributions to utility.

duration_terms <- list(
  Dur_a = function(pars, phm_sev, vac_notavail, econ_lvl, duration) {
    # Categorical, reference = 3 months
    if (duration == 6) return(pars$b_dur6)
    if (duration == 9) return(pars$b_dur9)
    rep(0, nrow(pars))
  },
  Dur_b = function(pars, phm_sev, vac_notavail, econ_lvl, duration) {
    pars$b_dur * duration
  },
  Dur_b_convex = function(pars, phm_sev, vac_notavail, econ_lvl, duration) {
    pars$b_dur2 * duration^2
  },
  Dur_b_concave = function(pars, phm_sev, vac_notavail, econ_lvl, duration) {
    pars$b_logdur * log(1 + duration)
  },
  Dur_c = function(pars, phm_sev, vac_notavail, econ_lvl, duration) {
    pars$b_phmsev_dur * phm_sev * duration
  },
  Dur_g = function(pars, phm_sev, vac_notavail, econ_lvl, duration) {
    pars$b_phmsev_dur2 * phm_sev * duration^2
  },
  Dur_d = function(pars, phm_sev, vac_notavail, econ_lvl, duration) {
    pars$b_vacdisc * vac_notavail * exp(-0.03 * duration / 12)
  },
  Dur_e = function(pars, phm_sev, vac_notavail, econ_lvl, duration) {
    pars$b_econ_dur * econ_lvl * duration
  },
  Dur_f = function(pars, phm_sev, vac_notavail, econ_lvl, duration) {
    # Population-average: omit the random per-individual offset
    # (Normal(0, sigma_u)) - see CLAUDE.md Section 4 on Dur_f.
    pars$b_phmsev_dur2 * phm_sev * duration^2
  }
)

variant_files <- c(
  Dur_a         = "Dur_a_2000.csv",
  Dur_b         = "Dur_b_2000.csv",
  Dur_b_convex  = "Dur_b_convex_2000.csv",
  Dur_b_concave = "Dur_b_concave_2000.csv",
  Dur_c         = "Dur_c_2000.csv",
  Dur_d         = "Dur_d_2000.csv",
  Dur_e         = "Dur_e_2000.csv",
  Dur_f         = "Dur_f_2000.csv",
  Dur_g         = "Dur_g_2000.csv"
)

load_draws <- function(variant) {
  path <- file.path(src_dir, variant_files[[variant]])
  if (!file.exists(path)) {
    warning(sprintf("Skipping %s: %s not found", variant, path))
    return(NULL)
  }
  read_csv(path, show_col_types = FALSE)
}

# ---- 2. shared (non-Duration) utility terms ----------------------------
# PHM x Vaccine 6-category dummy (+ sex/age interactions), Econ, Infection,
# Mortality, Education - identical across all nine variants.

phmvac_category <- function(phm, vaccine) {
  # phm: "Basic" | "RSC" | "Lockdown"; vaccine: "Available" | "NotAvailable"
  if (phm == "Basic" && vaccine == "Available") return(NA_character_) # reference
  paste0(tolower(sub("Reduced social contact|RSC", "rsc", phm)), "_",
         if (vaccine == "Available") "avail" else "notavail")
}

phmvac_term <- function(pars, phm, vaccine, male = 0, age3554 = 0, age55p = 0) {
  cat <- phmvac_category(phm, vaccine)
  if (is.na(cat)) return(rep(0, nrow(pars)))
  base <- pars[[paste0("b_phmvac_", cat)]]
  male_term <- if (male == 1) pars[[paste0("b_phmvac_", cat, "_male")]] else 0
  a35_term  <- if (age3554 == 1) pars[[paste0("b_phmvac_", cat, "_age3554")]] else 0
  a55_term  <- if (age55p == 1) pars[[paste0("b_phmvac_", cat, "_age55p")]] else 0
  base + male_term + a35_term + a55_term
}

shared_attribute_terms <- function(pars, econ, infection, mortality, education) {
  econ_term <- case_when(
    econ == 20 ~ pars$b_econ20, econ == 40 ~ pars$b_econ40, TRUE ~ 0
  )
  infection_term <- case_when(
    infection == 50 ~ pars$b_inc50, infection == 90 ~ pars$b_inc90, TRUE ~ 0
  )
  mortality_term <- case_when(
    mortality == 100 ~ pars$b_mor100, mortality == 150 ~ pars$b_mor150, TRUE ~ 0
  )
  education_term <- case_when(education == 10 ~ pars$b_edu10, TRUE ~ 0)
  econ_term + infection_term + mortality_term + education_term
}

phm_severity <- function(phm) c(Basic = 0, RSC = 1, Lockdown = 2)[[phm]]
econ_level   <- function(econ) c(`0` = 0, `20` = 1, `40` = 2)[[as.character(econ)]]

utility_draws <- function(variant, pars, phm, vaccine, duration, econ, infection,
                           mortality, education, male = 0, age3554 = 0, age55p = 0) {
  phm_sev <- phm_severity(phm)
  vac_notavail <- as.integer(vaccine == "NotAvailable")
  econ_lvl <- econ_level(econ)

  phmvac_term(pars, phm, vaccine, male, age3554, age55p) +
    duration_terms[[variant]](pars, phm_sev, vac_notavail, econ_lvl, duration) +
    shared_attribute_terms(pars, econ, infection, mortality, education)
}

# ---- 3. scenario definitions --------------------------------------------
# "Low health impact"  = Infection 25%, Mortality 50/day (best fielded levels)
# "High health impact"  = Infection 90%, Mortality 150/day (worst fielded levels)
# Lockdown arms carry the higher fielded economic/education cost that comes
# with strict measures; low-PHM arms carry the lowest.

arm_lockdown_lowhealth <- list(phm = "Lockdown", duration = 6,
                                econ = 40, infection = 25, mortality = 50, education = 10)
arm_lowphm_highhealth  <- list(phm = "Basic", duration = 6,
                                econ = 0, infection = 90, mortality = 150, education = 5)
arm_lowphm_lowhealth   <- list(phm = "Basic", duration = 6,
                                econ = 0, infection = 25, mortality = 50, education = 5)

pct_positive <- function(x) mean(x > 0)

summarise_check <- function(condition, question, variant, values, expect) {
  ci <- quantile(values, c(0.025, 0.975))
  tibble(
    condition = condition,
    question = question,
    variant = variant,
    mean = mean(values),
    ci_lo = ci[[1]],
    ci_hi = ci[[2]],
    pct_agreeing_with_expectation = if (expect == "positive") pct_positive(values) else pct_positive(-values),
    expectation = expect
  )
}

results <- list()

for (variant in names(variant_files)) {

  pars <- load_draws(variant)
  if (is.null(pars)) next

  u <- function(arm, vaccine, male = 0, age3554 = 0, age55p = 0) {
    utility_draws(variant, pars, arm$phm, vaccine, arm$duration, arm$econ,
                  arm$infection, arm$mortality, arm$education, male, age3554, age55p)
  }

  ## ---- Condition 1: low-health-impact lockdown vs high-health-impact low PHM ----

  # 1a. vaccine more attractive (Available - NotAvailable > 0) in BOTH arms?
  vac_effect_lockdown <- u(arm_lockdown_lowhealth, "Available") - u(arm_lockdown_lowhealth, "NotAvailable")
  vac_effect_lowphm   <- u(arm_lowphm_highhealth, "Available") - u(arm_lowphm_highhealth, "NotAvailable")
  results[[length(results) + 1]] <- summarise_check(
    "1. low-health lockdown vs high-health low-PHM", "1a. vaccine more attractive - lockdown arm",
    variant, vac_effect_lockdown, "positive")
  results[[length(results) + 1]] <- summarise_check(
    "1. low-health lockdown vs high-health low-PHM", "1a. vaccine more attractive - low-PHM arm",
    variant, vac_effect_lowphm, "positive")

  # 1b. does duration harm MORE under lockdown than under low PHM?
  #     (marginal effect of duration = utility at 9 months minus utility at 3 months,
  #      holding vaccine at Available so only the Duration term differs)
  dur9_lockdown <- utility_draws(variant, pars, "Lockdown", "Available", 9,
                                  arm_lockdown_lowhealth$econ, arm_lockdown_lowhealth$infection,
                                  arm_lockdown_lowhealth$mortality, arm_lockdown_lowhealth$education)
  dur3_lockdown <- utility_draws(variant, pars, "Lockdown", "Available", 3,
                                  arm_lockdown_lowhealth$econ, arm_lockdown_lowhealth$infection,
                                  arm_lockdown_lowhealth$mortality, arm_lockdown_lowhealth$education)
  dur9_lowphm <- utility_draws(variant, pars, "Basic", "Available", 9,
                                arm_lowphm_highhealth$econ, arm_lowphm_highhealth$infection,
                                arm_lowphm_highhealth$mortality, arm_lowphm_highhealth$education)
  dur3_lowphm <- utility_draws(variant, pars, "Basic", "Available", 3,
                                arm_lowphm_highhealth$econ, arm_lowphm_highhealth$infection,
                                arm_lowphm_highhealth$mortality, arm_lowphm_highhealth$education)
  duration_slope_lockdown <- dur9_lockdown - dur3_lockdown
  duration_slope_lowphm   <- dur9_lowphm - dur3_lowphm
  # "harms more under lockdown" -> the lockdown slope is more negative
  harms_more_under_lockdown <- duration_slope_lockdown - duration_slope_lowphm
  results[[length(results) + 1]] <- summarise_check(
    "1. low-health lockdown vs high-health low-PHM",
    "1b. duration harms more under lockdown (lockdown slope more negative)",
    variant, harms_more_under_lockdown, "negative")

  # 1c. parents unhappier about the low-PHM arm's weaker measures - NOT TESTABLE.
  #     The fitted utility function (Section 3, CLAUDE.md) has no
  #     LivingWithChildren term or interaction - Sex/Age-group are the only
  #     permitted covariates. Recorded as NA with a note rather than guessed.
  results[[length(results) + 1]] <- tibble(
    condition = "1. low-health lockdown vs high-health low-PHM",
    question = "1c. parents unhappier about weaker measures",
    variant = variant, mean = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
    pct_agreeing_with_expectation = NA_real_,
    expectation = "not testable - no parent/children covariate in the fitted utility function"
  )

  ## ---- Condition 2: low-health-impact lockdown vs low-health-impact low PHM ----

  # 2a. fatigue: utility of the (low-health) lockdown arm falls as duration rises?
  lockdown_dur9 <- utility_draws(variant, pars, "Lockdown", "Available", 9,
                                  arm_lockdown_lowhealth$econ, arm_lockdown_lowhealth$infection,
                                  arm_lockdown_lowhealth$mortality, arm_lockdown_lowhealth$education)
  lockdown_dur3 <- utility_draws(variant, pars, "Lockdown", "Available", 3,
                                  arm_lockdown_lowhealth$econ, arm_lockdown_lowhealth$infection,
                                  arm_lockdown_lowhealth$mortality, arm_lockdown_lowhealth$education)
  fatigue_slope <- lockdown_dur9 - lockdown_dur3
  results[[length(results) + 1]] <- summarise_check(
    "2. low-health lockdown vs low-health low-PHM", "2a. fatigue (utility falls as duration rises, lockdown arm)",
    variant, fatigue_slope, "negative")

  # 2b. economic cost of lockdown works against (offsets) the PHM/health benefit?
  #     Decompose: PHM benefit = phmvac_term(lockdown) - phmvac_term(basic);
  #     Econ cost  = econ_term(lockdown, 40%) - econ_term(basic, 0%).
  #     "Counters the direction" -> econ cost has the opposite sign to the
  #     PHM benefit (i.e. econ term is negative while PHM term is positive).
  phm_benefit <- phmvac_term(pars, "Lockdown", "Available") - phmvac_term(pars, "Basic", "Available")
  econ_cost <- case_when(TRUE ~ pars$b_econ40) - 0  # lockdown arm = 40%, low-PHM arm = 0% (reference)
  opposing_signs <- sign(phm_benefit) != sign(econ_cost)
  econ_ci <- quantile(econ_cost, c(0.025, 0.975))
  results[[length(results) + 1]] <- tibble(
    condition = "2. low-health lockdown vs low-health low-PHM",
    question = "2b. econ cost counters PHM benefit direction",
    variant = variant,
    mean = mean(econ_cost),
    ci_lo = econ_ci[[1]],
    ci_hi = econ_ci[[2]],
    pct_agreeing_with_expectation = mean(opposing_signs),
    expectation = "econ term negative while PHM term positive (opposing signs)"
  )
}

direction_test_summary <- bind_rows(results)
write_csv(direction_test_summary, file.path(out_dir, "direction_test_summary.csv"))

print(direction_test_summary, n = Inf)

# ---- 4. Check 3: cross-model sign consistency of shared coefficients ----

shared_coef_names <- c(
  "b_phmvac_basic_notavail", "b_phmvac_rsc_avail", "b_phmvac_rsc_notavail",
  "b_phmvac_lockdown_avail", "b_phmvac_lockdown_notavail",
  "b_econ20", "b_econ40", "b_inc50", "b_inc90",
  "b_mor100", "b_mor150", "b_edu10"
)

coef_signs <- map_dfr(names(variant_files), function(variant) {
  pars <- load_draws(variant)
  if (is.null(pars)) return(NULL)
  tibble(
    variant = variant,
    coefficient = shared_coef_names,
    posterior_mean = map_dbl(shared_coef_names, ~ if (.x %in% names(pars)) mean(pars[[.x]]) else NA_real_)
  )
}) %>%
  mutate(sign = sign(posterior_mean))

sign_consistency <- coef_signs %>%
  group_by(coefficient) %>%
  summarise(
    n_models = sum(!is.na(sign)),
    n_negative = sum(sign < 0, na.rm = TRUE),
    n_positive = sum(sign > 0, na.rm = TRUE),
    consistent = n_negative == 0 || n_positive == 0,
    .groups = "drop"
  )

write_csv(coef_signs, file.path(out_dir, "direction_test_coefs.csv"))

message("\nCross-model sign consistency (Check 3):")
print(sign_consistency, n = Inf)
if (!all(sign_consistency$consistent)) {
  inconsistent <- sign_consistency %>% filter(!consistent) %>% pull(coefficient)
  warning(sprintf("Sign inconsistent across Duration variants for: %s",
                   paste(inconsistent, collapse = ", ")))
}

# ---- 5. bar plot grid, one panel per scenario question -------------------
# Excludes 1c (not testable - no bars to draw). Bars = posterior mean,
# error bars = 95% interval across the 2,000 draws, fill = whether the
# draw-level result agrees with the stated theoretical expectation.

question_labels <- c(
  "1a. vaccine more attractive - lockdown arm"                          = "1a. Vaccine effect\n(lockdown arm)",
  "1a. vaccine more attractive - low-PHM arm"                           = "1a. Vaccine effect\n(low-PHM arm)",
  "1b. duration harms more under lockdown (lockdown slope more negative)" = "1b. Duration harms\nmore under lockdown",
  "2a. fatigue (utility falls as duration rises, lockdown arm)"         = "2a. Fatigue\n(lockdown arm)",
  "2b. econ cost counters PHM benefit direction"                       = "2b. Econ cost vs\nPHM benefit"
)

plot_data <- direction_test_summary %>%
  filter(!is.na(mean)) %>%
  mutate(
    question_label = recode(question, !!!question_labels),
    question_label = factor(question_label, levels = unique(question_labels)),
    variant = factor(variant, levels = names(variant_files)),
    agrees = pct_agreeing_with_expectation >= 0.5
  )

fig_dir <- file.path(out_dir, "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

direction_test_grid <- ggplot(plot_data, aes(x = variant, y = mean, fill = agrees)) +
  geom_col() +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.25, linewidth = 0.3) +
  geom_hline(yintercept = 0, linewidth = 0.3) +
  facet_wrap(~ question_label, nrow = 2, scales = "free_y") +
  scale_fill_manual(
    values = c(`TRUE` = "#2c7fb8", `FALSE` = "#d95f02"),
    labels = c(`TRUE` = "≥ 50% of draws agree", `FALSE` = "< 50% of draws agree"),
    name = NULL
  ) +
  labs(
    title = "Direction tests across Duration model variants",
    subtitle = "Posterior mean utility difference (bars) with 95% interval across 2,000 draws (error bars),\nby scenario question and Duration variant",
    x = "Duration model variant", y = "Utility difference"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "bottom",
    strip.text = element_text(face = "bold")
  )

ggsave(file.path(fig_dir, "direction_test_grid.png"), direction_test_grid,
       width = 11, height = 7, dpi = 300)

message(sprintf("\nBar plot grid written to %s", file.path(fig_dir, "direction_test_grid.png")))
