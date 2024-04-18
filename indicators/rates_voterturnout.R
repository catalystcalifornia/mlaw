# MLAW LA City Equity Index
# Calculate voter turnout rate by ZIP Code using precinct level data from LA County RR/CC and CA redistricting database
# Election year used 2022 General Election local LA City results
# Data sources: LA County Registrar-Recorder/County Clerk General Election Results 2022
# California Statewide Database 2022 General Election Geographic Data Los Angeles County RG to RR to SR to SVPREC xwalk & SRPREC_SHP

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

###### Voter turnout data ----

# Pull in statement of votes cast from register/recorder - using 2022 General Election as an indicator of turnout
# link: https://www.lavote.gov/home/voting-elections/current-elections/election-results/past-election-results
sov_general_22<- read_xls("W:/Project/ECI/MLAW/Data/Voter Turnout/lac_rr_cc/LOS_ANGELES_CITY_GEN-MAYOR_11-08-22_by_Precinct_PUBLIC_4300-8847.xls", range = "A3:J2856")

# clean it up
sov_general_22<-sov_general_22%>%
  select(LOCATION,PRECINCT,REGISTRATION,TYPE,`BALLOTS CAST`)

# rename columns
names(sov_general_22) <- c("location", "sov_precinct", "registered_voters", "type", "ballots_cast")

# pick out total vote summary
sov_general_22 <- sov_general_22 %>% filter(type=="TOTAL")

# get unique list of statement of vote (sov) precincts in LA City from 2022 election
la_sv_precincts<-sov_general_22$sov_precinct


###### Precinct crosswalks ----

# Pull in crosswalk of precinct types from redistricting database for Los Angeles
# data source https://statewidedatabase.org/d20/g22_geo_conv.html
# rg (registration precincts) to rr (map precincts) to sr (consolidated precincts from Redistricting database) to sv (voting precints) precincts
# precinct definitions https://statewidedatabase.org/diagrams.html
# technical documentation https://statewidedatabase.org/d10/Creating%20CA%20Official%20Redistricting%20Database.pdf
sr_sv_xwalk<- read.csv("W:/Project/ECI/MLAW/Data/Voter Turnout/037_rg_rr_sr_svprec_g22.csv")

# keep la city precincts
sr_sv_xwalk<-sr_sv_xwalk%>%filter(svprec %in% la_sv_precincts)

length(unique(sr_sv_xwalk$svprec))
#950 compared to 951, let's check the difference

rd_svprec<-sr_sv_xwalk$svprec

check<-sov_general_22%>%filter(!sov_precinct %in% rd_svprec)
# just ballot group 1 which is okay

###### Precinct shapes ----
# accessed from redistricting database https://statewidedatabase.org/d20/p22_geo_conv.html
# sprec_shp for Los Angeles
srprec_shp<-st_read("W:/Project/ECI/MLAW/Data/Voter Turnout/srprec_037_g22_v01_shp/srprec_037_g22_v01.shp")

#### Calculate voter turnout numbers ####

###### Prep precinct data ----
# join precinct crosswalk and votes cast data
df_prec<-sr_sv_xwalk%>%left_join(sov_general_22,by=c("svprec"="sov_precinct"))

# check if sv precincts match to more than one sv prec
check<-df_prec%>%group_by(svprec,srprec)%>%summarise(count=n())
# no they match up, take unique matches for crosswalk

sr_sv_xwalk<-sr_sv_xwalk%>%distinct(svprec,srprec)

# match voter turnout numbers to sr prec (redistricting database's consolidated precincts) shapes
sv_srprec_shp<-srprec_shp%>%
  left_join(sr_sv_xwalk,by=c("SRPREC"="srprec"))%>%
  left_join(sov_general_22,by=c("svprec"="sov_precinct"))%>%
  filter(registered_voters>0)

###### Join Precincts to LA City ZIP Codes ----
# transform shapes
sv_srprec_shp<-st_transform(sv_srprec_shp,3310)

zips<-st_transform(zips,3310)

# calculate area of precincts
sv_srprec_shp$area<-st_area(sv_srprec_shp)

# intersect with zips
srprec_zip_intersect<-st_intersection(sv_srprec_shp,zips)

# calculate prc overlap
srprec_zip_intersect$intersect_area<-st_area(srprec_zip_intersect)
srprec_zip_intersect$prc_area<-as.numeric(srprec_zip_intersect$intersect_area)/as.numeric(srprec_zip_intersect$area)

# keep intersects that are over 3% (reducing slivers intersecting)
srprec_zip<-srprec_zip_intersect %>% filter(prc_area>.03)

# test result
srprec_zip<-st_transform(srprec_zip,4326)
zips<-st_transform(zips,4326)

library(leaflet)
srprec_zip$color <- factor(srprec_zip$SRPREC, TRUE)
factpal <- colorFactor("Set1", srprec_zip$SRPREC)

leaflet() %>%
  addTiles()%>%
  addPolygons(data=srprec_zip,stroke = FALSE, smoothFactor = 0.2, fillOpacity = 1,
              color = ~factpal(srprec_zip$SRPREC))%>%
  addPolygons(data=zips,smoothFactor = 0.2, 
              fillOpacity = 0,opacity=1,weight=2,fillColor="white",color="black")

###### Calculate turnout rates by ZIP Code using prc area overlap ----
# spatial aerial apportionment
df<-srprec_zip%>%
  group_by(zipcode)%>%
  summarise(est_reg_voters=sum(registered_voters*prc_area),
            est_votes_cast=sum(ballots_cast*prc_area))

df<-df%>%mutate(turnout_rate=est_votes_cast/est_reg_voters)%>%st_drop_geometry


df_final <- df %>% rename(geoid=zipcode,
                          reg_voters_count=est_reg_voters,
                          voter_turnout_count=est_votes_cast,
                          voter_turnout_rate=turnout_rate)

# Calculate percentiles---------------------

df_final<-df_final%>%
  mutate(voter_turnout_pctile=percent_rank(voter_turnout_rate))

# Finalize table and push to postgres -------------------

# set column types
charvect = rep("numeric", ncol(df_final))
charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector
names(charvect) <- colnames(df_final)

# push to postgres
# dbWriteTable(con,  "rates_voterturnout", df_final,
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data

table_comment <- paste0("COMMENT ON TABLE rates_voterturnout  IS 'Voter turnout rates by ZIP Codes based on 2022 General Election Results for LA City.
Election results from LA County RR-CC, map precincts from CA Redistricting Database
R script: W:\\Project\\ECI\\MLAW\\R\\rates_voterturnout.R
QA document:
WW:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_voterturnout.docx';

COMMENT ON COLUMN rates_voterturnout.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_voterturnout.voter_turnout_rate IS 'Percentage of voters who cast ballots in 2022 General Election';
COMMENT ON COLUMN rates_voterturnout.voter_turnout_count IS 'Total number of voters who cast ballots in 2022 General Election';
COMMENT ON COLUMN rates_voterturnout.reg_voters_count IS 'Total registered voters in the ZIP Code';
COMMENT ON COLUMN rates_voterturnout.voter_turnout_pctile IS 'Percent rank of the estimate -rate';

")

# send table comment + column metadata
# dbSendQuery(conn = con, table_comment)

