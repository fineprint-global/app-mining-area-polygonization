# --------------------------------------------------------------------------------------
# this script creates a release version of the mining polygons -------------------------

# --------------------------------------------------------------------------------------
# required packages --------------------------------------------------------------------
library(gfcanalysis)
library(RPostgreSQL)
library(tidyverse)
library(lwgeom)
library(units)
library(nngeo)
library(sf)
library(raster)
readRenviron(".Renviron")

# define release version ---------------------------------------------------------------
release_version <- "v1"

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
  smoothr::fill_holes(units::set_units(1, ha)) %>% 
  dplyr::mutate(FID = dplyr::row_number())

# --------------------------------------------------------------------------------------
# get world map from Eurostat  ---------------------------------------------------------
if(!file.exists("./countries_polygon.gpkg")){
  download.file(url = "https://ec.europa.eu/eurostat/cache/GISCO/distribution/v2/countries/download/ref-countries-2016-01m.geojson.zip",
                destfile = "./ref-countries-2016-01m.geojson.zip", mode = "w")
  unzip(zipfile = "./ref-countries-2016-01m.geojson.zip", files = "CNTR_RG_01M_2016_4326.geojson", exdir = "./", overwrite = TRUE)
  sf::st_read(dsn = "./CNTR_RG_01M_2016_4326.geojson") %>%
    dplyr::select(ISO3_CODE, COUNTRY_NAME = NAME_ENGL) %>%
    lwgeom::st_make_valid() %>% 
    sf::st_cast("POLYGON") %>% 
    sf::st_write(dsn = "./countries_polygon.gpkg", delete_dsn = TRUE)
}

world_map <- sf::st_read(dsn = "./countries_polygon.gpkg") %>% 
  sf::st_transform("+proj=laea +datum=WGS84")

# --------------------------------------------------------------------------------------
# get country names intersecting mining polygons ---------------------------------------
ids_intersects <- sf::st_intersects(mining_polygons, world_map)

# polygons with single country intersection
country_names <- world_map %>% 
  sf::st_drop_geometry() %>% 
  tibble::as_tibble() %>% 
  dplyr::slice(unlist(ids_intersects[sapply(ids_intersects, length) == 1])) %>% 
  dplyr::mutate(FID = mining_polygons$FID[sapply(ids_intersects, length) == 1])

# correct for multiple intersections by keeping only the country with the largest share of the mine in terms of area 
country_names <- mining_polygons %>% 
  dplyr::filter(FID %in% which(sapply(ids_intersects, length) > 1)) %>% 
  sf::st_intersection(world_map) %>% 
  dplyr::mutate(area = sf::st_area(geometry)) %>% 
  sf::st_drop_geometry() %>% 
  dplyr::group_by(FID) %>% 
  dplyr::top_n(1, area) %>% 
  dplyr::ungroup() %>% 
  dplyr::select(-area) %>% 
  dplyr::bind_rows(country_names)

# correct for missing intersection by selecting the closest country
country_names <- world_map %>% 
  dplyr::slice(sf::st_nearest_feature(mining_polygons[which(sapply(ids_intersects, length) < 1),], .)) %>% 
  sf::st_drop_geometry() %>% 
  tibble::as_tibble() %>% 
  dplyr::mutate(FID = mining_polygons$FID[sapply(ids_intersects, length) < 1]) %>% 
  dplyr::bind_rows(country_names)

# --------------------------------------------------------------------------------------
# calculate mining area in km^2 an join country names ----------------------------------
mining_polygons <- mining_polygons %>% 
  dplyr::left_join(country_names) %>% 
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
path_to_mining_polygons <- paste0("./global_mining_polygons_",release_version,".gpkg")
sf::st_write(mining_polygons, layer = "mining_polygons", 
             dsn = path_to_mining_polygons, delete_dsn = TRUE)

# --------------------------------------------------------------------------------------
# write summary of mining aea per country in (km2) -------------------------------------
mining_polygons %>% 
  sf::st_drop_geometry() %>% 
  dplyr::select(-FID) %>% 
  tidyr::drop_na() %>%
  dplyr::group_by(COUNTRY_NAME, ISO3_CODE) %>%
  dplyr::summarise(AREA = sum(AREA)) %>% 
  dplyr::ungroup() %>% 
  dplyr::arrange(dplyr::desc(AREA)) %>% 
  readr::write_csv(paste0("./global_mining_area_per_country_",release_version,".csv"))

# --------------------------------------------------------------------------------------
# create 30sec global grid with a percentage of mining coverage per cell ---------------
# For help see: system("./calculate_area_weights.py -h")
tmp_file <- tempfile(pattern = "file", tmpdir = tempdir(), fileext = ".tif")
system.time(system(paste0("./calculate_area_weights.py \\
                          -i ",path_to_mining_polygons," \\
                          -o ",tmp_file," \\
                          -xmin ",  -180," \\
                          -xmax ",   180," \\
                          -ymin ",   -90," \\
                          -ymax ",    90," \\
                          -ncol ", 43200," \\
                          -nrow ", 21600)))

path_to_land_mask_raster <- Sys.getenv("path_to_land_mask_raster")
path_to_mining_30sec_grid <- paste0("./global_miningcover_30sec_",release_version,".tif")
raster::beginCluster(n = 12)
system.time(raster::clusterR(x = raster::stack(list(tmp_file, path_to_land_mask_raster)), 
                             fun = raster::overlay, args = list(fun = function(x, m) x * m), 
                             filename = path_to_mining_30sec_grid, datatype = 'INT2U', options = c("compress=LZW"), overwrite = TRUE, verbose = TRUE))
raster::endCluster()
