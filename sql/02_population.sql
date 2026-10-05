-- Sample design check: loans, bads and open loans in each part
-- Rules: docs/decisions.md

WITH base AS (
    SELECT id,
           loan_status,
           TO_DATE(issue_d, 'Mon-YYYY') AS issue_date
    FROM raw.lc_loans
    WHERE TRIM(term) = '36 months'
      AND issue_d IS NOT NULL
      AND loan_status NOT LIKE 'Does not meet%'
),
labelled AS (
    SELECT *,
           CASE
             WHEN issue_date BETWEEN DATE '2012-09-01' AND DATE '2013-12-01' THEN '1. train'
             WHEN issue_date BETWEEN DATE '2014-01-01' AND DATE '2014-12-01' THEN '2. validation'
             WHEN issue_date BETWEEN DATE '2015-01-01' AND DATE '2015-12-01' THEN '3. oot'
             WHEN issue_date >= DATE '2016-01-01'                            THEN '4. monitoring'
             ELSE '0. out of scope'
           END AS sample
    FROM base
)
SELECT sample,
       COUNT(*) AS n,
       SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END) AS n_bad,
       ROUND(100.0 * AVG(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END), 1) AS bad_rate,
       SUM(CASE WHEN loan_status NOT IN ('Fully Paid', 'Charged Off') THEN 1 ELSE 0 END) AS n_open
FROM labelled
GROUP BY sample
ORDER BY sample;



-- OOT (2015, 36m): loans not closed at the data cut-off
SELECT loan_status,
       issue_d,
       COUNT(*) AS n
FROM raw.lc_loans
WHERE TRIM(term) = '36 months'
  AND RIGHT(issue_d, 4) = '2015'
  AND loan_status NOT IN ('Fully Paid', 'Charged Off')
GROUP BY loan_status, issue_d
ORDER BY loan_status, TO_DATE(issue_d, 'Mon-YYYY');