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

-- Numeric variables: nulls and range (all modelling loans)
SELECT v.var,
       COUNT(*) - COUNT(v.val) AS n_null,
       MIN(v.val) AS min,
       ROUND(percentile_cont(0.01) WITHIN GROUP (ORDER BY v.val)::numeric, 1) AS p01,
       ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY v.val)::numeric, 1) AS p50,
       ROUND(percentile_cont(0.99) WITHIN GROUP (ORDER BY v.val)::numeric, 1) AS p99,
       MAX(v.val) AS max
FROM clean.v_population p
CROSS JOIN LATERAL (VALUES
    ('loan_amnt',            p.loan_amnt::numeric),
    ('annual_inc',           p.annual_inc::numeric),
    ('dti',                  p.dti::numeric),
    ('fico_range_low',       p.fico_range_low::numeric),
    ('fico_range_high',      p.fico_range_high::numeric),
    ('revol_util',           p.revol_util::numeric),
    ('revol_bal',            p.revol_bal::numeric),
    ('open_acc',             p.open_acc::numeric),
    ('total_acc',            p.total_acc::numeric),
    ('delinq_2yrs',          p.delinq_2yrs::numeric),
    ('inq_last_6mths',       p.inq_last_6mths::numeric),
    ('pub_rec',              p.pub_rec::numeric),
    ('pub_rec_bankruptcies', p.pub_rec_bankruptcies::numeric),
    ('mort_acc',             p.mort_acc::numeric)
) AS v(var, val)
GROUP BY v.var
ORDER BY v.var;

-- Suspicious values: zero income, dti = 999, utilisation over 100%, open > total accounts
SELECT COUNT(*) FILTER (WHERE annual_inc::numeric = 0)                         AS inc_zero,
       COUNT(*) FILTER (WHERE dti::numeric = 999)                              AS dti_999,
       COUNT(*) FILTER (WHERE annual_inc::numeric = 0 AND dti::numeric = 999)  AS inc_zero_and_dti_999,
       COUNT(*) FILTER (WHERE dti IS NULL)                                     AS dti_null,
       COUNT(*) FILTER (WHERE dti::numeric > 60 AND dti::numeric < 999)        AS dti_over_60,
       COUNT(*) FILTER (WHERE revol_util::numeric > 100)                       AS util_over_100,
       COUNT(*) FILTER (WHERE open_acc::numeric > total_acc::numeric)          AS open_gt_total
FROM clean.v_population;

-- earliest_cr_line: format, range, and any dates after the issue date
SELECT COUNT(*) FILTER (WHERE earliest_cr_line IS NULL)                              AS n_null,
       COUNT(*) FILTER (WHERE earliest_cr_line !~ '^[A-Z][a-z]{2}-[0-9]{4}$')         AS bad_format,
       MIN(TO_DATE(earliest_cr_line, 'Mon-YYYY'))                                    AS min_date,
       MAX(TO_DATE(earliest_cr_line, 'Mon-YYYY'))                                    AS max_date,
       COUNT(*) FILTER (WHERE TO_DATE(earliest_cr_line, 'Mon-YYYY') > issue_date)    AS after_issue
FROM clean.v_population;



-- Bureau and months-since fields: % missing by sample, and range
-- Runs without error = every value is numeric
SELECT v.var,
       ROUND(100.0 * AVG(CASE WHEN v.val IS NULL THEN 1 ELSE 0 END) FILTER (WHERE p.sample = 'train'), 1)      AS null_train,
       ROUND(100.0 * AVG(CASE WHEN v.val IS NULL THEN 1 ELSE 0 END) FILTER (WHERE p.sample = 'validation'), 1) AS null_val,
       ROUND(100.0 * AVG(CASE WHEN v.val IS NULL THEN 1 ELSE 0 END) FILTER (WHERE p.sample = 'oot'), 1)        AS null_oot,
       MIN(v.val) AS min,
       MAX(v.val) AS max
