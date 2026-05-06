-- =============================================================================
-- Afghanistan CBNA (Community-Based Needs Assessment) SQL Project
-- Schema: Table Definitions & Constraints
-- Author: Ahmadullah Ahmadzai
-- Data Source: IOM Afghanistan CBNA Dataset
--              Rounds 10–16 (Jun 2020 – 2022)
-- =============================================================================


-- =============================================================================
-- TABLE 1: provinces
-- Administrative Level 1 — 34 Afghan provinces
-- =============================================================================
CREATE TABLE IF NOT EXISTS provinces (
    province_id     INTEGER PRIMARY KEY,
    province_name   TEXT    NOT NULL,
    adm1_code       TEXT    NOT NULL UNIQUE  -- e.g. AF01 = Kabul
);


-- =============================================================================
-- TABLE 2: districts
-- Administrative Level 2 — 394 districts nested within provinces
-- =============================================================================
CREATE TABLE IF NOT EXISTS districts (
    district_id     INTEGER PRIMARY KEY,
    adm2_code       TEXT    NOT NULL UNIQUE, -- e.g. AF0101
    district_name   TEXT    NOT NULL,
    province_id     INTEGER NOT NULL,
    FOREIGN KEY (province_id) REFERENCES provinces(province_id)
);


-- =============================================================================
-- TABLE 3: settlements
-- 10,802 unique assessed settlements (villages / camps / urban pockets)
-- =============================================================================
CREATE TABLE IF NOT EXISTS settlements (
    settlement_id   INTEGER PRIMARY KEY,
    settlement_code TEXT    NOT NULL UNIQUE, -- e.g. AF0101_V_0001
    settlement_name TEXT,
    adm2_code       TEXT    NOT NULL,
    longitude       REAL,
    latitude        REAL,
    pashtun_greg    REAL,   -- Pashtun share (Gregory classification)
    pashtun_ethno   REAL,   -- Pashtun share (ethnographic classification)
    FOREIGN KEY (adm2_code) REFERENCES districts(adm2_code)
);


-- =============================================================================
-- TABLE 4: survey_rounds
-- Six rounds of data collection mapped to real-world periods
-- =============================================================================
CREATE TABLE IF NOT EXISTS survey_rounds (
    round_id        INTEGER PRIMARY KEY,  -- 1–6 (internal ID)
    round_label     TEXT    NOT NULL,     -- e.g. "Round 10"
    round_period    TEXT    NOT NULL      -- e.g. "Jun 2020"
);


-- =============================================================================
-- TABLE 5: observations  (FACT TABLE)
-- One row per settlement × round — 64,812 rows total
-- Core displacement, security, services and humanitarian aid indicators
-- =============================================================================
CREATE TABLE IF NOT EXISTS observations (
    observation_id              INTEGER PRIMARY KEY,
    settlement_id               INTEGER NOT NULL,
    round_id                    INTEGER NOT NULL,

    -- Population
    host_population             INTEGER,   -- Estimated host community size
    idp_arrivals                INTEGER,   -- Number of IDP arrivals
    change_idp_arrivals         REAL,      -- Change vs. previous round (%)

    -- IDP cause severity (0=none … 5=extreme)
    idp_conflict_severity       INTEGER,
    idp_disaster_severity       INTEGER,

    -- Security (0=none … 5=extreme)
    security_situation          INTEGER,

    -- Basic services (1=available, 0=not available)
    health_clinics_available    INTEGER,
    schools_available           INTEGER,

    -- Humanitarian aid delivery
    humanitarian_aid_delivered  INTEGER,   -- 1=delivered, 0=not delivered
    aid_emergency_shelter       INTEGER,
    aid_food_distribution       INTEGER,
    aid_cash                    INTEGER,
    aid_infrastructure          INTEGER,

    -- Difference-in-Differences (DiD) evaluation variables
    post_intervention           INTEGER,   -- 1=post-intervention period
    diff_in_diff                INTEGER,   -- 1=treatment group

    -- IDP resolution outcomes — conflict (1=resolved indicator triggered)
    conflict_res_1              INTEGER,
    conflict_res_2              INTEGER,
    conflict_res_3              INTEGER,
    conflict_res_4              INTEGER,
    conflict_res_5              INTEGER,

    -- IDP resolution outcomes — natural disaster
    disaster_res_1              INTEGER,
    disaster_res_2              INTEGER,
    disaster_res_3              INTEGER,
    disaster_res_4              INTEGER,
    disaster_res_5              INTEGER,

    FOREIGN KEY (settlement_id) REFERENCES settlements(settlement_id),
    FOREIGN KEY (round_id)      REFERENCES survey_rounds(round_id),
    UNIQUE (settlement_id, round_id)   -- each settlement assessed once per round
);


-- =============================================================================
-- INDEXES — speed up common filter/join patterns
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_obs_settlement  ON observations(settlement_id);
CREATE INDEX IF NOT EXISTS idx_obs_round        ON observations(round_id);
CREATE INDEX IF NOT EXISTS idx_obs_province     ON settlements(adm2_code);
CREATE INDEX IF NOT EXISTS idx_dist_province    ON districts(province_id);
