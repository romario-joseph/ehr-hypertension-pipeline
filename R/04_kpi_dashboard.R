# 04_kpi_dashboard.R
# Build the four headline KPIs + equity stratification table.
# Output: Tableau-ready CSVs in outputs/tables/
# Author: Romario Joseph | BU SPH

library(tidyverse)

htn <- readRDS("data/processed/htn_cohort.rds")

# --- KPI 1: HTN prevalence ---
kpi_prev <- tibble(
    metric = "HTN prevalence",
    numerator = sum(htn$has_htn, na.rm = TRUE),
    denominator = nrow(htn),
    value = numerator / denominator
  )

# --- KPI 2: Control rate among HTN patients ---
htn_pop <- htn |> filter(has_htn)
kpi_ctrl <- tibble(
    metric = "Control rate (last BP < 140/90)",
    numerator = sum(htn_pop$controlled, na.rm = TRUE),
    denominator = nrow(htn_pop),
    value = numerator / denominator
  )

# --- KPI 3: Follow-up gap rate ---
uncontrolled <- htn_pop |> filter(!controlled | is.na(controlled))
kpi_gap <- tibble(
    metric = "90-day follow-up gap",
    numerator = sum(uncontrolled$any_gap, na.rm = TRUE),
    denominator = nrow(uncontrolled),
    value = numerator / denominator
  )

# --- KPI 4: Equity — control rate ratio across race/ethnicity strata ---
equity <- htn_pop |>
  group_by(race) |>
  summarise(
        n = n(),
        n_controlled = sum(controlled, na.rm = TRUE),
        control_rate = n_controlled / n,
        .groups = "drop"
      ) |>
  arrange(control_rate)

kpi_equity <- tibble(
    metric = "Equity ratio (lowest ÷ highest control rate by race)",
    numerator = min(equity$control_rate, na.rm = TRUE),
    denominator = max(equity$control_rate, na.rm = TRUE),
    value = numerator / denominator
  )

kpi_table <- bind_rows(kpi_prev, kpi_ctrl, kpi_gap, kpi_equity)
write_csv(kpi_table, "outputs/tables/kpi_summary.csv")
write_csv(equity,    "outputs/tables/control_by_race.csv")

print(kpi_table)
message("Wrote KPI tables to outputs/tables/")
