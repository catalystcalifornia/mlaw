# MLAW LA City Equity Index
# Diabetes hospitalization rates by zip code for LA City
# Data Source: HCAI/OSHPD Patient Discharge database 2017-21
# Diabetes Hospitalizations/discharges by Patient ZIP. Includes all E11.xx codes. Hospitalizatons for principal diagnosis of diabetes only

##### Set Up Workspace #####
library(dplyr)
library(RPostgreSQL)
library(tidyr)
library(stringr)
library(sf)
options(scipen=999)

# Connect to postgres

source("W:\\RDA Team\\R\\credentials_source.R")

con <- connect_to_db("eci_mlaw")
con2<-connect_to_db("rda_shared_data")

#### Read in data ####
###### ZIP codes in LA City ----
zips<-st_read(con, query="SELECT * FROM crosswalk_zip_city_2022") #LA City zips

# create vector of la city zipcodes for filtering later:
la_zips<-zips$zipcode

###### Population base ----
pop<-dbGetQuery(con2, "SELECT geoid, dp05_0001e, dp05_0001m FROM demographics.acs_5yr_dp05_multigeo_2022 
                WHERE geolevel='zcta'")

###### Diabetes hospitalizations -----
indicator_df<-dbGetQuery(con2,"select * from health.oshpd_diabetes_hosp_zip_2017_21")
fivenum(indicator_df$discharge_count) # check data
sum(is.na(indicator_df$discharge_count))

#### Calculate diabetes rates at ZIP Code level ####

###### Join data ---------------------
# test success of join
df_all <-indicator_df%>%full_join(zips) 
qa<-df_all%>%filter(is.na(discharge_count) & !is.na(prc_zip_area))

qa_2<-df_all%>%filter(!is.na(discharge_count) & is.na(prc_zip_area))
# seem to mostly all be outside of LA City looking at 900XX codes and those with highest counts--some are on the border

# final join and getting pop denominator
df <-zips%>%st_drop_geometry()%>%left_join(indicator_df) # zips and indicator

df <-df%>%left_join(pop,by=c("zipcode"="geoid")) # zips to population

###### Calculate rates ----------
df_final<-df%>%rename(pop=dp05_0001e)%>% 
  mutate(diabetes_count=discharge_count/5,#take average count based on 5-year time period
         diabetes_rate=diabetes_count/pop*1000,
         pop_cv=dp05_0001m/1.645/pop*100)%>% 
  select(zipcode,diabetes_rate,diabetes_count,pop,pop_cv)
# 90071 and 90021 have really high rates, these are in downtown. Percentile method will reduce the impact of the outliers
# 90071 might indicate need to exclude ZIP Codes with less than 500 in population

# change inf to NA
df_final[sapply(df_final, is.infinite)] <- NA

# Calculate percentiles---------------------

df_final<-df_final%>%
  filter(!is.na(zipcode))%>%
  mutate(diabetes_pctile=percent_rank(diabetes_rate))%>%
  rename("geoid"="zipcode")

# Finalize table and push to postgres -------------------

# set column types
charvect = rep("numeric", ncol(df_final)) 
charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector
names(charvect) <- colnames(df_final)

# push to postgres
# dbWriteTable(con,  "rates_diabetes", df_final,
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_diabetes  IS 'Diabetes hospitalization rates by ZIP Code in LA City. Rates are per 1K people in each ZIP Code based on ZCTA level populaton data from ACS DP05.
Diabetes hospitalizations are based on patient discharges where principal diagnosis was diabetes, data provided by HCAI (OSHPD) for years 2017-21. Rates and counts are averages for 5-year period
R script: W://Project//ECI//MLAW//R//rates_diabetes.R
QA document: 
W:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_hcai.docx';

COMMENT ON COLUMN rates_diabetes.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_diabetes.diabetes_rate IS 'Diabetes hospitalizations rates in the ZIP Code per 1K people, average of 2017-21';
COMMENT ON COLUMN rates_diabetes.diabetes_count IS 'Average total number of diabetes-related hospitalizaton in the ZIP Code years 2017-21';
COMMENT ON COLUMN rates_diabetes.pop IS 'Total population in the ZIP Code';
COMMENT ON COLUMN rates_diabetes.pop_cv IS 'Population cv in percent';
COMMENT ON COLUMN rates_diabetes.diabetes_pctile IS 'Percent rank of the estimate -rate';

")

# send table comment + column metadata
# dbSendQuery(con = con, table_comment)

