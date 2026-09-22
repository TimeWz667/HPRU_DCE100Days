# 5_parameters_extraction.R
#
# Extracts fitted posterior draws (out/Dur_*_2000.csv) into the parameter
# package handed off to the simulation project: one JSON file per Duration
# model variant, at Outputs4Sims/{Model}/Pars/Pars_{id}.json.
#
# Each Pars_{id}.json is a JSON array of parameter sets, one object per
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
  Dur_a        = "Dur_a_2000.csv",
  Dur_b        = "Dur_b_2000.csv",
  Dur_b_convex = "Dur_b_convex_2000.csv",
  Dur_b_concave = "Dur_b_concave_2000.csv",
  Dur_c        = "Dur_c_2000.csv",
  Dur_d        = "Dur_d_2000.csv",
  Dur_e        = "Dur_e_2000.csv",
  Dur_f        = "Dur_f_2000.csv",
  Dur_g        = "Dur_g_2000.csv"
)

src_dir <- "out"
out_dir <- "Outputs4Sims"

# ---- extraction ---------------------------------------------------------

for (replication_id in c("s002"))

for (model in names(models)) {
  csv_path <- file.path(src_dir, models[[model]])

  if (!file.exists(csv_path)) {
    warning(sprintf("Skipping %s: %s not found", model, csv_path))
    next
  }

  draws <- read.csv(csv_path, check.names = FALSE)

  # One JSON object per posterior draw, field names = column names as-is.
  pars <- lapply(seq_len(nrow(draws)), function(i) as.list(draws[i, ]))

  pars_dir <- file.path(out_dir, model)
  dir.create(pars_dir, recursive = TRUE, showWarnings = FALSE)

  out_path <- file.path(pars_dir, sprintf("Pars_%s.json", replication_id))
  write(toJSON(pars, auto_unbox = TRUE, digits = NA), out_path)

  message(sprintf("%s: wrote %d draws to %s", model, nrow(draws), out_path))
}
