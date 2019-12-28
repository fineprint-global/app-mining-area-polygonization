# --------------------------------------------------------------------------------------
# this script calculates the accuracy of mining polygons based on control points -------
library(tidyverse)
library(caret)
library(sf)

# --------------------------------------------------------------------------------------
# get control points from PostGIS database ---------------------------------------------
control_tbl <- sf::st_read("./validation_points_v1.gpkg") %>% 
  sf::st_drop_geometry() %>%
  tibble::as_tibble()

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

