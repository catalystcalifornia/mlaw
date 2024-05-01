# MLAW LA City Equity Index
# Mental Health and Health Care Services per population by LA City ZIP Code
# Geocoding script using Google API to find exact locations of orgs in LA County that do not automatically match to LA City ZIP Code
# This is the second method for matching orgs to ZIP Codes in the city, the first being a ZIP Code name join

library(stringr)
library(tidygeocoder)

# load google API key for Catalyst California
source("W:\\RDA Team\\R\\credentials_source.R")
Sys.setenv(GOOGLEGEOCODE_API_KEY = google_geocoding_lbripa_key)

# connect to databases
mlaw_conn <- connect_to_db("eci_mlaw")
dbDisconnect(mlaw_conn)

# pull orgs to geocoded generated in rates_healthservices script
orgs_sql <- "select ein, name, street, city, state, zip, zipcode from irs_bmf_lac_health_mental_services_togeocode;"
orgs <- dbGetQuery(conn = mlaw_conn, orgs_sql)

# Temporarily filter out PO Box addresses to geocode by ZIP Code point
poboxes <- orgs %>%
  filter(grepl("^po box", street, fixed=FALSE, ignore.case=TRUE)) 
# Temporarily filter out streets of just numbers
incomplete_streets <- orgs %>%
  filter(grepl("^[0-9 //]+$", street, fixed=FALSE))

# EINs to exclude from cleaning steps
eins_exclude <- rbind(poboxes, incomplete_streets)

# create addresses from city, state, zipcode
eins_exclude <- eins_exclude %>%
  mutate(address = paste(city, state, zipcode, sep=", "))

# Filter out the po box and incomplete street addresses
cleanable_orgs <- orgs %>%
  filter(! ein %in% eins_exclude$ein)

cleanable_orgs<-cleanable_orgs%>%
  mutate(street = gsub("(#|-)", "", cleanable_orgs$street),
         street_clean = street)

# # remove street addresses that end with a PO Box
# cleanable_orgs$street_clean <- gsub("po box [0-9]+$", "", cleanable_orgs$street_clean, ignore.case=TRUE, fixed=FALSE)

# remove the last "word" of a street if it contains a number
cleanable_orgs$street_clean <- gsub("(\\w*\\d{1,}\\w*)$", "", cleanable_orgs$street, ignore.case=TRUE, fixed=FALSE) 

# create a regular expression to remove unnecessary address components (e.g., ste, apt, unit, bldg, etc) 
regex_components <- "( ste | suite | apt | spc | unit | pmb | bldg | no | po box | harriman buildi| 3rd floor| 2ND FLOOR  MAILBOX J)[ 0-9a-z]*$"

cleanable_orgs$regex_result <- grepl(regex_components, cleanable_orgs$street, ignore.case = TRUE, fixed=FALSE)
cleanable_orgs$street_clean <- ifelse(cleanable_orgs$regex_result==TRUE, 
                                      gsub(regex_components, "", cleanable_orgs$street, ignore.case = TRUE, fixed=FALSE), 
                                      cleanable_orgs$street_clean)

cleanable_orgs$street_clean <- gsub("^c\\/o", "", cleanable_orgs$street_clean, ignore.case=TRUE, fixed=FALSE)

final_cleanable_orgs <- cleanable_orgs %>%
  mutate(address = paste(street_clean, city, state, zipcode, sep=", ")) %>% 
  select(-c(street_clean, regex_result))

# bring all addresses into one df
final_addresses <- rbind(eins_exclude, final_cleanable_orgs)

# grab select cols and trim extra whitespace from addresses
final_addresses <- final_addresses %>%
  select(ein, name, address)

# clean up white space
final_addresses$address <- sapply(final_addresses$address, str_squish)

##### Geocode #####
# geocode_results <- final_addresses %>%
#   geocode(address=address,
#           lat="lat",
#           long = "lon",
#           method="google",
#           full_results=TRUE)
# 
# partial_matches <- geocode_results %>%
#   filter(partial_match==TRUE)

# Note: definitions of result types here: https://developers.google.com/maps/documentation/javascript/geocoding
geocode_results_select_columns <- geocode_results %>%
  select(1:2, address, lat, lon, formatted_address, partial_match, types, geometry.location_type, postcode_localities)

# Flatten lists to export to csv
geocode_results_select_columns$postcode_localities <- sapply(geocode_results_select_columns$postcode_localities, paste, collapse=", ")
geocode_results_select_columns$types <- sapply(geocode_results_select_columns$types, paste, collapse=", ")

geocode_results_select_columns <- geocode_results_select_columns %>%
  rename(address_type = types,
         location_type = geometry.location_type)

# Send initial geocoded results to csv
csv_filepath <- "W:\\Project\\ECI\\MLAW\\Data\\geocoded_lac_orgs_04262024.csv"
# write.csv(geocode_results_select_columns, csv_filepath, row.names = FALSE, fileEncoding = "UTF-8")

initial_results_table <- read.csv(csv_filepath, encoding="UTF-8")

# implement QA notes - manually recoding ein = 330166204, which included a 1/2 block in address
initial_results_table[initial_results_table$ein==330166204,]
initial_results_table[initial_results_table$ein==330166204, c("address", "lat", "lon")] <- c("600 1/2 Redondo Ave, Long Beach, CA 90814", 33.7744786, -118.1522637)
initial_results_table[initial_results_table$ein==330166204, c("formatted_address", "partial_match", "address_type", "location_type", "postcode_localities")] <- NA

final_table <- initial_results_table

