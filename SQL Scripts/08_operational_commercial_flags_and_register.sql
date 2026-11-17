-- =====================================================================================
-- 08 | Operational and commercial flags and issue register
-- Separate business-performance observations from data-quality defects; source values are preserved.
--   [OPS]        Operational performance: studio capacity, no-shows, staffing, opening hours.
--   [COMMERCIAL] Revenue, pricing and plan policy.
--   [COMPLIANCE] Policy or regulatory questions.
-- Booking rates use deduplicated booking records. Flags support further investigation.
-- =====================================================================================

-- ======================= PART 1 : FLAG QUERIES =========================================

-- 8.1 [OPS] Sessions where booking rows exceed capacity, with the CAUSE separated out.
-- Distinguish potential over-capacity demand from duplicate-driven inflation and cancelled bookings.
-- Without booking and cancellation timestamps, simultaneous overbooking cannot be confirmed.
SELECT s.id AS session_id, c.title, s.starts_at, c.capacity,
       COUNT(b.id)                                                   AS raw_booking_rows,
       SUM(b.status <> 'cancelled')                                  AS active_rows,
       COUNT(DISTINCT CASE WHEN b.status <> 'cancelled' THEN b.member_id END) AS distinct_active_members,
       CASE
         WHEN COUNT(DISTINCT CASE WHEN b.status <> 'cancelled' THEN b.member_id END) > c.capacity THEN 'OPS: genuine overbooking'
         WHEN SUM(b.status <> 'cancelled') > c.capacity                                          THEN 'DQ: duplicate rows push it over'
         ELSE 'Benign: only cancelled rows exceed'
       END AS interpretation
FROM   club_raw.sessions s
JOIN   club_raw.classes  c ON c.id = s.class_id
JOIN   club_raw.bookings b ON b.session_id = s.id
GROUP  BY s.id, c.title, s.starts_at, c.capacity
HAVING COUNT(b.id) > c.capacity
ORDER  BY s.starts_at;

-- 8.2 [OPS] Average fill rate by class: active (non-cancelled) places taken / places available.
--   Low fill = schedule or marketing question; high fill = capacity or waitlist question.
SELECT c.title, c.capacity, COUNT(DISTINCT s.id) AS sessions,
       SUM(b.status <> 'cancelled')                                  AS active_bookings,
       ROUND(100 * SUM(b.status <> 'cancelled') / (c.capacity * COUNT(DISTINCT s.id)), 1) AS fill_pct
FROM   club_raw.classes c
JOIN   club_raw.sessions s ON s.class_id = c.id
LEFT   JOIN club_clean.v_bookings_clean b ON b.session_id = s.id
GROUP  BY c.id, c.title, c.capacity
ORDER  BY fill_pct DESC;

-- 8.3 [OPS] Cancellation and no-show rates overall and by plan tier.
-- Both rates in this query use all clean bookings as their denominator.
-- Stage 11 also measures no-shows as a share of non-cancelled reservations, a distinct KPI.
SELECT 'all bookings' AS segment, COUNT(*) AS bookings,
       ROUND(100 * AVG(status = 'cancelled'), 1) AS cancelled_pct,
       ROUND(100 * AVG(status = 'no_show'), 1)   AS no_show_pct
FROM   club_clean.v_bookings_clean
UNION ALL
SELECT CONCAT('tier ', p.tier), COUNT(*),
       ROUND(100 * AVG(b.status = 'cancelled'), 1), ROUND(100 * AVG(b.status = 'no_show'), 1)
FROM   club_clean.v_bookings_clean b
JOIN   club_raw.members m ON m.id = b.member_id
JOIN   club_raw.plans   p ON p.id = m.plan_id
GROUP  BY p.tier
ORDER  BY segment;

-- 8.4 [OPS] No-shows and cancellations by booking lead time. Tests whether last-minute or very
--   early bookings behave differently (informs cancellation-window policy).
SELECT CASE WHEN hours_ahead <= 24 THEN '1. within 24h'
            WHEN hours_ahead <= 72 THEN '2. 1 to 3 days'
            ELSE '3. 3 to 7 days' END AS lead_time,
       COUNT(*) AS bookings,
       ROUND(100 * AVG(status = 'cancelled'), 1) AS cancelled_pct,
       ROUND(100 * AVG(status = 'no_show'), 1)   AS no_show_pct
