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

### Limitations so far
- No monthly payment history, so days past due can't be seen. A loan that went
  past 90 days and then cured looks the same as a clean one.
- 2012-2015 was a calm period for the US economy. No downturn in the sample.
- Only funded loans have outcomes. Rejected applications aren't in the model.

### Still open
`installment` is built from `int_rate`, so it carries some of LC's pricing. Use
it, or build affordability from `loan_amnt` and `annual_inc` instead?