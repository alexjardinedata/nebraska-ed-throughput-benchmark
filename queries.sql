-- ============================================================
-- Lincoln ED Throughput Benchmark — BigQuery SQL
-- CMS Public Hospital Quality Data (Nebraska subset)
-- Analyst: Alex Jardine
-- Source: CMS Provider Data Catalog
--   - Timely and Effective Care – Hospital (dataset yv7e-xc69)
--   - Hospital General Information
-- Tool: Google BigQuery (sandbox)
-- ------------------------------------------------------------
-- Reproduces the Power Query / Power BI pipeline in SQL to
-- validate results across two independent tools. Both engines
-- return the same answer: Bryan 117, St. Elizabeth 162,
-- NE acute-care benchmark 141.6.
--
-- Run order: 01 inspect -> 02 build fact -> 03 build dim ->
--            04 validation -> 05 currency -> 06 benchmark
-- Replace the project/dataset path if running in your own env:
--   my-project-48398-bh-interview.Bryan_ED_Benchmark
-- ============================================================


-- ============================================================
-- QUERY 1: Inspect raw schema
-- Question: What column names and types did the CSV load produce?
-- Concepts: INFORMATION_SCHEMA.COLUMNS
-- Note: Column name character map V2 sanitizes slashed headers
--       (City/Town -> City_Town). Spaced names are kept and must
--       be wrapped in backticks. Facility ID auto-typed STRING,
--       which preserves the leading-zero CCN join key.
-- ============================================================