FROM clean.v_population p
CROSS JOIN LATERAL (VALUES
    ('acc_now_delinq',                 p.acc_now_delinq::numeric),
    ('acc_open_past_24mths',           p.acc_open_past_24mths::numeric),
    ('avg_cur_bal',                    p.avg_cur_bal::numeric),
    ('bc_open_to_buy',                 p.bc_open_to_buy::numeric),
    ('bc_util',                        p.bc_util::numeric),
    ('chargeoff_within_12_mths',       p.chargeoff_within_12_mths::numeric),
    ('collections_12_mths_ex_med',     p.collections_12_mths_ex_med::numeric),
    ('delinq_amnt',                    p.delinq_amnt::numeric),
    ('mo_sin_old_il_acct',             p.mo_sin_old_il_acct::numeric),
    ('mo_sin_old_rev_tl_op',           p.mo_sin_old_rev_tl_op::numeric),
    ('mo_sin_rcnt_rev_tl_op',          p.mo_sin_rcnt_rev_tl_op::numeric),
    ('mo_sin_rcnt_tl',                 p.mo_sin_rcnt_tl::numeric),
    ('mths_since_last_delinq',         p.mths_since_last_delinq::numeric),
    ('mths_since_last_major_derog',    p.mths_since_last_major_derog::numeric),
    ('mths_since_last_record',         p.mths_since_last_record::numeric),
    ('mths_since_recent_bc',           p.mths_since_recent_bc::numeric),
    ('mths_since_recent_bc_dlq',       p.mths_since_recent_bc_dlq::numeric),
    ('mths_since_recent_inq',          p.mths_since_recent_inq::numeric),
    ('mths_since_recent_revol_delinq', p.mths_since_recent_revol_delinq::numeric),
    ('num_accts_ever_120_pd',          p.num_accts_ever_120_pd::numeric),
    ('num_actv_bc_tl',                 p.num_actv_bc_tl::numeric),
    ('num_actv_rev_tl',                p.num_actv_rev_tl::numeric),
    ('num_bc_sats',                    p.num_bc_sats::numeric),
    ('num_bc_tl',                      p.num_bc_tl::numeric),
    ('num_il_tl',                      p.num_il_tl::numeric),
    ('num_op_rev_tl',                  p.num_op_rev_tl::numeric),
    ('num_rev_accts',                  p.num_rev_accts::numeric),
    ('num_rev_tl_bal_gt_0',            p.num_rev_tl_bal_gt_0::numeric),
    ('num_sats',                       p.num_sats::numeric),
    ('num_tl_120dpd_2m',               p.num_tl_120dpd_2m::numeric),
    ('num_tl_30dpd',                   p.num_tl_30dpd::numeric),
    ('num_tl_90g_dpd_24m',             p.num_tl_90g_dpd_24m::numeric),
    ('num_tl_op_past_12m',             p.num_tl_op_past_12m::numeric),
    ('pct_tl_nvr_dlq',                 p.pct_tl_nvr_dlq::numeric),
    ('percent_bc_gt_75',               p.percent_bc_gt_75::numeric),
    ('tax_liens',                      p.tax_liens::numeric),
    ('tot_coll_amt',                   p.tot_coll_amt::numeric),
    ('tot_cur_bal',                    p.tot_cur_bal::numeric),
    ('tot_hi_cred_lim',                p.tot_hi_cred_lim::numeric),
    ('total_bal_ex_mort',              p.total_bal_ex_mort::numeric),
    ('total_bc_limit',                 p.total_bc_limit::numeric),
    ('total_il_high_credit_limit',     p.total_il_high_credit_limit::numeric),
    ('total_rev_hi_lim',               p.total_rev_hi_lim::numeric)
) AS v(var, val)
GROUP BY v.var
ORDER BY v.var;



-- Placeholder-looking values and utilisation over 100%
SELECT COUNT(*) FILTER (WHERE tot_hi_cred_lim::numeric  = 9999999) AS tot_hi_cred_lim_9999999,
       COUNT(*) FILTER (WHERE total_rev_hi_lim::numeric = 9999999) AS total_rev_hi_lim_9999999,
       COUNT(*) FILTER (WHERE bc_util::numeric > 100)               AS bc_util_over_100
FROM clean.v_population;