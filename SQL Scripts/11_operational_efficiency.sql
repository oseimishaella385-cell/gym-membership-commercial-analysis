-- 11 | Operational efficiency | MySQL 8.0.22+
USE club_clean;
-- Full session window 5 May–6 July. One row per session keeps capacity additive.
-- Reservation demand = attended + no_show; realised utilisation = attended/capacity.
-- No cancellation history: cannot measure simultaneous reservations or prove booking-cap breach.
CREATE OR REPLACE VIEW club_clean.v_analysis_session_performance AS
WITH outcomes AS (
    SELECT session_id,COUNT(*) AS bookings,
           SUM(CASE WHEN status='attended' THEN 1 ELSE 0 END) AS attended,
           SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) AS cancelled,
           SUM(CASE WHEN status='no_show' THEN 1 ELSE 0 END) AS no_shows
    FROM v_bookings_clean GROUP BY session_id
)
SELECT s.session_id,s.class_id,s.class_title,s.instructor_id,s.engagement,
       s.starts_at,s.session_date,s.capacity,s.duration_minutes,
       COALESCE(o.bookings,0) AS bookings,COALESCE(o.attended,0) AS attended,
       COALESCE(o.cancelled,0) AS cancelled,COALESCE(o.no_shows,0) AS no_shows,
       COALESCE(o.attended,0)+COALESCE(o.no_shows,0) AS non_cancelled,
       ROUND(100*COALESCE(o.attended,0)/NULLIF(s.capacity,0),2) AS utilisation_pct,
       ROUND(100*(COALESCE(o.attended,0)+COALESCE(o.no_shows,0))/NULLIF(s.capacity,0),2) AS reservation_fill_pct,
       CASE WHEN COALESCE(o.attended,0)+COALESCE(o.no_shows,0)>s.capacity THEN 1 ELSE 0 END AS over_capacity_flag,
       CASE WHEN COALESCE(o.attended,0)<0.5*s.capacity THEN 1 ELSE 0 END AS low_utilisation_flag
FROM v_sessions_enriched s LEFT JOIN outcomes o ON o.session_id=s.session_id;

-- 11.1: Aggregate session-level KPIs across the full class reporting window.
SELECT COUNT(*) AS sessions,SUM(capacity) AS places,SUM(bookings) AS bookings,
       SUM(attended) AS attended,SUM(cancelled) AS cancelled,SUM(no_shows) AS no_shows,
       ROUND(100*SUM(attended)/NULLIF(SUM(capacity),0),2) AS utilisation_pct,
       ROUND(100*SUM(non_cancelled)/NULLIF(SUM(capacity),0),2) AS reservation_fill_pct,
       ROUND(100*SUM(cancelled)/NULLIF(SUM(bookings),0),2) AS cancellation_pct,
       ROUND(100*SUM(no_shows)/NULLIF(SUM(bookings),0),2) AS all_booking_no_show_pct,
       ROUND(100*SUM(no_shows)/NULLIF(SUM(non_cancelled),0),2) AS non_cancelled_no_show_pct,
       SUM(over_capacity_flag) AS over_capacity_sessions,SUM(low_utilisation_flag) AS low_utilisation_sessions
FROM v_analysis_session_performance;

-- 11.2: Rank class demand and realised utilisation separately; weighted by capacity.
WITH class_metrics AS (
    SELECT class_id,class_title,COUNT(*) AS sessions,SUM(capacity) AS places,SUM(bookings) AS bookings,
           SUM(attended) AS attended,SUM(non_cancelled) AS non_cancelled,
           SUM(over_capacity_flag) AS flagged_sessions,
           ROUND(100*SUM(attended)/NULLIF(SUM(capacity),0),2) AS utilisation_pct,
           ROUND(100*SUM(non_cancelled)/NULLIF(SUM(capacity),0),2) AS reservation_fill_pct
    FROM v_analysis_session_performance GROUP BY class_id,class_title
)
SELECT *,DENSE_RANK() OVER (ORDER BY non_cancelled DESC) AS demand_rank,
       DENSE_RANK() OVER (ORDER BY utilisation_pct DESC) AS utilisation_rank
FROM class_metrics ORDER BY demand_rank,class_id;

-- 11.3: Investigate sessions with demand above capacity or actual utilisation below 50%.
-- The threshold is an illustrative business rule, not an industry benchmark.
SELECT session_id,class_title,starts_at,capacity,non_cancelled,attended,reservation_fill_pct,utilisation_pct,
       CASE WHEN over_capacity_flag=1 THEN 'Review capacity and waitlist'
            WHEN low_utilisation_flag=1 THEN 'Review scheduling and demand' END AS suggested_review
FROM v_analysis_session_performance WHERE over_capacity_flag=1 OR low_utilisation_flag=1
ORDER BY over_capacity_flag DESC,utilisation_pct,session_id;

-- 11.4: Instructor workload and associated outcomes; not a causal quality ranking.
SELECT instructor_id,engagement,COUNT(DISTINCT class_id) AS classes,COUNT(*) AS sessions,
       SUM(duration_minutes) AS scheduled_teaching_minutes,SUM(attended) AS attended,
       ROUND(100*SUM(attended)/NULLIF(SUM(capacity),0),2) AS utilisation_pct,
       ROUND(100*SUM(no_shows)/NULLIF(SUM(non_cancelled),0),2) AS non_cancelled_no_show_pct
FROM v_analysis_session_performance GROUP BY instructor_id,engagement ORDER BY attended DESC,instructor_id;

-- 11.5: Scheduling heatmap with sample size. Observational: each class has a fixed slot.
SELECT WEEKDAY(session_date)+1 AS weekday_number,DAYNAME(session_date) AS weekday_name,HOUR(starts_at) AS hour_of_day,
       COUNT(*) AS sessions,SUM(capacity) AS places,SUM(attended) AS attended,
       ROUND(100*SUM(attended)/NULLIF(SUM(capacity),0),2) AS utilisation_pct,
       ROUND(100*SUM(non_cancelled)/NULLIF(SUM(capacity),0),2) AS reservation_fill_pct
FROM v_analysis_session_performance GROUP BY weekday_number,weekday_name,hour_of_day
ORDER BY weekday_number,hour_of_day;

-- 11.6: Booking lead-time segments (hours_ahead definition remains unconfirmed).
WITH segments AS (
    SELECT CASE WHEN hours_ahead<=24 THEN '1. Within 24h' WHEN hours_ahead<=72 THEN '2. 25-72h'
                ELSE '3. Over 72h' END AS lead_time_band,status
    FROM v_bookings_clean
)
SELECT lead_time_band,COUNT(*) AS bookings,ROUND(100*AVG(status='cancelled'),2) AS cancellation_pct,
       ROUND(100*SUM(status='no_show')/NULLIF(SUM(status<>'cancelled'),0),2) AS non_cancelled_no_show_pct
FROM segments GROUP BY lead_time_band ORDER BY lead_time_band;
