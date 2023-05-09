library(tidyverse)
library(lubridate)
library(ggplot2)

oppty_file_transform <- function(oppty_file, amount_field, fiscal_start_month, test_data_start_date) {
  
  ### Transformation 1
  # Load opportunity-level data file - e.g. 'my_opportunities.csv'
  
  df_oppty <- read_csv(oppty_file)
  
  # Create time series by filtering Closed-Won opptys (i.e. revenue only) and aggregate by week

  df_revenue_ts <<- df_oppty %>%   #start with opportunity data per above
    filter(IsClosed == TRUE) %>%   #filters on Closed opptys
    filter(IsWon == TRUE) %>%   #filters on Won opptys
    arrange(CloseDate) %>%   #sort by CloseDate
    select(CloseDate, amount_field) %>%    #pull only data needed (CloseDate and ACV__c)
    group_by(week = cut(CloseDate,   #aggregate by week starting on Sunday
                        "week",
                        start.on.monday = FALSE)) %>%
    mutate(week = as.Date(week, "%Y-%m-%d")) %>%    #ensure "week" expressed as date
    summarise(revenue = sum(get(amount_field), na.rm=TRUE))   #set revenue to sum of ACV__c
  
  ### Transformation 2
  # R function that maps a calendar date to the appropriate fiscal quarter.
  # Function accepts a date "d" and the month number "fs" which starts the fiscal year.
  # (e.g. fiscal years starting Feb-1 would use a fiscal_start = 2)

  fiscal_qtr_assign <- function(d, fs) {
    y <- as.factor(quarter(d, with_year=T, fiscal_start= fs))
    return(y)
  }

  # Assign each week to the appropriate fiscal quarter.
  # The variable fiscal_start_month is the month number starting the fiscal year
  # (e.g. fiscal years starting Feb-1 would use a fiscal_start = 2)

  df_revenue_ts <- df_revenue_ts %>%
    mutate(fiscal_quarter = fiscal_qtr_assign(week, fiscal_start_month))

  ### Transformation 3
  # Split data into training and testing based on provided cutoff date (test_data_start_date)
  
  train <<- df_revenue_ts %>%
    filter(week < test_data_start_date)

  test <<- df_revenue_ts %>%
    filter(week >= test_data_start_date)

  tsplot_train_test <<- ggplot(data=train, aes(week,revenue)) + 
  geom_line(aes(color='Training')) +
  geom_line(data=test, aes(color='Testing')) +
  scale_y_continuous(labels=scales::dollar_format()) +
  ggtitle('Weekly revenue in $mm', subtitle = 'Train and Test') + labs(color="Data split") +
  guides(color = guide_legend(reverse = TRUE))
  }
  
