# -------------------------
# Setup
# -------------------------

library(shiny) 
library(leaflet)
library(RColorBrewer)
library(plyr)
library(ggplot2)
library(shinydashboard)


VariableDisplay <- read.csv("https://raw.githubusercontent.com/mikey-harper/ShinyApps/master/WindTurbineMapUK/data/VariableDisplayNames.csv")


# --- Functions
matchNames <- function(inputNames){
  # Matches variable names with their full descriptive name. Used when plotting or showing
  # results in a table
  #
  names <- VariableDisplay
  return(names[match(x = inputNames, table = names$Label, nomatch = ""), 2])
}


# Load Data
REPD <- read.csv("https://raw.githubusercontent.com/mikey-harper/ShinyApps/master/WindTurbineMapUK/TurbineAllData.csv", stringsAsFactors = FALSE)

# -------------------------
# User Interface
# -------------------------

# Design the User Interface
header <- dashboardHeader(title = "UK Onshore Wind Map", titleWidth = 450)

sidebar <- dashboardSidebar(
  
  # --- Data Filters
  
  tags$hr (),
  tags$h3 (" Data Filters"),
  checkboxGroupInput("status", "Planning Status", c(unique(REPD$Status.Summary)), selected = c(unique(REPD$Status.Summary))),
  sliderInput(inputId = "year", label = "Year of Planning", min = 1990, max = 2017, step = 1, value = c(1900,2017), sep = "", dragRange = TRUE),
  sliderInput(inputId = "capacity", label = "Wind Farm Capacity (MW)", min = min(REPD$Capacity), max = max(REPD$Capacity), step = 1, 
              value = c(min(REPD$Capacity),max(REPD$Capacity)), sep = "", dragRange = TRUE),
  selectInput("county", "County", c("All", sort(unique(REPD$County)))),
  tags$h3("Advanced Search"),
  selectizeInput("RefID", "Search by Ref ID", choices = unique(REPD$Ref.ID), selected = NULL, multiple = TRUE, options = list(create = TRUE)),
  tags$h3 (" Display Settings"),
  selectInput(inputId = "markerdisplay", label = "Variable to Display",
              choices = c("Planning Status" = "Status.Summary", "Capacity", "Turbine Capacity" = "Turbine.Capacity..MW.", "Total Capacity" = "Capacity",
                          "Number of Turbines" = "No..of.Turbines", "Turbine Height" = "Height.of.Turbines..m.", "Development Status" = "Development.Status",
                          "Year" = "Year"), selected = "Planning Status"),
  sliderInput("markersize", "Select Marker Size", 1, 10, 5, step = 0.5),
  
  tags$hr ()
)

# Main Panel
Panel1 <- tabPanel("Map & Stats",
                   fluidRow( column(width = 8, box(width = 12, 
                                                   leafletOutput("lmap", width = "100%", height = "800"))),
                             uiOutput("sidebar")
                   )
)

# Data Table Panel
Panel2 <- tabPanel("Data",
                   fluidRow(
                     column(width = 12,
                            tags$body("This table displays the data as specified within the filters. The data can exported using the button below the table"),
                            
                            dataTableOutput("table"))
                   )
)

# Analysis Panel                 
Panel3 <- tabPanel("Analysis",
                   fluidRow(box("To be added")
                   )
                   
)

body <- dashboardBody(
  tabsetPanel(Panel1, Panel2, Panel3)
)

ui <- dashboardPage(header, sidebar, body)

# -------------------------
# Server Processing
# -------------------------

