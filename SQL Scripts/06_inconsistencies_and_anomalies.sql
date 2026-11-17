-- =====================================================================================
-- 06 | Inconsistencies, anomalies and coverage limitations
-- Classification of findings:
--   [DQ]       Genuine data-quality defect: the record is wrong, impossible or untrustworthy.
--   [COVERAGE] The data is correct but the datasets do not cover the same period or events.
--   [CONFIRM] Unusual observations requiring business confirmation.
-- Operational and commercial performance is assessed separately in Stage 08.
-- =====================================================================================
-- =====================================================================================

-- ======================= A. VALUE FORMAT AND CONSISTENCY ===============================

-- 6.1 [DQ] Email format. A valid-looking address has one @, no spaces and a dot in the domain.
SELECT id, email FROM club_raw.members
WHERE  email NOT REGEXP '^[^@ ]+@[^@ ]+[.][A-Za-z]{2,}$';

-- 6.2 [DQ] Flag digits or symbols in names; allow common punctuation and spaces.
SELECT 'members' AS source_table, id, first_name, last_name FROM club_raw.members
WHERE  CONCAT(first_name, last_name) REGEXP '[^A-Za-z '' -]'
UNION ALL
SELECT 'instructors', id, first_name, last_name FROM club_raw.instructors
WHERE  CONCAT(first_name, last_name) REGEXP '[^A-Za-z '' -]';

-- 6.3 [DQ] Allowed values: any status, method or engagement outside the agreed list.
SELECT 'bookings.status' AS column_tested, status AS bad_value, COUNT(*) AS rows_found
FROM club_raw.bookings WHERE status NOT IN ('attended', 'cancelled', 'no_show') GROUP BY status
UNION ALL SELECT 'check_ins.method', method, COUNT(*)
FROM club_raw.check_ins WHERE method NOT IN ('key_fob', 'app_qr', 'front_desk') GROUP BY method
UNION ALL SELECT 'instructors.engagement', engagement, COUNT(*)
FROM club_raw.instructors WHERE engagement NOT IN ('employee', 'freelance') GROUP BY engagement;

-- 6.4 [DQ] Assess fee and allowance progression by tier and redundancy between tier and ID.
SELECT id, tier, monthly_fee, classes_per_month,
       ROUND(monthly_fee / classes_per_month, 2) AS fee_per_class_allowance,
       IF(tier = id, 'tier = id (redundant)', 'tier differs from id') AS tier_note,
       IF(monthly_fee > LAG(monthly_fee) OVER (ORDER BY tier)
          AND classes_per_month > LAG(classes_per_month) OVER (ORDER BY tier), 'ok',
          IF(tier = 1, 'ok (lowest tier)', 'CHECK')) AS monotonic_flag
FROM   club_raw.plans ORDER BY tier;

-- ======================= B. DATE AND NUMBER PLAUSIBILITY ===============================

-- 6.5 [CONFIRM] Members who were under 18 on the day they joined.
-- Age-at-joining observations require confirmation of membership and consent policies.
SELECT id AS member_id, birth_date, joined_on,
       TIMESTAMPDIFF(YEAR, birth_date, joined_on) AS age_at_joining
FROM   club_raw.members
WHERE  TIMESTAMPDIFF(YEAR, birth_date, joined_on) < 18
ORDER  BY age_at_joining, birth_date;

-- 6.6 [DQ] Flag impossible or implausible dates and values.
SELECT 'members joined in the future' AS test, COUNT(*) AS rows_found FROM club_raw.members WHERE joined_on > CURDATE()
UNION ALL SELECT 'members aged over 90 at joining', COUNT(*) FROM club_raw.members WHERE TIMESTAMPDIFF(YEAR, birth_date, joined_on) > 90
UNION ALL SELECT 'instructors qualified in the future', COUNT(*) FROM club_raw.instructors WHERE qualified_on > CURDATE()
UNION ALL SELECT 'bookings with lead time over 7 days (168h)', COUNT(*) FROM club_raw.bookings WHERE hours_ahead > 168
UNION ALL SELECT 'visits longer than 4 hours', COUNT(*) FROM club_raw.check_ins WHERE minutes_inside > 240
UNION ALL SELECT 'visits shorter than 10 minutes', COUNT(*) FROM club_raw.check_ins WHERE minutes_inside < 10;

-- ======================= C. BOOKING LOGIC ==============================================

-- 6.7 [DQ] Overlapping bookings: one member holding two active (non-cancelled) bookings for
--     DIFFERENT sessions that run at the same time. A person cannot be in two classes at once.
--     Method: reduce to distinct member-session pairs (so duplicate rows from Stage 4 do not
--     inflate the count), pair them up, and test whether the two time windows intersect.
--     Window A = [start, start + duration). Intersect when each starts before the other ends.
WITH active AS (
  SELECT DISTINCT b.member_id, b.session_id, s.starts_at, c.duration_minutes, c.title
  FROM   club_raw.bookings b
  JOIN   club_raw.sessions s ON s.id = b.session_id
  JOIN   club_raw.classes  c ON c.id = s.class_id
  WHERE  b.status <> 'cancelled'
)
SELECT a1.member_id, a1.session_id AS session_a, a1.title AS class_a, a1.starts_at AS start_a,
       a2.session_id AS session_b, a2.title AS class_b, a2.starts_at AS start_b
