-- Gym Membership & Commercial Performance Analysis | Stage 09
-- MySQL 8.0.22+ | Depends on Stage 07; derived views are replaceable.
-- No source data is updated. Fee currency unspecified; GBP is a presentation assumption.
-- All membership fees are snapshot list-price estimates, not billed revenue.
USE club_clean;

-- 09.1: Plan mix, contribution, rank, cumulative concentration.
-- Keep plans with zero members. Windows operate on one row per plan.
WITH plan_totals AS (
    SELECT p.id AS plan_id, p.tier, p.monthly_fee, p.classes_per_month,
           COUNT(m.member_id) AS members,
           COUNT(m.member_id) * p.monthly_fee AS monthly_run_rate
    FROM club_raw.plans p
    LEFT JOIN v_members_enriched m ON m.plan_id=p.id
    GROUP BY p.id,p.tier,p.monthly_fee,p.classes_per_month
)
SELECT *, ROUND(100*members/NULLIF(SUM(members) OVER (),0),2) AS member_share_pct,
       ROUND(100*monthly_run_rate/NULLIF(SUM(monthly_run_rate) OVER (),0),2) AS income_share_pct,
       monthly_run_rate*12 AS annualised_run_rate,
       DENSE_RANK() OVER (ORDER BY members DESC) AS popularity_rank,
       SUM(members) OVER (ORDER BY tier ROWS UNBOUNDED PRECEDING) AS cumulative_members
FROM plan_totals ORDER BY tier;

-- 09.2: Estimated fee run-rate; weighted average across members.
SELECT COUNT(*) AS members, SUM(monthly_fee) AS monthly_run_rate,
       12*SUM(monthly_fee) AS annualised_run_rate, ROUND(AVG(monthly_fee),2) AS average_monthly_fee
FROM v_members_enriched;

-- 09.3: June usage snapshot, all members including those with zero attended classes.
-- June is the only complete calendar month in the session extract; current plan is a proxy.
-- Candidate rule: attended >= current allowance and a higher tier exists.
-- The next tier is found by LEAD, not by hard-coding an assumed price increment.
CREATE OR REPLACE VIEW club_clean.v_analysis_june_usage AS
WITH june_attendance AS (
    SELECT b.member_id, COUNT(*) AS attended_classes
    FROM v_bookings_clean b JOIN v_sessions_enriched s ON s.session_id=b.session_id
    WHERE b.status='attended' AND s.session_date >= '2025-06-01' AND s.session_date < '2025-07-01'
    GROUP BY b.member_id
), plan_ladder AS (
    SELECT id AS plan_id, LEAD(tier) OVER (ORDER BY tier) AS next_tier,
           LEAD(monthly_fee) OVER (ORDER BY tier) AS next_fee
    FROM club_raw.plans
)
SELECT m.member_id,m.plan_id,m.tier,m.monthly_fee,m.classes_per_month,
       COALESCE(a.attended_classes,0) AS june_attended,
       ROUND(100*COALESCE(a.attended_classes,0)/NULLIF(m.classes_per_month,0),2) AS allowance_usage_pct,
       l.next_tier,l.next_fee,
       CASE WHEN COALESCE(a.attended_classes,0)>=m.classes_per_month AND l.next_tier IS NOT NULL THEN 1 ELSE 0 END AS upgrade_lead,
       CASE WHEN COALESCE(a.attended_classes,0)>m.classes_per_month THEN 1 ELSE 0 END AS above_allowance,
       CASE WHEN COALESCE(a.attended_classes,0)>=m.classes_per_month AND l.next_tier IS NOT NULL
            THEN l.next_fee-m.monthly_fee ELSE 0 END AS illustrative_monthly_uplift
FROM v_members_enriched m JOIN plan_ladder l ON l.plan_id=m.plan_id
LEFT JOIN june_attendance a ON a.member_id=m.member_id;

-- 09.4: Targeted outreach leads. IDs only; no personal information.
SELECT member_id,tier,june_attended,classes_per_month,allowance_usage_pct,next_tier,
       illustrative_monthly_uplift
FROM v_analysis_june_usage WHERE upgrade_lead=1
ORDER BY allowance_usage_pct DESC,member_id;

-- 09.5: Scenario, not a forecast: if ALL flagged members bought the next tier.
SELECT COUNT(*) AS members_assessed, SUM(june_attended) AS june_attended,
       SUM(above_allowance) AS above_allowance_members, SUM(upgrade_lead) AS upgrade_leads,
       SUM(illustrative_monthly_uplift) AS full_conversion_monthly_scenario,
       ROUND(SUM(illustrative_monthly_uplift)*0.25,2) AS illustrative_25pct_conversion_scenario
FROM v_analysis_june_usage;