FROM   club_clean.v_bookings_clean
GROUP  BY lead_time
ORDER  BY lead_time;

-- 8.5 [COMMERCIAL] Members using more classes than their plan allows in a calendar month.
-- Compare attended classes with the current plan allowance by calendar month.
-- Plan history and allowance policy are unavailable; flags indicate investigation opportunities, not confirmed breaches.
SELECT COUNT(*) AS member_months, SUM(attended > allowance) AS member_months_over_allowance
FROM (
  SELECT b.member_id, DATE_FORMAT(s.starts_at, '%Y-%m') AS ym, COUNT(*) AS attended, MAX(p.classes_per_month) AS allowance
  FROM   club_clean.v_bookings_clean b
  JOIN   club_raw.sessions s ON s.id = b.session_id
  JOIN   club_raw.members  m ON m.id = b.member_id
  JOIN   club_raw.plans    p ON p.id = m.plan_id
  WHERE  b.status = 'attended'
  GROUP  BY b.member_id, DATE_FORMAT(s.starts_at, '%Y-%m')
) AS usage_by_month;

-- 8.6 [COMMERCIAL] Plan mix and the contracted monthly fee run-rate (assumes every member is
--   currently active and pays list price; the data holds no billing or churn information).
SELECT p.tier, p.monthly_fee, p.classes_per_month, COUNT(m.id) AS members,
       COUNT(m.id) * p.monthly_fee AS monthly_fee_run_rate,
       ROUND(100 * COUNT(m.id) / (SELECT COUNT(*) FROM club_raw.members), 1) AS pct_of_members
FROM   club_raw.plans p
LEFT   JOIN club_raw.members m ON m.plan_id = p.id
GROUP  BY p.tier, p.monthly_fee, p.classes_per_month
ORDER  BY p.tier;

-- 8.7 [OPS] When people visit: check-ins by hour and entry method. Informs staffing, and
--   (for 00:00 to 05:59) the opening-hours question raised in Stage 6.
SELECT HOUR(checked_in_at) AS hour_of_day, COUNT(*) AS check_ins,
       SUM(method = 'key_fob') AS key_fob, SUM(method = 'app_qr') AS app_qr, SUM(method = 'front_desk') AS front_desk
FROM   club_raw.check_ins
GROUP  BY HOUR(checked_in_at)
ORDER  BY hour_of_day;

-- 8.8 [OPS] Instructor workload and outcomes: classes taught, active bookings and no-show rate.
SELECT i.id AS instructor_id, CONCAT(i.first_name, ' ', i.last_name) AS instructor, i.engagement,
       COUNT(DISTINCT c.id) AS classes, COUNT(DISTINCT s.id) AS sessions,
       SUM(b.status <> 'cancelled') AS active_bookings,
       ROUND(100 * AVG(b.status = 'no_show'), 1) AS no_show_pct
FROM   club_raw.instructors i
JOIN   club_raw.classes c  ON c.instructor_id = i.id
JOIN   club_raw.sessions s ON s.class_id = c.id
LEFT   JOIN club_clean.v_bookings_clean b ON b.session_id = s.id
GROUP  BY i.id, i.first_name, i.last_name, i.engagement
ORDER  BY active_bookings DESC;

-- 8.9 [COMPLIANCE] Age-at-joining policy review.
SELECT COUNT(*) AS members_joined_under_18 FROM club_clean.v_members_enriched WHERE joined_under_18;

-- ======================= PART 2 : ISSUE REGISTER =======================================
-- Classify findings separately by quality, coverage and business impact.
-- The issue register is a point-in-time record and is not designed for repeated insertion.

CREATE TABLE club_clean.dq_issue_register (
  issue_id             VARCHAR(8)   NOT NULL,
  category             VARCHAR(30)  NOT NULL,   -- Data quality / Coverage limitation / Needs confirmation / Operational / Commercial / Compliance
  severity             VARCHAR(10)  NOT NULL,   -- High / Medium / Low
  affected_table       VARCHAR(40)  NOT NULL,
  description          VARCHAR(255) NOT NULL,
  rows_affected        INT          NULL,
  rows_in_scope        INT          NULL,
  proposed_treatment   VARCHAR(255) NOT NULL,
  needs_business_input VARCHAR(3)   NOT NULL,   -- Yes / No
  status               VARCHAR(12)  NOT NULL DEFAULT 'Open',
  logged_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (issue_id)
) ENGINE=InnoDB;

