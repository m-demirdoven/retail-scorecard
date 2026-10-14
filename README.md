# Retail credit scorecard on Lending Club data


*Türkçe: [README.tr.md](README.tr.md)*

An application scorecard (PD model) for 36-month unsecured personal loans, built
and validated the way a bank would do it: a sample design that deals with
right-censoring, a written-down default definition, WoE binning and logistic
regression, and a model frozen before it was tested out of time.

Every decision, with the numbers behind it, is logged in
[`docs/decisions.md`](docs/decisions.md).

## Results

| Sample            | Loans   | Bad rate | Gini  | KS    | Gini of LC grade |
|-------------------|---------|----------|-------|-------|------------------|
| Train (2012-13)   | 120,683 | 12.4%    | 0.328 | 0.239 | 0.263            |
| Validation (2014) | 162,570 | 13.7%    | 0.323 | 0.232 | 0.300            |
| OOT (2015)        | 283,026 | 14.9%    | 0.336 | 0.244 | 0.335            |

- No loss of discrimination out of time. With application data only, the model
  matches or beats Lending Club's own grade.
- The score distribution is stable (PSI under 0.10 from 2014 to 2018).
- The PD level is too low on OOT: 13.0% predicted against 14.9% actual. Applicants
  look the same, but more of them went bad. The model needs recalibrating, not
  rebuilding.
- Counting borrowers who paid late fees as bad doesn't change the model
  (Gini 0.336 either way on OOT).

## Data

Lending Club accepted loans, 2007 to 2018 Q4, from Kaggle
([wordsforthewise/lending-club](https://www.kaggle.com/datasets/wordsforthewise/lending-club)).
2,260,701 loans, 151 columns. The data is not included in this repo.

## Sample design

Only 36-month loans. 60-month loans issued from 2014 on were still open when the
data was pulled, so they couldn't be tested on the same years.

| Set        | Loans issued         | Used for                                   |
|------------|----------------------|--------------------------------------------|
| Train      | Sep 2012 to Dec 2013 | fitting                                    |
| Validation | 2014                 | binning, variable selection, model choices |
| OOT        | 2015                 | final test, looked at once                 |
| Monitoring | 2016 to 2018         | PSI only (outcomes not final yet)          |

- After 2015 most loans are still Current (57% in 2017, 86% in 2018), so their
  outcomes can't be used.
- Train starts in September 2012 because about 35 bureau fields are empty before
  that. Keeping earlier loans would turn "missing" into a proxy for issue date.
- The model was saved and committed before the OOT set was scored.

## Default definition

Bad = Charged Off. Good = Fully Paid, including loans that paid late fees along the
way (1.5% of train). They look risky (average FICO equal to charged-off loans) but
they didn't default, and the target is default, not "ever late". A sensitivity
check with them counted as bad gives the same model.

## Model

Eleven variables, chosen from 60 candidates by IV (at least 0.02), then one per
group of highly correlated variables, then dropping anything that didn't add Gini.

| Variable                | What it measures                                 |
|-------------------------|--------------------------------------------------|
| `fico`                  | Credit score                                     |
| `acc_open_past_24mths`  | New credit accounts in the last two years        |
| `tot_hi_cred_lim`       | Total credit limit across all accounts           |
| `bc_open_to_buy`        | Unused credit card limit                         |
| `mths_since_recent_inq` | Months since the last credit enquiry             |
| `loan_to_income`        | Loan amount / annual income (derived)            |
| `purpose`               | What the loan is for                             |
| `annual_inc`            | Annual income                                    |
| `dti`                   | Debt to income                                   |
| `mo_sin_old_rev_tl_op`  | Age of the oldest card                           |
| `percent_bc_gt_75`      | Share of cards used above 75% of their limit     |

All coefficients have the expected sign, p-values are under 0.001 and VIF under
2.5.

One finding worth pointing out: past delinquencies, public records and bankruptcies
carry almost no information here (IV under 0.001). In a bank they'd be among the
strongest variables. Lending Club most likely turned those applicants down already,
so among approved loans there's little left to learn from them.

## Scorecard

600 points at good:bad odds of 50:1, 20 points to double the odds. Scores run from
464 to 632. FICO moves the score the most (25 points), closely followed by new
accounts in the last two years (24 points).

The points table is in [`reports/scorecard_table.csv`](reports/scorecard_table.csv).
There's also a 1-1900 view that looks like the Turkish Findeks score, as a
cosmetic rescaling.

Cut-off on OOT, using the 1-1900 view:

| Minimum score | Approved | Bad rate of approved | Bad loans avoided |
|---------------|----------|----------------------|-------------------|
| none          | 100%     | 14.9%                | 0%                |
| 700           | 86%      | 12.8%                | 26%               |
| 800           | 71%      | 11.0%                | 47%               |
| 900           | 53%      | 9.1%                 | 68%               |

## Limitations

- No monthly payment history, so days past due can't be seen. A loan that went past
  90 days and then cured looks like a clean one.
- Approved loans only, no reject inference. Lending Club's policy shows in the data:
  FICO never below 660, at least 36 months of credit history, loan amount capped at
  35,000.
- 2012 to 2015 was a calm period for the US economy. The model hasn't seen a
  downturn.
- LC's `grade` has 7 levels, which limits its Gini. `sub_grade` would be a fairer
  benchmark.
- FICO ended up with 13 bins. A scorecard used in practice would merge them.

## Possible next steps

- Recalibrate the PD level on recent data.
- Benchmark against `sub_grade`.
- Profit-based cut-off using interest rates and recoveries.
- A separate model for 60-month loans.

## Repository


sql/
01_exploration.sql first look at the raw data
02_population.sql sample design check
03_data_quality.sql data quality checks
04_build_clean.sql builds clean.lc_model
notebooks/
01_data_exploration loads the raw CSV into PostgreSQL
02_binning binning, variable selection, model, scaling
03_validation validation of the frozen model
docs/decisions.md every decision with its evidence
reports/ points table and validation results
models/ frozen model (scorecard_v1.joblib)


## Running it

1. Download `accepted_2007_to_2018Q4.csv.gz` from Kaggle into `data/raw/`.
2. Create a PostgreSQL database called `retail_scorecard`.
3. Run `notebooks/01_data_exploration` to load the raw table, then
   `sql/04_build_clean.sql`.
4. Run `notebooks/02_binning` and `notebooks/03_validation`.

Python 3.10 with pandas, numpy, scipy, scikit-learn, statsmodels, optbinning,
sqlalchemy and psycopg2-binary.

## Conclusion

A simple 11-variable model built on application data alone ranks borrowers as well
as Lending Club's own grade, and it keeps that performance out of time. Its weak
spot is the level: the default rate went up in 2015 and the model didn't see it
coming. If it were used in practice, the first job would be recalibrating it on
recent data.

Most of the work was about the data rather than the model: knowing which loans
have a final outcome, when each field started being collected, and how the
platform's own rules shape what the data can tell you. Missing any of these would
have made the model look better on paper and work worse in practice.