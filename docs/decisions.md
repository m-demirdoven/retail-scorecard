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