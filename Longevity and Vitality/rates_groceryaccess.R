# MLAW LA City Equity Index
# Supermarket and farmers market access by zip code for LA City
# Using SNAP Retailer database - supermarkets, super stores, and farmers markets
# Data source link: https://usda-snap-retailers-usda-fns.hub.arcgis.com/datasets/8b260f9a10b0459aa441ad8588c2251c_0/about
# Method: enhanced two-step floating catchment area supply/demand ratio
# accessibility of block groups with ZIP Codes to grocery stores based on supply and demand ratio at .5 mile, 1 mile, and 3 miles
# Population weighted block group centroids - https://www.census.gov/geographies/reference-files/time-series/geo/centers-population.html

##### Set Up Workspace #####
library(dplyr)
library(RPostgreSQL)
library(tidyr)
library(stringr)
library(sf)
library(mapview)
library(data.table)
options(scipen=999)

# Connect to postgres

source("W:\\RDA Team\\R\\credentials_source.R")

con <- connect_to_db("eci_mlaw")
con2<-connect_to_db("rda_shared_data")

#### Read in data ####
###### ZIP codes in LA City ----
# Final ZIP Codes for percentile rates
zips<-st_read(con, query="SELECT * FROM crosswalk_zip_city_2022") #LA City zips

# create vector of la city zipcodes for filtering later:
la_zips<-zips$zipcode

###### Grocery and food establishments -----
# testing different data sources for grocery stores, SNAP appears most reliable
###### SNAP Retailers  -----
# downloaded from: https://usda-snap-retailers-usda-fns.hub.arcgis.com/datasets/8b260f9a10b0459aa441ad8588c2251c_0/about
snap <- st_read("W:\\Project\\ECI\\MLAW\\Data\\Grocery Access\\SNAP Retailers\\SNAP_Retailer_Location_data\\SNAP_Retailer_Location_data.shp")

# clean up column names
names(snap) <- tolower(names(snap)) 

# narrow to LA County
snap<-snap%>%filter(county=="LOS ANGELES")

# look at store types
table(snap$store_type)

# explore other store type
# qa<-snap%>%filter(store_type=="Other")%>%group_by(store_name)%>%summarise(count=n())
# some specialty or ethnic markets, many are dollar tree, csv, etc. filter out dollar stores and pharmacies
# exclude these
# documentation from USDA Food Research Atlas
# https://www.ers.usda.gov/webdocs/publications/42711/12712_ap036l_1_.pdf?v=0
# supermarkets are mainly classified for industry supermarkets

# explore specialty
qa<-snap%>%filter(store_type=="Specialty Store")%>%group_by(store_name)%>%summarise(count=n())
# some ethnic markets, other fruits/veggies/meat markets

# explore grocery store
qa<-snap%>%filter(store_type=="Grocery Store")%>%group_by(store_name)%>%summarise(count=n())
# some are many mini marts

# explore super store
qa<-snap%>%filter(store_type=="Super Store")%>%group_by(store_name)%>%summarise(count=n())
# while usda excluded super stores, some are now larger grocery stores, like ralphs or food 4 less, opt to include here

# map each type
qa<-snap%>%filter(store_type=="Specialty Store")
mapview(qa)

qa<-snap%>%filter(store_type=="Grocery Store")
mapview(qa)

qa<-snap%>%filter(store_type=="Supermarket")
mapview(qa)

qa<-snap%>%filter(store_type=="Super Store")
mapview(qa)

# decided for super store and supermarket to match more traditional industry stores that could meet demand for groceries (vs. small corner stores)
# research on poor food access at smaller grocery stores
# https://www.ers.usda.gov/amber-waves/2018/march/distance-to-grocery-stores-and-vehicle-access-influence-food-spending-by-low-income-households-at-convenience-stores/

# narrow list to desired stores
snap_grocery<-snap%>%
  filter(store_type %in% c("Super Store","Supermarket","Farmers and Markets"))%>%
  filter(!grepl("Liquor",store_name)) # exclude any liquor stores that pass through

snap_grocery<-st_transform(snap_grocery,3310)

