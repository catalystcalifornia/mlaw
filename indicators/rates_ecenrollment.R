# MLAW LA City Equity Index
# Calculate ECE enrollment rate by ZIP code using enrollment and population data from
# American Institutes of Research and California Childcare Resource & Referral Network
# California Child Care Resource & Referral Network (2021); American Institutes for Research Early Learning Needs Assessment Tool (2020)
# Licensed child care, prek, TK enrollment per 100 children under age 5. 
# Accessible child care refers to enrollment in the home ZIP Code. 
# Catalyst California methodology: add numbers of 0-4 year olds enrolled in all forms of licensed care, prek, and transitional kindergarten.

##### Set Up Workspace #####

library(readxl)
library(dplyr)
library(RPostgreSQL)
library(tidyr)
library(tidycensus)
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

###### Infant and toddler enrollment data ----

########### 1. AIR IT DATA -- child pop for infants and toddlers <36 months old ###########

# get la county it data, converting asterisks to nulls
air_it <- read_xlsx("W:/Data/Education/American Institute for Research/2020/air_it_2020.xlsx", range = "A515:V960", na = "*")

#subset it data to columns we want
air_it <- air_it[c(1:2, 6, 10, 14, 18, 22)]

# rename columns
names(air_it) <- c("geoname", "pct_zip", "it", "it_under_85smi", "it_enrollment", "it_unmet_need", "it_pct_unmet_need")

# pick out la county
air_it_la <- air_it %>% filter(geoname == "Los Angeles") %>% select(-pct_zip)

# remove counties and rename geoid column
air_it <- air_it %>% filter(pct_zip != "Percent of Zip Code Allocation") %>% rename(geoid = geoname)

########### 2. AIR PREK DATA -- child pop for 3 and 4 year olds ###########

# get prek data, converting asterisks to nulls
air_prek <- read_xlsx("W:/Data/Education/American Institute for Research/2020/air_prek_2020.xlsx", range = "A513:V958", na = "*")

# subset prek data to columns we want
air_prek <- air_prek[c(1:2, 3:4, 7:8, 11:12, 15:16, 19:20)]

# rename columns
names(air_prek) <- c("geoname", "pct_zip", 
                     "prek3","prek4", 
                     "prek_under_85smi3","prek_under_85smi4", 
                     "prek_enrollment3","prek_enrollment4", 
                     "prek_unmet_need3", "prek_unmet_need4",
                     "prek_pct_unmet_need3", "prek_pct_unmet_need4")

# add 3 and 4 year olds
air_prek <- air_prek %>% mutate(
  prek = prek3 + prek4,
  prek_under_85smi = prek_under_85smi3 + prek_under_85smi4,
  prek_enrollment = prek_enrollment3 + prek_enrollment4,
  prek_unmet_need = prek_unmet_need3 + prek_unmet_need4,
  prek_pct_unmet_need = (prek_unmet_need3 + prek_unmet_need4) / (prek_under_85smi3 + prek_under_85smi4)
) %>% select (geoname, pct_zip, prek, prek_under_85smi, prek_enrollment, prek_unmet_need, prek_pct_unmet_need)

# pick out la county
air_prek_la <- air_prek %>% filter(geoname == "Los Angeles") %>% select(-pct_zip)

# remove counties and pct_zip column as it is duplicative in join next
air_prek <- air_prek %>% filter(pct_zip != "Percent of Zip Code Allocation") %>% rename(geoid = geoname) %>% select(-pct_zip)


########### 3. AIR TK DATA -- tk spots ###########

# get tk data
air_tk <- read_xlsx("W:/Data/Education/American Institute for Research/2020/tk.xlsx", range = "A513:F958", na = "*")
names(air_tk) <- c("geoname", "pct_zip", "three", "four", "five", "tk") 
air_tk <- air_tk %>% select(-"pct_zip", -"three", -"four", -"five")

