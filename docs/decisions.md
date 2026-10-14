# Decisions

Running log of choices made while building the scorecard. Numbers come from
`raw.lc_loans` (Kaggle `wordsforthewise/lending-club`, `accepted_2007_to_2018Q4.csv`,
2,260,701 rows, 151 columns).

## 2026-09-30

### 36-month loans only
60-month loans issued from 2014 on were still running when the data was pulled
(16.3% Current in 2014, 31.3% in 2015). 36-month loans up to 2015 are all closed.
If I kept both terms, the 2015 OOT set would only contain 36-month loans, so the
test wouldn't match what the model was trained on.

60-month loans also default about twice as often (2013 vintage: 25.1% vs 12.3%).
Part of that is just two extra years to go bad. Could be a second model later.

### Split by issue date

| Set        | Loans issued        | Used for                                   |
|------------|---------------------|--------------------------------------------|
| Train      | Sep 2012 to Dec 2013 | fitting                                   |
| Validation | 2014                | binning, variable selection, model choice  |
| OOT        | 2015                | final test, looked at once                 |
| Monitoring | 2016-2018           | PSI only                                   |

After 2015 a big part of the book is still Current (36m: 26.8% in 2016, 57.4% in
2017, 85.9% in 2018), so outcomes there aren't final. Application data is complete
though, so these years are fine for checking drift.

Rule for myself: no going back to change the model after seeing 2015.

### Dropped
- 33 blank rows at the end of the file (no status, no issue date).
- 2,749 "Does not meet the credit policy" loans. Old policy, mostly 2007-2010,
  not the population the model is meant for.
- No joint applications in the window (joint fields start in 2016), so this is
  an individual-borrower model.

### Columns I can't use
- Filled only from late 2015, empty in train: `open_acc_6m`, `open_act_il`,
  `open_il_12m`, `open_il_24m`, `mths_since_rcnt_il`, `total_bal_il`, `il_util`,
  `open_rv_12m`, `open_rv_24m`, `max_bal_bc`, `all_util`, `inq_fi`, `total_cu_tl`,
  `inq_last_12m`.
- `desc`: LC phased it out (62% filled in 2012, 0% from 2015).
- `member_id` is empty, `emp_title` is free text.
- `grade`, `sub_grade`, `int_rate` are LC's own risk assessment. Kept out of the
  model. `grade` will be used as a benchmark.
- Anything recorded after the loan was issued (payments, recoveries, last FICO,
  hardship, settlement) stays out of the features. Only allowed for building
  the target.

The `mths_since_*` fields are blank when the event never happened. That's
information, not a data problem. Missing gets its own bin.

## 2026-10-05

### Train starts September 2012
Checked `tot_cur_bal` by month for 36m loans in 2012: 0% filled Jan to Jul, 16% in
Aug, 99-100% from Sep. It's one of about 35 bureau fields that were ~48% filled
in 2012, so they most likely switched on at the same time. Should double check
the others in the data quality step. Starting earlier would make "missing" a
stand-in for the issue month.

### Default = Charged Off
Inside the modelling window every loan ended as either Fully Paid or Charged Off,
so there are no Current, Late or Grace cases to deal with. The only open question
was Fully Paid loans that paid a late fee.

Train window, 36m:

| Group                | Loans   | Share | Avg FICO | Avg int. rate |
|----------------------|---------|-------|----------|---------------|
| Fully Paid, clean    | 103,925 | 86.1% | 697      | 13.0          |
| Fully Paid, late fee | 1,751   | 1.5%  | 687      | 14.7          |
| Charged Off          | 15,007  | 12.4% | 687      | 15.0          |

The late-fee group looks a lot like the charged-off group on FICO and rate. I'm
still counting them as good: they paid in full, and the target is default
(90+ dpd, Basel), not "ever late". Their weaker profile should show up through
the application variables anyway. I'll refit with them as bad to see how much
it matters.


