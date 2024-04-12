# MLAW LA City Equity Index
# Race estimates and rates by LA City ZIP COde

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
library(data.table)

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
race<-dbGetQuery(con, "SELECT * FROM acs_5yr_dp05_multigeo_2022 WHERE geolevel = 'zcta'")

##### Calculate Race rates at ZIP Code level ####

# Take race data and filter for only tracts and zipcodes in LA County

race<-race%>%
  filter(geoid %in% la_zips)

# filter out columns of interest, then calculate the cvs for the race percentages and rename columns

df<-race%>%
  select(geoid, dp05_0033e, dp05_0033m, dp05_0033pe,dp05_0033pm, #tOTAL
         dp05_0079e, dp05_0079m, dp05_0079pe,dp05_0079pm, # NH-WHITE
         dp05_0080e, dp05_0080m, dp05_0080pe, dp05_0080pm, # NH-BLACK
         dp05_0082e, dp05_0082m, dp05_0082pe, dp05_0082pm, # NH-ASIAN
         dp05_0073e, dp05_0073m, dp05_0073pe, dp05_0073pm, # Latinx
         dp05_0068e, dp05_0068m, dp05_0068pe, dp05_0068pm, # AIAN -AOIC
         dp05_0070e, dp05_0070m, dp05_0070pe, dp05_0070pm # NHPI -AOIC
         
  )%>%
  mutate(tot_pop_cv=(dp05_0033m/1.645)/dp05_0033e*100,
         lat_pct_cv=((dp05_0073pm/1.645)/dp05_0073pe)*100,
         nh_white_pct_cv=((dp05_0079pm/1.645)/dp05_0079pe)*100,
         nh_black_pct_cv=((dp05_0080pm/1.645)/dp05_0080pe)*100,
         nh_asian_pct_cv=((dp05_0082pm/1.645)/dp05_0082pe)*100,
         aian_pct_cv=((dp05_0068pm/1.645)/dp05_0068pe)*100,
         nhpi_pct_cv=((dp05_0070pm/1.645)/dp05_0070pe)*100,
  )%>%
  
  rename(
    "tot_pop"= "dp05_0033e",
    "tot_pop_moe"="dp05_0033m",
    
    "latinx"="dp05_0073e",
    "lat_pct"="dp05_0073pe",
    "lat_pct_moe"="dp05_0073pm",
    
    "nh_black"="dp05_0080e",
    "nh_black_pct"="dp05_0080pe",
    "nh_black_pct_moe"="dp05_0080pm",
    
    "nh_white"="dp05_0079e",
    "nh_white_pct"="dp05_0079pe",
    "nh_white_pct_moe"="dp05_0079pm",
    
    "nh_asian"="dp05_0082e",
    "nh_asian_pct"="dp05_0082pe",
    "nh_asian_pct_moe"="dp05_0082pm",

    "aian_aoic"="dp05_0068e",
     "aian_pct"="dp05_0068pe",
    "aian_pct_moe"="dp05_0068pm",
    
    "nhpi_aoic"="dp05_0070e",
    "nhpi_pct"="dp05_0070pe",
    "nhpi_pct_moe"="dp05_0070pm",
    
    )%>%
  
  select(geoid, tot_pop, tot_pop_moe, 
         latinx, lat_pct, lat_pct_moe, lat_pct_cv,
        nh_black,  nh_black_pct, nh_black_pct_moe, nh_black_pct_cv,
        nh_white,  nh_white_pct, nh_white_pct_moe, nh_white_pct_cv,
        nh_asian, nh_asian_pct, nh_asian_pct_moe, nh_asian_pct_cv,
        aian_aoic, aian_pct, aian_pct_moe, aian_pct_cv,
        nhpi_aoic, nhpi_pct, nhpi_pct_moe, nhpi_pct_cv
  )

# replace the 'inf' and 'NaN' values to NULL.

df[sapply(df, is.nan)] <- NA
df[sapply(df, is.infinite)] <- NA

# Finalize and export to postgres----------------------

