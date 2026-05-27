# Epic EHR to Hypertension Management Pipeline

**Author:** Romario Joseph, MPH (BU SPH, Epidemiology & Biostatistics)
**Stack:** SQL (PostgreSQL), R 4.x, tidyverse, Quarto, Tableau-ready outputs
**Data:** 100% synthetic EHR records, generated to match Epic Clarity / Caboodle schemas. No PHI.

I built this repository to mirror the EHR analytics workflow I run in production at the Massachusetts Department of Public Health and, before that, at the Broad Institute. The whole thing runs on synthetic data so anyone can clone it and reproduce the KPIs without an access agreement.

## Epidemiological Objective

The question I am trying to answer is the one that drives most of my day job: among adults seen in primary care, what share have uncontrolled hypertension (BP at or above 140/90), and where are the follow-up gaps? Uncontrolled hypertension is the largest modifiable contributor to cardiovascular mortality in the United States, and the disparities in control rates across race, ethnicity, language, and insurance status are persistent enough that any pipeline I build has to surface them by default rather than as an afterthought.

I designed the pipeline around four linked questions:

1. HTN prevalence: what fraction of the adult primary-care panel meets a validated hypertension phenotype?
2. Control rate: among phenotyped HTN patients, what share have a most recent BP under 140/90?
3. Follow-up gap: among patients with an uncontrolled reading, what share have no documented BP recheck within 90 days?
4. Equity index: what is the control-rate ratio between the lowest and highest performing demographic stratum (age, sex, race/ethnicity, insurance, preferred language)?

Together these four KPIs are essentially a reimplementation of the CMS Controlling High Blood Pressure (CBP) quality measure, with the equity layer added on top.

## Methodological Framework

I built this as a deterministic, rule-based electronic phenotyping workflow. The logic is grounded in the eMERGE Network's algorithmic phenotyping tradition and the CMS CBP measure specification, and I tried to keep the methodological choices visible rather than buried in the code.

For the phenotype itself I use a Boolean rule set: a patient is hypertensive if they have at least one ICD-10 code in {I10, I11.x, I12.x, I13.x, I15.x, I16.x} on a qualifying encounter, OR at least two outpatient BP readings with SBP at or above 140 mmHg or DBP at or above 90 mmHg, taken on distinct encounter dates within a 24-month rolling window. The two-reading requirement on distinct dates is deliberate, because it is the cleanest way I know to guard against single-visit white-coat misclassification, and it lines up with the 2017 ACC/AHA guideline.

Control status is a binary outcome. I code a patient as "controlled" when their most recent BP in the prior 12 months has SBP under 140 and DBP under 90, and "uncontrolled" otherwise. The follow-up gap is just an uncontrolled reading without any subsequent BP measurement within 90 days.

For the equity layer I compute control rates and 95% Wilson confidence intervals within strata of age band, sex, race/ethnicity (OMB categories), insurance class, and preferred language. The headline statistic is the control-rate ratio between the lowest and highest performing stratum, which is the same idea as the rate ratios used in the CMS Health Equity Index. I use Wilson intervals rather than asymptotic normal intervals because demographic cells get small fast in a real primary-care panel, and the normal approximation pathologizes when the cell counts drop.

## Data Architecture

I structured the pipeline as a SQL to R to Quarto directed acyclic graph, with each node owning a single transformation. That separation is what lets the same code base run against a real Epic Clarity warehouse without rewriting the downstream logic.

**Stage 0, schema construction (`sql/00_schema.sql`).** A PostgreSQL schema that mirrors the relevant Epic Clarity / Caboodle tables: patient, encounter, vitals, dx, meds, lab. I declare primary and foreign keys explicitly so any referential integrity error surfaces immediately rather than propagating downstream.

**Stage 1, cohort extraction (`sql/01_extract_cohort.sql`, `sql/02_extract_bp.sql`).** I extract the adult primary-care cohort (age at least 18 at index encounter, at least one primary-care visit in the lookback window) and, separately, the longitudinal BP series (latest reading plus a trailing 24-month history per patient). I push the join down to SQL deliberately, because keeping the R-side memory footprint bounded is what makes the pipeline survive a warehouse-scale deployment.

**Stage 2, ingest (`R/01_extract.R`).** Connects via `DBI` and `RPostgres`, pulls into tibbles, and writes a typed manifest of row counts and primary-key uniqueness checks. Any deviation halts the pipeline.

