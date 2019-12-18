# --------------------------------------------------------------------------------------
# this script creates a release version of the mining polygons -------------------------
# define release version ---------------------------------------------------------------
release_version <- "v1"

# --------------------------------------------------------------------------------------
# required packages --------------------------------------------------------------------
library(rnaturalearth)
library(gfcanalysis)
library(RPostgreSQL)
library(tidyverse)
library(lwgeom)
library(units)
library(nngeo)
library(sf)

# --------------------------------------------------------------------------------------
# get raw data from PostGIS database ---------------------------------------------------
conn <- DBI::dbConnect(RPostgreSQL::PostgreSQL(),
                      host = Sys.getenv("db_host"),
                      port = Sys.getenv("db_port"),
                      dbname = Sys.getenv("db_name"),
                      user = Sys.getenv("db_user"),
                      password = Sys.getenv("db_password"))

raw_mining_polygons <- sf::st_read(conn, "mine_polygon")

DBI::dbDisconnect(conn)

# --------------------------------------------------------------------------------------
# clean overlaps, invalid shapes, and holes smaller than 1ha ---------------------------
mining_polygons <- raw_mining_polygons %>% 
  dplyr::filter(!sf::st_is_empty(.)) %>% 
  sf::st_geometry() %>% 
  lwgeom::st_make_valid() %>% 
  sf::st_transform("+proj=laea +datum=WGS84") %>%
  sf::st_union() %>% 
  sf::st_cast("POLYGON") %>% 
  sf::st_sf() %>% 
  dplyr::filter(sf::st_is(geometry, "POLYGON")) %>% 
  smoothr::fill_holes(units::set_units(1, ha)) 

# --------------------------------------------------------------------------------------
# join mining polygons to country names ------------------------------------------------
mining_polygons <- rnaturalearth::ne_countries(scale = 'small') %>% 
  sf::st_as_sf() %>% 
  dplyr::select(ISO3_CODE = iso_a3, COUNTRY_NAME = name, CONTINENT = continent) %>% 
  sf::st_transform("+proj=laea +datum=WGS84") %>% 
  sf::st_join(x = mining_polygons,
              y = .,
              left = TRUE, 
              join = nngeo::st_nn, 
              sparse = TRUE, 
              k = 1, 
              maxdist = 50000, 
              progress = TRUE)

# --------------------------------------------------------------------------------------
# calculate mining area in km^2 --------------------------------------------------------
mining_polygons <- mining_polygons %>% 
  sf::st_transform("+proj=longlat +datum=WGS84") %>% 
  dplyr::mutate(
    AREA = purrr::map_dbl(.x = geometry, crs = sf::st_crs(.), .pb = dplyr::progress_estimated(length(geometry)), 
                          .f = function(x, crs, .pb = NULL) {
                            if(!is.null(.pb)) .pb$tick()$print()
                            sf::st_sfc(x, crs = crs) %>% 
                              sf::st_transform(gfcanalysis::utm_zone(sf::as_Spatial(.), proj4string = TRUE)) %>%
                              sf::st_area() %>%
                              units::set_units(km^2)
                            })
    ) 

# --------------------------------------------------------------------------------------
# write release data to GeoPackage -----------------------------------------------------
sf::st_write(mining_polygons, layer = "mining_polygons", 
             dsn = paste0("./global_mining_polygons_",release_version,".gpkg"), delete_dsn = TRUE)

