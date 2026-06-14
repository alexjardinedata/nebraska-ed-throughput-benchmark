# Lincoln ED Throughput Benchmark — CMS Public Data

**Built in Power Query → Power BI, then independently reproduced in BigQuery SQL — both engines return the identical result.**

> Public CMS data shows Bryan absorbing Lincoln's ED demand faster than its competitor at higher volume — a directional read on resilience. The strategic question it raises, but can't answer, is how much capacity survives as coverage losses phase in.

**Testable business question:** Does Bryan's ED network show measurably better throughput than its Lincoln competitor and Nebraska acute-care peers in public CMS data — and does that finding hold after controlling for volume class and facility type?

---

## Project Overview

Lincoln is a two-system hospital market, and Bryan Health operates as the region's pressure-release valve — a Level II trauma center absorbing demand the surrounding region can't serve. Nebraska's Medicaid work requirements took effect May 1, 2026, with existing-enrollee checks phasing in through the renewal cycle beginning July 31, 2026. As coverage lapses, scheduled care is projected to convert into unscheduled ED demand, making ED capacity a strategic question.

This project benchmarks ED throughput for every Medicare-certified hospital in Nebraska — all five Bryan network facilities plus CHI Health St. Elizabeth — using public CMS hospital quality data.

**What makes this more than a single analysis:** the full cleaning and analysis pipeline was built twice, in two independent tools, and validated to produce the same answer.

| | Implementation |
|---|---|
| **Pipeline A** | Excel Power Query (cleaning + star schema) → Power BI (model, DAX, dashboards) |
| **Pipeline B** | BigQuery SQL (cleaning tables + CTE/window-function analysis) |
| **Result** | Identical: Bryan **117** min · St. Elizabeth **162** min · benchmark **141.6** |

---

## Primary Findings

**1. Bryan moves ED patients 45 minutes faster than its crosstown competitor — despite higher volume.**
Bryan Medical Center's median ED time is 117 minutes vs. 162 at CHI St. Elizabeth (~28% faster). Bryan operates in the "very high" ED volume class — one of only 3 of 75 Nebraska EDs — while St. Elizabeth is "medium." Faster throughput on a heavier load.

**2. The speed is network-wide, not a flagship outlier.**
All three Bryan acute facilities beat the Nebraska acute-care average of 141.6 minutes: Grand Island (105), Kearney (108), Bryan Medical Center (117). Consistency across facilities acquired in 2019 and 2022 implies transferable operational process.

**3. A second, independent indicator confirms the throughput story.**
CMS reports 0.0% of patients leaving without being seen across every Bryan facility, vs. 1.0% at St. Elizabeth and a 1.24% statewide acute average.

**Answer to the business question: yes, and it holds.** The finding survives both controls — the volume comparison runs in Bryan's favor, and the facility-type control sharpens the benchmark from the diluted statewide average (118.5) to the acute-care average (141.6), which Bryan still beats.

---

## Evidence

| Metric | Bryan Medical Center | CHI St. Elizabeth | Benchmark |
|---|---|---|---|
| Median ED time (OP_18b) | **117 min** | 162 min | 141.6 — NE acute-care avg |
| ED volume class (EDV) | **Very high** (1 of 3 in NE) | Medium | 66 of 75 NE EDs are "low" |
| Left without being seen (OP_22) | **0.0%** | 1.0% | 1.24% — NE acute-care avg |
| Network facilities (median ED min) | Grand Island 105 · Kearney 108 · Crete 100 · Merrick 125 | — | All acute facilities under avg |

**Benchmark note:** the raw statewide average (118.5) is diluted by 62 critical-access hospitals; the like-for-like comparison is the acute-care average (141.6), excluding both Lincoln hospitals so the compared facilities aren't in their own benchmark.

---

## Statistical Summary

To quantify *how much* better Bryan's throughput is — not just that it is better — I described the distribution of ED throughput across all 21 Nebraska acute-care hospitals and located each Lincoln-area hospital within it.

| Statistic (acute-hospital median ED times, n = 21) | Value |
|---|---|
| Mean | 138.0 min |
| Median | 132.0 min |
| Interquartile range (Q1–Q3) | 117 – 156 min (IQR 39) |
| Range (fastest – slowest) | 93 – 246 min |

**Where the Lincoln hospitals land:**

| Facility | Median ED min | Speed percentile* |
|---|---|---|
| Grand Island Regional (Bryan) | 105 | 85th |
| Kearney Regional (Bryan) | 108 | 80th |
| **Bryan Medical Center** | **117** | **75th** |
| CHI St. Elizabeth | 162 | 15th |

\*Percentile ordered so faster = higher. Bryan Medical Center sits exactly at the 25th-percentile boundary (Q1 = 117) — **faster than roughly 75% of Nebraska acute EDs** — while its regional facilities reach the 80th–85th. The competitor sits at the 15th.

**Method note:** these are descriptive statistics on published per-hospital medians, not patient-level data — so no inferential test (t-test, p-value) is claimed; that would require the underlying visit-level records. Because the distribution is right-skewed (mean 138 > median 132) and n < 30, the summary leads with **percentile and IQR**, which are robust to skew and assumption-free, rather than standard deviation or z-scores. Two reference populations are used deliberately: the **benchmark** (141.6) excludes both Lincoln hospitals to avoid circular comparison, while the **distribution** statistics (mean 138) include all acute EDs, since a percentile locates a hospital within the distribution it belongs to.

---

## How It Was Built

