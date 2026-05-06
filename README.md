# IOM's CBNA dataset cleaning and analysis — SQL Project

> **A humanitarian data analysis project built entirely in SQL**  
> Tracking displacement, security, and aid delivery across 10,802 Afghan settlements over six survey rounds (2020–2022)

---

## Project Overview

This project transforms the **Afghanistan Community-Based Needs Assessment (CBNA)** dataset — collected by the International Organization for Migration(IOM) into a fully normalised relational database and analyses it using SQL. The raw data was originally processed in Excel across six separate rounds; this project replicates and extends that analysis using pure SQL.

### What the data covers
- **10,802 settlements** monitored across all 34 Afghan provinces
- **6 survey rounds**: Jun 2020 → 2022 (spanning COVID-19, the Taliban takeover, and its aftermath)
- **64,812 observations** (balanced panel: every settlement assessed in every round)
- Key indicators: IDP arrivals, security situation, health/education access, humanitarian aid delivery

---

## Project Structure

```
afghanistan_cbna_sql/
│
├── 01_schema.sql              # Table definitions, constraints, indexes
├── 02_exploration.sql         # Data quality checks, distributions, null audits
├── 03_analysis.sql            # Core humanitarian analysis (5 themes)
├── 04_advanced_analysis.sql   # Window functions, CTEs, DiD evaluation
├── 05_views.sql               # Reusable reporting views
├── 06_portfolio_showcase.sql  # 8 curated highlight queries
│
├── afghanistan_cbna.db        # SQLite database (ready to run)
│
└── data/                      # CSV seed files for each normalised table
    ├── provinces.csv          (34 rows)
    ├── districts.csv          (394 rows)
    ├── settlements.csv        (10,802 rows)
    ├── survey_rounds.csv      (6 rows)
    └── observations.csv       (64,812 rows)
```

---

## Database Schema

The raw flat file (42 columns × 64,812 rows) was normalised into **5 tables** following 3NF principles:

```
provinces          districts           settlements
──────────         ──────────          ───────────
province_id   ←── province_id    ←── adm2_code ──┐
province_name      district_id        settlement_id│
adm1_code          adm2_code          settlement_code
                   district_name      settlement_name
                                      longitude / latitude
                                      pashtun_greg / ethno

survey_rounds      observations  (FACT TABLE)
─────────────      ─────────────────────────────────────
round_id      ←── round_id           observation_id
round_label        settlement_id ────┘
round_period       host_population
                   idp_arrivals
                   idp_conflict_severity (0–5)
                   idp_disaster_severity (0–5)
                   security_situation    (0–5)
                   health_clinics_available
                   schools_available
                   humanitarian_aid_delivered
                   aid_emergency_shelter / food / cash / infrastructure
                   post_intervention / diff_in_diff   ← DiD flags
                   conflict_res_1..5 / disaster_res_1..5
```

**Indexes** on `settlement_id`, `round_id`, `adm2_code`, and `province_id` ensure fast filtering and joining across 64K+ rows.

---

## Key Findings

| Metric | Finding |
|---|---|
| **Peak displacement** | Round 5 (Dec 2021) — avg 449 IDPs/settlement after Taliban takeover |
| **Worst-affected province** | Herat — 894,789 IDP arrivals in Round 6 alone |
| **Aid coverage** | Rose from 30.8% → 80.5% between rounds 1 and 6 |
| **School access** | Declined from 59% → 53% (Taliban education restrictions) |
| **Triple deprivation** | 3,090 settlements had no health, no schools, no aid simultaneously (Round 4 peak) |
| **Aid gap** | 467 high-displacement settlements received zero aid in Round 6 |

---

## SQL Techniques Demonstrated

### Foundations
- Multi-table `JOIN` (3–4 tables per query)
- `GROUP BY` with `HAVING` filters
- `CASE WHEN` for categorical classification
- Conditional aggregation (`SUM(CASE WHEN ...)`)
- `NULLIF` for safe division, `NULL` handling

### Intermediate
- **Common Table Expressions (CTEs)** — multi-step logic broken into readable named blocks
- **Subqueries** — in `WHERE`, `HAVING`, and `SELECT` clauses
- **Self-joins** — comparing the same table across rounds (round1 vs round6)

### Advanced
- **Window functions**: `LAG()`, `LEAD()`, `RANK()`, `ROW_NUMBER()`, `NTILE()`, `PERCENT_RANK()`
- **Moving averages**: `AVG() OVER (ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)`
- **Running totals**: cumulative `SUM() OVER (... UNBOUNDED PRECEDING)`
- **Partitioned ranking**: top-N per group using `ROW_NUMBER() OVER (PARTITION BY ...)`

### Database Design
- **Normalisation**: Flat file → 3NF relational schema
- **Views**: 5 reusable reporting views (settlement profile, national dashboard, aid gap targeting)
- **Indexing**: Strategic indexes for query performance
- **Composite scoring**: Vulnerability index combining 5 weighted indicators

### Econometric / Analytical
- **Difference-in-Differences (DiD)**: Quasi-experimental evaluation of humanitarian interventions
- **Longitudinal panel analysis**: Settlement-level trajectory tracking across 6 time periods
- **Surge detection**: Identifying settlements with >50% IDP jump between rounds

---

## How to Run

### Option 1 — SQLite (Recommended, no install needed)

```bash
# Open the pre-built database
sqlite3 afghanistan_cbna.db

# Run any script
.read 01_schema.sql
.read 02_exploration.sql
.read 03_analysis.sql
.read 04_advanced_analysis.sql
.read 05_views.sql
.read 06_portfolio_showcase.sql

# Example quick query
SELECT * FROM vw_national_dashboard;
```

### Option 2 — DB Browser for SQLite (GUI)
1. Download [DB Browser for SQLite](https://sqlitebrowser.org/) (free)
2. Open `afghanistan_cbna.db`
3. Go to **Execute SQL** tab
4. Paste and run any query from the `.sql` files

### Option 3 — PostgreSQL / MySQL
The schema and queries use standard SQL and are compatible with PostgreSQL and MySQL with minor adjustments:
- Replace `REAL` with `DOUBLE PRECISION` (PostgreSQL)
- `CREATE VIEW IF NOT EXISTS` → `CREATE OR REPLACE VIEW` (PostgreSQL)
- Import CSVs from the `data/` folder using `COPY` (PostgreSQL) or `LOAD DATA` (MySQL)

---

## Data Source

**International Organization for Migration (IOM)** — Afghanistan Community-Based Needs Assessment (CBNA)  
- Rounds 10–16 collected Jun 2020 – 2022
- Covers all 34 provinces, 388+ districts, 10,802 assessed settlements
- Indicators: displacement, security, health, education, humanitarian aid


