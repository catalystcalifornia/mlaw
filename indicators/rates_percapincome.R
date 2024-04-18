# MLAW LA City Equity Index
# Per capita income rates by LA City ZIP Code
# Data source: ACS B19301 5-year estimates 2018-22

##### Set Up Workspace #####
library(dplyr)
library(RPostgreSQL)
library(tidyr)
library(tidycensus)
library(stringr)

# Connect to postgres

source("W:\\RDA Team\\R\\credentials_source.R")

con <- connect_to_db("eci_mlaw")
con2<-connect_to_db("rda_shared_data")
drv <- dbDriver("PostgreSQL")

#### Read in data ####
###### ZIP codes in LA City ----
zips<-st_read(con, query="SELECT * FROM crosswalk_zip_city_2022") #LA City zips

# create vector of la city zipcodes for filtering later:
la_zips<-zips$zipcode

###### Indicator data ----
percapinc<-dbGetQuery(con, "SELECT * FROM acs_5yr_b19301_multigeo_2022 WHERE geolevel = 'zcta'")

#### Calculate per capita income rates at ZIP Code level ####

# take per capita income data and filter only for zips in la city

percapinc<-percapinc%>%
  filter(geoid %in% la_zips)

# Calculate SE and CVs--------------

df<-percapinc%>%
  mutate(percapinc_se=b19301_001m/1.645,
         percapinc_cv=percapinc_se/b19301_001e*100,
         pctile=percent_rank(b19301_001e))%>%
  rename("percapinc"="b19301_001e",
         "percapinc_moe"="b19301_001m")%>%
  select(-c(name, geolevel, percapinc_se))

# Finalize table and push to postgres -------------------

# make sure no trailing spaces anywhere in the df

names(df) <- gsub(" ", "", names(df))

df[df == " "] <- ""

# set column types

charvect = rep("numeric", ncol(df)) #create vector that is "varchar" for the number of columns in df

charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector

names(charvect) <- colnames(df)

# push to postgres

# dbWriteTable(con,  "rates_percapincome", df, 
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_percapincome  IS 'Per capita income for LA city zctas. R script: W:\\Project\\ECI\\MLAW\\R\\rates_percapincome.R
QA document: 
WW:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_percapincome.docx';

COMMENT ON COLUMN rates_percapincome.geoid IS 'Zipcode (2022)';
COMMENT ON COLUMN rates_percapincome.percapinc IS 'Per capita income (B19301e) in the past 12 months in 2022 inflation adjutsed dollars';
COMMENT ON COLUMN rates_percapincome.percapinc_moe IS 'Margin of error of estimate (B19301m)';
COMMENT ON COLUMN rates_percapincome.percapinc_cv IS 'CV';
COMMENT ON COLUMN rates_percapincome.pctile IS 'Percent rank of the estimate -percapinc';

")
 
# send table comment + column metadata
# dbSendQuery(conn = con, table_comment)
