-- =============================================================================
-- Afghanistan CBNA SQL Project
-- Script 06: Stored Queries for Portfolio Showcase
-- =============================================================================
-- PURPOSE: A curated set of "highlight" queries that demonstrate the full
--          range of SQL skills in one concise script. Ideal for a quick
--          portfolio walkthrough or README demonstration section.
-- =============================================================================


-- ════════════════════════════════════════════════════════════════════════════
--    QUERY 1 — Basic JOIN + Aggregation
--    "Which provinces had the highest total IDP arrivals in the last round?"
-- ════════════════════════════════════════════════════════════════════════════
SELECT
    p.province_name,
    SUM(o.idp_arrivals)                     AS total_idps,
    COUNT(DISTINCT s.settlement_id)         AS settlements,
    ROUND(AVG(o.security_situation), 2)     AS avg_security
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
WHERE o.round_id = 6
GROUP BY p.province_name
ORDER BY total_idps DESC
LIMIT 10;


-- ════════════════════════════════════════════════════════════════════════════
--    QUERY 2 — CASE WHEN + Conditional Aggregation
--    "Classify each province by aid coverage level"
-- ════════════════════════════════════════════════════════════════════════════
SELECT
    p.province_name,
    ROUND(AVG(o.humanitarian_aid_delivered) * 100.0, 1) AS aid_coverage_pct,
    CASE
        WHEN AVG(o.humanitarian_aid_delivered) >= 0.7  THEN 'High Coverage'
        WHEN AVG(o.humanitarian_aid_delivered) >= 0.4  THEN 'Moderate Coverage'
        WHEN AVG(o.humanitarian_aid_delivered) >= 0.2  THEN 'Low Coverage'
        ELSE                                                 'Critical Gap'
    END                                                 AS coverage_tier
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
GROUP BY p.province_name
ORDER BY aid_coverage_pct DESC;


-- ════════════════════════════════════════════════════════════════════════════
--    QUERY 3 — Subquery + HAVING
--    "Districts that ALWAYS had humanitarian aid delivered (all 6 rounds)"
-- ════════════════════════════════════════════════════════════════════════════
SELECT
    p.province_name,
    d.district_name,
    COUNT(DISTINCT s.settlement_id) AS settlements,
    COUNT(DISTINCT o.round_id)      AS rounds_with_full_aid
FROM observations  o
JOIN settlements   s ON o.settlement_id = s.settlement_id
JOIN districts     d ON s.adm2_code     = d.adm2_code
JOIN provinces     p ON d.province_id   = p.province_id
WHERE o.humanitarian_aid_delivered = 1
GROUP BY d.district_id
HAVING COUNT(DISTINCT o.round_id) = 6
ORDER BY settlements DESC;


-- ════════════════════════════════════════════════════════════════════════════
--    QUERY 4 — CTE + Window Function (LAG)
--    "Which settlements saw the biggest IDP surge between rounds 4 and 5?"
--     (i.e. the Taliban takeover period: Jun → Dec 2021)
-- ════════════════════════════════════════════════════════════════════════════
WITH round4 AS (
    SELECT settlement_id, idp_arrivals AS idp_r4
    FROM observations WHERE round_id = 4
),
round5 AS (
    SELECT settlement_id, idp_arrivals AS idp_r5
    FROM observations WHERE round_id = 5
)
SELECT
    p.province_name,
    d.district_name,
    s.settlement_name,
    r4.idp_r4,
    r5.idp_r5,
    r5.idp_r5 - r4.idp_r4                              AS absolute_increase,
    ROUND((r5.idp_r5 - r4.idp_r4) * 100.0
          / NULLIF(r4.idp_r4, 0), 1)                   AS pct_increase
FROM round4        r4
JOIN round5        r5 ON r4.settlement_id = r5.settlement_id
JOIN settlements   s  ON r4.settlement_id = s.settlement_id
JOIN districts     d  ON s.adm2_code      = d.adm2_code
JOIN provinces     p  ON d.province_id    = p.province_id
WHERE r5.idp_r5 > r4.idp_r4
ORDER BY absolute_increase DESC
LIMIT 15;


