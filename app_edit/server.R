### server.R

server <- function(input, output, session) {

  # initialize variables for context "server"
  current_poly_id <- reactiveVal(0)
  current_poly <- NULL
  # user_name <- Sys.getenv("SHINYPROXY_USERNAME")
  edit_module <- NULL
  
  prev_polys <- NULL
  del_polys <- NULL

  new_hold_entry <- function(current_poly_id = NULL){
    if(is.null(current_poly_id)){
      rlang::abort(message = "current_poly_id must be specified.")
    }
    
    # because DBI does not support pool, we need to check out a connection from the pool and return it after
    conn <- pool::poolCheckout(pool)
    DBI::dbSendQuery(conn, sprintf("UPDATE to_update SET status = 'HOLD' WHERE id = '%.0f'", current_poly_id))
    pool::poolReturn(conn)
  }

  # get new sample mines and start the edit-module from mapedit
  # returns the module, values can be accessed via edit_module()$finished
  start_edit_module <- function(){
    
    # Update progress bar for the user
    progress_done <- RPostgreSQL::dbGetQuery(pool,
                                             sprintf("SELECT COUNT(DISTINCT id) FROM updated;"))$count
    progress_all <- RPostgreSQL::dbGetQuery(pool,
                                            sprintf("SELECT COUNT(id) FROM to_update 
                                                     WHERE to_check = FALSE;"))$count
    
    if(progress_all != 0){
      shinyWidgets::updateProgressBar(session, id = "pb_user", value = progress_done, total = progress_all)
    }
    
    # Select sample following the id sequence. The samples have been previously randomized in the database.
    current_poly <<- get_next_polygon()
    if(is.character(current_poly)){
      modalDialog(
        title = "Hold on",
        current_poly,
        footer = tagList(
          modalButton("Cancel")
        ),
        fade = FALSE
      ) %>% showModal()
      
      return() # Stop execution of the current function
    }
    
    current_poly_id(current_poly$id[1])
    
    # get old (the ones not yet updated) and new (updated) polygons
    current_adjacent_polygons_old <- get_adjacent_polygons(current_poly, old = TRUE)
    current_adjacent_polygons_new <- get_adjacent_polygons(current_poly, old = FALSE)
    
    # create hold entry in mine_polygons table
    new_hold_entry(current_poly$id[1])

    # Create map and call edit-module from mapedit
    map <- leaflet::leaflet(options = leaflet::leafletOptions(crs = leaflet::leafletCRS("L.CRS.EPSG3857"))) %>%
      leaflet::addWMSTiles(
        "https://tiles.maps.eox.at/wms?",
        layers = "s2cloudless_3857",
        group = "Sentinel 2",
        options = leaflet::WMSTileOptions(format = "image/jpeg", version = "1.1.1", transparent = FALSE),
        attribution = paste("Sentinel-2 cloudless - https://s2maps.eu by EOX",
                            "IT Services GmbH (Contains modified Copernicus",
                            "Sentinel data 2016, 2017, & 2018)")) %>%
      leaflet::addTiles(urlTemplate = "https://mts1.google.com/vt/lyrs=s&hl=en&src=app&x={x}&y={y}&z={z}&s=G", attribution = 'Google', group = "Google Satellite") %>%
      leaflet::addTiles(urlTemplate = "https://mts1.google.com/vt/lyrs=m&hl=en&src=app&x={x}&y={y}&z={z}&s=G", attribution = 'Google', group = "Google Map") %>%
      leaflet.extras::addBingTiles(apikey = Sys.getenv("BING_MAPS_API_KEY"),
                                   imagerySet = c("Aerial"), group = "Bing Satellite") %>%
      leaflet::addPolygons(data = current_adjacent_polygons_old, group = "Old polygons", fillColor = "#FF7F7F", weight = 2, opacity = 1, color = "white", dashArray = "3", fillOpacity = 0.15) %>% 
      leaflet::addPolygons(data = current_adjacent_polygons_new, group = "New polygons", fillColor = "#7FFF7F", weight = 2, opacity = 1, color = "white", dashArray = "3", fillOpacity = 0.15)
    
    map <- map %>% 
      leaflet::addPolygons(data = current_poly, group = "Current polygon", fillColor = "#FF7F7F", weight = 2, opacity = 1, color = "white", dashArray = "3", fillOpacity = 0.6) %>%
      leaflet::addLayersControl(
        baseGroups = c("Google Satellite", "Sentinel 2", "Google Map", "Bing Satellite"),
        overlayGroups = c("Current polygon", "Old polygons", "New polygons"),
        options = leaflet::layersControlOptions(collapsed = FALSE),
        position = "bottomright"
      ) %>%
      leaflet::addScaleBar(position = "bottomleft")

    map %>%
      callModule(mapedit::editMod, id = "mine_edit", leafmap = ., targetLayerId = "Current polygon", crs = 3857, sf = TRUE, editor = "leaflet.extras") %>%  #, editor = "leafpm", ) %>%
      # mapedit::editFeatures(x = current_cluster_polygons, map = ., crs = 3857) %>%
      return() # return the module to be able to access the created spatial objects
  }
  
  output$txt_id <- renderText({
    sprintf("Current polygon-id: %s", current_poly_id())
  })

  # start the edit module
  edit_module <<- start_edit_module()

  ##############################################
  ## ACTUAL APP

  onStop(function(){
    ## remove the HOLD on the most recent mine when stopping (which was put on hold)

    tryCatch({ # if the pool still exists, then get the connection from pool
      conn <- pool::poolCheckout(pool)
      DBI::dbSendQuery(conn, sprintf("UPDATE to_update SET status = 'TO_CHECK' WHERE status = 'HOLD' AND id = '%.0f'", current_poly$id[1]))
      pool::poolReturn(conn)
    }, error = function(e) { # in case the pool is closed, make a new connection
      conn <- DBI::dbConnect(
        drv = RPostgreSQL::PostgreSQL(),
        host = Sys.getenv("db_host"),
        port = Sys.getenv("db_port"),
        dbname = Sys.getenv("db_name"),
        user = Sys.getenv("db_user"),
        password = Sys.getenv("db_password")
      )
      DBI::dbSendQuery(conn, sprintf("UPDATE to_update SET status = 'TO_CHECK' WHERE status = 'HOLD' AND id = '%.0f'", current_poly$id[1]))
      DBI::dbDisconnect(conn)
    }, finally = {
      message("HOLD-status of last polygon was put off.")
    })
  })

  # this function is used to get the polygons from the mapedit-module, save them into db, and then restart the module
  save_polygons_to_db <- function(status = "DONE"){

    # 1. Save Geometry in the DB

    ## store all new polygons in an object
    new_polygons <- edit_module()$all
    
    ## preparation for the coming check if there were any changes
    same_deleted <- FALSE
    same_all <- FALSE
    if(!is.null(edit_module()$deleted) &&
       !is.null(del_polys)){
      same_deleted <- !any(edit_module()$deleted$geometry != del_polys$geometry)
    } else if(is.null(edit_module()$deleted)){
      same_deleted <- TRUE
    }
    if(!is.null(edit_module()$all) &&
       !is.null(prev_polys)){
      same_all <- !any(edit_module()$all$geometry != prev_polys$geometry)
    } else if(is.null(edit_module()$all)){
      same_all <- TRUE
    }
    ## this checks if there were any changes (delete, edit, add), if not, we set the new poly to the current one
    if(same_deleted && same_all){
      new_polygons <- current_poly
    }

    ## combine all new_polygons to a multipolygon
    if(is.null(new_polygons)){ # no new polygons in the very first iteration
      multipolygon <- st_sfc(st_multipolygon())
    } else if( length(row.names(new_polygons)) == 0){ # no new polygons after at last one has been added before
      multipolygon <- st_sfc(st_multipolygon())
    } else { # new polygons
      multipolygon <- sf::st_combine(new_polygons$geometry)
    }
    
    ## Changing the projection to longlat (which it is, but currently wrongly states merc)
    sf::st_crs(multipolygon) <- "+proj=longlat +datum=WGS84 +no_defs"
    
    new_entry <- sf::st_sf(
      id_to_update = c(current_poly$id[1]),
      geometry = c(multipolygon),
      sf_column_name = "geometry"
    )

    ## because DBI does not support pool, we need to check out a connection from the pool and return it after
    conn <- pool::poolCheckout(pool)
    sf::dbWriteTable(conn, "updated", new_entry, append = T)
    DBI::dbSendQuery(conn, sprintf("UPDATE to_update SET status = 'CHECKED' WHERE status = 'HOLD' AND id = '%.0f'", current_poly$id[1]))
    pool::poolReturn(conn)

    ## store the $all column in a list to be able to compare the difference
    prev_polys <<- edit_module()$all
    del_polys <<- edit_module()$deleted
    
    # 2. reload module with new mine
    edit_module <- start_edit_module()
  }

  # NEXT BUTTON -------------------------------------------
  observeEvent(input$btn_next, {
    save_polygons_to_db(status = "DONE")
  })

}
