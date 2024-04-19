# MLAW LA City Equity Index
# Pollution burden scores overall and for hazardous waste facilities, toxic releases, pm 2.5, and drinking water contaminants
# Data Source: CalEnviroScreen v4 2021

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

# Read in tables from postgres

# LA City limited census tracts
library(rgdal)
# I save the 2010 LA city census tracts in the W drive: W:\Data\Geographies\LA City\Census_Tracts_2010_Population
# Downloaded from: https://geohub.lacity.org/datasets/lahub::census-tracts-2010-population/explore
tracts <- readOGR( 
  dsn="W:\\Data\\Geographies\\LA City\\Census_Tracts_2010_Population", 
  layer="Census_Tracts_2010_Population",
  verbose=FALSE
)

tracts<-st_as_sf(tracts)%>%
  select(TRACTCE10, geometry)%>%
  mutate(ct_geoid=paste0("06037",TRACTCE10)) # create full ct_geoid that includes state and county fips

# create vector of la city tracts for filtering later:
la_tracts<-tracts$ct_geoid

# Full LA County tracts to have a complete join with ZIP Code geos
# if we just use the city cut tracts that we miss out on tracts that intersect with part of ZIP Codes included
library(tigris)
la_county_tracts <- tracts(state = "CA", county = "Los Angeles", cb = TRUE, year = 2010)

# LA City zips
zcta<-st_read(con, query="SELECT * FROM crosswalk_zip_city_2022") 

# create vector of la city zipcodes for filtering later:
la_zips<-zcta$zipcode

# ces data
ces<-st_read(con, query= "SELECT * FROM oehha_ces4_tract_2021")

# ces vars:

# pm2.5: pm2_5 (annual mean) -raw value
# pollution burden percentile: polburdp -percentile
# contaminated drinking water: drinkwat -raw value
# proximity to hazardous waste: hazwaste -raw value
# toxic release from facilities: tox_rel -raw value

#####Prep CES data----------------------

# Filter CES data for only tracts in LA City based on 2010 tracts
# commenting out old join
# ces<-ces%>%
#   filter(ct_geoid %in% la_tracts)

# Intersect LA City ZIPs to full LA County tracts
zcta<-st_transform(zcta,3310)
la_county_tracts<-st_transform(la_county_tracts,3310)

tract_zip<-st_intersection(zcta,la_county_tracts)

# check intersect
library(mapview)
mapview(tract_zip)+mapview(zcta)
# intersect looks good

# get unique tracts
tract_zip<-tract_zip%>%mutate(ct_geoid=substr(GEO_ID, 10,20))
la_tracts_list<-unique(tract_zip$ct_geoid) # shorter geoid for ces join
la_tracts_list_long<-unique(tract_zip$GEO_ID) # longer geoid for joining back to ct shps

###Rescale the polburdp indicator so that the percentile is at the LA City tract level---------------------
ces<-ces%>%
  filter(ct_geoid %in% la_tracts_list)

ces<-ces%>%
  mutate(polburdp = percent_rank(polburdp))

# Now perform a percentile rank of the CES indicators that are within LA County
## NOTE the other indicators are raw values, not percentiles, and thus do not need to be rescaled

# Select columns of interest
ces<-ces%>%
  select(ct_geoid, pm2_5, polburdp, drinkwat, hazwaste, tox_rel)

### Create xwalk of zctas to tracts --------------------

# code from xwalk function from RC:  W:\Project\RACE COUNTS\2023_v5\API\arei_city_county_district_table.R 
tract_3310 <- la_county_tracts%>%filter(GEO_ID %in% la_tracts_list_long) # filter just for tracts intersecting with LA City Zips
tract_3310<-st_transform(tract_3310, 3310) # change projection to 3310
zcta_3310 <- st_transform(zcta, 3310) # change projection to 3310

# calculate area of tracts and zctas
tract_3310$tract_area <- st_area(tract_3310)
zcta_3310$zcta_area <- st_area(zcta_3310)

# run intersect
tract_zcta <-zcta_3310%>%
  st_intersection(tract_3310, zcta_3310) 

# calculate area of intersect
tract_zcta$intersect_area <- st_area(tract_zcta)

# calculate percent of intersect out of total zcta area, and percent of intersect out of total tract area
tract_zcta <-  tract_zcta %>% 
  mutate(prc_zcta_area = as.numeric(tract_zcta$intersect_area/ tract_zcta$zcta_area),
         prc_tract_area = as.numeric(tract_zcta$intersect_area/ tract_zcta$tract_area)
  )

# convert to df
tract_zcta <- as.data.frame(tract_zcta)