# final results - save to csv
final_csv_filepath <- "W:\\Project\\ECI\\MLAW\\Data\\geocoded_lac_orgs_05012024.csv"
# write.csv(final_table, final_csv_filepath, row.names = FALSE, fileEncoding = "UTF-8")

##### Step 5: send results to csv and pgadmin #####
final_table <- read.csv(final_csv_filepath, header=TRUE, encoding="UTF-8", colClasses = c("ein"="character"))

# Send geocoded results to pg
table_schema <- "data"
table_name <- "irs_bmf_lac_health_mental_services_geocoded"
conn <- connect_to_db("eci_mlaw")
# dbWriteTable(conn, c(table_schema, table_name), final_table,
#              overwrite = TRUE, row.names = FALSE)

# For column comments
# column_names <- names(final_table)
# column_comments <- list(
#   "EIN",
#   "Organization Name",
#   "Organization address provided to geocoder",
#   "Latitude",
#   "Longitude",
#   "Final address used by geocoder - can change from provided address; Is the address represented by the Latitude/Longitude coordinates.",
#   "Provided by geocoder - flags if address only had a partial match",
#   "Provided by geocoder - address type (e.g., street_address, premise, intersection, etc.). More details here: https://developers.google.com/maps/documentation/javascript/geocoding#GeocodingAddressTypes",
#   "Provided by geocoder - location type (e.g., ROOFTOP, RANGE_INTERPOLATED, GEOMETRIC_CENTER, or APPROXIMATE). More details here: https://developers.google.com/maps/documentation/javascript/geocoding#GeocodingResponses",
#   "Provided by geocoder - all the localities contained in a postal code; only present when the postal code contains multiple localities."
# )
# 
# for (i in seq_along(column_names)) {
#   column_comment <- column_comments[[i]]
#   
#   column_comment_sql <- paste0("COMMENT ON COLUMN ",
#                                table_schema, ".", table_name, ".", column_names[[i]]," IS '", column_comment, "';")
#   
#   dbSendQuery(conn, column_comment_sql)
# }
# 
# table_comment <- "Geocoded results for 515 Health and mental health service organizations in LA County that dont match to a LA City ZIP Code to verify that they are not in LA City.
# Includes orgs that have filed in last 3 years and meet filing requirements (e.g., required to file a 990) and meet our NTEE Codes for health/mental health services. Please note: ein 330166204 was manually geocoded.
# R Script: W:/Project/ECI/MLAW/R/geocode_lac_orgs.R
# QA Doc: W:/Project/ECI/MLAW/Documentation/QA_geocode_lac_orgs.docx"
# table_comment_sql <- paste0("COMMENT ON TABLE ", table_schema, ".", table_name,  " IS '", table_comment,"';")

dbSendQuery(conn, table_comment_sql)
dbDisconnect(conn)

##### SQL for geom columns #####
conn <- connect_to_db("eci_mlaw")
# schema_table_name <- paste0(table_schema, ".", table_name)
# add_geom_col_sql <- paste0("alter table ", schema_table_name, " add column geom Geometry('POINT', '3310');")
# set_srid_sql <- paste0("update ", schema_table_name, " set geom = ST_SetSRID(ST_TRANSFORM(ST_SetSRID(st_point(lon,lat), 4326), 3310), 3310);")
# create_geom_idx_sql <- paste0("create index irs_bmf_lac_health_mental_services_coords_geom_idx on ", schema_table_name, " using gist(geom);")
# vacuum_sql <- paste0("vacuum analyze ", schema_table_name, " ;")
# 
# dbSendQuery(conn, add_geom_col_sql)
# dbSendQuery(conn, set_srid_sql)
# dbSendQuery(conn, create_geom_idx_sql)
# dbSendQuery(conn, vacuum_sql)

dbDisconnect(conn)
# QA Notes:
# 330166204 - forgot to update this address to 600 1/2 Redondo Ave - result is off by about 1 mi (should probably be: 33.7736525379364, -118.15210743833588)
# Did we lose leading zeroes in the EIN column?

##### Exploratory notes, can delete after QA) #####
# Notes
# checked for duplicate EINS - none
ein_freq <-table(orgs$ein) %>%
  as.data.frame()
# remove "C/O" (occurs once at the beginning of an address)
# remove "STE [XYZ]" and "SUITE [XYZ]" and "STE 1 # 270" and "SUITE B-4" and "STE A"
# remove "APT 27"
# remove "SPC 125"
# remove "UNIT C"
# remove "PMB 371"
# remove "BLDG C"
# remove "NO 405"
# remove "2ND FLOOR - MAILBOX J"
# remove "HARRIMAN BUILDI"
# remove any "words" with numbers at the end (will impact other addresses -e.g., EIN 364581129, EIN 463385695, any PO Box)
### Examples "B-6", "458"
# 330166204 - ATLANTIC ALANO CLUB INC - 600 12 REDONDO AVE - LONG BEACH - CA - 90814-0000
### Should be 600 1/2 Redondo Ave
# 364581129 - ANGELS OF VICTORY YOUTH TREATMENT CENTER INC - 44806 1/2 - LANCASTER - CA - 93534-0000
### street seems incomplete?
# 463385695 - FASD NETWORK OF SOUTHERN CALIFORNIA - 595 - MANHATTAN BEACH - CA - 90267-0000
### street seems incomplete?
# 815073709 - JGC FOUNDATION - 11193 - BURBANK - CA - 91505-0000
### street seems incomplete?
# 954047835 - CHILDRENS MEDICAL CARE FOUNDATION - 2907 - BEVERLY HILLS - CA - 90213-0000
### street seems incomplete?