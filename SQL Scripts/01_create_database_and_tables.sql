-- =====================================================================================
-- 01 | Database and table creation | MySQL 8.0.22+
-- =====================================================================================
-- PURPOSE
--   Build the structure that will hold the seven original CSV files.
--
-- DESIGN PRINCIPLES
-- Separate original source data (club_raw) from derived views and audit objects (club_clean).
-- Structural constraints enforce primary keys, foreign keys and non-null fields.
-- Business-rule constraints are intentionally omitted so duplicate source events remain available for assessment.
-- Matching unsigned integer key types support referential integrity.
--
-- Initial schema creation; existing source tables must be preserved.
-- =====================================================================================

-- Original data lives here. utf8mb4 stores any character safely (names, emails).
CREATE DATABASE IF NOT EXISTS club_raw
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

-- Separate schema for derived views, audit checks and the issue register.
CREATE DATABASE IF NOT EXISTS club_clean
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

-- -------------------------------------------------------------------------------------
-- Tables are created PARENTS FIRST so each foreign key can point at an existing table.
-- Order: plans, instructors, members, classes, sessions, bookings, check_ins.
-- -------------------------------------------------------------------------------------

-- plans: 4 rows. Membership tiers, price and monthly class allowance.
CREATE TABLE club_raw.plans (
  id                INT UNSIGNED     NOT NULL,                 -- primary key, 1..4
  tier              TINYINT UNSIGNED NOT NULL,                 -- tier level (always equals id)
  monthly_fee       DECIMAL(8,2)     NOT NULL,                 -- DECIMAL, never FLOAT, for money; currency not stated in source
  classes_per_month TINYINT UNSIGNED NOT NULL,                 -- monthly class allowance (4/8/12/16)
  PRIMARY KEY (id)
) ENGINE=InnoDB COMMENT='Membership tiers';

-- instructors: 8 rows. Teaching staff.
CREATE TABLE club_raw.instructors (
  id           INT UNSIGNED NOT NULL,                          -- primary key, 1..8
  first_name   VARCHAR(50)  NOT NULL,
  last_name    VARCHAR(50)  NOT NULL,
  engagement   VARCHAR(20)  NOT NULL,                          -- employee / freelance. VARCHAR not ENUM so unexpected values load and can be reported
  qualified_on DATE         NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB COMMENT='Instructors';

-- members: 120 rows. Each member holds one (current) plan.
CREATE TABLE club_raw.members (
  id         INT UNSIGNED NOT NULL,                            -- primary key, 1..120
  first_name VARCHAR(50)  NOT NULL,                            -- personal data
  last_name  VARCHAR(60)  NOT NULL,                            -- personal data
  email      VARCHAR(255) NOT NULL,                            -- personal data; uniqueness is TESTED in Stage 4, not enforced
  birth_date DATE         NOT NULL,                            -- personal data
  joined_on  DATE         NOT NULL,
  plan_id    INT UNSIGNED NOT NULL,                            -- foreign key -> plans.id
  PRIMARY KEY (id),
  CONSTRAINT fk_members_plan FOREIGN KEY (plan_id) REFERENCES club_raw.plans (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT                      -- RESTRICT: a plan in use can never be deleted
) ENGINE=InnoDB COMMENT='Members and current plan';

-- classes: 14 rows. One recurring weekly class per row.
CREATE TABLE club_raw.classes (
  id               INT UNSIGNED      NOT NULL,                 -- primary key, 1..14
  title            VARCHAR(100)      NOT NULL,
  instructor_id    INT UNSIGNED      NOT NULL,                 -- foreign key -> instructors.id
  capacity         SMALLINT UNSIGNED NOT NULL,                 -- maximum places per session
  duration_minutes SMALLINT UNSIGNED NOT NULL,
  first_session_at DATETIME          NOT NULL,                 -- DATETIME has no timezone; source-local time is assumed (unconfirmed)
  PRIMARY KEY (id),
  CONSTRAINT fk_classes_instructor FOREIGN KEY (instructor_id) REFERENCES club_raw.instructors (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB COMMENT='Class catalogue';

-- sessions: 112 rows. Dated occurrences of a class (14 classes x 8 weeks).
CREATE TABLE club_raw.sessions (
  id        INT UNSIGNED     NOT NULL,                         -- primary key, 1..112
  class_id  INT UNSIGNED     NOT NULL,                         -- foreign key -> classes.id
  week_no   TINYINT UNSIGNED NOT NULL,                         -- occurrence number counted from the class's own first session (NOT a calendar week)
  starts_at DATETIME         NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_sessions_class FOREIGN KEY (class_id) REFERENCES club_raw.classes (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB COMMENT='Scheduled class sessions';

-- bookings: 778 rows. A member's reservation for a session, and its outcome.
CREATE TABLE club_raw.bookings (
  id          INT UNSIGNED      NOT NULL,                      -- primary key, 1..778
  session_id  INT UNSIGNED      NOT NULL,                      -- foreign key -> sessions.id
  member_id   INT UNSIGNED      NOT NULL,                      -- foreign key -> members.id
  hours_ahead SMALLINT UNSIGNED NOT NULL,                      -- assumed: hours between booking and session start (unconfirmed)
  status      VARCHAR(20)       NOT NULL,                      -- attended / cancelled / no_show
  PRIMARY KEY (id),
  KEY idx_bookings_session_member (session_id, member_id),     -- NON-unique on purpose: speeds duplicate checks, and still allows the duplicates to load
  CONSTRAINT fk_bookings_session FOREIGN KEY (session_id) REFERENCES club_raw.sessions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bookings_member FOREIGN KEY (member_id) REFERENCES club_raw.members (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB COMMENT='Class bookings';

-- check_ins: 1,044 rows. Club entries, not linked to classes.
CREATE TABLE club_raw.check_ins (
  id             INT UNSIGNED      NOT NULL,                   -- primary key, 1..1044
  member_id      INT UNSIGNED      NOT NULL,                   -- foreign key -> members.id
  checked_in_at  DATETIME          NOT NULL,
  method         VARCHAR(20)       NOT NULL,                   -- key_fob / app_qr / front_desk
  minutes_inside SMALLINT UNSIGNED NOT NULL,                   -- no check-out time exists, so source of this value is unverified
  PRIMARY KEY (id),
  KEY idx_checkins_member_time (member_id, checked_in_at),     -- also serves the member_id foreign key
  CONSTRAINT fk_checkins_member FOREIGN KEY (member_id) REFERENCES club_raw.members (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB COMMENT='Club entries';

-- -------------------------------------------------------------------------------------
-- Verify creation of the seven source tables.
-- -------------------------------------------------------------------------------------
SELECT table_name, table_comment
FROM   information_schema.tables
WHERE  table_schema = 'club_raw'
ORDER  BY table_name;
