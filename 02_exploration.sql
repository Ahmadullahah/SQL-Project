-- =============================================================================
-- Afghanistan CBNA SQL Project
-- Script 02: Data Exploration & Quality Checks
-- =============================================================================
-- PURPOSE: Understand the dataset before analysis — row counts, distributions,
--          null checks, and data-quality validation across all five tables.
-- =============================================================================


-- ──────────────────────────────────────────────────────────────────────────────
-- SECTION A: DATABASE OVERVIEW
-- ──────────────────────────────────────────────────────────────────────────────

-- A1. Row counts across all tables
SELECT 'provinces'     AS table_name, COUNT(*) AS row_count FROM provinces
UNION ALL
SELECT 'districts',                   COUNT(*)              FROM districts
UNION ALL
SELECT 'settlements',                 COUNT(*)              FROM settlements
UNION ALL
SELECT 'survey_rounds',               COUNT(*)              FROM survey_rounds
UNION ALL
SELECT 'observations',                COUNT(*)              FROM observations;
-- Expected: 34 | 394 | 10,802 | 6 | 64,812


-- A2. Survey rounds reference table
SELECT
    round_id,
    round_label,
    round_period,
    CASE round_id
        WHEN 1 THEN 'Baseline (COVID-19 onset)'
        WHEN 2 THEN 'Post-COVID first wave'
        WHEN 3 THEN 'Pre-Taliban transition'
        WHEN 4 THEN 'Late Republic'
        WHEN 5 THEN 'Post-Taliban takeover'
        WHEN 6 THEN 'Consolidation period'
    END AS context_note
FROM survey_rounds
ORDER BY round_id;


-- A3. Observations per round — confirm perfect panel balance
SELECT
    sr.round_label,
    sr.round_period,
    COUNT(o.observation_id)             AS num_observations,
    COUNT(DISTINCT o.settlement_id)     AS num_settlements
FROM observations o
JOIN survey_rounds sr ON o.round_id = sr.round_id
GROUP BY o.round_id
ORDER BY o.round_id;
-- All 6 rounds should show exactly 10,802 settlements — balanced panel


-- ──────────────────────────────────────────────────────────────────────────────
-- SECTION B: GEOGRAPHIC COVERAGE
-- ──────────────────────────────────────────────────────────────────────────────

-- B1. Settlements per province — coverage map
SELECT
    p.province_name,
    p.adm1_code,
    COUNT(DISTINCT d.district_id)   AS num_districts,
    COUNT(DISTINCT s.settlement_id) AS num_settlements
FROM provinces p
JOIN districts   d ON p.province_id = d.province_id
JOIN settlements s ON d.adm2_code   = s.adm2_code
GROUP BY p.province_id
ORDER BY num_settlements DESC;


-- B2. Top 10 most-assessed districts
SELECT
    p.province_name,
    d.district_name,
    COUNT(DISTINCT s.settlement_id) AS settlements
FROM districts   d
JOIN provinces   p ON d.province_id = p.province_id
JOIN settlements s ON d.adm2_code   = s.adm2_code
GROUP BY d.district_id
ORDER BY settlements DESC
LIMIT 10;


-- ──────────────────────────────────────────────────────────────────────────────
-- SECTION C: NULL / MISSING VALUE AUDIT
-- ──────────────────────────────────────────────────────────────────────────────

-- C1. Null check on key observation columns
SELECT
    COUNT(*) AS total_rows,

    -- Population fields
    SUM(CASE WHEN host_population         IS NULL THEN 1 ELSE 0 END) AS null_host_pop,
    SUM(CASE WHEN idp_arrivals            IS NULL THEN 1 ELSE 0 END) AS null_idp_arrivals,
    SUM(CASE WHEN change_idp_arrivals     IS NULL THEN 1 ELSE 0 END) AS null_change_idp,

    -- Severity fields
    SUM(CASE WHEN idp_conflict_severity   IS NULL THEN 1 ELSE 0 END) AS null_conflict_sev,
    SUM(CASE WHEN idp_disaster_severity   IS NULL THEN 1 ELSE 0 END) AS null_disaster_sev,
    SUM(CASE WHEN security_situation      IS NULL THEN 1 ELSE 0 END) AS null_security,

    -- Services
    SUM(CASE WHEN health_clinics_available IS NULL THEN 1 ELSE 0 END) AS null_health,
    SUM(CASE WHEN schools_available        IS NULL THEN 1 ELSE 0 END) AS null_schools