### OOT: 147 loans still open
The sample check in `sql/02_population.sql` found 147 loans in the 2015 OOT set
that were not closed at the data cut-off. So the note above (every loan is Fully
Paid or Charged Off) holds for train and validation, not for OOT. Most were issued
Oct to Dec 2015 and simply hadn't reached the end of their term.

| Status             | Loans |
|--------------------|-------|
| Current            | 72    |
| In Grace Period    | 9     |
| Late (16-30 days)  | 5     |
| Late (31-120 days) | 61    |

Dropped all 147. None of them is charged off, so they don't have a final outcome
under the default definition. Counting the 61 Late (31-120) loans as bad would
move the OOT bad rate from 14.89% to 14.90%, so the choice doesn't matter in
practice.

Sample sizes after this:
train 120,683 (15,007 bad, 12.4%), validation 162,570 (22,315 bad, 13.7%),
OOT 283,026 (42,132 bad, 14.9%).

### Limitations so far
- No monthly payment history, so days past due can't be seen. A loan that went
  past 90 days and then cured looks the same as a clean one.
- 2012-2015 was a calm period for the US economy. No downturn in the sample.
- Only funded loans have outcomes. Rejected applications aren't in the model.

### Still open
`installment` is built from `int_rate`, so it carries some of LC's pricing. Use
it, or build affordability from `loan_amnt` and `annual_inc` instead?

## 2026-10-14

### Data quality (sql/03_data_quality.sql)
Checked on the modelling population (`clean.v_population`, 566,279 loans).

Format is fine. The 14 main numeric fields and the 43 bureau and months-since
fields all cast to numeric without errors. `earliest_cr_line` is always Mon-YYYY
and never after the issue date (range 1944 to Nov 2012).

Impossible or placeholder values, to be set to missing in the clean table:
- `annual_inc` = 0 (2 loans)
- `dti` = 999 (1 loan)
- `tot_hi_cred_lim` = 9,999,999 (6 loans), `total_rev_hi_lim` = 9,999,999 (3 loans)

Too few to matter, but the rule is simple: if a value can't be real, treat it as
missing instead of dropping the loan.

Left as they are: `revol_util` over 100% (2,203 loans) and `bc_util` over 100%
(10,350). Balances can go over the limit with interest and fees. Other extreme
but possible values (`pub_rec` up to 86, `delinq_2yrs` up to 30, income up to 9M)
are left for binning to absorb.

Categoricals:
- `home_ownership`: NONE (35) and OTHER (40) will be merged into RENT.
- `emp_length`: "< 1 year" becomes 0, "10+ years" becomes 10. Missing stays as
  its own group (5,858 loans in train, 17.7% bad vs 12.4% overall).
- `purpose`: 14 values, small ones get grouped during binning.

Dropped:
- `num_tl_120dpd_2m`: missing share jumps from 0.2% in train to 4-5% in
  validation and OOT, and the value is almost always 0.
- `fico_range_high`: always `fico_range_low` + 4, so one of them is enough.

Lending Club policy shows up in the data (not errors, but they limit what the
model can learn):
- FICO is never below 660.
- `loan_amnt` is capped at 35,000.
- The latest `earliest_cr_line` is Nov 2012, so nobody had a very short history.

Drift to keep an eye on: the share of applicants with no past delinquency drops
after train. `mths_since_last_delinq` is missing for 55.6% in train, 48.9% in
validation and 48.0% in OOT, with a similar pattern for `major_derog` and
`last_record`. Fits with the bad rate going up from 12.4% to 14.9%. PSI should
pick this up.

Open: `verification_status`. Verified loans have a higher bad rate (13.0%) than
Not Verified (12.0%), probably because LC chose whom to verify. That makes it
partly LC's own risk view, like `grade`. Decide during binning.

### Clean table (sql/04_build_clean.sql)
`clean.lc_model`, one row per loan, 1,554,864 rows, every id unique.

