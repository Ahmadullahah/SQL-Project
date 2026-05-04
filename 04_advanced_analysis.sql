-- =============================================================================
-- Afghanistan CBNA SQL Project
-- Script 04: Advanced Analysis — Window Functions, CTEs & DiD Evaluation
-- =============================================================================
-- PURPOSE: Demonstrate advanced SQL techniques on real humanitarian data:
--   1. Window functions (LAG, RANK, running totals, moving averages)
--   2. Recursive / multi-step CTEs
--   3. Difference-in-Differences (DiD) causal evaluation
--   4. Settlement-level longitudinal profiling
--   5. Composite vulnerability scoring
-- =============================================================================


-- ──────────────────────────────────────────────────────────────────────────────
-- SECTION 1: WINDOW FUNCTIONS
-- ──────────────────────────────────────────────────────────────────────────────

-- W1. IDP arrivals with running total AND round-over-round change
--     per settlement (longitudinal panel view)
SELECT
    s.settlement_code,
    s.settlement_name,
    p.province_name,
    sr.round_label,
    o.idp_arrivals,

    -- Change from previous round for this settlement
    LAG(o.idp_arrivals) OVER (
        PARTITION BY o.settlement_id
        ORDER BY o.round_id
    )                                               AS prev_round_arrivals,

    o.idp_arrivals - LAG(o.idp_arrivals) OVER (
        PARTITION BY o.settlement_id
        ORDER BY o.round_id
    )                                               AS round_change,

    -- Running cumulative IDP total per settlement
    SUM(o.idp_arrivals) OVER (
        PARTITION BY o.settlement_id
        ORDER BY o.round_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                               AS cumulative_idps,

    -- Settlement's rank within its province by IDP arrivals each round
    RANK() OVER (
        PARTITION BY d.province_id, o.round_id
        ORDER BY o.idp_arrivals DESC
    )                                               AS rank_in_province
FROM observations  o
JOIN settlements   s  ON o.settlement_id = s.settlement_id
JOIN districts     d  ON s.adm2_code     = d.adm2_code
JOIN provinces     p  ON d.province_id   = p.province_id
JOIN survey_rounds sr ON o.round_id      = sr.round_id
ORDER BY o.settlement_id, o.round_id
LIMIT 60;    -- show first 10 settlements × 6 rounds


-- W2. 3-round moving average of security situation per province
--     Smooths out survey-specific noise to see structural trends
WITH province_round_security AS (
    SELECT
        p.province_name,
        o.round_id,
        ROUND(AVG(o.security_situation), 4) AS avg_security
    FROM observations  o
    JOIN settlements   s ON o.settlement_id = s.settlement_id
    JOIN districts     d ON s.adm2_code     = d.adm2_code
    JOIN provinces     p ON d.province_id   = p.province_id
    GROUP BY p.province_id, o.round_id
)
SELECT
    province_name,
    round_id,
    avg_security,
    ROUND(AVG(avg_security) OVER (
        PARTITION BY province_name
        ORDER BY round_id
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 4)                               AS moving_avg_3_rounds
FROM province_round_security
ORDER BY province_name, round_id;


-- W3. Percentile ranking of provinces by total IDP burden
WITH province_totals AS (
    SELECT
        p.province_name,
        SUM(o.idp_arrivals)              AS total_idps,
        COUNT(DISTINCT s.settlement_id)  AS settlements
    FROM observations  o
    JOIN settlements   s ON o.settlement_id = s.settlement_id
    JOIN districts     d ON s.adm2_code     = d.adm2_code
    JOIN provinces     p ON d.province_id   = p.province_id
    GROUP BY p.province_id
)
SELECT
    province_name,
    total_idps,
    settlements,
    ROUND(total_idps * 1.0 / settlements, 1)                    AS idp_per_settlement,
    RANK()        OVER (ORDER BY total_idps DESC)               AS rank_by_total,
    NTILE(4)      OVER (ORDER BY total_idps DESC)               AS quartile,   -- 1=highest burden
    ROUND(
        PERCENT_RANK() OVER (ORDER BY total_idps) * 100.0, 1
    )                                                           AS percentile
FROM province_totals
ORDER BY total_idps DESC;


-- W4. Top-3 highest-IDP settlements per province in the most recent round
WITH ranked AS (
    SELECT
        p.province_name,
        s.settlement_name,
        d.district_name,
        o.idp_arrivals,
        o.security_situation,
        o.humanitarian_aid_delivered,
        ROW_NUMBER() OVER (
            PARTITION BY p.province_id
            ORDER BY o.idp_arrivals DESC
        ) AS rn
    FROM observations  o
    JOIN settlements   s ON o.settlement_id = s.settlement_id
    JOIN districts     d ON s.adm2_code     = d.adm2_code
    JOIN provinces     p ON d.province_id   = p.province_id
    WHERE o.round_id = 6
)
SELECT
    province_name,
    rn                           AS province_rank,
    settlement_name,
    district_name,
    idp_arrivals,
    security_situation,
    CASE humanitarian_aid_delivered WHEN 1 THEN 'Yes' ELSE 'No' END AS aid_delivered
FROM ranked
WHERE rn <= 3
ORDER BY province_name, rn;


-- ──────────────────────────────────────────────────────────────────────────────
-- SECTION 2: MULTI-STEP CTEs
-- ──────────────────────────────────────────────────────────────────────────────

-- C1. Identify settlements that WORSENED on all three key indicators
--     (IDP arrivals ↑, security ↑, aid delivery ↓) between Round 1 and Round 6
WITH round1 AS (
    SELECT settlement_id, idp_arrivals, security_situation, humanitarian_aid_delivered
    FROM observations WHERE round_id = 1
),
round6 AS (
    SELECT settlement_id, idp_arrivals, security_situation, humanitarian_aid_delivered
    FROM observations WHERE round_id = 6
),
deteriorated AS (
    SELECT
        r1.settlement_id,
        r1.idp_arrivals   AS idp_r1,  r6.idp_arrivals   AS idp_r6,
        r1.security_situation AS sec_r1, r6.security_situation AS sec_r6,
        r1.humanitarian_aid_delivered AS aid_r1, r6.humanitarian_aid_delivered AS aid_r6,
        r6.idp_arrivals - r1.idp_arrivals               AS idp_change,
        r6.security_situation - r1.security_situation   AS security_change
    FROM round1 r1
    JOIN round6 r6 ON r1.settlement_id = r6.settlement_id
    WHERE r6.idp_arrivals        > r1.idp_arrivals       -- more IDPs
      AND r6.security_situation  > r1.security_situation  -- worse security
      AND r6.humanitarian_aid_delivered < r1.humanitarian_aid_delivered -- lost aid
)
SELECT
    p.province_name,
    d.district_name,
    s.settlement_name,
    dt.idp_r1, dt.idp_r6, dt.idp_change,
    dt.sec_r1, dt.sec_r6, dt.security_change
FROM deteriorated dt
JOIN settlements  s ON dt.settlement_id = s.settlement_id
JOIN districts    d ON s.adm2_code      = d.adm2_code
JOIN provinces    p ON d.province_id    = p.province_id
ORDER BY dt.idp_change DESC
LIMIT 30;


-- C2. Province-level vulnerability composite score
--     Combines: displacement burden + insecurity + service gap + aid gap
WITH province_metrics AS (
    SELECT
        p.province_id,
        p.province_name,
        -- Normalise each metric to 0-1 range for scoring
        AVG(o.idp_arrivals)                     AS avg_idp,
        AVG(o.security_situation)               AS avg_sec,
        1 - AVG(o.health_clinics_available)     AS health_gap,   -- 1 = no access
        1 - AVG(o.schools_available)            AS school_gap,
        1 - AVG(o.humanitarian_aid_delivered)   AS aid_gap
    FROM observations  o
    JOIN settlements   s ON o.settlement_id = s.settlement_id
    JOIN districts     d ON s.adm2_code     = d.adm2_code
    JOIN provinces     p ON d.province_id   = p.province_id
    GROUP BY p.province_id
),
max_vals AS (
    SELECT
        MAX(avg_idp) AS max_idp,
        MAX(avg_sec) AS max_sec
    FROM province_metrics
)
SELECT
    pm.province_name,
    ROUND(pm.avg_idp, 1)    AS avg_idp_arrivals,
    ROUND(pm.avg_sec, 3)    AS avg_security_score,
    ROUND(pm.health_gap * 100.0, 1) AS health_gap_pct,
    ROUND(pm.school_gap * 100.0, 1) AS school_gap_pct,
    ROUND(pm.aid_gap    * 100.0, 1) AS aid_gap_pct,

    -- Composite vulnerability index (equal-weight, 0–100 scale)
    ROUND(
        (
            (pm.avg_idp / mv.max_idp)   * 25 +   -- displacement weight: 25%
            (pm.avg_sec / mv.max_sec)   * 25 +   -- security weight: 25%
            pm.health_gap               * 20 +   -- health access: 20%
            pm.school_gap               * 15 +   -- education access: 15%
            pm.aid_gap                  * 15      -- aid coverage: 15%
        ) * 100.0,
    2)                       AS vulnerability_index
FROM province_metrics pm
CROSS JOIN max_vals mv
ORDER BY vulnerability_index DESC;


-- ──────────────────────────────────────────────────────────────────────────────
-- SECTION 3: DIFFERENCE-IN-DIFFERENCES (DiD) EVALUATION
-- ──────────────────────────────────────────────────────────────────────────────
-- The dataset includes post_intervention and diff_in_diff flags that allow
-- a quasi-experimental evaluation of humanitarian intervention effects.
--
-- DiD groups:
--   Control  — Pre  (post=0, DiD=0): baseline, no intervention
--   Control  — Post (post=1, DiD=0): post period, no intervention
--   Treat    — Pre  (post=0, DiD=1): pre-intervention, treatment area
--   Treat    — Post (post=1, DiD=1): post-intervention, treatment area
--
-- DiD estimator = (TreatPost - TreatPre) - (CtrlPost - CtrlPre)
-- ──────────────────────────────────────────────────────────────────────────────

-- D1. DiD group means — IDP arrivals
SELECT
    CASE
        WHEN post_intervention=0 AND diff_in_diff=0 THEN 'Control   — Pre'
        WHEN post_intervention=1 AND diff_in_diff=0 THEN 'Control   — Post'
        WHEN post_intervention=0 AND diff_in_diff=1 THEN 'Treatment — Pre'
        WHEN post_intervention=1 AND diff_in_diff=1 THEN 'Treatment — Post'
    END                                         AS group_label,
    COUNT(*)                                    AS observations,
    ROUND(AVG(idp_arrivals), 2)                 AS avg_idp_arrivals,
    ROUND(AVG(security_situation), 3)           AS avg_security,
    ROUND(AVG(humanitarian_aid_delivered)*100,1)AS pct_aid_delivered,
    ROUND(AVG(health_clinics_available)  *100,1)AS pct_health_access,
    ROUND(AVG(schools_available)         *100,1)AS pct_school_access
FROM observations
GROUP BY post_intervention, diff_in_diff
ORDER BY diff_in_diff, post_intervention;


-- D2. DiD estimator calculation — IDP arrivals outcome
WITH group_means AS (
    SELECT
        post_intervention,
        diff_in_diff,
        AVG(idp_arrivals) AS mean_idp
    FROM observations
    GROUP BY post_intervention, diff_in_diff
)
SELECT
    -- ATT (Average Treatment Effect on the Treated)
    ROUND(
        (   -- Treatment Post
            (SELECT mean_idp FROM group_means WHERE post_intervention=1 AND diff_in_diff=1)
            -- Treatment Pre
          - (SELECT mean_idp FROM group_means WHERE post_intervention=0 AND diff_in_diff=1)
        )
        -
        (   -- Control Post
            (SELECT mean_idp FROM group_means WHERE post_intervention=1 AND diff_in_diff=0)
            -- Control Pre
          - (SELECT mean_idp FROM group_means WHERE post_intervention=0 AND diff_in_diff=0)
        ),
    4) AS did_estimator_idp_arrivals,

    -- Interpretation aid
    ROUND(
        (SELECT mean_idp FROM group_means WHERE post_intervention=1 AND diff_in_diff=1)
      - (SELECT mean_idp FROM group_means WHERE post_intervention=0 AND diff_in_diff=1),
    2) AS treatment_group_change,

    ROUND(
        (SELECT mean_idp FROM group_means WHERE post_intervention=1 AND diff_in_diff=0)
      - (SELECT mean_idp FROM group_means WHERE post_intervention=0 AND diff_in_diff=0),
    2) AS control_group_change;


-- D3. DiD by province — heterogeneous treatment effects
WITH province_did AS (
    SELECT
        p.province_name,
        AVG(CASE WHEN o.post_intervention=1 AND o.diff_in_diff=1 THEN o.idp_arrivals END) AS tp,
        AVG(CASE WHEN o.post_intervention=0 AND o.diff_in_diff=1 THEN o.idp_arrivals END) AS tc,
        AVG(CASE WHEN o.post_intervention=1 AND o.diff_in_diff=0 THEN o.idp_arrivals END) AS cp,
        AVG(CASE WHEN o.post_intervention=0 AND o.diff_in_diff=0 THEN o.idp_arrivals END) AS cc
    FROM observations  o
    JOIN settlements   s ON o.settlement_id = s.settlement_id
    JOIN districts     d ON s.adm2_code     = d.adm2_code
    JOIN provinces     p ON d.province_id   = p.province_id
    GROUP BY p.province_id
    HAVING tp IS NOT NULL AND tc IS NOT NULL
       AND cp IS NOT NULL AND cc IS NOT NULL
)
SELECT
    province_name,
    ROUND((tp - tc) - (cp - cc), 2) AS did_estimate,
    CASE
        WHEN (tp - tc) - (cp - cc) < 0 THEN 'Intervention reduced displacement'
        WHEN (tp - tc) - (cp - cc) > 0 THEN 'Displacement increased despite intervention'
        ELSE 'No effect'
    END                             AS interpretation
FROM province_did
ORDER BY did_estimate;


-- ──────────────────────────────────────────────────────────────────────────────
-- SECTION 4: LONGITUDINAL SETTLEMENT PROFILES
-- ──────────────────────────────────────────────────────────────────────────────

-- L1. Full trajectory for the 10 settlements with highest AVERAGE IDP arrivals
WITH top_settlements AS (
    SELECT settlement_id, ROUND(AVG(idp_arrivals), 0) AS avg_idp
    FROM observations
    GROUP BY settlement_id
    ORDER BY avg_idp DESC
    LIMIT 10
)
SELECT
    s.settlement_code,
    s.settlement_name,
    p.province_name,
    sr.round_label,
    sr.round_period,
    o.idp_arrivals,
    o.security_situation,
    CASE o.humanitarian_aid_delivered WHEN 1 THEN 'Yes' ELSE 'No' END AS aid,
    CASE o.health_clinics_available   WHEN 1 THEN 'Yes' ELSE 'No' END AS health,
    CASE o.schools_available          WHEN 1 THEN 'Yes' ELSE 'No' END AS schools
FROM observations  o
JOIN top_settlements ts ON o.settlement_id = ts.settlement_id
JOIN settlements    s  ON o.settlement_id = s.settlement_id
JOIN districts      d  ON s.adm2_code     = d.adm2_code
JOIN provinces      p  ON d.province_id   = p.province_id
JOIN survey_rounds  sr ON o.round_id      = sr.round_id
ORDER BY ts.avg_idp DESC, o.round_id;


-- L2. Settlements that experienced IDP surges (>50% jump between consecutive rounds)
WITH lagged AS (
    SELECT
        settlement_id,
        round_id,
        idp_arrivals,
        LAG(idp_arrivals) OVER (
            PARTITION BY settlement_id ORDER BY round_id
        ) AS prev_arrivals
    FROM observations
)
SELECT
    p.province_name,
    d.district_name,
    s.settlement_name,
    sr.round_label                              AS surge_round,
    l.prev_arrivals                             AS arrivals_before,
    l.idp_arrivals                              AS arrivals_after,
    ROUND(
        (l.idp_arrivals - l.prev_arrivals) * 100.0
        / NULLIF(l.prev_arrivals, 0),
    1)                                          AS pct_increase
FROM lagged         l
JOIN settlements    s  ON l.settlement_id = s.settlement_id
JOIN districts      d  ON s.adm2_code     = d.adm2_code
JOIN provinces      p  ON d.province_id   = p.province_id
JOIN survey_rounds  sr ON l.round_id      = sr.round_id
WHERE l.prev_arrivals > 0
  AND l.idp_arrivals  > l.prev_arrivals * 1.5   -- 50%+ surge
ORDER BY pct_increase DESC
LIMIT 30;