######  Farmers Markets -----
# downloaded from: https://data.lacounty.gov/datasets/c25921094a7d40e48302ad3a92fbed90_40/explore?location=33.937820%2C-118.157671%2C8.00
farmers_markets <- st_read("W:\\Project\\ECI\\MLAW\\Data\\Grocery Access\\Farmers Markets\\Farmers_Markets\\Farmers_Markets.shp")

# clean up column names
names(farmers_markets) <- tolower(names(farmers_markets)) 

farmers_markets<-st_transform(farmers_markets,3310)

# check against SNAP retailers to see if similar list
snap_farmers<-snap_grocery%>%filter(store_type=="Farmers and Markets")

# comparing names and addresses they are mostly the same
library(mapview)
mapview(snap_farmers)+mapview(farmers_markets,col.regions="black")
# slightly different locations
# will go for snap farmers markets since it's more recently updated


###### Active Businesses -----
# explore feasibility of using active businesses list from LA City
# downloaded from: https://data.lacity.org/Administration-Finance/Listing-of-Active-Businesses/6rrh-rzua/about_data
businesses <- read.csv("W:\\Project\\ECI\\MLAW\\Data\\Grocery Access\\LA Active Businesses\\Listing_of_Active_Businesses_20240422.csv")
businesses$NAICS<-as.character(businesses$NAICS)

names(businesses) <- tolower(names(businesses)) 
library(janitor)
businesses<-businesses%>%clean_names()

# 445100 # grocery
# 445230 # fruit and vegetable
naics_codes<-list("445100","445230")

businesess_grocery<-businesses%>%filter(naics %in% naics_codes)
# reviewing business names, inclined to use SNAP first

# map coordinates
# separate coordinates
businesess_grocery <- separate(businesess_grocery, location, into = c("lat", "long"), sep = ",")
businesess_grocery$long <- gsub("\\)", "", businesess_grocery$long)
businesess_grocery$lat <- gsub("\\(", "", businesess_grocery$lat)
businesses_grocery_sf <-businesess_grocery%>%filter(!is.na(long))
businesses_grocery_sf <- st_as_sf(x = businesses_grocery_sf, 
                       coords = c("long","lat"), 
                       crs = "EPSG:4326")

mapview(businesses_grocery_sf)
# seems to include a lot of corner/convenience stores and even some outside of LAC
# opt for snap database


#### Calculate grocery access indicator using the enhanced two-step floating catchment area method (E2SFCA) ----
# Reference: https://ij-healthgeographics.biomedcentral.com/articles/10.1186/s12942-017-0105-9

###### Load and prep blog group data -----
# get bg polygons in LA County for first step - ratio of provider to demand/inhabitants within catchment area
library(tigris)
la_county_bgs <- block_groups(state = "CA", county = "Los Angeles", cb = TRUE, year = 2020) # shapes for first step block group boundaries in LA County
names(la_county_bgs) <- tolower(names(la_county_bgs)) 


# get blog group weighted population centroids for 2nd step - supply locations within X distance from bg centroid
blog_centroids<-fread("https://www2.census.gov/geo/docs/reference/cenpop2020/blkgrp/CenPop2020_Mean_BG06.txt",data.table=F)

# clean data frame names and fields for joining later
names(blog_centroids) <- tolower(names(blog_centroids)) 

blog_centroids<-blog_centroids%>%
  mutate(countyfp=str_pad(countyfp,3,pad="0"),
         geoid=paste0("0",statefp,countyfp,tractce,blkgrpce)) # get long geoid to match to block group shapes

# filter for LA County
blog_centroids<-blog_centroids%>%filter(countyfp=="037")

# Join total population to bgs shapes
bg_polys_pop<-la_county_bgs%>%
  left_join(blog_centroids%>%select(geoid,population),by=c("geoid"="geoid"))

bg_polys_pop<-st_transform(bg_polys_pop,3310) # transform for spatial analysis

###### Step 1: Calculate the supply-to-demand ratio for each market ------
# We will calculate the population within 3 zones of each market, using buffers of 0-.5 miles, .5-1 miles, 1-3 miles
# employ a fast-step decay function of 1.00, 0.42 and 0.09

