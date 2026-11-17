-- =====================================================================================
-- 03 | Missing values and data profiling
-- CLASSIFICATION: all checks here test GENUINE DATA QUALITY (is the data complete and well-formed?)
-- =====================================================================================
-- PURPOSE
--   Confirm every column is populated and sane before we test relationships and logic.
-- NOT NULL constraints do not prevent blank text or coercion to zero and zero-dates.
-- Completeness checks include these possible substitutes.
-- =====================================================================================

-- ---------- 3.1 NULL / blank count per column (one query per table) ----------
-- Each *_missing column counts rows where the value is NULL or only spaces.

SELECT COUNT(*) AS total_rows,
       SUM(id IS NULL) AS id_missing, SUM(tier IS NULL) AS tier_missing,
       SUM(monthly_fee IS NULL) AS fee_missing, SUM(classes_per_month IS NULL) AS allowance_missing
FROM club_raw.plans;

SELECT COUNT(*) AS total_rows,
       SUM(id IS NULL) AS id_missing,
       SUM(first_name IS NULL OR TRIM(first_name) = '') AS first_name_missing,
       SUM(last_name  IS NULL OR TRIM(last_name)  = '') AS last_name_missing,
       SUM(engagement IS NULL OR TRIM(engagement) = '') AS engagement_missing,
       SUM(qualified_on IS NULL) AS qualified_on_missing
FROM club_raw.instructors;

SELECT COUNT(*) AS total_rows,
       SUM(id IS NULL) AS id_missing,
       SUM(first_name IS NULL OR TRIM(first_name) = '') AS first_name_missing,
       SUM(last_name  IS NULL OR TRIM(last_name)  = '') AS last_name_missing,
       SUM(email      IS NULL OR TRIM(email)      = '') AS email_missing,
       SUM(birth_date IS NULL) AS birth_date_missing,
       SUM(joined_on  IS NULL) AS joined_on_missing,
       SUM(plan_id    IS NULL) AS plan_id_missing
FROM club_raw.members;

SELECT COUNT(*) AS total_rows,
       SUM(id IS NULL) AS id_missing,
       SUM(title IS NULL OR TRIM(title) = '') AS title_missing,
       SUM(instructor_id IS NULL) AS instructor_id_missing,
       SUM(capacity IS NULL) AS capacity_missing,
       SUM(duration_minutes IS NULL) AS duration_missing,
       SUM(first_session_at IS NULL) AS first_session_missing
FROM club_raw.classes;

SELECT COUNT(*) AS total_rows,
       SUM(id IS NULL) AS id_missing, SUM(class_id IS NULL) AS class_id_missing,
       SUM(week_no IS NULL) AS week_no_missing, SUM(starts_at IS NULL) AS starts_at_missing
FROM club_raw.sessions;

SELECT COUNT(*) AS total_rows,
       SUM(id IS NULL) AS id_missing, SUM(session_id IS NULL) AS session_id_missing,
       SUM(member_id IS NULL) AS member_id_missing, SUM(hours_ahead IS NULL) AS hours_ahead_missing,
       SUM(status IS NULL OR TRIM(status) = '') AS status_missing
FROM club_raw.bookings;

SELECT COUNT(*) AS total_rows,
       SUM(id IS NULL) AS id_missing, SUM(member_id IS NULL) AS member_id_missing,
       SUM(checked_in_at IS NULL) AS checked_in_at_missing,
       SUM(method IS NULL OR TRIM(method) = '') AS method_missing,
       SUM(minutes_inside IS NULL) AS minutes_inside_missing
FROM club_raw.check_ins;

-- ---------- 3.2 Silent substitutes: zeros and zero-dates where a real value is required ----------
-- Check for numeric and date placeholders that may result from import coercion.
SELECT 'plans.monthly_fee <= 0' AS test, COUNT(*) AS rows_found FROM club_raw.plans WHERE monthly_fee <= 0
UNION ALL SELECT 'plans.classes_per_month <= 0', COUNT(*) FROM club_raw.plans WHERE classes_per_month <= 0
UNION ALL SELECT 'classes.capacity <= 0',        COUNT(*) FROM club_raw.classes WHERE capacity <= 0
UNION ALL SELECT 'classes.duration_minutes <= 0',COUNT(*) FROM club_raw.classes WHERE duration_minutes <= 0
UNION ALL SELECT 'sessions.week_no = 0',         COUNT(*) FROM club_raw.sessions WHERE week_no = 0
UNION ALL SELECT 'bookings.hours_ahead = 0',     COUNT(*) FROM club_raw.bookings WHERE hours_ahead = 0
UNION ALL SELECT 'check_ins.minutes_inside = 0', COUNT(*) FROM club_raw.check_ins WHERE minutes_inside = 0
UNION ALL SELECT 'members.birth_date year < 1900', COUNT(*) FROM club_raw.members WHERE YEAR(birth_date) < 1900
UNION ALL SELECT 'members.joined_on year < 1900',  COUNT(*) FROM club_raw.members WHERE YEAR(joined_on) < 1900
UNION ALL SELECT 'instructors.qualified_on year < 1900', COUNT(*) FROM club_raw.instructors WHERE YEAR(qualified_on) < 1900
UNION ALL SELECT 'classes.first_session_at year < 1900', COUNT(*) FROM club_raw.classes WHERE YEAR(first_session_at) < 1900
UNION ALL SELECT 'sessions.starts_at year < 1900',       COUNT(*) FROM club_raw.sessions WHERE YEAR(starts_at) < 1900
UNION ALL SELECT 'check_ins.checked_in_at year < 1900',  COUNT(*) FROM club_raw.check_ins WHERE YEAR(checked_in_at) < 1900;

