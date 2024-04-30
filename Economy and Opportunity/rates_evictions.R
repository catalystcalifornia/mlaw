# MLAW LA City Equity Index
# Eviction rates per renter households by LA City ZIP Code
# Data source: LA City Control, Eviction Notices February-Dec 2023
# Data source link: https://evictions.lacontroller.app/ 

##### Set Up Workspace #####
library(dplyr)
library(RPostgreSQL)
library(tidyr)
library(tidycensus)
library(readxl)
library(stringr)
library(sf)
library(tigris)
library(rpostgis)
library(areal)

# Connect to postgres

source("W:\\RDA Team\\R\\credentials_source.R")

con <- connect_to_db("eci_mlaw")
con2<-connect_to_db("rda_shared_data")
drv <- dbDriver("PostgreSQL")

# Read in tables from postgres ----

###### ZIP Codes --------
zcta<-st_read(con, query="SELECT * FROM crosswalk_zip_city_2022") #LA City zips

# create vector of la city zipcodes for filtering later:
la_zips<-zcta$zipcode

###### Population and tenure (renter households) ----------
pop<-dbGetQuery(con2, "SELECT geoid, dp05_0001e, dp05_0001m FROM demographics.acs_5yr_dp05_multigeo_2022 
                WHERE geolevel ILIKE 'zcta'")

tenure<-dbGetQuery(con2, "SELECT geoid, b25003_003e	, b25003_003m	 FROM housing.acs_5yr_b25003_multigeo_2022
                WHERE geolevel ILIKE 'zcta'")%>%
  filter(geoid %in% la_zips) # only keep la city zip values

evict<-dbGetQuery(con2, "SELECT * FROM housing.lacomptroller_evictions_2023")

# Explore data and test methods ----------------

table(evict$eviction_category)

cause<-as.data.frame(table(evict$cause))

###### Rate calc method 1: Calculate rates by zip---------------------

df<-evict%>%
  mutate(total=n())%>% # total evictions: denominator
  group_by(zip)%>%
  mutate(count=n(), # total by zip, numerator
         rate=count/total*100)%>%
  ungroup()%>%
  mutate(pctile=percent_rank(rate))%>%
  select(zip, total, count, rate, pctile)

###### Rate calc method 2: Calc rates out of total renters within each zip ------------------
# final method
df2<-evict%>%
  group_by(zip)%>%
  summarise(count=n())%>%
  left_join(tenure, by=c("zip"="geoid"))%>%
  rename("renter_tot"="b25003_003e",
         "renter_tot_moe"="b25003_003m")%>% 
  mutate(rate=count/renter_tot*100)
# some ZIPs that don't join to tenure are outside of LA City or on the border

# join the other way to keep our 105 ZIP Code base
df_final<-evict%>%
  group_by(zip)%>%
  summarise(count=n())%>%
  right_join(tenure, by=c("zip"="geoid"))%>%
  rename("renter_tot"="b25003_003e",
         "renter_tot_moe"="b25003_003m")%>% 
  mutate(rate=count/renter_tot*100,
         renter_cv=renter_tot_moe/1.645/renter_tot*100)

# 90071 has 0 renters and 0 evictions
# going to replace that with NA for now 

df_final[sapply(df_final, is.infinite)] <- NA

# calculate percentiles
df_final<-df_final%>%
  mutate(eviction_pctile=percent_rank(rate))%>%
  rename("geoid"="zip",
         eviction_count=count,
         eviction_rate=rate)%>%
  select(geoid, renter_tot, renter_cv, eviction_count, eviction_rate, eviction_pctile)

# going to switch this to df now to push to postgres
df<-df_final

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

# dbWriteTable(con,  "rates_evictions", df, 
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_evictions  IS 'Rate of evictions in LA City by zipcode. Original data from LA Controller office for Feb 2023-Dec 2023
R script: W:\\Project\\ECI\\MLAW\\R\\rates_evictions.R
QA document: 
WW:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_evictions.docx';

COMMENT ON COLUMN rates_evictions.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_evictions.renter_tot IS 'Total number of renters in the zipcode based off ACS table B25003';
COMMENT ON COLUMN rates_evictions.eviction_count IS 'Count of evictions';
COMMENT ON COLUMN rates_evictions.eviction_rate IS 'Rate of evictions out of total renters';
COMMENT ON COLUMN rates_evictions.eviction_pctile IS 'Percent rank of the estimate -rate';

")

# send table comment + column metadata
# dbSendQuery(conn = con, table_comment)

