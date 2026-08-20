# rules/ui/

HUD-facing signal emitters and display helpers. Signals flow out only — the HUD observes
and never calls back into rules to mutate state. No combat formulas live here; affordability
checks call into the appropriate subsystem rather than recomputing costs.
