# --------------------------------------------------------------------------------------
# this script creates grid talies with the percentage of mining cover per grid cell 
# based ond the mining polygons 
# --------------------------------------------------------------------------------------
release_version <- "v1"

# --------------------------------------------------------------------------------------
# required packages --------------------------------------------------------------------
# this script also depends on the python libraries: sys, argparse, multiprocessing,
# rasterio, fiona, numpy, shapely, joblib, delayed, affine and the python script ./calculate_area_weights.py
library(tidyverse)
library(raster)
readRenviron(".Renviron")

# --------------------------------------------------------------------------------------
# define input parameters --------------------------------------------------------------
release_version <- "v1"
mining_polygons_file_path <- paste0("./global_mining_polygons_",release_version,".gpkg")
mining_gir_path <- Sys.getenv("mining_gir_path") # Output path 
tile_grid_path <- Sys.getenv("tile_grid_path")   # Hansen_GFC-2017-v1.5_treecover2000* files 
dir.create(mining_gir_path, recursive = TRUE, showWarnings = FALSE)

# --------------------------------------------------------------------------------------
# create mining grid tiles -------------------------------------------------------------
tiles <- dir(tile_grid_path, pattern = ".tif$", full.names = TRUE)
pb <- progress_estimated(length(tiles))
for(tl in tiles){

  # get tile 
  r_tl <- raster::raster(tl)
  
  # set output file name 
  out_tl_path <- basename(tl) %>%
    stringr::str_replace("Hansen_GFC-2017-v1.5_treecover2000", paste0("/miningcover_1arcsecond_",release_version)) %>%
    stringr::str_glue(mining_gir_path, .)

  # calculate tile area weights 
  # For help see: system("./calculate_area_weights.py -h")
  system(paste0("./calculate_area_weights.py \\
                -i ",mining_polygons_file_path," \\
                -o ",out_tl_path," \\
                -xmin ",extent(r_tl)[1]," \\
                -xmax ",extent(r_tl)[2]," \\
                -ymin ",extent(r_tl)[3]," \\
                -ymax ",extent(r_tl)[4]," \\
                -ncol ",ncol(r_tl)," \\
                -nrow ",nrow(r_tl)))

  pb$tick()$print()
  
}