# references for buffers
# walkability of .5 mile from USDA 
# https://www.ers.usda.gov/webdocs/publications/42711/12712_ap036l_1_.pdf?v=0
# https://www.ers.usda.gov/amber-waves/2018/march/distance-to-grocery-stores-and-vehicle-access-influence-food-spending-by-low-income-households-at-convenience-stores/
# 1 mile threshold used for food access research atlas
# https://link.springer.com/article/10.1007/s12571-023-01381-5
# buffers of 1-2 miles cover 55-65% of visited food establishments
# https://www.cdc.gov/pcd/issues/2015/15_0065.htm
# shorter distances to groceries and supermarkets and mean to food establishments was 2.6 miles
# mean supermarket was 2.5 miles away in King County study
# https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3464835/

# transform spatial data frames
st_crs(snap_grocery) # right system
st_crs(bg_polys_pop)

# calculate area of block groups for allocating population to supermarket points and prep block groups with population matched
bg_polys_pop$bg_area<-st_area(bg_polys_pop) 
bg_polys_pop<-bg_polys_pop%>%select(geoid,population,bg_area)%>%mutate(population=as.numeric(population))

# Create buffers around each supermarket at 0-.5 miles, .5-1 miles, 1-3 miles
## FIRST BUFFER - 0.5 miles in meters: 804.672 
## 3310 uses meters
buffer_snap_1 <- st_buffer(snap_grocery, 804.672) # .5 mile buffer around each supermarket
snap_blocks_1 <-st_intersection(buffer_snap_1, bg_polys_pop) # intersection of buffers and block groups to get population in each buffer
snap_blocks_1$intersect_area <- st_area(snap_blocks_1) # what is the area of the intersection to allocate population
snap_blocks_1$prc_bg_area <- as.numeric(snap_blocks_1$intersect_area/snap_blocks_1$bg_area)
snap_pop_1<-snap_blocks_1%>%
  mutate(prc_bg_area=ifelse(prc_bg_area>=1,1,prc_bg_area))%>% # keep all of the block if all of the block is in the intersect
  group_by(record_id,store_name)%>% # get the population within a .5 mile of each store
  summarise(pop_1mi=sum(prc_bg_area*population))%>% # scale population of the block groups intersecting store buffers by the percent of block group in the intersect
  as.data.frame()%>%
  select(-geometry)

## SECOND BUFFER - 1 miles in meters: 1609.34
buffer_snap_2 <- st_buffer(snap_grocery, 1609.34)
snap_blocks_2 <-st_intersection(buffer_snap_2, bg_polys_pop)
snap_blocks_2$intersect_area <- st_area(snap_blocks_2)
snap_blocks_2$prc_bg_area <- as.numeric(snap_blocks_2$intersect_area/snap_blocks_2$bg_area)
snap_pop_2<-snap_blocks_2%>%
  mutate(prc_bg_area=ifelse(prc_bg_area>=1,1,prc_bg_area))%>%
  group_by(record_id,store_name)%>%
  summarise(pop_2mi=sum(prc_bg_area*population))%>%
  as.data.frame()%>%
  select(-geometry)

## THIRD BUFFER - 3 miles in meters: 4828.03
buffer_snap_3 <- st_buffer(snap_grocery, 4828.03)
snap_blocks_3 <-st_intersection(buffer_snap_3, bg_polys_pop)
snap_blocks_3$intersect_area <- st_area(snap_blocks_3)
snap_blocks_3$prc_bg_area <- as.numeric(snap_blocks_3$intersect_area/snap_blocks_3$bg_area)
snap_pop_3<-snap_blocks_3%>%
  mutate(prc_bg_area=ifelse(prc_bg_area>=1,1,prc_bg_area))%>%
  group_by(record_id,store_name)%>%
  summarise(pop_3mi=sum(prc_bg_area*population))%>%
  as.data.frame()%>%
  select(-geometry)


