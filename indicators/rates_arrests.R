# MLAW LA City Equity Index
# Arrest rates by zip code for LA City


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

###### Population base for arrest data ----
pop<-dbGetQuery(con2, "SELECT geoid, dp05_0001e, dp05_0001m FROM demographics.acs_5yr_dp05_multigeo_2022 
                WHERE geolevel='zcta'")

###### Arrest data for LA City including reporting districts -----
arrests<-dbGetQuery(con2,"select * from crime_and_justice.lapd_arrests_2020_2023")
arrests<-arrests%>%filter(lubridate::year(arrest_date) %in% c(2022))

repdist<-st_read(con2,query="select gid,agency,bureau,aprec,abbrev_apr,prec,repdist,name,geom_3310 from geographies_la.lapd_reporting_districts_2022",geom="geom_3310")


#### Calculate arrests counts at ZIP Code level ####
###### Clean coordinates ----
check<-arrests%>%filter(is.na(lon) | lon==0) # check for na coordinates or missing coordinates

# 14400    ERWIN STREET MALL exists in other stops with coordinates manually update where missing in stops 6333848, 6333879, 6417952
# coordinates are 34.1837, -118.4476
# Mcadden and Santa Monica manually update coordinates to @34.090711,-118.3400335 based on google maps
# clean up missing coordinates
arrests_df <- arrests%>% mutate(lat = ifelse(report_id %in% c("6333848","6333879","6417952"), 34.1837, lat),
                                lon = ifelse(report_id %in% c("6333848","6333879","6417952"), -118.4476, lon))%>%
  mutate(lat = ifelse(report_id %in% c("6310233"), 34.090711, lat),
         lon = ifelse(report_id %in% c("6310233"), -118.3400335, lon))%>%
  select(report_id,report_type,arrest_date,area_id,area_name, reporting_district,lon,lat)

arrests_sf <- st_as_sf(x = arrests_df, 
                       coords = c("lon", "lat"), 
                       crs = "EPSG:4326")

###### Point to polygon join ----
# transform to 3310
arrests_sf <- st_transform(arrests_sf, crs = 3310)

# join to ZIP Codes based on point in polygon
arrests_zips <- arrests_sf %>% st_join(zips)
sum(is.na(arrests_zips$zipcode)) #569 stops don't join, use reporting district for these

# point to polygon join result
arrests_zips_point <- arrests_sf %>% st_join(zips)%>%filter(!is.na(zipcode))%>%st_drop_geometry%>%select(-gid,-prc_zip_area,-city)

###### Polygon to polygon join ----
# arrests that need a polygon to polygon join
arrests_zips_rep <- arrests_sf %>% st_join(zips)%>%filter(is.na(zipcode))%>%select(-zipcode,-city,-prc_zip_area,-gid)%>%st_drop_geometry

# calculate rep distict area
repdist$area<-st_area(repdist)

# intersect with zips
repdist_zip_intersect<-st_intersection(repdist,zips)

# calculate prc overlap
repdist_zip_intersect$intersect_area<-st_area(repdist_zip_intersect)
repdist_zip_intersect$prc_area<-repdist_zip_intersect$intersect_area/repdist_zip_intersect$area

# reporting districts are pretty small so keep with highest ranked intersect
repdist_zip_join<-repdist_zip_intersect %>% mutate(rank=prc_area)%>%group_by(name) %>% top_n(1, rank)

# drop those that barely intersect
repdist_zip_join<-repdist_zip_join%>%filter(as.numeric(prc_area)>.20)

# join rep district to zip code join to the arrests missing zip codes after the point to poly join
arrests_zips_rep<-arrests_zips_rep%>%
  left_join(repdist_zip_join%>%
              select(name,zipcode,prc_area),by=c("reporting_district"="name"))%>%
  st_drop_geometry%>%
  select(-geom_3310,-prc_area)

# check NAs
na<-arrests_zips_rep%>%filter(is.na(zipcode))%>%group_by(reporting_district)%>%summarise(count=n())
# looking at top frequency ones
# 1944 is mainly san fernando area--we could add back in that zip code if we want
# 0459 and 0469 are in boyle heights so on the edge of LA City--might want to expand ZIP Codes to 20% again
# 1465 is a portion of Ladera
sum(na$count) # 242 out of 61,872 arrests don't join. Okay with that rate though want to make sure some parts of the city aren't being ommitted

# calculate counts per zipcode
arrests_zips<-rbind(arrests_zips_rep,arrests_zips_point)

arrests_zips<-arrests_zips%>%group_by(zipcode)%>%summarise(count=n())

# Rate calc: # arrests per 1K in zipcode---------------------
df<-arrests_zips%>%left_join(pop,by=c("zipcode"="geoid"))
# 90095 is UCLA consider dropping from xwalk and 90090 is dodger stadium, but for now make sure to omit from ranks

# join to crosswalk to make sure we scale population to the part of the ZIP in LA City
df<-df%>%left_join(zips%>%st_drop_geometry%>%select(zipcode,prc_zip_area)  )

df_final<-df%>%rename(pop=dp05_0001e,arrest_count=count)%>%
  mutate(scaled_pop=pop*prc_zip_area,
         arrest_rate=arrest_count/scaled_pop*1000,
         pop_cv=dp05_0001m/1.645/pop*100)%>% # doesn't work to scale down a cv, but pop cv's are stable anyways
  select(zipcode,arrest_rate,arrest_count,scaled_pop,pop,pop_cv)
# 90071 and 90021 have really high rates, these are in downtown, could be because of location and any events that happened in the area, leave for now since percentile method will reduce the impact of the outlier

# change inf to NA
df_final[sapply(df_final, is.infinite)] <- NA

# Calculate percentiles---------------------

df_final<-df_final%>%
  filter(!is.na(zipcode))%>%
  mutate(pctile=percent_rank(arrest_rate))%>%
  rename("geoid"="zipcode")


# Finalize table and push to postgres -------------------

# set column types
charvect = rep("numeric", ncol(df_final)) 
charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector
names(charvect) <- colnames(df_final)

# push to postgres
# dbWriteTable(con,  "rates_arrests", df_final,
#              overwrite = FALSE, row.names = FALSE,
#              field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_arrests  IS 'Rate of arrests in LA City made by LAPD by zipcode for 2022 for entire population. Population in each ZIP Code scaled to the % intersect with LA City. Original data from LAPD arrest data posted on the city open data portal. Arrests joined to ZIP Codes by lat and lon and secondly by reporting district, some arrests do not join, representing less than 1% of arrests
R script: W:\\Project\\ECI\\MLAW\\R\\rates_arrests.R
QA document: 
WW:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_arrests.docx';

COMMENT ON COLUMN rates_arrests.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_arrests.arrest_rate IS 'Rate of arrests in the ZIP Code per 1K people';
COMMENT ON COLUMN rates_arrests.arrest_count IS 'Total number of arrests in the ZIP Code by LAPD in 2022';
COMMENT ON COLUMN rates_arrests.pop IS 'Total population in the ZIP Code';
COMMENT ON COLUMN rates_arrests.pop_cv IS 'Population cv in percent';
COMMENT ON COLUMN rates_arrests.pctile IS 'Percent rank of the estimate -rate';

")

# send table comment + column metadata
# dbSendQuery(conn = con, table_comment)

