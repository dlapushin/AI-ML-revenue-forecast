# AI-ML-revenue-forecast
A framework for using standard Salesforce reports and data to help drive a state-of-the-art ML-based revenue forecasting model that can provide meaningful forecasts over multiple quarters. All that's needed is a Salesforce report and either R or Python.  An overview of the process is shown below and full details are discussed in a 3 part series of articles on Medium. [Medium article](https://medium.com/@dlapushin/open-source-b2b-sales-forecasting-c1cd7bc9b2a8)

![Forecast Loop](https://github.com/dlapushin/AI-ML-revenue-forecast/blob/main/sales_forecast_process.png)

## Step 1: Use Salesforce (or other CRM) to download opportunity data

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

## Step 2: Data Preparation
There are a 3 data transformations needed at this point. R makes this quite straightforward and the code is provided below as well.

**Transformation #1**: Create a weekly time series from the ingested opportunity level data. We choose weekly because using 2 to 3 years of historical quarterly revenue levels would yield at most a dozen observations — not nearly enough data for a meaningful model. By the same token, trying to model daily sales levels would introduce substantial noise. A happy medium is to create a weekly time-series which is what we’ll use throughout these discussions.

**Transformation #2**: Tag each opportunity with an appropriate fiscal quarter based on the fiscal calendar and the opportunity’s CloseDate. This will allow us to more easily train and validate the model. We’ll assume each fiscal week starts on Sunday with any revenue from the subsequent business days assigned to that week .

**Transformation #3**: Split the data into training and testing components. A reasonable rule of thumb is to use the first 65%-80% of the revenue history for model training, and leave the rest for testing/validation. For example, with a 3 year opportunity history, the first 2 would be used for training and the most recent used for testing/validation.

The R code assumes you have the opportunity file in R’s working directory, and is named “my opportunities.csv”. You can simply make a copy of this function — oppty_file_transform() — and run it in R by providing the 4 required parameters.
For example, *oppty_file_transform(“my_opportunities.csv”, “ARR_Amount__c”, 1, test_data_start_date = “2022–01–01”)*

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





