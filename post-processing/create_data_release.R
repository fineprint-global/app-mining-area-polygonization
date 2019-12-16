library(tidyverse)
library(sf)
library(units)
library(lwgeom)
library(rmapshaper)
library(nngeo)
library(rnaturalearth)
library(gfcanalysis)
library(RPostgreSQL)

output_dsn <- "./global_mining_polygons_v1r5.gpkg"

# --------------------------------------------------------------------------------------
# get raw data from PostGIS database ---------------------------------------------------
conn <- DBI::dbConnect(RPostgreSQL::PostgreSQL(),
                       host = Sys.getenv("db_host"),
                       port = Sys.getenv("db_port"),
                       dbname = Sys.getenv("db_name"),
                       user = Sys.getenv("db_user"),
                       password = Sys.getenv("db_password"))

raw_mining_polygons <- sf::st_read(conn, "mine_polygon")

# --------------------------------------------------------------------------------------
# clean overlaps, invalid shapes, and islands smaller than 1ha -------------------------
mining_polygons <- raw_mining_polygons %>% 
  sf::st_geometry() %>% 
  rmapshaper::ms_explode(sys = TRUE) %>% 
  rmapshaper::ms_dissolve(snap = TRUE, sys = TRUE) %>% 
  rmapshaper::ms_clip(bbox = c(-180, -90, 180, 90), sys = TRUE) %>% 
  rmapshaper::ms_filter_islands(min_area = 10000, sys = TRUE) %>% 
  rmapshaper::ms_explode(sys = TRUE) %>% 
  lwgeom::st_make_valid() %>% 
  sf::st_sf() %>% 
  dplyr::mutate(is_poly = sf::st_is(geometry, "POLYGON")) %>%
  dplyr::filter(is_poly) %>%
  dplyr::select(-is_poly) %>% 
  sf::st_transform("+proj=laea +datum=WGS84")
  
# --------------------------------------------------------------------------------------
# join mining polygons to country names ------------------------------------------------
mining_polygons <- rnaturalearth::ne_countries(scale = 'small') %>% 
  sf::st_as_sf() %>% 
  dplyr::select(COUNTRY = name, ISO_A3 = iso_a3, CONTINENT = continent) %>% 
  sf::st_transform("+proj=laea +datum=WGS84") %>% 
  sf::st_join(y = mining_polygons,
              left = FALSE, 
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
    AREA = purrr::map_dbl(.x = geom, crs = sf::st_crs(.), .pb = dplyr::progress_estimated(length(geom)), 
                          .f = function(x, crs, .pb = NULL) {
                            if(!is.null(.pb)) .pb$tick()$print()
                            sf::st_sfc(x, crs = crs) %>% 
                              sf::st_transform(gfcanalysis::utm_zone(sf::as_Spatial(.), proj4string = TRUE)) %>%
                              sf::st_area() %>%
                              units::set_units(km^2)
                            })
    ) 

sf::st_write(mining_polygons, dsn = output_dsn)
DBI::dbDisconnect(conn)

