# BigQuery SQL Cleaning Changelog

**Project:** Lincoln ED Throughput Benchmark
**Purpose:** Reproduce the Power Query pipeline (see `CHANGELOG_PowerQuery.md`) in BigQuery to validate results across two independent tools.
**Dataset:** `Bryan_ED_Benchmark` (BigQuery sandbox)
**Result:** Identical to the Power BI dashboard — Bryan 117, St. Elizabeth 162, benchmark 141.6.

---

## 01 — Raw load

- Loaded both CSVs via console upload → `timely_care_raw`, `hospital_info_raw`.
- Settings: auto-detect schema; **Column name character map V2** (sanitizes slashed headers, e.g. `City/Town` → `City_Town`, instead of failing the load); **Header rows to skip = 1**.
- `Facility ID` auto-typed as STRING — leading zeros preserved automatically (no manual fix needed, unlike Power Query).
- Column names retained spaces; referenced with backticks (`` `Facility ID` ``).

---

## 02 — `timely_care_clean` (mirrors FactMeasures)

- **score_numeric:** `SAFE_CAST(Score AS FLOAT64)`
  - *Collapses three Power Query steps — null "Not Available" → change type → replace errors → null — into one. `SAFE_CAST` returns null for any non-numeric value instead of throwing an error that would fail the whole query.*
- **score_category:** `CASE WHEN TRIM(LOWER(Score)) IN ('low','medium','high','very high') THEN TRIM(LOWER(Score)) END`
  - *`LOWER` normalizes case and `TRIM` strips whitespace before matching (defends against inconsistent source formatting); non-matching values → null.*
- **data_status:** `CASE WHEN Footnote IS NULL OR TRIM(Footnote) = '' THEN 'Reported' ELSE 'Suppressed/Low Sample' END`
  - *Matches the dashboard labels exactly.*
- **Trim match/key columns:** `TRIM` applied to `Facility ID` (join key), `Measure ID` and `State` (filter columns), and `Score_Category` (grouping field).
  - *Mirrors the Power Query trim step. Trims only columns used for joining, filtering, or grouping — display-only columns (Facility Name, Measure Name) left alone. Trimming the join key at source means downstream joins compare clean keys with no join-time TRIM.*
- Carried `Start Date` / `End Date` for the data-currency check.
- `WHERE TRIM(State) = 'NE'` — trim in the filter too, so the filter and the stored value stay coherent.

---

## 03 — `hospital_info_clean` (mirrors DimHospital)

- Built from `hospital_info_raw`, **not** from the fact table — this carries the real `Hospital Type` column used for the acute / critical-access split (not a value derived from the CCN pattern).
- **Trim match/key columns:** `TRIM` on `Facility ID` (join key) and `Hospital Type` (grouping/filter field used for the benchmark population). Mirrors the Power Query trims.
- **org_group** via `CASE` on the (trimmed) CCN — same mapping as Power Query (Bryan network CCNs / 280020 / else).
- `SELECT DISTINCT` enforces key uniqueness — mirrors Remove Duplicates.
- `WHERE TRIM(State) = 'NE'`.

---

## 04 — Validation

- **Duplicate-key check:** `GROUP BY facility_id HAVING COUNT(*) > 1` → returned zero rows.
  - *Window-function alternatives also valid: `COUNT(*) OVER (PARTITION BY facility_id)` to flag, or `ROW_NUMBER() OVER (PARTITION BY facility_id)` to dedupe (keep `rn = 1`). GROUP BY/HAVING is leaner for a check; ROW_NUMBER is the standard tool for actually removing duplicates.*
- **Target-facility classification check:** all six facilities resolve and classify correctly (Bryan / Grand Island / Kearney = Acute Care; Crete / Merrick = Critical Access; St. Elizabeth = Acute Care, Lincoln Competitor).
- **Data-currency check:** OP_18b = 2024-07-01 → 2025-06-30; OP_22 = 2024-01-01 → 2024-12-31.

---

## 05 — Benchmark analysis

- **CTEs:** `ed_times` (fact `f` joined to `hospital_info_clean h`, filtered to OP_18b and non-null score) and `acute_avg` (benchmark population).
- **Join:** `ON f.facility_id = h.facility_id` — no TRIM in the join, because both keys are trimmed at source (sections 02 and 03).
- **Window function:** `RANK() OVER (ORDER BY score_numeric)` for facility ranking.
- **Benchmark definition decision:**
  - First pass averaged **all** acute EDs including Bryan + St. Elizabeth → **138.0**.
  - Revised to exclude both Lincoln hospitals (`org_group = 'Other Nebraska'`) → **141.6**.
  - *Rationale: benchmarking a facility against a pool that contains itself is mildly circular. Both Lincoln hospitals are named comparisons in this analysis, so they are kept out of the "rest of Nebraska" background average — leaving three non-overlapping groups (Bryan / competitor / field). Matches the Power BI subtotal exactly.*
- **Cross-tool validation:** SQL output equals the Power BI dashboard — Bryan 117, St. Elizabeth 162, benchmark 141.6 — confirming the same cleaning logic produces the same answer in two independent engines.

