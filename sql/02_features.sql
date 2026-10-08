-- =============================================================
-- MIMIC-IV Sepsis Mortality Project
-- Phase 2: Building the feature table
-- Data: MIMIC-IV v3.1 on BigQuery (physionet-data)
-- My dataset: mimic-project-510003.Sepsis_project (location: US)
-- Builds on: cohort_final (01_cohort.sql)
-- =============================================================


-- -------------------------------------------------------------
-- STEP 4: Feature table
-- One row per patient: cohort_final + first-day vitals, labs, lactate
-- Vitals: min and max (in sepsis, the extremes matter most)
-- Labs: the dangerous direction for each (e.g. low platelets, high creatinine)
-- Flags: bilirubin and lactate are often not measured (informative missingness)
-- All joins on stay_id (each first_day table has one row per ICU stay)
-- Result: 20,963 rows | bilirubin measured 59.4% | lactate measured 72.8%
-- -------------------------------------------------------------
CREATE OR REPLACE TABLE `mimic-project-510003.Sepsis_project.cohort_features` AS
SELECT
  c.*,

  -- Vital signs (first day)
  v.heart_rate_min,  v.heart_rate_max,
  v.sbp_min,         v.sbp_max,
  v.dbp_min,         v.dbp_max,
  v.mbp_min,         v.mbp_max,
  v.resp_rate_min,   v.resp_rate_max,
  v.temperature_min, v.temperature_max,
  v.spo2_min,        v.spo2_max,
  v.glucose_min,     v.glucose_max,

  -- Labs (first day)
  l.wbc_min, l.wbc_max,
  l.hemoglobin_min,
  l.platelets_min,
  l.creatinine_max,
  l.bilirubin_total_max,
  l.bun_max,
  l.bicarbonate_min,

  -- Blood gas (first day)
  b.lactate_max,

  -- "Was it measured?" flags (1 = yes, 0 = no)
  IF(l.bilirubin_total_max IS NOT NULL, 1, 0) AS has_bilirubin,
  IF(b.lactate_max IS NOT NULL, 1, 0) AS has_lactate

FROM `mimic-project-510003.Sepsis_project.cohort_final` c
LEFT JOIN `physionet-data.mimiciv_3_1_derived.first_day_vitalsign` v ON c.stay_id = v.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_derived.first_day_lab` l       ON c.stay_id = l.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_derived.first_day_bg` b        ON c.stay_id = b.stay_id;

-- Check: row count must stay 20,963; average of a 0/1 flag = % measured
-- Result: 20,963 | 0.594 | 0.728
SELECT
  COUNT(*) AS n_stays,
  AVG(has_bilirubin) AS pct_bilirubin,
  AVG(has_lactate) AS pct_lactate
FROM `mimic-project-510003.Sepsis_project.cohort_features`;
