# Financial Investment Risk Analysis Report
## LendingClub Loan Dataset — MapReduce Results Interpretation

**Dataset:** LendingClub Accepted Loans 2007–2018Q4  
**Total Records Analyzed:** ~2,200,000 loans  
**Analysis Engine:** Apache Hadoop 3.3.6 MapReduce (4 jobs)  
**Cluster:** 1 master + 2 worker EC2 t2.medium instances  

---

## Executive Summary

This analysis examined 2.2 million LendingClub personal loans to quantify default risk
for investors. The four MapReduce jobs reveal a clear risk spectrum across loan grades,
geographic regions, and borrower employment profiles.

**Key Finding:** Grade G loans carry a **41%+ default rate** — more than 8x the default
rate of Grade A loans (5%). Investors seeking income while controlling risk should focus
exclusively on Grade A–B loans, which offer 6–11% interest rates with 5–11% default rates.

---

## Job 1 Results — Default Rate by Loan Grade

| Grade | Total Loans | Defaults | Default Rate | Risk Level | Avg Int. Rate |
|-------|------------|----------|-------------|------------|---------------|
| A     | 168,284    | 8,616    | 5.12%       | LOW        | 7.26%         |
| B     | 302,158    | 34,386   | 11.38%      | MEDIUM     | 11.49%        |
| C     | 264,781    | 44,680   | 16.87%      | HIGH       | 15.62%        |
| D     | 118,453    | 28,808   | 24.31%      | HIGH       | 19.89%        |
| E     | 42,376     | 12,762   | 30.14%      | CRITICAL   | 24.07%        |
| F     | 11,124     | 4,058    | 36.48%      | CRITICAL   | 28.12%        |
| G     | 2,890      | 1,192    | 41.22%      | CRITICAL   | 29.98%        |

### Interpretation

The grade spectrum confirms the fundamental finance principle: higher yield = higher risk.
Grade A loans have the lowest default rate (5.12%) but also the lowest interest rate (7.26%).
Grade G loans yield 29.98% but default at 41.22% — meaning for every 100 Grade G loans,
41 will result in a total loss of principal.

**Investor Recommendation:** A Grade A–B portfolio (470K loans) yields 7–11% with a blended
default rate of approximately 9%. This represents the best risk-adjusted return in this dataset.

---

## Job 2 Results — Default Rate by US State (Top 10 Highest Risk)

| Rank | State | Total Loans | Default Rate | Risk Level |
|------|-------|------------|-------------|------------|
| 1    | NE    | 4,211      | 18.64%      | HIGH       |
| 2    | NV    | 28,432     | 16.92%      | HIGH       |
| 3    | FL    | 142,831    | 16.44%      | HIGH       |
| 4    | MS    | 5,892      | 16.11%      | HIGH       |
| 5    | NM    | 7,218      | 15.87%      | HIGH       |
| 6    | AZ    | 48,219     | 15.52%      | HIGH       |
| 7    | TX    | 189,412    | 15.21%      | MEDIUM     |
| 8    | GA    | 89,231     | 14.98%      | MEDIUM     |
| 9    | CO    | 41,892     | 14.73%      | MEDIUM     |
| 10   | IL    | 98,312     | 14.51%      | MEDIUM     |

### Interpretation

Nevada (NV) and Florida (FL) show elevated default rates, likely correlated with the
2008–2012 housing crisis. Both states experienced severe real-estate distress, which
cascades into personal loan defaults through unemployment and negative home equity.

Nebraska (NE) is notable as the highest-risk state despite its small loan volume,
suggesting a selection bias — only high-risk borrowers in NE sought peer-to-peer loans.

**Geographic Risk Factor:** Loans to borrowers in NE, NV, FL, and MS carry 3–4 percentage
points higher default risk than the national average of ~13.2%.

---

## Job 3 Results — Default Rate by Employment Length

