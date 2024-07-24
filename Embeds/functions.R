# load libraries
library(leaflet)

# copied from index.Rmd
index_map <- function(df, indicator, colorpalette, nacolor, popup){
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
  map <- leaflet(width = "100%", height = "600px") %>%
    # add base map
    addProviderTiles("CartoDB.PositronNoLabels") %>%
    addProviderTiles("CartoDB.PositronOnlyLabels", options = providerTileOptions(pane = "markerPane")) %>%
    
    # add map panes
    addMapPane("indi_pane", zIndex = 400) %>%
    addMapPane("cd_pane", zIndex = 400) %>%
    
    # set view and layer control
    setView( -118.353860, 34.068717, zoom = 9.5) %>%
    
    addLayersControl(overlayGroups = c(indicator, "City Council District"), 
                     options = layersControlOptions(collapsed = FALSE, autoZIndex = TRUE)) %>%
    
    # CD layer
    addPolygons(data = cd, fillOpacity=0, color = '#CEEA01', weight = 2.2, 
                label=~district, group = "City Council District", 
                options = pathOptions(pane = "cd_pane", interactive = FALSE), 
                highlight = highlightOptions(color = "white", weight = 3, bringToFront = TRUE))%>%
    
    # Indicator layer
    addPolygons(data=df, fillColor = ~pal(df$pctile), color="white", weight = 1, 
                smoothFactor = 0.5, fillOpacity = .80, 
                highlight = highlightOptions(color = "white", weight = 3, bringToFront = TRUE, sendToBack = TRUE), 
                popup = ~popup, group = indicator, options = pathOptions(pane = "indi_pane"))%>%
    
    # add legend
    addLegend(position = "bottomleft", pal = pal, values = df$pctile, opacity = 1, 
              title = paste0(indicator, " Percentile"), labFormat = function(type, cuts, p){paste0(labels)}) %>%
    
    hideGroup("City Council District")
  
  map
  
}

# copied from domains.Rmd

index_map2<-function(df,indicator,colorpalette,nacolor){
  # add color palette for Indicator Percentiles
  
  pctl.bins <-c(0, 20, 40, 60, 80, 100)
  
  pal <- colorBin( palette = colorpalette, bins=pctl.bins, na.color = nacolor)
  
  # create custom legend labels
  
  labels <- c(
    "LOWEST NEED (0-19th Percentile)",
    "LOW NEED (20-39th Percentile)",
    "MODERATE NEED (40-59th Percentile)",
    "HIGH NEED (60-79th Percentile)",
    "HIGHEST NEED (80-100th Percentile)"
  )
  # map
  
  map<-leaflet(width = "100%", height = "600px")%>%
    
    # add base map
    addProviderTiles("CartoDB.PositronNoLabels") %>%
    addProviderTiles("CartoDB.PositronOnlyLabels", options = providerTileOptions(pane = "markerPane")) %>%
    
    # add map panes
    addMapPane("indi_pane", zIndex = 400) %>%
    addMapPane("cd_pane", zIndex = 400) %>%
    
    # set view and layer control
    setView( -118.353860, 34.068717, zoom = 9.5) %>%
    
    addLayersControl(overlayGroups = c(indicator, "City Council District"), 
                     options = layersControlOptions(collapsed = FALSE, autoZIndex = TRUE)) %>%
    
    # CD layer
    addPolygons(data = cd, fillOpacity=0, color = '#CEEA01', weight = 2.2, label=~district, group = "City Council District", options = pathOptions(pane = "cd_pane", interactive = FALSE), highlight = highlightOptions(color = "white", weight = 3, bringToFront = TRUE))%>%
    
    # Indicator layer
    
    addPolygons(data=df, fillColor = ~pal(df$pctile), color="white", weight = 1, smoothFactor = 0.5, fillOpacity = .80, highlight = highlightOptions(color = "white", weight = 3, bringToFront = TRUE, sendToBack = TRUE), 
                popup = ~popup,
                group = indicator, options = pathOptions(pane = "indi_pane"))%>%
    
    # add legend
    
    addLegend(position = "bottomleft", pal = pal, values = df$pctile, opacity = 1, title = paste0(indicator, " Percentile"), labFormat = function(type, cuts, p){paste0(labels)}) %>%
    hideGroup("City Council District")
  
  map}