-- ---------- 3.3 Hidden whitespace and non-printable characters in every text column ----------
-- TRIM identifies surrounding spaces; the ASCII pattern flags characters outside printable ASCII for review.
SELECT 'members.first_name' AS column_tested, COUNT(*) AS rows_found FROM club_raw.members WHERE first_name <> TRIM(first_name) OR first_name REGEXP '[^ -~]'
UNION ALL SELECT 'members.last_name',  COUNT(*) FROM club_raw.members WHERE last_name  <> TRIM(last_name)  OR last_name  REGEXP '[^ -~]'
UNION ALL SELECT 'members.email',      COUNT(*) FROM club_raw.members WHERE email      <> TRIM(email)      OR email      REGEXP '[^ -~]'
UNION ALL SELECT 'instructors.first_name', COUNT(*) FROM club_raw.instructors WHERE first_name <> TRIM(first_name) OR first_name REGEXP '[^ -~]'
UNION ALL SELECT 'instructors.last_name',  COUNT(*) FROM club_raw.instructors WHERE last_name  <> TRIM(last_name)  OR last_name  REGEXP '[^ -~]'
UNION ALL SELECT 'instructors.engagement', COUNT(*) FROM club_raw.instructors WHERE engagement <> TRIM(engagement) OR engagement REGEXP '[^ -~]'
UNION ALL SELECT 'classes.title',      COUNT(*) FROM club_raw.classes WHERE title <> TRIM(title) OR title REGEXP '[^ -~]'
UNION ALL SELECT 'bookings.status',    COUNT(*) FROM club_raw.bookings WHERE status <> TRIM(status) OR status REGEXP '[^ -~]'
UNION ALL SELECT 'check_ins.method',   COUNT(*) FROM club_raw.check_ins WHERE method <> TRIM(method) OR method REGEXP '[^ -~]';

-- ---------- 3.4 Value ranges for every numeric and date column ----------
-- Profile source ranges against the data dictionary.
SELECT 'plans.monthly_fee' AS column_tested, MIN(monthly_fee) AS min_value, MAX(monthly_fee) AS max_value FROM club_raw.plans
UNION ALL SELECT 'plans.classes_per_month', MIN(classes_per_month), MAX(classes_per_month) FROM club_raw.plans
UNION ALL SELECT 'classes.capacity',        MIN(capacity), MAX(capacity) FROM club_raw.classes
UNION ALL SELECT 'classes.duration_minutes',MIN(duration_minutes), MAX(duration_minutes) FROM club_raw.classes
UNION ALL SELECT 'sessions.week_no',        MIN(week_no), MAX(week_no) FROM club_raw.sessions
UNION ALL SELECT 'bookings.hours_ahead',    MIN(hours_ahead), MAX(hours_ahead) FROM club_raw.bookings
UNION ALL SELECT 'check_ins.minutes_inside',MIN(minutes_inside), MAX(minutes_inside) FROM club_raw.check_ins
UNION ALL SELECT 'members.birth_date',      MIN(birth_date), MAX(birth_date) FROM club_raw.members
UNION ALL SELECT 'members.joined_on',       MIN(joined_on), MAX(joined_on) FROM club_raw.members
UNION ALL SELECT 'instructors.qualified_on',MIN(qualified_on), MAX(qualified_on) FROM club_raw.instructors
UNION ALL SELECT 'classes.first_session_at',MIN(first_session_at), MAX(first_session_at) FROM club_raw.classes
UNION ALL SELECT 'sessions.starts_at',      MIN(starts_at), MAX(starts_at) FROM club_raw.sessions
UNION ALL SELECT 'check_ins.checked_in_at', MIN(checked_in_at), MAX(checked_in_at) FROM club_raw.check_ins;

-- ---------- 3.5 Allowed-value lists for categorical columns ----------
-- Profile category frequencies and identify unexpected labels.
SELECT status, COUNT(*) AS bookings FROM club_raw.bookings GROUP BY status ORDER BY bookings DESC;
SELECT method, COUNT(*) AS check_ins FROM club_raw.check_ins GROUP BY method ORDER BY check_ins DESC;
SELECT engagement, COUNT(*) AS instructors FROM club_raw.instructors GROUP BY engagement ORDER BY instructors DESC;

