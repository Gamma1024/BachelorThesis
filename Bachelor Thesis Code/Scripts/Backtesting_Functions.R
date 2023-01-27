#==========================================================================#
########################## Backtesting Functions  ##########################
#==========================================================================#

# !!!!! Important Note !!!!! #
# The code for the Conditional Predictive Ability Test by Giacomini and White
# (2006) is based on the Matlab code provided by the authors and was only
# translated to R by me. The Matlab code can be found here:
# http://www.runmycode.org/companion/view/88
# I compared my implementation with theirs for a few different pairs of VaR 
# losses and got the same results

#------------------------------------#
########### Importing Data ###########
#------------------------------------#

## Portfolio Plrets
stocks_plret_df <- read.csv("./Data/StockPlrets.csv", header = TRUE)
portfolio_plret_df <- read.csv("./Data/PortfolioPlrets.csv", header = TRUE)


## Don't run when importing
if (sys.nframe() == 0) {
  ## VaR
  # Univariate:
  Uni_Normal_GARCH_VaR <- read.csv("./Data/VaR/Uni_Normal_GARCH_VaR.csv", 
                                   header = TRUE)
  Uni_EWMA_VaR <- read.csv("./Data/VaR/Uni_EWMA_VaR.csv", 
                           header = TRUE)
  Uni_t_GJR_GARCH_VaR <- read.csv("./Data/VaR/Uni_t_GJR_GARCH.csv", 
                                  header = TRUE)
  Uni_Skewt_GJR_GARCH_VaR <- read.csv("./Data/VaR/Uni_Skewt_GJR_GARCH.csv", 
                                      header = TRUE)
  Uni_Skewt_NGARCH_VaR <- read.csv("./Data/VaR/Uni_Skewt_NGARCH.csv", 
                                   header = TRUE)
  
  # Multivariate
  Multi_DCC_GARCH_VaR <- read.csv("./Data/VaR/Multi_DCC_GARCH.csv",
                                  header = TRUE)
  
  Multi_Fortin_Normal_VaR <- read.csv("./Data/VaR/Multi_cop_norm_VaR.csv", 
                                      header = TRUE)
  
  
  Multi_Fortin_t_VaR <- read.csv("./Data/VaR/Multi_cop_t_VaR.csv", header = TRUE)
}



#--------------------------------------------------#
########### VaR Exceedence Plot Function ###########
#--------------------------------------------------#
# before the more formal tests it is always a good idea to first have a look at 
# a graphical representation


# load lubridate for year() function to extract year from Date
if (!require(lubridate)) install.packages("lubridate")
if (!require(tidyverse)) install.packages("tidyverse")

#' VaR Exceedence Plot
#' 
#' Plots returns and line of VaR and marks every point where the return is 
#' below the VaR line as an exceedence and displays how many exceedences there 
#' are in each year
#' 
#' @param dataframe dataframe with VaR
#' @param VaR_in_col_nr integer indicating in which column of dataframe the VaR
#'  is
#' @param pf_plrets dataframe of portfolio percentage returns
#' @param alpha VaR level in percent w/o percentage sign
#' @param modelname Name of model as character
#' 
#' @return Exceedences plot which highlights exceedances and
#'  displays number of exceedances per year
VaR_exceed_plot <- function(dataframe, VaR_in_col_nr, pf_plrets, alpha, 
                            modelname){
  VaR_df <- data.frame(Date = as.Date(dataframe[,1]),
      VaR = dataframe[,VaR_in_col_nr],
      Exceedance = as.factor(pf_plrets[-c(1:1000),2]<dataframe[,VaR_in_col_nr])
    )
  exceedances_per_year  <- VaR_df %>% 
    mutate(year = year(Date)) %>% 
    select(Exceedance, year) %>% 
    count(year, Exceedance) %>% 
    mutate(n = ifelse(Exceedance==TRUE, n, 0)) %>% 
    select(-Exceedance) %>% 
    group_by(year) %>% 
    summarise(n = sum(n))
  
  ggplot(VaR_df, aes(x = Date, y = VaR))+
    geom_point(aes(x = Date, y = pf_plrets[-c(1:1000), 2], 
                   color = Exceedance, shape = Exceedance), size =1.5, 
               alpha = 2)+
    scale_shape_manual(values = c(20, 4), name="",
                       labels = c("Lower than VaR", "Greater than VaR"))+
    scale_color_manual(values = c("gray", "red"), name = "", 
                       labels = c("Lower than VaR", "Greater than VaR"))+
    geom_line(alpha = 0.7)+
    labs(y = "Daily Portfolio Returns", x = "Date", 
         title = paste0(alpha, "% VaR Exceedances Plot for ",modelname))+
    theme_light()+
    theme(legend.position = c(.15, .8), 
          legend.background = element_rect(color = NA), 
          legend.key = element_rect(color = "transparent"))+
    annotate("text", x = as.Date("2005-01-15"), y = -7, size = 3, hjust = 0,
             label = paste("Number of Exceedances per Year:", "\n2004:", 
                           exceedances_per_year$n[1], "\n2005:", 
                           exceedances_per_year$n[2],
                           "\n2006:", exceedances_per_year$n[3], 
                           "\n2007:", exceedances_per_year$n[4]))+
    annotate("text", x = as.Date("2005-10-15"), y = -7, size = 3, hjust = 0,
             label = paste(" ","\n2008:", exceedances_per_year$n[5],"\n2009:", 
                           exceedances_per_year$n[6],
                           "\n2010:", exceedances_per_year$n[7], "\n2011:", 
                           exceedances_per_year$n[8]))
}

