library(sf)
library(DBI)
library(tidyverse)

# --------------------------------------------------------------------------------------
# connect PostGIS mine vector database -------------------------------------------------
conn <- DBI::dbConnect(
  drv = RPostgreSQL::PostgreSQL(),
  host = Sys.getenv("db_host"),
  port = Sys.getenv("db_port"),
  dbname = Sys.getenv("db_name"),
  user = Sys.getenv("db_admin_user"),
  password = Sys.getenv("db_admin_password"),
)

# --------------------------------------------------------------------------------------
# read mines from files ----------------------------------------------------------------
to_update_tbl <- sf::st_read(dsn = "./app_edit/db/polygons_to_check_v1.gpkg", 
                              stringsAsFactors = FALSE) %>% 
  dplyr::select(geom, to_check) %>% 
  dplyr::rename("geometry" = "geom") %>% 
  dplyr::mutate(status = if_else(to_check, "TO_CHECK", "DONT_CHECK"))

# --------------------------------------------------------------------------------------
# feed polygons to check to database ---------------------------------------------------
sf::st_write(obj = to_update_tbl, 
             dsn = conn, 
             layer = "to_update", 
             append = TRUE, 
             factorsAsCharacter = TRUE)

# --------------------------------------------------------------------------------------
# run vacuun analyze -------------------------------------------------------------------
DBI::dbSendQuery(conn, statement = "VACUUM ANALYZE to_update;")

# --------------------------------------------------------------------------------------
# close database connection ------------------------------------------------------------
DBI::dbDisconnect(conn)

# --------------------------------------------------------------------------------------
# remove all variables from environment ------------------------------------------------
rm(list=ls())
