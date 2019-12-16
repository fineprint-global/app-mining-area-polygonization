# --------------------------------------------------------------------------------------
# this script calculates the accuracy of mining polygons based on control points -------
library(RPostgreSQL)
library(tidyverse)
library(caret)
library(sf)

# --------------------------------------------------------------------------------------
# get control points from PostGIS database ---------------------------------------------
conn <- DBI::dbConnect(RPostgreSQL::PostgreSQL(),
                       host = Sys.getenv("db_host"),
                       port = Sys.getenv("db_port"),
                       dbname = Sys.getenv("db_name_accuracy"),
                       user = Sys.getenv("db_user"),
                       password = Sys.getenv("db_password"))

validation_unit <- sf::st_read(conn, "validation_unit")
validation <- dplyr::tbl(conn, "validation") %>% 
  dplyr::filter(!is.null(timestamp)) %>% 
  dplyr::collect()


# --------------------------------------------------------------------------------------
# get control points from PostGIS database ---------------------------------------------
control_tbl <- validation_unit %>% 
  dplyr::right_join(validation, by = c("id" = "id_validation_unit"), suffix = c(".mapped", ".reference")) %>% 
  dplyr::transmute(id = id, 
                   mapped = factor(is_mine.mapped, levels = c(TRUE, FALSE), labels = c("mine", "no-mine")), 
                   reference = factor(is_mine.reference, levels = c(TRUE, FALSE), labels = c("mine", "no-mine"))) %>% 
  dplyr::filter(id > 50) %>% 
  sf::st_drop_geometry() %>% 
  dplyr::select(-id) %>% 
  tibble::as_tibble()

DBI::dbDisconnect(conn)

# --------------------------------------------------------------------------------------
# calculate accuracy -------------------------------------------------------------------
err <- table(control_tbl) %>% 
  as.matrix()

# User's accuracy = Sensitivity = Recall (positive class) =  
diag(err) / apply(err, 2, sum)

# Producer's accuracy 
diag(err) / apply(err, 1, sum)

# Overall accuracy
sum(diag(err)) / sum(apply(err, 1, sum))

# All accuracy metrics 
caret::confusionMatrix(data = control_tbl$mapped, reference = control_tbl$reference, mode = "everything")

