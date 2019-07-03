### ui.R

ui <- function(){
  fluidPage(
    theme = "bootstrap.min.css",
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "style.css")
    ),
    fluidRow(
      mapedit::editModUI("mine_edit", width = "100%", height = "100%")
    ),
    absolutePanel( id = "controls", class = "panel panel-default", fixed = TRUE,
                   draggable = TRUE, top = 60, left = "auto", right = 20, bottom = "auto",
                   width = 250, height = "auto",
                   h2("Global Mining-Vectorisation App"),
                   wellPanel(
                     # actionButton("btn_back", "Back", icon = icon("chevron-left")),
                     actionButton("btn_help", "Help", icon = icon("ambulance")),
                     actionButton("btn_next", "Next", icon = icon("chevron-right")),
                     textAreaInput("ta_note", "Note"),
                     shinyWidgets::progressBar(id = "pb_user", value = 0, display_pct = TRUE)
                   )
    )
  )
}