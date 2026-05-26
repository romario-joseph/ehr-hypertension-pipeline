# 03_htn_phenotype.R
# Apply CMS CBP / 2017 ACC-AHA hypertension phenotype logic
# Author: Romario Joseph | BU SPH

library(tidyverse)
library(lubridate)

cohort   <- readRDS("data/processed/cohort.rds")
vitals   <- readRDS("data/processed/vitals_clean.rds")
dx       <- readRDS("data/processed/dx.rds")

HTN_ICD <- c("I10", "I11", "I12", "I13", "I15", "I16")

# --- Diagnosis-based HTN ---
htn_dx <- dx |>
  mutate(icd3 = substr(icd10, 1, 3)) |>
  filter(icd3 %in% HTN_ICD) |>
  distinct(patient_id) |>
  mutate(htn_by_dx = TRUE)

# --- BP-based HTN (>=2 readings >=140/90 on separate dates within 24 months) ---
htn_bp <- vitals |>
  filter(measured_at >= today() - months(24),
                  sbp_mmhg >= 140 | dbp_mmhg >= 90) |>
  mutate(visit_date = as_date(measured_at)) |>
  distinct(patient_id, visit_date) |>
  group_by(patient_id) |>
  summarise(n_high_visits = n(), .groups = "drop") |>
  filter(n_high_visits >= 2) |>
  mutate(htn_by_bp = TRUE) |>
  select(patient_id, htn_by_bp)

htn <- cohort |>
  left_join(htn_dx, by = "patient_id") |>
  left_join(htn_bp, by = "patient_id") |>
  mutate(
        htn_by_dx = coalesce(htn_by_dx, FALSE),
        htn_by_bp = coalesce(htn_by_bp, FALSE),
        has_htn   = htn_by_dx | htn_by_bp
      )

# --- Control status (last BP in prior 12 months) ---
last_bp <- vitals |>
  filter(measured_at >= today() - months(12)) |>
  group_by(patient_id) |>
  slice_max(measured_at, n = 1, with_ties = FALSE) |>
  ungroup() |>
  transmute(patient_id,
                        last_sbp = sbp_mmhg,
                        last_dbp = dbp_mmhg,
                        last_bp_date = as_date(measured_at),
                        controlled = sbp_mmhg < 140 & dbp_mmhg < 90)

htn_full <- htn |> left_join(last_bp, by = "patient_id")

# --- 90-day follow-up gap ---
high_readings <- vitals |>
  filter(sbp_mmhg >= 140 | dbp_mmhg >= 90) |>
  select(patient_id, high_date = measured_at)

follow_up <- high_readings |>
  inner_join(vitals |> select(patient_id, next_date = measured_at),
                          by = "patient_id",
                          relationship = "many-to-many") |>
  filter(next_date > high_date,
                  next_date <= high_date + days(90)) |>
  distinct(patient_id, high_date) |>
  mutate(has_followup = TRUE)

gap <- high_readings |>
  left_join(follow_up, by = c("patient_id", "high_date")) |>
  mutate(has_followup = coalesce(has_followup, FALSE)) |>
  group_by(patient_id) |>
  summarise(any_gap = any(!has_followup), .groups = "drop")

htn_full <- htn_full |> left_join(gap, by = "patient_id")

saveRDS(htn_full, "data/processed/htn_cohort.rds")
message("HTN cohort built: ", nrow(htn_full), " rows | ",
                sum(htn_full$has_htn, na.rm = TRUE), " with HTN")
