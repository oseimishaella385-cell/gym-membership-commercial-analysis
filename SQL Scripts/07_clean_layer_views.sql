-- =====================================================================================
-- 07 | Clean analytical views and audit trail
-- =====================================================================================
-- PURPOSE
-- Create analytical views in club_clean without changing raw records.
--
-- Booking deduplication assumption, subject to business confirmation:
-- Retain one record per member-session pair, prioritising attended, then no_show, then cancelled.
-- The lowest ID breaks ties. Legitimate rebooking history may be lost from the analytical view;
-- original records and excluded records remain accessible for audit.
--
-- =====================================================================================

-- 7.1 v_bookings_flagged: EVERY raw booking row plus flags describing its duplicate status.
--   rows_in_group      how many raw rows share this member + session
--   keep_order         1 = the row the rule keeps, 2+ = surplus rows
--   is_exact_duplicate same session, member, lead time AND status as another row
--   has_conflicting_status  rows in the group disagree on status (MIN <> MAX of text)
CREATE OR REPLACE VIEW club_clean.v_bookings_flagged AS
SELECT b.id, b.session_id, b.member_id, b.hours_ahead, b.status,
       COUNT(*) OVER (PARTITION BY b.session_id, b.member_id)                           AS rows_in_group,
       ROW_NUMBER() OVER (PARTITION BY b.session_id, b.member_id
                          ORDER BY CASE b.status WHEN 'attended' THEN 1 WHEN 'no_show' THEN 2 ELSE 3 END,
                                   b.id)                                                 AS keep_order,
       COUNT(*) OVER (PARTITION BY b.session_id, b.member_id, b.hours_ahead, b.status) > 1 AS is_exact_duplicate,
       MIN(b.status) OVER (PARTITION BY b.session_id, b.member_id)
         <> MAX(b.status) OVER (PARTITION BY b.session_id, b.member_id)                  AS has_conflicting_status
FROM   club_raw.bookings b;

-- 7.2 v_bookings_clean: one row per member-session pair for reporting counts and rates.
CREATE OR REPLACE VIEW club_clean.v_bookings_clean AS
SELECT id, session_id, member_id, hours_ahead, status
FROM   club_clean.v_bookings_flagged
WHERE  keep_order = 1;

-- 7.3 v_bookings_excluded: the surplus rows the clean view hides, kept for audit and review.
CREATE OR REPLACE VIEW club_clean.v_bookings_excluded AS
SELECT id, session_id, member_id, hours_ahead, status, rows_in_group, is_exact_duplicate, has_conflicting_status
FROM   club_clean.v_bookings_flagged
WHERE  keep_order > 1;

-- 7.4 v_sessions_enriched: sessions joined to class and instructor, with the capacity needed
--     for utilisation work and the true calendar date (never use week_no for trends).
CREATE OR REPLACE VIEW club_clean.v_sessions_enriched AS
SELECT s.id AS session_id, s.class_id, c.title AS class_title, c.capacity, c.duration_minutes,
       c.instructor_id, CONCAT(i.first_name, ' ', i.last_name) AS instructor_name, i.engagement,
       s.week_no AS class_occurrence_no, s.starts_at, DATE(s.starts_at) AS session_date
FROM   club_raw.sessions s
JOIN   club_raw.classes c     ON c.id = s.class_id
JOIN   club_raw.instructors i ON i.id = c.instructor_id;

-- 7.5 v_members_enriched: members with plan details and age at joining.
CREATE OR REPLACE VIEW club_clean.v_members_enriched AS
SELECT m.id AS member_id, m.joined_on, m.plan_id, p.tier, p.monthly_fee, p.classes_per_month,
       TIMESTAMPDIFF(YEAR, m.birth_date, m.joined_on) AS age_at_joining,
       TIMESTAMPDIFF(YEAR, m.birth_date, m.joined_on) < 18 AS joined_under_18
FROM   club_raw.members m
JOIN   club_raw.plans p ON p.id = m.plan_id;

-- 7.6 v_check_ins_flagged: check-ins with flags for the anomalies that need business confirmation.
--   is_out_of_hours      entry between 00:00 and 05:59 (flagged, NOT removed: it may be legitimate)
CREATE OR REPLACE VIEW club_clean.v_check_ins_flagged AS
SELECT ci.id, ci.member_id, ci.checked_in_at, DATE(ci.checked_in_at) AS visit_date,
       ci.method, ci.minutes_inside,
       HOUR(ci.checked_in_at) < 6 AS is_out_of_hours
FROM   club_raw.check_ins ci;

-- ---------- 7.7 VERIFY THE CLEAN LAYER ----------
-- Reconcile source, retained and excluded booking populations.
SELECT (SELECT COUNT(*) FROM club_raw.bookings)             AS raw_rows,
       (SELECT COUNT(*) FROM club_clean.v_bookings_clean)   AS clean_rows,
       (SELECT COUNT(*) FROM club_clean.v_bookings_excluded) AS excluded_rows,
       (SELECT COUNT(*) FROM club_clean.v_bookings_flagged WHERE is_exact_duplicate) AS exact_duplicate_rows_flagged;

-- Test uniqueness at the member-session grain.
SELECT session_id, member_id, COUNT(*) AS rows_found
FROM   club_clean.v_bookings_clean
GROUP  BY session_id, member_id
HAVING COUNT(*) > 1;

-- Status mix before and after the rule. This shows what the dedup rule changes.
SELECT 'raw' AS version, status, COUNT(*) AS bookings FROM club_raw.bookings GROUP BY status
UNION ALL
SELECT 'clean', status, COUNT(*) FROM club_clean.v_bookings_clean GROUP BY status
ORDER BY version DESC, status;

-- Compare current source fingerprints with the ingestion baseline.
SELECT b.table_name,
       IF(b.row_count = n.row_count AND b.content_fingerprint = n.content_fingerprint, 'UNCHANGED', 'CHANGED - INVESTIGATE') AS integrity
FROM   club_clean.raw_baseline b JOIN club_clean.v_raw_fingerprint_now n ON n.table_name = b.table_name
ORDER  BY b.table_name;
