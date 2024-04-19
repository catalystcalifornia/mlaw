# MLAW LA City Equity Index
# Pedestrian and bicycle injuries per 1K in LA City ZIP Codes
# Data source: UC Berkeley Transportation Injury Mapping System
# Link: https://tims.berkeley.edu/help/SWITRS.php#Codebook

# Set up workspace

library(dplyr)
library(RPostgreSQL)
library(tidyr)
library(tidycensus)
library(readxl)
library(stringr)
library(sf)
library(sp)
library(tigris)
library(rpostgis)
library(areal)
library(mapview)

source("W:\\RDA Team\\R\\credentials_source.R")
con <- connect_to_db("eci_mlaw")
con2<- connect_to_db("rda_shared_data")

## Pull in data --------

# pull in TIMS victims and crashes data from rda_shared database
# Code book: https://tims.berkeley.edu/help/SWITRS.php#Codebook

victims <- dbGetQuery(con2, "SELECT * FROM built_environment.tims_victims_2015_22")
crashes <- dbGetQuery(con2, "SELECT * FROM built_environment.tims_crashes_2015_22")

# pull in la city zips
zips<-st_read(con, query="SELECT * FROM crosswalk_zip_city_2022")

# read in zcta pop data

pop<-dbGetQuery(con2, "SELECT * FROM demographics.acs_5yr_dp05_multigeo_2022 where
                geolevel = 'zcta'")

# Select coordinates data from crash table
coordinates <- crashes %>% 
  select(case_id, accident_year, latitude, longitude, point_x, point_y, primary_rd, secondary_rd, direction)%>% 
  mutate(point_x = ifelse(is.na(point_x), longitude, point_x), 
         point_y = ifelse(is.na(point_y), latitude, point_y)) # make the coord columns equal the latitude and longitude columns if it is missing


## Step 1: filter data for pedestrian/bicyclists killed or severely injured --------

## According to the codebook: "For the purpose of analysis across multiple years with old definition (2, 3, and 4), we combined injury status categories using the latest definitions (5, 6 and 7); i.e., all victims coded as "Severe Injury" or "Suspected Serious Injury" are shown as "Suspected Serious Injury" in our tools."
victims_filtered <- victims %>%
  filter(victim_degree_of_injury %in% c("1", "2", "5") &
           victim_role %in% c("3", "4") &
           accident_year %in% c("2018", "2019","2020", "2021", "2022")) %>% 
  select(case_id, party_number, victim_degree_of_injury, victim_role, victim_age, county, city, accident_year)

# join victims data to coordinates 
victims_coordinates <- victims_filtered %>% 
  left_join(coordinates, by = c("case_id", "accident_year")) 

# separate out NA coordinates from victims df and save as separate table
coordinates_na <- victims_coordinates %>% 
  filter(is.na(point_x)) # there are 102 observations without lat long coords

victims_coordinates_df <- victims_coordinates %>%
  filter(!is.na(point_x))

# create spatial df out of victims data
victims_spdf <- SpatialPointsDataFrame(
  coords = victims_coordinates_df [, c("point_x", "point_y")],
  data = victims_coordinates_df,
  proj4string = CRS("+init=epsg:4326")
)

# mapview::mapview(victims_spdf) ---make sure that we used the correct original CRS by mapping it

# convert to sf object
victims_sf <- st_as_sf(victims_spdf)

# Set CRS to 3310 to do a spatial join for victims/zip data 
victims_sf <- victims_sf%>%
  st_transform(3310)

zips <- zips%>%
  st_transform(3310)

# Step 2: merge victims with zips  --------------------------------------
victims_zip<-victims_sf%>%
  st_join(zips,
          join=st_intersects)

# check on duplicate case_ids/party_number fields across different zips
qa<-victims_zip%>%
  select(zipcode, case_id, party_number)%>%
  group_by(case_id, zipcode, party_number)%>%
  mutate(count=n())%>%
  filter(!is.na(zipcode))

# check how many NA zipcodes there are
sum(is.na(victims_zip$zipcode)) #2967

# lets separate out the NA zipcodes and map them to see if they are outside LA city
victims_zip_na<-victims_zip%>%
  filter(is.na(zipcode))

mapview(zips)+mapview(victims_zip_na) # visualize against la city zips, looks like these are outside the zips

# filter out the NAs from the intersection
victims_zip<-victims_zip%>%
  filter(!is.na(zipcode))

# Step 3: Calculate rate per 1,000 at the zipcode level --------------
ind_df <- victims_zip %>% 
  select(zipcode) %>% 
  rename(sub_id = zipcode) %>% 
  group_by(sub_id) %>% 
  summarize(raw = n()) 

# For now, continue with zcta population as denominator to calculate rates
total_pop <- zips%>%
  left_join(pop, by=c("zipcode"="geoid"))%>%
  rename("sub_id" = "zipcode",
         "pop"="dp05_0001e",
         "pop_moe"="dp05_0001m")%>%
  select(sub_id, pop, pop_moe)%>%
  as.data.frame()

ind_df <- ind_df %>% 
  left_join(total_pop, by = c())%>%
  mutate(raw = ifelse(is.na(raw), 0, raw), 
         pop_cv=pop_moe/1.645/pop*100,
         rate_1k = (raw/pop)*1000)

# Step 4: Calculate percentiles -----------

# Add percentile rank on the rate column

ind_df<-ind_df%>%
  mutate(pctile=percent_rank(rate_1k))


# Finalize and send to postgres-----------------------

# clean up column names and column order
df<-ind_df%>%
  select(sub_id, raw, pop, pop_moe, pop_cv, rate_1k, pctile)%>%
  rename("geoid"="sub_id",
         transitinj_count=raw,
         transitinj_1k_rate=rate_1k,
         transitinj_pctile=pctile)%>%
  st_drop_geometry()

# set column types
charvect = rep("numeric", ncol(df)) 
charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector
names(charvect) <- colnames(df)

# push to postgres
# dbWriteTable(con,  "rates_transitinjury", df,
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data
table_comment <- paste0("COMMENT ON TABLE rates_transitinjury  IS 'Rate of transit injuries in LA City by zipcode for 
2018-2022 (pooled) for entire population. Rates are per 1k total population. Transit injuries filtered for 
pedestrian/bicyclists killed or severely injured.  
Original data from UC Berkeley TIMS portal. 
R script: W:\\Project\\ECI\\MLAW\\R\\rates_transitinjury.R
QA document: 
WW:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_transitinjury.docx';

COMMENT ON COLUMN rates_transitinjury.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_transitinjury.transitinj_count IS 'Total transit injuries in zipcode, 
defined as pedestrian/bicyclists killed or severely injured';
COMMENT ON COLUMN rates_transitinjury.pop IS 'Zcta population from DP05';
COMMENT ON COLUMN rates_transitinjury.pop_moe IS 'Zcta population moe from DP05';
COMMENT ON COLUMN rates_transitinjury.pop_cv IS 'Zcta population cv';
COMMENT ON COLUMN rates_transitinjury.transitinj_1k_rate IS 'Rate of transit injuries per 1k total population using original zcta population number';
COMMENT ON COLUMN rates_transitinjury.transitinj_pctile IS 'Percentile of transit injury rates that were calculated with original zcta population number';


")

# send table comment + column metadata
# dbSendQuery(conn = con, table_comment)