---

## 06 — Descriptive statistics (Queries 7 & 8)

Added to quantify *how much* better Bryan's throughput is, not just that it is better.

- **Query 7 — distribution of acute-hospital medians:** `COUNT`, `AVG`, `STDDEV_SAMP`, and `APPROX_QUANTILES` for median, Q1, Q3, IQR, min/max/range.
  - *`STDDEV_SAMP` (sample, n−1) not `STDDEV_POP` — the 21 hospitals are a sample/snapshot, not the full universe.*
  - *`APPROX_QUANTILES(col, N)` returns N+1 cut points as a zero-indexed array; `[OFFSET(1)]`/`[OFFSET(3)]` on a 4-bucket split give Q1/Q3. IQR = Q3 − Q1, computed inline.*
- **Query 8 — each Lincoln hospital's position in that distribution:** `AVG() OVER ()` and `STDDEV_SAMP() OVER ()` (empty `OVER ()` broadcasts the whole-set mean/SD to every row) to compute a z-score, plus `PERCENT_RANK() OVER (ORDER BY median_min DESC)` for a speed percentile.

- **Dual reference-population decision (important):**
  - The **benchmark** (Query 6) uses the mean of acute EDs **excluding** both Lincoln hospitals → **141.6**. This is a *comparison* statistic; a facility shouldn't be benchmarked against a pool containing itself.
  - The **descriptive statistics** (Queries 7 & 8) use **all 21** acute EDs **including** Bryan and St. Elizabeth → mean **138.0**. This is a *distribution* statistic; a z-score/percentile locates a hospital *within* the distribution it belongs to, so it must be included.
  - *These are deliberately different populations for deliberately different purposes — not an inconsistency. Both are labeled wherever cited (141.6 = benchmark; 138.0 = distribution mean).*

- **Percentile inversion decision:** `PERCENT_RANK` is ordered `DESC` so that **faster hospitals score a higher percentile** — aligning the number with "better" for non-technical readers. Without `DESC`, St. Elizabeth (slow) would read as 85th percentile, which sounds positive but is the opposite of the finding.

- **Reporting decision (skew + small n):** the distribution is right-skewed (mean 138 > median 132; slowest 246 far past Q3 156), and n=21 (<30). Audience-facing materials therefore lead with **percentile and IQR** (assumption-free, robust to skew) and **omit the z-score**, which assumes approximate normality the data doesn't support. The z-score is retained in SQL for a technical reader but not surfaced in the README or dashboard.
  - *Headline statistic: Bryan Medical Center sits exactly at Q1 (117 min) — the 25th-percentile boundary — i.e., faster than ~75% of Nebraska acute EDs.*

---

## Power Query → SQL Function Map (reference)


| Power Query step | BigQuery equivalent |
|---|---|
| Replace "Not Available" + change type + replace errors | `SAFE_CAST(... AS FLOAT64)` |
| `Text.Lower` | `LOWER()` |
| `Text.Trim` | `TRIM()` |
| `List.Contains({...}, x)` | `x IN (...)` |
| Remove Duplicates on key | `SELECT DISTINCT` / `ROW_NUMBER()` filter |
| Filter Rows | `WHERE` |
| Custom conditional column | `CASE WHEN ... THEN ... ELSE ... END` |
| Merge (join) on key | `JOIN ... ON` |

---

## Revision History

### 2026-06-13
**Added**
- Descriptive statistics (Queries 7 & 8): distribution summary (n, mean, median, SD, Q1/Q3, IQR, range) and per-hospital percentile + z-score. Documents the dual reference-population choice (138.0 distribution mean vs. 141.6 benchmark), the `DESC` percentile inversion so faster = higher, and the decision to lead with percentile/IQR and omit the z-score given right-skew and n<30.

**Changed**
- `timely_care_clean`: added `TRIM` to `Measure ID`, `State`, and `Score_Category` (match/filter/group columns), plus `TRIM(LOWER())` in the category match — mirrors the Power Query trim step and defends filters/grouping against whitespace.
- `hospital_info_clean`: added `TRIM` to `Hospital Type` (benchmark grouping field).
- Benchmark join: removed the join-time `TRIM` — both keys are now trimmed at source, so the join compares clean keys directly.
- Rebuilt both tables with `CREATE OR REPLACE TABLE` to apply the corrected cleaning.

**Fixed**
- Benchmark population: `acute_avg` now excludes both Lincoln hospitals (`org_group = 'Other Nebraska'`). Prior version averaged all acute EDs *including* the facilities being compared → 138.0; corrected to 141.6, matching the Power BI dashboard. Reason: benchmarking a facility against a pool containing itself is circular.

**Note**
- SQL trims `State` in the filter (`WHERE TRIM(State) = 'NE'`); the Power Query DimHospital filters `State` without a trim. Source `State` values contained no whitespace, so both produce identical row sets — the SQL trim is precautionary, and the difference is intentional, not an oversight.

### 2026-06-12
**Added**
- Initial build: `timely_care_raw` / `hospital_info_raw` loads, `timely_care_clean`, `hospital_info_clean`, validation checks, and the benchmark query.
