-- 10 | Customer engagement | MySQL 8.0.22+
USE club_clean;
-- Check-ins and class outcomes are different events. Never add them to claim unique visits.
-- Compare member engagement only within the shared 8-week window (5 May–29 June 2025).
-- Aggregate each fact before joining to members, avoiding a many-to-many fan-out.
CREATE OR REPLACE VIEW club_clean.v_analysis_member_engagement AS
WITH visits AS (
    SELECT member_id, COUNT(*) AS check_ins, COUNT(DISTINCT visit_date) AS visit_days,
           MAX(visit_date) AS last_visit_date
    FROM v_check_ins_flagged
    WHERE visit_date BETWEEN '2025-05-05' AND '2025-06-29'
    GROUP BY member_id
), activity AS (
    SELECT b.member_id,COUNT(*) AS bookings,
           SUM(CASE WHEN b.status='attended' THEN 1 ELSE 0 END) AS attended,
           SUM(CASE WHEN b.status='cancelled' THEN 1 ELSE 0 END) AS cancelled,
           SUM(CASE WHEN b.status='no_show' THEN 1 ELSE 0 END) AS no_shows
    FROM v_bookings_clean b JOIN v_sessions_enriched s ON s.session_id=b.session_id
    WHERE s.session_date BETWEEN '2025-05-05' AND '2025-06-29'
    GROUP BY b.member_id
)
SELECT m.member_id,m.tier,m.plan_id,
       COALESCE(v.check_ins,0) AS check_ins,COALESCE(v.visit_days,0) AS visit_days,v.last_visit_date,
       DATEDIFF('2025-06-29',v.last_visit_date) AS days_since_last_visit,
       COALESCE(a.bookings,0) AS bookings,COALESCE(a.attended,0) AS attended,
       COALESCE(a.cancelled,0) AS cancelled,COALESCE(a.no_shows,0) AS no_shows,
       CASE WHEN COALESCE(v.check_ins,0)<=3 THEN 'Low (0-3)'
            WHEN COALESCE(v.check_ins,0)<=11 THEN 'Moderate (4-11)'
            ELSE 'High (12+)' END AS engagement_segment
FROM v_members_enriched m LEFT JOIN visits v ON v.member_id=m.member_id
LEFT JOIN activity a ON a.member_id=m.member_id;

-- 10.1: Engagement segments. Illustrative thresholds, not validated churn scores.
SELECT engagement_segment, COUNT(*) AS members, SUM(check_ins) AS check_ins,
       ROUND(AVG(check_ins),2) AS average_check_ins, SUM(attended) AS class_attendances,
       ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),2) AS member_share_pct
FROM v_analysis_member_engagement GROUP BY engagement_segment ORDER BY MIN(check_ins);

-- 10.2: Low-engagement outreach list, ranked by recency and visit frequency.
SELECT member_id,tier,check_ins,visit_days,days_since_last_visit,attended,
       ROW_NUMBER() OVER (ORDER BY last_visit_date IS NOT NULL, days_since_last_visit DESC,check_ins,member_id) AS outreach_priority
FROM v_analysis_member_engagement WHERE engagement_segment='Low (0-3)'
ORDER BY outreach_priority;

-- 10.3: Weekly gym visits and class attendance, using true Monday-start calendar weeks.
-- Generate a weekly spine so zero-activity weeks are not dropped. Compare only shared coverage.
WITH RECURSIVE weeks AS (
    SELECT CAST('2025-05-05' AS DATE) AS week_start
    UNION ALL SELECT DATE_ADD(week_start,INTERVAL 7 DAY) FROM weeks WHERE week_start<'2025-06-23'
), visits AS (
    SELECT DATE_SUB(visit_date,INTERVAL WEEKDAY(visit_date) DAY) AS week_start,COUNT(*) AS visits
    FROM v_check_ins_flagged WHERE visit_date BETWEEN '2025-05-05' AND '2025-06-29' GROUP BY 1
), classes AS (
    SELECT DATE_SUB(s.session_date,INTERVAL WEEKDAY(s.session_date) DAY) AS week_start,COUNT(*) AS attended
    FROM v_bookings_clean b JOIN v_sessions_enriched s ON s.session_id=b.session_id
    WHERE b.status='attended' AND s.session_date BETWEEN '2025-05-05' AND '2025-06-29' GROUP BY 1
), weekly AS (
    SELECT w.week_start,COALESCE(v.visits,0) AS visits,COALESCE(c.attended,0) AS attended
    FROM weeks w LEFT JOIN visits v ON v.week_start=w.week_start LEFT JOIN classes c ON c.week_start=w.week_start
), trends AS (
    SELECT *,LAG(visits) OVER (ORDER BY week_start) AS previous_visits,
           LAG(attended) OVER (ORDER BY week_start) AS previous_attended
    FROM weekly
)
SELECT *,ROUND(100*(CAST(visits AS SIGNED)-CAST(previous_visits AS SIGNED))/NULLIF(previous_visits,0),2) AS visit_wow_pct,
       ROUND(100*(CAST(attended AS SIGNED)-CAST(previous_attended AS SIGNED))/NULLIF(previous_attended,0),2) AS attendance_wow_pct,
       SUM(visits) OVER (ORDER BY week_start ROWS UNBOUNDED PRECEDING) AS cumulative_visits
FROM trends ORDER BY week_start;

-- 10.4: Peak check-in hours and rank (observed entries, not concurrent occupancy).
WITH hourly AS (
    SELECT HOUR(checked_in_at) AS hour_of_day,COUNT(*) AS check_ins
    FROM v_check_ins_flagged GROUP BY 1
)
SELECT *,DENSE_RANK() OVER (ORDER BY check_ins DESC) AS peak_rank,
       ROUND(100*check_ins/SUM(check_ins) OVER (),2) AS share_pct
FROM hourly ORDER BY peak_rank,hour_of_day;

-- 10.5: Engagement by current plan. Rates use ratio of sums, not mean of member percentages.
SELECT tier, COUNT(*) AS members, SUM(check_ins) AS check_ins, ROUND(AVG(check_ins),2) AS visits_per_member,
       SUM(bookings) AS bookings,SUM(attended) AS attended,
       ROUND(100*SUM(cancelled)/NULLIF(SUM(bookings),0),2) AS cancellation_pct,
       ROUND(100*SUM(no_shows)/NULLIF(SUM(bookings)-SUM(cancelled),0),2) AS non_cancelled_no_show_pct
FROM v_analysis_member_engagement GROUP BY tier ORDER BY tier;

-- 10.6: Reconcile member, check-in and booking counts within the common coverage window.
SELECT COUNT(*) AS members,SUM(check_ins) AS check_ins,SUM(bookings) AS bookings,
       SUM(attended+cancelled+no_shows) AS reconciled_outcomes
FROM v_analysis_member_engagement;
