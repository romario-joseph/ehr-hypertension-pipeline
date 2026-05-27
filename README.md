# Epic EHR → Hypertension Management Pipeline

**Author:** Romario Joseph, MPH · BU SPH (Epidemiology & Biostatistics)
**Stack:** SQL (PostgreSQL) · R 4.x · tidyverse · Quarto · Tableau-ready outputs
**Data:** 100% **synthetic** EHR records generated to match Epic Clarity / Caboodle schemas. No PHI.

---

## Epidemiological Objective

Among adults seen in primary care, **what share have uncontrolled hypertension (BP ≥ 140/90), and where are the gaps in equitable follow-up?** Uncontrolled hypertension is the single largest modifiable contributor to cardiovascular mortality in the United States, and disparities in control rates by race/ethnicity, language, and insurance status remain a persistent source of avoidable morbidity. This pipeline operationalizes the CMS *Controlling High Blood Pressure* (CBP) quality measure as a reproducible, equity-stratified analytic asset that can be deployed against any Epic Clarity / Caboodle–like schema. It is designed to answer four linked clinical-equity questions:

1. **HTN prevalence** — what fraction of the adult primary-care panel meets a validated hypertension phenotype?
2. **Control rate** — among phenotyped HTN patients, what share have a most-recent BP < 140/90 mmHg?
3. **Follow-up gap** — among patients with an uncontrolled reading, what share have no documented BP recheck within 90 days?
4. **Equity index** — what is the control-rate ratio between the lowest- and highest-performing demographic stratum (age × sex × race/ethnicity × insurance × preferred language)?

---

## Methodological Framework

The pipeline is a deterministic, rule-based **electronic phenotyping** workflow grounded in the eMERGE Network's algorithmic phenotyping tradition and the CMS CBP measure specification. Specifically, the methodological stack includes:

- **Computable phenotype definition (Boolean rule set).** Hypertension status is operationalized as a disjunction of (a) ICD-10 diagnostic codes in {I10, I11.x, I12.x, I13.x, I15.x, I16.x} on ≥ 1 encounter, OR (b) ≥ 2 outpatient blood-pressure readings with SBP ≥ 140 mmHg or DBP ≥ 90 mmHg measured on **distinct encounter dates** within a 24-month rolling window. The two-reading requirement on distinct dates is a deliberate guard against single-visit white-coat misclassification, consistent with the 2017 ACC/AHA guideline.
- **Control status (binary outcome).** *Controlled* = most-recent BP within the prior 12 months has SBP < 140 mmHg AND DBP < 90 mmHg. *Uncontrolled* = otherwise. *Follow-up gap* = uncontrolled reading without any subsequent BP measurement within 90 days.
- **Equity stratification.** Control rates and 95% Wilson confidence intervals are computed within strata of age band, sex, race/ethnicity (OMB categories), insurance class, and preferred language. The summary equity statistic is the **control-rate ratio** of the lowest- versus highest-performing stratum, a direct analog of the rate ratios used in the CMS Health Equity Index.
- **KPI reporting layer.** All KPIs are emitted as long-format Tableau-ready CSVs and rendered into a Quarto clinician-facing dashboard.

The pipeline is intentionally **semi-parametric in spirit**: prevalence, control, and gap are estimated non-parametrically from the EHR, while stratum-specific comparisons are bounded by exact Wilson intervals rather than asymptotic normal approximations to remain valid in small demographic cells.

---

## Data Architecture

The pipeline is structured as an explicit **SQL → R → Quarto** directed acyclic graph, with each node owning a single, auditable transformation. This separation is what allows the same code base to be redeployed against a real Epic Clarity warehouse without rewriting downstream logic.

**Stage 0 — Schema construction (`sql/00_schema.sql`).** A PostgreSQL schema mirrors the relevant Epic Clarity / Caboodle tables: `patient`, `encounter`, `vitals`, `dx`, `meds`, `lab`. Primary and foreign keys are explicitly declared so referential integrity errors surface immediately rather than propagating downstream.

**Stage 1 — Cohort extraction (`sql/01_extract_cohort.sql`, `sql/02_extract_bp.sql`).** Extracts the adult primary-care cohort (age ≥ 18 at index encounter, ≥ 1 primary-care visit in the lookback window) and, separately, the longitudinal BP series (latest reading plus trailing 24-month history per patient). Pushing the join down to SQL keeps the R-side memory footprint bounded for warehouse-scale deployments.

**Stage 2 — Ingest (`R/01_extract.R`).** Connects via `DBI`/`RPostgres`, pulls into tibbles, and writes a typed manifest of row counts and primary-key uniqueness checks. Any deviation halts the pipeline.

**Stage 3 — Cleaning & plausibility validation (`R/02_clean_validate.R`).** Handles the data-engineering constraints that distinguish a publishable EHR pipeline from a brittle script:

