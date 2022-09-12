########################################################################################
### 1. Load packages
########################################################################################

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

sf_use_s2(FALSE)

########################################################################################
### 2. Data setup
########################################################################################

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

########################################################################################
### 3. Load data
########################################################################################

mine_point_tbl <- st_read("./db/input/mine_level_data_points_app.gpkg",
                          stringsAsFactors = FALSE) #, layer = "facilities", stringsAsFactors = FALSE, as_tibble = TRUE)

## adjust data to db naming
mine_point_tbl <- mine_point_tbl %>% 
  dplyr::rename(fp_id = pf_id,
                development_stage = decelopment_stage,
                geometry = geom)

# fix data to fit the database
# mine_point_tbl$mine_type %>% as.character() %>% nchar %>% max(na.rm=TRUE)
mine_point_tbl <- mine_point_tbl %>% 
  dplyr::mutate(mine_type = substr(mine_type, 1, 50),
                mine_name = substr(mine_name, 1, 50),
                country = substr(country, 1, 100),
                list_of_commodities = substr(list_of_commodities, 1, 250),
                development_stage = substr(development_stage, 1, 50),
                operating_status = substr(operating_status, 1, 50),
                coordinate_accuracy = "",
                known_as = ""
                )

# --------------------------------------------------------------------------------------
# sort mines by country and commodities ------------------------------------------------
mine_point_tbl <- mine_point_tbl %>% 
  dplyr::arrange(id_app_user, country, list_of_commodities)

########################################################################################
### 4. Insert data
########################################################################################

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

mine_point_tbl <- mine_point_tbl %>% 
  dplyr::select(id,
                geometry,
                fp_id,
                mine_name,
                country,
                list_of_commodities,
                development_stage,
                operating_status,
                coordinate_accuracy,
                known_as,
                mine_type,
                id_mine_cluster)

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