## Don't run when importing
if (sys.nframe() == 0) {
  VaR_exceed_plot(Uni_Normal_GARCH_VaR, 3, portfolio_plret_df, alpha = 5,
                  "Uni_Normal_GARCH")
  VaR_exceed_plot(Uni_Normal_GARCH_VaR, 2, portfolio_plret_df, alpha = 1, 
                  "Uni_Normal_GARCH")
}


#-----------------------------------------------------------------------------#
###### Tests for Independence and Conditional and Unconditional Coverage ######
#-----------------------------------------------------------------------------#

## Load rugarch to compare tests to tests implemented in rugarch
if (!require(rugarch)) install.packages("rugarch")

#' Test of unconditional coverage
#'
#' @param p VaR percentile e.g. 1%
#' @param VaR VaR forecasts of a model (only the column with p% VaR values)
#' @param plrets portfolio returns dataframe with dates in first column& returns
#'in second column
#'
#' @return test statistic of likelihood ratio test of unconditional coverage
LR_uc <- function(p, VaR, plrets = portfolio_plret_df[-c(1:1000),2]){
  indicator <- ifelse(plrets-VaR<0, 1, 0)
  n1 <- sum(indicator)
  n0 <- length(VaR) - n1
  
  lik_p <- (1 - p)^n0 * p^n1
  
  pi_mle <- n1 / (n0 + n1)
  lik_pi_mle <- (1 - pi_mle)^n0 * pi_mle^n1
  
  LR <- -2 * log(lik_p / lik_pi_mle)
  return(LR)
}

## Don't run when importing
if (sys.nframe() == 0) {
  uc1 <- LR_uc(0.01, Uni_t_GJR_GARCH_VaR[,2])
  ugarch_uc1 <- VaRTest(alpha = 0.01, portfolio_plret_df[-c(1:1000),2], 
                        Uni_t_GJR_GARCH_VaR[,2], conf.level = 0.95)$uc.LRstat
  uc1==ugarch_uc1
  
  
  uc2 <- LR_uc(0.05, Uni_Normal_GARCH_VaR[,3])
  ugarch_uc2 <- VaRTest(alpha = 0.05, portfolio_plret_df[-c(1:1000),2], 
                        Uni_Normal_GARCH_VaR[,3], conf.level = 0.95)$uc.LRstat
  uc2==ugarch_uc2
  # get same value as rugarch implementation
}



