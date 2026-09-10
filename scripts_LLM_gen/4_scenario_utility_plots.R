library(tidyverse)
library(patchwork)

# ---------------------------------------------------------------------------
# 1. Inputs: population (for Sex/Age), shared across every Duration variant.
# ---------------------------------------------------------------------------
pop <- read_csv(here::here("data", "Sims", "syn_pop_2000.csv")) %>%
  transmute(
    male      = as.integer(Sex == "Male"),
    age_3554  = as.integer(Age >= 35 & Age <= 54),
    age_55p   = as.integer(Age >= 55)
  )

n_pop <- nrow(pop)

# ---------------------------------------------------------------------------
# 2. PHM x Vaccine utility term - identical coding/reference level across
#    every Duration variant (Basic + Available is the reference).
# ---------------------------------------------------------------------------
phmvac_category <- function(phm, vaccine) {
  case_when(
    phm == "Basic"    & vaccine == "Available"     ~ "basic_avail",
    phm == "Basic"    & vaccine != "Available"     ~ "basic_notavail",
    phm == "Lockdown" & vaccine == "Available"     ~ "lockdown_avail",
    phm == "Lockdown" & vaccine != "Available"     ~ "lockdown_notavail",
    TRUE ~ NA_character_
  )
}

# PHM severity, ordinal (0/1/2), used only by variant C's PHM_sev x Duration
# interaction (stan/dce_model_durC.stan) - independent of the PHM x Vaccine
# dummies above. Basic = 0, Lockdown = 2 (Reduced social contact = 1 is not
# used by any scenario here).
phm_severity <- function(phm) {
  case_when(phm == "Basic" ~ 0, phm == "Lockdown" ~ 2, TRUE ~ NA_real_)
}

phmvac_term <- function(theta_draws, category) {
  if (category == "basic_avail") return(rep(0, nrow(theta_draws)))
  main <- paste0("b_phmvac_", category)
  theta_draws[[main]] +
    theta_draws[[paste0(main, "_male")]]     * pop$male +
    theta_draws[[paste0(main, "_age3554")]]  * pop$age_3554 +
    theta_draws[[paste0(main, "_age55p")]]   * pop$age_55p
}

shared_attribute_terms <- function(theta_draws, econ, infection, mortality, education) {
  theta_draws$b_econ20 * as.integer(econ == 20) +
    theta_draws$b_econ40 * as.integer(econ == 40) +
    theta_draws$b_inc50 * as.integer(infection == 50) +
    theta_draws$b_inc90 * as.integer(infection == 90) +
    theta_draws$b_mor100 * as.integer(mortality == 100) +
    theta_draws$b_mor150 * as.integer(mortality == 150) +
    theta_draws$b_edu10 * as.integer(education == 10)
}

# ---------------------------------------------------------------------------
# 3. Duration variants. Each defines its own posterior-draw file and its own
#    Duration term, matching that file's stan/dce_model_*.stan coding.
#    Everything else (PHM x Vaccine, Econ/Infection/Mortality/Education) is
#    shared - see stan/duration-variants.md.
# ---------------------------------------------------------------------------
# `tag` names every output file/folder for this variant (matches the
# posterior CSV's own "Dur_x" naming, e.g. Dur_a_2000.csv -> tag "Dur_a").
variants <- list(
  Dur_a = list(
    tag   = "Dur_a",
    label = "Option A (Duration categorical: 3/6/9 months, dummy-coded)",
    file  = "Dur_a_2000.csv",
    duration_term = function(theta_draws, phm, duration) {
      theta_draws$b_dur6 * as.integer(duration == 6) +
        theta_draws$b_dur9 * as.integer(duration == 9)
    }
  ),
  Dur_b = list(
    tag   = "Dur_b",
    label = "Option B (Duration continuous, single coefficient)",
    file  = "Dur_b_2000.csv",
    duration_term = function(theta_draws, phm, duration) {
      theta_draws$b_dur * duration
    }
  ),
  Dur_c = list(
    tag   = "Dur_c",
    label = "Variant C (PHM severity x Duration interaction)",
    file  = "Dur_c_2000.csv",
    duration_term = function(theta_draws, phm, duration) {
      theta_draws$b_phmsev_dur * phm_severity(phm) * duration
    }
  )
)

