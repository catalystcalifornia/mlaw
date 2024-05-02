# MLAW Los Angeles City Equity Index

<br>

<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a></li>
       <li><a href="#acknowledgements-and-partners">Acknowledgements and Partners</a>
    <li><a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#data-methodology">Data Methodology</a>
      <ul>
        <li><a href="#indicator-selection">Indicator Selection</a></li>
        <li><a href="#la-city-zip-codes">LA City ZIP Codes</a></li>
         <li><a href="#indicator-domains">Indicator Domains</a></li>
         <li><a href="#analysis-overview">Analysis Overview</a></li>
         <li><a href="#data-sources">Data Sources</a></li>
         <li><a href="#limitations">Limitations</a></li>
      </ul>
    </li>
    <li><a href="#contributors">Contributors</a></li>
    <li><a href="#contact-us">Contact Us</a></li>
    <li><a href="#about-catalyst-california">About Catalyst California</a>
      <ul>
        <li><a href="#our-vision">Our Vision</a></li>
        <li><a href="#our-mission">Our Mission</a></li>
      </ul>
    </li>
    <li><a href="#citation">Citation</a></li>
    <li><a href="#license">License</a></li>
  </ol>
</details>

## About The Project

To uplift the challenges faced by residents in the City of Los Angeles, particularly in communities that have seen systemic divestment and exclusion from critical resources, Catalyst California collaborated with the Make Los Angeles Whole (MLAW) Coalition to identify a set of indicators that would provide a framework for a more equitable city. This project was done in response to the the Measure of Access, Disparity, and Equity (MADE) Index launched by the City Administrative Office (CAO) in the fall of 2023. The MADE Index sought to highlight equity issues in the distribution of resources in the city as well as identify areas for priority investment.