#' Test of independence
#'
#' @param p VaR percentile e.g. 1%
#' @param VaR VaR forecasts of a model (only the column with p% VaR values)
#' @param plrets portfolio returns dataframe with dates in first column& returns
#'in second column
#'
#' @return test statistic of likelihood ratio test of independence
LR_ind <- function(p, VaR, plrets = portfolio_plret_df[-c(1:1000),2]){
  indicator <- as.numeric(ifelse(plrets-VaR<0, 1, 0))
  tab <- table(indicator[-length(indicator)], indicator[-1])
  n00 <- tab[1,1]
  n01 <- tab[1,2]
  n10 <- tab[2,1]
  n11 <- tab[2,2]
  
  pi_MLE_01 <- n01/(n00+n01)
  pi_MLE_11 <- n11/(n10+n11)
  lik_Pi1_MLE <- (1 - pi_MLE_01)^n00 * pi_MLE_01^n01 * 
    (1 - pi_MLE_11)^n10 * pi_MLE_11^n11
  
  pi2_MLE <- (n01 + n11) / sum(tab)
  lik_Pi2_MLE <- (1 - pi2_MLE)^(n00 + n10) * pi2_MLE^(n01 + n11)
  
  LR <- -2 * log(lik_Pi2_MLE / lik_Pi1_MLE)
  return(LR)
}


#' Test of conditional coverage
#'
#' As in rugarch, the cc test statistic is for numerical reasons calculated as
#' the sum of ind& uc test statistics.
#'
#' @param p VaR percentile e.g. 1%
#' @param VaR VaR forecasts of a model (only the column with p% VaR values)
#' @param plrets portfolio returns dataframe with dates in first column& returns
#'in second column
#'
#' @return test statistic of likelihood ratio test of coonditional coverage
LR_cc <- function(p, VaR, plrets = portfolio_plret_df[-c(1:1000),2]){
  uc <- LR_uc(p, VaR)
  ind <- LR_ind(p, VaR)
  LR <- uc + ind
  return(LR)
}

## Don't run when importing
if (sys.nframe() == 0) {
  cc1 <- LR_cc(0.01, Uni_t_GJR_GARCH_VaR[, 2])
  cc1==VaRTest(alpha = 0.01, portfolio_plret_df[-c(1:1000),2], 
               Uni_t_GJR_GARCH_VaR[,2], conf.level = 0.95)$cc.LRstat
  
  cc2 <- LR_cc(0.05, Uni_Normal_GARCH_VaR[, 3])
  cc2==VaRTest(alpha = 0.05, portfolio_plret_df[-c(1:1000),2], 
               Uni_Normal_GARCH_VaR[,3], conf.level = 0.95)$cc.LRstat
}


# get same value as rugarch implementation


## Create class to return separate list for each test
setClass(Class="LR_tests",
         representation(
           cc  = "list",
           ind = "list",
           uc  = "list"
         )
)


#' Test of unconditional coverage
#'
#' Implements backtesting as described in Christoffersen (1998) i.e. implements
#' the LR test of unconditional coverage, the LR test of independence and the LR
#' test of conditional coverage.
#'
#' @param p VaR percentile e.g. 1%
#' @param VaR VaR forecasts of a model (only the column with p% VaR values)
#' @param plrets portfolio returns dataframe with dates in first column& returns
#'in second column
#' @param conf_level the confidence level of the test
#'
#' @return returns instance of class "LR_tests" i.e. a list for each of the three
#' tests that includes the critical value, the test statistic, the p-value and
#' the decision i.e. reject or not
VaR_LR_tests <- function(p, VaR, plrets = portfolio_plret_df[-c(1:1000),2],
                         conf_level = 0.95){
  LR_uc <- LR_uc(p, VaR)
  LR_ind <- LR_ind(p, VaR)
  LR_cc <- LR_cc(p, VaR)
  
  crit_val_uc <- crit_val_ind <- qchisq(conf_level, df = 1)
  crit_val_cc <- qchisq(conf_level, df = 2)
  
  p_val_uc <- 1 - pchisq(LR_uc, df = 1)
  p_val_ind <- 1 - pchisq(LR_ind, df = 1)
  p_val_cc <- 1 - pchisq(LR_cc, df = 2)
  
  reject_uc <- ifelse(p_val_uc < 1 - conf_level, TRUE, FALSE)
  reject_ind <- ifelse(p_val_ind < 1 - conf_level, TRUE, FALSE)
  reject_cc <- ifelse(p_val_cc < 1 - conf_level, TRUE, FALSE)
  
  return(new("LR_tests",
             cc  = list(crit_val_cc = crit_val_cc, LR_cc = LR_cc, 
                        p_val_cc = p_val_cc, reject_cc = reject_cc),
             ind = list(crit_val_ind = crit_val_ind, LR_ind = LR_ind,
                        p_val_ind = p_val_ind, reject_ind = reject_ind),
             uc  = list(crit_val_uc = crit_val_uc, LR_uc = LR_uc,
                        p_val_uc = p_val_uc, reject_uc = reject_uc)))
}

