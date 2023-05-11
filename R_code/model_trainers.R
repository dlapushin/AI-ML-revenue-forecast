### Load libraries

library(modeltime)
library(tidyverse)
library(xgboost)
library(tidymodels)
library(lubridate)
library(timetk)
library(ggplot2)
library(parsnip)
library(tsfeatures)

### Time series diagnostics
## function to combine 3 features (entropy, stability, and lumpiness) into one list
ts_metrics <- function(ts) {
  metrics <- list()
  metrics <- append(metrics, tsfeatures::entropy(ts))
  metrics <- append(metrics, tsfeatures::stability(ts))
  metrics <- append(metrics, tsfeatures::lumpiness(ts))
  return(metrics)
}

ts_metrics(df_revenue_ts$revenue) 

actuals <- rbind(train, test)

### Train 5 standard modeltime models on time-series dataframe "train"
### Display chart of forecast vs. test

# Model 1: auto_arima ----
model_fit_arima_no_boost <- arima_reg() %>%
  set_engine(engine = "auto_arima") %>%
  fit(revenue ~ week, data = train)

# Model 2: arima_boost ----
model_fit_arima_boosted <- arima_boost(
  min_n = 2,
  learn_rate = 0.015
) %>%
  set_engine(engine = "auto_arima_xgboost") %>%
  fit(revenue ~ week + as.numeric(week) + factor(month(week, label=TRUE), 
      ordered=F), 
  data = train)

# Model 3: ets ----
model_fit_ets <- exp_smoothing() %>%
  set_engine(engine = "ets") %>%
  fit(revenue ~ week, data = train)
#> frequency = 12 observations per 1 year

# Model 4: prophet ----
model_fit_prophet <- prophet_reg(seasonality_yearly=TRUE, seasonality_weekly=TRUE) %>%
  set_engine(engine = "prophet") %>%
  fit(revenue ~ week, data = train)

# Model 5: lm ----
model_fit_lm <- linear_reg() %>%
  set_engine("lm") %>%
  fit(revenue ~ as.numeric(week) + factor(month(week, label = TRUE), ordered = FALSE),
      data = train)

#### Test fitted models to time-series dataframe "test"

set.seed(123)
models_tbl <- modeltime_table(
  model_fit_arima_no_boost,
  model_fit_arima_boosted,
  model_fit_ets,
  model_fit_prophet,
  model_fit_lm
)

calibration_tbl <- models_tbl %>%
  modeltime_calibrate(new_data = test)

calibration_tbl %>%
modeltime_accuracy() %>%
table_modeltime_accuracy(.interactive = FALSE) 

calibration_tbl %>%
  modeltime_forecast(
    new_data    = test,
    actual_data = actuals,
    conf_interval = .9  # display a 90% confidence band around each forecast
  ) %>% 
  mutate(.conf_lo = ifelse(.conf_lo < 0, 0, .conf_lo)) %>%  # this is purely to avoid a confidence range that dips below zero 
  plot_modeltime_forecast(
    .conf_interval_show=TRUE, 
    .interactive = TRUE,
    .title = 'Fiscal Year Forecasts'
  ) -> forecast_vs_test_chart

forecast_vs_test_chart
