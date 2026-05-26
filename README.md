# Epic EHR → Hypertension Management Pipeline

**Author:** Romario Joseph, MPH · BU SPH (Epidemiology & Biostatistics)
**Stack:** SQL (PostgreSQL) · R 4.x · tidyverse · Quarto · Tableau-ready outputs
**Data:** 100% **synthetic** EHR records generated to match Epic Clarity / Caboodle schemas. No PHI.

---

## What this is
A portable, end-to-end pipeline that mirrors the EHR analytics workflows I built at the Broad Institute and now at the Massachusetts Department of Public Health: pull structured records from an Epic-like schema, clean and validate them, apply USPSTF/AHA hypertension management logic, and produce a clinician-facing KPI dashboard.

The whole pipeline runs on synthetic data so the repo is fully reproducible without any access agreement.

---

## The clinical question
> Among adults seen in primary care, **what share have uncontrolled hypertension (BP ≥ 140/90), and where are the gaps in follow-up?**
>
> The pipeline answers four KPIs that map directly to CMS Stars / HEDIS CBP:
> 1. **HTN prevalence** (ICD-10 I10–I16 or two BP readings ≥ 140/90)
> 2. 2. **Control rate** among patients with HTN (last BP < 140/90)
>    3. 3. **Follow-up gap** (no BP recheck within 90 days of an uncontrolled reading)
>       4. 4. **Equity stratification** by age, sex, race/ethnicity, insurance, and language
>         
>          5. ---
>         
>          6. ## Pipeline
>          7. ```
>               Epic-like Postgres                 R / tidyverse                Outputs
> ┌────────────────────┐      ┌────────────────────┐    ┌─────────────────┐
> │ patient, encounter,  │ →    │ 01_extract_sql.R   │ →  │ KPI tables       │
> │ vitals, dx, meds,   │      │ 02_clean_validate  │    │ (Tableau-ready)  │
> │ lab tables          │      │ 03_htn_phenotype   │    │ Quarto report    │
> └────────────────────┘      │ 04_kpi_dashboard   │    │ Decision support │
>                             └────────────────────┘    └─────────────────┘
> ```
>
> ## Repository structure
> ```
> ehr-hypertension-pipeline/
> ├── README.md
> ├── sql/
> │   ├── 00_schema.sql          ← Epic-like tables (patient, encounter, vitals, dx, meds)
> │   ├── 01_extract_cohort.sql  ← adult primary-care cohort
> │   └── 02_extract_bp.sql      ← latest + trailing BP per patient
> ├── R/
> │   ├── 01_extract.R           ← connect + pull SQL into tibbles
> │   ├── 02_clean_validate.R    ← unit checks, plausibility filters
> │   ├── 03_htn_phenotype.R     ← phenotype + control logic
> │   └── 04_kpi_dashboard.R     ← KPI tables for Tableau
> ├── data/
> │   ├── synthetic/             ← generated CSVs (committed)
> │   └── README.md
> ├── reports/
> │   └── htn_kpi_report.qmd     ← Quarto report
> └── LICENSE
> ```
>
> ## Phenotype logic
> ```
> HTN = (
>   ≥ 1 ICD-10 in {I10, I11.x, I12.x, I13.x, I15.x, I16.x}
>   OR
>   ≥ 2 outpatient BP readings with SBP ≥ 140 OR DBP ≥ 90,
>   taken on separate encounter dates within 24 months
> )
>
> Controlled = last BP within prior 12 months has SBP < 140 AND DBP < 90
> Follow-up gap = uncontrolled reading without any BP recheck within 90 days
> ```
> Mirrors the CMS CBP (Controlling High Blood Pressure) measure and 2017 ACC/AHA thresholds.
>
> ## KPIs produced
> | KPI | Definition | Tableau field |
> |-----|-----------|---------------|
> | HTN prevalence | n_htn / n_adults | `kpi_prevalence` |
> | Control rate | n_controlled / n_htn | `kpi_control` |
> | Follow-up gap | n_gap / n_uncontrolled | `kpi_gap` |
> | Equity index | control rate ratio (lowest vs highest stratum) | `kpi_equity` |
>
> ## Reproduce
> ```bash
> # 1. Spin up a local Postgres + load the synthetic schema
> psql -f sql/00_schema.sql
> psql -f data/synthetic/load_synthetic.sql
>
> # 2. Run the R pipeline
> Rscript R/01_extract.R
> Rscript R/02_clean_validate.R
> Rscript R/03_htn_phenotype.R
> Rscript R/04_kpi_dashboard.R
>
> # 3. Render the report
> quarto render reports/htn_kpi_report.qmd
> ```
>
> ## Why this matters
> At scale (70+ provider networks at MA DPH, multi-site recruitment at Broad), the same four KPIs become a real-world-evidence backbone for primary-care quality improvement. The pipeline pattern — SQL extract → R phenotype → KPI table → dashboard — is reusable for diabetes (HbA1c), CKD (eGFR), and any other chronic condition with a defined control threshold.
>
> ## Disclaimer
> All data in this repo is synthetic. No real patient information is included. Not for clinical use.
>
> ## Contact
> **Romario Joseph** · rjoseph3@bu.edu · [LinkedIn](https://www.linkedin.com/in/romariojosephpublichealth/)
> 
