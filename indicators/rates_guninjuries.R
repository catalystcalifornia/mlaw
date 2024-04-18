# MLAW LA City Equity Index
# Gun injury rates per 10K by zip code for LA City


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

###### Gun injury hospitalizations -----
indicator_df<-dbGetQuery(con2,"select * from health.oshpd_guninj_hosp_zip_2017_21")

View(indicator_df)
# some data are suppressed, less than <11 count, recode those to midpoint between 0 and 11
indicator_df<-indicator_df%>%mutate(discharge_count_raw=discharge_count,
                                    discharge_count=ifelse(discharge_count=="<11",5.5,as.numeric(discharge_count)))
fivenum(indicator_df$discharge_count) # one really high value of 234

sum(is.na(indicator_df$discharge_count)) # no NAs

#### Calculate gun injury rates at ZIP Code level ####

###### Join data ---------------------
# test success of join
df_all <-indicator_df%>%full_join(zips) 
qa<-df_all%>%filter(is.na(discharge_count) & !is.na(prc_zip_area))
# some with no counts are in higher income areas, e.g., 91436,90077, for now assume if there is a population in the ZIP Code, then the rate is 0 if no counts reported

qa_2<-df_all%>%filter(!is.na(discharge_count) & is.na(prc_zip_area))
# seem to mostly all be outside of LA City looking at 900XX codes and those with highest counts--some are on the border

# final join and getting pop denominator
df <-zips%>%st_drop_geometry()%>%left_join(indicator_df) # zips and indicator

df <-df%>%left_join(pop,by=c("zipcode"="geoid")) # zips to population

###### Calculate rates ----------
df_final<-df%>%rename(pop=dp05_0001e)%>% 
  mutate(guninj_count=ifelse(pop>0 & is.na(discharge_count), 0, discharge_count/5),#take average count based on 5-year time period
         guninj_rate=guninj_count/pop*10000, # given low counts of gun injuries making per 10K
         pop_cv=dp05_0001m/1.645/pop*100)

View(df_final) # looks good, reduce columns

df_final<-df_final%>% 
  select(zipcode,guninj_rate,guninj_count,pop,pop_cv)
# 90012 which includes dodger stadium and china town has a higher rate

# change inf to NA
df_final[sapply(df_final, is.infinite)] <- NA

# Calculate percentiles---------------------

df_final<-df_final%>%
  filter(!is.na(zipcode))%>%
  mutate(guninj_pctile=percent_rank(guninj_rate))%>%
  rename("geoid"="zipcode")

# Finalize table and push to postgres -------------------

# set column types
charvect = rep("numeric", ncol(df_final)) 
charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector
names(charvect) <- colnames(df_final)

# push to postgres
# dbWriteTable(con,  "rates_guninj", df_final,
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_guninj  IS 'Non-fatal gun injury hospitalization rates by ZIP Code in LA City. Rates are per 10K people in each ZIP Code based on ZCTA level populaton data from ACS DP05.
Non-fatal gun injury hospitalizations are based on patient discharge data provided by HCAI (OSHPD) for years 2017-21. Rates and counts are averages for 5-year period
R script: W://Project//ECI//MLAW//R//rates_guninjuries.R
QA document: 
W:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_hcai.docx';

COMMENT ON COLUMN rates_guninj.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_guninj.guninj_rate IS 'Non-fatal gun injury hospitalizations rates in the ZIP Code per 10K people, average of 2017-21';
COMMENT ON COLUMN rates_guninj.guninj_count IS 'Average total number of gun injury hospitalizatons in the ZIP Code years 2017-21';
COMMENT ON COLUMN rates_guninj.pop IS 'Total population in the ZIP Code';
COMMENT ON COLUMN rates_guninj.pop_cv IS 'Population cv in percent';
COMMENT ON COLUMN rates_guninj.guninj_pctile IS 'Percent rank of the estimate -rate';

")

# send table comment + column metadata
# dbSendQuery(con = con, table_comment)

