-- Modelling population used by all checks below
-- 36m loans, Sep 2012 to Dec 2015, closed only (see docs/decisions.md)

CREATE SCHEMA clean;

CREATE VIEW clean.v_population AS
WITH closed AS (
    SELECT r.*,
           TO_DATE(r.issue_d, 'Mon-YYYY') AS issue_date
    FROM raw.lc_loans r
    WHERE TRIM(r.term) = '36 months'
      AND r.loan_status IN ('Fully Paid', 'Charged Off')
)
SELECT *,
       CASE
         WHEN issue_date BETWEEN DATE '2012-09-01' AND DATE '2013-12-01' THEN 'train'
         WHEN issue_date BETWEEN DATE '2014-01-01' AND DATE '2014-12-01' THEN 'validation'
         ELSE 'oot'
       END AS sample,
       CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END AS bad
FROM closed
WHERE issue_date BETWEEN DATE '2012-09-01' AND DATE '2015-12-01';


-- Check: counts should match docs/decisions.md
SELECT sample,
       COUNT(*) AS n,
       SUM(bad) AS n_bad,
       ROUND(100.0 * AVG(bad), 1) AS bad_rate
FROM clean.v_population
GROUP BY sample
ORDER BY MIN(issue_date);

-- Categorical variables: values, counts and bad rate (train only)
SELECT 'emp_length' AS var, emp_length AS value, COUNT(*) AS n, ROUND(100.0 * AVG(bad), 1) AS bad_rate
FROM clean.v_population WHERE sample = 'train' GROUP BY emp_length
UNION ALL
SELECT 'home_ownership', home_ownership, COUNT(*), ROUND(100.0 * AVG(bad), 1)
FROM clean.v_population WHERE sample = 'train' GROUP BY home_ownership
UNION ALL
SELECT 'verification_status', verification_status, COUNT(*), ROUND(100.0 * AVG(bad), 1)
FROM clean.v_population WHERE sample = 'train' GROUP BY verification_status
UNION ALL
SELECT 'purpose', purpose, COUNT(*), ROUND(100.0 * AVG(bad), 1)
FROM clean.v_population WHERE sample = 'train' GROUP BY purpose
ORDER BY var, value;


-- Numeric variables: values that cannot be read as a number (nulls not counted)
SELECT COUNT(*) AS n,
       SUM(CASE WHEN loan_amnt            !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS loan_amnt,
       SUM(CASE WHEN annual_inc           !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS annual_inc,
       SUM(CASE WHEN dti                  !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS dti,
       SUM(CASE WHEN fico_range_low       !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS fico_low,
       SUM(CASE WHEN fico_range_high      !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS fico_high,
       SUM(CASE WHEN revol_util           !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS revol_util,
       SUM(CASE WHEN revol_bal            !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS revol_bal,
       SUM(CASE WHEN open_acc             !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS open_acc,
       SUM(CASE WHEN total_acc            !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS total_acc,
       SUM(CASE WHEN delinq_2yrs          !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS delinq_2yrs,
       SUM(CASE WHEN inq_last_6mths       !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS inq_6m,
       SUM(CASE WHEN pub_rec              !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS pub_rec,
       SUM(CASE WHEN pub_rec_bankruptcies !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS bankruptcies,
       SUM(CASE WHEN mort_acc             !~ '^-?[0-9]+(\.[0-9]+)?$' THEN 1 ELSE 0 END) AS mort_acc
FROM clean.v_population;
