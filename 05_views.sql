-- =============================================================================
-- Afghanistan CBNA SQL Project
-- Script 05: Views — Reusable Reporting Layers
-- =============================================================================
-- PURPOSE: Create SQL VIEWs that act as pre-built report layers.
--          These simplify downstream queries and demonstrate good database
--          design (separation of raw tables from reporting logic).
-- =============================================================================


-- ──────────────────────────────────────────────────────────────────────────────
-- VIEW 1: vw_settlement_full
-- Fully joined settlement profile — avoids repetitive JOIN boilerplate
-- ──────────────────────────────────────────────────────────────────────────────
CREATE VIEW IF NOT EXISTS vw_settlement_full AS
SELECT
    s.settlement_id,
    s.settlement_code,
    s.settlement_name,
    s.longitude,
    s.latitude,
    d.adm2_code,
    d.district_name,
    p.province_id,
    p.province_name,
    p.adm1_code,
    s.pashtun_greg,
    s.pashtun_ethno
FROM settlements s
JOIN districts   d ON s.adm2_code   = d.adm2_code
JOIN provinces   p ON d.province_id = p.province_id;

-- Usage example:
-- SELECT * FROM vw_settlement_full WHERE province_name = 'Kabul';


-- ──────────────────────────────────────────────────────────────────────────────
-- VIEW 2: vw_observations_full
-- Single flat view of all observations with geography and round labels
-- ──────────────────────────────────────────────────────────────────────────────
CREATE VIEW IF NOT EXISTS vw_observations_full AS
SELECT
    o.observation_id,
    -- Geography
    sf.settlement_code,
    sf.settlement_name,
    sf.district_name,
    sf.province_name,
    sf.adm1_code,
    sf.longitude,
    sf.latitude,
    -- Time
    sr.round_id,
    sr.round_label,
    sr.round_period,
    -- Population & displacement
    o.host_population,
    o.idp_arrivals,
    o.change_idp_arrivals,
    o.idp_conflict_severity,
    o.idp_disaster_severity,
    -- Security
    o.security_situation,
    CASE o.security_situation
        WHEN 0 THEN 'No Threat'
        WHEN 1 THEN 'Minimal'
        WHEN 2 THEN 'Low'
        WHEN 3 THEN 'Moderate'
        WHEN 4 THEN 'High'
        WHEN 5 THEN 'Extreme'
    END                         AS security_label,
    -- Services
    o.health_clinics_available,
    o.schools_available,
    -- Humanitarian aid
    o.humanitarian_aid_delivered,
    o.aid_emergency_shelter,
    o.aid_food_distribution,
    o.aid_cash,
    o.aid_infrastructure,
    -- Evaluation flags
    o.post_intervention,
    o.diff_in_diff,
    -- Resolution outcomes
    o.conflict_res_1, o.conflict_res_2, o.conflict_res_3,
    o.conflict_res_4, o.conflict_res_5,
    o.disaster_res_1, o.disaster_res_2, o.disaster_res_3,
    o.disaster_res_4, o.disaster_res_5
FROM observations        o
JOIN vw_settlement_full sf ON o.settlement_id = sf.settlement_id
JOIN survey_rounds      sr ON o.round_id      = sr.round_id;

-- Usage examples:
-- SELECT * FROM vw_observations_full WHERE province_name = 'Herat' AND round_id = 6;
-- SELECT province_name, AVG(idp_arrivals) FROM vw_observations_full GROUP BY province_name;


-- ──────────────────────────────────────────────────────────────────────────────
-- VIEW 3: vw_province_summary
-- Pre-aggregated province dashboard — one row per province × round
-- ──────────────────────────────────────────────────────────────────────────────
CREATE VIEW IF NOT EXISTS vw_province_summary AS
SELECT
    o.round_id,
    sr.round_label,
    sr.round_period,
    p.province_id,
    p.province_name,
    COUNT(DISTINCT s.settlement_id)                     AS settlements_assessed,
    SUM(o.idp_arrivals)                                 AS total_idp_arrivals,
    ROUND(AVG(o.idp_arrivals), 1)                       AS avg_idp_per_settlement,
    MAX(o.idp_arrivals)                                 AS max_idp_settlement,
    ROUND(AVG(o.security_situation), 3)                 AS avg_security_score,
    SUM(CASE WHEN o.security_situation >= 4 THEN 1 ELSE 0 END) AS high_threat_count,
    ROUND(AVG(o.humanitarian_aid_delivered) * 100.0, 1) AS pct_aid_delivered,
    ROUND(AVG(o.health_clinics_available)   * 100.0, 1) AS pct_health_access,
    ROUND(AVG(o.schools_available)          * 100.0, 1) AS pct_school_access,
    ROUND(AVG(o.aid_food_distribution)      * 100.0, 1) AS pct_food_aid,
    ROUND(AVG(o.aid_cash)                   * 100.0, 1) AS pct_cash_aid,
    ROUND(AVG(o.aid_emergency_shelter)      * 100.0, 1) AS pct_shelter_aid