INSERT INTO club_clean.dq_issue_register
 (issue_id, category, severity, affected_table, description, rows_affected, rows_in_scope, proposed_treatment, needs_business_input)
SELECT 'DQ-01', 'Data quality', 'High', 'bookings', 'Exact duplicate booking rows (same session, member, lead time, status)',
       (SELECT COUNT(*) FROM club_clean.v_bookings_flagged WHERE is_exact_duplicate), (SELECT COUNT(*) FROM club_raw.bookings),
       'Keep one row per group in v_bookings_clean and retain originals in club_raw', 'No'
UNION ALL SELECT 'DQ-02', 'Data quality', 'High', 'bookings', 'Member-session pairs with conflicting statuses (e.g. attended and cancelled)',
       (SELECT COUNT(DISTINCT CONCAT(session_id, '-', member_id)) FROM club_clean.v_bookings_flagged WHERE has_conflicting_status),
       (SELECT COUNT(*) FROM (SELECT 1 FROM club_raw.bookings GROUP BY session_id, member_id) g),
       'Apply status-precedence rule (attended > no_show > cancelled), then confirm with booking-system owner', 'Yes'
UNION ALL SELECT 'DQ-03', 'Data quality', 'Medium', 'bookings', 'Surplus booking rows hidden from v_bookings_clean (all duplicate types)',
       (SELECT COUNT(*) FROM club_clean.v_bookings_excluded), (SELECT COUNT(*) FROM club_raw.bookings),
       'Review list in v_bookings_excluded, then request source-system correction', 'Yes'
UNION ALL SELECT 'DQ-04', 'Data quality', 'Low', 'bookings', 'Overlapping active bookings for one member (different sessions, same time). Tested after de-duplication',
       (SELECT COUNT(*) FROM (
          SELECT a1.member_id FROM
            (SELECT DISTINCT b.member_id, b.session_id, s.starts_at, c.duration_minutes
             FROM club_raw.bookings b JOIN club_raw.sessions s ON s.id = b.session_id JOIN club_raw.classes c ON c.id = s.class_id
             WHERE b.status <> 'cancelled') a1
          JOIN (SELECT DISTINCT b.member_id, b.session_id, s.starts_at, c.duration_minutes
             FROM club_raw.bookings b JOIN club_raw.sessions s ON s.id = b.session_id JOIN club_raw.classes c ON c.id = s.class_id
             WHERE b.status <> 'cancelled') a2
            ON a2.member_id = a1.member_id AND a2.session_id > a1.session_id
          WHERE TIMESTAMPDIFF(MINUTE, a1.starts_at, a2.starts_at) < a1.duration_minutes
            AND TIMESTAMPDIFF(MINUTE, a2.starts_at, a1.starts_at) < a2.duration_minutes) x),
       NULL, 'None expected. Re-test after any source-system correction', 'Yes'
UNION ALL SELECT 'DQ-05', 'Data quality', 'Medium', 'check_ins', 'minutes_inside looks generated: near-identical averages across entry methods, no check-out time to verify',
       (SELECT COUNT(*) FROM club_raw.check_ins), (SELECT COUNT(*) FROM club_raw.check_ins),
       'Mark field UNVERIFIED and avoid dwell-time conclusions until source is confirmed', 'Yes'
UNION ALL SELECT 'DQ-06', 'Data quality', 'Low', 'sessions', 'week_no counts from each class''s first session, not the calendar week',
       (SELECT COUNT(*) FROM club_raw.sessions WHERE week_no <> FLOOR(DATEDIFF(DATE(starts_at), '2025-05-05') / 7) + 1),
       (SELECT COUNT(*) FROM club_raw.sessions),
       'Derive calendar weeks from starts_at, never trend on week_no', 'No'
UNION ALL SELECT 'DQ-07', 'Data quality', 'Low', 'plans', 'tier column duplicates id in every row (redundant)',
       (SELECT COUNT(*) FROM club_raw.plans WHERE tier = id), (SELECT COUNT(*) FROM club_raw.plans),
       'Document only. Use one of the two columns, never both', 'No'