## Don't run when importing
if (sys.nframe() == 0) {
  VaR_LR_tests(0.01, Uni_Normal_GARCH_VaR[, 2])
}


#----------------------------------------------------------------#
########### Calculate Exceedances and Nominal Coverage ###########
#----------------------------------------------------------------#

#' Empirical Coverage
#' 
#' Calculates and returns the nominal coverage
#'
#' @param VaR Value at risk forecasts of a model
#' @param plrets portfolio returns dataframe with dates in first column& returns
#' in second column
#'
#' @return nominal coverage
empirical_coverage <- function(VaR, plrets = portfolio_plret_df[-c(1:1000),2]){
  indicator <- ifelse(plrets-VaR<0, 1, 0)
  coverage <- sum(indicator)/length(VaR)
  return(empirical_coverage = coverage)
}

## Don't run when importing
if (sys.nframe() == 0) {
  empirical_coverage(Uni_Normal_GARCH_VaR[,2])
  empirical_coverage(Uni_t_GJR_GARCH_VaR[,2])
}


if (!require(tidyverse)) install.packages("tidyverse")
# lubridate to extract year from Date
if (!require(lubridate)) install.packages("lubridate")

#' Exceedances
#' 
#' Calculates and returns the total number of exceedances as well as the
#'  exceedances per year
#'
#' @param VaR Value at risk forecasts of a model
#' @param plrets portfolio returns dataframe with dates in first column& returns
#'in second column
#'
#' @return list with total number of exceedances and exceedences per year
exceedances <- function(VaR, plrets = portfolio_plret_df[-c(1:1000),]){
  indicator <- ifelse(plrets[,2]-VaR<0, 1, 0)
  indicator_df <- data.frame(Date = plrets[,1],
                             Exceedance = as.factor(indicator)
                             )
  exc_per_year  <- indicator_df %>% 
    mutate(year = year(Date)) %>% 
    select(Exceedance, year) %>% 
    count(year, Exceedance) %>% 
    mutate(n = ifelse(Exceedance==1, n, 0)) %>% 
    select(-Exceedance) %>% 
    group_by(year) %>% 
    summarise(n = sum(n))
  return(list(total_exc = sum(indicator), exc_per_year = exc_per_year))
}

## Don't run when importing
if (sys.nframe() == 0) {
  exceedances(Uni_Normal_GARCH_VaR[,2])
  exceedances(Uni_t_GJR_GARCH_VaR[,2])
}





#' Exceedances Table
#'
#' Create tables for the 1% VaR and the 5% VaR that consist of the total number
#' of exceedances and the exceedences per year 
#'
#' @param VaR_list list of VaR dataframes with date in first column, 1% VaR in
#' second column and 5% VaR in third column
#' @param plrets portfolio returns dataframe with dates in first column& returns
#'in second column
#'
#' @return list of exceedance tables for 1% VaR and 5% VaR
exceedances_table <- function(VaR_list, 
                              plrets = portfolio_plret_df[-c(1:1000),]){
  n <- length(VaR_list)
  matrix_99 <- matrix(0L, nrow = n, ncol = 9)
  for (i in 1:n){
    matrix_99[i, 1] <- unlist(exceedances(VaR_list[[i]][,2])$total_exc)
    matrix_99[i, 2:9] <- unlist(exceedances(VaR_list[[i]][,2])$exc_per_year[,2])
  }
  table_99 <- data.frame(matrix_99)
  colnames(table_99) <- c("Total_Exc", "2004", "2005", "2006", "2007",
                          "2008", "2009", "2010", "2011")
  rownames(table_99) <- names(VaR_list)
  
  matrix_95 <- matrix(0L, nrow = n, ncol = 9)
  for (i in 1:n){
    matrix_95[i, 1] <- unlist(exceedances(VaR_list[[i]][,3])$total_exc)
    matrix_95[i, 2:9] <- unlist(exceedances(VaR_list[[i]][,3])$exc_per_year[,2])
  }
  table_95 <- data.frame(matrix_95)
  colnames(table_95) <- c("Total_Exc", "2004", "2005", "2006", "2007",
                          "2008", "2009", "2010", "2011")
  rownames(table_95) <- names(VaR_list)
  
  return(list(table_99 = table_99, table_95 = table_95))
}

