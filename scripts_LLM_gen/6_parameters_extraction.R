# 5_parameters_extraction.R
#
# Extracts fitted posterior draws (out/Dur_*_2000.csv) into the parameter
# package handed off to the simulation project: one JSON file per Duration
# model variant, at Outputs4Sims/{Model}/Pars/Pars_{id}.csv
#
# Each Pars_{id}.csv is a csv array of parameter sets, one object per
# posterior draw, field names matching that variant's Stan coefficients
# exactly. {id} mirrors the survey-replication numbering upstream
# (Results/simulated_respondents_ans_s*.csv); only "s001" exists today.
#
# See Outputs4Sims/CLAUDE.md for the full data contract this script
# produces.

library(jsonlite)

# ---- configuration ----------------------------------------------------

# Duration model variant -> posterior draw CSV under out/
models <- list(
  Scenario_1        = "Dur_a_2000.csv",
  Scenario_2        = "Dur_d_2000.csv",
  Scenario_3        = "Dur_f_2000.csv"
)

src_dir <- "out"
out_dir <- "Outputs4Sims"
info_dir <- "Results"

# ---- extraction ---------------------------------------------------------

for (replication_id in c("s002")) {
  info <- read.csv(file.path(info_dir, sprintf("simulated_respondents_info_%s.csv", replication_id)), check.names = FALSE)
  
  for (model in names(models)) {
    csv_path <- file.path(src_dir, models[[model]])
    
    if (!file.exists(csv_path)) {
      warning(sprintf("Skipping %s: %s not found", model, csv_path))
      next
    }
    
    draws <- read.csv(csv_path, check.names = FALSE)
    draws <- draws[sample.int(nrow(info), replace = T), ]
    pars <- bind_cols(info, draws)

    pars_dir <- file.path(out_dir, model)
    dir.create(pars_dir, recursive = TRUE, showWarnings = FALSE)
    
    out_path <- file.path(pars_dir, sprintf("Pars_%s.csv", replication_id))
    write_csv(pars, out_path)
    
    message(sprintf("%s: wrote %d draws to %s", model, nrow(draws), out_path))
  }
}