**Stage 3, cleaning and plausibility validation (`R/02_clean_validate.R`).** This is where I do the data-engineering work that separates a publishable EHR pipeline from a brittle script.

For unit harmonization, I coerce BP readings to mmHg and unit-check lab values against LOINC reference ranges. For plausibility filtering, I flag readings outside physiologic bounds (SBP under 70 or above 250 mmHg, DBP under 40 or above 150 mmHg) as implausible and exclude them from phenotype determination, but I keep them in an audit table so the exclusion rate is reportable.

For duplicate clinic visits, I deduplicate encounters that share `(patient_id, encounter_date, encounter_type)` by keeping the record with the most complete vitals payload (fewest NA fields), breaking ties by the latest `encounter_datetime`. That prevents double-counting from registration re-checks, which is a real and surprisingly common issue in Epic data.

For outliers I use a within-patient Tukey fence (1.5 times the IQR around the patient's own median) and winsorize at the fence rather than dropping. Winsorizing preserves the sample size while still attenuating the kind of typographic data-entry errors you see in real EHR vitals. I report the winsorization rate per stratum so a reviewer can confirm the procedure does not differentially affect any subgroup.

For missing data I tried to be explicit rather than imputing silently. For demographics, missing race/ethnicity is retained as an "Unknown" stratum and reported separately, never collapsed into a reference category. For the BP series, patients with zero plausible outpatient readings in the 24-month window are coded as "phenotype-indeterminate" and excluded from the denominator, with the exclusion count surfaced as a measure-validity diagnostic. For ICD-10 codes, absence is treated as a true negative only when the patient has at least one qualifying primary-care encounter in the window; otherwise the patient is censored from the cohort. That is the eMERGE "case / control / indeterminate" trichotomy, and the reason I use it is that complete-case analysis silently biases EHR studies in ways that are hard to detect after the fact.

**Stage 4, phenotype application (`R/03_htn_phenotype.R`).** Applies the Boolean rule set above, but reports the ICD-only arm and the BP-only arm separately so reviewers can see the contribution of each. This also makes it trivial to re-run a sensitivity analysis at the 130/80 ACC/AHA stage 1 threshold.

**Stage 5, KPI emission (`R/04_kpi_dashboard.R`).** Emits four Tableau-ready CSVs (`kpi_prevalence`, `kpi_control`, `kpi_gap`, `kpi_equity`), each with stratum keys, point estimates, and Wilson 95% CIs.

**Stage 6, reporting (`reports/htn_kpi_report.qmd`).** A Quarto document that renders a single-page clinician-facing dashboard from the KPI tables.

```
ehr-hypertension-pipeline/
├── README.md
├── sql/
│   ├── 00_schema.sql             # Epic-like tables (patient, encounter, vitals, dx, meds)
│   ├── 01_extract_cohort.sql     # adult primary-care cohort
│   └── 02_extract_bp.sql         # latest + trailing BP per patient
├── R/
│   ├── 01_extract.R              # connect + pull SQL into tibbles
│   ├── 02_clean_validate.R       # unit checks, plausibility, dedup, winsorization
│   ├── 03_htn_phenotype.R        # phenotype + control logic
│   └── 04_kpi_dashboard.R        # KPI tables for Tableau
├── data/
│   ├── synthetic/                # generated CSVs (committed)
│   └── README.md
├── reports/
│   └── htn_kpi_report.qmd        # Quarto report
└── LICENSE
```

## KPIs produced

| KPI | Definition | Tableau field |
|-----|------------|---------------|
| HTN prevalence | n_htn / n_adults | `kpi_prevalence` |
| Control rate | n_controlled / n_htn | `kpi_control` |
| Follow-up gap | n_gap / n_uncontrolled | `kpi_gap` |
| Equity index | control rate ratio (lowest vs highest stratum) | `kpi_equity` |

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

## Why this matters

At scale (70+ provider networks at MA DPH, multi-site recruitment at the Broad Institute), these four KPIs become a real-world-evidence backbone for primary-care quality improvement. The same pattern (SQL extract, R phenotype, KPI table, dashboard) is reusable for diabetes (HbA1c), CKD (eGFR), and any other chronic condition with a defined control threshold.

## Disclaimer

All data in this repo is synthetic. No real patient information is included. Not for clinical use.

## Contact

Romario Joseph, rjoseph3@bu.edu, [LinkedIn](https://www.linkedin.com/in/romariojosephpublichealth/)