- **Unit harmonization.** BP readings are coerced to mmHg; lab values are unit-checked against LOINC reference ranges.
- **Plausibility filters.** Readings outside physiologic bounds (SBP < 70 or > 250 mmHg; DBP < 40 or > 150 mmHg) are flagged as implausible and excluded from phenotype determination, but retained in an audit table so the exclusion rate is reportable.
- **Duplicate clinic-visit handling.** Encounters sharing `(patient_id, encounter_date, encounter_type)` are deduplicated by retaining the record with the most complete vitals payload (fewest NA fields), with ties broken by latest `encounter_datetime`. This prevents double-counting from registration re-checks.
- **Outlier treatment.** Within-patient BP outliers are identified using a patient-specific Tukey fence (1.5 × IQR around the within-patient median) and winsorized at the fence rather than dropped, preserving sample size while attenuating typographic data-entry errors. The winsorization rate is reported per stratum so reviewers can confirm it does not differentially affect any subgroup.
- **Missing-data strategy.** Missingness is modeled explicitly rather than imputed silently. (i) For demographics, missing race/ethnicity is retained as an *Unknown* stratum and reported separately, never collapsed into a reference category. (ii) For BP series, patients with zero plausible outpatient readings in the 24-month window are coded as *phenotype-indeterminate* and excluded from the denominator with the exclusion count surfaced as a measure-validity diagnostic. (iii) For ICD-10 dx codes, absence is treated as a true negative only when the patient has ≥ 1 qualifying primary-care encounter in the window (otherwise the patient is censored from the cohort). This is the eMERGE-style "case / control / indeterminate" trichotomy, which avoids the silent bias of complete-case analysis.

**Stage 4 — Phenotype application (`R/03_htn_phenotype.R`).** Applies the Boolean rule set above, distinguishing the ICD-only arm from the BP-only arm so reviewers can see the contribution of each. This also enables sensitivity analyses where the BP threshold is dropped from 140/90 to 130/80 (2017 ACC/AHA stage 1) without recomputing the cohort.

**Stage 5 — KPI emission (`R/04_kpi_dashboard.R`).** Produces four Tableau-ready CSVs (`kpi_prevalence`, `kpi_control`, `kpi_gap`, `kpi_equity`), each with stratum keys, point estimates, and Wilson 95% CIs.

**Stage 6 — Reporting (`reports/htn_kpi_report.qmd`).** A Quarto document renders a single-page clinician-facing dashboard from the KPI tables.

```
ehr-hypertension-pipeline/
├── README.md
├── sql/
│   ├── 00_schema.sql             ← Epic-like tables (patient, encounter, vitals, dx, meds)
│   ├── 01_extract_cohort.sql     ← adult primary-care cohort
│   └── 02_extract_bp.sql         ← latest + trailing BP per patient
├── R/
│   ├── 01_extract.R              ← connect + pull SQL into tibbles
│   ├── 02_clean_validate.R       ← unit checks, plausibility, dedup, winsorization
│   ├── 03_htn_phenotype.R        ← phenotype + control logic
│   └── 04_kpi_dashboard.R        ← KPI tables for Tableau
├── data/
│   ├── synthetic/                ← generated CSVs (committed)
│   └── README.md
├── reports/
│   └── htn_kpi_report.qmd        ← Quarto report
└── LICENSE
```

---

## KPIs produced

| KPI | Definition | Tableau field |
|-----|------------|---------------|
| HTN prevalence | n_htn / n_adults | `kpi_prevalence` |
| Control rate | n_controlled / n_htn | `kpi_control` |
| Follow-up gap | n_gap / n_uncontrolled | `kpi_gap` |
| Equity index | control rate ratio (lowest vs highest stratum) | `kpi_equity` |

---

## Reproduce

```bash
# 1. Spin up a local Postgres + load the synthetic schema
psql -f sql/00_schema.sql
psql -f data/synthetic/load_synthetic.sql

# 2. Run the R pipeline
Rscript R/01_extract.R
Rscript R/02_clean_validate.R
Rscript R/03_htn_phenotype.R
Rscript R/04_kpi_dashboard.R

# 3. Render the report
quarto render reports/htn_kpi_report.qmd
```

---

## Why this matters

At scale (70+ provider networks at MA DPH, multi-site recruitment at the Broad Institute), the same four KPIs become a real-world-evidence backbone for primary-care quality improvement. The pipeline pattern — **SQL extract → R phenotype → KPI table → dashboard** — is reusable for diabetes (HbA1c), CKD (eGFR), and any other chronic condition with a defined control threshold.

---

## Disclaimer

All data in this repo is synthetic. No real patient information is included. Not for clinical use.

## Contact

Romario Joseph · rjoseph3@bu.edu · [LinkedIn](https://www.linkedin.com/in/romariojosephpublichealth/)
