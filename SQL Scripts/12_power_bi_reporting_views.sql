-- 12 | Power BI reporting layer | MySQL 8.0.22+ | Depends on Stages 09–11.
-- Each reporting view has a declared grain. No names, emails or birth dates.
USE club_clean;

-- One row per calendar date, covering both sources; no check-in coverage after 29 June.
CREATE OR REPLACE VIEW club_clean.pbi_date AS
WITH RECURSIVE calendar AS (
    SELECT CAST('2025-05-05' AS DATE) AS activity_date
    UNION ALL SELECT DATE_ADD(activity_date,INTERVAL 1 DAY) FROM calendar WHERE activity_date<'2025-07-06'
)
SELECT activity_date, DATE_SUB(activity_date,INTERVAL WEEKDAY(activity_date) DAY) AS week_start,
       YEAR(activity_date) AS calendar_year,MONTH(activity_date) AS month_number,
       DATE_FORMAT(activity_date,'%Y-%m') AS 'year_month',
       WEEKDAY(activity_date)+1 AS weekday_number,DAYNAME(activity_date) AS weekday_name,
       CASE WHEN activity_date<='2025-06-29' THEN 1 ELSE 0 END AS check_in_coverage
FROM calendar;

-- One row per member. Snapshot fields do not respond to activity-date filters.
-- Segment and upgrade flags refer to 5 May–29 June and June respectively.
CREATE OR REPLACE VIEW club_clean.pbi_members AS
SELECT m.member_id,m.plan_id,m.tier,m.monthly_fee,m.classes_per_month,
       e.engagement_segment,e.check_ins AS snapshot_check_ins,e.days_since_last_visit,
       j.june_attended,j.allowance_usage_pct,j.upgrade_lead,j.above_allowance,j.next_tier,j.illustrative_monthly_uplift
FROM v_members_enriched m
JOIN v_analysis_member_engagement e ON e.member_id=m.member_id
JOIN v_analysis_june_usage j ON j.member_id=m.member_id;

-- One row per session. The capacity column is safe to sum only at this grain.
CREATE OR REPLACE VIEW club_clean.pbi_sessions AS
SELECT session_id,class_id,class_title,instructor_id,engagement AS instructor_engagement,
       starts_at,session_date,WEEKDAY(session_date)+1 AS weekday_number,DAYNAME(session_date) AS weekday_name,
       HOUR(starts_at) AS hour_of_day,capacity,duration_minutes,
       over_capacity_flag,low_utilisation_flag
FROM v_analysis_session_performance;

-- One row per retained member/session booking. No fee or capacity here.
CREATE OR REPLACE VIEW club_clean.pbi_bookings AS
SELECT id AS booking_id,session_id,member_id,status,hours_ahead,
       CASE WHEN hours_ahead<=24 THEN '1. Within 24h' WHEN hours_ahead<=72 THEN '2. 25-72h'
            ELSE '3. Over 72h' END AS lead_time_band
FROM v_bookings_clean;

-- One row per entry event. No class identifier exists; never infer class attendance.
CREATE OR REPLACE VIEW club_clean.pbi_check_ins AS
SELECT id AS check_in_id,member_id,visit_date,checked_in_at,HOUR(checked_in_at) AS hour_of_day,
       method,is_out_of_hours
FROM v_check_ins_flagged;

-- Validate reporting-view grain by comparing row counts with distinct key counts.
SELECT 'pbi_date' AS view_name,COUNT(*) AS rows_found,COUNT(DISTINCT activity_date) AS unique_keys,63 AS expected FROM pbi_date
UNION ALL SELECT 'pbi_members',COUNT(*),COUNT(DISTINCT member_id),120 FROM pbi_members
UNION ALL SELECT 'pbi_sessions',COUNT(*),COUNT(DISTINCT session_id),112 FROM pbi_sessions
UNION ALL SELECT 'pbi_bookings',COUNT(*),COUNT(DISTINCT booking_id),745 FROM pbi_bookings
UNION ALL SELECT 'pbi_check_ins',COUNT(*),COUNT(DISTINCT check_in_id),1044 FROM pbi_check_ins;

-- Check referential integrity across the five Power BI relationships.
SELECT 'booking_member' AS relationship_name,COUNT(*) AS orphan_rows FROM pbi_bookings b LEFT JOIN pbi_members m ON m.member_id=b.member_id WHERE m.member_id IS NULL
UNION ALL SELECT 'booking_session',COUNT(*) FROM pbi_bookings b LEFT JOIN pbi_sessions s ON s.session_id=b.session_id WHERE s.session_id IS NULL
UNION ALL SELECT 'session_date',COUNT(*) FROM pbi_sessions s LEFT JOIN pbi_date d ON d.activity_date=s.session_date WHERE d.activity_date IS NULL
UNION ALL SELECT 'checkin_member',COUNT(*) FROM pbi_check_ins c LEFT JOIN pbi_members m ON m.member_id=c.member_id WHERE m.member_id IS NULL
UNION ALL SELECT 'checkin_date',COUNT(*) FROM pbi_check_ins c LEFT JOIN pbi_date d ON d.activity_date=c.visit_date WHERE d.activity_date IS NULL;

-- Verify that raw table fingerprints match the ingestion baseline.
SELECT b.table_name,IF(b.row_count=n.row_count AND b.content_fingerprint=n.content_fingerprint,'UNCHANGED','CHANGED - INVESTIGATE') AS integrity
FROM club_clean.raw_baseline b JOIN club_clean.v_raw_fingerprint_now n ON n.table_name=b.table_name ORDER BY b.table_name;