FROM   active a1
JOIN   active a2 ON a2.member_id = a1.member_id AND a2.session_id > a1.session_id
WHERE  TIMESTAMPDIFF(MINUTE, a1.starts_at, a2.starts_at) < a1.duration_minutes   -- B starts before A ends
  AND  TIMESTAMPDIFF(MINUTE, a2.starts_at, a1.starts_at) < a2.duration_minutes   -- A starts before B ends
ORDER  BY a1.member_id, a1.starts_at;

-- ======================= D. CROSS-DATASET COVERAGE =====================================

-- 6.8 [COVERAGE] Each dataset's date window. The booking and class schedule runs to 6 Jul 2025
--     but check-ins stop at 29 Jun 2025, so any analysis joining them must use a common window.
SELECT 'check_ins'    AS dataset, MIN(checked_in_at) AS first_event, MAX(checked_in_at) AS last_event FROM club_raw.check_ins
UNION ALL SELECT 'sessions',  MIN(starts_at), MAX(starts_at) FROM club_raw.sessions
UNION ALL SELECT 'members (joined_on)', MIN(joined_on), MAX(joined_on) FROM club_raw.members;

-- 6.9 [COVERAGE] Sessions and bookings that fall AFTER the last check-in on file.
SELECT COUNT(DISTINCT s.id) AS sessions_after_checkin_data_ends,
       COUNT(b.id)          AS booking_rows,
       SUM(b.status = 'attended')  AS attended,
       SUM(b.status = 'cancelled') AS cancelled,
       SUM(b.status = 'no_show')   AS no_show
FROM   club_raw.sessions s
JOIN   club_raw.bookings b ON b.session_id = s.id
WHERE  s.starts_at > (SELECT MAX(checked_in_at) FROM club_raw.check_ins);

-- 6.10 [COVERAGE] Compare attended bookings with same-day check-ins.
-- A date-level match is not evidence of a specific class visit; attendance cannot be validated from entry events.
SELECT COUNT(*) AS attended_bookings,
       SUM(EXISTS (SELECT 1 FROM club_raw.check_ins ci
                   WHERE ci.member_id = b.member_id AND DATE(ci.checked_in_at) = DATE(s.starts_at))) AS with_same_day_checkin,
       ROUND(100 * SUM(EXISTS (SELECT 1 FROM club_raw.check_ins ci
                   WHERE ci.member_id = b.member_id AND DATE(ci.checked_in_at) = DATE(s.starts_at))) / COUNT(*), 1) AS pct_matched
FROM   club_raw.bookings b
JOIN   club_raw.sessions s ON s.id = b.session_id
WHERE  b.status = 'attended';

-- 6.11 [COVERAGE] week_no is NOT a calendar week. It counts weeks from each class's own first
--      session. This compares it with a true calendar week index (week 1 = week of Mon 5 May 2025).
-- Calendar dates, not class occurrence numbers, are the basis for time-series analysis.
SELECT COUNT(*) AS sessions,
       SUM(s.week_no = FLOOR(DATEDIFF(DATE(s.starts_at), '2025-05-05') / 7) + 1) AS week_no_equals_calendar_week
FROM   club_raw.sessions s;

-- ======================= E. CHECK-IN BEHAVIOUR =========================================

-- 6.12 [CONFIRM] Overnight check-ins: opening hours and timestamp conventions require confirmation.
SELECT HOUR(checked_in_at) AS hour_of_day, COUNT(*) AS check_ins
FROM   club_raw.check_ins
WHERE  HOUR(checked_in_at) < 6
GROUP  BY HOUR(checked_in_at)
ORDER  BY hour_of_day;

-- 6.13 [CONFIRM] Multiple check-ins per member-day may reflect legitimate re-entry.
SELECT COUNT(*) AS member_days_with_multiple_checkins
FROM (SELECT member_id, DATE(checked_in_at) AS visit_date
      FROM   club_raw.check_ins
      GROUP  BY member_id, DATE(checked_in_at)
      HAVING COUNT(*) > 1) AS d;

-- 6.14 [DQ] Identify apparent overlapping visits using the preceding entry and reported duration.
-- The interpretation depends on the reliability of minutes_inside and re-entry policy.
SELECT COUNT(*) AS overlapping_visit_pairs
FROM (
  SELECT checked_in_at,
         LAG(checked_in_at)    OVER (PARTITION BY member_id ORDER BY checked_in_at) AS prev_in,
         LAG(minutes_inside)   OVER (PARTITION BY member_id ORDER BY checked_in_at) AS prev_minutes
  FROM   club_raw.check_ins
) AS v
WHERE  prev_in IS NOT NULL
  AND  TIMESTAMPDIFF(MINUTE, prev_in, checked_in_at) < prev_minutes;

-- 6.15 [DQ - suspicion] Compare dwell-time distributions across entry methods.
-- Similar distributions may indicate a generated or derived field; no check-out time is available for verification.
SELECT method, COUNT(*) AS check_ins, ROUND(AVG(minutes_inside), 1) AS avg_minutes,
       ROUND(STDDEV_POP(minutes_inside), 1) AS stddev_minutes, MIN(minutes_inside) AS min_minutes, MAX(minutes_inside) AS max_minutes
FROM   club_raw.check_ins
GROUP  BY method
ORDER  BY method;

