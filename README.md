# gym-membership-commercial-analysis
End-to-end data analytics project exploring gym membership performance, customer engagement, commercial opportunities and operational efficiency using MySQL, Power BI and DAX.

# Gym Membership & Commercial Performance Analysis

## 1. Project Overview

This project explores gym membership performance, customer engagement and operational efficiency to identify opportunities for commercial growth and improved business performance.

Using MySQL and Power BI, I developed an end-to-end analytical workflow involving data extraction, data quality assessment, cleaning, transformation, advanced SQL analysis, relational data modelling and interactive dashboard development.

The analysis focuses on translating raw data into actionable insights and recommendations that could support management in making informed business decisions.

## 2. Business Objectives

The primary objective is to identify opportunities to increase membership income, improve customer engagement and optimise operational efficiency.

### Membership and Commercial Performance

- Which membership plans are the most popular?
- Which membership tiers contribute the highest estimated income?
- Are there opportunities to increase income through membership upgrades?
- How is estimated income distributed across membership tiers?

### Customer Engagement

- How frequently are members using the gym?
- Which members demonstrate low engagement?
- When is the gym busiest?
- How does customer behaviour vary across membership tiers?

### Operational Efficiency

- Is the gym effectively utilising its class capacity?
- Which fitness classes have the highest and lowest utilisation?
- How significant are cancellations and no-shows?
- Are there opportunities to improve scheduling and resource allocation?

## 3. Tools and Technologies

- **MySQL:** Data ingestion, cleaning, transformation and advanced analysis.
- **MySQL Workbench:** Database management and SQL development.
- **Power BI:** Data modelling, interactive visualisation and business reporting.
- **DAX:** KPI calculations and analytical measures.
- **GitHub:** Project documentation and version control.

## 4. Dataset Overview

The dataset contains 2,080 original records across seven relational tables.

| Table | Records | Description |
|---|---:|---|
| Members | 120 | Membership information |
| Plans | 4 | Membership tiers, pricing and class allowances |
| Instructors | 8 | Fitness instructors |
| Classes | 14 | Available fitness classes |
| Sessions | 112 | Scheduled class sessions |
| Bookings | 778 | Class reservations and booking outcomes |
| Check-ins | 1,044 | Gym entry records |
| **Total** | **2,080** | |

The class analysis covers 5 May to 6 July 2025, while gym check-in records cover 5 May to 29 June 2025.

