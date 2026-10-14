-- Modelling table: one row per loan, typed and cleaned
-- Rules: docs/decisions.md

DROP TABLE IF EXISTS clean.lc_model;

CREATE TABLE clean.lc_model AS
WITH base AS (
    SELECT r.*,
           TO_DATE(r.issue_d, 'Mon-YYYY') AS issue_date
    FROM raw.lc_loans r
    WHERE TRIM(r.term) = '36 months'
      AND r.loan_status NOT LIKE 'Does not meet%'
),
scoped AS (
    SELECT *,
           CASE
             WHEN issue_date BETWEEN DATE '2012-09-01' AND DATE '2013-12-01' THEN 'train'
             WHEN issue_date BETWEEN DATE '2014-01-01' AND DATE '2014-12-01' THEN 'validation'
             WHEN issue_date BETWEEN DATE '2015-01-01' AND DATE '2015-12-01' THEN 'oot'
             ELSE 'monitoring'
           END AS sample
    FROM base
    WHERE issue_date >= DATE '2012-09-01'
)
SELECT
    -- keys and labels
    id,
    issue_date,
    sample,
    CASE WHEN sample = 'monitoring' THEN NULL
         WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END AS bad,
    CASE WHEN sample = 'monitoring' THEN NULL
         WHEN loan_status = 'Charged Off' OR total_rec_late_fee::numeric > 0 THEN 1 ELSE 0 END AS bad_alt,
    grade AS lc_grade,                                   -- benchmark only, not a model input

    -- loan and borrower
    loan_amnt::numeric                                   AS loan_amnt,
    purpose,
    CASE WHEN emp_length = '< 1 year' THEN 0
         ELSE SUBSTRING(emp_length FROM '[0-9]+')::int END AS emp_length_yrs,   -- "10+ years" -> 10
    CASE WHEN home_ownership IN ('NONE', 'OTHER') THEN 'RENT'
         ELSE home_ownership END                         AS home_ownership,
    NULLIF(annual_inc::numeric, 0)                       AS annual_inc,          -- 0 is not a real income
    verification_status,
    NULLIF(dti::numeric, 999)                            AS dti,                 -- 999 is a placeholder

    -- derived
    CASE WHEN annual_inc::numeric > 0
         THEN ROUND(loan_amnt::numeric / annual_inc::numeric, 4) END AS loan_to_income,
    (DATE_PART('year',  AGE(issue_date, TO_DATE(earliest_cr_line, 'Mon-YYYY'))) * 12
   + DATE_PART('month', AGE(issue_date, TO_DATE(earliest_cr_line, 'Mon-YYYY'))))::int AS credit_hist_months,

    -- main bureau fields
    fico_range_low::numeric                              AS fico,
    revol_util::numeric                                  AS revol_util,
    revol_bal::numeric                                   AS revol_bal,
    open_acc::numeric                                    AS open_acc,
    total_acc::numeric                                   AS total_acc,
    delinq_2yrs::numeric                                 AS delinq_2yrs,
    inq_last_6mths::numeric                              AS inq_last_6mths,
    pub_rec::numeric                                     AS pub_rec,
    pub_rec_bankruptcies::numeric                        AS pub_rec_bankruptcies,
    mort_acc::numeric                                    AS mort_acc,

    -- months since last event (missing = never happened)
    mths_since_last_delinq::numeric                      AS mths_since_last_delinq,
    mths_since_last_record::numeric                      AS mths_since_last_record,
    mths_since_last_major_derog::numeric                 AS mths_since_last_major_derog,
    mths_since_recent_bc::numeric                        AS mths_since_recent_bc,
    mths_since_recent_bc_dlq::numeric                    AS mths_since_recent_bc_dlq,
    mths_since_recent_inq::numeric                       AS mths_since_recent_inq,
    mths_since_recent_revol_delinq::numeric              AS mths_since_recent_revol_delinq,

    -- other bureau fields (filled from Sep 2012)
    acc_now_delinq::numeric                              AS acc_now_delinq,
    acc_open_past_24mths::numeric                        AS acc_open_past_24mths,
    avg_cur_bal::numeric                                 AS avg_cur_bal,
    bc_open_to_buy::numeric                              AS bc_open_to_buy,
    bc_util::numeric                                     AS bc_util,
    chargeoff_within_12_mths::numeric                    AS chargeoff_within_12_mths,
    collections_12_mths_ex_med::numeric                  AS collections_12_mths_ex_med,
    delinq_amnt::numeric                                 AS delinq_amnt,
    mo_sin_old_il_acct::numeric                          AS mo_sin_old_il_acct,
    mo_sin_old_rev_tl_op::numeric                        AS mo_sin_old_rev_tl_op,
    mo_sin_rcnt_rev_tl_op::numeric                       AS mo_sin_rcnt_rev_tl_op,
    mo_sin_rcnt_tl::numeric                              AS mo_sin_rcnt_tl,
    num_accts_ever_120_pd::numeric                       AS num_accts_ever_120_pd,
    num_actv_bc_tl::numeric                              AS num_actv_bc_tl,
    num_actv_rev_tl::numeric                             AS num_actv_rev_tl,
    num_bc_sats::numeric                                 AS num_bc_sats,
    num_bc_tl::numeric                                   AS num_bc_tl,
    num_il_tl::numeric                                   AS num_il_tl,
    num_op_rev_tl::numeric                               AS num_op_rev_tl,
    num_rev_accts::numeric                               AS num_rev_accts,
    num_rev_tl_bal_gt_0::numeric                         AS num_rev_tl_bal_gt_0,
    num_sats::numeric                                    AS num_sats,
    num_tl_30dpd::numeric                                AS num_tl_30dpd,
    num_tl_90g_dpd_24m::numeric                          AS num_tl_90g_dpd_24m,
    num_tl_op_past_12m::numeric                          AS num_tl_op_past_12m,
    pct_tl_nvr_dlq::numeric                              AS pct_tl_nvr_dlq,
    percent_bc_gt_75::numeric                            AS percent_bc_gt_75,
    tax_liens::numeric                                   AS tax_liens,
    tot_coll_amt::numeric                                AS tot_coll_amt,
    tot_cur_bal::numeric                                 AS tot_cur_bal,
    NULLIF(tot_hi_cred_lim::numeric, 9999999)            AS tot_hi_cred_lim,     -- placeholder
    total_bal_ex_mort::numeric                           AS total_bal_ex_mort,
    total_bc_limit::numeric                              AS total_bc_limit,
    total_il_high_credit_limit::numeric                  AS total_il_high_credit_limit,
    NULLIF(total_rev_hi_lim::numeric, 9999999)           AS total_rev_hi_lim     -- placeholder
