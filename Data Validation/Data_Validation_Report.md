# Data Validation Report

**Project:** Gym Membership & Commercial Performance Analysis  
**Case study:** Small community gym (sample dataset)  
**Tools:** MySQL, MySQL Workbench

## Objective

Assess the completeness, consistency and relational integrity of the source data before commercial and operational analysis. Preserve the original records and document any changes made to the reporting layer.

## Validation summary

| Validation check | Finding | Treatment |
|---|---|---|
| Data ingestion | 2,080 records across seven tables | Reconcile imported counts against the source files |
| Missing values | No missing values identified in the source checks | No imputation required |
| Duplicate bookings | 31 repeated member-session groups, containing 64 records and 33 surplus rows | Retain one outcome per member-session pair in the clean view |
| Conflicting booking outcomes | 15 repeated groups contain conflicting statuses | Apply a documented status-priority rule; subject to business confirmation |
| Referential integrity | Zero orphan records across the six foreign-key relationships | No orphan remediation required |
| Clean layer reconciliation | 778 raw bookings = 745 retained + 33 excluded | Use the clean view for booking KPIs; retain excluded rows for audit |
| Raw data preservation | Row counts and content fingerprints checked against the ingestion baseline for all seven tables | Retain the original data in `club_raw` |

## Data ingestion reconciliation

| Table | Source records |
|---|---:|
| plans | 4 |
| instructors | 8 |
| members | 120 |
| classes | 14 |
| sessions | 112 |
| bookings | 778 |
| check_ins | 1,044 |
| **Total** | **2,080** |

## Cleaning methodology

The reporting layer (`club_clean`) uses SQL views rather than deleting or overwriting source records in `club_raw`. A `ROW_NUMBER()` window function partitions bookings by member and session and prioritises outcomes in the order `attended`, `no_show`, `cancelled`. Where outcomes are equal, the lowest booking ID is retained. The rule provides a consistent analytical outcome but does not establish the true sequence of booking events; cancellation and rebooking may be legitimate.

After applying this rule, the booking count decreased from 778 to 745 (33 surplus rows excluded, approximately 4.24% of the raw booking records). Excluded records remain accessible through an audit view.

## Supporting evidence

The accompanying MySQL Workbench screenshots document the validation queries and their outputs. The relevant scripts are included in the repository.

| Evidence | SQL stage | Purpose |
|---|---|---|
| Data ingestion validation | 02 | Compare loaded and expected row counts |
| Missing value checks | 03 | Check completeness; membership query shown as an example |
| Duplicate detection | 04 | Quantify repeated and conflicting booking records |
| Referential integrity | 05 | Check for unmatched parent records |
| Clean layer validation | 07 | Reconcile raw, retained and excluded booking records |
| Raw data preservation | 07 | Compare current row counts and content fingerprints with the baseline |

## Remaining limitations

- Check-ins cannot be directly linked to individual class bookings.
- Unusual check-in times and near-duplicate entries require business confirmation; they are not automatically removed.
- Membership plan history, actual payments and cancellation timestamps are unavailable.
- Counts and fingerprints provide a practical preservation check, not absolute proof of identical contents.

## Conclusion

The validation process established a consistent basis for membership, engagement and class-performance analysis while retaining the original source data. Documented assumptions and unresolved issues should accompany the resulting KPIs so that management can interpret the findings appropriately. The clean reporting layer reduces the risk of inflated booking counts and supports traceable, reproducible analysis.