| Sample     | Loans   | Bad    | Bad rate | Bad (late fee counted) |
|------------|---------|--------|----------|------------------------|
| train      | 120,683 | 15,007 | 12.4%    | 16,758                 |
| validation | 162,570 | 22,315 | 13.7%    | 25,062                 |
| oot        | 283,026 | 42,132 | 14.9%    | 48,268                 |
| monitoring | 988,585 | n/a    | n/a      | n/a                    |

`bad_alt` counts late-fee payers as bad, for the sensitivity check. Their share
goes up from 1.5% in train to 2.2% in OOT.

`installment` is left out. It is built from `int_rate`, so it carries LC's own
pricing. Added `loan_to_income` (loan_amnt / annual_inc) instead, plus
`credit_hist_months` (issue date minus `earliest_cr_line`).

Shortest credit history is 36 months in every sample. One more LC policy rule:
nobody with less than three years of history.

Odd values in monitoring only: 973 missing incomes, 91 incomes under 1,000 (one
is 1, which gives `loan_to_income` = 35,000), 1,076 missing dti and 5 histories
over 75 years. Train and validation are clean. OOT only has the 2 zero incomes
and 3 dti cases noted above. Left as they are, since monitoring is only used for
PSI and these are a tiny share.

Missing `emp_length` keeps going up: 4.9% train, 5.9% validation, 6.7% OOT,
8.1% monitoring. Missing is the riskiest group (17.7% bad in train), so this is
another drift item for PSI.

### Binning and variable selection (notebooks/02_binning.ipynb)
Binning done with `optbinning` on train only. Numeric variables had to have a bad
rate that only goes up or only goes down across bins (`auto_asc_desc`). Missing
values get their own bin.

60 candidates. What the IVs on train say:
- FICO is the strongest at 0.129. Most variables sit between 0.02 and 0.08.
  Nothing above 0.3.
- Delinquency history is close to useless: `delinq_2yrs`, `mths_since_last_delinq`,
  `pub_rec` and bankruptcies are all under 0.001. Most likely LC turned down
  applicants with bad histories, so there's little left to learn among approved
  loans.
- `verification_status` has IV 0.002, so it's dropped. That closes the open point
  above.
- `loan_amnt` on its own is close to 0, but `loan_to_income` gets 0.047.

Selection: kept IV >= 0.02 (28 variables). Where two variables had WoE correlation
around 0.7 or more, kept the one with the higher IV, so roughly one per family.
That left 12.
- `home_ownership` vs `mort_acc` (correlation 0.65): kept `mort_acc`, since it
  comes from the credit file and `home_ownership` is self-reported.
- `mort_acc` was then dropped too: p-value 0.04 and Gini didn't move without it
  (0.328 / 0.323 either way). Its information is mostly inside `tot_hi_cred_lim`.
- `purpose` kept despite low IV (0.023). Small business loans are clearly riskier
  and it's easy to explain.

Final 11: `fico`, `annual_inc`, `tot_hi_cred_lim`, `bc_open_to_buy`, `dti`,
`loan_to_income`, `acc_open_past_24mths`, `mths_since_recent_inq`,
`percent_bc_gt_75`, `mo_sin_old_rev_tl_op`, `purpose`.

### Model
Logistic regression on WoE, fitted on train. All coefficients negative (higher WoE
means safer, so lower PD). p-values all below 0.001 and VIF all under 2.5
(checked on the 12-variable fit before dropping `mort_acc`).

Gini 0.328 on train, 0.323 on validation. Lower than a typical bank application
scorecard (0.5 to 0.7), which makes sense: approved loans only, FICO 660 and up,
so the population is more uniform.

### Scaling
600 points at good:bad odds of 50:1, 20 points to double the odds.
Points per bin = -factor x (coef x WoE + intercept / n) + offset / n.
Total score runs from 464 to 632.

