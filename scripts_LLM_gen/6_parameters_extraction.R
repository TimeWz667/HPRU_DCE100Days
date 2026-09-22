# 6_parameters_extraction.R
#
# Rewritten parameter-extraction step for the simulation handoff package
# (Outputs4Sims/). Supersedes 5_parameters_extraction.R. Differences:
#   - Only three Duration variants are exported: Dur_a, Dur_d, Dur_f,
#     relabelled Scenario_1, Scenario_2, Scenario_3 respectively.
#   - Each respondent's demographic/survey info (Results/
#     simulated_respondents_info_s001.csv) is combined with ONE posterior
#     draw per respondent, sampled at random with replacement - i.e. the
#     respondent-to-draw pairing is done here, once, rather than left for
#     the simulation to do at run time.
#   - Output is CSV, not JSON: one file per scenario, one row per
#     respondent (2,000 rows), columns = respondent info + that
#     respondent's assigned parameter set.
#
# This bakes in a single Monte Carlo realisation of the respondent-draw
# pairing (fixed by the seed below), rather than handing the simulation
# project the full 2,000-draw array to resample from on every run - see
# the note in Outputs4Sims/CLAUDE.md Section 5 on what this trades away.
#
# Inputs:  Results/simulated_respondents_info_s001.csv  (2,000 respondents)
#          out/Dur_a_2000.csv, out/Dur_d_2000.csv, out/Dur_f_2000.csv
# Outputs: Outputs4Sims/Scenario_1/Pars/Pars_s001.csv  (was Dur_a)
#          Outputs4Sims/Scenario_2/Pars/Pars_s001.csv  (was Dur_d)
#          Outputs4Sims/Scenario_3/Pars/Pars_s001.csv  (was Dur_f)

library(readr)
library(dplyr)

replication_id <- "s002"
seed <- 20260922  # fixed so the respondent-to-draw pairing is reproducible

# Duration model variant -> scenario label -> posterior draw CSV under out/
scenario_map <- list(
  Dur_a = list(scenario = "Scenario_1", file = "Dur_a_2000.csv"),
  Dur_d = list(scenario = "Scenario_2", file = "Dur_d_2000.csv"),
  Dur_f = list(scenario = "Scenario_3", file = "Dur_f_2000.csv")
)

src_dir <- "out"
info_dir <- "Results"
out_dir <- "Outputs4Sims"

info_path <- file.path(info_dir, sprintf("simulated_respondents_info_%s.csv", replication_id))
info <- read_csv(info_path, show_col_types = FALSE)
n_resp <- nrow(info)

set.seed(seed)

for (model in names(scenario_map)) {
  scenario <- scenario_map[[model]]$scenario
  csv_path <- file.path(src_dir, scenario_map[[model]]$file)

  if (!file.exists(csv_path)) {
    warning(sprintf("Skipping %s (%s): %s not found", model, scenario, csv_path))
    next
  }

  draws <- read_csv(csv_path, show_col_types = FALSE)

  # One posterior draw per respondent, at random, with replacement.
  draw_idx <- sample.int(nrow(draws), size = n_resp, replace = TRUE)

  combined <- bind_cols(
    info,
    draw_id = draw_idx,
    draws[draw_idx, ]
  )

  pars_dir <- file.path(out_dir, scenario, "Pars")
  dir.create(pars_dir, recursive = TRUE, showWarnings = FALSE)

  out_path <- file.path(pars_dir, sprintf("Pars_%s.csv", replication_id))
  write_csv(combined, out_path)

  message(sprintf("%s -> %s: wrote %d respondents x %d columns to %s",
                   model, scenario, nrow(combined), ncol(combined), out_path))
}
