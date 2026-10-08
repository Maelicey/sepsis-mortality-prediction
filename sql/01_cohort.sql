-- =============================================================
-- MIMIC-IV Sepsis Mortality Project
-- Phase 1: Building the cohort
-- Data: MIMIC-IV v3.1 on BigQuery (physionet-data)
-- My dataset: mimic-project-510003.Sepsis_project (location: US)
-- Run the queries in order. Each CREATE query builds one table.
-- =============================================================


-- -------------------------------------------------------------
-- STEP 1: Base cohort
-- Adults (18+), first ICU stay only, with in-hospital death label
-- Result: 65,366 stays, 10.8% mortality
-- -------------------------------------------------------------
CREATE OR REPLACE TABLE `mimic-project-510003.Sepsis_project.cohort_base` AS
WITH first_icu AS (
  SELECT
    subject_id, hadm_id, stay_id, intime, outtime, los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS icu_seq
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT
  f.subject_id, f.hadm_id, f.stay_id, f.intime, f.outtime,
  f.los AS icu_los_days,
  p.gender,
  p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
  a.admission_type, a.race, a.insurance,
  a.hospital_expire_flag AS died_in_hospital
FROM first_icu f
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON f.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.hadm_id = a.hadm_id
WHERE f.icu_seq = 1
  AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) >= 18;

-- Check
SELECT COUNT(*) AS n_stays, AVG(died_in_hospital) AS mortality_rate
FROM `mimic-project-510003.Sepsis_project.cohort_base`;


-- -------------------------------------------------------------
-- STEP 2: Add the Sepsis-3 flag
-- LEFT JOIN keeps every patient; COALESCE turns missing into FALSE
-- Result: 65,366 stays (no duplicates), 22,506 septic, 15.3% mortality
-- -------------------------------------------------------------
CREATE OR REPLACE TABLE `mimic-project-510003.Sepsis_project.cohort_sepsis` AS
SELECT
  c.*,
  COALESCE(s.sepsis3, FALSE) AS sepsis3,
  s.suspected_infection_time,
  s.sofa_score
FROM `mimic-project-510003.Sepsis_project.cohort_base` c
LEFT JOIN `physionet-data.mimiciv_3_1_derived.sepsis3` s
  ON c.stay_id = s.stay_id;

-- Check
SELECT
  COUNT(*) AS n_stays,
  COUNTIF(sepsis3) AS n_sepsis,
  AVG(IF(sepsis3, died_in_hospital, NULL)) AS sepsis_mortality
FROM `mimic-project-510003.Sepsis_project.cohort_sepsis`;

-- Check: how many were septic within 24h of ICU admission?
-- Result: 20,963 of 22,506 (93%)
SELECT
  COUNT(*) AS n_stays,
  COUNTIF(sepsis3) AS n_sepsis,
  COUNTIF(sepsis3 AND suspected_infection_time <= DATETIME_ADD(intime, INTERVAL 24 HOUR)) AS n_sepsis_24h
FROM `mimic-project-510003.Sepsis_project.cohort_sepsis`;


-- -------------------------------------------------------------
-- STEP 3: Final cohort
-- Only patients septic within the first 24h of ICU (avoids data leakage)
-- Expected: 20,963 stays
-- -------------------------------------------------------------
CREATE OR REPLACE TABLE `mimic-project-510003.Sepsis_project.cohort_final` AS
SELECT *
FROM `mimic-project-510003.Sepsis_project.cohort_sepsis`
WHERE sepsis3 AND suspected_infection_time <= DATETIME_ADD(intime, INTERVAL 24 HOUR);

-- Check
-- Result: 20,963 stays, 15.0% mortality
SELECT COUNT(*) AS n_stays, AVG(died_in_hospital) AS mortality_rate
FROM `mimic-project-510003.Sepsis_project.cohort_final`;
