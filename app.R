# Library imports ---------------------------------
library(shiny)
library(shinyWidgets)

library(tidyverse)
library(datamods)
library(dplyr)
library(DT)
library(xgboost)
library(tidymodels)
library(modeltime)
library(lubridate)
library(timetk)
library(gridExtra)
library(parsnip)
library(tsfeatures)

library(ggplot2)
library(plotly)

options(shiny.maxRequestSize=50*1024^2) 


ui <- fluidPage(
  titlePanel("Revenue Forecasting Toolkit"),
  sidebarLayout(
    sidebarPanel(
      fileInput("file", "Choose CSV File",
                accept = c(".csv"), 
                placeholder = "salesforce_export.csv"
      ),
      
    actionButton("update", "Update View", class = "btn-success"),
    
    selectizeInput('id_field', 'ID field', choices = NULL),
    selectizeInput('amount_field', 'Amount field', choices = NULL),
    selectizeInput('createddate_field', 'CreatedDate field', choices = NULL),
    selectizeInput('closedate_field', 'CloseDate field', choices = NULL),
    selectizeInput('isclosed_field', 'IsClosed field', choices = NULL),
    selectizeInput('iswon_field', 'IsWon field', choices = NULL),
    selectizeInput('other_field', 'Other helpful fields', choices = NULL, multiple = TRUE)
    )
    ,

# Main panel definition ---------------------------------
    
    mainPanel(
      tabsetPanel(type="tabs",
                  ### Data Load panel
                  {tabPanel("Data Load", 
                           headerPanel(""),                           
                           dateRangeInput('closedateRange',
                                          label = 'Date range input: yyyy-mm-dd',
                                          start = Sys.Date() - (3*365), 
                                          end = Sys.Date()
                                          ),
                           DT::DTOutput("table"),
                           br(),
                           textOutput("filter_res"),
                           plotlyOutput("opptys_plotly") 
                           )},
                  ### Time-Series panel
                  {tabPanel("Time-Series",
                           headerPanel(""),
                           actionButton("tscreate", "Create", class = "btn-success"),
                           br(),
                           br(),
                           DT::DTOutput("table_ts"),
                           dateInput("train_test_splitdate", 
                                     label = h4("Train/Test Split@date"), 
                                     value = Sys.Date() - 365),
                           plotlyOutput("ts_plotly", height="300px"),
                           DT::DTOutput("table_ts_features")
                  )},
                  ### Fit models panel                  
                  {tabPanel("Model",
                           headerPanel(""),
                           actionButton("fitmodel", "Fit Models", class = "btn-success"),
                           br(),
                           br(),
                           textOutput("params_all"),
                           h4("Weekly fit metrics"),
                           DT::DTOutput("table_ts_fit_metrics"), 
                           plotlyOutput("ts_metrics_plotly", height="300px"),
#                           DT::DTOutput("table_ts_fit_details"),
                           h4("Quarterly fit metrics"),
                           #DT::DTOutput("table_quarterly_revenue")
                           plotlyOutput("ts_quarterly_metrics_plotly", height="300px")
                  )},
                  ### Run forecast panel
                  {tabPanel("Forecast",
                           headerPanel(""),
                           selectizeInput('model_select',
                                          'Select one model to generate forecast',
                                          choices = NULL
                                       ),
                           actionButton("forecast_run", "Forecast", class = "btn-success"),
                  )}
      )
    )
)
)

