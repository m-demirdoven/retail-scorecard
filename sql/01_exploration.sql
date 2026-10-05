-- First look at raw.lc_loans
-- Numbers referenced in docs/decisions.md come from these queries.
-- The column fill check by year was done in notebooks/01_data_exploration.ipynb.

-- Row count (2,260,701)
SELECT COUNT(*) FROM raw.lc_loans;


-- loan_status distribution
SELECT loan_status,
       COUNT(*) AS n,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM raw.lc_loans
GROUP BY loan_status
ORDER BY n DESC;


-- Status by issue year
SELECT RIGHT(issue_d, 4) AS issue_year,
       COUNT(*) AS n,
       ROUND(100.0 * SUM(CASE WHEN loan_status = 'Current'     THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_current,
       ROUND(100.0 * SUM(CASE WHEN loan_status = 'Fully Paid'  THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_fully_paid,
       ROUND(100.0 * SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_charged_off
FROM raw.lc_loans
GROUP BY issue_year
ORDER BY issue_year;


-- Status by issue year and term
-- 60m loans are still open from 2014 on, 36m loans are closed up to 2015
SELECT RIGHT(issue_d, 4) AS issue_year,
       TRIM(term) AS loan_term,
       COUNT(*) AS n,
       ROUND(100.0 * SUM(CASE WHEN loan_status = 'Current'     THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_current,
       ROUND(100.0 * SUM(CASE WHEN loan_status = 'Fully Paid'  THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_fully_paid,
       ROUND(100.0 * SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_charged_off
FROM raw.lc_loans
WHERE issue_d IS NOT NULL
GROUP BY issue_year, loan_term
ORDER BY issue_year, loan_term;


-- When do the bureau fields start in 2012? (36m)
-- tot_cur_bal: 0% Jan-Jul, 16% Aug, 99-100% from Sep
SELECT issue_d,
       COUNT(*) AS n,
       ROUND(100.0 * COUNT(tot_cur_bal) / COUNT(*)) AS pct_tot_cur_bal
FROM raw.lc_loans
WHERE TRIM(term) = '36 months'
  AND RIGHT(issue_d, 4) = '2012'
GROUP BY issue_d
ORDER BY TO_DATE(issue_d, 'Mon-YYYY');


-- Fully Paid loans with late fees vs clean vs charged off (train window only)
SELECT CASE
         WHEN loan_status = 'Charged Off'      THEN '3. Charged Off'
         WHEN total_rec_late_fee::numeric > 0  THEN '2. Fully Paid, late fee'
         ELSE                                       '1. Fully Paid, clean'
       END AS grp,
       COUNT(*) AS n,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct,
       ROUND(AVG(fico_range_low::numeric)) AS avg_fico,
       ROUND(AVG(REPLACE(int_rate, '%', '')::numeric), 1) AS avg_int_rate
FROM raw.lc_loans
WHERE TRIM(term) = '36 months'
  AND TO_DATE(issue_d, 'Mon-YYYY') BETWEEN DATE '2012-09-01' AND DATE '2013-12-01'
  AND loan_status IN ('Fully Paid', 'Charged Off')
GROUP BY grp
ORDER BY grp;