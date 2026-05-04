-- =============================================================================
-- Afghanistan CBNA SQL Project
-- Script 03: Core Analysis Queries
-- =============================================================================
-- PURPOSE: Answer the key humanitarian questions embedded in the CBNA dataset:
--   1. IDP displacement trends over time
--   2. Provincial-level displacement burden
--   3. Security situation evolution
--   4. Humanitarian aid delivery performance
--   5. Access to basic services (health + education)
-- =============================================================================


-- ──────────────────────────────────────────────────────────────────────────────
-- ANALYSIS 1: IDP DISPLACEMENT TRENDS OVER TIME
-- ──────────────────────────────────────────────────────────────────────────────

-- Q1a. Total & average IDP arrivals per survey round
SELECT
    sr.round_id,
    sr.round_label,
    sr.round_period,
    SUM(o.idp_arrivals)                     AS total_idp_arrivals,
    ROUND(AVG(o.idp_arrivals), 1)           AS avg_per_settlement,
    MAX(o.idp_arrivals)                     AS max_single_settlement,
    COUNT(CASE WHEN o.idp_arrivals > 0 THEN 1 END) AS settlements_with_idps
FROM observations  o
JOIN survey_rounds sr ON o.round_id = sr.round_id
GROUP BY o.round_id
ORDER BY o.round_id;
-- KEY INSIGHT: Average IDP arrivals rose from ~395 (Round 1/Jun 2020)
-- to a peak of ~449 (Round 5/Dec 2021) after the Taliban takeover,
-- reflecting the acute post-takeover displacement crisis.


-- Q1b. Round-over-round change in total IDP arrivals
WITH round_totals AS (
    SELECT
        o.round_id,
        sr.round_label,
        SUM(o.idp_arrivals) AS total_idps
    FROM observations  o
    JOIN survey_rounds sr ON o.round_id = sr.round_id
    GROUP BY o.round_id
)
SELECT
    round_id,
    round_label,
    total_idps,
    LAG(total_idps) OVER (ORDER BY round_id)        AS prev_round_total,
    total_idps - LAG(total_idps) OVER (ORDER BY round_id) AS abs_change,
    ROUND(
        (total_idps - LAG(total_idps) OVER (ORDER BY round_id))
        * 100.0 / NULLIF(LAG(total_idps) OVER (ORDER BY round_id), 0),
    2)                                              AS pct_change
FROM round_totals
ORDER BY round_id;


-- Q1c. Settlements with consistently HIGH displacement (all 6 rounds, arrivals > 1000)
SELECT
    s.settlement_code,
    s.settlement_name,
    p.province_name,
    d.district_name,
    COUNT(o.round_id)              AS rounds_above_threshold,
    MIN(o.idp_arrivals)            AS min_arrivals,
    MAX(o.idp_arrivals)            AS max_arrivals,
    ROUND(AVG(o.idp_arrivals), 0)  AS avg_arrivals
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
WHERE o.idp_arrivals > 1000
GROUP BY s.settlement_id
HAVING COUNT(o.round_id) = 6       -- present in ALL rounds above threshold
ORDER BY avg_arrivals DESC
LIMIT 20;


-- ──────────────────────────────────────────────────────────────────────────────
-- ANALYSIS 2: PROVINCIAL DISPLACEMENT BURDEN
-- ──────────────────────────────────────────────────────────────────────────────

-- Q2a. Total IDP arrivals by province across ALL rounds
SELECT
    p.province_name,
    COUNT(DISTINCT s.settlement_id)         AS settlements_assessed,
    SUM(o.idp_arrivals)                     AS total_idp_arrivals,
    ROUND(AVG(o.idp_arrivals), 1)           AS avg_per_settlement,
    ROUND(
        SUM(o.idp_arrivals) * 100.0 /
        (SELECT SUM(idp_arrivals) FROM observations),
    2)                                      AS share_of_national_total_pct
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
GROUP BY p.province_id
ORDER BY total_idp_arrivals DESC;