How much each variable can move the score: `fico` 25, `acc_open_past_24mths` 24,
`tot_hi_cred_lim` 20, `mths_since_recent_inq` / `bc_open_to_buy` / `loan_to_income`
17, `purpose` 15, `annual_inc` 11, `dti` 10, `mo_sin_old_rev_tl_op` 8,
`percent_bc_gt_75` 4.

Also added a 1-1900 view that looks like the Turkish Findeks score: a straight
stretch of 464-632 onto 1-1900. Cosmetic only, it doesn't mean the same as a real
Findeks score.

| Score (1-1900) | Bad rate train | Bad rate validation |
|----------------|----------------|---------------------|
| 1-699          | 25.6%          | 26.0%               |
| 700-1099       | 12.8%          | 13.8%               |
| 1100-1499      | 5.0%           | 5.5%                |
| 1500-1699      | 1.0%           | 2.1%                |

Bad rate drops band by band in both samples. Validation is a bit higher in every
band: the model ranks 2014 well but slightly underestimates the level. To look at
under calibration.

Notes:
- FICO ended up with 13 bins. A scorecard used in practice would probably merge
  them into 5 or 6.
- `percent_bc_gt_75` only moves the score by 4 points. Keep an eye on it.


## Validation (notebooks/03_validation.ipynb)

### Model frozen before OOT
Saved as `models/scorecard_v1.joblib` and committed before the OOT set was scored
for the first time (commit "Freeze scorecard v1 before opening OOT"). OOT was
scored once and nothing was changed after that.

### Discrimination

| Sample     | Bad rate | Gini  | KS    | Gini of LC grade |
|------------|----------|-------|-------|------------------|
| train      | 12.4%    | 0.328 | 0.239 | 0.263            |
| validation | 13.7%    | 0.323 | 0.232 | 0.300            |
| OOT        | 14.9%    | 0.336 | 0.244 | 0.335            |

No drop on OOT. Using application data only, the model matches or beats LC's own
grade. To be fair to LC: `grade` only has 7 levels (A to G), which caps its Gini.
`sub_grade` (35 levels) would be a fairer comparison and would probably do a bit
better.

### Calibration

| Sample     | Predicted PD | Actual bad rate |
|------------|--------------|-----------------|
| train      | 12.4%        | 12.4%           |
| validation | 13.1%        | 13.7%           |
| OOT        | 13.0%        | 14.9%           |

The model still ranks OOT loans well but underestimates the level by 1.9 points.
The bad rate went up 2.5 points from train to OOT, and the model's predicted PD
only moved 0.6 of that. So most of the increase isn't explained by who applied.
Recommendation: recalibrate the PD level on recent data. No need to rebuild the
model.

### Stability
PSI on score deciles, train as the base: validation 0.009, OOT 0.010,
2016 0.002, 2017 0.013, 2018 0.068. All under 0.10. 2018 is moving up and worth
watching.

Read together with calibration: the same kind of applicants, but more of them
going bad. Something outside the application data changed, like the economy or
LC's own process.

### Sensitivity to the default definition
Same bins and variables, refitted with late-fee payers counted as bad. On the main
target the alternative model gets Gini 0.327 / 0.322 / 0.336, against
0.328 / 0.323 / 0.336 for v1. No coefficient changes sign. The choice made in the
default definition doesn't matter in practice.

### Cut-off (OOT, 1-1900 view)

| Minimum score | Approved | Bad rate of approved | Bads avoided |
|---------------|----------|----------------------|--------------|
| none          | 100%     | 14.9%                | 0%           |
| 700           | 86%      | 12.8%                | 26%          |
| 800           | 71%      | 11.0%                | 47%          |
| 900           | 53%      | 9.1%                 | 68%          |
| 1000          | 35%      | 7.2%                 | 83%          |

Which cut-off is right depends on the margin earned on good loans against the loss
on bad ones. Not modelled here.