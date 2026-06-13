# Power Query Cleaning Changelog

**Project:** Lincoln ED Throughput Benchmark
**Source:** CMS Provider Data Catalog — "Timely and Effective Care – Hospital" (dataset `yv7e-xc69`) and "Hospital General Information." Nebraska subset.
**Measurement period:** OP_18b = Jul 1, 2024 – Jun 30, 2025; OP_22 = CY 2024.
**Tools:** Excel Power Query → Power BI (data model, DAX, dashboards).

---

## FactMeasures — Timely & Effective Care

1. **Source** — import CSV (comma-delimited, Windows-1252 encoding, 16 columns).
2. **Promote headers** — first row to column names.
3. **Changed Type** — `Start Date` / `End Date` typed as Date.
4. **Replace "Not Available" → null** in `Score` (pre-clean before the split).
5. **Duplicate `Score` column ×2** — to derive a numeric and a categorical version from the single mixed-type Score field.
6. **Rename** the copies → `Score_Numeric` and `Score_Category`.
7. **Score_Numeric cleaning** — replace "Not Available" → null, then change type to Decimal, then **Replace Errors → null**. (Categorical text such as "very high" errors on numeric conversion; those errors become null.)
8. **Score_Category cleaning** — custom column keeping only `{low, medium, high, very high}` via `List.Contains` on the lowercased value; everything else → null. Original column removed, cleaned column renamed back to `Score_Category`.
9. **Filter `State` = "NE".**
10. **Remove original `Score` column** — split complete; raw mixed-type column no longer needed.
11. **Data_Status flag** — any footnoted row → "Suppressed/Low Sample", else "Reported".
    - *Decision: flag any footnote rather than decoding individual footnote codes — a benchmarking analysis needs only a clean-vs-caveated distinction. Extend with `List.Contains` on specific codes if a stakeholder needs suppression reasons.*
12. **Trim match/key columns** — `Text.Trim` applied to `Facility ID`, `Measure ID`, `Score_Category`, and `State`.
    - *Decision: trim only the columns used for joining, filtering, or grouping — those are where trailing whitespace silently corrupts results (a join misses, a filter drops rows, a group splits in two). Display-only columns (Facility Name, Address) left untrimmed. Here: Facility ID = join key; Measure ID and State = filter columns; Score_Category = grouping field.*
    - *This corrected an asymmetry in the original build where only the dimension key was trimmed — both fact and dimension keys are now trimmed at source.*

---

## DimHospital — Hospital General Information

1. **Source** — import CSV (38 columns).
2. **Promote headers.**
3. **Filter `State` = "NE"** — done early to shrink all downstream work.
4. **Keep model columns** — Facility ID, Facility Name, City/Town, County/Parish, Hospital Type, Hospital Ownership, Emergency Services, Hospital overall rating.
   - *Dimension tables stay lean — only fields the model slices or displays by.*
5. **Replace "Not Available" → null** in `Hospital overall rating`.
6. **Clean star rating** — type to Whole Number.
   - *Kept numeric; null rather than zero, since zero would poison averages.*
7. **Trim `Facility ID`** — strip whitespace from the join key (prevents silent relationship failures where `"280003 "` ≠ `"280003"`).
8. **Remove duplicates on `Facility ID`** — enforce key uniqueness, required for the 1-side of the relationship.
9. **Org_Group** — custom column: Bryan network CCNs → "Bryan Health Network"; `280020` → "Lincoln Competitor"; else "Other Nebraska".
   - *Hardcoded by CCN; update the list if network composition changes.*
10. **Trim `Hospital Type`** — `Text.Trim` on the field used for the acute / critical-access split and the benchmark population.
   - *A grouping/filter column: a trailing space would split "Acute Care Hospitals" into two groups and distort the benchmark average. (Facility ID was already trimmed at step 7.)*

---

## Data Model

- **Relationship:** `DimHospital[Facility ID]` 1 → * `FactMeasures[Facility ID]`.
- **Explicit DAX measures** (`Median ED Minutes`, `% Left Without Being Seen`) created for unit-correct formatting, since the long-format fact table is unit-heterogeneous (one column holds both minutes and percentages across different measures).
- **Grain decision:** fact table kept in long format (one row per facility-measure). The presentation layer reshapes via PivotTable/matrix rather than pivoting the data wide — preserves consistent grain.

---

## Key Data-Quality Decisions (summary)

| Decision | Why |
|---|---|
| Facility ID kept as Text | Preserve leading-zero CCN, the cross-file join key |
| Score split into two columns | Source mixes numeric (minutes) and categorical (volume class) in one field |
| Footnote → simple "Suppressed/Low Sample" flag | Benchmarking needs clean-vs-caveated, not code-level detail |
| Star rating null, not zero | Zero would distort averages |
| Trim only match/key columns (Facility ID, Measure ID, Score_Category, State, Hospital Type) | Whitespace silently corrupts joins, filters, and grouping; display-only columns left alone to keep the load-bearing trims visible |
