library(tidyverse)

# ---------------------------------------------------------------------------
# 1. Inputs: population (for Sex/Age) and Option A's fitted parameters
#    (2000 posterior draws), same coding as scripts_LLM_gen/3_utility_exp.R.
# ---------------------------------------------------------------------------
pop <- read_csv(here::here("data", "Sims", "syn_pop_2000.csv")) %>%
  transmute(
    male      = as.integer(Sex == "Male"),
    age_3554  = as.integer(Age >= 35 & Age <= 54),
    age_55p   = as.integer(Age >= 55)
  )

params <- read_csv(here::here("out", "durA_2000.csv"))

n_pop   <- nrow(pop)
n_draws <- nrow(params)

# ---------------------------------------------------------------------------
# 2. Utility building blocks (same reference levels/coding as
#    dce_model_optionA.stan and 3_utility_exp.R): Basic + Available, 3
#    months, 0% closed, 25% infection, 50 deaths/day, 5 falling behind.
# ---------------------------------------------------------------------------
DURATION_MONTHS <- 6  # fixed across all scenarios below - see plot subtitles

phmvac_category <- function(phm, vaccine) {
  case_when(
    phm == "Basic"    & vaccine == "Available"     ~ "basic_avail",
    phm == "Basic"    & vaccine != "Available"     ~ "basic_notavail",
    phm == "Lockdown" & vaccine == "Available"     ~ "lockdown_avail",
    phm == "Lockdown" & vaccine != "Available"     ~ "lockdown_notavail",
    TRUE ~ NA_character_
  )
}

# PHM x Vaccine contribution, vectorised over the population: theta_draws has
# one param DRAW PER PERSON (matched outside this function - see
# population_utility() below), so every b_* column here is already an
# n_pop-length vector.
phmvac_term <- function(theta_draws, category) {
  if (category == "basic_avail") return(rep(0, nrow(theta_draws)))
  main <- paste0("b_phmvac_", category)
  theta_draws[[main]] +
    theta_draws[[paste0(main, "_male")]]     * pop$male +
    theta_draws[[paste0(main, "_age3554")]]  * pop$age_3554 +
    theta_draws[[paste0(main, "_age55p")]]   * pop$age_55p
}

# Full utility for the population, for ONE situation, given one param draw
# per person (`theta_draws`, an n_pop-row slice of `params`).
population_utility <- function(theta_draws, phm, vaccine, duration, econ, infection, mortality, education) {
  category <- phmvac_category(phm, vaccine)
  if (is.na(category)) stop("Unrecognised phm/vaccine combination: ", phm, " / ", vaccine)

  phmvac_term(theta_draws, category) +
    theta_draws$b_dur6  * as.integer(duration == 6) +
    theta_draws$b_dur9  * as.integer(duration == 9) +
    theta_draws$b_econ20 * as.integer(econ == 20) +
    theta_draws$b_econ40 * as.integer(econ == 40) +
    theta_draws$b_inc50 * as.integer(infection == 50) +
    theta_draws$b_inc90 * as.integer(infection == 90) +
    theta_draws$b_mor100 * as.integer(mortality == 100) +
    theta_draws$b_mor150 * as.integer(mortality == 150) +
    theta_draws$b_edu10 * as.integer(education == 10)
}

# ---------------------------------------------------------------------------
# 3. Scenarios - each pairs a PHM level with an outbreak/economic outcome.
#    Duration is fixed at DURATION_MONTHS throughout, so all three scenarios
#    isolate PHM x Vaccine x outcome, not Duration.
# ---------------------------------------------------------------------------
scenario_attrs <- tribble(
  ~scenario,             ~phm,       ~econ, ~infection, ~mortality, ~education,
  "1. Timely lockdown",   "Basic",     0,    90,         150,        10,   # uncontrolled outbreak, no restriction cost
  "1. Timely lockdown",   "Lockdown", 40,    25,         50,         5,    # outbreak suppressed, but at economic cost
  "2. Lockdown failed",   "Basic",     0,    90,         150,        10,   # same bad outcome...
  "2. Lockdown failed",   "Lockdown", 40,    90,         150,        10,   # ...whichever PHM was chosen
  "3. Overkill lockdown", "Basic",     0,    25,         50,         5,    # outbreak already low-impact...
  "3. Overkill lockdown", "Lockdown", 40,    25,         50,         5     # ...lockdown adds cost for no gain
) %>%
  mutate(scenario = fct_inorder(scenario), phm = factor(phm, levels = c("Basic", "Lockdown")))

