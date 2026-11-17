-- =====================================================================================
-- 05 | Referential integrity and cross-table logic
-- CLASSIFICATION: GENUINE DATA QUALITY (do the tables agree with each other?)
-- =====================================================================================
-- PURPOSE
--   (A) Prove the six foreign keys exist and no child row points at a missing parent.
--   (B) Look for parents with no children (informational).
--   (C) Test cross-table LOGIC that a foreign key cannot express: dates that must follow
--       other dates, schedule consistency.
-- Independent orphan checks remain useful for subsequent extracts or loads where constraints are disabled.
-- =====================================================================================

-- ---------- 5.1 Do the six foreign keys exist? ----------
SELECT constraint_name, table_name AS child_table, referenced_table_name AS parent_table,
       update_rule, delete_rule
FROM   information_schema.referential_constraints
WHERE  constraint_schema = 'club_raw'
ORDER  BY constraint_name;

-- ---------- 5.2 Orphan test: child rows whose parent does not exist ----------
-- LEFT JOIN keeps every child row; where no parent matched, the parent's id is NULL = orphan.
SELECT 'members.plan_id -> plans.id' AS relationship, COUNT(*) AS orphan_rows
FROM club_raw.members m LEFT JOIN club_raw.plans p ON p.id = m.plan_id WHERE p.id IS NULL
UNION ALL SELECT 'classes.instructor_id -> instructors.id', COUNT(*)
FROM club_raw.classes c LEFT JOIN club_raw.instructors i ON i.id = c.instructor_id WHERE i.id IS NULL
UNION ALL SELECT 'sessions.class_id -> classes.id', COUNT(*)
FROM club_raw.sessions s LEFT JOIN club_raw.classes c ON c.id = s.class_id WHERE c.id IS NULL
UNION ALL SELECT 'bookings.session_id -> sessions.id', COUNT(*)
FROM club_raw.bookings b LEFT JOIN club_raw.sessions s ON s.id = b.session_id WHERE s.id IS NULL
UNION ALL SELECT 'bookings.member_id -> members.id', COUNT(*)
FROM club_raw.bookings b LEFT JOIN club_raw.members m ON m.id = b.member_id WHERE m.id IS NULL
UNION ALL SELECT 'check_ins.member_id -> members.id', COUNT(*)
FROM club_raw.check_ins c LEFT JOIN club_raw.members m ON m.id = c.member_id WHERE m.id IS NULL;

-- ---------- 5.3 Parents with no children (informational, not an error) ----------
-- Parents without children may be legitimate or indicate incomplete coverage.
SELECT 'plans with no members' AS check_name, COUNT(*) AS parents_without_children
FROM club_raw.plans p WHERE NOT EXISTS (SELECT 1 FROM club_raw.members m WHERE m.plan_id = p.id)
UNION ALL SELECT 'instructors with no classes', COUNT(*)
FROM club_raw.instructors i WHERE NOT EXISTS (SELECT 1 FROM club_raw.classes c WHERE c.instructor_id = i.id)
UNION ALL SELECT 'classes with no sessions', COUNT(*)
FROM club_raw.classes c WHERE NOT EXISTS (SELECT 1 FROM club_raw.sessions s WHERE s.class_id = c.id)
UNION ALL SELECT 'sessions with no bookings', COUNT(*)
FROM club_raw.sessions s WHERE NOT EXISTS (SELECT 1 FROM club_raw.bookings b WHERE b.session_id = s.id)
UNION ALL SELECT 'members with no bookings', COUNT(*)
FROM club_raw.members m WHERE NOT EXISTS (SELECT 1 FROM club_raw.bookings b WHERE b.member_id = m.id)
UNION ALL SELECT 'members with no check-ins', COUNT(*)
FROM club_raw.members m WHERE NOT EXISTS (SELECT 1 FROM club_raw.check_ins c WHERE c.member_id = m.id);

-- ---------- 5.4 Timeline logic across tables ----------
-- Test chronological and scheduling rules not enforced by foreign keys.

-- (a) A check-in before the member joined.
SELECT 'check-in before joined_on' AS test, COUNT(*) AS rows_found
FROM club_raw.check_ins c JOIN club_raw.members m ON m.id = c.member_id
WHERE DATE(c.checked_in_at) < m.joined_on
-- (b) A booking made before the member joined. The booking moment is approximated as
--     session start minus hours_ahead (assumes hours_ahead means lead time).
UNION ALL SELECT 'booking made before joined_on', COUNT(*)
FROM club_raw.bookings b
JOIN club_raw.sessions s ON s.id = b.session_id
JOIN club_raw.members  m ON m.id = b.member_id
WHERE TIMESTAMPDIFF(HOUR, m.joined_on, s.starts_at) < b.hours_ahead
-- (c) A session that starts before its class's first_session_at.
UNION ALL SELECT 'session before class first_session_at', COUNT(*)
FROM club_raw.sessions s JOIN club_raw.classes c ON c.id = s.class_id
WHERE s.starts_at < c.first_session_at
-- (d) A session whose weekday or time of day differs from its class's first session.
--     (Each class is meant to run weekly at one fixed slot.)
UNION ALL SELECT 'session weekday/time differs from class slot', COUNT(*)
FROM club_raw.sessions s JOIN club_raw.classes c ON c.id = s.class_id
WHERE DAYOFWEEK(s.starts_at) <> DAYOFWEEK(c.first_session_at) OR TIME(s.starts_at) <> TIME(c.first_session_at)
-- (e) week_no that disagrees with the number of weeks since the class's first session.
UNION ALL SELECT 'week_no inconsistent with class start', COUNT(*)
FROM club_raw.sessions s JOIN club_raw.classes c ON c.id = s.class_id
WHERE s.week_no <> FLOOR(DATEDIFF(DATE(s.starts_at), DATE(c.first_session_at)) / 7) + 1
-- (f) A class whose first_session_at does not match its earliest actual session.
UNION ALL SELECT 'classes.first_session_at <> earliest session', COUNT(*)
FROM club_raw.classes c
JOIN (SELECT class_id, MIN(starts_at) AS first_start FROM club_raw.sessions GROUP BY class_id) f ON f.class_id = c.id
WHERE c.first_session_at <> f.first_start;

-- ---------- 5.5 Sessions per class ----------
-- Compare scheduled occurrence counts across classes.
SELECT c.id AS class_id, c.title, COUNT(s.id) AS sessions, MIN(s.week_no) AS first_week, MAX(s.week_no) AS last_week
FROM   club_raw.classes c LEFT JOIN club_raw.sessions s ON s.class_id = c.id
GROUP  BY c.id, c.title
ORDER  BY c.id;