## Don't run when importing
if (sys.nframe() == 0) {
  test_VaR_list <- list(EWMA = Uni_EWMA_VaR, Normal_GARCH = Uni_Normal_GARCH_VaR,
                        t_GJR = Uni_t_GJR_GARCH_VaR, 
                        Skewt_GJR = Uni_Skewt_GJR_GARCH_VaR,
                        skewt_NGARCH = Uni_Skewt_NGARCH_VaR,
                        normal_DCC_GARCH = Multi_DCC_GARCH_VaR)
  exceedances_table(test_VaR_list)$table_99
  exceedances_table(test_VaR_list)$table_95
}


#---------------------------------------------------------------#
########### Table for Exceedances and LR Test Pvalues ###########
#---------------------------------------------------------------#

#' Performance table
#' 
#' Create a summary table for backtesting that includes nominal coverage,
#' exceedances (over the years) and LR tests of Christoffersen (1998). 
#'
#' @param VaR_list list of VaR dataframes with date in first column, 1% VaR in
#' second column and 5% VaR in third column
#' @param plrets portfolio returns dataframe with dates in first column& returns
#'in second column
#' @param conf_level confidence level for LR tests of Christoffersen (1998). By
#' default 95%
#'
#' @return list with performance table for 1% VaR and for 5% VaR
performance_table <- function(VaR_list, plrets = portfolio_plret_df[-c(1:1000),],
                              conf_level = 0.95){
  n <- length(VaR_list)
  coverage_99 <- matrix(0L, nrow = n, ncol = 1)
  tests_99 <- matrix(0L, nrow = n, ncol = 3)
  for (i in 1:n){
    coverage_99[i, 1] <- empirical_coverage(VaR_list[[i]][,2], plrets[,2])
    tests_99[i, 1] <- unlist(VaR_LR_tests(0.01, VaR_list[[i]][,2], 
                                          plrets[,2])@uc$p_val_uc)
    tests_99[i, 2] <- unlist(VaR_LR_tests(0.01, VaR_list[[i]][,2], 
                                          plrets[,2])@ind$p_val_ind)
    tests_99[i, 3] <- unlist(VaR_LR_tests(0.01, VaR_list[[i]][,2], 
                                          plrets[,2])@cc$p_val_cc)
  }
  exceed_99 <- exceedances_table(VaR_list, plrets)$table_99
  performance_table_99 <- data.frame(coverage_99, tests_99, exceed_99)
  colnames(performance_table_99) <- c("coverage_1%", "uc", "ind", "cc", 
                                      "Total_Exc", "2004", "2005", "2006", 
                                      "2007", "2008", "2009", "2010", "2011")
  rownames(performance_table_99) <- names(VaR_list)
  
  coverage_95 <- matrix(0L, nrow = n, ncol = 1)
  tests_95 <- matrix(0L, nrow = n, ncol = 3)
  for (i in 1:n){
    coverage_95[i, 1] <- empirical_coverage(VaR_list[[i]][,3], plrets[,2])
    tests_95[i, 1] <- unlist(VaR_LR_tests(0.05, VaR_list[[i]][,3], 
                                          plrets[,2])@uc$p_val_uc)
    tests_95[i, 2] <- unlist(VaR_LR_tests(0.05, VaR_list[[i]][,3],
                                          plrets[,2])@ind$p_val_ind)
    tests_95[i, 3] <- unlist(VaR_LR_tests(0.05, VaR_list[[i]][,3], 
                                          plrets[,2])@cc$p_val_cc)
  }
  exceed_95 <- exceedances_table(VaR_list, plrets)$table_95
  performance_table_95 <- data.frame(coverage_95, tests_95, exceed_95)
  colnames(performance_table_95) <- c("coverage_5%", "uc", "ind", "cc", 
                                      "Total_Exc", "2004", "2005", "2006", 
                                      "2007", "2008", "2009", "2010", "2011")
  rownames(performance_table_95) <- names(VaR_list)
  
  return(list(performance_table_99 = performance_table_99 %>% round(3), 
              performance_table_95 = performance_table_95 %>% round(3)))
}

