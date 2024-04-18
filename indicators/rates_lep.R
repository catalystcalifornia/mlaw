# MLAW LA City Equity Index
# Limited English Speaking household rates by LA City ZIP Code
# Data source: S1602 ACS 5-year estimates ZCTA table 2018-22


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

###### Indicator data ----
indicator<-dbGetQuery(con2, "SELECT * FROM demographics.acs_5yr_s1602_multigeo_2022 
                WHERE geolevel='zcta'")

#### Calculate LEP rates at ZIP Code level ####

###### filter for LA City ---------------------
indicator<-indicator%>%filter(geoid %in% la_zips)

###### Calculate rates ----------
df_final<-indicator%>%
  mutate(hhlds_pop=s1602_c01_001e,#all households
         hhlds_cv=s1602_c01_001m/1.645/hhlds_pop*100, # all households cv
         lep_hhlds_count=s1602_c03_001e,#all limited english households
         lep_hhlds_cv=s1602_c03_001m/1.645/lep_hhlds_count*100, # all limited english households cv
         lep_hhlds_rate=lep_hhlds_count/hhlds_pop*100, # lep households rate
         lep_hhlds_rate_moe=moe_prop(lep_hhlds_count,hhlds_pop,s1602_c03_001m,s1602_c01_001m), # lep households moe
         lep_hhlds_rate_cv=lep_hhlds_rate_moe/1.645/lep_hhlds_rate*100) %>% # lep households cv
  select(geoid,lep_hhlds_rate,lep_hhlds_rate_cv,lep_hhlds_count,lep_hhlds_cv,hhlds_pop,hhlds_cv)

# change inf and nan to NA
df_final[sapply(df_final, is.infinite)] <- NA
df_final[sapply(df_final, is.nan)] <- NA

# Calculate percentiles---------------------

df_final<-df_final%>%
  mutate(lep_pctile=percent_rank(lep_hhlds_rate))

# Finalize table and push to postgres -------------------

# set column types
charvect = rep("numeric", ncol(df_final)) 
charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector
names(charvect) <- colnames(df_final)

# push to postgres
# dbWriteTable(con,  "rates_lep", df_final,
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_lep  IS 
'Limited English proficiency households by ZIP Code in LA City, approximated using ZCTA-level data based on limited english speaking households out of all households in a ZCTA
R script: W://Project//ECI//MLAW//R//rates_lep.R
QA document: 
W:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_lep.docx';

COMMENT ON COLUMN rates_lep.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_lep.lep_hhlds_rate IS 'Limited English proficiency households %';
COMMENT ON COLUMN rates_lep.lep_hhlds_rate_cv IS 'Coefficient of variation for limited English proficiency households %';
COMMENT ON COLUMN rates_lep.lep_hhlds_count IS 'Limited English proficiency households count - numerator for the estimate';
COMMENT ON COLUMN rates_lep.lep_hhlds_cv IS 'Coefficient of variation for limited English proficiency households count';
COMMENT ON COLUMN rates_lep.hhlds_pop IS 'Total households count - universe or denominator of the estimate';
COMMENT ON COLUMN rates_lep.hhlds_cv IS 'Coefficient of variation for total households count';
COMMENT ON COLUMN rates_lep.lep_pctile IS 'Percent rank of the estimate -rate';
")

# send table comment + column metadata
# dbSendQuery(con = con, table_comment)