-- Q2b. Province-level IDP trends — pivoted across rounds
SELECT
    p.province_name,
    SUM(CASE WHEN o.round_id = 1 THEN o.idp_arrivals END) AS round10_Jun2020,
    SUM(CASE WHEN o.round_id = 2 THEN o.idp_arrivals END) AS round11_Dec2020,
    SUM(CASE WHEN o.round_id = 3 THEN o.idp_arrivals END) AS round12_Mar2021,
    SUM(CASE WHEN o.round_id = 4 THEN o.idp_arrivals END) AS round13_Jun2021,
    SUM(CASE WHEN o.round_id = 5 THEN o.idp_arrivals END) AS round14_Dec2021,
    SUM(CASE WHEN o.round_id = 6 THEN o.idp_arrivals END) AS round16_2022,
    SUM(o.idp_arrivals)                                    AS grand_total
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
GROUP BY p.province_id
ORDER BY grand_total DESC
LIMIT 15;


-- Q2c. Districts with the highest IDP burden in the most recent round (Round 6)
SELECT
    p.province_name,
    d.district_name,
    COUNT(DISTINCT s.settlement_id)     AS settlements,
    SUM(o.idp_arrivals)                 AS total_idps_round6,
    ROUND(AVG(o.security_situation), 2) AS avg_security_score,
    ROUND(AVG(o.idp_conflict_severity), 2) AS avg_conflict_severity
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
WHERE o.round_id = 6
GROUP BY d.district_id
ORDER BY total_idps_round6 DESC
LIMIT 15;


-- ──────────────────────────────────────────────────────────────────────────────
-- ANALYSIS 3: SECURITY SITUATION EVOLUTION
-- ──────────────────────────────────────────────────────────────────────────────