FROM observations;
-- change_idp_arrivals has ~10,802 NULLs (Round 1 has no previous round to compare)


-- C2. NULLs in change_idp_arrivals broken down by round (expected only in Round 1)
SELECT
    sr.round_label,
    COUNT(*) AS total,
    SUM(CASE WHEN change_idp_arrivals IS NULL THEN 1 ELSE 0 END) AS null_change,
    ROUND(
        SUM(CASE WHEN change_idp_arrivals IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    1) AS pct_null
FROM observations o
JOIN survey_rounds sr ON o.round_id = sr.round_id
GROUP BY o.round_id
ORDER BY o.round_id;


-- ──────────────────────────────────────────────────────────────────────────────
-- SECTION D: VALUE DISTRIBUTIONS
-- ──────────────────────────────────────────────────────────────────────────────

-- D1. Security situation distribution (0 = No threat → 5 = Extreme)
SELECT
    security_situation                              AS security_level,
    CASE security_situation
        WHEN 0 THEN 'No Threat'
        WHEN 1 THEN 'Minimal'
        WHEN 2 THEN 'Low'
        WHEN 3 THEN 'Moderate'
        WHEN 4 THEN 'High'
        WHEN 5 THEN 'Extreme'
    END                                             AS label,
    COUNT(*)                                        AS frequency,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM observations), 2) AS pct
FROM observations
GROUP BY security_situation
ORDER BY security_situation;


-- D2. IDP arrival statistics — overall
SELECT
    MIN(idp_arrivals)                   AS min_arrivals,
    MAX(idp_arrivals)                   AS max_arrivals,
    ROUND(AVG(idp_arrivals), 1)         AS avg_arrivals,
    -- approximate median via ordering
    (SELECT idp_arrivals FROM observations
     ORDER BY idp_arrivals
     LIMIT 1 OFFSET (SELECT COUNT(*)/2 FROM observations)) AS median_arrivals
FROM observations
WHERE idp_arrivals > 0;    -- exclude zero-IDP settlements


-- D3. Humanitarian aid type breakdown (share of observations where delivered)
SELECT
    'Emergency Shelter'  AS aid_type,
    ROUND(AVG(aid_emergency_shelter)   * 100.0, 2) AS pct_delivered
FROM observations
UNION ALL
SELECT 'Food Distribution', ROUND(AVG(aid_food_distribution)  * 100.0, 2) FROM observations
UNION ALL
SELECT 'Cash Assistance',   ROUND(AVG(aid_cash)               * 100.0, 2) FROM observations
UNION ALL
SELECT 'Infrastructure',    ROUND(AVG(aid_infrastructure)     * 100.0, 2) FROM observations
ORDER BY pct_delivered DESC;


-- D4. DiD (Difference-in-Differences) group sizes
SELECT
    post_intervention                               AS post,
    diff_in_diff                                    AS treatment,
    CASE
        WHEN post_intervention=0 AND diff_in_diff=0 THEN 'Control   — Pre'
        WHEN post_intervention=1 AND diff_in_diff=0 THEN 'Control   — Post'
        WHEN post_intervention=0 AND diff_in_diff=1 THEN 'Treatment — Pre'
        WHEN post_intervention=1 AND diff_in_diff=1 THEN 'Treatment — Post'
    END                                             AS group_label,
    COUNT(*)                                        AS obs_count
FROM observations
GROUP BY post_intervention, diff_in_diff
ORDER BY post_intervention, diff_in_diff;