-- ════════════════════════════════════════════════════════════════════════════
--    QUERY 5 — Multi-CTE + RANK()
--    "Rank provinces by vulnerability on three dimensions simultaneously"
-- ════════════════════════════════════════════════════════════════════════════
WITH metrics AS (
    SELECT
        p.province_name,
        AVG(o.idp_arrivals)                   AS avg_idp,
        AVG(o.security_situation)             AS avg_sec,
        1 - AVG(o.humanitarian_aid_delivered) AS aid_gap
    FROM observations o
    JOIN settlements  s ON o.settlement_id = s.settlement_id
    JOIN districts    d ON s.adm2_code     = d.adm2_code
    JOIN provinces    p ON d.province_id   = p.province_id
    GROUP BY p.province_id
)
SELECT
    province_name,
    ROUND(avg_idp, 1)                               AS avg_idp_arrivals,
    ROUND(avg_sec, 3)                               AS avg_security,
    ROUND(aid_gap * 100.0, 1)                       AS aid_gap_pct,
    RANK() OVER (ORDER BY avg_idp  DESC)            AS rank_displacement,
    RANK() OVER (ORDER BY avg_sec  DESC)            AS rank_insecurity,
    RANK() OVER (ORDER BY aid_gap  DESC)            AS rank_aid_gap,
    -- Composite rank = sum of individual ranks (lower = worse overall)
    RANK() OVER (ORDER BY avg_idp DESC)
    + RANK() OVER (ORDER BY avg_sec DESC)
    + RANK() OVER (ORDER BY aid_gap DESC)           AS composite_rank_sum
FROM metrics
ORDER BY composite_rank_sum ASC
LIMIT 15;


-- ════════════════════════════════════════════════════════════════════════════
--    QUERY 6 — Difference-in-Differences (DiD)
--    "Did humanitarian intervention reduce IDP arrivals?"
-- ════════════════════════════════════════════════════════════════════════════
WITH group_means AS (
    SELECT
        post_intervention,
        diff_in_diff,
        ROUND(AVG(idp_arrivals), 4) AS mean_idp
    FROM observations
    GROUP BY post_intervention, diff_in_diff
)
SELECT
    'Control — Pre'   AS group_label,
    (SELECT mean_idp FROM group_means WHERE post_intervention=0 AND diff_in_diff=0) AS mean_idp
UNION ALL
SELECT 'Control — Post',
    (SELECT mean_idp FROM group_means WHERE post_intervention=1 AND diff_in_diff=0)
UNION ALL
SELECT 'Treatment — Pre',
    (SELECT mean_idp FROM group_means WHERE post_intervention=0 AND diff_in_diff=1)
UNION ALL
SELECT 'Treatment — Post',
    (SELECT mean_idp FROM group_means WHERE post_intervention=1 AND diff_in_diff=1)
UNION ALL
SELECT '──── DiD Estimator ────',
    ROUND(
        (
          (SELECT mean_idp FROM group_means WHERE post_intervention=1 AND diff_in_diff=1)
        - (SELECT mean_idp FROM group_means WHERE post_intervention=0 AND diff_in_diff=1)
        )
        -
        (
          (SELECT mean_idp FROM group_means WHERE post_intervention=1 AND diff_in_diff=0)
        - (SELECT mean_idp FROM group_means WHERE post_intervention=0 AND diff_in_diff=0)
        ),
    4);


-- ════════════════════════════════════════════════════════════════════════════
--    QUERY 7 — View Usage + Filtering
--    "Pull the national dashboard and flag rounds with declining school access"
-- ════════════════════════════════════════════════════════════════════════════
SELECT
    round_label,
    round_period,
    total_idp_arrivals,
    national_aid_coverage_pct,
    health_access_pct,
    school_access_pct,
    triply_deprived_settlements,
    CASE
        WHEN school_access_pct < LAG(school_access_pct) OVER (ORDER BY round_id)
        THEN '⚠ Declined'
        WHEN school_access_pct > LAG(school_access_pct) OVER (ORDER BY round_id)
        THEN '✓ Improved'
        ELSE '— Stable'
    END AS school_trend
FROM vw_national_dashboard
ORDER BY round_id;


-- ════════════════════════════════════════════════════════════════════════════
--    QUERY 8 — Geospatial Bounding Box Filter
--    "Settlements in the northern region (lat > 36°N)"
-- ════════════════════════════════════════════════════════════════════════════
SELECT
    sf.province_name,
    sf.district_name,
    sf.settlement_name,
    sf.latitude,
    sf.longitude,
    SUM(o.idp_arrivals)                     AS total_idps_all_rounds,
    ROUND(AVG(o.security_situation), 2)     AS avg_security
FROM vw_settlement_full sf
JOIN observations       o  ON sf.settlement_id = o.settlement_id
WHERE sf.latitude > 36.0
GROUP BY sf.settlement_id
ORDER BY total_idps_all_rounds DESC
LIMIT 20;
