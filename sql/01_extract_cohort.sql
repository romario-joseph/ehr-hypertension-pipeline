-- 01_extract_cohort.sql
-- Adults (>=18) with at least one outpatient primary-care visit in the last 24 months.
-- Output one row per patient with demographics for stratification.

WITH adults AS (
    SELECT
      p.patient_id,
      p.birth_date,
      DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age,
      p.sex,
      p.race,
      p.ethnicity,
      p.preferred_language,
      p.insurance_primary
    FROM ehr.patient p
    WHERE p.deceased_date IS NULL
      AND p.birth_date <= CURRENT_DATE - INTERVAL '18 years'
  ),
recent_pcp AS (
    SELECT DISTINCT e.patient_id
    FROM ehr.encounter e
    WHERE e.enc_type = 'OUTPATIENT'
      AND e.department ILIKE '%primary care%'
      AND e.enc_date >= CURRENT_DATE - INTERVAL '24 months'
  )
SELECT a.*
FROM adults a
JOIN recent_pcp r USING (patient_id);
