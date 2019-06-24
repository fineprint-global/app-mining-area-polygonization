### app.R
# This connects all pieces of the shiny app.
# 1. source global.R
# 2. source ui and server
# 3. start the shiny app

### 1. source global.R
source("./global.R")

### 2. source ui and server
# ui
source('./ui.R')

# server 
source('./server.R')


### 3. start the shiny app
# allow bookmarking (necessary to allow saving the state of the app in a URL)
enableBookmarking(store = "url")

# run app
shiny::shinyApp(ui = ui, server = server)