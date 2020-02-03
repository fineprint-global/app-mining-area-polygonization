### global.R
# This file is loaded on startup of the app.
# Here, code that only needs to be performed once is executed.
# Typically, this includes defining libraries,
# setting up the database connection, and
# defining variables connected to database operation.

## STRUCTURE
# 1. Load packages
# 2. Data setup
# 3. Functions

##################################################################
### 1. Load packages
##################################################################

library(shiny)
library(tidyverse)
library(sf)
# devtools::install_github("Gutschlhofer/mapedit", force = TRUE)
library(mapedit) # make sure the modified version of mapedit is used
library(shiny)
library(shinyjs)
library(httr)
library(DBI)
library(pool)
library(lwgeom)

##################################################################
### 2. Data setup
##################################################################

# connect PostGIS database via a pool object for better Shiny behaviour ------------------------------------------------
pool <- pool::dbPool(
  drv = RPostgreSQL::PostgreSQL(),
  host = Sys.getenv("db_host"),
  port = Sys.getenv("db_port"),
  dbname = Sys.getenv("db_name"),
  user = Sys.getenv("db_user"),
  password = Sys.getenv("db_password"),
  minSize = 1,
  maxSize = Inf,
  idleTimeout = 300,
  validationInterval = 120
)
onStop(function() { # this is required to close the pool so we have no leaking connections
  pool::poolClose(pool)
  message("Pool closed.")
})

##################################################################
### 3. Functions
##################################################################

get_next_polygon <- function(){
  next_poly <- sf::st_read(dsn = pool, 
                           layer = NULL,
                           query = sprintf("SELECT * FROM to_update 
                                            WHERE status = 'TO_CHECK' AND id NOT IN 
                                            (SELECT id_to_update FROM updated) LIMIT 1;"))
  
  if(is.null(next_poly) | nrow(next_poly) == 0){
    return("You are done updating the polygons. Congratulations!
           Please get in contact with your supervisor!")
  }
  
  return(next_poly)
}

get_adjacent_polygons <- function(current_poly = NULL, old = TRUE){
  if(is.null(current_poly)){
    rlang::abort(message = "current_poly must be specified.")
  }
  
  if(old){
    # NOW, provide all polygons (except the one in question)
    ## 1. get the ones in to_update
    polygons_1 <- sf::st_read(dsn = pool, 
                              layer = NULL,
                              query = sprintf('SELECT * FROM to_update
                                             WHERE NOT id = %.0f AND
                                                   NOT id IN (SELECT id_to_update FROM updated) AND
                                                   ST_DWithin(geometry, 
                                                              ST_GeomFromText(\'SRID=4326; %s\'),
                                                              50000, TRUE)',
                                              current_poly$id[1],
                                              sf::st_as_text(current_poly$geometry)[1]))
    
    if(nrow(polygons_1) > 0){
      poly <- sf::st_combine(polygons_1$geometry)
    } else {
      poly <- sf::st_multipolygon() %>%
        sf::st_sfc() %>%
        sf::st_sf()
      
      sf::st_crs(poly$geometry) <- "+proj=longlat +datum=WGS84 +no_defs"
    }
  } else {
    ## 2. get the ones in updated
    polygons_2 <- sf::st_read(dsn = pool, 
                              layer = NULL,
                              query = sprintf('SELECT * FROM updated
                                             WHERE ST_DWithin(geometry, 
                                                              ST_GeomFromText(\'SRID=4326; %s\'),
                                                              50000, TRUE)',
                                              sf::st_as_text(current_poly$geometry)[1]))
    
    if(nrow(polygons_2) > 0){
      poly <- sf::st_combine(polygons_2$geometry)
    } else {
      poly <- sf::st_multipolygon() %>%
        sf::st_sfc() %>%
        sf::st_sf()
      
      sf::st_crs(poly$geometry) <- "+proj=longlat +datum=WGS84 +no_defs"
    }
  }
  
  return(poly)
}

# https://github.com/pointhi/leaflet-color-markers
get_leaflet_marker_url <- function(color = "blue"){
  return(sprintf("https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-%s.png", color))
}

# allow bookmarking (necessary to allow saving the state of the app in a URL)
enableBookmarking(store = "url")
