-- =====================================================================================
-- 02 | CSV ingestion and source preservation
-- =====================================================================================
-- PURPOSE
--   Load each CSV into its club_raw table exactly as supplied, prove the load was
--   complete, record a fingerprint of the original data, and (optionally) lock club_raw.
--
-- Import configuration: replace C:/club_data/ with the local CSV directory.
-- LOAD DATA LOCAL INFILE requires both server and client support.
-- MySQL Workbench client option: OPT_LOCAL_INFILE=1.
-- Administrative privileges are required to change the global server setting.
--
-- Source CSVs use CRLF line endings. The import terminator must match the source files.
-- Foreign-key dependencies determine the load order.
-- LOAD DATA LOCAL INFILE can convert errors into warnings; warnings and row counts are audited.
-- =====================================================================================

SET GLOBAL local_infile = 1;                       -- server switch (admin account needed)
SHOW VARIABLES LIKE 'local_infile';

-- ---------------------------- LOADS (parents first) ----------------------------------
-- IGNORE 1 LINES skips the header row. The column list maps CSV columns, in file order,
-- to table columns. Text is loaded as-is: no trimming, no case changes, no deduplication.

LOAD DATA LOCAL INFILE 'C:/club_data/plans.csv'
INTO TABLE club_raw.plans
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, tier, monthly_fee, classes_per_month);
SHOW WARNINGS;

LOAD DATA LOCAL INFILE 'C:/club_data/instructors.csv'
INTO TABLE club_raw.instructors
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, first_name, last_name, engagement, qualified_on);
SHOW WARNINGS;

LOAD DATA LOCAL INFILE 'C:/club_data/members.csv'
INTO TABLE club_raw.members
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, first_name, last_name, email, birth_date, joined_on, plan_id);
SHOW WARNINGS;

LOAD DATA LOCAL INFILE 'C:/club_data/classes.csv'
INTO TABLE club_raw.classes
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, title, instructor_id, capacity, duration_minutes, first_session_at);
SHOW WARNINGS;

LOAD DATA LOCAL INFILE 'C:/club_data/sessions.csv'
INTO TABLE club_raw.sessions
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, class_id, week_no, starts_at);
SHOW WARNINGS;

LOAD DATA LOCAL INFILE 'C:/club_data/bookings.csv'
INTO TABLE club_raw.bookings
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, session_id, member_id, hours_ahead, status);
SHOW WARNINGS;

LOAD DATA LOCAL INFILE 'C:/club_data/check_ins.csv'
INTO TABLE club_raw.check_ins
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, member_id, checked_in_at, method, minutes_inside);
SHOW WARNINGS;

-- ---------------------------- VERIFY THE LOAD ----------------------------------------
-- V1. Row counts against the number of data rows in each CSV (file lines minus header).
-- Compare loaded counts against the source inventory to detect incomplete imports.
SELECT t.table_name, t.rows_loaded, t.rows_expected,
       IF(t.rows_loaded = t.rows_expected, 'PASS', 'FAIL') AS result
FROM (
  SELECT 'plans'       AS table_name, COUNT(*) AS rows_loaded,    4 AS rows_expected FROM club_raw.plans
  UNION ALL SELECT 'instructors',  COUNT(*),    8 FROM club_raw.instructors
  UNION ALL SELECT 'members',      COUNT(*),  120 FROM club_raw.members
  UNION ALL SELECT 'classes',      COUNT(*),   14 FROM club_raw.classes
  UNION ALL SELECT 'sessions',     COUNT(*),  112 FROM club_raw.sessions
  UNION ALL SELECT 'bookings',     COUNT(*),  778 FROM club_raw.bookings
  UNION ALL SELECT 'check_ins',    COUNT(*), 1044 FROM club_raw.check_ins
) AS t;

-- V2. Hidden carriage-return test. If the line terminator was wrong, the LAST column of each
--     row would end in an invisible \r. The last text column is bookings.status.
SELECT COUNT(*) AS rows_with_hidden_cr
FROM   club_raw.bookings
WHERE  status LIKE '%\r%';

-- ---------------------------- PRESERVE THE ORIGINALS ---------------------------------
-- Baseline row counts and summed row-level CRC32 checksums support source-preservation checks.
-- This is a lightweight integrity indicator, not a cryptographic guarantee.

CREATE TABLE club_clean.raw_baseline (
  table_name          VARCHAR(30)     NOT NULL,
  row_count           INT UNSIGNED    NOT NULL,
  content_fingerprint BIGINT UNSIGNED NOT NULL,
  captured_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (table_name)
) ENGINE=InnoDB;

-- A view that always computes the CURRENT fingerprint of club_raw.
CREATE OR REPLACE VIEW club_clean.v_raw_fingerprint_now AS
SELECT 'plans' AS table_name, COUNT(*) AS row_count,
       SUM(CRC32(CONCAT_WS('|', id, tier, monthly_fee, classes_per_month))) AS content_fingerprint
FROM club_raw.plans
UNION ALL SELECT 'instructors', COUNT(*), SUM(CRC32(CONCAT_WS('|', id, first_name, last_name, engagement, qualified_on))) FROM club_raw.instructors
UNION ALL SELECT 'members', COUNT(*), SUM(CRC32(CONCAT_WS('|', id, first_name, last_name, email, birth_date, joined_on, plan_id))) FROM club_raw.members
UNION ALL SELECT 'classes', COUNT(*), SUM(CRC32(CONCAT_WS('|', id, title, instructor_id, capacity, duration_minutes, first_session_at))) FROM club_raw.classes
UNION ALL SELECT 'sessions', COUNT(*), SUM(CRC32(CONCAT_WS('|', id, class_id, week_no, starts_at))) FROM club_raw.sessions
UNION ALL SELECT 'bookings', COUNT(*), SUM(CRC32(CONCAT_WS('|', id, session_id, member_id, hours_ahead, status))) FROM club_raw.bookings
UNION ALL SELECT 'check_ins', COUNT(*), SUM(CRC32(CONCAT_WS('|', id, member_id, checked_in_at, method, minutes_inside))) FROM club_raw.check_ins;

-- Capture the initial baseline once, after a successful load.
INSERT INTO club_clean.raw_baseline (table_name, row_count, content_fingerprint)
SELECT table_name, row_count, content_fingerprint FROM club_clean.v_raw_fingerprint_now;

-- Compare the current row counts and fingerprints with the original baseline.
SELECT b.table_name, b.row_count AS rows_at_load, n.row_count AS rows_now,
       IF(b.row_count = n.row_count AND b.content_fingerprint = n.content_fingerprint,
          'UNCHANGED', 'CHANGED - INVESTIGATE') AS integrity
FROM   club_clean.raw_baseline b
JOIN   club_clean.v_raw_fingerprint_now n ON n.table_name = b.table_name
ORDER  BY b.table_name;

-- Optional administrative protection: raw-schema read-only mode (MySQL 8.0.22+).
-- ALTER DATABASE club_raw READ ONLY = 1;