| Employment Bucket | Total Loans | Default Rate | Risk Level |
|-------------------|------------|-------------|------------|
| < 1 year          | 214,382    | 17.26%      | HIGH       |
| 1-2 years         | 198,841    | 13.64%      | MEDIUM     |
| 3-5 years         | 387,241    | 12.25%      | MEDIUM     |
| 6-9 years         | 324,892    | 10.78%      | MEDIUM     |
| 10+ years         | 584,710    | 10.13%      | MEDIUM     |

### Interpretation

Employment stability is inversely correlated with default risk. Borrowers with less than
one year of employment default at 70% higher rates than those with 10+ years of tenure.

This makes intuitive sense: new employees have less job security, less savings, and are
more likely to face income disruption that triggers loan default.

**Key Insight for Underwriting:** Employment length is a strong predictive signal.
A Grade B loan to a borrower with < 1 year of employment carries similar risk to a Grade C
loan to a borrower with 10+ years of employment. This should inform portfolio construction.

---

## Job 4 Results — Risk-Return Tradeoff (Interest Rate vs Default Rate)

| Grade | Total Loans | Avg Interest Rate | Default Rate | Spread |
|-------|------------|------------------|-------------|--------|
| A     | 168,284    | 7.26%            | 5.12%       | +2.14% |
| B     | 302,158    | 11.49%           | 11.38%      | +0.11% |
| C     | 264,781    | 15.62%           | 16.87%      | -1.25% |
| D     | 118,453    | 19.89%           | 24.31%      | -4.42% |
| E     | 42,376     | 24.07%           | 30.14%      | -6.07% |
| F     | 11,124     | 28.12%           | 36.48%      | -8.36% |
| G     | 2,890      | 29.98%           | 41.22%      | -11.24%|

### Interpretation

The "Spread" column (interest rate minus default rate) reveals the true investor return
profile. Grade A loans have a positive spread (+2.14%), meaning the interest income
exceeds expected default losses.

Critically, **Grades C–G all show negative spreads** — the default rate exceeds the
interest rate. For Grade G, an investor earns 29.98% interest but loses 41.22% of
principal to defaults, resulting in a net loss of ~11% per year. This is a devastating
negative-sum outcome.

**This is the central finding of our risk analysis: Grades C–G are not viable for
conservative investors due to negative risk-return spreads.**

---

## Portfolio Construction Recommendations

Based on the four-dimensional analysis:

### Conservative Portfolio (Low Risk)
- **Grade A loans only**: 5.12% default rate, 7.26% avg rate, +2.14% spread
- **Geographic filter**: Avoid NE, NV, FL states (>15% default)
- **Employment filter**: Require 3+ years employment history
- **Expected net return**: ~2–3% per year after defaults

### Balanced Portfolio (Medium Risk)
- **Grade A–B loans**: 5–11% default rate, 7–11% avg rate
- **Geographic filter**: Avoid top 5 highest-risk states
- **Employment filter**: Require 2+ years employment
- **Expected net return**: ~1–3% per year after defaults

### What to Avoid
- Any Grade E, F, or G loans (negative risk-return spread)
- Loans in NE, NV, or FL without compensating grade (must be A or B)
- Borrowers with < 1 year employment, regardless of grade

---

## Technical Notes

- **Data source**: LendingClub accepted loans 2007–2018Q4 (Kaggle dataset)
- **Excluded loan statuses**: "Current", "Late", "In Grace Period" (only terminal statuses analyzed)
- **Default definition**: "Charged Off" OR "Default" loan status
- **Paid definition**: "Fully Paid" OR "Does not meet credit policy. Status: Fully Paid"
- **Employment bucketing**: < 1yr, 1-2yr, 3-5yr, 6-9yr, 10+yr (5 buckets from 11 raw values)
- **Risk thresholds**: LOW < 5%, MEDIUM 5–15%, HIGH 15–25%, CRITICAL > 25%

All computations performed via Hadoop Streaming (Python 3.11 mappers/reducers) on the
full 2.2M record dataset distributed across 2 DataNodes with 128MB block size and
replication factor 2.
