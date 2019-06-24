### global.R
# This file is loaded on startup of the app.
# Here, code that only needs to be performed once is executed.
# Typically, this includes defining libraries,
# setting up the database connection, and
# defining variables connected to database operation.

## STRUCTURE
# 1. Load packages
# 2. Data setup

##################################################################
### 1. LOAD PACKAGES
##################################################################

library(shiny)

##################################################################
### 2. DATA SETUP
##################################################################

# connect PostGIS database via a pool object for better Shiny behaviour ------------------------------------------------
# pool <- pool::dbPool(
#   drv = RPostgreSQL::PostgreSQL(),
#   host = Sys.getenv("db_host"), # for usage inside docker: ioviz_db; outside the docker-environment: use proper server ip and port,
#   port = Sys.getenv("db_port"),
#   dbname = Sys.getenv("db_name"),
#   user = Sys.getenv("db_user"),
#   password = Sys.getenv("db_password"),
#   minSize = 1,
#   maxSize = Inf,
#   idleTimeout = 300, # 5 minutes,
#   validationInterval = 120
# )
# onStop(function() { # this is required to close the pool so we have no leaking connections
#   poolClose(pool)
#   message("Pool closed.")
# })