**Data source:** [Gym Memberships and Class Bookings Dataset](https://databasesample.com/datasets/gym-memberships-and-class-bookings-dataset)

## 5. Data Cleaning and Validation

Before conducting the analysis, I assessed the accuracy, consistency and reliability of the dataset.

The data preparation process included:

- Missing value identification.
- Duplicate record detection.
- Referential integrity checks.
- Data profiling.
- Identification of inconsistencies and anomalies.
- Validation of primary and foreign key relationships.
- Separation of data quality issues from operational and commercial concerns.

A total of 33 surplus booking records were excluded from the cleaned reporting layer, resulting in 745 unique member-session booking records.

A status-priority rule was implemented using SQL window functions to resolve conflicting booking outcomes.

Two database schemas were maintained:

- `club_raw` — original, unmodified source data.
- `club_clean` — cleaned, transformed and analysis-ready reporting views.

This approach preserved the original dataset while maintaining transparency and auditability throughout the analytical process.

## 6. Advanced SQL Analysis

The project contains 12 SQL scripts covering the complete analytical workflow, from database creation to Power BI reporting views.

Advanced SQL techniques include:

- Common Table Expressions (CTEs).
- Recursive CTEs.
- Complex relational joins.
- Window functions.
- ROW_NUMBER().
- DENSE_RANK().
- LAG().
- LEAD().
- Conditional aggregation.
- Subqueries.
- CASE WHEN statements.
- Running totals.
- Reusable SQL views.

These techniques were used to analyse membership concentration, segment customers, identify commercial opportunities, evaluate attendance trends and assess operational performance.

## 7. Key Findings and Business Insights

### 7.1 Membership and Commercial Performance

| KPI | Result |
|---|---:|
| Total members | 120 |
| Estimated monthly membership income | £4,480 |
| Estimated annualised membership income | £53,760 |
| Average monthly membership fee | £37.33 |
| Potential membership upgrade leads | 12 |
| Illustrative monthly income uplift | £240 |

#### Membership Distribution

| Membership tier | Monthly fee | Members | Estimated monthly income |
|---|---:|---:|---:|
| Tier 1 | £19 | 47 | £893 |
| Tier 2 | £39 | 46 | £1,794 |
| Tier 3 | £59 | 17 | £1,003 |
| Tier 4 | £79 | 10 | £790 |
| **Total** | | **120** | **£4,480** |

The analysis revealed that 77.5% of members subscribe to the two lowest-priced membership tiers.

Despite Tier 1 having the largest membership base, Tier 2 contributes the highest estimated monthly income, accounting for approximately 40% of total estimated membership income.

#### Membership Upgrade Opportunities

By comparing June class attendance against each member's monthly class allowance, I identified 12 potential upgrade candidates.

These members had reached or exceeded their existing class allowance and had a higher membership tier available.

| Upgrade conversion scenario | Additional monthly income | Annualised additional income |
|---|---:|---:|
| 25% | £60 | £720 |
| 50% | £120 | £1,440 |
| 75% | £180 | £2,160 |
| 100% | £240 | £2,880 |

**Business recommendation:** Introduce personalised membership upgrade offers targeting members whose class usage suggests they may benefit from a higher membership tier, rather than implementing a blanket price increase.

These scenarios represent hypothetical opportunities, not guaranteed income or revenue forecasts.

### 7.2 Customer Engagement

A total of 1,044 gym check-ins were recorded during the eight-week observation period.

Members were segmented according to their visiting frequency.

| Engagement segment | Check-in frequency | Members | Percentage |
|---|---|---:|---:|
| Low | 0–3 visits | 44 | 36.7% |
| Moderate | 4–11 visits | 35 | 29.2% |
| High | 12+ visits | 41 | 34.2% |

The analysis revealed that over one-third of members visited the gym three times or fewer during the observation period.

This identifies a customer segment that may benefit from additional engagement initiatives. However, low engagement alone does not establish that a member intends to cancel their membership.

#### Peak Visiting Hours

The busiest individual hourly period was between 7 pm and 8 pm, during which 92 check-ins were recorded across the observation period.

**Business recommendations:**

- Introduce personalised engagement campaigns for infrequent visitors.
- Offer fitness progress reviews and goal-setting initiatives.
- Investigate barriers to regular gym attendance.
- Review staffing allocation during peak evening hours.

### 7.3 Operational Efficiency

| Operational KPI | Result |
|---|---:|
| Total scheduled sessions | 112 |
| Total scheduled class places | 1,240 |
| Total cleaned bookings | 745 |
| Attended bookings | 484 |
| Cancelled bookings | 162 |
| No-shows | 99 |
| Actual capacity utilisation | 39.03% |
| Cancellation rate | 21.74% |
| No-show rate | 16.98% |
| Potentially overbooked sessions | 2 |
| Underutilised sessions | 72 |

The analysis revealed an overall class capacity utilisation rate of 39.03%, highlighting an opportunity to improve the use of available facilities and scheduled class resources.

Approximately 64.3% of scheduled sessions operated below the analytical utilisation threshold of 50%.

#### Class Performance

| Fitness class | Capacity utilisation |
|---|---:|
| HIIT Circuit | 69.4% |
| Core and Abs | 62.5% |
| Indoor Rowing | 53.8% |
| Kettlebell | 45.0% |
| Zumba | 42.7% |
| Boxing Fitness | 35.6% |
| Vinyasa Flow | 35.4% |
| Reformer Pilates | 34.4% |
| Strength Basics | 34.4% |
| Mobility and Stretch | 34.1% |
| Hatha Yoga | 33.0% |
| Barre | 31.8% |
| Spin | 29.5% |
| Aqua Fit | 23.1% |

HIIT Circuit achieved the highest capacity utilisation, followed by Core and Abs and Indoor Rowing.

Aqua Fit achieved the lowest capacity utilisation, suggesting an opportunity to investigate scheduling, promotion and member preferences.

#### Cancellations and No-shows

Of the 745 cleaned bookings, 162 were cancelled and 99 resulted in no-shows.

Approximately 17% of non-cancelled reservations resulted in members not attending their scheduled classes.

**Business recommendations:**

- Review the scheduling of consistently underutilised classes.
- Investigate opportunities to expand high-demand fitness classes.
- Trial automated booking reminders.
- Review cancellation policies and waitlist functionality.
- Evaluate instructor and facility allocation against observed demand.

## 8. Business Recommendations Summary

| Business area | Key finding | Recommended action |
|---|---|---|
| Membership income | 12 potential upgrade candidates | Introduce targeted upgrade offers |
| Customer engagement | 44 low-engagement members | Develop personalised engagement campaigns |
| Staffing | Peak visits between 7 pm and 8 pm | Review evening staffing allocation |
| Class performance | 72 underutilised sessions | Review scheduling and class promotion |
| Booking efficiency | 99 no-shows | Trial automated reminders and waitlists |

The proposed recommendations aim to support sustainable commercial growth, improve member experience and optimise operational resources.

## 9. Power BI Dashboard

The interactive Power BI report is structured around two business reporting pages.

### Page 1 — Membership & Commercial Performance

- Membership distribution.
- Estimated monthly and annualised income.
- Income contribution by membership tier.
- Customer engagement segmentation.
- Membership upgrade opportunities.
- Commercial insights and recommendations.

### Page 2 — Engagement & Operational Efficiency

- Weekly class attendance trends.
- Class capacity utilisation.
- Cancellation and no-show rates.
- Class performance comparisons.
- Peak visiting hours heatmap.
- Operational insights and recommendations.

The report uses SQL reporting views, relational data modelling and custom DAX measures to support interactive business analysis.

## Power BI Dashboard

The two-page interactive Power BI dashboard presents key commercial and operational insights to support management decision-making.

### Membership & Commercial Performance

![Membership Dashboard](Power%20BI/Membership_dashboard.png)

### Engagement & Operational Efficiency

![Operational Dashboard](Power%20BI/Operational_dashboard.png)
## 10. Data Limitations and Assumptions

- The analysis uses a sample dataset rather than actual gym performance records.
- The source does not specify a currency; GBP has been assumed for presentation purposes.
- Estimated membership income assumes all recorded members pay their current listed membership fee.
- Actual revenue, profitability and confirmed membership churn cannot be calculated from the available data.
- Membership upgrade opportunities are hypothetical and do not represent confirmed customer demand.
- Engagement segmentation and the 50% underutilisation threshold are analyst-defined criteria.
- The dataset covers a limited observation period and cannot establish long-term seasonal trends.
- Gym check-in records and class attendance records cannot be directly linked to individual visits.

## 11. Conclusion & Future Recommendations

The analysis identified three key opportunities for the gym: increasing membership income, strengthening customer engagement and improving operational efficiency.

With 77.5% of members subscribed to the two lowest-priced membership tiers, the gym could explore targeted membership upgrades as an alternative to increasing prices across its entire customer base. The identification of 12 potential upgrade candidates demonstrates how understanding customer behaviour can uncover opportunities for commercial growth.

Customer engagement also presents an area for improvement, with 36.7% of members visiting the gym three times or fewer during the eight-week observation period. Developing personalised engagement initiatives could encourage more frequent attendance, improve customer satisfaction and potentially support long-term membership retention.

From an operational perspective, an overall class capacity utilisation rate of 39.03% suggests that existing resources could be used more effectively. By reviewing class schedules, promoting underutilised classes and trialling booking reminders, the gym could improve attendance and make better use of its facilities and instructors.

### Future Recommendations

To support further business growth, future analysis could incorporate:

- Membership renewal and cancellation records to identify factors influencing customer retention.
- Payment and expenditure data to assess actual revenue, profitability and customer lifetime value.
- Customer feedback to better understand membership preferences and barriers to attendance.
- Historical attendance data to identify seasonal trends and anticipate future demand.
- The performance of targeted marketing campaigns and membership upgrade offers to measure their commercial impact.

By continuously monitoring these areas, the gym could move towards a more proactive, customer-focused business strategy that balances commercial growth with an improved member experience and more efficient use of resources.