# Server functions ---------------------------------
server <- function(input, output, session) {
  
  # Read the uploaded file as a data frame
  data <- eventReactive(input$update, {
    file <- input$file
    if(is.null(file)) {
      return(NULL)
    }
    read.csv(file$datapath, header = TRUE)
  })
  
  ### Observe field map selections in Data Load panel
  {
  observeEvent(input$update,{
    updateSelectizeInput(session, 'id_field', selected = 'Id', choices = colnames(data()))
  })
  observeEvent(input$update,{
    updateSelectizeInput(session, 'amount_field', selected = 'Amount', choices = colnames(data()))
  })
  observeEvent(input$update,{
    updateSelectizeInput(session, 'createddate_field', selected = 'CreatedDate', choices = colnames(data()))
  })
  observeEvent(input$update,{
    updateSelectizeInput(session, 'closedate_field', selected = 'CloseDate', choices = colnames(data()))
  })
  observeEvent(input$update,{
    updateSelectizeInput(session, 'isclosed_field', selected = 'IsClosed', choices = colnames(data()))
  })
  observeEvent(input$update,{
    updateSelectizeInput(session, 'iswon_field', selected = 'IsWon', choices = colnames(data()))
  })
  observeEvent(input$update,{
    updateSelectizeInput(session, 'other_field', choices = colnames(data()))
  })
  }
  
  # filter_isclosed <- renderPrint(sapply(input$table_state$columns, function(x) x$search$search, simplify = FALSE)[6])  
  # filter_iswon <- renderPrint(sapply(input$table_state$columns, function(x) x$search$search, simplify = FALSE)[7])
  # 
  # output$filter_res <- reactive({
  #   filter_isclosed()
  # })
  
  ### define filteredData dataframe
  filteredData <- reactive({
    data() %>% dplyr::select(input$id_field,
                      input$amount_field,
                      input$createddate_field,
                      input$closedate_field,
                      input$isclosed_field,
                      input$iswon_field,
                      input$other_field) %>%
        filter(.data[[input$isclosed_field]] == 'True') %>%
        filter(.data[[input$iswon_field]] == 'True') %>%
        arrange(.data[[input$closedate_field]]) %>%
        filter(.data[[input$closedate_field]] >= as.Date(as.character(input$closedateRange[1]))) %>%
        filter(.data[[input$closedate_field]] <= as.Date(as.character(input$closedateRange[2]))) #%>%
        #mutate(across(c(input$other_field), factor))
        }
    )
    
  ### render output for filteredData datatable and scatterplot
  {output$table <- DT::renderDT(filteredData(), 
                               filter="top",
                               options = list(stateSave = TRUE))   ## permits saving state of filters for later use
  
  output$opptys_plotly <- renderPlotly({
    d <- filteredData()
    plot_ly(d,
            x = ~.data[[input$closedate_field]],
            y = ~.data[[input$amount_field]],
            type='scatter',
            mode='markers',
            alpha=0.4) %>% 
      layout(title = "Opportunity level revenue by Close Date",
             xaxis = list(title = 'Date'),
             yaxis = list(title = 'Revenue ($\'s)')
      )
  })
  }

  ### define WEEKLY TIME SERIES (weekly_filteredData_ts) dataframe of weekly revenue
  weekly_filteredData_ts <- eventReactive(input$tscreate, {
    filteredData() %>% 
      dplyr::select(input$closedate_field, input$amount_field) %>%
      mutate(week = as.Date(.data[[input$closedate_field]], "%Y-%m-%d")) %>%
      dplyr::group_by(week_map = cut(week, "week", start.on.monday=FALSE)) %>% 
      dplyr::mutate(week_map = as.Date(week_map,"%Y-%m-%d")) %>%
      dplyr::select(week_map,input$amount_field) %>% 
      group_by(week_map) %>% 
      summarise(revenue = sum(.data[[input$amount_field]], na.rm=TRUE)) 
    }
  )
  
  ### render output for weekly time-series data-table and scatterplot
  output$table_ts <- DT::renderDT(weekly_filteredData_ts(), 
                                  options=list(lengthMenu=c(5,10,20),
                                               pageLength=5
                                               )
                                  )
  
  
  ### create TRAIN and TEST datasets, split at the provided train_test_splitdate
  train <- eventReactive(paste(input$train_test_splitdate,
                               input$tscreate),
                         {
    weekly_filteredData_ts() %>%
      filter(week_map < as.Date(input$train_test_splitdate,"%Y-%m-%d"))
    }
  )

  test <- eventReactive(paste(input$train_test_splitdate,
                        input$tscreate),
                        {
    weekly_filteredData_ts() %>%
      filter(week_map >= as.Date(input$train_test_splitdate,"%Y-%m-%d"))
    }
  )

  output$ts_plotly <- renderPlotly({
    d <- train() 
    fig <- plot_ly(d,
            x = ~week_map,
            y = ~revenue,
            type='scatter',
            mode='lines+markers', 
            color = I("blue"),
            alpha=0.4) %>% 
      layout(title = "Opportunity Revenue by Week",
             xaxis = list(title = 'Date'),
             yaxis = list(title = 'Revenue ($\'s)')
      )
    fig <- fig %>% add_trace(data = test(),
                             inherit = TRUE,
                             x = ~week_map,
                             y = ~revenue,
                             type = 'scatter',
                             mode='lines+markers',
                             color = I("green"),
                             alpha = 0.4) %>% 
                   add_lines(x = as.Date(as.character(input$train_test_splitdate)), color=I("green"))
    
    fig
    })
  

# Time series ts features ---------------------------------    
  ts_metrics <- function(ts) {
      metrics <- list()
      metrics <- append(metrics, round(tsfeatures::entropy(ts),2))
      metrics <- append(metrics, round(tsfeatures::stability(ts),2))
      metrics <- append(metrics, round(tsfeatures::lumpiness(ts),2))
      return(data.frame(metrics))
    }
  
  ts_metrics_obj <- eventReactive(input$tscreate, {
                                  ts_metrics(weekly_filteredData_ts()$revenue)
                                    }
                                 )
  
  output$table_ts_features <- DT::renderDT(ts_metrics_obj(), options = list(dom = 't'))
  
  
# Model fit functions/definitions ---------------------------------

  ### Model_Fits function that accepts train and test  
  model_fits_detail <- function(train, test) {
    
    # Model: arima ----
      model_fit_arima_no_boost <- arima_reg() %>%
        set_engine(engine = "auto_arima") %>%
        fit(revenue ~ week_map, data = train)
    
    # Model: prophet ----
      model_fit_prophet <- prophet_reg(seasonality_yearly=TRUE, seasonality_weekly=TRUE) %>%
        set_engine(engine = "prophet") %>%
        fit(revenue ~ week_map, data = train)

      model_fit_lm <- linear_reg() %>%
        set_engine("lm") %>%
        fit(revenue ~ as.numeric(week_map) + 
              factor(month(week_map, label = TRUE), ordered = FALSE),
            data = train)
      
    set.seed(123)
    
    models_tbl <- modeltime_table(model_fit_arima_no_boost,
                                  model_fit_prophet,
                                  model_fit_lm) %>%
                    modeltime_calibrate(new_data=test)
    
    return(models_tbl)
    }
  
  model_fits_accuracy <- function(.mod_tbl){
    mfa <- .mod_tbl %>% 
      modeltime::modeltime_accuracy() %>%
      modeltime::table_modeltime_accuracy(.interactive = FALSE)
    
    return(mfa)
  }  
  
  fiscal_qtr_assign <- function(x, fs) {
    y <- as.factor(quarter(x, with_year=T, fiscal_start= fs))
    return(y)
  }
  
  model_fits_forecast <- function(.mod_tbl, train, test){
    mff <- .mod_tbl %>%
      modeltime::modeltime_forecast(
        new_data    = test,
        actual_data = rbind(train,test),
        conf_interval = .9
      ) %>%
      dplyr::mutate(.fiscal_quarter = fiscal_qtr_assign(.index, 1))
    
    return(mff)
    }

  models_fit_results <- eventReactive(input$fitmodel, {  
    model_fits_detail(train(), test()) 
  }
  )
  
  output$table_ts_fit_metrics <- DT::renderDT(data.frame(models_fit_results() %>% model_fits_accuracy()))
  
  data_model_fits_forecast <- eventReactive(input$fitmodel, {
    models_fit_results() %>% 
      model_fits_forecast(train(),test())
  })
  
  output$params_all <- eventReactive(input$fitmodel, {
    paste("Data range: ", 
          as.Date(as.character(input$closedateRange[1])),
          " to ",
          as.Date(as.character(input$closedateRange[2])),
          "Train | Test split date: ",
          as.Date(input$train_test_splitdate,"%Y-%m-%d"))
    }
  )
                                     
  output$table_ts_fit_details <- DT::renderDT(data.frame(data_model_fits_forecast()))
  
# Quarterly revenue aggregation (functions) ---------------------------------

  model_forecast_qtrly_accuracy <- function(.weekly_fcst){
    
    models <- .weekly_fcst %>% 
                filter(.model_desc != 'ACTUAL') %>%
                pull(.model_desc) %>%
                unique()
    
    quarters <- .weekly_fcst$'.fiscal_quarter' %>% unique()
    
    df_errors_all <- data.frame()
    
    for(q in quarters) {
      actual_rev = .weekly_fcst %>% 
        filter(.model_desc == 'ACTUAL' & .fiscal_quarter == q) %>%
        summarise(actual_revenue = sum(.value, na.rm=TRUE)) %>%
        pull(actual_revenue)
      
      for(m in models) {
        model_fcst_rev <- .weekly_fcst %>% 
          filter(.model_desc == m & .fiscal_quarter == q) %>%
          summarise(forecast_revenue = sum(.value, na.rm=TRUE)) %>%
          pull(forecast_revenue)
        
        df_error =data.frame('model'=m, 
                             'quarter'=q,
                             'forecast'= model_fcst_rev,
                             'actual'= actual_rev,
                             'pct_error' = ((model_fcst_rev / actual_rev) - 1)
                             )
        
        df_errors_all <- rbind(df_errors_all, df_error)
      }
    }
  
  return(df_errors_all %>% arrange('model','quarter'))
  }

# Quarterly revenue aggregation (outputs) ---------------------------------
  
  table_tsfit_quarterly_errors <- eventReactive(input$fitmodel, {
    data_model_fits_forecast() %>% 
      model_forecast_qtrly_accuracy() %>%
      filter(quarter %in% c("2022.2", "2022.3", "2022.4", "2023.1")) #%>%
      #mutate(pct_error = scales::percent(pct_error))
  })
  
  output$table_quarterly_revenue <- DT::renderDT(data.frame(table_tsfit_quarterly_errors()))

  plotly_quarterly_errors_obj <- eventReactive(input$fitmodel, {
    table_tsfit_quarterly_errors() %>%
    plot_ly(x = ~quarter, 
            y = ~pct_error, 
            type = 'scatter', 
            mode = 'markers+lines',
            color = ~model
            ) %>%
      layout(yaxis = list(tickformat = ".0%"))
    }
  )
  
  output$ts_quarterly_metrics_plotly <- renderPlotly({
    plotly_quarterly_errors_obj()
  }
  )
  
  # Model fit plots ---------------------------------
  model_plots <- function(.mod_tbl, test) {
    set.seed(123)
    
    fit_plot <- .mod_tbl %>%
      plot_modeltime_forecast(
        .conf_interval_show=TRUE, 
        .interactive = TRUE,
        .title = 'Fiscal Year Forecasts'
        ) 
    return(fit_plot)
  }  

  plotly_obj <- eventReactive(input$fitmodel, {
    models_fit_results() %>% 
      model_fits_forecast(train(), test()) %>%
      model_plots()
  })

  output$ts_metrics_plotly <- renderPlotly({
    plotly_obj()
    }
  )
  
  model_choices <- eventReactive(input$fitmodel, {
    data_model_fits_forecast() %>%
      select(.model_desc) %>% 
      filter(.model_desc != 'ACTUAL') %>%
      unique()
  })
  
  observeEvent(input$fitmodel,{
    updateSelectizeInput(session, 'model_select', choices = model_choices())
  })

  observeEvent(input$forecast_run,{
    print('Breakpoint')
  })
  
}
    
if (interactive())
  shinyApp(ui, server)