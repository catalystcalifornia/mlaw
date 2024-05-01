# MLAW LA City Equity Index
# Impervious land percentage by ZIP Code in LA City
# Data Source: National Land Cover Database 2021
# Link: https://www.usgs.gov/centers/eros/science/national-land-cover-database
# Average/median impervious land cover by ZIP Code calculated in ArcGIS using Zonal Statistics tool


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

###### Impervious land cover data  -----
# ZIP Code level data generated from raster data from the national land cover database
# https://www.mrlc.gov/data?f%5B0%5D=category%3AUrban%20Imperviousness
impervious <- st_read(con, query="SELECT * FROM nlcd_zipcode_imperviousland_2021")
# median column is the indicator

######### Double check data at ZIP Code level comparing to CT estimates from prior project ---------
# land cover at census tract level generated for Bold Vision report
impervious_ct <- read.table("W:\\Data\\Built Environment\\NationalLandCoverDatabase\\2021\\nlcd_census_tract_pct_impervious_2021.txt", header = TRUE, sep = ",")

# 2021 la county tracts from census api
library(tigris)
la_county_tracts <- tracts(state = "CA", county = "Los Angeles", cb = TRUE, year = 2021)

# join ct shapes to impervious surfaces ct data
impervious_shp<-la_county_tracts%>%left_join(impervious_ct%>%mutate(GEOID=paste0("0",GEOID)))

# map tract level estimates
library(leaflet)

# create a color palette for the map
mypalette <- colorNumeric(palette="YlOrRd",domain=impervious_shp$MEDIAN,
  na.color = "transparent")

# map the data
leaflet(impervious_shp) %>%
  addTiles() %>%
  addPolygons(
    stroke = FALSE, fillOpacity = 0.5,
    smoothFactor = 0.5,  fillColor = ~ mypalette(MEDIAN),
  )%>%
  addLegend(
    pal = mypalette, values = ~MEDIAN, opacity = 0.9,
   position = "bottomleft"
  )

# check la county ZIPs estimates
lac_zips <- st_read(con2, query="SELECT * FROM geographies_la.lacounty_zipcodes_2022")%>%st_make_valid()%>%
  group_by(zipcode)%>% # la county ZIP Codes shapefile clean up for unique records, removing multipolygons
  summarise()

# join zip shapes to zip impervious data
impervious_shp_zip<-lac_zips%>%left_join(impervious%>%mutate(median=as.numeric(median)))

# create a color palette for the map
mypalettez <- colorNumeric(palette="YlOrRd",domain=impervious_shp_zip$median,
                          na.color = "transparent")

# map the data
leaflet(impervious_shp_zip) %>%
  addTiles() %>%
  addPolygons(
    stroke = FALSE, fillOpacity = 0.5,
    smoothFactor = 0.5,  fillColor = ~ mypalette(median),
  )%>%
  addLegend(
    pal = mypalettez, values = ~median, opacity = 0.9,
    position = "bottomleft"
  )
# maps are comparable, some detail is lost in SFV and AV and in the eastern areas of LAC due to ZIP Code level

#### Calculate percentiles at ZIP Code level for LA City ####
###### filter for LA City ----
df<-impervious%>%filter(zipcode %in% la_zips)%>%
  mutate(imperv_median_rate=as.numeric(median))%>%
  select(zipcode,imperv_median_rate)

###### percentile rank ----
df_final<-df%>%
  mutate(imperv_pctile=percent_rank(imperv_median_rate))%>%
  rename("geoid"="zipcode")


# Finalize table and push to postgres -------------------
# set column types
charvect = rep("numeric", ncol(df_final)) 
charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector
names(charvect) <- colnames(df_final)

# push to postgres
# dbWriteTable(con,  "rates_imperviousland", df_final,
#              overwrite = FALSE, row.names = FALSE,
#              field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_imperviousland  IS 
'Average, or median, impervious land cover by ZIP Code in LA City
Generated from raster data from the national land cover data. 
Impervious surfaces defined as surfaces that dont allow water to seep into the ground, mainly asphalt and concrete.
These surfaces contribute to heat in urban areas and cause heat stress in warm seasons. It also means water flows into a story drain or nearby body of water picking up pollutants in the process.
R script: W:\\Project\\ECI\\MLAW\\R\\rates_imperviousland.R
QA document:
WW:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_impervious_land.docx';

COMMENT ON COLUMN rates_imperviousland.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_imperviousland.imperv_median_rate IS 'Percent impervious land cover for the ZIP Code';
COMMENT ON COLUMN rates_imperviousland.imperv_pctile IS 'Percentile rank of impervious land cover based on the rate';
")

# send table comment + column metadata
# dbSendQuery(conn = con, table_comment)

