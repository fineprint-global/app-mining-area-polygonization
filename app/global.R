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
# devtools::install_github("r-spatial/mapedit", force = TRUE)
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

# set current version and revision
VERSION <- 1
REVISION <- 0

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

get_next_cluster <- function(user_name = NULL){
  if(is.null(user_name)){
    rlang::abort(message = "user_name must be specified.")
  }
  
  next_cluster <- RPostgreSQL::dbGetQuery(pool,
                                          sprintf("SELECT * FROM mine_cluster 
                                                   WHERE id_app_user = '%s' AND id NOT IN 
                                                   (SELECT id_mine_cluster FROM mine_polygon WHERE id_app_user = '%s') LIMIT 1;",
                                                  user_name, user_name))

  if(is.null(next_cluster) | nrow(next_cluster) == 0){
    return("You are done vectorizing all mines assigned to your user. Congratulations!
           Please get in contact with your supervisor!")
  }

  return(next_cluster)
}

get_current_cluster_points <- function(current_cluster_id = NULL){
  if(is.null(current_cluster_id)){
    rlang::abort(message = "current_cluster_id must be specified.")
  }
  
  # fetch the points for the current cluster
  cluster_points <- sf::st_read(dsn = pool, layer = NULL,
                              query = sprintf("SELECT * FROM mine_point 
                                               WHERE id_mine_cluster = %.0f", 
                                              current_cluster_id))
  
  return(cluster_points)
}

# get_current_cluster_poly <- function(current_cluster_id = NULL){
#   # fetch the most recent geometries for the current mine
#   mine_polygon <- sf::st_read(dsn = pool, layer = NULL,
#                                query = sprintf("SELECT * FROM mine_polygon WHERE id_mine_cluster = %.0f ORDER BY created_at DESC LIMIT 1", current_cluster_id))
# 
#   polygons <- mine_polygon %>%
#     lwgeom::st_make_valid() %>%
#     sf::st_cast(group_or_split = TRUE) %>%
#     dplyr::filter(sf::st_geometry_type(.) %in% c("POLYGON", "MULTIPOLYGON")) %>%
#     sf::st_cast("POLYGON")
# 
#   # this is a temporary fix as long as there are still geometries with wrong CRS in the database
#   # this should not be needed anymore
#   # sf::st_crs(polygons) <- "+proj=longlat +datum=WGS84 +no_defs"
# 
#   return(polygons)
# }

get_all_cluster_points <- function(current_cluster_buffer = NULL){
  # fetch mining areas from db
  mine_points <-
    if(is.null(current_cluster_buffer)){
      sf::st_read(dsn = pool, layer = "mine_point")
    } else {
      sf::st_read(dsn = pool, layer = NULL,
                  query = sprintf('SELECT * FROM mine_point
                                   WHERE ST_DWithin(geometry, 
                                                    ST_GeomFromText(\'SRID=4326; %s\'),
                                                    50000, TRUE)',
                                  sf::st_as_text(current_cluster_buffer[[1]])))
    }
  
  # this is to check if the table is empty
  if(nrow(mine_points) == 0){
    mine_points <- sf::st_multipolygon() %>%
      sf::st_sfc() %>%
      sf::st_sf()
  }
  
  return(mine_points)
}

get_other_cluster_polygons <- function(current_cluster_id = NULL,
                                       current_cluster_buffer = NULL){
  # fetch mining areas from db
  mine_polygons <-
    if(is.null(current_cluster_id)){
      sf::st_read(dsn = pool, layer = "mine_polygon")
    } else {
      sf::st_read(dsn = pool, layer = NULL,
                  query = sprintf('SELECT * FROM mine_polygon "mines"
                                   WHERE NOT mines.id_mine_cluster = %.0f AND
                                   ST_DWithin(geometry, ST_GeographyFromText(\'SRID=4326; %s\'), 50000, TRUE) AND
                                   created_at = (SELECT max(created_at)
                                                 FROM mine_polygon
                                                 WHERE id_mine_cluster = mines.id_mine_cluster)',
                                  current_cluster_id, sf::st_as_text(current_cluster_buffer[[1]])))
    }

  # this is to check if the table is empty
  if(nrow(mine_polygons) == 0){
    mine_polygons <- sf::st_multipolygon() %>%
      sf::st_sfc() %>%
      sf::st_sf()
  }
  
  return(mine_polygons)
}

# https://github.com/pointhi/leaflet-color-markers
get_leaflet_marker_url <- function(color = "blue"){
  return(sprintf("https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-%s.png", color))
}

# # allow bookmarking (necessary to allow saving the state of the app in a URL)
# enableBookmarking(store = "url")