# make sure no trailing spaces anywhere

names(df) <- gsub(" ", "", names(df))

df[df == " "] <- ""

# set column types

charvect = rep("numeric", ncol(df)) #create vector that is "varchar" for the number of columns in df

charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector

names(charvect) <- colnames(df)

table_name <- "rates_race"

# push to postgres

dbWriteTable(con,  table_name, df,
             overwrite = TRUE, row.names = FALSE,
             field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_race  IS 'Estimates, MOEs, Percents, Percent MOEs and Percent CVs for racial groups. All racial groups are exclusive of Latinx except for NHPI and AIAN which are alone or in combination with other races. 
Racial data is pulled from ACS 5-year estimates 2018-2022 table DP05. Data is only for zctas in LA County.
R script: W:\\Project\\ECI\\MLAW\\R\\rates_race.R
QA document: 
W:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_race.docx';

COMMENT ON COLUMN rates_race.geoid IS 'Geoid';
COMMENT ON COLUMN rates_race.tot_pop IS 'Total population estimate';
COMMENT ON COLUMN rates_race.tot_pop_moe IS 'Total population estimate MOE';

COMMENT ON COLUMN rates_race.latinx IS 'Total of population that is Latinx';
COMMENT ON COLUMN rates_race.lat_pct IS 'Percentage of population that is Latinx';
COMMENT ON COLUMN rates_race.lat_pct_moe IS 'Percentage of population that is Latinx MOE';
COMMENT ON COLUMN rates_race.lat_pct_cv IS 'Percentage of population that is Latinx CV';

COMMENT ON COLUMN rates_race.nh_black IS 'Total population that is NH-Black';
COMMENT ON COLUMN rates_race.nh_black_pct IS 'Percentage of population that is NH-Black';
COMMENT ON COLUMN rates_race.nh_black_pct_moe IS 'Percentage of population that is NH-Black MOE';
COMMENT ON COLUMN rates_race.nh_black_pct_cv IS 'Percentage of population that is NH-Black CV';

COMMENT ON COLUMN rates_race.nh_white IS 'Total population that is NH-White';
COMMENT ON COLUMN rates_race.nh_white_pct IS 'Percentage of population that is NH-White';
COMMENT ON COLUMN rates_race.nh_white_pct_moe IS 'Percentage of population that is NH-White MOE';
COMMENT ON COLUMN rates_race.nh_white_pct_cv IS 'Percentage of population that is NH-White CV';

COMMENT ON COLUMN rates_race.nh_asian IS 'Total population that is NH-Asian';
COMMENT ON COLUMN rates_race.nh_asian_pct IS 'Percentage of population that is NH-Asian';
COMMENT ON COLUMN rates_race.nh_asian_pct_moe IS 'Percentage of population that is NH-Asian MOE';
COMMENT ON COLUMN rates_race.nh_asian_pct_cv IS 'Percentage of population that is NH-Asian CV';

COMMENT ON COLUMN rates_race.aian_aoic IS 'Total population that is AIAN alone or in combination with other races';
COMMENT ON COLUMN rates_race.aian_pct IS 'Percentage of population that is AIAN alone or in combination with other races';
COMMENT ON COLUMN rates_race.aian_pct_moe IS 'Percentage of population that is AIAN alone or in combination with other races MOE';
COMMENT ON COLUMN rates_race.aian_pct_cv IS 'Percentage of population that is AIAN alone or in combination with other races CV';

COMMENT ON COLUMN rates_race.nhpi_aoic IS 'Total population that is NHPI alone or in combination with other races';
COMMENT ON COLUMN rates_race.nhpi_pct IS 'Percentage of population that is NHPI alone or in combination with other races';
COMMENT ON COLUMN rates_race.nhpi_pct_moe IS 'Percentage of population that is NHPI alone or in combination with other races MOE';
COMMENT ON COLUMN rates_race.nhpi_pct_cv IS 'Percentage of population that is NHPI alone or in combination with other races CV';
")

# send table comment + column metadata
dbSendQuery(conn = con, table_comment)
