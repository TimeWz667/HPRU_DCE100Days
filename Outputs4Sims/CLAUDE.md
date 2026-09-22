# CLAUDE.md — outbreak-response simulation handoff package

This folder (`Outputs4Sims/`) is the self-contained handoff package from
the `HPRU_DCE100Days` discrete choice experiment (DCE) project to the
simulation project.

**Task: build an agent-based (or population-average) Monte Carlo
simulation model that uses the fitted DCE utility function to determine
how a simulated population responds to public health measures during an
outbreak, across three named scenarios.**

Read, in this order:

1. **`build_guide.md`** — the model specification and build instructions.
   Standalone: nothing outside this folder is required, and every path in
   it is relative to this folder. Start here to build the simulation.
2. **`README.md`** — how the parameter files were extracted, the nine
   underlying Duration models, and why three of them (`Dur_a`, `Dur_d`,
   `Dur_f`, relabelled `Scenario_1`/`Scenario_2`/`Scenario_3`) were
   selected for this package. Background, not required to build.
3. **`duration-variants.md`** — full detail on all nine Duration model
   variants, referenced by `README.md`.

Parameter files: `Scenario_1/Pars_s002.csv`,
`Scenario_2/Pars_s002.csv`, `Scenario_3/Pars_s002.csv`.