### Pipeline A — Power Query → Power BI
- Cleaned raw CMS CSVs in Power Query: split a mixed numeric/categorical Score column into two typed fields, flagged footnoted (suppressed/low-sample) rows, preserved leading-zero facility IDs, trimmed match/key columns.
- Modeled as a star schema (hospital dimension + long-format measure fact table) with explicit DAX measures for unit-correct formatting.
- Dashboards: ED throughput benchmark, walkout-rate comparison, data-coverage audit.

### Pipeline B — BigQuery SQL
- Reproduced the same cleaning in SQL: `SAFE_CAST` for numeric coercion, `CASE`/`IN` for category extraction, footnote flag, `TRIM` on match/key columns.
- Benchmark query uses two CTEs, a join across fact and dimension tables, a filtered aggregate for the benchmark population, and a `RANK()` window function.
- Output validated against the Power BI dashboard — same numbers, two engines.

All six BigQuery queries (raw inspect → cleaning → validation → benchmark) are in one organized file: [`queries.sql`](queries.sql). Power Query M code: [`FactMeasures.m`](FactMeasures.m), [`DimHospital.m`](DimHospital.m).

Full step-by-step logic and decision rationale for both pipelines:
- [`CHANGELOG_PowerQuery.md`](CHANGELOG_PowerQuery.md)
- [`CHANGELOG_SQL.md`](CHANGELOG_SQL.md)

---

## Measuring the Capacity Ceiling

The benchmark answers a performance question: Bryan moves ED patients faster than its competitor and the state, and it holds under volume and facility-type controls. But the strategic question Bryan faces is capacity under rising demand — who absorbs the Medicaid-driven shift as coverage losses convert scheduled care into unscheduled ED visits. Public data can't measure capacity directly, so this project answered the closest proxy it could: throughput at load, plus zero walkouts at the state's highest volume class — a directional read that Bryan carries the most load with the least visible strain. That is a resilience signal, not a capacity measurement.

These three recommendations are how you'd measure the ceiling for real. Each requires internal data the public files don't contain, and together they form a sequence — **diagnose** how much cushion is already spent, **detect** new demand as it arrives, **respond** before throughput degrades.

**1. Diagnose — quantify behavioral-health boarding.** *How much of the cushion is already silently consumed.* Public medians can't see the admitted-and-waiting population, and behavioral health is the chronically capacity-constrained line. *Needs:* Epic ADT timestamps + psych bed census. *Produces:* the boarding-hours decomposition a capacity investment case requires — the share of ED capacity already lost to patients waiting for a bed.

**2. Detect — build a coverage-loss early-warning monitor.** *The leading edge of the demand surge.* The Urban Institute (characterized as left-leaning in the source reporting) projects Nebraska Medicaid expansion enrollment could decline by 16,000–30,000 by 2028 — a 23–43% drop off the ~70,000 expansion base — driven by the new work requirement *and* a federal shift to six-month eligibility redeterminations. As coverage lapses, covered scheduled care converts into uninsured, unscheduled ED visits. *Needs:* registration/payer-mix data tracked weekly against the renewal/disenrollment cycle (existing-enrollee checks begin July 31, 2026). *Produces:* a leading indicator of unscheduled demand weeks before it reaches the income statement.

**3. Respond — forecast census 7–14 days out.** *Staff ahead of the load before it tests the ceiling.* Predict census by service line to flex staffing proactively rather than premium-pay reactively — structurally the same forecasting problem as athlete availability: constrained capacity, seasonal demand, individualized risk. *Needs:* admissions time series, with the coverage-loss signal from #2 as a model input. *Produces:* staffing-grid inputs that protect throughput as load rises; success = fewer premium-labor hours at equal or better throughput.

---

## Data Source & Currency

- **Source:** CMS Provider Data Catalog — [Timely and Effective Care – Hospital](https://data.cms.gov/provider-data/dataset/yv7e-xc69) and Hospital General Information (Nebraska subset).
- **Measurement period:** OP_18b = Jul 1, 2024 – Jun 30, 2025; OP_22 = CY 2024. (Public hospital-quality data lags ~12 months by design — which is precisely why the recommendations point to internal data for current operations.)
- **Limitations:** medians cover discharged ED patients only (boarding not captured); 0.0% walkouts is CMS-reported and may round from a small true rate; Bryan East/West share one CMS certification number (campus-level analysis needs internal data).
- **Coverage-loss projection:** the 16,000–30,000 figure is an Urban Institute estimate for 2028 (attributing the decline to the work requirement plus six-month redeterminations), reported by the Nebraska Hospital Association / CNN. It sizes the demand risk; it is not a measured or current disenrollment count.

---

## Repository Contents

```
.
├── README.md
├── index.html                  Interactive dashboard (GitHub Pages)
├── queries.sql                 All six BigQuery queries (cleaning → benchmark)
├── FactMeasures.m              Power Query M — fact table cleaning
├── DimHospital.m               Power Query M — dimension table cleaning
├── CHANGELOG_PowerQuery.md     Power Query cleaning steps + decisions
├── CHANGELOG_SQL.md            BigQuery cleaning steps + revision history
├── 01_ed_throughput.png        Power BI dashboard — ED throughput
├── 02_walkouts.png             Power BI dashboard — walkouts
├── Bryan_ED_Benchmark.pbix     Power BI source file
└── *.csv                       Cleaned table + benchmark query outputs
```

**Live dashboard:** [alexjardinedata.github.io/nebraska-ed-throughput-benchmark](https://alexjardinedata.github.io/nebraska-ed-throughput-benchmark/)

---

*Part of a data-analysis portfolio. See also: [NCAA Women's Basketball SQL Analysis](https://github.com/alexjardinedata/ncaa-wbb-sql-analysis).*