###### Step 1 FINAL CALC: Calculate the ratio per 1000 habitants -----
# employ a fast-step decay function of 1.00 @ .5 miles, 0.42 @ 1 mile and 0.09 @ 3 miles
# join all the buffer data frames together that have the population in each radious from each supermarket
step1<-snap_grocery%>%left_join(snap_pop_1)%>%left_join(snap_pop_2)%>%left_join(snap_pop_3)

# calculate the total population within the radii and the first ratio
# because the buffers are concentric, we need to subtract the prior buffer from each subsequent buffer to not double count the population in each radii
step1<-step1%>%
  mutate(pop_total=pop_1mi*1+(pop_2mi-pop_1mi)*.42+(pop_3mi-pop_2mi)*.09,
         r_final=1/((pop_1mi/1000*1+(pop_2mi-pop_1mi)/1000*.42+(pop_3mi-pop_2mi)/1000*.09))) # r final is what is used to calculate final access scores


###### Step 2 Calculate the supply-to-demand ratio for each market by joining initial ratios to block group centroids ------
# clean population weighted centroids and prep for spatial analysis
bg_centroids_geom<-st_as_sf(blog_centroids, coords=c("longitude","latitude"),crs=4326,agr="identity")
bg_centroids_geom<-st_transform(bg_centroids_geom, crs=3310)

# Create buffers around each block group centroid @ .5mi, 1mi, 2mi
## FIRST BUFFER -- .5 miles in meters: 804.672
##  join supermarkets to block group centroids when they are within .5 miles of population-weighted centroid
blocks_snap_1<-st_join(bg_centroids_geom,step1,join=st_is_within_distance,dist=804.672)
blocks_supply_1<-blocks_snap_1%>%group_by(geoid)%>% # group by block group centroid to get the sum of the initial ratios of each supermarket within .5 miles
  summarise(snap_count_1=sum(!is.na(store_name)),
            pop_total_1=sum(pop_total,na.rm=TRUE),
            r_1_final=sum(r_final,na.rm=TRUE))%>% # this is the sum of the initial ratio for all supermarkets within .5 miles
  as.data.frame()%>%
  select(-geometry)

## SECOND BUFFER -- 1 miles in meters: 1609.34
blocks_snap_2<-st_join(bg_centroids_geom,step1,join=st_is_within_distance,dist=1609.34)
blocks_supply_2<-blocks_snap_2%>%group_by(geoid)%>%
  summarise(snap_count_2=sum(!is.na(store_name)),
            pop_total_2=sum(pop_total,na.rm=TRUE),
            r_2_final=sum(r_final,na.rm=TRUE))%>%
  as.data.frame()%>%
  select(-geometry)

## THIRD BUFFER -- 3 miles in meters: 4828.032
blocks_snap_3<-st_join(bg_centroids_geom,step1,join=st_is_within_distance,dist=4828.032)
blocks_supply_3<-blocks_snap_3%>%group_by(geoid)%>%
  summarise(snap_count_3=sum(!is.na(store_name)),
            pop_total_3=sum(pop_total,na.rm=TRUE),
            r_3_final=sum(r_final,na.rm=TRUE))%>%
  as.data.frame()%>%
  select(-geometry)


###### Step 2 FINAL CALC: Calculate the final accessibility ratio ----
# employ a fast-step decay function of 1.00 @ .5, 0.42 @ 1 and 0.09 @ 3
# join together all the summed initial ratios at each buffer zone
step2<-bg_centroids_geom%>%left_join(blocks_supply_1)%>%left_join(blocks_supply_2)%>%left_join(blocks_supply_3)

step2<-step2%>%
  mutate(snap_count=snap_count_3, # total stores within a 3 mile buffer
         a_pop_sum=pop_total_1*1+(pop_total_2-pop_total_1)*.42+(pop_total_3-pop_total_2)*.09, # adjusted population/demand not necessary for calc
         a_final=r_1_final*1+(r_2_final-r_1_final)*.42+(r_3_final-r_2_final)*.09) # final access score which is the sum of the initial ratios for all supermarkets at each buffer zone