vaccine_levels <- c("Available", "Not available")

situations <- scenario_attrs %>%
  crossing(vaccine = vaccine_levels) %>%
  mutate(vaccine = factor(vaccine, levels = vaccine_levels))

# ---------------------------------------------------------------------------
# 4. Monte Carlo: for each situation, repeatedly (a) pair each of the 2000
#    population members with a randomly sampled parameter draw, (b) compute
#    the population's mean utility, then summarise across replicates for a
#    95% interval (the between-replicate spread reflects posterior
#    uncertainty in the parameters, not sampling from the population itself,
#    since the whole population is used every time).
# ---------------------------------------------------------------------------
N_REPS <- 200
set.seed(20260910)

situation_utility_reps <- function(phm, vaccine, econ, infection, mortality, education) {
  map_dbl(seq_len(N_REPS), function(i) {
    draw_idx <- sample.int(n_draws, n_pop, replace = TRUE)
    theta_draws <- params[draw_idx, ]
    u <- population_utility(theta_draws, phm, vaccine, DURATION_MONTHS, econ, infection, mortality, education)
    mean(u)
  })
}

results <- situations %>%
  mutate(
    rep_means = pmap(list(phm, vaccine, econ, infection, mortality, education), situation_utility_reps)
  ) %>%
  mutate(
    mean_u = map_dbl(rep_means, mean),
    ci_lo  = map_dbl(rep_means, ~ quantile(.x, 0.025)),
    ci_hi  = map_dbl(rep_means, ~ quantile(.x, 0.975))
  ) %>%
  select(-rep_means)

write_csv(results, here::here("out", "scenario_utility_results.csv"))

# ---------------------------------------------------------------------------
# 5. Bar plots - one per scenario: two PHM-level bars, panelled by vaccine
#    availability, subtitle stating the utility function's dependence on
#    PHM, Vaccine and Duration (Duration fixed at DURATION_MONTHS here).
# ---------------------------------------------------------------------------
subtitle_formula <- sprintf(
  "U = f(PHM x Vaccine) + f(Duration = %d months) + Econ + Infection + Mortality + Education",
  DURATION_MONTHS
)

plot_scenario <- function(df, scenario_name) {
  ggplot(df, aes(x = phm, y = mean_u, fill = phm)) +
    geom_col(width = 0.6) +
    geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.15) +
    facet_wrap(~ vaccine, labeller = labeller(vaccine = ~ paste("Vaccine:", .))) +
    scale_fill_manual(values = c(Basic = "#6BAED6", Lockdown = "#B2182B"), guide = "none") +
    labs(
      title = scenario_name,
      subtitle = subtitle_formula,
      x = "Public health measure",
      y = "Population-mean utility (relative to Basic + Vaccine available)"
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.subtitle = element_text(size = 9, colour = "grey30"))
}

scenario_names <- levels(scenario_attrs$scenario)

plots <- map(scenario_names, function(s) {
  plot_scenario(filter(results, scenario == s), s)
})
names(plots) <- scenario_names

fig_dir <- here::here("out", "figures")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

iwalk(plots, function(p, s) {
  fname <- paste0("scenario_", str_replace_all(str_remove(s, "^\\d+\\.\\s*"), " ", "_"), ".png")
  ggsave(file.path(fig_dir, fname), p, width = 7, height = 4.5, dpi = 300)
})

# Display all three if run interactively
walk(plots, print)
