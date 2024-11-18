# load libraries
library(leaflet)
library(htmlwidgets)

# copied from index.Rmd and updated
index_map <- function(df, indicator, colorpalette, nacolor="#9B9A9A", data_popup, custom_popup){
  # Function also requires the following global variables: 
  # 'cd' spatial dataframe with 'district' column
  # the 'df' spatial dataframe must have a 'pctile' column that stores the indicator layer values
  
  pctl.bins <- c(0, 20, 40, 60, 80, 100)
  
  # add color palette for Indicator Percentiles
  pal <- colorBin(palette=colorpalette, bins=pctl.bins, na.color=nacolor)
  
  # create custom legend labels
  labels <- c(
    "LOWEST NEED (0-19th Percentile)",
    "LOW NEED (20-39th Percentile)",
    "MODERATE NEED (40-59th Percentile)",
    "HIGH NEED (60-79th Percentile)",
    "HIGHEST NEED (80-100th Percentile)"
  )
  
  # map
  map <- leaflet(width = "100%", 
                 height = "600px",
                 options = leafletOptions(zoomControl = FALSE, 
                                          attributionControl=FALSE)) %>%
    
    # add base maps, panes, and set view
    addProviderTiles("CartoDB.PositronNoLabels") %>%
    addProviderTiles("CartoDB.PositronOnlyLabels", options = providerTileOptions(pane = "markerPane")) %>%
    
    addMapPane("indi_pane", zIndex = 400) %>%
    addMapPane("cd_pane", zIndex = 400) %>%
    
    setView( -118.53, 34.045, zoom = 10) %>%
    
    # add custom sidebar
    addControl(html=custom_popup, position = "topleft") %>%
    
    # Indicator layer
    addPolygons(data=df, 
                color="white",
                weight = 1, 
                smoothFactor = 0.5,
                opacity = 1.0,
                fillOpacity = 0.85, 
                fillColor = ~pal(df$pctile), 
                highlight = highlightOptions(color = "white",
                                             weight = 5, 
                                             bringToFront = TRUE, 
                                             sendToBack = TRUE), 
                group = indicator, 
                options = pathOptions(pane = "indi_pane"),
                popup = ~data_popup) %>%
    
    # CD layer
    addPolygons(data = cd, 
                opacity = 1,
                fillOpacity=0, 
                color = '#CEEA01', 
                weight = 3, 
                label=~district, 
                group = "City Council District", 
                options = pathOptions(pane = "cd_pane", 
                                      interactive = FALSE))%>%
    
    # add layers control to toggle index and districts
    addLayersControl(overlayGroups = c(indicator, "City Council District"), 
                     options = layersControlOptions(collapsed = FALSE, autoZIndex = TRUE)) %>%
    
    # add legend
    addLegend(position = "bottomleft", pal = pal, values = df$pctile, opacity = 1, 
              title = paste0(indicator, " Percentile"), labFormat = function(type, cuts, p){paste0(labels)}) %>%
    
    
    hideGroup("City Council District") 
  
  return(map)
  
}

