# MLAW LA City Equity Index
# Rent burden rates by LA City ZIP Code

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

# Download ACS table B25070 (Rent burden data from the census) and add into postgres-------------------------

# Set source for ACS 5-Yr table update fx
source("W:\\RDA Team\\R\\ACS Updates\\acs_rda_shared_tables.R") # This fx also creates or imports the correct vintage CA CBF ZCTA list

# Script file path, for postgres table comment
filepath <- "W:\\Project\\ECI\\MLAW\\R\\rates_houseburden.R"

# Define arguments for ACS table update fx
yr <- 2022 # update for the ACS data/ZCTA vintage needed

### If you add a new table, you must also update table_vars below
table <- list(
  "B25070"
) 

## Run fx to get updates ACS table(s)
update_acs(yr=yr, acs_tables=table,filepath)


# Read in tables for analysis-----------------------

###### Indicator data ----
indicator<-dbGetQuery(con2, "SELECT * FROM housing.acs_5yr_b25070_multigeo_2022 WHERE geolevel='zcta'")

###### ZIP codes in LA City ----
zips<-st_read(con, query="SELECT * FROM crosswalk_zip_city_2022") #LA City zips

# create vector of la city zipcodes for filtering the census data:
la_zips<-zips$zipcode

#### Calculate Rent burden rates at ZIP Code level ####

###### filter for LA City ---------------------
indicator<-indicator%>%filter(geoid %in% la_zips)

###### analysis  ---------------------

# aggregate data to calculate estimate total for rent burden (rentburden) which we define as spending >=30% of income on rent

df<-indicator%>%
  group_by(geoid)%>%
  mutate(rentburden=sum(b25070_007e	,b25070_008e,b25070_009e,b25070_010e),
         rentburden_moe=moe_sum(moe=c(b25070_007m	,b25070_008m,b25070_009m,b25070_010m), 
                                estimate=c(b25070_007e	,b25070_008e,b25070_009e,b25070_010e),
                                na.rm=T),
         rentburden_cv=rentburden_moe/1.645/rentburden*100,
         rentburden_rate=rentburden/b25070_001e*100,
         rentburden_rate_moe=moe_prop(rentburden,b25070_001e,rentburden_moe, b25070_001m ),
         rentburden_rate_cv=rentburden_rate_moe/1.645/rentburden_rate*100)%>%
  select(geoid,b25070_001e, b25070_001m, rentburden, rentburden_moe, rentburden_cv, 
         rentburden_rate, rentburden_rate_moe,rentburden_rate_cv )%>%
  rename("pop"="b25070_001e",
         "pop_moe"="b25070_001m")%>%
  ungroup()

# change inf and nan to NA
df[sapply(df, is.infinite)] <- NA
df[sapply(df, is.nan)] <- NA

##### Calculate percentiles ---------------------

df<-df%>%
  mutate(pctile=percent_rank(rentburden_rate))

#### Finalize and push to postgres---------------

# make sure no trailing spaces anywhere

names(df) <- gsub(" ", "", names(df))

df[df == " "] <- ""

# set column types

charvect = rep("numeric", ncol(df)) #create vector that is "varchar" for the number of columns in df

charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector

names(charvect) <- colnames(df)

table_name <- "rates_houseburden"

# push to postgres

dbWriteTable(con,  table_name, df,
             overwrite = TRUE, row.names = FALSE,
             field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_houseburden  IS 'Rate and estimates of renter units that are 
rent burdened aggregated to the zcta level. Data is only for zctas in LA City. Rent burden is defined by more than 30% or more 
of income on rent.
R script: W:\\Project\\ECI\\MLAW\\R\\rates_houseburden.R
QA document: 
W:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_houseburden.docx';

COMMENT ON COLUMN rates_houseburden.geoid IS 'zcta';
COMMENT ON COLUMN rates_houseburden.pop IS 'Total renter occupied housing units';
COMMENT ON COLUMN rates_houseburden.pop_moe IS 'Total renter occupied housing units MOE';
COMMENT ON COLUMN rates_houseburden.rentburden IS 'Total renter occupied housing units that are rent burdened. This is defined as spending 30% or more of total income on rent';
COMMENT ON COLUMN rates_houseburden.rentburden_moe IS 'Total renter occupied housing units that are rent burdened MOE';
COMMENT ON COLUMN rates_houseburden.rentburden_cv IS 'Total renter occupied housing units that are rent burdened CV';
COMMENT ON COLUMN rates_houseburden.rentburden_rate IS 'Percentage of renter occupied units that are rent burdened out of total renter occupied units by zcta';
COMMENT ON COLUMN rates_houseburden.rentburden_rate_moe IS 'MOE of the percentage of renter occupied units that are rent burdened';
COMMENT ON COLUMN rates_houseburden.rentburden_rate_cv IS 'CV of the percentage of renter occupied units that are rent burdened';
COMMENT ON COLUMN rates_houseburden.pctile IS 'Percent rank of the estimate -rentburden_rate';




")

# send table comment + column metadata
dbSendQuery(conn = con, table_comment)

