# MLAW Los Angeles City Equity Index

<br>

<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a></li>
    <li><a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#data-methodology">Data Methodology</a>
      <ul>
        <li><a href="#data-dictionary">Data Dictionary</a></li>
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
    <li><a href="#partners">Partners</a></li>
  </ol>
</details>

## About The Project

The Los Angeles (LA) City Equity Index is a tool that the City Administrative Office (CAO) office is in the process of implementing to inform how city budget dollars are allocated. Tools like this are important to ensure that communities most negatively impacted by redlining, disinvestment and systemic racism are given higher priority when it comes to investment, or protection against budget cuts. The following [analysis](https://catalystcalifornia.github.io/mlaw/la_city_equity_index), created with the MLAW coalition, recommends indicators, an equity index, and a conceptual framework for understanding the indicators and why they are important to Angelenos.  We also map the results of the  equity index and the individual indicators to show which parts of the city are "higher need," or need more investment or protections from budget cuts. The results were groundtruthed by partner organizations in the MLAW coalition. All indicators are correlated with race to ensure that groups most impacted by systemic racism are also being prioritized within the index.  

<li><a href="https://catalystcalifornia.github.io/mlaw/la_city_equity_index">Link to online index analysis and results</a></li>

<p align="right">(<a href="#top">back to top</a>)</p>


### Built with

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
```

<p align="right">(<a href="#top">back to top</a>)</p>


## Data Methodology

### Indicator Selection

The MLAW equity index was created by first gathering community input from various sources to determine what issue areas, and subsequently indicators, were important to prioritize for inclusion in the index. Community input was gathered directly from MLAW partner organizations, and from a survey that MLAW partners distributed to their respective community constituents. A final list of indicators was produced and vetted by the MLAW coalition after cross-referencing the survey results and partner feedback. Additional criteria used for indicator inclusion was that the data source was somewhat up-to-date, the data source was updated on a semi-regular basis, and that the data source was available at a sub-city level. 

### LA City Crosswalk

The final set of indicators and the equity index is analyzed at the LA city zipcode level. To achieve this, we create an LA city zipcode crosswalk that lists the zipcodes that are mostly in LA city boundaries. We define this as zipcodes with at least 25% of its geological area within LA city limits. We manually exclude the following zipcodes from the crosswalk and overall analysis: 90095 (UCLA), 90089 (USC), 91330 (CSU Northridge), and 90090 (Dodger Stadium). 

### Indicator Domains

The final set of indicators are grouped into four conceptual domains:
* Safe Environments: LA City residents experience safe environments with safety from pollution, traffic injuries, and harmful policing.
* Economy and Opportunity: LA City residents have the opportunity to equitably engage in the economy.
* Democracy and Power: LA City residents have the opportunity to equitably participate and influence democracy.
* Longevity and Vitality: LA City live with with freedom from disease and illness, and have the ability to access resources that increase community wellness.

### Analysis

All indicators are individually analyzed at the zipcode level by calculating the rate of each indicator for each zipcode. A percentile ranking is then measured for each indicator across all of the zipcodes. The higher the indicator percentile ranking is for a zipcode, the higher the rate of a particular indicator is for that zipcode relative to other zipcodes. Percentile rankings are the primary way we determine which zipcodes are "high need" relative to others. Most indicators we use are challenge-based, meaning that the higher the percentile ranking is, the higher the need is. For example, indicators such as rent burden or arrests, we want to observe lower rates of. The higher the rate of rent burden is, the higher the need is. We also use indicators that are asset-based, meaning that the higher the rate is, the better the condition is. An example of this is voter turnout. The higher the rate of voter turnout is, the lower the need is. We adjust asset-based indicators by multiplying the rate with -1. This way, across all indicators, the higher the percentile is, the higher the need is. 

We then take indicators within each conceptual domain and calculate a __domain index__. The domain index is calculated by taking the average of the indicator percentiles within the domain, which we call a domain score, and then calculating a percent ranking of the domain scores to obtain the domain percentiles. For example, the __Democracy and Power Domain Index__ is calculated by first taking the average of the voter turnout, limited english speaking households, and race composite score percentiles within each zipcode to obtain the democracy and power domain score. A percent ranking is then calculated on that average across all the zipcodes to obstain the democracy and power domain percentile. The __Equity Index__ for each zipcode is calculated by taking the average of each of the domain scores for each zipcode. ZIP Codes had to have at least 50% of indicators in a domain to get a domain score and index score.




| Domain                         | Description    | Indicators                                                                                                                                                                                      |
| ----------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Safe Environments | LA City residents experience safe environments with safety from pollution, traffic injuries, and harmful policing. | Race Composite Score (Black, Latine, AIAN, NHPI, Asian); Particulate Matter (PM) 2.5; Proximity to Hazardous Waste Facilities; Pedestrian and Bicyclist Fatalities and Injuries; Arrests; Hospitalizations for Gun Injuries |
| Economy and Opportunity | LA City residents have the opportunity to equitably engage in the economy. | Race Composite Score (Black, Latine, AIAN, NHPI, Asian); Early Childhood Education (ECE) Enrollment; Rent Burden; Evictions; Per Capita Income |           
| Democracy and Power | LA City residents have the opportunity to equitably participate and influence democracy. | Race Composite Score (Black, Latine, AIAN, NHPI, Asian); Limited English Speaking Households; Voter Turnout for the 2022 General Election | 
| Longevity and Vitality | LA City residents live with freedom from disease and illness, and have the ability to access resources that increase community wellness. | Race Composite Score (Black, Latine, AIAN, NHPI, Asian); Diabetes Hospitalizations; Impervious Land Cover; Health and Mental Health Care Services Access; Grocery Store Access |

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
Jacky Guerrero -jgguerrero[at]catalystcalifornia.org

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

## Partners

This work would not have been possible without the collaboration and invaluable insights provided by the partners in the MLAW coalition: 

* [Community Coalition](https://cocosouthla.org/)
* [Inner City Struggle](https://www.innercitystruggle.org/)
* [Black Women for Wellness](https://bwwla.org/)
* [Brotherhood Crusade](https://www.brotherhoodcrusade.org/)
* [SEIU 2015](https://www.seiu2015.org/)
* [SEIU 99](https://www.seiu99.org/)
* [Catalyst California](https://www.catalystcalifornia.org/)

<p align="right">(<a href="#top">back to top</a>)</p>