# pick out la county
air_tk_la <- air_tk %>% filter(geoname == "Los Angeles")
air_tk <- air_tk %>% filter(geoname != "Los Angeles") %>% rename(geoid = geoname)


########### 4. CCCRRN DATA  -- center capacity from infant and toddlers to tk ###########

# get CCCRRN data
cccrrn <- read_xlsx("W:/Data/Education/CCCRRN/2021/CatalystCA2021Data_rev.xlsx") %>% rename(geoid = ZIPCODE)

# format columns for join
air_it$geoid <- as.character(air_it$geoid)
air_it$pct_zip <- as.numeric(air_it$pct_zip)
air_prek$geoid <- as.character(air_prek$geoid)
cccrrn$geoid <- as.character(cccrrn$geoid)

########### 3.5 Join AIR IT, PREK, TK, & CCRRN data)

#join it, prek, and tk data
df <- left_join(air_it, air_prek, by = "geoid")
df <- left_join(df, cccrrn, by = "geoid")
df <- left_join(df, air_tk, by = "geoid")

#remove ZIP codes with less that 10% overlap in County and treat the rest as 100%
#the only ZIP remaining with less the 90% in is 91361, which is primarily open space outside of LA
df <- df %>% filter(pct_zip >= 10)


#### Calculate infant and toddler enrollment rate ####
# calculating as we did for racecounts ece enrollment
# assumes ccrrn capacity = full enrollment. 
df$children <- rowSums(df[,c("it", "prek")], na.rm = TRUE) # total children 0-4 estimated in ZIP
df$enrollment <- rowSums(df[,c("INFCAP", "PRECAP", "FCCCAP", "tk")], na.rm = TRUE) # total child care capacity for children 0-4 in ZIP
df$enrollment_rate <- df$enrollment / df$children * 100 # estimated % of children enrolled or spots per 100 children

#clean up and format
# change NaN and infinite to NA
df[sapply(df, is.nan)] <- NA

df[sapply(df, is.infinite)] <- NA

# filter for la city zips
df<-df%>%filter(geoid%in% la_zips)

# which zip is missing
df_missing<-zips%>%left_join(df,by=c("zipcode"="geoid"))%>%filter(is.na(enrollment_rate))
#90071 in downtown is missing

df_final <- df %>% select(geoid,enrollment_rate,children,enrollment)%>%
  rename(ecenrollment_rate=enrollment_rate)

# Calculate percentiles---------------------

df_final<-df_final%>%
  mutate(ecenrollment_pctile=percent_rank(ecenrollment_rate))

# Finalize table and push to postgres -------------------

# set column types
charvect = rep("numeric", ncol(df_final))
charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector
names(charvect) <- colnames(df_final)

# push to postgres
# dbWriteTable(con,  "rates_ecenrollment", df_final,
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_ecenrollment  IS 'ECE enrollment rates by ZIP COde in LA CITY.
Calculated based on data from AIR and CCCRRN--estimates number of children enrolled or childcare spots per children 0-4 in ZIP Code using enrollment data, childcare capacity, and estimated population data from AIR and CCCRRN.
Assumes centers are enrolled at capacity and assumes children are accessing enrollment or centers in their ZIP Code
R script: W:\\Project\\ECI\\MLAW\\R\\rates_ecenrollment.R
QA document:
WW:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_ecenrollment.docx';

COMMENT ON COLUMN rates_ecenrollment.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_ecenrollment.ecenrollment_rate IS 'Rate of children enrolled in ECE can be interpreted as percent of children enrolled or number of spots per 100 children in ZIP';
COMMENT ON COLUMN rates_ecenrollment.children IS 'Total number of children in the ZIP Code based on data from AIR based on ACS data';
COMMENT ON COLUMN rates_ecenrollment.enrollment IS 'Total children enrolled or enrollment spots for 0-4 year olds in ZIP';
COMMENT ON COLUMN rates_ecenrollment.ecenrollment_pctile IS 'Percent rank of the estimate -rate';

")

# send table comment + column metadata
# dbSendQuery(conn = con, table_comment)

