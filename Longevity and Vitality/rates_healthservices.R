# MLAW LA City Equity Index
# Mental health/Health service rates by LA City ZIP Code
# Data Source: IRS EO BMF 2024
# https://www.irs.gov/charities-non-profits/exempt-organizations-business-master-file-extract-eo-bmf

##### Set Up Workspace #####
library(dplyr)
library(RPostgreSQL)
library(tidyr)
library(readxl)
library(stringr)
library(rpostgis)

# Connect to postgres

source("W:\\RDA Team\\R\\credentials_source.R")

con <- connect_to_db("eci_mlaw")
con2<-connect_to_db("rda_shared_data")
drv <- dbDriver("PostgreSQL")


#### Read in data ####
###### ZIP codes in LA City ----

zips<-st_read(con, query="SELECT * FROM crosswalk_zip_city_2022",geom="geom")
la_zips<-zips$zipcode # create vector of zips for filtering

pop<-dbGetQuery(con2, "SELECT geoid, dp05_0001e, dp05_0001m FROM demographics.acs_5yr_dp05_multigeo_2022 
                WHERE geolevel ILIKE 'zcta'")

# join population data with our zipcode crosswalk so we get population estimates and MOEs for LA City zipcodes

pop<-zips%>%
  left_join(pop, by=c("zipcode"="geoid"))

###### Indicator data ----
# read in latest IRS data which I downloaded from https://www.irs.gov/charities-non-profits/exempt-organizations-business-master-file-extract-eo-bmf (updated  02/13/2024)
# and saved here:  W:\Data\Nonprofit\IRS BMF\IRS BMF 2024

irs<-read.csv("W:\\Data\\Nonprofit\\IRS BMF\\IRS BMF 2024\\eo_ca.csv")
filing_req_cd<-c(1,2,3) # filing req CD codes as a vector for filtering to target actual nonprofits and service orgs

###### ZIP Code database to identify ZIPs in LA County for geocoding ----
# Data Source link: https://www.unitedstateszipcodes.org/zip-code-database/
zip_db<-read.csv("W:\\Data\\Geographies\\ZIP Code Database\\2024\\zip_code_database.csv")

# filter for LA County ZIP Codes to prioritize orgs for geocoding
zip_db<-zip_db%>%filter(county=="Los Angeles County")

zip_db_list<-as.character(zip_db$zip)

#### Calculate Mental health/Health service rates at ZIP Code level ####

###### Step 0: Create separate IRS file with filters for ECI to review 4/5/24-------------------

# irs_eci<-irs%>%
#   mutate(tax_period_year=substr(TAX_PERIOD, 1,4),
#          zipcode=substr(ZIP, 1,5))%>% 
#   filter(zipcode %in% la_zips &
#            tax_period_year>=2021 & 
#            PF_FILING_REQ_CD == 0 &
#            FILING_REQ_CD %in% filing_req_cd)%>%
#   group_by(NTEE_CD)%>%
#   mutate(org_count=n())%>%
#   slice(1)%>%
#   select(NTEE_CD, org_count)%>% 
#   mutate(NTEE_CD=ifelse(NTEE_CD %in% "", NA, NTEE_CD))
#   
# # export as excel
# 
# openxlsx::write.xlsx(irs_eci, file = "W:\\Project\\ECI\\MLAW\\Data\\irs_eci.xlsx")

###### Final NTEE Target Codes ------------------------
# NTEE Codes Catalyst California identified as direct mental health or health services based on IRS BMF data dictionary
ntee_list<-c("E70","E60","E32","E50","E30","E21","E40","E42","E20","E22","E24","F20","F60","F30","F22","F21","F80",
             "F32","F33","F70","F40","F42")

###### Step 1: Create a geocode list for orgs in LA County ------------------------

# filter the irs data for orgs that meet our criteria and that are in LA County ZIP Codes
# then also filter out for the NTEE codes of interest (health/mental health services)

df_geocodes<-irs%>%
  mutate(tax_period_year=substr(TAX_PERIOD, 1,4), # get most recent filing year
         zipcode=substr(ZIP, 1,5), # trim ZIP Code
         ntee=substr(NTEE_CD, 1,3))%>%  # trim NTEE Code
  filter(zipcode %in% zip_db_list & # filter for orgs in LA County
           ntee %in% ntee_list & # filter for orgs in our target NTEE activity codes
           tax_period_year>=2021 & # only select orgs that have filed in past 3 years to include only active orgs
           PF_FILING_REQ_CD == 0 & # do not include public foundations
           FILING_REQ_CD %in% filing_req_cd # only orgs required to file a 990 EZ, 990 N, or 990 group return
  )

# find which orgs are not matched to LA City ZIP Codes to confirm via geocoding
df_geocodes<-df_geocodes%>%filter(!zipcode %in% la_zips)
# qa<-table(df_geocodes$CITY)%>%as.data.frame()
# some are in LA City or sub-cities (Woodland Hills)

# # push to database for geocoding
# # set column types
# charvect = rep("varchar", ncol(df_geocodes)) 
# 
# # add df colnames to the character vector
# names(charvect) <- colnames(df_geocodes)
# names(df_geocodes) <- tolower(names(df_geocodes))

# push to postgres
# dbWriteTable(con,  "irs_bmf_lac_health_mental_services_togeocode", df_geocodes,
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data
# table_comment <- paste0("COMMENT ON TABLE irs_bmf_lac_health_mental_services_togeocode  IS 
# 'Health and mental health services in LA County that dont match to a LA City ZIP Code to prioritize for geocoding and verification that they are not in LA City.
# Includes orgs that have filed in last 3 years and meet filing requirements (e.g., required to file a 990)
# and meet our NTEE Codes for health/mental health services
# R script: W:\\Project\\ECI\\MLAW\\R\\rates_healthservices.R
# QA document: 
# W:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_healthservices.docx';
# ")

# send table comment + column metadata
# dbSendQuery(conn = con, table_comment)

###### Step 2: Filter the IRS data and match to LA City ZIP Codes ------------------------

# filter the irs data for orgs that meet our criteria and that are in LA City ZIP Codes
# then also filter out for the NTEE codes of interest (health/mental health services)

# 2a: First match by ZIP Code in the address field
df<-irs%>%
  mutate(tax_period_year=substr(TAX_PERIOD, 1,4), # get most recent filing year
         zipcode=substr(ZIP, 1,5), # trim ZIP Code
         ntee=substr(NTEE_CD, 1,3))%>% # trim NTEE Code
  filter(zipcode %in% la_zips & # filter for orgs in LA County
           ntee %in% ntee_list & # filter for orgs in our target NTEE activity codes
           tax_period_year>=2021 &  # only select orgs that have filed in past 3 years to include only active orgs
           PF_FILING_REQ_CD == 0 & # do not include public foundations
           FILING_REQ_CD %in% filing_req_cd # only orgs required to file a 990 EZ, 990 N, or 990 group return
  )

# 2b: Match to ZIP Code based on geocoded point
irs_geocoded<-st_read(con, query="SELECT * FROM irs_bmf_lac_health_mental_services_geocoded", geom="geom")
table(irs_geocoded$location_type)
qa<-irs_geocoded%>%left_join(df_geocodes%>%mutate(ein=as.character(EIN)))
# most approximate geocodes matched to the ZIP Code, which is okay and most are PO Boxes

# join geocoded addresses to LA City Zips based on centroid
st_crs(zips)
st_crs(irs_geocoded)

df_points<-st_join(irs_geocoded,zips)

df_points<-df_points%>%
  filter(!is.na(zipcode))%>%
  left_join(df_geocodes%>%
              mutate(ein=as.character(EIN))%>%
              select(ein,INCOME_CD),by=c("ein"))

# 2c: Join two methods
names(df) <- tolower(names(df)) 
names(df_points) <- tolower(names(df_points)) 

df_zips<-df%>%select(ein,zipcode,income_cd)
df_points<-df_points%>%select(ein,zipcode,income_cd)%>%st_drop_geometry()
df<-rbind(df_zips,df_points)

###### Step 3: Apply income weights and calculate weighted / raw counts---------------------------

# Recode the income_cd field for our weights. I am using the same weights that were used in the JESI:
# $0 to $499,999 = 1
# $500,000 to $999,999 = 2
# $1,000,000 to $4,999,999 = 3
# $5,000,000 or greater = 4

df<-df%>%
  mutate(income_weight=ifelse(income_cd == 0, 1, 
                              ifelse(income_cd  ==  1, 1,
                                     ifelse(income_cd %in% 2, 1,
                                            ifelse(income_cd %in% 3, 1,
                                                   ifelse(income_cd %in% 4, 1,
                                                          ifelse(income_cd %in% 5, 2,
                                                                 ifelse(income_cd %in% 6, 3,
                                                                        ifelse(income_cd %in% 7, 4,
                                                                               ifelse(income_cd %in% 8, 4,
                                                                                      ifelse(income_cd %in% 9, 4, NA
                                                                                      )))))))))))%>%
  group_by(zipcode)%>%
  summarise(adj_count=sum(income_weight,na.rm=TRUE),
            raw_count=n()
  )


###### Step 4: Finalize table and calculate rates -----------------------

df_final<-pop%>%
  select(zipcode, dp05_0001e, dp05_0001m)%>%
  left_join(df, by=c("zipcode"="zipcode"))%>%
  mutate(pop=dp05_0001e, 
         pop_moe=dp05_0001m,
         pop_cv=pop_moe/1.645/pop*100,
         adj_count=ifelse(is.na(adj_count),0,adj_count),#assume NA counts are actually 0
         raw_count=ifelse(is.na(raw_count),0,raw_count),
         adj_rate=adj_count/(dp05_0001e)*10000,
         raw_rate=raw_count/(dp05_0001e)*10000)%>%
  st_drop_geometry()



###### Calculate percentiles----------

df_final<-df_final%>%
  mutate(healthservice_adj_pctile=percent_rank(adj_rate),
         healthservice_raw_pctile=percent_rank(raw_rate))


# test how unweighted and weighted percentiles are correlated
library("ggpubr")
ggscatter(df_final, x = "healthservice_adj_pctile", y = "healthservice_raw_pctile", 
          add = "reg.line", conf.int = TRUE, 
          cor.coef = TRUE, cor.method = "pearson",
          xlab = "Income weighted", ylab = "Raw")


# final select columns of interest

df_final<-df_final%>%
  select(zipcode, pop, pop_moe, pop_cv, raw_count, adj_count, raw_rate, adj_rate, healthservice_raw_pctile,healthservice_adj_pctile)%>%
  rename("geoid"="zipcode")

# Push to postgres---------------------------------------

# set column types
charvect = rep("numeric", ncol(df_final)) 
charvect <- replace(charvect, c(1), c("varchar"))

# add df colnames to the character vector
names(charvect) <- colnames(df_final)

# push to postgres
# dbWriteTable(con,  "rates_healthservices", df_final,
#              overwrite = TRUE, row.names = FALSE,
#              field.types = charvect)

# add meta data
table_comment <- paste0("COMMENT ON TABLE rates_healthservices  IS 'Rate of mental/health services in LA City by zipcode. NTEE codes used to define mental/health 
service organizations was decided by ECI team
Count of mental/health services are adjusted by organization income revenue and presented in raw values. Rates are per 10k total adjusted zcta population. 
Methodology for filtering mental/health service organizations
and recoding income weights matches JESI methodology: https://www.catalystcalifornia.org/campaign-tools/maps-and-data/justice-equity-services-index
Organization data from IRS EO BMF file: https://www.irs.gov/charities-non-profits/exempt-organizations-business-master-file-extract-eo-bmf
R script: W:\\Project\\ECI\\MLAW\\R\\rates_healthservices.R
QA document: 
WW:\\Project\\ECI\\MLAW\\Documentation\\QA_rates_healthservices.docx';

COMMENT ON COLUMN rates_healthservices.geoid IS 'Zipcode';
COMMENT ON COLUMN rates_healthservices.pop IS 'Raw zipcode population. Originally DP05_0001e';
COMMENT ON COLUMN rates_healthservices.pop_moe IS 'zcta population moe from DP05_0001m';
COMMENT ON COLUMN rates_healthservices.pop_cv IS 'zcta population cv';
COMMENT ON COLUMN rates_healthservices.raw_count IS 'Raw count of health/mental health services within zipcode';
COMMENT ON COLUMN rates_healthservices.adj_count IS 'Adjusted count of health/mental health services within zipcode using organizations reported income as weight';
COMMENT ON COLUMN rates_healthservices.raw_rate IS 'Rate of health/mental health services within ZIP Code per 10K pop';
COMMENT ON COLUMN rates_healthservices.adj_rate IS 'Rate of health/mental health services within zipcode using organizations reported income as weight to calculate the numerator
of the rate calculation';
COMMENT ON COLUMN rates_healthservices.healthservice_adj_pctile IS 'Percentile of income adjusted weight';
COMMENT ON COLUMN rates_healthservices.healthservice_raw_pctile IS 'Percentile of raw rate';
")

# send table comment + column metadata
# dbSendQuery(conn = con, table_comment)