-- Q3a. National average security score by round
SELECT
    sr.round_label,
    sr.round_period,
    ROUND(AVG(o.security_situation), 3)     AS avg_security_score,
    SUM(CASE WHEN o.security_situation >= 4 THEN 1 ELSE 0 END) AS high_threat_settlements,
    ROUND(
        SUM(CASE WHEN o.security_situation >= 4 THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    1)                                      AS pct_high_threat
FROM observations  o
JOIN survey_rounds sr ON o.round_id = sr.round_id
GROUP BY o.round_id
ORDER BY o.round_id;


-- Q3b. Most insecure provinces — average security score across all rounds
SELECT
    p.province_name,
    ROUND(AVG(o.security_situation), 3)     AS avg_security,
    SUM(CASE WHEN o.security_situation = 5 THEN 1 ELSE 0 END) AS extreme_threat_obs,
    ROUND(
        SUM(CASE WHEN o.security_situation = 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    1)                                      AS pct_extreme
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
GROUP BY p.province_id
ORDER BY avg_security DESC
LIMIT 10;


-- Q3c. Correlation proxy: High security threat vs. IDP arrivals
--      Compare avg IDP arrivals across security levels
SELECT
    o.security_situation                    AS security_level,
    CASE o.security_situation
        WHEN 0 THEN 'No Threat'
        WHEN 1 THEN 'Minimal'
        WHEN 2 THEN 'Low'
        WHEN 3 THEN 'Moderate'
        WHEN 4 THEN 'High'
        WHEN 5 THEN 'Extreme'
    END                                     AS label,
    COUNT(*)                                AS observations,
    ROUND(AVG(o.idp_arrivals), 1)           AS avg_idp_arrivals,
    ROUND(AVG(o.idp_conflict_severity), 2)  AS avg_conflict_severity,
    ROUND(AVG(o.host_population), 0)        AS avg_host_population
FROM observations o
GROUP BY o.security_situation
ORDER BY o.security_situation;


-- ──────────────────────────────────────────────────────────────────────────────
-- ANALYSIS 4: HUMANITARIAN AID DELIVERY PERFORMANCE
-- ──────────────────────────────────────────────────────────────────────────────

-- Q4a. Overall aid delivery rate by round
SELECT
    sr.round_label,
    sr.round_period,
    COUNT(*)                                                    AS total_settlements,
    SUM(o.humanitarian_aid_delivered)                           AS settlements_received_aid,
    ROUND(AVG(o.humanitarian_aid_delivered) * 100.0, 1)         AS pct_coverage,

    -- Aid type breakdown
    ROUND(AVG(o.aid_emergency_shelter)  * 100.0, 1)             AS pct_shelter,
    ROUND(AVG(o.aid_food_distribution)  * 100.0, 1)             AS pct_food,
    ROUND(AVG(o.aid_cash)               * 100.0, 1)             AS pct_cash,
    ROUND(AVG(o.aid_infrastructure)     * 100.0, 1)             AS pct_infra
FROM observations  o
JOIN survey_rounds sr ON o.round_id = sr.round_id
GROUP BY o.round_id
ORDER BY o.round_id;


-- Q4b. Aid delivery rate by province — identify coverage gaps
SELECT
    p.province_name,
    COUNT(*)                                                AS total_obs,
    ROUND(AVG(o.humanitarian_aid_delivered) * 100.0, 1)    AS pct_aid_delivered,
    ROUND(AVG(o.aid_food_distribution)      * 100.0, 1)    AS pct_food,
    ROUND(AVG(o.aid_cash)                   * 100.0, 1)    AS pct_cash,
    ROUND(AVG(o.aid_emergency_shelter)      * 100.0, 1)    AS pct_shelter,
    ROUND(AVG(o.idp_arrivals), 0)                          AS avg_idp_arrivals
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
GROUP BY p.province_id
ORDER BY pct_aid_delivered DESC;


-- Q4c. Aid gap analysis: high-IDP settlements that received NO aid
--      These are the most critical under-served locations
SELECT
    p.province_name,
    d.district_name,
    s.settlement_name,
    sr.round_label,
    o.idp_arrivals,
    o.security_situation,
    o.idp_conflict_severity,
    o.idp_disaster_severity
FROM observations  o
JOIN settlements   s  ON o.settlement_id = s.settlement_id
JOIN districts     d  ON s.adm2_code     = d.adm2_code
JOIN provinces     p  ON d.province_id   = p.province_id
JOIN survey_rounds sr ON o.round_id      = sr.round_id
WHERE o.humanitarian_aid_delivered = 0
  AND o.idp_arrivals > 1000           -- high displacement burden
ORDER BY o.idp_arrivals DESC
LIMIT 25;


-- ──────────────────────────────────────────────────────────────────────────────
-- ANALYSIS 5: ACCESS TO BASIC SERVICES
-- ──────────────────────────────────────────────────────────────────────────────

-- Q5a. Health clinic & school availability by round (national trend)
SELECT
    sr.round_label,
    sr.round_period,
    ROUND(AVG(o.health_clinics_available) * 100.0, 1)  AS pct_health_access,
    ROUND(AVG(o.schools_available)        * 100.0, 1)  AS pct_school_access,
    ROUND(AVG(o.health_clinics_available) * 100.0, 1)
        - ROUND(AVG(o.schools_available)  * 100.0, 1)  AS health_school_gap
FROM observations  o
JOIN survey_rounds sr ON o.round_id = sr.round_id
GROUP BY o.round_id
ORDER BY o.round_id;
-- NOTABLE: School access declined steeply after Round 4, reflecting
-- the Taliban's education restrictions particularly for girls.


-- Q5b. Provinces with the lowest service coverage (latest round)
SELECT
    p.province_name,
    ROUND(AVG(o.health_clinics_available) * 100.0, 1)  AS pct_health,
    ROUND(AVG(o.schools_available)        * 100.0, 1)  AS pct_schools,
    ROUND(AVG(o.humanitarian_aid_delivered) * 100.0,1) AS pct_aid,
    COUNT(*)                                            AS settlements
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
WHERE o.round_id = 6
GROUP BY p.province_id
ORDER BY (pct_health + pct_schools) ASC   -- lowest combined service score first
LIMIT 10;


-- Q5c. Triple deprivation: settlements with NO health, NO school, NO aid (Round 6)
SELECT
    p.province_name,
    COUNT(*)                            AS triply_deprived_settlements,
    ROUND(AVG(o.idp_arrivals), 0)       AS avg_idp_arrivals,
    ROUND(AVG(o.security_situation), 2) AS avg_security
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
WHERE o.round_id                   = 6
  AND o.health_clinics_available   = 0
  AND o.schools_available          = 0
  AND o.humanitarian_aid_delivered = 0
GROUP BY p.province_id
ORDER BY triply_deprived_settlements DESC;
