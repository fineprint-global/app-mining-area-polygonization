### server.R

server <- function(input, output, session) {

  # initialize variables for context "server"
  current_cluster <- NULL
  current_cluster_polygons <- NULL
  previous_polygons <- NULL # used to compare polygons across mapedit calls
  user_name <- Sys.getenv("SHINYPROXY_USERNAME")
  edit_module <- NULL

  new_hold_entry <- function(current_cluster_id = NULL){
    if(is.null(current_cluster_id)){
      rlang::abort(message = "current_cluster_id must be specified.")
    }
    
    hold_entry <- sf::st_sf(
      id_mine_cluster = c(current_cluster_id),
      created_at = c(Sys.time()),
      status = c("HOLD"),
      id_app_user = c(user_name),
      geometry = c(sf::st_sfc(sf::st_multipolygon())), # empty geography
      sf_column_name = "geometry",
      seconds_spent = 0,
      version = VERSION,
      revision = REVISION
    )

    # because DBI does not support pool, we need to check ourselves a connection from the pool and return it after
    conn <- pool::poolCheckout(pool)
    sf::dbWriteTable(conn, "mine_polygon", hold_entry, append = T)
    pool::poolReturn(conn)
  }

  start_time <- NULL

  # get new sample mines and start the edit-module from mapedit
  # returns the module, values can be accessed via edit_module()$finished
  start_edit_module <- function(){
    
    # Update progress bar for the user
    progress_done <- RPostgreSQL::dbGetQuery(pool,
                                             sprintf("SELECT COUNT(id) FROM mine_cluster 
                                                     WHERE id_app_user = '%s' AND id IN 
                                                     (SELECT id_mine_cluster FROM mine_polygon WHERE id_app_user = '%s');",
                                             user_name, user_name))$count
    progress_all <- RPostgreSQL::dbGetQuery(pool,
                                            sprintf("SELECT COUNT(id) FROM mine_cluster 
                                                     WHERE id_app_user = '%s';",
                                                     user_name, user_name))$count
    
    if(progress_all != 0){
      shinyWidgets::updateProgressBar(session, id = "pb_user", value = progress_done/progress_all*100)
    }
    
    # Select sample following the id sequence. The samples have been previously are randomized in the database.
    current_cluster <<- get_next_cluster(user_name = user_name)
    if(is.character(current_cluster)){
      modalDialog(
        title = "Hold on",
        current_cluster,
        footer = tagList(
          modalButton("Cancel")
        ),
        fade = FALSE
      ) %>% showModal()
      
      return() # Stop execution of the current function
    }
    
    # get polygons and points associated with the current_cluster_id
    # current_cluster_polygons <<- get_current_cluster_poly(current_cluster_id = current_cluster$id)
    current_cluster_polygons <- NULL
    current_cluster_points <- get_current_cluster_points(current_cluster_id = current_cluster$id)

    # create a buffer around the points of the current_cluster
    current_cluster_buffer <- current_cluster_points %>% 
      sf::st_buffer(dist = 0.1) %>%
      sf::st_union()
    
    other_cluster_polygons <- get_other_cluster_polygons(current_cluster_id = current_cluster$id,
                                                         current_cluster_buffer = current_cluster_buffer)
    
    all_cluster_points <- get_all_cluster_points(current_cluster_buffer = current_cluster_buffer)
    
    other_cluster_points <- all_cluster_points %>% 
      dplyr::filter(id_mine_cluster != current_cluster$id)
    
    if(nrow(other_cluster_points) > 0){
      # create a buffer around the points of other clusters
      other_cluster_buffer <- other_cluster_points %>% 
        sf::st_buffer(dist = 0.1) %>%
        sf::st_union()
    } else {
      other_cluster_buffer <- NULL
    }
    
    # create hold entry in mine_polygons table
    new_hold_entry(current_cluster_id = current_cluster$id[1])

    # template for the popup for mine-markers
    popup_template <- '
    <table>
    <thead>
    <tr><th><a href="https://www.google.com/maps/search/%s %s mine" target="_blank">%s</a>&nbsp;</th><th>(fineprintID: %s)</th></tr>
    </thead>
    <tbody>
    <tr><td>Known As&nbsp;</td><td>%s</td></tr>
    <tr><td>Country&nbsp;</td><td>%s</td></tr>
    <tr><td>Coordinate Accuracy&nbsp;</td><td>%s</td></tr>
    <tr><td>Commodities&nbsp;</td><td>%s</td></tr>
    <tr><td>Mine Type&nbsp;</td><td>%s</td></tr>
    <tr><td>Operating Status&nbsp;</td><td>%s</td></tr>
    <tr><td>Development Stage&nbsp;</td><td>%s</td></tr>
    </tbody>
    </table>'

    icons_mines <- leaflet::icons(
      iconUrl = ifelse(all_cluster_points$id_mine_cluster == current_cluster$id, 
                       get_leaflet_marker_url("red"), 
                       get_leaflet_marker_url("blue")),
      shadowUrl = "https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png",
      iconWidth = 25, iconHeight = 41,
      iconAnchorX = 12, iconAnchorY = 41,
      popupAnchorX = 1, popupAnchorY = -34,
      shadowWidth = 41, shadowHeight = 41
    )

    all_cluster_points$known_as <- ifelse(nchar(all_cluster_points$known_as) > 150, paste0(substr(all_cluster_points$known_as, 1, 150), "..."), current_cluster_points$known_as)

    # Create map and call edit-module from mapedit
    map <- leaflet::leaflet(options = leaflet::leafletOptions(crs = leaflet::leafletCRS("L.CRS.EPSG3857"))) %>%
      leaflet::addWMSTiles(
        "https://tiles.maps.eox.at/wms?",
        layers = "s2cloudless-2019_3857",
        group = "Sentinel 2",
        options = leaflet::WMSTileOptions(format = "image/jpeg", version = "1.1.1", transparent = FALSE),
        attribution = paste("Sentinel-2 cloudless - https://s2maps.eu by EOX",
                            "IT Services GmbH (Contains modified Copernicus",
                            "Sentinel data 2019)")) %>%
      leaflet::addTiles(urlTemplate = "https://mts1.google.com/vt/lyrs=s&hl=en&src=app&x={x}&y={y}&z={z}&s=G", attribution = 'Google', group = "Google Satellite") %>%
      leaflet::addTiles(urlTemplate = "https://mts1.google.com/vt/lyrs=m&hl=en&src=app&x={x}&y={y}&z={z}&s=G", attribution = 'Google', group = "Google Map") %>%
      leaflet.extras::addBingTiles(apikey = Sys.getenv("BING_MAPS_API_KEY"),
                                   imagerySet = c("Aerial"), group = "Bing Satellite") %>%
      # add FINEPRINT WMS polygons layer
      leaflet::addWMSTiles("https://vps.fineprint.global/gs/geoserver/pre-release/wms?", 
                           layers = "pre-release:mining_polygons",
                           group = "Mining polygons v2",
                           options = leaflet::WMSTileOptions(format = "image/png", 
                                                             version = "1.1.0",
                                                             transparent = TRUE,
                                                             opacity = 0.5)) %>% 
      # add current cluster buffer
      leaflet::addPolygons(data = current_cluster_buffer, group = "Cluster-buffer", fillColor = "#FF7F7F", weight = 2, opacity = 1, color = "#FF7F7F", dashArray = "3", fillOpacity = 0)
    
    if(!is.null(other_cluster_buffer)){
      map <- map %>% leaflet::addPolygons(data = other_cluster_buffer, group = "Other cluster-buffer", fillColor = "#FFEDA0", weight = 2, opacity = 1, color = "white", dashArray = "3", fillOpacity = 0.15)
    }
    if(!is.null(other_cluster_polygons)){
      map <- map %>% leaflet::addPolygons(data = other_cluster_polygons, group = "Other cluster-polygons", fillColor = "#ADD8E6", weight = 2, opacity = 1, color = "white", fillOpacity = 0.5)
    }
    
    map <- map %>% 
      # leaflet::addPolygons(data = current_cluster_polygons, group = "Current mine-area", fillColor = "#FF7F7F", weight = 2, opacity = 1, color = "white", dashArray = "3", fillOpacity = 0.6) %>%
      leaflet::addMarkers(data = all_cluster_points, group = "Mine locations", icon = icons_mines,
                          popup = ~sprintf(popup_template, mine_name, country, # the first two variables for the maps search
                                           mine_name, fp_id, known_as, country, coordinate_accuracy, list_of_commodities, mine_type, operating_status, development_stage)) %>%
      leaflet::addLayersControl(
        baseGroups = c("Sentinel 2", "Google Satellite", "Google Map", "Bing Satellite"),
        overlayGroups = c("Mine locations", "Cluster-buffer", "Other cluster-buffer", "Other cluster-polygons", "Mining polygons v2"), # "Current mine-area", 
        options = leaflet::layersControlOptions(collapsed = FALSE),
        position = "bottomright"
      ) %>%
      leaflet::addScaleBar(position = "bottomleft")

    start_time <<- Sys.time()

    map %>%
      callModule(mapedit::editMod, id = "mine_edit", leafmap = ., targetLayerId = "Current mine-area", crs = 3857, sf = TRUE, editor = "leaflet.extras") %>%  #, editor = "leafpm", ) %>%
      # mapedit::editFeatures(x = current_cluster_polygons, map = ., crs = 3857) %>%
      return() # return the module to be able to access the created spatial objects
  }

  # start the edit module
  edit_module <<- start_edit_module()

  ##############################################
  ## ACTUAL APP

  onStop(function(){
    ## remove the HOLD on the most recent mine when stopping (which was put on hold)
    current_cluster_id <- current_cluster$id[1] # get ID of current cluster

    tryCatch({ # if the pool still exists, then get the connection from pool
      conn <- pool::poolCheckout(pool)
      DBI::dbSendQuery(conn, sprintf("DELETE FROM mine_polygon WHERE status = 'HOLD' AND id_app_user = '%s'", user_name))
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
      DBI::dbSendQuery(conn, sprintf("DELETE FROM mine_polygon WHERE status = 'HOLD' AND id_app_user = '%s'", user_name))
      DBI::dbDisconnect(conn)
    }, finally = {
      message("HOLD-status of last mine was put off.")
    })
  })

  # this function is used to get the polygons from the mapedit-module, save them into db, and then restart the module
  save_polygons_to_db <- function(status = "DONE", note = ""){

    # 1. Save Geometry in the DB
    
    ## store all new polygons in an object
    new_polygons <- edit_module()$all
    
    # # the lines below are only relevant in case of revisions, right now, there are just insertions
    # ## check if the new polygons are empty & deleted is empty, too - this means that nothing has been changed
    # ## then take the current_cluster_polygons
    # if(is.null(new_polygons) & is.null(edit_module()$deleted)){
    #   new_polygons <- current_cluster_polygons
    # }

    # get ID of current cluster
    current_cluster_id <- current_cluster$id[1]

    # combine all new_polygons to a multipolygon
    if(is.null(new_polygons)){ # no new polygons in the very first iteration
      multipolygon <- st_sfc(st_multipolygon())
    } else if( length(row.names(new_polygons)) == 0 | 
               (length(new_polygons$`_leaflet_id`) == length(previous_polygons$`_leaflet_id`) &&
                all(new_polygons$`_leaflet_id` == previous_polygons$`_leaflet_id`))){
      # no new polygons after at least one has been added before
      multipolygon <- st_sfc(st_multipolygon())
    } else { # new polygons
      multipolygon <- sf::st_combine(new_polygons$geometry)
      previous_polygons <<- new_polygons # reset previous polygons
    }
    
    # Changing the projection to longlat (which it is, but currently wrongly states merc)
    sf::st_crs(multipolygon) <- "+proj=longlat +datum=WGS84 +no_defs"
    
    new_entry <- sf::st_sf(
      id_mine_cluster = c(current_cluster_id),
      created_at = c(Sys.time()),
      status = c(status),
      note = c(note),
      id_app_user = c(user_name),
      seconds_spent = as.double(Sys.time() - start_time, units = "secs"),
      version = VERSION,
      revision = REVISION,
      geometry = c(multipolygon),
      sf_column_name = "geometry"
    )

    # because DBI does not support pool, we need to check out a connection from the pool and return it after
    conn <- pool::poolCheckout(pool)
    sf::dbWriteTable(conn, "mine_polygon", new_entry, append = T)
    DBI::dbSendQuery(conn, sprintf("DELETE FROM mine_polygon WHERE status = 'HOLD' AND id_app_user = '%s'", user_name))
    pool::poolReturn(conn)

    # 2. reload module with new mine
    edit_module <- start_edit_module()

    updateTextAreaInput(session, "ta_note", value = "")
  }

  # NEXT BUTTON -------------------------------------------
  observeEvent(input$btn_next, {
    note <- input$ta_note
    save_polygons_to_db(status = "DONE", note = note)
  })

  # HELP BUTTON -------------------------------------------
  observeEvent(input$btn_help, {
    modalDialog(
      selectInput("help_status", "What's wrong?",
                  list("Unclear extent", "Other")),
      textAreaInput("help_note", label = "Note:", value = input$ta_note),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("help_ok", "OK")
      ),
      fade = FALSE
    ) %>% showModal()
  })

  # When OK button is pressed, store the user input in the database.
  observeEvent(input$help_ok, {
    ## get variables
    status <- input$help_status
    note <- input$help_note
    # cut the status to 10 chars
    status <- ifelse(status == "Mine not found", "Not found", ifelse(status == "Unclear extent", "UnclearExt", status))

    save_polygons_to_db(status = status, note = note)

    removeModal()
  })
}
