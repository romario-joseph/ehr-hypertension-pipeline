-- 00_schema.sql
-- Minimal Epic-like schema for the EHR Hypertension Pipeline
-- Models the subset of Clarity/Caboodle tables relevant to BP management.
-- All data loaded into this schema is SYNTHETIC.

DROP SCHEMA IF EXISTS ehr CASCADE;
CREATE SCHEMA ehr;

CREATE TABLE ehr.patient (
      patient_id        BIGINT PRIMARY KEY,
      birth_date        DATE        NOT NULL,
      sex               TEXT        CHECK (sex IN ('F','M','X','U')),
      race              TEXT,
      ethnicity         TEXT,
      preferred_language TEXT,
      insurance_primary TEXT,
      deceased_date     DATE
  );

CREATE TABLE ehr.encounter (
      encounter_id      BIGINT PRIMARY KEY,
      patient_id        BIGINT REFERENCES ehr.patient(patient_id),
      enc_date          DATE        NOT NULL,
      enc_type          TEXT        CHECK (enc_type IN ('OUTPATIENT','INPATIENT','ED','TELEHEALTH')),
      department        TEXT,
      provider_id       BIGINT
  );

CREATE TABLE ehr.vitals (
      vital_id          BIGSERIAL PRIMARY KEY,
      encounter_id      BIGINT REFERENCES ehr.encounter(encounter_id),
      patient_id        BIGINT REFERENCES ehr.patient(patient_id),
      measured_at       TIMESTAMP NOT NULL,
      sbp_mmhg          INT,
      dbp_mmhg          INT,
      pulse_bpm         INT,
      bmi               NUMERIC(4,1)
  );

CREATE TABLE ehr.diagnosis (
      dx_id             BIGSERIAL PRIMARY KEY,
      encounter_id      BIGINT REFERENCES ehr.encounter(encounter_id),
      patient_id        BIGINT REFERENCES ehr.patient(patient_id),
      icd10             TEXT NOT NULL,
      dx_date           DATE NOT NULL,
      is_primary        BOOLEAN DEFAULT FALSE
  );

CREATE TABLE ehr.medication (
      med_id            BIGSERIAL PRIMARY KEY,
      patient_id        BIGINT REFERENCES ehr.patient(patient_id),
      rxnorm            TEXT,
      med_class         TEXT,    -- e.g. ACEI, ARB, CCB, THIAZIDE, BB
    start_date        DATE,
      end_date          DATE
  );

CREATE INDEX idx_vitals_pt_date ON ehr.vitals (patient_id, measured_at);
CREATE INDEX idx_dx_icd ON ehr.diagnosis (icd10);
CREATE INDEX idx_enc_pt_date ON ehr.encounter (patient_id, enc_date);
