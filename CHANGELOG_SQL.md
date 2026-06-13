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