FROM scoped
WHERE sample = 'monitoring'
   OR loan_status IN ('Fully Paid', 'Charged Off');


-- Check: rows and bads by sample
SELECT sample,
       COUNT(*)  AS n,
       SUM(bad)  AS n_bad,
       ROUND(100.0 * AVG(bad), 1) AS bad_rate,
       SUM(bad_alt) AS n_bad_alt
FROM clean.lc_model
GROUP BY sample
ORDER BY MIN(issue_date);

-- Check: unique ids, derived fields, values set to missing
SELECT COUNT(*)                                        AS n,
       COUNT(DISTINCT id)                              AS n_unique_id,
       MIN(credit_hist_months)                         AS min_hist,
       MAX(credit_hist_months)                         AS max_hist,
       MIN(loan_to_income)                             AS min_lti,
       MAX(loan_to_income)                             AS max_lti,
       COUNT(*) FILTER (WHERE annual_inc IS NULL)      AS inc_null,
       COUNT(*) FILTER (WHERE dti IS NULL)             AS dti_null,
       COUNT(*) FILTER (WHERE emp_length_yrs IS NULL)  AS emp_null
FROM clean.lc_model;


-- Check: missing and odd values by sample
SELECT sample,
       COUNT(*) FILTER (WHERE annual_inc IS NULL)         AS inc_null,
       COUNT(*) FILTER (WHERE annual_inc < 1000)          AS inc_under_1000,
       COUNT(*) FILTER (WHERE dti IS NULL)                AS dti_null,
       COUNT(*) FILTER (WHERE credit_hist_months > 900)   AS hist_over_75y,
       ROUND(100.0 * AVG(CASE WHEN emp_length_yrs IS NULL THEN 1 ELSE 0 END), 1) AS emp_null_pct
FROM clean.lc_model
GROUP BY sample
ORDER BY MIN(issue_date);