SELECT column_name, data_type
FROM `my-project-48398-bh-interview.Bryan_ED_Benchmark.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'timely_care_raw';


-- ============================================================
-- QUERY 2: Build the cleaned fact table
-- Question: How do we turn the raw measures file into a typed,
--           analysis-ready fact table?
-- Concepts: CREATE TABLE AS, SAFE_CAST, CASE, TRIM, LOWER
-- Note: SAFE_CAST collapses three Power Query steps (null
--       "Not Available" -> change type -> replace errors -> null)
--       into one — non-numeric values return null instead of
--       failing the query. Trims only match/filter/group columns.
-- ============================================================

CREATE OR REPLACE TABLE `my-project-48398-bh-interview.Bryan_ED_Benchmark.timely_care_clean` AS
SELECT
  TRIM(`Facility ID`)                                    AS facility_id,    -- join key, trimmed at source
  `Facility Name`                                        AS facility_name,  -- display only, not trimmed
  TRIM(State)                                            AS state,          -- filter column
  TRIM(`Measure ID`)                                     AS measure_id,     -- filter column
  `Measure Name`                                         AS measure_name,   -- display only, not trimmed
  SAFE_CAST(Score AS FLOAT64)                            AS score_numeric,  -- "Not Available"/text -> null
  CASE WHEN TRIM(LOWER(Score)) IN ('low','medium','high','very high')
       THEN TRIM(LOWER(Score)) END                       AS score_category, -- volume class, grouping field
  CASE WHEN Footnote IS NULL OR TRIM(Footnote) = ''
       THEN 'Reported' ELSE 'Suppressed/Low Sample' END  AS data_status,    -- matches dashboard labels
  `Start Date`                                           AS start_date,
  `End Date`                                             AS end_date
FROM `my-project-48398-bh-interview.Bryan_ED_Benchmark.timely_care_raw`
WHERE TRIM(State) = 'NE';


-- ============================================================
-- QUERY 3: Build the clean hospital dimension
-- Question: How do we classify each NE hospital (network, type)?
-- Concepts: CREATE TABLE AS, SELECT DISTINCT, CASE, TRIM
-- Note: Built from hospital_info_raw so it carries the real
--       Hospital Type column (acute vs critical-access) rather
--       than deriving it from the CCN. SELECT DISTINCT enforces
--       key uniqueness (the 1-side of the relationship).
-- ============================================================

CREATE OR REPLACE TABLE `my-project-48398-bh-interview.Bryan_ED_Benchmark.hospital_info_clean` AS
SELECT DISTINCT
  TRIM(`Facility ID`)                                    AS facility_id,    -- join key, trimmed at source
  `Facility Name`                                        AS facility_name,  -- display only
  TRIM(`Hospital Type`)                                  AS hospital_type,  -- grouping/filter field
  CASE
    WHEN TRIM(`Facility ID`) IN ('280003','280134','280139','281354','281328') THEN 'Bryan Health Network'
    WHEN TRIM(`Facility ID`) = '280020' THEN 'Lincoln Competitor'
    ELSE 'Other Nebraska'
  END AS org_group
FROM `my-project-48398-bh-interview.Bryan_ED_Benchmark.hospital_info_raw`
WHERE TRIM(State) = 'NE';


-- ============================================================
-- QUERY 4: Validation — duplicate keys and target classification
-- Question: Is the dimension key unique, and do the six target
--           facilities classify correctly?
-- Concepts: GROUP BY / HAVING, WHERE, ORDER BY
-- Finding: Duplicate check returns zero rows. All six facilities
--          resolve: Bryan/Grand Island/Kearney = Acute Care,
--          Crete/Merrick = Critical Access, St. Elizabeth = Acute.
-- ============================================================

-- 4a. No duplicate keys (1-side of relationship requirement)
SELECT facility_id, COUNT(*) AS n
FROM `my-project-48398-bh-interview.Bryan_ED_Benchmark.hospital_info_clean`
GROUP BY facility_id
HAVING COUNT(*) > 1;

-- 4b. Target facilities resolve and classify correctly
SELECT facility_id, facility_name, org_group, hospital_type
FROM `my-project-48398-bh-interview.Bryan_ED_Benchmark.hospital_info_clean`
WHERE org_group IN ('Bryan Health Network','Lincoln Competitor')
ORDER BY org_group, facility_id;


-- ============================================================
-- QUERY 5: Data-currency check
-- Question: What measurement period does the published data cover?
-- Concepts: MIN/MAX on dates, GROUP BY
-- Finding: OP_18b = 2024-07-01 to 2025-06-30 (12-month window);
--          OP_22 = 2024-01-01 to 2024-12-31 (calendar year).
--          Public hospital-quality data lags ~12 months by design.
-- ============================================================

SELECT measure_id, MIN(start_date) AS period_start, MAX(end_date) AS period_end
FROM `my-project-48398-bh-interview.Bryan_ED_Benchmark.timely_care_clean`
WHERE measure_id IN ('OP_18b','OP_22')
GROUP BY measure_id;


-- ============================================================
-- QUERY 6: Benchmark analysis (the payoff)
-- Question: Does Bryan's network beat its Lincoln competitor and
--           the Nebraska acute-care benchmark for ED throughput?
-- Concepts: CTEs, JOIN, filtered aggregate, CROSS JOIN to a
--           one-row scalar, RANK() window function
-- Note: The benchmark (acute_avg) excludes both Lincoln hospitals
--       (org_group = 'Other Nebraska') — benchmarking a facility
--       against a pool containing itself is circular. This matches
--       the Power BI subtotal exactly (141.6).
-- Finding: Bryan Medical Center 117 vs CHI St. Elizabeth 162 — a
--          45-minute (~28%) gap. All Bryan acute facilities beat
--          the 141.6 benchmark; St. Elizabeth is +20.4 above it.
-- ============================================================

WITH ed_times AS (
  SELECT
    f.facility_id, f.facility_name, f.score_numeric,
    h.org_group, h.hospital_type
  FROM `my-project-48398-bh-interview.Bryan_ED_Benchmark.timely_care_clean` f
  JOIN `my-project-48398-bh-interview.Bryan_ED_Benchmark.hospital_info_clean` h
    ON f.facility_id = h.facility_id          -- both keys trimmed at source; no TRIM needed here
  WHERE f.measure_id = 'OP_18b' AND f.score_numeric IS NOT NULL
),
acute_avg AS (
  SELECT AVG(score_numeric) AS ne_acute_avg
  FROM ed_times
  WHERE hospital_type = 'Acute Care Hospitals'
    AND org_group = 'Other Nebraska'          -- exclude Bryan + St. E, matching the dashboard subtotal
)
SELECT
  e.facility_name,
  e.org_group,
  e.hospital_type,
  e.score_numeric                              AS median_ed_minutes,
  ROUND(a.ne_acute_avg, 1)                     AS ne_acute_benchmark,
  ROUND(e.score_numeric - a.ne_acute_avg, 1)   AS vs_benchmark,
  RANK() OVER (ORDER BY e.score_numeric)       AS speed_rank
FROM ed_times e CROSS JOIN acute_avg a
WHERE e.org_group IN ('Bryan Health Network','Lincoln Competitor')
ORDER BY e.score_numeric;


-- ============================================================
-- QUERY 7: Descriptive statistics — acute-hospital ED distribution
-- Question: How is ED throughput distributed across Nebraska
--           acute-care hospitals, and is the distribution skewed?
-- Concepts: AVG, STDDEV_SAMP, APPROX_QUANTILES (median, Q1, Q3, IQR),
--           MIN/MAX, COUNT
-- Note: Unit of analysis is the per-hospital published median
--       (OP_18b), not patient-level data — every stat describes
--       spread ACROSS hospitals. Population here is ALL acute EDs
--       (includes Bryan + St. Elizabeth) because this DESCRIBES the
--       distribution they belong to — distinct from the benchmark
--       in Query 6, which EXCLUDES them to avoid circular comparison.
-- Finding: n=21, mean 138.0 > median 132.0 and slowest (246) sits
--          far past Q3 (156) — the distribution is right-skewed.
--          Because of the skew, IQR (39.0; Q1 117 to Q3 156) is the
--          honest spread measure, not SD (36.5). Bryan Medical Center
--          at 117 sits exactly at Q1 — the 25th-percentile boundary.
-- ============================================================

WITH acute AS (
  SELECT f.facility_id, f.facility_name, f.score_numeric AS median_min, h.org_group
  FROM `my-project-48398-bh-interview.Bryan_ED_Benchmark.timely_care_clean` f
  JOIN `my-project-48398-bh-interview.Bryan_ED_Benchmark.hospital_info_clean` h
    ON f.facility_id = h.facility_id
  WHERE f.measure_id = 'OP_18b'
    AND f.score_numeric IS NOT NULL
    AND h.hospital_type = 'Acute Care Hospitals'
)
SELECT
  COUNT(*)                                              AS n_acute_hospitals,
  ROUND(AVG(median_min), 1)                             AS mean_min,
  ROUND(APPROX_QUANTILES(median_min, 2)[OFFSET(1)], 1) AS median_of_medians,
  ROUND(STDDEV_SAMP(median_min), 1)                     AS sd_min,
  ROUND(APPROX_QUANTILES(median_min, 4)[OFFSET(1)], 1) AS q1_min,
  ROUND(APPROX_QUANTILES(median_min, 4)[OFFSET(3)], 1) AS q3_min,
  ROUND(APPROX_QUANTILES(median_min, 4)[OFFSET(3)]
      - APPROX_QUANTILES(median_min, 4)[OFFSET(1)], 1)  AS iqr_min,
  MIN(median_min)                                       AS fastest,
  MAX(median_min)                                       AS slowest,
  ROUND(MAX(median_min) - MIN(median_min), 1)           AS range_min
FROM acute;


-- ============================================================
-- QUERY 8: Percentile and z-score — Lincoln hospitals in context
-- Question: Where do the Lincoln-area hospitals fall within the
--           distribution of Nebraska acute EDs?
-- Concepts: window aggregates with empty OVER () to broadcast the
--           overall mean/SD to every row; PERCENT_RANK window
--           function (DESC so faster = higher percentile)
-- Note: PERCENT_RANK uses ORDER BY median_min DESC so that FASTER
--       hospitals score HIGHER — aligns the number with "better"
--       for a non-technical reader. z_score retained for reference
--       but NOT reported in audience-facing materials: n<30 and the
--       distribution is right-skewed (Query 7), so a percentile is
--       the honest, assumption-free statistic. Population = all acute
--       EDs (same as Query 7), so positioning describes the true
--       distribution each hospital belongs to.
-- Finding: Bryan Medical Center = 75th percentile for speed (faster
--          than 75% of NE acute EDs); Grand Island 85th, Kearney 80th.
--          CHI St. Elizabeth = 15th percentile.
-- ============================================================

WITH acute AS (
  SELECT f.facility_id, f.facility_name, f.score_numeric AS median_min, h.org_group
  FROM `my-project-48398-bh-interview.Bryan_ED_Benchmark.timely_care_clean` f
  JOIN `my-project-48398-bh-interview.Bryan_ED_Benchmark.hospital_info_clean` h
    ON f.facility_id = h.facility_id
  WHERE f.measure_id = 'OP_18b'
    AND f.score_numeric IS NOT NULL
    AND h.hospital_type = 'Acute Care Hospitals'
),
scored AS (
  SELECT
    facility_name, org_group, median_min,
    ROUND((median_min - AVG(median_min) OVER ()) / STDDEV_SAMP(median_min) OVER (), 2) AS z_score,
    ROUND(PERCENT_RANK() OVER (ORDER BY median_min DESC) * 100, 0)                     AS pct_faster_than
  FROM acute
)
SELECT *
FROM scored
WHERE org_group IN ('Bryan Health Network','Lincoln Competitor')
ORDER BY median_min;