###### TEST Convert access score to percentiles per block group ----
# map block group results to see how it performed for LA County
indicator_df<-step2 %>% 
  mutate(indicator_final=percent_rank(a_final)*100) # percent rank by block group

# join to block group shapes for mapping
indicator_df<-indicator_df%>%st_drop_geometry()
bg_access<-bg_polys_pop%>%
  left_join(indicator_df%>%select(geoid,indicator_final,a_final))%>%
  rename(access_ptile=indicator_final,
         access_score=a_final)

######## Export to bg values postgres and shapefile ########

# set column types
charvect = rep("numeric", ncol(bg_access)) 
charvect <- replace(charvect, c(1), c("varchar"))
charvect <- replace(charvect, c(6), c("geometry"))

# add df colnames to the character vector
names(charvect) <- colnames(bg_access)

# push to postgres
# dbWriteTable(con,  "groceryaccess_blockgrp_scores", bg_access,
#              overwrite = FALSE, row.names = FALSE,
#              field.types = charvect)

# add meta data
table_comment <- paste0("COMMENT ON TABLE groceryaccess_blockgrp_scores  IS 'Block group level grocery store access accessibility scores used to calculate ZIP Code level access
Higher percentile and a higher accessibility scores indicates higher access measured based on enhanced two-step floating catchment area
Grocery access is measured at the block group level where supply-demand ratios for grocery stores are provided to block groups based on population weighted centroids
buffers of .5 miles, 1 mile, and 3 miles are used. Accounts for population likely accessing each supermarket and then sums the demand for each supermarket for each block group
R script:W:/Project/ECI/MLAW/R/rates_groceryaccess.R
QA document:
W:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_groceryaccess.docx';

COMMENT ON COLUMN groceryaccess_blockgrp_scores.geoid IS 'block group geoid';
COMMENT ON COLUMN groceryaccess_blockgrp_scores.population IS 'block group population';
COMMENT ON COLUMN groceryaccess_blockgrp_scores.bg_area IS 'block group area';
COMMENT ON COLUMN groceryaccess_blockgrp_scores.access_ptile IS 'Percentile rank of block group accessibility scores where a higher percentile means higher access';
COMMENT ON COLUMN groceryaccess_blockgrp_scores.access_score IS 'Block group accessibility score where higher scores indicators higher access to grocery stores';
                                           ")

# send table comment + column metadata
dbSendQuery(con = con, table_comment)

# write to shapefile
st_write(bg_access, "W:/Project/ECI/MLAW/Shapefiles/groceryaccess_blockgrp_scores.shp")
         
# transform for map
bg_access<-st_transform(bg_access,4326)

library(leaflet)
# create a color palette for the map
mypalettez <- colorNumeric(palette="YlOrRd",domain=bg_access$indicator_final,
                           na.color = "transparent")

# map the data
leaflet(bg_access) %>%
  addTiles() %>%
  addPolygons(
    stroke = FALSE, fillOpacity = 0.5,
    smoothFactor = 0.5,  fillColor = ~ mypalettez(indicator_final),
  )%>%
  addLegend(
    pal = mypalettez, values = ~indicator_final, opacity = 0.9,
    position = "bottomleft"
  )
# looks good

##### Calculate ZIP Code Percentiles for LA City ZIPs ----
### Join to ZIP Codes
st_crs(zips) # right geom

# because block groups are so small, we'll match block groups to the ZIP Codes where their population weighted centroids fall
indicator_df<-bg_centroids_geom%>%left_join(indicator_df%>%select(geoid,a_final))

# join to ZIP Codes based on centroid
bgs_zips<-st_join(indicator_df,zips)

# summarise raw access scores by ZIP Code --percentiles will be calculated from these raw access scores
zips_indicator<-bgs_zips%>%
  group_by(zipcode)%>%
  summarise(grocery_access_rate=sum(a_final,na.rm=TRUE))%>%
  filter(!is.na(zipcode))
# there are 103 ZIP Codes represented, 2 are missing 

df_final<-zips%>% # original zip code df
  left_join(zips_indicator%>%st_drop_geometry())%>% # zip code df with the indicator join
  select(zipcode,grocery_access_rate)%>%
  mutate(grocery_access_pctile=percent_rank(grocery_access_rate))
# 90010 and 90071 are missing, looking at these we assume they have low populations and probably have no bg centers, okay to exclude

# map result to test
df_final<-st_transform(df_final,4326)

# create a color palette for the map
mypalettez <- colorNumeric(palette="YlOrRd",domain=df_final$grocery_access_pctile,
                           na.color = "transparent")

# map the data
leaflet(df_final) %>%
  addTiles() %>%
  addPolygons(
    stroke = FALSE, fillOpacity = 0.5,
    smoothFactor = 0.5,  fillColor = ~ mypalettez(grocery_access_pctile),
  )%>%
  addLegend(
    pal = mypalettez, values = ~grocery_access_pctile, opacity = 0.9,
    position = "bottomleft"
  )

# looks good

##### Export to postgres ----
df_final<-df_final%>%st_drop_geometry()
df_final<-df_final%>%rename(geoid=zipcode)

# set column types
charvect = rep("numeric", ncol(df_final)) 
charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector
names(charvect) <- colnames(df_final)

# push to postgres
dbWriteTable(con,  "rates_groceryaccess", df_final,
             overwrite = TRUE, row.names = FALSE,
             field.types = charvect)

# add meta data
table_comment <- paste0("COMMENT ON TABLE rates_groceryaccess  IS 'Grocery store access by ZIP code measured based on enhanced two-step floating catchment area
grocery access is measured first at the block group level where supply-demand ratios for grocery stores are provided to block groups based on population weighted centroids
buffers of .5 miles, 1 mile, and 3 miles are used. Accounts for population likely accessing each supermarket and then sums the demand for each supermarket for each block group
higher access scores indicator more access
R script:W:/Project/ECI/MLAW/R/rates_groceryaccess.R
QA document:
W:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_groceryaccess.docx';

COMMENT ON COLUMN rates_groceryaccess.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_groceryaccess.grocery_access_rate IS 'Sum of accessibility scores for block groups with centroids in the ZIP Code, higher score is higher access';
COMMENT ON COLUMN rates_groceryaccess.grocery_access_pctile IS 'Percentile rank of ZIP Codes sum of accessibility scores rate higher percentile means higher access';
")

# send table comment + column metadata
dbSendQuery(con = con, table_comment)


##### TEST STRAIGHT RATIO METHOD ----
# ECI preferred more exact method with the buffers but showing here
pop_zcta<-dbGetQuery(con2, "SELECT geoid, dp05_0001e, dp05_0001m FROM demographics.acs_5yr_dp05_multigeo_2022 
                WHERE geolevel='zcta'") # using tracts to get more detailed access levels

snap_zips<-st_join(snap_grocery,zips)

# summarise by ZIP Code and calculate rate per 1K and then percent rank
snap_zips_indicator<-zips%>%left_join(snap_zips%>%st_drop_geometry)%>%
  group_by(zipcode)%>%
  summarise(grocery_count=n())

snap_zips_indicator<-snap_zips_indicator%>%
  left_join(pop_zcta,by=c("zipcode"="geoid"))%>%
              mutate(grocery_access_rate=ifelse(is.na(grocery_count),0,grocery_count/dp05_0001e*1000),
                     grocery_access_pctile=percent_rank(grocery_access_rate))

snap_zips_indicator<-st_transform(snap_zips_indicator,4326)

# create a color palette for the map
mypalettez <- colorNumeric(palette="YlOrRd",domain=snap_zips_indicator$grocery_access_pctile,
                           na.color = "transparent")

# map the data
leaflet(snap_zips_indicator) %>%
  addTiles() %>%
  addPolygons(
    stroke = FALSE, fillOpacity = 0.5,
    smoothFactor = 0.5,  fillColor = ~ mypalettez(grocery_access_pctile),
  )%>%
  addLegend(
    pal = mypalettez, values = ~grocery_access_pctile, opacity = 0.9,
    position = "bottomleft"
  )

# enhanced two-step floating catchment area made more sense with how people access grocery stores over straight ZIP Code rate calc