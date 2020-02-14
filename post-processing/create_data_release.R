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
library(xml2)
library(stringr)
library(viridis)
source("./R/gs_create_sld_color_palette.R")
source("./R/gs_create_jenks_breaks_color_palette.R")


# define release version ---------------------------------------------------------------
release_version <- "v1"
dir.create("./output", showWarnings = FALSE, recursive = TRUE)

# --------------------------------------------------------------------------------------
# get raw data -------------------------------------------------------------------------
raw_mining_polygons <- sf::st_read("./input/global_mining_polygons_v1r6_raw.gpkg")

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
if(!file.exists("./output/countries_polygon.gpkg")){
  download.file(url = "https://ec.europa.eu/eurostat/cache/GISCO/distribution/v2/countries/download/ref-countries-2016-01m.geojson.zip",
                destfile = "./output/ref-countries-2016-01m.geojson.zip", mode = "w")
  unzip(zipfile = "./output/ref-countries-2016-01m.geojson.zip", files = "CNTR_RG_01M_2016_4326.geojson", exdir = "./output", overwrite = TRUE)
  sf::st_read(dsn = "./output/CNTR_RG_01M_2016_4326.geojson") %>%
    dplyr::select(ISO3_CODE, COUNTRY_NAME = NAME_ENGL) %>%
    lwgeom::st_make_valid() %>% 
    sf::st_cast("POLYGON") %>% 
    sf::st_write(dsn = "./output/countries_polygon.gpkg", delete_dsn = TRUE)
}

world_map <- sf::st_read(dsn = "./output/countries_polygon.gpkg") %>% 
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
path_to_mining_polygons <- paste0("./output/global_mining_polygons_",release_version,".gpkg")
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
  readr::write_csv(paste0("./output/global_mining_area_per_country_",release_version,".csv"))

# --------------------------------------------------------------------------------------
# create global 30arcsecond grid (approximately 1 kilometer) 
# with the mining area weights per cell 
# For help see: system("./calculate_area_weights.py -h")
path_to_area_weights <- "./output/tmp_global_mining_area_weights_30arcsecond.tif"
path_to_land_mask <- Sys.getenv(paste0("path_to_land_mask_30arcsecond"))
system.time(system(paste0("./calculate_area_weights.py \\
                          -i ",path_to_mining_polygons," \\
                          -o ",path_to_area_weights," \\
                          -xmin ",  -180," \\
                          -xmax ",   180," \\
                          -ymin ",   -90," \\
                          -ymax ",    90," \\
                          -ncol ",  43200," \\
                          -nrow ",  21600)))

# mask land 30arcsecond grid (approximately 1 kilometer) 
raster::rasterOptions(progress = "text")
raster::beginCluster(n = 12)

r_prec <- raster::stack(raster::raster(path_to_land_mask), raster::raster(path_to_area_weights)) %>% 
  raster::clusterR(raster::overlay, args = list(fun = function(m, w) m * w),
                   filename = paste0("./output/global_miningarea_percentage_", release_version,"_30arcsecond.tif"), 
                   datatype = 'INT1U', options = "compress=LZW", overwrite = TRUE, verbose = TRUE)

r_area <- raster::stack(list(a = raster::area(r_prec), w = r_prec)) %>% 
  raster::clusterR(raster::overlay, args = list(fun = function(a, w) a * w / 100),
                   filename = paste0("./output/global_miningarea_", release_version,"_30arcsecond.tif"),
                   datatype = 'FLT4S', options = "compress=LZW", overwrite = TRUE, verbose = TRUE)

grid_levels <- tibble::tribble(        ~name, ~fact,
                                "5arcminute",    10, # aggregation factor from 30arcsecond to 5arcminute (approximately 10 kilometer)
                               "30arcminute",    60) # aggregation factor from 30arcsecond to 30arcminute (approximately 55 kilometer)

for(g in 1:nrow(grid_levels) ){

  fact <- grid_levels$fact[g]
  grid_name <- grid_levels$name[g]
  fname_perc <- paste0("./output/global_miningarea_percentage_",release_version,"_",grid_name,".tif")
  fname_area <- paste0("./output/global_miningarea_",release_version,"_",grid_name,".tif")
  
  print(paste("Writing", grid_name, "grid to", fname_perc))
  print(paste("Aggregation factor ", fact))
  
  print(paste("Aggregate grid cell area to ", grid_name))
  r_agg_area <- raster::aggregate(r_area, fact = fact, fun = sum, na.rm = TRUE, 
                                  filename = fname_area, datatype = 'FLT4S', options = "compress=LZW", overwrite = TRUE, verbose = TRUE)
  
  
  r_agg_prec <- raster::stack(list(ta = raster::area(r_agg_area), ma = r_agg_area)) %>% 
    raster::clusterR(raster::overlay, args = list(fun = function(ta, ma) round(ma / ta * 100)), 
                     filename = fname_perc, datatype = 'INT1U', options = "compress=LZW", overwrite = TRUE, verbose = TRUE)

}

# Create Geoserver visualization layer 5arcminute grid (approximately 1 kilometer) 
gs_file <- paste0("./output/global_miningarea_percentage_",release_version,"_",grid_name,"_gs.tif")
paste0("./output/global_miningarea_percentage_",release_version,"_5arcminute.tif") %>% 
  raster::raster() %>% 
  raster::clusterR(raster::overlay, args = list(fun = function(w) w / w * w),
                   filename = gs_file, datatype = 'INT1U', options = "compress=LZW", overwrite = TRUE, verbose = TRUE)

print("Calculating Jenks Natural Breaks for visualization")
gs_create_jenks_breaks_color_palette(src = gs_file, k = 10) %>% 
  gs_create_sld_color_palette() %>% 
  xml2::write_xml(stringr::str_replace_all(gs_file, ".tif", ".xml"))

raster::endCluster()