## Don't run when importing
if (sys.nframe() == 0) {
  performance_table(test_VaR_list)$performance_table_99 
  performance_table(test_VaR_list)$performance_table_95
}




#---------------------------------------------------------------#
########### CPA Test as in Giacomini and White (2006) ###########
#---------------------------------------------------------------#


#' Loss VaR
#' 
#' Calculates loss function for VaR i.e. tick loss function for quantile 
#' regression
#' 
#' @param VaR dataframe w/ dates in first column, 99% VaR in second column and 
#' 95% VaR in third column
#' @param plrets portfolio returns; by default portfolio returns from t=1001 
#' until t=T
#' @param percentile 1- VaR percentiles; by default c(0.99, 0.95)
#'
#' @return list w/ losses for the percentiles as first two elements and 
#' mean losses for the percentiles as last two elements
loss_VaR <- function(VaR, plrets = portfolio_plret_df[-c(1:1000),2], 
                     percentile = c(0.99, 0.95)){
  indicator_99 <- ifelse(plrets-VaR[2]<0, 1, 0)
  indicator_95 <- ifelse(plrets-VaR[3]<0, 1, 0)
  loss_99 <- (plrets-VaR[2])*(percentile[1]-indicator_99)
  loss_95 <- (plrets-VaR[3])*(percentile[2]-indicator_95)
  return(list(
    loss_99=loss_99, 
    loss_95 = loss_95, 
    mean_loss_99 = colMeans(loss_99), 
    mean_loss_95 = colMeans(loss_95)
    ))
}

## Don't run when importing
if (sys.nframe() == 0) {
  Uni_t_GJR_loss <- loss_VaR(Uni_t_GJR_GARCH_VaR)
  Uni_Normal_loss <- loss_VaR(Uni_Normal_GARCH_VaR)
  Uni_Normal_loss$mean_loss_99
  Uni_t_GJR_loss$mean_loss_99
}


## Don't run when importing
if (sys.nframe() == 0) {
  ## Compare w/ VaRloss function from rugarch package:
  all.equal(VaRloss(0.95, portfolio_plret_df[-c(1:1000),2], 
                    Uni_Normal_GARCH_VaR[,3]), 
            as.numeric(as.matrix(100*Uni_Normal_loss$loss_95)))
  all.equal(VaRloss(0.95, portfolio_plret_df[-c(1:1000),2], 
                    Uni_t_GJR_GARCH_VaR[,3]), 
            as.numeric(as.matrix(100*Uni_t_GJR_loss$loss_95)))
  # rugarch VaRloss is 100* the loss calculated above
}



#' Ranking VaR forecasts
#' 
#' Ranking VaR forecasts in ascending order based on their average VaR/ tick loss.
#'
#' @param VaR_list list of VaR dataframes with date in first column, 1% VaR in
#' second column and 5% VaR in third column
#' @param plrets portfolio returns; by default portfolio returns from t=1001 
#' until t=T
#' @param percentile 1- VaR percentiles; by default c(0.99, 0.95)
#'
#' @return list with tables for 1% and 5% VaR ranking
VaR_loss_ranking <- function(VaR_list, plrets = portfolio_plret_df[-c(1:1000),],
                             percentile = c(0.99, 0.95)){
  n <- length(VaR_list)
  matrix_99 <- matrix(0L, nrow = n, ncol = 1)
  matrix_95 <- matrix(0L, nrow = n, ncol = 1)
  for (i in 1:n){
    matrix_99[i, 1] <- unlist(loss_VaR(VaR_list[[i]])$mean_loss_99)
    matrix_95[i, 1] <- unlist(loss_VaR(VaR_list[[i]])$mean_loss_95)
  }
  table_99 <- data.frame(matrix_99)
  colnames(table_99) <- c("mean_VaR_loss")
  rownames(table_99) <- names(VaR_list)
  table_99 <- table_99 %>% arrange(mean_VaR_loss) # arange in ascending order
  
  
  table_95 <- data.frame(matrix_95)
  colnames(table_95) <- c("mean_VaR_loss")
  rownames(table_95) <- names(VaR_list)
  table_95 <- table_95 %>% arrange(mean_VaR_loss) 
  return(list(table_99 = table_99, table_95 = table_95))
}

