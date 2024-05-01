# ZIP Code to LA City crosswalk
# Create a list of ZIP codes that are mainly in LA City for LA City Equity Index
# Source for ZIP Code shapes: https://geohub.lacity.org/datasets/70748ba37ecc418891e052e800437681_5/about
# Downloaded ZIP Code file in February 2022, but most data are all from 2022 or earlier sources
# Source for LA City Boundary: https://catalog.data.gov/dataset/city-boundary-of-los-angeles
# Downloaded in July 2023

##### Environment set up #####
library(dplyr)  
library(RPostgreSQL) 
library(rpostgis) 
library(leaflet)
library(sf)
library(formattable)
library(tidyverse)
library(htmltools)
options(scipen=999)
source("W:\\RDA Team\\R\\credentials_source.R")

con <- connect_to_db("rda_shared_data")
con2 <- connect_to_db("eci_mlaw")

##### Import geos #####
# import zip codes and ensure crs and shape validity
zip_codes <- st_read(con, query = "select * from geographies_la.lacounty_zipcodes_2022")
zip_codes <- st_transform(zip_codes, crs = 3310)
length(unique(zip_codes$zipcode)) # check for multi polygons, there are a few
# get rid of them
zip_codes_lac<-zip_codes%>%group_by(zipcode)%>%summarise()
# 312 unique ZIPS

# download city boundary
lacity <- st_read(con, query = "select gid, city,objectid,geom_3310 from  geographies_la.lacity_boundary_2021", geom="geom_3310")
lacity <- st_transform(lacity, crs = 3310) 

# calculate area of zip_codes 
zip_codes_lac$zip_area <- st_area(zip_codes_lac)

# import population data for reference
pop<-dbGetQuery(con, "SELECT geoid, dp05_0001e, dp05_0001m FROM demographics.acs_5yr_dp05_multigeo_2022 
                WHERE geolevel='zcta'")

##### Intersect geographies #####

# intersect zips and la city
intersects <- st_intersection(zip_codes_lac, lacity)

# calculate area of the intersect
intersects$intersect_area <- st_area(intersects)

# calculate percent of intersect out of total zip area
intersects$prc_zip_area <- as.numeric(intersects$intersect_area/intersects$zip_area)
min(intersects$prc_zip_area)

##### Identify threshold for inclusion in crosswalk #####
# test out different thresholds, everything that intersects to start
# qa<-zip_codes_lac%>%left_join(intersects%>%st_drop_geometry)%>%filter(prc_zip_area>0)
# 
# qa<-st_transform(qa,4326)
# 
# lacity<-st_transform(lacity,4326)
# 
# leaflet() %>% 
#   addTiles()%>%
#   addPolygons(data=qa, smoothFactor = 0.2, fillOpacity = 1, fillColor="white",
#               color = "black", popup=htmlEscape(paste0(qa$zipcode, ",",qa$prc_zip_area)))%>%
#   addPolygons(data=lacity, smoothFactor = 0.2, fillOpacity = .2, fillColor="white",
#               color = "red")
# # some ZIP Codes in north that branch out and others that share small slivers
# 
# # start with 20% intersect
# qa_20<-zip_codes_lac%>%left_join(intersects%>%st_drop_geometry)%>%filter(prc_zip_area>.20)
# 
# qa_20<-st_transform(qa_20,4326)
# 
# lacity<-st_transform(lacity,4326)
# 
# leaflet() %>% 
#   addTiles()%>%
#   addPolygons(data=qa_20, smoothFactor = 0.2, fillOpacity = 1, fillColor="white",
#               color = "black", popup=htmlEscape(paste0(qa_20$zipcode, ",",qa_20$prc_zip_area)))%>%
#   addPolygons(data=lacity, smoothFactor = 0.2, fillOpacity = .2, fillColor="white",
#               color = "red")
# 
# # looks good though la tujunga drops, considering add back in 91042 manually given majority of ZIP Code outside of LA doesn't have a population
# 
# # increase to 25%
# qa_25<-zip_codes_lac%>%left_join(intersects%>%st_drop_geometry)%>%filter(prc_zip_area>.25)
# 
# qa_25<-st_transform(qa_25,4326)
# 
# lacity<-st_transform(lacity,4326)
# 
# leaflet() %>% 
#   addTiles()%>%
#   addPolygons(data=qa_25, smoothFactor = 0.2, fillOpacity = 1, fillColor="white",
#               color = "black", popup=htmlEscape(paste0(qa_25$zipcode, ",",qa_25$prc_zip_area)))%>%
#   addPolygons(data=lacity, smoothFactor = 0.2, fillOpacity = .2, fillColor="white",
#               color = "red")

# looks good, drops culver city which is good and part of santa monica, add back in 91042, and omit 91340 that is mostly city of san fernando


##### Final export ####
df<- intersects%>%st_drop_geometry%>%filter(prc_zip_area>=.25 & zipcode!='91340'| zipcode=='91042')%>%
  left_join(pop,by=c("zipcode"="geoid"))
# 90095 has 0 population, 90090 has null population

# filter out ZIP Code with 0 population which is UCLA and other university ZIP Codes
# 90089 USC # 91330 CSUN # 90090 dodger stadium (drops from null population)
df<-df%>%filter(!is.na(dp05_0001e) & !zipcode %in% c("90095","90089","91330"))
df<-zip_codes_lac%>%right_join(df)

# format crosswalk
df <- df %>% select(zipcode, city, prc_zip_area) %>%
  mutate(city="City of Los Angeles")

df$gid <- 1:nrow(df)

# send to postgres
table_name <- "crosswalk_zip_city_2022"
schema <- 'data'

indicator <- "Crosswalk of LA County ZIP codes (2022) and LA City boundary (2021) where zip codes have at least a 25% overlap with the city. ZIP Code 91042 - La Tujunga is manually added and ZIP Code 91340 - City of San Fernando is manually dropped"
source <- "ZIP Codes from LA County open data portal. Original ZIP Code table from geographies_la.lacounty_zipcodes_2022. See QA doc for details: W:\\Project\\ECI\\MLAW\\Documentation\\QA_zip_city_xwalk.doc"

# dbWriteTable(con2, c(schema, table_name), df,
#              overwrite = TRUE, row.names = FALSE)

#comment on table and columns
comment <- paste0("COMMENT ON TABLE ", schema, ".", table_name,  " IS '", indicator, " from ", source, ".';
                                          COMMENT ON COLUMN ", schema, ".", table_name, ".zipcode IS 'ZIP code number';
                   COMMENT ON COLUMN ", schema, ".", table_name, ".city IS 'City name';
                   COMMENT ON COLUMN ", schema, ".", table_name, ".prc_zip_area IS 'Percent of ZIP code area in LA City';
                                      COMMENT ON COLUMN ", schema, ".", table_name, ".geom IS 'Geom in 3310 for whole ZIP Code--not just ZIP Code part';

                   ")
# print(comment)
# dbSendQuery(con2, comment)

#disconnect
dbDisconnect(con2)
dbDisconnect(con)