population_utility <- function(theta_draws, duration_term_fn, phm, vaccine, duration, econ, infection, mortality, education) {
  category <- phmvac_category(phm, vaccine)
  if (is.na(category)) stop("Unrecognised phm/vaccine combination: ", phm, " / ", vaccine)

  phmvac_term(theta_draws, category) +
    duration_term_fn(theta_draws, phm, duration) +
    shared_attribute_terms(theta_draws, econ, infection, mortality, education)
}

# ---------------------------------------------------------------------------
# 4. Scenarios - same three outbreak/PHM pairings for every variant. Duration
#    is fixed at DURATION_MONTHS throughout, so each scenario isolates PHM x
#    Vaccine x outcome, not Duration.
# ---------------------------------------------------------------------------
DURATION_MONTHS <- 6

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

scenario_names <- levels(scenario_attrs$scenario)

# ---------------------------------------------------------------------------
# 5. Monte Carlo + plotting, run once per variant.
# ---------------------------------------------------------------------------
N_REPS <- 200

run_variant <- function(variant_key) {
  v <- variants[[variant_key]]
  cat("\n===", v$tag, "-", v$label, "===\n")

  params <- read_csv(here::here("out", v$file))
  n_draws <- nrow(params)
  set.seed(20260910)

  situation_utility_reps <- function(phm, vaccine, econ, infection, mortality, education) {
    map_dbl(seq_len(N_REPS), function(i) {
      draw_idx <- sample.int(n_draws, n_pop, replace = TRUE)
      theta_draws <- params[draw_idx, ]
      u <- population_utility(theta_draws, v$duration_term, phm, vaccine, DURATION_MONTHS, econ, infection, mortality, education)
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

  write_csv(results, here::here("out", paste0("scenario_utility_results_", v$tag, ".csv")))

  subtitle_formula <- sprintf("%s | Duration fixed at %d months", v$label, DURATION_MONTHS)

  plot_scenario <- function(df, scenario_name, with_subtitle = TRUE) {
    p <- ggplot(df, aes(x = phm, y = mean_u, fill = phm)) +
      geom_col(width = 0.6) +
      geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.15) +
      facet_wrap(~ vaccine, labeller = labeller(vaccine = ~ paste("Vaccine:", .))) +
      scale_fill_manual(values = c(Basic = "#6BAED6", Lockdown = "#B2182B"), guide = "none") +
      labs(
        title = scenario_name,
        x = "Public health measure",
        y = "Population-mean utility (relative to Basic + Vaccine available)"
      ) +
      theme_minimal(base_size = 12) +
      theme(plot.subtitle = element_text(size = 9, colour = "grey30"))
    if (with_subtitle) p <- p + labs(subtitle = subtitle_formula)
    p
  }

  plots <- map(scenario_names, ~ plot_scenario(filter(results, scenario == .x), .x))
  names(plots) <- scenario_names

  fig_dir <- here::here("out", "figures", v$tag)
  dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

  iwalk(plots, function(p, s) {
    fname <- paste0("scenario_", str_replace_all(str_remove(s, "^\\d+\\.\\s*"), " ", "_"), ".png")
    ggsave(file.path(fig_dir, fname), p, width = 7, height = 4.5, dpi = 300)
  })

  combined_plots <- map(scenario_names, ~ plot_scenario(filter(results, scenario == .x), .x, with_subtitle = FALSE))
  combined_fig <- wrap_plots(combined_plots, ncol = 1) +
    plot_layout(axis_titles = "collect") +
    plot_annotation(
      title = "Utility of Basic measures vs Lockdown across outbreak scenarios",
      subtitle = subtitle_formula,
      theme = theme(plot.subtitle = element_text(size = 9, colour = "grey30"))
    )
  ggsave(file.path(fig_dir, "scenario_utility_combined.png"), combined_fig, width = 7, height = 11, dpi = 300)

  list(results = results, plots = plots, combined = combined_fig)
}

variant_outputs <- map(names(variants), run_variant)
names(variant_outputs) <- names(variants)

# Display combined figures if run interactively
walk(variant_outputs, ~ print(.x$combined))