UNION ALL SELECT 'CV-01', 'Coverage limitation', 'High', 'bookings / check_ins', 'Attended bookings with no same-day check-in by that member',
       (SELECT COUNT(*) FROM club_raw.bookings b JOIN club_raw.sessions s ON s.id = b.session_id
        WHERE b.status = 'attended'
          AND NOT EXISTS (SELECT 1 FROM club_raw.check_ins ci WHERE ci.member_id = b.member_id AND DATE(ci.checked_in_at) = DATE(s.starts_at))),
       (SELECT COUNT(*) FROM club_raw.bookings WHERE status = 'attended'),
       'Do not use check-ins to validate attendance. Ask whether class entry is scanned separately', 'Yes'
UNION ALL SELECT 'CV-02', 'Coverage limitation', 'High', 'sessions / bookings', 'Sessions after the last check-in on file (29 Jun 2025)',
       (SELECT COUNT(*) FROM club_raw.sessions WHERE starts_at > (SELECT MAX(checked_in_at) FROM club_raw.check_ins)),
       (SELECT COUNT(*) FROM club_raw.sessions),
       'Trim to a common window (5 May to 29 Jun 2025) when combining bookings and check-ins', 'No'
UNION ALL SELECT 'CF-01', 'Needs confirmation', 'Medium', 'check_ins', 'Check-ins between 00:00 and 05:59',
       (SELECT COUNT(*) FROM club_raw.check_ins WHERE HOUR(checked_in_at) < 6), (SELECT COUNT(*) FROM club_raw.check_ins),
       'Confirm opening hours and timezone. Flagged in v_check_ins_flagged, not removed', 'Yes'
UNION ALL SELECT 'OP-01', 'Operational', 'High', 'sessions / bookings', 'Sessions with more DISTINCT active members than capacity (genuine overbooking)',
       (SELECT COUNT(*) FROM (SELECT s.id FROM club_raw.sessions s JOIN club_raw.classes c ON c.id = s.class_id
                              JOIN club_clean.v_bookings_clean b ON b.session_id = s.id
                              WHERE b.status <> 'cancelled' GROUP BY s.id, c.capacity HAVING COUNT(*) > c.capacity) o),
       (SELECT COUNT(*) FROM club_raw.sessions),
       'Operations to review waitlist and booking cap rules. NOT a data fix', 'Yes'
UNION ALL SELECT 'CM-01', 'Commercial', 'Medium', 'bookings / plans', 'Member-months with attended classes above plan allowance',
       (SELECT COUNT(*) FROM (SELECT b.member_id, DATE_FORMAT(s.starts_at, '%Y-%m') AS ym, COUNT(*) AS n, MAX(p.classes_per_month) AS a
                              FROM club_clean.v_bookings_clean b JOIN club_raw.sessions s ON s.id = b.session_id
                              JOIN club_raw.members m ON m.id = b.member_id JOIN club_raw.plans p ON p.id = m.plan_id
                              WHERE b.status = 'attended' GROUP BY b.member_id, DATE_FORMAT(s.starts_at, '%Y-%m') HAVING COUNT(*) > MAX(p.classes_per_month)) z),
       NULL, 'Commercial team to confirm whether allowance is a hard cap. Plan history needed to be certain', 'Yes'
UNION ALL SELECT 'CP-01', 'Compliance', 'Low', 'members', 'Members aged under 18 at joining',
       (SELECT COUNT(*) FROM club_clean.v_members_enriched WHERE joined_under_18), (SELECT COUNT(*) FROM club_raw.members),
       'Check against age policy and consent records. NOT a data fix', 'Yes';

-- Final report: everything found, grouped so data fixes and business actions stay separate.
SELECT category, issue_id, severity, affected_table, description, rows_affected, rows_in_scope, needs_business_input
FROM   club_clean.dq_issue_register
ORDER  BY FIELD(category, 'Data quality', 'Coverage limitation', 'Needs confirmation', 'Operational', 'Commercial', 'Compliance'), issue_id;

-- Verify source preservation against ingestion fingerprints.
SELECT b.table_name,
       IF(b.row_count = n.row_count AND b.content_fingerprint = n.content_fingerprint, 'UNCHANGED', 'CHANGED - INVESTIGATE') AS integrity
FROM   club_clean.raw_baseline b JOIN club_clean.v_raw_fingerprint_now n ON n.table_name = b.table_name
ORDER  BY b.table_name;