## Don't run when importing
if (sys.nframe() == 0) {
  VaR_loss_ranking(test_VaR_list)$table_99
  VaR_loss_ranking(test_VaR_list)$table_95
}



## Create class to return two lists in CPA_test function
setClass(Class="CPA",
         representation(
           VaR_99="list",
           VaR_95="list"
         )
)

#' Conditional Predictive Ability Test by Giacomini and White (2006)
#' 
#' Implements CPA test to allow for binary model comparisons in predictive 
#' ability with a confidence level of 95%
#'
#' @param VaR1 VaR forecasts of model i (whole dataframe)
#' @param VaR2 VaR forecasts of model j (whole dataframe)
#' @param plrets portfolio returns; by default portfolio returns from t=1001 
#' until t=T
#'
#' @return instance of class "CPA" i.e. for the 1% and the 5% VaR it returns
#' a list of the test statistic, pvalue, critical value and the test decision
#' (i.e. which model has higher predictive ability and whether this difference
#' is significant or not)
CPA_test <- function(VaR1, VaR2, plrets = portfolio_plret_df[-c(1:1000),2]){
  loss1 <- loss_VaR(VaR1)
  loss2 <- loss_VaR(VaR2)
  
   
  ## 99%
  d_ij_99 <- as.matrix(loss1$loss_99)-as.matrix(loss2$loss_99)#loss differential
  T <- length(d_ij_99)
  h_tminus1_99 <- cbind(matrix(1, ncol = 1, nrow = T-1), 
                        matrix(d_ij_99[1:T-1], nrow = T-1, ncol = 1))
  
  
  
  lossdiff <- d_ij_99[2:T] # loss differential from 2nd observation onwards
  
  reg_99 <- matrix(1, nrow = nrow(h_tminus1_99), ncol = ncol(h_tminus1_99))
  for (jj in 1:2) reg_99[, jj] <- h_tminus1_99[, jj]*lossdiff
  
  # since forecasting horizon is 1, test stat can be calculated as n*R^2
  # from the regression of one on ht_minus1_99*lossdiff
  fit_99 <- lm(matrix(1, nrow = T-1, ncol =1)~0+reg_99)
  r2_99 <- summary(fit_99)$r.squared
  n <- T-1-1+1 # n=T-tau-m1+1 in paper
  test_stat_99 <- n*r2_99
  
  
  ## 95%
  d_ij_95 <- as.matrix(loss1$loss_95)-as.matrix(loss2$loss_95)#loss differential
  T <- length(d_ij_95)
  h_tminus1_95 <- cbind(matrix(1, ncol = 1, nrow = T-1), 
                        matrix(d_ij_95[1:T-1], nrow = T-1, ncol = 1))
  
  
  
  lossdiff <- d_ij_95[2:T] # loss differential from 2nd observation onwards
  
  reg_95 <- matrix(1, nrow = nrow(h_tminus1_95), ncol = ncol(h_tminus1_95))
  for (jj in 1:2) reg_95[, jj] <- h_tminus1_95[, jj]*lossdiff
  
  # since forecasting horizon is 1, test stat can be calculated as n*R^2
  # from the regression of one on ht_minus1_95*lossdiff
  fit_95 <- lm(matrix(1, nrow = T-1, ncol =1)~0+reg_95)
  r2_95 <- summary(fit_95)$r.squared
  n <- T-1-1+1 # n=T-tau-m1+1 in paper
  test_stat_95 <- n*r2_95
  
  ## Critical Values
  crit_val_99 <- qchisq(0.95, 2)
  crit_val_95 <- qchisq(0.95, 2)
  
  ## Calculate p-values
  p_val_99 <- 1-pchisq(abs(test_stat_99),2)
  p_val_95 <- 1-pchisq(abs(test_stat_95),2)
  
  mean_diff_loss_99 <- loss1$mean_loss_99-loss2$mean_loss_99
  signif_99 <- p_val_99<0.05
  ifelse(mean_diff_loss_99<0, c(better_99 <- "row"), c(better_99 <- "col"))
  
  mean_diff_loss_95 <- loss1$mean_loss_95-loss2$mean_loss_95
  signif_95 <- p_val_95<0.05
  ifelse(mean_diff_loss_95<0, c(better_95 <- "row"), c(better_95 <- "col"))
  
  if (signif_99 == TRUE){
    message(better_99, " performs significantly better")
  }
  
  if (signif_95 == TRUE){
    message(better_95, " performs significantly better")
  }
  
  return(new("CPA", 
             VaR_99 = list(test_stat_99 = test_stat_99, 
                           crit_val_99 = crit_val_99, p_val_99 = p_val_99, 
                           signif_99 = signif_99, better_99 = better_99),
             VaR_95 = list(test_stat_95 = test_stat_95, 
                           crit_val_95 = crit_val_95, p_val_95 = p_val_95, 
                           signif_95 = signif_95, better_95 = better_95)
  ))
}