Tools like this are important to ensure that communities most negatively impacted by redlining, disinvestment and systemic racism are given higher priority when it comes to investment, or protection against budget cuts. Because of this, it is essential that these tools are inextricably linked to the priorities and experiences of the most impacted communities. The following [analysis](https://catalystcalifornia.github.io/mlaw/la_city_equity_index), created with the MLAW coalition, recommends indicators, an equity index, and a conceptual framework for a LA City Equity Index that is guided by community feedback. In the analysis, we map the results of the  equity index and the individual indicators to show which parts of the city are "higher need," or need more investments. All indicators are correlated with race to ensure that groups most impacted by systemic racism are being prioritized within the index. 

This repository provides access to our detailed code for each indicator and a summary of our recommendations to the city. Our index results and recommendations were additionally groundtruthed by partner organizations in the MLAW Coalition. For more information on our process and recommendations, please see the following read me, our detailed recommendations, and analysis.  

[add link to recommendations pdf]
<li><a href="https://catalystcalifornia.github.io/mlaw/la_city_equity_index">Link to online index analysis and results</a></li>

<p align="right">(<a href="#top">back to top</a>)</p>

## Acknowledgements and Partners

This work would not have been possible without the collaboration and invaluable insights provided by our partners in the MLAW Coalition. Our partners collected community surveys throughout the survey to inform issues included in the index and provided their feedback throughout the index development process to shape the domains and indicators included. We urge decision-makers or those looking to develop public indices for budgeting to engage in ongoing, meaningful community engagement to inform index development and implementation.

MLAW Coalition partners include:

* [Community Coalition](https://cocosouthla.org/)
* [Inner City Struggle](https://www.innercitystruggle.org/)
* [Black Women for Wellness](https://bwwla.org/)
* [Brotherhood Crusade](https://www.brotherhoodcrusade.org/)
* [SEIU 2015](https://www.seiu2015.org/)
* [SEIU 99](https://www.seiu99.org/)
* [Catalyst California](https://www.catalystcalifornia.org/)

<p align="right">(<a href="#top">back to top</a>)</p>

## Built with

<img src="https://upload.wikimedia.org/wikipedia/commons/thumb/1/1b/R_logo.svg/1086px-R_logo.svg.png?20160212050515" alt="R" height="32px"/> &nbsp; <img  src="https://upload.wikimedia.org/wikipedia/commons/d/d0/RStudio_logo_flat.svg" alt="RStudio" height="32px"/> &nbsp; <img  src="https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/Git-logo.svg/768px-Git-logo.svg.png?20160811101906" alt="RStudio" height="32px"/>

<p align="right">(<a href="#top">back to top</a>)</p>

## Getting Started

### Prerequisites

We completed the data cleaning, analysis, and visualization using the following software. 
* [R](https://cran.rstudio.com/)
* [RStudio](https://posit.co/download/rstudio-desktop)

We used several R packages to analyze data and perform different functions, including the following.
* dplyr
* sf
* tidyr
* usethis
* leaflet

```
list.of.packages <- c("usethis","dplyr","data.table", "sf", tidyr")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages)

devtools::install_github("r-lib/usethis")

library(usethis)
library(dplyr)
library(sf)
library(tidyr)
library(leaflet)
library(RPostgreSQL)
library(readxl)
library(stringr)
library(rpostgis)

```

<p align="right">(<a href="#top">back to top</a>)</p>


## Data Methodology

### Indicator Selection

The LA City Equity index was created by first gathering community input to determine what issue areas, and subsequently indicators, were important to prioritize for inclusion in the index. Community input was gathered directly from MLAW Coalition partners, and from a survey that MLAW Coalition partners distributed to their respective community constituents. A final list of indicators was produced and vetted by the MLAW Coalition after cross-referencing the survey results, partner feedback, and correlations between every indicator and Black, Indigenous, People of Color (BIPOC) populations. Additional criteria used for indicator inclusion was that the indicator data source had recent enough data, the data source was updated on a semi-regular basis, and that the data source was available at a sub-city level. 

### LA City ZIP Codes

The final set of indicators and index is analyzed at the LA City ZIP Code level. To achieve this, we create an LA city ZIP Code crosswalk that lists the ZIP Codes that are mostly within LA City boundaries. We define this as ZIP Codes with at least 25% of its geographical area within LA City limits. We manually exclude the following ZIP Codes associated with universities or event spaces from the index: 90095 (UCLA), 90089 (USC), 91330 (CSU Northridge), and 90090 (Dodger Stadium). 

The LA County ZIP Codes we used to create our crosswalk can be viewed and downloaded from [LA City Geohub](https://geohub.lacity.org/datasets/70748ba37ecc418891e052e800437681_5/about). This data was last updated in 2023. 

### Indicator Domains

The final set of indicators are grouped into four conceptual domains:

| Domain                         | Description    | Indicators                                                                                                                                                                                      |
| ----------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Safe Environments | LA City residents experience safe environments with safety from pollution, traffic injuries, and harmful policing. | Race Composite Score (Black, Latine, AIAN, NHPI, Asian); Particulate Matter (PM) 2.5; Proximity to Hazardous Waste Facilities; Pedestrian and Bicyclist Fatalities and Injuries; Arrests; Hospitalizations for Gun Injuries |
| Economy and Opportunity | LA City residents have the opportunity to equitably engage in the economy. | Race Composite Score (Black, Latine, AIAN, NHPI, Asian); Early Childhood Education (ECE) Enrollment; Rent Burden; Evictions; Per Capita Income |           
| Democracy and Power | LA City residents have the opportunity to equitably participate and influence democracy. | Race Composite Score (Black, Latine, AIAN, NHPI, Asian); Limited English Speaking Households; Voter Turnout for the 2022 General Election | 
| Longevity and Vitality | LA City residents live with freedom from disease and illness, and have the ability to access resources that increase community wellness. | Race Composite Score (Black, Latine, AIAN, NHPI, Asian); Diabetes Hospitalizations; Impervious Land Cover; Health and Mental Health Care Services Access; Grocery Store Access |

We also calculate a **Race Composite Score** which is the average percentile of the Black, Latine, AIAN, NHPI and Asian populations within a ZIP Code. This is included in all of the domain index calculations and the equity index calculation to ensure that the index incorporates racial equity in the final results.

### Analysis Overview

All indicators are individually analyzed at the ZIP Code level by calculating the rate of each indicator for each ZIP Code. A percentile ranking is then measured for each indicator across all LA City ZIP Codes. The higher the indicator percentile ranking is for a ZIP Code, the higher the indicator rate is for that ZIP Code relative to other ZIP Codes in LA City. Percentile rankings are the primary way we determine which ZIP Codes are "high need" relative to others. Most indicators we use are challenge-based, meaning that the higher the percentile ranking is, the higher the need is. For example, the higher the rate or percentile of rent burden, the higher the need is. We also use indicators that are asset-based, meaning that the higher the rate is, the better the condition is, or the lower the need. An example of this is voter turnout. The higher the rate or percentile of voter turnout is, the lower the need is. We adjust asset-based indicators in our index methodology by multiplying their percentiles by -1. This way the final domain and equity index can be interpreted consistently: the higher the percentile is, the higher the need is. 

To calculate the resulting LA City Index, we take indicators within each conceptual domain and calculate a **domain index**. The domain index is calculated by taking the average of the indicator percentiles within the domain, which we call a _domain score_, and then calculating a percentile ranking of the domain score to obtain the _domain percentile_. For example, the **Democracy and Power Domain** is calculated by first taking the average of the voter turnout, limited English speaking households, and race composite score percentiles within each ZIP Code to obtain the _democracy and power domain score_. A percentile ranking is then calculated on that domain score across all the ZIP Codes to obtain the _Democracy and Power Domain percentile_. The __LA City Equity Index__ for each ZIP Code is calculated by taking the average of each of the domain scores for each ZIP Code. ZIP Codes had to have at least 50% of indicators in each domain to get a domain score and index score.

Please view our indicator scripts within each domain and our main analysis R Markdown for detailed methodology.

### Data Sources

Please visit our detailed recommendations for a list of data sources by indicator.

### Limitations

All public data sources are subject to limitations, including those used to analyze the indicators that make up this index. All of the indicators, with the exception of health/mental health services, are derived from data sources that were updated in 2021 or 2022. Not all data sources are originally published at the ZIP code level. These data sources need to be adjusted from their respective geographic level to the ZIP code level in order to be used in the index calculation.

The health/mental health services indicator is analyzed using the IRS Exempt Organizations Business Master File (EO BMF). The addresses listed on the EO BMF are an organization's headquarter address and therefore may not accurately reflect the area where services are being delivered for that organization. It is also difficult to accurately define the geographic service area of a health/mental health organization. 

There was difficulty in obtaining a comprehensive indicator to represent healthy food access. Our grocery store access indicator uses SNAP authorized-food retailers to calculate access to grocery stores and farmers markets. 

It is crucial to supplement indicator analysis with community feedback, and to ground-truth any indicator analysis and index results with community members. Working with data limitations is unavoidable, making it that much more important to embed community input throughout the analysis process and ensure that the final results reflect the true landscape and needs of LA City's various communities.  

<p align="right">(<a href="#top">back to top</a>)</p>

## Contributors

* [Elycia Mulholland-Graves](https://github.com/elyciamg)
* [Jennifer Zhang](https://github.com/jzhang514)
* [Hillary Khan](https://github.com/hillaryk-ap)
* [Jacky Guerrero](https://www.catalystcalifornia.org/who-we-are/staff/jacky-guerrero)
* [Michael Nailat](https://www.catalystcalifornia.org/who-we-are/staff/michael-nailat)
* [Kianna Ruff](https://www.catalystcalifornia.org/who-we-are/staff/kianna-ruff)
* [Mariselle Moscoso](https://www.catalystcalifornia.org/who-we-are/staff/mariselle-moscoso) 


<p align="right">(<a href="#top">back to top</a>)</p>

## Contact Us

Elycia Mulholland Graves - egraves[at]catalystcalifornia.org  <br>
Jacky Guerrero -jguerrero[at]catalystcalifornia.org

<p align="right">(<a href="#top">back to top</a>)</p>

## About Catalyst California

### Our Vision
A world where systems are designed for justice and support equitable access to resources and opportunities for all Californians to thrive.

### Our Mission
[Catalyst California](https://www.catalystcalifornia.org/) advocates for racial justice by building power and transforming public systems. We partner with communities of color, conduct innovative research, develop policies for actionable change, and shift money and power back into our communities. 

[Click here to view Catalyst California's Projects on GitHub](https://github.com/catalystcalifornia)

<p align="right">(<a href="#top">back to top</a>)</p>

## License

Distributed under the MIT License. See `LICENSE.txt` for more information.

<p align="right">(<a href="#top">back to top</a>)</p>

