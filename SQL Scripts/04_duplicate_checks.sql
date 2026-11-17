-- =====================================================================================
-- 04 | Duplicate record assessment
-- CLASSIFICATION: GENUINE DATA QUALITY (duplicates distort every count and rate downstream)
-- =====================================================================================
-- PURPOSE
--   Find rows that appear more than once. Primary keys stop two rows sharing an id, but they
--   do NOT stop the same business event being recorded twice under different ids.
-- Read-only assessment; the source records are preserved and deduplication is implemented in Stage 07.
-- =====================================================================================

-- ---------- 4.1 Primary key sanity (all tables) ----------
-- Assess primary-key uniqueness and sequence completeness; gaps are not conclusive evidence of loss.
SELECT 'plans' AS table_name, COUNT(*) AS `rows`, COUNT(DISTINCT id) AS distinct_ids, MIN(id) AS min_id, MAX(id) AS max_id FROM club_raw.plans
UNION ALL SELECT 'instructors', COUNT(*), COUNT(DISTINCT id), MIN(id), MAX(id) FROM club_raw.instructors
UNION ALL SELECT 'members',     COUNT(*), COUNT(DISTINCT id), MIN(id), MAX(id) FROM club_raw.members
UNION ALL SELECT 'classes',     COUNT(*), COUNT(DISTINCT id), MIN(id), MAX(id) FROM club_raw.classes
UNION ALL SELECT 'sessions',    COUNT(*), COUNT(DISTINCT id), MIN(id), MAX(id) FROM club_raw.sessions
UNION ALL SELECT 'bookings',    COUNT(*), COUNT(DISTINCT id), MIN(id), MAX(id) FROM club_raw.bookings
UNION ALL SELECT 'check_ins',   COUNT(*), COUNT(DISTINCT id), MIN(id), MAX(id) FROM club_raw.check_ins;

-- ---------- 4.2 Bookings: EXACT duplicates ----------
-- Identify repeated business fields with distinct record IDs.
SELECT session_id, member_id, hours_ahead, status,
       COUNT(*) AS copies, GROUP_CONCAT(id ORDER BY id) AS booking_ids
FROM   club_raw.bookings
GROUP  BY session_id, member_id, hours_ahead, status
HAVING COUNT(*) > 1;

-- ---------- 4.3 Bookings: more than one row per member and session (summary) ----------
-- A member should hold one booking per session. Several rows may be an error OR a legitimate
-- history (cancelled, then re-booked). The summary separates the two patterns:
--   same_status_groups        = repeats with the same outcome -> very likely duplicates
--   conflicting_status_groups = repeats with different outcomes -> needs a business rule
WITH grp AS (
  SELECT session_id, member_id, COUNT(*) AS n_rows, COUNT(DISTINCT status) AS n_status
  FROM   club_raw.bookings
  GROUP  BY session_id, member_id
  HAVING COUNT(*) > 1                      -- keep only member-session pairs that repeat
)
SELECT COUNT(*)           AS duplicate_groups,
       SUM(n_rows)        AS rows_involved,
       SUM(n_rows - 1)    AS surplus_rows,  -- rows that would disappear if one per group were kept
       SUM(n_status = 1)  AS same_status_groups,
       SUM(n_status > 1)  AS conflicting_status_groups
FROM   grp;

-- ---------- 4.4 Bookings: which status patterns occur? ----------
-- Enumerate status combinations per member-session pair; booking IDs determine display order, not chronology.
SELECT pattern, COUNT(*) AS member_session_pairs
FROM (
  SELECT session_id, member_id, GROUP_CONCAT(status ORDER BY id SEPARATOR '|') AS pattern
  FROM   club_raw.bookings
  GROUP  BY session_id, member_id
  HAVING COUNT(*) > 1
) AS p
GROUP  BY pattern
ORDER  BY member_session_pairs DESC, pattern;

-- 4.5 Detailed review of affected booking rows.
-- group_size counts records sharing each member-session pair.
SELECT b.session_id, b.member_id, b.id AS booking_id, b.status, b.hours_ahead,
       COUNT(*) OVER (PARTITION BY b.session_id, b.member_id) AS group_size
FROM   club_raw.bookings b
WHERE  EXISTS (SELECT 1 FROM club_raw.bookings d
               WHERE d.session_id = b.session_id AND d.member_id = b.member_id AND d.id <> b.id)
ORDER  BY b.session_id, b.member_id, b.id;

-- ---------- 4.6 Check-ins: duplicates and near-duplicates ----------
-- (a) Exact duplicate check-ins: identical member and timestamp.
SELECT member_id, checked_in_at, COUNT(*) AS copies
FROM   club_raw.check_ins
GROUP  BY member_id, checked_in_at
HAVING COUNT(*) > 1;

-- (b) Near-duplicate check-ins within five minutes. LAG retrieves the preceding event per member.
SELECT member_id, prev_in, checked_in_at, TIMESTAMPDIFF(MINUTE, prev_in, checked_in_at) AS minutes_apart
FROM (
  SELECT member_id, checked_in_at,
         LAG(checked_in_at) OVER (PARTITION BY member_id ORDER BY checked_in_at) AS prev_in
  FROM   club_raw.check_ins
) AS x
WHERE  prev_in IS NOT NULL
  AND  TIMESTAMPDIFF(MINUTE, prev_in, checked_in_at) <= 5
ORDER  BY member_id, checked_in_at;

-- ---------- 4.7 Members: duplicate people ----------
-- Same email ignoring case, or the same name and date of birth under two member ids.
SELECT LOWER(email) AS email_lower, COUNT(*) AS members, GROUP_CONCAT(id ORDER BY id) AS member_ids
FROM   club_raw.members GROUP BY LOWER(email) HAVING COUNT(*) > 1;

SELECT LOWER(first_name) AS first_name, LOWER(last_name) AS last_name, birth_date,
       COUNT(*) AS members, GROUP_CONCAT(id ORDER BY id) AS member_ids
FROM   club_raw.members GROUP BY LOWER(first_name), LOWER(last_name), birth_date HAVING COUNT(*) > 1;

-- ---------- 4.8 Reference tables: duplicate sessions, classes, instructors, plans ----------
SELECT 'sessions: same class at same start time' AS test, COUNT(*) AS rows_found
FROM (SELECT class_id, starts_at FROM club_raw.sessions GROUP BY class_id, starts_at HAVING COUNT(*) > 1) x
UNION ALL SELECT 'classes: same title', COUNT(*)
FROM (SELECT LOWER(title) FROM club_raw.classes GROUP BY LOWER(title) HAVING COUNT(*) > 1) x
UNION ALL SELECT 'instructors: same full name', COUNT(*)
FROM (SELECT LOWER(first_name), LOWER(last_name) FROM club_raw.instructors GROUP BY LOWER(first_name), LOWER(last_name) HAVING COUNT(*) > 1) x
UNION ALL SELECT 'plans: same tier', COUNT(*)
FROM (SELECT tier FROM club_raw.plans GROUP BY tier HAVING COUNT(*) > 1) x;

-- Conflicting booking outcomes require a documented business rule; see Stage 07.