## Don't run when importing
if (sys.nframe() == 0) {
  CPA_test(Uni_t_GJR_GARCH_VaR, Uni_Skewt_NGARCH_VaR)
  CPA_test(Uni_t_GJR_GARCH_VaR, Uni_EWMA_VaR)
}


#' CPA Test table
#'
#' @param VaR_list list of VaR dataframes with date in first column, 1% VaR in
#' second column and 5% VaR in third column
#' @param plrets portfolio returns; by default portfolio returns from t=1001 
#' until t=T
#' 
#' @return list of tables for the two VaR levels. Each entry in the table includes
#' the p-value and which model performed better (if one did)
CPA_table <- function(VaR_list, plrets = portfolio_plret_df[-c(1:1000),2]){
  CPA_matrix_99 <- matrix(nrow = length(VaR_list)-1, ncol = length(VaR_list)-1)
  CPA_matrix_95 <- matrix(nrow = length(VaR_list)-1, ncol = length(VaR_list)-1)
  rows <- VaR_list[-length(VaR_list)]
  cols <- VaR_list[-1]
  
  
  for (i in seq_along(rows)){
    for (j in seq_along(cols)){
      if (i<=j){
        p_val_99 <- CPA_test(rows[[i]], cols[[j]], 
                             plrets = plrets)@VaR_99$p_val_99
        better_99 <- CPA_test(rows[[i]], cols[[j]], 
                              plrets = plrets)@VaR_99$better_99
        
        p_val_95 <- CPA_test(rows[[i]], cols[[j]], 
                             plrets = plrets)@VaR_95$p_val_95
        better_95 <- CPA_test(rows[[i]], cols[[j]], 
                              plrets = plrets)@VaR_95$better_95
        
        CPA_matrix_99[i,j] <- paste(as.character(round(as.numeric(p_val_99),3)),
                                    better_99, sep  =";")
        CPA_matrix_95[i,j] <- paste(as.character(round(as.numeric(p_val_95),3)),
                                    better_95, sep  =";")
        }
    }
  }
  CPA_table_99 <- data.frame(CPA_matrix_99)
  colnames(CPA_table_99) <- names(cols)
  rownames(CPA_table_99) <- names(rows)
  
  CPA_table_95 <- data.frame(CPA_matrix_95)
  colnames(CPA_table_95) <- names(cols)
  rownames(CPA_table_95) <- names(rows)
  
  return(list(CPA_table_99 = CPA_table_99,
              CPA_table_95 = CPA_table_95))
}

## Don't run when importing
if (sys.nframe() == 0) {
  CPA_table(test_VaR_list)
}

