# AI-ML-revenue-forecast

## Summary
A framework for using standard Salesforce reports and data to help drive a state-of-the-art ML-based revenue forecasting model that can provide meaningful forecasts over multiple fiscal quarters. All that's needed is a Salesforce report and either R or Python.  An overview of the process is shown below and full details are discussed in a 3 part series of articles on Medium. [Medium article](https://medium.com/@dlapushin/open-source-b2b-sales-forecasting-c1cd7bc9b2a8)

## Environment Setup
By far the easiest way to follow this tutorial and try out the code is to pull the Github repo into RStudio using the following steps.
1. Create a new project under File menu:

![step1](https://github.com/dlapushin/AI-ML-revenue-forecast/blob/main/pic1/step1.png)

2. Choose to create using Version Control:

![step2](https://github.com/dlapushin/AI-ML-revenue-forecast/blob/main/pic1/step2.png)

3. Select Git:

![step3](https://github.com/dlapushin/AI-ML-revenue-forecast/blob/main/pic1/step3.png)

4. Enter https://github.com/dlapushin/AI-ML-revenue-forecast/ in the Repository URL and leave the rest as is.  Click 'Create Project'.

![step4](https://github.com/dlapushin/AI-ML-revenue-forecast/blob/main/pic1/step4.png)

5. The code files should load at this point and you will see a copy of the repo folder in RStudio.  The folder **R_code** will contain file with all needed R functions.

![step5](https://github.com/dlapushin/AI-ML-revenue-forecast/blob/main/pic1/step5.png)


## Overview of Process and Process Steps

![Forecast Loop](https://github.com/dlapushin/AI-ML-revenue-forecast/blob/main/sales_forecast_process.png)

Each of the numbered steps is explained and detailed below.

### Step 1: Use Salesforce (or other CRM) to download opportunity data

The data for training the forecast model can be downloaded from Salesforce simply by creating an Opportunity level report for the past 2–3 years at a minimum. The key fields to include in the report would be:

**Opportunity ID**
* an alpha-numeric code unique to every opportunity

**CreateDate**
* the date on which the opportunity was created in the CRM (used for reference initially but potentially a model feature as well)

**ACV, ARR, or Amount (in base currency e.g. $US)** 
* the annualized contact value (ACV) of the sale; for multi-year licenses, this would be a per-annum amount

**CloseDate**
* (YYYY-MM-DD) the calendar date on which the opportunity was closed

**IsClosed**
* (True/False) a flag field indicating that an opportunity was in fact closed and no longer being actively worked on by Sales

**IsWon**
* (True/False) a flag field indicating that an opportunity was in fact won and a sale was made; should only be True if ‘IsClosed’ = True

Export this data as a .csv file (e.g. my_opportunities.csv)

### Step 2: Data Preparation
There are a 3 data transformations needed at this point, all are included in the R code file - **oppty_file_transform.R** - which you can load directly by running the below command in the RStudio console: 

> source("~/AI-ML-revenue-forecast/R_code/oppty_file_transform.R", echo=TRUE)

**Transformation #1**: Create a weekly time series from the ingested opportunity level data. We choose weekly because using 2 to 3 years of historical quarterly revenue levels would yield at most a dozen observations — not nearly enough data for a meaningful model. By the same token, trying to model daily sales levels would introduce substantial noise. A happy medium is to create a weekly time-series which is what we’ll use throughout these discussions.

**Transformation #2**: Tag each opportunity with an appropriate fiscal quarter based on the fiscal calendar and the opportunity’s CloseDate. This will allow us to more easily train and validate the model. We’ll assume each fiscal week starts on Sunday with any revenue from the subsequent business days assigned to that week .

**Transformation #3**: Split the data into training and testing components. A reasonable rule of thumb is to use the first 65%-80% of the revenue history for model training, and leave the rest for testing/validation. For example, with a 3 year opportunity history, the first 2 would be used for training and the most recent used for testing/validation.

The R code assumes you have the opportunity .csv file in R’s working directory. You can then apply this function to your opportunity export file, e.g. my_opportunities.csv, for example, 

> oppty_file_transform(“my_opportunities.csv”, “ARR_Amount__c”, 1, test_data_start_date = “2022–01–01”)

where:

* filename (e.g. “my_opportunities.csv”)
* name of the amount field (e.g. “ARR_Amount__c”)
* the number of the month starting the fiscal year (e.g. “1” for Jan, “2” for Feb, etc.)
* the calendar date that marks beginning of test data (e.g. “2022–01–01”)

Running this function successfully will create 3 dataframes and 1 plot: 
* df_revenue_ts
* train
* test 
* a chart tsplot_train_test showing the weekly series broken out by train and test

Because they’re created inside the R function using global scope definition(<<-), they can all be viewed after calling the oppty_file_transform() function.

### Step 3: Data diagnostics / Model evaluation

> A quick sidebar — time series can sometimes behave so erratically that they are not amenable to prediction, at least on their own. As mentioned, there are some simple metrics we can run as a “pre-flight check”. This provides an early indication of whether an accurate statistical forecast model is even possible.

Three of these metrics are the *entropy, stability, and lumpiness scores* which help measure the stationarity of a series. This simply refers to whether the time-series appear to follow a consistent distribution, i.e. with a stable average and stable range of variation around the average. So these metrics give an indication of how predictable the revenue series is, before we even start model testing. 

For example, if historical revenue shows high entropy and low stability, we should expect that 1) simple forecast models based just on this history will most likely be inaccurate, and 2) we should consider testing and tuning deep-learning style models or adding other appropriate variables that may contribute some predictive power (say, a leading indicator of revenue such as Marketing pipeline).

1. Fit a range of candidate models to the train data:

- ARIMA
- Exponential Smoothed (ETS)
- Linear with Time Features
- Prophet

2. For each fitted model, create a forecast for the test data period. We can use the modeltime_forecast function to do this and aggregate the resulting forecast levels into quarterly groupings.

3. Similarly, aggregate the test data into quarterly totals (e.g. Q1, Q2, Q3, and Q4 ) by grouping on the fiscal_quarter field.

4. For each model, we measure the difference between the forecasted quarterly revenue (#2 above) vs. actual quarterly revenue (#3 above) and record their percent difference by quarter.

5. Comparing an average absolute error calculation for each model tells us which model offered the best overall quarterly predictions. Decide which model is optimal based on these metrics.