# clean up and select columns of interest

xwalk <- tract_zcta%>%
  st_drop_geometry()%>%   # don't need this to be a spatial df anymore
  select(zipcode, GEO_ID, zcta_area, tract_area, intersect_area, prc_tract_area, prc_zcta_area)


# Join zcta-tract xwalk to CES data---------------------

# we will use the Unfiltered xwalk for now

df<-ces%>%
  left_join(xwalk%>%mutate(ct_geoid=substr(GEO_ID, 10,20)))%>%
  select(-geometry)%>%
  as.data.frame()

# Adjust CES var values using tract-zcta prc area intersection ------

df<-df%>%
  mutate(pm2_5_adj=pm2_5*prc_zcta_area,
         drinkwat_adj=drinkwat*prc_zcta_area,
         polburdp_adj=polburdp*prc_zcta_area, ###rescaled pctile for la city
         hazwaste_adj=hazwaste*prc_zcta_area, 
         tox_rel_adj=tox_rel*prc_zcta_area)

# aggregate data to the zipcode level

df<-df%>%
  group_by(zipcode) %>%
  summarize(
    pm2_5_adj = sum(pm2_5_adj),
    drinkwat_adj = sum(drinkwat_adj),
    polburdp_adj = sum(polburdp_adj),
    hazwaste_adj = sum(hazwaste_adj),
    tox_rel_adj = sum(tox_rel_adj))

# then recalculate percentile rank off new adjusted values

df<-df%>%filter(!is.na(zipcode))%>%
  mutate(pm2_5_pctile_adj = percent_rank(pm2_5_adj),
         drinkwat_pctile_adj = percent_rank(drinkwat_adj),
         hazwaste_pctile_adj = percent_rank(hazwaste_adj),
         tox_rel_pctile_adj = percent_rank(tox_rel_adj),
         polburdp_pctile_adj = percent_rank(polburdp_adj),
  )%>%
  rename("geoid"="zipcode") # for consistency making this column geoid across all rate tables

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

# dbWriteTable(con,  "rates_ces", df,
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_ces  IS 'Calenviroscreen indicators of interest for the MLAW project (pm2.5, pollution burden, drinking water, prox to hazardous waste, toxic releases)
  aggregated to the zipcode level for LA city. Values are adjusted from tract to zipcode level using the percent of tract area within the tract-zipcode intersect. Table includes adjusted values and percentiles at the 
  zipcode level.
R script: W:\\Project\\ECI\\MLAW\\R\\rates_ces.R
QA document: 
WW:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_ces.docx';

COMMENT ON COLUMN rates_ces.geoid IS 'Zipcode (2022)';
COMMENT ON COLUMN rates_ces.pm2_5_adj IS 'pm2.5 annual mean adjusted to zipcode level';
COMMENT ON COLUMN rates_ces.drinkwat_adj IS 'Drinking water contaminant index for selected contaminants
 adjutsed to zipcode level';
COMMENT ON COLUMN rates_ces.polburdp_adj IS 'Pollution burden percentile rescaled to LA city level and then adjusted to zipcode level';
COMMENT ON COLUMN rates_ces.hazwaste_adj IS 'Sum of weighted hazardous waste facilities and large quantity generators within buffered distances to populated blocks of census tracts
 adjusted to zipcode level';
COMMENT ON COLUMN rates_ces.tox_rel_adj IS 'Toxicity-weighted concentrations of modeled chemical releases to air from facility emissions and off-site incineration (from RSEI)
 adjusted to zipcode level';
 
COMMENT ON COLUMN rates_ces.pm2_5_pctile_adj IS 'Percentile of the pm2.5 annual mean adjusted to zipcode level';
COMMENT ON COLUMN rates_ces.drinkwat_pctile_adj IS 'Percentile of the Drinking water contaminant index for selected contaminants';

COMMENT ON COLUMN rates_ces.polburdp_pctile_adj IS 'Final percentile of pollution burden percentile that was rescaled to LA city level and then adjusted to zipcode level';

COMMENT ON COLUMN rates_ces.hazwaste_pctile_adj IS 'Percentile of sum of weighted hazardous waste facilities and large quantity generators within buffered distances to populated blocks of census tracts
 adjusted to zipcode level';
 COMMENT ON COLUMN rates_ces.tox_rel_pctile_adj IS 'Percentile of Toxicity-weighted concentrations of modeled chemical releases to air from facility emissions and off-site incineration (from RSEI)
 adjusted to zipcode level';
 
")

# send table comment + column metadata
# dbSendQuery(conn = con, table_comment)