server <- function(input, output){
  
  # Function first filters the data by the user selection
  inputTable <- reactive({
    Table <- REPD[REPD$Status.Summary %in% input$status &
                    REPD$Year %in% input$year[[1]]:input$year[[2]] &
                    REPD$Capacity >= input$capacity[[1]] &
                    REPD$Capacity <= input$capacity[[2]],
                  ] # Apply Planning Status Filter
    
    if(input$county != "All"){Table <- Table[Table$County %in% input$county,]}
    
    if(!is.null(input$RefID)){Table <- Table[Table$Ref.ID %in% unlist(input$RefID), ]}
    return(Table)
  })
  
  # --- Produce Map based on filtered data
  
  # Create Basemap
  map <- leaflet(REPD) %>%
    addTiles() %>%
    addProviderTiles(providers$Esri.WorldImagery, options = providerTileOptions(noWrap = TRUE), group = "Imagery") %>%
    addProviderTiles(providers$Stamen.TonerLite, options = providerTileOptions(noWrap = TRUE), group = "Basic") %>%
    addLayersControl(baseGroups = c("Map", "Basic"), options = layersControlOptions(collapsed = FALSE))
  
  # Update Map when filter is changed
  output$lmap <- renderLeaflet(map)
  
  # --- Plots Points

  observe({
    if(nrow(inputTable())==0) {leafletProxy("lmap") %>% clearShapes()}
    else{
      
      # Display Column
      Data <- inputTable()
      
      FilteredData <- Data[Data[[input$markerdisplay]] != "",] # Remove any blank values from the display
      DisplayVariable <- FilteredData[[input$markerdisplay]] # Extract the display variable as a list
      
      id <-  as.vector(Data$Ref.ID)
      
      popup <- paste0("<b>Site Name</b>: ", FilteredData$Site.Name, tags$br(), 
                      "<b>Project Size</b>: ", FilteredData$Capacity, "MW", tags$br(),
                      "<b>Year</b>: ", FilteredData$Year, tags$br(),
                      "<b>Number of Turbines</b>: ", FilteredData$No..of.Turbines, tags$br(),
                      "<b>Development Status</b>:", FilteredData$Development.Status, tags$br(),
                      "<b>Planning Application:</b>: ", FilteredData$Planning.Application.Reference)
      
      # Build Colour Palettes based on the type of input data
      if(class(DisplayVariable)=="character" & length(unique(DisplayVariable)) <= 2){
        domainValues <- unique(DisplayVariable)
        pallete <- c("Red", "Green")
        pal <- colorFactor(pallete, domainValues,  na.color = "#808080")
      }
      if(class(DisplayVariable)=="character" & length(unique(DisplayVariable)) > 2){
        domainValues <- unique(DisplayVariable)
        pallete <- RColorBrewer::brewer.pal(length(domainValues), "Set2")
        pal <- colorFactor(pallete, domainValues,  na.color = "#808080")
      }
      if(is.numeric(DisplayVariable)| is.integer(DisplayVariable)){
        Low <- min(as.numeric(DisplayVariable), na.rm = TRUE)
        High <- max(as.numeric(DisplayVariable), na.rm = TRUE)
        domainValues <- round(Low - 0.5):round(High - 0.5)
        pal <- colorNumeric(c("red", "green"), domainValues,  na.color = "#808080")
      }
      else{pal <- colorFactor(pallete, unique(DisplayVariable),  na.color = "#808080")}
      
      
      # Add points to map based on filtered data
      leafletProxy("lmap", data = FilteredData) %>%
        clearMarkers() %>%
        removeControl(layerId = "Legend") %>%
        addCircleMarkers(lng=~lon, lat=~lat, radius = input$markersize, popup = popup, layerId = id,  fillColor = pal(DisplayVariable), fillOpacity = 0.8, stroke = TRUE, weight = 1, color = "black") %>%
        fitBounds(~min(lon), ~min(lat), ~max(lon), ~max(lat)) %>%
        addLegend("bottomright", pal = pal, values = domainValues, opacity = 1, title = input$markerdisplay, layerId = "Legend")
    }
  })
  
  
  
  # Find which point is selected
  observe({
    click <- input$lmap_marker_click
    
    # Create Display message
    if(is.null(click)){text <- "Click a point on the map to view a full breakdown of the survey results"}
    else{text<-click$id}
    
    output$Click_text<-renderText(text)
    
    # Create a table for the individual surveys
    output$PointResult <- renderDataTable({
      if(is.null(click)){return(NA)} # Skip if no point has been clicked
      
      # Filter and transpose
      Data <- REPD
      values <- Data[Data$Ref.ID==click$id, 1:which(names(REPD) == "Est_Turbine.Capacity..MW.")-1] %>%
        t()
      
      # Create a dataframe of the values 
      b <- data.frame("Parameter" = row.names(values),
                      "Value" = values[,1],
                      row.names = NULL)
      
      # Filters to only show complete values
      b$Parameter <- matchNames(b$Parameter)
      completeValues <- b[b$Parameter != "",]
      
      
      return(completeValues)
    },  options = list(dom = 't', width = '100%', pageLength = 200))
    
    
    # Show the predicted scores for each parameter
    output$PredictedProbability <- renderDataTable({
      if(is.null(click)){return(NA)} # Skip if no point has been clicked
      
      # Filter and transpose
      Data <- REPD
      values <- Data[Data$Ref.ID==click$id, which(names(REPD) == "Est_Turbine.Capacity..MW."):ncol(Data)] %>%
        t()
      
      # Create a dataframe of the values 
      b <- data.frame("Parameter" = row.names(values),
                      "Value" = values[,1],
                      row.names = NULL)
      
      # Filters to only show complete values
      completeValues <- b[(complete.cases(b) & !is.na(b$Value) & b$Value != ""),]
      
      return(completeValues)
    },  options = list(dom = 't', width = '100%', pageLength = 200))
    
    
    # Print text of the planning acceptance rates of the selected turbine
    output$Acceptability <- renderText({
      if(is.null(click)){return(NA)} # Skip if no point has been clicked
      
      # Filter and transpose
      Data <- REPD
      score <- Data[Data$Ref.ID==click$id, names(Data) == "Site.Score"]
      
      return(paste0("Predicted Acceptance Rate: ", round(score * 100, 0), "%"))
    })
    
    output$report <- downloadHandler(
        filename = paste0("TurbineInformation_", input$TurbineRef, ".pdf"),
        content = function(file) {
          # Copy the report file to a temporary directory before processing it, in
          # case we don't have write permissions to the current working dir (which
          # can happen when deployed).
          tempReport <- file.path(tempdir(), "report.Rmd")
          file.copy("report.Rmd", tempReport, overwrite = TRUE)
          
          # Set up parameters to pass to Rmd document
          params <- list(n = input$TurbineRef)
          
          # Knit the document, passing in the `params` list, and eval it in a
          # child of the global environment (this isolates the code in the document
          # from the code in this app).
          rmarkdown::render(tempReport, output_file = file,
                            params = params,
                            envir = new.env(parent = globalenv())
          )
        }
      )
    
    
    ### --- Output Results
    
    # Show Output Table
    output$table <- renderDataTable({
      inputTable()
      },
      options = list(scrollX = TRUE, pageLength = 5,  drawCallback = I("function( settings ) {document.getElementById('ex1').style.width = '600px';}")))
  
  
    output$sidebar <- renderUI({
      column(width = 4,
             box(title="About this Work", width = 12, status = "warning",
                 tags$body('This dashboard presents part of the analysis of wind turbine acceptance rates in the UK by Michael Harper. Read the research paper here: '),
                 tags$a("Link to Paper", href="https://eprints.soton.ac.uk/408181/")),
             box(title="Detailed Survey Results", width = 12, status = "primary", collapsible = TRUE, collapsed = FALSE,
                 wellPanel(id = "tPanel",style = "overflow-y:scroll; height: 300px; max-height: 100%",
                           dataTableOutput("PointResult"))
             ),
             box(title="Export Results", width = 12, status = "primary", collapsible = TRUE, collapsed = FALSE,
                 tags$body("Generate a Detailed PDF report on a particular site"),
                 selectizeInput("TurbineRef", "Search by Ref ID", choices = unique(REPD$Ref.ID), selected = NULL, multiple = FALSE, options = list(create = TRUE)),
                 downloadButton("report", "Download a Detailed Report"),
                 tags$br(),
                 tags$h5("Note: this takes about 30 seconds to run. Depending on your browser, it may open a new window")
             )
             )
      })
  })
  
}


# Run the app
# -----------------------
shinyApp(ui, server)