FROM observations  o
JOIN settlements   s  ON o.settlement_id = s.settlement_id
JOIN districts     d  ON s.adm2_code     = d.adm2_code
JOIN provinces     p  ON d.province_id   = p.province_id
JOIN survey_rounds sr ON o.round_id      = sr.round_id
GROUP BY o.round_id, p.province_id;

-- Usage example:
-- SELECT * FROM vw_province_summary WHERE province_name = 'Kabul' ORDER BY round_id;


-- ──────────────────────────────────────────────────────────────────────────────
-- VIEW 4: vw_national_dashboard
-- One row per survey round — national KPIs for executive summary
-- ──────────────────────────────────────────────────────────────────────────────
CREATE VIEW IF NOT EXISTS vw_national_dashboard AS
SELECT
    sr.round_id,
    sr.round_label,
    sr.round_period,
    COUNT(DISTINCT o.settlement_id)                         AS settlements_surveyed,
    SUM(o.idp_arrivals)                                     AS total_idp_arrivals,
    ROUND(AVG(o.idp_arrivals), 1)                           AS avg_idp_per_settlement,
    ROUND(AVG(o.security_situation), 3)                     AS national_avg_security,
    SUM(CASE WHEN o.security_situation >= 4 THEN 1 ELSE 0 END) AS high_threat_settlements,
    ROUND(AVG(o.humanitarian_aid_delivered) * 100.0, 1)     AS national_aid_coverage_pct,
    ROUND(AVG(o.health_clinics_available)   * 100.0, 1)     AS health_access_pct,
    ROUND(AVG(o.schools_available)          * 100.0, 1)     AS school_access_pct,
    -- Aid type breakdown
    ROUND(AVG(o.aid_food_distribution)      * 100.0, 1)     AS food_aid_pct,
    ROUND(AVG(o.aid_cash)                   * 100.0, 1)     AS cash_aid_pct,
    ROUND(AVG(o.aid_emergency_shelter)      * 100.0, 1)     AS shelter_aid_pct,
    ROUND(AVG(o.aid_infrastructure)         * 100.0, 1)     AS infra_aid_pct,
    -- High-severity counts
    SUM(CASE WHEN o.idp_conflict_severity >= 4 THEN 1 ELSE 0 END) AS high_conflict_displacement,
    SUM(CASE WHEN o.idp_disaster_severity >= 4 THEN 1 ELSE 0 END) AS high_disaster_displacement,
    -- Triple deprivation
    SUM(CASE
        WHEN o.health_clinics_available=0
         AND o.schools_available=0
         AND o.humanitarian_aid_delivered=0 THEN 1 ELSE 0
    END)                                                    AS triply_deprived_settlements
FROM observations  o
JOIN survey_rounds sr ON o.round_id = sr.round_id
GROUP BY o.round_id
ORDER BY o.round_id;

-- Usage:
-- SELECT * FROM vw_national_dashboard;


-- ──────────────────────────────────────────────────────────────────────────────
-- VIEW 5: vw_aid_gap
-- Settlements currently (Round 6) without aid but with high displacement
-- Ready-to-use for humanitarian prioritisation / targeting
-- ──────────────────────────────────────────────────────────────────────────────
CREATE VIEW IF NOT EXISTS vw_aid_gap AS
SELECT
    sf.province_name,
    sf.district_name,
    sf.settlement_code,
    sf.settlement_name,
    sf.latitude,
    sf.longitude,
    o.idp_arrivals,
    o.idp_conflict_severity,
    o.idp_disaster_severity,
    o.security_situation,
    o.health_clinics_available,
    o.schools_available,
    -- Priority score: higher = more urgent
    (o.idp_arrivals / 100)
    + (o.idp_conflict_severity * 50)
    + (o.idp_disaster_severity * 30)
    + ((5 - o.security_situation) * 10)  -- more accessible = higher operational priority
    + ((1 - o.health_clinics_available) * 20)
    + ((1 - o.schools_available) * 10)  AS priority_score
FROM observations        o
JOIN vw_settlement_full sf ON o.settlement_id = sf.settlement_id
WHERE o.round_id                   = 6
  AND o.humanitarian_aid_delivered = 0
  AND o.idp_arrivals               > 500
ORDER BY priority_score DESC;

-- Usage:
-- SELECT * FROM vw_aid_gap LIMIT 20;  -- top 20 priority locations for aid targeting


-- ──────────────────────────────────────────────────────────────────────────────
-- QUICK VERIFICATION: Run the national dashboard
-- ──────────────────────────────────────────────────────────────────────────────
SELECT * FROM vw_national_dashboard;