# copied from index.Rmd and updated
domains_map <- function(df, four_domains=c(), colorpalette, nacolor="#9B9A9A", data_popup, custom_popup){
  # Function also requires the following global variables: 
  # 'cd' spatial dataframe with 'district' column
  # the 'df' spatial dataframe must have a 'pctile' column that stores the indicator layer values
  
  pctl.bins <- c(0, 20, 40, 60, 80, 100)
  
  # add color palette for Indicator Percentiles
  index_pal <- colorBin(palette=colorpalette[[1]], bins=pctl.bins, na.color=nacolor)
  domain1_pal <- colorBin(palette=colorpalette[[2]], bins=pctl.bins, na.color=nacolor)
  domain2_pal <- colorBin(palette=colorpalette[[3]], bins=pctl.bins, na.color=nacolor)
  domain3_pal <- colorBin(palette=colorpalette[[4]], bins=pctl.bins, na.color=nacolor)
  domain4_pal <- colorBin(palette=colorpalette[[5]], bins=pctl.bins, na.color=nacolor)
  
  # create custom legend labels
  labels <- c(
    "LOWEST NEED (0-19th Percentile)",
    "LOW NEED (20-39th Percentile)",
    "MODERATE NEED (40-59th Percentile)",
    "HIGH NEED (60-79th Percentile)",
    "HIGHEST NEED (80-100th Percentile)"
  )
  
  # map
  map <- leaflet(width = "100%", height = "600px",
                 options = leafletOptions(zoomControl = FALSE, 
                                          attributionControl=FALSE)) %>%
    
    # add base maps, panes, and set view
    addProviderTiles("CartoDB.PositronNoLabels") %>%
    addProviderTiles("CartoDB.PositronOnlyLabels", options = providerTileOptions(pane = "markerPane")) %>%
    
    addMapPane("indi_pane", zIndex = 400) %>%
    addMapPane("cd_pane", zIndex = 400) %>%
    
    setView( -118.53, 34.045, zoom = 10) %>%
    
    # add custom sidebar
    addControl(html=custom_popup, position = "topleft") %>%
    
    # Domain #1 layer
    addPolygons(data=df, 
                color="white",
                weight = 1, 
                smoothFactor = 0.5,
                opacity = 1.0,
                fillOpacity = 0.85, 
                fillColor = ~domain1_pal(df$safe_environments_pctile), 
                highlight = highlightOptions(color = "white",
                                             weight = 5, 
                                             bringToFront = TRUE, 
                                             sendToBack = TRUE), 
                group = four_domains[[1]], 
                options = pathOptions(pane = "indi_pane"),
                popup = ~data_popup) %>%
    
    # Domain #2 layer
    addPolygons(data=df, 
                color="white",
                weight = 1, 
                smoothFactor = 0.5,
                opacity = 1.0,
                fillOpacity = 0.85,
                fillColor = ~domain2_pal(df$econ_opp_pctile), 
                highlight = highlightOptions(color = "white", 
                                             weight = 5, 
                                             bringToFront = TRUE, 
                                             sendToBack = TRUE), 
                group = four_domains[[2]],
                options = pathOptions(pane = "indi_pane"),
                popup = ~data_popup) %>%
    
    # Domain #3 layer
    addPolygons(data=df, 
                color="white",
                weight = 1, 
                smoothFactor = 0.5,
                opacity = 1.0,
                fillOpacity = 0.85,
                fillColor = ~domain3_pal(df$democracy_pctile), 
                highlight = highlightOptions(color = "white", 
                                             weight = 5, 
                                             bringToFront = TRUE, 
                                             sendToBack = TRUE), 
                group = four_domains[[3]], 
                options = pathOptions(pane = "indi_pane"),
                popup = ~data_popup) %>%
    
    # Domain #4 layer
    addPolygons(data=df, 
                color="white",
                weight = 1, 
                smoothFactor = 0.5,
                opacity = 1.0,
                fillOpacity = 0.85,
                fillColor = ~domain4_pal(df$longevity_pctile),
                highlight = highlightOptions(color = "white", 
                                             weight = 5, 
                                             bringToFront = TRUE, 
                                             sendToBack = TRUE), 
                group = four_domains[[4]], 
                options = pathOptions(pane = "indi_pane"),
                popup = ~data_popup) %>%
    
    # CD layer
    addPolygons(data = cd, 
                opacity = 1,
                fillOpacity=0, 
                color = '#CEEA01', 
                weight = 3, 
                label=~district, 
                group = "City Council District", 
                options = pathOptions(pane = "cd_pane", 
                                      interactive = FALSE))%>%
    
    # add layers control to toggle index, domains, and districts
    addLayersControl(
      baseGroups = c(four_domains),
      overlayGroups = c("City Council District"),
      options = layersControlOptions(collapsed = FALSE, autoZIndex = TRUE)) %>%
    
    hideGroup("City Council District") 
  
  return(map)
  
}


# # copied from domains.Rmd - can probably delete
# 
# index_map2<-function(df,indicator,colorpalette,nacolor){
#   # add color palette for Indicator Percentiles
#   
#   pctl.bins <-c(0, 20, 40, 60, 80, 100)
#   
#   pal <- colorBin( palette = colorpalette, bins=pctl.bins, na.color = nacolor)
#   
#   # create custom legend labels
#   
#   labels <- c(
#     "LOWEST NEED (0-19th Percentile)",
#     "LOW NEED (20-39th Percentile)",
#     "MODERATE NEED (40-59th Percentile)",
#     "HIGH NEED (60-79th Percentile)",
#     "HIGHEST NEED (80-100th Percentile)"
#   )
#   # map
#   
#   map <- leaflet(width = "100%", height = "600px")%>%
#     
#     # add base map
#     addProviderTiles("CartoDB.PositronNoLabels") %>%
#     addProviderTiles("CartoDB.PositronOnlyLabels", options = providerTileOptions(pane = "markerPane")) %>%
#     
#     # add map panes
#     addMapPane("indi_pane", zIndex = 400) %>%
#     addMapPane("cd_pane", zIndex = 400) %>%
#     
#     # set view and layer control
#     setView( -118.353860, 34.068717, zoom = 9.5) %>%
#     
#     addLayersControl(overlayGroups = c(indicator, "City Council District"), 
#                      options = layersControlOptions(collapsed = FALSE, autoZIndex = TRUE)) %>%
#     
#     # CD layer
#     addPolygons(data = cd, fillOpacity=0, color = '#CEEA01', weight = 2.2, 
#                 label=~district, group = "City Council District", 
#                 options = pathOptions(pane = "cd_pane", interactive = FALSE), 
#                 highlight = highlightOptions(color = "white", weight = 3, 
#                                              bringToFront = TRUE))%>%
#     
#     # Indicator layer
#     addPolygons(data=df, fillColor = ~pal(df$pctile), color="white", weight = 1, 
#                 smoothFactor = 0.5, fillOpacity = .80, 
#                 highlight = highlightOptions(color = "white", weight = 3, 
#                                              bringToFront = TRUE, sendToBack = TRUE), 
#                 popup = ~popup, group = indicator, 
#                 options = pathOptions(pane = "indi_pane"))%>%
#     
#     # add legend
#     addLegend(position = "bottomleft", pal = pal, values = df$pctile, opacity = 1, 
#               title = paste0(indicator, " Percentile"), 
#               labFormat = function(type, cuts, p){paste0(labels)}) %>%
#     
#     hideGroup("City Council District")
#   
#   map
#   }