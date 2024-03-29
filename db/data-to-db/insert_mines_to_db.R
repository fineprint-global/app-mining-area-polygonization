library(sf)
library(DBI)
library(tidyverse)

# this fixes a bug when the db insert of mine_point would unexpectedly crash
sf_use_s2(FALSE)

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
mine_point_tbl <- sf::st_read(dsn = "./db/input/snl_mines_selection_v2_tbl.gpkg", 
                               stringsAsFactors = FALSE) %>% 
  # rename columns to fit db nomenclature
  dplyr::rename("geometry" = "geom",
                "mine_name" = "mine",
                "fp_id" = "id") %>% 
  dplyr::select(-snl_id, -primary_commodity)

# --------------------------------------------------------------------------------------
# sort mines by country and commodities ------------------------------------------------
mine_point_tbl <- mine_point_tbl %>% 
  dplyr::arrange(id_app_user, country, list_of_commodities)

# --------------------------------------------------------------------------------------
# create cluster table -----------------------------------------------------------------
mine_cluster_tbl <- mine_point_tbl %>% 
  sf::st_drop_geometry() %>% 
  dplyr::select(id = id_mine_cluster, id_app_user) %>% 
  tibble::as_tibble() %>% 
  dplyr::distinct()

# --------------------------------------------------------------------------------------
# create user table --------------------------------------------------------------------
app_user_tbl <- mine_point_tbl %>% 
  sf::st_drop_geometry() %>% 
  dplyr::select(id = id_app_user) %>% 
  tibble::as_tibble() %>% 
  dplyr::distinct()

# --------------------------------------------------------------------------------------
# feed users table to database ---------------------------------------------------------
DBI::dbWriteTable(conn = conn, 
                  name = "app_user", 
                  value = app_user_tbl, 
                  append = TRUE, 
                  row.names = FALSE)

# --------------------------------------------------------------------------------------
# feed clusters id table to database ---------------------------------------------------
DBI::dbWriteTable(conn = conn, 
                  name = "mine_cluster", 
                  value = mine_cluster_tbl, 
                  append = TRUE, 
                  row.names = FALSE)

# --------------------------------------------------------------------------------------
# feed mine points to database ---------------------------------------------------------
mine_point_tbl <- mine_point_tbl %>%
  dplyr::select(-id_app_user)

sf::st_write(obj = mine_point_tbl, 
             dsn = conn, 
             layer = "mine_point", 
             append = TRUE, 
             factorsAsCharacter = TRUE)

# --------------------------------------------------------------------------------------
# run vacuun analyze -------------------------------------------------------------------
DBI::dbSendQuery(conn, statement = "VACUUM ANALYZE mine_cluster;")
DBI::dbSendQuery(conn, statement = "VACUUM ANALYZE mine_point;")

# --------------------------------------------------------------------------------------
# close database connection ------------------------------------------------------------
DBI::dbDisconnect(conn)

# --------------------------------------------------------------------------------------
# remove all variables from environment ------------------------------------------------
rm(list=ls())
